import Foundation
import Testing
@testable import PokeTokenBar

@Suite("FocusStartSuggestionsTests")
struct FocusStartSuggestionsTests {
    private let base = Date(timeIntervalSince1970: 1_757_000_000)

    @Test func recentTasksKeepLatestThreeDistinctLabels() {
        var log = FocusSessionLog()
        for (index, entry) in [("옛 작업", 25), ("문서", 25), ("리뷰", 50),
                               ("개발", 90), ("문서", 50)].enumerated() {
            log.record(minutes: entry.1, label: entry.0, at: base.addingTimeInterval(Double(index)))
        }
        #expect(FocusStartSuggestions.recentTasks(in: log) == [
            FocusStartSuggestion(label: "문서", minutes: 50),
            FocusStartSuggestion(label: "개발", minutes: 90),
            FocusStartSuggestion(label: "리뷰", minutes: 50)
        ])
        #expect(FocusStartSuggestions.recentTasks(in: FocusSessionLog()).isEmpty)
    }

    @Test func recentTasksNormalizeWhitespaceAndKeepCaseDistinct() {
        var log = FocusSessionLog()
        for label in [" 문서  작성 ", "Review", "review", "문서 작성", nil, "  "] as [String?] {
            log.record(minutes: 25, label: label, at: base)
        }
        #expect(FocusStartSuggestions.recentTasks(in: log).map(\.label) == ["문서 작성", "review", "Review"])
    }

    @Test func recentTasksUseSupportedDurationsWithoutChangingHistory() {
        var log = FocusSessionLog()
        for (index, minutes) in [26, 51, 89].enumerated() {
            log.record(minutes: minutes, label: "작업 \(index)", at: base.addingTimeInterval(Double(index)))
        }
        let original = log
        #expect(FocusStartSuggestions.recentTasks(in: log).map(\.minutes) == [90, 50, 25])
        #expect(log == original)
    }

    @Test func goalHintsUseCompletedSessionsOnly() {
        #expect(FocusStartSuggestions.goalHint(completed: 0, goal: 4) == .firstSession)
        #expect(FocusStartSuggestions.goalHint(completed: 1, goal: 4) == .remaining(3))
        #expect(FocusStartSuggestions.goalHint(completed: 3, goal: 4) == .oneRemaining)
        #expect(FocusStartSuggestions.goalHint(completed: 4, goal: 4) == .reached)
        #expect(FocusStartSuggestions.goalHint(completed: 5, goal: 4) == .reached)
        #expect(FocusStartSuggestions.goalHint(completed: 1, goal: 1) == .reached)
    }
}
