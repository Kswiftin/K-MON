import XCTest
@testable import PokeTokenBar

// MARK: 새 알 (리롤 — 현재 포켓몬 폐기, 도감·확률 무영향)

private struct FreshEggNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class FreshEggTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 활성 포켓몬(baseID 10, common 3형태, 성장 200M) + 도감 1개 + 수집기록 1개(1:3) + 지갑.
    /// active=false 면 알(활성 없음) 상태.
    private func store(active: Bool = true, shiny: Bool = false, used: Int = 5_000_000_000,
                       spent: Int = 0, eggs: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("egg-\(UUID().uuidString).json")
        let mon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":\(shiny)}"
        let dex = "{\"baseID\":1,\"finalID\":3,\"chainOrder\":[1,2,3],\"rarity\":\"common\"}"
        let balance = max(0, used - spent)
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":\(spent),\"starPieces\":\(balance),"
            + "\"lastDate\":\"d\",\"focusEggs\":\(eggs),\"active\":\(active ? mon : "null"),\"dex\":[\(dex)],\"collectedFinals\":[\"1:3\"]}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: FreshEggNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 7))
    }

    func testPriceMatchesStarPieceEconomy() { XCTAssertEqual(FreshEgg.price, 20_000) }

    /// [핵심] 리롤 = 폐기: active 사라지고 새 알(eggUsage 0). **도감·확률(collectedFinals) 불변** = "뽑은 적 없던 것처럼".
    func testBuyFreshEggDiscardsWithoutDexOrProbabilityImpact() {
        let s = store(used: 5_000_000_000, spent: 0)
        let persistedDexBefore = s.state.dex
        let collectedBefore = s.state.collectedFinals
        XCTAssertEqual(s.dexEntries.count, persistedDexBefore.count + 1,
                       "현재 포켓몬은 졸업 전에도 도감 화면에 표시")
        XCTAssertTrue(s.hasActive)
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertNotNil(s.state.active, "현재 포켓몬은 유지하고 알을 인벤토리에 추가")
        XCTAssertFalse(s.isEgg)
        XCTAssertEqual(s.focusEggCount, 1)
        XCTAssertEqual(s.state.dex.map(\.id), persistedDexBefore.map(\.id),
                       "영구 도감 불변 — 졸업이 아니라 폐기")
        XCTAssertEqual(s.dexEntries.count, persistedDexBefore.count + 1)
        XCTAssertEqual(s.state.collectedFinals, collectedBefore, "확률 가중(collectedFinals) 불변")
        XCTAssertEqual(s.focusEggCount, 1, "구매한 알은 인벤토리에 보관")
        XCTAssertEqual(s.state.starPieces, 5_000_000_000 - FreshEgg.price)
    }

    /// 폐기한 개체(baseID 10)의 종은 collectedFinals 에 들어가지 않는다(이후 부화 확률에 영향 없음).
    func testDiscardedSpeciesNotCollected() {
        let s = store()
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertFalse(s.state.collectedFinals.contains { $0.hasPrefix("10:") },
                       "폐기 개체 종은 수집 기록에 없어야 함")
    }

    /// 알 상태(활성 없음)에선 리롤할 게 없어 불가.
    func testCannotRerollWhenEgg() {
        let s = store(active: false, used: 5_000_000_000)
        XCTAssertFalse(s.hasActive)
        XCTAssertTrue(s.canBuyFreshEgg)
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertEqual(s.focusEggCount, 1)
    }

    /// 잔액이 가격 미만이면 불가 — 활성 유지.
    func testCannotRerollWithoutFunds() {
        let s = store(used: FreshEgg.price - 1)
        XCTAssertFalse(s.canBuyFreshEgg)
        XCTAssertFalse(s.buyFreshEgg())
        XCTAssertNotNil(s.state.active, "활성 유지")
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    /// 이로치도 폐기 가능(추가 경고는 UI 단계, 로직은 동일) — 리롤 후 흔적 없음.
    func testShinyCanBeRerolled() {
        let s = store(shiny: true)
        XCTAssertTrue(s.currentIsShiny)
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertNotNil(s.state.active)
        XCTAssertTrue(s.currentIsShiny)
    }

    // MARK: 알 저장고 상한(999) — 잘라낸 몫의 주인 (#82 부류)

    /// [회귀] 저장고가 꽉 차면 알을 팔지 않는다. 예전엔 `canBuyEgg` 에 상한 검사가 없어
    /// **별의조각은 차감되고** `min(999, 1000)` 이 999 라 알은 0개 늘었다 — 값만 치르고 빈손.
    /// 덤으로 부화 시각만 하나 더 쌓여 개수와 어긋났다.
    func testBuyingAnEggWithFullStorageChargesNothing() {
        let s = store(eggs: 999)
        XCTAssertEqual(s.state.focusEggReadyDates.count, 999, "기동 시 reconcile 이 날짜를 개수에 맞춘다")
        let before = s.state.starPieces
        XCTAssertFalse(s.canBuyFreshEgg, "저장고가 꽉 차면 살 수 없다")
        XCTAssertFalse(s.buyEgg(nil))
        XCTAssertEqual(s.state.starPieces, before, "살 수 없으면 값도 나가지 않는다")
        XCTAssertEqual(s.state.focusEggs, 999)
        XCTAssertEqual(s.state.focusEggReadyDates.count, 999)
    }

    /// [회귀] 지급 경로도 마찬가지 — `focusEggs` 만 클램프하고 날짜는 무조건 append 하면 두 배열이
    /// 세션 내내 어긋난다(`nextStoredEggHatchAt` 이 없는 알의 카운트다운을 그리고
    /// `beginIncubatingFocusEgg` 의 `removeFirst()` 짝이 밀린다). 다음 기동의
    /// `reconcileStoredEggDates()` 가 잘라 주지만 **세션 안에서는 안 낫는다.**
    func testGymRewardAtFullEggStorageAddsNoHatchDate() {
        let s = store(eggs: 999)
        XCTAssertNotNil(s.recordGymVictory(GymLeague.catalog[0]), "체육관 보상 자체는 지급된다")
        XCTAssertEqual(s.state.focusEggs, 999)
        XCTAssertEqual(s.state.focusEggReadyDates.count, 999,
                       "안 들어간 알의 부화 시각을 쌓지 않는다")
    }
}
