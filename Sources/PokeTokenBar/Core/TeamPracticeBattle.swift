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

    mutating func switchMine(to index: Int) -> Bool {
        guard mine.indices.contains(index), index != myActive, mine[index].isAlive, result == nil else { return false }
        myActive = index
        return true
    }

    mutating func useMove(_ index: Int) -> Bool {
        guard result == nil, mine[myActive].isAlive, opponents[opponentActive].isAlive else { return false }
        let myMoves = mine[myActive].snapshot.moves ?? MoveSpec.fallbackSet(types: mine[myActive].snapshot.types)
        let myIndex = mine[myActive].pp.contains(where: { $0 > 0 }) ? index : -1
        guard myIndex == -1 || (myMoves.indices.contains(myIndex) && mine[myActive].pp[myIndex] > 0) else { return false }
        let cpuAvailable = opponents[opponentActive].pp.indices.filter { opponents[opponentActive].pp[$0] > 0 }
        let cpuIndex = cpuAvailable.randomElement() ?? -1
        let cpuMoves = opponents[opponentActive].snapshot.moves ?? MoveSpec.fallbackSet(types: opponents[opponentActive].snapshot.types)
        let myMove = myIndex < 0 ? MoveSpec.struggle() : myMoves[myIndex]
        let cpuMove = cpuIndex < 0 ? MoveSpec.struggle() : cpuMoves[cpuIndex]
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
