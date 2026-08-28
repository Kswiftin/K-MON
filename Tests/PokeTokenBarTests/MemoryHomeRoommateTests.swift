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
    }
}
