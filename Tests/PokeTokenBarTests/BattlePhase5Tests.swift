import XCTest
@testable import PokeTokenBar

final class BattlePhase5Tests: XCTestCase {
    private func snapshot(types: [PokemonType] = [.normal], speed: Int = 100) -> BattleSnapshot {
        BattleSnapshot(speciesID: 1, name: "Test", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: speed))
    }

    private func attack(id: Int = 1, power: Int = 80) -> MoveSpec {
        MoveSpec(id: id, names: ["en": "Test"], type: .normal, power: power,
                 damageClass: .physical, accuracy: nil, pp: 20)
    }

    func testDrainHealsFromDamageAndClampsAtMaximumHP() {
        var attacker = BattleSide(snapshot())
        attacker.hp = attacker.stats.hp - 1
        var defender = BattleSide(snapshot())
        var move = attack(); move.drain = 50
        var rng = SplitMix64(seed: 1)

        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: move, rng: &rng)

        XCTAssertEqual(attacker.hp, attacker.stats.hp, "drain must not exceed maximum HP")
        XCTAssertTrue(events.contains { if case .heal(.a, amount: 1, cause: .drain) = $0 { return true }; return false })
    }

    func testRecoilCanFaintTheAttacker() {
        var attacker = BattleSide(snapshot()); attacker.hp = 1
        var defender = BattleSide(snapshot())
        var move = attack(); move.drain = -100
        var rng = SplitMix64(seed: 1)

        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: move, rng: &rng)

        XCTAssertEqual(attacker.hp, 0)
        XCTAssertTrue(events.contains { if case .damage(.a, _, cause: .recoil) = $0 { return true }; return false })
        XCTAssertTrue(events.contains(.faint(.a)))
    }

    func testFixedMultiHitReportsEachHitInItsOutcomeAndOneAggregateDamageEvent() {
        var attacker = BattleSide(snapshot()), defender = BattleSide(snapshot())
        var move = attack(); move.minHits = 2; move.maxHits = 2
        var rng = SplitMix64(seed: 5)
        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: move, rng: &rng)

        XCTAssertTrue(events.contains(.multiHit(.a, hits: 2)))
        XCTAssertEqual(events.filter { if case .damage(.b, _, .move) = $0 { return true }; return false }.count, 1)
    }

    func testFlinchStopsOnlyTheLaterActorAndClearsAtNextTurn() {
        var a = BattleSide(snapshot(speed: 10)), b = BattleSide(snapshot(speed: 200))
        var flinching = attack(); flinching.flinchChance = 100; flinching.priority = 1
        let ordinary = attack(id: 2)
        var rng = SplitMix64(seed: 2)

        let first = BattleEngine.resolveTurn(a: &a, b: &b, moveA: flinching, moveB: ordinary,
                                             turn: 1, rng: &rng)
        XCTAssertTrue(first.contains(.cant(.b, .flinch)))
        XCTAssertTrue(b.flinched, "flinch remains volatile until the next turn begins")

        let second = BattleEngine.resolveTurn(a: &a, b: &b, moveA: ordinary, moveB: ordinary,
                                              turn: 2, rng: &rng)
        XCTAssertTrue(second.contains(.move(.b, moveID: 2)))
        XCTAssertFalse(b.flinched)
    }

    func testNewMoveFieldsAreValidatedAtTheMultiplayerBoundary() {
        var valid = attack(); valid.drain = -100; valid.flinchChance = 100; valid.minHits = 2; valid.maxHits = 5
        XCTAssertTrue(MultiplayerValidation.validMoves([valid]))
        valid.minHits = 6; valid.maxHits = 2
        XCTAssertFalse(MultiplayerValidation.validMoves([valid]))
    }
}
