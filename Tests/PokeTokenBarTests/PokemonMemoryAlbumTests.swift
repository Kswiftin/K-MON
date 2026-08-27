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

    func testDistinctStableEventIDsKeepRepeatedEventsWhileReplayIsIdempotent() {
        let url = temporaryURL(), companionID = UUID()
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)

        album.record(companionID: companionID, body: "First adventure", source: .event,
                     eventID: "adventure:run-1")
        album.record(companionID: companionID, body: "Second adventure", source: .event,
                     eventID: "adventure:run-2")
        album.record(companionID: companionID, body: "Replay", source: .event,
                     eventID: "adventure:run-1")

        XCTAssertEqual(album.entries(for: companionID).map(\.eventID),
                       ["adventure:run-1", "adventure:run-2"])
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).entries(for: companionID).count, 2,
                       "Persisted event IDs must also suppress a replay after relaunch")
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
        let migrated = PokemonMemoryAlbum(fileURL: url)
        XCTAssertEqual(migrated.entries(for: companionID).count, 1)
        XCTAssertEqual(migrated.firstRecordedAt(for: companionID), legacy.memories[companionID]?.first?.createdAt,
                       "Old albums derive their first-record date from their earliest retained memory")

        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(PokemonMemoryAlbum(fileURL: url).entries(for: companionID).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }

    func testMilestonesCountOnlyNewSettlementsAndPersistAcrossRelaunch() {
        let url = temporaryURL(), companionID = UUID()
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)
        let first = Date(timeIntervalSinceReferenceDate: 1_000)
        album.record(companionID: companionID, body: "First", source: .event, createdAt: first)
        for number in 0..<10 {
            album.recordCompletedFocusSession(companionID: companionID, sessionID: "run-\(number)",
                                              completedAt: first.addingTimeInterval(Double(number + 1)))
        }
        album.recordCompletedFocusSession(companionID: companionID, sessionID: "run-9",
                                          completedAt: first.addingTimeInterval(99))

        let milestones = album.milestones(for: companionID, now: first)
        XCTAssertEqual(album.firstRecordedAt(for: companionID), first)
        XCTAssertEqual(milestones.map(\.id), ["first-record", "focus-10"])
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).milestones(for: companionID, now: first).map(\.id),
                       ["first-record", "focus-10"])
    }

    func testFocusMilestoneBoundariesAndEvolutionSurviveMemoryEviction() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL()), companionID = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        for number in 0..<100 {
            album.recordCompletedFocusSession(companionID: companionID, sessionID: "run-\(number)",
                                              completedAt: start.addingTimeInterval(Double(number)))
        }
        album.recordEvolution(companionID: companionID, eventID: "evolution-stable-id", evolvedSpeciesID: 26,
                              occurredAt: start)
        for number in 0...200 {
            album.record(companionID: companionID, body: "Event \(number)", source: .event,
                         eventID: "event-\(number)", createdAt: start.addingTimeInterval(Double(number + 200)))
        }

        let ids = album.milestones(for: companionID, now: start).map(\.id)
        XCTAssertTrue(ids.contains("focus-10"))
        XCTAssertTrue(ids.contains("focus-30"))
        XCTAssertTrue(ids.contains("focus-100"))
        XCTAssertTrue(ids.contains("evolution:evolution-stable-id"))
        XCTAssertEqual(album.entries(for: companionID).count, 200)
    }

    func testFirstRecordAnniversaryUsesThePersistedFirstDate() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL()), companionID = UUID()
        let first = Date(timeIntervalSinceReferenceDate: 10_000)
        album.record(companionID: companionID, body: "First", source: .event, createdAt: first)
        let almostYear = Calendar.current.date(byAdding: .day, value: 364, to: first)!
        let anniversary = Calendar.current.date(byAdding: .year, value: 1, to: first)!

        XCTAssertFalse(album.milestones(for: companionID, now: almostYear).contains { $0.id == "anniversary-1" })
        XCTAssertTrue(album.milestones(for: companionID, now: anniversary).contains { $0.id == "anniversary-1" })
    }
}
