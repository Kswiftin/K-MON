import XCTest
@testable import PokeTokenBar

@MainActor
final class MemoryHomeRoomRenovationTests: XCTestCase {
    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("room-r8-\(UUID().uuidString).json") }

    func testPlacementSnapsAvoidsCollisionsAndRespectsInventory() {
        let file = url(); defer { try? FileManager.default.removeItem(at: file) }
        let album = PokemonMemoryAlbum(fileURL: file)
        let owned = [ItemKind.roomBed.rawValue: 2]
        let first = album.placeDecor(.roomBed, at: .init(x: 0.51, y: 0.61), ownedItems: owned)
        let second = album.placeDecor(.roomBed, at: .init(x: 0.51, y: 0.61), ownedItems: owned)
        XCTAssertNotNil(first); XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.position, second?.position)
        XCTAssertFalse(album.moveDecor(id: UUID(), to: .init(x: 0, y: 0)))
        XCTAssertNil(album.placeDecor(.roomBed, at: .init(x: 0.5, y: 0.6), ownedItems: owned))
    }

    func testLegacySlotsMigrateToCampusGridAndPersist() {
        let file = url(); defer { try? FileManager.default.removeItem(at: file) }
        var access = MemoryHomeAccessSettings()
        access.roomLayout = ["left": .roomBed, "center": .roomTable, "right": .roomLamp]
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:], memoryHomeAccess: access)
        let album = PokemonMemoryAlbum(fileURL: file)
        album.replace(with: snapshot, validCompanionIDs: [])
        XCTAssertEqual(album.roomStyle, .campus)
        XCTAssertEqual(album.memoryHomeAccess.placedDecor.count, 3)
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: file).memoryHomeAccess.placedDecor.count, 3)
    }

    func testFeaturedPhotoAndStyleTicketsAreExplicit() {
        let album = PokemonMemoryAlbum(fileURL: url())
        XCTAssertTrue(album.isRoomStyleUnlocked(.campus))
        XCTAssertFalse(album.isRoomStyleUnlocked(.lovely))
        album.unlockRoomStyle(.lovely); album.selectRoomStyle(.lovely)
        XCTAssertEqual(album.roomStyle, .lovely)
        let photo = MemoryHomePhoto(speciesID: 25, isShiny: false, caption: "", frame: "a", background: "b", composition: "c", trainerStyle: "d")
        album.addPhoto(photo); album.setFeaturedPhoto(id: photo.id)
        XCTAssertEqual(album.memoryHomeAccess.featuredPhotoID, photo.id)
    }
}
