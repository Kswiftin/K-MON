import XCTest
@testable import PokeTokenBar

@MainActor
final class MemoryHomePokeLogTests: XCTestCase {
    func testPokeLogUsesExistingFactsWithoutCreatingStoredState() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let album = PokemonMemoryAlbum(fileURL: url)
        let id = UUID(); let met = Date(timeIntervalSince1970: 1_700_000_000)
        album.recordFirstMeeting(companionID: id, at: met)
        album.record(companionID: id, body: "Met on an adventure", source: .event, createdAt: met)
        album.recordCompletedFocusSession(companionID: id, sessionID: "one", completedAt: met)
        let log = album.pokeLog(for: id, now: met.addingTimeInterval(31 * 86_400))
        XCTAssertEqual(log.daysTogether, 31)
        XCTAssertEqual(log.completedFocusSessions, 1)
        XCTAssertEqual(log.firstMeetingMethod?.body, "Met on an adventure")
        XCTAssertGreaterThanOrEqual(log.closenessHearts, 2)
    }
}
