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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-outfit-\(UUID().uuidString).json")
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

    func testSanitizeStripsUnownedWornItems() {
        var state = CompanionState()
        state.outfit = TrainerOutfit(worn: [.hat: .capRed])
        let clean = SaveTransfer.sanitized(state)
        XCTAssertEqual(clean.outfit.worn, [:])
    }

    func testShopEntryOutfitPrice() {
        XCTAssertEqual(ShopEntry.outfit(.backpack).price, 800)
    }
}

/// 스토어를 세우기 위한 최소 진화 라인 — 의상은 종·진화와 무관하므로 내용은 아무래도 좋다.
/// `DungeonProgressTests.dungeonTestLine` 은 파일 스코프 private 라 여기서 못 쓴다 — 그대로 복제.
private let outfitTestLine: EvoLine = {
    var names: [Int: [String: String]] = [:]
    for id in [1, 2, 3] { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: 1,
                   tree: EvoNode(speciesID: 1,
                                 children: [EvoNode(speciesID: 2,
                                                    children: [EvoNode(speciesID: 3, children: [])])]),
                   rarity: .common, names: names)
}()
