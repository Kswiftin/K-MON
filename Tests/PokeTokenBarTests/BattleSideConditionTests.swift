import XCTest
@testable import PokeTokenBar

/// 한쪽 진영에 깔리는 상태(리플렉터·빛의장막·오로라베일·신비의부적·하얀안개·행운의부적).
///
/// 날씨·필드와 달리 **판 전체가 아니라 건 쪽에만** 걸린다. 그래서 `BattleField` 가 편(`BattleTeamSlot`)
/// 별로 하나씩 들고, `applyAttack` 은 공격자가 어느 편인지를 받아야 한다.
final class BattleSideConditionTests: XCTestCase {

    private func side(_ types: [PokemonType] = [.normal], level: Int = 50,
                      speed: Int = 100, hp: Int? = nil) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: level,
                                            nature: nil, isShiny: false, types: types,
                                            base: BattleStats(hp: 100, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: speed),
                                            weightHectograms: 100))
        if let hp { out.hp = hp }
        return out
    }

    private func spec(_ id: Int, type: PokemonType = .normal,
                      damageClass: MoveDamageClass = .physical, power: Int = 80,
                      accuracy: Int? = 100) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "기술"], type: type, power: power,
                            damageClass: damageClass, accuracy: accuracy, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0; move.targetsUser = false
        return move
    }

    /// 방어 측 편에 `condition` 이 깔린 판과 아무것도 없는 판에서 같은 공격의 데미지를 잰다.
    private func damage(_ move: MoveSpec, under condition: BattleSideCondition?,
                        weather: BattleWeather? = nil, seed: UInt64 = 4) -> Int {
        var field = BattleField()
        // 오로라베일은 눈이 있어야 깔린다. 눈 자체는 데미지 배율이 없어(9세대) 대조군과 값이 갈리지 않는다.
        if let weather { _ = field.start(weather) }
        else if condition == .auroraVeil { _ = field.start(BattleWeather.snow) }
        if let condition { XCTAssertTrue(field.start(condition, for: .b)) }
        var attacker = side([.fighting]), defender = side([.normal], hp: 9_999)
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyHit(attacker: &attacker, defender: &defender,
                                     attackerActor: .a, defenderActor: .b, move: move,
                                     field: field, defenderTeam: .b, rng: &rng)
            .compactMap { if case .damage(_, let amount, _) = $0 { return amount } else { return nil } }
            .reduce(0, +)
    }

    /// 리플렉터는 물리만, 빛의장막은 특수만 반으로 깎는다. 분류를 안 보는 오구현은 한쪽만 보면 통과한다.
    func testReflectAndLightScreenEachHalveTheirOwnDamageClass() {
        let punch = spec(5, type: .fighting, damageClass: .physical)
        let beam = spec(85, type: .fighting, damageClass: .special)

        XCTAssertEqual(damage(punch, under: .reflect), damage(punch, under: nil) / 2, accuracy: 1)
        XCTAssertEqual(damage(beam, under: .reflect), damage(beam, under: nil),
                       "리플렉터는 특수기를 안 막는다")
        XCTAssertEqual(damage(beam, under: .lightScreen), damage(beam, under: nil) / 2, accuracy: 1)
        XCTAssertEqual(damage(punch, under: .lightScreen), damage(punch, under: nil),
                       "빛의장막은 물리기를 안 막는다")
    }

    /// 오로라베일은 둘 다 깎는다 — 대신 눈이 내릴 때만 깔린다.
    func testAuroraVeilHalvesBothClassesButNeedsSnow() {
        let punch = spec(5, type: .fighting, damageClass: .physical)
        let beam = spec(85, type: .fighting, damageClass: .special)
        XCTAssertEqual(damage(punch, under: .auroraVeil), damage(punch, under: nil) / 2, accuracy: 1)
        XCTAssertEqual(damage(beam, under: .auroraVeil), damage(beam, under: nil) / 2, accuracy: 1)

        var noSnow = BattleField()
        XCTAssertFalse(noSnow.start(.auroraVeil, for: .a), "눈이 없으면 깔리지 않는다")
        var snowing = BattleField()
        _ = snowing.start(BattleWeather.snow)
        XCTAssertTrue(snowing.start(.auroraVeil, for: .a))
    }

    /// 장막은 **급소를 막지 못한다**(3세대 이후 규칙). 급소가 장막을 뚫지 못하면 장막 한 장이
    /// 배틀을 통째로 잠근다.
    func testACriticalHitIgnoresTheScreens() {
        var punch = spec(5, type: .fighting, damageClass: .physical)
        punch.critRate = 6                                      // 확정 급소
        XCTAssertEqual(damage(punch, under: .reflect), damage(punch, under: nil),
                       "급소는 리플렉터를 뚫는다")
    }

    /// 장막은 **건 쪽만** 지킨다. 편을 안 보면 한쪽이 깐 리플렉터가 상대까지 지킨다.
    func testAScreenProtectsOnlyTheSideThatSetIt() {
        let punch = spec(5, type: .fighting, damageClass: .physical)
        var field = BattleField()
        XCTAssertTrue(field.start(.reflect, for: .a))
        var attacker = side([.fighting]), defender = side([.normal], hp: 9_999)
        var rng = SplitMix64(seed: 4)
        let dealt = BattleEngine.applyHit(attacker: &attacker, defender: &defender,
                                          attackerActor: .a, defenderActor: .b, move: punch,
                                          field: field, defenderTeam: .b, rng: &rng)
            .compactMap { if case .damage(_, let amount, _) = $0 { return amount } else { return nil } }
            .reduce(0, +)
        XCTAssertEqual(dealt, damage(punch, under: nil), "상대 편의 장막은 나를 지키지 않는다")
    }

    /// 행운의부적은 그 편이 **맞는** 급소를 막는다. 급소 판정 자체는 그대로 굴려야 rng 소비가 안 갈린다.
    func testLuckyChantStopsCriticalHitsAgainstThatSide() {
        var punch = spec(5, type: .fighting, damageClass: .physical)
        punch.critRate = 6
        var field = BattleField()
        XCTAssertTrue(field.start(.luckyChant, for: .b))
        var attacker = side([.fighting]), defender = side([.normal], hp: 9_999)
        var rng = SplitMix64(seed: 4)
        let events = BattleEngine.applyHit(attacker: &attacker, defender: &defender,
                                           attackerActor: .a, defenderActor: .b, move: punch,
                                           field: field, defenderTeam: .b, rng: &rng)
        XCTAssertFalse(events.contains { if case .crit = $0 { return true }; return false },
                       "확정 급소 기술도 행운의부적 앞에서는 급소가 아니다")
        XCTAssertEqual(damage(punch, under: .luckyChant), damage(punch, under: nil) * 2 / 3,
                       accuracy: 2, "급소 1.5배가 빠진 만큼만 줄어든다")
    }

    /// 신비의부적은 상대가 거는 상태이상을 막는다.
    func testSafeguardBlocksAStatusFromTheOpponent() {
        var spore = spec(147, type: .grass, damageClass: .status, power: 0, accuracy: nil)
        spore.ailment = "sleep"; spore.ailmentChance = 0
        var field = BattleField()
        XCTAssertTrue(field.start(.safeguard, for: .b))
        var attacker = side([.grass]), defender = side([.normal])
        var rng = SplitMix64(seed: 4)
        _ = BattleEngine.applyHit(attacker: &attacker, defender: &defender,
                                  attackerActor: .a, defenderActor: .b, move: spore,
                                  field: field, defenderTeam: .b, rng: &rng)
        XCTAssertNil(defender.status, "신비의부적을 편 쪽은 잠들지 않는다")

        let open = BattleField()
        var target = side([.normal])
        var openRng = SplitMix64(seed: 4)
        var caster = side([.grass])
        _ = BattleEngine.applyHit(attacker: &caster, defender: &target,
                                  attackerActor: .a, defenderActor: .b, move: spore,
                                  field: open, defenderTeam: .b, rng: &openRng)
        XCTAssertEqual(target.status, .sleep, "부적이 없으면 걸린다 — 이 대조군이 없으면 테스트가 빈 판이다")
    }

    /// 하얀안개는 상대가 내리는 랭크만 막는다. 자기 상승까지 막으면 쓰는 쪽이 손해를 본다.
    func testMistBlocksTheOpponentsDropsButNotOwnBoosts() {
        var growl = spec(45, type: .normal, damageClass: .status, power: 0, accuracy: nil)
        growl.statChanges = [StatChange(stat: .atk, change: -1)]
        growl.statChance = 0
        var field = BattleField()
        XCTAssertTrue(field.start(.mist, for: .b))
        var attacker = side(), defender = side()
        var rng = SplitMix64(seed: 4)
        _ = BattleEngine.applyHit(attacker: &attacker, defender: &defender,
                                  attackerActor: .a, defenderActor: .b, move: growl,
                                  field: field, defenderTeam: .b, rng: &rng)
        XCTAssertEqual(defender.stage(.atk), 0, "하얀안개를 편 쪽은 깎이지 않는다")

        var swordsDance = spec(14, type: .normal, damageClass: .status, power: 0, accuracy: nil)
        swordsDance.statChanges = [StatChange(stat: .atk, change: 2)]
        swordsDance.statChance = 0
        var mistedField = BattleField()
        XCTAssertTrue(mistedField.start(.mist, for: .a))
        var booster = side(), other = side()
        var boostRng = SplitMix64(seed: 4)
        _ = BattleEngine.applyHit(attacker: &booster, defender: &other,
                                  attackerActor: .a, defenderActor: .b, move: swordsDance,
                                  field: mistedField, defenderTeam: .b, rng: &boostRng)
        XCTAssertEqual(booster.stage(.atk), 2, "자기 랭크 상승은 안개와 무관하다")
    }

    /// 기술로 깔린다 — 같은 것을 다시 깔면 실패하고(영구 장막 방지), 5턴이 지나면 걷힌다.
    func testAScreenLastsFiveTurnsAndCannotBeRefreshed() throws {
        let reflect = spec(try XCTUnwrap(moveID(calling: .reflect)), damageClass: .status,
                           power: 0, accuracy: nil)
        var field = BattleField()
        var caster = side(), target = side(hp: 9_999)
        var rng = SplitMix64(seed: 4)
        let events = BattleEngine.applyAttack(attacker: &caster, defender: &target,
                                              attackerActor: .a, defenderActor: .b, move: reflect,
                                              field: &field, attackerTeam: .a, rng: &rng)
        XCTAssertTrue(events.contains(.sideConditionStarted(.a, .reflect)))
        XCTAssertTrue(field.has(.reflect, for: .a))
        XCTAssertFalse(field.has(.reflect, for: .b), "상대 편에는 안 깔린다")

        var again = BattleEngine.applyAttack(attacker: &caster, defender: &target,
                                             attackerActor: .a, defenderActor: .b, move: reflect,
                                             field: &field, attackerTeam: .a, rng: &rng)
        XCTAssertTrue(again.contains(.immune(.b)), "이미 깔려 있으면 실패한다")
        again = []

        var ended: [BattleEvent] = []
        for _ in 0..<BattleSideCondition.duration { ended = BattleEngine.advanceField(&field) }
        XCTAssertTrue(ended.contains(.sideConditionEnded(.a, .reflect)))
        XCTAssertFalse(field.has(.reflect, for: .a), "5턴이면 걷힌다")
    }

    /// 이 상태를 까는 기술의 id — 데이터에서 되짚는다(엔진은 반대 방향만 안다).
    private func moveID(calling condition: BattleSideCondition) -> Int? {
        ShowdownMoveData.effects.keys.sorted().first {
            BattleSideCondition.called(byMoveID: $0) == condition
        }
    }

    /// 무브셋 게이트가 이 기술들을 통과시켜야 한다 — 막혀 있으면 아무도 배우지 못해 코드가 죽는다.
    func testSideConditionMovesAreOfferedInMovesets() throws {
        for condition in BattleSideCondition.allCases {
            let move = spec(try XCTUnwrap(moveID(calling: condition)),
                            damageClass: .status, power: 0, accuracy: nil)
            XCTAssertTrue(move.hasModeledStatusEffect,
                          "\(condition) 를 부르는 기술이 무브셋 후보에서 빠진다")
            XCTAssertTrue(VariableDamage.isUsable(move))
        }
    }

    /// `applyAttack` 을 부르는 **모든 모드**가 공격자의 편을 넘겨야 한다. 한 곳만 빠지면 그 모드에서
    /// 장막이 늘 좌변에 깔린다 — 화면에는 정상으로 보이고 누구를 지키는지만 틀린다.
    func testEveryModePassesTheAttackersTeam() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources,
                                                                includingPropertiesForKeys: nil))
        var callersWithoutTeam: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("applyAttack(attacker:"), !text.contains("static func applyAttack") else {
                continue
            }
            if !text.contains("attackerTeam:") { callersWithoutTeam.append(url.lastPathComponent) }
        }
        XCTAssertEqual(callersWithoutTeam, [],
                       "편을 안 넘기면 그 모드의 장막이 엉뚱한 쪽을 지킨다")
    }
}
