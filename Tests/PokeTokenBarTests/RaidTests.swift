import XCTest
@testable import PokeTokenBar

/// LAN 협동 레이드(#80)의 순수 코어 — 오늘의 보스·해치 시각·정산·협동 보스전 판정.
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
        snapshot.speciesID = RaidBoss.speciesID(dayKey: dayKey)
        snapshot.moves = [tackle(power: 40)]
        return RaidBoss.bossFighter(tier: tier, snapshot: snapshot)
    }

    // MARK: 오늘의 보스 — 날짜 결정론

    /// 같은 날은 모두에게 같은 보스다. 이게 깨지면 게스트의 오늘자 검증이 정상 호스트를 거절한다.
    func testTodaysBossIsDeterministicPerDayKey() {
        XCTAssertEqual(RaidBoss.speciesID(dayKey: "2026-09-02"), RaidBoss.speciesID(dayKey: "2026-09-02"))
        XCTAssertTrue(RaidBoss.speciesPool.contains(RaidBoss.speciesID(dayKey: "2026-09-02")))
    }

    /// 날짜가 바뀌면 로테이션이 돈다. 한 해를 돌려 **풀의 절반 이상**이 실제로 나오는지 본다 —
    /// 상수를 돌려주는 오구현은 위 테스트만으로는 초록이다.
    func testBossRotatesAcrossTheYear() {
        var seen = Set<Int>()
        for month in 1...12 {
            for day in 1...28 { seen.insert(RaidBoss.speciesID(dayKey: String(format: "2026-%02d-%02d", month, day))) }
        }
        XCTAssertGreaterThan(seen.count, RaidBoss.speciesPool.count / 2,
                             "1년치 날짜가 풀의 절반도 못 밟으면 로테이션이 아니다")
    }

    /// 자리를 바꾼 날짜 키가 같은 보스를 내면 안 된다 — 자릿수를 안 보는 합산 해시의 전형적 붕괴다.
    func testDayKeyHashIsPositionSensitive() {
        XCTAssertNotEqual(RaidBoss.speciesID(dayKey: "2026-09-02"),
                          RaidBoss.speciesID(dayKey: "2026-09-20"))
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
    }

    /// 화면이 그리는 권장 인원이 위 산수와 **같은 표**에서 나와야 한다 — 따로 적으면 갈라진다.
    func testRecommendedRunnersMatchesTheHPTable() {
        XCTAssertEqual(RaidTier.one.recommendedRunners, 1)
        XCTAssertEqual(RaidTier.three.recommendedRunners, 2)
        XCTAssertEqual(RaidTier.five.recommendedRunners, 3)
    }

    /// 보스 레벨은 티어를 따라 오른다 — HP 가 절대값이라 **화력을 정하는 유일한 손잡이**다.
    func testBossLevelRisesWithTier() {
        XCTAssertLessThan(RaidTier.one.bossLevel, RaidTier.three.bossLevel)
        XCTAssertLessThan(RaidTier.three.bossLevel, RaidTier.five.bossLevel)
        XCTAssertLessThanOrEqual(RaidTier.five.bossLevel, RaidBoss.partyLevel,
                                 "보스가 파티보다 높은 레벨이면 화력이 HP 표와 무관하게 튄다")
    }

    // MARK: 해치 시각 — 아침에 공개되는 무작위

    func testThreeHatchesOnePerBlock() {
        let minutes = RaidBoss.hatchMinutes(dayKey: "2026-09-02", isWeekend: false)
        XCTAssertEqual(minutes.count, RaidBoss.weekdayBlocks.count)
        for (minute, block) in zip(minutes, RaidBoss.weekdayBlocks) {
            XCTAssertTrue(block.contains(minute), "\(minute) 분이 블록 \(block) 밖이다")
        }
        XCTAssertEqual(minutes, minutes.sorted(), "블록이 겹치지 않으므로 결과도 오름차순이다")
    }

    func testHatchTimesAreDeterministicPerDay() {
        XCTAssertEqual(RaidBoss.hatchMinutes(dayKey: "2026-09-02", isWeekend: false),
                       RaidBoss.hatchMinutes(dayKey: "2026-09-02", isWeekend: false))
        XCTAssertNotEqual(RaidBoss.hatchMinutes(dayKey: "2026-09-02", isWeekend: false),
                          RaidBoss.hatchMinutes(dayKey: "2026-09-03", isWeekend: false))
    }

    /// 주말은 사무실 시나리오가 아니다 — 창이 통째로 뒤로 밀린다.
    func testWeekendWindowsShiftLater() {
        let weekday = RaidBoss.hatchMinutes(dayKey: "2026-09-05", isWeekend: false)
        let weekend = RaidBoss.hatchMinutes(dayKey: "2026-09-05", isWeekend: true)
        XCTAssertGreaterThan(weekend[0], weekday[0])
        XCTAssertGreaterThan(weekend[2], weekday[2])
    }

    /// **마지막 블록은 창을 넘지 않는다.** 45분 활성이 창 밖에서 끝나면 "오늘 마지막"이 아무도
    /// 없는 시간대에 열린다 — 이슈의 열린 질문을 캡으로 닫은 자리다.
    func testTheLastHatchFinishesInsideItsWindow() {
        for offset in 0...365 {
            let key = String(format: "2026-01-%02d", (offset % 28) + 1)
            for weekend in [false, true] {
                let last = RaidBoss.hatchMinutes(dayKey: key, isWeekend: weekend)[2]
                let blocks = weekend ? RaidBoss.weekendBlocks : RaidBoss.weekdayBlocks
                XCTAssertLessThanOrEqual(last + RaidBoss.activeMinutes,
                                         blocks[2].upperBound + RaidBoss.activeMinutes)
                XCTAssertLessThanOrEqual(last + RaidBoss.activeMinutes, 22 * 60,
                                         "마지막 해치가 22시를 넘겨 끝난다")
            }
        }
    }

    // MARK: 정산 — 기여도가 무임승차를 가른다

    /// 기여도 항이 없으면 캐리와 무임승차의 보상이 같다. 그 항이 실제로 갈라놓는지 본다.
    func testContributionSeparatesTheCarrierFromTheFreeloader() {
        let carry = RaidBoss.settlement(tier: .five, myDamage: 2_400, totalDamage: 2_800,
                                        turnsRemaining: 5, survivingRunners: 3)
        let coast = RaidBoss.settlement(tier: .five, myDamage: 400, totalDamage: 2_800,
                                        turnsRemaining: 5, survivingRunners: 3)
        XCTAssertGreaterThan(carry.contribution, coast.contribution)
        XCTAssertGreaterThan(carry.total, coast.total)
        XCTAssertEqual(carry.base, coast.base, "기본급은 잡은 사실에 대한 것이라 같다")
    }

    /// 정산은 자기가 늘린 지갑을 **전부 설명해야 한다**(defect-log: 한 지갑에 여러 경로).
    func testSettlementTotalExplainsEveryTerm() {
        let s = RaidBoss.settlement(tier: .three, myDamage: 800, totalDamage: 1_600,
                                    turnsRemaining: 4, survivingRunners: 2)
        XCTAssertEqual(s.total, s.base + s.contribution + s.turnBonus + s.survivorBonus)
        XCTAssertEqual(s.contribution, RaidTier.three.baseReward / 2, "절반을 넣었으면 기여 항도 절반")
    }

    /// 경계 — 아무도 피해를 안 넣은 판(턴 상한 패배 뒤 잘못 불린 경우)에서 0 나눗셈이 나면 안 된다.
    func testSettlementSurvivesZeroTotalDamage() {
        let s = RaidBoss.settlement(tier: .one, myDamage: 0, totalDamage: 0,
                                    turnsRemaining: 0, survivingRunners: 0)
        XCTAssertEqual(s.contribution, 0)
        XCTAssertEqual(s.total, RaidTier.one.baseReward)
    }

    /// 음수·초과분은 경계에서 자른다 — 호스트가 보내오는 값이 정산에 그대로 들어가는 자리다.
    func testSettlementClampsHostSuppliedNumbers() {
        let s = RaidBoss.settlement(tier: .one, myDamage: 9_999, totalDamage: 100,
                                    turnsRemaining: -5, survivingRunners: -3)
        XCTAssertEqual(s.contribution, RaidTier.one.baseReward, "기여 비율은 1 을 못 넘는다")
        XCTAssertEqual(s.turnBonus, 0)
        XCTAssertEqual(s.survivorBonus, 0)
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

    /// 4인 파티 + 보스 = 5명. 기존 `(2...4)` 정원 가드에 그대로 걸리는 자리다.
    func testFullPartyRaidExceedsTheOldFighterCap() throws {
        let fighters = [runner("A"), runner("B"), runner("C"), runner("D"), boss()]
        XCTAssertTrue(MultiplayerValidation.validStart(fighters: fighters, mode: .coopBoss))
        XCTAssertNoThrow(try MultiplayerBattle(fighters: fighters, mode: .coopBoss, seed: 1))
        // 다른 모드는 상한이 그대로다 — 협동전 때문에 개인전이 5명이 되면 안 된다.
        XCTAssertThrowsError(try MultiplayerBattle(fighters: fighters, mode: .freeForAll, seed: 1))
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
        wrongSpecies.side.snapshot.speciesID = RaidBoss.speciesID(dayKey: today) == 129 ? 10 : 129
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
        var lobby = try MultiplayerLobby(host: host, capacity: 4, activity: .raid)
        XCTAssertFalse(lobby.canStart, "준비 전에는 못 연다")
        lobby.setReady(true, participantID: host.id)
        XCTAssertTrue(lobby.canStart, "1인 레이드는 혼자서도 시작한다")
        XCTAssertEqual(lobby.mode, .coopBoss)
    }

    /// 형제 활동은 그대로여야 한다 — 레이드 예외가 4인 방까지 1명으로 열지 않는지 본다.
    func testASingleRunnerStillCannotStartAPlainBattleRoom() throws {
        let host = LobbyParticipant(id: UUID(), trainerName: "호스트", speciesID: 143,
                                    team: .solo, isReady: true, isHost: true)
        let lobby = try MultiplayerLobby(host: host, capacity: 4, activity: .battle)
        XCTAssertFalse(lobby.canStart)
    }
}
