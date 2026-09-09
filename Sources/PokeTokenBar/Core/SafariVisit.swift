import Foundation

/// 조우 하나에 있었던 행동과 그 결과 한 줄 — 화면이 문장으로 옮긴다(Core 는 로컬라이즈 문자열을
/// 안 만든다). "조우 시작" 은 별도 행동이 아니므로 `action`/`outcome` 이 nil 인 줄로 남긴다.
struct SafariLogEntry: Sendable, Codable, Equatable {
    let speciesID: Int
    let action: SafariAction?
    let outcome: SafariOutcome?
    /// 미끼/진흙의 90% 부작용이 이 줄에서 실제로 일어났는지 — 다른 액션은 `nil`.
    /// 옵셔널이라 기존 곁파일(이 필드가 없던 시절 저장분)도 그대로 디코딩된다(`decodeIfPresent`).
    /// 기본값을 둬 조우 시작 로그(`action`/`outcome` 도 nil인 줄) 생성부는 그대로 컴파일된다.
    let sideEffectTriggered: Bool?

    init(speciesID: Int, action: SafariAction?, outcome: SafariOutcome?, sideEffectTriggered: Bool? = nil) {
        self.speciesID = speciesID
        self.action = action
        self.outcome = outcome
        self.sideEffectTriggered = sideEffectTriggered
    }
}

/// 사파리존 방문 하나 — 걷기 상태(`SafariWalker`)와 조우 상태(`SafariEncounter`)를 아우르고,
/// 볼·걸음·방문당 포획 상한을 관리한다. `RogueRun` 과 마찬가지로 `Codable` 을 직접 준수하지
/// 않는다 — `SplitMix64` 가 `Codable` 이 아니라서다(씨앗과 소비된 상태를 분리해서 저장해야
/// 하므로 `SafariZoneSave` 가 그 변환을 전담한다).
struct SafariVisit: Sendable {
    let zone: SafariZone.ZoneID
    let seed: UInt64
    private(set) var balls: Int
    private(set) var stepsRemaining: Int
    private(set) var walker: SafariWalker
    private(set) var currentEncounter: SafariEncounter?
    /// 이 방문에서 잡은 수 — 방문당 상한(`SafariZone.catchesPerVisitCap`)을 재는 로컬 카운터.
    /// 날짜와 무관하므로 원장이 아니라 여기 산다(방문이 끝나면 함께 사라진다).
    private(set) var catchesThisVisit = 0
    private(set) var caughtSpeciesIDs: [Int] = []
    private(set) var visitLog: [SafariLogEntry] = []
    /// 방문이 자연 종료됐나(걸음 소진 또는 포획 여유 소진). 종료된 뒤에는 `advance`/`act` 가
    /// 아무 상태도 안 바꾼다 — 화면이 이 플래그를 보고 요약 화면으로 넘어간다.
    private(set) var hasEnded = false
    private var rng: SplitMix64
    /// 저장 전용 — `SafariZoneSave` 가 소비된 뒤의 rng 상태를 읽는 자리(seed 는 별도 필드로
    /// 이미 공개돼 있다).
    var rngState: UInt64 { rng.state }

    init(zone: SafariZone.ZoneID, seed: UInt64) {
        self.zone = zone
        self.seed = seed
        self.balls = SafariZone.ballsPerVisit
        self.stepsRemaining = SafariZone.stepsPerVisit
        let bounds = SafariFieldBounds.standard
        self.walker = SafariWalker(startingAt: SafariCell(x: bounds.width / 2, y: bounds.height / 2))
        self.rng = SplitMix64(seed: seed)
    }

    /// 매 프레임 호출 — 조우가 없을 때만 걷기를 진행한다(조우 중엔 이동 입력을 무시한다).
    /// 칸에 새로 도착한 순간에만 걸음을 소모하고 인카운터를 정확히 한 번 굴린다.
    ///
    /// `catchesRemainingToday` 는 순수 Core 가 날짜를 모르므로 `CompanionStore` 가 매 호출마다
    /// 최신값을 흘려준다. 이 방문·오늘 어느 한쪽이라도 포획 여유가 0이면 새 조우를 굴리지 않고
    /// **그 자리에서 방문을 끝낸다** — 볼·걸음이 남아 있어도 더 걸을 이유가 없다.
    mutating func advance(dt: Double, heldKeys: Set<SafariDirectionKey>, catchesRemainingToday: Int) {
        guard !hasEnded, currentEncounter == nil else { return }
        guard walker.tick(dt: dt, heldKeys: heldKeys, bounds: SafariFieldBounds.standard) else { return }
        stepsRemaining = max(0, stepsRemaining - 1)
        guard stepsRemaining > 0 else { hasEnded = true; return }
        let catchesRemainingThisVisit = SafariZone.catchesPerVisitCap - catchesThisVisit
        guard min(catchesRemainingThisVisit, catchesRemainingToday) > 0 else { hasEnded = true; return }
        guard balls > 0, Int(rng.next() % 100) < SafariZone.stepEncounterPercent else { return }
        let speciesID = SafariZone.chooseEncounter(zone: zone, rng: &rng)
        let rarity = SafariZone.rarity(speciesID: speciesID, zone: zone)
        currentEncounter = SafariEncounter(speciesID: speciesID, rarity: rarity)
        visitLog.append(SafariLogEntry(speciesID: speciesID, action: nil, outcome: nil))
    }

