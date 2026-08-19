import XCTest
@testable import PokeTokenBar

/// 상태이상 6종 + 혼란(volatile). Gen 2 의 의사결정층을 현대 데미지 파이프라인 위에 얹는 단계다.
///
/// 여기 있는 테스트는 대부분 **대조군을 끼고** 쓴다. 상태이상은 "전부 절반", "전부 1/8", "전부 막힘"
/// 같은 뭉뚱그린 오구현이 단독 테스트만으로는 전부 초록으로 통과하는 부류이기 때문이다.
final class BattleStatusTests: XCTestCase {

    // MARK: 고정 재료

    /// 한 턴에 쓰러지지 않는 표준 스파링 상대 — Lv.50, 종족값 전부 100 → HP 175, 나머지 120.
    private func tank(_ types: [PokemonType] = [.normal], speed: Int = 100) -> BattleSnapshot {
        BattleSnapshot(speciesID: 143, name: "탱커", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: speed))
    }

    /// 필중·저위력 — 명중 판정을 건너뛰므로 rng 소비가 상태 분기 것만 남는다.
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
        XCTAssertEqual(quick.effectiveSpeed, quick.stats.spe / 4, "Gen 2 마비는 스피드 25% 다")
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
                       "Gen 2 는 25% 다 (Gen 7 부터 50%) — 0 이나 1 이면 판정이 아예 죽었다")
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

    /// 맹독은 1/16 부터 매턴 1/16 씩 누적한다. 값이 세 턴 모두 다르므로 "그냥 1/8" 오구현이 걸린다.
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
    /// 대조군(노말 타입)이 함께 있어야 "면역"과 "부여 자체가 죽음"을 가른다.
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
        XCTAssertEqual(BattleEngine.rulesVersion, 3, "상태이상 도입 = 규칙 3")
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
