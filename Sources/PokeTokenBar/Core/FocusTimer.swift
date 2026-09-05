import Foundation

enum FocusPhase: String, Sendable { case idle, focus, rest }

@MainActor
@Observable
final class FocusTimer {
    private(set) var phase: FocusPhase = .idle
    private(set) var endsAt: Date?
    private(set) var completedSessions = 0
    private(set) var focusMinutes = 25
    /// 세션 완료 정산 훅. **돌려줄 값이 없다** — 정산 결과를 화면에 남기는 일은 스토어의
    /// `lastClaim` 이 맡는다. 예전엔 여기 `lastReward` 로도 들고 있었지만, 그 값은 세션 완료
    /// 경로에만 채워져 나머지 세 정산 경로를 설명하지 못했다(#192). 반환형을 남겨 두면 그걸
    /// 채우려고 없는 보상을 지어내는 자리가 다시 생긴다(앱 루트가 실제로 그랬다).
    var onFocusCompleted: ((Int) -> Void)?
    /// 다음 휴식 길이. 완료 훅이 **기록을 남긴 뒤** 읽힌다 — 오늘 몇 세션째인지는 원장만 알고,
    /// 순서가 뒤집히면 긴 휴식이 한 세션씩 밀린다(화면엔 아무 오류도 안 뜬다).
    ///
    /// 위 훅에 반환형을 되살리지 않고 이름을 갈라 두는 이유는 그 주석 그대로다 — 그 자리는 없는
    /// 보상을 지어내는 자리였다. 휴식 길이는 보상이 아니라서 다른 훅으로 받는다.
    var nextRestMinutes: (() -> Int)?
    /// 휴식이 끝났다. 체인이 다음 집중을 켜는 자리다.
    var onRestCompleted: (() -> Void)?

    var isRunning: Bool { phase != .idle && endsAt != nil }

    /// 집중을 **시작한** 횟수. 화면이 "지난 세션의 안내" 를 스스로 내리는 기준이다 — 시작마다
    /// 오르므로 뷰는 자기가 들고 있는 값과 비교만 하면 되고, `onChange` 실행 순서에 기대지 않는다.
    /// (모험 시작 정산은 시작과 같은 갱신에서 들어온다 — 순서에 기대면 그 정산이 지워진다.)
    private(set) var sessionStartSeq = 0

    func startFocus(minutes: Int = 25, now: Date = Date()) {
        phase = .focus
        sessionStartSeq += 1
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
            onFocusCompleted?(focusMinutes)                  // 기록이 먼저 — 아래가 그 집계를 읽는다
            startRest(minutes: nextRestMinutes?() ?? FocusChainRules.shortRestMinutes, now: now)
        } else {
            stop()
            // **마지막 문장이다.** 뒤에 무엇을 더하면 훅이 켠 다음 세션을 그것이 지운다.
            // `stop()` 앞에 두면 훅이 본 단계가 `.rest` 라 게이트가 그 시작을 거절한다.
            onRestCompleted?()
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
