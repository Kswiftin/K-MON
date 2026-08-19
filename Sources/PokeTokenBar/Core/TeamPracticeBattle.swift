import Foundation

struct TeamPracticeBattle {
    var mine: [BattleSide]
    var opponents: [BattleSide]
    var myActive = 0
    var opponentActive = 0
    var turn = 1
    var events: [BattleEvent] = []
    var rng: SplitMix64
    var result: Bool?

    var mySlot: BattleSide { mine[myActive] }
    var opponentSlot: BattleSide { opponents[opponentActive] }
    var availableSwitches: [Int] { mine.indices.filter { $0 != myActive && mine[$0].isAlive } }

    /// 교체 — **그 턴의 행동이다.** 본가와 같이 교체하는 쪽은 공격하지 못하고, 새로 나온 포켓몬이
    /// 상대 공격을 맞으며 시작한다.
    ///
    /// 예전엔 활성 슬롯만 바꾸고 끝나서 교체가 공짜였다. 상성이 나쁘면 계속 갈아타며 유리한
    /// 상대만 때릴 수 있었고, 상대는 그동안 한 번도 움직이지 못했다.
    mutating func switchMine(to index: Int) -> Bool {
        guard mine.indices.contains(index), index != myActive, mine[index].isAlive, result == nil else { return false }
        // Gen 2 는 물러난 포켓몬의 맹독을 보통 독으로 강등한다(Gen 3 부터는 유지 + 카운터만 리셋).
        // 이게 없으면 맹독은 한 번 걸리면 배틀이 끝날 때까지 배수가 계속 커진다.
        if mine[myActive].status == .toxic {
            mine[myActive].status = .poison
            mine[myActive].statusCounter = 0
        }
        myActive = index
        opponentAttacksAlone()
        turn += 1
        advanceFainted()
        return true
    }

    /// CPU 가 이번에 쓸 기술 — PP 가 남은 것 중 하나, 전부 떨어졌으면 발버둥(index −1).
    ///
    /// **배틀의 `rng` 에서 뽑는다.** `randomElement()`(시스템 RNG)를 쓰던 때는 같은 seed 로도 배틀이
    /// 재현되지 않았다. 로컬 전용이라 desync 는 없지만 seed 를 고정한 회귀 테스트를 쓸 수 없었고,
    /// 상태이상·랭크업처럼 확률 분기가 늘어나는 기전은 그 테스트 없이 검증할 방법이 없다.
    private mutating func cpuMoveChoice() -> (move: MoveSpec, index: Int) {
        let slot = opponents[opponentActive]
        let candidates = slot.pp.indices.filter { slot.pp[$0] > 0 }
        guard !candidates.isEmpty else { return (MoveSpec.struggle(), -1) }
        let index = candidates[Int(rng.next() % UInt64(candidates.count))]
        return (slot.move(at: index), index)
    }

    /// 상대 공격 1회만 해상 — 내가 교체에 턴을 썼을 때 상대 몫이다.
    /// 이벤트는 `applyAttack` 이 만든다(엔진 좌변이 나 = `.a`, CPU = `.b`).
    private mutating func opponentAttacksAlone() {
        guard opponents[opponentActive].isAlive, mine[myActive].isAlive else { return }
        let (move, moveIndex) = cpuMoveChoice()
        if moveIndex >= 0 { opponents[opponentActive].pp[moveIndex] -= 1 }
        events.append(.turn(turn))
        events += BattleEngine.applyAttack(attacker: &opponents[opponentActive], defender: &mine[myActive],
                                           attackerActor: .b, defenderActor: .a, move: move, rng: &rng)
        // 교체로 넘긴 턴도 턴이다 — 잔뎀은 그대로 들어간다.
        events += BattleEngine.endOfTurnResidual(&mine[myActive], actor: .a)
        events += BattleEngine.endOfTurnResidual(&opponents[opponentActive], actor: .b)
    }

    mutating func useMove(_ index: Int) -> Bool {
        guard result == nil, mine[myActive].isAlive, opponents[opponentActive].isAlive else { return false }
        let myIndex = mine[myActive].mustStruggle ? -1 : index
        guard myIndex == -1 || mine[myActive].canUse(moveAt: myIndex) else { return false }
        let myMove = mine[myActive].move(at: myIndex)
        let (cpuMove, cpuIndex) = cpuMoveChoice()
        if myIndex >= 0 { mine[myActive].pp[myIndex] -= 1 }
        if cpuIndex >= 0 { opponents[opponentActive].pp[cpuIndex] -= 1 }
        let resolved = BattleEngine.resolveTurn(a: &mine[myActive], b: &opponents[opponentActive],
                                                moveA: myMove, moveB: cpuMove, turn: turn, rng: &rng)
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
