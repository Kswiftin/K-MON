import XCTest
@testable import PokeTokenBar

/// 타겟 유도 — 따라와·성원·스포트라이트가 이번 턴의 단일 타겟 공격을 자기(또는 지목한 자리)로 끌어온다.
///
/// **1대1 에서는 아무 일도 하지 않는다**(끌어올 상대가 하나뿐이다). 그래서 이 규칙은 필드에 넷이
/// 서는 두 모드 — 웨이브 런(`WaveBattle`)과 방(`MultiplayerBattle`) — 에서만 값을 가지고, 두
/// 모드가 **같은 판정**을 써야 한다. 한쪽에만 배선하면 그 모드에서만 따라와가 아무 일도 하지 않고
/// 화면에는 정상으로 보인다(입장 데미지가 정확히 그 모양으로 새어 나간 적이 있다).
final class BattleRedirectTests: XCTestCase {

    // MARK: 픽스처

    /// 한 방에 죽지 않는 개체 — 유도가 한 턴짜리라 다음 턴까지 살아 있어야 값을 잰다.
    private func snapshot(_ id: Int, hp: Int = 300, power: Int = 40, speed: Int = 100,
                          types: [PokemonType] = [.normal],
                          moves: [MoveSpec]? = nil) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "M\(id)", trainer: "T", level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: hp, atk: 80, def: 80, spa: 80, spd: 80, spe: speed),
                       moves: moves ?? [MoveSpec(id: 1, names: ["en": "Hit"], type: .normal,
                                                 power: power, damageClass: .physical,
                                                 accuracy: nil, pp: 20)])
    }

    /// 유도기 하나만 든 개체. **id 가 규칙이다** — 엔진이 데이터에 물어 이 기술을 알아본다.
    private func drawSnapshot(_ id: Int, moveID: Int, priority: Int = 2, speed: Int = 100,
                              hp: Int = 300, types: [PokemonType] = [.normal]) -> BattleSnapshot {
        var move = MoveSpec(id: moveID, names: ["en": "Draw"], type: .normal, power: 0,
                            damageClass: .status, accuracy: nil, pp: 20)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = moveID != 671            // 스포트라이트만 남을 지목한다
        move.priority = priority
        return snapshot(id, hp: hp, speed: speed, types: types, moves: [move])
    }

    private func battle(mine: [BattleSnapshot], opponents: [BattleSnapshot],
                        seed: UInt64 = 7) -> WaveBattle {
        WaveBattle(mine: mine.map(BattleSide.init), opponents: opponents.map(BattleSide.init),
                   rng: SplitMix64(seed: seed))
    }

    private func fighter(_ id: UUID, snapshot: BattleSnapshot,
                         team: BattleTeam) -> MultiplayerFighter {
        MultiplayerFighter(participant: LobbyParticipant(id: id, trainerName: "T",
                                                         speciesID: snapshot.speciesID, team: team,
                                                         isReady: true, isHost: false),
                           snapshot: snapshot)
    }

    // MARK: 데이터가 어느 기술인지 답한다

    /// 세 유도기가 각자 자기 키를 부른다 — 손 목록이면 하나가 조용히 빠진다.
    func testTheDataNamesTheMovesThatDrawAttacks() {
        for (id, expected) in [(266, BattleVolatile.followMe), (476, .ragePowder), (671, .spotlight)] {
            XCTAssertEqual(BattleVolatile.called(byMoveID: id), expected,
                           "기술 \(id) 가 유도기인 것을 엔진이 모른다")
            XCTAssertTrue(expected.drawsAttacks, "\(expected) 가 공격을 끌어오지 않는다")
        }
        XCTAssertFalse(BattleVolatile.endure.drawsAttacks, "인내는 유도기가 아니다")
    }

    /// 유도는 **한 턴짜리**다 — 무기한으로 두면 한 번 쓴 칸이 배틀 내내 모든 공격을 받는다.
    func testTheDrawLastsASingleTurn() {
        for volatileStatus in [BattleVolatile.followMe, .ragePowder, .spotlight] {
            XCTAssertEqual(volatileStatus.selfDuration, 1, "\(volatileStatus) 가 한 턴짜리가 아니다")
        }
    }

    // MARK: 웨이브 런 (2대2)

    /// 따라와를 쓴 칸이 **상대의 단일 타겟 공격 전부**를 받는다. 옆 칸은 한 대도 안 맞는다.
    func testFollowMePullsEveryFoeAttackOntoTheUserInTheWaveRun() {
        var subject = battle(mine: [snapshot(1), drawSnapshot(2, moveID: 266, speed: 400)],
                             opponents: [snapshot(90, speed: 10), snapshot(91, speed: 10)])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))

        XCTAssertEqual(subject.mine[0].hp, subject.mine[0].stats.hp,
                       "따라와를 쓴 칸이 있는데 옆 칸이 맞았다")
        XCTAssertLessThan(subject.mine[1].hp, subject.mine[1].stats.hp,
                          "따라와를 쓴 칸이 한 대도 안 맞았다")
    }

    /// 유도는 그 턴만이다 — 다음 턴의 공격은 원래 자리로 돌아간다.
    func testTheDrawIsGoneOnTheNextTurn() {
        var subject = battle(mine: [snapshot(1), drawSnapshot(2, moveID: 266, speed: 400)],
                             opponents: [snapshot(90, speed: 10), snapshot(91, speed: 10)])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertFalse(subject.mine[1].has(.followMe), "턴이 끝났는데 유도가 남아 있다")

        // 다음 턴의 공격이 어디로 가는지는 **판정 함수에 직접 묻는다.** CPU 의 타겟은 무작위라
        // "0번 칸이 맞았나" 로 재면 우연히 1번을 고른 판에서 통과해 버린다.
        var hit = MoveSpec(id: 1, names: ["en": "Hit"], type: .normal, power: 40,
                           damageClass: .physical, accuracy: nil, pp: 20)
        hit.targetsUser = false
        XCTAssertNil(BattleEngine.redirectedTarget(
            move: hit, attacker: subject.opponents[0],
            candidates: [(slot: 0, side: subject.mine[0]), (slot: 1, side: subject.mine[1])]),
                     "유도가 한 턴을 넘어 살아 다음 턴의 공격까지 끌어간다")
    }

    /// 풀 타입은 **성원의 가루를 무시한다**(본가와 같다). 따라와는 가루가 아니라 그대로 끌어온다.
    func testRagePowderDoesNotPullGrassTypesButFollowMeDoes() {
        var powder = battle(mine: [snapshot(1), drawSnapshot(2, moveID: 476, speed: 400)],
                            opponents: [snapshot(90, speed: 10, types: [.grass]),
                                        snapshot(91, speed: 10, types: [.grass])])
        XCTAssertTrue(powder.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(powder.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertLessThan(powder.mine[0].hp, powder.mine[0].stats.hp,
                          "풀 타입이 가루에 끌려갔다")

        var draw = battle(mine: [snapshot(1), drawSnapshot(2, moveID: 266, speed: 400)],
                          opponents: [snapshot(90, speed: 10, types: [.grass]),
                                      snapshot(91, speed: 10, types: [.grass])])
        XCTAssertTrue(draw.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(draw.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertEqual(draw.mine[0].hp, draw.mine[0].stats.hp,
                       "따라와는 가루가 아니라 풀 타입도 끌어온다")
    }

    /// 광역기는 끌려오지 않는다 — 원래 전원을 때리는 기술이라 끌 자리가 없다.
    func testASpreadMoveIsNotRedirected() {
        var spread = MoveSpec(id: 89, names: ["en": "Quake"], type: .normal, power: 60,
                              damageClass: .physical, accuracy: nil, pp: 20, target: "all-opponents")
        spread.targetsUser = false
        var subject = battle(mine: [snapshot(1), drawSnapshot(2, moveID: 266, speed: 400)],
                             opponents: [snapshot(90, speed: 10, moves: [spread]),
                                         snapshot(91, speed: 10, moves: [spread])])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertLessThan(subject.mine[0].hp, subject.mine[0].stats.hp,
                          "광역기가 유도에 끌려 한 자리만 때렸다")

        // **판정 함수에도 직접 묻는다.** 웨이브 런의 광역기는 유도 판정을 지나지 않는 갈래라
        // 위 단언만으로는 판정 안의 광역기 가드가 사라져도 초록이다(방은 그 가드가 유일한 문이다).
        var drawer = BattleSide(drawSnapshot(2, moveID: 266))
        XCTAssertTrue(drawer.start(.followMe, turns: 1))
        XCTAssertNil(BattleEngine.redirectedTarget(
            move: spread, attacker: BattleSide(snapshot(90)),
            candidates: [(slot: 0, side: BattleSide(snapshot(1))), (slot: 1, side: drawer)]),
                     "광역기가 유도 판정에 끌려갔다")
    }

    // MARK: 방 (2대2 팀전)

    /// 방에서도 같은 규칙이다 — 팀 동료가 쓴 따라와가 상대의 공격을 자기에게 끌어온다.
    func testFollowMePullsTheFoeAttackInTheRoom() throws {
        let ids = (0..<4).map { _ in UUID() }
        let fighters = [
            fighter(ids[0], snapshot: snapshot(1, speed: 10), team: .red),
            fighter(ids[1], snapshot: drawSnapshot(2, moveID: 266, speed: 400), team: .red),
            fighter(ids[2], snapshot: snapshot(90, speed: 50), team: .blue),
            fighter(ids[3], snapshot: snapshot(91, speed: 50), team: .blue),
        ]
        var battle = try MultiplayerBattle(fighters: fighters, mode: .teams, seed: 11)
        _ = try battle.resolveRound([
            MultiplayerAction(attackerID: ids[0], targetID: ids[2], moveIndex: 0),
            MultiplayerAction(attackerID: ids[1], targetID: ids[1], moveIndex: 0),
            MultiplayerAction(attackerID: ids[2], targetID: ids[0], moveIndex: 0),
            MultiplayerAction(attackerID: ids[3], targetID: ids[0], moveIndex: 0),
        ])
        XCTAssertEqual(battle.fighters[0].side.hp, battle.fighters[0].side.stats.hp,
                       "따라와를 쓴 동료가 있는데 지목된 참가자가 맞았다")
        XCTAssertLessThan(battle.fighters[1].side.hp, battle.fighters[1].side.stats.hp,
                          "따라와를 쓴 참가자가 한 대도 안 맞았다")
    }

    /// **개인전에는 동료가 없다** — 유도가 상대의 공격을 자기에게 끌어오면 남을 지켜 준 셈이
    /// 아니라 남의 표적을 빼앗은 것이 된다. 개인전은 각자가 한 편이므로 끌어올 편이 없다.
    func testTheDrawDoesNotReachAcrossFightersInAFreeForAll() throws {
        let ids = (0..<3).map { _ in UUID() }
        let fighters = [
            fighter(ids[0], snapshot: snapshot(1, speed: 10), team: .solo),
            fighter(ids[1], snapshot: drawSnapshot(2, moveID: 266, speed: 400), team: .solo),
            fighter(ids[2], snapshot: snapshot(90, speed: 50), team: .solo),
        ]
        var battle = try MultiplayerBattle(fighters: fighters, mode: .freeForAll, seed: 11)
        _ = try battle.resolveRound([
            MultiplayerAction(attackerID: ids[0], targetID: ids[2], moveIndex: 0),
            MultiplayerAction(attackerID: ids[1], targetID: ids[1], moveIndex: 0),
            MultiplayerAction(attackerID: ids[2], targetID: ids[0], moveIndex: 0),
        ])
        XCTAssertLessThan(battle.fighters[0].side.hp, battle.fighters[0].side.stats.hp,
                          "개인전인데 남의 유도가 공격을 가로챘다")
    }

    /// 회귀: **자기에게 거는 기술은 방에서 아예 낼 수 없었다.** 사전 검증이 "자기 자신은 못
    /// 때린다" 로 자기 지목을 거절했고, 그 문을 열자 이번엔 해상 루프가 시전 **전에** 뜬 방어측
    /// 사본으로 시전 결과를 덮어썼다(공격측·방어측이 같은 자리라서). 두 결함 모두 화면에는
    /// "기술을 썼는데 아무 일도 없다" 로만 보인다.
    func testASelfAimedMoveSurvivesTheRoundInTheRoom() throws {
        let ids = (0..<2).map { _ in UUID() }
        let fighters = [
            fighter(ids[0], snapshot: drawSnapshot(1, moveID: 164, speed: 400), team: .red),
            fighter(ids[1], snapshot: snapshot(90, speed: 10), team: .blue),
        ]
        var battle = try MultiplayerBattle(fighters: fighters, mode: .teams, seed: 3)
        _ = try battle.resolveRound([
            MultiplayerAction(attackerID: ids[0], targetID: ids[0], moveIndex: 0),
            MultiplayerAction(attackerID: ids[1], targetID: ids[0], moveIndex: 0),
        ])
        // **이벤트가 아니라 상태로 잰다.** 덮어쓰기 결함은 이벤트를 그대로 내보내고 상태만 잃는다 —
        // 로그만 보면 기술이 성공한 판과 구별되지 않는다(대타출동은 라운드를 넘어 사는 상태라
        // 한 턴짜리 유도와 달리 라운드가 끝난 뒤에도 값을 읽을 수 있다).
        XCTAssertGreaterThan(battle.fighters[0].side.substituteHP, 0,
                             "자기에게 건 기술의 결과가 라운드 안에서 사라졌다")
    }

    // MARK: 로그

    /// 유도가 붙은 줄이 **세 기술 모두** 자기 문구를 가진다 — 같으면 로그가 어느 유도인지 못 말한다.
    func testEachDrawHasItsOwnWordingInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            let lines = [BattleVolatile.followMe, .ragePowder, .spotlight]
                .map { l.battleVolatileStarted("리자몽", $0) }
            XCTAssertEqual(Set(lines).count, 3, "\(lang) 에서 유도 문구가 겹친다")
        }
    }
}
