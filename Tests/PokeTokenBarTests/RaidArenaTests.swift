import XCTest
@testable import PokeTokenBar

/// 레이드 화면에 1v1·웨이브 런과 **같은 배틀 UX**(필드 + 턴 재생)를 얹는 층의 순수 판정.
///
/// 뷰 자체는 여기서 못 밟는다. 그래서 재생이 실제로 도는지를 가르는 결정들 —
/// 스트림이 자라는가 · 재생 중 입력을 받는가 · 결과를 언제 여는가 — 을 전부 떼어내 여기서 본다
/// (`MultiplayerRoomCenter.creditsRaceFinish`·`ChallengeView.presentsPokeathlon` 과 같은 이유).
final class RaidArenaTests: XCTestCase {

    // MARK: 고정 재료

    private func snapshot(hp: Int = 100, level: Int = RaidBoss.partyLevel) -> BattleSnapshot {
        var made = BattleSnapshot(speciesID: 143, name: "탱커", trainer: nil, level: level,
                                  nature: nil, isShiny: false, types: [.normal],
                                  base: BattleStats(hp: hp, atk: 100, def: 100, spa: 100,
                                                    spd: 100, spe: 100))
        made.moves = [MoveSpec(id: 33, names: ["en": "Tackle"], type: .normal, power: 80,
                               damageClass: .physical, accuracy: nil, pp: 35)]
        return made
    }

    private func runner(_ name: String, id: UUID = UUID()) -> MultiplayerFighter {
        MultiplayerFighter(participant: LobbyParticipant(id: id, trainerName: name, speciesID: 143,
                                                         team: .red, isReady: true, isHost: false),
                           snapshot: snapshot())
    }

    private func boss(tier: RaidTier = .five) -> MultiplayerFighter {
        RaidBoss.bossFighter(tier: tier, snapshot: snapshot(level: tier.bossLevel))
    }

    // MARK: Phase 1 — 누적 스트림

    /// **재생이 도는 유일한 조건이다.** 방은 라운드 이벤트를 `combatEvents = events` 로 덮어썼다.
    /// `BattleAnimator.sync` 는 자라는 스트림을 전제하므로(`stream.count >= playedCount`),
    /// 덮어쓰면 매 라운드가 "새 배틀"로 읽혀 재생 없이 seed 만 되고 화면이 결과로 스냅한다.
    @MainActor
    func testResolvedRoundsAccumulateIntoOneStream() {
        let center = MultiplayerRoomCenter(companion: stubStore(TestClock(), tag: "raid-stream"))
        let party = [runner("A")], fighters = party + [boss()]

        center.debugBeginRaidCombat(fighters: fighters, tier: .five)
        XCTAssertTrue(center.combatEvents.isEmpty, "새 배틀은 빈 스트림에서 시작한다")

        center.debugApplyResolvedRound(fighters: fighters, events: [.turn(1), .faint(.fighter(party[0].id))])
        center.debugApplyResolvedRound(fighters: fighters, events: [.turn(2)])

        XCTAssertEqual(center.combatEvents.count, 3, "두 라운드가 한 스트림에 이어 붙는다")
        XCTAssertEqual(center.combatEvents.first, .turn(1))
        XCTAssertEqual(center.combatEvents.last, .turn(2))
    }

    /// 다음 판은 스트림을 비우고 시작한다 — 안 비우면 재생기가 지난 배틀을 이어서 튼다.
    @MainActor
    func testANewRaidStartsFromAnEmptyStream() {
        let center = MultiplayerRoomCenter(companion: stubStore(TestClock(), tag: "raid-stream2"))
        let fighters = [runner("A"), boss()]

        center.debugBeginRaidCombat(fighters: fighters, tier: .five)
        center.debugApplyResolvedRound(fighters: fighters, events: [.turn(1)])
        XCTAssertFalse(center.combatEvents.isEmpty)

        center.debugBeginRaidCombat(fighters: fighters, tier: .five)
        XCTAssertTrue(center.combatEvents.isEmpty)
        XCTAssertEqual(center.combatRound, 1)
    }

    // MARK: Phase 2 — 보스 HP 막대의 분모

    /// 보스 HP 는 종족값이 아니라 **티어 절대값**이다. `CombatantBar` 는 `side.stats.hp` 로
    /// 나누므로 그대로 쓰면 막대가 100% 를 넘어 칸 밖으로 나간다.
    func testCombatantBarUsesTheOverriddenMaximum() {
        let side = BattleSide(snapshot())
        XCTAssertEqual(CombatantBar.maxHP(of: side, override: nil), side.stats.hp,
                       "오버라이드가 없으면 종족값에서 나온 최대 HP 다")
        XCTAssertEqual(CombatantBar.maxHP(of: side, override: RaidTier.five.bossHP),
                       RaidTier.five.bossHP)
    }

