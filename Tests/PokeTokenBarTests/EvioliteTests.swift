import XCTest
@testable import PokeTokenBar

/// 진화의휘석 — **아직 진화할 수 있는** 개체의 방어·특수방어를 1.5 배로 만든다.
///
/// 조건이 스냅샷에 실린다는 점이 다른 물건과 갈리는 곳이다: 종 전용 물건은 종 번호만 보면 되지만
/// (`restrictedSpecies`), 이쪽은 "이 개체가 더 진화하나" 를 진화 라인에서 알아내 와이어에 실어야
/// 한다(`BattleSnapshot.canStillEvolve`). 값이 없으면 물건은 아무 일도 하지 않는다.
final class EvioliteTests: XCTestCase {

    private func side(canStillEvolve: Bool?) -> BattleSide {
        BattleSide(BattleSnapshot(speciesID: 133, name: "테스트", trainer: nil, level: 50,
                                  nature: nil, isShiny: false, types: [.normal],
                                  base: BattleStats(hp: 200, atk: 100, def: 100,
                                                    spa: 100, spd: 100, spe: 100),
                                  heldItem: .eviolite, weightHectograms: 100,
                                  canStillEvolve: canStillEvolve))
    }

    func testTheEvioliteRidesTheHeldItemAxis() {
        XCTAssertEqual(ItemKind.eviolite.bagUse, .heldItem)
        XCTAssertEqual(ItemKind.eviolite.heldBattleEffect, .eviolite)
        XCTAssertNil(ItemKind.eviolite.evolutionRule)
        XCTAssertNotNil(ItemKind.eviolite.shopPrice)
        XCTAssertEqual(ItemKind.eviolite.spriteName, "eviolite")
        XCTAssertTrue(MultiplayerValidation.validHeldItem(.eviolite))
        XCTAssertEqual(L().itemName(.eviolite), "진화의휘석")
        XCTAssertFalse(L().itemDescription(.eviolite).isEmpty)
        XCTAssertFalse(L().heldItemEffectHint(.eviolite).isEmpty)
    }

    /// 아직 진화할 수 있는 개체에게만 효과가 붙는다 — 방어·특수방어 둘 다다.
    func testTheEvioliteOnlyWorksWhileTheHolderCanStillEvolve() {
        let young = side(canStillEvolve: true)
        XCTAssertEqual(young.heldEffect, .eviolite)
        XCTAssertEqual(young.heldEffect?.statScale(.def)?.numerator, 3)
        XCTAssertEqual(young.heldEffect?.statScale(.def)?.denominator, 2)
        XCTAssertEqual(young.heldEffect?.statScale(.spd)?.numerator, 3)
        XCTAssertNil(young.heldEffect?.statScale(.atk), "공격까지 올렸다")

        // 다 자란 개체와 **모르는** 개체(값이 없는 스냅샷)에는 효과가 없다.
        XCTAssertNil(side(canStillEvolve: false).heldEffect, "진화를 마친 개체에 휘석이 붙었다")
        XCTAssertNil(side(canStillEvolve: nil).heldEffect, "진화 여부를 모르는데 휘석이 붙었다")
    }

    /// 실제 데미지가 줄어든다 — 축만 답하고 엔진이 안 물으면 아무 일도 일어나지 않는다.
    func testTheEvioliteActuallySoftensIncomingHits() {
        var move = MoveSpec(id: 33, names: ["ko": "몸통박치기"], type: .normal, power: 80,
                            damageClass: .physical, accuracy: nil, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0; move.targetsUser = false

        var attacker = BattleSide(BattleSnapshot(speciesID: 25, name: "공격", trainer: nil,
                                                 level: 50, nature: nil, isShiny: false,
                                                 types: [.normal],
                                                 base: BattleStats(hp: 200, atk: 120, def: 100,
                                                                   spa: 100, spd: 100, spe: 100),
                                                 heldItem: nil, weightHectograms: 100))
        var young = side(canStillEvolve: true)
        var grown = side(canStillEvolve: false)
        var rngA = SplitMix64(seed: 7)
        var rngB = SplitMix64(seed: 7)
        _ = BattleEngine.applyHit(attacker: &attacker, defender: &young, attackerActor: .a,
                                  defenderActor: .b, move: move, rng: &rngA)
        var second = attacker
        _ = BattleEngine.applyHit(attacker: &second, defender: &grown, attackerActor: .a,
                                  defenderActor: .b, move: move, rng: &rngB)
        XCTAssertGreaterThan(young.hp, grown.hp, "휘석을 쥔 쪽이 더 깎였다")
    }

    /// 진화 라인이 "더 진화하나" 에 답한다 — 스냅샷을 만드는 자리가 손으로 종 번호를 세지 않는다.
    func testTheEvolutionLineAnswersWhetherASpeciesCanStillEvolve() {
        let line = EvoLine(baseID: 172,
                           tree: EvoNode(speciesID: 172,
                                         children: [EvoNode(speciesID: 25,
                                                            children: [EvoNode(speciesID: 26,
                                                                               children: [])])]),
                           rarity: .common, names: [:])
        XCTAssertTrue(line.canEvolveFurther(from: 172))
        XCTAssertTrue(line.canEvolveFurther(from: 25))
        XCTAssertFalse(line.canEvolveFurther(from: 26), "마지막 형태가 더 진화한다고 답했다")
        XCTAssertFalse(line.canEvolveFurther(from: 999), "라인에 없는 종에 답했다")
    }
}
