import Foundation

/// 웨이브 런 전용 전투 — 한쪽에 **최대 두 칸**이 동시에 선다(2대2).
///
/// `TeamPracticeBattle` 을 고치지 않고 따로 두는 이유는 공유다: 그 타입은 체육관·토너먼트·LAN
/// 대전이 함께 쓰고 활성 칸이 각각 하나로 굳어 있다. 거기에 슬롯 배열을 끼우면 세 모드의 턴
/// 규칙이 한 번에 흔들린다. 반대로 `BattleEngine` 은 **손대지 않고 그대로 재사용한다** —
/// `applyAttack`·`endOfTurnResidual` 은 이미 "공격자 하나 · 방어자 하나" 단위라 칸이 늘어도
/// 규칙이 같고, 엔진을 고치면 `rulesVersion`·와이어 계약이 함께 움직인다.
///
/// **이벤트 주인은 `.fighter(UUID)` 다.** `.a`/`.b` 는 한쪽에 한 칸일 때만 쓸 수 있어서
/// 2대2 에서는 같은 편 두 칸이 한 주인으로 접힌다(로그·HP바·흔들림이 엉뚱한 칸에 붙는다).
/// 칸마다 배틀 안에서만 사는 id 를 두고 그 id 로 이벤트를 낸다 — LAN 팀전(`MultiplayerBattle`)이
/// 쓰는 것과 같은 주인 표현이다.
struct WaveBattle: Sendable {
    /// 필드 한 칸. `teamIndex` 는 지금 그 자리에 선 팀 인덱스이고, **쓰러진 개체도 교체되기
    /// 전까지 그 자리에 남는다** — 재생기(`ReplaySide.active`)가 칸을 인덱스로 읽으므로 빈
    /// 값으로 두면 기절한 스프라이트가 화면에서 즉시 사라진다.
    struct FieldSlot: Sendable, Equatable {
        /// 이벤트 주인. 배틀이 만들어질 때 한 번 뽑고 바뀌지 않는다 — 칸 위의 개체가 교체돼도
        /// 같은 자리다(재생기의 `sides` 키가 turn 중간에 바뀌면 그 칸의 표시 상태가 끊긴다).
        let id: UUID
        var teamIndex: Int
    }

    /// 한 칸이 이번 턴에 할 일.
    enum SlotAction: Sendable, Equatable {
        /// `target` 은 **상대 필드 칸의 순번**이다(팀 인덱스가 아니다) — 화면이 고르는 것은 자리다.
        case move(index: Int, target: Int)
        case switchTo(teamIndex: Int)
    }

    /// 한쪽 필드의 칸 수 상한. 3대3(트리플)은 이 값만 올려서는 안 된다 — 광역기 사거리 규칙이
    /// 먼저 필요하다.
    static let maxFieldSlots = 2

    var mine: [BattleSide]
    var opponents: [BattleSide]
    var myField: [FieldSlot]
    var opponentField: [FieldSlot]
    var turn = 1
    var events: [BattleEvent] = []
    var rng: SplitMix64
    /// 승부 — `nil` 은 진행 중이다. 무승부가 값으로 있어야 동시 전멸이 승리로 접히지 않는다
    /// (1대1·팀 연습과 같은 규칙).
    var result: BattleOutcome?
    /// 아직 해상되지 않은 내 칸의 행동. 살아 있는 칸이 모두 채워지는 순간 턴이 돈다.
    var pendingActions: [Int: SlotAction] = [:]

