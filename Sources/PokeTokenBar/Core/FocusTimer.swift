import Foundation

enum FocusPhase: String, Sendable { case idle, focus, rest }

@MainActor
@Observable
final class FocusTimer {
    private(set) var phase: FocusPhase = .idle
    private(set) var endsAt: Date?
    private(set) var completedSessions = 0
    private(set) var focusMinutes = 25
    private(set) var lastReward: FocusSessionReward?
    var onFocusCompleted: ((Int) -> FocusSessionReward)?

    var isRunning: Bool { phase != .idle && endsAt != nil }

    func startFocus(minutes: Int = 25, now: Date = Date()) {
        phase = .focus
        focusMinutes = max(1, minutes)
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
            startRest(now: now)
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
