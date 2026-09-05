import XCTest
@testable import PokeTokenBar

// 세션 체인 — 휴식이 끝나면 다음 집중이 이어진다(PRD 마일스톤 2).
//
// 고치는 것: `FocusTimer.tick` 은 휴식이 끝나면 `stop()` 으로 idle 에 떨어뜨리고 거기서 끝난다.
// "다음 세션을 시작할 이유도 신호도 없어 앱을 잊는" pain 이 정확히 그 한 줄이다.
//
// **체인 상태를 새로 만들지 않는다.** 체인 위치는 마일스톤 1의 원장(`FocusSessionLog`)이 낸
// 오늘 세션 수에서 파생한다 — 그래서 재기동해도 긴 휴식 주기가 처음부터 다시 시작되지 않고,
// 자정에는 저절로 리셋된다. 아래 `testLongRestCadenceResetsAtMidnight` 가 그 파생을 지킨다.
//
// 판정이 순수한 이유: `FocusTimer` 도 `CompanionStore` 도 `@MainActor` 에 네트워크까지 물려 있어,
// 조건표를 거기 두면 표만 따로 검증할 방법이 없어진다(`PokedoroSessionGate` 와 같은 이유).
final class FocusChainTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_755_000_000)

    /// 인자 하나만 바꿔 가며 분기를 밟는다. **단독 분기 검증에 필요하다** — 두 조건을 함께
    /// 흔들면 `A || B` 게이트에서 B 단독 경로를 영영 안 밟고도 초록이 뜬다(#56 회귀의 부류).
    private func afterRest(displayAwake: Bool = true, completedToday: Int = 1, dailyGoal: Int = 4,
                           refusal: PokedoroSessionGate.Refusal? = nil) -> FocusChainRules.RestEnd {
        FocusChainRules.afterRest(displayAwake: displayAwake, minutes: 25,
                                  completedToday: completedToday, dailyGoal: dailyGoal,
                                  refusal: refusal)
    }

    // MARK: 긴 휴식 주기

    /// 4세션마다 긴 휴식. 세는 기준은 **오늘 마친 세션 수**다.
    func testLongRestArrivesEveryFourthSession() {
        XCTAssertEqual(FocusChainRules.restMinutes(completedToday: 1), FocusChainRules.shortRestMinutes)
        XCTAssertEqual(FocusChainRules.restMinutes(completedToday: 2), FocusChainRules.shortRestMinutes)
        XCTAssertEqual(FocusChainRules.restMinutes(completedToday: 3), FocusChainRules.shortRestMinutes)
        XCTAssertEqual(FocusChainRules.restMinutes(completedToday: 4), FocusChainRules.longRestMinutes)
        XCTAssertEqual(FocusChainRules.restMinutes(completedToday: 5), FocusChainRules.shortRestMinutes)
        XCTAssertEqual(FocusChainRules.restMinutes(completedToday: 8), FocusChainRules.longRestMinutes,
                       "주기는 하루에 한 번이 아니라 4세션마다 돈다")
    }

    /// 0은 짧은 휴식이다. `0 % 4 == 0` 이라 나머지만 보면 **아직 한 세션도 안 마친 상태에**
    /// 긴 휴식이 붙는다 — 기록 실패로 집계가 0인 경우에 실제로 도달한다.
    func testZeroCompletedSessionsDoesNotEarnLongRest() {
        XCTAssertEqual(FocusChainRules.restMinutes(completedToday: 0), FocusChainRules.shortRestMinutes)
    }

    /// 화면이 "긴 휴식 중" 이라고 말할 근거는 휴식 길이를 정한 것과 **같은 파생**이어야 한다.
    /// 따로 세면 15분짜리 휴식에 그냥 "휴식 중" 이 뜬다 — 사용자는 왜 길게 쉬는지 알 수 없다.
    func testLongRestLabelFollowsTheSameDerivationAsItsLength() {
        for count in 0...9 {
            XCTAssertEqual(FocusChainRules.isLongRest(completedToday: count),
                           FocusChainRules.restMinutes(completedToday: count) == FocusChainRules.longRestMinutes,
                           "\(count)세션째의 라벨과 길이가 어긋난다")
        }
        XCTAssertTrue(FocusChainRules.isLongRest(completedToday: FocusChainRules.sessionsPerLongRest))
        XCTAssertFalse(FocusChainRules.isLongRest(completedToday: 0))
    }

    // MARK: 휴식이 끝났을 때 무엇을 하는가

    /// 사람이 앞에 있고(디스플레이 켜짐) 목표가 남았으면 다음 집중이 저절로 시작된다 — 체인의 본체다.
    func testChainStartsNextSessionWhileDisplayIsAwake() {
        XCTAssertEqual(afterRest(), .start(minutes: 25))
    }

    /// **디스플레이 잠듦 단독.** 다른 조건은 위와 같다 — 이 한 값만으로 자동 시작이 알림으로 바뀐다.
    /// 이 분기가 PRD 위험표의 "자리를 비운 사이 가짜 세션" 을 막는 유일한 장치다.
    func testSleepingDisplayNotifiesInsteadOfStarting() {
        XCTAssertEqual(afterRest(displayAwake: false), .notify)
    }

    /// 오늘 목표를 채웠으면 **깨어 있어도** 멈춘다. 목표를 넘겨서까지 자동으로 미는 것이
    /// 디스플레이만 켜 두고 자리를 뜬 경우에 가짜 세션이 무한히 쌓이는 마지막 통로다.
    func testChainStopsAtTheDailyGoal() {
        XCTAssertEqual(afterRest(completedToday: 4, dailyGoal: 4), .goalReached)
        XCTAssertEqual(afterRest(completedToday: 9, dailyGoal: 4), .goalReached,
                       "목표를 이미 넘긴 상태에서도 자동으로 밀지 않는다")
    }

    /// 거절이 **맨 앞이다.** 깨어 있고 목표가 남았어도, 시작 자체가 막혀 있으면 아무것도 안 한다 —
    /// 시작할 수 없는 상태에서 "다음 세션 시작!" 알림을 띄우면 알림이 거짓말이 된다.
    func testBlockedStartHaltsTheChainBeforeAnyNotification() {
        XCTAssertEqual(afterRest(refusal: .noCompanion), .halted(.noCompanion))
        XCTAssertEqual(afterRest(displayAwake: false, refusal: .adventureUnclaimed),
                       .halted(.adventureUnclaimed))
    }

    // MARK: 타이머 훅 — 순서가 곧 계약이다

    /// 휴식 길이는 완료 훅이 **기록을 남긴 뒤** 읽혀야 한다. 오늘 몇 세션째인지는 원장만 아는데,
    /// 순서가 뒤집히면 4세션째에도 5분 휴식이 온다 — 화면엔 아무 오류도 안 뜨고 긴 휴식이 영영 안 온다.
    @MainActor
    func testRestLengthIsReadAfterTheCompletionHookRecords() {
        let timer = FocusTimer()
        var calls: [String] = []
        timer.onFocusCompleted = { _ in calls.append("record") }
        timer.nextRestMinutes = { calls.append("read"); return FocusChainRules.longRestMinutes }

        timer.startFocus(minutes: 25, now: start)
        let focusEnd = start.addingTimeInterval(25 * 60)
        timer.tick(now: focusEnd)

        XCTAssertEqual(calls, ["record", "read"], "휴식 길이를 기록 전에 읽으면 긴 휴식이 한 세션씩 밀린다")
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(timer.remaining(at: focusEnd), TimeInterval(FocusChainRules.longRestMinutes * 60),
                       "공급된 휴식 길이가 무시됐다")
    }

    /// 훅이 없으면 지금까지의 동작(5분 휴식) 그대로다 — 배선하지 않은 테스트·대화 경로가 조용히 바뀌면 안 된다.
    @MainActor
    func testRestFallsBackToShortWhenNoLengthHookIsWired() {
        let timer = FocusTimer()
        timer.startFocus(minutes: 25, now: start)
        let focusEnd = start.addingTimeInterval(25 * 60)
        timer.tick(now: focusEnd)

        XCTAssertEqual(timer.remaining(at: focusEnd),
                       TimeInterval(FocusChainRules.shortRestMinutes * 60))
    }

    /// 휴식 종료 훅은 `stop()` **뒤에** 오고, `tick` 의 마지막 문장이다.
    ///
    /// 앞에 오면 콜백이 본 단계가 `.rest` 라 `PokedoroSessionGate.startRefusal` 이
    /// `.timerAlreadyRunning` 으로 거절한다. 뒤에 문장이 더 붙으면 콜백이 켠 세션이 지워진다.
    /// 두 사고 모두 "체인이 그냥 안 이어진다" 로만 보인다.
    @MainActor
    func testRestCompletionHookRunsAfterStopAndItsNewSessionSurvives() {
        let timer = FocusTimer()
        let restEnd = start.addingTimeInterval(TimeInterval(FocusChainRules.shortRestMinutes * 60))
        var phaseInsideHook: FocusPhase?
        timer.onRestCompleted = {
            phaseInsideHook = timer.phase
            timer.startFocus(minutes: 25, now: restEnd)
        }

        timer.startRest(minutes: FocusChainRules.shortRestMinutes, now: start)
        timer.tick(now: restEnd)

        XCTAssertEqual(phaseInsideHook, .idle, "훅이 stop() 앞에서 불렸다 — 게이트가 시작을 거절한다")
        XCTAssertEqual(timer.phase, .focus, "훅이 켠 세션이 tick 의 뒤 문장에 지워졌다")
        XCTAssertTrue(timer.isRunning)
    }

    /// 집중이 끝날 때는 휴식 종료 훅이 불리지 않는다. 두 전이가 같은 훅을 밟으면 집중이
    /// 끝나자마자 다음 집중이 켜져 휴식이 통째로 사라진다.
    @MainActor
    func testFocusCompletionDoesNotFireTheRestHook() {
        let timer = FocusTimer()
        var restHookCalls = 0
        timer.onRestCompleted = { restHookCalls += 1 }

        timer.startFocus(minutes: 25, now: start)
        timer.tick(now: start.addingTimeInterval(25 * 60))

        XCTAssertEqual(restHookCalls, 0)
        XCTAssertEqual(timer.phase, .rest)
    }

    // MARK: 하루 경계 — 체인 위치는 원장에서 파생한다

    /// 어제 4세션을 마쳤어도 오늘 첫 세션의 휴식은 5분이다.
    ///
    /// 체인 카운터를 따로 들지 않고 원장의 오늘 집계를 쓰기 때문에 **저절로** 맞아야 한다.
    /// 여기가 깨지면 하루의 정의가 두 벌인 것이다(`CompanionStore.dayKey` 하나여야 한다).
    @MainActor
    func testLongRestCadenceResetsAtMidnight() {
        let clock = TestClock()
        let store = stubStore(clock, tag: "focus-chain")

        for _ in 0..<FocusChainRules.sessionsPerLongRest {
            store.completeFocusSession(minutes: 25)
            clock.advance(60)
        }
        XCTAssertEqual(store.focusSessionsToday, FocusChainRules.sessionsPerLongRest, "테스트 전제")
        XCTAssertEqual(FocusChainRules.restMinutes(completedToday: store.focusSessionsToday),
                       FocusChainRules.longRestMinutes)

        // 36시간 — 24시간만 넘기면 DST 로 25시간짜리 날인 지역에서 같은 날에 머무를 수 있다.
        clock.advance(36 * 3600)
        store.completeFocusSession(minutes: 25)

        XCTAssertEqual(store.focusSessionsToday, 1, "테스트 전제: 자정을 넘겨 오늘 집계가 비어야 한다")
        XCTAssertEqual(FocusChainRules.restMinutes(completedToday: store.focusSessionsToday),
                       FocusChainRules.shortRestMinutes,
                       "어제 4세션이 오늘 첫 세션에 긴 휴식을 줬다 — 하루 경계가 두 벌이다")
    }

    /// 재기동해도 체인 위치가 처음으로 돌아가지 않는다. `FocusTimer` 는 저장되지 않으므로
    /// 체인 카운터를 타이머에 뒀다면 앱을 열 때마다 긴 휴식 주기가 다시 시작됐을 것이다.
    @MainActor
    func testChainPositionSurvivesRelaunch() {
        let clock = TestClock()
        let directory = storeDirectory("focus-chain-relaunch")
        let stateURL = directory.appendingPathComponent(CompanionStorageLocations.stateFileName)
        let opened = CompanionStore(provider: StubProvider(value: stubMaxLevelLine), clock: clock.closure,
                                    fileURL: stateURL, rng: SeededRNG(seed: 7))
        for _ in 0..<3 { opened.completeFocusSession(minutes: 25); clock.advance(60) }

        let reopened = CompanionStore(provider: StubProvider(value: stubMaxLevelLine), clock: clock.closure,
                                      fileURL: stateURL, rng: SeededRNG(seed: 7))

        XCTAssertEqual(reopened.focusSessionsToday, 3, "재기동에 오늘 집계가 사라졌다")
        XCTAssertEqual(FocusChainRules.restMinutes(completedToday: reopened.focusSessionsToday + 1),
                       FocusChainRules.longRestMinutes,
                       "재기동 뒤 네 번째 세션이 긴 휴식을 못 받는다 — 주기가 처음부터 다시 셌다")
    }

    // MARK: 하루 목표 설정

    /// 목표는 사용자가 정한다. 기본은 긴 휴식 한 주기(4세션)다.
    @MainActor
    func testDailyFocusGoalDefaultsToOneLongRestCycle() {
        let suite = "focus-goal-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppSettings(defaults: defaults).dailyFocusGoal, FocusChainRules.defaultDailyGoal)
    }

    /// 저장된 값을 **읽을 때** 클램프한다. 0이 들어오면 체인이 첫 세션부터 `.goalReached` 로
    /// 죽고, 999가 들어오면 목표가 사실상 없는 것이 된다 — 손편집·구버전 키 둘 다 도달 경로다.
    @MainActor
    func testDailyFocusGoalIsClampedWhenRestored() {
        let suite = "focus-goal-clamp-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(0, forKey: "dailyFocusGoal")
        XCTAssertEqual(AppSettings(defaults: defaults).dailyFocusGoal, FocusChainRules.goalRange.lowerBound)

        defaults.set(999, forKey: "dailyFocusGoal")
        XCTAssertEqual(AppSettings(defaults: defaults).dailyFocusGoal, FocusChainRules.goalRange.upperBound)
    }

    /// 목표는 창을 닫았다 열어도 남는다.
    @MainActor
    func testDailyFocusGoalSurvivesReopeningSettings() {
        let suite = "focus-goal-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.dailyFocusGoal = 6

        XCTAssertEqual(AppSettings(defaults: defaults).dailyFocusGoal, 6)
    }
}