    /// 필드 칸 수는 **상대 마릿수와 파티 마릿수 중 작은 쪽**이다. 파티가 한 마리면 2대1 이다 —
    /// 포켓로그도 플레이어 필드를 파티 수로 자른다(`src/battle-scene.ts:733`). 자르지 않으면
    /// 아무도 서지 않은 칸이 상대 공격의 타겟 후보로 남는다.
    init(mine: [BattleSide], opponents: [BattleSide], rng: SplitMix64) {
        self.mine = mine
        self.opponents = opponents
        self.rng = rng
        let format = min(Self.maxFieldSlots, opponents.count)
        self.opponentField = (0..<format).map { FieldSlot(id: UUID(), teamIndex: $0) }
        let leads = mine.indices.filter { mine[$0].isAlive }.prefix(format)
        // 살아 있는 개체가 없는 파티로는 필드를 세울 수 없다 — 그래도 칸을 하나 두는 이유는
        // 화면이다(빈 필드를 그리는 경로가 없다). 이 판은 첫 정산에서 패배로 닫힌다.
        self.myField = leads.isEmpty
            ? (mine.isEmpty ? [] : [FieldSlot(id: UUID(), teamIndex: 0)])
            : leads.map { FieldSlot(id: UUID(), teamIndex: $0) }
    }

    // MARK: 필드 읽기

    func mySide(at ordinal: Int) -> BattleSide? {
        guard myField.indices.contains(ordinal) else { return nil }
        return mine[myField[ordinal].teamIndex]
    }

    func opponentSide(at ordinal: Int) -> BattleSide? {
        guard opponentField.indices.contains(ordinal) else { return nil }
        return opponents[opponentField[ordinal].teamIndex]
    }

    var livingMySlots: [Int] { myField.indices.filter { mine[myField[$0].teamIndex].isAlive } }
    var livingOpponentSlots: [Int] {
        opponentField.indices.filter { opponents[opponentField[$0].teamIndex].isAlive }
    }

    /// 필드에 없고 살아 있는 내 팀 인덱스 — 교체·기절 보충의 후보다.
    var benchCandidates: [Int] {
        let onField = Set(myField.map(\.teamIndex))
        return mine.indices.filter { mine[$0].isAlive && !onField.contains($0) }
    }

    /// 사용자가 **먼저 채워야 하는** 칸 — 쓰러진 개체가 서 있고 벤치가 남은 자리다.
    /// 채우기 전에는 행동을 받지 않는다(`slotsAwaitingAction` 이 비어 있다).
    var slotsNeedingSendOut: [Int] {
        guard result == nil, !benchCandidates.isEmpty else { return [] }
        return myField.indices.filter { !mine[myField[$0].teamIndex].isAlive }
    }

    /// 이번 턴에 아직 행동을 안 정한 칸. 이 배열이 비면 턴이 돈다.
    var slotsAwaitingAction: [Int] {
        guard result == nil, slotsNeedingSendOut.isEmpty else { return [] }
        return livingMySlots.filter { pendingActions[$0] == nil }
    }

    private func actor(mine ordinal: Int) -> BattleActor { .fighter(myField[ordinal].id) }
    private func actor(opponent ordinal: Int) -> BattleActor { .fighter(opponentField[ordinal].id) }

    // MARK: 입력

    /// 쓰러진 칸을 벤치에서 채운다 — **턴을 쓰지 않는다**(본가와 같다). 살아 있는 개체를 바꾸는
    /// 것은 `SlotAction.switchTo` 로, 그쪽은 그 칸의 행동을 대가로 낸다.
    ///
    /// 기절 보충을 공짜로 두는 이유는 2대2 의 산수다. 1대1 시절 규칙(교체 = 그 턴 헌납)을 그대로
    /// 쓰면 한 마리를 잃을 때마다 남은 칸이 **둘을 상대로** 한 턴을 더 내주고, 그 한 턴에 다시
    /// 하나가 눕는 연쇄가 된다.
    @discardableResult
    mutating func sendOut(teamIndex: Int, toSlot ordinal: Int) -> Bool {
        guard result == nil, myField.indices.contains(ordinal),
              !mine[myField[ordinal].teamIndex].isAlive,
              benchCandidates.contains(teamIndex) else { return false }
        myField[ordinal].teamIndex = teamIndex
        events.append(.sendOut(actor(mine: ordinal), teamIndex: teamIndex))
        return true
    }

