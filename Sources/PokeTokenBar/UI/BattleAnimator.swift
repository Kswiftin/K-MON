import Foundation

/// 재생 큐를 실제로 돌리는 쪽 (계획 §6 Phase 7). 순수 계층(`BattleReplay`)이 "무엇을 얼마나" 를
/// 정하고, 여기서 그걸 시간축에 푼다 — 뷰는 이 객체가 들고 있는 값(표시 HP · 진행도 · 오버레이)만
/// 읽는 순수 렌더러로 남는다.
///
/// 지금까지는 턴이 해상되면 HP 가 즉시 최종값으로 튀고 로그 네 줄이 한꺼번에 나타났다. 그래서
/// 무엇이 일어났는지 볼 시간이 없었고, 해상 직후 바로 다음 턴 입력이 열렸다.
@MainActor
@Observable
final class BattleAnimator {
    private(set) var overlay = ReplayOverlay.idle
    /// 재생이 소비한 이벤트 수 — 뷰는 **로그도 이만큼만** 잘라 보여 준다. 로그가 스트림 전체를
    /// 그리면 재생이 그 줄에 닿기 전에 결과가 먼저 새어 나가 재생할 이유가 없어진다.
    private(set) var playedCount = 0

    /// 화면에 그릴 HP. 엔진의 HP 와 다른 값을 들 수 있다는 것이 이 클래스의 존재 이유다.
    private var displayHP: [BattleActor: Int] = [:]
    private var stream: [BattleEvent] = []
    private var engineHP: [BattleActor: Int] = [:]
    private var speed: ReplaySpeed = .normal
    /// 첫 동기화인가 — 첫 화면은 재생하지 않고 현재 상태를 그대로 받는다.
    private var hasSeeded = false
    private var task: Task<Void, Never>?

    /// 모르는 쪽은 `nil` 이다 — 0 을 돌려주면 뷰가 쓰러진 것처럼 그린다.
    func hp(for actor: BattleActor) -> Int? { displayHP[actor] }

    /// 뷰가 스트림이 길어질 때마다 부른다. `hp` 는 엔진이 계산해 둔 **현재** HP다.
    func sync(events: [BattleEvent], hp: [BattleActor: Int], speed: ReplaySpeed) {
        stream = events
        engineHP = hp
        self.speed = speed

        // 첫 화면과 새 배틀은 재생하지 않는다. 팝오버를 닫아 뒀다 다시 열면 그동안 쌓인 턴이
        // 통째로 들어오는데, 그걸 처음부터 재생하면 이미 지나간 배틀을 다시 보게 되고 그동안
        // 입력이 잠긴다.
        //
        // **빈 스트림은 언제나 새 배틀이다.** "짧아졌으면 새 배틀" 로만 보면, 아직 한 스텝도
        // 재생하지 않은 채(진행도 0) 다음 배틀이 시작될 때 0 과 0 이 같아 갈아타지 못한다 —
        // 그러면 새 배틀의 만피 대신 이전 배틀의 HP 가 첫 데미지가 들어올 때까지 남는다.
        // 이벤트가 하나도 없으면 따라잡을 것도 없으므로 엔진 값이 곧 화면 값이다.
        guard hasSeeded, !stream.isEmpty, stream.count >= playedCount else { return seed() }
        guard playedCount < stream.count else { return }

        // 끄기는 비동기 한 프레임도 미루지 않는다 — 미루면 "끄기" 인데도 입력이 한 순간 잠긴다.
        guard speed != .off else { return drain() }
        overlay.isPlaying = true
        if task == nil { task = Task { [weak self] in await self?.play() } }
    }

    /// 재생 없이 현재 상태를 그대로 받는다.
    private func seed() {
        task?.cancel()
        task = nil
        hasSeeded = true
        playedCount = stream.count
        displayHP = engineHP
        overlay = .idle
    }

    /// 남은 스텝을 기다림 없이 전부 적용한다.
    private func drain() {
        for step in steps() { displayHP = step.hp }
        playedCount = stream.count
        overlay = .idle
        reconcile()
    }

    private func play() async {
        // 재생 중 다음 턴이 들어올 수 있다(양쪽 선택이 이미 모여 있으면 곧바로 해상된다).
        // 그래서 한 배치를 끝낸 뒤 스트림을 다시 본다.
        while playedCount < stream.count, !Task.isCancelled {
            for step in steps() {
                if Task.isCancelled { break }
                displayHP = step.hp
                overlay = ReplayOverlay(isPlaying: true,
                                        hit: BattleReplay.struck(by: step.event),
                                        popped: step.event)
                playedCount += 1
                if step.duration > 0 { try? await Task.sleep(for: .seconds(step.duration)) }
            }
        }
        // 새 배틀로 갈아탄 뒤라면 이 뒷정리가 남의 상태를 덮는다.
        guard !Task.isCancelled else { return }
        task = nil
        overlay = .idle
        reconcile()
    }

    /// 아직 재생하지 않은 나머지. 호출부가 이미 남은 게 있는지 보고 부르므로 여기서 또 막지
    /// 않는다 — 다 재생한 뒤라도 빈 슬라이스라 안전하다.
    private func steps() -> [ReplayStep] {
        BattleReplay.steps(Array(stream[playedCount...]), from: displayHP, speed: speed)
    }

    /// 재생이 끝난 값이 엔진과 다르면 엔진을 따른다. HP 를 움직이는 이벤트가 늘었는데 투영에
    /// 반영하지 않으면 바가 배틀 내내 어긋난 채로 남는다 — 조용히 맞추지 않고 로그를 남긴다
    /// (`nil` 과 빈 값을 구분하는 것과 같은 부류의 규칙: 삼키면 다음 사람이 못 찾는다).
    private func reconcile() {
        guard displayHP != engineHP else { return }
        AppLog.write("battle replay: 표시 HP \(displayHP) 가 엔진 HP \(engineHP) 와 다르다 — 엔진 값으로 맞춘다")
        displayHP = engineHP
    }
}
