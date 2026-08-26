import XCTest
@testable import PokeTokenBar

@MainActor
final class MemoryHomeViewTests: XCTestCase {
    func testMemoryHomeCanBeConstructedForTheActiveCompanion() {
        let store = CompanionStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-home-view-\(UUID().uuidString).json"))

        XCTAssertNotNil(MemoryHomeView(store: store))
    }

    func testMemoryHomeIsEnabledAndDiagnosticsRecordOnlyAfterOptIn() throws {
        let suite = "memory-home-settings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let settings = AppSettings(defaults: defaults, clock: { date })

        XCTAssertTrue(settings.memoryHomeEnabled)
        XCTAssertFalse(settings.memoryHomeDiagnosticsEnabled)
        settings.recordMemoryHomeEntry(); settings.recordManualMemoryCreated()
        let beforeOptIn = try XCTUnwrap(JSONSerialization.jsonObject(with: settings.memoryHomeDiagnosticsData()) as? [String: Any])
        XCTAssertEqual(beforeOptIn["homeEntriesByWeek"] as? [String: Int], [:])
        XCTAssertEqual(beforeOptIn["manualMemoriesByWeek"] as? [String: Int], [:])

        settings.memoryHomeDiagnosticsEnabled = true
        settings.recordMemoryHomeEntry(); settings.recordManualMemoryCreated()
        let json = String(decoding: try settings.memoryHomeDiagnosticsData(), as: UTF8.self)
        XCTAssertTrue(json.contains("homeEntriesByWeek"))
        XCTAssertTrue(json.contains("manualMemoriesByWeek"))
        XCTAssertFalse(json.contains("private note"))
        XCTAssertFalse(json.contains("companionID"))
    }
}