    /// **네 액션의 유일한 진입점.** 조우가 없으면(`currentEncounter == nil`) 아무 것도 안 하고
    /// `.continuing` 을 돌려준다. 볼이 없는데 `.ball` 을 보내도 마찬가지다 — 이 두 게이트가
    /// `SafariAction` 네 값 전부에 대해 같은 자리에서 걸리므로, 나중에 새 게이트를 넣을 때
    /// 입력 경로 하나를 빠뜨리는 결함 부류(`defect-log.md`)가 구조적으로 재발하지 않는다.
    @discardableResult
    mutating func act(_ action: SafariAction) -> SafariOutcome {
        guard var encounter = currentEncounter else { return .continuing }
        guard action != .ball || balls > 0 else { return .continuing }
        if action == .ball { balls -= 1 }
        let outcome = encounter.act(action, rng: &rng)
        visitLog.append(SafariLogEntry(speciesID: encounter.speciesID, action: action, outcome: outcome,
                                       sideEffectTriggered: encounter.lastSideEffect))
        switch outcome {
        case .caught:
            catchesThisVisit += 1
            caughtSpeciesIDs.append(encounter.speciesID)
            currentEncounter = nil
        case .fled, .ranAway, .timedOut:
            currentEncounter = nil
        case .continuing:
            currentEncounter = encounter
        }
        return outcome
    }

    /// `act(.ball)` 이 `.caught` 를 낸 직후, 그 개체를 실제로 영구 반영하는
    /// `CompanionStore.catchInSafariZone` 이 실패했을 때(스프라이트 없음·라인 조회 실패 등)
    /// 호출한다. `catchesThisVisit`/`caughtSpeciesIDs` 는 조우 결과가 나는 즉시 낙관적으로
    /// 갱신되므로, 실제 커밋이 실패하면 이 방문 로컬 카운터만 그 만큼 되돌려 방문당 상한이
    /// 잡지도 못한 개체 때문에 부풀려지지 않게 한다. `hasEnded` 는 건드리지 않는다 — 이미
    /// 종료 판정이 난 방문을 되살리면 화면 흐름(요약 화면 전환)이 더 꼬인다.
    mutating func revertUncommittedCatch() {
        guard catchesThisVisit > 0, !caughtSpeciesIDs.isEmpty else { return }
        catchesThisVisit -= 1
        caughtSpeciesIDs.removeLast()
    }

    /// 저장된 방문을 복원할 때만 쓰는 이니셜라이저(`SafariZoneSave.restored` 전용). 다른 모든
    /// 필드는 `advance`/`act` 로만 바뀌어야 하므로, 이 경로 밖에서 직접 만들지 않는다.
    init(zone: SafariZone.ZoneID, seed: UInt64, balls: Int, stepsRemaining: Int,
         walker: SafariWalker, currentEncounter: SafariEncounter?, catchesThisVisit: Int,
         caughtSpeciesIDs: [Int], visitLog: [SafariLogEntry], hasEnded: Bool, rngState: UInt64) {
        self.zone = zone
        self.seed = seed
        self.balls = balls
        self.stepsRemaining = stepsRemaining
        self.walker = walker
        self.currentEncounter = currentEncounter
        self.catchesThisVisit = catchesThisVisit
        self.caughtSpeciesIDs = caughtSpeciesIDs
        self.visitLog = visitLog
        self.hasEnded = hasEnded
        self.rng = SplitMix64(seed: 0)
        self.rng.state = rngState
    }

    /// 디스크에 남길 형태 — `CompanionStore.persistSafariVisit()` 이 이걸 인코딩한다.
    var saveForm: SafariZoneSave { SafariZoneSave(self) }
}
