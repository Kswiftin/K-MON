import XCTest
@testable import PokeTokenBar

@MainActor
final class MemoryHomePokeLogTests: XCTestCase {
    func testPokeLogUsesExistingFactsWithoutCreatingStoredState() throws {
        let url = memoryAlbumURL("poke-log")
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
    func testSeasonRecapCountsOnlyCurrentSeasonEntries() {
        let album = PokemonMemoryAlbum(fileURL: memoryAlbumURL("season-recap"))
        let id = UUID(); let now = Date(timeIntervalSince1970: 1_725_000_000)
        album.record(companionID: id, body: "memory", source: .event, createdAt: now)
        XCTAssertEqual(album.seasonRecap(for: [id], now: now).memoryCount, 1)
    }
}
