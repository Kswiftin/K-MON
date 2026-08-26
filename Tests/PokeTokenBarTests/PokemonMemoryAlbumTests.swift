import XCTest
@testable import PokeTokenBar

private struct LegacyMemorySnapshot: Codable {
    let memories: [UUID: [LegacyMemory]]
}

private struct LegacyMemory: Codable {
    let id: UUID
    let companionID: UUID
    let createdAt: Date
    let source: PokemonMemorySource
    let body: String
    let eventID: String?
}

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

    func testAutomaticMemoryCanBeHiddenRestoredAndPersists() {
        let url = temporaryURL(), companionID = UUID()
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)
        album.record(companionID: companionID, body: "Event", source: .event)
        let automatic = album.entries(for: companionID)[0]

        XCTAssertTrue(album.setHidden(automatic, isHidden: true))
        XCTAssertTrue(PokemonMemoryAlbum(fileURL: url).entries(for: companionID)[0].isHidden)

        let reloaded = PokemonMemoryAlbum(fileURL: url)
        let hidden = reloaded.entries(for: companionID)[0]
        XCTAssertTrue(reloaded.setHidden(hidden, isHidden: false))
        XCTAssertFalse(PokemonMemoryAlbum(fileURL: url).entries(for: companionID)[0].isHidden)
        XCTAssertFalse(reloaded.delete(hidden), "Automatic evidence cannot be deleted")
    }

    func testTimelineHidesEntriesAndLimitsToTwentyNewest() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL()), companionID = UUID()
        for number in 0..<20 { album.record(companionID: companionID, body: "Event \(number)", source: .event) }
        XCTAssertTrue(album.addManual(companionID: companionID, body: "Private note"))
        let hidden = album.entries(for: companionID)[20]

        album.setHidden(hidden, isHidden: true)

        XCTAssertEqual(album.timeline(for: companionID).count, 20)
        XCTAssertFalse(album.timeline(for: companionID).contains(where: { $0.id == hidden.id }))
    }

    func testAlbumKeepsTwoHundredEntriesAndClearsAnEvictedPin() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL()), companionID = UUID()
        for number in 0..<200 { album.record(companionID: companionID, body: "Event \(number)", source: .event) }
        album.pin(album.entries(for: companionID)[0])

        album.record(companionID: companionID, body: "Event 200", source: .event)

        XCTAssertEqual(album.entries(for: companionID).count, 200)
        XCTAssertNil(album.pinned(for: companionID))
    }

    func testPruningRemovesDanglingEntriesAndPins() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let retainedID = UUID(), releasedID = UUID()
        album.record(companionID: retainedID, body: "Keep", source: .event)
        album.record(companionID: releasedID, body: "Remove", source: .event)
        album.pin(album.entries(for: releasedID)[0])

        album.prune(validCompanionIDs: [retainedID])

        XCTAssertTrue(album.entries(for: releasedID).isEmpty)
        XCTAssertNil(album.pinned(for: releasedID))
    }

    func testLegacySnapshotDecodesAndCorruptFileIsBackedUp() throws {
        let url = temporaryURL(), companionID = UUID()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
        }
        let legacy = LegacyMemorySnapshot(memories: [companionID: [
            LegacyMemory(id: UUID(), companionID: companionID, createdAt: Date(), source: .event,
                         body: "Legacy", eventID: nil)
        ]])
        try JSONEncoder().encode(legacy).write(to: url)
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).entries(for: companionID).count, 1)

        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(PokemonMemoryAlbum(fileURL: url).entries(for: companionID).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }
}
