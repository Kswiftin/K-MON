import XCTest
@testable import PokeTokenBar

@MainActor
final class MemoryHomeViewTests: XCTestCase {
    func testMiniRoomThemeMapsEachPersistedThemeToItsTint() {
        XCTAssertEqual(MemoryHomeRoomTheme.tint(for: .blue), PokedoroTheme.blue)
        XCTAssertEqual(MemoryHomeRoomTheme.tint(for: .mint), PokedoroTheme.mint)
        XCTAssertEqual(MemoryHomeRoomTheme.tint(for: .yellow), PokedoroTheme.yellow)
        XCTAssertEqual(MemoryHomeRoomTheme.tint(for: .red), PokedoroTheme.red)
    }

    /// 방 스타일 4종의 색과 세 언어 이름. 테마(사용자가 고른 4색)와 **다른 축**이라 색이
    /// 겹쳐도 컴파일러는 아무 말을 하지 않는다.
    func testRoomStyleHasADistinctTintAndNamePerStyle() {
        let tints = MemoryHomeRoomStyle.allCases.map(MemoryHomeRoomStyle.tint(for:))
        XCTAssertEqual(Set(tints.map(String.init(describing:))).count, MemoryHomeRoomStyle.allCases.count,
                       "스타일 색이 겹쳤다")
        for language in [AppLanguage.ko, .en, .ja] {
            let names = MemoryHomeRoomStyle.allCases.map { $0.name(L(language)) }
            XCTAssertEqual(Set(names).count, MemoryHomeRoomStyle.allCases.count,
                           "\(language): 스타일 이름이 겹쳤다")
            XCTAssertFalse(names.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
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
