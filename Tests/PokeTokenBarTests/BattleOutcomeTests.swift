import XCTest
@testable import PokeTokenBar

/// 승패 판정 회귀 — "이기지 않은 쪽까지 승리"를 막는 가드들.
///
/// 세 경로(1v1 연결 끊김·팀 연습/체육관·4인 방)가 각자 판정을 들고 있었고 그중 둘이 승리를 남발했다.
/// ① `connectionDropped` 이 끊김을 무조건 내 승리로 접어 와이파이 한 번 끊기면 **양쪽이 동시에** 이기고
/// 양쪽 다 판돈 ★ 과 LP 를 받았다(별의조각 총량이 늘어난다) ② `advanceFainted` 가 상대 전멸을 먼저 보고
/// `return` 해 동시 전멸(무승부)이 승리가 됐다(체육관이면 배지까지) ③ 반대로 팀전에서는 이긴 팀의
/// 쓰러진 대원이 패배로 기록됐다.
///
/// 판정은 이제 순수 함수 세 개(`BattleEngine.disconnectOutcome`·`MultiplayerBattle.outcome`/`isFinished`)로
/// 모였고, 아래 테스트가 그 함수들의 트리거 브랜치를 직접 밟는다.
final class BattleOutcomeTests: XCTestCase {

    // MARK: 픽스처

    private func snapshot(baseHP: Int = 200, speed: Int = 50, power: Int = 10) -> BattleSnapshot {
        BattleSnapshot(speciesID: 143, name: "Mon", trainer: nil, level: 50, nature: nil, isShiny: false,
                       types: [.normal],
                       base: BattleStats(hp: baseHP, atk: 60, def: 60, spa: 5, spd: 60, spe: speed),
                       moves: [MoveSpec(id: 1, names: [:], type: .normal, power: power,
                                        damageClass: .physical, accuracy: 100, pp: 30)])
    }

    private func side(baseHP: Int = 200, speed: Int = 50, hpFraction: (Int, Int) = (1, 1)) -> BattleSide {
        var side = BattleSide(snapshot(baseHP: baseHP, speed: speed))
        side.hp = side.stats.hp * hpFraction.0 / hpFraction.1
        return side
    }

    private func fighter(_ id: UUID, team: BattleTeam, alive: Bool = true) -> MultiplayerFighter {
        var fighter = MultiplayerFighter(
            participant: LobbyParticipant(id: id, trainerName: "T", speciesID: 143,
                                          team: team, isReady: true, isHost: false),
            snapshot: snapshot())
        if !alive { fighter.side.hp = 0 }
        return fighter
    }

    // MARK: 팀 연습·체육관 — 동시 전멸은 무승부다

    /// 회귀: `advanceFainted` 가 상대 전멸을 먼저 판정하고 `return` 했다 → 내 팀도 같은 턴에 전멸했는데
    /// 승리가 됐고, 체육관이면 `settlePracticeResult` 가 그 자리에서 배지를 줬다.
    ///
    /// 트리거: 내 공격이 상대 마지막 한 마리를 눕히고, 그 턴의 잔뎀이 내 마지막 한 마리를 눕힌다.
    /// `resolveTurn` 은 두 공격이 끝난 뒤 잔뎀을 넣으므로 동시 전멸이 실제로 도달 가능하다.
    func testMutualWipeInPracticeIsADrawNotAWin() {
        var battle = TeamPracticeBattle(mine: [BattleSide(snapshot())],
                                        opponents: [BattleSide(snapshot(speed: 40))],
                                        rng: SplitMix64(seed: 7))
        battle.mine[0].hp = 1
        battle.mine[0].status = .poison       // 턴 끝 잔뎀이 내 마지막 한 마리를 데려간다
        battle.opponents[0].hp = 1            // 내 공격이 상대 마지막 한 마리를 눕힌다

        XCTAssertTrue(battle.useMove(0))

        XCTAssertFalse(battle.mine[0].isAlive, "내 쪽도 전멸했다")
        XCTAssertFalse(battle.opponents[0].isAlive, "상대도 전멸했다")
        XCTAssertEqual(battle.result, .draw, "동시 전멸은 무승부다 — 승리로 접으면 체육관 배지까지 나간다")
    }

