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
        album.setFurniture(.roomBed, in: "left", ownedItems: [ItemKind.roomBed.rawValue: 1])
        album.setFurniture(.roomLamp, in: "right", ownedItems: [:])
        XCTAssertEqual(album.memoryHomeAccess.roomLayout["left"], .roomBed)
        XCTAssertNil(album.memoryHomeAccess.roomLayout["right"])
    }

    func testImportedLayoutDropsConsumablesAndFurnitureMissingFromTheBag() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let album = PokemonMemoryAlbum(fileURL: url)
        var access = MemoryHomeAccessSettings()
        access.roomLayout = ["left": .roomBed, "center": .rareCandy, "right": .roomLamp]
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:], milestones: [:],
                                                  roomThemes: [:], memoryHomeAccess: access)

        album.replace(with: snapshot, validCompanionIDs: [], ownedItems: [ItemKind.roomBed.rawValue: 1])

        XCTAssertEqual(album.memoryHomeAccess.roomLayout, ["left": .roomBed])
    }
}
