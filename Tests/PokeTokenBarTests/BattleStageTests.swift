import XCTest
@testable import PokeTokenBar

/// Phase 3 — 랭크업(스탯 단계) + 변화기 무브셋 편입.
///
/// 이 파일의 테스트는 대부분 **대조군을 낀다.** 랭크는 "전부 곱한다", "급소면 전부 무시한다",
/// "명중·회피를 합산해서 한 번 곱한다" 같은 뭉뚱그린 오구현이 단독 테스트로는 전부 초록으로
/// 통과하는 부류다. 세대별 값이 갈리는 자리(§3.2)는 어느 세대를 골랐는지까지 잠근다.
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

    /// 상성은 데미지 기술의 규칙이다. 변화기(위력 0)는 타입 면역을 타지 않는다 —
    /// **단 상태를 거는 변화기는 그대로 본다**(전기자석파 → 땅). 대조군 없이 한쪽만 고치면
    /// 두 오구현("전부 무시" / "전부 검사")이 모두 초록으로 통과한다.
    func testStatChangeMovesIgnoreTypeImmunityButAilmentMovesDoNot() {
        var user = BattleSide(tank()), ghost = BattleSide(tank([.ghost]))
        let events = attack(&user, &ghost,
                            statusMove(changes: [StatChange(stat: .atk, change: -1)]))
        XCTAssertEqual(ghost.stage(.atk), -1, "노말 변화기는 고스트에게도 걸린다")
        XCTAssertFalse(events.contains(.immune(.b)))

        var caster = BattleSide(tank())
        var ground = BattleSide(tank([.ground]))
        var thunderWave = MoveSpec(id: 86, names: ["en": "Thunder Wave"], type: .electric, power: 0,
                                   damageClass: .status, accuracy: nil, pp: 20)
        thunderWave.ailment = "paralysis"
        let blocked = attack(&caster, &ground, thunderWave)
        XCTAssertTrue(blocked.contains(.immune(.b)), "상태를 거는 변화기는 상성을 본다")
        XCTAssertNil(ground.status, "땅 타입은 전기자석파에 마비되지 않는다")
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

    private func moveJSON(statChanges: String?, statChance: Int?) -> Data {
        let changes = statChanges.map { #", "stat_changes": \#($0)"# } ?? ""
        let chance = statChance.map { #", "meta": {"stat_chance": \#($0)}"# } ?? ""
        return Data("""
        {"id": 14, "power": 0, "accuracy": null, "pp": 20, "priority": 0,
         "type": {"name": "normal", "url": null},
         "damage_class": {"name": "status", "url": null},
         "names": [{"name": "Swords Dance", "language": {"name": "en", "url": null}}],
         "flavor_text_entries": []\(changes)\(chance)}
        """.utf8)
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

    /// `stat_changes` 는 응답에 늘 있다(없으면 빈 배열). 그래서 **키가 없는 것**은 "아직 안 받아봤다"
    /// 라는 뜻이고, `[]` 는 "받았고 변화가 없다" 다 — 둘을 섞으면 매 로드마다 다시 받거나 영영 안 고친다.
    /// `CompanionStore` 는 `@MainActor` 라 이 한 테스트만 메인 액터에서 돈다.
    @MainActor
    func testMissingStatChangesStayNilSoTheSaveCanConverge() throws {
        let unfetched = try XCTUnwrap(MoveSpec.from(
            try JSONDecoder().decode(MoveDTO.self, from: moveJSON(statChanges: nil, statChance: nil)),
            fallbackName: "swords-dance", languages: ["en"]))
        XCTAssertNil(unfetched.statChanges)
        XCTAssertTrue(CompanionStore.needsDetailRefresh(unfetched), "안 받아본 스펙은 다시 받는다")

        let fetchedEmpty = try XCTUnwrap(MoveSpec.from(
            try JSONDecoder().decode(MoveDTO.self, from: moveJSON(statChanges: "[]", statChance: 0)),
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

        // 위력 내림차순으로만 뽑으면 위력 0 인 변화기는 **절대** 안 들어온다 — 그래서 슬롯이 필요하다.
        let attacksOnly = PokeAPIClient.pickFour(
            from: [attackSpec(1, .fire, 90), attackSpec(2, .normal, 100),
                   attackSpec(3, .flying, 75), attackSpec(4, .dragon, 80)],
            types: [.fire, .flying])
        XCTAssertEqual(attacksOnly.count, 4, "변화기가 없으면 네 칸 전부 공격기다")
        XCTAssertTrue(attacksOnly.allSatisfy { $0.power > 0 })
    }

    /// 쓸 데 없는 변화기(랭크도 상태도 없는 미구현 부류)보다 실제로 뭔가 하는 변화기를 고른다.
    func testStatusSlotPrefersAMoveThatActuallyDoesSomething() {
        let inert = MoveSpec(id: 99, names: [:], type: .normal, power: 0,
                             damageClass: .status, accuracy: nil, pp: 10)
        let useful = statusMove(id: 14, changes: [StatChange(stat: .atk, change: 2)])
        let picked = PokeAPIClient.pickFour(from: [inert, useful], types: [.normal])
        XCTAssertEqual(picked.map(\.id), [14], "구현된 효과가 있는 변화기가 그 칸을 가진다")
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

    /// 라운드 결과는 호스트가 브로드캐스트한다 — 랭크가 와이어를 못 건너면 게스트 화면에서 화살표가
    /// 사라지고, 게스트가 보는 배틀과 호스트가 보는 배틀이 갈린다.
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

    /// 데미지 결과가 바뀌었고(랭크·명중), 이벤트 스트림에 case 가 늘었다 → 두 버전 다 올라가야 한다.
    /// 안 올리면 구버전 피어와 붙어 같은 배틀을 서로 다르게 보고, 구버전 게스트는 `.boost` 를
    /// 디코딩하지 못해 라운드에서 멈춘다.
    func testRuleAndProtocolVersionsMovedWithStages() {
        XCTAssertGreaterThanOrEqual(BattleEngine.rulesVersion, 6, "랭크업부터 규칙 6 이상")
        XCTAssertGreaterThanOrEqual(MultiplayerWireMessage.protocolVersion, 5, "`.boost` 가 늘어난 계약")
    }
}
