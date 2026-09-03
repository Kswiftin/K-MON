import XCTest
@testable import PokeTokenBar

/// 레이드를 **방에 얹는** 층 — 턴 상한, 보스 AI, 방 이름, 탐색 알림 판정, 하루 한 번 지급.
///
/// 소켓 자체는 여기서 못 밟는다(살아 있는 `NWConnection` 이 필요하다). 그래서 방 로직 중
/// **순수하게 떼어낼 수 있는 판정은 전부 떼어내** 여기서 검증한다 —
/// `MultiplayerRoomCenter.creditsRaceFinish` 가 같은 이유로 `nonisolated static` 인 것과 같다.
final class RaidRoomTests: XCTestCase {

    // MARK: 고정 재료

    private func snapshot(level: Int = RaidBoss.partyLevel, def: Int = 100,
                          moves: [MoveSpec]) -> BattleSnapshot {
        var made = BattleSnapshot(speciesID: 143, name: "탱커", trainer: nil, level: level,
                                  nature: nil, isShiny: false, types: [.normal],
                                  base: BattleStats(hp: 100, atk: 100, def: def, spa: 100,
                                                    spd: def, spe: 100))
        made.moves = moves
        return made
    }

    private func move(id: Int, power: Int) -> MoveSpec {
        MoveSpec(id: id, names: ["en": "M\(id)"], type: .normal, power: power,
                 damageClass: .physical, accuracy: nil, pp: 20)
    }

    private func runner(_ name: String, id: UUID = UUID(), def: Int = 100) -> MultiplayerFighter {
        let participant = LobbyParticipant(id: id, trainerName: name, speciesID: 143,
                                           team: .red, isReady: true, isHost: false)
        return MultiplayerFighter(participant: participant,
                                  snapshot: snapshot(def: def, moves: [move(id: 33, power: 80)]))
    }

    private func boss(tier: RaidTier = .one, moves: [MoveSpec]? = nil) -> MultiplayerFighter {
        RaidBoss.bossFighter(tier: tier,
                             snapshot: snapshot(level: tier.bossLevel,
                                                moves: moves ?? [move(id: 33, power: 40)]))
    }

    // MARK: 턴 상한

    /// 상한은 **새 판정 상태를 만들지 않고** 닫는다 — 파티를 전멸 처리하면 기존
    /// `isFinished`/`winners`/보상 경로가 그대로 패배로 닫고, 게스트에게도 기존 브로드캐스트로
    /// 같은 상태가 간다.
    func testTurnCapEndsTheRaidAsALoss() throws {
        let a = runner("A"), b = runner("B")
        var battle = try MultiplayerBattle(fighters: [a, b, boss()], mode: .coopBoss, seed: 1)
        XCTAssertFalse(battle.isFinished)

        battle.endByTurnCap()
        XCTAssertTrue(battle.isFinished)
        XCTAssertEqual(MultiplayerBattle.outcome(for: a.id, fighters: battle.fighters, mode: .coopBoss), .loss)
        XCTAssertEqual(MultiplayerBattle.outcome(for: b.id, fighters: battle.fighters, mode: .coopBoss), .loss)
        XCTAssertTrue(try XCTUnwrap(battle.fighters.first { $0.id == RaidBoss.bossID }).isAlive,
                      "보스는 살아서 이긴다 — 러너만 눕는다")
    }

    /// **트리거 브랜치**: 상한 판정이 모드를 안 보면 일반 4인 방도 20라운드에 강제 종료된다.
    ///
    /// 판정을 `static` 으로 두는 이유는 `isFinished`·`winners` 와 같다 — 게스트는 자기 `battle` 을
    /// 갱신하지 않으므로 인스턴스 프로퍼티로만 두면 게스트 쪽 판정이 개시 시점에 굳는다.
    func testTurnCapAppliesOnlyToRaids() throws {
        XCTAssertFalse(MultiplayerBattle.reachedTurnCap(round: 1, mode: .coopBoss),
                       "1라운드에 상한일 수는 없다")
        XCTAssertFalse(MultiplayerBattle.reachedTurnCap(round: RaidBoss.turnCap, mode: .coopBoss),
                       "상한 라운드 자체는 아직 싸울 수 있다")
        XCTAssertTrue(MultiplayerBattle.reachedTurnCap(round: RaidBoss.turnCap + 1, mode: .coopBoss))

        XCTAssertFalse(MultiplayerBattle.reachedTurnCap(round: RaidBoss.turnCap + 1, mode: .freeForAll),
                       "개인전은 턴 상한이 없다")
        XCTAssertFalse(MultiplayerBattle.reachedTurnCap(round: RaidBoss.turnCap + 1, mode: .teams),
                       "팀전도 턴 상한이 없다")

        // 인스턴스 편의 접근자도 같은 답을 내야 한다 — 갈라지면 호스트와 게스트가 다른 판을 본다.
        let raid = try MultiplayerBattle(fighters: [runner("A"), boss()], mode: .coopBoss, seed: 1)
        XCTAssertEqual(raid.reachedTurnCap,
                       MultiplayerBattle.reachedTurnCap(round: raid.round, mode: raid.mode))
    }

    // MARK: 보스 AI

