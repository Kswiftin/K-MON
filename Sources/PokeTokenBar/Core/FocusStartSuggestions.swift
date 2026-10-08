import Foundation

struct FocusStartSuggestion: Equatable, Sendable {
    let label: String
    let minutes: Int
}

enum FocusGoalHint: Equatable, Sendable {
    case firstSession
    case remaining(Int)
    case oneRemaining
    case reached

    var text: String {
        switch self {
        case .firstSession: "첫 집중을 시작해 볼까요?"
        case .remaining(let count): "오늘 목표까지 \(count)세션 남았어요"
        case .oneRemaining: "한 세션 더 하면 오늘 목표 달성!"
        case .reached: "오늘 목표를 달성했어요"
        }
    }
}

/// 기존 완료 원장에서 시작 선택지만 파생한다. 기록과 보상은 변경하지 않는다.
enum FocusStartSuggestions {
    static func recentTasks(in log: FocusSessionLog) -> [FocusStartSuggestion] {
        let newestFirst = log.sessions.enumerated().sorted { lhs, rhs in
            if lhs.element.endedAt == rhs.element.endedAt { return lhs.offset > rhs.offset }
            return lhs.element.endedAt > rhs.element.endedAt
        }
        var seen = Set<String>()
        var suggestions: [FocusStartSuggestion] = []
        for (_, session) in newestFirst {
            guard let label = FocusSession.sanitize(label: session.label),
                  seen.insert(label).inserted else { continue }
            suggestions.append(FocusStartSuggestion(
                label: label, minutes: FocusChainRules.nearestFocusLength(to: session.minutes)))
            if suggestions.count == 3 { break }
        }
        return suggestions
    }

    static func goalHint(completed: Int, goal: Int) -> FocusGoalHint {
        if completed >= goal { return .reached }
        if completed <= 0 { return .firstSession }
        let remaining = goal - completed
        return remaining == 1 ? .oneRemaining : .remaining(remaining)
    }

    static func continuationTitle(for session: FocusSession) -> String {
        let duration = "\(session.minutes)분 이어하기"
        return session.label.map { "\($0) · \(duration)" } ?? duration
    }

    static func restEndMessage(for session: FocusSession?) -> String {
        guard let session else { return "눌러서 다음 집중을 시작하세요." }
        return "\(continuationTitle(for: session)). 눌러서 다음 집중을 준비하세요."
    }

}