    /// 한 칸의 행동을 적는다. 살아 있는 칸이 모두 채워지면 **그 자리에서 턴을 해상한다** —
    /// 화면이 따로 "턴 시작" 을 누르지 않아도 1대1 과 같은 흐름으로 돈다.
    ///
    /// 같은 칸에 다시 부르면 앞 입력을 덮는다(수정 경로). 받아들이지 못한 입력은 `false` 다 —
    /// 범위 밖 타겟·PP 없는 기술·이미 필드에 선 개체로의 교체가 그렇다.
    @discardableResult
    mutating func choose(_ action: SlotAction, forSlot ordinal: Int) -> Bool {
        guard result == nil, slotsNeedingSendOut.isEmpty, livingMySlots.contains(ordinal),
              !livingOpponentSlots.isEmpty else { return false }
        switch action {
        case .move(let index, let target):
            guard opponentField.indices.contains(target) else { return false }
            let side = mine[myField[ordinal].teamIndex]
            let resolved = side.mustStruggle ? -1 : index
            guard resolved == -1 || side.canUse(moveAt: resolved) else { return false }
            pendingActions[ordinal] = .move(index: resolved, target: target)
        case .switchTo(let teamIndex):
            guard benchCandidates.contains(teamIndex) else { return false }
            // 두 칸이 같은 개체를 예약하면 한 개체가 두 자리에 선다 — 그 개체가 한 턴에 두 번
            // 움직이고 데미지도 두 몫으로 들어간다.
            guard !pendingActions.contains(where: { $0.key != ordinal
                                                    && $0.value == .switchTo(teamIndex: teamIndex) })
            else { return false }
            pendingActions[ordinal] = action
        }
        if slotsAwaitingAction.isEmpty { resolveTurn() }
        return true
    }

    /// 내 편이 **아무도 공격하지 않는** 턴 — 볼 던지기의 대가다. 상대는 전원 움직이고 잔뎀도
    /// 들어간다. 한 칸만 헌납하는 값으로 두면 2대2 에서 볼 던지기가 사실상 공짜가 된다(남은
    /// 칸이 그 턴에도 때린다).
    @discardableResult
    mutating func spendTurnWithoutAttacking() -> Bool {
        guard result == nil, slotsNeedingSendOut.isEmpty,
              !livingMySlots.isEmpty, !livingOpponentSlots.isEmpty else { return false }
        pendingActions = [:]
        resolveTurn()
        return true
    }

    /// 잡힌 상대를 전투에서 뺀다 — **쓰러진 것과 같은 자리**(`advanceFainted`)를 지난다.
    /// 배열에서 지우지 않는 이유는 인덱스가 필드 칸의 좌표라서다.
    mutating func retireOpponent(atSlot ordinal: Int) {
        guard result == nil, opponentField.indices.contains(ordinal) else { return }
        opponents[opponentField[ordinal].teamIndex].hp = 0
        advanceFainted()
    }

    // MARK: 턴 해상

    /// 이번 턴의 공격 하나. 실행 시점에 인덱스를 다시 읽으므로(앞순서에서 교체·기절이 일어난다)
    /// 여기에는 **자리**만 담는다.
    private struct Attack {
        let isMine: Bool
        let slot: Int
        let moveIndex: Int
        let target: Int
    }

