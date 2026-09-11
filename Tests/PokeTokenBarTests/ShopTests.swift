import XCTest
@testable import PokeTokenBar

// MARK: 상점 (재화 = usedSinceInstall − spentTokens, 이상한 사탕 구매)

/// 라인 로딩이 필요 없는 상점 테스트용 provider(항상 throw — 지갑/구매는 라인과 무관).
private struct ShopNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class ShopTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// usedSinceInstall/spentTokens 를 직접 지정한 상태 파일을 만들어 로드 — 지갑 잔액을 결정적으로
    /// 세팅(update() 의 delta 적립 경로를 우회). testCannotUseWhileLineUnloaded 와 동일한 JSON 시드 패턴.
    private func store(used: Int, spent: Int = 0, rareCandy: Int = 0,
                       file: String = #filePath) -> CompanionStore {
        let url = storeStateURL("shop")
        let inv = rareCandy > 0 ? ",\"inventory\":{\"rareCandy\":\(rareCandy)}" : ""
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":\(spent),\"starPieces\":\(max(0, used - spent)),"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]\(inv)}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1))
    }

    // MARK: 잔액 계산

    func testAvailableEqualsUsedWhenNothingSpent() {
        XCTAssertEqual(store(used: 1_000_000_000).availableTokens, 1_000_000_000)
    }

    func testAvailableSubtractsSpent() {
        XCTAssertEqual(store(used: 1_000_000_000, spent: 300_000_000).availableTokens, 700_000_000)
    }

    /// spent > used(비정상 상태 파일)이어도 음수로 새지 않는다(max 가드).
    func testAvailableNeverNegative() {
        XCTAssertEqual(store(used: 100_000_000, spent: 500_000_000).availableTokens, 0)
    }

    /// 하위호환: spentTokens 키 없는 구버전 저장 → 0 으로 로드(잔액 = used).
    func testDecodesWithoutSpentTokens() throws {
        let json = #"{"installBaselineSet":true,"usedSinceInstall":900,"lastDate":"d","dex":[]}"#
        let s = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(s.spentTokens, 0)
        XCTAssertEqual(s.usedSinceInstall, 900)
    }

    func testSpentTokensRoundTrip() throws {
        var st = CompanionState()
        st.usedSinceInstall = 1000
        st.spentTokens = 400
        let round = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(round.spentTokens, 400)
    }

    // MARK: 구매 가능 판정 (경계)

    func testCanBuyAtExactPrice() {
        XCTAssertTrue(store(used: RareCandy.price).canBuyRareCandy)
    }

    func testCannotBuyOneBelowPrice() {
        XCTAssertFalse(store(used: RareCandy.price - 1).canBuyRareCandy)
    }

    // MARK: 구매 (차감 + 적립 + 영속)

    func testBuyDebitsWalletAndCreditsInventory() {
        let s = store(used: 1_000_000_000)
        XCTAssertTrue(s.buyRareCandy())
        XCTAssertEqual(s.rareCandyCount, 1)
        XCTAssertEqual(s.state.starPieces, 1_000_000_000 - RareCandy.price)
        XCTAssertEqual(s.availableTokens, 1_000_000_000 - RareCandy.price)
        XCTAssertEqual(s.state.usedSinceInstall, 1_000_000_000, "성장 미터(usedSinceInstall)는 불변")
    }

    /// 잔액 부족이면 no-op — 인벤토리·지출 원장 불변, false 반환.
    func testBuyInsufficientIsNoOp() {
        let s = store(used: RareCandy.price - 1)
        XCTAssertFalse(s.buyRareCandy())
        XCTAssertEqual(s.rareCandyCount, 0)
        XCTAssertEqual(s.state.starPieces, RareCandy.price - 1)
    }

    /// 여러 번 구매하면 잔액이 바닥날 때까지만 성공(가드가 매번 재평가).
    func testMultipleBuysUntilBroke() {
        // 2개까지 가능, 3번째는 잔액 부족으로 실패
        let leftover = RareCandy.price / 2
        let s = store(used: RareCandy.price * 2 + leftover)
        XCTAssertTrue(s.buyRareCandy())
        XCTAssertTrue(s.buyRareCandy())
        XCTAssertFalse(s.buyRareCandy())
        XCTAssertEqual(s.rareCandyCount, 2)
        XCTAssertEqual(s.state.starPieces, leftover)
        XCTAssertEqual(s.availableTokens, leftover)
    }

    /// 구매는 이미 가진 사탕에 합산된다(무료 지급분과 같은 인벤토리).
    func testBuyAddsToExistingStock() {
        let s = store(used: 1_000_000_000, rareCandy: 3)
        XCTAssertTrue(s.buyRareCandy())
        XCTAssertEqual(s.rareCandyCount, 4)
        XCTAssertEqual(s.ownedItems.first?.kind, .rareCandy)
        XCTAssertEqual(s.ownedItems.first?.count, 4)
    }

    /// [영속] 재시작(같은 파일 재로드) 후 지출·재고가 유지된다.
    func testBuyPersistsAcrossRestart() {
        let url = storeStateURL("shop-persist")
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,\"installBaselineSet\":true,\"usedSinceInstall\":1000000000,\"spentTokens\":0,\"starPieces\":1000000000,"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        let s1 = CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertTrue(s1.buyRareCandy())

        let s2 = CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertEqual(s2.rareCandyCount, 1, "재고 영속")
        XCTAssertEqual(s2.state.starPieces, 1_000_000_000 - RareCandy.price)
        XCTAssertEqual(s2.availableTokens, 1_000_000_000 - RareCandy.price)
    }

    // MARK: 수량 구매 (한 번에 여러 개)

    /// 상한 = 잔액 / 단가 (내림). 잔여 잔액으로는 한 개도 더 못 산다.
    func testMaxPurchasableIsBalanceDividedByPrice() {
        let leftover = RareCandy.price / 2
        let s = store(used: RareCandy.price * 4 + leftover)
        XCTAssertEqual(s.maxPurchasable(.rareCandy), 4)
    }

    /// 수량 구매는 총액을 한 번에 차감하고 재고를 그만큼 올린다.
    func testBuyQuantityDebitsTotalAndCreditsAll() {
        let s = store(used: RareCandy.price * 10)
        XCTAssertTrue(s.buy(.rareCandy, quantity: 5))
        XCTAssertEqual(s.rareCandyCount, 5)
        XCTAssertEqual(s.availableTokens, RareCandy.price * 5)
    }

    /// 전량 구매 — 잔액이 모자라면 살 수 있는 만큼만 사는 부분 구매를 하지 않고 통째로 no-op.
    func testBuyQuantityIsAllOrNothing() {
        let s = store(used: RareCandy.price * 3)
        XCTAssertFalse(s.buy(.rareCandy, quantity: 4))
        XCTAssertEqual(s.rareCandyCount, 0)
        XCTAssertEqual(s.availableTokens, RareCandy.price * 3)
    }

    func testBuyQuantityZeroOrNegativeIsNoOp() {
        let s = store(used: RareCandy.price * 3)
        XCTAssertFalse(s.buy(.rareCandy, quantity: 0))
        XCTAssertFalse(s.buy(.rareCandy, quantity: -2))
        XCTAssertEqual(s.availableTokens, RareCandy.price * 3)
    }

    // MARK: 탭 분류

    /// **판매품은 탭 하나에만 들어간다.** 상점 탭은 화면 쪽 필터로 갈리는데, 세 필터가 각자
    /// `ItemKind` 를 보므로 조건이 겹치면 같은 아이템이 두 탭에 뜨고 어긋나면 **어느 탭에도 안 뜬다**
    /// (지닌물건이 100종 넘게 늘 예정이라 '도구' 탭에서 갈라낸 자리다).
    ///
    /// 필터가 화면 안 private 이라 소스에서 센다 — 조건을 함수로 빼면 그 함수만 초록이고
    /// 화면은 여전히 옛 조건을 쓸 수 있다.
    func testEveryPurchasableItemLandsInExactlyOneTab() throws {
        let items = store(used: 0).purchasableItems
        for kind in items {
            let tabs = [kind.isEvolutionItem, kind.bagUse == .heldItem,
                        !kind.isEvolutionItem && kind.bagUse != .heldItem].filter { $0 }
            XCTAssertEqual(tabs.count, 1, "\(kind.rawValue) 가 탭 \(tabs.count) 개에 걸린다")
        }
        XCTAssertTrue(items.contains { $0.bagUse == .heldItem }, "배틀 탭이 빈 목록이면 아무것도 안 잠근다")
        let source = try SourceScan.sources().first { $0.name.contains("ShopView") }
        let code = try XCTUnwrap(source?.code)
        XCTAssertTrue(code.contains("case .battle:"), "상점 화면에 배틀 탭이 없다")
        XCTAssertTrue(code.contains("$0.bagUse != .heldItem"),
                      "'도구' 탭이 지닌물건을 그대로 두고 있다 — 두 탭에 겹쳐 뜬다")
    }

    // MARK: 기술머신 필터 — 카드 노출과 데이터 조회의 순환 차단

    /// **회귀.** 타입/습득 필터가 보는 `machineTypes`/`machineLearnable` 을 보이는 카드에만
    /// 맡기면(`TechnicalMachineShopCard.task`) 필터가 카드 노출을 정하고 카드 노출이 그 값을
    /// 채우는 순환이 생긴다 — 필터를 켜는 순간 아직 한 번도 안 보인 항목은 영원히 필터를 못
    /// 통과해 목록이 거의 비어 보였다(2026-09-11 사용자 보고 — "기술머신 필터가 안됨").
    ///
    /// 뷰 상태/비동기 조회라 순수 함수로 못 재서 소스에서 본다 — 전체 도감을 카드 노출과
    /// 무관하게 미리 채우는 자리(`prefetchMachineFilterData`)가 여전히 있는지 확인한다.
    func testMachineFilterDataIsPrefetchedIndependentlyOfCardVisibility() throws {
        let source = try SourceScan.sources().first { $0.name.contains("ShopView") }
        let code = try XCTUnwrap(source?.code)
        XCTAssertTrue(code.contains("func prefetchMachineFilterData"),
                      "필터 데이터를 미리 채우는 자리가 없다 — 카드 노출에만 의존하면 순환이 되돌아온다")
        XCTAssertTrue(code.contains("for machine in TechnicalMachine.catalog"),
                      "미리 채우는 자리가 필터링된 목록이 아니라 전체 도감을 도는지 확인한다")
        XCTAssertTrue(code.contains(".task(id: store.currentSpeciesID ?? 0)")
                      && code.contains("await prefetchMachineFilterData()"),
                      "미리 채우는 자리가 실제로 화면에 연결돼 있는지 확인한다")
    }

    // MARK: 정렬 (가격 저렴한 순)

    /// 상점 목록은 가격 오름차순.
    func testItemsSortedByPriceAscending() {
        let items = store(used: 0).purchasableItems
        let prices = items.compactMap(\.shopPrice)
        XCTAssertEqual(prices, prices.sorted(), "shopPrice 오름차순 — 가격 상수가 바뀌어도 정렬 불변식 유지")
    }

    // MARK: shopEntries (판매 아이템 + 알 3종을 하나의 가격 오름차순 목록으로 병합)

    /// 활성 포켓몬이 있으면 알 3종이 각자의 가격 위치에 끼워져 전체가 가격 오름차순.
    /// (회귀: 알이 ForEach 밖에서 무조건 맨 아래로 append 돼 3B 부적보다 아래에 놓이던 표시.)
    /// 등급 알을 인접 그룹으로 묶지 **않는** 것이 의도다 — 그러면 4B 희귀 알이 3B 부적 위로 올라가
    /// 위 회귀를 부분적으로 되살린다. 티어 관계는 카드의 등급 배지로 읽힌다.
    func testShopEntriesInterleavesFreshEggByPrice() {
        let url = storeStateURL("shop-entries")
        let mon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false}"
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,\"installBaselineSet\":true,\"usedSinceInstall\":5000000000,\"spentTokens\":0,\"starPieces\":5000000000,"
            + "\"lastDate\":\"d\",\"active\":\(mon),\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        let s = CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertTrue(s.hasActive)
        XCTAssertTrue(s.shopEntries.contains(.egg(nil)))
        let prices = s.shopEntries.map(\.price)
        XCTAssertEqual(prices, prices.sorted(), "가격 상수가 바뀌어도 오름차순 불변식 유지")
    }

    /// 활성 포켓몬이 없으면(알 상태) 리롤 대상이 없어 알은 **등급 알까지 전부** 목록에서 빠진다.
    /// 프리미엄 알만 알 상태에서 살 수 있게 하는 안은 채택하지 않았다 — 기존 새 알과 게이트를 통일한다.
    func testShopEntriesOmitsFreshEggWhenNoActive() {
        let s = store(used: 5_000_000_000)   // active 없음
        XCTAssertFalse(s.hasActive)
        XCTAssertTrue(s.shopEntries.contains(.egg(nil)))
    }
}
