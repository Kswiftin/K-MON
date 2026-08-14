import Foundation

/// 메뉴바 상태 문구 — focus > adventuring > resting 우선순위를 뷰 밖 순수 로직으로 고정한다(#20).
/// 뷰(AppDelegate) 안의 if 사슬로 두면 상태가 하나 늘 때(예: 완료된 모험) 분기 누락이 컴파일도
/// 테스트도 안 걸러 그대로 배포된다 — resolve() 하나로 강제하고 테스트로 표를 잠근다.
enum MenuBarStatus: Equatable {
    case focus(prefix: String, clock: String)
    case adventuring(remaining: String)
    /// 모험이 끝났는데 아직 수령 전 — 다음 집중 세션을 막는 상태라 "휴식 중"과 구분해야 한다.
    case adventureClaimable
    case resting

    static func resolve(focusTimer: FocusTimer, activeAdventure: AdventureRun?, now: Date = Date()) -> MenuBarStatus {
        if focusTimer.isRunning {
            let prefix = focusTimer.phase == .focus ? "FOCUS" : "BREAK"
            return .focus(prefix: prefix, clock: focusTimer.clockText(at: now))
        }
        if let run = activeAdventure {
            return run.isComplete(at: now)
                ? .adventureClaimable
                : .adventuring(remaining: Self.remainingClockText(run.endsAt, at: now))
        }
        return .resting
    }

    func text(_ l: L) -> String {
        switch self {
        case .focus(let prefix, let clock): return "\(prefix) \(clock)"
        case .adventuring(let remaining): return "\(l.menuBarAdventuring) \(remaining)"
        case .adventureClaimable: return l.menuBarAdventureClaimable
        case .resting: return l.menuBarResting
        }
    }

    /// 모험 종료까지 남은 시간 — 해안 모험은 최대 2시간이라 FocusTimer.clockText() 의 mm:ss 만 쓰면
    /// 분이 두 자리를 넘어 119:59 처럼 나온다. 1시간 이상이면 1h23m, 미만이면 12:34.
    static func remainingClockText(_ endsAt: Date, at now: Date) -> String {
        let seconds = max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h\(String(format: "%02d", minutes))m"
                         : String(format: "%02d:%02d", minutes, seconds % 60)
    }
}
