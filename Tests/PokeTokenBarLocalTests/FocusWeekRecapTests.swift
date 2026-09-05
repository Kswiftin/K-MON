import Foundation
import Testing
@testable import PokeTokenBar

/// 주간 회고 — 한 주의 집중을 요일·라벨별로 되돌아보는 표(PRD 마일스톤 4).
///
/// **저장하는 것이 하나도 없다.** 회고는 마일스톤 1–3 이 쌓아 둔 원장(`FocusSessionLog`)에서
/// 전부 파생한다 — `FocusChainRules` 가 체인 위치를 파생시킨 것과 같은 형태다. 그래서 이 스위트는
/// 스토어 없이 자정·주 경계·보존 기간·손상 입력을 다 밟을 수 있다.
///
/// 여기서 지키는 것 중 **가장 조용히 틀릴 수 있는 값은 하루 평균의 분모**다. 항상 7로 나누면
/// 월요일 오전의 이번 주가 어느 지난주보다도 무조건 나빠 보이는데, 이 화면이 존재하는 이유가
/// 정확히 주 대 주 비교라 그 나눗셈 하나가 PRD 주 지표를 통째로 거꾸로 읽게 만든다.
@Suite("FocusWeekRecapTests")
struct FocusWeekRecapTests {

    /// 기준 시각. 값 자체엔 뜻이 없고, **여기서 그 주의 월요일을 뽑아** 모든 날짜를 파생시킨다 —
    /// 요일을 손으로 적으면 그 하드코딩이 곧 이 스위트의 첫 번째 거짓말이 된다.
    private static let reference = Date(timeIntervalSince1970: 1_757_000_000)

    private var calendar: Calendar { CompanionStore.isoCalendar }
    private var monday: Date { CompanionStore.weekStart(Self.reference) }

