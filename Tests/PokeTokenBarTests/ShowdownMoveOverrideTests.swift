import XCTest
@testable import PokeTokenBar

/// PokéAPI 의 기술 데이터 결손을 쇼다운 표로 메우는 층.
///
/// PokéAPI 의 `move_meta` 는 7세대에서 끊긴다 — 8세대 이후 177개 중 92개는 meta 행이 아예 없어
/// 다단 히트·드레인·상태이상·풀린치·급소 보정이 전부 nil 로 디코딩된다. 명중률도 필중 기술에
/// null 이 아니라 **0** 을 실어, 그대로 읽으면 명중 0% 가 된다.
///
/// 여기 있는 테스트는 **결손 데이터를 그대로 재현한 JSON** 으로 시작한다. 정상 응답으로 테스트하면
/// 보정층이 통째로 죽어 있어도 초록으로 통과한다(그게 이 결함이 릴리스까지 간 경로다).
final class ShowdownMoveOverrideTests: XCTestCase {
    /// meta 가 통째로 없고 명중률이 0 인 응답 — 9세대 기술이 PokéAPI 에서 실제로 오는 모양이다.
    private func gapJSON(id: Int, power: Int, accuracy: String,
                         damageClass: String = "physical", name: String) -> Data {
        Data("""
        {"id": \(id), "power": \(power), "accuracy": \(accuracy), "pp": 10, "priority": 0,
         "type": {"name": "steel", "url": null},
         "damage_class": {"name": "\(damageClass)", "url": null},
         "names": [{"name": "\(name)", "language": {"name": "en", "url": null}}],
         "flavor_text_entries": []}
        """.utf8)
    }

    private func spec(_ json: Data, name: String) throws -> MoveSpec {
        try XCTUnwrap(MoveSpec.from(try JSONDecoder().decode(MoveDTO.self, from: json),
                                    fallbackName: name, languages: ["en"]))
    }