    /// 보스에겐 클라이언트가 없어 호스트가 대신 낸다. 관장 AI 와 **같은 점수식**
    /// (`BattleModel.expectedDamageScore`)을 쓰는지, 그리고 결정론인지 본다.
    func testBossPicksItsBestMoveAgainstTheSoftestRunner() throws {
        let tough = runner("단단", def: 200)
        let squishy = runner("물렁", def: 20)
        let armed = boss(moves: [move(id: 1, power: 10), move(id: 2, power: 100)])
        let action = try XCTUnwrap(MultiplayerBattle.bossAction(fighters: [tough, squishy, armed]))

        XCTAssertEqual(action.attackerID, RaidBoss.bossID)
        XCTAssertEqual(action.moveIndex, 1, "위력 100 쪽을 고른다")
        XCTAssertEqual(action.targetID, squishy.id, "방어가 낮은 쪽이 기대 피해가 크다")
        // 결정론 — 같은 입력이면 같은 답이다(호스트가 매 턴 부르는 자리라 흔들리면 안 된다).
        XCTAssertEqual(MultiplayerBattle.bossAction(fighters: [tough, squishy, armed]), action)
    }

    func testBossActionIsNilWhenThereIsNothingToDo() {
        var deadBoss = boss()
        deadBoss.side.hp = 0
        XCTAssertNil(MultiplayerBattle.bossAction(fighters: [runner("A"), deadBoss]),
                     "쓰러진 보스는 행동하지 않는다")

        var downed = runner("A")
        downed.side.hp = 0
        XCTAssertNil(MultiplayerBattle.bossAction(fighters: [downed, boss()]),
                     "때릴 러너가 없으면 행동하지 않는다")

        let soloRunner = runner("A")
        XCTAssertNil(MultiplayerBattle.bossAction(fighters: [soloRunner]), "보스가 없는 판")
    }

    // MARK: 방 이름 — 붙기 전에 티어가 보여야 한다

    /// 방 광고에 TXT 가 없어 목록에서 티어를 보여 줄 통로가 이름뿐이다(체육관이 재임 시각을
    /// 이름에 싣는 것과 같은 이유). 티어를 모르면 1★ 인 줄 알고 5★ 에 혼자 들어간다.
    func testRaidRoomNameCarriesTheTier() throws {
        let name = RaidRoomName.make(trainerName: "지우", idTag: "ABC123", tier: .five)
        XCTAssertTrue(RaidRoomName.isRaidRoomName(name))
        let parsed = try XCTUnwrap(RaidRoomName.parse(name))
        XCTAssertEqual(parsed.tier, .five)
        XCTAssertEqual(parsed.idTag, "ABC123")
        XCTAssertEqual(parsed.trainerName, "지우")

        XCTAssertFalse(RaidRoomName.isRaidRoomName("GYM · 지우#ABC123"))
        XCTAssertNil(RaidRoomName.parse("GYM · 1 · v15 · 지우#ABC123"), "남의 방 이름은 파싱하지 않는다")
        XCTAssertNil(RaidRoomName.parse("RAID · 5 · 지우"), "식별자가 없는 이름은 통째로 nil")
        XCTAssertNil(RaidRoomName.parse("RAID · 지우#ABC123"), "티어 자리가 없는 이름은 통째로 nil")
        XCTAssertNil(RaidRoomName.parse("RAID · 9 · 지우#ABC123"), "모르는 티어는 받아들이지 않는다")
    }

    /// 63바이트 예산 — 잘리는 건 트레이너 이름뿐이고 티어·식별자는 살아남아야 한다.
    /// 접미가 잘리면 같은 이름 두 기기가 서로를 자기로 오인한다(`LANServiceName` 의 이유).
    func testRaidRoomNameFitsTheBonjourBudget() throws {
        let long = String(repeating: "가", count: 40)
        let name = RaidRoomName.make(trainerName: long, idTag: "ABC123", tier: .three)
        XCTAssertLessThanOrEqual(name.utf8.count, LANServiceName.maxBytes)
        let parsed = try XCTUnwrap(RaidRoomName.parse(name))
        XCTAssertEqual(parsed.tier, .three)
        XCTAssertEqual(parsed.idTag, "ABC123", "식별자는 절대 잘리지 않는다")
    }

    // MARK: 탐색 알림

    /// 이슈가 "discovery is the real gate" 라고 부른 자리. 알림이 없으면 기본 경험은
    /// **방을 열고 혼자 시간 초과되는 것**이다. 브라우저 결과는 같은 목록을 반복해서 주므로
    /// 한 방에 한 번만 알려야 하고, 내 방은 알리면 안 된다.
    func testOnlyNewForeignRaidRoomsAreAnnounced() {
        let mine = RaidRoomName.make(trainerName: "나", idTag: "MYTAG1", tier: .one)
        let theirs = RaidRoomName.make(trainerName: "이웃", idTag: "OTHER1", tier: .five)
        let gym = "GYM · 1 · v14 · 이웃#OTHER1"

        XCTAssertEqual(MultiplayerRoomCenter.newlyVisibleRaidRooms(
            previous: [], current: [mine, theirs, gym], myIDTag: "MYTAG1"), [theirs],
            "내 방과 체육관 방은 알리지 않는다")

        XCTAssertEqual(MultiplayerRoomCenter.newlyVisibleRaidRooms(
            previous: [theirs], current: [theirs], myIDTag: "MYTAG1"), [],
            "이미 본 방은 다시 알리지 않는다 — 브라우저는 같은 목록을 반복해서 준다")

        let second = RaidRoomName.make(trainerName: "이웃2", idTag: "OTHER2", tier: .three)
        XCTAssertEqual(MultiplayerRoomCenter.newlyVisibleRaidRooms(
            previous: [theirs], current: [theirs, second], myIDTag: "MYTAG1"), [second])
    }

