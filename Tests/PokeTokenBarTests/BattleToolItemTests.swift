import XCTest
@testable import PokeTokenBar

/// 일반 배틀 도구 12종 — 힘의머리띠·박식안경·달인의띠·메트로놈(데미지 배율), 초점렌즈(급소),
/// 광각렌즈·포커스렌즈·반짝가루·무사태평향로(명중), 조개껍질방울·큰뿌리(때린 뒤 회복),
/// 검은오물(턴 끝 회복 또는 데미지).
///
/// 앞 배치들과 갈리는 점은 **조건이 물건 밖에 있다**는 것이다: 같은 도구가 기술 분류·상성·
/// 연속 사용 횟수·상대가 이미 움직였는지에 따라 다른 답을 낸다. 그래서 축이 값이 아니라 물음이고
/// (`outgoingDamageScale`·`accuracyScale`), 엔진은 그 물음 한 자리에서만 묻는다.
@MainActor
final class BattleToolItemTests: XCTestCase {

    private static let tools: [ItemKind] = [
        .muscleBand, .wiseGlasses, .expertBelt, .metronome, .scopeLens,
        .wideLens, .zoomLens, .brightPowder, .laxIncense,
        .shellBell, .blackSludge, .bigRoot
    ]

    private func side(types: [PokemonType] = [.normal], held: ItemKind? = nil,
                      hp: Int? = nil) -> BattleSide {
        var side = BattleSide(BattleSnapshot(speciesID: 1, name: "테스트", trainer: nil, level: 50,
                                             nature: nil, isShiny: false, types: types,
                                             base: BattleStats(hp: 100, atk: 100, def: 100,
                                                               spa: 100, spd: 100, spe: 100),
                                             moves: nil, heldItem: held, weightHectograms: 100))
        if let hp { side.hp = hp }
        return side
    }

