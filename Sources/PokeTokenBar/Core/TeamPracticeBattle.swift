import Foundation

struct TeamBattleSlot: Identifiable {
    let id = UUID()
    var snapshot: BattleSnapshot
    var hp: Int
    var pp: [Int]

    init(_ snapshot: BattleSnapshot) {
        self.snapshot = snapshot
        hp = snapshot.effectiveStats().hp
        pp = (snapshot.moves ?? MoveSpec.fallbackSet(types: snapshot.types)).map(\.pp)
    }

    var isAlive: Bool { hp > 0 }
}

struct TeamPracticeBattle {
    var mine: [TeamBattleSlot]
    var opponents: [TeamBattleSlot]
    var myActive = 0
    var opponentActive = 0
    var turn = 1
    var events: [NetBattleEvent] = []
    var rng: SplitMix64
    var result: Bool?

    var mySlot: TeamBattleSlot { mine[myActive] }
    var opponentSlot: TeamBattleSlot { opponents[opponentActive] }
    var availableSwitches: [Int] { mine.indices.filter { $0 != myActive && mine[$0].isAlive } }

    /// 교체 — **그 턴의 행동이다.** 본가와 같이 교체하는 쪽은 공격하지 못하고, 새로 나온 포켓몬이
    /// 상대 공격을 맞으며 시작한다.
    ///
    /// 예전엔 활성 슬롯만 바꾸고 끝나서 교체가 공짜였다. 상성이 나쁘면 계속 갈아타며 유리한
    /// 상대만 때릴 수 있었고, 상대는 그동안 한 번도 움직이지 못했다.
    mutating func switchMine(to index: Int) -> Bool {
        guard mine.indices.contains(index), index != myActive, mine[index].isAlive, result == nil else { return false }
        myActive = index
        opponentAttacksAlone()
        turn += 1
        advanceFainted()
        return true
    }

    /// CPU 가 이번에 쓸 기술 — PP 가 남은 것 중 하나, 전부 떨어졌으면 발버둥(index −1).
    private func cpuMoveChoice() -> (move: MoveSpec, index: Int) {
        let slot = opponents[opponentActive]
        let moves = slot.snapshot.moves ?? MoveSpec.fallbackSet(types: slot.snapshot.types)
        guard let index = slot.pp.indices.filter({ slot.pp[$0] > 0 }).randomElement() else {
            return (MoveSpec.struggle(), -1)
        }
        return (moves[index], index)
    }

    /// 상대 공격 1회만 해상 — 내가 교체에 턴을 썼을 때 상대 몫이다.
    private mutating func opponentAttacksAlone() {
        let opponent = opponents[opponentActive]
        guard opponent.isAlive, mine[myActive].isAlive else { return }
        let (move, moveIndex) = cpuMoveChoice()
        if moveIndex >= 0 { opponents[opponentActive].pp[moveIndex] -= 1 }
        let outcome = BattleEngine.resolveAttack(
            attacker: opponent.snapshot, attackerStats: opponent.snapshot.effectiveStats(),
            defender: mine[myActive].snapshot, defenderStats: mine[myActive].snapshot.effectiveStats(),
            move: move, rng: &rng)
        mine[myActive].hp = max(0, mine[myActive].hp - outcome.damage)
        events.append(NetBattleEvent(attackerIsA: false, moveID: move.id, missed: outcome.missed,
                                     damage: outcome.damage, effectiveness: outcome.effectiveness,
                                     isCritical: outcome.isCritical, defenderHPAfter: mine[myActive].hp))
    }

    mutating func useMove(_ index: Int) -> Bool {
        guard result == nil, mine[myActive].isAlive, opponents[opponentActive].isAlive else { return false }
        let myMoves = mine[myActive].snapshot.moves ?? MoveSpec.fallbackSet(types: mine[myActive].snapshot.types)
        let myIndex = mine[myActive].pp.contains(where: { $0 > 0 }) ? index : -1
        guard myIndex == -1 || (myMoves.indices.contains(myIndex) && mine[myActive].pp[myIndex] > 0) else { return false }
        let (cpuMove, cpuIndex) = cpuMoveChoice()
        let myMove = myIndex < 0 ? MoveSpec.struggle() : myMoves[myIndex]
        if myIndex >= 0 { mine[myActive].pp[myIndex] -= 1 }
        if cpuIndex >= 0 { opponents[opponentActive].pp[cpuIndex] -= 1 }
        var myHP = mine[myActive].hp
        var cpuHP = opponents[opponentActive].hp
        let resolved = BattleEngine.resolveTurn(
            a: mine[myActive].snapshot, b: opponents[opponentActive].snapshot,
            statsA: mine[myActive].snapshot.effectiveStats(), statsB: opponents[opponentActive].snapshot.effectiveStats(),
            hpA: &myHP, hpB: &cpuHP, moveA: myMove, moveB: cpuMove, rng: &rng)
        mine[myActive].hp = myHP
        opponents[opponentActive].hp = cpuHP
        events.append(contentsOf: resolved)
        turn += 1
        advanceFainted()
        return true
    }

    private mutating func advanceFainted() {
        if !opponents[opponentActive].isAlive {
            if let next = opponents.indices.first(where: { opponents[$0].isAlive }) { opponentActive = next }
            else { result = true; return }
        }
        if !mine[myActive].isAlive {
            if let next = mine.indices.first(where: { mine[$0].isAlive }) { myActive = next }
            else { result = false }
        }
    }
}
