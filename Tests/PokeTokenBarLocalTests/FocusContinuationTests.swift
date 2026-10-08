import Foundation
import Testing
@testable import PokeTokenBar

@Suite("FocusContinuationTests")
@MainActor
struct FocusContinuationTests {
    private let base = Date(timeIntervalSince1970: 1_757_000_000)

    // 실제 원장 시각을 건네므로 tick과 저장 시계가 달라도 같은 기록을 재개한다.
    private func completedTimer(label: String? = "문서 작성") -> (FocusTimer, FocusSessionLog, Date) {
        let timer = FocusTimer()
        var log = FocusSessionLog()
        let recordedAt = base.addingTimeInterval(25 * 60 + 0.25)
        timer.onFocusCompleted = { minutes, name in
            log.record(minutes: minutes, label: name, at: recordedAt)
            timer.rememberCompletedSession(log.sessions.last!)
        }
        timer.startFocus(minutes: 25, label: label, now: base)
        timer.tick(now: base.addingTimeInterval(25 * 60))
        return (timer, log, base.addingTimeInterval(30 * 60))
    }

    @Test func continuationIsReadyOnlyAfterNormalRestCompletion() {
        let (timer, log, restEnd) = completedTimer()
        #expect(timer.phase == .rest)
        #expect(timer.focusLabel == nil)
        #expect(timer.continuation(in: log, now: restEnd) == nil)
        #expect(timer.continuationSession?.endedAt == base.addingTimeInterval(1500.25))
        var hookSawReady = false
        timer.onRestCompleted = {
            hookSawReady = timer.phase == .idle && timer.continuation(in: log, now: restEnd) != nil
        }
        timer.tick(now: restEnd)
        #expect(hookSawReady)
        #expect(timer.continuation(in: log, now: restEnd)?.label == "문서 작성")
        #expect(timer.completedSessions == 1)
        #expect(log.sessions.count == 1)
    }

    @Test func stopAndNewStartClearContinuation() {
        for stopDuringRest in [true, false] {
            let (timer, log, restEnd) = completedTimer()
            if !stopDuringRest { timer.tick(now: restEnd) }
            timer.stop()
            #expect(timer.continuation(in: log, now: restEnd) == nil)
            #expect(timer.continuationSession == nil)
            #expect(!timer.isContinuationReady)
        }
        let (timer, log, restEnd) = completedTimer()
        timer.tick(now: restEnd)
        timer.startFocus(minutes: 50, now: restEnd)
        #expect(timer.continuationSession == nil)
        #expect(timer.continuation(in: log, now: restEnd) == nil)
    }

    @Test func continuationRequiresSameDayAndCurrentLog() {
        let (timer, log, restEnd) = completedTimer()
        timer.tick(now: restEnd)
        #expect(timer.continuation(in: log, now: restEnd) != nil)
        #expect(timer.continuation(in: log, now: restEnd.addingTimeInterval(86_400)) == nil)
        #expect(timer.continuation(in: FocusSessionLog(), now: restEnd) == nil)
        var otherLog = FocusSessionLog()
        otherLog.record(minutes: 25, label: "다른 작업", at: restEnd)
        #expect(timer.continuation(in: otherLog, now: restEnd) == nil)
        #expect(FocusTimer().continuation(in: log, now: restEnd) == nil)
    }

    @Test func continuationSupportsUnlabelledWorkAndLongNames() {
        let (timer, log, restEnd) = completedTimer(label: nil)
        timer.tick(now: restEnd)
        let session = timer.continuation(in: log, now: restEnd)!
        #expect(session.label == nil)
        #expect(FocusStartSuggestions.continuationTitle(for: session) == "25분 이어하기")
        let named = FocusSession(endedAt: base, minutes: 50, label: "문서 작성")
        #expect(FocusStartSuggestions.continuationTitle(for: named) == "문서 작성 · 50분 이어하기")
        #expect(FocusStartSuggestions.restEndMessage(for: named).contains("문서 작성"))
        #expect(FocusStartSuggestions.restEndMessage(for: named).contains("50분"))
        #expect(FocusStartSuggestions.restEndMessage(for: session).contains("25분"))
        #expect(FocusStartSuggestions.restEndMessage(for: nil) == "눌러서 다음 집중을 시작하세요.")
        let (longTimer, longLog, longRestEnd) = completedTimer(label: String(repeating: "가", count: 60))
        longTimer.tick(now: longRestEnd)
        #expect(longTimer.continuation(in: longLog, now: longRestEnd)?.label?.count == 40)
    }