    private func tank(_ types: [PokemonType] = [.normal], hp: Int = 100) -> BattleSnapshot {
        BattleSnapshot(speciesID: 143, name: "탱커", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: hp, atk: 100, def: 100, spa: 100, spd: 100, spe: 100))
    }

    private func move(id: Int, power: Int = 0, damageClass: MoveDamageClass = .physical) -> MoveSpec {
        MoveSpec(id: id, names: ["en": "test"], type: .steel, power: power,
                 damageClass: damageClass, accuracy: 100, pp: 10)
    }

    // MARK: 명중률 0 — 필중 기술이 무조건 빗나가던 결함

    /// 타키온커터. PokéAPI 는 `accuracy: 0` 을 주는데 실제로는 필중이다.
    func testNeverMissMoveWithZeroAccuracyDecodesAsAlwaysHitting() throws {
        let decoded = try spec(gapJSON(id: 911, power: 50, accuracy: "0",
                                       damageClass: "special", name: "Tachyon Cutter"),
                               name: "tachyon-cutter")
        XCTAssertNil(decoded.accuracy, "명중률 0 은 '필중' 이라는 뜻이다 — 0% 가 아니다")
    }

    /// **표에 없는 기술도 같은 규칙을 탄다.** 보정표만 고치면 다음 세대가 나올 때 같은 결함이
    /// 그대로 재발한다 — 0 을 필중으로 읽는 규칙 자체가 디코딩에 있어야 한다.
    func testAnyMoveWithZeroAccuracyNeverMissesEvenWithoutAnOverride() throws {
        XCTAssertNil(ShowdownMoveData.overrides[9999], "보정표에 없는 id 여야 이 테스트가 뜻이 있다")
        let decoded = try spec(gapJSON(id: 9999, power: 60, accuracy: "0", name: "Unknown"),
                               name: "unknown")
        XCTAssertNil(decoded.accuracy)
    }

    /// 명중률 0 이 실제로 **빗나감으로 이어지지 않는지** 확인한다. 스펙만 보면 배선이 죽어 있어도
    /// 통과하므로 판정 함수까지 태운다.
    func testZeroAccuracyMoveDoesNotMissInBattle() {
        let attacker = BattleSide(tank()), defender = BattleSide(tank())
        var zeroAccuracy = move(id: 9999, power: 60)
        zeroAccuracy.accuracy = 0
        XCTAssertNil(BattleEngine.hitChance(of: zeroAccuracy, attacker: attacker, defender: defender),
                     "옛 세이브·구버전 피어가 실어 보낸 0 도 필중으로 읽어야 한다")
    }

    /// 구버전 피어가 명중률 0 을 실어 보내면 **무브셋 전체가 반려**돼 입장 자체가 막혔다.
    func testPeerMovesetWithZeroAccuracyIsAccepted() {
        var zeroAccuracy = move(id: 911, power: 50)
        zeroAccuracy.accuracy = 0
        XCTAssertTrue(MultiplayerValidation.validMoves([zeroAccuracy]),
                      "0 은 필중이라는 뜻이라 정상 값이다 — 반려하면 상대 팀 전체가 입장에서 막힌다")
    }

    // MARK: meta 결손 — 다단기가 1히트로 죽던 결함

    func testTachyonCutterHitsTwice() throws {
        let decoded = try spec(gapJSON(id: 911, power: 50, accuracy: "0",
                                       damageClass: "special", name: "Tachyon Cutter"),
                               name: "tachyon-cutter")
        XCTAssertEqual(decoded.minHits, 2)
        XCTAssertEqual(decoded.maxHits, 2)
    }

    /// 파퓰레이션밤은 위력 20 × 10 히트다. meta 가 없어 1 히트로 읽히면 위력 20 짜리 잡기술이 된다.
    func testPopulationBombHitsTenTimes() throws {
        let decoded = try spec(gapJSON(id: 860, power: 20, accuracy: "90", name: "Population Bomb"),
                               name: "population-bomb")
        XCTAssertEqual(decoded.minHits, 10)
        XCTAssertEqual(decoded.maxHits, 10)
    }

    /// 보정이 **덮어쓰기가 아니라 메우기**인지 본다. PokéAPI 가 준 값이 있으면 그대로 둔다.
    func testOverrideLeavesFieldsPokeAPIAlreadySupplied() throws {
        let decoded = try spec(gapJSON(id: 860, power: 20, accuracy: "90", name: "Population Bomb"),
                               name: "population-bomb")
        XCTAssertEqual(decoded.accuracy, 90, "명중률은 PokéAPI 값이 맞다 — 보정표가 건드리지 않는다")
        XCTAssertEqual(decoded.power, 20)
    }

    // MARK: 가변 위력 — 위력 0 으로 와서 데미지가 0 이던 결함

    /// 하드프레스는 상대 HP 비율에 비례한다(최대 100). PokéAPI 는 위력 0 을 준다.
    ///
    /// 절반 HP 를 정확한 값으로 잡지 않는 이유는 **정수 나눗셈**이다 — 최대 HP 가 홀수면 절반이
    /// 내림으로 밀려 49 가 나온다. 기대값을 같은 식으로 다시 쓰면 식이 틀려도 통과하므로,
    /// 양 끝점(만피 100, 1 HP 1)만 정확히 잡고 가운데는 구간으로 본다.
    func testHardPressScalesWithTargetHealth() {
        let attacker = BattleSide(tank())
        var rng = SplitMix64(seed: 1)
        let full = BattleSide(tank())
        XCTAssertEqual(VariableDamage.from(move(id: 912), attacker: attacker, defender: full,
                                           rng: &rng), .power(100))
        var half = BattleSide(tank())
        half.hp = half.stats.hp / 2
        guard case .power(let halfPower)? = VariableDamage.from(move(id: 912), attacker: attacker,
                                                                defender: half, rng: &rng) else {
            return XCTFail("하드프레스는 가변 위력이어야 한다")
        }
        XCTAssertTrue((49...50).contains(halfPower), "절반 HP 에서 위력 \(halfPower)")
        // HP 가 1 이어도 위력 0 으로 접히지 않는다 — 접히면 다시 죽은 기술이 된다.
        var sliver = BattleSide(tank())
        sliver.hp = 1
        XCTAssertEqual(VariableDamage.from(move(id: 912), attacker: attacker, defender: sliver,
                                           rng: &rng), .power(1))
    }

    /// 황폐가는 상대 현재 HP 의 절반을 깎는다. PokéAPI 는 위력 1 을 줘서 사실상 0 데미지였다.
    func testRuinationHalvesTargetHealth() {
        let attacker = BattleSide(tank())
        var defender = BattleSide(tank())
        defender.hp = 80
        var rng = SplitMix64(seed: 1)
        XCTAssertEqual(VariableDamage.from(move(id: 877, damageClass: .special),
                                           attacker: attacker, defender: defender, rng: &rng),
                       .fixedHP(40))
    }

    /// 인과응보는 분류를 가리지 않고 맞은 데미지의 1.5 배를 돌려준다(메탈버스트와 같다).
    func testComeuppanceReturnsOneAndAHalfTimesTheDamageTaken() {
        var attacker = BattleSide(tank())
        let defender = BattleSide(tank())
        var rng = SplitMix64(seed: 1)
        attacker.lastHitThisTurn = IncomingHit(amount: 40, damageClass: .special)
        XCTAssertEqual(VariableDamage.from(move(id: 894), attacker: attacker, defender: defender,
                                           rng: &rng), .fixedHP(60))
        // 맞은 것이 없으면 실패한다 — 메탈버스트와 같은 규칙이다.
        var untouched = BattleSide(tank())
        untouched.lastHitThisTurn = nil
        XCTAssertEqual(VariableDamage.from(move(id: 894), attacker: untouched, defender: defender,
                                           rng: &rng), .noEffect)
    }

    /// 세 기술 모두 **실제로 데미지를 낸다.** 위력 계산만 확인하면 파이프라인 어딘가에서 다시
    /// 0 으로 접혀도 통과한다 — 그게 원래 결함의 모양이었다.
    func testFormerlyDeadMovesNowDealDamage() {
        for id in [912, 877, 894] {
            var attacker = BattleSide(tank())
            attacker.lastHitThisTurn = IncomingHit(amount: 40, damageClass: .physical)
            var defender = BattleSide(tank())
            var rng = SplitMix64(seed: 7)
            var field = BattleField()
            _ = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                         attackerActor: .a, defenderActor: .b,
                                         move: move(id: id), field: &field, rng: &rng)
            XCTAssertLessThan(defender.hp, defender.stats.hp, "기술 \(id) 가 데미지를 내야 한다")
        }
    }
}
