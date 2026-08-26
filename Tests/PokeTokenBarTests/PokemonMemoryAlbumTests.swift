import XCTest
@testable import PokeTokenBar

@MainActor
final class PokemonMemoryAlbumTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pokemon-memory-home-\(UUID().uuidString).json")
    }

    func testManualMemoryValidatesGraphemesAndPersists() {
        let url = temporaryURL(), companionID = UUID()
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)

        XCTAssertFalse(album.addManual(companionID: companionID, body: ""))
        XCTAssertFalse(album.addManual(companionID: companionID, body: String(repeating: "👨‍👩‍👧‍👦", count: 281)))
        XCTAssertTrue(album.addManual(companionID: companionID, body: "오늘 함께 집중했다."))

        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).entries(for: companionID).first?.source, .manual)
    }

    func testPinnedMemoryIsScopedToCompanionAndClearsWhenDeleted() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let firstID = UUID(), secondID = UUID()
        album.record(companionID: firstID, body: "First", source: .event)
        album.record(companionID: secondID, body: "Second", source: .event)
        let first = album.entries(for: firstID)[0]
        let second = album.entries(for: secondID)[0]

        album.pin(first)
        album.pin(second)

        XCTAssertEqual(album.pinned(for: firstID)?.id, first.id)
        XCTAssertEqual(album.pinned(for: secondID)?.id, second.id)
        XCTAssertFalse(album.delete(first), "Automatic evidence cannot be deleted")

        XCTAssertTrue(album.addManual(companionID: firstID, body: "Private note"))
        let manual = album.entries(for: firstID).last!
        album.pin(manual)
        XCTAssertTrue(album.delete(manual))
        XCTAssertNil(album.pinned(for: firstID))
    }

    func testTimelineHidesEntriesAndLimitsToTwentyNewest() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL()), companionID = UUID()
        for number in 0..<21 { album.record(companionID: companionID, body: "Event \(number)", source: .event) }
        let hidden = album.entries(for: companionID)[20]

        album.setHidden(hidden, isHidden: true)

        XCTAssertEqual(album.timeline(for: companionID).count, 20)
        XCTAssertFalse(album.timeline(for: companionID).contains(where: { $0.id == hidden.id }))
    }

    func testLegacySnapshotDecodesAndCorruptFileIsBackedUp() throws {
        let url = temporaryURL(), companionID = UUID()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
        }
        let legacy = """
        {"memories":{"\(companionID.uuidString)":[{"id":"\(UUID().uuidString)","companionID":"\(companionID.uuidString)","createdAt":1,"source":"event","body":"Legacy"}]}}
        """
        try Data(legacy.utf8).write(to: url)
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).entries(for: companionID).count, 1)

        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(PokemonMemoryAlbum(fileURL: url).entries(for: companionID).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }
}