    /// 무승부를 도입하면서 승/패가 무승부로 뭉개지지 않는지 — 양방향 대조군.
    /// (한쪽만 보면 "전부 무승부"로 만들어도 위 테스트가 통과한다.)
    func testPracticeKeepsReportingPlainWinsAndLosses() {
        var win = TeamPracticeBattle(mine: [BattleSide(snapshot())],
                                     opponents: [BattleSide(snapshot(speed: 40))],
                                     rng: SplitMix64(seed: 7))
        win.opponents[0].hp = 1
        XCTAssertTrue(win.useMove(0))
        XCTAssertEqual(win.result, .win, "상대만 전멸하면 승리다")

        var loss = TeamPracticeBattle(mine: [BattleSide(snapshot(power: 0))],
                                      opponents: [BattleSide(snapshot(speed: 40))],
                                      rng: SplitMix64(seed: 7))
        loss.mine[0].hp = 1
        loss.mine[0].status = .poison
        XCTAssertTrue(loss.useMove(0))
        XCTAssertEqual(loss.result, .loss, "내 쪽만 전멸하면 패배다")
    }

    /// 연습전도 자동 출전을 스트림에 남긴다 — LAN 과 같은 규칙이다(재생기는 한 벌뿐이라,
    /// 한 엔진만 이벤트를 안 내보내면 그 모드에서만 새로 나온 개체가 이전 개체 HP 로 그려진다).
    func testPracticeRecordsTheAutomaticSendOutForTheReplay() {
        var battle = TeamPracticeBattle(mine: [BattleSide(snapshot())],
                                        opponents: [BattleSide(snapshot(power: 0)),
                                                    BattleSide(snapshot(power: 0))],
                                        rng: SplitMix64(seed: 7))
        battle.opponents[0].hp = 1
        XCTAssertTrue(battle.useMove(0))

        XCTAssertNil(battle.result, "상대가 한 마리 남았으면 배틀은 계속된다")
        XCTAssertEqual(battle.opponentActive, 1)
        XCTAssertEqual(battle.events.last, .sendOut(.b, teamIndex: 1),
                       "출전은 기절 뒤다 — 앞에 두면 기절이 새 개체에 그려진다")
    }

    /// 연습전 교체도 출전을 남기고, 그 출전은 **턴 머리 다음·상대 공격 앞**이다.
    /// 뒤에 두면 재생이 이전 개체에 남의 데미지를 그린다.
    func testPracticeSwitchRecordsTheSendOutBeforeTheOpponentAttacks() {
        var battle = TeamPracticeBattle(mine: [BattleSide(snapshot(power: 0)),
                                               BattleSide(snapshot(power: 0))],
                                        opponents: [BattleSide(snapshot(speed: 200, power: 80))],
                                        rng: SplitMix64(seed: 7))
        XCTAssertTrue(battle.switchMine(to: 1))

        XCTAssertEqual(battle.events.first, BattleEvent.turn(1), "턴 머리가 빠지면 로그에 턴 구분이 없다")
        XCTAssertEqual(battle.events.dropFirst().first, BattleEvent.sendOut(.a, teamIndex: 1))
        let damage = battle.events.firstIndex { if case .damage(.a, _, _) = $0 { return true } else { return false } }
        XCTAssertNotNil(damage, "교체해 들어온 쪽이 맞지 않으면 순서를 볼 수 없다")
        XCTAssertGreaterThan(damage ?? -1, 1, "출전이 데미지 뒤면 이전 개체가 남의 데미지를 맞는다")
    }

    /// 전멸 판정을 앞으로 당기면서 슬롯 교대가 죽지 않았는지 — 상대 한 마리가 쓰러지고 다음이
    /// 남아 있으면 배틀은 계속되고 활성 슬롯만 넘어간다(체육관은 상대가 3마리다).
    func testFaintedOpponentSlotAdvancesWhileTheTeamStillStands() {
        var battle = TeamPracticeBattle(mine: [BattleSide(snapshot())],
                                        opponents: [BattleSide(snapshot(speed: 40)),
                                                    BattleSide(snapshot(speed: 40))],
                                        rng: SplitMix64(seed: 7))
        battle.opponents[0].hp = 1

        XCTAssertTrue(battle.useMove(0))

        XCTAssertFalse(battle.opponents[0].isAlive)
        XCTAssertEqual(battle.opponentActive, 1, "다음 상대가 나온다")
        XCTAssertNil(battle.result, "한 마리 남았으므로 승부는 안 났다")
    }

    // MARK: 1v1 연결 끊김 — 양쪽이 동시에 이길 수 없다

