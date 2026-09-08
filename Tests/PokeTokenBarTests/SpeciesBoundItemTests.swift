import XCTest
@testable import PokeTokenBar

/// 특정 종에게만 일하는 물건 10종 — 전기구슬(피카츄)·굵은뼈(탕구리 계열)·금속파우더·
/// 스피드파우더(메타몽)·럭키펀치(럭키)·대파(파오리 계열)·마음의물방울(라티 남매)·보옥 셋
/// (디아루가·펄기아·기라티나).
///
/// 앞선 물건들과 갈리는 점은 **누가 쥐었는지를 묻는다**는 것이다. 그래서 이 배치의 잠금 하나는
/// 축이 아니라 게이트다: 엉뚱한 종이 쥐면 `BattleSide.heldEffect` 가 통째로 `nil` 이라, 배율을
/// 곱하는 자리마다 종을 다시 묻지 않는다(한 자리만 빠뜨리면 그 배율만 아무에게나 붙는다).
@MainActor
final class SpeciesBoundItemTests: XCTestCase {

    private static let bound: [ItemKind] = [
        .lightBall, .thickClub, .metalPowder, .quickPowder, .luckyPunch,
        .stick, .soulDew, .adamantOrb, .lustrousOrb, .griseousOrb
    ]

    private func side(species: Int, types: [PokemonType] = [.normal],
                      held: ItemKind? = nil) -> BattleSide {
        BattleSide(BattleSnapshot(speciesID: species, name: "테스트", trainer: nil, level: 50,
                                  nature: nil, isShiny: false, types: types,
                                  base: BattleStats(hp: 100, atk: 100, def: 100,
                                                    spa: 100, spd: 100, spe: 100),
                                  moves: nil, heldItem: held, weightHectograms: 100))
    }

