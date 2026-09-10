import XCTest
@testable import PokeTokenBar

/// 레이드를 **방에 얹는** 층 — 턴 상한, 보스 AI, 방 이름, 탐색 알림 판정, 하루 한 번 지급.
///
/// 소켓 자체는 여기서 못 밟는다(살아 있는 `NWConnection` 이 필요하다). 그래서 방 로직 중
/// **순수하게 떼어낼 수 있는 판정은 전부 떼어내** 여기서 검증한다 —
/// `MultiplayerRoomCenter.creditsRaceFinish` 가 같은 이유로 `nonisolated static` 인 것과 같다.
final class RaidRoomTests: XCTestCase {

    /// 8인으로 늘린 로비와 실제 소켓 상한이 같은 정원을 가리켜야 한다. 관전자 연결도 별도다.
    func testRaidGuestConnectionLimitMatchesEightRunnersAndSpectators() {
        XCTAssertEqual(MultiplayerRoomCenter.maxGuestConnections(activity: .raid),
                       MultiplayerLobby.raidCapacity - 1 + MultiplayerLobby.spectatorCapacity)
        XCTAssertEqual(MultiplayerLobby.raidCapacity, 8)
    }

    /// 한 판 뒤 나간 UUID가 명단에서 제거되면 같은 사용자가 같은 방에 다시 참가할 수 있다.
    func testDepartedRaidRunnerCanRejoinWithTheSameID() throws {
        let host = LobbyParticipant(id: UUID(), trainerName: "호스트", speciesID: 143,
                                    team: .red, isReady: true, isHost: true)
        let returningID = UUID()
        let guest = LobbyParticipant(id: returningID, trainerName: "재참가", speciesID: 25,
                                     team: .red, isReady: true, isHost: false)
        var lobby = try MultiplayerLobby(host: host, capacity: MultiplayerLobby.raidCapacity,
                                         activity: .raid)

        try lobby.join(guest)
        try lobby.leave(participantID: returningID)
        XCTAssertNoThrow(try lobby.join(guest))
        XCTAssertEqual(lobby.participants.filter { $0.id == returningID }.count, 1)
    }

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

    // MARK: 보스 교체(정오·자정) 알림 시각