    /// 회귀(별의조각이 늘어나던 자리): 끊김을 `iWon: true` 로 접었다. 네트워크가 죽으면 두 피어가
    /// 각자 몰수승을 선언하고 각자 `settleRankedBrawl(won: true)` 로 판돈과 +25 LP 를 받았다.
    ///
    /// 두 피어는 같은 배틀 상태를 보고 있으므로 판정을 상태에서 뽑으면 결론이 **서로 반대**여야 한다.
    /// 같은 상태를 me/opp 만 뒤집어 넣어 그걸 단언한다.
    func testDisconnectNeverHandsBothPeersAWin() {
        let leading = side(hpFraction: (4, 5)), trailing = side(hpFraction: (2, 5))

        let fromLeader = BattleEngine.disconnectOutcome(me: leading, opp: trailing)
        let fromTrailer = BattleEngine.disconnectOutcome(me: trailing, opp: leading)

        XCTAssertEqual(fromLeader, true, "HP 가 앞선 쪽이 이긴다")
        XCTAssertEqual(fromTrailer, false, "뒤진 쪽이 진다 — 네트워크를 끊어도 이득이 없다")
        XCTAssertFalse(fromLeader == true && fromTrailer == true, "양쪽이 동시에 이길 수는 없다")
    }

    /// 동률은 무효(nil) — 호출부가 이 nil 로 랭크·판돈 정산을 건너뛴다.
    func testDisconnectAtEqualFootingIsANoContest() {
        XCTAssertNil(BattleEngine.disconnectOutcome(me: side(hpFraction: (1, 2)),
                                                    opp: side(hpFraction: (1, 2))))
        // 최대 HP 가 다른 두 종이 둘 다 한 대도 안 맞았으면 비율은 정확히 같다(첫 턴에 끊긴 경우).
        // 절대값 비교였다면 덩치 큰 쪽이 이겼을 자리다.
        XCTAssertNil(BattleEngine.disconnectOutcome(me: side(baseHP: 200), opp: side(baseHP: 60)),
                     "최대 HP 가 달라도 비율이 같으면 무효다 — 시작하자마자 끊기면 아무도 이기지 않는다")
    }

    /// 판정은 남은 HP **비율**이다. 절대값으로 비교하면 덩치 큰 종이 항상 이긴다.
    func testDisconnectComparesRatiosNotRawHitPoints() {
        let small = side(baseHP: 60, hpFraction: (9, 10))     // 비율 0.9, 절대값은 작다
        let big = side(baseHP: 200, hpFraction: (1, 2))       // 비율 0.5, 절대값은 크다
        XCTAssertLessThan(small.hp, big.hp, "픽스처 전제: 절대값은 작은 쪽이 적다")

        XCTAssertEqual(BattleEngine.disconnectOutcome(me: small, opp: big), true)
        XCTAssertEqual(BattleEngine.disconnectOutcome(me: big, opp: small), false)
    }

    // MARK: 4인 방 — 이긴 팀의 쓰러진 대원도 승자다

    /// 회귀(반대 방향): 팀전 승패를 내 생존으로만 봤다. 팀이 이겼는데 내가 쓰러졌으면 패배 기록이 남았다.
    func testTeamsOutcomeCountsFallenTeammatesAsWinners() {
        let survivor = UUID(), fallenAlly = UUID(), enemy1 = UUID(), enemy2 = UUID()
        let fighters = [fighter(survivor, team: .red), fighter(fallenAlly, team: .red, alive: false),
                        fighter(enemy1, team: .blue, alive: false), fighter(enemy2, team: .blue, alive: false)]

        XCTAssertTrue(MultiplayerBattle.isFinished(fighters: fighters, mode: .teams))
        XCTAssertEqual(MultiplayerBattle.outcome(for: survivor, fighters: fighters, mode: .teams), .win)
        XCTAssertEqual(MultiplayerBattle.outcome(for: fallenAlly, fighters: fighters, mode: .teams), .win,
                       "이긴 팀의 쓰러진 대원도 이긴 것이다")
        XCTAssertEqual(MultiplayerBattle.outcome(for: enemy1, fighters: fighters, mode: .teams), .loss)
        XCTAssertEqual(Set(MultiplayerBattle.winners(fighters: fighters, mode: .teams)),
                       [survivor, fallenAlly], "winningIDs 도 같은 규칙을 쓴다")
    }