    /// 그 주 `day` 번째 날(0 = 월요일)의 `hour` 시 `minute` 분.
    /// **초 산술을 쓰지 않는다** — DST 가 있는 지역에서 하루가 23·25시간이라 주 안에서도 밀린다.
    private func moment(day: Int, hour: Int, minute: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: day, to: monday)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    }

    /// 세션을 **시간 오름차순으로** 적는다. `record` 는 적을 때마다 정규화하며 미래 항목을
    /// 버리므로(`FocusSessionLog.normalize`), 거꾸로 넣으면 앞서 넣은 것이 조용히 사라진다.
    private func log(_ entries: [(Date, Int, String?)]) -> FocusSessionLog {
        var log = FocusSessionLog()
        for (at, minutes, label) in entries.sorted(by: { $0.0 < $1.0 }) {
            log.record(minutes: minutes, label: label, at: at)
        }
        return log
    }

    // MARK: 주 경계

    /// 주는 **월요일에 시작해 일요일에 끝나고 항상 일곱 칸**이다.
    ///
    /// 일요일 23:55 세션은 이번 주의 마지막 칸이어야 하고, 월요일 00:00 직전 세션은 이번 주가
    /// 아니어야 한다. 경계가 하루 밀리면 회고의 모든 숫자가 조용히 한 칸씩 어긋나는데, 그 어긋남은
    /// 합계가 여전히 그럴듯해서 화면만 봐서는 알 수 없다.
    @Test func testTheWeekRunsMondayThroughSundayInSevenSlots() {
        let recap = FocusWeekRecap.build(
            log: log([(moment(day: -1, hour: 23), 25, nil),          // 지난 주 일요일
                      (moment(day: 0, hour: 0, minute: 5), 25, nil),
                      (moment(day: 6, hour: 23, minute: 55), 50, nil),
                      (moment(day: 7, hour: 1), 25, nil)]),          // 다음 주 월요일
            weekStart: monday, now: moment(day: 7, hour: 2))

        #expect(recap.days.count == 7)
        // 그레고리력 요일 번호: 1 = 일요일, 2 = 월요일.
        #expect(calendar.component(.weekday, from: recap.days[0].date) == 2, "주가 월요일에 시작하지 않는다")
        #expect(calendar.component(.weekday, from: recap.days[6].date) == 1, "주가 일요일에 끝나지 않는다")
        #expect(recap.days[0].sessions == 1, "월요일 00:05 세션이 첫 칸에 없다")
        #expect(recap.days[6].minutes == 50, "일요일 23:55 세션이 마지막 칸에 없다")
        #expect(recap.sessions == 2, "주 밖 세션이 섞여 들어왔다")
    }

    /// 회고의 "이번 주" 와 주간 미션의 "이번 주" 가 **같아야 한다.**
    ///
    /// 주간 미션·주간 모험이 이미 `CompanionStore.weekKey` 로 주를 센다. 회고만 다른 달력을 쓰면
    /// 같은 앱이 "이번 주" 를 두 가지로 말하는데, 그 차이는 일요일 하루에만 드러나 리포트도 안 온다.
    @Test func testEveryDayOfTheWeekSharesTheWeekKeyWithItsStart() {
        let recap = FocusWeekRecap.build(log: FocusSessionLog(), weekStart: monday,
                                         now: moment(day: 3, hour: 12))
        let expected = CompanionStore.weekKey(recap.weekStart)
        for day in recap.days {
            #expect(CompanionStore.weekKey(day.date) == expected,
                    "\(day.dayKey) 가 회고와 다른 주에 속한다 — 달력이 둘로 갈렸다")
        }
    }

    /// 요일 막대의 합과 라벨 목록의 합이 **같은 수를 말해야** 한다. 갈리면 화면이 스스로 모순되고,
    /// 그때 사용자가 믿을 수 없게 되는 것은 화면이 아니라 기록 전체다.
    @Test func testTheDayBarsAndTheLabelListReportTheSameTotals() {
        let recap = FocusWeekRecap.build(
            log: log([(moment(day: 0, hour: 9), 25, "리뷰"),
                      (moment(day: 0, hour: 11), 50, nil),
                      (moment(day: 3, hour: 14), 25, "리뷰"),
                      (moment(day: 5, hour: 16), 90, "설계")]),
            weekStart: monday, now: moment(day: 6, hour: 20))

        #expect(recap.days.reduce(0) { $0 + $1.sessions } == recap.sessions)
        #expect(recap.days.reduce(0) { $0 + $1.minutes } == recap.minutes)
        #expect(recap.labels.reduce(0) { $0 + $1.sessions } == recap.sessions,
                "라벨 없는 세션이 목록에서 빠져 합이 갈렸다")
        #expect(recap.labels.reduce(0) { $0 + $1.minutes } == recap.minutes)
        #expect(recap.sessions == 4 && recap.minutes == 190)
    }

    // MARK: 하루 평균 — 이 계획에서 가장 조용히 틀릴 값

    /// **이번 주는 지나간 날 수로, 지난 주는 7로 나눈다.**
    ///
    /// 항상 7로 나누면 월요일 오전의 이번 주가 어느 지난주보다도 무조건 나빠 보인다. 주 대 주
    /// 비교가 이 화면의 존재 이유라, 그 분모 하나가 PRD 주 지표를 거꾸로 읽게 만든다.
    @Test func testTheDailyAverageDividesByElapsedDaysThisWeekAndBySevenForPastWeeks() {
        let entries: [(Date, Int, String?)] = [(moment(day: 0, hour: 9), 25, nil),
                                               (moment(day: 1, hour: 9), 25, nil),
                                               (moment(day: 2, hour: 9), 25, nil)]
        // 수요일 정오 — 월·화·수 사흘이 지났다.
        let thisWeek = FocusWeekRecap.build(log: log(entries), weekStart: monday,
                                            now: moment(day: 2, hour: 12))
        #expect(thisWeek.elapsedDays == 3, "이번 주인데 분모가 지나간 날 수가 아니다")
        #expect(thisWeek.dailyAverageSessions == 1.0)

        // 같은 세 세션을 지나간 주로 보면 분모는 7이다.
        let pastWeek = FocusWeekRecap.build(log: log(entries), weekStart: monday,
                                            now: moment(day: 9, hour: 12))
        #expect(pastWeek.elapsedDays == 7, "지나간 주인데 분모가 7이 아니다")
        #expect(pastWeek.dailyAverageSessions < thisWeek.dailyAverageSessions,
                "같은 세션 수인데 지난 주와 이번 주의 평균이 같다 — 분모가 고정됐다")
    }

    /// 주 마지막 날에는 이번 주와 지나간 주의 분모가 만난다 — 상한이 7을 넘지 않는지 본다.
    @Test func testTheElapsedDayCountNeverExceedsSeven() {
        let recap = FocusWeekRecap.build(log: FocusSessionLog(), weekStart: monday,
                                         now: moment(day: 6, hour: 23, minute: 59))
        #expect(recap.elapsedDays == 7)
    }

    // MARK: 라벨

    /// 라벨 목록은 **분 내림차순, 동률이면 라벨 오름차순**이고 라벨 없는 묶음이 맨 뒤다.
    ///
    /// 정렬이 불안정하면 팝오버를 닫았다 열 때마다 같은 주가 다른 순서로 보인다. 회고에서
    /// 그건 곧 "이 화면은 매번 다른 말을 한다" 는 신호다.
    @Test func testLabelTotalsSortByMinutesThenLabelAndKeepTheUnlabeledBucketLast() {
        let entries: [(Date, Int, String?)] = [(moment(day: 0, hour: 9), 25, "나중"),
                                               (moment(day: 1, hour: 9), 25, "가나다"),
                                               (moment(day: 2, hour: 9), 90, "설계"),
                                               (moment(day: 3, hour: 9), 50, nil)]
        let recap = FocusWeekRecap.build(log: log(entries), weekStart: monday,
                                         now: moment(day: 4, hour: 9))

        #expect(recap.labels.map(\.label) == ["설계", "가나다", "나중", nil],
                "정렬이 분 내림차순 → 라벨 오름차순 → 라벨 없음 순이 아니다")
        #expect(recap.labeledSessions == 3, "라벨 없는 세션이 라벨 붙은 세션으로 세어졌다")

        // 같은 입력을 두 번 빌드하면 같은 순서다 — 불안정 정렬을 여기서 잡는다.
        let again = FocusWeekRecap.build(log: log(entries), weekStart: monday,
                                         now: moment(day: 4, hour: 9))
        #expect(again.labels == recap.labels)
    }

    /// 같은 라벨의 여러 세션은 한 줄로 합쳐진다 — 회고는 목록이 아니라 요약이다.
    @Test func testSessionsSharingALabelCollapseIntoOneRow() {
        let recap = FocusWeekRecap.build(
            log: log([(moment(day: 0, hour: 9), 25, "리뷰"),
                      (moment(day: 2, hour: 9), 50, "리뷰")]),
            weekStart: monday, now: moment(day: 3, hour: 9))

        #expect(recap.labels.count == 1)
        #expect(recap.labels.first?.sessions == 2 && recap.labels.first?.minutes == 75)
    }

    // MARK: 체인 지속률(근사)

    /// 앞 세션이 끝나고 창(30분) 안에 다음 세션이 **시작**됐으면 이어진 것으로 센다.
    ///
    /// PRD 지표 2("세션 체인 지속률")를 새 계측 없이 원장에서 근사하는 값이다. 시작 시각이
    /// 저장돼 있지 않아 `endedAt - minutes` 로 되돌려 계산한다.
    @Test func testChainedSessionsCountOnlyStartsInsideTheWindow() {
        // 09:25 종료 → 09:35 시작(간격 10분, 이어짐) → 10:00 종료.
        let chained = FocusWeekRecap.build(
            log: log([(moment(day: 0, hour: 9, minute: 25), 25, nil),
                      (moment(day: 0, hour: 10, minute: 0), 25, nil)]),
            weekStart: monday, now: moment(day: 1, hour: 9))
        #expect(chained.chainedSessions == 1, "창 안에서 시작한 세션이 안 세어졌다")

        // 09:25 종료 → 12:00 시작(간격 2시간 35분, 끊김).
        let broken = FocusWeekRecap.build(
            log: log([(moment(day: 0, hour: 9, minute: 25), 25, nil),
                      (moment(day: 0, hour: 12, minute: 25), 25, nil)]),
            weekStart: monday, now: moment(day: 1, hour: 9))
        #expect(broken.chainedSessions == 0, "창 밖에서 시작한 세션이 이어진 것으로 세어졌다")
    }

    /// **자정을 넘어도 이어진 것이다.** 23:50 에 끝내고 00:10 에 시작한 것은 사람에게 한 흐름이다 —
    /// 날짜별로 쪼개 세면 그 한 번이 매번 끊긴 것으로 기록된다.
    @Test func testAChainSurvivesMidnight() {
        let recap = FocusWeekRecap.build(
            log: log([(moment(day: 0, hour: 23, minute: 50), 25, nil),
                      (moment(day: 1, hour: 0, minute: 35), 25, nil)]),
            weekStart: monday, now: moment(day: 2, hour: 9))
        #expect(recap.chainedSessions == 1)
    }

    /// 겹친 세션(간격이 음수)은 안 센다. 이 원장은 무결성 서명 밖이라 손으로 고칠 수 있고,
    /// 겹치도록 적으면 "전부 이어졌다" 는 100% 짜리 가짜 지표를 만들 수 있다.
    @Test func testOverlappingSessionsDoNotCountAsChained() {
        let recap = FocusWeekRecap.build(
            log: log([(moment(day: 0, hour: 10, minute: 0), 25, nil),
                      (moment(day: 0, hour: 10, minute: 5), 25, nil)]),  // 09:40 시작 — 앞 세션과 겹친다
            weekStart: monday, now: moment(day: 1, hour: 9))
        #expect(recap.chainedSessions == 0, "겹친 세션이 이어진 것으로 세어졌다")
    }

    // MARK: 되돌아볼 수 있는 범위

    /// **가장 오래된 주가 통째로 보존 기간 안**이어야 한다 — 주의 **어느 요일에 열어도.**
    ///
    /// 상한을 손으로 적으면(12) 앞부분이 이미 잘려 나간 반쪽 주가 목록에 남고, 반쪽 주를 온전한
    /// 주와 나란히 비교하는 순간 그 비교가 곧 오답이다. 보존 기간에서 파생해야 90일을 늘렸을 때
    /// 범위가 따라 늘고, 줄였을 때 따라 준다.
    ///
    /// **일곱 요일을 다 훑는 이유**: 이 값이 아슬아슬해지는 건 주의 **끝**에서다. 오프셋은 이번 주
    /// 월요일에서 재는데 그 월요일은 `now` 로부터 최대 7일 전이라, 수요일에 열면 12주도 통과하고
    /// 일요일 밤에 열어야 비로소 넘친다. 실제로 처음엔 기준 시각 하나(수요일)만 넣었더니 상한을
    /// 12로 망가뜨려도 초록이었다 — 결함 트리거와 **다른 경로**로 통과해 아무것도 안 지키고 있었다.
    @Test func testTheOldestReachableWeekFitsEntirelyInsideRetentionOnEveryWeekday() {
        for day in 0..<7 {
            let now = moment(day: day, hour: 23, minute: 59)
            let oldest = CompanionStore.weekStart(now, weeksAgo: FocusWeekRecap.maxWeeksBack)
            let retentionFloor = now.addingTimeInterval(-Double(FocusSessionLog.retentionDays) * 86_400)
            #expect(oldest >= retentionFloor, """
                \(day) 번째 요일에 열면 가장 오래된 회고 주의 앞부분이 보존 기간 밖이다 — \
                반쪽 주를 온전한 주와 나란히 놓고 늘었다/줄었다를 읽게 된다
                """)
        }
    }

    /// 주를 거슬러 오를 때 **한 주씩** 움직인다. 초 산술(`-86_400 * 7`)로 만들면 DST 가 있는
    /// 지역에서 두 오프셋이 같은 주에 떨어져 "지난 주" 버튼이 아무 일도 안 하는 구간이 생긴다.
    @Test func testEachStepBackLandsOnADistinctWeek() {
        let keys = (0...FocusWeekRecap.maxWeeksBack).map {
            CompanionStore.weekKey(CompanionStore.weekStart(Self.reference, weeksAgo: $0))
        }
        #expect(Set(keys).count == keys.count, "서로 다른 오프셋이 같은 주를 가리킨다: \(keys)")
    }

    // MARK: 빈 주

    /// 세션이 하나도 없는 주도 일곱 칸을 내놓고, 평균 계산이 0으로 나누지 않는다.
    /// 앱을 처음 켠 주와 쉬어 간 주가 여기 해당한다 — 화면이 가장 먼저 만나는 상태다.
    @Test func testAnEmptyWeekStillHasSevenZeroDays() {
        let recap = FocusWeekRecap.build(log: FocusSessionLog(), weekStart: monday,
                                         now: moment(day: 2, hour: 12))
        #expect(recap.days.count == 7)
        #expect(recap.days.allSatisfy { $0.sessions == 0 && $0.minutes == 0 })
        #expect(recap.labels.isEmpty)
        #expect(recap.sessions == 0 && recap.minutes == 0 && recap.chainedSessions == 0)
        #expect(recap.dailyAverageSessions == 0, "빈 주의 평균이 0이 아니다(0으로 나눴다)")
    }
}

/// 스토어를 거치는 경로 — 회고가 **재기동을 넘는가**. 원장은 옆 파일에 남으므로 넘어야 맞다.
@MainActor
@Suite("FocusWeekRecapStoreTests")
struct FocusWeekRecapStoreTests {

    /// 그 주 월요일 09:00 에 멈춰 있는 시계. 스토어는 클로저를 받아 두므로 이 값을 그대로 본다.
    private static var mondayMorning: Date {
        CompanionStore.weekStart(Date(timeIntervalSince1970: 1_757_000_000))
            .addingTimeInterval(9 * 3600)
    }

    /// 라벨을 붙여 마친 세션이 앱을 껐다 켠 뒤에도 회고의 **같은 요일·같은 라벨**에 남는다.
    /// 마일스톤 1–3 이 옆 파일에 쌓아 둔 것이 회고의 유일한 입력이라, 이 경로가 끊기면 화면이
    /// 켤 때마다 빈 주를 그린다.
    @Test func testTheRecapSurvivesARelaunch() throws {
        let directory = storeFixtureDirectory("focus-recap")
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent(CompanionStorageLocations.stateFileName)
        let now = Self.mondayMorning

        let store = CompanionStore(clock: { now }, fileURL: stateURL)
        store.completeFocusSession(minutes: 25, label: "PR 리뷰")

        let reopened = CompanionStore(clock: { now }, fileURL: stateURL)
        let recap = reopened.focusRecap()

        #expect(recap.days[0].sessions == 1, "재기동 후 월요일 칸이 비었다")
        #expect(recap.days[0].minutes == 25)
        #expect(recap.labels.first?.label == "PR 리뷰")
        #expect(recap.labeledSessions == 1)
    }

    /// 지나간 주를 물으면 이번 주 세션이 섞이지 않는다 — 오프셋이 안 먹으면 주 이동 버튼이
    /// 아무 일도 안 하면서 매번 같은 숫자를 보여 준다.
    @Test func testAskingForALastWeekRecapDoesNotIncludeThisWeek() throws {
        let directory = storeFixtureDirectory("focus-recap-offset")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Self.mondayMorning

        let store = CompanionStore(clock: { now },
                                   fileURL: directory.appendingPathComponent(CompanionStorageLocations.stateFileName))
        store.completeFocusSession(minutes: 25, label: "이번 주")

        #expect(store.focusRecap().sessions == 1)
        #expect(store.focusRecap(weeksAgo: 1).sessions == 0, "지난 주 회고에 이번 주 세션이 들어왔다")
    }
}
