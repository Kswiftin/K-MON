import XCTest
@testable import PokeTokenBar

// 작업 라벨 — 집중을 시작할 때 붙인 한 줄이 세션과 함께 기록에 남는다(PRD 마일스톤 3).
//
// 라벨은 **사용자가 친 문자열**이라 이 저장소가 지금까지 다뤄 온 값들과 성질이 다르다: 길이도
// 줄 수도 앱이 통제하지 못하고, 원장은 무결성 서명 밖의 옆 파일이라 손으로도 고칠 수 있다.
// 그래서 이 파일이 지키는 것은 크게 셋이다 —
//   ① 정리는 **한 함수**에서만 일어난다(시작 경로와 디스크 경로가 갈리면 화면과 기록이 다른 말을 한다),
//   ② 라벨 칸이 늘어도 **마일스톤 1 형식 파일이 그대로 열린다**(안 열리면 90일치 기준선이 지워진다),
//   ③ 라벨의 수명은 **집중 세션의 수명과 같다**(휴식까지 남으면 화면이 거짓을 말한다).
final class FocusSessionLabelTests: XCTestCase {

    private let clock = TestClock()

    // MARK: ① 정리 — 시작 경로와 디스크 경로가 같은 함수를 탄다

    /// 앞뒤 공백만 있는 라벨은 라벨이 아니다. `""` 를 남기면 "라벨이 붙은 세션 비율"(PRD 성공 지표)이
    /// 라벨 없는 세션까지 세어 부풀려진다.
    func testBlankLabelsBecomeNil() {
        XCTAssertNil(FocusSession.sanitize(label: nil))
        XCTAssertNil(FocusSession.sanitize(label: ""))
        XCTAssertNil(FocusSession.sanitize(label: "   \n\t "))
        XCTAssertEqual(FocusSession.sanitize(label: "  PR 리뷰  "), "PR 리뷰")
    }

    /// 라벨은 **한 줄**이다. 줄바꿈이 남으면 팝오버 카드가 늘어나고, 터미널은 한 줄로 세어 둔
    /// 화면에 두 줄을 그려 그 아래가 통째로 밀린다.
    func testLabelsAreFlattenedToOneLine() {
        let flattened = FocusSession.sanitize(label: "설계\n검토\t마무리")
        XCTAssertEqual(flattened, "설계 검토 마무리")
        XCTAssertFalse(flattened?.contains("\n") ?? true)
    }

    /// 상한을 넘는 라벨은 자른다. 손편집 한 줄로 1,000자를 넣을 수 있고, 그 문자열은 팝오버와
    /// 터미널 두 화면을 지나간다.
    func testOverlongLabelsAreClamped() {
        let long = String(repeating: "가", count: FocusSession.maxLabelCharacters + 20)
        let clamped = FocusSession.sanitize(label: long)
        XCTAssertEqual(clamped?.count, FocusSession.maxLabelCharacters)
    }

    // MARK: ② 형식 호환 — 마일스톤 1 파일이 그대로 열린다

    /// 라벨 칸이 **없는** 파일(마일스톤 1이 90일 동안 쌓아 둔 그 형식)이 그대로 디코딩된다.
    ///
    /// 이게 이번 변경의 유일한 되돌릴 수 없는 위험이다: 디코딩이 실패하면 `loadFocusSessions` 가
    /// 파일을 **지우고**(복원 못 할 파일은 지운다는 계약) 주 지표의 기준선이 함께 사라진다.
    func testMilestoneOneFilesWithoutLabelsStillDecode() throws {
        let payload: [String: Any] = ["sessions": [
            ["endedAt": clock.now.addingTimeInterval(-3600).timeIntervalSince1970, "minutes": 25],
            ["endedAt": clock.now.addingTimeInterval(-1800).timeIntervalSince1970, "minutes": 50]
        ]]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let log = try FocusSessionLog.decoder.decode(FocusSessionLog.self, from: data)

        XCTAssertEqual(log.sessions.count, 2, "라벨 칸이 없는 옛 파일이 통째로 버려졌다")
        XCTAssertNil(log.sessions.first?.label)
        XCTAssertEqual(log.minutes(on: CompanionStore.dayKey(clock.now)), 75)
    }

    // MARK: ③ 신뢰경계 — 디스크에서 온 라벨도 거른다