    private mutating func resolveTurn() {
        events.append(.turn(turn))
        applyPendingSwitches()
        // 턴 머리에 "이번 턴에 맞은 것" 을 비운다 — 필드 전원이다. 한 칸이라도 빠지면 그 칸의
        // 카운터(카운터·미러코트)가 지난 턴 데미지를 되돌려준다.
        for slot in myField { BattleEngine.beginTurn(&mine[slot.teamIndex]) }
        for slot in opponentField { BattleEngine.beginTurn(&opponents[slot.teamIndex]) }

        var attacks = myField.indices.compactMap { ordinal -> Attack? in
            guard case .move(let index, let target) = pendingActions[ordinal],
                  mine[myField[ordinal].teamIndex].isAlive else { return nil }
            return Attack(isMine: true, slot: ordinal, moveIndex: index, target: target)
        }
        attacks += cpuAttacks()

        // 본가와 같은 순서: 기술 우선도 → 스피드 → 무작위. tie-break 키는 정렬에 들어가기
        // **전에** 하나씩 뽑는다 — 비교 클로저 안에서 rng 를 부르면 소비 횟수가 정렬 알고리즘의
        // 비교 횟수에 딸려가고, 그러면 같은 seed 로 판이 재현되지 않는다(LAN 팀전과 같은 함정).
        let tieBreakers = attacks.map { _ in rng.next() }
        let ordered = zip(attacks, tieBreakers).sorted { lhs, rhs in
            let left = side(of: lhs.0), right = side(of: rhs.0)
            let leftPriority = left.move(at: lhs.0.moveIndex).turnPriority
            let rightPriority = right.move(at: rhs.0.moveIndex).turnPriority
            if leftPriority != rightPriority { return leftPriority > rightPriority }
            if left.effectiveSpeed != right.effectiveSpeed {
                return left.effectiveSpeed > right.effectiveSpeed
            }
            return lhs.1 < rhs.1
        }.map(\.0)

        for attack in ordered { execute(attack) }

        // 턴 끝 잔뎀·나머지회복 — 1대1 과 같은 규칙이고, 순서는 필드 배열 순서로 고정한다.
        for slot in myField {
            events += BattleEngine.endOfTurnResidual(&mine[slot.teamIndex],
                                                     actor: .fighter(slot.id))
        }
        for slot in opponentField {
            events += BattleEngine.endOfTurnResidual(&opponents[slot.teamIndex],
                                                     actor: .fighter(slot.id))
        }
        turn += 1
        pendingActions = [:]
        advanceFainted()
    }

    /// 교체는 공격보다 먼저 일어난다(본가와 같다) — 그래서 교체한 칸은 새로 나온 개체가 그 턴의
    /// 공격을 맞는다. 나가는 개체의 랭크·혼란은 여기서 지운다.
    private mutating func applyPendingSwitches() {
        for ordinal in myField.indices {
            guard case .switchTo(let teamIndex) = pendingActions[ordinal],
                  benchCandidates.contains(teamIndex) else { continue }
            BattleEngine.prepareForSwitch(&mine[myField[ordinal].teamIndex])
            myField[ordinal].teamIndex = teamIndex
            events.append(.sendOut(actor(mine: ordinal), teamIndex: teamIndex))
        }
    }

    /// CPU 의 행동 — 야생이므로 기술도 타겟도 배틀 `rng` 에서 무작위로 뽑는다. 시스템 RNG
    /// (`randomElement()`)를 쓰면 같은 seed 로도 판이 재현되지 않아, 확률 분기가 붙은 결함을
    /// 회귀 테스트로 잡을 수 없다.
    ///
    /// **소비 순서는 칸 순서대로 "기술 → 타겟" 이다.** 이 순서가 곧 세이브를 이어 연 판의
    /// 재현 규칙이라, 바꾸면 저장된 rng 상태가 다른 판을 만든다.
    private mutating func cpuAttacks() -> [Attack] {
        livingOpponentSlots.compactMap { ordinal in
            let side = opponents[opponentField[ordinal].teamIndex]
            let candidates = side.pp.indices.filter { side.pp[$0] > 0 }
            let moveIndex = candidates.isEmpty
                ? -1
                : candidates[Int(rng.next() % UInt64(candidates.count))]
            let targets = livingMySlots
            guard !targets.isEmpty else { return nil }
            let target = targets[Int(rng.next() % UInt64(targets.count))]
            return Attack(isMine: false, slot: ordinal, moveIndex: moveIndex, target: target)
        }
    }

