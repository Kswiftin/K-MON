import XCTest
@testable import PokeTokenBar

/// 테라스탈 — 개체의 타입이 **테라 타입 하나로** 접힌다.
///
/// STAB 가 세 갈래로 갈리는 것이 규칙의 핵심이다: 테라 타입이 원래 타입 중 하나면 그 타입이 2배,
/// 원래 타입인데 지금 타입이 아닌 것도 **1.5배로 남고**, 나머지는 무보정이다. "현재 타입만 STAB"
/// 로 짜면 접혀 나간 옛 타입 기술이 조용히 약해지고 화면에는 아무 표시도 없다.
///
/// 테라 타입은 지금 **개체의 첫 번째 타입**으로 파생된다(본가의 야생 개체 규칙). 아이템으로
/// 바꾸는 경로가 붙으면 그때 저장 값이 이 파생을 덮고, 그때부터 "원래에 없던 테라 타입" 갈래가
/// 실제로 밟힌다 — 식은 이미 그 경우를 담고 있다.
final class BattleTeraTests: XCTestCase {

    private func side(_ types: [PokemonType], atk: Int = 100, spa: Int = 100,
                      hp: Int? = nil) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 6, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: types,
                                            base: BattleStats(hp: 100, atk: atk, def: 100,
                                                              spa: spa, spd: 100, spe: 100),
                                            weightHectograms: 100))
        if let hp { out.hp = hp }
        return out
    }

    private func spec(_ id: Int, type: PokemonType, power: Int = 60,
                      damageClass: MoveDamageClass = .special) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "기술"], type: type, power: power,
                            damageClass: damageClass, accuracy: 100, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0; move.targetsUser = false
        return move
    }

    /// 한 방의 데미지 — 같은 seed 로 재므로 값 차이는 규칙 차이다.
    private func damage(_ move: MoveSpec, from attacker: BattleSide,
                        to defender: BattleSide? = nil, seed: UInt64 = 4) -> Int {
        var user = attacker, target = defender ?? side([.normal], hp: 9_999)
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyHit(attacker: &user, defender: &target,
                                     attackerActor: .a, defenderActor: .b, move: move, rng: &rng)
            .compactMap { if case .damage(_, let amount, _) = $0 { return amount } else { return nil } }
            .reduce(0, +)
    }

    /// 테라 타입은 개체의 첫 번째 타입이다.
    func testTheTeraTypeComesFromTheSpecies() {
        XCTAssertEqual(side([.fire, .flying]).snapshot.teraType, .fire)
        XCTAssertEqual(side([.water]).snapshot.teraType, .water)
    }

    /// 테라스탈하면 현재 타입이 하나로 접힌다 — 공격도 방어도 그 타입으로 판정된다.
    func testTerastallizingReplacesTheActiveTypes() {
        var charizard = side([.fire, .flying])
        XCTAssertEqual(charizard.activeTypes, [.fire, .flying])
        charizard.isTerastallized = true
        XCTAssertEqual(charizard.activeTypes, [.fire], "테라 타입 하나만 남는다")
    }

    /// 테라 타입 기술은 **2배**, 접혀 나간 옛 타입 기술은 **1.5배로 남는다**, 나머지는 무보정.
    func testStabSplitsThreeWaysAfterTerastallizing() {
        var mon = side([.fire, .flying])
        mon.isTerastallized = true
        let fire = spec(53, type: .fire)
        let flying = spec(403, type: .flying)
        let electric = spec(85, type: .electric)

        let plain = damage(electric, from: mon)
        XCTAssertEqual(Double(damage(fire, from: mon)), Double(plain) * 2, accuracy: 2,
                       "테라 타입은 2배다")
        XCTAssertEqual(Double(damage(flying, from: mon)), Double(plain) * 1.5, accuracy: 2,
                       "접혀 나간 옛 타입도 1.5배가 남는다")

        // 대조군 — 테라 전에는 둘 다 1.5배다. 이 줄이 없으면 "원래부터 2배였다" 를 구별할 수 없다.
        let before = side([.fire, .flying])
        XCTAssertEqual(damage(fire, from: before), damage(flying, from: before))
        XCTAssertEqual(Double(damage(fire, from: before)),
                       Double(damage(electric, from: before)) * 1.5, accuracy: 2)
    }

    /// 방어도 현재 타입으로 판정된다 — 불꽃테라가 된 불꽃·비행은 바위 4배를 2배로 줄인다.
    func testTerastallizingChangesWhatTheDefenderTakes() {
        let rockSlide = spec(157, type: .rock, damageClass: .physical)
        let attacker = side([.normal])
        var terastallized = side([.fire, .flying], hp: 9_999)
        terastallized.isTerastallized = true

        let before = damage(rockSlide, from: attacker, to: side([.fire, .flying], hp: 9_999), seed: 8)
        let after = damage(rockSlide, from: attacker, to: terastallized, seed: 8)
        XCTAssertEqual(Double(after), Double(before) / 2, accuracy: 2,
                       "비행이 사라져 바위가 4배에서 2배로 내려온다")
    }

    /// 비행이 두 번째 타입인 개체가 테라스탈하면 **땅에 닿는다** — 필드 효과와 부유 판정이 본다.
    func testTerastallizingOffFlyingPutsThePokemonOnTheGround() {
        var dragon = side([.dragon, .flying])
        XCTAssertFalse(BattleField.isGrounded(dragon))
        dragon.isTerastallized = true
        XCTAssertTrue(BattleField.isGrounded(dragon), "드래곤테라라 더 이상 비행이 아니다")
    }

    /// 모래 잔뎀 면역도 현재 타입으로 갈린다 — 바위·강철·땅으로 테라스탈하면 안 깎인다.
    func testSandstormLooksAtTheCurrentTypes() {
        var field = BattleField()
        XCTAssertTrue(field.start(BattleWeather.sandstorm))

        var exposed = side([.water], hp: 200)
        let hurt = BattleEngine.endOfTurnWeather(&exposed, actor: .a, field: field)
        XCTAssertFalse(hurt.isEmpty, "물 타입은 모래에 깎인다")

        var rockTera = side([.rock, .water], hp: 200)
        rockTera.isTerastallized = true
        XCTAssertTrue(BattleEngine.endOfTurnWeather(&rockTera, actor: .a, field: field).isEmpty,
                      "바위테라는 모래에 안 깎인다")

        // 반대 방향도 본다 — 바위·물이 물테라가 되면 면역이 사라진다.
        var lostImmunity = side([.water, .rock], hp: 200)
        lostImmunity.isTerastallized = true
        XCTAssertFalse(BattleEngine.endOfTurnWeather(&lostImmunity, actor: .a, field: field).isEmpty,
                       "물테라가 되면 모래를 맞는다")
    }

    /// 독 타입의 맹독 필중도 현재 타입으로 갈린다.
    func testPoisonTypeToxicFollowsTheCurrentTypes() {
        var toxic = MoveSpec(id: MoveSpec.toxicMoveID, names: ["ko": "맹독"], type: .poison,
                             power: 0, damageClass: .status, accuracy: 1, pp: 10)
        toxic.ailment = "poison"; toxic.ailmentChance = 100
        toxic.statChanges = []; toxic.statChance = 0; toxic.targetsUser = false

        // 명중률 1% 라, 상태가 걸렸다면 독 타입 필중 경로를 지난 것이다.
        var user = side([.poison, .water])
        user.isTerastallized = true
        var target = side([.normal], hp: 200)
        var rng = SplitMix64(seed: 6)
        _ = BattleEngine.applyHit(attacker: &user, defender: &target, attackerActor: .a,
                                  defenderActor: .b, move: toxic, rng: &rng)
        XCTAssertEqual(target.status, .toxic, "독테라는 맹독이 필중이다")

        var noLonger = side([.water, .poison])
        noLonger.isTerastallized = true
        var lucky = side([.normal], hp: 200)
        var missRng = SplitMix64(seed: 6)
        _ = BattleEngine.applyHit(attacker: &noLonger, defender: &lucky, attackerActor: .a,
                                  defenderActor: .b, move: toxic, rng: &missRng)
        XCTAssertNil(lucky.status, "물테라가 되면 1% 명중을 그대로 굴린다")
    }

    /// 테라버스트는 테라스탈 상태에서 테라 타입이 되고, 공격·특공 중 높은 쪽으로 분류가 갈린다.
    func testTeraBlastTakesTheTeraTypeAndTheHigherAttackStat() {
        let blast = spec(MoveSpec.teraBlastID, type: .normal, power: 80)

        let plain = side([.water], atk: 200, spa: 60)
        XCTAssertEqual(blast.asUsed(by: plain).type, .normal, "테라 전에는 노말이다")
        XCTAssertEqual(blast.asUsed(by: plain).damageClass, .special, "테라 전에는 특수다")

        var physical = side([.water], atk: 200, spa: 60)
        physical.isTerastallized = true
        XCTAssertEqual(blast.asUsed(by: physical).type, .water)
        XCTAssertEqual(blast.asUsed(by: physical).damageClass, .physical,
                       "공격이 특공보다 높으면 물리로 나간다")

        var special = side([.water], atk: 60, spa: 200)
        special.isTerastallized = true
        XCTAssertEqual(blast.asUsed(by: special).damageClass, .special)

        // 랭크도 본다 — 특공만 올려 둔 물리형은 특수로 나간다(본가와 같다).
        var boosted = side([.water], atk: 200, spa: 60)
        boosted.isTerastallized = true
        boosted.stages[.spa] = 6
        XCTAssertEqual(blast.asUsed(by: boosted).damageClass, .special)
    }

    /// 모의전에서 실제로 쓸 수 있어야 한다 — **진영당 한 번**, 턴을 쓰지 않는다.
    func testPracticeBattleTerastallizesOncePerSideWithoutSpendingATurn() {
        var practice = TeamPracticeBattle(mine: [side([.water], hp: 200)],
                                          opponents: [side([.fire], hp: 200)],
                                          rng: SplitMix64(seed: 3))
        XCTAssertTrue(practice.canTerastallizeMine)
        let turnBefore = practice.turn
        XCTAssertTrue(practice.terastallizeMine())
        XCTAssertTrue(practice.mySlot.isTerastallized)
        XCTAssertEqual(practice.turn, turnBefore, "테라스탈은 턴을 쓰지 않는다")
        XCTAssertTrue(practice.events.contains(.terastallized(.a, .water)))

        XCTAssertFalse(practice.canTerastallizeMine)
        XCTAssertFalse(practice.terastallizeMine(), "배틀당 한 번이다")
    }

    /// CPU 는 절반 이하로 깎였을 때 한 번 쓴다 — **무작위를 쓰지 않아** rng 소비가 늘지 않는다
    /// (늘면 같은 seed 의 예전 판이 재현되지 않는다).
    func testTheCPUTerastallizesWhenHalfDownAndRollsNothingExtra() {
        var healthy = TeamPracticeBattle(mine: [side([.water], hp: 200)],
                                         opponents: [side([.fire], hp: 200)],
                                         rng: SplitMix64(seed: 3))
        _ = healthy.useMove(0)
        XCTAssertFalse(healthy.opponentTerastalUsed, "멀쩡한 상대는 아직 안 쓴다")

        var hurt = TeamPracticeBattle(mine: [side([.water], hp: 200)],
                                      opponents: [side([.fire], hp: 200)],
                                      rng: SplitMix64(seed: 3))
        hurt.opponents[0].hp = hurt.opponents[0].stats.hp / 2
        _ = hurt.useMove(0)
        XCTAssertTrue(hurt.opponentTerastalUsed)
        XCTAssertTrue(hurt.opponents[0].isTerastallized)
        XCTAssertTrue(hurt.events.contains(.terastallized(.b, .fire)))
        // 같은 seed·같은 턴 수를 태운 두 판의 rng 상태가 같다 — 테라스탈이 난수를 안 뽑았다는 뜻이다.
        XCTAssertEqual(hurt.rng.next(), healthy.rng.next())
    }

    /// AI 추정도 실제로 나가는 형태를 봐야 한다 — 노말로 재면 CPU 가 자기 최대 피해 기술을
    /// 저평가한다(화면에는 "왜 이 기술을 안 쓰지" 로만 보인다).
    func testTheAIScoresTeraBlastWithItsTeraType() {
        var user = side([.water], atk: 200, spa: 60)
        let blast = spec(MoveSpec.teraBlastID, type: .normal, power: 80)
        let fireTarget = side([.fire], hp: 9_999)

        let before = BattleEngine.expectedDamageScore(of: blast, from: user, to: fireTarget)
        user.isTerastallized = true
        let after = BattleEngine.expectedDamageScore(of: blast, from: user, to: fireTarget)
        XCTAssertGreaterThan(after, before,
                             "물 2배 + 물리 200 공격이 반영되지 않았다")
    }

    /// 다른 기술은 `asUsed(by:)` 가 손대지 않는다 — 테라버스트만 예외다.
    func testAsUsedLeavesEveryOtherMoveAlone() {
        var mon = side([.water])
        mon.isTerastallized = true
        let surf = spec(57, type: .water)
        XCTAssertEqual(surf.asUsed(by: mon), surf)
    }

    /// **엔진을 지나는 공격은 `asUsed(by:)` 를 먹어야 한다.** 원본 스펙을 쓰는 경로에서는
    /// 테라버스트가 노말 특수기로 나가고, 화면에는 위력만 이상하게 보인다.
    func testTeraBlastGoesThroughTheEngineWithItsTeraType() {
        var user = side([.water], atk: 200, spa: 60)
        user.isTerastallized = true
        let blast = spec(MoveSpec.teraBlastID, type: .normal, power: 80)
        var target = side([.fire], hp: 9_999)
        var rng = SplitMix64(seed: 4)
        let events = BattleEngine.applyHit(attacker: &user, defender: &target,
                                           attackerActor: .a, defenderActor: .b,
                                           move: blast, rng: &rng)
        XCTAssertTrue(events.contains(.superEffective(.b)),
                      "테라버스트가 물 기술로 나가지 않았다 — 노말이면 불꽃에게 1배다")
    }
}
