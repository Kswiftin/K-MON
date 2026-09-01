import XCTest
@testable import PokeTokenBar

/// 포켓로그식 런 코어(프로토타입). 잠그는 것은 **웨이브 진행 규칙과 파티 이월**이다 —
/// 전투 자체는 `TeamPracticeBattle`·`BattleEngine` 이 이미 자기 테스트로 잠겨 있다.
final class RogueRunTests: XCTestCase {

    private func snapshot(_ id: Int, level: Int = 5, hp: Int = 100, speed: Int = 100,
                          types: [PokemonType] = [.normal]) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "M\(id)", trainer: "T", level: level, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: hp, atk: 100, def: 50, spa: 100, spd: 50, spe: speed),
                       moves: [MoveSpec(id: 1, names: ["en": "Hit"], type: .normal, power: 200,
                                        damageClass: .physical, accuracy: nil, pp: 20)])
    }

    /// 내가 반드시 선공하고 한 방에 끝나는 상황 — 승리 경로를 rng 흔들림 없이 밟는다.
    private func makeRun(partySize: Int = 2, seed: UInt64 = 1) -> RogueRun {
        RogueRun(party: (0..<partySize).map { snapshot(1 + $0, speed: 200) },
                 opponents: [snapshot(99, level: 5, hp: 1, speed: 1)],
                 seed: seed)
    }

    // MARK: 난이도 곡선

    func testBossWavesAreEveryFourth() {
        XCTAssertEqual((1...RogueRun.finalWave).filter { RogueRun.isBoss(wave: $0) },
                       [4, 8, 12, 16, 20, 24, 28, 30])
    }

    /// 판 길이는 30 웨이브다. 12 는 강화가 쌓이기 전에 판이 닫혀 "너무 쉽다"의 직접 원인이었다.
    func testRunLengthIsThirtyWaves() {
        XCTAssertEqual(RogueRun.finalWave, 30)
        XCTAssertTrue(RogueRun.isBoss(wave: RogueRun.finalWave), "최종 웨이브는 언제나 보스다")
    }

    func testOpponentLevelRisesAndBossesAddMore() {
        XCTAssertEqual(RogueRun.opponentLevel(wave: 1), 2)       // 기준선 5 − 핸디캡 3
        XCTAssertEqual(RogueRun.opponentLevel(wave: 4), 13)      // 보스는 기준선 11 +2
        XCTAssertEqual(RogueRun.opponentLevel(wave: 28), 61)     // 기준선 59 +2
        XCTAssertEqual(RogueRun.opponentLevel(wave: 30), 65)     // 최종 기준선 63 +2
    }

    /// 보스는 기준선 위에 선다. 예전엔 기준선과 동급이라 파티가 보스마다 1 씩 앞서 나갔고,
    /// 그 여유가 판 전체를 "너무 쉽다"로 만든 축 중 하나였다.
    func testBossesOutlevelThePartyBaseline() {
        for wave in [4, 8, 12, 16, 20, 24, 28] {
            XCTAssertGreaterThan(RogueRun.opponentLevel(wave: wave),
                                 RogueRun.partyLevelBaseline(wave: wave), "wave \(wave)")
        }
    }

    /// 마지막 웨이브의 야생은 파티 기준선과 **동급**이다 — 핸디캡이 0 까지 좁아진다.
    func testWildHandicapReachesZeroAtTheEnd() {
        XCTAssertEqual(RogueTuning.standard.wildLevelHandicapEnd, 0)
        let lastWild = RogueRun.finalWave - 1     // 30 은 보스다
        XCTAssertEqual(RogueRun.opponentLevel(wave: lastWild),
                       RogueRun.partyLevelBaseline(wave: lastWild))
    }

    /// 야생은 파티 기준선보다 **낮아야** 한다. PokeRogue 는 웨이브 1 에 레벨 2 야생을 레벨 5
    /// 스타터에게 붙인다(`baseLevel = 1 + wave/2 + (wave/25)^2`) — 플레이어가 처음부터 위에 선다.
    /// 우리는 파티가 한 마리라 그 여유가 더 필요하다.
    func testWildWavesStayBelowThePartyLevelBaseline() {
        let tuning = RogueTuning.standard
        for wave in 1...RogueRun.finalWave where !RogueRun.isBoss(wave: wave) {
            XCTAssertEqual(RogueRun.opponentLevel(wave: wave),
                           RogueRun.partyLevelBaseline(wave: wave) - tuning.wildHandicap(wave: wave),
                           "wave \(wave)")
        }
    }

    /// 핸디캡은 판이 갈수록 좁아진다 — 난이도를 우상향으로 만드는 축이다. 좁아지지 않으면
    /// 야생 웨이브가 통째로 공짜가 되고 보스 네 칸에만 난이도가 몰린다(실측 hazard 0.000).
    func testWildHandicapNarrowsAcrossTheRun() {
        let tuning = RogueTuning.standard
        XCTAssertEqual(tuning.wildHandicap(wave: 1), tuning.wildLevelHandicapStart)
        XCTAssertEqual(tuning.wildHandicap(wave: tuning.finalWave), tuning.wildLevelHandicapEnd)
        for wave in 1..<tuning.finalWave {
            XCTAssertGreaterThanOrEqual(tuning.wildHandicap(wave: wave),
                                        tuning.wildHandicap(wave: wave + 1), "wave \(wave)")
        }
    }

    /// 보스만 기준선에 붙고, 그 이상 올라가는 것은 최종 웨이브뿐이다.
    /// 최종 보스만 다른 보스보다 더 올라간다(보스 보너스 + 최종 보너스).
    func testTheFinalBossStandsHighestAboveTheBaseline() {
        let final = RogueRun.opponentLevel(wave: RogueRun.finalWave)
            - RogueRun.partyLevelBaseline(wave: RogueRun.finalWave)
        let ordinary = RogueRun.opponentLevel(wave: 8) - RogueRun.partyLevelBaseline(wave: 8)
        XCTAssertGreaterThan(final, ordinary)
    }

    /// 기준선은 스타터 5 에서 승리마다 +2 로 센 보수적인 값이다(보스 +3 의 여유는 세지 않는다).
    func testPartyLevelBaselineTracksTheStarterCurve() {
        XCTAssertEqual(RogueRun.partyLevelBaseline(wave: 1), 5)
        XCTAssertEqual(RogueRun.partyLevelBaseline(wave: 30), 63)
    }

    // MARK: 상대 종 티어

    private func stats(total: Int) -> BattleStats {
        let each = total / 6
        return BattleStats(hp: each, atk: each, def: each, spa: each, spd: each,
                           spe: total - each * 5)
    }

    /// 웨이브 1 에 슬라킹(670)·전설이 나오던 결함의 회귀 — 상한이 티어 순으로 오르고, 최종 보스
    /// 상한(640)도 전설 대부분(660~720)을 막는다.
    func testBaseStatCapRisesWithTheWaveAndKeepsLegendariesOut() {
        XCTAssertFalse(RogueRun.isFairOpponent(baseStats: stats(total: 670), wave: 1))
        XCTAssertTrue(RogueRun.isFairOpponent(baseStats: stats(total: 318), wave: 1))
        XCTAssertLessThan(RogueRun.baseStatTotalCap(wave: 3), RogueRun.baseStatTotalCap(wave: 5))
        XCTAssertLessThan(RogueRun.baseStatTotalCap(wave: 5), RogueRun.baseStatTotalCap(wave: 9))
        // 마지막 구간 500 + 보스 60. 전설 대부분(660~720)은 여기서 막힌다.
        XCTAssertEqual(RogueRun.baseStatTotalCap(wave: RogueRun.finalWave), 560)
        XCTAssertFalse(RogueRun.isFairOpponent(baseStats: stats(total: 680),
                                               wave: RogueRun.finalWave))
    }

    /// 보스는 **자기 구간** 상한 +60 이다. 구간 경계가 보스 웨이브를 다음 구간으로 밀어버리면
    /// 보스 4 가 480 이 되어 뒤따르는 웨이브 5–7(420)보다 세지는 톱니가 생긴다 — 단조 증가만
    /// 재던 예전 테스트가 그걸 통과시켰다.
    func testBossCapsStayInTheirOwnTier() {
        XCTAssertEqual(RogueRun.baseStatTotalCap(wave: 4), 380)     // 1구간 320 + 보스 60
        XCTAssertEqual(RogueRun.baseStatTotalCap(wave: 8), 406)     // 2구간 346 + 보스 60
        XCTAssertGreaterThan(RogueRun.baseStatTotalCap(wave: 4), RogueRun.baseStatTotalCap(wave: 3))
        // 단조 증가는 **야생 웨이브끼리** 잰다. 보스 상한이 뒤 구간의 야생보다 높은 것은 결함이
        // 아니라 설계다(보스는 구간의 벽이다) — 모든 웨이브를 한 줄로 세우면 보스 보너스보다 구간
        // 폭이 커야만 통과하는, 웨이브 수에 매인 단정이 된다(30 웨이브에서 구간 폭은 26 이다).
        let wildCaps = (1...RogueRun.finalWave)
            .filter { !RogueRun.isBoss(wave: $0) }
            .map { RogueRun.baseStatTotalCap(wave: $0) }
        XCTAssertEqual(wildCaps, wildCaps.sorted(), "야생 상한이 뒤로 갈수록 낮아지는 구간이 있다")
        // 보스는 **자기 구간** 상한 + 보너스다. 다음 구간 값을 빌려 오면 여기서 깨진다.
        for wave in stride(from: RogueTuning.standard.bossEvery, through: RogueRun.finalWave,
                           by: RogueTuning.standard.bossEvery) {
            XCTAssertEqual(RogueRun.baseStatTotalCap(wave: wave),
                           RogueRun.baseStatTotalCap(wave: wave - 1)
                               + RogueTuning.standard.bossStatBonus, "wave \(wave)")
        }
    }

    /// 웨이브 수를 늘려도 구간이 늘 뿐 상한의 시작·끝은 그대로다 — 오르는 폭만 완만해진다.
    func testTierCapsStretchWithTheRunLength() {
        var long = RogueTuning.standard
        long.finalWave = 20
        XCTAssertEqual(RogueRun.baseStatTotalCap(wave: 1, tuning: long),
                       RogueTuning.standard.firstTierCap)
        XCTAssertEqual(RogueRun.baseStatTotalCap(wave: 20, tuning: long),
                       RogueTuning.standard.lastTierCap + long.bossStatBonus)
        let wildCaps = (1...20)
            .filter { !RogueRun.isBoss(wave: $0, tuning: long) }
            .map { RogueRun.baseStatTotalCap(wave: $0, tuning: long) }
        XCTAssertEqual(wildCaps, wildCaps.sorted(), "야생 상한이 뒤로 갈수록 낮아지는 구간이 있다")
    }

    /// 하한이 없으면 최종 보스로 잉어킹(200)이 나온다.
    func testTooWeakSpeciesAreRejectedForLateWaves() {
        XCTAssertFalse(RogueRun.isFairOpponent(baseStats: stats(total: 200),
                                               wave: RogueRun.finalWave))
    }

    /// 채워야 할 빈 칸이 있으면 볼을 던질 수 없다. 이 게이트가 없던 동안은 실패한 던지기가
    /// **볼만 먹고 턴을 쓰지 않았다** — 기절 보충 전에는 턴이 돌지 않으므로 대가가 사라졌다.
    func testABallCannotBeThrownWhileASlotWaitsForAReplacement() {
        var run = makeRun(partySize: 2)
        run.debugFaintInBattle(0)
        XCTAssertEqual(run.battle.slotsNeedingSendOut, [0], "테스트 전제: 채울 칸이 있어야 한다")
        XCTAssertFalse(run.canThrowBall)
        let balls = run.balls
        XCTAssertFalse(run.throwBall())
        XCTAssertEqual(run.balls, balls, "거부된 던지기는 볼을 먹지 않는다")
        run.sendOut(1, toSlot: 0)
        XCTAssertTrue(run.canThrowBall)
    }

    // MARK: 포획

    /// 확률은 HP 비율로 정해진다 — 만피 33%, 빈사 직전 상한 95%.
    func testCatchChanceRisesAsTheTargetWeakens() {
        var target = BattleSide(snapshot(50, level: 20))
        XCTAssertEqual(RogueRun.catchChance(target: target), 1.0 / 3, accuracy: 0.01)
        target.hp = 1
        XCTAssertEqual(RogueRun.catchChance(target: target), 0.95, accuracy: 0.01)
    }

    /// 상태이상은 확률을 올린다 — 잠듦·얼음이 가장 크다.
    func testStatusRaisesTheCatchChance() {
        var target = BattleSide(snapshot(50, level: 20))
        let plain = RogueRun.catchChance(target: target)
        target.status = .paralysis
        let paralysed = RogueRun.catchChance(target: target)
        target.status = .sleep
        XCTAssertGreaterThan(paralysed, plain)
        XCTAssertGreaterThan(RogueRun.catchChance(target: target), paralysed)
    }

    /// 보스 웨이브는 판의 관문이자 회복 지점이라 잡아서 건너뛸 수 없다.
    func testBossWavesRejectTheBall() {
        var run = makeRun()
        run.debugJump(toWave: 4)
        XCTAssertFalse(run.canThrowBall)
        XCTAssertFalse(run.throwBall())
        XCTAssertEqual(run.balls, RogueRun.ballsPerRun)
    }

    func testBallsRunOut() {
        var run = makeRun()
        run.debugSetBalls(0)
        XCTAssertFalse(run.canThrowBall)
        XCTAssertFalse(run.throwBall())
    }

    func testFullPartyRejectsTheBall() {
        let run = makeRun(partySize: RogueRun.partyLimit)
        XCTAssertFalse(run.canThrowBall)
    }

    /// 성공하면 상대가 파티에 들어오고, 웨이브는 쓰러뜨렸을 때와 **같은 규칙**으로 넘어간다.
    func testCatchingAddsTheTargetAndClearsTheWave() {
        let run = caughtRun()
        XCTAssertEqual(run.party.count, 3)
        XCTAssertEqual(run.stage, .picking)
        XCTAssertEqual(run.balls, RogueRun.ballsPerRun - 1)
        XCTAssertEqual(run.party.last?.snapshot.speciesID, 99)
        XCTAssertNil(run.party.last?.status)
    }

    /// 잡힌 개체는 그 전투의 경험치를 받지 않는다 — 원래 파티만 레벨이 오른다.
    func testCaughtMemberDoesNotGainTheWaveLevel() {
        let run = caughtRun()
        XCTAssertEqual(run.party[0].snapshot.level, 5 + RogueRun.levelGain(wave: 1))
        XCTAssertEqual(run.party.last?.snapshot.level, 5)
    }

    /// 실패한 볼도 그 턴을 쓴다 — 상대만 움직인다. 대가가 없으면 볼이 마를 때까지 던지는 것이
    /// 언제나 최선이 된다.
    func testAFailedBallCostsTheTurn() {
        let run = failedBallRun()
        XCTAssertEqual(run.stage, .battling)
        XCTAssertGreaterThan(run.battle.turn, 1)
        XCTAssertLessThan(run.party[0].hp, run.party[0].stats.hp)
    }

    /// 확률이 95% 라 잡히는 seed, 5% 라 실패하는 seed 를 각각 찾아 두 갈래를 다 밟는다.
    /// 볼 시험용 판 — 파티가 상대 공격 한 번에 죽지 않아야 실패 갈래를 볼 수 있다.
    private func ballRun(seed: UInt64) -> RogueRun {
        RogueRun(party: (0..<2).map { snapshot(1 + $0, hp: 4000, speed: 200) },
                 opponents: [snapshot(99, level: 5, hp: 100, speed: 1)],
                 seed: seed)
    }

    private func caughtRun() -> RogueRun {
        for seed in UInt64(1)...200 {
            var run = ballRun(seed: seed)
            run.debugSetOpponentHP(1)   // 확률 95%
            if run.throwBall() { return run }
        }
        XCTFail("no seed produced a catch")
        return ballRun(seed: 1)
    }

    private func failedBallRun() -> RogueRun {
        for seed in UInt64(1)...500 {
            var run = ballRun(seed: seed)
            // 만피 상대는 실패 확률이 3분의 2 다.
            if !run.throwBall() { return run }
        }
        XCTFail("no seed produced a failed ball")
        return ballRun(seed: 1)
    }

    /// 상대가 둘이 되는 판정은 **확률**이다(PokeRogue 의 1/8 과 같은 자리). 임계값이던 시절엔
    /// 특정 웨이브부터 늘 둘이라 판 후반이 통째로 같은 모양이었다.
    ///
    /// 판정은 판 seed 와 웨이브만 본다 — 같은 판을 다시 열어도(런 rng 는 그사이 소비된다)
    /// 같은 웨이브가 같은 마릿수여야 한다.
    func testDoubleOpponentIsRolledPerWave() {
        var doubles = 0
        var singles = 0
        for seed in UInt64(1)...400 {
            for wave in 1...RogueRun.finalWave {
                let count = RogueRun.opponentCount(wave: wave, seed: seed)
                XCTAssertEqual(count, RogueRun.opponentCount(wave: wave, seed: seed),
                               "seed \(seed) wave \(wave): 같은 입력이 다른 답을 냈다")
                if wave == RogueRun.finalWave {
                    XCTAssertEqual(count, 1, "최종 웨이브는 늘 한 마리다")
                } else if RogueRun.isBoss(wave: wave) {
                    XCTAssertLessThanOrEqual(count, 2)
                } else if count == 2 { doubles += 1 } else { singles += 1 }
            }
        }
        // 1/8 근처여야 한다. 폭을 넓게 잡는 이유는 seed 400 개 표본이라서다 — 여기서 걸러야 할
        // 것은 비율의 소수점이 아니라 "늘 하나" 나 "늘 둘" 로 굳어 버린 판정이다.
        let ratio = Double(doubles) / Double(doubles + singles)
        XCTAssertGreaterThan(ratio, 0.05, "야생 더블이 사실상 안 나온다")
        XCTAssertLessThan(ratio, 0.25, "야생 더블이 너무 잦다")
    }

    /// 보스 웨이브는 야생보다 **덜** 둘이 된다 — 보스는 종족값 상한을 올린 한 마리로 서는 벽이라
    /// 둘이 되면 관문이 아니라 사고가 된다(PokeRogue 도 보스 분모가 32 로 더 크다).
    func testBossWavesRollDoublesLessOften() {
        var bossDoubles = 0
        var bossTotal = 0
        for seed in UInt64(1)...2000 {
            for wave in 1..<RogueRun.finalWave where RogueRun.isBoss(wave: wave) {
                bossTotal += 1
                if RogueRun.opponentCount(wave: wave, seed: seed) == 2 { bossDoubles += 1 }
            }
        }
        XCTAssertLessThan(Double(bossDoubles) / Double(bossTotal), 0.08,
                          "보스 더블 비율이 야생과 다르지 않다")
    }

    /// 둘 중 하나를 잡아도 웨이브는 끝나지 않는다. 잡은 개체는 **그 자리에서** 파티에 들어와야
    /// 한다 — 다음 행동이 `battle.mine` 에서 파티를 다시 읽으므로 안 넣으면 조용히 사라진다.
    func testCatchingOneOfTwoKeepsTheWaveRunning() {
        var run = twoOpponentRun()
        XCTAssertEqual(run.stage, .battling)
        XCTAssertEqual(run.party.count, 3)
        XCTAssertEqual(run.battle.mine.count, 3)
        run.useMove(0)
        XCTAssertEqual(run.party.count, 3, "잡은 개체가 다음 행동에 사라졌다")
    }

    private func twoOpponentRun() -> RogueRun {
        for seed in UInt64(1)...200 {
            var run = RogueRun(party: (0..<2).map { snapshot(1 + $0, hp: 4000, speed: 200) },
                               opponents: [snapshot(98, hp: 100, speed: 1),
                                           snapshot(99, hp: 100, speed: 1)],
                               seed: seed)
            run.debugSetOpponentHP(1)
            if run.throwBall() { return run }
        }
        XCTFail("no seed produced a catch")
        return makeRun()
    }

    // MARK: 화면 국면 (재생과 코어 국면의 어긋남)

    /// 승리 정산은 마지막 턴이 재생되기 **전에** 국면을 넘긴다. 화면이 국면만 보고 그리면
    /// 결정타·기절·로그가 뜨기 전에 보상 목록이 전투를 덮는다 — 실제로 그렇게 어긋나 있었다.
    func testRewardScreenWaitsForTheLastTurnToFinishPlaying() {
        XCTAssertEqual(RogueRunPhase.of(stage: .picking, hasUnplayedEvents: true, hasNotice: false),
                       .battle)
        XCTAssertEqual(RogueRunPhase.of(stage: .picking, hasUnplayedEvents: false, hasNotice: false),
                       .picking)
    }

    /// 패배·클리어도 같은 규칙이다 — 결과 화면이 마지막 턴을 잡아먹으면 판이 끝난 이유를 못 본다.
    func testEndingWaitsForTheLastTurnToo() {
        for stage in [RogueRun.Stage.cleared, .failed] {
            XCTAssertEqual(RogueRunPhase.of(stage: stage, hasUnplayedEvents: true, hasNotice: false),
                           .battle, "\(stage)")
            XCTAssertEqual(RogueRunPhase.of(stage: stage, hasUnplayedEvents: false, hasNotice: false),
                           .ending, "\(stage)")
        }
    }

    /// 포획 성공은 이벤트를 하나도 만들지 않는다(잡힌 상대는 조용히 빠진다). 알림이 떠 있는
    /// 동안 전투를 붙잡지 않으면 "잡았다"가 화면에 존재하지 않는다.
    func testCatchNoticeHoldsTheBattleScreen() {
        XCTAssertEqual(RogueRunPhase.of(stage: .picking, hasUnplayedEvents: false, hasNotice: true),
                       .battle)
        XCTAssertEqual(RogueRunPhase.of(stage: .routing, hasUnplayedEvents: false, hasNotice: true),
                       .battle)
    }

    /// 로딩만은 예외다 — 전투가 이미 다음 웨이브 것으로 교체된 뒤라, 붙잡으면 지나간 판이 남는다.
    func testLoadingNeverHoldsTheOldBattle() {
        XCTAssertEqual(RogueRunPhase.of(stage: .loadingWave, hasUnplayedEvents: true,
                                        hasNotice: true), .loading)
    }

    // MARK: 진행

    func testWinningOffersThreeDistinctModifiers() {
        var run = makeRun()
        run.useMove(0)
        XCTAssertEqual(run.stage, .picking)
        XCTAssertEqual(run.offers.count, RogueRun.offerCount)
        XCTAssertEqual(Set(run.offers).count, RogueRun.offerCount)
    }

    func testPickingAdvancesTheWaveAndWaitsForOpponents() {
        var run = makeRun()
        run.useMove(0)
        run.pick(run.offers[0])
        XCTAssertEqual(run.wave, 1, "보상을 골랐다고 웨이브가 넘어가지는 않는다 — 길을 먼저 고른다")
        XCTAssertEqual(run.stage, .routing)
        run.take(.safe)
        XCTAssertEqual(run.wave, 2)
        XCTAssertEqual(run.stage, .loadingWave)
        run.beginWave(opponents: [snapshot(98, hp: 1, speed: 1)])
        XCTAssertEqual(run.stage, .battling)
    }

    /// 제시되지 않은 보상은 고를 수 없다 — 화면이 목록 밖의 값을 넣어도 웨이브가 넘어가지 않는다.
    func testPickIgnoresModifiersThatWereNotOffered() {
        var run = makeRun()
        run.useMove(0)
        let notOffered = RunModifier.allCases.first { !run.offers.contains($0) }!
        run.pick(notOffered)
        XCTAssertEqual(run.wave, 1)
        XCTAssertEqual(run.stage, .picking)
    }

    /// 파티 HP 는 웨이브를 넘어 이월된다 — 이게 이 판의 유일한 자원이다.
    func testPartyDamageCarriesIntoTheNextWave() {
        // 상대 첫 타를 **버티고** 반격으로 끝내야 이월을 볼 수 있다. 종족 HP 100 이면 레벨 5 유효
        // HP 가 26 인데 상대 일격이 급소까지 겹치면 그걸 넘어 쓰러진다 — 그래서 HP 를 크게 둔다.
        var run = RogueRun(party: [snapshot(1, hp: 900, speed: 1)],
                           opponents: [snapshot(99, level: 5, hp: 1, speed: 200)],
                           seed: 7)
        run.useMove(0)   // 상대가 먼저 때린 뒤 내가 쓰러뜨린다
        guard run.stage == .picking else { return XCTFail("승리하지 못했다: \(run.stage)") }
        let carried = run.party[0].hp
        XCTAssertLessThan(carried, run.party[0].stats.hp)
        run.pick(run.offers.first { $0 != .potion && $0 != .candy } ?? run.offers[0])
        run.take(.safe)
        run.beginWave(opponents: [snapshot(98, hp: 1, speed: 1)])
        XCTAssertEqual(run.battle.mine[0].hp, carried)
    }

    /// 앞 웨이브에서 1번이 쓰러졌으면 다음 웨이브는 **살아 있는 칸**으로 시작한다.
    func testNextWaveLeadsWithALivingMember() {
        var run = makeRun(partySize: 2)
        run.useMove(0)
        run.pick(run.offers[0])
        run.take(.safe)
        var fainted = run
        fainted.debugFaint(0)
        fainted.beginWave(opponents: [snapshot(98, hp: 1, speed: 1)])
        XCTAssertEqual(fainted.battle.myField.map(\.teamIndex), [1])
    }

    /// 웨이브를 넘어 이월하는 것은 HP·PP·주 상태이상뿐이다. 랭크·혼란은 전투 안의 값이라 넘기면
    /// 앞 웨이브에서 깎인 랭크를 판이 끝날 때까지 지고 간다.
    func testWaveTransitionClearsBattleOnlyState() {
        var side = BattleSide(snapshot(1))
        side.hp = side.stats.hp / 2
        side.pp[0] = 3
        side.changeStage(.atk, by: -2)
        side.confusionTurns = 3
        side.status = .poison
        var run = makeRun()
        run.useMove(0)
        run.pick(run.offers.first { $0 != .potion && $0 != .cleanse && $0 != .elixir } ?? run.offers[0])
        run.take(.safe)
        run.debugSetParty([side])
        run.beginWave(opponents: [snapshot(98, hp: 1, speed: 1)])
        XCTAssertEqual(run.battle.mine[0].stage(.atk), 0)
        XCTAssertEqual(run.battle.mine[0].confusionTurns, 0)
        XCTAssertEqual(run.battle.mine[0].hp, side.hp, "HP 는 이월한다 — 이게 이 판의 자원이다")
        XCTAssertEqual(run.battle.mine[0].pp[0], 3)
        XCTAssertNil(run.battle.mine[0].status,
                     "주 상태이상은 웨이브를 넘기지 않는다 — 한 마리 파티가 되돌릴 수단이 없다")
    }

    /// 독 하나로 판이 끝나던 자리 — 승리 정산에서 주 상태이상을 지운다. HP·PP 는 그대로 이월한다.
    func testWinningAWaveClearsStatusButKeepsDamage() {
        var run = RogueRun(party: [snapshot(1, hp: 900, speed: 1)],
                           opponents: [snapshot(99, level: 5, hp: 1, speed: 200)],
                           seed: 7)
        run.debugAfflict(.poison)
        run.useMove(0)   // 상대가 먼저 때리고, 내가 눕히고, 턴 끝에 독뎀이 들어간다
        guard run.stage == .picking else { return XCTFail("승리하지 못했다: \(run.stage)") }
        XCTAssertNil(run.party[0].status)
        XCTAssertLessThan(run.party[0].hp, run.party[0].stats.hp, "HP 는 회복되지 않는다")
    }

    func testFinalWaveVictoryClearsTheRun() {
        var run = makeRun()
        run.debugJump(toWave: RogueRun.finalWave)
        run.useMove(0)
        XCTAssertEqual(run.stage, .cleared)
        XCTAssertTrue(run.offers.isEmpty)
    }

    /// 보스를 넘으면 살아 있는 파티가 최대 HP 의 70% 까지 차오른다 — 이월 자원이 HP·PP 뿐이라 회복 지점이 없으면
    /// 후반 웨이브가 되돌릴 수 없는 소화가 된다. 야생 웨이브에서는 회복하지 않는다(이월이 자원이다).
    func testBossVictoryRestoresTheParty() {
        func damagedWin(atWave wave: Int) -> RogueRun {
            var run = RogueRun(party: [snapshot(1, hp: 900, speed: 1)],
                               opponents: [snapshot(99, level: 5, hp: 1, speed: 200)],
                               seed: 7)
            run.debugJump(toWave: wave)
            run.useMove(0)   // 상대가 먼저 때린 뒤 내가 쓰러뜨린다
            return run
        }
        let boss = damagedWin(atWave: 4)
        XCTAssertTrue(RogueRun.isBoss(wave: 4))
        let floor = Int((Double(boss.party[0].stats.hp) * RogueTuning.standard.bossHealRatio).rounded())
        XCTAssertGreaterThanOrEqual(boss.party[0].hp, floor)
        XCTAssertLessThan(boss.party[0].hp, boss.party[0].stats.hp,
                          "보스 회복은 완전 회복이 아니다 — 만피로 채우면 HP 이월이 무의미해진다")
        XCTAssertEqual(boss.party[0].pp, boss.party[0].moves.map(\.pp), "PP 는 전부 되돌린다")

        let wild = damagedWin(atWave: 3)
        XCTAssertLessThan(wild.party[0].hp, wild.party[0].stats.hp,
                          "야생 웨이브에서 회복하면 HP 이월이 자원이 아니게 된다")
    }

    func testPartyWipeFailsTheRun() {
        var run = RogueRun(party: [snapshot(1, hp: 1, speed: 1)],
                           opponents: [snapshot(99, level: 50, speed: 200)],
                           seed: 3)
        run.useMove(0)
        XCTAssertEqual(run.stage, .failed)
    }

    // MARK: 보상 효과

    func testPotionHealsTheLivingOnly() {
        var side = BattleSide(snapshot(1))
        side.hp = 1
        var dead = BattleSide(snapshot(2))
        dead.hp = 0
        var run = RogueRun(party: [snapshot(1), snapshot(2)], opponents: [snapshot(99)], seed: 1)
        run.debugSetParty([side, dead])
        run.debugApply(.potion)
        XCTAssertGreaterThan(run.party[0].hp, 1)
        XCTAssertEqual(run.party[1].hp, 0)
    }

    func testReviveBringsBackOneFaintedMember() {
        var dead = BattleSide(snapshot(2))
        dead.hp = 0
        var run = RogueRun(party: [snapshot(1), snapshot(2)], opponents: [snapshot(99)], seed: 1)
        run.debugSetParty([BattleSide(snapshot(1)), dead])
        run.debugApply(.revive)
        XCTAssertEqual(run.party[1].hp, run.party[1].stats.hp / 2)
    }

    /// 레벨업은 최대 HP 를 올린다 — **비율**로 옮기지 않으면 다친 개체가 조용히 손해를 본다.
    func testLevelUpKeepsTheDamageRatio() {
        var side = BattleSide(snapshot(1, level: 10))
        side.hp = side.stats.hp / 2
        let next = RogueRun.leveledUp(side, by: 2)
        XCTAssertGreaterThan(next.stats.hp, side.stats.hp)
        XCTAssertEqual(Double(next.hp) / Double(next.stats.hp), 0.5, accuracy: 0.02)
    }

    /// 쓰러진 개체는 레벨이 올라도 살아나지 않는다.
    func testLevelUpDoesNotReviveTheFainted() {
        var side = BattleSide(snapshot(1, level: 10))
        side.hp = 0
        XCTAssertEqual(RogueRun.leveledUp(side, by: 2).hp, 0)
    }

    func testElixirRestoresPowerPoints() {
        var side = BattleSide(snapshot(1))
        side.pp[0] = 0
        var run = RogueRun(party: [snapshot(1)], opponents: [snapshot(99)], seed: 1)
        run.debugSetParty([side])
        run.debugApply(.elixir)
        XCTAssertEqual(run.party[0].pp[0], run.party[0].moves[0].pp)
    }

    // MARK: 화면 계약 (소스 가드)

    /// 런은 `CompanionStore` 가 들어야 한다. 뷰의 `@State` 로 들면 팝오버를 닫는 순간 판이 사라진다
    /// (실제로 그렇게 유실됐다). 로직 테스트로는 잡을 수 없어 소스에서 기계적으로 확인한다.
    func testRunStateLivesInTheStore() throws {
        let source = try Self.viewSource()
        XCTAssertTrue(source.contains("store.rogueRun"),
                      "런을 store 에서 읽고 써야 팝오버를 닫아도 이어진다")
        XCTAssertFalse(source.contains("case running("),
                       "진행 중인 런을 뷰 상태(enum)로 되들이면 창을 닫을 때 사라진다")
    }

    /// 런은 자기 경기장(`WaveRunArenaView` — 한쪽에 최대 두 칸)을 쓰지만, 기술 버튼·PP 배지·로그는
    /// 그 안에서도 **배틀 화면과 같은 조각**이어야 한다. 직접 그리면 같은 기술이 화면마다 다른
    /// 색으로 보인다.
    func testRunBattleUsesTheSharedArenaRenderer() throws {
        let source = try Self.viewSource()
        XCTAssertTrue(source.contains("WaveRunArenaView("),
                      "던전 런은 2대2 를 그리는 자기 경기장을 쓴다")
        XCTAssertFalse(source.contains("Text(\"PP "),
                       "PP 표시를 직접 그리면 공용 렌더러의 색·배지 규칙에서 벗어난다")
    }

    /// 종을 전 범위에서 균등 추첨하면 웨이브 1 에 슬라킹·전설이 나온다. 채택 규칙은 코어
    /// (`RogueRun.chooseOpponent`)가 들고 있고 — 시뮬레이터가 같은 규칙을 봐야 하기 때문이다 —
    /// 뷰가 그 규칙을 실제로 지나는지는 로직 테스트로 못 잡으므로 소스에서 기계적으로 확인한다.
    func testWildDrawFiltersBySpeciesTier() throws {
        let source = try Self.viewSource()
        XCTAssertTrue(source.contains("RogueRun.chooseOpponent("),
                      "야생 뽑기는 코어의 채택 규칙(웨이브 티어)을 지나야 한다")
        XCTAssertFalse(source.contains("wildDrawAttempts"),
                       "재추첨 횟수까지 뷰가 다시 들면 시뮬레이터와 규칙이 갈린다")
    }

    /// 코어 쪽 규칙 자체 — 티어를 벗어난 후보는 거르고, 전부 어긋나면 가장 약한 것을 쓴다.
    func testChooseOpponentTakesTheFairCandidateThenTheWeakest() async {
        // 종족값 합 = hp + speed + 300 (나머지 축은 헬퍼가 고정한다). 웨이브 1 상한은 320.
        var offered = [snapshot(1, hp: 200), snapshot(2, hp: 10, speed: 5)]
        let fair = await RogueRun.chooseOpponent(wave: 1) { offered.isEmpty ? nil : offered.removeFirst() }
        XCTAssertEqual(fair?.speciesID, 2, "티어 밖(과대) 후보를 지나 공정한 후보를 잡는다")

        var allTooBig = [snapshot(3, hp: 300), snapshot(4, hp: 220)]   // 700 · 620
        let weakest = await RogueRun.chooseOpponent(wave: 1, attempts: 2) {
            allTooBig.isEmpty ? nil : allTooBig.removeFirst()
        }
        XCTAssertEqual(weakest?.speciesID, 4, "다 어긋나면 그중 가장 약한 종으로 판을 연다")
    }

    /// 재생기를 빼면 기절·피격이 화면에 뜨기 전에 필드가 다음 포켓몬으로 갈아탄다 — 사용자에게는
    /// "맞아서 쓰러진" 순간이 없고 그냥 교체된 것처럼 보인다(실제 리포트).
    func testRunBattleDrivesTheReplayAnimator() throws {
        let source = try Self.viewSource()
        XCTAssertTrue(source.contains("BattleAnimator()"), "런 전투도 기존 배틀과 같은 재생기를 쓴다")
        XCTAssertTrue(source.contains("animator.playedCount"),
                      "로그는 재생이 닿은 지점까지만 보여야 한다")
        XCTAssertTrue(source.contains("overlay: animator.overlay"),
                      "피격·기절 연출을 렌더러에 넘겨야 한다")
    }

    /// 화면 문구는 전부 `L.t` 를 지나야 한다 — 프로토타입이라 영어 리터럴로 두었더니 한국어 사용자에게
    /// 그대로 영어가 나갔다.
    func testRunScreenHasNoUntranslatedSentences() throws {
        let source = try Self.viewSource()
        var offenders: [String] = []
        for marker in ["Text(\"", "Button(\""] {
            for segment in source.components(separatedBy: marker).dropFirst() {
                guard let first = segment.first, first.isLetter, first.isASCII else { continue }
                offenders.append(marker + segment.prefix(40))
            }
        }
        XCTAssertTrue(offenders.isEmpty, "번역을 지나지 않은 문구: \(offenders)")
    }

    private static func viewSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/PokeTokenBarTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // <repo>
        return try String(contentsOf: root.appendingPathComponent("Sources/PokeTokenBar/UI/RogueRunView.swift"),
                          encoding: .utf8)
    }

    func testCleanseClearsStatusAndConfusion() {
        var side = BattleSide(snapshot(1))
        side.status = .burn
        side.statusCounter = 2
        side.confusionTurns = 3
        var run = RogueRun(party: [snapshot(1)], opponents: [snapshot(99)], seed: 1)
        run.debugSetParty([side])
        run.debugApply(.cleanse)
        XCTAssertNil(run.party[0].status)
        XCTAssertEqual(run.party[0].statusCounter, 0)
        XCTAssertEqual(run.party[0].confusionTurns, 0)
    }
}
