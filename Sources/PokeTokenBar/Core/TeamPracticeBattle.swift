import Foundation

/// CPU의 기술 선택 방식. 일반 모의전은 연습 상대여서 무작위성을 남기고, 체육관 관장은
/// 상성·명중률을 읽어 가장 위협적인 기술을 쓴다.
enum OpponentMoveStrategy: Sendable {
    case random
    case damageFocused
}

struct TeamPracticeBattle {
    var mine: [BattleSide]
    var opponents: [BattleSide]
    var opponentMoveStrategy: OpponentMoveStrategy = .random
    var myActive = 0
    var opponentActive = 0
    var turn = 1
    var events: [BattleEvent] = []
    var rng: SplitMix64
    /// 승부 — `nil` 은 아직 진행 중이다. 예전엔 `Bool?` 라 무승부를 담을 자리가 없어
    /// 동시 전멸이 승리로 접혔다(체육관이면 배지까지 나갔다).
    var result: BattleOutcome?

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
        BattleEngine.prepareForSwitch(&mine[myActive])
        myActive = index
        // 턴 머리와 출전을 **여기서** 적는다 — 재생기가 개체 전환을 알아야 새로 나온 개체를
        // 이전 개체 HP 로 그리지 않고, 출전이 상대 공격보다 먼저여야 순서가 실제와 맞는다.
        events.append(.turn(turn))
        events.append(.sendOut(.a, teamIndex: index))
        opponentAttacksAlone()
        turn += 1
        advanceFainted()
        return true
    }

    /// CPU 가 이번에 쓸 기술 — PP 가 남은 것 중 하나, 전부 떨어졌으면 발버둥(index −1).
    ///
    /// 일반 모의전은 **배틀의 `rng` 에서** 무작위로 뽑는다. `randomElement()`(시스템 RNG)면 같은
    /// seed 로도 배틀이 재현되지 않아, 확률 분기가 늘어나는 기전(상태이상·랭크업)을 회귀 테스트로
    /// 잡을 수 없다. 체육관 관장은 그 무작위성을 쓰지 않고 예상 피해가 가장 큰 기술을 고른다.
    private mutating func cpuMoveChoice() -> (move: MoveSpec, index: Int) {
        let slot = opponents[opponentActive]
        let candidates = slot.pp.indices.filter { slot.pp[$0] > 0 }
        guard !candidates.isEmpty else { return (MoveSpec.struggle(), -1) }

        if case .damageFocused = opponentMoveStrategy {
            let target = mine[myActive]
            let scores = candidates.map { (index: $0, score: expectedDamage(of: slot.move(at: $0), from: slot, to: target)) }
            let bestScore = scores.map(\.score).max() ?? 0
            let best = scores.filter { $0.score == bestScore }.map(\.index)
            // 같은 기대값이면 배틀 RNG로만 갈라 재현성을 보존한다. 예컨대 동일한 위력의 물리·특수
            // 기술이 같은 피해를 낼 때도 항상 첫 번째 버튼만 고르면 관장 패턴이 지나치게 굳는다.
            let index = best[Int(rng.next() % UInt64(best.count))]
            return (slot.move(at: index), index)
        }

        let index = candidates[Int(rng.next() % UInt64(candidates.count))]
        return (slot.move(at: index), index)
    }

    /// 관장 AI의 한 턴용 피해 추정. 실제 엔진과 같은 스탯·STAB·상성·명중 공식을 쓰되, 급소와
    /// 난수는 평균화하지 않는다. 변화기는 현재 관장 무브셋에서 실전 이득을 보장할 수 없으므로
    /// 공격기보다 낮게 둔다 — 회복·랭크업 전술을 지원할 때 별도 전략으로 승격하면 된다.
    private func expectedDamage(of move: MoveSpec, from attacker: BattleSide, to defender: BattleSide) -> Int {
        guard move.damageClass != .status, move.power > 0 else { return 0 }
        let effectiveness = BattleEngine.typeMultiplier(of: move, against: defender)
        guard effectiveness > 0 else { return 0 }

        let isPhysical = move.damageClass == .physical
        let offense: BattleStat = isPhysical ? .atk : .spa
        let guardStat: BattleStat = isPhysical ? .def : .spd
        var power = move.power
        var attack = StatStages.apply(attacker.rawStat(offense), stage: attacker.stage(offense))
        if let ability = attacker.ability {
            attack = ability.adjustedAttack(attack, isPhysical: isPhysical, status: attacker.status)
            power = ability.adjustedPower(power, move: move)
        }
        if isPhysical, attacker.status == .burn, attacker.ability != .guts { attack /= 2 }
        var defense = StatStages.apply(defender.rawStat(guardStat), stage: defender.stage(guardStat))
        if let ability = defender.ability {
            defense = ability.adjustedDefense(defense, isPhysical: isPhysical, status: defender.status)
        }

        var damage = BattleEngine.baseDamage(level: attacker.snapshot.level, power: power,
                                             attack: attack, defense: defense) + 2
        if attacker.snapshot.types.contains(move.type) { damage = damage * 3 / 2 }
        damage = TypeChart.apply(damage, of: move.type, against: defender.snapshot.types)
        if let ability = defender.ability {
            damage = ability.adjustedDamage(damage, moveType: move.type, effectiveness: effectiveness)
        }
        let accuracy = min(100, max(0, BattleEngine.hitChance(of: move, attacker: attacker, defender: defender) ?? 100))
        return max(0, damage) * accuracy
    }

    /// 상대 공격 1회만 해상 — 내가 교체에 턴을 썼을 때 상대 몫이다.
    /// 이벤트는 `applyAttack` 이 만든다(엔진 좌변이 나 = `.a`, CPU = `.b`).
    private mutating func opponentAttacksAlone() {
        guard opponents[opponentActive].isAlive, mine[myActive].isAlive else { return }
        BattleEngine.beginTurn(&mine[myActive]); BattleEngine.beginTurn(&opponents[opponentActive])
        let (move, moveIndex) = cpuMoveChoice()
        if moveIndex >= 0 { opponents[opponentActive].pp[moveIndex] -= 1 }
        events += BattleEngine.applyAttack(attacker: &opponents[opponentActive], defender: &mine[myActive],
                                           attackerActor: .b, defenderActor: .a, move: move, rng: &rng)
        // 교체로 넘긴 턴도 턴이다 — 잔뎀은 그대로 들어간다.
        events += BattleEngine.endOfTurnResidual(&mine[myActive], actor: .a)
        events += BattleEngine.endOfTurnResidual(&opponents[opponentActive], actor: .b)
    }

    /// 내가 공격 대신 다른 행동(볼 던지기)에 턴을 쓴다 — **교체와 같은 대가다.** 상대만 한 번
    /// 움직이고 잔뎀도 들어간다. 이 대가가 없으면 실패해도 잃는 것이 없어 볼을 마를 때까지
    /// 던지는 것이 언제나 최선이 된다.
    mutating func spendTurnWithoutAttacking() -> Bool {
        guard result == nil, mine[myActive].isAlive, opponents[opponentActive].isAlive else { return false }
        events.append(.turn(turn))
        opponentAttacksAlone()
        turn += 1
        advanceFainted()
        return true
    }

    /// 잡힌 상대를 전투에서 뺀다 — **쓰러진 것과 같은 자리**(`advanceFainted`)를 지나 다음 상대로
    /// 넘어가거나 승부를 적는다. 배열에서 지우지 않는 이유는 인덱스가 이벤트 스트림(`sendOut`)의
    /// 좌표이기 때문이다 — 지우면 재생기가 엉뚱한 개체를 그린다.
    mutating func retireOpponent() {
        guard result == nil else { return }
        opponents[opponentActive].hp = 0
        advanceFainted()
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

    /// 손가락흔들기처럼 버튼에 표시된 기술과 실제 발동 기술이 다른 모드용 턴 해상.
    /// PP는 원래 슬롯에서 소비하지만 데미지·상태·연출은 호출된 기술 스펙을 그대로 사용한다.
    mutating func useResolvedMoves(_ myMove: MoveSpec, cpuMove: MoveSpec, slotIndex: Int = 0) -> Bool {
        guard result == nil, mine[myActive].isAlive, opponents[opponentActive].isAlive,
              mine[myActive].canUse(moveAt: slotIndex), opponents[opponentActive].canUse(moveAt: slotIndex)
        else { return false }
        mine[myActive].pp[slotIndex] -= 1
        opponents[opponentActive].pp[slotIndex] -= 1
        events += BattleEngine.resolveTurn(a: &mine[myActive], b: &opponents[opponentActive],
                                           moveA: myMove, moveB: cpuMove, turn: turn, rng: &rng)
        turn += 1
        advanceFainted()
        return true
    }

    /// 쓰러진 활성 슬롯을 다음 개체로 넘기고, 넘길 데가 없으면 승부를 적는다.
    ///
    /// **전멸 판정을 양쪽 다 먼저 본다.** 예전엔 상대 전멸을 확인한 자리에서 `result = true; return`
    /// 했는데 내 쪽도 같은 턴에 전멸할 수 있다 — `resolveTurn` 은 두 공격이 끝난 뒤 잔뎀을 넣으므로
    /// "내 공격이 상대 마지막을 눕히고 잔뎀이 내 마지막을 눕히는" 턴이 실제로 존재하고, 그 턴이
    /// 승리로 접혀 체육관 배지까지 나갔다. 1v1(`resolveIfReady`)은 같은 상황을 무승부로 본다 —
    /// 두 엔진이 같은 규칙을 봐야 한다.
    private mutating func advanceFainted() {
        let myTeamWiped = !mine.contains(where: \.isAlive)
        let opponentTeamWiped = !opponents.contains(where: \.isAlive)
        if myTeamWiped || opponentTeamWiped {
            result = myTeamWiped ? (opponentTeamWiped ? .draw : .loss) : .win
            return
        }
        // 자동 출전도 스트림에 남는다 — 재생기가 이 이벤트를 보고서야 표시 상태를 새 개체로
        // 갈아탄다. 없으면 기절 턴에 새로 나온 만피 개체를 이전 개체의 HP 로 깎아 그린다.
        if !opponents[opponentActive].isAlive,
           let next = opponents.indices.first(where: { opponents[$0].isAlive }) {
            opponentActive = next
            events.append(.sendOut(.b, teamIndex: next))
        }
        if !mine[myActive].isAlive,
           let next = mine.indices.first(where: { mine[$0].isAlive }) {
            myActive = next
            events.append(.sendOut(.a, teamIndex: next))
        }
    }
}
