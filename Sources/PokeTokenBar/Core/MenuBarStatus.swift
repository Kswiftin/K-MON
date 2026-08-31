import Foundation

/// 메뉴바 상태 문구 — focus > adventuring > resting 우선순위를 뷰 밖 순수 로직으로 고정한다(#20).
/// 뷰(AppDelegate) 안의 if 사슬로 두면 상태가 하나 늘 때(예: 완료된 모험) 분기 누락이 컴파일도
/// 테스트도 안 걸러 그대로 배포된다 — resolve() 하나로 강제하고 테스트로 표를 잠근다.
enum MenuBarStatus: Equatable {
    case battleChallengeSent(peer: String)
    case battleChallengeReceived(peer: String)
    case privateMessage
    case battling(peer: String, isMyTurn: Bool)
    case focus(prefix: String, clock: String)
    case adventuring(remaining: String)
    /// 모험이 끝났는데 아직 수령 전 — 다음 집중 세션을 막는 상태라 "휴식 중"과 구분해야 한다.
    case adventureClaimable
    case resting

    /// FocusTimer 인스턴스를 통째로 받지 않는다 — FocusTimer 는 @MainActor 라 그러면 이 함수까지
    /// 액터에 묶여 진짜 순수 함수가 아니게 된다. 호출부(MainActor 컨텍스트)가 값만 미리 뽑아 넘긴다.
    static func resolve(battlePhase: BattleCenter.Phase = .ready, battle: NetBattleState? = nil,
                        focusRunning: Bool, focusPhase: FocusPhase, focusClockText: String,
                        activeAdventure: AdventureRun?, now: Date = Date()) -> MenuBarStatus {
        switch battlePhase {
        case .challenging(let peer): return .battleChallengeSent(peer: peer)
        case .incoming: return .privateMessage
        case .poolBuilding(let peer), .teamBuilding(let peer), .waitingTeam(let peer):
            return .battleChallengeSent(peer: peer)
        case .battling:
            let peer = battle?.opp.snapshot.trainer ?? "?"
            return .battling(peer: peer, isMyTurn: battle?.myAction == nil)
        default: break
        }
        if focusRunning {
            let prefix = focusPhase == .focus ? "FOCUS" : "BREAK"
            return .focus(prefix: prefix, clock: focusClockText)
        }
        if let run = activeAdventure {
            return run.isComplete(at: now)
                ? .adventureClaimable
                : .adventuring(remaining: Self.remainingClockText(run.endsAt, at: now))
        }
        return .resting
    }

    /// 툴팁과 VoiceOver에서 사용할 전체 상태 설명.
    func fullDescription(_ l: L) -> String {
        switch self {
        case .battleChallengeSent(let peer): return l.menuBarBattleChallengeSent(peer)
        case .battleChallengeReceived(let peer): return l.menuBarBattleChallengeReceived(peer)
        case .privateMessage: return l.t("메시지가 왔습니다", "You have a message", "メッセージが届きました")
        case .battling(let peer, let isMyTurn): return l.menuBarBattling(peer, isMyTurn: isMyTurn)
        case .focus(let prefix, let clock): return "\(prefix) \(clock)"
        case .adventuring(let remaining): return "\(l.menuBarAdventuring) \(remaining)"
        case .adventureClaimable: return l.menuBarAdventureClaimable
        case .resting: return l.menuBarResting
        }
    }

    /// 한정된 메뉴 막대 공간에 표시할 언어 비의존적 컴팩트 제목.
    var compactTitle: String {
        switch self {
        case .battleChallengeSent, .battleChallengeReceived, .battling:
            return "B"
        case .privateMessage:
            return "!"
        case .focus(let prefix, let clock):
            return "\(prefix == "BREAK" ? "B" : "F") \(clock)"
        case .adventuring(let remaining):
            return "A \(remaining)"
        case .adventureClaimable:
            return "!"
        case .resting:
            return "R"
        }
    }

    /// 모험 종료까지 남은 시간 — 해안 모험은 최대 2시간이라 FocusTimer.clockText() 의 mm:ss 만 쓰면
    /// 분이 두 자리를 넘어 119:59 처럼 나온다. 1시간 이상이면 1h23m, 미만이면 12:34.
    static func remainingClockText(_ endsAt: Date, at now: Date) -> String {
        remainingClockText(seconds: Int(endsAt.timeIntervalSince(now).rounded(.up)))
    }

    /// 초를 그대로 받는 쪽 — 남은 시간을 **시각이 아니라 초로** 들고 있는 자리(호스트가 계산해
    /// 보내온 쿨다운 등)가 같은 형식을 쓰게 한다. 바닥(0)이 두 곳에서 구현되지 않도록 형식은 여기 하나다.
    static func remainingClockText(seconds rawSeconds: Int) -> String {
        let seconds = max(0, rawSeconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h\(String(format: "%02d", minutes))m"
                         : String(format: "%02d:%02d", minutes, seconds % 60)
    }
}