    private func attackMove(_ id: Int = 33, type: PokemonType = .normal, power: Int = 60,
                            damageClass: MoveDamageClass = .physical,
                            accuracy: Int? = 100, drain: Int? = nil) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "공격\(id)"], type: type, power: power,
                            damageClass: damageClass, accuracy: accuracy, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = false
        move.drain = drain
        return move
    }

    private func dealt(_ events: [BattleEvent]) -> Int {
        events.reduce(0) {
            if case .damage(.b, let amount, .move) = $1 { return $0 + amount }
            return $0
        }
    }

    private func healed(_ events: [BattleEvent], _ actor: BattleActor) -> Int {
        events.reduce(0) {
            if case .heal(let who, let amount) = $1, who == actor { return $0 + amount }
            return $0
        }
    }

    private func hit(_ move: MoveSpec, attacker: BattleSide, defender: BattleSide,
                     seed: UInt64 = 11) -> [BattleEvent] {
        var a = attacker, b = defender
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyHit(attacker: &a, defender: &b, attackerActor: .a,
                                     defenderActor: .b, move: move, rng: &rng)
    }

    private func damage(_ move: MoveSpec, attacker: BattleSide, defender: BattleSide,
                        seed: UInt64 = 11) -> Int {
        dealt(hit(move, attacker: attacker, defender: defender, seed: seed))
    }

    // MARK: - 아이템 축

    func testTheBattleToolsRideTheHeldItemAxis() {
        for kind in Self.tools {
            XCTAssertEqual(kind.bagUse, .heldItem, kind.rawValue)
            XCTAssertNotNil(kind.heldBattleEffect, kind.rawValue)
            XCTAssertNil(kind.evolutionRule, kind.rawValue)
            XCTAssertNotNil(kind.shopPrice, kind.rawValue)
            XCTAssertNotNil(kind.spriteName, kind.rawValue)
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "피어의 \(kind.rawValue) 가 반려된다")
            XCTAssertFalse(L().itemName(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().itemDescription(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().heldItemEffectHint(kind).isEmpty, kind.rawValue)
            XCTAssertNil(kind.heldBattleEffect?.restrictedSpecies, "\(kind.rawValue) 에 종 제한이 생겼다")
        }
        XCTAssertEqual(ItemKind.muscleBand.spriteName, "muscle-band")
        XCTAssertEqual(L().itemName(.blackSludge), "검은오물")
        // 반짝가루와 무사태평향로는 같은 효과다 — 느림보꼬리·만복향로와 같은 자리다.
        XCTAssertEqual(ItemKind.brightPowder.heldBattleEffect,
                       ItemKind.laxIncense.heldBattleEffect)
    }

    // MARK: - 데미지 배율

    /// 힘의머리띠는 물리만, 박식안경은 특수만 올린다 — 분류가 안 맞으면 한 값도 다르지 않다.
    func testTheBandAndGlassesScaleOnlyTheirOwnDamageClass() {
        let physical = attackMove()
        let special = attackMove(94, type: .psychic, damageClass: .special)
        let target = side()
        for (kind, boosted, untouched) in [(ItemKind.muscleBand, physical, special),
                                           (ItemKind.wiseGlasses, special, physical)] {
            XCTAssertGreaterThan(damage(boosted, attacker: side(held: kind), defender: target),
                                 damage(boosted, attacker: side(), defender: target),
                                 kind.rawValue)
            XCTAssertEqual(damage(untouched, attacker: side(held: kind), defender: target),
                           damage(untouched, attacker: side(), defender: target),
                           "\(kind.rawValue) 가 다른 분류까지 올렸다")
        }
    }

    /// 달인의띠는 **효과가 굉장할 때만** 올린다.
    func testTheExpertBeltScalesOnlySuperEffectiveHits() {
        let fire = attackMove(52, type: .fire)
        let grass = side(types: [.grass])
        let normal = side()
        XCTAssertGreaterThan(damage(fire, attacker: side(held: .expertBelt), defender: grass),
                             damage(fire, attacker: side(), defender: grass))
        XCTAssertEqual(damage(fire, attacker: side(held: .expertBelt), defender: normal),
                       damage(fire, attacker: side(), defender: normal),
                       "효과가 보통인 히트까지 올랐다")
    }

    /// 메트로놈은 같은 기술을 이어 쓸수록 오르고 상한에서 멈춘다.
    func testTheMetronomeGrowsWithConsecutiveUsesAndStops() {
        let move = attackMove()
        let target = side()
        func damage(uses: Int, held: ItemKind?) -> Int {
            var attacker = side(held: held)
            attacker.consecutiveMoveUses = uses
            return self.damage(move, attacker: attacker, defender: target)
        }
        XCTAssertEqual(damage(uses: 1, held: .metronome), damage(uses: 1, held: nil),
                       "첫 사용부터 올랐다")
        XCTAssertGreaterThan(damage(uses: 2, held: .metronome), damage(uses: 1, held: .metronome))
        XCTAssertGreaterThan(damage(uses: 6, held: .metronome), damage(uses: 2, held: .metronome))
        XCTAssertEqual(damage(uses: 9, held: .metronome), damage(uses: 6, held: .metronome),
                       "상한을 넘어서도 계속 올랐다")
    }

    /// 초점렌즈는 급소 단계를 올린다 — 럭키펀치와 같은 축이고 크기만 다르다.
    func testTheScopeLensRaisesTheCritStage() {
        XCTAssertEqual(HeldItemEffect.scopeLens.bonusCritStages, 1)
        let move = attackMove()
        func crits(_ attacker: BattleSide) -> Int {
            (0..<200).reduce(0) { count, seed in
                let events = hit(move, attacker: attacker, defender: side(), seed: UInt64(seed))
                return count + (events.contains(.crit(.b)) ? 1 : 0)
            }
        }
        XCTAssertGreaterThan(crits(side(held: .scopeLens)), crits(side()),
                             "초점렌즈가 급소 단계를 안 올렸다")
    }

    // MARK: - 명중

    func testTheLensesRaiseAccuracyAndTheDustLowersIt() {
        let move = attackMove(accuracy: 70)
        let bare = BattleEngine.hitChance(of: move, attacker: side(), defender: side())
        XCTAssertEqual(bare, 70)

        XCTAssertGreaterThan(BattleEngine.hitChance(of: move, attacker: side(held: .wideLens),
                                                    defender: side()) ?? 0, 70)
        for dust in [ItemKind.brightPowder, .laxIncense] {
            XCTAssertLessThan(BattleEngine.hitChance(of: move, attacker: side(),
                                                     defender: side(held: dust)) ?? 100, 70,
                              dust.rawValue)
        }
    }

    /// 포커스렌즈는 **상대가 이번 턴 이미 움직였을 때만** 올린다.
    func testTheZoomLensOnlyHelpsWhenTheTargetAlreadyMoved() {
        let move = attackMove(accuracy: 70)
        var moved = side()
        moved.movedThisTurn = true
        XCTAssertEqual(BattleEngine.hitChance(of: move, attacker: side(held: .zoomLens),
                                              defender: side()), 70,
                       "상대가 아직 안 움직였는데 올랐다")
        XCTAssertGreaterThan(BattleEngine.hitChance(of: move, attacker: side(held: .zoomLens),
                                                    defender: moved) ?? 0, 70)
    }

    // MARK: - 때린 뒤 회복

    /// 조개껍질방울은 넣은 데미지의 일부를 회복한다 — 드레인 기술이 아니어도 회복한다.
    func testTheShellBellHealsAShareOfTheDamageDealt() {
        let move = attackMove()
        let hurt = side(held: .shellBell, hp: 40)
        let events = hit(move, attacker: hurt, defender: side())
        XCTAssertGreaterThan(healed(events, .a), 0)
        XCTAssertEqual(healed(hit(move, attacker: side(hp: 40), defender: side()), .a), 0,
                       "물건이 없는데 회복했다")
    }

    /// 큰뿌리는 드레인 기술의 **회복만** 키운다(데미지는 그대로다).
    func testTheBigRootScalesDrainHealingOnly() {
        let drain = attackMove(71, type: .grass, damageClass: .special, drain: 50)
        let target = side()
        let bare = hit(drain, attacker: side(hp: 30), defender: target)
        let rooted = hit(drain, attacker: side(held: .bigRoot, hp: 30), defender: target)
        XCTAssertGreaterThan(healed(rooted, .a), healed(bare, .a))
        XCTAssertEqual(dealt(rooted), dealt(bare), "큰뿌리가 데미지까지 바꿨다")
    }

    // MARK: - 턴 끝

    /// 검은오물은 독 타입에게는 회복, 나머지에게는 데미지다 — 한 물건이 두 답을 낸다.
    func testTheBlackSludgeHealsPoisonTypesAndHurtsEveryoneElse() {
        var poison = side(types: [.poison], held: .blackSludge, hp: 40)
        let healEvents = BattleEngine.endOfTurnResidual(&poison, actor: .a)
        XCTAssertGreaterThan(healed(healEvents, .a), 0)
        XCTAssertGreaterThan(poison.hp, 40)

        var other = side(held: .blackSludge, hp: 40)
        let hurtEvents = BattleEngine.endOfTurnResidual(&other, actor: .a)
        XCTAssertLessThan(other.hp, 40)
        XCTAssertTrue(hurtEvents.contains { event in
            if case .damage(.a, _, .heldItem) = event { return true }
            return false
        }, "검은오물 데미지 줄이 원인을 안 밝힌다")
    }

    /// 먹다남은음식도 같은 축으로 답한다 — 축을 만들며 옛 물건이 빠지면 회복이 조용히 사라진다.
    func testTheLeftoversAnswerTheSameResidualAxis() {
        var side = side(held: .leftovers, hp: 40)
        let events = BattleEngine.endOfTurnResidual(&side, actor: .a)
        XCTAssertGreaterThan(healed(events, .a), 0)
    }
}
