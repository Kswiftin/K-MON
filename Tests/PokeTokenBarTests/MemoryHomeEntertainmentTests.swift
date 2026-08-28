import XCTest
@testable import PokeTokenBar

@MainActor
final class MemoryHomeEntertainmentTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-home-entertainment-\(UUID().uuidString).json")
    }

    func testJukeboxSelectionPersistsWithoutChangingLegacyData() {
        let url = temporaryURL()
        let album = PokemonMemoryAlbum(fileURL: url)

        album.setJukeboxTrack(.summerRiver)

        XCTAssertEqual(album.memoryHomeAccess.jukeboxTrack, .summerRiver)
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).memoryHomeAccess.jukeboxTrack, .summerRiver)
    }

    func testGuestbookValidatesBoundsAndPersistsNewestFirst() {
        let url = temporaryURL()
        let album = PokemonMemoryAlbum(fileURL: url)
        let earlier = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)

        XCTAssertTrue(album.addGuestbookEntry(author: "민지", body: "방문 찍고 감~~", authorKind: .trainer, createdAt: earlier))
        XCTAssertTrue(album.addGuestbookEntry(author: "피카츄", body: "pika pika ⚡", authorKind: .companion, createdAt: later))
        XCTAssertFalse(album.addGuestbookEntry(author: "민지", body: "두\n줄", authorKind: .trainer))
        XCTAssertFalse(album.addGuestbookEntry(author: "민지", body: String(repeating: "가", count: MemoryHomeAccessSettings.guestbookBodyLimit + 1), authorKind: .trainer))

        XCTAssertEqual(album.memoryHomeAccess.guestbookEntries.map(\.body), ["pika pika ⚡", "방문 찍고 감~~"])
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).memoryHomeAccess.guestbookEntries.map(\.author), ["피카츄", "민지"])
    }

    func testGuestbookIsBoundedAndLegacySnapshotsGetEntertainmentDefaults() throws {
        let url = temporaryURL()
        let album = PokemonMemoryAlbum(fileURL: url)
        for index in 0..<(MemoryHomeAccessSettings.guestbookLimit + 3) {
            XCTAssertTrue(album.addGuestbookEntry(author: "나", body: "메모 \(index)", authorKind: .trainer,
                                                   createdAt: Date(timeIntervalSince1970: TimeInterval(index))))
        }
        XCTAssertEqual(album.memoryHomeAccess.guestbookEntries.count, MemoryHomeAccessSettings.guestbookLimit)
        XCTAssertEqual(album.memoryHomeAccess.guestbookEntries.first?.body, "메모 \(MemoryHomeAccessSettings.guestbookLimit + 2)")

        let legacyURL = temporaryURL()
        try Data(#"{"memories":{},"pinnedMemoryIDs":{}}"#.utf8).write(to: legacyURL)
        let legacy = PokemonMemoryAlbum(fileURL: legacyURL)
        XCTAssertEqual(legacy.memoryHomeAccess.jukeboxTrack, .afterSchool)
        XCTAssertTrue(legacy.memoryHomeAccess.guestbookEntries.isEmpty)
    }
}