    private func attackMove(_ id: Int = 33, type: PokemonType = .normal, power: Int = 60,
                            damageClass: MoveDamageClass = .physical) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "공격\(id)"], type: type, power: power,
                            damageClass: damageClass, accuracy: 100, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = false
        return move
    }

    private func dealt(_ events: [BattleEvent]) -> Int {
        events.reduce(0) {
            if case .damage(.b, let amount, .move) = $1 { return $0 + amount }
            return $0
        }
    }

    private func damage(_ move: MoveSpec, attacker: BattleSide, defender: BattleSide,
                        seed: UInt64 = 11) -> Int {
        var a = attacker, b = defender
        var rng = SplitMix64(seed: seed)
        return dealt(BattleEngine.applyHit(attacker: &a, defender: &b, attackerActor: .a,
                                           defenderActor: .b, move: move, rng: &rng))
    }

    // MARK: - 아이템 축과 게이트

    func testTheSpeciesBoundItemsRideTheHeldItemAxis() {
        for kind in Self.bound {
            XCTAssertEqual(kind.bagUse, .heldItem, kind.rawValue)
            XCTAssertNotNil(kind.heldBattleEffect, kind.rawValue)
            XCTAssertNil(kind.evolutionRule, kind.rawValue)
            XCTAssertNotNil(kind.shopPrice, kind.rawValue)
            XCTAssertNotNil(kind.spriteName, kind.rawValue)
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "피어의 \(kind.rawValue) 가 반려된다")
            XCTAssertFalse(L().itemName(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().itemDescription(kind).isEmpty, kind.rawValue)
            XCTAssertNotNil(kind.heldBattleEffect?.restrictedSpecies, "\(kind.rawValue) 에 종 제한이 없다")
        }
        XCTAssertEqual(ItemKind.stick.spriteName, "stick")
        XCTAssertEqual(L().itemName(.lightBall), "전기구슬")
    }

    /// **게이트는 한 자리다.** 엉뚱한 종이 쥐면 효과 자체가 없다 — 물건은 그대로 붙어 있다.
    func testAnItemBoundToAnotherSpeciesDoesNothing() {
        XCTAssertNil(side(species: 1, held: .lightBall).heldEffect)
        XCTAssertNotNil(side(species: 25, held: .lightBall).heldEffect)
        XCTAssertNil(side(species: 25, held: .thickClub).heldEffect)
        XCTAssertNotNil(side(species: 104, held: .thickClub).heldEffect)
        XCTAssertNotNil(side(species: 105, held: .thickClub).heldEffect)
    }

    // MARK: - 능력치를 곱하는 물건

    /// 전기구슬은 피카츄의 공격·특공을 두 배로 만든다.
    func testTheLightBallDoublesPikachusAttackAndSpecialAttack() {
        let physical = attackMove(type: .normal)
        let special = attackMove(94, type: .psychic, damageClass: .special)
        let target = side(species: 1)
        for move in [physical, special] {
            let bare = damage(move, attacker: side(species: 25), defender: target)
            let held = damage(move, attacker: side(species: 25, held: .lightBall), defender: target)
            XCTAssertGreaterThan(held, bare, "\(move.id) 가 안 올랐다")
        }
        // 다른 종이 쥐면 한 값도 다르지 않다.
        XCTAssertEqual(damage(physical, attacker: side(species: 1, held: .lightBall), defender: target),
                       damage(physical, attacker: side(species: 1), defender: target))
    }

    /// 금속파우더는 메타몽의 방어를, 스피드파우더는 스피드를 두 배로 만든다.
    func testTheDittoPowdersScaleDefenseAndSpeed() {
        let tackle = attackMove()
        let attacker = side(species: 1)
        let bare = damage(tackle, attacker: attacker, defender: side(species: 132))
        let guarded = damage(tackle, attacker: attacker,
                             defender: side(species: 132, held: .metalPowder))
        XCTAssertLessThan(guarded, bare, "금속파우더가 방어를 안 올렸다")

        XCTAssertEqual(side(species: 132, held: .quickPowder).effectiveSpeed,
                       side(species: 132).effectiveSpeed * 2)
        XCTAssertEqual(side(species: 1, held: .quickPowder).effectiveSpeed,
                       side(species: 1).effectiveSpeed, "종이 안 맞는데 스피드가 올랐다")
    }

    /// 마음의물방울은 라티 남매의 특공·특방을 1.5 배로 만든다.
    func testTheSoulDewScalesBothSpecialStats() {
        let special = attackMove(94, type: .psychic, damageClass: .special)
        let bare = damage(special, attacker: side(species: 380), defender: side(species: 1))
        let held = damage(special, attacker: side(species: 380, held: .soulDew),
                          defender: side(species: 1))
        XCTAssertGreaterThan(held, bare)

        let incoming = damage(special, attacker: side(species: 1), defender: side(species: 381))
        let guarded = damage(special, attacker: side(species: 1),
                             defender: side(species: 381, held: .soulDew))
        XCTAssertLessThan(guarded, incoming, "특방이 안 올랐다")
    }

    // MARK: - 급소를 올리는 물건

    /// 럭키펀치·대파는 급소 단계를 올린다 — 같은 seed 묶음에서 급소가 더 자주 난다.
    func testTheCritItemsRaiseTheCritStage() {
        XCTAssertEqual(HeldItemEffect.luckyPunch.bonusCritStages, 2)
        XCTAssertEqual(HeldItemEffect.leek.bonusCritStages, 2)
        let move = attackMove()
        func crits(_ attacker: BattleSide) -> Int {
            (0..<200).reduce(0) { count, seed in
                var a = attacker, b = side(species: 1)
                var rng = SplitMix64(seed: UInt64(seed))
                let events = BattleEngine.applyHit(attacker: &a, defender: &b, attackerActor: .a,
                                                   defenderActor: .b, move: move, rng: &rng)
                return count + (events.contains(.crit(.b)) ? 1 : 0)
            }
        }
        let bare = crits(side(species: 113))
        let held = crits(side(species: 113, held: .luckyPunch))
        XCTAssertGreaterThan(held, bare, "럭키펀치가 급소 단계를 안 올렸다(\(bare) → \(held))")
    }

    // MARK: - 보옥 셋

    /// 보옥은 **두 타입**을 올린다 — 한 타입만 답하는 축으로는 담을 수 없다.
    func testTheOrbsBoostTwoTypesEach() {
        let boosted: [ItemKind: (Int, [PokemonType])] = [
            .adamantOrb: (483, [.dragon, .steel]),
            .lustrousOrb: (484, [.dragon, .water]),
            .griseousOrb: (487, [.dragon, .ghost])
        ]
        // 맞는 쪽을 물 타입으로 둔다 — 노말이면 고스트 기술이 면역(0배)이라 배율을 잴 수 없다.
        let target = side(species: 1, types: [.water])
        for (kind, (species, types)) in boosted {
            XCTAssertEqual(kind.heldBattleEffect?.boostedMoveTypes, Set(types), kind.rawValue)
            for type in types {
                let move = attackMove(type: type, damageClass: .special)
                let bare = damage(move, attacker: side(species: species), defender: target)
                let held = damage(move, attacker: side(species: species, held: kind),
                                  defender: target)
                XCTAssertGreaterThan(held, bare, "\(kind.rawValue) 가 \(type.name) 를 안 올렸다")
            }
            // 올리지 않는 타입은 그대로다.
            let plain = attackMove(type: .normal)
            XCTAssertEqual(damage(plain, attacker: side(species: species, held: kind),
                                  defender: target),
                           damage(plain, attacker: side(species: species), defender: target),
                           kind.rawValue)
        }
    }
}
