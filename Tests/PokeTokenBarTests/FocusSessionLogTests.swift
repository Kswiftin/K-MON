import XCTest
@testable import PokeTokenBar

// 집중 세션 원장 — 완료한 세션을 날짜·길이와 함께 남긴다(PRD 마일스톤 1).
//
// 왜 새 타입인가: 화면과 터미널이 쓰던 `FocusTimer.completedSessions` 는 **프로세스 수명 카운터**라
// 앱을 껐다 켜면 0으로 돌아가고 자정도 모른다. 그런데 터미널은 그 값에 "오늘 마친 집중 N회" 라는
// 라벨을 붙여 내보내고 있었다(`PokedoroViewChannel.focusSnapshot`) — 문구가 값보다 많은 것을
// 약속한 상태였다. 이 원장이 그 약속을 지킨다.
//
// 원장은 순수 값 타입이다. 스토어 없이 자정·보존기간·손상 세이브를 다 밟을 수 있는 자리를 만든다.
final class FocusSessionLogTests: XCTestCase {

    private let clock = TestClock()

    // MARK: 날짜 경계

    /// 자정을 넘긴 세션은 **오늘** 집계에서 빠지고 그날 집계에는 남는다.
    /// `completedSessions` 가 못 하던 바로 그것 — 누적 카운터는 어제 것을 오늘로 계속 센다.
    ///
    /// 36시간을 넘기는 이유: 24시간만 넘기면 DST 로 25시간짜리 날이 되는 지역에서 같은 날에
    /// 머무를 수 있다. 그 경우 이 테스트는 "경계를 넘겼다" 고 믿으면서 아무것도 검증하지 않는다.
    func testYesterdaysSessionLeavesTodaysCount() {
        var log = FocusSessionLog()
        let recordedKey = CompanionStore.dayKey(clock.now)
        log.record(minutes: 25, at: clock.now)

        clock.advance(36 * 3600)
        let todayKey = CompanionStore.dayKey(clock.now)
        XCTAssertNotEqual(recordedKey, todayKey, "테스트 전제: 날짜 키가 실제로 바뀌어야 한다")

        XCTAssertEqual(log.count(on: recordedKey), 1, "기록한 날의 집계는 남아 있어야 한다")
        XCTAssertEqual(log.minutes(on: recordedKey), 25)
        XCTAssertEqual(log.count(on: todayKey), 0, "어제 세션이 오늘로 넘어왔다")
        XCTAssertEqual(log.minutes(on: todayKey), 0)
    }

    /// 같은 날 여러 세션은 개수와 분이 함께 쌓인다.
    func testSameDaySessionsAccumulate() {
        var log = FocusSessionLog()
        log.record(minutes: 25, at: clock.now)
        clock.advance(3600)
        log.record(minutes: 50, at: clock.now)

        let key = CompanionStore.dayKey(clock.now)
        XCTAssertEqual(log.count(on: key), 2)
        XCTAssertEqual(log.minutes(on: key), 75)
    }

    // MARK: 보존 기간

    /// 보존 기간 밖 항목은 기록하는 순간 버려진다 — 원장이 무한히 자라지 않는 유일한 장치다.
    func testRecordDropsEntriesBeyondRetention() {
        var log = FocusSessionLog()
        let oldKey = CompanionStore.dayKey(clock.now)
        log.record(minutes: 25, at: clock.now)

        clock.advance(Double(FocusSessionLog.retentionDays) * 86_400 + 3600)
        log.record(minutes: 25, at: clock.now)

        XCTAssertEqual(log.count(on: oldKey), 0, "보존 기간 밖 세션이 남아 있다")
        XCTAssertEqual(log.count(on: CompanionStore.dayKey(clock.now)), 1)
    }

    // MARK: 신뢰경계 — 디스크에서 온 값

    /// 0분·음수 세션은 기록이 아니라 버그다. 받아 두면 "오늘 5세션" 이 실제 집중과 무관해진다.
    func testNonPositiveMinutesAreNotRecorded() {
        var log = FocusSessionLog()
        log.record(minutes: 0, at: clock.now)
        log.record(minutes: -25, at: clock.now)
        XCTAssertEqual(log.count(on: CompanionStore.dayKey(clock.now)), 0)
    }

    /// 손편집·시계 되돌림으로 들어온 미래 시각과 비현실적 길이를 버린다.
    /// 이 원장은 서명 대상이 아닌 옆 파일이라, 디코딩 직후의 이 정규화가 유일한 관문이다.
    func testNormalizeDropsFutureAndAbsurdEntries() throws {
        let now = clock.now
        let payload: [String: Any] = ["sessions": [
            ["endedAt": now.addingTimeInterval(-3600).timeIntervalSince1970, "minutes": 25],
            ["endedAt": now.addingTimeInterval(3600).timeIntervalSince1970, "minutes": 25],
            ["endedAt": now.timeIntervalSince1970, "minutes": 100_000],
            ["endedAt": now.timeIntervalSince1970, "minutes": 0]
        ]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var log = try FocusSessionLog.decoder.decode(FocusSessionLog.self, from: data)
        XCTAssertEqual(log.sessions.count, 4, "테스트 전제: 정규화 전에는 넷 다 들어와 있어야 한다")

        log.normalize(now: now)

        XCTAssertEqual(log.sessions.count, 1, "미래·과다·0분 항목이 살아남았다")
        XCTAssertEqual(log.minutes(on: CompanionStore.dayKey(now)), 25)
    }

    /// 복원할 수 없는 파일은 기동 때 **지운다**. 그대로 두면 켤 때마다 같은 실패를 반복하고,
    /// 기록이 다시 쌓이기 시작한다는 것을 사용자는 화면에서 알 수 없다.
    /// 웨이브 런 옆 파일이 이미 같은 계약을 지킨다(`loadRogueRun`).
    @MainActor
    func testCorruptLogFileIsDiscardedOnLaunch() {
        let directory = storeDirectory("focus-corrupt")
        let logURL = directory.appendingPathComponent(CompanionStorageLocations.focusSessionsFileName)
        try? Data("이건 JSON 이 아니다".utf8).write(to: logURL)

        let store = CompanionStore(provider: StubProvider(value: stubMaxLevelLine), clock: clock.closure,
                                   fileURL: directory.appendingPathComponent(CompanionStorageLocations.stateFileName),
                                   rng: SeededRNG(seed: 3))

        XCTAssertEqual(store.focusSessionsToday, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path),
                       "복원 못 할 파일이 남으면 다음 기동도 같은 실패를 반복한다")
        // 버린 뒤에도 기록은 정상적으로 다시 쌓인다 — 지우는 것이 곧 복구다.
        store.completeFocusSession(minutes: 25)
        XCTAssertEqual(store.focusSessionsToday, 1)
    }

    /// 왕복(인코딩 → 디코딩)이 값을 보존한다 — 옆 파일에 적고 다음 기동에 읽는 실제 경로다.
    func testEncodingRoundTripPreservesSessions() throws {
        var log = FocusSessionLog()
        log.record(minutes: 25, at: clock.now)
        let data = try FocusSessionLog.encoder.encode(log)
        let restored = try FocusSessionLog.decoder.decode(FocusSessionLog.self, from: data)
        XCTAssertEqual(restored, log)
    }
}
