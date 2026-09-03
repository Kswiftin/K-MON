import XCTest
@testable import PokeTokenBar

/// 트레이너 꾸미기 저장 상태(#outfit) — 구매·착용·서명·관대 디코딩.
@MainActor
final class OutfitStoreTests: XCTestCase {
    private func makeStore() -> CompanionStore {
        makeStoreWithWallet(0)
    }

    /// 지갑을 미리 채운 세이브 파일로 스토어를 띄운다 — `state` 는 `private(set)` 라 생성 뒤 직접
    /// 대입할 수 없다(`DungeonSettlementTests.makeStore` 와 같은 우회).
    private func makeStoreWithWallet(_ starPieces: Int) -> CompanionStore {
        let url = storeStateURL("outfit")
        let json = """
        {"economyVersion":\(IdleEconomy.currentVersion),"forcedResetVersion":\(SaveTransfer.forcedResetVersion),\
        "starPieces":\(starPieces)}
        """
        try? Data(json.utf8).write(to: url)
        return CompanionStore(provider: StubProvider(value: outfitTestLine), clock: TestClock().closure,
                              fileURL: url, rng: SeededRNG(seed: 3))
    }

    func testBuyingDeductsAndOwns() {
        let store = makeStoreWithWallet(1_000)
        XCTAssertTrue(store.canBuyOutfit(.capRed))
        XCTAssertTrue(store.buyOutfit(.capRed))
        XCTAssertEqual(store.state.starPieces, 700)
        XCTAssertTrue(store.ownsOutfit(.capRed))
        XCTAssertFalse(store.canBuyOutfit(.capRed), "소유한 것은 다시 못 산다")
        XCTAssertFalse(store.buyOutfit(.capRed))
        XCTAssertEqual(store.state.starPieces, 700)
    }

    func testCannotBuyUnsoldOrUnaffordable() {
        let store = makeStoreWithWallet(100)
        XCTAssertFalse(store.canBuyOutfit(.capRed))
        XCTAssertFalse(store.buyOutfit(.capRed))
        let richStore = makeStoreWithWallet(100_000)
        XCTAssertFalse(richStore.canBuyOutfit(.helmetExplorer), "업적 보상은 상점에 없다")
        XCTAssertFalse(richStore.buyOutfit(.helmetExplorer))
    }

    func testWearRequiresOwnershipAndMatchingSlot() {
        let store = makeStore()
        store.wear(.capRed, in: .hat)
        XCTAssertEqual(store.outfit.worn, [:], "미소유는 못 입는다")
        store.grantOutfit(.capRed)
        store.wear(.capRed, in: .top)
        XCTAssertEqual(store.outfit.worn, [:], "슬롯이 다르면 못 입는다")
        store.wear(.capRed, in: .hat)
        XCTAssertEqual(store.outfit.worn, [.hat: .capRed])
        store.wear(nil, in: .hat)
        XCTAssertEqual(store.outfit.worn, [:])
    }

    func testGrantIsIdempotent() {
        let store = makeStore()
        XCTAssertTrue(store.grantOutfit(.cloakWorn))
        XCTAssertFalse(store.grantOutfit(.cloakWorn))
    }

    func testOldSaveWithoutOutfitKeysDecodesToDefaults() throws {
        let json = #"{"starPieces": 5}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(CompanionState.self, from: json)
        XCTAssertEqual(state.outfit, TrainerOutfit())
        XCTAssertTrue(state.ownedOutfits.isEmpty)
    }

    func testCanonicalCarriesOwnedButNotWorn() {
        var state = CompanionState()
        XCTAssertFalse(SaveTransfer.canonicalString(state).contains("outf"), "빈 소유는 세그먼트가 없어야 구서명이 유효하다")
        state.ownedOutfits = [.teeWhite, .capRed]
        state.outfit = TrainerOutfit(worn: [.hat: .capRed])
        let canonical = SaveTransfer.canonicalString(state)
        XCTAssertTrue(canonical.contains("outfcap_red,tee_white"))
        state.outfit = TrainerOutfit()
        XCTAssertEqual(SaveTransfer.canonicalString(state), canonical, "착용은 서명에 들어가지 않는다")
    }

    /// 원래 이 테스트는 기본 `CompanionState()` 로 돌렸는데, `forcedResetVersion`(기본 0)이
    /// `SaveTransfer.forcedResetVersion`(1) 보다 낮아 강제 초기화 조기 반환에 걸려 새 `CompanionState()`
    /// 를 그대로 돌려준다 — `outfit.worn` 이 비어 있는 게 애초에 기본값이라 통과하지만, 검증 대상인
    /// `s.outfit = s.outfit.normalized(owned:)` 줄은 타지 않는다. `economyVersion` 도 기본값(0)이면
    /// `migratedToIdleEconomy` 가 진행을 통째로 새 `CompanionState()` 로 갈아엎어(도감·언어만 승계)
    /// `ownedOutfits` 까지 날린다. 두 조기 반환을 모두 지나야 이 줄에 실제로 도달한다(경로 고정).
    func testSanitizeStripsUnownedWornItems() {
        var state = CompanionState()
        state.forcedResetVersion = SaveTransfer.forcedResetVersion
        state.economyVersion = IdleEconomy.currentVersion
        state.ownedOutfits = [.teeWhite]
        state.outfit = TrainerOutfit(worn: [.hat: .capRed, .top: .teeWhite])
        let clean = SaveTransfer.sanitized(state)
        XCTAssertEqual(clean.outfit.worn, [.top: .teeWhite], "미소유(.capRed)는 벗기고 소유(.teeWhite)는 남긴다")
    }

    func testShopEntryOutfitPrice() {
        XCTAssertEqual(ShopEntry.outfit(.backpack).price, 800)
    }

    /// 미래 빌드가 저장한 rawValue(`future_hat`)는 이 빌드가 모른다 — 항목만 걸러내고
    /// (`Lossy<OutfitItem>`) 나머지 소유(`cap_red`)는 살아야 한다.
    func testUnknownOwnedOutfitIdsAreDroppedNotFatal() throws {
        let json = #"{"ownedOutfits":["cap_red","future_hat"]}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(CompanionState.self, from: json)
        XCTAssertEqual(state.ownedOutfits, [.capRed])
    }
}

/// 스토어를 세우기 위한 최소 진화 라인 — 의상은 종·진화와 무관하므로 내용은 아무래도 좋다.
private let outfitTestLine: EvoLine = {
    var names: [Int: [String: String]] = [:]
    for id in [1, 2, 3] { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: 1,
                   tree: EvoNode(speciesID: 1,
                                 children: [EvoNode(speciesID: 2,
                                                    children: [EvoNode(speciesID: 3, children: [])])]),
                   rarity: .common, names: names)
}()
