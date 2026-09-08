import XCTest
@testable import PokeTokenBar

/// 면역·무시 물건 6종 — 풍선(땅 기술 면역과 맞으면 터짐), 통굽부츠(입장 데미지 무시),
/// 방진고글(날씨 잔뎀 무시), 만능우산(날씨 위력 보정 무시), 겨냥표적(타입 면역 해제),
/// 가벼운돌(체중 절반).
///
/// 앞 배치들과 갈리는 점은 **무엇을 얹지 않는가**를 답한다는 것이다: 배율을 곱하는 대신 이미 있는
/// 규칙 한 줄을 건너뛴다. 그래서 축이 값이 아니라 "이 규칙이 이 개체에게 적용되는가" 다.
@MainActor
final class ImmunityItemTests: XCTestCase {

    private static let items: [ItemKind] = [
        .airBalloon, .heavyDutyBoots, .safetyGoggles, .utilityUmbrella, .ringTarget, .floatStone
    ]

    private func side(types: [PokemonType] = [.normal], held: ItemKind? = nil,
                      hp: Int? = nil, ability: String? = nil,
                      weight: Int? = 100) -> BattleSide {
        var side = BattleSide(BattleSnapshot(speciesID: 1, name: "테스트", trainer: nil, level: 50,
                                             nature: nil, isShiny: false, types: types,
                                             base: BattleStats(hp: 100, atk: 100, def: 100,
                                                               spa: 100, spd: 100, spe: 100),
                                             moves: nil, ability: ability, heldItem: held,
                                             weightHectograms: weight))
        if let hp { side.hp = hp }
        return side
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

    private func hit(_ move: MoveSpec, attacker: BattleSide, defender: inout BattleSide,
                     field: BattleField = BattleField(), seed: UInt64 = 11) -> [BattleEvent] {
        var a = attacker
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyHit(attacker: &a, defender: &defender, attackerActor: .a,
                                     defenderActor: .b, move: move, field: field, rng: &rng)
    }

    private func dealt(_ events: [BattleEvent]) -> Int {
        events.reduce(0) {
            if case .damage(.b, let amount, .move) = $1 { return $0 + amount }
            return $0
        }
    }

    private func damage(_ move: MoveSpec, attacker: BattleSide, defender: BattleSide,
                        field: BattleField = BattleField(), seed: UInt64 = 11) -> Int {
        var target = defender
        return dealt(hit(move, attacker: attacker, defender: &target, field: field, seed: seed))
    }

    // MARK: - 아이템 축

    func testTheImmunityItemsRideTheHeldItemAxis() {
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
        XCTAssertEqual(ItemKind.airBalloon.spriteName, "air-balloon")
        XCTAssertEqual(L().itemName(.ringTarget), "겨냥표적")
        // 통굽부츠·만능우산은 PokéAPI 에 스프라이트가 없다(8세대 아이템) — 이모지 폴백만 쓴다.
        // 파일명을 지어내면 화면에 깨진 이미지가 남는다.
        XCTAssertNil(ItemKind.heavyDutyBoots.spriteName)
        XCTAssertNil(ItemKind.utilityUmbrella.spriteName)
    }

    // MARK: - 풍선

    /// 풍선을 쥔 개체는 땅에 닿지 않는다 — 땅 기술이 통하지 않고, 발밑에 깔린 것도 안 밟는다.
    func testTheAirBalloonLiftsTheHolderOffTheGround() {
        let quake = attackMove(89, type: .ground)
        XCTAssertEqual(damage(quake, attacker: side(), defender: side(held: .airBalloon)), 0)
        XCTAssertGreaterThan(damage(quake, attacker: side(), defender: side()), 0)
        XCTAssertFalse(BattleField.isGrounded(side(held: .airBalloon)))
        // 검은철구와 **같은 축**이라 방향만 반대다 — 뜬 개체를 내려놓는 쪽이 저기다.
        XCTAssertTrue(BattleField.isGrounded(side(types: [.flying], held: .ironBall)))
    }

    /// 뜬 개체는 발밑 함정(압정)을 안 밟지만 스텔스록은 그대로 맞는다 — 그 하나만 공중에 뜬다.
    func testTheAirBalloonSkipsOnlyTheGroundedHazards() {
        var field = BattleField()
        XCTAssertTrue(field.start(.spikes, for: .a))
        var floating = side(held: .airBalloon)
        var rng = SplitMix64(seed: 3)
        XCTAssertTrue(BattleEngine.applyEntryHazards(&floating, actor: .a, team: .a,
                                                     field: field, rng: &rng).isEmpty)
        XCTAssertTrue(field.start(.stealthRock, for: .a))
        var rocked = side(held: .airBalloon)
        XCTAssertFalse(BattleEngine.applyEntryHazards(&rocked, actor: .a, team: .a,
                                                      field: field, rng: &rng).isEmpty)
        XCTAssertLessThan(rocked.hp, rocked.stats.hp)
    }

    /// 맞으면 터진다 — 그 뒤에는 땅 기술이 통한다.
    func testTheAirBalloonPopsOnTheFirstDamagingHit() {
        var holder = side(held: .airBalloon)
        let events = hit(attackMove(), attacker: side(), defender: &holder)
        XCTAssertTrue(holder.heldItemConsumed, "맞았는데 풍선이 남았다")
        XCTAssertTrue(events.contains(.heldItemTriggered(.b, .airBalloon)), "터진 줄이 없다")
        XCTAssertNil(holder.heldEffect)
        XCTAssertTrue(BattleField.isGrounded(holder), "터진 뒤에도 떠 있다")
        // 변화기는 데미지가 없으므로 터뜨리지 않는다.
        var untouched = side(held: .airBalloon)
        _ = hit(attackMove(45, power: 0, damageClass: .status), attacker: side(), defender: &untouched)
        XCTAssertFalse(untouched.heldItemConsumed, "데미지 없는 기술이 풍선을 터뜨렸다")
    }

    // MARK: - 통굽부츠

    /// 통굽부츠는 **모든** 입장 데미지를 건너뛴다 — 뜬 개체가 안 밟는 세 가지까지 포함해서다.
    func testTheHeavyDutyBootsIgnoreEveryEntryHazard() {
        var field = BattleField()
        for condition in [BattleSideCondition.stickyWeb, .stealthRock, .spikes, .toxicSpikes] {
            XCTAssertTrue(field.start(condition, for: .a), condition.rawValue)
        }
        var booted = side(held: .heavyDutyBoots)
        var rng = SplitMix64(seed: 3)
        XCTAssertTrue(BattleEngine.applyEntryHazards(&booted, actor: .a, team: .a,
                                                     field: field, rng: &rng).isEmpty)
        XCTAssertEqual(booted.hp, booted.stats.hp)
        XCTAssertNil(booted.status)
        XCTAssertEqual(booted.stage(.spe), 0)
        var bare = side()
        XCTAssertFalse(BattleEngine.applyEntryHazards(&bare, actor: .a, team: .a,
                                                      field: field, rng: &rng).isEmpty)
    }

    // MARK: - 방진고글

    /// 방진고글은 모래바람의 턴 끝 데미지를 막는다.
    func testTheSafetyGogglesBlockTheWeatherResidual() {
        var field = BattleField()
        XCTAssertTrue(field.start(.sandstorm))
        var goggled = side(held: .safetyGoggles)
        XCTAssertTrue(BattleEngine.endOfTurnWeather(&goggled, actor: .a, field: field).isEmpty)
        XCTAssertEqual(goggled.hp, goggled.stats.hp)
        var bare = side()
        XCTAssertFalse(BattleEngine.endOfTurnWeather(&bare, actor: .a, field: field).isEmpty)
        XCTAssertLessThan(bare.hp, bare.stats.hp)
    }

    // MARK: - 만능우산

    /// 만능우산을 쥔 쪽은 볕·비의 위력 보정을 받지 않는다 — 올리는 쪽도 깎는 쪽도 없어진다.
    func testTheUtilityUmbrellaIgnoresTheSunAndRainPowerScale() {
        let ember = attackMove(52, type: .fire, damageClass: .special)
        var sun = BattleField(); XCTAssertTrue(sun.start(.sun))
        var rain = BattleField(); XCTAssertTrue(rain.start(.rain))
        let target = side()
        let plain = damage(ember, attacker: side(), defender: target)
        XCTAssertGreaterThan(damage(ember, attacker: side(), defender: target, field: sun), plain)
        XCTAssertEqual(damage(ember, attacker: side(held: .utilityUmbrella), defender: target,
                              field: sun), plain, "볕이 우산 너머로 위력을 올렸다")
        XCTAssertEqual(damage(ember, attacker: side(held: .utilityUmbrella), defender: target,
                              field: rain), plain, "비가 우산 너머로 위력을 깎았다")
        // 모래바람은 우산이 막지 않는다 — 그건 방진고글의 일이다.
        var sand = BattleField(); XCTAssertTrue(sand.start(.sandstorm))
        var holder = side(held: .utilityUmbrella)
        XCTAssertFalse(BattleEngine.endOfTurnWeather(&holder, actor: .a, field: sand).isEmpty)
    }

    // MARK: - 겨냥표적

    /// 겨냥표적을 쥔 개체에게는 **타입** 면역이 없어진다 — 특성 면역은 그대로다.
    func testTheRingTargetRemovesOnlyTheTypeImmunities() {
        let tackle = attackMove()
        let ghost = side(types: [.ghost])
        XCTAssertEqual(damage(tackle, attacker: side(), defender: ghost), 0)
        XCTAssertGreaterThan(damage(tackle, attacker: side(),
                                    defender: side(types: [.ghost], held: .ringTarget)), 0)
        // 부유는 특성이라 표적이 뚫지 못한다 — 표적은 상성표만 본다.
        let quake = attackMove(89, type: .ground)
        XCTAssertEqual(damage(quake, attacker: side(),
                              defender: side(held: .ringTarget, ability: "levitate")), 0)
    }

    // MARK: - 가벼운돌

    /// 가벼운돌은 체중을 절반으로 만든다 — 체중으로 위력이 정해지는 기술이 약해진다.
    func testTheFloatStoneHalvesTheHolderWeight() {
        XCTAssertEqual(side(held: .floatStone, weight: 1_000).effectiveWeightHectograms, 500)
        XCTAssertEqual(side(weight: 1_000).effectiveWeightHectograms, 1_000)
        XCTAssertNil(side(held: .floatStone, weight: nil).effectiveWeightHectograms)
        let lowKick = attackMove(VariableDamage.MoveID.lowKick, type: .fighting, power: 0)
        var rng = SplitMix64(seed: 5)
        let heavy: VariableDamage? = VariableDamage.from(lowKick, attacker: side(),
                                                         defender: side(weight: 1_000), rng: &rng)
        let lightened: VariableDamage? =
            VariableDamage.from(lowKick, attacker: side(),
                                defender: side(held: .floatStone, weight: 1_000), rng: &rng)
        XCTAssertEqual(heavy, .power(100))
        XCTAssertEqual(lightened, .power(80), "가벼운돌이 체중을 안 깎았다")
    }
}
