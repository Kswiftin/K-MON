import XCTest
@testable import PokeTokenBar

/// 맞으면·빗나가면·필드 위에서 랭크를 올리는 물건 10종 — 약점보험, 구근·충전지·눈덩이·
/// 빛이끼(타입별 반응), 허탕보험, 필드 씨앗 4.
///
/// 열 물건이 하는 일은 같다: **한 번 랭크를 올리고 사라진다**. 갈리는 것은 무엇이 방아쇠인가뿐이라
/// 축도 방아쇠별로 셋이고(맞은 히트·빗나간 내 기술·발밑의 필드), 올리는 랭크는 셋 다 같은 값
/// (`StatChange` 목록)으로 답한다 — 올리는 자리를 하나로 두려는 것이다.
final class ReactiveItemTests: XCTestCase {

    private static let items: [ItemKind] = [
        .weaknessPolicy, .absorbBulb, .cellBattery, .snowball, .luminousMoss, .blunderPolicy,
        .electricSeed, .grassySeed, .mistySeed, .psychicSeed
    ]

    private func side(types: [PokemonType] = [.normal], held: ItemKind? = nil) -> BattleSide {
        BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                  nature: nil, isShiny: false, types: types,
                                  base: BattleStats(hp: 200, atk: 100, def: 100,
                                                    spa: 100, spd: 100, spe: 100),
                                  heldItem: held, weightHectograms: 100))
    }

    private func attackMove(_ id: Int = 33, type: PokemonType = .normal, power: Int = 60,
                            accuracy: Int? = 100) -> MoveSpec {
        var out = MoveSpec(id: id, names: ["ko": "공격\(id)"], type: type, power: power,
                           damageClass: .special, accuracy: accuracy, pp: 10)
        out.ailment = "none"; out.ailmentChance = 0
        out.statChanges = []; out.statChance = 0; out.targetsUser = false
        return out
    }

    @discardableResult
    private func hit(_ move: MoveSpec, attacker: inout BattleSide, defender: inout BattleSide,
                     seed: UInt64 = 11) -> [BattleEvent] {
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyHit(attacker: &attacker, defender: &defender, attackerActor: .a,
                                     defenderActor: .b, move: move, rng: &rng)
    }

    // MARK: - 아이템 축

    func testTheReactiveItemsRideTheHeldItemAxis() {
        for kind in Self.items {
            XCTAssertEqual(kind.bagUse, .heldItem, kind.rawValue)
            XCTAssertNotNil(kind.heldBattleEffect, kind.rawValue)
            XCTAssertNil(kind.evolutionRule, kind.rawValue)
            XCTAssertNotNil(kind.shopPrice, kind.rawValue)
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "피어의 \(kind.rawValue) 가 반려된다")
            XCTAssertFalse(L().itemName(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().itemDescription(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().heldItemEffectHint(kind).isEmpty, kind.rawValue)
            XCTAssertNil(kind.heldBattleEffect?.restrictedSpecies, "\(kind.rawValue) 에 종 제한이 생겼다")
        }
        XCTAssertEqual(L().itemName(.weaknessPolicy), "약점보험")
        XCTAssertEqual(ItemKind.luminousMoss.spriteName, "luminous-moss")
        // 허탕보험만 PokéAPI 에 스프라이트가 없다(8세대) — 이모지 폴백만 쓴다.
        XCTAssertNil(ItemKind.blunderPolicy.spriteName)
        for kind in Self.items where kind != .blunderPolicy {
            XCTAssertNotNil(kind.spriteName, kind.rawValue)
        }
    }

    // MARK: - 약점보험

    /// 효과가 굉장한 히트에만 답하고, 공격·특공을 둘 다 두 단계 올린 뒤 사라진다.
    func testTheWeaknessPolicyAnswersOnlySuperEffectiveHits() {
        var attacker = side()
        var holder = side(types: [.grass], held: .weaknessPolicy)
        let events = hit(attackMove(52, type: .fire), attacker: &attacker, defender: &holder)
        XCTAssertEqual(holder.stage(.atk), 2)
        XCTAssertEqual(holder.stage(.spa), 2)
        XCTAssertTrue(holder.heldItemConsumed)
        XCTAssertTrue(events.contains(.heldItemTriggered(.b, .weaknessPolicy)))

        var plain = side(held: .weaknessPolicy)
        hit(attackMove(), attacker: &attacker, defender: &plain)
        XCTAssertEqual(plain.stage(.atk), 0, "효과가 보통인 히트에 보험이 터졌다")
        XCTAssertFalse(plain.heldItemConsumed)
    }

    // MARK: - 타입별 반응 넷

    /// 구근·충전지·눈덩이·빛이끼는 자기 타입 히트에만 답한다.
    func testEachTypedReactorAnswersOnlyItsOwnMoveType() {
        let cases: [(ItemKind, PokemonType, BattleStat)] = [
            (.absorbBulb, .water, .spa), (.cellBattery, .electric, .atk),
            (.snowball, .ice, .atk), (.luminousMoss, .water, .spd)
        ]
        for (kind, type, stat) in cases {
            var attacker = side()
            var holder = side(held: kind)
            hit(attackMove(55, type: type), attacker: &attacker, defender: &holder)
            XCTAssertEqual(holder.stage(stat), 1, kind.rawValue)
            XCTAssertTrue(holder.heldItemConsumed, kind.rawValue)

            var other = side(held: kind)
            hit(attackMove(), attacker: &attacker, defender: &other)   // 노말 히트
            XCTAssertEqual(other.stage(stat), 0, "\(kind.rawValue) 가 남의 타입에 답했다")
            XCTAssertFalse(other.heldItemConsumed, kind.rawValue)
        }
    }

    /// 데미지가 들어가지 않은 히트에는 답하지 않는다 — 전기 기술을 흘린 땅 타입의 충전지는 그대로다.
    func testTheTypedReactorsNeedAnActualHit() {
        var attacker = side()
        var immune = side(types: [.ground], held: .cellBattery)
        hit(attackMove(85, type: .electric), attacker: &attacker, defender: &immune)
        XCTAssertEqual(immune.stage(.atk), 0)
        XCTAssertFalse(immune.heldItemConsumed)
    }

    // MARK: - 실수보험

    /// 자기 기술이 빗나가면 스피드가 두 단계 오르고 보험은 사라진다 — 맞으면 아무 일도 없다.
    func testTheBlunderPolicyAnswersTheHoldersOwnMiss() {
        let shaky = attackMove(87, accuracy: 1)      // 거의 반드시 빗나간다
        var holder = side(held: .blunderPolicy)
        var target = side()
        let events = hit(shaky, attacker: &holder, defender: &target, seed: 2)
        XCTAssertTrue(events.contains(.miss(.a)), "이 seed 에서 맞았다 — 테스트가 아무것도 안 본다")
        XCTAssertEqual(holder.stage(.spe), 2)
        XCTAssertTrue(holder.heldItemConsumed)
        XCTAssertTrue(events.contains(.heldItemTriggered(.a, .blunderPolicy)))

        var lucky = side(held: .blunderPolicy)
        hit(attackMove(), attacker: &lucky, defender: &target)
        XCTAssertEqual(lucky.stage(.spe), 0, "맞은 기술에 보험이 터졌다")
        XCTAssertFalse(lucky.heldItemConsumed)
    }

    // MARK: - 필드 씨앗

    /// 씨앗은 자기 필드 위에서만 터진다. 뜬 개체는 필드를 안 받으므로 그대로다.
    func testEachSeedAnswersOnlyItsOwnTerrain() {
        let cases: [(ItemKind, BattleTerrain, BattleStat)] = [
            (.electricSeed, .electric, .def), (.grassySeed, .grassy, .def),
            (.mistySeed, .misty, .spd), (.psychicSeed, .psychic, .spd)
        ]
        for (kind, terrain, stat) in cases {
            var field = BattleField()
            XCTAssertTrue(field.start(terrain))
            var holder = side(held: kind)
            let events = BattleEngine.endOfTurnWeather(&holder, actor: .a, field: field)
            XCTAssertEqual(holder.stage(stat), 1, kind.rawValue)
            XCTAssertTrue(holder.heldItemConsumed, kind.rawValue)
            XCTAssertTrue(events.contains(.heldItemTriggered(.a, kind)), kind.rawValue)

            var wrongField = BattleField()
            XCTAssertTrue(wrongField.start(terrain == .electric ? .misty : .electric))
            var idle = side(held: kind)
            _ = BattleEngine.endOfTurnWeather(&idle, actor: .a, field: wrongField)
            XCTAssertEqual(idle.stage(stat), 0, "\(kind.rawValue) 가 남의 필드에 답했다")

            var floating = side(types: [.flying], held: kind)
            _ = BattleEngine.endOfTurnWeather(&floating, actor: .a, field: field)
            XCTAssertEqual(floating.stage(stat), 0, "뜬 개체가 필드를 받았다")
        }
    }
}