    /// 개인전은 마지막 하나만 승자다 — 팀 규칙이 개인전으로 새면 전원 승리가 된다.
    func testFreeForAllOutcomeIsWinOnlyForTheLastOneStanding() {
        let alive = UUID(), dead1 = UUID(), dead2 = UUID()
        let fighters = [fighter(alive, team: .solo), fighter(dead1, team: .solo, alive: false),
                        fighter(dead2, team: .solo, alive: false)]

        XCTAssertEqual(MultiplayerBattle.outcome(for: alive, fighters: fighters, mode: .freeForAll), .win)
        XCTAssertEqual(MultiplayerBattle.outcome(for: dead1, fighters: fighters, mode: .freeForAll), .loss)
        XCTAssertEqual(MultiplayerBattle.winners(fighters: fighters, mode: .freeForAll), [alive])
    }

    /// 방에서도 동시 전멸은 아무도 이기지 않았다 — 개인전·팀전 양쪽에서.
    func testMutualWipeInARoomIsADrawForEveryone() {
        let a = UUID(), b = UUID()
        let solo = [fighter(a, team: .solo, alive: false), fighter(b, team: .solo, alive: false)]
        XCTAssertEqual(MultiplayerBattle.outcome(for: a, fighters: solo, mode: .freeForAll), .draw)
        XCTAssertTrue(MultiplayerBattle.winners(fighters: solo, mode: .freeForAll).isEmpty)

        let teams = [fighter(a, team: .red, alive: false), fighter(b, team: .blue, alive: false)]
        XCTAssertEqual(MultiplayerBattle.outcome(for: b, fighters: teams, mode: .teams), .draw)
    }

    // MARK: 판정의 근거는 불변이어야 한다 — 모드가 배틀 중에 바뀌면 안 된다

    /// 회귀(끊김과 무관한 두 번째 "동시 승리" 경로): 방 판정이 `lobby.mode` 를 봤다. 그 값은 팀 편성에서
    /// 파생되는 **가변값**이라(`runners` 가 전부 `solo` 인가) 배틀 중에도 바뀌었고, 편성 메시지에는
    /// phase 게이트가 없었다.
    ///
    /// 개인전 도중 한 명이 팀을 `red` 로 바꾸고 그 사람이 쓰러지면, 남은 `solo` 들이 "한 팀"으로 묶여
    /// **여럿이 살아 있는데 배틀이 끝난 것으로 판정**되고 생존자 전원이 승리가 된다. 아래는 그 판정
    /// 민감도를 고정한다 — 같은 전투원 목록이 모드에 따라 정반대로 읽힌다.
    func testTheSameFightersReadOppositelyUnderTheWrongMode() {
        let a = UUID(), b = UUID(), dead = UUID()
        let fighters = [fighter(a, team: .solo), fighter(b, team: .solo),
                        fighter(dead, team: .red, alive: false)]

        XCTAssertFalse(MultiplayerBattle.isFinished(fighters: fighters, mode: .freeForAll),
                       "개인전이면 둘이 살아 있으므로 아직 안 끝났다")
        XCTAssertTrue(MultiplayerBattle.isFinished(fighters: fighters, mode: .teams),
                      "팀전으로 읽으면 살아 있는 둘이 같은 팀이라 끝난 것으로 보인다")
        XCTAssertEqual(MultiplayerBattle.outcome(for: a, fighters: fighters, mode: .teams), .win)
        XCTAssertEqual(MultiplayerBattle.outcome(for: b, fighters: fighters, mode: .teams), .win,
                       "그래서 잘못된 모드로 판정하면 생존자 전원이 승리가 된다")
        XCTAssertNil(MultiplayerBattle.outcome(for: a, fighters: fighters, mode: .freeForAll),
                     "바른 모드에서는 승패가 아직 없다")
    }

