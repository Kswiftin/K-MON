import XCTest
@testable import PokeTokenBar

/// 날씨 — **판 전체**에 걸리는 첫 상태다. 어느 한쪽의 `BattleSide` 가 아니라 `BattleField` 에 살고,
/// 배틀 모드 넷(1v1 LAN·연습·웨이브·방)이 각자 하나씩 들고 엔진에 넘긴다.
///
/// 데미지 공식에 날씨를 안 가져오던 유예(`resolveSingleHit` 의 "§3.3 대로 안 가져온다")가 여기서
/// 끝난다. 그래서 이 파일은 위력 배율뿐 아니라 **모드마다 빠뜨리지 않았는지**까지 본다 —
/// 인자로 나르는 상태는 한 자리만 빠져도 그 모드에서만 조용히 날씨가 없다.
final class BattleWeatherTests: XCTestCase {

    private func side(_ types: [PokemonType] = [.normal], hp: Int? = nil) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: types,
                                            base: BattleStats(hp: 100, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: 100),
                                            weightHectograms: 100))
        if let hp { out.hp = hp }
        return out
    }

    private func move(_ id: Int, type: PokemonType = .normal, power: Int = 80,
                      damageClass: MoveDamageClass = .special) -> MoveSpec {
        var out = MoveSpec(id: id, names: ["ko": "기술"], type: type, power: power,
                           damageClass: damageClass, accuracy: nil, pp: 10)
        out.ailment = "none"; out.ailmentChance = 0
        out.statChanges = []; out.statChance = 0; out.targetsUser = false
        return out
    }

    private func attack(_ spec: MoveSpec, field: inout BattleField,
                        attacker: BattleSide, defender: BattleSide,
                        seed: UInt64 = 42) -> (dealt: Int, events: [BattleEvent]) {
        var mine = attacker, theirs = defender
        let before = theirs.hp
        var rng = SplitMix64(seed: seed)
        let events = BattleEngine.applyAttack(attacker: &mine, defender: &theirs,
                                              attackerActor: .a, defenderActor: .b,
                                              move: spec, field: &field, rng: &rng)
        return (before - theirs.hp, events)
    }

    // MARK: 거는 쪽

    /// 날씨기는 날씨를 걸고 그 줄을 남긴다. **같은 날씨를 다시 걸면 실패한다** — 연장되면 한쪽이
    /// 매 턴 다시 걸어 영구 날씨가 되고, 5턴 제한이 아무 뜻도 없어진다.
    func testAWeatherMoveStartsTheWeatherOnceAndThenFails() {
        var field = BattleField()
        let sunnyDay = move(241, power: 0, damageClass: .status)
        let first = attack(sunnyDay, field: &field, attacker: side(), defender: side())
        XCTAssertEqual(field.weather, .sun)
        XCTAssertEqual(field.weatherTurns, BattleWeather.duration)
        XCTAssertTrue(first.events.contains(.weatherStarted(.sun)))

        field.weatherTurns = 2
        let again = attack(sunnyDay, field: &field, attacker: side(), defender: side())
        XCTAssertFalse(again.events.contains(.weatherStarted(.sun)))
        XCTAssertEqual(field.weatherTurns, 2, "다시 걸어도 턴이 늘어나지 않는다")

        let rainDance = move(240, power: 0, damageClass: .status)
        _ = attack(rainDance, field: &field, attacker: side(), defender: side())
        XCTAssertEqual(field.weather, .rain, "다른 날씨는 덮어쓴다")
        XCTAssertEqual(field.weatherTurns, BattleWeather.duration)
    }

    /// 날씨기는 무브셋에 올라갈 수 있어야 한다 — 상태이상도 랭크도 안 거는 변화기라, 게이트를
    /// 안 열면 예전처럼 "코드엔 있는데 아무도 못 배우는" 기술이 된다.
    func testWeatherMovesAreOfferedInMovesets() {
        for id in [241, 240, 201, 883] {
            XCTAssertTrue(move(id, power: 0, damageClass: .status).hasModeledStatusEffect,
                          "id \(id) 를 못 배우면 날씨를 부를 방법이 없다")
            XCTAssertTrue(VariableDamage.isUsable(move(id, power: 0, damageClass: .status)))
        }
    }

    // MARK: 데미지 배율

    /// 볕이 쨍쨍하면 불꽃이 세지고 물이 약해진다. 비는 정확히 반대다 — 한쪽만 보면 부호를 뒤집은
    /// 구현이 통과한다.
    func testSunAndRainPushFireAndWaterInOppositeDirections() {
        let fire = move(1, type: .fire), water = move(2, type: .water)
        var none = BattleField(), sun = BattleField(), rain = BattleField()
        _ = sun.start(.sun); _ = rain.start(.rain)

        let target = side([.normal], hp: 9_999)
        let fireBase = attack(fire, field: &none, attacker: side(), defender: target).dealt
        let waterBase = attack(water, field: &none, attacker: side(), defender: target).dealt

        XCTAssertGreaterThan(attack(fire, field: &sun, attacker: side(), defender: target).dealt,
                             fireBase, "쾌청에서 불꽃은 세진다")
        XCTAssertLessThan(attack(water, field: &sun, attacker: side(), defender: target).dealt,
                          waterBase, "쾌청에서 물은 약해진다")
        XCTAssertGreaterThan(attack(water, field: &rain, attacker: side(), defender: target).dealt,
                             waterBase, "비에서 물은 세진다")
        XCTAssertLessThan(attack(fire, field: &rain, attacker: side(), defender: target).dealt,
                          fireBase, "비에서 불꽃은 약해진다")
    }

    /// 날씨가 안 걸린 타입은 흔들리지 않는다 — 대조군이 없으면 "전부 1.5배" 오구현이 통과한다.
    func testWeatherLeavesUnrelatedTypesAlone() {
        let normal = move(3, type: .normal)
        var none = BattleField(), sun = BattleField()
        _ = sun.start(.sun)
        let target = side([.normal], hp: 9_999)
        XCTAssertEqual(attack(normal, field: &sun, attacker: side(), defender: target).dealt,
                       attack(normal, field: &none, attacker: side(), defender: target).dealt)
    }

    // MARK: 턴 끝

    /// 모래바람은 턴 끝에 깎는다 — 바위·땅·강철만 빼고. 눈은 9세대부터 깎지 않는다.
    func testSandstormChipsOnlyTheTypesItShould() {
        var field = BattleField()
        _ = field.start(.sandstorm)
        var exposed = side([.normal])
        let events = BattleEngine.endOfTurnWeather(&exposed, actor: .a, field: field)
        XCTAssertEqual(exposed.stats.hp - exposed.hp, max(1, exposed.stats.hp / 16))
        XCTAssertTrue(events.contains { if case .damage(_, _, .weather) = $0 { return true }
                                        return false })

        for type in [PokemonType.rock, .ground, .steel] {
            var immune = side([type])
            XCTAssertEqual(BattleEngine.endOfTurnWeather(&immune, actor: .a, field: field), [],
                           "\(type) 는 모래에 안 깎인다")
            XCTAssertEqual(immune.hp, immune.stats.hp)
        }

        var snowy = BattleField()
        _ = snowy.start(.snow)
        var inSnow = side([.normal])
        XCTAssertEqual(BattleEngine.endOfTurnWeather(&inSnow, actor: .a, field: snowy), [],
                       "눈은 데미지가 없다(9세대) — 있으면 싸라기눈 시절 규칙으로 돈다")
    }

    /// 모래에 쓰러지면 기절 줄이 따라 나온다 — 안 내면 HP 0 인 개체가 살아 있는 것처럼 남는다.
    func testSandstormFaintReportsIt() {
        var field = BattleField()
        _ = field.start(.sandstorm)
        var dying = side([.normal], hp: 1)
        let events = BattleEngine.endOfTurnWeather(&dying, actor: .a, field: field)
        XCTAssertEqual(events.last, .faint(.a))
    }

    /// 날씨는 5턴 뒤에 끝나고 그 줄을 남긴다. 개체 수와 무관하게 **턴마다 한 번** 줄어야 한다 —
    /// 개체마다 줄이면 2:2 웨이브에서 날씨가 절반만 간다.
    func testWeatherExpiresAfterFiveTurnsAndSaysSo() {
        var field = BattleField()
        _ = field.start(.rain)
        for turn in 1..<BattleWeather.duration {
            XCTAssertEqual(BattleEngine.advanceField(&field), [], "\(turn)턴째엔 아직 안 끝난다")
            XCTAssertEqual(field.weather, .rain)
        }
        XCTAssertEqual(BattleEngine.advanceField(&field), [.weatherEnded(.rain)])
        XCTAssertNil(field.weather)
        XCTAssertEqual(BattleEngine.advanceField(&field), [], "끝난 뒤엔 아무 일도 없다")
    }

    /// 한 턴을 통째로 굴려도 같은 규칙이어야 한다 — 엔진 밖에서 손으로 부른 것과 갈리면
    /// 실제 배틀에서만 다른 값이 나온다.
    func testAFullTurnAdvancesTheWeatherExactlyOnce() {
        var field = BattleField()
        _ = field.start(.sandstorm)
        var a = side([.normal], hp: 9_999), b = side([.normal], hp: 9_999)
        var rng = SplitMix64(seed: 3)
        let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: move(3), moveB: move(3),
                                              turn: 1, field: &field, rng: &rng)
        XCTAssertEqual(field.weatherTurns, BattleWeather.duration - 1)
        XCTAssertEqual(events.filter { if case .damage(_, _, .weather) = $0 { return true }
                                       return false }.count, 2, "모래는 양쪽을 깎는다")
    }

    // MARK: 필드 (땅에 깔리는 쪽)

    private func flying() -> BattleSide { side([.flying], hp: 9_999) }

    /// 필드기는 필드를 깔고 그 줄을 남긴다. 무브셋 게이트도 같이 열려 있어야 한다 —
    /// 안 열면 날씨기와 똑같이 "코드엔 있는데 아무도 못 배우는" 기술이 된다.
    func testATerrainMoveStartsTheTerrainAndIsLearnable() {
        var field = BattleField()
        let electricTerrain = move(604, power: 0, damageClass: .status)
        let events = attack(electricTerrain, field: &field, attacker: side(), defender: side()).events
        XCTAssertEqual(field.terrain, .electric)
        XCTAssertEqual(field.terrainTurns, BattleTerrain.duration)
        XCTAssertTrue(events.contains(.terrainStarted(.electric)))
        for id in [604, 580, 581, 678] {
            XCTAssertTrue(move(id, power: 0, damageClass: .status).hasModeledStatusEffect,
                          "id \(id) 를 못 배우면 필드를 깔 방법이 없다")
        }
    }

    /// 필드 보정은 **땅에 닿은 쪽만** 받는다. 뜬 쪽까지 받으면 필드와 날씨의 차이가 사라진다.
    func testTerrainBoostsOnlyGroundedAttackers() {
        var none = BattleField(), electric = BattleField()
        _ = electric.start(.electric)
        let bolt = move(1, type: .electric)
        let target = side([.normal], hp: 9_999)

        let base = attack(bolt, field: &none, attacker: side(), defender: target).dealt
        XCTAssertGreaterThan(attack(bolt, field: &electric, attacker: side(), defender: target).dealt,
                             base, "땅에 닿은 쪽은 1.3배")
        XCTAssertEqual(attack(bolt, field: &electric, attacker: flying(), defender: target).dealt,
                       attack(bolt, field: &none, attacker: flying(), defender: target).dealt,
                       "뜬 쪽은 필드를 안 받는다")
    }

    /// 미스트필드는 올리는 게 아니라 **드래곤을 반으로** 깎는다 — 맞는 쪽이 땅에 닿았을 때만이다.
    func testMistyTerrainHalvesDragonAgainstGroundedTargets() {
        var none = BattleField(), misty = BattleField()
        _ = misty.start(.misty)
        let dragonMove = move(2, type: .dragon)
        let grounded = side([.normal], hp: 9_999)

        XCTAssertLessThan(attack(dragonMove, field: &misty, attacker: side(), defender: grounded).dealt,
                          attack(dragonMove, field: &none, attacker: side(), defender: grounded).dealt)
        XCTAssertEqual(attack(dragonMove, field: &misty, attacker: side(), defender: flying()).dealt,
                       attack(dragonMove, field: &none, attacker: side(), defender: flying()).dealt,
                       "뜬 상대는 안개의 보호를 못 받는다")
    }

    /// 일렉트릭필드는 잠듦만, 미스트필드는 주 상태 전부를 막는다 — 땅에 닿은 쪽만이다.
    func testTerrainBlocksTheStatusesItShould() {
        var sleepMove = move(79, power: 0, damageClass: .status)
        sleepMove.ailment = "sleep"; sleepMove.ailmentChance = 0
        var electric = BattleField(), misty = BattleField(), none = BattleField()
        _ = electric.start(.electric); _ = misty.start(.misty)

        XCTAssertNotNil(afflicted(sleepMove, field: &none), "필드가 없으면 잠든다")
        XCTAssertNil(afflicted(sleepMove, field: &electric), "일렉트릭필드는 잠들지 않는다")
        XCTAssertNil(afflicted(sleepMove, field: &misty), "미스트필드도 막는다")
        XCTAssertNotNil(afflicted(sleepMove, field: &electric, target: flying()),
                        "뜬 쪽은 필드가 안 지켜 준다")

        var burnMove = move(261, power: 0, damageClass: .status)
        burnMove.ailment = "burn"; burnMove.ailmentChance = 0
        XCTAssertNotNil(afflicted(burnMove, field: &electric),
                        "일렉트릭필드는 잠듦만 막는다 — 화상까지 막으면 미스트필드와 구별이 없다")
        XCTAssertNil(afflicted(burnMove, field: &misty))
    }

    /// 상태가 걸렸으면 그 상태를, 아니면 nil.
    private func afflicted(_ spec: MoveSpec, field: inout BattleField,
                           target: BattleSide? = nil) -> Status? {
        var mine = side(), theirs = target ?? side([.normal], hp: 9_999)
        var rng = SplitMix64(seed: 4)
        _ = BattleEngine.applyAttack(attacker: &mine, defender: &theirs, attackerActor: .a,
                                     defenderActor: .b, move: spec, field: &field, rng: &rng)
        return theirs.status
    }

    /// 그래스필드는 땅에 닿은 쪽을 턴 끝에 회복시킨다. 모래와 **같은 자리**라 둘 다 걸리면
    /// 회복이 먼저다 — 순서가 바뀌면 모래에 쓰러진 개체가 그 턴에 되살아난다.
    func testGrassyTerrainHealsGroundedAndStillTakesTheSandstorm() {
        var field = BattleField()
        _ = field.start(.grassy)
        var hurt = side([.normal], hp: 10)
        let healed = BattleEngine.endOfTurnWeather(&hurt, actor: .a, field: field)
        XCTAssertEqual(hurt.hp, 10 + max(1, hurt.stats.hp / 16))
        XCTAssertTrue(healed.contains { if case .heal = $0 { return true }; return false })

        var floating = flying()
        floating.hp = 10
        XCTAssertEqual(BattleEngine.endOfTurnWeather(&floating, actor: .a, field: field), [],
                       "뜬 쪽은 풀에 안 닿는다")

        _ = field.start(.sandstorm)
        var both = side([.normal], hp: 10)
        let events = BattleEngine.endOfTurnWeather(&both, actor: .a, field: field)
        XCTAssertEqual(events.count, 2, "회복과 모래가 둘 다 나온다")
        if case .heal = events[0] {} else { XCTFail("회복이 먼저여야 한다") }
    }

    /// 라이징볼트는 일렉트릭필드 위의 **상대**에게 두 배다.
    func testRisingVoltageDoublesOnElectricTerrain() {
        let risingVoltage = move(VariableDamage.MoveID.risingVoltage, type: .electric, power: 70)
        var electric = BattleField()
        _ = electric.start(.electric)
        var rng = SplitMix64(seed: 1)
        XCTAssertEqual(VariableDamage.from(risingVoltage, attacker: side(), defender: side(),
                                           field: BattleField(), rng: &rng), .power(70))
        XCTAssertEqual(VariableDamage.from(risingVoltage, attacker: side(), defender: side(),
                                           field: electric, rng: &rng), .power(140))
        XCTAssertEqual(VariableDamage.from(risingVoltage, attacker: side(), defender: flying(),
                                           field: electric, rng: &rng), .power(70),
                       "뜬 상대는 필드 위에 없다")
    }

    /// 필드도 5턴이다. 날씨와 **같이** 걸려 있으면 둘 다 각자 줄어야 한다 — 한 카운터를 나눠 쓰면
    /// 나중에 깐 쪽이 먼저 걸린 쪽의 남은 턴을 물려받는다.
    func testWeatherAndTerrainCountDownIndependently() {
        var field = BattleField()
        _ = field.start(.rain)
        _ = BattleEngine.advanceField(&field)
        _ = field.start(.psychic)
        XCTAssertEqual(field.weatherTurns, BattleWeather.duration - 1)
        XCTAssertEqual(field.terrainTurns, BattleTerrain.duration)

        var ended: [BattleEvent] = []
        for _ in 0..<BattleTerrain.duration { ended += BattleEngine.advanceField(&field) }
        XCTAssertEqual(ended, [.weatherEnded(.rain), .terrainEnded(.psychic)],
                       "비가 먼저 끝나고 필드가 나중에 끝난다")
        XCTAssertNil(field.weather)
        XCTAssertNil(field.terrain)
    }

    // MARK: 모드마다 빠뜨리지 않았는지

    /// `applyAttack` 을 부르는 곳은 **전부** 날씨를 넘겨야 한다. 한 곳만 빠지면 그 모드에서만
    /// 날씨가 없고, 화면에는 정상으로 보이며 숫자만 틀린다(`beginTurn` 가드와 같은 이유).
    func testEveryBattleModePassesTheFieldThrough() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources,
                                                                includingPropertiesForKeys: nil))
        var gaps: [String] = []
        var callers = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // 정의가 아니라 **호출**만 본다.
            guard text.contains("applyAttack(attacker:"), !text.contains("static func applyAttack")
            else { continue }
            callers += 1
            // 호출 하나를 인자 목록 끝까지 훑는다 — 창이 짧으면 인자를 다 못 담아 있는데 없다고 읽는다.
            var rest = Substring(text)
            while let start = rest.range(of: "applyAttack(attacker:") {
                let after = rest[start.upperBound...]
                let end = after.range(of: "applyAttack(attacker:")?.lowerBound ?? after.endIndex
                if !after[..<end].prefix(600).contains("field:") {
                    gaps.append("\(url.lastPathComponent): applyAttack")
                }
                rest = after
            }
            // 잔뎀을 넣는 턴 루프면 날씨 몫과 남은 턴도 같이 봐야 한다.
            if text.contains("endOfTurnResidual(") {
                if !text.contains("endOfTurnWeather(") { gaps.append("\(url.lastPathComponent): 날씨 잔뎀") }
                if !text.contains("advanceField(") { gaps.append("\(url.lastPathComponent): 남은 턴") }
            }
        }
        XCTAssertEqual(gaps, [], "이 모드에서만 날씨가 없다 — 화면은 정상이고 숫자만 틀린다")
        XCTAssertGreaterThanOrEqual(callers, 4, "호출자를 못 찾았으면 스캔이 고장 난 것이다")
    }
}
