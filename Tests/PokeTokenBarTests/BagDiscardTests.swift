import XCTest
@testable import PokeTokenBar

/// 가방 버리기 — 환불 없이 재고만 줄인다. 라인 로딩과 무관하므로 항상 throw 하는 provider 로 충분하다.
private struct DiscardNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class BagDiscardTests: XCTestCase {

    private func store(inventory: [ItemKind: Int] = [:], starPieces: Int = 0,
                       album: PokemonMemoryAlbum? = nil) -> CompanionStore {
        let url = storeStateURL("discard")
        let inventoryJSON = inventory.map { "\"\($0.key.rawValue)\":\($0.value)" }.joined(separator: ",")
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,"
            + "\"installBaselineSet\":true,\"starPieces\":\(starPieces),\"lastDate\":\"d\",\"dex\":[],"
            + "\"collectedFinals\":[],\"inventory\":{\(inventoryJSON)}}"
        try? Data(json.utf8).write(to: url)
        return CompanionStore(provider: DiscardNoProvider(), fileURL: url, memoryAlbum: album,
                              rng: SeededRNG(seed: 1))
    }

    /// 기술머신 재고는 구매 경로로 쌓는다 — `state` 는 private(set) 이라 테스트가 직접 못 쓴다.
    private func storeWithMachines(_ machine: TechnicalMachine, count: Int) -> CompanionStore {
        let s = store(starPieces: machine.price * count)
        XCTAssertTrue(s.buyTechnicalMachine(machine, quantity: count))
        return s
    }

    // MARK: 아이템

    func testDiscardReducesStock() {
        let s = store(inventory: [.rareCandy: 5])
        XCTAssertTrue(s.discardItem(.rareCandy, quantity: 2))
        XCTAssertEqual(s.itemCount(.rareCandy), 3)
    }

    /// 전부 버리면 가방 목록에서 사라진다(개수 0 이 남아 빈 카드로 보이면 안 된다).
    func testDiscardingEverythingRemovesItFromBag() {
        let s = store(inventory: [.rareCandy: 3])
        XCTAssertTrue(s.discardItem(.rareCandy, quantity: 3))
        XCTAssertEqual(s.itemCount(.rareCandy), 0)
        XCTAssertFalse(s.ownedItems.contains { $0.kind == .rareCandy })
    }

    /// 보유 수보다 많이 버릴 수 없다 — 부분 처리 없이 통째로 no-op.
    func testDiscardingMoreThanOwnedIsNoOp() {
        let s = store(inventory: [.mint: 2])
        XCTAssertFalse(s.discardItem(.mint, quantity: 3))
        XCTAssertEqual(s.itemCount(.mint), 2)
    }

    func testDiscardingZeroOrNegativeIsNoOp() {
        let s = store(inventory: [.mint: 2])
        XCTAssertFalse(s.discardItem(.mint, quantity: 0))
        XCTAssertFalse(s.discardItem(.mint, quantity: -1))
        XCTAssertEqual(s.itemCount(.mint), 2)
    }

    /// 보유형(이로치 부적)은 버리기 대상이 아니다 — 상시 효과가 조용히 사라지는 것을 막는다.
    func testPassiveItemCannotBeDiscarded() {
        let s = store(inventory: [.shinyCharm: 1])
        XCTAssertFalse(s.discardItem(.shinyCharm))
        XCTAssertTrue(s.ownsShinyCharm)
    }

    /// 버리기는 환불이 아니다 — 지갑은 그대로다.
    func testDiscardDoesNotRefund() {
        let s = store(inventory: [.rareCandy: 2])
        XCTAssertTrue(s.discardItem(.rareCandy, quantity: 2))
        XCTAssertEqual(s.availableTokens, 0)
    }

    func testDiscardPersistsAcrossRestart() {
        let url = storeStateURL("discard-persist")
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,"
            + "\"installBaselineSet\":true,\"starPieces\":0,\"lastDate\":\"d\",\"dex\":[],"
            + "\"collectedFinals\":[],\"inventory\":{\"rareCandy\":4}}"
        try? Data(json.utf8).write(to: url)
        let first = CompanionStore(provider: DiscardNoProvider(), fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertTrue(first.discardItem(.rareCandy, quantity: 3))

        let reloaded = CompanionStore(provider: DiscardNoProvider(), fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertEqual(reloaded.itemCount(.rareCandy), 1)
    }

    // MARK: 기술머신

    func testDiscardingMachineReducesStock() {
        let machine = TechnicalMachine.catalog[0]
        let s = storeWithMachines(machine, count: 3)
        XCTAssertTrue(s.discardTechnicalMachine(machine, quantity: 2))
        XCTAssertEqual(s.technicalMachineCount(machine.moveID), 1)
    }

    func testDiscardingAllMachinesRemovesItFromBag() {
        let machine = TechnicalMachine.catalog[0]
        let s = storeWithMachines(machine, count: 2)
        XCTAssertTrue(s.discardTechnicalMachine(machine, quantity: 2))
        XCTAssertTrue(s.ownedTechnicalMachines.isEmpty)
    }

    func testDiscardingMoreMachinesThanOwnedIsNoOp() {
        let machine = TechnicalMachine.catalog[0]
        let s = storeWithMachines(machine, count: 1)
        XCTAssertFalse(s.discardTechnicalMachine(machine, quantity: 2))
        XCTAssertEqual(s.technicalMachineCount(machine.moveID), 1)
    }

    // MARK: 미니룸 배치 정합

    /// 방에 놓은 가구를 버리면 배치도 함께 걷힌다. 여기를 지나지 않으면 소유하지 않은 가구가
    /// 다음 기동(로드 시 prune)까지 방에 그려진 채 남는다.
    func testDiscardingPlacedFurnitureAlsoRemovesItFromTheRoom() {
        let albumURL = storeStateURL("discard-room")
        let album = PokemonMemoryAlbum(fileURL: albumURL)
        let owned = [ItemKind.roomBed.rawValue: 2]
        XCTAssertNotNil(album.placeDecor(.roomBed, at: .init(x: 0.3, y: 0.6), ownedItems: owned))
        XCTAssertNotNil(album.placeDecor(.roomBed, at: .init(x: 0.7, y: 0.6), ownedItems: owned))

        let s = store(inventory: [.roomBed: 2], album: album)
        XCTAssertTrue(s.discardItem(.roomBed, quantity: 1))
        XCTAssertEqual(album.memoryHomeAccess.placedDecor.filter { $0.item == .roomBed }.count, 1)

        XCTAssertTrue(s.discardItem(.roomBed, quantity: 1))
        XCTAssertTrue(album.memoryHomeAccess.placedDecor.isEmpty)
    }
}
