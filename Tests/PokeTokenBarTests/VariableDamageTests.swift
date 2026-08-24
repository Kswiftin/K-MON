import XCTest
@testable import PokeTokenBar

/// PokéAPI 가 `power: null` 로 주는 공격기(1~5세대 37개).
///
/// 회귀 원본: `MoveSpec.from` 이 null 을 0 에 접고 엔진이 `power <= 0` 을 변화기로 봐서,
/// 일렉트릭볼·지구던지기 같은 공격기가 **PP 만 태우고 로그 한 줄만 남기는** 죽은 기술이었다.
/// 상성도 안 탔다(전기가 물에게 2배로 안 들어갔다).
final class VariableDamageTests: XCTestCase {

    // MARK: 고정 재료

    /// 종족값 전부 100(스피드만 인자) Lv.50. **기대값은 종족값이 아니라 유효 스탯에서 뽑는다** —
    /// 엔진이 보는 건 레벨·개체값이 반영된 값이라, 종족값 비율로 기대값을 쓰면 다른 걸 재게 된다.
    private func side(_ types: [PokemonType] = [.normal], level: Int = 50,
                      speed: Int = 100, hp: Int? = nil, weight: Int? = nil) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: level,
                                            nature: nil, isShiny: false, types: types,
                                            base: BattleStats(hp: 100, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: speed),
                                            weightHectograms: weight))
        if let hp { out.hp = hp }
        return out
    }

    private func spec(_ id: Int, type: PokemonType = .normal,
                      damageClass: MoveDamageClass = .physical, accuracy: Int? = 100) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "기술"], type: type, power: 0,
                            damageClass: damageClass, accuracy: accuracy, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0; move.targetsUser = false
        return move
    }

    // MARK: 위력 — 순수 계산

    /// 일렉트릭볼은 **상대보다 빠를수록** 세고, 자이로볼은 그 반대다. 둘을 같이 잠근다 —
    /// 비율의 분자·분모를 뒤집는 오구현은 한쪽만 보면 통과한다.
    func testSpeedRatioMovesRunInOppositeDirections() {
        let slow = side(speed: 50), fast = side(speed: 400)
        XCTAssertEqual(VariableDamage.electroBallPower(attacker: slow, defender: fast), 40,
                       "느린 쪽이 쓰면 최저 위력이다")
        XCTAssertEqual(VariableDamage.electroBallPower(attacker: fast, defender: slow), 150)
        XCTAssertEqual(VariableDamage.gyroBallPower(attacker: fast, defender: slow), 1 + 25 *
                       slow.effectiveSpeed / fast.effectiveSpeed,
                       "빠른 쪽이 쓰면 자이로볼은 약하다")
        XCTAssertEqual(VariableDamage.gyroBallPower(attacker: side(speed: 5), defender: side(speed: 400)),
                       150, "상한 150 을 넘지 않는다")
    }

    /// 동속에서 일렉트릭볼은 최저(40)다 — `<=` 를 `<` 로 쓰면 동속이 한 칸 위로 새어 나간다.
    func testElectroBallAtEqualSpeedIsTheFloor() {
        XCTAssertEqual(VariableDamage.electroBallPower(attacker: side(speed: 100),
                                                       defender: side(speed: 100)), 40)
    }

    /// 기사회생은 내 HP 가, 목조르기는 상대 HP 가 기준이다. 방향이 반대라 같이 본다.
    func testHealthRatioMovesUseOppositeSides() {
        let full = side(), nearlyDead = side(hp: 1)
        XCTAssertEqual(VariableDamage.lowHealthPower(full), 20)
        XCTAssertEqual(VariableDamage.lowHealthPower(nearlyDead), 200)
        XCTAssertEqual(VariableDamage.targetHealthPower(full), 120)
        XCTAssertEqual(VariableDamage.targetHealthPower(nearlyDead), 1,
                       "빈사인 상대에게도 최소 1 은 나온다(0 이면 데미지 줄이 사라진다)")
    }

    /// 응징은 상대가 **올린** 랭크만 센다. 내린 랭크까지 세면 상대를 깎아 놓고 응징이 세진다.
    func testPunishmentCountsOnlyRaisedStages() {
        var target = side()
        target.changeStage(.atk, by: 2)
        target.changeStage(.def, by: -3)
        XCTAssertEqual(VariableDamage.punishmentPower(target), 100, "60 + 20×2")
        var maxed = side()
        for stat in BattleStat.allCases { maxed.changeStage(stat, by: 6) }
        XCTAssertEqual(VariableDamage.punishmentPower(maxed), 200, "상한 200")
    }

    /// 체중은 **헥토그램**(0.1kg)이다 — PokéAPI 단위이자 본가가 위력 구간을 나누는 단위다.
    /// kg 으로 바꾸면 10.0kg 같은 경계에서 소수점 때문에 한 칸씩 밀린다. 경계값을 같이 잠근다.
    func testWeightPowerUsesHectogramBoundaries() {
        XCTAssertEqual(VariableDamage.targetWeightPower(60), 20, "피카츄 6kg")
        XCTAssertEqual(VariableDamage.targetWeightPower(99), 20, "9.9kg 은 아직 최저 구간")
        XCTAssertEqual(VariableDamage.targetWeightPower(100), 40, "10.0kg 부터 한 칸 올라간다")
        XCTAssertEqual(VariableDamage.targetWeightPower(1999), 100)
        XCTAssertEqual(VariableDamage.targetWeightPower(2000), 120, "200kg 부터 최대")
    }

    /// 저공격은 **상대** 체중, 헤비봄버는 **둘의 비율**이다. 방향이 반대라 같이 본다 —
    /// 분자·분모를 뒤집은 오구현은 한쪽만 보면 통과한다.
    func testWeightMovesReadOppositeSides() {
        XCTAssertEqual(VariableDamage.weightRatioPower(attacker: 1000, defender: 1000), 40,
                       "동체중이면 최저")
        XCTAssertEqual(VariableDamage.weightRatioPower(attacker: 2000, defender: 1000), 60,
                       "정확히 2배가 경계 안쪽이다")
        XCTAssertEqual(VariableDamage.weightRatioPower(attacker: 5000, defender: 1000), 120,
                       "5배부터 최대")
        XCTAssertEqual(VariableDamage.weightRatioPower(attacker: 60, defender: 3600), 40,
                       "내가 훨씬 가벼우면 최저 — 상대 체중만 보는 구현이면 여기서 갈린다")
    }

    // MARK: 엔진 — 한 턴

    private func attack(_ move: MoveSpec, _ attacker: BattleSide, _ defender: BattleSide,
                        seed: UInt64 = 42) -> (dealt: Int, events: [BattleEvent], attacker: BattleSide) {
        var mine = attacker, theirs = defender
        let before = theirs.hp
        var rng = SplitMix64(seed: seed)
        let events = BattleEngine.applyAttack(attacker: &mine, defender: &theirs,
                                              attackerActor: .a, defenderActor: .b,
                                              move: move, rng: &rng)
        return (before - theirs.hp, events, mine)
    }

    /// **원본 결함.** 이 단언이 죽으면 일렉트릭볼 부류가 다시 PP 만 태운다.
    func testAVariablePowerMoveActuallyDealsDamageAndTakesTypeEffectiveness() {
        let electroBall = spec(VariableDamage.MoveID.electroBall, type: .electric, damageClass: .special)
        let result = attack(electroBall, side([.electric], speed: 400), side([.water], speed: 50))
        XCTAssertGreaterThan(result.dealt, 0, "위력 0 으로 접히면 PP 만 태우는 죽은 기술이 된다")
        XCTAssertTrue(result.events.contains { if case .superEffective = $0 { return true }; return false },
                      "공격기이므로 상성을 탄다 — 전기는 물에게 2배다")
    }

    /// 고정 데미지는 공식을 타지 않는다. 상성은 **면역만** 본다.
    func testFixedDamageIgnoresTheFormulaButNotImmunity() {
        let nightShade = spec(VariableDamage.MoveID.nightShade, type: .ghost, damageClass: .special)
        let hit = attack(nightShade, side([.ghost], level: 37), side([.psychic]))
        XCTAssertEqual(hit.dealt, 37, "레벨만큼만 깎는다 — 상성 2배도 급소도 곱해지지 않는다")
        XCTAssertFalse(hit.events.contains { if case .crit = $0 { return true }; return false },
                       "공식을 안 탄 기술에 급소 문구가 붙으면 배율이 곱해진 것처럼 읽힌다")

        let blocked = attack(nightShade, side([.ghost], level: 37), side([.normal]))
        XCTAssertEqual(blocked.dealt, 0)
        XCTAssertTrue(blocked.events.contains { if case .immune = $0 { return true }; return false })
    }

    /// 일격필살은 레벨이 높은 상대에게 통하지 않는다. **그리고 통하지 않았다고 말해야 한다** —
    /// 데미지 0 으로만 끝내면 로그가 기술명 한 줄뿐이라, 고치려던 그 무반응이 그대로 재현된다.
    func testAOneHitKOFailsAgainstAHigherLevelAndSaysSo() {
        let fissure = spec(VariableDamage.MoveID.fissure, type: .ground, accuracy: 30)
        let blocked = attack(fissure, side([.ground], level: 50), side([.normal], level: 80))
        XCTAssertEqual(blocked.dealt, 0)
        XCTAssertTrue(blocked.events.contains { if case .immune = $0 { return true }; return false },
                      "실패도 줄을 남겨야 한다")
    }

    /// 일격필살은 **공식을 안 탄다** — 배율 문구를 붙이면 상성·급소가 곱해진 것처럼 읽힌다.
    /// 억제하는 주체는 플래그가 아니라 `fixedOutcome` 이다(상성을 1, 급소를 false 로 못박는다).
    /// 지구쪼개기(땅)를 전기 타입에게 쓴다 — 상성표를 타면 2배라, 억제가 풀리면 여기서 새어 나온다.
    func testAOneHitKOSuppressesTheCritAndEffectivenessLines() throws {
        let fissure = spec(VariableDamage.MoveID.fissure, type: .ground, accuracy: 30)
        var landed: (dealt: Int, events: [BattleEvent], attacker: BattleSide)?
        for seed in UInt64(1)...200 where landed == nil {
            let result = attack(fissure, side([.ground], level: 50), side([.electric], level: 50), seed: seed)
            if result.dealt > 0 { landed = result }
        }
        let hit = try XCTUnwrap(landed, "200 seed 안에 한 번도 안 맞았다")

        XCTAssertFalse(hit.events.contains { if case .crit = $0 { return true }; return false },
                       "공식을 안 탄 기술에 급소 문구를 붙이면 배율이 곱해진 것처럼 읽힌다")
        XCTAssertFalse(hit.events.contains { if case .superEffective = $0 { return true }; return false },
                       "땅 → 전기는 상성표로 2배지만, 일격필살은 배율을 쓰지 않는다")
        XCTAssertFalse(hit.events.contains { if case .resisted = $0 { return true }; return false })
    }

    /// 맞으면 남은 HP 와 무관하게 쓰러진다.
    func testAOneHitKOEmptiesTheTargetWhenItLands() {
        let fissure = spec(VariableDamage.MoveID.fissure, type: .ground, accuracy: 30)
        // 명중 30% 라 맞는 seed 를 찾아 쓴다. seed 를 고정으로 박으면 rng 순서가 바뀔 때 조용히 죽는다.
        let landing = (UInt64(1)...300).first { seed in
            attack(fissure, side([.ground], level: 50), side([.normal], level: 50), seed: seed).dealt > 0
        }
        XCTAssertNotNil(landing, "300 시드 안에 한 번도 안 맞으면 명중 판정 쪽이 깨진 것이다")
        let hit = attack(fissure, side([.ground], level: 50), side([.normal], level: 50),
                         seed: landing ?? 1)
        XCTAssertEqual(hit.dealt, side([.normal], level: 50).stats.hp, "남은 HP 를 전부 가져간다")
        XCTAssertTrue(hit.events.contains { if case .faint = $0 { return true }; return false })
    }

    /// 자폭기는 데미지를 넣은 **뒤에** 자기가 쓰러진다.
    func testFinalGambitSpendsTheUsersRemainingHealth() {
        let gambit = spec(VariableDamage.MoveID.finalGambit, type: .fighting)
        let result = attack(gambit, side([.fighting], hp: 90), side([.normal]))
        XCTAssertEqual(result.dealt, 90, "내 남은 HP 만큼 넣는다")
        XCTAssertEqual(result.attacker.hp, 0)
        XCTAssertTrue(result.events.contains { if case .faint(.a) = $0 { return true }; return false })
    }

    /// 체중이 실제로 위력에 실리는지 — 순수 함수가 아니라 **엔진을 통과시켜** 본다.
    func testAWeightMoveHitsHarderAgainstAHeavierTarget() {
        let grassKnot = spec(VariableDamage.MoveID.grassKnot, type: .grass, damageClass: .special)
        let heavy = attack(grassKnot, side([.grass]), side([.ground], weight: 3000))
        let light = attack(grassKnot, side([.grass]), side([.ground], weight: 60))
        XCTAssertGreaterThan(heavy.dealt, light.dealt, "300kg 이 6kg 보다 아파야 한다")
    }

    /// 체중을 못 받아왔으면 **실패시킨다.** 0 으로 접으면 저공격이 모든 상대에게 최저 위력으로
    /// 나가고, 그게 맞는 값인지 화면에서 구별할 수 없다. 헤비봄버는 0 나눗셈 자리이기도 하다.
    func testAWeightMoveFailsLoudlyWhenTheWeightIsMissing() {
        let grassKnot = spec(VariableDamage.MoveID.grassKnot, type: .grass, damageClass: .special)
        let result = attack(grassKnot, side([.grass]), side([.ground], weight: nil))
        XCTAssertEqual(result.dealt, 0)
        XCTAssertTrue(result.events.contains { if case .immune = $0 { return true }; return false },
                      "조용히 0 을 넣으면 고치려던 그 무반응이 된다")

        let heavySlam = spec(VariableDamage.MoveID.heavySlam, type: .steel)
        let noSelfWeight = attack(heavySlam, side([.steel], weight: nil), side([.normal], weight: 100))
        XCTAssertEqual(noSelfWeight.dealt, 0, "내 체중이 없어도 마찬가지다")
    }

    // MARK: 되돌려주기 — 한 턴 전체

    private func counterMove(_ id: Int, type: PokemonType,
                             damageClass: MoveDamageClass) -> MoveSpec {
        var move = spec(id, type: type, damageClass: damageClass)
        move.priority = -5      // 카운터·미러코트는 늘 후공이다 — 맞고 나서 되받아야 하므로
        return move
    }

    private func plainMove(_ id: Int, damageClass: MoveDamageClass) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "보통기술"], type: .normal, power: 60,
                            damageClass: damageClass, accuracy: 100, pp: 20)
        move.statChanges = []; move.targetsUser = false
        return move
    }

    /// 상대가 때리고 내가 되돌려준다. `applyAttack` 한 번이 아니라 **턴 전체**를 돌려야
    /// 의미가 있다 — 맞은 기록이 턴 안에서 만들어지고 읽히기 때문이다.
    /// 되돌려주는 쪽은 **느리게** 둔다. 카운터·미러코트는 우선도 −5 라 순서가 저절로 맞지만,
    /// 메탈버스트는 우선도 0 이라 동속이면 선공을 잡을 수 있다 — 그러면 맞은 게 없어 실패한다.
    /// 동속으로 두면 rng 가 순서를 정해 테스트가 seed 에 따라 흔들린다.
    private func counterTurn(_ counter: MoveSpec, against incoming: MoveSpec)
        -> (taken: Int, returned: Int, events: [BattleEvent]) {
        var attacker = side([.normal], speed: 200), counterer = side([.fighting], speed: 50)
        var rng = SplitMix64(seed: 7)
        let attackerHP = attacker.hp
        let events = BattleEngine.resolveTurn(a: &attacker, b: &counterer, moveA: incoming,
                                              moveB: counter, turn: 1, rng: &rng)
        return (counterer.stats.hp - counterer.hp, attackerHP - attacker.hp, events)
    }

    /// 카운터는 물리만, 미러코트는 특수만 되돌려준다. 분류를 안 보는 오구현은 한쪽만 보면 통과한다.
    func testCounterAndMirrorCoatOnlyReturnTheirOwnDamageClass() {
        let counter = counterMove(VariableDamage.MoveID.counter, type: .fighting, damageClass: .physical)
        let mirrorCoat = counterMove(VariableDamage.MoveID.mirrorCoat, type: .psychic, damageClass: .special)
        let physical = plainMove(33, damageClass: .physical)
        let special = plainMove(129, damageClass: .special)

        let countered = counterTurn(counter, against: physical)
        XCTAssertEqual(countered.returned, countered.taken * 2, "맞은 양의 2배를 돌려준다")

        let wrongClass = counterTurn(counter, against: special)
        XCTAssertEqual(wrongClass.returned, 0, "카운터는 특수기를 되받지 못한다")
        XCTAssertTrue(wrongClass.events.contains { if case .immune = $0 { return true }; return false },
                      "실패도 줄을 남겨야 한다")

        let coated = counterTurn(mirrorCoat, against: special)
        XCTAssertEqual(coated.returned, coated.taken * 2)
        XCTAssertEqual(counterTurn(mirrorCoat, against: physical).returned, 0,
                       "미러코트는 물리기를 되받지 못한다")
    }

    /// **초기화 회귀.** 턴 시작에 기록을 안 비우면 지난 턴 데미지가 되돌아온다 —
    /// 화면에는 정상으로 보이고 숫자만 틀리는 부류라 눈으로는 못 잡는다.
    func testTheIncomingHitDoesNotLeakIntoTheNextTurn() {
        let counter = counterMove(VariableDamage.MoveID.counter, type: .fighting, damageClass: .physical)
        let physical = plainMove(33, damageClass: .physical)
        var status = spec(45, type: .normal, damageClass: .status, accuracy: nil)
        status.statChanges = []

        var attacker = side([.normal]), counterer = side([.fighting])
        var rng = SplitMix64(seed: 7)
        _ = BattleEngine.resolveTurn(a: &attacker, b: &counterer, moveA: physical, moveB: physical,
                                     turn: 1, rng: &rng)
        let attackerHP = attacker.hp
        // 2턴째엔 상대가 변화기를 쓴다 — 이번 턴에 맞은 게 없으니 카운터는 실패해야 한다.
        _ = BattleEngine.resolveTurn(a: &attacker, b: &counterer, moveA: status, moveB: counter,
                                     turn: 2, rng: &rng)
        XCTAssertEqual(attackerHP - attacker.hp, 0, "1턴째 데미지가 2턴째에 되돌아오면 안 된다")
    }

    /// 메탈버스트는 분류를 안 가리는 대신 배율이 1.5 배다.
    func testMetalBurstReturnsEitherClassAtALowerRate() {
        var metalBurst = spec(VariableDamage.MoveID.metalBurst, type: .steel)
        metalBurst.priority = 0
        let special = plainMove(129, damageClass: .special)
        let result = counterTurn(metalBurst, against: special)
        XCTAssertEqual(result.returned, result.taken * 3 / 2, "특수기도 받되 1.5 배다")
    }

    /// `applyAttack` 을 직접 부르는 턴 루프는 **전부** 기록을 비워야 한다. 한 곳만 빠지면
    /// 그 모드에서만 카운터가 지난 턴 데미지를 되돌려준다. 새 모드가 생기면 여기서 먼저 깨진다.
    func testEveryTurnLoopClearsTheIncomingHit() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources,
                                                                includingPropertiesForKeys: nil))
        var loopsWithoutReset: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // 정의(`static func applyAttack`)가 아니라 **호출**만 센다.
            let callsApplyAttack = text.contains("applyAttack(attacker:")
                && !text.contains("static func applyAttack")
            let isEngine = url.lastPathComponent == "BattleModel.swift"
            guard callsApplyAttack || isEngine else { continue }
            if !text.contains("beginTurn(") { loopsWithoutReset.append(url.lastPathComponent) }
        }
        XCTAssertEqual(loopsWithoutReset, [],
                       "턴 루프가 기록을 안 비우면 그 모드에서만 카운터가 지난 턴 값을 되돌려준다")
    }

    /// 대조군 — 보통 공격기는 이 변경에 흔들리지 않아야 한다. 없으면 "전부 고정 데미지로 바꾸기"
    /// 같은 오구현이 위 테스트를 전부 통과한다.
    func testAnOrdinaryMoveStillGoesThroughTheFormula() {
        var spark = MoveSpec(id: 209, names: ["ko": "스파크"], type: .electric, power: 65,
                             damageClass: .physical, accuracy: 100, pp: 20)
        spark.statChanges = []; spark.targetsUser = false
        let result = attack(spark, side([.electric]), side([.water]))
        XCTAssertGreaterThan(result.dealt, 65, "STAB·상성·급소가 곱해지므로 위력 숫자보다 크다")
        var rng = SplitMix64(seed: 1)
        XCTAssertNil(VariableDamage.from(spark, attacker: side(), defender: side(), rng: &rng),
                     "보통 기술은 가변 위력 표에 없다")
    }

    // MARK: 아직 모델링하지 않은 기술

    /// 위력을 못 뽑는 기술은 무브셋 후보에서 뺀다 — 넣으면 예전과 똑같이 죽은 칸이 된다.
    func testUnmodeledMovesAreKeptOutOfMovesets() {
        XCTAssertFalse(VariableDamage.isUsable(spec(216)), "은혜갚기(친밀도)는 아직 못 뽑는다")
        XCTAssertFalse(VariableDamage.isUsable(spec(251)), "집단구타(파티 + 다단 히트)도 마찬가지")
        XCTAssertTrue(VariableDamage.isUsable(spec(VariableDamage.MoveID.counter)),
                      "맞은 기록이 들어온 뒤로 카운터는 풀렸다")
        XCTAssertTrue(VariableDamage.isUsable(spec(VariableDamage.MoveID.electroBall)),
                      "구현한 기술까지 막으면 고친 의미가 없다")
        XCTAssertTrue(VariableDamage.isUsable(spec(VariableDamage.MoveID.lowKick)),
                      "체중이 들어온 뒤로 저공격은 풀렸다")
        XCTAssertTrue(VariableDamage.isUsable(spec(209)), "보통 기술은 당연히 통과")
    }

    /// 스냅샷에만 실려 나가는 옵셔널 축(체중·특성)을 한 자리라도 빠뜨리면 **그 모드에서만** 조용히
    /// 동작이 달라진다. 전부 기본값 `nil` 인 옵셔널 인자라 컴파일러가 못 잡으므로 소스에서 직접 센다.
    /// 스냅샷을 만드는 새 자리가 생기면 이 테스트가 먼저 깨진다.
    ///
    /// 축마다 스캔을 따로 두지 않는다 — 같은 순회를 두 벌 들고 있으면 새 자리가 생겼을 때
    /// 한쪽만 고치게 된다. 새 옵셔널 축은 이 배열에 이름만 더한다.
    func testEveryBattleSnapshotSiteCarriesTheWireOnlyFields() throws {
        // 인자 목록 전체를 담을 만큼 넉넉해야 한다. 창이 짧으면 **있는데 없다고** 읽는다
        // (체육관 스냅샷이 특성 인자가 붙으면서 400자를 넘겨 실제로 그렇게 실패했다).
        let window = 800
        let required = ["weightHectograms:", "ability:"]
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources,
                                                                includingPropertiesForKeys: nil))
        var gaps: [String] = []
        var sites = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `BattleSnapshot(` 로 시작하는 호출 하나를 인자 목록 끝까지 훑는다.
            var rest = Substring(text)
            while let start = rest.range(of: "BattleSnapshot(") {
                let call = rest[start.upperBound...].prefix(window)
                sites += 1
                for field in required where !call.contains(field) {
                    gaps.append("\(url.lastPathComponent): \(field)")
                }
                rest = rest[start.upperBound...]
            }
        }
        XCTAssertEqual(gaps, [],
                       "체중을 빠뜨리면 저공격·헤비봄버가 그 상대에게만 실패하고, 특성을 빠뜨리면 그 모드만 특성이 없다")
        XCTAssertGreaterThanOrEqual(sites, 4, "스냅샷 생성 자리를 하나도 못 찾았으면 스캔이 고장난 것이다")
    }

    /// 구현한 id 와 뺀 id 가 겹치면, 구현해 놓고 후보에서 빼는 모순이 조용히 생긴다.
    func testTheImplementedAndUnmodeledSetsDoNotOverlap() {
        let implemented: Set<Int> = [
            VariableDamage.MoveID.guillotine, VariableDamage.MoveID.hornDrill,
            VariableDamage.MoveID.sonicBoom, VariableDamage.MoveID.seismicToss,
            VariableDamage.MoveID.dragonRage, VariableDamage.MoveID.fissure,
            VariableDamage.MoveID.nightShade, VariableDamage.MoveID.psywave,
            VariableDamage.MoveID.superFang, VariableDamage.MoveID.flail,
            VariableDamage.MoveID.reversal, VariableDamage.MoveID.magnitude,
            VariableDamage.MoveID.endeavor, VariableDamage.MoveID.sheerCold,
            VariableDamage.MoveID.gyroBall, VariableDamage.MoveID.trumpCard,
            VariableDamage.MoveID.wringOut, VariableDamage.MoveID.punishment,
            VariableDamage.MoveID.crushGrip, VariableDamage.MoveID.electroBall,
            VariableDamage.MoveID.finalGambit, VariableDamage.MoveID.lowKick,
            VariableDamage.MoveID.grassKnot, VariableDamage.MoveID.heavySlam,
            VariableDamage.MoveID.heatCrash, VariableDamage.MoveID.counter,
            VariableDamage.MoveID.mirrorCoat, VariableDamage.MoveID.metalBurst,
        ]
        XCTAssertTrue(implemented.isDisjoint(with: VariableDamage.unmodeledMoveIDs))
        XCTAssertEqual(implemented.count + VariableDamage.unmodeledMoveIDs.count, 37,
                       "PokéAPI 기준 1~5세대의 위력 null 비변화기는 37개다 — 합이 어긋나면 빠뜨린 기술이 있다")
    }
}
