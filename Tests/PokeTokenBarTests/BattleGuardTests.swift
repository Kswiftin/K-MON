import XCTest
@testable import PokeTokenBar

/// 방어 부류(방어·잠깨기·니들가드·더스트슈트·불꽃의벽·실크트랩·블로킹·맥스가드).
///
/// 여덟 기술이 쇼다운에서는 각자 다른 volatile 키지만, **막는 일은 똑같다** — 갈리는 것은 막은
/// 뒤 상대에게 무엇을 하나뿐이고 그건 접촉 판정이 있어야 한다(아직 없다). 그래서 엔진은 하나로
/// 구현하고 어느 기술이 부르는지는 데이터가 답한다.
final class BattleGuardTests: XCTestCase {

    private func side(_ types: [PokemonType] = [.normal], speed: Int = 100, hp: Int? = nil) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: types,
                                            base: BattleStats(hp: 100, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: speed),
                                            weightHectograms: 100))
        if let hp { out.hp = hp }
        return out
    }

    private func spec(_ id: Int, power: Int = 60, damageClass: MoveDamageClass = .physical,
                      accuracy: Int? = 100, priority: Int? = nil,
                      ailment: String = "none", targetsUser: Bool = false) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "기술"], type: .normal, power: power,
                            damageClass: damageClass, accuracy: accuracy, pp: 10)
        move.ailment = ailment; move.ailmentChance = ailment == "none" ? 0 : 100
        move.statChanges = []; move.statChance = 0
        move.targetsUser = targetsUser
        move.priority = priority
        return move
    }

    /// 방어기를 부르는 기술 id — 데이터에서 되짚는다.
    private var guardMoveIDs: [Int] {
        ShowdownMoveData.effects.keys.sorted().filter { BattleGuard.called(byMoveID: $0) }
    }

    /// 여덟 키가 전부 실제 기술로 이어진다 — 열거만 하고 부르는 기술이 없으면 죽은 코드다.
    func testEveryGuardKeyHasAMoveThatCallsIt() {
        var callers: [String: [Int]] = [:]
        for (id, effect) in ShowdownMoveData.effects {
            guard let key = effect.volatileStatus, BattleGuard.showdownKeys.contains(key) else { continue }
            callers[key, default: []].append(id)
        }
        XCTAssertEqual(Set(callers.keys), BattleGuard.showdownKeys,
                       "엔진이 아는 키인데 부르는 기술이 데이터에 없다")
        // 방어(182)·잠깨기(197)가 같은 `protect` 키를 쓴다 — 키 하나에 기술 여럿이 정상이다.
        XCTAssertEqual(callers["protect"]?.sorted(), [182, 197])
    }

    /// 방어기는 무브셋 후보를 통과해야 한다 — 막히면 아무도 배우지 못해 코드가 죽는다.
    func testGuardMovesAreOfferedInMovesets() throws {
        XCTAssertFalse(guardMoveIDs.isEmpty)
        for id in guardMoveIDs {
            let move = spec(id, power: 0, damageClass: .status, accuracy: nil, targetsUser: true)
            XCTAssertTrue(move.hasModeledStatusEffect, "방어기 \(id) 가 무브셋 후보에서 빠진다")
            XCTAssertTrue(VariableDamage.isUsable(move))
        }
    }

    /// 지킨 턴에는 데미지도 상태도 들어오지 않는다.
    func testAGuardedSideTakesNoDamageAndNoStatus() {
        var attacker = side(), defender = side(hp: 9_999)
        defender.isGuarding = true
        var field = BattleField()
        var rng = SplitMix64(seed: 3)
        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: spec(33, ailment: "paralysis"),
                                              field: &field, rng: &rng)
        XCTAssertTrue(events.contains(.guardBlocked(.b)))
        XCTAssertEqual(defender.hp, 9_999, "막은 턴에는 한 점도 안 깎인다")
        XCTAssertNil(defender.status, "상태도 안 걸린다")
        XCTAssertTrue(attacker.lastMoveFailed, "막힌 것은 실패다 — 분함의발구르기가 이 값을 본다")
    }

    /// **자기에게 거는 기술은 막히지 않는다** — 방어와 나 사이에는 아무것도 없다.
    /// 대상을 안 보고 막는 오구현은 상대가 방어만 눌러도 내 랭크업을 봉쇄한다.
    func testAGuardDoesNotBlockTheAttackersOwnBuff() {
        var attacker = side(), defender = side(hp: 9_999)
        defender.isGuarding = true
        var swordsDance = spec(14, power: 0, damageClass: .status, accuracy: nil, targetsUser: true)
        swordsDance.statChanges = [StatChange(stat: .atk, change: 2)]
        swordsDance.statChance = 0
        var field = BattleField()
        var rng = SplitMix64(seed: 3)
        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: swordsDance, field: &field, rng: &rng)
        XCTAssertFalse(events.contains(.guardBlocked(.b)))
        XCTAssertEqual(attacker.stage(.atk), 2)
    }

    /// 페인트 부류는 방어를 뚫는다 — 데이터가 예외로 답한다.
    func testFeintGoesThroughAGuard() {
        XCTAssertTrue(BattleGuard.isIgnored(byMoveID: 364), "페인트는 방어를 뚫는다")
        XCTAssertFalse(BattleGuard.isIgnored(byMoveID: 33), "몸통박치기는 막힌다")

        var attacker = side(), defender = side(hp: 9_999)
        defender.isGuarding = true
        var field = BattleField()
        var rng = SplitMix64(seed: 3)
        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: spec(364, power: 30), field: &field, rng: &rng)
        XCTAssertFalse(events.contains(.guardBlocked(.b)))
        XCTAssertLessThan(defender.hp, 9_999, "뚫는 기술은 데미지가 들어간다")
    }

    /// 방어기를 쓰면 이번 턴만 지킨다 — 턴 머리에서 비워지므로 다음 턴 공격은 그대로 들어온다.
    func testAGuardLastsOnlyForItsOwnTurn() throws {
        let protect = spec(try XCTUnwrap(guardMoveIDs.first { $0 == 182 }),
                           power: 0, damageClass: .status, accuracy: nil,
                           priority: 4, targetsUser: true)
        var a = side(speed: 50, hp: 9_999), b = side(speed: 100, hp: 9_999)
        var field = BattleField()
        var rng = SplitMix64(seed: 5)
        let first = BattleEngine.resolveTurn(a: &a, b: &b, moveA: protect, moveB: spec(33),
                                             turn: 1, field: &field, rng: &rng)
        XCTAssertTrue(first.contains(.guardUp(.a)), "우선도 +4 라 느려도 먼저 지킨다")
        XCTAssertTrue(first.contains(.guardBlocked(.a)))
        XCTAssertEqual(a.hp, 9_999)

        let second = BattleEngine.resolveTurn(a: &a, b: &b, moveA: spec(33), moveB: spec(33),
                                              turn: 2, field: &field, rng: &rng)
        XCTAssertFalse(second.contains(.guardBlocked(.a)), "다음 턴에는 지키고 있지 않다")
        XCTAssertLessThan(a.hp, 9_999)
        XCTAssertFalse(a.isGuarding)
    }

    /// 연속으로 쓰면 실패하기 쉬워진다. **첫 방어는 rng 를 뽑지 않는다** — 뽑으면 방어를 넣은
    /// 뒤 모든 판정이 한 칸 밀려 같은 seed 의 예전 판이 재현되지 않는다.
    func testAGuardGetsHarderToKeepUpAndTheFirstOneRollsNothing() throws {
        let protect = spec(182, power: 0, damageClass: .status, accuracy: nil, targetsUser: true)
        var user = side(), other = side(hp: 9_999)
        var field = BattleField()

        var rng = SplitMix64(seed: 11)
        var untouched = SplitMix64(seed: 11)
        _ = BattleEngine.applyAttack(attacker: &user, defender: &other, attackerActor: .a,
                                     defenderActor: .b, move: protect, field: &field, rng: &rng)
        XCTAssertTrue(user.isGuarding)
        XCTAssertEqual(user.guardStreak, 1)
        XCTAssertEqual(rng.next(), untouched.next(), "첫 방어는 난수를 소비하지 않는다")

        // 두 번째부터는 1/3 이다 — seed 를 바꿔 가며 성공·실패가 **둘 다** 나오는 것을 본다.
        var outcomes = Set<Bool>()
        for seed in UInt64(0)..<40 {
            var repeated = side(), target = side(hp: 9_999)
            repeated.guardStreak = 1
            var seedRng = SplitMix64(seed: seed)
            _ = BattleEngine.applyAttack(attacker: &repeated, defender: &target, attackerActor: .a,
                                         defenderActor: .b, move: protect, field: &field, rng: &seedRng)
            outcomes.insert(repeated.isGuarding)
        }
        XCTAssertEqual(outcomes, [true, false], "연속 방어가 늘 성공하거나 늘 실패하면 확률이 없다")
    }

    /// 실패한 방어는 연속을 끊는다 — 안 끊으면 한 번 실패한 뒤로 확률이 영영 회복되지 않는다.
    func testAFailedGuardResetsTheStreak() {
        let protect = spec(182, power: 0, damageClass: .status, accuracy: nil, targetsUser: true)
        var field = BattleField()
        for seed in UInt64(0)..<40 {
            var user = side(), other = side(hp: 9_999)
            user.guardStreak = 2
            var rng = SplitMix64(seed: seed)
            _ = BattleEngine.applyAttack(attacker: &user, defender: &other, attackerActor: .a,
                                         defenderActor: .b, move: protect, field: &field, rng: &rng)
            if user.isGuarding {
                XCTAssertEqual(user.guardStreak, 3)
            } else {
                XCTAssertEqual(user.guardStreak, 0, "실패했으면 처음부터다")
                XCTAssertTrue(user.lastMoveFailed)
            }
        }
    }

    /// 광역기는 대상마다 `applyHit` 을 직접 부르는 모드가 있다(웨이브 런) — 막는 판정이
    /// `applyAttack` 에만 있으면 그 모드의 광역기가 방어를 통째로 통과한다.
    func testAGuardAlsoBlocksTheSpreadPathThatSkipsApplyAttack() {
        var attacker = side(), guarded = side(hp: 9_999), exposed = side(hp: 9_999)
        guarded.isGuarding = true
        var rng = SplitMix64(seed: 3)
        let blocked = BattleEngine.applyHit(attacker: &attacker, defender: &guarded,
                                            attackerActor: .a, defenderActor: .b,
                                            move: spec(33), rng: &rng)
        XCTAssertEqual(blocked, [.guardBlocked(.b)])
        XCTAssertEqual(guarded.hp, 9_999)

        // 같은 광역기의 다른 대상은 그대로 맞는다 — 한 쪽의 방어가 기술 전체를 끄지 않는다.
        _ = BattleEngine.applyHit(attacker: &attacker, defender: &exposed,
                                  attackerActor: .a, defenderActor: .b,
                                  move: spec(33), rng: &rng)
        XCTAssertLessThan(exposed.hp, 9_999)
    }

    /// 사이에 다른 기술을 끼우면 연속이 끊긴다 — 그 다음 방어는 확률 벌점 없이 성공한다.
    func testAnotherMoveInBetweenClearsTheStreak() {
        var user = side(), other = side(hp: 9_999)
        user.guardStreak = 3
        var field = BattleField()
        var rng = SplitMix64(seed: 9)
        _ = BattleEngine.applyAttack(attacker: &user, defender: &other, attackerActor: .a,
                                     defenderActor: .b, move: spec(33), field: &field, rng: &rng)
        XCTAssertEqual(user.guardStreak, 0)

        var untouched = SplitMix64(seed: 21)
        var afterRng = SplitMix64(seed: 21)
        _ = BattleEngine.applyAttack(attacker: &user, defender: &other, attackerActor: .a,
                                     defenderActor: .b,
                                     move: spec(182, power: 0, damageClass: .status,
                                                accuracy: nil, targetsUser: true),
                                     field: &field, rng: &afterRng)
        XCTAssertTrue(user.isGuarding, "끊긴 뒤의 첫 방어는 확정 성공이다")
        XCTAssertEqual(afterRng.next(), untouched.next(), "그래서 난수도 안 뽑는다")
    }
}
