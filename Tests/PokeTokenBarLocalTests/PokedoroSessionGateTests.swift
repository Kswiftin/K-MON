import Testing
@testable import PokeTokenBar

/// 집중 세션 세 동작(시작·정산·종료)의 거절 판정표. **세 프런트엔드가 같은 표를 읽는다** —
/// 팝오버 버튼, 대화 도구(`PokemonChatToolbox`), 터미널 요청. 표를 뽑아 두지 않으면 조건이
/// 프런트엔드마다 한 벌씩 생기고, 갈라진 걸 알아챌 방법은 손으로 맞대 보는 것뿐이다
/// (`defect-log.md` "가드가 중복이라 하나를 지워도 아무 테스트가 안 깨지는 부류").
@Suite("PokedoroSessionGateTests")
struct PokedoroSessionGateTests {

    /// 아무것도 안 걸린 상태 — 각 테스트가 자기가 보는 축만 바꿔 쓴다.
    private func state(phase: FocusPhase = .idle,
                       hasCompanion: Bool = true,
                       hasAdventure: Bool = false,
                       inProgress: Bool = false) -> PokedoroSessionState {
        PokedoroSessionState(phase: phase, hasCompanion: hasCompanion,
                             hasAdventure: hasAdventure, adventureIsInProgress: inProgress)
    }

    // MARK: 시작

    @Test func testStartIsAllowedWhenNothingIsRunning() {
        #expect(PokedoroSessionGate.startRefusal(state()) == nil)
    }

    /// **휴식 단독을 반드시 본다.** `FocusTimer.isRunning` 은 `phase != .idle` 이라 휴식에서도
    /// 참인데, 그 구간엔 모험이 이미 정산돼 없다 — 모험만 보는 게이트는 휴식을 조용히 덮어써
    /// 화면이 못 하는 일을 대화만 할 수 있었다(`PokemonChatTools` 의 그 주석이 이 테스트다).
    @Test func testStartIsRefusedWhileTheTimerRunsAndSaysWhichPhase() {
        #expect(PokedoroSessionGate.startRefusal(state(phase: .focus)) == .timerAlreadyRunning(.focus))
        #expect(PokedoroSessionGate.startRefusal(state(phase: .rest)) == .timerAlreadyRunning(.rest))
    }

    /// 모험이 걸려 있으면 거절인데, **사유가 갈라져야** 한다. 뭉개면 사용자도 모델도 다음 수를
    /// 고를 수 없다 — 진행 중이면 기다리는 것이고 정산 대기면 `claim` 이 다음 수다.
    @Test func testStartSeparatesAnOngoingAdventureFromAnUnclaimedReward() {
        #expect(PokedoroSessionGate.startRefusal(state(hasAdventure: true, inProgress: true))
                == .adventureInProgress)
        #expect(PokedoroSessionGate.startRefusal(state(hasAdventure: true, inProgress: false))
                == .adventureUnclaimed)
    }

    /// 동행이 없으면(알 부화 중) 모험을 보낼 대상이 없다. `startFocusAdventure` 의 guard 가
    /// 조용히 false 를 돌려주므로, 사유를 여기서 만들지 않으면 화면이 "실패" 만 말한다.
    @Test func testStartIsRefusedWithoutACompanion() {
        #expect(PokedoroSessionGate.startRefusal(state(hasCompanion: false)) == .noCompanion)
    }

    /// 타이머가 돌면서 모험도 걸린 상태에서는 **타이머 사유가 먼저다** — 사용자가 먼저 할 일은
    /// 도는 세션을 끝내는 것이지 모험을 정산하는 것이 아니다.
    @Test func testTimerRefusalWinsOverTheAdventureRefusal() {
        #expect(PokedoroSessionGate.startRefusal(state(phase: .focus, hasAdventure: true, inProgress: true))
                == .timerAlreadyRunning(.focus))
    }

    // MARK: 정산

    @Test func testClaimIsAllowedOnlyWhenTheAdventureIsFinished() {
        #expect(PokedoroSessionGate.claimRefusal(state(hasAdventure: true, inProgress: false)) == nil)
    }

    @Test func testClaimIsRefusedWithoutAnAdventure() {
        #expect(PokedoroSessionGate.claimRefusal(state()) == .nothingToClaim)
    }

    /// 아직 나가 있는 모험을 정산하면 시간을 안 채우고 보상을 받는 셈이다.
    @Test func testClaimIsRefusedWhileTheAdventureIsStillRunning() {
        #expect(PokedoroSessionGate.claimRefusal(state(hasAdventure: true, inProgress: true))
                == .adventureInProgress)
    }

    // MARK: 종료

    /// **`A || B` 게이트라 B 단독을 따로 본다.** 앱을 다시 연 직후가 바로 B 단독이다 —
    /// `FocusTimer` 는 저장되지 않아 타이머는 `.idle` 인데 모험은 디스크에 남아 있다. 그 구간에
    /// 끝낼 것이 없다고 답하면 사용자는 정산 대기 모험을 영영 못 치운다.
    @Test func testStopIsAllowedWhenEitherTheTimerOrTheAdventureIsAlive() {
        #expect(PokedoroSessionGate.stopRefusal(state(phase: .focus)) == nil, "타이머 단독")
        #expect(PokedoroSessionGate.stopRefusal(state(hasAdventure: true, inProgress: true)) == nil,
                "모험 단독 — 앱을 다시 연 직후의 상태")
        #expect(PokedoroSessionGate.stopRefusal(state(hasAdventure: true, inProgress: false)) == nil,
                "정산 대기 단독")
    }

    /// 아무것도 안 돌아가는데 "집중을 끝냈다" 가 뜨면 그건 거짓이다. 앱을 다시 연 직후
    /// (타이머 idle · 모험 없음)가 항상 이 상태다.
    @Test func testStopIsRefusedWhenNothingIsRunning() {
        #expect(PokedoroSessionGate.stopRefusal(state()) == .nothingRunning)
    }
}
