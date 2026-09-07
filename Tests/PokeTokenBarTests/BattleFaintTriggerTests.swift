import XCTest
@testable import PokeTokenBar

/// 기절 순간에 답하는 셋 — 인내(버틴다)·운명공동체(같이 쓰러진다)·원한(PP 를 앗는다).
///
/// 앞 배치들과 갈리는 점은 **판정 시점**이다: 턴 끝도 데미지 계산도 아니라 "이 기술로 쓰러졌다" 는
/// 순간이다. 그래서 검증도 그 순간에만 걸리는지(잔뎀으로 쓰러질 때는 안 걸리는지)를 함께 본다.
/// 어느 기술이 무엇을 부르는지는 여기서도 손 목록이 아니라 쇼다운 데이터가 답한다.
final class BattleFaintTriggerTests: XCTestCase {

    /// 인내(203)·운명공동체(194)·원한(288) — id 를 손으로 들지 않고 데이터로 되짚는다.
    private func moveID(callingVolatile volatileStatus: BattleVolatile) -> Int {
        ShowdownMoveData.effects.keys.sorted().first {
            BattleVolatile.called(byMoveID: $0) == volatileStatus
        } ?? -1
    }

    private func side(hp: Int? = nil, moves: [MoveSpec]? = nil) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: [.normal],
                                            base: BattleStats(hp: 100, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: 100),
                                            moves: moves,
                                            weightHectograms: 100))
        if let hp { out.hp = hp }
        return out
    }

    private func statusMove(_ id: Int) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "기술"], type: .normal, power: 0,
                            damageClass: .status, accuracy: nil, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = true
        return move
    }

    private func attackMove(_ id: Int = 33, power: Int = 60) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "공격"], type: .normal, power: power,
                            damageClass: .physical, accuracy: 100, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = false
        return move
    }

    @discardableResult
    private func use(_ move: MoveSpec, by attacker: inout BattleSide, actor: BattleActor = .a,
                     on defender: inout BattleSide, defenderActor: BattleActor = .b,
                     seed: UInt64 = 7) -> [BattleEvent] {
        var field = BattleField()
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                        attackerActor: actor, defenderActor: defenderActor,
                                        move: move, field: &field, rng: &rng)
    }

    // MARK: - 데이터

    /// 셋 다 쇼다운 데이터의 키로 이어진다 — 이어지지 않으면 아무 기술도 부르지 않는 죽은 효과다.
    func testTheDataNamesTheMoveThatCallsEachFaintTrigger() {
        XCTAssertEqual(BattleVolatile.called(byMoveID: 203), .endure)
        XCTAssertEqual(BattleVolatile.called(byMoveID: 194), .destinyBond)
        XCTAssertEqual(BattleVolatile.called(byMoveID: 288), .grudge)
        for volatileStatus in [BattleVolatile.endure, .destinyBond, .grudge] {
            XCTAssertTrue(volatileStatus.targetsUser, "\(volatileStatus) 는 자기에게 거는 상태다")
            XCTAssertNil(volatileStatus.healDivisor)
            XCTAssertNil(volatileStatus.residualDamage)
            XCTAssertEqual(volatileStatus.critStages, 0)
        }
    }

    /// 셋 다 무브셋 후보를 통과한다 — 막히면 아무도 배우지 못해 코드가 죽는다.
    func testTheThreeMovesAreOfferedInMovesets() {
        for volatileStatus in [BattleVolatile.endure, .destinyBond, .grudge] {
            let move = statusMove(moveID(callingVolatile: volatileStatus))
            XCTAssertTrue(move.hasModeledStatusEffect, "\(volatileStatus) 기술이 무브셋에서 빠진다")
            XCTAssertTrue(VariableDamage.isUsable(move))
        }
    }

    // MARK: - 인내

    /// 인내를 쓴 턴에는 치명타 한 방에도 HP 1 이 남는다.
    func testEnduringLeavesOneHitPointBehind() {
        var defender = side(hp: 5), attacker = side()
        use(statusMove(moveID(callingVolatile: .endure)), by: &defender, actor: .b,
            on: &attacker, defenderActor: .a)
        XCTAssertTrue(defender.has(.endure))

        let events = use(attackMove(), by: &attacker, on: &defender)
        XCTAssertEqual(defender.hp, 1, "인내는 남은 HP 를 하나 남긴다")
        XCTAssertTrue(defender.isAlive)
        XCTAssertTrue(events.contains(.volatileTriggered(.b, .endure)), "버틴 줄이 없다")
        XCTAssertFalse(events.contains(.faint(.b)))
    }

    /// HP 가 이미 1 이면 데미지가 0 이 된다 — 그래도 버틴 줄은 나간다(무반응 턴이 아니다).
    func testEnduringAtOneHitPointTakesNoDamageAtAll() {
        var defender = side(hp: 1), attacker = side()
        use(statusMove(moveID(callingVolatile: .endure)), by: &defender, actor: .b,
            on: &attacker, defenderActor: .a)
        let events = use(attackMove(), by: &attacker, on: &defender)
        XCTAssertEqual(defender.hp, 1)
        XCTAssertTrue(events.contains(.volatileTriggered(.b, .endure)))
    }

    /// 죽지 않을 데미지는 그대로 들어간다 — 인내가 데미지 감쇠가 되면 안 된다.
    func testEnduringDoesNotSoftenASurvivableHit() {
        var plain = side(hp: 99), enduring = side(hp: 99), attacker = side()
        use(statusMove(moveID(callingVolatile: .endure)), by: &enduring, actor: .b,
            on: &attacker, defenderActor: .a)
        var attackerA = attacker, attackerB = attacker
        use(attackMove(), by: &attackerA, on: &plain)
        use(attackMove(), by: &attackerB, on: &enduring)
        XCTAssertEqual(plain.hp, enduring.hp)
        XCTAssertLessThan(enduring.hp, 99, "데미지가 아예 안 들어갔다면 이 테스트는 아무것도 안 잠근다")
    }

    /// 인내는 **기술로만** 버틴다 — 독 잔뎀으로는 쓰러진다(본가·쇼다운과 같다).
    func testEnduringDoesNotSaveFromResidualDamage() {
        var owner = side(hp: 3), other = side()
        use(statusMove(moveID(callingVolatile: .endure)), by: &owner, actor: .b,
            on: &other, defenderActor: .a)
        owner.status = .poison
        let events = BattleEngine.endOfTurnResidual(&owner, actor: .b)
        XCTAssertEqual(owner.hp, 0)
        XCTAssertTrue(events.contains(.faint(.b)))
    }

    /// 인내는 한 턴짜리다 — 턴이 끝나면 풀리고 다음 턴의 한 방은 쓰러뜨린다.
    func testEnduringWearsOffAtTheEndOfTheTurn() {
        var defender = side(hp: 5), attacker = side()
        use(statusMove(moveID(callingVolatile: .endure)), by: &defender, actor: .b,
            on: &attacker, defenderActor: .a)
        let ended = BattleEngine.endOfTurnResidual(&defender, actor: .b)
        XCTAssertTrue(ended.contains(.volatileEnded(.b, .endure)))
        XCTAssertFalse(defender.has(.endure))

        use(attackMove(), by: &attacker, on: &defender)
        XCTAssertEqual(defender.hp, 0, "풀린 뒤에는 그냥 맞는다")
    }

    /// 인내는 방어기와 **같은 연속 카운터**를 쓴다 — 번갈아 눌러 벌점을 피할 수 없다.
    func testEnduringSharesTheGuardStreakWithProtect() {
        var user = side(), other = side()
        use(statusMove(moveID(callingVolatile: .endure)), by: &user, on: &other)
        XCTAssertEqual(user.guardStreak, 1, "인내 성공은 방어 연속을 센다")

        // 방어 뒤에 인내를 쓰면 확률이 1/3 로 떨어진다(카운터를 나누면 100% 로 성공한다).
        var successes = 0
        for seed in UInt64(0)..<90 {
            var protector = side(), dummy = side()
            use(statusMove(182), by: &protector, on: &dummy, seed: seed)
            XCTAssertEqual(protector.guardStreak, 1)
            var target = side()
            use(statusMove(moveID(callingVolatile: .endure)), by: &protector, on: &target, seed: seed)
            if protector.has(.endure) { successes += 1 }
        }
        XCTAssertGreaterThan(successes, 10)
        XCTAssertLessThan(successes, 60, "카운터를 공유하지 않으면 90번 다 성공한다")
    }

    // MARK: - 운명공동체

    /// 운명공동체를 걸어 둔 개체가 기술로 쓰러지면 쓰러뜨린 쪽도 같이 쓰러진다.
    func testDestinyBondTakesTheAttackerDownToo() {
        var defender = side(hp: 5), attacker = side()
        use(statusMove(moveID(callingVolatile: .destinyBond)), by: &defender, actor: .b,
            on: &attacker, defenderActor: .a)
        let events = use(attackMove(), by: &attacker, on: &defender)
        XCTAssertEqual(defender.hp, 0)
        XCTAssertEqual(attacker.hp, 0, "쓰러뜨린 쪽도 같이 쓰러진다")
        XCTAssertTrue(events.contains(.volatileTriggered(.b, .destinyBond)))
        // 맞은 쪽이 먼저, 때린 쪽이 뒤다(쇼다운 순서).
        let faints = events.compactMap { event -> BattleActor? in
            if case .faint(let actor) = event { return actor }
            return nil
        }
        XCTAssertEqual(faints, [.b, .a])
    }

    /// 잔뎀으로 쓰러지면 아무도 데려가지 않는다 — 기술로 쓰러진 순간만 훅이다.
    func testDestinyBondDoesNotTriggerOnResidualFaint() {
        var owner = side(hp: 3), other = side()
        use(statusMove(moveID(callingVolatile: .destinyBond)), by: &owner, actor: .b,
            on: &other, defenderActor: .a)
        owner.status = .poison
        let events = BattleEngine.endOfTurnResidual(&owner, actor: .b)
        XCTAssertEqual(owner.hp, 0)
        XCTAssertFalse(events.contains(.volatileTriggered(.b, .destinyBond)))
        XCTAssertTrue(other.isAlive)
    }

    /// 다음 기술을 내면 풀린다 — 안 풀면 한 번 건 운명공동체가 배틀 내내 산다.
    func testDestinyBondEndsWhenItsOwnerMovesAgain() {
        var owner = side(hp: 5), attacker = side()
        use(statusMove(moveID(callingVolatile: .destinyBond)), by: &owner, actor: .b,
            on: &attacker, defenderActor: .a)
        let ended = use(attackMove(), by: &owner, actor: .b, on: &attacker, defenderActor: .a)
        XCTAssertTrue(ended.contains(.volatileEnded(.b, .destinyBond)))
        XCTAssertFalse(owner.has(.destinyBond))

        use(attackMove(), by: &attacker, on: &owner)
        XCTAssertEqual(owner.hp, 0)
        XCTAssertTrue(attacker.isAlive, "풀린 뒤에는 데려가지 않는다")
    }

    /// 턴 끝만으로는 풀리지 않는다 — 느린 쪽이 건 운명공동체는 다음 턴의 선공까지 살아야 한다.
    func testDestinyBondSurvivesTheEndOfTheTurn() {
        var owner = side(hp: 5), other = side()
        use(statusMove(moveID(callingVolatile: .destinyBond)), by: &owner, actor: .b,
            on: &other, defenderActor: .a)
        _ = BattleEngine.endOfTurnResidual(&owner, actor: .b)
        XCTAssertTrue(owner.has(.destinyBond))
    }

    // MARK: - 원한

    /// 원한을 걸어 둔 개체가 쓰러지면 쓰러뜨린 **그 기술**의 PP 가 0 이 된다.
    func testGrudgeEmptiesThePPOfTheKillingMove() {
        let killer = attackMove(), spare = attackMove(34)
        var attacker = side(moves: [killer, spare])
        var defender = side(hp: 5)
        use(statusMove(moveID(callingVolatile: .grudge)), by: &defender, actor: .b,
            on: &attacker, defenderActor: .a)
        let events = use(killer, by: &attacker, on: &defender)
        XCTAssertEqual(defender.hp, 0)
        XCTAssertEqual(attacker.pp[0], 0, "쓰러뜨린 기술의 PP 가 남아 있다")
        XCTAssertEqual(attacker.pp[1], spare.pp, "다른 기술의 PP 는 그대로다")
        XCTAssertTrue(events.contains(.volatileTriggered(.b, .grudge)))
        XCTAssertTrue(attacker.isAlive, "원한은 데려가지 않는다")
    }

    /// 잔뎀으로 쓰러지면 PP 를 앗지 않는다.
    func testGrudgeDoesNotTriggerOnResidualFaint() {
        var owner = side(hp: 3), other = side(moves: [attackMove()])
        use(statusMove(moveID(callingVolatile: .grudge)), by: &owner, actor: .b,
            on: &other, defenderActor: .a)
        owner.status = .poison
        let events = BattleEngine.endOfTurnResidual(&owner, actor: .b)
        XCTAssertFalse(events.contains(.volatileTriggered(.b, .grudge)))
        XCTAssertEqual(other.pp[0], attackMove().pp)
    }

    /// 쓰러지지 않으면 아무 일도 없다 — 맞기만 해서 PP 가 빠지면 원한이 상시 효과가 된다.
    func testGrudgeDoesNothingWhileItsOwnerSurvives() {
        var attacker = side(moves: [attackMove()])
        var defender = side(hp: 99)
        use(statusMove(moveID(callingVolatile: .grudge)), by: &defender, actor: .b,
            on: &attacker, defenderActor: .a)
        use(attackMove(), by: &attacker, on: &defender)
        XCTAssertTrue(defender.isAlive)
        XCTAssertEqual(attacker.pp[0], attackMove().pp)
    }

    /// 운명공동체와 원한이 같이 붙어 있으면 둘 다 걸린다 — 한쪽이 다른 쪽을 가리지 않는다.
    ///
    /// **기술 두 개로는 이 상태를 만들 수 없다**(두 번째 기술을 내는 순간 첫 상태가 풀린다). 그래서
    /// 상태를 직접 붙여 훅만 잰다 — 훅이 둘을 순서대로 보는지가 이 테스트의 대상이다.
    func testBothBondAndGrudgeFireOnTheSameFaint() {
        let killer = attackMove()
        var attacker = side(moves: [killer])
        var defender = side(hp: 5)
        XCTAssertTrue(defender.start(.destinyBond))
        XCTAssertTrue(defender.start(.grudge))
        let events = use(killer, by: &attacker, on: &defender)
        XCTAssertEqual(attacker.hp, 0)
        XCTAssertEqual(attacker.pp[0], 0)
        XCTAssertTrue(events.contains(.volatileTriggered(.b, .destinyBond)))
        XCTAssertTrue(events.contains(.volatileTriggered(.b, .grudge)))
    }
}