    @Test func rememberingOutsideCompletionCannotCreateAReadyCandidate() {
        let timer = FocusTimer()
        let session = FocusSession(endedAt: base, minutes: 25, label: "작업")
        timer.rememberCompletedSession(session)
        timer.startRest(now: base)
        timer.tick(now: base.addingTimeInterval(300))
        #expect(timer.continuationSession == nil)
        #expect(!timer.isContinuationReady)
    }

    private func store(in directory: URL, clock: @escaping () -> Date) -> CompanionStore {
        let store = CompanionStore(clock: clock, fileURL: directory.appendingPathComponent("state.json"))
        let mon = MonState(baseID: 25, pathIDs: [25], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1)
        store.debugSetBoxedMons([mon])
        store.switchCompanion(to: mon.id)
        return store
    }

    @Test func sharedStartRejectsRunningTimerWithoutSideEffects() {
        let directory = storeFixtureDirectory("focus-start-gate")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store(in: directory, clock: { base })
        for phase in [FocusPhase.focus, .rest] {
            let timer = FocusTimer()
            if phase == .focus { timer.startFocus(minutes: 50, label: "진행 중", now: base) }
            else { timer.startRest(now: base) }
            let end = timer.endsAt
            #expect(!timer.startFocusSession(minutes: 25, label: "덮어쓰기", companion: store))
            #expect(timer.phase == phase)
            #expect(timer.endsAt == end)
            #expect(store.activeAdventure == nil)
        }
    }

    @Test func rejectedStartKeepsCandidateAndSuccessConsumesIt() {
        let directory = storeFixtureDirectory("focus-resume-gate")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(clock: { base }, fileURL: directory.appendingPathComponent("state.json"))
        let (timer, log, restEnd) = completedTimer()
        timer.tick(now: restEnd)
        let session = timer.continuation(in: log, now: restEnd)!
        #expect(!timer.startFocusSession(minutes: session.minutes, label: session.label, companion: store))
        #expect(timer.continuation(in: log, now: restEnd) == session)
        let mon = MonState(baseID: 25, pathIDs: [25], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1)
        store.debugSetBoxedMons([mon])
        store.switchCompanion(to: mon.id)
        #expect(timer.startFocusSession(minutes: session.minutes, label: session.label, companion: store))
        #expect(timer.focusMinutes == 25)
        #expect(timer.focusLabel == "문서 작성")
        #expect(timer.continuationSession == nil)
        let end = timer.endsAt
        let adventure = store.activeAdventure
        #expect(!timer.startFocusSession(minutes: 90, companion: store))
        #expect(timer.endsAt == end)
        #expect(store.activeAdventure == adventure)
        #expect(store.focusSessionsToday == 0)
    }

    @Test func sharedStartPreservesAutomaticSettlementOfCompletedAdventure() {
        let directory = storeFixtureDirectory("focus-auto-claim")
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = base
        let store = store(in: directory, clock: { now })
        #expect(store.startFocusAdventure(minutes: 25))
        now = base.addingTimeInterval(1500)
        let before = store.state.starPieces
        let timer = FocusTimer()
        #expect(timer.startFocusSession(minutes: 25, companion: store))
        #expect(store.state.starPieces > before)
        let settled = store.state.starPieces
        #expect(store.claimAdventure() == nil)
        #expect(store.state.starPieces == settled)
        #expect(store.focusSessionsToday == 0)
    }
}