    /// 그래서 판정은 **배틀 시작 시점에 고정된** 모드를 봐야 한다. `MultiplayerBattle.mode` 가 `let` 이고
    /// 호스트·게스트·관전자 모두 `.start` 로 같은 값을 받으므로, 그 값이 유일한 근거다.
    ///
    /// 소스 스캔으로 고정한다 — `MultiplayerRoomCenter` 는 `@MainActor` + 리스너 소유라 테스트에서
    /// 인스턴스를 세울 수 없고, 여기서 막고 싶은 건 "판정이 어느 값을 먼저 보는가"라는 한 줄이다.
    func testTheRoomTakesItsVerdictModeFromTheBattleNotTheLobby() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeTokenBar/Core/MultiplayerRoomCenter.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("battle?.mode ?? lobby?.mode"),
                      "판정 모드는 배틀에서 먼저 가져와야 한다 — `lobby?.mode` 를 먼저 보면 배틀 중 편성 변경이 승패를 바꾼다")
        // 편성 메시지·로컬 조작 양쪽에 게이트가 있어야 한다. 화면에서 버튼을 감추는 것만으로는
        // 상대가 보내오는 `.team` 메시지를 막지 못한다.
        // 하한으로 단언한다 — 정확히 2 로 고정하면 게이트를 **더** 다는 정상 변경이 테스트를 깨고,
        // 여기서 지키고 싶은 건 "두 수신 경로가 게이트 뒤에 있다"뿐이다.
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: "!self.isInPlay").count - 1, 2,
                                    "`.ready`·`.team` 수신 두 곳이 경기 중에는 편성을 받지 않아야 한다")
        XCTAssertTrue(source.contains("guard let me = myParticipant, !isInPlay"),
                      "내가 누르는 준비 토글도 경기 중에는 막힌다")
        XCTAssertTrue(source.contains("guard !isInPlay, lobby?.mode == .teams"),
                      "내가 고르는 팀도 경기 중에는 막힌다")
    }

    /// 방 결과 화면은 승/패/무/관전 **네 갈래**다. 예전엔 `didIWin` 하나로 갈라 무승부(동시 전멸)와
    /// 관전자에게 "패배"라고 말했다 — 관전자는 싸우지도 않았고, 무승부는 진 게 아니다.
    func testTheRoomResultCoversDrawAndSpectators() throws {
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L(lang).battleSpectatorFinished.isEmpty, "\(lang) 문구가 있어야 한다")
        }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // 방 배틀 화면은 `RoomBattleView` 로 떼어냈다(#209) — 스캔 대상도 함께 옮긴다.
        let view = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeTokenBar/UI/RoomBattleView.swift"), encoding: .utf8)

        XCTAssertTrue(view.contains("center.multiplayer.myOutcome"),
                      "방 결과는 네 갈래 `myOutcome` 을 쓴다")
        XCTAssertFalse(view.contains("didIWin"),
                       "두 갈래 판정으로 돌아가면 관전자·무승부가 다시 패배로 표시된다")
        XCTAssertFalse(view.contains("battleReward"),
                       "주지 않는 보상을 표시하지 않는다")
    }

    /// 관전자(전투원이 아닌 참가자)와 진행 중인 배틀은 `nil` — 호출부가 이 nil 로 기록·보상을 건너뛴다.
    /// 예전엔 관전자도 라운드 브로드캐스트마다 `grantRewardIfFinished` 를 타 패배 기록이 남았다.
    func testOutcomeIsNilForSpectatorsAndForUnfinishedBattles() {
        let alive = UUID(), dead = UUID(), spectator = UUID()
        let finished = [fighter(alive, team: .solo), fighter(dead, team: .solo, alive: false)]

        XCTAssertNil(MultiplayerBattle.outcome(for: spectator, fighters: finished, mode: .freeForAll),
                     "전투원이 아니면 승패가 없다")

        let ongoing = [fighter(alive, team: .solo), fighter(dead, team: .solo)]
        XCTAssertFalse(MultiplayerBattle.isFinished(fighters: ongoing, mode: .freeForAll))
        XCTAssertNil(MultiplayerBattle.outcome(for: alive, fighters: ongoing, mode: .freeForAll),
                     "아직 안 끝난 배틀엔 승패가 없다")
        XCTAssertTrue(MultiplayerBattle.winners(fighters: ongoing, mode: .freeForAll).isEmpty,
                      "안 끝난 배틀엔 승자가 없다")

        // 배틀 시작 전 — `combatFighters` 가 빈 배열이다. 여기서 "끝났다"가 나오면 방에 들어서는
        // 순간 결과 화면이 뜬다.
        XCTAssertFalse(MultiplayerBattle.isFinished(fighters: [], mode: .freeForAll))
        XCTAssertNil(MultiplayerBattle.outcome(for: alive, fighters: [], mode: .freeForAll),
                     "전투원 목록이 비어 있으면(배틀 전) 승패가 없다")
    }
}