    private func side(of attack: Attack) -> BattleSide {
        attack.isMine
            ? mine[myField[attack.slot].teamIndex]
            : opponents[opponentField[attack.slot].teamIndex]
    }

    /// 공격 하나를 해상한다. **타겟이 이미 쓰러졌으면 남은 상대로 돌려 때린다** — 본가 3세대
    /// 이후와 같은 규칙이고, 돌리지 않으면 두 칸이 같은 상대를 고른 턴의 뒤 칸이 통째로 헛돈다.
    /// 공격자가 앞순서에 쓰러졌으면 아무 일도 없다(PP 도 줄지 않는다).
    private mutating func execute(_ attack: Attack) {
        let attackerIndex = attack.isMine
            ? myField[attack.slot].teamIndex : opponentField[attack.slot].teamIndex
        let attackerAlive = attack.isMine
            ? mine[attackerIndex].isAlive : opponents[attackerIndex].isAlive
        guard attackerAlive else { return }
        // 타겟 자리 → 살아 있는 자리로 보정. 남은 상대가 없으면 이 턴은 여기서 끝난다.
        let targetSlots = attack.isMine ? livingOpponentSlots : livingMySlots
        guard let targetSlot = targetSlots.contains(attack.target) ? attack.target : targetSlots.first
        else { return }
        let attackerActor = attack.isMine ? actor(mine: attack.slot) : actor(opponent: attack.slot)
        let defenderActor = attack.isMine ? actor(opponent: targetSlot) : actor(mine: targetSlot)

        if attack.isMine {
            let defenderIndex = opponentField[targetSlot].teamIndex
            let move = mine[attackerIndex].move(at: attack.moveIndex)
            if attack.moveIndex >= 0 { mine[attackerIndex].pp[attack.moveIndex] -= 1 }
            events += BattleEngine.applyAttack(attacker: &mine[attackerIndex],
                                               defender: &opponents[defenderIndex],
                                               attackerActor: attackerActor,
                                               defenderActor: defenderActor,
                                               move: move, rng: &rng)
        } else {
            let defenderIndex = myField[targetSlot].teamIndex
            let move = opponents[attackerIndex].move(at: attack.moveIndex)
            if attack.moveIndex >= 0 { opponents[attackerIndex].pp[attack.moveIndex] -= 1 }
            events += BattleEngine.applyAttack(attacker: &opponents[attackerIndex],
                                               defender: &mine[defenderIndex],
                                               attackerActor: attackerActor,
                                               defenderActor: defenderActor,
                                               move: move, rng: &rng)
        }
    }

    /// 전멸 판정과 상대 쪽 자동 보충.
    ///
    /// **양쪽 전멸을 먼저 함께 본다.** 한쪽만 보고 승리를 적으면 "내 마지막 공격이 상대를 눕히고
    /// 턴 끝 잔뎀이 내 마지막을 눕히는" 턴이 승리로 접힌다(팀 연습에서 실제로 배지가 나갔다).
    private mutating func advanceFainted() {
        let myWiped = !mine.contains(where: \.isAlive)
        let theirsWiped = !opponents.contains(where: \.isAlive)
        if myWiped || theirsWiped {
            result = myWiped ? (theirsWiped ? .draw : .loss) : .win
            return
        }
        // 상대의 빈 칸은 스스로 채운다 — 고를 사람이 없다. 내 칸은 사용자가 고른다
        // (`slotsNeedingSendOut`).
        for ordinal in opponentField.indices
        where !opponents[opponentField[ordinal].teamIndex].isAlive {
            let onField = Set(opponentField.map(\.teamIndex))
            guard let next = opponents.indices.first(where: {
                opponents[$0].isAlive && !onField.contains($0)
            }) else { continue }
            opponentField[ordinal].teamIndex = next
            events.append(.sendOut(actor(opponent: ordinal), teamIndex: next))
        }
    }
}