    /// **네 자리가 같은 분모를 봐야 한다** — 티어·채움 비율·내 표기·상대 표기. 하나만 빠뜨리면
    /// 색과 길이가 서로 다른 척도를 그린다(defect-log: 상한이 누적 지점마다 흩어지면 한 곳은
    /// 반드시 빠진다).
    func testEveryReadoutInTheBarSharesThatMaximum() {
        var side = BattleSide(snapshot())
        // **두 분모가 서로 다른 답을 내는 값**을 고른다. 만피로 재면 어느 분모로도 `.healthy` 라
        // 오버라이드를 안 써도 통과한다 — 대조군이 없는 단언이다.
        side.hp = RaidTier.five.bossHP / 10                 // 티어 기준 10% = 빈사
        let max = CombatantBar.maxHP(of: side, override: RaidTier.five.bossHP)

        XCTAssertEqual(HPTier.of(hp: side.hp, max: max), .critical, "티어 기준 10% 면 빈사색이다")
        XCTAssertEqual(HPReadout.theirs(hp: side.hp, max: max), "10%")
        XCTAssertEqual(HPReadout.ratio(hp: side.hp, max: max), 0.1, accuracy: 0.001)

        // 대조군 — 종족값으로 재면 같은 HP 가 **만피 초과**로 읽혀 색도 길이도 거짓말을 한다.
        XCTAssertEqual(HPTier.of(hp: side.hp, max: side.stats.hp), .healthy)
        XCTAssertGreaterThan(Double(side.hp) / Double(side.stats.hp), 1)
    }

    // MARK: Phase 3·4 — 재생 배선

    /// 재생기는 주인별 표시 상태를 받는다. 레이드는 1인 1마리라 팀이 한 칸씩이다.
    func testEveryFighterBecomesItsOwnReplaySide() throws {
        let a = runner("A"), b = runner("B"), theBoss = boss()
        let sides = RaidArena.replaySides([a, b, theBoss])

        XCTAssertEqual(sides.count, 3)
        let mine = try XCTUnwrap(sides[.fighter(a.id)])
        XCTAssertEqual(mine.team.count, 1, "레이드는 교체가 없어 팀이 한 마리다")
        XCTAssertEqual(mine.active, 0)
        XCTAssertNotNil(sides[.fighter(RaidBoss.bossID)], "보스도 주인이다 — 없으면 보스 바가 안 움직인다")
    }

    /// **트리거 브랜치 — 보고된 정지.** 이벤트 없이 끝나는 경로가 있다: 이탈 몰수와 턴 상한은
    /// `broadcastCombatState()` 로 **빈 이벤트**를 보내므로 `combatEvents` 도 `combatRound` 도
    /// 안 바뀌고, 그러면 뷰의 `.onChange` 가 안 걸려 재생기가 영영 안 불린다.
    ///
    /// 그 상태에서 `playedCount < streamCount` 로 남아 있으면 결과가 **영원히** 안 뜬다.
    /// 결과를 미루는 근거는 "재생이 돌고 있다" 이지 "숫자가 아직 다르다" 가 아니다 —
    /// 돌고 있지 않으면 더 기다릴 이유가 없다.
    func testAStalledReplayDoesNotHideTheResultForever() {
        XCTAssertTrue(RaidArena.showsResult(isFinished: true, playedCount: 3, streamCount: 9,
                                            isReplaying: false),
                      "재생이 멈춰 있으면 더 기다리지 않는다 — 이게 화면이 얼어붙던 조건이다")
        XCTAssertFalse(RaidArena.showsResult(isFinished: true, playedCount: 3, streamCount: 9,
                                             isReplaying: true),
                       "돌고 있는 재생은 끝까지 기다린다")
    }

    /// **결과 화면은 재생 뒤로 미룬다.** 승부가 난 라운드가 즉시 결과로 넘어가면, 재생기를 붙인
    /// 이유(결정타를 보여 주는 것)가 가장 중요한 턴에 그대로 사라진다.
    func testTheResultWaitsForTheReplayToCatchUp() {
        XCTAssertFalse(RaidArena.showsResult(isFinished: true, playedCount: 3, streamCount: 9,
                                             isReplaying: true),
                       "아직 재생 중이면 결과를 열지 않는다")
        XCTAssertTrue(RaidArena.showsResult(isFinished: true, playedCount: 9, streamCount: 9,
                                            isReplaying: false))
        XCTAssertFalse(RaidArena.showsResult(isFinished: false, playedCount: 9, streamCount: 9,
                                             isReplaying: false),
                       "안 끝났으면 따라잡았어도 결과가 아니다")
    }