    /// 디스크에서 온 라벨은 시작 경로를 안 거쳤다. `normalize` 가 유일한 관문이므로 길이·줄바꿈
    /// 규칙을 여기서도 걸어야 한다 — 시작 경로만 정리하면 손편집이 그대로 화면까지 간다.
    func testNormalizeCleansLabelsThatCameFromDisk() throws {
        let payload: [String: Any] = ["sessions": [[
            "endedAt": clock.now.addingTimeInterval(-60).timeIntervalSince1970,
            "minutes": 25,
            "label": "  " + String(repeating: "나", count: 200) + "\n두 번째 줄  "
        ]]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var log = try FocusSessionLog.decoder.decode(FocusSessionLog.self, from: data)

        log.normalize(now: clock.now)

        let label = try XCTUnwrap(log.sessions.first?.label)
        XCTAssertEqual(label.count, FocusSession.maxLabelCharacters, "디스크 라벨이 상한을 넘겼다")
        XCTAssertFalse(label.contains("\n"), "디스크 라벨의 줄바꿈이 살아남았다")
    }

    /// 빈 라벨로 손편집된 항목은 라벨 없는 세션이 된다 — 세션 자체는 버리지 않는다.
    func testNormalizeKeepsSessionsWhoseLabelBecomesEmpty() throws {
        let payload: [String: Any] = ["sessions": [[
            "endedAt": clock.now.addingTimeInterval(-60).timeIntervalSince1970,
            "minutes": 25, "label": "   "
        ]]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var log = try FocusSessionLog.decoder.decode(FocusSessionLog.self, from: data)

        log.normalize(now: clock.now)

        XCTAssertEqual(log.sessions.count, 1, "라벨이 비었다고 세션을 버리면 집계가 줄어든다")
        XCTAssertNil(log.sessions.first?.label)
    }

    // MARK: ④⑤ 타이머 — 라벨의 수명은 세션의 수명과 같다

    /// 완료 훅은 분과 **라벨을 함께** 받는다. 앱 루트가 타이머에서 라벨을 따로 읽게 하면
    /// "비우기 전에 읽어야 한다" 는 순서 계약이 하나 더 생기고, 그 부류는 화면에 아무 오류도
    /// 남기지 않는다(마일스톤 2의 `nextRestMinutes` 가 같은 모양이었다).
    @MainActor
    func testCompletionHookCarriesTheLabelOfTheSessionThatJustEnded() {
        let timer = FocusTimer()
        var recorded: [(Int, String?)] = []
        timer.onFocusCompleted = { minutes, label in recorded.append((minutes, label)) }

        timer.startFocus(minutes: 25, label: "  릴리스 노트  ", now: clock.now)
        timer.tick(now: clock.now.addingTimeInterval(25 * 60))

        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.0, 25)
        XCTAssertEqual(recorded.first?.1, "릴리스 노트", "라벨이 완료 훅까지 오지 않으면 기록에 남을 길이 없다")
    }

    /// 라벨은 **집중 단계에서만** 산다. 휴식으로 넘어가면 비운다 — 안 비우면 15분 긴 휴식 내내
    /// 팝오버와 터미널이 방금 끝난 일을 "지금 하는 일" 로 띄운다.
    @MainActor
    func testLabelIsClearedWhenTheBreakStartsAndWhenTheTimerStops() {
        let timer = FocusTimer()

        timer.startFocus(minutes: 25, label: "설계", now: clock.now)
        XCTAssertEqual(timer.focusLabel, "설계", "테스트 전제: 집중 중에는 라벨이 살아 있다")
        timer.tick(now: clock.now.addingTimeInterval(25 * 60))
        XCTAssertEqual(timer.phase, .rest, "테스트 전제: 휴식으로 넘어갔다")
        XCTAssertNil(timer.focusLabel, "휴식 중에도 라벨이 남아 화면이 거짓을 말한다")

        timer.startFocus(minutes: 25, label: "구현", now: clock.now)
        timer.stop()
        XCTAssertNil(timer.focusLabel, "종료한 세션의 라벨이 다음 세션까지 따라간다")
    }

    /// 라벨 없이 시작하는 경로는 그대로다 — 기존 호출부(대화·터미널)는 인자를 안 넘긴다.
    @MainActor
    func testStartingWithoutALabelStaysLabelless() {
        let timer = FocusTimer()
        timer.startFocus(minutes: 25, now: clock.now)
        XCTAssertNil(timer.focusLabel)
    }

    // MARK: ⑥⑦ 스토어 — 기록에 남고 재기동을 넘는다

    /// 라벨은 세션과 함께 옆 파일에 남고, 앱을 껐다 켜도 그대로 읽힌다.
    /// (마일스톤 1이 개수·분으로 지킨 계약을 라벨까지 넓힌다.)
    @MainActor
    func testLabelSurvivesRelaunch() {
        let clock = TestClock()
        let directory = storeDirectory("focus-label-relaunch")
        let stateURL = directory.appendingPathComponent(CompanionStorageLocations.stateFileName)
        let opened = CompanionStore(provider: StubProvider(value: stubMaxLevelLine), clock: clock.closure,
                                    fileURL: stateURL, rng: SeededRNG(seed: 7))
        opened.completeFocusSession(minutes: 25, label: "PR 리뷰")

        let reopened = CompanionStore(provider: StubProvider(value: stubMaxLevelLine), clock: clock.closure,
                                      fileURL: stateURL, rng: SeededRNG(seed: 7))

        XCTAssertEqual(reopened.todaysFocusSessions.count, 1)
        XCTAssertEqual(reopened.todaysFocusSessions.first?.label, "PR 리뷰", "재기동에 라벨이 사라졌다")
        XCTAssertEqual(reopened.todaysFocusSessions.first?.minutes, 25)
    }

    /// 목록과 개수는 **같은 파생**에서 온다. 갈리면 "오늘 3세션" 인데 두 줄만 보이는 상태가 생긴다.
    @MainActor
    func testTodaysListAndTodaysCountAgree() {
        let store = stubStore(clock, tag: "focus-label-list")
        store.completeFocusSession(minutes: 25, label: "설계")
        clock.advance(3600)
        store.completeFocusSession(minutes: 50)

        XCTAssertEqual(store.todaysFocusSessions.count, store.focusSessionsToday)
        XCTAssertEqual(store.todaysFocusSessions.map(\.minutes).reduce(0, +), store.focusMinutesToday)
        XCTAssertEqual(store.todaysFocusSessions.compactMap(\.label), ["설계"],
                       "라벨 없는 세션이 빈 문자열로 세어졌다")
    }

    /// 어제 라벨이 오늘 목록에 섞이지 않는다 — 목록도 하루 경계를 개수와 같은 키로 본다.
    @MainActor
    func testYesterdaysLabelsLeaveTodaysList() {
        let store = stubStore(clock, tag: "focus-label-midnight")
        store.completeFocusSession(minutes: 25, label: "어제 일")

        clock.advance(36 * 3600)   // 36시간 — DST 로 25시간짜리 날인 지역에서도 자정을 넘긴다

        XCTAssertTrue(store.todaysFocusSessions.isEmpty, "어제 세션이 오늘 목록에 남았다")
    }
}
