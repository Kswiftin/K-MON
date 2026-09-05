import Foundation

/// 집중 세션 판정에 필요한 값 한 벌. `FocusTimer` 와 `CompanionStore` 를 직접 읽지 않고 이
/// 구조체를 거치는 이유는 판정을 순수 함수로 유지하기 위해서다 — 둘 다 `@MainActor` 에 네트워크
/// 로딩까지 물려 있어, 그대로 두면 조건표만 따로 검증할 방법이 없어진다(`TUIHomeModel` 과 같은 이유).
struct PokedoroSessionState: Equatable, Sendable {
    /// 타이머 단계. `.idle` 이 곧 "안 돈다" 다.
    ///
    /// `FocusTimer.isRunning` 은 `phase != .idle && endsAt != nil` 이지만 두 값은 항상 함께
    /// 움직인다(`startFocus`·`stop` 이 유일한 전이). 여기서 두 필드로 나눠 두면 서로 어긋난
    /// 상태를 테스트가 만들 수 있고, 그 상태는 프로덕션에 없다 — 경계에서 한 값으로 접는다.
    var phase: FocusPhase
    /// 모험을 보낼 대상이 있는가. 알을 부화기에 넣으면 활성 개체가 빈다.
    var hasCompanion: Bool
    var hasAdventure: Bool
    /// 아직 나가 있는가. `hasAdventure` 가 참인데 이게 거짓이면 **정산 대기**다.
    var adventureIsInProgress: Bool
}

extension PokedoroSessionState {
    /// 살아 있는 타이머·스토어에서 판정 입력을 조립한다. **조립도 한 곳이다.**
    ///
    /// 위 표를 한 벌로 두는 이유가 조립에도 그대로 걸린다 — 프런트엔드마다 이 네 줄을 복사하면
    /// `isRunning` 을 접는 방식이 갈리는 순간 "대화로는 거절되는데 다른 데서는 통과하는" 상태가
    /// 생기고, 갈라진 걸 알아챌 방법은 손으로 맞대 보는 것뿐이다. 실제로 대화 도구와 터미널
    /// 실행기가 주석까지 같은 사본을 들고 있었고, 세션 체인이 세 번째가 될 참이었다.
    @MainActor
    init(timer: FocusTimer, companion: CompanionStore) {
        self.init(phase: timer.isRunning ? timer.phase : .idle,
                  hasCompanion: companion.hasActive,
                  hasAdventure: companion.activeAdventure != nil,
                  adventureIsInProgress: companion.isAdventureInProgress)
    }
}

/// 집중 세션 세 동작(시작·정산·종료)의 **유일한 거절 판정표**.
///
/// 팝오버 버튼·대화 도구·터미널 요청이 모두 이 표를 읽는다. 프런트엔드마다 조건을 다시 쓰면
/// 표가 여러 벌이 되고, 한쪽만 고쳐도 아무 테스트가 안 깨진다 — 갈라진 걸 알아챌 방법은 손으로
/// 맞대 보는 것뿐이다.
///
/// **문구는 여기 없다.** 대화는 모델용 영문 한 줄이 필요하고 터미널은 사람이 읽는 한국어가
/// 필요하다 — 사유만 돌려주고 표현은 각 프런트엔드가 맡는다.
enum PokedoroSessionGate {
    /// 거절 사유. 뭉개지 않고 갈라 둔다 — 사용자도 모델도 **다음 수**를 이 값으로 고른다
    /// (진행 중이면 기다리는 것이고, 정산 대기면 `claim` 이 다음 수다).
    enum Refusal: Equatable, Sendable {
        /// 이미 도는 세션이 있다. 어느 단계인지 실어 준다 — 휴식 중이면 할 말이 다르다.
        case timerAlreadyRunning(FocusPhase)
        case adventureInProgress
        case adventureUnclaimed
        case noCompanion
        case nothingRunning
        case nothingToClaim
    }

    /// 집중을 시작할 수 있는가. `nil` 이면 시작해도 된다.
    ///
    /// **타이머를 모험보다 먼저 본다.** `isRunning` 은 휴식에서도 참인데 그 구간엔 모험이 이미
    /// 정산돼 없다 — 모험만 보면 휴식 중 시작이 조용히 통과한다. 그리고 둘 다 걸렸을 때
    /// 사용자가 먼저 할 일은 도는 세션을 끝내는 것이지 모험을 정산하는 것이 아니다.
    static func startRefusal(_ state: PokedoroSessionState) -> Refusal? {
        if state.phase != .idle { return .timerAlreadyRunning(state.phase) }
        if state.hasAdventure { return state.adventureIsInProgress ? .adventureInProgress : .adventureUnclaimed }
        if !state.hasCompanion { return .noCompanion }
        return nil
    }

    /// 정산할 수 있는가. 끝난 모험만 정산된다 — 완료 판정의 권위는 여전히
    /// `CompanionStore.claimAdventure` 한 곳이고, 이 함수는 **부르기 전에 사유를 말하기 위해** 있다.
    static func claimRefusal(_ state: PokedoroSessionState) -> Refusal? {
        guard state.hasAdventure else { return .nothingToClaim }
        return state.adventureIsInProgress ? .adventureInProgress : nil
    }

    /// 끝낼 것이 있는가. **타이머와 모험 중 하나만 살아 있어도 참이다** — 앱을 다시 연 직후가
    /// 모험 단독이다(`FocusTimer` 는 저장되지 않아 타이머는 `.idle` 인데 모험은 디스크에 남는다).
    /// 타이머만 보면 그 구간의 정산 대기 모험을 영영 못 치운다.
    static func stopRefusal(_ state: PokedoroSessionState) -> Refusal? {
        state.phase != .idle || state.hasAdventure ? nil : .nothingRunning
    }
}
