import Foundation

enum FocusPhase: String, Sendable { case idle, focus, rest }

@MainActor
@Observable
final class FocusTimer {
    private(set) var phase: FocusPhase = .idle
    private(set) var endsAt: Date?
    private(set) var completedSessions = 0
    private(set) var focusMinutes = FocusPreset.classic.minutes
    /// 이번 세션이 끝나면 이어질 휴식 길이. 집중을 시작할 때 프리셋에서 정해 둔다 — `tick()` 이
    /// 기본값 5분으로 휴식을 열던 동안 90분 세션 뒤에도 5분만 쉬었다.
    private(set) var restMinutes = FocusPreset.classic.restMinutes
    private(set) var lastReward: FocusSessionReward?
    var onFocusCompleted: ((Int) -> FocusSessionReward)?

    var isRunning: Bool { phase != .idle && endsAt != nil }

    /// 휴식 길이는 인자로 받지 않는다 — 분에서 프리셋을 접어 함께 정한다. 두 값을 따로 받으면
    /// 버튼 경로와 대화 경로가 각자 다른 조합을 넘길 수 있다.
    func startFocus(minutes: Int = FocusPreset.classic.minutes, now: Date = Date()) {
        phase = .focus
        focusMinutes = max(1, minutes)
        restMinutes = FocusPreset.nearest(toMinutes: focusMinutes).restMinutes
        endsAt = now.addingTimeInterval(TimeInterval(focusMinutes * 60))
    }

    func startRest(minutes: Int = 5, now: Date = Date()) {
        phase = .rest
        endsAt = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
    }

    func stop() { phase = .idle; endsAt = nil }

    func tick(now: Date = Date()) {
        guard let endsAt, now >= endsAt else { return }
        if phase == .focus {
            completedSessions += 1
            lastReward = onFocusCompleted?(focusMinutes)
            startRest(minutes: restMinutes, now: now)
        } else {
            stop()
        }
    }

    func remaining(at now: Date = Date()) -> TimeInterval {
        max(0, endsAt?.timeIntervalSince(now) ?? 0)
    }

    func clockText(at now: Date = Date()) -> String {
        let seconds = Int(remaining(at: now).rounded(.up))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
