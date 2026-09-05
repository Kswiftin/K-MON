import Foundation

/// 세션 체인 규칙 — 한 세션이 끝난 뒤 무엇이 이어지는가.
///
/// **체인 상태를 따로 들지 않는다.** 체인 위치는 원장(`FocusSessionLog`)이 낸 **오늘 마친 세션 수**
/// 하나에서 파생한다. 카운터를 `FocusTimer` 에 두면 타이머가 저장되지 않으므로 앱을 열 때마다 긴
/// 휴식 주기가 처음부터 다시 시작되고, 세이브에 두면 자정 리셋을 따로 써야 한다 — 원장은 이미
/// 재기동을 넘고 `CompanionStore.dayKey` 로 자정을 안다. 파생이 곧 그 두 문제의 답이다.
///
/// **판정은 순수하다.** `FocusTimer` 도 `CompanionStore` 도 `@MainActor` 에 네트워크 로딩까지
/// 물려 있어, 조건표를 거기 두면 표만 따로 검증할 방법이 없어진다(`PokedoroSessionGate` 와 같은 이유).
enum FocusChainRules {
    /// 집중 길이는 세션마다 고르는데(`PokemonChatTool.focusMinutes`) 휴식 길이가 상수인 이유:
    /// 여는 순간 "4세션 후 긴 휴식" 이라는 규칙이 설정값에 의존하게 된다.
    // ponytail: 5/15 고정 — 다른 길이가 실제로 필요해지면 그때 연다.
    static let shortRestMinutes = 5
    static let longRestMinutes = 15
    static let sessionsPerLongRest = 4

    /// 기본 하루 목표 = 긴 휴식 한 주기. 두 값을 따로 쓰면 "네 세션 뒤 긴 휴식인데 목표는 셋" 같은
    /// 어긋난 기본값이 생긴다.
    static let defaultDailyGoal = sessionsPerLongRest
    static let goalRange = 1...12

    /// 방금 오늘 `completedToday` 번째 세션을 마쳤을 때 이어질 휴식 길이.
    ///
    /// `> 0` 을 함께 보는 이유: `0 % 4 == 0` 이라 나머지만 보면 **한 세션도 안 마친 상태**에 긴
    /// 휴식이 붙는다. 기록이 실패해 집계가 0으로 남는 경로가 실제로 있다(옆 파일 쓰기 실패).
    static func restMinutes(completedToday: Int) -> Int {
        completedToday > 0 && completedToday % sessionsPerLongRest == 0
            ? longRestMinutes : shortRestMinutes
    }

    /// 지금 도는 휴식이 긴 휴식인가 — 화면·터미널이 "긴 휴식 중" 이라고 말할 근거.
    ///
    /// 길이를 정한 것과 **같은 파생**을 쓴다. 화면이 따로 세면 15분짜리 휴식에 그냥 "휴식 중" 이
    /// 떠서, 사용자는 왜 길게 쉬는지 알 수 없다 — 긴 휴식이 오는 것 자체가 체인이 주는 보상이다.
    static func isLongRest(completedToday: Int) -> Bool {
        restMinutes(completedToday: completedToday) == longRestMinutes
    }

    /// 휴식이 끝났을 때 무엇을 하는가.
    enum RestEnd: Equatable, Sendable {
        /// 다음 집중을 자동으로 시작한다.
        case start(minutes: Int)
        /// 사람이 자리에 없다. 알림만 남기고 돌아와서 고르게 한다.
        case notify
        /// 오늘 목표를 채웠다. 더 할지는 사람이 정한다.
        case goalReached
        /// 지금은 시작 자체가 막혀 있다. 알림도 띄우지 않는다 — 사유가 남을 뿐이다.
        case halted(PokedoroSessionGate.Refusal)
    }

    /// 휴식 종료 판정. **거절 → 목표 → 사람 유무** 순이다.
    ///
    /// 거절이 맨 앞인 이유: 시작할 수 없는 상태에서 "다음 세션 시작!" 알림을 띄우면 알림이
    /// 거짓말이 된다(동행을 부화기에 넣어 비어 있는 경우가 실제 경로다).
    ///
    /// 목표가 사람 유무보다 앞인 이유: 목표를 넘겨서까지 자동으로 미는 것이, 디스플레이만 켜 두고
    /// 자리를 뜬 경우에 가짜 세션이 무한히 쌓이는 마지막 통로다. 목표에서 멈추면 그 손해가
    /// 하루 목표치로 묶인다.
    ///
    /// - Parameter minutes: 이어 갈 집중 길이. 방금 끝난 세션과 같은 길이다 — 체인은 사용자가
    ///   고른 길이를 유지한다.
    static func afterRest(displayAwake: Bool, minutes: Int, completedToday: Int,
                          dailyGoal: Int, refusal: PokedoroSessionGate.Refusal?) -> RestEnd {
        if let refusal { return .halted(refusal) }
        if completedToday >= dailyGoal { return .goalReached }
        return displayAwake ? .start(minutes: minutes) : .notify
    }
}
