import XCTest
@testable import PokeTokenBar

/// LAN 협동 레이드(#80)의 순수 코어 — 오늘의 보스·정산·협동 보스전 판정.
///
/// 이 파일이 지키는 것은 **표**다. 티어 숫자는 언제든 조정하는 손잡이지만, 조정이 "1★는 혼자,
/// 3★는 둘, 5★는 셋" 이라는 설계 의도를 조용히 깨뜨리면 안 된다 — 그 관계를 산수로 못 박는다.
final class RaidTests: XCTestCase {

    // MARK: 고정 재료

    /// Lv.50, 종족값 전부 100 → HP 175. 랭크·데미지 검산이 손으로 되는 값(`BattleStageTests` 와 같다).
    private func tank(level: Int = RaidBoss.partyLevel, speed: Int = 100) -> BattleSnapshot {
        BattleSnapshot(speciesID: 143, name: "탱커", trainer: nil, level: level, nature: nil,
                       isShiny: false, types: [.normal],
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: speed))
    }

    private func tackle(power: Int = 80) -> MoveSpec {
        MoveSpec(id: 33, names: ["en": "Tackle"], type: .normal, power: power,
                 damageClass: .physical, accuracy: nil, pp: 35)
    }

    /// 러너 한 명 — 레이드 파티는 팀 `.red` 다.
    private func runner(_ name: String = "러너", id: UUID = UUID()) -> MultiplayerFighter {
        var snapshot = tank()
        snapshot.moves = [tackle()]
        let participant = LobbyParticipant(id: id, trainerName: name, speciesID: snapshot.speciesID,
                                           team: .red, isReady: true, isHost: false)
        return MultiplayerFighter(participant: participant, snapshot: snapshot)
    }

    /// 오늘자 보스 — 호스트가 굽는 것과 같은 경로로 만든다.
    private func boss(tier: RaidTier = .one, dayKey: String = "2026-09-02",
                      speed: Int = 1) -> MultiplayerFighter {
        var snapshot = tank(level: tier.bossLevel, speed: speed)
        snapshot.speciesID = RaidBoss.speciesID(dayKey: dayKey, tier: tier)
        snapshot.isShiny = RaidBoss.isShinyBoss(tier: tier)
        snapshot.moves = [tackle(power: 40)]
        return RaidBoss.bossFighter(tier: tier, snapshot: snapshot)
    }

    // MARK: 오늘의 보스 — 날짜 결정론

    /// 같은 날은 모두에게 같은 보스다. 이게 깨지면 게스트의 오늘자 검증이 정상 호스트를 거절한다.
    func testTodaysBossIsDeterministicPerDayKey() {
        for tier in RaidTier.allCases {
            XCTAssertEqual(RaidBoss.speciesID(dayKey: "2026-09-02", tier: tier),
                           RaidBoss.speciesID(dayKey: "2026-09-02", tier: tier))
            XCTAssertTrue(RaidBoss.speciesPool(for: tier).contains(
                RaidBoss.speciesID(dayKey: "2026-09-02", tier: tier)))
        }
    }

    /// **회귀(#270)**: 티어마다 풀이 갈리므로 같은 날이어도 티어가 다르면 보스도 다르다(각 풀이
    /// 서로소라 우연히 같은 값이 나올 수도 없다). 이게 깨지면 1★와 5★가 다시 같은 종을 내고,
    /// 티어를 나눈 의미가 사라진다.
    func testEachTierDrawsFromItsOwnPool() {
        for dayKey in ["2026-09-02", "2026-09-20", "2026-12-25"] {
            let byTier = RaidTier.allCases.map { RaidBoss.speciesID(dayKey: dayKey, tier: $0) }
            XCTAssertEqual(Set(byTier).count, RaidTier.allCases.count,
                           "\(dayKey): 티어마다 다른 종이어야 한다")
        }
        XCTAssertTrue(Set(RaidBoss.uncommonSpeciesPool).isDisjoint(with: RaidBoss.rareSpeciesPool))
        XCTAssertTrue(Set(RaidBoss.uncommonSpeciesPool).isDisjoint(with: RaidBoss.legendarySpeciesPool))
        XCTAssertTrue(Set(RaidBoss.rareSpeciesPool).isDisjoint(with: RaidBoss.legendarySpeciesPool))
        XCTAssertTrue(Set(RaidBoss.weeklySpeciesPool).isDisjoint(with: RaidBoss.uncommonSpeciesPool))
        XCTAssertTrue(Set(RaidBoss.weeklySpeciesPool).isDisjoint(with: RaidBoss.rareSpeciesPool))
        XCTAssertTrue(Set(RaidBoss.weeklySpeciesPool).isDisjoint(with: RaidBoss.legendarySpeciesPool))
    }

    /// 날짜가 바뀌면 로테이션이 돈다. 한 해를 돌려 **풀의 절반 이상**이 실제로 나오는지 본다 —
    /// 상수를 돌려주는 오구현은 위 테스트만으로는 초록이다.
    func testBossRotatesAcrossTheYear() {
        var seen = Set<Int>()
        for month in 1...12 {
            for day in 1...28 {
                seen.insert(RaidBoss.speciesID(dayKey: String(format: "2026-%02d-%02d", month, day), tier: .three))
            }
        }
        XCTAssertGreaterThan(seen.count, RaidBoss.speciesPool(for: .three).count / 2,
                             "1년치 날짜가 풀의 절반도 못 밟으면 로테이션이 아니다")
    }

    /// 자리를 바꾼 날짜 키가 같은 보스를 내면 안 된다 — 자릿수를 안 보는 합산 해시의 전형적 붕괴다.
    func testDayKeyHashIsPositionSensitive() {
        XCTAssertNotEqual(RaidBoss.speciesID(dayKey: "2026-09-02", tier: .three),
                          RaidBoss.speciesID(dayKey: "2026-09-20", tier: .three))
    }

    func testNoonSplitsTheDayIntoTwoDifferentBosses() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 11, minute: 59))!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))!

        XCTAssertEqual(RaidBoss.periodKey(morning, calendar: calendar), "2026-09-07-am")
        XCTAssertEqual(RaidBoss.periodKey(afternoon, calendar: calendar), "2026-09-07-pm")
        XCTAssertNotEqual(RaidBoss.speciesID(at: morning, tier: .three, calendar: calendar),
                          RaidBoss.speciesID(at: afternoon, tier: .three, calendar: calendar))
    }

    func testCatchRatesFollowRarity() {
        XCTAssertEqual(RaidBoss.catchPercent(for: .legendary), 5)
        XCTAssertEqual(RaidBoss.catchPercent(for: .rare), 15)
        XCTAssertEqual(RaidBoss.catchPercent(for: .uncommon), 25)
    }

    func testWeeklySixStarBossIsAlwaysShinyAndHasThreePercentCatchRate() {
        let species = RaidBoss.speciesID(dayKey: "2026-W37", tier: .six)
        XCTAssertTrue(RaidBoss.isShinyBoss(tier: .six))
        XCTAssertFalse(RaidBoss.isShinyBoss(tier: .five))
        XCTAssertTrue(boss(tier: .six, dayKey: "2026-W37").side.snapshot.isShiny)
        XCTAssertEqual(RaidBoss.catchPercent(tier: .six, speciesID: species), 3)
    }

    func testRaidPoolsAreBroadEnoughToAvoidFrequentRepeats() {
        XCTAssertGreaterThanOrEqual(RaidBoss.uncommonSpeciesPool.count, 100)
        XCTAssertGreaterThanOrEqual(RaidBoss.rareSpeciesPool.count, 20)
        XCTAssertGreaterThanOrEqual(RaidBoss.legendarySpeciesPool.count, 30)
        XCTAssertGreaterThanOrEqual(RaidBoss.weeklySpeciesPool.count, 80)
    }

    // MARK: 이벤트 창(2026-09-11 08~20시) — 레이드 1시간 로테이션

    func testLiveEventWindowIsOnlyActiveOnTheGivenDayAndHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 9, year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day,
                                               hour: hour, minute: minute))!
        }

        XCTAssertFalse(LiveEventWindow.isActive(at(11, 7, 59), calendar: calendar), "창 시작 직전")
        XCTAssertTrue(LiveEventWindow.isActive(at(11, 8), calendar: calendar), "창 시작")
        XCTAssertTrue(LiveEventWindow.isActive(at(11, 19, 59), calendar: calendar), "창 끝 직전")
        XCTAssertFalse(LiveEventWindow.isActive(at(11, 20), calendar: calendar), "창 끝")
        XCTAssertFalse(LiveEventWindow.isActive(at(10, 12), calendar: calendar), "하루 전")
        XCTAssertFalse(LiveEventWindow.isActive(at(12, 12), calendar: calendar), "하루 뒤")
        XCTAssertFalse(LiveEventWindow.isActive(at(11, 12, year: 2027), calendar: calendar), "1년 뒤 같은 날짜")
    }

    /// `endDate` 는 그 날의 20:00 을 낸다 — 레이드 화면의 "N시간 M분 남음" 배너
    /// (`RaidView.eventRemainingText`)가 이 값과 지금 시각의 차로 카운트다운을 계산한다.
    func testLiveEventWindowEndDateIsTwentyHundredOnTheSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 12))!
        let expectedEnd = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 20))!

        XCTAssertEqual(LiveEventWindow.endDate(noon, calendar: calendar), expectedEnd)
    }

    /// 이벤트 창 동안만 보스 종 선택이 반나절(`periodKey`)이 아니라 시간(`hourlyKey`)을 탄다 —
    /// 6★ 는 그 주 내내 고정이라 이벤트와 무관하다.
    func testBossKeyRotatesHourlyOnlyDuringTheEventWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let inEvent = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 13, minute: 30))!
        let nextHour = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 14, minute: 5))!
        let outsideEvent = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 13, minute: 30))!

        XCTAssertEqual(RaidBoss.bossKey(at: inEvent, tier: .three, calendar: calendar), "2026-09-11-13")
        XCTAssertEqual(RaidBoss.bossKey(at: nextHour, tier: .three, calendar: calendar), "2026-09-11-14")
        XCTAssertNotEqual(RaidBoss.bossKey(at: inEvent, tier: .three, calendar: calendar),
                          RaidBoss.bossKey(at: nextHour, tier: .three, calendar: calendar),
                          "같은 반나절 안이라도 시간이 바뀌면 보스 선택 키가 바뀌어야 한다")
        XCTAssertEqual(RaidBoss.speciesID(at: inEvent, tier: .three, calendar: calendar),
                       RaidBoss.speciesID(dayKey: "2026-09-11-13", tier: .three),
                       "speciesID(at:) 는 bossKey 가 낸 키를 그대로 써야 한다")

        // 창 밖에서는 평소처럼 반나절 키다.
        XCTAssertEqual(RaidBoss.bossKey(at: outsideEvent, tier: .three, calendar: calendar), "2026-09-12-pm")

        // 6★ 는 이벤트와 무관하게 그 주 내내 고정.
        XCTAssertEqual(RaidBoss.bossKey(at: inEvent, tier: .six, calendar: calendar),
                       RaidBoss.weeklyPeriodKey(inEvent, calendar: calendar))
    }

    /// [회귀 가드] `MultiplayerRoomCenter.applyRaidSettlement` 는 시계를 주입받지 않아
    /// (`Date()` 를 직접 쓴다) 이 판정을 그 자리에 `||` 로만 남기면 이벤트 쪽 분기가 CI 에서
    /// 한 번도 실행되지 않는 죽은 줄로 남는다 — `RaidBoss.shouldDrawRaidCatcher` 로 뽑아내
    /// 여기서 직접 이벤트 경계를 테스트한다.
    func testShouldDrawRaidCatcherIgnoresPayoutOnlyDuringTheEventWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let inEvent = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 13))!
        let outsideEvent = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 21))!

        XCTAssertTrue(RaidBoss.shouldDrawRaidCatcher(payoutSucceeded: true, at: outsideEvent, calendar: calendar),
                      "평소엔 지급 성공이 곧 추첨 조건이다")
        XCTAssertFalse(RaidBoss.shouldDrawRaidCatcher(payoutSucceeded: false, at: outsideEvent, calendar: calendar),
                       "평소엔 지급이 안 됐으면(같은 구간 재도전) 추첨도 없다")
        XCTAssertTrue(RaidBoss.shouldDrawRaidCatcher(payoutSucceeded: false, at: inEvent, calendar: calendar),
                      "이벤트 창 동안은 지급 성공 여부와 무관하게 항상 추첨을 돌려야 한다")
    }

    func testEvolutionDayAndNightAlsoChangeAtNoon() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let beforeNoon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7,
                                                             hour: 11, minute: 59))!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))!

        XCTAssertTrue(RaidHalfDay.satisfiesEvolution("day", at: beforeNoon, calendar: calendar))
        XCTAssertFalse(RaidHalfDay.satisfiesEvolution("night", at: beforeNoon, calendar: calendar))
        XCTAssertFalse(RaidHalfDay.satisfiesEvolution("day", at: noon, calendar: calendar))
        XCTAssertTrue(RaidHalfDay.satisfiesEvolution("night", at: noon, calendar: calendar))
    }

    // MARK: 티어 표 — 설계 의도를 산수로 못 박는다

    /// 1★는 혼자, 3★는 둘, 5★는 셋. **보스 HP 는 참가 인원으로 스케일하지 않으므로** 이 관계는
    /// 오로지 HP 표와 턴 상한이 만든다. 표를 만지다 관계가 깨지면 여기가 빨개진다.
    func testTierHPGatesPartySize() {
        let budget = RaidBoss.runnerDamageBudget
        XCTAssertLessThanOrEqual(RaidTier.one.bossHP, budget, "1★는 혼자 잡을 수 있어야 한다")
        XCTAssertGreaterThan(RaidTier.three.bossHP, budget, "3★를 혼자 잡을 수 있으면 팀을 짤 이유가 없다")
        XCTAssertLessThanOrEqual(RaidTier.three.bossHP, budget * 2)
        XCTAssertGreaterThan(RaidTier.five.bossHP, budget * 2, "5★는 둘로는 못 잡는다")
        XCTAssertLessThanOrEqual(RaidTier.five.bossHP, budget * 3)
        XCTAssertGreaterThan(RaidTier.six.bossHP, budget * 4, "6★는 추천 인원보다 적으면 어렵게 둔다")
        XCTAssertLessThanOrEqual(RaidTier.six.bossHP, budget * 5)
    }

    /// 화면이 그리는 권장 인원이 위 산수와 **같은 표**에서 나와야 한다 — 따로 적으면 갈라진다.
    func testRecommendedRunnersMatchesTheHPTable() {
        XCTAssertEqual(RaidTier.one.recommendedRunners, 1)
        XCTAssertEqual(RaidTier.three.recommendedRunners, 2)
        XCTAssertEqual(RaidTier.five.recommendedRunners, 3)
        XCTAssertEqual(RaidTier.six.recommendedRunners, 5)
    }

    /// 보스 레벨은 티어를 따라 오른다 — HP 가 절대값이라 **화력을 정하는 유일한 손잡이**다.
    func testBossLevelRisesWithTier() {
        XCTAssertLessThan(RaidTier.one.bossLevel, RaidTier.three.bossLevel)
        XCTAssertLessThan(RaidTier.three.bossLevel, RaidTier.five.bossLevel)
        XCTAssertLessThanOrEqual(RaidTier.five.bossLevel, RaidBoss.partyLevel,
                                 "보스가 파티보다 높은 레벨이면 화력이 HP 표와 무관하게 튄다")
        XCTAssertEqual(RaidTier.six.bossLevel, RaidBoss.partyLevel)
    }

    func testSixStarBossStaysFixedForTheWholeWeek() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 9))!
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        XCTAssertEqual(RaidBoss.speciesID(at: monday, tier: .six, calendar: calendar),
                       RaidBoss.speciesID(at: sunday, tier: .six, calendar: calendar))
    }

    // MARK: 정산 — 기여도가 무임승차를 가른다

    /// 기여도 항이 없으면 캐리와 무임승차의 보상이 같다. 그 항이 실제로 갈라놓는지 본다.
    func testContributionSeparatesTheCarrierFromTheFreeloader() {
        let carry = RaidBoss.settlement(tier: .five, myDamage: 2_400, totalDamage: 2_800,
                                        turnsRemaining: 5, survivingRunners: 3, runnerCount: 3)
        let coast = RaidBoss.settlement(tier: .five, myDamage: 400, totalDamage: 2_800,
                                        turnsRemaining: 5, survivingRunners: 3, runnerCount: 3)
        XCTAssertGreaterThan(carry.contribution, coast.contribution)
        XCTAssertGreaterThan(carry.total, coast.total)
        XCTAssertEqual(carry.base, coast.base, "기본급은 잡은 사실에 대한 것이라 같다")
    }

    /// 정산은 자기가 늘린 지갑을 **전부 설명해야 한다**(defect-log: 한 지갑에 여러 경로).
    func testSettlementTotalExplainsEveryTerm() {
        let s = RaidBoss.settlement(tier: .three, myDamage: 800, totalDamage: 1_600,
                                    turnsRemaining: 4, survivingRunners: 2, runnerCount: 2)
        XCTAssertEqual(s.total, s.base + s.contribution + s.turnBonus + s.survivorBonus)
        XCTAssertEqual(s.contribution, RaidTier.three.baseReward / 2, "절반을 넣었으면 기여 항도 절반")
    }

    /// 경계 — 아무도 피해를 안 넣은 판(턴 상한 패배 뒤 잘못 불린 경우)에서 0 나눗셈이 나면 안 된다.
    func testSettlementSurvivesZeroTotalDamage() {
        let s = RaidBoss.settlement(tier: .one, myDamage: 0, totalDamage: 0,
                                    turnsRemaining: 0, survivingRunners: 0, runnerCount: 2)
        XCTAssertEqual(s.contribution, 0)
        XCTAssertEqual(s.total, RaidTier.one.baseReward)
    }

    /// 음수·초과분은 경계에서 자른다 — 호스트가 보내오는 값이 정산에 그대로 들어가는 자리다.
    func testSettlementClampsHostSuppliedNumbers() {
        let s = RaidBoss.settlement(tier: .one, myDamage: 9_999, totalDamage: 100,
                                    turnsRemaining: -5, survivingRunners: -3, runnerCount: 2)
        XCTAssertEqual(s.contribution, RaidTier.one.baseReward, "기여 비율은 1 을 못 넘는다")
        XCTAssertEqual(s.turnBonus, 0)
        XCTAssertEqual(s.survivorBonus, 0)
    }

    // MARK: 혼자 도는 판 — 협동 항만 접힌다

    /// **혼자면 기본급만이다.** 기여도·남은 턴·생존은 협동 항이라 사람이 둘 이상일 때만 붙는다.
    ///
    /// 지급을 통째로 0 으로 두지 않는 이유가 설계다 — 1★ 는 혼자 잡히도록 HP 를 고른 티어라,
    /// 0 을 주면 이웃 없는 사용자에게 이 기능이 콘텐츠가 0 이 된다(`RaidTier` 주석). 줄이되 없애지
    /// 않는 것이 "뭉칠 이유"와 "혼자서도 돌 만함"을 동시에 지키는 자리다.
    func testASoloRunnerGetsTheBaseAndNothingElse() {
        let solo = RaidBoss.settlement(tier: .one, myDamage: 400, totalDamage: 400,
                                       turnsRemaining: 19, survivingRunners: 1, runnerCount: 1)
        XCTAssertEqual(solo.base, RaidTier.one.baseReward, "기본급은 잡은 사실에 대한 것이라 남는다")
        XCTAssertEqual(solo.contribution, 0, "혼자면 기여 비율이 언제나 100% 라 항이 뜻을 잃는다")
        XCTAssertEqual(solo.turnBonus, 0)
        XCTAssertEqual(solo.survivorBonus, 0)
        XCTAssertEqual(solo.total, RaidTier.one.baseReward)
    }

    /// 화면과 정산이 **같은 술어**를 본다. 정산표에 `+0 ✨` 세 줄이 이유 없이 뜨면 규칙이 아니라
    /// 계산 오류로 읽히므로 화면이 그 자리에서 설명해야 하고(`raidAlreadyPaidToday` 와 같은 이유),
    /// 설명 조건을 따로 적으면 문구와 실제 정산이 갈린다.
    func testCoopTermsApplyExactlyWhenTheSettlementKeepsThem() {
        XCTAssertFalse(RaidBoss.coopTermsApply(runnerCount: 1), "혼자면 협동 항이 없다")
        XCTAssertTrue(RaidBoss.coopTermsApply(runnerCount: RaidBoss.minimumCoopRunners))
        for count in 0...4 {
            let settled = RaidBoss.settlement(tier: .three, myDamage: 800, totalDamage: 800,
                                              turnsRemaining: 5, survivingRunners: count,
                                              runnerCount: count)
            XCTAssertEqual(settled.contribution > 0, RaidBoss.coopTermsApply(runnerCount: count),
                           "\(count)인 판에서 화면 술어와 정산이 갈린다")
        }
    }

    /// **대조군.** 같은 입력에 사람만 하나 더 있으면 네 항이 전부 산다 — 이걸 안 재면
    /// "협동 항이 통째로 죽었다" 도 초록이다.
    func testTwoRunnersKeepEveryCoopTerm() {
        let party = RaidBoss.settlement(tier: .one, myDamage: 400, totalDamage: 400,
                                        turnsRemaining: 19, survivingRunners: 1, runnerCount: 2)
        XCTAssertEqual(party.contribution, RaidTier.one.baseReward, "100% 기여는 기본급 전액이다")
        XCTAssertEqual(party.turnBonus, RaidBoss.turnBonusPerTurn * 19)
        XCTAssertEqual(party.survivorBonus, RaidBoss.survivorBonusPerRunner)
        XCTAssertGreaterThan(party.total, RaidTier.one.baseReward)
    }

    // MARK: 포획 추첨 — 서버 없이 모두가 같은 한 명에 닿는다

    /// 당첨자는 **정렬된 UUID + 시드**로 정해진다. 정렬이 없으면 피어마다 `fighters` 배열 순서가
    /// 달라 같은 판에서 서로 다른 사람을 당첨자로 계산하고, 아무도 못 잡거나 둘이 잡는다.
    func testCatcherIsTheSameForEveryPeerOrdering() {
        let ids = (0..<4).map { _ in UUID() }
        let mine = RaidBoss.catcher(runnerIDs: ids, seed: 0xDEAD_BEEF, finishedRound: 3)
        XCTAssertNotNil(mine)
        for _ in 0..<20 {
            XCTAssertEqual(RaidBoss.catcher(runnerIDs: ids.shuffled(), seed: 0xDEAD_BEEF, finishedRound: 3), mine,
                           "배열 순서가 답을 바꾸면 피어끼리 다른 당첨자를 본다")
        }
    }

    /// 뽑힌 사람은 반드시 참가자다 — 인덱스가 범위를 벗어나면 아무도 못 받는다.
    func testCatcherIsAlwaysOneOfTheRunners() {
        let ids = (0..<3).map { _ in UUID() }
        for seed in [UInt64](arrayLiteral: 0, 1, 2, 3, .max, 12_345) {
            let picked = RaidBoss.catcher(runnerIDs: ids, seed: seed, finishedRound: 3)
            XCTAssertTrue(ids.contains { $0 == picked }, "시드 \(seed) 가 참가자 밖을 짚었다")
        }
    }

    /// 시드가 도는 동안 한 사람만 계속 뽑히면 "랜덤 1명" 이 아니다.
    func testCatcherRotatesAcrossSeeds() {
        let ids = (0..<3).map { _ in UUID() }
        let picked = Set((0..<64).compactMap { RaidBoss.catcher(runnerIDs: ids, seed: UInt64($0), finishedRound: 3) })
        XCTAssertEqual(picked.count, 3, "시드를 64번 굴려도 세 명이 다 안 나오면 추첨이 아니다")
    }

    func testCatcherIsNilWithoutRunners() {
        XCTAssertNil(RaidBoss.catcher(runnerIDs: [], seed: 7, finishedRound: 3))
    }

    /// **당첨자는 판이 끝나기 전에 알 수 없어야 한다.** `.raidStart` 가 시드와 편성을 함께 나르므로,
    /// 추첨이 그 둘만 읽으면 아무 피어(혹은 와이어를 읽는 사람)나 1라운드에 결과를 계산할 수 있다.
    /// 못 이기는 걸 아는 세 명에게 20턴의 누적 피해는 정산 말고는 아무것도 주지 않는데, 기여도 항이
    /// 지키려던 유인이 바로 그것이다.
    func testTheDrawIsNotDecidedBeforeTheFightEnds() {
        let ids = (0..<3).map { _ in UUID() }
        let byRound = Set((1...RaidBoss.turnCap).compactMap {
            RaidBoss.catcher(runnerIDs: ids, seed: 0xC0FF_EE, finishedRound: $0)
        })
        XCTAssertGreaterThan(byRound.count, 1,
                             "끝난 라운드가 답을 못 바꾸면 시드만으로 당첨자를 미리 계산할 수 있다")
    }

    /// 그래도 **한 판 안에서는** 답이 하나다 — 같은 판을 두 번 물으면 같은 사람이어야 한다.
    /// (같은 시드·같은 라운드는 모든 피어가 스스로 계산할 수 있는 값이라 와이어가 늘지 않는다.)
    func testTheDrawIsStableWithinOneRaid() {
        let ids = (0..<4).map { _ in UUID() }
        let first = RaidBoss.catcher(runnerIDs: ids, seed: 99, finishedRound: 7)
        XCTAssertEqual(RaidBoss.catcher(runnerIDs: ids, seed: 99, finishedRound: 7), first)
    }

    /// 티어는 포획 기회를 막지 않고 난이도와 별의조각만 가른다.
    func testOnlyThreeAndFiveStarGrantACatch() {
        XCTAssertTrue(RaidTier.one.grantsCatch)
        XCTAssertTrue(RaidTier.three.grantsCatch)
        XCTAssertTrue(RaidTier.five.grantsCatch)
    }

    // MARK: 협동 보스전 판정

    func testBossDeadIsAWinForEveryRunner() throws {
        let a = runner("A"), b = runner("B")
        var deadBoss = boss()
        deadBoss.side.hp = 0
        let fighters = [a, b, deadBoss]
        XCTAssertTrue(MultiplayerBattle.isFinished(fighters: fighters, mode: .coopBoss))
        XCTAssertEqual(MultiplayerBattle.outcome(for: a.id, fighters: fighters, mode: .coopBoss), .win)
        XCTAssertEqual(MultiplayerBattle.outcome(for: b.id, fighters: fighters, mode: .coopBoss), .win,
                       "쓰러진 대원도 파티가 이겼으면 승리다")
    }

    func testPartyWipeIsALoss() {
        var a = runner("A"), b = runner("B")
        a.side.hp = 0; b.side.hp = 0
        let fighters = [a, b, boss()]
        XCTAssertTrue(MultiplayerBattle.isFinished(fighters: fighters, mode: .coopBoss))
        XCTAssertEqual(MultiplayerBattle.outcome(for: a.id, fighters: fighters, mode: .coopBoss), .loss)
    }

    func testRaidIsNotFinishedWhileBothSidesLive() {
        let fighters = [runner(), boss()]
        XCTAssertFalse(MultiplayerBattle.isFinished(fighters: fighters, mode: .coopBoss))
        XCTAssertNil(MultiplayerBattle.outcome(for: fighters[0].id, fighters: fighters, mode: .coopBoss))
    }

    /// **트리거 브랜치**: 1인 레이드. 러너 1 + 보스 1 = 2 명이라 기존 정원 가드는 통과하지만,
    /// 편성 규칙이 `.teams` 것을 그대로 쓰면(4명·2:2) 솔로가 통째로 막힌다.
    func testSoloRaidIsAValidStart() throws {
        let fighters = [runner(), boss()]
        XCTAssertTrue(MultiplayerValidation.validStart(fighters: fighters, mode: .coopBoss))
        XCTAssertNoThrow(try MultiplayerBattle(fighters: fighters, mode: .coopBoss, seed: 1))
    }

    /// 8인 파티 + 보스 = 9명. 기존 4인 레이드 정원 가드에 그대로 걸리는 자리다.
    func testEightRunnerRaidExceedsTheOldFighterCap() throws {
        let fighters = (1...8).map { runner("R\($0)") } + [boss()]
        XCTAssertTrue(MultiplayerValidation.validStart(fighters: fighters, mode: .coopBoss))
        XCTAssertNoThrow(try MultiplayerBattle(fighters: fighters, mode: .coopBoss, seed: 1))
        // 다른 모드는 상한이 그대로다 — 협동전 때문에 개인전이 5명이 되면 안 된다.
        XCTAssertThrowsError(try MultiplayerBattle(fighters: fighters, mode: .freeForAll, seed: 1))
    }

    func testRaidRejectsANinthRunner() throws {
        let fighters = (1...9).map { runner("R\($0)") } + [boss()]
        XCTAssertFalse(MultiplayerValidation.validStart(fighters: fighters, mode: .coopBoss))
        XCTAssertThrowsError(try MultiplayerBattle(fighters: fighters, mode: .coopBoss, seed: 1))
    }

    func testRaidStartNeedsExactlyOneBoss() {
        XCTAssertFalse(MultiplayerValidation.validStart(fighters: [runner(), runner()], mode: .coopBoss),
                       "보스가 없으면 협동전이 아니다")
        XCTAssertFalse(MultiplayerValidation.validStart(fighters: [boss(), boss()], mode: .coopBoss),
                       "러너가 없으면 아무도 싸우지 않는다")
    }

    // MARK: 오늘자 보스 검증 — 조작 호스트가 보상을 부풀리는 길

    /// 보상은 각 클라이언트가 **자기 지갑에** 넣는다. 그래서 "이게 오늘의 5★ 가 맞나"를
    /// 받는 쪽이 스스로 계산해 확인하지 않으면, 조작된 호스트가 잉어킹을 5★ 로 광고해
    /// 방 전체에 5★ 보상을 뿌린다.
    func testGuestRejectsABossThatIsNotTodays() {
        let today = "2026-09-02"
        let honest = [runner(), boss(tier: .five, dayKey: today)]
        XCTAssertTrue(RaidBoss.validRaidStart(fighters: honest, tier: .five, dayKey: today))

        var wrongSpecies = boss(tier: .five, dayKey: today)
        wrongSpecies.side.snapshot.speciesID = RaidBoss.speciesID(dayKey: today, tier: .five) == 129 ? 10 : 129
        XCTAssertFalse(RaidBoss.validRaidStart(fighters: [runner(), wrongSpecies],
                                               tier: .five, dayKey: today),
                       "오늘의 종이 아니면 거절한다")

        // 종은 맞는데 **1★ 보스에 5★ 보상**을 붙인 방. HP 가 티어의 절대값과 정확히 같아야 한다.
        let cheapBoss = boss(tier: .one, dayKey: today)
        XCTAssertFalse(RaidBoss.validRaidStart(fighters: [runner(), cheapBoss],
                                               tier: .five, dayKey: today))

        var inflated = boss(tier: .five, dayKey: today)
        inflated.side.hp = 1
        XCTAssertFalse(RaidBoss.validRaidStart(fighters: [runner(), inflated],
                                               tier: .five, dayKey: today))
    }

    /// 러너 쪽은 레벨을 눕힌다 — 안 보면 레벨 100 파티가 5★ 를 3턴에 끝낸다.
    func testRaidStartRequiresRunnersAtThePartyLevel() {
        var overleveled = runner()
        overleveled.side.snapshot.level = 100
        XCTAssertFalse(MultiplayerValidation.validStart(fighters: [overleveled, boss()], mode: .coopBoss))
    }

    // MARK: 기여도 누적

    /// `BattleEvent.damage` 의 주인은 **맞은 쪽**이라 이벤트 스트림으로는 공격자 귀속이 안 된다.
    /// 해상 루프가 직접 세는지 본다 — 이 값이 곧 보상의 기여도 항이다.
    func testDamageDealtIsAttributedToTheAttacker() throws {
        let a = runner("A"), b = runner("B")
        // 보스는 느리게 둬 러너들이 먼저 때리게 한다(순서가 갈리면 마지막 일격에 과대 계상된다).
        var battle = try MultiplayerBattle(fighters: [a, b, boss(tier: .five)], mode: .coopBoss, seed: 7)
        let bossID = RaidBoss.bossID
        _ = try battle.resolveRound([
            MultiplayerAction(attackerID: a.id, targetID: bossID, moveIndex: 0),
            MultiplayerAction(attackerID: b.id, targetID: bossID, moveIndex: 0),
            MultiplayerAction(attackerID: bossID, targetID: a.id, moveIndex: 0)
        ])
        XCTAssertGreaterThan(battle.damageDealt[a.id] ?? 0, 0)
        XCTAssertGreaterThan(battle.damageDealt[b.id] ?? 0, 0)
        XCTAssertNil(battle.damageDealt[bossID], "보스가 러너를 때린 건 기여도가 아니다")

        let bossHP = RaidTier.five.bossHP
        let dealt = (battle.damageDealt[a.id] ?? 0) + (battle.damageDealt[b.id] ?? 0)
        let boss = try XCTUnwrap(battle.fighters.first { $0.id == bossID })
        XCTAssertEqual(bossHP - boss.side.hp, dealt, "누적 합이 실제로 깎인 HP 와 같아야 한다")
    }

    // MARK: 로비

    /// 이슈의 요구 하나 — 1★는 혼자 열어 혼자 시작할 수 있어야 한다.
    func testRaidLobbyStartsWithASingleRunner() throws {
        let host = LobbyParticipant(id: UUID(), trainerName: "호스트", speciesID: 143,
                                    team: .red, isReady: false, isHost: true)
        var lobby = try MultiplayerLobby(host: host, capacity: MultiplayerLobby.raidCapacity, activity: .raid)
        XCTAssertFalse(lobby.canStart, "준비 전에는 못 연다")
        lobby.setReady(true, participantID: host.id)
        XCTAssertTrue(lobby.canStart, "1인 레이드는 혼자서도 시작한다")
        XCTAssertEqual(lobby.mode, .coopBoss)
    }

    func testRaidLobbyAcceptsEightRunnersAndRejectsTheNinth() throws {
        let host = LobbyParticipant(id: UUID(), trainerName: "호스트", speciesID: 143,
                                    team: .red, isReady: true, isHost: true)
        var lobby = try MultiplayerLobby(host: host, capacity: MultiplayerLobby.raidCapacity, activity: .raid)
        for index in 2...8 {
            try lobby.join(LobbyParticipant(id: UUID(), trainerName: "참가자 \(index)", speciesID: 25,
                                            team: .red, isReady: true, isHost: false))
        }
        XCTAssertEqual(lobby.runners.count, 8)
        XCTAssertThrowsError(try lobby.join(LobbyParticipant(id: UUID(), trainerName: "아홉 번째", speciesID: 25,
                                                             team: .red, isReady: true, isHost: false))) { error in
            XCTAssertEqual(error as? LobbyError, .runnersFull)
        }
    }

    /// 형제 활동은 그대로여야 한다 — 레이드 예외가 4인 방까지 1명으로 열지 않는지 본다.
    func testASingleRunnerStillCannotStartAPlainBattleRoom() throws {
        let host = LobbyParticipant(id: UUID(), trainerName: "호스트", speciesID: 143,
                                    team: .solo, isReady: true, isHost: true)
        let lobby = try MultiplayerLobby(host: host, capacity: 4, activity: .battle)
        XCTAssertFalse(lobby.canStart)
    }
}
