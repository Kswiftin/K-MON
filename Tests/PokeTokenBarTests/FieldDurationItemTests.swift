import XCTest
@testable import PokeTokenBar

/// 지속 시간을 늘리는 물건 6종 — 빛의점토(장막), 날씨 돌 넷(차가운바위·보송보송바위·뜨거운바위·
/// 축축한바위), 그라운드코트(필드).
///
/// 앞 배치들과 갈리는 점은 **판에 거는 것**을 바꾼다는 것이다. 그래서 축을 묻는 자리가 지닌 개체가
/// 아니라 **거는 순간**이다: 판은 누가 걸었는지를 안 들고 있어도 되고(들면 교체·기절마다 주인을
/// 따라다녀야 한다), 물건은 거는 그 자리에서 한 번만 답한다.
final class FieldDurationItemTests: XCTestCase {

    private static let items: [ItemKind] = [
        .lightClay, .icyRock, .smoothRock, .heatRock, .dampRock, .terrainExtender
    ]

    private func side(held: ItemKind? = nil) -> BattleSide {
        BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                  nature: nil, isShiny: false, types: [.normal],
                                  base: BattleStats(hp: 100, atk: 100, def: 100,
                                                    spa: 100, spd: 100, spe: 100),
                                  heldItem: held, weightHectograms: 100))
    }

    private func statusMove(_ id: Int) -> MoveSpec {
        var out = MoveSpec(id: id, names: ["ko": "기술\(id)"], type: .normal, power: 0,
                           damageClass: .status, accuracy: nil, pp: 10)
        out.ailment = "none"; out.ailmentChance = 0
        out.statChanges = []; out.statChance = 0; out.targetsUser = false
        return out
    }

    @discardableResult
    private func cast(_ id: Int, held: ItemKind? = nil,
                      into field: inout BattleField) -> [BattleEvent] {
        var mine = side(held: held), theirs = side()
        var rng = SplitMix64(seed: 9)
        return BattleEngine.applyAttack(attacker: &mine, defender: &theirs, attackerActor: .a,
                                        defenderActor: .b, move: statusMove(id), field: &field,
                                        rng: &rng)
    }

    // MARK: - 아이템 축

    func testTheDurationItemsRideTheHeldItemAxis() {
        for kind in Self.items {
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
        XCTAssertEqual(L().itemName(.smoothRock), "보송보송바위")
        XCTAssertEqual(ItemKind.lightClay.spriteName, "light-clay")
    }

    // MARK: - 빛의점토

    /// 빛의점토를 쥔 쪽이 깔면 장막이 8턴 간다 — 안 쥐면 5턴이다.
    func testTheLightClayStretchesTheScreens() {
        for reflectID in [115, 113] {
            var bare = BattleField()
            cast(reflectID, into: &bare)
            var clayed = BattleField()
            cast(reflectID, held: .lightClay, into: &clayed)
            let condition = BattleSideCondition.called(byMoveID: reflectID)!
            XCTAssertEqual(bare.layers(condition, for: .a), condition.duration)
            XCTAssertEqual(clayed.layers(condition, for: .a), HeldItemBalance.extendedFieldTurns)
        }
    }

    /// 장막이 아닌 진영 상태는 안 늘어난다 — 순풍이 8턴을 불면 선공이 통째로 뒤집힌다.
    func testTheLightClayLeavesTheOtherSideConditionsAlone() {
        var field = BattleField()
        cast(366, held: .lightClay, into: &field)          // 순풍
        XCTAssertEqual(field.layers(.tailwind, for: .a), BattleSideCondition.tailwind.duration)
    }

    // MARK: - 날씨 돌

    /// 날씨 돌은 **자기 날씨만** 늘린다 — 뜨거운바위를 쥐고 비를 불러도 5턴이다.
    func testEachWeatherRockStretchesOnlyItsOwnWeather() {
        let byWeather: [(ItemKind, Int, BattleWeather)] = [
            (.heatRock, 241, .sun), (.dampRock, 240, .rain), (.icyRock, 258, .snow),
            (.smoothRock, 201, .sandstorm)
        ]
        for (rock, moveID, weather) in byWeather {
            var bare = BattleField()
            cast(moveID, into: &bare)
            XCTAssertEqual(bare.weather, weather, "\(moveID) 이 날씨를 안 불렀다")
            XCTAssertEqual(bare.weatherTurns, BattleWeather.duration)

            var stretched = BattleField()
            cast(moveID, held: rock, into: &stretched)
            XCTAssertEqual(stretched.weatherTurns, HeldItemBalance.extendedFieldTurns,
                           rock.rawValue)

            var wrong = BattleField()
            cast(moveID, held: .terrainExtender, into: &wrong)
            XCTAssertEqual(wrong.weatherTurns, BattleWeather.duration,
                           "그라운드코트가 날씨까지 늘렸다")
        }
    }

    // MARK: - 그라운드코트

    /// 그라운드코트는 필드를 8턴으로 늘린다 — 날씨는 그대로다.
    func testTheTerrainExtenderStretchesOnlyTheTerrain() {
        var bare = BattleField()
        cast(604, into: &bare)                              // 일렉트릭필드
        XCTAssertEqual(bare.terrain, .electric)
        XCTAssertEqual(bare.terrainTurns, BattleTerrain.duration)

        var stretched = BattleField()
        cast(604, held: .terrainExtender, into: &stretched)
        XCTAssertEqual(stretched.terrainTurns, HeldItemBalance.extendedFieldTurns)

        var rocked = BattleField()
        cast(604, held: .heatRock, into: &rocked)
        XCTAssertEqual(rocked.terrainTurns, BattleTerrain.duration, "날씨 돌이 필드를 늘렸다")
    }

    /// 늘어난 턴은 실제로 그만큼 간다 — 시작 값만 크고 감소가 빨리 끝나면 아무 뜻이 없다.
    func testTheStretchedWeatherActuallyLastsTheExtraTurns() {
        var field = BattleField()
        cast(241, held: .heatRock, into: &field)
        for _ in 0..<(HeldItemBalance.extendedFieldTurns - 1) {
            _ = BattleEngine.advanceField(&field)
            XCTAssertEqual(field.weather, .sun)
        }
        XCTAssertTrue(BattleEngine.advanceField(&field).contains(.weatherEnded(.sun)))
        XCTAssertNil(field.weather)
    }
}
