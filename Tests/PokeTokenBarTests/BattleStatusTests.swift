import XCTest
@testable import PokeTokenBar

/// 상태이상 6종 + 혼란(volatile). Gen 2 의 의사결정층을 현대 데미지 파이프라인 위에 얹는 단계다.
///
/// 여기 있는 테스트는 대부분 **대조군을 낀다.** 상태이상은 "전부 절반", "전부 1/8", "전부 막힘"
/// 같은 뭉뚱그린 오구현이 단독 테스트만으로는 전부 초록으로 통과하는 부류이기 때문이다.
final class BattleStatusTests: XCTestCase {

    // MARK: 고정 재료

    /// 한 턴에 쓰러지지 않는 표준 스파링 상대 — Lv.50, 종족값 전부 100 → HP 175, 나머지 120.
    private func tank(_ types: [PokemonType] = [.normal], speed: Int = 100) -> BattleSnapshot {
        BattleSnapshot(speciesID: 143, name: "탱커", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: speed))
    }

    /// 필중·저위력 — 명중 판정을 건너뛰므로 rng 를 상태 분기에서만 쓴다.
    private func harmless() -> MoveSpec {
        MoveSpec(id: 33, names: [:], type: .normal, power: 10,
                 damageClass: .physical, accuracy: nil, pp: 35)
    }

    private func attack(_ attacker: inout BattleSide, _ defender: inout BattleSide,
                        _ move: MoveSpec, rng: inout SplitMix64) -> [BattleEvent] {
        BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                 attackerActor: .a, defenderActor: .b, move: move, rng: &rng)
    }

    // MARK: 화상 — 물리만 절반 (대조군 필수)

    /// 화상은 **물리** 데미지만 절반이다. 특수기 대조군이 없으면 "전부 절반" 오구현이 초록으로 통과한다.
    func testBurnHalvesPhysicalDamageButLeavesSpecialAlone() {
        let physical = MoveSpec(id: 1, names: [:], type: .normal, power: 80,
                                damageClass: .physical, accuracy: nil, pp: 10)
        let special = MoveSpec(id: 2, names: [:], type: .normal, power: 80,
                               damageClass: .special, accuracy: nil, pp: 10)
        func damage(_ move: MoveSpec, burned: Bool) -> Int {
            var attacker = BattleSide(tank())
            if burned { attacker.status = .burn }
            var rng = SplitMix64(seed: 7)   // 같은 seed → 급소·난수 폭이 같다. 차이는 화상뿐이다.
            return BattleEngine.resolveAttack(attacker: attacker, defender: BattleSide(tank()),
                                              move: move, rng: &rng).damage
        }
        XCTAssertLessThan(damage(physical, burned: true), damage(physical, burned: false),
                          "화상이면 물리 데미지가 줄어야 한다")
        XCTAssertEqual(damage(special, burned: true), damage(special, burned: false),
                       "특수기는 화상과 무관하다 — 여기가 같지 않으면 공격 전체를 깎고 있다")
    }

    // MARK: 마비 — 스피드 25% 가 실제로 순서를 뒤집는다

    /// 스탯만 확인하면 순서 계산 경로를 밟지 않는다. 같은 배틀에서 선공이 실제로 넘어가는지 본다.
    func testParalysisQuartersSpeedAndActuallyFlipsTurnOrder() {
        var quick = BattleSide(tank(speed: 100))
        let sluggish = BattleSide(tank(speed: 50))
        XCTAssertGreaterThan(quick.effectiveSpeed, sluggish.effectiveSpeed, "마비 전엔 이쪽이 선공이다")

        quick.status = .paralysis
        XCTAssertEqual(quick.effectiveSpeed, quick.stats.spe / 4, "Gen 2 마비는 스피드를 25% 로 깎는다")
        XCTAssertLessThan(quick.effectiveSpeed, sluggish.effectiveSpeed)

        for seed in UInt64(0)..<20 {
            var rng = SplitMix64(seed: seed)
            var a = quick, b = sluggish
            let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: harmless(), moveB: harmless(),
                                                  turn: 1, rng: &rng)
            XCTAssertEqual(events.moveActors.first, .b, "seed \(seed): 마비된 쪽이 후공이어야 한다")
        }
    }

    /// 마비는 25% 확률로 행동 자체를 막는다. 확률 분기라 seed 를 순회해 관측한다.
    func testParalysisBlocksTheMoveAboutAQuarterOfTheTime() {
        var blocked = 0
        let rounds: UInt64 = 400
        for seed in UInt64(0)..<rounds {
            var side = BattleSide(tank()); side.status = .paralysis
            var defender = BattleSide(tank())
            var rng = SplitMix64(seed: seed)
            let events = attack(&side, &defender, harmless(), rng: &rng)
            if events.contains(.cant(.a, .paralysis)) {
                blocked += 1
                XCTAssertTrue(events.moveActors.isEmpty, "막혔으면 기술을 쓰지 않는다")
            }
        }
        XCTAssertEqual(Double(blocked) / Double(rounds), 0.25, accuracy: 0.08,
                       "Gen 2 는 25%(Gen 7 부터 50%) — 0 이나 1 이면 판정이 아예 죽었다")
    }

    // MARK: 잠듦 — 카운터 2~8 → 행동불능 1~7턴, 깬 턴에 바로 행동

    func testSleepBlocksUntilTheCounterRunsOutAndActsOnTheWakingTurn() {
        for seed in UInt64(0)..<24 {
            var side = BattleSide(tank())
            var defender = BattleSide(tank())
            var rng = SplitMix64(seed: seed)
            BattleEngine.inflict(.sleep, on: &side, actor: .a, rng: &rng)
            XCTAssertEqual(side.status, .sleep)
            XCTAssertTrue((2...8).contains(side.statusCounter), "seed \(seed): Gen 2 카운터는 2~8 이다")

            let blocked = side.statusCounter - 1
            XCTAssertTrue((1...7).contains(blocked), "카운터 N 은 행동불능 N−1 턴이다")
            for turn in 0..<blocked {
                let events = attack(&side, &defender, harmless(), rng: &rng)
                XCTAssertTrue(events.contains(.cant(.a, .sleep)), "seed \(seed) \(turn): 자고 있다")
                XCTAssertTrue(events.moveActors.isEmpty, "자고 있으면 기술을 쓰지 않는다")
            }
            // Gen 1 과 다른 점 — 깬 턴을 통째로 버리지 않는다.
            let waking = attack(&side, &defender, harmless(), rng: &rng)
            XCTAssertTrue(waking.contains(.cureStatus(.a, .sleep)), "seed \(seed): 깨어난다")
            XCTAssertEqual(waking.moveActors, [.a], "깬 턴에 바로 움직인다")
            XCTAssertNil(side.status)
        }
    }

    // MARK: 얼음 — 매턴 해동 판정

    func testFreezeBlocksTheMoveUntilItThaws() {
        var blockedSeen = false, thawSeen = false
        for seed in UInt64(0)..<120 {
            var side = BattleSide(tank()); side.status = .freeze
            var defender = BattleSide(tank())
            var rng = SplitMix64(seed: seed)
            let events = attack(&side, &defender, harmless(), rng: &rng)
            if events.contains(.cant(.a, .freeze)) {
                blockedSeen = true
                XCTAssertEqual(side.status, .freeze, "안 녹았으면 상태가 남는다")
                XCTAssertTrue(events.moveActors.isEmpty)
            }
            if events.contains(.cureStatus(.a, .freeze)) {
                thawSeen = true
                XCTAssertNil(side.status)
                XCTAssertEqual(events.moveActors, [.a], "녹은 턴에는 바로 움직인다")
            }
        }
        XCTAssertTrue(blockedSeen, "얼어서 못 움직이는 seed 가 있어야 한다")
        XCTAssertTrue(thawSeen, "녹는 seed 가 있어야 한다 — 없으면 영구 동결이다")
        XCTAssertEqual(BattleEngine.thawChance, 20,
                       "Gen 3 값을 기본으로 뒀다 — Gen 2 의 10% 는 평균 10턴이라 사실상 사망 선고다")
    }

    // MARK: 혼란 — 2~5턴, 50% 자멸, 무속성 물리 위력 40

    func testConfusionHurtsItselfAndSnapsOutWhenItsTurnsRunOut() {
        var selfHitSeen = false, actedSeen = false
        for seed in UInt64(0)..<40 {
            var side = BattleSide(tank())
            var defender = BattleSide(tank())
            var rng = SplitMix64(seed: seed)
            BattleEngine.inflict(.confusion, on: &side, actor: .a, rng: &rng)
            XCTAssertTrue((2...5).contains(side.confusionTurns), "seed \(seed): 혼란은 2~5턴이다")
            XCTAssertNil(side.status, "혼란은 주 상태가 아니다")

            var cured = false
            let turns = side.confusionTurns
            for _ in 0..<turns {
                let before = side.hp
                let events = attack(&side, &defender, harmless(), rng: &rng)
                if events.contains(.cant(.a, .confusion)) {
                    selfHitSeen = true
                    XCTAssertLessThan(side.hp, before, "자멸은 자기 HP 를 깎는다")
                    XCTAssertTrue(events.contains { event in
                        if case .damage(.a, _, .confusion) = event { return true } else { return false }
                    }, "자멸 데미지는 원인이 혼란으로 실린다")
                    XCTAssertTrue(events.moveActors.isEmpty)
                } else {
                    actedSeen = true
                    XCTAssertEqual(events.moveActors, [.a], "판정을 통과하면 그 턴에 공격한다")
                }
                if events.contains(.cureStatus(.a, .confusion)) { cured = true }
            }
            XCTAssertTrue(cured, "seed \(seed): \(turns)턴이 지나면 풀려야 한다")
            XCTAssertEqual(side.confusionTurns, 0)
        }
        XCTAssertTrue(selfHitSeen && actedSeen, "50% 판정이면 양쪽이 다 관측돼야 한다")
    }

    /// 자멸로도 쓰러진다. `--show-regions` 에서 이 기절 분기가 `^0` 이었다 — 위 테스트는 자멸을
    /// 관측하지만 HP 가 넉넉해 한 번도 죽지 않았고, 커버리지 숫자로는 그게 드러나지 않는다.
    func testConfusionSelfHitCanFaintAndTheStreamSaysSo() {
        for seed in UInt64(0)..<40 {
            var side = BattleSide(tank())
            var defender = BattleSide(tank())
            var rng = SplitMix64(seed: seed)
            BattleEngine.inflict(.confusion, on: &side, actor: .a, rng: &rng)
            side.hp = 1

            let events = attack(&side, &defender, harmless(), rng: &rng)

            guard events.contains(.cant(.a, .confusion)) else { continue }
            XCTAssertEqual(side.hp, 0)
            XCTAssertTrue(events.contains(.faint(.a)), "자멸로 쓰러져도 스트림이 말해야 한다")
            return
        }
        XCTFail("40개 seed 안에서 자멸이 한 번도 나지 않았다 — 판정 자체를 확인해야 한다")
    }

    /// 마지막 혼란 턴에 자멸로 쓰러지면 해제 줄을 붙이지 않는다 — "쓰러졌다 / 혼란이 풀렸다" 로 읽힌다.
    /// 살아남는 대조군이 없으면 해제 줄을 아예 지운 오구현도 통과한다.
    func testAFaintingSelfHitDoesNotAlsoReportTheConfusionWoreOff() {
        /// 마지막 혼란 턴을 강제로 만든다 — `confusionTurns` 은 판정 전에 1 줄어든다.
        func lastTurn(seed: UInt64, hp: Int) -> [BattleEvent] {
            var side = BattleSide(tank()), defender = BattleSide(tank())
            var rng = SplitMix64(seed: seed)
            BattleEngine.inflict(.confusion, on: &side, actor: .a, rng: &rng)
            side.confusionTurns = 1
            side.hp = hp
            return attack(&side, &defender, harmless(), rng: &rng)
        }
        for seed in UInt64(0)..<40 {
            let fainted = lastTurn(seed: seed, hp: 1)
            guard fainted.contains(.cant(.a, .confusion)) else { continue }
            XCTAssertTrue(fainted.contains(.faint(.a)))
            XCTAssertFalse(fainted.contains(.cureStatus(.a, .confusion)),
                           "기절 뒤에 해제 줄이 붙으면 로그가 '쓰러졌다 / 혼란이 풀렸다' 가 된다")
            XCTAssertTrue(lastTurn(seed: seed, hp: 175).contains(.cureStatus(.a, .confusion)),
                          "살아남으면 같은 턴에 해제 줄이 나와야 한다 — 여기가 없으면 해제를 통째로 잃었다")
            return
        }
        XCTFail("40개 seed 안에서 자멸이 한 번도 나지 않았다 — 판정 자체를 확인해야 한다")
    }

    /// 혼란 자멸은 무속성이다 — 자기 타입 STAB 도 상성도 타지 않는다.
    func testConfusionDamageIsTypelessAndUnaffectedByTheOwnType() {
        let normal = BattleEngine.confusionDamage(BattleSide(tank([.normal])))
        let ghost = BattleEngine.confusionDamage(BattleSide(tank([.ghost])))
        XCTAssertEqual(normal, ghost, "타입이 달라도 자멸 데미지는 같다")
        var burned = BattleSide(tank()); burned.status = .burn
        XCTAssertLessThan(BattleEngine.confusionDamage(burned), normal,
                          "자멸은 물리라 화상에 절반이 된다 (Gen 2)")
    }

    // MARK: 턴 끝 잔뎀

    func testBurnAndPoisonTakeAnEighthOfMaxHPAtTheEndOfEachTurn() {
        for (status, cause) in [(Status.burn, DamageCause.burn), (Status.poison, DamageCause.poison)] {
            var side = BattleSide(tank())
            var rng = SplitMix64(seed: 1)
            BattleEngine.inflict(status, on: &side, actor: .a, rng: &rng)
            let full = side.stats.hp
            let events = BattleEngine.endOfTurnResidual(&side, actor: .a)

            XCTAssertEqual(side.hp, full - full / 8, "\(status): 최대 HP 의 1/8")
            XCTAssertTrue(events.contains(.damage(.a, amount: full / 8, cause: cause)),
                          "\(status): 원인이 실려야 로그가 '기술을 맞았다' 로 새지 않는다")
        }
    }

    /// 맹독은 1/16 부터 매턴 1/16씩 누적한다. 값이 세 턴 모두 다르므로 "그냥 1/8" 오구현이 걸린다.
    func testToxicDamageGrowsBySixteenthsEveryTurn() {
        var side = BattleSide(tank())
        var rng = SplitMix64(seed: 1)
        BattleEngine.inflict(.toxic, on: &side, actor: .a, rng: &rng)
        let full = side.stats.hp

        var amounts: [Int] = []
        for _ in 0..<3 {
            amounts += BattleEngine.endOfTurnResidual(&side, actor: .a).compactMap { event in
                if case .damage(_, let amount, .toxic) = event { return amount } else { return nil }
            }
        }
        XCTAssertEqual(amounts, [full / 16, full * 2 / 16, full * 3 / 16])
    }

    func testResidualDamageCanFaintAndTheStreamSaysSo() {
        var side = BattleSide(tank())
        var rng = SplitMix64(seed: 1)
        BattleEngine.inflict(.poison, on: &side, actor: .a, rng: &rng)
        side.hp = 1

        let events = BattleEngine.endOfTurnResidual(&side, actor: .a)

        XCTAssertEqual(side.hp, 0)
        XCTAssertTrue(events.contains(.faint(.a)), "잔뎀으로 쓰러져도 스트림이 말해야 한다")
    }

    /// 잔뎀은 턴의 **끝**이다. 공격보다 앞에 오면 그 턴의 데미지 계산과 기절 시점이 달라진다.
    func testResolveTurnAppliesResidualDamageToBothSidesAfterTheAttacks() {
        var a = BattleSide(tank()), b = BattleSide(tank())
        var rng = SplitMix64(seed: 4)
        BattleEngine.inflict(.burn, on: &a, actor: .a, rng: &rng)
        BattleEngine.inflict(.poison, on: &b, actor: .b, rng: &rng)

        let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: harmless(), moveB: harmless(),
                                              turn: 1, rng: &rng)

        let lastMove = events.lastIndex { if case .move = $0 { return true } else { return false } }
        let firstResidual = events.firstIndex { event in
            if case .damage(_, _, .burn) = event { return true }
            if case .damage(_, _, .poison) = event { return true }
            return false
        }
        XCTAssertNotNil(lastMove)
        XCTAssertNotNil(firstResidual)
        XCTAssertLessThan(lastMove!, firstResidual!, "잔뎀은 두 공격이 모두 끝난 뒤다")
        XCTAssertTrue(events.contains { if case .damage(.a, _, .burn) = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains { if case .damage(.b, _, .poison) = $0 { return true } else { return false } })
    }

    // MARK: 부여 규칙 — 면역·중복

    /// Gen 2 타입 면역만 가져온다(전기 → 마비 면역은 Gen 6 부터라 넣지 않는다).
    /// 대조군(노말 타입)이 함께 있어야 "면역"과 "부여가 아예 죽은 것"을 가른다.
    func testGen2TypeImmunitiesBlockTheMatchingStatus() {
        func inflicted(_ status: Status, on types: [PokemonType]) -> Status? {
            var side = BattleSide(tank(types))
            var rng = SplitMix64(seed: 1)
            let events = BattleEngine.inflict(status, on: &side, actor: .a, rng: &rng)
            XCTAssertEqual(events.isEmpty, side.status == nil && !side.isConfused,
                           "부여에 실패했으면 이벤트도 없어야 한다")
            return side.status
        }
        XCTAssertNil(inflicted(.burn, on: [.fire]), "불꽃 타입은 화상을 입지 않는다")
        XCTAssertNil(inflicted(.freeze, on: [.ice]), "얼음 타입은 얼지 않는다")
        XCTAssertNil(inflicted(.poison, on: [.poison]), "독 타입은 독에 걸리지 않는다")
        XCTAssertNil(inflicted(.toxic, on: [.steel]), "강철 타입도 독에 걸리지 않는다 (Gen 2 신설)")
        // 대조군 — 같은 상태가 다른 타입에는 붙는다.
        XCTAssertEqual(inflicted(.burn, on: [.normal]), .burn)
        XCTAssertEqual(inflicted(.freeze, on: [.normal]), .freeze)
        XCTAssertEqual(inflicted(.poison, on: [.normal]), .poison)
        // 전기 타입 마비 면역은 Gen 6 규칙이라 여기서는 걸린다.
        XCTAssertEqual(inflicted(.paralysis, on: [.electric]), .paralysis)
    }

    func testOnlyOneMainStatusSticksButConfusionRidesAlongside() {
        var side = BattleSide(tank())
        var rng = SplitMix64(seed: 1)

        XCTAssertFalse(BattleEngine.inflict(.burn, on: &side, actor: .a, rng: &rng).isEmpty)
        XCTAssertTrue(BattleEngine.inflict(.paralysis, on: &side, actor: .a, rng: &rng).isEmpty,
                      "주 상태는 한 번에 하나다")
        XCTAssertEqual(side.status, .burn)

        XCTAssertFalse(BattleEngine.inflict(.confusion, on: &side, actor: .a, rng: &rng).isEmpty)
        XCTAssertEqual(side.status, .burn, "혼란은 volatile 이라 주 상태를 밀어내지 않는다")
        XCTAssertTrue(side.isConfused)
    }

    func testAFaintedSideTakesNoNewStatus() {
        var side = BattleSide(tank())
        side.hp = 0
        var rng = SplitMix64(seed: 1)
        XCTAssertTrue(BattleEngine.inflict(.burn, on: &side, actor: .a, rng: &rng).isEmpty)
        XCTAssertNil(side.status)
    }

    // MARK: 결정성 — 상태가 얹힌 배틀도 두 피어가 같은 결과를 본다

    /// 상태 없는 배틀만 테스트하면 이 부류(조건부 rng 소비로 인한 desync)를 못 잡는다.
    func testResolveTurnStaysDeterministicWithStatusesInPlay() {
        func run() -> ([BattleEvent], Int, Int) {
            var rng = SplitMix64(seed: 77)
            var a = BattleSide(tank()), b = BattleSide(tank(speed: 60))
            BattleEngine.inflict(.paralysis, on: &a, actor: .a, rng: &rng)
            BattleEngine.inflict(.confusion, on: &a, actor: .a, rng: &rng)
            BattleEngine.inflict(.sleep, on: &b, actor: .b, rng: &rng)
            var events: [BattleEvent] = []
            for turn in 1...8 {
                events += BattleEngine.resolveTurn(a: &a, b: &b, moveA: harmless(), moveB: harmless(),
                                                   turn: turn, rng: &rng)
            }
            return (events, a.hp, b.hp)
        }
        let first = run()
        for attempt in 0..<5 {
            XCTAssertTrue(run() == first, "\(attempt + 1)번째 재실행이 갈라졌다 — 두 피어면 desync 다")
        }
        XCTAssertTrue(first.0.contains { if case .cant = $0 { return true } else { return false } },
                      "상태 분기를 실제로 밟은 스트림이어야 이 테스트가 의미를 갖는다")
    }

    /// 규칙이 바뀌면 버전을 올린다 — 구버전 피어는 같은 배틀을 다르게 보므로 핸드셰이크에서 막아야 한다.
    func testRulesVersionMovesWithTheStatusConditions() {
        XCTAssertEqual(BattleEngine.rulesVersion, 13,
                       """
                       상태이상 = 3, 변화기 = 4, 끊김/에스크로 = 5, LAN 팀전 = 6, 출전 이벤트 = 7, \
                       랭크 = 8, 가변 위력 = 9, 체중 = 10, 되돌려주기 = 11, 변화기 상성 = 12, \
                       드레인·반동·다단·풀린치 = 13
                       """)
    }

    /// 위력 0 인 변화기는 데미지를 넣지 않는다. 예전엔 식의 `+2` 가 남아 2 데미지가 박혔고,
    /// `.damage` 이벤트까지 나가 로그가 "2 데미지" 를 찍었다. `learnedMoves` 는 변화기를
    /// 걸러내지 않으므로(`moveSet` 만 걸러낸다) 실제 배틀에서 밟히는 경로다.
    func testStatusMovesDealNoDamage() {
        let thunderWave = MoveSpec(id: 86, names: ["en": "Thunder Wave"], type: .electric, power: 0,
                                   damageClass: .status, accuracy: nil, pp: 20,
                                   ailment: "paralysis", ailmentChance: 0)
        var attacker = BattleSide(tank()), defender = BattleSide(tank())
        let before = defender.hp
        var rng = SplitMix64(seed: 11)
        let events = attack(&attacker, &defender, thunderWave, rng: &rng)
        XCTAssertEqual(defender.hp, before, "변화기는 HP 를 깎지 않는다")
        XCTAssertFalse(events.contains { if case .damage = $0 { return true } else { return false } },
                       "0 데미지 이벤트가 나가면 로그가 '맞았는데 0' 으로 읽힌다")
        XCTAssertTrue(events.contains(.status(.b, .paralysis)), "상태는 그대로 걸린다")
    }

    // MARK: PokéAPI 데이터 경로 — meta.ailment 가 실제로 상태를 거는 데까지

    private func moveJSON(id: Int, meta: String) -> Data {
        Data("""
        {"id": \(id), "power": 40, "accuracy": 100, "pp": 25, "priority": 0,
         "type": {"name": "fire", "url": null},
         "damage_class": {"name": "special", "url": null},
         "names": [], "flavor_text_entries": [], "meta": {\(meta)}}
        """.utf8)
    }

    /// 불꽃 2차효과 화상 — 확률만 갈아 끼워 쓴다.
    private func ember(chance: Int) -> MoveSpec {
        MoveSpec(id: 52, names: [:], type: .fire, power: 40, damageClass: .special,
                 accuracy: nil, pp: 25, ailment: "burn", ailmentChance: chance)
    }

    func testMoveSpecCarriesTheAilmentFromPokeAPIJSON() throws {
        let json = moveJSON(id: 52, meta: #""ailment": {"name": "burn", "url": null}, "ailment_chance": 10"#)
        let spec = try XCTUnwrap(MoveSpec.from(try JSONDecoder().decode(MoveDTO.self, from: json),
                                               fallbackName: "ember", languages: ["en"]))
        XCTAssertEqual(spec.ailment, "burn")
        XCTAssertEqual(spec.ailmentChance, 10)
        XCTAssertEqual(spec.inflictedStatus, .burn)
        XCTAssertEqual(spec.ailmentChancePercent, 10)
    }

    /// 구현한 6종이 **전부** 이어지는지 본다. 하나만 확인하면 나머지 분기가 죽어 있어도
    /// 통과한다(실제로 `--show-regions` 에서 paralysis·freeze·confusion 분기가 `^0` 이었다).
    func testEveryImplementedAilmentNameMapsToItsStatus() throws {
        let mapping: [(String, Status)] = [("burn", .burn), ("poison", .poison), ("paralysis", .paralysis),
                                           ("sleep", .sleep), ("freeze", .freeze), ("confusion", .confusion)]
        for (name, status) in mapping {
            let json = moveJSON(id: 52, meta: #""ailment": {"name": "\#(name)", "url": null}, "ailment_chance": 30"#)
            let spec = try XCTUnwrap(MoveSpec.from(try JSONDecoder().decode(MoveDTO.self, from: json),
                                                   fallbackName: name, languages: ["en"]))
            XCTAssertEqual(spec.inflictedStatus, status, "\(name) 이 상태로 이어져야 한다")
        }
    }

    /// `meta` 가 없던 옛 캐시 응답은 상태를 걸지 않는 기술로 읽는다 — `priority`·`critRate` 와 같은 규칙.
    func testMoveSpecWithoutMetaCarriesNoAilment() throws {
        let json = Data("""
        {"id": 33, "power": 40, "accuracy": 100, "pp": 35, "priority": 0,
         "type": {"name": "normal", "url": null},
         "damage_class": {"name": "physical", "url": null},
         "names": [], "flavor_text_entries": []}
        """.utf8)
        let spec = try XCTUnwrap(MoveSpec.from(try JSONDecoder().decode(MoveDTO.self, from: json),
                                               fallbackName: "tackle", languages: ["en"]))
        XCTAssertNil(spec.ailment)
        XCTAssertNil(spec.inflictedStatus)
        XCTAssertEqual(spec.ailmentChancePercent, 0)
    }

    /// 구현하지 않은 14종은 **부여를 무시하되 원본 이름은 남긴다.** 스펙만 확인하면 배선이 죽어
    /// 있어도 통과하므로, 실제 공격을 한 번 태워서 아무 일도 없는지까지 본다.
    func testUnimplementedAilmentsAreIgnoredRatherThanGuessed() throws {
        for name in ["leech-seed", "trap", "nightmare", "yawn", "none"] {
            let json = moveJSON(id: 73, meta: #""ailment": {"name": "\#(name)", "url": null}, "ailment_chance": 100"#)
            let spec = try XCTUnwrap(MoveSpec.from(try JSONDecoder().decode(MoveDTO.self, from: json),
                                                   fallbackName: name, languages: ["en"]))
            XCTAssertEqual(spec.ailment, name, "원본은 남긴다 — 나중에 구현할 때 재조회하지 않아도 된다")
            XCTAssertNil(spec.inflictedStatus, "\(name): 구현하지 않은 상태는 걸지 않는다")
        }
        var attacker = BattleSide(tank()), defender = BattleSide(tank())
        var rng = SplitMix64(seed: 1)
        let seeded = MoveSpec(id: 73, names: [:], type: .grass, power: 40, damageClass: .special,
                              accuracy: nil, pp: 10, ailment: "leech-seed", ailmentChance: 100)
        let events = attack(&attacker, &defender, seeded, rng: &rng)
        XCTAssertNil(defender.status)
        XCTAssertFalse(events.contains { if case .status = $0 { return true } else { return false } })
    }

    /// PokéAPI 는 맹독에도 `poison` 을 준다 — 이름만 보면 보통 독과 구분되지 않는다.
    func testToxicIsRecognisedByMoveIDBecausePokeAPICallsItPlainPoison() {
        let toxic = MoveSpec(id: MoveSpec.toxicMoveID, names: [:], type: .poison, power: 0,
                             damageClass: .status, accuracy: 90, pp: 10,
                             ailment: "poison", ailmentChance: 0)
        XCTAssertEqual(toxic.inflictedStatus, .toxic)
        XCTAssertEqual(toxic.ailmentChancePercent, 100, "변화기는 상태 부여가 본체라 확률이 아니다")

        let sludge = MoveSpec(id: 124, names: [:], type: .poison, power: 65, damageClass: .special,
                              accuracy: 100, pp: 20, ailment: "poison", ailmentChance: 30)
        XCTAssertEqual(sludge.inflictedStatus, .poison, "보통 독기는 그대로 보통 독이다")
        XCTAssertEqual(sludge.ailmentChancePercent, 30)
    }

    func testSecondaryEffectLandsAtItsChance() {
        func burnRate(_ chance: Int) -> Double {
            var burned = 0
            let rounds: UInt64 = 200
            for seed in UInt64(0)..<rounds {
                var attacker = BattleSide(tank()), defender = BattleSide(tank())
                var rng = SplitMix64(seed: seed)
                _ = attack(&attacker, &defender, ember(chance: chance), rng: &rng)
                if defender.status == .burn { burned += 1 }
            }
            return Double(burned) / Double(rounds)
        }
        XCTAssertEqual(burnRate(0), 0, "확률 0 인 공격기는 절대 걸지 않는다")
        XCTAssertEqual(burnRate(100), 1, "100%면 매번 걸린다")
        XCTAssertEqual(burnRate(30), 0.30, accuracy: 0.10)
    }

    /// 2차효과는 **붙을 수 있는지를 먼저** 보고 그 뒤에만 확률을 굴린다. 굴리고 나서 버리면 rng
    /// 스트림이 한 칸 더 나가 그 뒤의 모든 판정이 밀린다 — 이 저장소에서 소비 순서는 프로토콜이다.
    /// 결과값만 보는 테스트로는 이 차이가 안 잡힌다(`inflict` 가 어차피 한 번 더 거른다).
    func testSecondaryEffectSpendsNoRollOnATargetThatCannotBeAfflicted() {
        func rngStateAfterAttack(defender types: [PokemonType], move: MoveSpec) -> UInt64 {
            var attacker = BattleSide(tank()), defender = BattleSide(tank(types))
            var rng = SplitMix64(seed: 9)
            _ = attack(&attacker, &defender, move, rng: &rng)
            return rng.state
        }
        let noAilment = MoveSpec(id: 52, names: [:], type: .fire, power: 40,
                                 damageClass: .special, accuracy: nil, pp: 25)
        // 불꽃 타입은 화상 면역 → 확률 판정 자체를 건너뛰므로 상태 없는 기술과 소비량이 같다.
        XCTAssertEqual(rngStateAfterAttack(defender: [.fire], move: ember(chance: 100)),
                       rngStateAfterAttack(defender: [.fire], move: noAilment))
        // 대조군 — 걸릴 수 있는 상대에게는 한 번 더 굴린다.
        XCTAssertNotEqual(rngStateAfterAttack(defender: [.normal], move: ember(chance: 100)),
                          rngStateAfterAttack(defender: [.normal], move: noAilment))
    }

    func testSecondaryEffectDoesNotLandOnAFaintedTarget() {
        let frail = BattleSnapshot(speciesID: 92, name: "약골", trainer: nil, level: 5, nature: nil,
                                   isShiny: false, types: [.normal],
                                   base: BattleStats(hp: 1, atk: 1, def: 1, spa: 1, spd: 1, spe: 1))
        var attacker = BattleSide(tank()), defender = BattleSide(frail)
        var rng = SplitMix64(seed: 2)

        let events = attack(&attacker, &defender, ember(chance: 100), rng: &rng)

        XCTAssertFalse(defender.isAlive)
        XCTAssertNil(defender.status, "쓰러진 상대에게는 상태가 붙지 않는다")
        XCTAssertFalse(events.contains { if case .status = $0 { return true } else { return false } })
    }

    /// Gen 2 는 물러난 포켓몬의 맹독을 보통 독으로 강등한다. 없으면 한 번 걸린 맹독의 배수가
    /// 배틀이 끝날 때까지 계속 커진다.
    func testSwitchingDowngradesToxicToOrdinaryPoison() {
        var battle = TeamPracticeBattle(mine: [BattleSide(tank()), BattleSide(tank())],
                                        opponents: [BattleSide(tank())],
                                        rng: SplitMix64(seed: 5))
        var rng = SplitMix64(seed: 1)
        BattleEngine.inflict(.toxic, on: &battle.mine[0], actor: .a, rng: &rng)
        XCTAssertEqual(battle.mine[0].statusCounter, 1)

        XCTAssertTrue(battle.switchMine(to: 1))

        XCTAssertEqual(battle.mine[0].status, .poison)
        XCTAssertEqual(battle.mine[0].statusCounter, 0, "누적 배수도 같이 리셋된다")
    }

    /// 혼란은 volatile 이라 물러나면 풀린다. 남겨 두면 다시 나올 때 옛 카운터로 계속 혼란이다.
    func testSwitchingClearsConfusion() {
        var battle = TeamPracticeBattle(mine: [BattleSide(tank()), BattleSide(tank())],
                                        opponents: [BattleSide(tank())],
                                        rng: SplitMix64(seed: 5))
        var rng = SplitMix64(seed: 1)
        BattleEngine.inflict(.confusion, on: &battle.mine[0], actor: .a, rng: &rng)
        XCTAssertGreaterThan(battle.mine[0].confusionTurns, 0)

        XCTAssertTrue(battle.switchMine(to: 1))

        XCTAssertEqual(battle.mine[0].confusionTurns, 0, "교체로 혼란이 풀려야 한다")
    }

    /// 상대가 보내온 무브셋의 부여 확률은 신뢰 경계 밖이다 — 100 을 넘기면 매턴 확정 부여가 된다.
    func testValidationRejectsAnOutOfRangeAilmentChance() {
        func accepted(_ chance: Int?) -> Bool {
            var snapshot = tank()
            snapshot.moves = [MoveSpec(id: 52, names: [:], type: .fire, power: 40,
                                       damageClass: .special, accuracy: 100, pp: 25,
                                       ailment: "burn", ailmentChance: chance)]
            return MultiplayerValidation.valid(
                participant: LobbyParticipant(id: UUID(), trainerName: "T", speciesID: 143,
                                              team: .solo, isReady: true, isHost: false),
                snapshot: snapshot)
        }
        XCTAssertTrue(accepted(30))
        XCTAssertTrue(accepted(nil), "값이 없던 시절의 무브셋은 그대로 통과한다")
        XCTAssertFalse(accepted(400))
        XCTAssertFalse(accepted(-1))
    }

    /// 시작 스냅샷의 상태이상도 호스트가 보내오는 값이다. 최대 HP 만 보던 동안은 `sleep` +
    /// `statusCounter: 9999` 로 시작한 게스트가 배틀 내내 한 번도 못 움직였다.
    func testValidStartRejectsAFighterThatBeginsWithAStatus() {
        func fighter(_ configure: (inout BattleSide) -> Void = { _ in }) -> MultiplayerFighter {
            var f = MultiplayerFighter(
                participant: LobbyParticipant(id: UUID(), trainerName: "T", speciesID: 143,
                                             team: .solo, isReady: true, isHost: false),
                snapshot: tank())
            configure(&f.side)
            return f
        }
        XCTAssertTrue(MultiplayerValidation.validStart(fighters: [fighter(), fighter()], mode: .freeForAll))
        XCTAssertFalse(MultiplayerValidation.validStart(
            fighters: [fighter(), fighter { $0.status = .sleep }], mode: .freeForAll),
            "주 상태를 안 보면 영구히 못 움직이는 배틀이 시작된다")
        XCTAssertFalse(MultiplayerValidation.validStart(
            fighters: [fighter(), fighter { $0.confusionTurns = 3 }], mode: .freeForAll),
            "혼란은 volatile 이라 주 상태 검사에 안 걸린다 — 따로 봐야 한다")
    }

    // MARK: 배지 표기

    func testStatusBadgesAreTheShowdownAbbreviations() {
        XCTAssertEqual(Status.burn.badge, "BRN")
        XCTAssertEqual(Status.poison.badge, "PSN")
        XCTAssertEqual(Status.toxic.badge, "TOX")
        XCTAssertEqual(Status.paralysis.badge, "PAR")
        XCTAssertEqual(Status.sleep.badge, "SLP")
        XCTAssertEqual(Status.freeze.badge, "FRZ")
        XCTAssertEqual(Status.confusion.badge, "CNF")
    }
}
