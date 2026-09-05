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

    /// 체인 알림의 식별자 앞머리. **띄우는 쪽과 눌렀을 때 보내는 쪽이 같은 상수를 본다** —
    /// 문자열을 두 번 적으면 한쪽만 고쳐졌을 때 알림이 엉뚱한 화면을 연다
    /// (`PopoverNavigation.destination(forNotificationID:)`).
    static let notificationIDPrefix = "focus-chain"

    /// 휴식이 끝났을 때 무엇을 하는가.
    ///
    /// **여기에 "자동으로 시작한다" 는 없다.** 시작을 앱이 정하면 자리를 비운 사이에도 세션이
    /// 쌓여 기록이 실제 집중과 무관해지는데, 그 기록이 곧 PRD 주 지표의 기준선이다. 체인이 하는
    /// 일은 "다음 세션을 시작할 이유와 신호" 를 주는 것까지고, 시작 여부는 사람이 쥔다.
    enum RestEnd: Equatable, Sendable {
        /// 다음 집중을 시작하라고 부른다. 누르면 집중 타이머 화면이 열린다.
        case promptNextSession
        /// 오늘 목표를 채웠다. 더 할지는 사람이 정한다 — 같은 문구로 계속 부르지 않는다.
        case goalReached
        /// 지금은 시작 자체가 막혀 있다. 알림도 띄우지 않는다 — 사유가 남을 뿐이다.
        case halted(PokedoroSessionGate.Refusal)
    }

    /// 휴식 종료 판정. **거절 → 목표** 순이다.
    ///
    /// 거절이 맨 앞인 이유: 시작할 수 없는 상태에서 "다음 세션 시작하세요" 라고 부르면 알림이
    /// 거짓말이 된다. 사용자는 알림을 누르고 팝오버를 열었다가 눌리지 않는 버튼만 보게 된다
    /// (동행을 부화기에 넣어 비어 있는 경우가 실제 경로다). 목표 달성 축하보다도 앞이다 —
    /// 못 하는 일을 축하할 수는 없다.
    static func afterRest(completedToday: Int, dailyGoal: Int,
                          refusal: PokedoroSessionGate.Refusal?) -> RestEnd {
        if let refusal { return .halted(refusal) }
        return completedToday >= dailyGoal ? .goalReached : .promptNextSession
    }
}