    /// 항상 정확히 둘을 낸다 — 자정 직전이어도 다음 자정과 그다음 정오가 잡혀 알림 개수가
    /// 흔들리지 않는다(예약 부화 창을 없애며 "하루 셋" 대신 "하루 둘"이 됐다).
    func testUpcomingBossRotationsAlwaysReturnsTwoAscendingTimes() throws {
        let calendar = Calendar(identifier: .gregorian)
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 9)))
        let rotations = MultiplayerRoomCenter.upcomingBossRotations(after: morning, calendar: calendar)

        XCTAssertEqual(rotations.count, 2)
        XCTAssertEqual(rotations, rotations.sorted())
        for rotation in rotations { XCTAssertGreaterThan(rotation, morning) }
    }

    /// 아침에 물으면 [오늘 정오, 내일 자정]이다 — 오늘 자정은 이미 지났으니 후보에서 빠진다.
    func testMorningSeesTodaysNoonThenTomorrowsMidnight() throws {
        let calendar = Calendar(identifier: .gregorian)
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 9)))
        let rotations = MultiplayerRoomCenter.upcomingBossRotations(after: morning, calendar: calendar)

        let todayNoon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 12)))
        let tomorrowMidnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 0)))
        XCTAssertEqual(rotations, [todayNoon, tomorrowMidnight])
    }

    /// 자정 직전에 물으면 오늘 몫은 이미 다 지났으니 [내일 자정, 내일 정오]로 넘어간다 —
    /// nil을 내면 화면이 밤새 "다음 교체 없음"을 그린다.
    func testLateNightRollsOverIntoTomorrow() throws {
        let calendar = Calendar(identifier: .gregorian)
        let lateNight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 23, minute: 30)))
        let rotations = MultiplayerRoomCenter.upcomingBossRotations(after: lateNight, calendar: calendar)

        let tomorrowMidnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 0)))
        let tomorrowNoon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)))
        XCTAssertEqual(rotations, [tomorrowMidnight, tomorrowNoon])
    }

    // MARK: 와이어 계약

    /// 새 case 는 왕복해야 한다. 특히 `[UUID: Int]` 는 키가 String 도 Int 도 아니라 JSON 에서
    /// **배열**(k,v,k,v)로 인코딩된다 — 모양이 조용히 깨지면 정산이 통째로 0 이 된다.
    func testRaidWireMessagesRoundTrip() throws {
        let fighters = [runner("A"), boss(tier: .five)]
        let start = MultiplayerWireMessage.raidStart(seed: 42, fighters: fighters, tier: .five,
                                                     periodKey: RaidBoss.periodKey(Date()))
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
        todays.speciesID = RaidBoss.speciesID(dayKey: dayKey, tier: .five)
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

    @MainActor
    func testRaidRewardReopensAtNoon() {
        let calendar = Calendar.current
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7,
                                                          hour: 11, minute: 59))!
        let clock = TestClock(morning)
        let store = stubStore(clock, tag: "raid-half-day-reward")

        XCTAssertEqual(store.creditRaidReward(500), 500)
        XCTAssertEqual(store.creditRaidReward(500), 0)
        clock.advance(60)
        XCTAssertFalse(store.raidRewardClaimedToday)
        XCTAssertEqual(store.creditRaidReward(500), 500)
    }

    /// **회귀(2026-09-08)**: `SaveTransfer.maxKeyLength` 가 10 이던 동안, 재시작마다
    /// `sanitized()` 의 `clampedKey` 가 `RaidBoss.periodKey` 형식("yyyy-MM-dd-am/pm", 13자)의
    /// "-am"/"-pm" 접미사를 10자로 잘랐다. JSON 파일에는 원본이 그대로 있지만 로드된 값만
    /// 매번 잘려 `raidRewardClaimedToday` 가 항상 false 로 보였다 — 앱을 껐다 켤 때마다 하루
    /// 한 번 지급이 무한 재지급됐다. 위 테스트들은 전부 같은 인스턴스 안에서 시계만 돌려 이
    /// 재로드 경로(`load()` → `sanitized()`)를 아무도 밟지 않았다. 같은 파일 URL·같은 고정
    /// 시각으로 두 번째 `CompanionStore` 를 만들어 "재시작"을 흉내 낸다.
    @MainActor
    func testRaidRewardSurvivesRestart() {
        let url = storeStateURL("raid-restart")
        let fixedNow = Date(timeIntervalSince1970: 1_755_000_000)
        let first = CompanionStore(provider: StubProvider(value: stubMaxLevelLine),
                                   clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(first.creditRaidReward(500), 500)
        XCTAssertTrue(first.raidRewardClaimedToday, "지급 직후에는 당연히 참이다")

        // "재시작" — 같은 파일을 새 인스턴스가 다시 읽는다. 시각은 고정해 오전/오후 경계를
        // 지나지 않았다는 것을 보장한다(경계를 지나면 재지급이 의도된 동작이다).
        let second = CompanionStore(provider: StubProvider(value: stubMaxLevelLine),
                                    clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(second.state.starPieces, 500, "지급된 재화 자체는 재시작으로 사라지지 않는다")
        XCTAssertTrue(second.raidRewardClaimedToday,
                      "재시작 후에도 오늘 이미 받았다는 사실이 유지돼야 한다 — 안 그러면 앱을 껐다 켤 때마다 재지급된다")
        XCTAssertEqual(second.creditRaidReward(500), 0, "재시작 후 재도전해도 이미 받은 날은 0이어야 한다")
    }

    /// 포획도 같은 부류다 — 지급과 별도 원장이지만 재시작 지속성 요건은 같다.
    @MainActor
    func testRaidCatchSurvivesRestart() {
        let url = storeStateURL("raid-catch-restart")
        let fixedNow = Date(timeIntervalSince1970: 1_755_000_000)
        let first = CompanionStore(provider: StubProvider(value: stubMaxLevelLine),
                                   clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertTrue(first.claimRaidCatch())

        let second = CompanionStore(provider: StubProvider(value: stubMaxLevelLine),
                                    clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertTrue(second.raidCatchClaimedToday, "재시작 후에도 오늘 이미 잡았다는 사실이 유지돼야 한다")
        XCTAssertFalse(second.claimRaidCatch(), "재시작 후 재도전해도 이미 잡은 날은 다시 못 잡아야 한다")
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

    /// [회귀] 6★ 는 보스가 오전/오후로 안 바뀌고 그 주 내내 고정인데, 지급 원장은 다른 티어와
    /// 같은 반나절 키를 써서 "오전 1회·오후 1회"로 잘렸다 — 아침에 두 판을 이겨도 두 번째
    /// 보상이 없었다(사용자 보고, 2026-09-10). **주가 아니라 하루 2회다** — 오전/오후를 넘나들지
    /// 않고 같은 반나절 안에서 두 번째 승리를 줘도 지급돼야 한다는 게 이 테스트의 핵심이다.
    @MainActor
    func testSixStarDailyRewardGivesTwiceRegardlessOfHalfDay() {
        let clock = TestClock()
        let store = stubStore(clock, tag: "raid-six-daily-reward")

        XCTAssertEqual(store.creditRaidReward(1_000, tier: .six), 1_000, "오늘 첫 승리는 지급된다")
        XCTAssertFalse(store.raidRewardClaimedToday(tier: .six), "하루 2회 중 아직 한 번만 썼다")

        // 시계를 전혀 돌리지 않는다 — 같은 반나절 안에서의 두 번째 승리를 검증하는 것이 요점이다.
        XCTAssertEqual(store.creditRaidReward(1_000, tier: .six), 1_000,
                       "오전/오후 구분 없이 오늘 두 번째 승리도 지급돼야 한다")
        XCTAssertTrue(store.raidRewardClaimedToday(tier: .six), "오늘의 2회를 다 썼다")
        XCTAssertEqual(store.creditRaidReward(1_000, tier: .six), 0, "오늘 세 번째는 없다")

        // 날짜가 바뀌면 다시 2회가 열린다.
        clock.advance(24 * 60 * 60)
        XCTAssertFalse(store.raidRewardClaimedToday(tier: .six), "날짜가 바뀌면 다시 2회가 열린다")
        XCTAssertEqual(store.creditRaidReward(1_000, tier: .six), 1_000)
    }

    /// 포획 추첨은 지급 성공(`raidPayout > 0`)에서만 도므로, 포획 원장도 지급과 같은 하루 한도를
    /// 따라야 한다 — 안 그러면 같은 반나절 안의 두 번째 승리에서 보상은 나가는데 포획만
    /// "이미 오늘 잡음"으로 막히는 어긋난 조합이 생긴다.
    @MainActor
    func testSixStarDailyCatchAllowsTwiceRegardlessOfHalfDay() {
        let clock = TestClock()
        let store = stubStore(clock, tag: "raid-six-daily-catch")

        XCTAssertTrue(store.claimRaidCatch(tier: .six))
        XCTAssertFalse(store.raidCatchClaimedToday(tier: .six), "하루 2회 중 아직 한 번만 썼다")
        XCTAssertTrue(store.claimRaidCatch(tier: .six), "같은 반나절 안에서도 두 번째 포획이 열려야 한다")
        XCTAssertTrue(store.raidCatchClaimedToday(tier: .six))
        XCTAssertFalse(store.claimRaidCatch(tier: .six), "오늘 세 번째는 없다")

        clock.advance(24 * 60 * 60)
        XCTAssertTrue(store.claimRaidCatch(tier: .six), "날짜가 바뀌면 다시 2회가 열린다")
    }

    // MARK: 포획 원장 — 지급 원장과 갈라져 있어야 한다

    /// 포획도 하루 한 마리다. 지급(`creditRaidReward`)과 **같은 규칙, 다른 원장**이다.
    @MainActor
    func testTheRaidCatchIsClaimedOncePerDay() {
        let clock = TestClock()
        let store = stubStore(clock, tag: "raid-catch-ledger")

        XCTAssertFalse(store.raidCatchClaimedToday)
        XCTAssertTrue(store.claimRaidCatch())
        XCTAssertTrue(store.raidCatchClaimedToday)
        XCTAssertFalse(store.claimRaidCatch(), "같은 날 두 번째 포획은 없다")

        clock.advance(24 * 60 * 60)
        XCTAssertTrue(store.claimRaidCatch(), "날짜 키가 넘어가면 다시 열린다")
    }

    /// **이 테스트가 원장을 따로 둔 이유 그 자체다.**
    ///
    /// 포획을 지급 원장에 태우면 이런 하루가 된다: 아침에 혼자 1★ 를 돌아 기본급 300 을 받는다 →
    /// `raidRewardDate` 가 오늘로 찍힌다 → 점심에 친구들과 3★ 를 잡아도 지급이 0 이라 포획까지
    /// 사라진다. 사용자는 아침에 잃은 것을 점심에야 알게 되고, 화면엔 아무 설명이 없다.
    @MainActor
    func testASmallSoloPayoutDoesNotBurnTodaysCatch() {
        let store = stubStore(TestClock(), tag: "raid-catch-independent")

        XCTAssertEqual(store.creditRaidReward(RaidTier.one.baseReward), RaidTier.one.baseReward)
        XCTAssertTrue(store.raidRewardClaimedToday)

        XCTAssertFalse(store.raidCatchClaimedToday, "지급 원장이 포획 원장을 태우면 안 된다")
        XCTAssertTrue(store.claimRaidCatch())

        // 반대 방향도 같다 — 포획을 먼저 해도 그날의 지급은 살아 있다.
        let other = stubStore(TestClock(), tag: "raid-catch-independent-2")
        XCTAssertTrue(other.claimRaidCatch())
        XCTAssertFalse(other.raidRewardClaimedToday)
        XCTAssertEqual(other.creditRaidReward(500), 500)
    }

    // MARK: 포획 배선 — 방이 추첨을 돌려 한 명에게만 넣는다

    /// 뽑고 싶은 사람이 뽑히는 시드를 찾는다. 추첨이 시드 함수라 테스트가 결과를 고를 수 있다 —
    /// 못 고르면 "누군가는 뽑힌다" 만 재게 되고, 뽑힌 쪽·안 뽑힌 쪽을 갈라서 못 본다.
    private func seedDrawing(_ target: UUID, from ids: [UUID], finishedRound: Int, tier: RaidTier = .three,
                             file: StaticString = #filePath, line: UInt = #line) -> UInt64 {
        let runners = ids.map { runner("runner", id: $0) }
        let species = RaidBoss.speciesID(at: Date(), tier: tier)
        for seed in UInt64(0)..<100_000 {
            let caught = RaidBoss.catchAttempts(runners: runners, speciesID: species, tier: tier, seed: seed,
                                                finishedRound: finishedRound).filter(\.succeeded).map(\.id)
            if caught == [target] { return seed }
        }
        XCTFail("100,000 개 시드 안에 이 사람만 잡는 판이 없다", file: file, line: line)
        return 0
    }

    /// **끝에서 끝까지.** 정산이 닫히면 뽑힌 사람의 박스에 보스가 실제로 들어와야 한다.
    /// 당첨자 계산만 재면 "계산은 맞는데 아무도 안 부른다" 가 초록으로 남는다.
    @MainActor
    func testTheDrawnRunnerTakesTheBossHome() async {
        let store = stubStore(TestClock(), tag: "raid-catch-wired")
        await store.hatch(baseID: 20)
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let mate = runner("동료")
        let boss = todaysBoss(tier: .three)
        let seed = seedDrawing(me.id, from: [me.id, mate.id], finishedRound: 1)
        XCTAssertTrue(center.applyGuestRaidStart(seed: seed, fighters: [me, mate, boss], tier: .three))

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 800, mate.id: 800])
        await center.debugAwaitRaidCatch()

        XCTAssertEqual(center.raidCatcherID, me.id)
        XCTAssertEqual(store.state.boxedMons.count, 1, "뽑혔는데 박스가 비어 있으면 배선이 끊긴 것이다")
        XCTAssertEqual(store.state.boxedMons.first?.currentID, boss.side.snapshot.speciesID,
                       "잡힌 종이 오늘의 보스가 아니다")
        XCTAssertTrue(store.raidCatchClaimedToday(tier: .three), "이 판은 3★ 원장에 찍혀야 한다")
    }

    /// **판이 도는 중에 온 로비 갱신은 명단만 바꾼다.** 누가 들어오거나 나가면 호스트가 로비를
    /// 전원에게 다시 뿌리는데, 그걸 받은 게스트가 화면 단계까지 로비로 되돌리면 배틀에서 튕긴다.
    /// 그 뒤 라운드는 `phase == .battling` 가드에 막혀 영영 안 들어오고 정산도 못 받는다 —
    /// 남은 사람들 눈에는 방이 통째로 멈춘 것으로 보인다.
    @MainActor
    func testALobbyUpdateDuringTheRaidDoesNotThrowGuestsOutOfTheBattle() throws {
        let store = stubStore(TestClock(), tag: "raid-midfight-join")
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let mate = runner("동료")
        let boss = todaysBoss(tier: .one)
        XCTAssertTrue(center.applyGuestRaidStart(seed: 11, fighters: [me, mate, boss], tier: .one))
        XCTAssertEqual(center.phase, .battling)

        // 늦게 들어온 사람이 하나 늘어난 명단이 도착한다.
        let host = LobbyParticipant(id: mate.id, trainerName: "동료", speciesID: 143,
                                    team: .red, isReady: true, isHost: true)
        var lobby = try XCTUnwrap(try? MultiplayerLobby(host: host,
                                                        capacity: MultiplayerLobby.raidCapacity,
                                                        activity: .raid))
        try lobby.join(LobbyParticipant(id: center.myID, trainerName: "나", speciesID: 143,
                                        team: .red, isReady: true, isHost: false))
        try lobby.join(LobbyParticipant(id: UUID(), trainerName: "지각", speciesID: 143,
                                        team: .red, isReady: false, isHost: false))
        center.applyGuestLobby(lobby)

        XCTAssertEqual(center.phase, .battling, "판이 도는 중에는 화면 단계가 로비로 돌아가면 안 된다")
        XCTAssertEqual(center.lobby?.participants.count, 3, "명단 자체는 갱신된다")

        // 튕기지 않았으니 다음 라운드가 그대로 들어온다.
        var hurtBoss = boss
        hurtBoss.side.hp = boss.side.hp - 1
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, hurtBoss], events: [])
        XCTAssertEqual(center.combatRound, 2, "라운드가 막히면 게스트는 판이 멈춘 것을 본다")
    }

    /// **판이 도는 레이드 방은 입장을 받지 않는다.** 늦게 들어온 사람에게 그 판의 편성을 보내는
    /// 경로가 레이드엔 없어(토너먼트·체육관에는 있다), 받아 봐야 판이 끝날 때까지 로비 화면만
    /// 보는 참가자가 명단에 하나 느는 것으로 끝난다.
    @MainActor
    func testARaidInProgressTurnsNewcomersAway() {
        let store = stubStore(TestClock(), tag: "raid-join-locked")
        let center = MultiplayerRoomCenter(companion: store)
        XCTAssertTrue(center.acceptsJoinWhileInPlay, "로비에서는 당연히 받는다")

        let me = runner("나", id: center.myID)
        let mate = runner("동료")
        XCTAssertTrue(center.applyGuestRaidStart(seed: 11, fighters: [me, mate, todaysBoss(tier: .one)],
                                                 tier: .one))
        XCTAssertFalse(center.acceptsJoinWhileInPlay, "판이 도는 중에는 받지 않는다")
    }

    /// 시작 메시지에 내 전투원이 없으면 기술을 낼 수 없는 유령 참가자가 된다.
    @MainActor
    func testGuestRejectsRaidStartWhenItsOwnRunnerIsMissing() {
        let store = stubStore(TestClock(), tag: "raid-missing-self")
        let center = MultiplayerRoomCenter(companion: store)
        let someoneElse = runner("다른 참가자")

        XCTAssertFalse(center.applyGuestRaidStart(
            seed: 11, fighters: [someoneElse, todaysBoss(tier: .one)], tier: .one))
        XCTAssertEqual(center.phase, .idle)
        XCTAssertEqual(center.lastError, store.l.raidBossMismatch)
    }

    /// 안 뽑힌 사람은 못 잡는다 — 그래도 정산은 그대로 받는다. 둘이 갈리지 않으면 방 전원이 잡는다.
    @MainActor
    func testARunnerWhoWasNotDrawnStillGetsPaid() async {
        let store = stubStore(TestClock(), tag: "raid-catch-not-drawn")
        await store.hatch(baseID: 20)
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let mate = runner("동료")
        let boss = todaysBoss(tier: .three)
        let seed = seedDrawing(mate.id, from: [me.id, mate.id], finishedRound: 1)
        XCTAssertTrue(center.applyGuestRaidStart(seed: seed, fighters: [me, mate, boss], tier: .three))

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 800, mate.id: 800])
        await center.debugAwaitRaidCatch()

        XCTAssertEqual(center.raidCatcherID, mate.id, "화면이 누가 가져갔는지 말할 수 있어야 한다")
        XCTAssertTrue(store.state.boxedMons.isEmpty, "안 뽑혔는데 잡혔다")
        XCTAssertFalse(store.raidCatchClaimedToday, "남이 잡은 판이 내 원장을 태우면 안 된다")
        XCTAssertEqual(center.raidPayout, center.raidSettlement?.total, "정산은 그대로 받는다")
    }

    /// **트리거 브랜치**: 1★ 도 이기면 포획이 있다(포획은 별·인원과 무관하다 — 위 주석 정정 참고).
    /// 400 HP 를 둘이 몇 턴에 깨는 티어라 열면 하루 한 마리가 사실상 보장된 수입이 된다.
    @MainActor
    func testAOneStarWinGetsTheSameRarityCatchChance() async {
        let store = stubStore(TestClock(), tag: "raid-catch-one-star")
        await store.hatch(baseID: 20)
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let mate = runner("동료")
        let boss = todaysBoss()
        let seed = seedDrawing(me.id, from: [me.id, mate.id], finishedRound: 1, tier: .one)
        XCTAssertTrue(center.applyGuestRaidStart(seed: seed, fighters: [me, mate, boss], tier: .one))

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 400])
        await center.debugAwaitRaidCatch()

        XCTAssertEqual(center.raidCatcherID, me.id, "별 등급과 무관하게 포획 확률을 적용한다")
        XCTAssertEqual(store.state.boxedMons.count, 1)
        XCTAssertTrue(store.raidCatchClaimedToday)
    }

    /// **트리거 브랜치**: 혼자 잡으면 포획이 없다. 러너가 한 명이면 추첨이 언제나 자기 자신이라,
    /// 이 가드가 없으면 3★ 를 혼자 깰 수 있는 사람에게 매일 한 마리가 그냥 나간다.
    @MainActor
    func testASoloWinGetsTheSameRarityCatchChance() async {
        let store = stubStore(TestClock(), tag: "raid-catch-solo")
        await store.hatch(baseID: 20)
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let boss = todaysBoss(tier: .three)
        let seed = seedDrawing(me.id, from: [me.id], finishedRound: 1)
        XCTAssertTrue(center.applyGuestRaidStart(seed: seed, fighters: [me, boss], tier: .three))

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 1_600])
        await center.debugAwaitRaidCatch()

        XCTAssertEqual(center.raidCatcherID, me.id, "혼자 성공해도 포획 확률은 적용된다")
        XCTAssertEqual(store.state.boxedMons.count, 1)
    }

    /// **회귀**: 방을 나간 러너는 추첨 풀에 없다.
    ///
    /// `forfeit` 은 hp 를 0 으로 만들고 `hasLeft` 를 세우지만 편성에는 남긴다 — 방을 떠난 사람도
    /// 같은 자리를 지난다(`retireFighter`). `hasLeft` 로 안 걸러내면 이미 `leaveRoom` 을 지난
    /// 사람이 당첨되고, 그 클라이언트는 정산도 포획도 부르지 않으므로 **보스가 아무에게도 안
    /// 간다**. 화면은 그 사이 "동료가 데려갔다" 를 그린다.
    @MainActor
    func testARunnerWhoLeftIsNeverDrawn() async {
        let store = stubStore(TestClock(), tag: "raid-catch-left")
        await store.hatch(baseID: 20)
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        var mate = runner("동료")
        let boss = todaysBoss(tier: .three)
        // 생존자 한 명에게 포획 성공이 나는 시드를 골라, 나간 동료가 결과 순서에 끼지 않음을 본다.
        let seed = seedDrawing(me.id, from: [me.id], finishedRound: 1)
        XCTAssertTrue(center.applyGuestRaidStart(seed: seed, fighters: [me, mate, boss], tier: .three))

        mate.side.hp = 0; mate.hasLeft = true   // 방을 나갔다 — 편성에는 남는다
        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 1_600, mate.id: 0])
        await center.debugAwaitRaidCatch()

        XCTAssertEqual(center.raidCatcherID, me.id, "방에 남아 있는 사람만 뽑힌다")
        XCTAssertEqual(store.state.boxedMons.count, 1, "당첨자가 실제로 데려가야 한다")
        XCTAssertTrue(store.raidCatchClaimedToday(tier: .three), "이 판은 3★ 원장에 찍혀야 한다")
    }

    /// **회귀**: 쓰러졌지만 방에 남은 러너는 추첨 대상이다(#270). `hasLeft` 를 안 세우면
    /// hp 만으로는 "쓰러짐"과 "이탈"을 못 갈라, 같이 싸우고도 쓰러진 참가자가 위 테스트처럼
    /// 통째로 제외됐다 — 승리에 기여했는데 포획 기회만 없는 것이 이상하다는 지적으로 바꿨다.
    @MainActor
    func testAFaintedButPresentRunnerIsStillDrawn() async {
        let store = stubStore(TestClock(), tag: "raid-catch-fainted-present")
        await store.hatch(baseID: 20)
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        var mate = runner("동료")
        let boss = todaysBoss(tier: .three)
        // 내가 아니라 쓰러진 동료가 뽑히는 시드를 골라, 대상에서 안 빠졌음을 직접 본다.
        let seed = seedDrawing(mate.id, from: [me.id, mate.id], finishedRound: 1)
        XCTAssertTrue(center.applyGuestRaidStart(seed: seed, fighters: [me, mate, boss], tier: .three))

        mate.side.hp = 0   // 싸우다 쓰러졌을 뿐 방은 나가지 않았다 — hasLeft 는 false 로 남는다
        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 1_600, mate.id: 0])
        await center.debugAwaitRaidCatch()

        XCTAssertEqual(center.raidCatcherID, mate.id, "쓰러졌어도 방에 남았으면 대상이다")
        // 동료의 포획은 동료 자신의 클라이언트가 지갑에 넣는다 — 내 화면은 결과만 본다.
        XCTAssertEqual(store.state.boxedMons.count, 0)
    }

    /// 내가 뽑히는 이긴 3★ 판을 한 판 돈다 — 포획 **결과만** 다른 테스트들이 같은 여섯 줄을 쓴다.
    @MainActor
    private func raidWhereIAmDrawn(_ store: CompanionStore) async -> MultiplayerRoomCenter {
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let mate = runner("동료")
        let boss = todaysBoss(tier: .three)
        let seed = seedDrawing(me.id, from: [me.id, mate.id], finishedRound: 1)
        XCTAssertTrue(center.applyGuestRaidStart(seed: seed, fighters: [me, mate, boss], tier: .three))

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 800, mate.id: 800])
        await center.debugAwaitRaidCatch()
        XCTAssertEqual(center.raidCatcherID, center.myID, "테스트 전제: 내가 뽑혔다")
        return center
    }

    /// **회귀**: 오늘 두 번째 이후의 승리(별의조각은 이미 받음)는 포획 추첨을 돌리지 않는다.
    ///
    /// 설계대로다(`lan-raid-design.md`) — "추가 판에도 참가하고 채팅할 수 있지만 같은 구간의
    /// 보상·포획은 없다." 지급이 0 인 판에서 추첨까지 돌리면 무제한 재도전으로 포획 확률을
    /// 불리는 길이 열린다. 화면이 이 판을 설명 없이 비워 두는 문제는 뷰(`finishedFooter`)가
    /// 안내 문구로 채운다 — 코어의 게이트 자체는 건드리지 않는다.
    @MainActor
    func testASecondWinOfTheDayDrawsNoCatcher() async {
        let store = stubStore(TestClock(), tag: "raid-catch-second-win-no-draw")
        await store.hatch(baseID: 20)
        // 이 판이 실제로 겨루는 티어(3★)의 원장을 미리 채운다 — 원장이 티어별로 갈리므로
        // 1★를 미리 채워도 3★ 승리는 여전히 "이 구간의 첫 승리" 다.
        XCTAssertEqual(store.creditRaidReward(RaidTier.three.baseReward, tier: .three),
                       RaidTier.three.baseReward)
        XCTAssertTrue(store.raidRewardClaimedToday(tier: .three), "테스트 전제: 별의조각은 이미 받았다")

        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let mate = runner("동료")
        let boss = todaysBoss(tier: .three)
        let seed = seedDrawing(me.id, from: [me.id, mate.id], finishedRound: 1)
        XCTAssertTrue(center.applyGuestRaidStart(seed: seed, fighters: [me, mate, boss], tier: .three))

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 800, mate.id: 800])
        await center.debugAwaitRaidCatch()

        XCTAssertEqual(center.raidPayout, 0, "오늘 두 번째 지급은 0 이다")
        XCTAssertNil(center.raidCatcherID, "추가 승리는 포획 추첨을 돌리지 않는다")
        XCTAssertTrue(center.raidCatchAttempts.isEmpty)
    }

    /// **회귀**: 오늘 이미 한 마리를 잡았는데 이번 판 주사위가 실패로 나오면, "놓쳤다"가 아니라
    /// 여전히 "이미 진행했다"로 남아야 한다. 주사위부터 보면 방금 실패한 것으로 읽힌다.
    @MainActor
    func testAnAlreadyClaimedCatcherIsNeverToldTheyEscaped() async {
        let store = stubStore(TestClock(), tag: "raid-catch-claimed-then-missed")
        await store.hatch(baseID: 20)
        store.claimRaidCatch(tier: .three)   // 오늘 이 티어(3★)로 이미 한 마리 데려왔다

        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let mate = runner("동료")
        let boss = todaysBoss(tier: .three)
        // 내가 아니라 동료가 뽑히는 시드 — 내 주사위는 실패로 나온다.
        let seed = seedDrawing(mate.id, from: [me.id, mate.id], finishedRound: 1)
        XCTAssertTrue(center.applyGuestRaidStart(seed: seed, fighters: [me, mate, boss], tier: .three))

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 800, mate.id: 800])
        await center.debugAwaitRaidCatch()

        XCTAssertEqual(center.raidCatcherID, mate.id, "테스트 전제: 동료가 뽑혔다")
        XCTAssertEqual(center.raidCatchResult, .claimedToday,
                       "주사위가 실패여도 이미 오늘 잡았으면 '놓쳤다'가 아니다")
    }

    /// **회귀**: 오늘 이미 한 마리를 데려왔으면 화면이 그 사실을 말해야 한다.
    ///
    /// 예전에는 어떤 실패든 "보스 정보를 불러오지 못해 … 오늘 다시 도전할 수 있어요" 였다 —
    /// 이 판에서는 두 문장 다 거짓이다. 원장 가드가 네트워크를 건드리기 전에 돌려보내므로 불러올
    /// 시도조차 없었고, 오늘 다시 도전해도 결과는 같다.
    @MainActor
    func testASecondCatchInTheSameDayTellsTheUserWhy() async {
        let store = stubStore(TestClock(), tag: "raid-catch-claimed-msg")
        await store.hatch(baseID: 20)
        store.claimRaidCatch(tier: .three)   // 오전에 이 티어(3★)로 이미 한 마리 데려왔다

        let center = await raidWhereIAmDrawn(store)

        XCTAssertEqual(center.raidCatchResult, .claimedToday)
        XCTAssertEqual(center.lastError, store.l.raidCatchAlreadyToday,
                       "로드 실패가 아니라 '하루 한 마리' 라고 말해야 한다")
        XCTAssertTrue(store.state.boxedMons.isEmpty)
    }

    /// **회귀**: 포획이 실패한 판은 성공 문구의 근거를 남기지 않는다.
    ///
    /// `raidCatcherID` 는 비동기 포획이 시작되기 **전에** 정해진다. 화면이 그 값만 보고 "상자에
    /// 있어요" 를 그리던 동안, 라인 조회가 실패하면 같은 화면에 오류 문구와 성공 문구가 나란히
    /// 남았다 — 그리고 상자는 비어 있었다.
    @MainActor
    func testAFailedCatchSaysSoAndKeepsTodaysChance() async {
        let store = CompanionStore(provider: RaidLineFailingProvider(), clock: TestClock().closure,
                                   fileURL: storeStateURL("raid-catch-failed"), rng: SeededRNG(seed: 7))

        let center = await raidWhereIAmDrawn(store)

        XCTAssertEqual(center.raidCatchResult, .unavailable,
                       "실패가 성공과 같은 값이면 화면이 '상자에 있어요' 를 그린다")
        XCTAssertEqual(center.lastError, store.l.raidCatchFailed)
        XCTAssertNil(store.state.active)
        XCTAssertTrue(store.state.boxedMons.isEmpty)
        XCTAssertFalse(store.raidCatchClaimedToday, "못 잡은 판이 오늘의 기회를 태우면 안 된다")
    }

    /// **회귀(관례)**: 방을 떠난 뒤 도착한 포획 결과가 화면에 남으면 안 된다.
    ///
    /// `sessionEpoch` 가 있는 이유다 — await 뒤의 쓰기는 사용자가 이미 떠난 방의 것일 수 있다.
    /// 가드가 없던 동안 나가기를 누른 뒤 모집 화면(혹은 **다음 레이드 방**)에 "보스 정보를 불러오지
    /// 못했어요" 가 떴다.
    ///
    /// 잡던 개체는 그대로 잡는다 — 그건 내 세이브에 들어가는 값이라 방을 떠나는 것과 무관하다.
    @MainActor
    func testALeftRoomNeverShowsTheCatchResult() async {
        let species = RaidBoss.speciesID(at: Date(), tier: .three)
        let provider = RaidSuspendedLineProvider(species: species)
        let store = CompanionStore(provider: provider, clock: TestClock().closure,
                                   fileURL: storeStateURL("raid-catch-stale"), rng: SeededRNG(seed: 7))
        let center = MultiplayerRoomCenter(companion: store)
        let me = runner("나", id: center.myID)
        let mate = runner("동료")
        let boss = todaysBoss(tier: .three)
        let seed = seedDrawing(me.id, from: [me.id, mate.id], finishedRound: 1)
        XCTAssertTrue(center.applyGuestRaidStart(seed: seed, fighters: [me, mate, boss], tier: .three))

        var downedBoss = boss
        downedBoss.side.hp = 0
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, downedBoss], events: [])
        center.applyGuestRaidSettlement([me.id: 800, mate.id: 800])
        XCTAssertEqual(center.raidCatcherID, center.myID, "테스트 전제: 내가 뽑혔다")
        // 조회가 실제로 붙잡히기를 기다린다 — `Task { }` 는 나중에 시작된다.
        var spins = 0
        while await provider.isSuspended() == false, spins < 1_000 { await Task.yield(); spins += 1 }
        let isSuspended = await provider.isSuspended()
        XCTAssertTrue(isSuspended, "테스트 전제: 포획이 라인 조회에서 도는 중이다")

        center.leaveRoom()          // 라인 조회가 아직 안 끝난 창에서 나간다
        await provider.resume()
        await center.debugAwaitRaidCatch()

        XCTAssertNil(center.lastError, "떠난 방의 결과가 다음 화면에 남았다")
        XCTAssertNil(center.raidCatchResult)
        XCTAssertEqual(store.state.active?.currentID, species, "잡던 개체는 그대로 잡는다")
    }

    /// 진 판은 아무도 못 잡는다 — 정산이 안 열리는 것과 같은 이유다.
    @MainActor
    func testALostRaidCatchesNothing() async {
        let store = stubStore(TestClock(), tag: "raid-catch-lost")
        await store.hatch(baseID: 20)
        let center = MultiplayerRoomCenter(companion: store)
        var me = runner("나", id: center.myID)
        var mate = runner("동료")
        let boss = todaysBoss(tier: .three)
        XCTAssertTrue(center.applyGuestRaidStart(seed: seedDrawing(me.id, from: [me.id, mate.id], finishedRound: 1),
                                                 fighters: [me, mate, boss], tier: .three))

        me.side.hp = 0; mate.side.hp = 0   // 파티 전멸
        center.applyGuestResolvedRound(round: 1, fighters: [me, mate, boss], events: [])
        center.applyGuestRaidSettlement([me.id: 800])
        await center.debugAwaitRaidCatch()

        XCTAssertNil(center.raidCatcherID)
        XCTAssertTrue(store.state.boxedMons.isEmpty)
        XCTAssertFalse(store.raidCatchClaimedToday, "진 판이 그날의 포획 기회를 태우면 안 된다")
    }

    // MARK: 포획 — 보스가 박스로 들어온다

    /// 잡은 보스는 **박스로** 간다. 동행을 밀어내지 않는다 — 밀어내면 레이드 한 판이 키우던
    /// 파트너를 조용히 치운다.
    ///
    /// 종은 스텁 라인의 종(20)으로 부른다. 실제 클라이언트의 `line(baseSpeciesID:)` 는 요청한 종을
    /// 포함한 체인 전체의 이름을 싣고 오므로(`allIDs(tree)`), 요청한 종의 이름이 있다는 전제는
    /// 스텁과 실물이 같다.
    @MainActor
    func testCatchingTheBossPutsItInTheBox() async {
        let store = stubStore(TestClock(), tag: "raid-catch-box")
        await store.hatch(baseID: 20)
        let partner = store.state.active?.id
        XCTAssertNotNil(partner, "테스트 전제: 동행이 있다")

        let result = await store.catchRaidBoss(speciesID: 20)
        XCTAssertEqual(result, .box)

        XCTAssertEqual(store.state.active?.id, partner, "동행은 그대로다")
        XCTAssertEqual(store.state.boxedMons.count, 1)
        let caught = try? XCTUnwrap(store.state.boxedMons.first)
        XCTAssertEqual(caught?.currentID, 20)
        XCTAssertEqual(caught?.totalForms, 1, "풀은 전부 최종 진화체라 단일 형태로 선다")
        XCTAssertNotNil(caught?.firstMetAt, "첫 만남이 없으면 홈·추억이 이 개체를 못 센다")
        XCTAssertNotNil(caught?.names?[20], "이름이 없으면 도감이 종 번호(#20)를 그린다")
        XCTAssertEqual(caught?.rarity, .common, "희귀도는 라인에서 읽는다 — 박아 두면 전설이 흔해진다")
        XCTAssertTrue(store.raidCatchClaimedToday, "성공한 포획은 오늘의 원장을 쓴다")
    }

    /// 하루 한 마리. 두 번째 판이 같은 날 또 잡으면 3★ 를 반복해 하루에 전설을 여러 마리 얻는다.
    @MainActor
    func testASecondCatchOnTheSameDayIsRefused() async {
        let store = stubStore(TestClock(), tag: "raid-catch-twice")
        await store.hatch(baseID: 20)
        let first = await store.catchRaidBoss(speciesID: 20)
        let second = await store.catchRaidBoss(speciesID: 20)
        XCTAssertEqual(first, .box)
        XCTAssertEqual(second, .claimedToday, "실패와 하루 한 마리는 화면이 다르게 말해야 한다")
        XCTAssertEqual(store.state.boxedMons.count, 1, "박스에 두 마리가 들어오면 안 된다")
    }

    /// 스프라이트가 없는 번호는 잡히지 않는다 — 박스에 그릴 수 없는 칸이 영구히 남는다
    /// (`PokemonAssets.hasAnimatedSprite` 가 교환 경계에서 지키는 것과 같은 계약).
    /// 원장도 안 쓴다: 못 잡은 판이 그날의 기회를 태우면 안 된다.
    @MainActor
    func testAnUndrawableSpeciesIsNeverCaught() async {
        let store = stubStore(TestClock(), tag: "raid-catch-gap")
        await store.hatch(baseID: 20)
        let gap = PokemonAssets.spriteGaps.first ?? 990
        let result = await store.catchRaidBoss(speciesID: gap)
        XCTAssertEqual(result, .unavailable)
        XCTAssertTrue(store.state.boxedMons.isEmpty)
        XCTAssertFalse(store.raidCatchClaimedToday, "못 잡은 판이 오늘의 기회를 태우면 안 된다")
    }

    /// 동행이 비어 있으면(졸업 직후 등) 박스가 아니라 바로 동행으로 들어간다 — 보관 알 부화와
    /// 같은 규칙이다. 안 그러면 동행 없는 화면을 두고 사용자가 박스에서 직접 꺼내야 한다.
    @MainActor
    func testTheCatchFillsAnEmptyCompanionSlot() async {
        let store = stubStore(TestClock(), tag: "raid-catch-empty")
        XCTAssertNil(store.state.active, "테스트 전제: 동행이 없다")

        let result = await store.catchRaidBoss(speciesID: 20)
        XCTAssertEqual(result, .companion, "빈 동행 자리를 채웠으면 '상자' 라고 말할 수 없다")
        XCTAssertEqual(store.state.active?.currentID, 20)
        XCTAssertTrue(store.state.boxedMons.isEmpty)
    }

    /// **회귀**: 잡은 보스는 다음 라인 로드를 지나도 **잡은 그 모습**이어야 한다.
    ///
    /// 실제 `line(baseSpeciesID:)` 는 최종체를 물어도 체인 **뿌리부터** 트리를 싣고 온다. 저장된
    /// 경로가 뿌리에서 시작하지 않으면 정규화가 뿌리로 되돌리던 동안, 잡은 가디안이 동행 자리에
    /// 앉는 순간 레벨 1 랄토스가 됐다 — 추첨 풀 32종 중 21종이 이전 진화를 가진다.
    ///
    /// `stubMaxLevelLine`(단일 노드) 로는 어떤 시드로도 못 밟는다. 이 부류를 재려면 3단 라인이 필요하다.
    @MainActor
    func testACaughtBossKeepsItsFormWhenTheLineLoads() async {
        let store = threeStageStore(TestClock(), tag: "raid-catch-form")
        XCTAssertNil(store.state.active, "테스트 전제: 동행이 없어 잡은 보스가 동행 자리로 간다")

        let result = await store.catchRaidBoss(speciesID: 445)
        XCTAssertEqual(result, .companion)
        await store.debugReloadCurrentLine()

        XCTAssertEqual(store.state.active?.currentID, 445, "라인 로드가 잡은 보스를 1단계로 되돌렸다")
        XCTAssertEqual(store.state.active?.pathIDs, [445], "경로는 잡은 자리에서 시작한다")
        XCTAssertEqual(store.state.active?.totalForms, 1, "최종체를 잡았으면 앞으로 진화할 곳이 없다")
    }

    /// 같은 계약의 다른 쪽 — 체인 **중간**을 잡으면 남은 진화는 살아 있어야 한다. 뿌리로 되돌리는
    /// 것도, 단일 형태로 못 박는 것도 둘 다 틀린 답이다(풀에 중간 종이 들어오는 날 조용히 갈린다).
    @MainActor
    func testCatchingAMidChainSpeciesKeepsTheRemainingEvolutions() async {
        let store = threeStageStore(TestClock(), tag: "raid-catch-midchain")

        let result = await store.catchRaidBoss(speciesID: 444)
        XCTAssertEqual(result, .companion)
        await store.debugReloadCurrentLine()

        XCTAssertEqual(store.state.active?.currentID, 444)
        XCTAssertEqual(store.state.active?.plannedPathIDs, [444, 445], "남은 진화가 사라졌다")
        XCTAssertEqual(store.state.active?.totalForms, 2)
    }

    // MARK: 게스트 시점 — 호스트와 갈라지는 축

    /// 오늘의 보스 한 마리. 게스트 검증(`validRaidStart`)을 통과하려면 종이 오늘의 종이어야 한다.
    private func todaysBoss(tier: RaidTier = .one) -> MultiplayerFighter {
        var todays = snapshot(level: tier.bossLevel, moves: [move(id: 33, power: 40)])
        todays.speciesID = RaidBoss.speciesID(at: Date(), tier: tier)
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

    /// 세 티어 모두 상시 열려 있다(2026-09-08, 예약 부화 창 폐지) — 5★ 를 여는 데 시각 게이트가
    /// 다시 생기지 않았는지 지킨다.
    @MainActor
    func testAllTiersOpenWithoutATimeGate() {
        let store = stubStore(TestClock(), tag: "raid-open-anytime")
        let center = MultiplayerRoomCenter(companion: store)

        center.createRaidRoom(tier: .five)
        XCTAssertEqual(center.raidTier, .five)
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
        XCTAssertEqual(RoomBattleView.RecentBattleLabel.text(mode: .coopBoss, participantCount: 3), "RAID 3P")
        XCTAssertEqual(RoomBattleView.RecentBattleLabel.text(mode: .freeForAll, participantCount: 3), "3P")
        XCTAssertEqual(RoomBattleView.RecentBattleLabel.text(mode: .teams, participantCount: 4), "2 vs 2")
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

    /// 6★ 는 "오늘인가"(`raidRewardDateTierSix`)와 별개로 "오늘 몇 번 받았나"
    /// (`raidRewardCountTierSix`)를 서명 밖에 두면, 날짜는 그대로 두고 횟수만 0으로 되돌리는
    /// 것만으로 오늘의 두 번째 보상을 계속 받는다.
    func testDeletingTheSixStarRewardCountAfterSigningIsDetected() {
        var state = CompanionState()
        state.raidRewardDateTierSix = "2026-09-10"
        state.raidRewardCountTierSix = 2
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed))

        signed.raidRewardCountTierSix = 0
        XCTAssertTrue(SaveTransfer.isTampered(signed), "날짜는 그대로 두고 횟수만 되돌리는 방향이 곧 재수령 방향이다")
    }

    /// 포획 횟수도 같은 부류다 — `testDeletingTheSixStarRewardCountAfterSigningIsDetected` 와 짝이다.
    func testDeletingTheSixStarCatchCountAfterSigningIsDetected() {
        var state = CompanionState()
        state.raidCatchDateTierSix = "2026-09-10"
        state.raidCatchCountTierSix = 2
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed))

        signed.raidCatchCountTierSix = 0
        XCTAssertTrue(SaveTransfer.isTampered(signed), "날짜는 그대로 두고 횟수만 되돌리는 방향이 곧 재포획 방향이다")
    }

    /// [회귀 가드] `r6d` 세그먼트 자체는 **건드리지 않았다** — 값의 뜻만(반나절 키 → 하루 키)
    /// 바뀌었을 뿐, `canonicalString` 이 그 필드를 붙이는 방식(`"r6d" + 원문 그대로`)은 그대로다.
    /// 그래서 이미 배포된 세이브가 반나절 키로 서명한 상태여도(6★ 레이드를 한 번이라도 도전한
    /// 세이브) 그 서명은 여전히 재현된다. 값을 그대로 두고 형식(`":count"` 접미 등)을 덧붙이는
    /// 실수를 하면 이 테스트가 바로 깨진다 — `signed()`/`isTampered()` 왕복만으로는 자기 자신과
    /// 비교하는 것이라 형식이 바뀌어도 통과해 버린다(`r6a` 세그먼트를 통째로 지웠던
    /// hotfix, 2026-09-10, 은 세그먼트 자체가 사라진 경우라 여기 해당하지 않는다).
    func testTheSixStarRewardDateSegmentFormatIsUnchanged() {
        var state = CompanionState()
        state.raidRewardDateTierSix = "2026-09-08-am"   // 이번 배포 전 형식(반나절 키) 그대로도 안전해야 한다
        let segments = SaveTransfer.canonicalString(state).components(separatedBy: "|")
        XCTAssertTrue(segments.contains("r6d2026-09-08-am"),
                      "r6d 세그먼트는 raidRewardDateTierSix 값을 그대로 붙여야 한다 — 형식을 바꾸면 이미 배포된 세이브의 서명이 깨진다")
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

    /// 포획 원장도 서명 대상이다 — 지우는 것만으로 같은 날 몇 마리든 다시 잡는다.
    /// 잡은 개체는 박스에 영구히 남으므로 지급 원장보다 되돌리기 어렵다.
    func testDeletingTheRaidCatchDateAfterSigningIsDetected() {
        var state = CompanionState()
        state.raidCatchDate = "2026-09-02"
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed))

        signed.raidCatchDate = ""
        XCTAssertTrue(SaveTransfer.isTampered(signed), "지우는 방향이 곧 재포획 방향이다")
    }

    /// 조건부 append 여야 한다 — 무조건 붙이면 이 필드가 없던 정상 세이브가 전부 조작 판정된다.
    func testDefaultStateGainsNoRaidCatchCanonicalSegment() {
        XCTAssertFalse(SaveTransfer.canonicalString(CompanionState()).contains("|rc"))
    }

    /// [회귀] 6성 레이드 도전 횟수 제한(`weeklyRaidAttemptDate`/`weeklyRaidAttemptsToday`)을 없애며
    /// 그 필드가 채우던 canonical 세그먼트(`r6a`)도 통째로 지웠다. **필드 제거는 필드 추가의 반대
    /// 방향이라 "새 필드는 integrityVersion 을 안 올린다" 규칙이 적용되지 않는다** — 그 세그먼트가
    /// 이미 서명에 들어 있던(6성 레이드를 한 번이라도 시도한) 기존 세이브는 새 코드가 그 세그먼트를
    /// 다시 만들어 낼 수 없어 해시가 영원히 어긋난다. 실제로 배포 후 사용자 세이브가 초기화되는
    /// 사고로 이어졌다(2026-09-10, `integrityVersion` 12→13 으로 대응).
    func testASaveSignedWithTheRemovedWeeklyRaidAttemptSegmentIsExempt() {
        // 그 필드가 있던 시절의 canonical 문자열을 손으로 재현한다 — `weeklyRaidAttemptDate`/
        // `weeklyRaidAttemptsToday` 만 채워진 상태에서, 옛 코드는 "|eg0" 다음 "|ef0" 앞에
        // "|r6a<date>:<count>" 를 끼워 넣었다(구 `canonicalString` 의 append 순서 — `eg` 직후,
        // `ef` 직전. `c6d`~`wed` 사이 다른 조건부 세그먼트는 전부 비어 있어 안 끼었다).
        let deviceSeed = "test-device"
        let base = SaveTransfer.canonicalString(CompanionState(), deviceSeed: deviceSeed)
        XCTAssertTrue(base.contains("|eg0|ef0"), "기준 문자열 형식이 바뀌었다 — 아래 스플라이스 위치를 다시 확인하라")
        let legacyCanonical = base.replacingOccurrences(of: "|eg0|ef0", with: "|eg0|r6a2026-09-08:2|ef0")
        let legacyHash = String(Self.fnv1aForTest(legacyCanonical), radix: 16)

        var legacy = CompanionState()
        legacy.integrityVersion = 12   // r6a 세그먼트가 있던 시절(11→12 상향 이후, 12→13 상향 이전)
        legacy.integrity = legacyHash

        XCTAssertFalse(SaveTransfer.isTampered(legacy, deviceSeed: deviceSeed),
                       "r6a 세그먼트가 들어 있던 구서명이 조작으로 잡히면 그 세이브를 가진 사용자 전원이 초기화된다")

        // 대조군 — 같은 해시에 현재 버전을 써 넣으면 실제로 안 맞는다(구버전 면제가 하는 일이지,
        // 해시가 우연히 같아서 통과하는 게 아님을 보인다).
        var claimingCurrentVersion = legacy
        claimingCurrentVersion.integrityVersion = SaveTransfer.integrityVersion
        XCTAssertTrue(SaveTransfer.isTampered(claimingCurrentVersion, deviceSeed: deviceSeed))
    }

    /// `SaveTransfer.fnv1a` 는 private 이라 여기서 같은 알고리즘을 그대로 재현한다 — 표준 FNV-1a
    /// (64비트)라 구현이 갈릴 여지가 없다.
    private static func fnv1aForTest(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }

    /// 계정 원장이다 — 더 최근 날짜를 안 남기면 맥 A 에서 잡고 내보내 맥 B 로 불러오는 것만으로
    /// 같은 날 두 마리가 된다(`raidRewardDate` 와 같은 부류·같은 이유).
    func testRebaseKeepsTheNewerRaidCatchDate() {
        var imported = CompanionState()
        imported.raidCatchDate = "2026-08-01"
        var current = CompanionState()
        current.raidCatchDate = "2026-09-02"
        XCTAssertEqual(SaveTransfer.rebasedForThisDevice(imported, current: current).raidCatchDate,
                       "2026-09-02", "이 기기가 오늘 이미 잡았으면 잡은 것이다")

        imported.raidCatchDate = "2026-09-02"
        current.raidCatchDate = "2026-08-01"
        XCTAssertEqual(SaveTransfer.rebasedForThisDevice(imported, current: current).raidCatchDate,
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

    // MARK: 레이드 스냅샷 레벨

    /// **트리거 브랜치**: 레이드 스냅샷은 처음부터 파티 레벨로 만든다.
    ///
    /// `startRaid` 는 러너의 `snapshot.level` 만 50 으로 눕힌다. 스냅샷을 개체 레벨로 만들어 두면
    /// 몸만 50 이 되고 자동 무브셋은 개체 레벨에 머문다 — `CompanionStore.battleSnapshot` 주석이
    /// "몸은 50 인데 기술은 3" 으로 한 번 고쳐 둔 결함이 레이드에서 되살아난다. 대표 포켓몬으로
    /// Lv.7 박스 개체를 일부러 내보낼 수 있게 된 지금은 예외가 아니라 기본 경로다.
    ///
    /// 판단을 호출부의 삼항식이 아니라 `raidLevel` 안에 둔 덕에 **여기서 전 분기를 실행한다.**
    /// 예전엔 이 자리가 소스 grep 이라 조건을 뒤집어도 2085개가 전부 초록이었다 — 글자만 봤기
    /// 때문이다(리뷰에서 주입해 확인했다).
    func testOnlyRaidRoomsAreBuiltAtPartyLevel() {
        for activity in RoomActivity.allCases {
            let level = MultiplayerRoomCenter.raidLevel(activity: activity)
            if activity == .raid {
                XCTAssertEqual(level, RaidBoss.partyLevel, "안 눕히면 몸과 기술의 레벨이 갈린다")
            } else {
                XCTAssertNil(level, "\(activity) 는 실제 레벨로 싸운다 — 여기서 눕히면 안 된다")
            }
        }
    }

    /// 남의 방에 들어갈 때는 활동을 아직 모른다(로비는 붙은 뒤에 온다) — 방 이름으로 가른다.
    /// 여는 자리와 들어가는 자리가 같은 규칙을 각자 적으면 한쪽만 뒤집혀도 안 깨지므로,
    /// 두 입구 모두 이 함수를 지난다.
    func testJoiningSortsRaidRoomsByName() {
        let raidRoom = RaidRoomName.make(trainerName: "나", idTag: "abc123", tier: .three)
        XCTAssertEqual(MultiplayerRoomCenter.raidLevel(serviceName: raidRoom), RaidBoss.partyLevel)
        XCTAssertNil(MultiplayerRoomCenter.raidLevel(serviceName: "GYM · 3 · 나#abc123"),
                     "체육관 방을 레이드로 읽으면 남의 방 편성까지 눕는다")
    }
}

/// 라인 조회가 항상 실패하는 제공자 — 오프라인·PokéAPI 5xx 로 포획이 못 끝나는 판을 만든다.
private struct RaidLineFailingProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw RaidProviderError.offline }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
}

