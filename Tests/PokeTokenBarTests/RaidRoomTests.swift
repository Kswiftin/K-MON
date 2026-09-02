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
    func testTurnCapAppliesOnlyToRaids() throws {
        var raid = try MultiplayerBattle(fighters: [runner("A"), boss()], mode: .coopBoss, seed: 1)
        XCTAssertFalse(raid.reachedTurnCap, "1라운드에 상한일 수는 없다")

        let solo = { (name: String) -> MultiplayerFighter in
            let p = LobbyParticipant(id: UUID(), trainerName: name, speciesID: 143,
                                     team: .solo, isReady: true, isHost: false)
            return MultiplayerFighter(participant: p, snapshot: self.snapshot(moves: [self.move(id: 33, power: 80)]))
        }
        let plain = try MultiplayerBattle(fighters: [solo("A"), solo("B")], mode: .freeForAll, seed: 1)
        XCTAssertFalse(plain.reachedTurnCap)

        // 상한을 넘겨 본다 — 레이드만 참이어야 한다.
        raid.debugAdvanceRound(to: RaidBoss.turnCap + 1)
        XCTAssertTrue(raid.reachedTurnCap)
        var plainPast = plain
        plainPast.debugAdvanceRound(to: RaidBoss.turnCap + 1)
        XCTAssertFalse(plainPast.reachedTurnCap, "개인전은 턴 상한이 없다")
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
}