    /// 끝난 판이 "다른 참가자의 행동을 기다리는 중" 을 띄우면 안 된다 — 아무도 안 온다.
    /// 화면이 무엇을 말할지는 입력 가능 여부와 **다른 축**이다.
    func testAFinishedRaidStopsClaimingItIsWaitingForPlayers() {
        XCTAssertEqual(RaidArena.prompt(isReplaying: false, isAlive: true,
                                        isFinished: true, hasSubmitted: true), .finished)
        XCTAssertEqual(RaidArena.prompt(isReplaying: false, isAlive: true,
                                        isFinished: false, hasSubmitted: true), .waitingForOthers)
        XCTAssertEqual(RaidArena.prompt(isReplaying: true, isAlive: true,
                                        isFinished: false, hasSubmitted: true), .replaying)
        XCTAssertEqual(RaidArena.prompt(isReplaying: false, isAlive: false,
                                        isFinished: false, hasSubmitted: false), .knockedOut)
        XCTAssertEqual(RaidArena.prompt(isReplaying: false, isAlive: true,
                                        isFinished: false, hasSubmitted: false), .chooseMove)
    }

    /// 재생 중에는 기술 버튼을 받지 않는다 — 받으면 지난 턴을 보는 중에 다음 턴이 나간다.
    func testInputIsClosedWhileReplayingAndAfterSubmitting() {
        func accepts(submitted: Bool = false, alive: Bool = true,
                     finished: Bool = false, replaying: Bool = false) -> Bool {
            RaidArena.acceptsInput(hasSubmitted: submitted, isAlive: alive,
                                   isFinished: finished, isReplaying: replaying)
        }
        XCTAssertTrue(accepts())
        XCTAssertFalse(accepts(replaying: true), "재생 중엔 잠긴다")
        XCTAssertFalse(accepts(submitted: true), "이미 냈으면 잠긴다")
        XCTAssertFalse(accepts(alive: false), "쓰러졌으면 잠긴다")
        XCTAssertFalse(accepts(finished: true), "끝난 판은 잠긴다")
    }

    /// **보고된 정지 재현**: 보스가 죽었는데 결과가 안 뜨고 "다른 참가자를 기다리는 중" 에서
    /// 멈춘다. 뷰가 하는 sync 호출을 그대로 흉내 내 재생기가 실제로 따라잡는지 본다.
    @MainActor
    func testTheResultAppearsOnceTheKillingRoundHasReplayed() async throws {
        let center = MultiplayerRoomCenter(companion: stubStore(TestClock(), tag: "raid-freeze"))
        let me = runner("나")
        var deadBoss = boss()
        deadBoss.side.hp = 0
        let animator = BattleAnimator()

        // 뷰의 `syncReplay()` 와 같은 호출. 속도는 사용자가 쓰던 기본값이다.
        func sync() {
            animator.sync(events: center.combatEvents,
                          sides: RaidArena.replaySides(center.combatFighters),
                          speed: .normal)
        }

        center.debugBeginRaidCombat(fighters: [me, boss()], tier: .five)
        sync()                                            // `.onAppear`

        // 보스를 눕히는 라운드가 도착한다.
        center.debugApplyResolvedRound(
            fighters: [me, deadBoss],
            events: [.turn(1), .damage(.fighter(RaidBoss.bossID), amount: RaidTier.five.bossHP,
                                       cause: .move), .faint(.fighter(RaidBoss.bossID))])
        sync()                                            // `.onChange`

        XCTAssertTrue(center.isBattleFinished, "보스가 죽었으면 판은 끝났다")

        // 재생이 끝날 때까지 기다린다 — 예산은 2.4초라 넉넉히 준다.
        for _ in 0..<200 where animator.playedCount < center.combatEvents.count {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(animator.playedCount, center.combatEvents.count,
                       "재생이 스트림을 못 따라잡으면 결과 화면이 영영 안 뜬다")
        XCTAssertTrue(RaidArena.showsResult(isFinished: center.isBattleFinished,
                                            playedCount: animator.playedCount,
                                            streamCount: center.combatEvents.count,
                                            isReplaying: animator.overlay.isPlaying))
    }

    /// 로그는 **재생이 소비한 만큼만** 보여 준다. 스트림 전체를 그리면 재생이 그 줄에 닿기 전에
    /// 결과가 먼저 새어 나가 재생할 이유가 없어진다(`BattleAnimator.playedCount` 주석).
    func testTheLogIsSlicedToWhatTheReplayHasPlayed() {
        let stream: [BattleEvent] = [.turn(1), .crit(.a), .turn(2), .crit(.b)]
        XCTAssertEqual(RaidArena.visibleEvents(stream, playedCount: 2), [.turn(1), .crit(.a)])
        XCTAssertEqual(RaidArena.visibleEvents(stream, playedCount: 0), [])
        // 경계 — 재생기가 스트림보다 앞서 보고할 수 있는 순간(새 배틀 전환)에도 터지면 안 된다.
        XCTAssertEqual(RaidArena.visibleEvents(stream, playedCount: 99), stream)
    }
}