/// 라인 조회를 **첫 한 번만** 붙잡아 두는 제공자 — "포획이 도는 중" 이라는 창을 테스트가 직접
/// 만든다. 풀어 준 뒤의 조회(포획 직후의 라인 재로드)는 바로 돌려준다.
private actor RaidSuspendedLineProvider: PokeProviding {
    private let species: Int
    private var pending: CheckedContinuation<EvoLine, Never>?
    private var released = false

    init(species: Int) { self.species = species }

    private var made: EvoLine {
        EvoLine(baseID: species, tree: EvoNode(speciesID: species, children: []),
                rarity: .legendary, names: [species: ["en": "Boss", "ko": "보스", "ja": "ボス"]])
    }

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        if released { return made }
        return await withCheckedContinuation { continuation in
            precondition(pending == nil, "한 번에 하나만 붙잡는다")
            pending = continuation
        }
    }

    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }

    /// 조회가 실제로 붙잡혀 있나. **폴링이 필요하다** — `Task { }` 는 나중에 시작되므로, 기다리지
    /// 않고 풀어 주면 풀 대상이 아직 없어 조회가 영원히 매달린다.
    func isSuspended() -> Bool { pending != nil }

    func resume() {
        released = true
        let waiting = pending
        pending = nil
        waiting?.resume(returning: made)
    }
}

private enum RaidProviderError: Error { case offline }
