import XCTest
@testable import PokeTokenBar

@MainActor final class MemoryHomeRoommateTests: XCTestCase {
    func testAliasPersistsAndRoommatesAreOwnedUniqueAndCapped() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let album = PokemonMemoryAlbum(fileURL: url); let ids = (0..<4).map { _ in UUID() }
        XCTAssertTrue(album.setPeerAlias("우리집", for: UUID()))
        album.setRoommates([ids[0], ids[0], ids[1], ids[2], ids[3]], validCompanionIDs: Set(ids))
        XCTAssertEqual(album.memoryHomeAccess.roommateIDs, Array(ids.prefix(3)))
        album.prune(validCompanionIDs: [ids[1]])
        XCTAssertEqual(album.memoryHomeAccess.roommateIDs, [ids[1]])
        // R8 배치는 가방을 대조한다 — 안 가진 가구는 방에 들어오지 않는다.
        XCTAssertNotNil(album.placeDecor(.roomBed, at: .init(x: 0.2, y: 0.7),
                                         ownedItems: [ItemKind.roomBed.rawValue: 1]))
        XCTAssertNil(album.placeDecor(.roomLamp, at: .init(x: 0.8, y: 0.7), ownedItems: [:]))
        XCTAssertEqual(album.memoryHomeAccess.placedDecor.map(\.item), [.roomBed])
    }

    func testImportedLayoutDropsConsumablesAndFurnitureMissingFromTheBag() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let album = PokemonMemoryAlbum(fileURL: url)
        var access = MemoryHomeAccessSettings()
        access.roomLayout = ["left": .roomBed, "center": .rareCandy, "right": .roomLamp]
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:], milestones: [:],
                                                  roomThemes: [:], memoryHomeAccess: access)

        album.replace(with: snapshot, validCompanionIDs: [], ownedItems: [ItemKind.roomBed.rawValue: 1])

        // 소비 아이템(사탕)은 가구가 아니라서, 램프는 가방에 없어서 떨어진다. 침대 하나만 남는다.
        // legacy 슬롯은 이전이 소비했으므로 **비어 있어야** 한다 — 남아 있으면 다음 실행에서
        // 이전이 다시 돌아 초기화한 방에 가구가 되살아난다.
        XCTAssertEqual(album.memoryHomeAccess.placedDecor.map(\.item), [.roomBed])
        XCTAssertTrue(album.memoryHomeAccess.roomLayout.isEmpty)
    }

    func testRoomPositionsPhotosAndVisitStampsPersist() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let album = PokemonMemoryAlbum(fileURL: url)
        let companionID = UUID()
        let bed = album.placeDecor(.roomBed, at: .init(x: 0.32, y: 0.64),
                                   ownedItems: [ItemKind.roomBed.rawValue: 1])
        album.setCompanionPosition(.clamped(x: 0.61, y: 0.67), for: companionID, validCompanionIDs: [companionID])
        album.addPhoto(.init(speciesID: 25, isShiny: false, caption: "우리", frame: "heart", background: "forest", composition: "together", trainerStyle: "trainer"))
        album.recordMemoryHomeVisitStamp(homeID: "nearby-home")

        let loaded = PokemonMemoryAlbum(fileURL: url)
        // 배치는 8×6 격자에 스냅되므로 요청한 좌표와 정확히 같지는 않다 — 같은 **격자칸**으로
        // 재시작 후에도 살아 있는지를 본다.
        XCTAssertEqual(loaded.memoryHomeAccess.placedDecor.map(\.position), bed.map { [$0.position] })
        XCTAssertEqual(loaded.companionPosition(for: companionID), .clamped(x: 0.61, y: 0.67))
        XCTAssertEqual(loaded.memoryHomeAccess.photos.count, 1)
        XCTAssertNotNil(loaded.memoryHomeAccess.visitedHomeStamps["nearby-home"])
    }
}
