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

    func testRoomPositionsPhotosAndVisitStampsPersist() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let album = PokemonMemoryAlbum(fileURL: url)
        let companionID = UUID()
        album.setFurniture(.roomBed, in: "left", ownedItems: [ItemKind.roomBed.rawValue: 1])
        album.setFurniturePosition(.clamped(x: 0.32, y: 0.64), in: "left")
        album.setCompanionPosition(.clamped(x: 0.61, y: 0.67), for: companionID, validCompanionIDs: [companionID])
        album.addPhoto(.init(speciesID: 25, isShiny: false, caption: "우리", frame: "heart", background: "forest", composition: "together", trainerStyle: "trainer"))
        album.recordMemoryHomeVisitStamp(homeID: "nearby-home")

        let loaded = PokemonMemoryAlbum(fileURL: url)
        XCTAssertEqual(loaded.furniturePosition(for: "left"), .clamped(x: 0.32, y: 0.64))
        XCTAssertEqual(loaded.companionPosition(for: companionID), .clamped(x: 0.61, y: 0.67))
        XCTAssertEqual(loaded.memoryHomeAccess.photos.count, 1)
        XCTAssertNotNil(loaded.memoryHomeAccess.visitedHomeStamps["nearby-home"])
    }
}