    // MARK: 예약 부화 시각표

    /// 시각표는 **아침에 공개된다** — 무작위인데 공개하지 않으면 마침 접속해 있던 사람만 참여한다.
    /// 그래서 하루치를 미리 계산할 수 있어야 하고, 모든 클라이언트가 같은 답을 내야 한다.
    func testHatchesAreThreeAscendingTimesOnTheGivenDay() throws {
        let calendar = RaidSchedule.calendar
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 12)))
        let hatches = RaidSchedule.hatches(on: noon)

        XCTAssertEqual(hatches.count, 3)
        XCTAssertEqual(hatches, hatches.sorted())
        for hatch in hatches {
            XCTAssertTrue(calendar.isDate(hatch, inSameDayAs: noon), "그날 안에 있어야 한다")
        }
        // 같은 날의 어느 시각으로 물어도 같은 시각표다 — 아침에 공개한 표가 오후에 바뀌면 안 된다.
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 20)))
        XCTAssertEqual(RaidSchedule.hatches(on: evening), hatches)
    }

    /// 부화한 보스는 45분간 산다. 그 창 안이면 5★ 방을 열 수 있고, 밖이면 못 연다.
    func testAHatchIsActiveForItsWindowAndNotBefore() throws {
        let calendar = RaidSchedule.calendar
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 0)))
        let first = try XCTUnwrap(RaidSchedule.hatches(on: day).first)

        XCTAssertNil(RaidSchedule.activeHatch(at: first.addingTimeInterval(-60)), "부화 1분 전엔 없다")
        XCTAssertEqual(RaidSchedule.activeHatch(at: first), first)
        XCTAssertEqual(RaidSchedule.activeHatch(at: first.addingTimeInterval(44 * 60)), first)
        XCTAssertNil(RaidSchedule.activeHatch(at: first.addingTimeInterval(46 * 60)), "45분이 지나면 닫힌다")
    }

    /// 다음 부화는 **내일까지 넘어가서** 찾는다 — 오늘 셋이 다 지난 저녁에 nil 을 내면 화면이
    /// "다음 5★ 없음" 을 그린다.
    func testNextHatchRollsOverIntoTomorrow() throws {
        let calendar = RaidSchedule.calendar
        let lateNight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 23, minute: 30)))
        let next = try XCTUnwrap(RaidSchedule.nextHatch(after: lateNight))
        XCTAssertGreaterThan(next, lateNight)
        XCTAssertTrue(calendar.isDate(next, inSameDayAs: lateNight.addingTimeInterval(24 * 60 * 60)),
                      "오늘 게 다 지났으면 내일 첫 부화다")

        // **대조군**: 오늘 것이 남아 있으면 내일로 넘어가지 않는다. 이 갈래를 안 밟으면
        // "항상 내일 첫 부화" 라는 오구현도 위 단언만으로는 초록이다.
        let dawn = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 1)))
        let today = try XCTUnwrap(RaidSchedule.nextHatch(after: dawn))
        XCTAssertEqual(today, RaidSchedule.hatches(on: dawn).first)
    }

    /// 주말은 창이 뒤로 밀린다 — 2026-09-05 는 토요일이다.
    func testWeekendUsesTheLaterWindows() throws {
        let calendar = RaidSchedule.calendar
        let saturday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 0)))
        XCTAssertEqual(calendar.component(.weekday, from: saturday), 7, "토요일이어야 한다")
        let first = try XCTUnwrap(RaidSchedule.hatches(on: saturday).first)
        let minute = calendar.component(.hour, from: first) * 60 + calendar.component(.minute, from: first)
        XCTAssertTrue(RaidBoss.weekendBlocks[0].contains(minute), "주말 첫 창은 11시 이후다")
    }

    /// 15분 전 알림은 **필수다** — 시각이 무작위라 습관이 대신해 주지 못한다. 예약할 시각은
    /// 지금보다 미래인 것만이어야 한다(과거로 예약하면 알림이 즉시 터지거나 조용히 버려진다).
    func testReminderTimesAreFifteenMinutesAheadAndInTheFuture() throws {
        let calendar = RaidSchedule.calendar
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 7)))
        let reminders = RaidSchedule.upcomingReminders(after: morning)
        let hatches = RaidSchedule.hatches(on: morning)

        XCTAssertEqual(reminders.count, 3, "아침엔 셋 다 남아 있다")
        for (reminder, hatch) in zip(reminders, hatches) {
            XCTAssertEqual(hatch.timeIntervalSince(reminder), TimeInterval(RaidSchedule.reminderLeadMinutes * 60))
            XCTAssertGreaterThan(reminder, morning)
        }

        // 마지막 부화 뒤에는 오늘 몫이 없다 — 내일 것은 내일 아침에 다시 건다.
        let lastHatch = try XCTUnwrap(hatches.last)
        XCTAssertTrue(RaidSchedule.upcomingReminders(after: lastHatch).isEmpty)
    }

    // MARK: 와이어 계약

    /// 새 case 는 왕복해야 한다. 특히 `[UUID: Int]` 는 키가 String 도 Int 도 아니라 JSON 에서
    /// **배열**(k,v,k,v)로 인코딩된다 — 모양이 조용히 깨지면 정산이 통째로 0 이 된다.
    func testRaidWireMessagesRoundTrip() throws {
        let fighters = [runner("A"), boss(tier: .five)]
        let start = MultiplayerWireMessage.raidStart(seed: 42, fighters: fighters, tier: .five)
        XCTAssertEqual(try JSONDecoder().decode(MultiplayerWireMessage.self,
                                                from: JSONEncoder().encode(start)), start)

        let settlement = MultiplayerWireMessage.raidSettlement(contributions: [fighters[0].id: 1_234])
        let decoded = try JSONDecoder().decode(MultiplayerWireMessage.self,
                                               from: JSONEncoder().encode(settlement))
        guard case .raidSettlement(let contributions) = decoded else { return XCTFail("raidSettlement") }
        XCTAssertEqual(contributions[fighters[0].id], 1_234)
    }

    /// 보스는 최대 HP 규칙에서 빠지므로 **HP 가 와이어를 그대로 건너야** 한다 — 깎여서 도착하면
    /// 게스트의 오늘자 검증이 정직한 호스트를 거절한다.
    func testTheBossKeepsItsTierHPAcrossTheWire() throws {
        let dayKey = "2026-09-02"
        var todays = snapshot(level: RaidTier.five.bossLevel, moves: [move(id: 33, power: 40)])
        todays.speciesID = RaidBoss.speciesID(dayKey: dayKey)
        let sent = RaidBoss.bossFighter(tier: .five, snapshot: todays)
        XCTAssertTrue(RaidBoss.validBoss(sent, tier: .five, dayKey: dayKey), "보내는 쪽부터 유효해야 한다")

        let received = try JSONDecoder().decode(MultiplayerFighter.self,
                                                from: JSONEncoder().encode(sent))
        XCTAssertEqual(received.side.hp, RaidTier.five.bossHP)
        XCTAssertTrue(RaidBoss.validBoss(received, tier: .five, dayKey: dayKey),
                      "와이어를 건넌 보스도 그대로 오늘의 보스여야 한다")
    }

    /// **대조군**: 보스 예외가 다른 전투원까지 열어 주면 안 된다. 상류가 이 클램프를 넣은 이유는
    /// 재생 중 `hp + amount` 오버플로이고(#208), 레이드는 그 재생을 쓰는 쪽이다.
    func testTheHPCeilingStillClampsEveryoneElse() throws {
        var inflated = runner("A")
        inflated.side.hp = 99_999
        let received = try JSONDecoder().decode(MultiplayerFighter.self,
                                                from: JSONEncoder().encode(inflated))
        XCTAssertEqual(received.side.hp, received.side.stats.hp, "보스가 아니면 종족값에서 잘린다")

        // 보스도 무한은 아니다 — 천장이 티어 최대치로 바뀔 뿐이다.
        var greedyBoss = boss(tier: .five)
        greedyBoss.side.hp = 99_999
        let cappedBoss = try JSONDecoder().decode(MultiplayerFighter.self,
                                                  from: JSONEncoder().encode(greedyBoss))
        XCTAssertEqual(cappedBoss.side.hp, RaidTier.maxBossHP)
    }

    // MARK: 하루 한 번 지급

    /// #79 와 같은 규칙 — 시도는 무제한, 지급은 하루 한 번. 규칙이 하나여야 배울 게 하나다.
    @MainActor
    func testRaidRewardIsPaidOncePerDay() {
        let clock = TestClock()
        let store = stubStore(clock, tag: "raid-reward")
        let before = store.state.starPieces

        XCTAssertEqual(store.creditRaidReward(500), 500)
        XCTAssertEqual(store.state.starPieces, before + 500)
        XCTAssertTrue(store.raidRewardClaimedToday)

        XCTAssertEqual(store.creditRaidReward(500), 0, "같은 날 두 번째는 0 이다")
        XCTAssertEqual(store.state.starPieces, before + 500, "지갑도 안 늘어난다")

        // 자정 타이머가 아니라 **날짜 키 비교**로 넘긴다(`MissionBoard` 와 같은 방식).
        clock.advance(24 * 60 * 60)
        XCTAssertFalse(store.raidRewardClaimedToday)
        XCTAssertEqual(store.creditRaidReward(500), 500)
        XCTAssertEqual(store.state.starPieces, before + 1_000)
    }

    /// 0 이하는 원장을 소모하지 않는다 — 안 그러면 진 판이 그날의 지급 기회를 태운다.
    @MainActor
    func testALostRaidDoesNotBurnTheDailyPayout() {
        let clock = TestClock()
        let store = stubStore(clock, tag: "raid-loss")
        XCTAssertEqual(store.creditRaidReward(0), 0)
        XCTAssertFalse(store.raidRewardClaimedToday, "진 판은 오늘의 지급을 태우지 않는다")
        XCTAssertEqual(store.creditRaidReward(300), 300)
    }

    // MARK: 게스트 시점 — 호스트와 갈라지는 축

    /// 오늘의 보스 한 마리. 게스트 검증(`validRaidStart`)을 통과하려면 종이 오늘의 종이어야 한다.
    private func todaysBoss(tier: RaidTier = .one) -> MultiplayerFighter {
        var todays = snapshot(level: tier.bossLevel, moves: [move(id: 33, power: 40)])
        todays.speciesID = RaidBoss.speciesID(dayKey: CompanionStore.dayKey(Date()))
        return RaidBoss.bossFighter(tier: tier, snapshot: todays)
    }

    /// **회귀(#1)**: 게스트가 `.roundResolved` 에서 먼저 정산해 기여도 항이 항상 0 이었다.
    ///
    /// 호스트는 `roundResolved` 를 먼저 보내고 그 뒤에 `raidSettlement` 를 보낸다. 같은 연결이라
    /// 게스트는 항상 이 순서로 받는데, 예전엔 첫 메시지에서 빈 기여도로 지급을 끝내고 하루 한 번
    /// 원장을 태워 버려 뒤늦게 온 정확한 정산은 0 을 돌려받았다 — 캐리한 게스트가 기여도 항
    /// 전부를 못 받고, 화면은 항목별 합계를 보여 주면서 "이미 받았습니다" 를 띄웠다.
    ///
    /// 호스트 시점 테스트로는 어떤 입력으로도 못 밟는 경로다(호스트는 두 값을 동시에 안다).
    @MainActor
    func testAGuestWaitsForTheSettlementBeforePayingItself() {
        let store = stubStore(TestClock(), tag: "raid-guest-payout")
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        // **둘이어야 한다.** 기여도 항은 협동 항이라 1인 판에서는 접힌다(`minimumCoopRunners`) —
        // 혼자 두면 이 테스트가 재려는 "기여도가 도착해야 지급한다" 대신 1인 규칙만 재게 된다.
        let mate = runner("동료")
        let boss = todaysBoss()
        XCTAssertTrue(center.applyGuestRaidStart(seed: 1, fighters: [me, mate, boss], tier: .one))

        // 아직 안 끝난 라운드는 정산을 열지 않는다.
        var hurtBoss = boss
        hurtBoss.side.hp = RaidTier.one.bossHP / 2
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, hurtBoss], events: [])
        XCTAssertNil(center.raidSettlement, "판이 안 끝났는데 정산이 열리면 안 된다")

        // 같은 라운드가 한 번 더 와도 무시한다 — 안 거르면 라운드가 두 칸 뛰어 남은 턴이 갈린다.
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, hurtBoss], events: [])

        // 호스트가 마지막 라운드를 먼저 보낸다 — 보스가 쓰러졌지만 기여도는 아직 안 왔다.
        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 2, fighters: [me, mate, downedBoss], events: [])
        XCTAssertNil(center.raidSettlement, "기여도가 오기 전에 정산하면 안 된다")
        XCTAssertNil(center.raidPayout)
        XCTAssertFalse(store.raidRewardClaimedToday, "빈 정산으로 하루치 원장을 태우면 안 된다")

        // 이제 정산이 온다 — 혼자 다 넣었으니 기여도 항은 기본급 전액이다.
        center.applyGuestRaidSettlement([me.id: 400])
        let settlement = center.raidSettlement
        XCTAssertEqual(settlement?.contribution, RaidTier.one.baseReward,
                       "100% 기여인데 0 이면 빈 기여도로 계산한 것이다")
        XCTAssertEqual(center.raidPayout, settlement?.total, "정산표와 실제 지급액이 같아야 한다")
        XCTAssertEqual(store.state.starPieces, settlement?.total)
    }

    /// **트리거 브랜치(#1)**: 순서가 뒤집혀 도착해도 지급은 한 번, 그리고 반드시 일어나야 한다.
    /// 게스트 지급을 `.raidSettlement` 로만 옮기면 "정산이 라운드보다 먼저 오면 영영 안 준다" 가
    /// 새 실패 모양이 된다 — 기여도 도착과 판 종료를 **둘 다** 조건으로 두어야 양쪽이 닫힌다.
    @MainActor
    func testTheSettlementPaysOnceRegardlessOfArrivalOrder() {
        let store = stubStore(TestClock(), tag: "raid-guest-order")
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let boss = todaysBoss()
        XCTAssertTrue(center.applyGuestRaidStart(seed: 1, fighters: [me, boss], tier: .one))

        center.applyGuestRaidSettlement([me.id: 400])
        XCTAssertNil(center.raidPayout, "판이 아직 안 끝났다 — 기여도만으로 지급하면 안 된다")

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, downedBoss], events: [])
        let paid = center.raidPayout
        XCTAssertEqual(paid, center.raidSettlement?.total)

        // 같은 정산이 한 번 더 와도 두 번 지급하지 않는다.
        center.applyGuestRaidSettlement([me.id: 400])
        XCTAssertEqual(center.raidPayout, paid)
        XCTAssertEqual(store.state.starPieces, paid)
    }

    /// 무임승차 — 한 대도 못 때린 러너도 기본급·남은 턴·생존 항은 받는다. 기여도 항만 0 이다.
    /// **기여도 항이 이 식의 존재 이유**라, 캐리와 무임승차가 같은 값을 받으면 협동이 뜻을 잃는다.
    @MainActor
    func testAFreeriderGetsTheBaseButNoContributionShare() {
        let store = stubStore(TestClock(), tag: "raid-freerider")
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let carry = runner("캐리")
        let boss = todaysBoss(tier: .three)
        XCTAssertTrue(center.applyGuestRaidStart(seed: 1, fighters: [me, carry, boss], tier: .three))

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, carry, downedBoss], events: [])
        // 내 이름이 기여도에 아예 없다 — 한 대도 못 때렸다.
        center.applyGuestRaidSettlement([carry.id: 1_600])

        let settlement = center.raidSettlement
        XCTAssertEqual(settlement?.contribution, 0, "기여가 0 이면 기여도 항도 0 이다")
        XCTAssertEqual(settlement?.base, RaidTier.three.baseReward, "그래도 기본급은 받는다")
        XCTAssertEqual(center.raidPayout, settlement?.total)
    }

    /// **1인 판은 기본급만 나간다.** 순수 정산에서 한 번 재지만(`RaidTests`) 방 층이 러너 수를
    /// 실제로 세어 넘기는지는 여기서만 드러난다 — 로비 값으로 세면 게스트에겐 그 값이 없어
    /// 조용히 0 이 되고, 그러면 협동 판까지 기본급만 받는다.
    @MainActor
    func testASoloRaidPaysTheBaseOnly() {
        let store = stubStore(TestClock(), tag: "raid-solo-base")
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let boss = todaysBoss()
        XCTAssertTrue(center.applyGuestRaidStart(seed: 1, fighters: [me, boss], tier: .one))

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 400])

        let settlement = center.raidSettlement
        XCTAssertEqual(settlement?.base, RaidTier.one.baseReward, "혼자여도 기본급은 받는다")
        XCTAssertEqual(settlement?.contribution, 0)
        XCTAssertEqual(settlement?.turnBonus, 0, "혼자 19턴 남기고 끝내도 협동 항은 안 붙는다")
        XCTAssertEqual(settlement?.survivorBonus, 0)
        XCTAssertEqual(center.raidPayout, RaidTier.one.baseReward)
        XCTAssertEqual(store.state.starPieces, RaidTier.one.baseReward)
    }

    /// 협동전이 아닌 방에 정산 메시지가 오면 무시한다 — 호스트가 보내는 값이라 받는 쪽이 본다.
    @MainActor
    func testARaidSettlementIsIgnoredOutsideACoopRaid() {
        let store = stubStore(TestClock(), tag: "raid-settlement-stray")
        let center = MultiplayerRoomCenter(companion: store)
        center.applyGuestRaidSettlement([center.myID: 9_999])
        XCTAssertNil(center.raidSettlement)
        XCTAssertNil(center.raidPayout)
        XCTAssertTrue(center.raidContributions.isEmpty, "레이드가 아닌 방의 기여도를 받아 두지 않는다")
    }

    /// **회귀(#7)**: 남은 턴 보너스가 호스트와 게스트에서 한 턴 갈렸다. 게스트는 라운드를 올린
    /// **뒤에** `combatRound` 로 종료 라운드를 채워, 같은 판인데 정산표 숫자가 서로 달랐다.
    @MainActor
    func testTurnBonusCountsTheResolvedRoundNotTheNextOne() {
        let store = stubStore(TestClock(), tag: "raid-guest-turns")
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let mate = runner("동료")   // 남은 턴도 협동 항이라 1인 판에서는 0 이다
        let boss = todaysBoss()
        XCTAssertTrue(center.applyGuestRaidStart(seed: 1, fighters: [me, mate, boss], tier: .one))

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 400])

        // 1라운드에 끝냈으면 남은 턴은 19 다. 18 이면 게스트가 한 라운드 늦게 센 것이다.
        XCTAssertEqual(center.raidSettlement?.turnBonus,
                       RaidBoss.turnBonusPerTurn * (RaidBoss.turnCap - 1))
    }

    /// **회귀(#11)**: 교전 중에 뜬 방을 "알린 방" 으로 적어 두어, 판이 끝나 `.idle` 로 돌아온
    /// 뒤에도 영영 다시 못 알렸다 — 45분짜리 5★ 창을 통째로 놓치는 자리다.
    @MainActor
    func testARoomSeenDuringCombatIsStillAnnouncedAfterwards() {
        let store = stubStore(TestClock(), tag: "raid-announce")
        let center = MultiplayerRoomCenter(companion: store)
        let theirs = RaidRoomName.make(trainerName: "이웃", idTag: "OTHER1", tier: .five)

        // 내 판이 도는 중에 이웃이 방을 연다.
        XCTAssertTrue(center.applyGuestRaidStart(seed: 1, fighters: [runner("나", id: center.myID),
                                                                     todaysBoss()], tier: .one))
        center.announceNewRaidRooms([theirs])
        XCTAssertTrue(center.announcedRaidRooms.isEmpty, "알리지 못한 방을 알린 것으로 적으면 안 된다")

        // 판이 끝나 목록으로 돌아오면 그 방은 여전히 **처음 보는 방**이다.
        center.leaveRoom()
        center.announceNewRaidRooms([theirs])
        XCTAssertEqual(center.announcedRaidRooms, [theirs])

        // 그리고 두 번 알리지는 않는다 — 브라우저는 같은 목록을 반복해서 준다.
        center.announceNewRaidRooms([theirs])
        XCTAssertEqual(center.announcedRaidRooms, [theirs])
    }

    /// 사라진 방은 목록에서 빠져야 한다 — 안 빼면 껐다 켠 같은 방을 영영 다시 못 알린다.
    @MainActor
    func testAVanishedRoomLeavesTheAnnouncedList() {
        let store = stubStore(TestClock(), tag: "raid-announce-gone")
        let center = MultiplayerRoomCenter(companion: store)
        let theirs = RaidRoomName.make(trainerName: "이웃", idTag: "OTHER1", tier: .one)
        center.announceNewRaidRooms([theirs])
        XCTAssertEqual(center.announcedRaidRooms, [theirs])

        center.announceNewRaidRooms([])
        XCTAssertTrue(center.announcedRaidRooms.isEmpty)
        center.announceNewRaidRooms([theirs])
        XCTAssertEqual(center.announcedRaidRooms, [theirs], "다시 뜬 방은 다시 알린다")
    }

    /// **회귀(#10)**: 5★ 를 부화 창 안으로 가두는 검사가 티어 피커의 **렌더 시점** 계산 한 곳뿐이라,
    /// 화면을 열어 둔 채 45분 창이 지나면 버튼이 그대로 남아 창 밖에서 5★ 방이 열렸다.
    @MainActor
    func testFiveStarRoomsOnlyOpenInsideAHatchWindow() throws {
        let store = stubStore(TestClock(), tag: "raid-hatch-gate")
        let center = MultiplayerRoomCenter(companion: store)
        let calendar = RaidSchedule.calendar
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 0)))
        let hatch = try XCTUnwrap(RaidSchedule.hatches(on: day).first)

        center.createRaidRoom(tier: .five, now: hatch.addingTimeInterval(TimeInterval(
            (RaidBoss.activeMinutes + 1) * 60)))
        XCTAssertNil(center.raidTier, "창 밖에서는 티어조차 잡히지 않는다")
        XCTAssertEqual(center.lastError, store.l.raidHatchClosed)

        // **대조군**: 창 안이면 열린다. 이걸 안 밟으면 "5★ 를 언제나 막는다" 도 초록이다.
        center.createRaidRoom(tier: .five, now: hatch)
        XCTAssertEqual(center.raidTier, .five)

        // 1★·3★ 는 창과 무관하다 — 아무 때나 여는 방이 존재하는 이유다.
        center.leaveRoom()
        center.createRaidRoom(tier: .one, now: hatch.addingTimeInterval(TimeInterval(
            (RaidBoss.activeMinutes + 1) * 60)))
        XCTAssertEqual(center.raidTier, .one)
    }

    /// **회귀(#12)**: 예약 알림 제거 개수를 평일 블록 수 하나에서만 뽑아, 주말 블록이 하나라도
    /// 많아지면 지워지지 않는 알림이 남는다(껐는데도 어제 예약이 살아 터진다).
    func testHatchReminderIdentifiersCoverBothWeekdayAndWeekend() {
        XCTAssertGreaterThanOrEqual(RaidBoss.hatchBlocksPerDay, RaidBoss.weekdayBlocks.count)
        XCTAssertGreaterThanOrEqual(RaidBoss.hatchBlocksPerDay, RaidBoss.weekendBlocks.count)
    }

    /// **회귀(#8)**: 패배 문구가 무조건 "턴이 다 됐습니다" 라, 3턴 만에 전멸한 판도 턴 초과라고
    /// 말했다 — 필요한 건 화력이 아니라 티어를 낮추거나 사람을 모으는 것인데 반대로 배우게 된다.
    func testATurnCapLossIsToldApartFromAWipe() {
        XCTAssertFalse(RaidBoss.endedByTurnCap(round: 4), "17턴 남기고 전멸한 판은 턴 초과가 아니다")
        XCTAssertFalse(RaidBoss.endedByTurnCap(round: RaidBoss.turnCap), "상한 라운드 자체는 아직 싸운다")
        XCTAssertTrue(RaidBoss.endedByTurnCap(round: RaidBoss.turnCap + 1))
    }

    /// **회귀(#6)**: 1인 레이드 승리가 배틀 업적을 올려, 바로 그 줄이 지키려던 "혼자 무한 반복
    /// 금지" 불변식이 깨졌다. 1★ 는 러너 한 명으로 시작되고 상대는 NPC 보스이며 시도·승리가
    /// 무제한이라, 세면 이웃 없이 사다리를 끝까지 올릴 수 있다.
    @MainActor
    func testASoloRaidWinDoesNotCountTowardTheBattleAchievement() async {
        // 업적 카운터는 사다리 안에 있다 — 넘은 단계의 보상이 지갑으로 나오므로 지갑으로 잰다
        // (`WaveRunAchievementTests` 와 같은 방식). 첫 칸이 1승이라 한 판이면 바로 드러난다.
        // 파트너가 있어야 전적이 남는다(`grantBattleReward` 의 첫 가드).
        func hatched(_ tag: String) async -> CompanionStore {
            let store = stubStore(TestClock(), tag: tag)
            await store.hatch(baseID: 20)
            return store
        }

        let solo = await hatched("raid-achievement-solo")
        let before = solo.state.starPieces
        solo.grantBattleReward(won: true, participantCount: 1, mode: .coopBoss, opponentNames: ["보스"])
        XCTAssertEqual(solo.state.starPieces, before, "혼자 잡은 레이드는 세지 않는다")
        XCTAssertEqual(solo.state.battleHistory.count, 1, "전적은 남는다 — 업적만 안 센다")

        // **대조군**: 사람이 둘 이상인 협동전은 그대로 센다 — 안 밟으면 "레이드는 전부 안 센다"
        // 도, "배틀 업적이 통째로 죽었다" 도 초록이다.
        let party = await hatched("raid-achievement-party")
        party.grantBattleReward(won: true, participantCount: 2, mode: .coopBoss, opponentNames: ["보스"])
        XCTAssertGreaterThan(party.state.starPieces, before)

        // 1인 **일반 배틀**도 그대로다 — 이 예외는 협동전 한 곳에만 걸려 있어야 한다.
        let duel = await hatched("raid-achievement-duel")
        duel.grantBattleReward(won: true, participantCount: 1, mode: .freeForAll, opponentNames: ["상대"])
        XCTAssertGreaterThan(duel.state.starPieces, before)
    }

    // MARK: 전적 표기

    /// 협동전이 `3P` 로 나오면 4인 개인전과 구별되지 않는다 — 전적 목록에서 두 줄이 같아 보인다.
    func testRecentBattleLabelDistinguishesRaids() {
        XCTAssertEqual(BattleView.RecentBattleLabel.text(mode: .coopBoss, participantCount: 3), "RAID 3P")
        XCTAssertEqual(BattleView.RecentBattleLabel.text(mode: .freeForAll, participantCount: 3), "3P")
        XCTAssertEqual(BattleView.RecentBattleLabel.text(mode: .teams, participantCount: 4), "2 vs 2")
    }

    // MARK: 서명 — 지우면 다시 받는 필드다

    /// 이 날짜가 하루 한 번의 **유일한** 멱등 가드라 서명 밖에 두면 지우는 것만으로 무한 재수령이다
    /// (defect-log: 1회성 보상의 멱등 가드가 서명 밖에 있는 부류).
    func testDeletingTheRaidRewardDateAfterSigningIsDetected() {
        var state = CompanionState()
        state.raidRewardDate = "2026-09-02"
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed))

        signed.raidRewardDate = ""
        XCTAssertTrue(SaveTransfer.isTampered(signed), "지우는 방향이 곧 재수령 방향이다")
    }

    /// 조건부 append 여야 한다 — 무조건 붙이면 이 필드가 없던 정상 세이브가 전부 조작 판정된다.
    func testDefaultStateGainsNoRaidCanonicalSegment() {
        XCTAssertFalse(SaveTransfer.canonicalString(CompanionState()).contains("|rd"))
    }

    /// 세이브 이전에서 이 필드는 **계정 원장**이다(일일 사탕 원장과 같은 부류). 더 최근 날짜를
    /// 남기지 않으면 맥 A 에서 받고 내보내 맥 B 로 불러오는 것만으로 같은 날 두 번 받는다.
    ///
    /// 분류 목록(`testEveryCompanionStateFieldIsClassifiedForTransfer`)에 적는 것만으로는 부족하다 —
    /// 그 목록은 산문이고, 실제 병합이 없어도 초록이다.
    func testRebaseKeepsTheNewerRaidRewardDate() {
        var imported = CompanionState()
        imported.raidRewardDate = "2026-08-01"
        var current = CompanionState()
        current.raidRewardDate = "2026-09-02"
        XCTAssertEqual(SaveTransfer.rebasedForThisDevice(imported, current: current).raidRewardDate,
                       "2026-09-02", "이 기기가 오늘 이미 받았으면 받은 것이다")

        // 반대 방향도 같은 규칙이다 — 옮겨온 쪽이 더 최근이면 그쪽을 남긴다.
        imported.raidRewardDate = "2026-09-02"
        current.raidRewardDate = "2026-08-01"
        XCTAssertEqual(SaveTransfer.rebasedForThisDevice(imported, current: current).raidRewardDate,
                       "2026-09-02")
    }

    /// 1인 레이드 전적이 불러오기에서 사라지면 안 된다 — 정규화 하한이 2 였을 때 그랬다
    /// (보스는 사람이 아니라 참가자 수에 들지 않는다).
    func testASoloRaidRecordSurvivesNormalization() {
        var state = CompanionState()
        state.battleHistory = [BattleRecord(playedAt: Date(timeIntervalSince1970: 0), mode: .coopBoss,
                                            participantCount: 1, won: true, reward: 0,
                                            opponentNames: [])]
        XCTAssertEqual(SaveTransfer.sanitized(state).battleHistory.count, 1)
    }
}
