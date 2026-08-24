import XCTest
@testable import PokeTokenBar

/// Phase 3 — 랭크업(스탯 단계) + 변화기 무브셋 편입.
///
/// 이 파일의 테스트는 대부분 **대조군을 낀다.** "전부 곱한다", "급소면 전부 무시한다",
/// "명중·회피를 합산한다" 같은 뭉뚱그린 오구현은 단독 테스트로 전부 초록이 되는 부류다.
/// 세대별로 값이 갈리는 자리(§3.2)는 어느 세대를 골랐는지까지 잠근다.
final class BattleStageTests: XCTestCase {

    // MARK: 고정 재료

    /// Lv.50, 종족값 전부 100 → HP 175, 나머지 120. 랭크 배율을 손으로 검산할 수 있는 값이다.
    private func tank(_ types: [PokemonType] = [.normal], speed: Int = 100) -> BattleSnapshot {
        BattleSnapshot(speciesID: 143, name: "탱커", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: speed))
    }

    /// 필중 물리 — 명중 판정을 건너뛰므로 rng 소비가 급소 → 난수 둘뿐이다.
    private func tackle(power: Int = 80) -> MoveSpec {
        MoveSpec(id: 33, names: ["en": "Tackle"], type: .normal, power: power,
                 damageClass: .physical, accuracy: nil, pp: 35)
    }

    /// 명중률이 있는 기술 — 명중·회피 랭크가 붙는 경로를 밟는다.
    private func aimed(accuracy: Int = 100) -> MoveSpec {
        MoveSpec(id: 34, names: ["en": "Aimed"], type: .normal, power: 40,
                 damageClass: .physical, accuracy: accuracy, pp: 20)
    }

    /// 위력 없는 변화기 — 부호가 대상을 정한다(양수 = 자기, 음수 = 상대).
    private func statusMove(id: Int = 14, type: PokemonType = .normal,
                            changes: [StatChange], chance: Int? = nil) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["en": "Stat Move"], type: type, power: 0,
                            damageClass: .status, accuracy: nil, pp: 20)
        move.statChanges = changes
        move.statChance = chance
        return move
    }

    private func attack(_ attacker: inout BattleSide, _ defender: inout BattleSide,
                        _ move: MoveSpec, seed: UInt64 = 1) -> [BattleEvent] {
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                        attackerActor: .a, defenderActor: .b, move: move, rng: &rng)
    }

    // MARK: 랭크 배율표 — Gen 3+ 분수 (§3.2 결정)

    /// Gen 2 는 25/28/33/40/50/66/100/150/… 라는 **근사 소수**를 썼다. 우리는 같은 값의 정수 분수
    /// (2/8 … 2/2 … 8/2)를 쓴다 — 두 피어가 각자 계산하는 구조에서 정수 연산이 안전하다.
    func testDamageStageMultipliersFollowTheGen3Fractions() {
        let expected: [Int: Int] = [0: 100, 1: 150, 2: 200, 3: 250, 4: 300, 5: 350, 6: 400,
                                    -1: 66, -2: 50, -3: 40, -4: 33, -5: 28, -6: 25]
        for (stage, value) in expected.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(StatStages.apply(100, stage: stage), value, "단계 \(stage)")
        }
        XCTAssertEqual(StatStages.apply(100, stage: 9), 400, "±6 밖은 클램프된다")
        XCTAssertEqual(StatStages.apply(100, stage: -9), 25)
        XCTAssertEqual(StatStages.apply(120, stage: 1), 180, "정수 곱·나눗셈이다")
    }

    /// 명중·회피는 **다른 표**(Gen 2)를 쓴다. 데미지 스탯 표를 그대로 쓰면 +1 이 150% 가 된다.
    func testAccuracyStageTableIsTheGen2OneNotTheDamageTable() {
        XCTAssertEqual(StatStages.accuracyPercent(stage: 0), 100)
        XCTAssertEqual(StatStages.accuracyPercent(stage: 1), 133)
        XCTAssertEqual(StatStages.accuracyPercent(stage: 6), 300)
        XCTAssertEqual(StatStages.accuracyPercent(stage: -1), 75)
        XCTAssertEqual(StatStages.accuracyPercent(stage: -6), 33)
        XCTAssertEqual(StatStages.accuracyPercent(stage: 9), 300, "±6 밖은 클램프된다")
        XCTAssertNotEqual(StatStages.accuracyPercent(stage: 1), StatStages.apply(100, stage: 1),
                          "명중 표와 데미지 표가 같으면 한쪽 표가 배선되지 않았다")
    }

    /// 랭크는 −6…+6 에서 멈추고, 멈춘 뒤의 시도는 **0 만큼** 적용된다(이벤트가 나가지 않는 근거).
    func testStagesClampAtSixInBothDirections() {
        var side = BattleSide(tank())
        XCTAssertEqual(side.stage(.atk), 0, "랭크는 0 에서 시작한다")

        for _ in 0..<3 { XCTAssertEqual(side.changeStage(.atk, by: 2), 2) }
        XCTAssertEqual(side.stage(.atk), 6)
        XCTAssertEqual(side.changeStage(.atk, by: 2), 0, "상한에서는 아무것도 적용되지 않는다")
        XCTAssertEqual(side.stage(.atk), 6)
        XCTAssertEqual(side.changeStage(.atk, by: -1), -1, "상한이어도 내려가는 건 된다")

        XCTAssertEqual(side.changeStage(.def, by: -8), -6, "한 번에 넘겨도 상한까지만 적용된다")
        XCTAssertEqual(side.stage(.def), -6)
        XCTAssertEqual(side.changeStage(.def, by: -1), 0)
    }

    // MARK: 데미지에 실제로 연결됐는가 (표만 맞아도 배선이 없으면 위 테스트는 초록이다)

    func testStagesScaleBothAttackAndDefenseInResolveAttack() {
        func damage(attackerStage: Int, defenderStage: Int) -> Int {
            var attacker = BattleSide(tank()), defender = BattleSide(tank())
            attacker.changeStage(.atk, by: attackerStage)
            defender.changeStage(.def, by: defenderStage)
            var rng = SplitMix64(seed: 3)   // 같은 seed → 급소·난수 폭이 같다. 차이는 랭크뿐이다.
            return BattleEngine.resolveAttack(attacker: attacker, defender: defender,
                                              move: tackle(), rng: &rng).damage
        }
        let plain = damage(attackerStage: 0, defenderStage: 0)
        XCTAssertGreaterThan(damage(attackerStage: 2, defenderStage: 0), plain, "공격 +2 는 더 아프다")
        XCTAssertLessThan(damage(attackerStage: -2, defenderStage: 0), plain, "공격 −2 는 덜 아프다")
        XCTAssertLessThan(damage(attackerStage: 0, defenderStage: 2), plain, "방어 +2 는 덜 맞는다")
        XCTAssertGreaterThan(damage(attackerStage: 0, defenderStage: -2), plain, "방어 −2 는 더 맞는다")
    }

    /// 특수기는 특공·특방 랭크를 본다. 물리 랭크만 배선하면 이 테스트만 빨강이 된다.
    func testSpecialMovesReadTheSpecialStages() {
        let special = MoveSpec(id: 57, names: [:], type: .normal, power: 80,
                               damageClass: .special, accuracy: nil, pp: 15)
        func damage(_ apply: (inout BattleSide) -> Void) -> Int {
            var attacker = BattleSide(tank())
            let defender = BattleSide(tank())
            apply(&attacker)
            var rng = SplitMix64(seed: 3)
            return BattleEngine.resolveAttack(attacker: attacker, defender: defender,
                                              move: special, rng: &rng).damage
        }
        let plain = damage { _ in }
        XCTAssertGreaterThan(damage { $0.changeStage(.spa, by: 2) }, plain, "특공 랭크가 특수기를 키운다")
        XCTAssertEqual(damage { $0.changeStage(.atk, by: 2) }, plain, "공격 랭크는 특수기와 무관하다")
    }

    // MARK: 급소는 **불리한** 랭크만 무시한다

    /// 위 테스트가 쓰는 급소 seed — 처음 급소가 나는 값을 한 번 찾아 고정한다.
    private lazy var critSeed: UInt64 = {
        let attacker = BattleSide(tank()), defender = BattleSide(tank())
        for seed in UInt64(0)..<512 {
            var rng = SplitMix64(seed: seed)
            if BattleEngine.resolveAttack(attacker: attacker, defender: defender,
                                          move: tackle(), rng: &rng).isCritical { return seed }
        }
        return 0
    }()

    /// Gen 3+ 규칙: 급소는 공격측의 마이너스 랭크와 방어측의 플러스 랭크를 무시한다.
    /// (전부 무시하면 랭크를 올린 쪽이 급소에서 손해를 본다 — 올릴 이유가 없어진다.)
    func testCriticalHitsIgnoreOnlyTheUnfavourableStages() {
        func critDamage(_ apply: (inout BattleSide, inout BattleSide) -> Void) -> Int {
            var attacker = BattleSide(tank()), defender = BattleSide(tank())
            apply(&attacker, &defender)
            var rng = SplitMix64(seed: critSeed)
            let outcome = BattleEngine.resolveAttack(attacker: attacker, defender: defender,
                                                     move: tackle(), rng: &rng)
            // 랭크는 rng 를 소비하지 않으므로 같은 seed 면 급소 여부가 설정과 무관하게 같다.
            XCTAssertTrue(outcome.isCritical, "seed \(critSeed) 는 급소여야 한다")
            return outcome.damage
        }
        let plain = critDamage { _, _ in }
        XCTAssertGreaterThan(plain, 0)

        XCTAssertEqual(critDamage { _, defender in defender.changeStage(.def, by: 3) }, plain,
                       "급소는 방어측의 **올라간** 방어를 무시한다")
        XCTAssertEqual(critDamage { attacker, _ in attacker.changeStage(.atk, by: -3) }, plain,
                       "급소는 공격측의 **내려간** 공격을 무시한다")
        XCTAssertGreaterThan(critDamage { attacker, _ in attacker.changeStage(.atk, by: 3) }, plain,
                             "올린 공격은 급소에서도 살아 있어야 한다")
        XCTAssertGreaterThan(critDamage { _, defender in defender.changeStage(.def, by: -3) }, plain,
                             "깎인 방어는 급소에서도 살아 있어야 한다")
    }

    // MARK: 명중·회피 — **따로** 곱한다 (Gen 2)

    /// Gen 5+ 는 명중 단계와 회피 단계를 **합산해** 한 번 곱한다 — 그 방식이면 (+1, +1) 이 100% 다.
    /// Gen 2 는 두 배율을 각각 곱하므로 99% 다. 이 한 값이 어느 세대인지를 가른다.
    func testAccuracyAndEvasionMultiplySeparately() {
        var attacker = BattleSide(tank()), defender = BattleSide(tank())
        XCTAssertNil(BattleEngine.hitChance(of: tackle(), attacker: attacker, defender: defender),
                     "필중기는 명중 계산을 타지 않는다")
        XCTAssertEqual(BattleEngine.hitChance(of: aimed(), attacker: attacker, defender: defender), 100)

        attacker.changeStage(.accuracy, by: 1)
        XCTAssertEqual(BattleEngine.hitChance(of: aimed(), attacker: attacker, defender: defender), 133)

        defender.changeStage(.evasion, by: 1)
        XCTAssertEqual(BattleEngine.hitChance(of: aimed(), attacker: attacker, defender: defender), 99,
                       "단계를 합산해 한 번 곱하면 100 이 된다 — Gen 5 방식이다")

        var evasive = BattleSide(tank())
        evasive.changeStage(.evasion, by: 1)
        XCTAssertEqual(BattleEngine.hitChance(of: aimed(), attacker: BattleSide(tank()), defender: evasive), 75,
                       "회피 +1 은 상대 명중을 75% 로 깎는다")
    }

    /// 회피 랭크가 `resolveAttack` 까지 배선됐는지 — 표만 맞고 호출부가 없으면 위 테스트는 초록이다.
    func testEvasionStagesActuallyMakeAttacksMiss() {
        func missCount(evasion: Int) -> Int {
            var defender = BattleSide(tank())
            defender.changeStage(.evasion, by: evasion)
            return (UInt64(0)..<200).reduce(0) { count, seed in
                var rng = SplitMix64(seed: seed)
                let outcome = BattleEngine.resolveAttack(attacker: BattleSide(tank()), defender: defender,
                                                         move: aimed(), rng: &rng)
                return count + (outcome.missed ? 1 : 0)
            }
        }
        XCTAssertEqual(missCount(evasion: 0), 0, "명중 100 은 랭크가 없으면 빗나가지 않는다")
        XCTAssertGreaterThan(missCount(evasion: 6), 100, "회피 +6 이면 3분의 1 만 맞는다")
    }

    // MARK: 스피드 랭크 — 순서를 실제로 뒤집는다

    /// 스탯만 확인하면 순서 계산 경로를 밟지 않는다. 마비와 함께 걸리는 경우도 같이 본다 —
    /// 마비(25%)가 랭크 **뒤에** 곱해져야 한다.
    func testSpeedStagesFlipTurnOrderAndStackWithParalysis() {
        var boosted = BattleSide(tank(speed: 100))
        let rival = BattleSide(tank(speed: 100))
        XCTAssertEqual(boosted.effectiveSpeed, rival.effectiveSpeed)

        boosted.changeStage(.spe, by: 1)
        XCTAssertEqual(boosted.effectiveSpeed, 180, "120 × 3/2")

        boosted.status = .paralysis
        XCTAssertEqual(boosted.effectiveSpeed, 45, "랭크 뒤에 마비 25% — 180/4")

        // 실제 턴 순서: 스피드 랭크 +2 가 붙은 쪽이 원래 느려도 선공한다.
        var slow = BattleSide(tank(speed: 60))
        slow.changeStage(.spe, by: 2)
        let fast = BattleSide(tank(speed: 100))
        XCTAssertGreaterThan(slow.effectiveSpeed, fast.effectiveSpeed)
        for seed in UInt64(0)..<20 {
            var rng = SplitMix64(seed: seed)
            var a = slow, b = fast
            let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: tackle(), moveB: tackle(),
                                                  turn: 1, rng: &rng)
            let first = events.compactMap { event -> BattleActor? in
                if case .move(let actor, _) = event { return actor } else { return nil }
            }.first
            XCTAssertEqual(first, .a, "seed \(seed): 스피드 +2 가 선공이어야 한다")
        }
    }

    // MARK: 변화기 — 부호가 대상을 정한다

    func testStatusMoveRaisesTheUserAndLowersTheTarget() {
        var attacker = BattleSide(tank()), defender = BattleSide(tank())
        let events = attack(&attacker, &defender,
                            statusMove(changes: [StatChange(stat: .atk, change: 2)]))

        XCTAssertEqual(attacker.stage(.atk), 2, "올리는 변화기는 자기에게 걸린다")
        XCTAssertEqual(defender.stage(.atk), 0)
        XCTAssertTrue(events.contains(.boost(.a, .atk, 2)), "스트림에 랭크 변화가 실려야 한다")
        XCTAssertFalse(events.contains { if case .damage = $0 { return true } else { return false } },
                       "위력 0 은 데미지를 만들지 않는다")

        var user = BattleSide(tank()), target = BattleSide(tank())
        let drops = attack(&user, &target, statusMove(changes: [StatChange(stat: .def, change: -1)]))
        XCTAssertEqual(target.stage(.def), -1, "내리는 변화기는 상대에게 걸린다")
        XCTAssertEqual(user.stage(.def), 0)
        XCTAssertTrue(drops.contains(.boost(.b, .def, -1)))
    }

    /// 상한에 닿은 랭크는 **이벤트를 내지 않는다** — 0 만큼 바뀐 줄이 로그에 남으면 거짓말이다.
    func testMaxedStageEmitsNoBoostEvent() {
        var attacker = BattleSide(tank()), defender = BattleSide(tank())
        attacker.changeStage(.atk, by: 6)
        let events = attack(&attacker, &defender,
                            statusMove(changes: [StatChange(stat: .atk, change: 1)]))
        XCTAssertFalse(events.contains { if case .boost = $0 { return true } else { return false } })
        XCTAssertEqual(attacker.stage(.atk), 6)
    }

    /// 상성은 **데미지 기술의 규칙**이라 변화기(위력 0)는 타입 면역을 타지 않는다.
    /// 예외는 `MoveSpec.typeBlockedStatusMoveIDs` 에 명시한 것뿐이다(전기자석파 → 땅).
    ///
    /// 예전엔 "상태를 **거는** 변화기는 전부 상성표를 본다" 였고, 그 한 줄이 이상한빛(고스트→노말),
    /// 노래(노말→고스트), 최면술(에스퍼→악)까지 같이 막았다. 대조군 없이 한쪽만 보면
    /// 두 오구현("전부 무시" / "전부 검사")이 모두 초록이다.
    func testStatusMovesIgnoreTypeImmunityExceptTheListedOnes() {
        var user = BattleSide(tank()), ghost = BattleSide(tank([.ghost]))
        let events = attack(&user, &ghost,
                            statusMove(changes: [StatChange(stat: .atk, change: -1)]))
        XCTAssertEqual(ghost.stage(.atk), -1, "노말 변화기는 고스트에게도 걸린다")
        XCTAssertFalse(events.contains(.immune(.b)))

        // 상태를 거는 변화기도 마찬가지다 — 이상한빛은 고스트지만 노말에게 통해야 한다.
        var ghostCaster = BattleSide(tank([.ghost]))
        var normal = BattleSide(tank())
        var confuseRay = MoveSpec(id: 109, names: ["en": "Confuse Ray"], type: .ghost, power: 0,
                                  damageClass: .status, accuracy: nil, pp: 10)
        confuseRay.ailment = "confusion"
        confuseRay.targetsUser = false
        let confused = attack(&ghostCaster, &normal, confuseRay)
        XCTAssertFalse(confused.contains(.immune(.b)), "노말↔고스트 면역은 데미지 기술의 규칙이다")
        XCTAssertTrue(normal.isConfused)

        var caster = BattleSide(tank())
        var ground = BattleSide(tank([.ground]))
        var thunderWave = MoveSpec(id: MoveSpec.thunderWaveID, names: ["en": "Thunder Wave"],
                                   type: .electric, power: 0,
                                   damageClass: .status, accuracy: nil, pp: 20)
        thunderWave.ailment = "paralysis"
        let blocked = attack(&caster, &ground, thunderWave)
        XCTAssertTrue(blocked.contains(.immune(.b)), "명시한 예외는 상성을 본다")
        XCTAssertNil(ground.status, "땅 타입은 전기자석파에 마비되지 않는다")
    }

    /// 변화기에는 급소·상성 문구를 붙이지 않는다 — 깎을 데미지가 없어 배율이 아무 데도 안 쓰인다.
    /// 전기자석파(상성표를 보는 유일한 상태기)가 물에게 "효과가 굉장했다" 를 달면 마비가 2배로
    /// 걸린 것처럼 읽힌다. 무효(0배)는 실제로 실패했다는 뜻이라 그대로 남긴다.
    func testStatusMovesDoNotCarryCriticalOrEffectivenessLines() {
        var caster = BattleSide(tank())
        var water = BattleSide(tank([.water]))
        var thunderWave = MoveSpec(id: MoveSpec.thunderWaveID, names: ["en": "Thunder Wave"],
                                   type: .electric, power: 0,
                                   damageClass: .status, accuracy: nil, pp: 20)
        thunderWave.ailment = "paralysis"
        let events = attack(&caster, &water, thunderWave)
        XCTAssertEqual(water.status, .paralysis)
        XCTAssertFalse(events.contains(.superEffective(.b)), "전기가 물에게 2배여도 마비는 2배가 없다")
        XCTAssertFalse(events.contains { if case .crit = $0 { return true } else { return false } })
    }

    /// **아무것도 못 한 변화기는 그 사실을 말해야 한다.** 데미지가 없는 기술이라 이벤트를 안 내면
    /// 로그에 기술명 한 줄만 남아 무반응이 된다 — 독가루를 강철에게 쓰면 정확히 그 모양이었다.
    /// 상성표가 아니라 `canBeAfflicted`(상태 기준 면역)가 막는 경로라 위 테스트로는 안 잡힌다.
    func testAStatusMoveThatDidNothingSaysSo() {
        var caster = BattleSide(tank())
        var steel = BattleSide(tank([.steel]))
        var poisonPowder = MoveSpec(id: 77, names: ["en": "Poison Powder"], type: .poison, power: 0,
                                    damageClass: .status, accuracy: nil, pp: 35)
        poisonPowder.ailment = "poison"
        poisonPowder.targetsUser = false
        let events = attack(&caster, &steel, poisonPowder)
        XCTAssertNil(steel.status, "강철은 독에 걸리지 않는다")
        XCTAssertTrue(events.contains(.immune(.b)), "조용히 지나가면 고치려던 그 무반응이 된다")
    }

    /// **자기 대상 상태기는 상대에게 걸지 않는다.** 잠자기는 `damage_class: status` + `ailment: sleep`
    /// 이라 `ailmentChancePercent` 가 100 을 주고, `applySecondaryEffect` 는 상태를 늘 상대에게 건다 —
    /// 대상을 안 보면 회복 없는 **필중 100% 수면기**가 되고 CPU 는 무작위로 그것을 쓴다.
    /// 대조군(`targetsUser = false`)이 없으면 "상태기를 아예 안 건다" 는 오구현도 초록이다.
    func testSelfTargetingAilmentMovesAreNotCastOnTheOpponent() {
        func rest(targetsUser: Bool?) -> MoveSpec {
            var move = MoveSpec(id: 156, names: ["en": "Rest"], type: .psychic, power: 0,
                                damageClass: .status, accuracy: nil, pp: 10)
            move.ailment = "sleep"
            move.targetsUser = targetsUser
            return move
        }
        var user = BattleSide(tank()), target = BattleSide(tank())
        let events = attack(&user, &target, rest(targetsUser: true))
        XCTAssertNil(target.status, "자기 대상 수면기가 상대를 재우면 안 된다")
        XCTAssertNil(user.status, "회복·수면을 구현하지 않았으므로 자기에게도 걸지 않는다")
        XCTAssertFalse(events.contains { if case .status = $0 { return true } else { return false } })

        // 대조군: 같은 모양인데 대상이 상대인 상태기(수면가루)는 그대로 걸려야 한다.
        var caster = BattleSide(tank()), victim = BattleSide(tank())
        _ = attack(&caster, &victim, rest(targetsUser: false))
        XCTAssertEqual(victim.status, .sleep, "상대 대상 상태기는 계속 걸린다")
    }

    /// **부호가 섞인 랭크 변화는 대상을 가릴 수 없다.** 저주(자기 스피드 −1 + 공격·방어 +1)를
    /// 부호 규칙에 맡기면 스피드 감소가 상대에게 걸려 자기 버프 둘 + 상대 디버프 하나가 된다.
    /// 확정 자기감소 공격기와 같은 자리(`statChangePercent == 0`)에서 걸러야 한 규칙만 남는다.
    func testMixedSignStatChangesAreSkippedBecauseTheSignCannotPickATarget() {
        let curse = statusMove(id: 174, type: .ghost,
                               changes: [StatChange(stat: .spe, change: -1),
                                         StatChange(stat: .atk, change: 1),
                                         StatChange(stat: .def, change: 1)])
        XCTAssertTrue(curse.hasAmbiguousStatTargets)
        XCTAssertEqual(curse.statChangePercent, 0, "가릴 수 없으면 걸지 않는다")

        var user = BattleSide(tank()), target = BattleSide(tank())
        let events = attack(&user, &target, curse)
        XCTAssertEqual(target.stage(.spe), 0, "자기 스피드 감소가 상대에게 걸리면 완전히 뒤집힌다")
        XCTAssertEqual(user.stage(.atk), 0, "한 기술의 랭크 변화는 통째로 걸리거나 통째로 안 걸린다")
        XCTAssertFalse(events.contains { if case .boost = $0 { return true } else { return false } })

        // 대조군: 부호가 하나뿐이면(고대의힘 부류) 여러 축이어도 그대로 걸린다.
        let manyUp = statusMove(changes: [StatChange(stat: .atk, change: 1),
                                          StatChange(stat: .def, change: 1)])
        XCTAssertFalse(manyUp.hasAmbiguousStatTargets)
        var boosted = BattleSide(tank()), other = BattleSide(tank())
        _ = attack(&boosted, &other, manyUp)
        XCTAssertEqual(boosted.stage(.atk), 1)
        XCTAssertEqual(boosted.stage(.def), 1)
    }

    /// 공격기의 2차 랭크 변화는 PokéAPI 가 확률을 준 것만 적용한다. 확률 0 짜리 랭크 변화는
    /// 인파이트·깨트리다처럼 **자기를** 깎는 기술이라, 부호 규칙으로 처리하면 상대를 깎는다.
    func testDamagingMoveAppliesStatChangesOnlyWithAnExplicitChance() {
        var certain = tackle()
        certain.statChanges = [StatChange(stat: .def, change: -1)]
        certain.statChance = 100
        var attacker = BattleSide(tank()), defender = BattleSide(tank())
        let events = attack(&attacker, &defender, certain)
        XCTAssertEqual(defender.stage(.def), -1, "확률이 있는 2차효과는 상대에게 걸린다")
        XCTAssertTrue(events.contains(.boost(.b, .def, -1)))

        var selfDrop = tackle()
        selfDrop.statChanges = [StatChange(stat: .atk, change: -1), StatChange(stat: .def, change: -1)]
        selfDrop.statChance = nil
        for seed in UInt64(0)..<40 {
            var user = BattleSide(tank()), target = BattleSide(tank())
            _ = attack(&user, &target, selfDrop, seed: seed)
            XCTAssertEqual(target.stage(.def), 0, "seed \(seed): 확률 없는 랭크 변화는 적용하지 않는다")
            XCTAssertEqual(user.stage(.atk), 0)
        }

        XCTAssertEqual(certain.statChangePercent, 100)
        XCTAssertEqual(selfDrop.statChangePercent, 0, "공격기 + 확률 없음 = 적용 안 함")
        XCTAssertEqual(statusMove(changes: [StatChange(stat: .atk, change: 1)]).statChangePercent, 100,
                       "변화기는 랭크 변화가 본체라 늘 걸린다")
    }

    /// **트리거 브랜치**: 확률 판정이 *실패하는* 쪽. 확정(100%)·미적용(0%)만 보면 굴림이 없거나
    /// 늘 성공하는 구현도 초록이다(`--show-regions` 에서 실패 분기가 `^0` 이었다).
    /// 20% 짜리 2차효과를 seed 로 순회해 **두 결과가 모두** 나오는지 본다.
    func testPartialChanceStatDropSometimesFailsItsRoll() {
        var flinchy = tackle()
        flinchy.statChanges = [StatChange(stat: .def, change: -1)]
        flinchy.statChance = 20
        var applied = 0, skipped = 0
        for seed in UInt64(0)..<80 {
            var user = BattleSide(tank()), target = BattleSide(tank())
            _ = attack(&user, &target, flinchy, seed: seed)
            if target.stage(.def) == -1 { applied += 1 } else { skipped += 1 }
        }
        XCTAssertGreaterThan(applied, 0, "20% 는 걸리기도 해야 한다")
        XCTAssertGreaterThan(skipped, applied, "20% 는 대부분 안 걸린다 — 늘 걸리면 확률을 안 본다")
    }

    /// 쓰러진 상대에게는 랭크가 걸리지 않는다 — 상태이상과 같은 규칙이다.
    func testFaintedTargetTakesNoStatDrop() {
        var frail = tank()
        frail.base = BattleStats(hp: 1, atk: 1, def: 1, spa: 1, spd: 1, spe: 1)
        var strong = tackle()
        strong.statChanges = [StatChange(stat: .def, change: -1)]
        strong.statChance = 100
        var attacker = BattleSide(tank()), defender = BattleSide(frail)
        let events = attack(&attacker, &defender, strong)
        XCTAssertFalse(defender.isAlive)
        XCTAssertEqual(defender.stage(.def), 0)
        XCTAssertFalse(events.contains { if case .boost = $0 { return true } else { return false } })
    }

    // MARK: 교체하면 랭크가 0 으로

    /// 교체는 랭크를 버린다. 맹독 강등(Phase 2)이 이미 있는 자리라, 랭크만 남으면 다시 나올 때
    /// 옛 랭크로 싸운다.
    func testSwitchingOutClearsStages() {
        var battle = TeamPracticeBattle(mine: [BattleSide(tank()), BattleSide(tank())],
                                        opponents: [BattleSide(tank())],
                                        rng: SplitMix64(seed: 5))
        battle.mine[0].changeStage(.atk, by: 3)
        battle.mine[0].changeStage(.spe, by: -2)

        XCTAssertTrue(battle.switchMine(to: 1))

        XCTAssertEqual(battle.mine[0].stage(.atk), 0, "물러난 쪽의 랭크는 사라진다")
        XCTAssertEqual(battle.mine[0].stage(.spe), 0)
        XCTAssertTrue(battle.mine[0].stages.isEmpty, "0 을 남기지 않고 비운다")
    }

    /// 랭크 리셋은 **공유 헬퍼 안**에 있어야 한다 — LAN 교체(`BattleNet` 의 `switchSlot`)는 팀 연습을
    /// 거치지 않고 `prepareForSwitch` 만 부른다. 리셋이 팀 연습 호출부에 인라인으로 있으면 위
    /// 테스트는 통과하는데 LAN 교체만 랭크를 들고 나온다(무료 세팅).
    func testPrepareForSwitchItselfClearsStages() {
        var side = BattleSide(tank())
        side.changeStage(.atk, by: 6)
        side.confusionTurns = 3
        side.status = .toxic

        BattleEngine.prepareForSwitch(&side)

        XCTAssertTrue(side.stages.isEmpty, "교체 정리를 부른 경로는 전부 랭크가 사라진다")
        XCTAssertEqual(side.confusionTurns, 0)
        XCTAssertEqual(side.status, .poison, "맹독 강등은 그대로 — 같은 헬퍼가 세 규칙을 다 쓴다")
    }

    // MARK: 로그 — 랭크 변화가 자기 줄로 나간다

    func testBoostEventsBecomeTheirOwnLocalizedLine() {
        func lines(_ events: [BattleEvent], _ lang: AppLanguage) -> [String] {
            BattleLog.lines(events, l: L(lang), name: { $0 == .a ? "거북왕" : "리자몽" },
                            moveName: { _, _ in "칼춤" }).map(\.text)
        }
        let stream: [BattleEvent] = [.move(.a, moveID: 14), .boost(.a, .atk, 2)]
        XCTAssertEqual(lines(stream, .ko), ["거북왕의 칼춤!", "거북왕의 공격이 크게 올라갔다!"])
        XCTAssertEqual(lines(stream, .en), ["거북왕 used 칼춤!", "거북왕's Attack rose sharply!"])
        XCTAssertEqual(lines([.boost(.b, .spe, -1)], .ko), ["리자몽의 스피드가 떨어졌다!"])
        XCTAssertEqual(lines([.boost(.b, .spe, -1)], .ja), ["리자몽の すばやさが さがった！"])
        XCTAssertEqual(lines([.boost(.a, .accuracy, 1)], .ko).first, "거북왕의 명중률이 올라갔다!")
    }

    /// 화면 배지 — 0 인 랭크는 빼고, 캐논 순서(공·방·특공·특방·스피드·명중·회피)로.
    func testStageReadoutShowsOnlyNonZeroStagesInCanonicalOrder() {
        XCTAssertNil(StageReadout.text([:]), "랭크가 없으면 그릴 게 없다")
        XCTAssertNil(StageReadout.text([.atk: 0]), "0 만 있으면 빈 배지가 뜨지 않는다")
        XCTAssertEqual(StageReadout.text([.spe: -1, .atk: 2]), "Atk▲2 Spe▼1")
        XCTAssertEqual(StageReadout.text([.evasion: 1, .spd: -2, .def: 1]), "Def▲1 SpD▼2 Eva▲1")
    }

    // MARK: PokéAPI 매핑

    private func moveJSON(statChanges: String?, statChance: Int?, target: String? = nil) -> Data {
        let changes = statChanges.map { #", "stat_changes": \#($0)"# } ?? ""
        let chance = statChance.map { #", "meta": {"stat_chance": \#($0)}"# } ?? ""
        let targetRef = target.map { #", "target": {"name": "\#($0)", "url": null}"# } ?? ""
        return Data("""
        {"id": 14, "power": 0, "accuracy": null, "pp": 20, "priority": 0,
         "type": {"name": "normal", "url": null},
         "damage_class": {"name": "status", "url": null},
         "names": [{"name": "Swords Dance", "language": {"name": "en", "url": null}}],
         "flavor_text_entries": []\(changes)\(chance)\(targetRef)}
        """.utf8)
    }

    /// `target` 이 자기 대상 기술을 가리는 **유일한 신호다** — `stat_changes`·`meta.ailment` 에는
    /// 대상이 없다. 키가 없으면 `nil`(구버전 응답)이고, 그때는 부호 규칙으로 떨어진다.
    func testMoveSpecCarriesTheTargetFromPokeAPI() throws {
        func spec(target: String?) throws -> MoveSpec {
            try XCTUnwrap(MoveSpec.from(
                try JSONDecoder().decode(MoveDTO.self,
                                         from: moveJSON(statChanges: "[]", statChance: 0, target: target)),
                fallbackName: "swords-dance", languages: ["en"]))
        }
        XCTAssertEqual(try spec(target: "user").targetsUser, true)
        XCTAssertEqual(try spec(target: "users-field").targetsUser, true)
        XCTAssertEqual(try spec(target: "selected-pokemon").targetsUser, false,
                       "`selected-pokemon` 은 자기 랭크를 깎는 공격기도 쓰므로 자기 대상이 아니다")
        XCTAssertNil(try spec(target: nil).targetsUser, "키가 없으면 모른다 — 부호 규칙으로 떨어진다")
    }

    func testMoveSpecCarriesStatChangesFromPokeAPI() throws {
        let json = moveJSON(statChanges: #"[{"change": 2, "stat": {"name": "attack", "url": null}}]"#,
                            statChance: 0)
        let dto = try JSONDecoder().decode(MoveDTO.self, from: json)
        let spec = try XCTUnwrap(MoveSpec.from(dto, fallbackName: "swords-dance", languages: ["en"]))

        XCTAssertEqual(spec.statChanges, [StatChange(stat: .atk, change: 2)])
        XCTAssertEqual(spec.statChance, 0)
        XCTAssertEqual(spec.damageClass, .status)
        XCTAssertEqual(spec.power, 0)
    }

    /// 7종의 화면 약어·이름·기준값을 **전부** 밟는다. 로그·배지 테스트는 자기가 쓴 두세 개만
    /// 실행하는데 라인 커버리지는 그걸 초록으로 보고한다(`Status.badgeTint` 로 겪은 부류다).
    func testEveryStatHasALabelANameAndABaseline() {
        XCTAssertEqual(BattleStat.allCases.map(\.shortLabel),
                       ["Atk", "Def", "SpA", "SpD", "Spe", "Acc", "Eva"])
        for lang in [AppLanguage.ko, .en, .ja] {
            let names = BattleStat.allCases.map { $0.name(lang) }
            XCTAssertEqual(Set(names).count, BattleStat.allCases.count,
                           "\(lang): 이름이 겹치면 로그에서 어느 스탯인지 알 수 없다")
            XCTAssertFalse(names.contains { $0.isEmpty }, "\(lang): 빈 이름")
        }
        let side = BattleSide(tank(speed: 100))
        XCTAssertEqual(BattleStat.allCases.map { side.rawStat($0) },
                       [120, 120, 120, 120, 120, 100, 100],
                       "명중·회피는 스탯이 아니라 랭크만 있는 축이라 기준값 100 이다")
    }

    /// PokéAPI 스탯 이름 7종이 전부 매핑된다. 하나라도 빠지면 그 기술의 랭크 변화가 조용히 사라진다.
    func testEveryPokeAPIStatNameMaps() {
        let pairs: [(String, BattleStat)] = [("attack", .atk), ("defense", .def),
                                             ("special-attack", .spa), ("special-defense", .spd),
                                             ("speed", .spe), ("accuracy", .accuracy), ("evasion", .evasion)]
        for (name, stat) in pairs {
            XCTAssertEqual(BattleStat(apiName: name), stat, name)
        }
        XCTAssertNil(BattleStat(apiName: "hp"), "랭크가 없는 스탯은 매핑하지 않는다")
    }

    /// `stat_changes` 는 응답에 늘 있다(없으면 빈 배열). 그래서 **키 없음**은 "아직 안 받아봤다",
    /// `[]` 는 "받았고 변화 없음" 이다 — 섞으면 매 로드마다 다시 받거나 영영 안 고친다.
    /// `CompanionStore` 가 `@MainActor` 라 이 한 테스트만 메인 액터에서 돈다.
    @MainActor
    func testMissingStatChangesStayNilSoTheSaveCanConverge() throws {
        let unfetched = try XCTUnwrap(MoveSpec.from(
            try JSONDecoder().decode(MoveDTO.self, from: moveJSON(statChanges: nil, statChance: nil)),
            fallbackName: "swords-dance", languages: ["en"]))
        XCTAssertNil(unfetched.statChanges)
        XCTAssertTrue(CompanionStore.needsDetailRefresh(unfetched), "안 받아본 스펙은 다시 받는다")

        // `target` 을 같이 넣는다 — 이 테스트가 보는 축은 `statChanges` 뿐인데, 대상 축을 nil 로
        // 두면 그 축 때문에 다시 받게 되어 랭크 축 판정이 죽어도 초록이 된다.
        let fetchedEmpty = try XCTUnwrap(MoveSpec.from(
            try JSONDecoder().decode(MoveDTO.self, from: moveJSON(statChanges: "[]", statChance: 0,
                                                                 target: "selected-pokemon")),
            fallbackName: "swords-dance", languages: ["en"]))
        XCTAssertEqual(fetchedEmpty.statChanges, [])
        XCTAssertFalse(CompanionStore.needsDetailRefresh(fetchedEmpty),
                       "받았고 변화가 없는 스펙을 매번 다시 받으면 로드마다 네트워크가 돈다")

        XCTAssertFalse(CompanionStore.needsDetailRefresh(MoveSpec.struggle()),
                       "id 가 음수인 합성 기술은 받을 데가 없다")
    }

    // MARK: 무브셋 — 변화기가 실제로 들어오되 한 칸만

    func testPickFourGivesStatusMovesAtMostOneSlot() {
        func attackSpec(_ id: Int, _ type: PokemonType, _ power: Int) -> MoveSpec {
            MoveSpec(id: id, names: [:], type: type, power: power,
                     damageClass: .physical, accuracy: 100, pp: 10)
        }
        let statusA = statusMove(id: 14, changes: [StatChange(stat: .atk, change: 2)])
        let statusB = statusMove(id: 45, changes: [StatChange(stat: .atk, change: -1)])
        let picked = PokeAPIClient.pickFour(
            from: [attackSpec(1, .fire, 90), attackSpec(2, .normal, 100), attackSpec(3, .flying, 75),
                   attackSpec(4, .dragon, 80), statusA, statusB],
            types: [.fire, .flying])

        XCTAssertEqual(picked.count, 4)
        XCTAssertEqual(picked.filter { $0.damageClass == .status }.count, 1,
                       "변화기는 4칸 중 한 칸까지다 — 두 칸이면 화력이 사라진다")
        XCTAssertEqual(picked.filter { $0.power > 0 }.count, 3)

        // 위력 내림차순으로만 뽑으면 위력 0 인 변화기는 **절대** 안 들어온다 — 그래서 칸을 나눈다.
        let attacksOnly = PokeAPIClient.pickFour(
            from: [attackSpec(1, .fire, 90), attackSpec(2, .normal, 100),
                   attackSpec(3, .flying, 75), attackSpec(4, .dragon, 80)],
            types: [.fire, .flying])
        XCTAssertEqual(attacksOnly.count, 4, "변화기가 없으면 네 칸 전부 공격기다")
        XCTAssertTrue(attacksOnly.allSatisfy { $0.power > 0 })
    }

    /// 쓸데없는 변화기(랭크도 상태도 없는 미구현 부류)보다 실제로 뭔가 하는 변화기를 고른다.
    func testStatusSlotPrefersAMoveThatActuallyDoesSomething() {
        let inert = MoveSpec(id: 99, names: [:], type: .normal, power: 0,
                             damageClass: .status, accuracy: nil, pp: 10)
        let useful = statusMove(id: 14, changes: [StatChange(stat: .atk, change: 2)])
        let picked = PokeAPIClient.pickFour(from: [inert, useful], types: [.normal])
        XCTAssertEqual(picked.map(\.id), [14], "구현된 효과가 있는 변화기가 그 칸을 가진다")
    }

    /// 변화기 칸의 기준은 **엔진이 실제로 적용하는가** 다. 자기 대상 상태기(잠자기)와 부호가 섞인
    /// 랭크 변화(저주)는 엔진이 건너뛰므로 그 칸에 앉히면 PP 만 태운다 — 효과 미구현 변화기와 같다.
    func testStatusSlotSkipsMovesTheEngineWillNotApply() {
        func attackSpec(_ id: Int, _ type: PokemonType, _ power: Int) -> MoveSpec {
            MoveSpec(id: id, names: [:], type: type, power: power,
                     damageClass: .physical, accuracy: 100, pp: 10)
        }
        var rest = MoveSpec(id: 156, names: [:], type: .psychic, power: 0,
                            damageClass: .status, accuracy: nil, pp: 10)
        rest.ailment = "sleep"
        rest.targetsUser = true
        let curse = statusMove(id: 174, type: .ghost,
                               changes: [StatChange(stat: .spe, change: -1),
                                         StatChange(stat: .atk, change: 1)])
        let attacks = [attackSpec(1, .fire, 90), attackSpec(2, .normal, 100),
                       attackSpec(3, .flying, 75), attackSpec(4, .dragon, 80)]

        for useless in [rest, curse] {
            let picked = PokeAPIClient.pickFour(from: attacks + [useless], types: [.fire, .flying])
            XCTAssertEqual(picked.count, 4)
            XCTAssertTrue(picked.allSatisfy { $0.power > 0 },
                          "기술 \(useless.id): 엔진이 건너뛰는 변화기가 화력 한 칸을 먹었다")
        }
        // 대조군: 같은 자리에 걸리는 상태기(수면가루)가 오면 그 칸을 가진다.
        var powder = rest
        powder.targetsUser = false
        XCTAssertEqual(PokeAPIClient.pickFour(from: attacks + [powder], types: [.fire, .flying])
                        .filter { $0.power <= 0 }.count, 1)
    }

    /// **트리거 브랜치**: 쓸 만한 변화기가 하나도 없는 풀. 위 테스트는 *더 나은* 변화기를 고르는지만
    /// 보므로 폴백이 남아 있어도 초록이다. 그 칸은 공격기에게 돌아가야 한다.
    func testInertStatusMovesGiveTheirSlotBackToAttacks() {
        func attackSpec(_ id: Int, _ type: PokemonType, _ power: Int) -> MoveSpec {
            MoveSpec(id: id, names: [:], type: type, power: power,
                     damageClass: .physical, accuracy: 100, pp: 10)
        }
        let inert = MoveSpec(id: 99, names: [:], type: .normal, power: 0,
                             damageClass: .status, accuracy: nil, pp: 10)
        let picked = PokeAPIClient.pickFour(
            from: [attackSpec(1, .fire, 90), attackSpec(2, .normal, 100), attackSpec(3, .flying, 75),
                   attackSpec(4, .dragon, 80), inert],
            types: [.fire, .flying])
        XCTAssertEqual(picked.count, 4)
        XCTAssertTrue(picked.allSatisfy { $0.power > 0 },
                      "효과 없는 변화기가 화력 한 칸을 먹으면 안 된다")
    }

    // MARK: 신뢰경계 — 상대가 보내오는 랭크 변화

    func testValidationRejectsHostileStatChanges() {
        let participant = LobbyParticipant(id: UUID(), trainerName: "상대", speciesID: 143,
                                           team: .solo, isReady: true, isHost: false)
        func snapshot(with move: MoveSpec) -> BattleSnapshot {
            var snap = tank()
            snap.moves = [move]
            return snap
        }
        let sane = statusMove(changes: [StatChange(stat: .atk, change: 2)])
        XCTAssertTrue(MultiplayerValidation.valid(participant: participant, snapshot: snapshot(with: sane)))

        var tooBig = sane
        tooBig.statChanges = [StatChange(stat: .atk, change: 7)]
        XCTAssertFalse(MultiplayerValidation.valid(participant: participant, snapshot: snapshot(with: tooBig)),
                       "±6 밖의 랭크 변화는 거절한다")

        var tooMany = sane
        tooMany.statChanges = Array(repeating: StatChange(stat: .atk, change: 1), count: 12)
        XCTAssertFalse(MultiplayerValidation.valid(participant: participant, snapshot: snapshot(with: tooMany)),
                       "스탯 수보다 많은 변화는 거절한다")

        var badChance = sane
        badChance.statChance = 101
        XCTAssertFalse(MultiplayerValidation.valid(participant: participant, snapshot: snapshot(with: badChance)))

        // 개수 상한만 보면 **중복**으로 그 상한을 빠져나간다 — `+2 공격` 일곱 개는 7 ≤ 7 을
        // 통과하고 한 방에 최대 랭크를 만든다(로그도 일곱 줄).
        var duplicated = sane
        duplicated.statChanges = Array(repeating: StatChange(stat: .atk, change: 2),
                                       count: BattleStat.allCases.count)
        XCTAssertFalse(MultiplayerValidation.valid(participant: participant,
                                                   snapshot: snapshot(with: duplicated)),
                       "같은 스탯을 여러 번 담은 무브셋은 거절한다")
    }

    /// 최대 HP 로 시작하는 배틀이면 랭크도 0 이어야 한다 — 안 보면 `stages: [atk: 6]` 으로 시작한다.
    func testValidStartRejectsFightersThatAlreadyHaveStages() {
        func fighter(_ stage: Int) -> MultiplayerFighter {
            let participant = LobbyParticipant(id: UUID(), trainerName: "T\(stage)", speciesID: 143,
                                               team: .solo, isReady: true, isHost: false)
            var made = MultiplayerFighter(participant: participant, snapshot: tank())
            if stage != 0 { made.side.changeStage(.atk, by: stage) }
            return made
        }
        XCTAssertTrue(MultiplayerValidation.validStart(fighters: [fighter(0), fighter(0)], mode: .freeForAll))
        XCTAssertFalse(MultiplayerValidation.validStart(fighters: [fighter(0), fighter(6)], mode: .freeForAll))
    }

    /// 라운드 결과는 호스트가 브로드캐스트한다. 랭크가 와이어를 못 건너면 게스트 화면에서 화살표가
    /// 사라지고, 게스트와 호스트가 서로 다른 배틀을 본다.
    func testFighterWireCarriesStages() throws {
        let participant = LobbyParticipant(id: UUID(), trainerName: "호스트", speciesID: 143,
                                           team: .solo, isReady: true, isHost: false)
        var sent = MultiplayerFighter(participant: participant, snapshot: tank())
        sent.side.changeStage(.atk, by: 2)
        sent.side.changeStage(.evasion, by: -1)

        let data = try JSONEncoder().encode(sent)
        let received = try JSONDecoder().decode(MultiplayerFighter.self, from: data)
        XCTAssertEqual(received.side.stage(.atk), 2)
        XCTAssertEqual(received.side.stage(.evasion), -1)

        // 랭크가 없던 시절의 피어가 보낸 모양 — 키가 없으면 랭크 없음으로 읽는다.
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "stages")
        let legacy = try JSONDecoder().decode(
            MultiplayerFighter.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.side.stages.isEmpty)
    }

    /// **트리거 브랜치**: `validStart` 는 개시 시점만 본다 — 라운드마다 오는 랭크는 아무도 검사하지
    /// 않는다. 클램프가 없으면 배지가 `Atk▲99` 로 뜨고 다음 `changeStage` 가 `-93` 을 로그에 쓴다.
    func testWireStagesAreClampedAndZeroKeysDropped() throws {
        let participant = LobbyParticipant(id: UUID(), trainerName: "호스트", speciesID: 143,
                                           team: .solo, isReady: true, isHost: false)
        let honest = MultiplayerFighter(participant: participant, snapshot: tank())
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(honest)) as? [String: Any])
        json["stages"] = ["atk": 99, "spe": -50, "def": 0]

        let forged = try JSONDecoder().decode(
            MultiplayerFighter.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(forged.side.stage(.atk), StatStages.limit, "±6 밖은 경계에서 잘린다")
        XCTAssertEqual(forged.side.stage(.spe), -StatStages.limit)
        XCTAssertNil(forged.side.stages[.def], "0 인 스탯은 키를 두지 않는다 — `stages` 의 불변식")
        XCTAssertEqual(StageReadout.text(forged.side.stages), "Atk▲6 Spe▼6",
                       "화면에 6 밖의 숫자가 뜨면 클램프가 배선되지 않았다")
    }

    /// **트리거 브랜치**: 값이 아니라 **키**가 이상한 경우. `[BattleStat: Int]` 로 바로 디코딩하면
    /// 모르는 키 하나가 파이터 — 곧 라운드 메시지 전체 — 의 디코딩을 던져서 게스트가 그 자리에
    /// 멈춘다. 값 클램프만 있으면 이 경로는 한 번도 밟히지 않는다.
    func testWireStagesDropUnknownStatKeysInsteadOfFailingTheWholeRound() throws {
        let participant = LobbyParticipant(id: UUID(), trainerName: "호스트", speciesID: 143,
                                           team: .solo, isReady: true, isHost: false)
        let honest = MultiplayerFighter(participant: participant, snapshot: tank())
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(honest)) as? [String: Any])
        json["stages"] = ["hp": 3, "sp_atk": 2, "atk": 2]

        let forged = try JSONDecoder().decode(
            MultiplayerFighter.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(forged.side.stage(.atk), 2, "아는 키는 그대로 읽는다")
        XCTAssertEqual(forged.side.stages.count, 1, "랭크가 없는 `hp`·모르는 이름은 버린다")
    }

    /// 랭크 0 짜리 `.boost` 는 줄이 없다 — 이벤트 스트림도 호스트가 보내오는 값이다.
    func testZeroBoostEventDrawsNoLine() {
        let lines = BattleLog.lines([.boost(.a, .atk, 0)], l: L(.ko),
                                    name: { _ in "거북왕" }, moveName: { _, _ in "칼춤" })
        XCTAssertTrue(lines.isEmpty, "0 만큼 바뀐 랭크에 줄을 내면 로그가 거짓말을 한다")
    }

    /// 무브셋 경계를 **두 경로가 공유하는 한 함수**로 못 박는다. 방에만 있으면 `statChance: 5000` 이
    /// 1v1 에서 무검사로 들어간다. (핸드셰이크가 실제로 부르는지는 여기서 못 본다 — 리뷰 몫.)
    func testMoveBoundsAreSharedByBothNetPaths() {
        var hostile = statusMove(changes: [StatChange(stat: .atk, change: 2)])
        hostile.statChance = 5_000
        XCTAssertFalse(MultiplayerValidation.validMoves([hostile]))
        XCTAssertTrue(MultiplayerValidation.validMoves(
            [statusMove(changes: [StatChange(stat: .atk, change: 2)])]))
        XCTAssertTrue(MultiplayerValidation.validMoves([]), "무브셋 없는 스냅샷은 폴백으로 간다")
    }

    /// 이벤트 스트림에 case 가 늘었다(`.boost`) → 와이어 계약 버전이 올라가야 한다. 안 올리면
    /// 구버전 게스트가 모르는 case 를 만나 라운드 메시지 **전체**를 디코딩하지 못한다.
    ///
    /// `rulesVersion` 은 여기서 보지 않는다 — `BattleStatusTests` 가 `== 8` 로 못 박고 그 파일에
    /// 버전 히스토리 근거가 누적돼 있다. 두 곳에서 같은 값을 단정하면 올릴 때 한 곳을 잊는다.
    func testProtocolVersionMovedWithStages() {
        // 하한을 실제 값으로 잡는다 — 6 으로 두면 랭크가 들어오기 **전** 버전에서도 통과해
        // "버전을 올렸는가" 를 아무것도 검증하지 않는다.
        XCTAssertGreaterThanOrEqual(MultiplayerWireMessage.protocolVersion, 5, "`.boost` 가 늘어난 계약")
    }

    // MARK: 상태·랭크 확률의 기본값 규칙은 한 곳이다

    /// `ailmentChancePercent` 와 `statChangePercent` 는 **같은 기본값 규칙**을 쓴다: 명시 확률이
    /// 있으면 그 값, 없으면 변화기는 100(효과가 기술 본체다) 공격기는 0. 규칙이 두 벌로 복제돼
    /// 있으면 한쪽만 고쳐도 컴파일·테스트가 아무것도 알려주지 않고 상태 부여와 랭크 변화가
    /// 서로 다른 확률로 갈라진다.
    func testAilmentAndStatChanceShareOneDefaultRule() {
        func spec(_ damageClass: MoveDamageClass, chance: Int?) -> MoveSpec {
            var move = MoveSpec(id: 14, names: ["en": "M"], type: .normal,
                                power: damageClass == .status ? 0 : 60,
                                damageClass: damageClass, accuracy: nil, pp: 20)
            move.ailmentChance = chance
            move.statChance = chance
            move.statChanges = [StatChange(stat: .atk, change: 1)]
            return move
        }
        for (damageClass, chance, expected) in [(MoveDamageClass.status, nil, 100),
                                                (.status, 30, 30),
                                                (.physical, nil, 0),
                                                (.physical, 10, 10)] {
            let move = spec(damageClass, chance: chance)
            XCTAssertEqual(move.ailmentChancePercent, expected,
                           "\(damageClass) + \(chance.map(String.init) ?? "nil")")
            XCTAssertEqual(move.statChangePercent, expected,
                           "두 축이 갈라졌다 — 기본값 규칙은 한 곳에서만 온다")
        }
    }

    // MARK: 스피드 하한 — 랭크 −6 이 0 을 만들지 않는다

    /// 선공 판정이 스피드를 그대로 비교하므로 0 이 나오면 **어떤 상대에게도 무조건 후공**이 되고
    /// 0 끼리는 무작위로 떨어진다. 마비 분기에는 `max(1, …)` 하한이 있고 비마비 분기에는 없어
    /// 비대칭인데, 실제로 0 에 닿는지를 **최악값으로** 확인한다: 종족값 1 · 레벨 1 · 스피드가
    /// 내려가는 성격 · 랭크 −6. `effectiveStats()` 의 `+5` 가 하한이라 여기서 0 이 나오지 않는다.
    /// 스탯 공식을 건드리면 이 테스트가 먼저 깨진다.
    func testSpeedNeverCollapsesToZeroAtTheWorstStage() {
        let slowest = BattleSnapshot(speciesID: 213, name: "느림", trainer: nil, level: 1,
                                     nature: .brave,   // 공격↑ 스피드↓
                                     isShiny: false, types: [.normal],
                                     base: BattleStats(hp: 1, atk: 1, def: 1, spa: 1, spd: 1, spe: 1))
        var side = BattleSide(slowest)
        side.changeStage(.spe, by: -6)

        XCTAssertGreaterThanOrEqual(side.effectiveSpeed, 1,
                                    "0 이면 선공 판정이 무조건 후공 + 0 끼리 무작위가 된다")
        side.status = .paralysis
        XCTAssertGreaterThanOrEqual(side.effectiveSpeed, 1, "마비까지 겹쳐도 하한은 유지된다")
    }

    // MARK: 대가를 모델링하지 않은 큰 상승 — 배가르기 부류

    /// 배가르기(공격 +6, 대가는 최대 HP 절반)는 HP 소모가 어디에도 없어서, 통과시키면 첫 턴 공짜
    /// +6 이다. **엔진에서** 접어야 한다 — 무브셋 선택에만 게이트를 두면 `learnedMoves` 경로(변화기를
    /// 안 걸러낸다)로 들어온 같은 기술이 그대로 적용된다.
    func testUnpricedBigGainIsNotApplied() {
        let bellyDrum = statusMove(id: 187, changes: [StatChange(stat: .atk, change: 6)])
        var attacker = BattleSide(tank()), defender = BattleSide(tank())
        let events = attack(&attacker, &defender, bellyDrum)

        XCTAssertEqual(attacker.stage(.atk), 0, "대가가 없는 +6 은 걸리지 않는다")
        XCTAssertFalse(events.contains { if case .boost = $0 { return true } else { return false } },
                       "적용도 안 되는 랭크에 로그 줄이 나가면 화면이 거짓말을 한다")
        // 대조군: 대가가 없어도 정상 범위(±2)인 칼춤은 그대로 걸린다 — 문턱이 변화기를 통째로
        // 막아 버리면 랭크 기능 자체가 죽는다.
        var second = BattleSide(tank())
        _ = attack(&second, &defender, statusMove(changes: [StatChange(stat: .atk, change: 2)]))
        XCTAssertEqual(second.stage(.atk), 2, "±2 짜리 변화기는 계속 걸린다")
    }

    /// 무브셋 칸도 같이 비어야 한다 — 엔진이 건너뛰는 기술이 칸을 차지하면 PP 만 태우는 칸이 된다.
    /// 엔진과 **같은 값**(`statChangePercent`)을 보는지 확인한다.
    func testUnpricedBigGainDoesNotHoldAMoveSlot() {
        let bellyDrum = statusMove(id: 187, changes: [StatChange(stat: .atk, change: 6)])
        XCTAssertEqual(bellyDrum.statChangePercent, 0, "엔진이 0 으로 접는다")
        XCTAssertTrue(bellyDrum.hasUnpricedGain)
        XCTAssertFalse(statusMove(changes: [StatChange(stat: .atk, change: 2)]).hasUnpricedGain,
                       "±2 는 대가 없이도 정상 범위다")
    }

    // MARK: KO 낸 턴의 자기 랭크 상승

    /// 고대의힘 부류(공격기 + 자기 랭크 상승)로 상대를 쓰러뜨려도 **내 랭크는 오른다**(본가와 같다).
    /// 예전엔 기절이 `applyAttack` 에서 조기반환해 랭크 적용이 통째로 사라졌다 — 랭크를 올릴 기회가
    /// KO 여부에 따라 무작위로 없어졌다.
    func testSelfBoostSurvivesAKnockout() {
        var boosting = tackle(power: 200)
        boosting.statChanges = [StatChange(stat: .atk, change: 1), StatChange(stat: .def, change: 1)]
        boosting.statChance = 100            // 확률이 붙어야 부호 규칙이 자기 상승으로 읽는다
        var attacker = BattleSide(tank()), defender = BattleSide(tank())
        defender.hp = 1                      // 무엇을 맞아도 쓰러진다

        let events = attack(&attacker, &defender, boosting)

        XCTAssertFalse(defender.isAlive)
        XCTAssertEqual(attacker.stage(.atk), 1, "KO 낸 턴에도 자기 랭크는 오른다")
        XCTAssertEqual(attacker.stage(.def), 1)
        // `.faint` 는 맨 뒤다 — 쓰러진 뒤에 랭크가 오르는 것처럼 읽히면 안 된다(Showdown 순서).
        let boostIndex = events.firstIndex { if case .boost = $0 { return true } else { return false } }
        let faintIndex = events.firstIndex { if case .faint = $0 { return true } else { return false } }
        XCTAssertNotNil(boostIndex)
        XCTAssertNotNil(faintIndex)
        XCTAssertLessThan(try XCTUnwrap(boostIndex), try XCTUnwrap(faintIndex))
    }

    /// 반대 방향 — **쓰러진 상대의 랭크는 안 깎는다.** 다 적용하게 풀면 기절한 개체에 `.boost` 가
    /// 나가 로그가 "쓰러진 포켓몬의 방어가 떨어졌다" 를 찍는다.
    func testOpponentDropIsSkippedWhenTheTargetFaints() {
        var dropping = tackle(power: 200)
        dropping.statChanges = [StatChange(stat: .def, change: -1)]
        dropping.statChance = 100
        var attacker = BattleSide(tank()), defender = BattleSide(tank())
        defender.hp = 1

        let events = attack(&attacker, &defender, dropping)

        XCTAssertFalse(defender.isAlive)
        XCTAssertEqual(defender.stage(.def), 0, "쓰러진 상대에게는 걸지 않는다")
        XCTAssertFalse(events.contains { if case .boost = $0 { return true } else { return false } })
    }

    // MARK: 세이브 수렴 — 축을 더하면 판정도 같이 늘린다

    /// 랭크 축으로 이미 한 번 갱신된 세이브(= `statChanges` 가 채워진)는 대상 축이 비어 있으면
    /// **다시 받아야 한다.** 안 그러면 그 기기는 영영 `targetsUser` 가 nil 이라, 잠자기·저주 처방이
    /// 자기 기기에서만 안 먹는다.
    @MainActor
    func testFilledStatChangesStillRefetchWhenTheTargetAxisIsMissing() {
        var halfFetched = statusMove(changes: [])
        halfFetched.descriptions = ["en": "A move."]
        XCTAssertNil(halfFetched.targetsUser)
        XCTAssertTrue(CompanionStore.needsDetailRefresh(halfFetched),
                      "축을 더했는데 판정을 안 늘리면 옛 데이터로 계속 싸운다")

        halfFetched.targetsUser = false
        XCTAssertFalse(CompanionStore.needsDetailRefresh(halfFetched),
                       "두 축을 다 받은 스펙을 또 받으면 로드마다 네트워크가 돈다")
    }
}
