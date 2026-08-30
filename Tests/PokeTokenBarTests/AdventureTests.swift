import XCTest
@testable import PokeTokenBar

final class AdventureTests: XCTestCase {
    func testLegacyIntegrityVersionDoesNotResetOnSchemaUpgrade() {
        var state = CompanionState()
        state.integrityVersion = 0
        state.integrity = "old-canonical-signature"
        XCTAssertFalse(SaveTransfer.isTampered(state))
        let signed = SaveTransfer.signed(state)
        XCTAssertEqual(signed.integrityVersion, SaveTransfer.integrityVersion)
        XCTAssertFalse(SaveTransfer.isTampered(signed))
    }

    func testAdventureProgressAndRewardAreDeterministic() {
        let start = Date(timeIntervalSince1970: 1_000)
        let run = AdventureRun(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                               zone: .forest, startedAt: start,
                               endsAt: start.addingTimeInterval(600), companionSpeciesID: 25)
        XCTAssertEqual(run.progress(at: start.addingTimeInterval(300)), 0.5)
        XCTAssertFalse(run.isComplete(at: start.addingTimeInterval(599)))
        XCTAssertTrue(run.isComplete(at: start.addingTimeInterval(600)))
        XCTAssertEqual(AdventureRules.reward(for: run), AdventureRules.reward(for: run))
        XCTAssertGreaterThan(AdventureRules.reward(for: run).stardust, 0)
    }

    func testLobbySupportsAtMostFourAndRequiresEveryoneReady() throws {
        func player(_ n: Int, ready: Bool = false) -> LobbyParticipant {
            LobbyParticipant(id: UUID(), trainerName: "P\(n)", speciesID: n,
                             team: .solo, isReady: ready, isHost: false)
        }
        let host = player(1, ready: true)
        var lobby = try MultiplayerLobby(host: host)
        let p2 = player(2, ready: true), p3 = player(3, ready: true), p4 = player(4, ready: true)
        try lobby.join(p2); try lobby.join(p3); try lobby.join(p4)
        XCTAssertTrue(lobby.canStart)
        XCTAssertThrowsError(try lobby.join(player(5))) { XCTAssertEqual($0 as? LobbyError, .runnersFull) }
    }

    func testTeamLobbyRequiresTwoVersusTwo() throws {
        func player(_ n: Int, _ team: BattleTeam) -> LobbyParticipant {
            LobbyParticipant(id: UUID(), trainerName: "P\(n)", speciesID: n,
                             team: team, isReady: true, isHost: false)
        }
        let host = player(1, .red)
        var lobby = try MultiplayerLobby(host: host)
        try lobby.join(player(2, .red)); try lobby.join(player(3, .blue))
        XCTAssertFalse(lobby.canStart)
        try lobby.join(player(4, .blue))
        XCTAssertTrue(lobby.canStart)
        XCTAssertEqual(lobby.mode, .teams)
    }

    func testFourPlayerRoundResolvesInSpeedOrderAndIsDeterministic() throws {
        let ids = (1...4).map { _ in UUID() }
        func fighter(_ index: Int) -> MultiplayerFighter {
            // **id 는 음수로 둔다.** 양수는 PokéAPI 의 실제 기술 번호라, 지어낸 값이 우연히
            // 특수 기술과 겹친다 — 예전 `10 + index` 는 12 에서 조르기(일격필살)에 걸려
            // 한 명이 첫 라운드에 쓰러졌고, 그 대상의 공격이 통째로 건너뛰어졌다.
            // 앱의 합성 기술도 같은 이유로 음수를 쓴다(`MoveSpec.fallbackSet`·`struggle`).
            let move = MoveSpec(id: -(10 + index), names: [:], type: .normal, power: 40,
                                damageClass: .physical, accuracy: 100, pp: 20)
            let snapshot = BattleSnapshot(speciesID: index, name: "M\(index)", trainer: "P\(index)",
                                          level: 20, nature: nil, isShiny: false, types: [.normal],
                                          base: BattleStats(hp: 80, atk: 60, def: 60, spa: 60, spd: 60,
                                                            spe: 400 + index), moves: [move])
            return MultiplayerFighter(participant: LobbyParticipant(id: ids[index - 1], trainerName: "P\(index)",
                                                                      speciesID: index, team: .solo,
                                                                      isReady: true, isHost: index == 1),
                                      snapshot: snapshot)
        }
        let fighters = (1...4).map(fighter)
        let actions = (0..<4).map { i in
            MultiplayerAction(attackerID: ids[i], targetID: ids[(i + 1) % 4], moveIndex: 0)
        }
        var first = try MultiplayerBattle(fighters: fighters, mode: .freeForAll, seed: 77)
        var second = try MultiplayerBattle(fighters: fighters, mode: .freeForAll, seed: 77)
        let a = try first.resolveRound(actions), b = try second.resolveRound(actions)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.moveActors.count, 4, "네 명이 각자 한 번 행동한다")
        XCTAssertEqual(a.first, .turn(1), "라운드 번호가 스트림 앞에 온다")
        XCTAssertEqual(first.round, 2)
    }

    /// 기술 1개(위력 40 / PP 20)만 든 파이터 — 스피드로 라운드 순서를 고정한다.
    private func soloMoveFighter(_ id: UUID, speed: Int) -> MultiplayerFighter {
        let move = MoveSpec(id: 1, names: [:], type: .normal, power: 40,
                            damageClass: .physical, accuracy: 100, pp: 20)
        let snapshot = BattleSnapshot(speciesID: 1, name: "Mon", trainer: nil, level: 20,
                                      nature: nil, isShiny: false, types: [.normal],
                                      base: BattleStats(hp: 80, atk: 60, def: 60, spa: 60,
                                                        spd: 60, spe: speed),
                                      moves: [move])
        return MultiplayerFighter(participant: LobbyParticipant(id: id, trainerName: "T", speciesID: 1,
                                                                 team: .solo, isReady: true, isHost: false),
                                  snapshot: snapshot)
    }

    /// 상대가 보내오는 `pp` 는 `moves` 와 길이가 맞는다는 보장이 없다. 예전 사전 검증은 무브셋
    /// 인덱스만 봤고, 해상 루프가 `pp[moveIndex]` 를 그대로 읽어 **인덱스 범위를 벗어났다**(거절이
    /// 아니라 크래시다). 이제 경계에서 둘을 같이 본다.
    func testResolveRoundRejectsFighterWhosePPArrayIsTooShort() throws {
        let attackerID = UUID(), targetID = UUID()
        var attacker = soloMoveFighter(attackerID, speed: 100)
        attacker.side.pp = []                    // 무브셋은 1개인데 pp 는 0개
        let target = soloMoveFighter(targetID, speed: 10)
        var battle = try MultiplayerBattle(fighters: [attacker, target], mode: .freeForAll, seed: 3)

        XCTAssertThrowsError(try battle.resolveRound([
            MultiplayerAction(attackerID: attackerID, targetID: targetID, moveIndex: 0),
            MultiplayerAction(attackerID: targetID, targetID: attackerID, moveIndex: 0),
        ])) { XCTAssertEqual($0 as? MultiplayerBattleError, .invalidMove) }
    }

    /// 회귀: PP 검증이 **해상 루프 안**에 있었다(사전 검증 루프는 인덱스만 봤다). 남지 않은 기술을
    /// 지목한 액션이 섞여 있으면 그보다 순서가 앞선 공격은 이미 적용된 뒤에 throw 가 난다.
    /// `mutating` 메서드는 throw 해도 그때까지의 변경이 호출자에게 남으므로 라운드가 반쯤 적용된
    /// 상태가 된다. 호스트(`finishRoundIfReady`)는 그 라운드를 통째로 버리면서 턴 타이머를 다시
    /// 걸지 않으니(`scheduleTurnTimeout()` 은 성공 경로에만 있다) 방의 진행이 멈춘다.
    /// 상대가 보내오는 액션은 신뢰 경계 밖이라 이 조건은 원격에서 만들 수 있다.
    func testResolveRoundRejectsSpentMoveBeforeAnyDamage() throws {
        let fastID = UUID(), slowID = UUID()
        // 빠른 쪽이 먼저 때리고, 느린 쪽의 규칙 위반 액션은 그 뒤에 걸린다(부분 적용이 드러나는 순서).
        let fast = soloMoveFighter(fastID, speed: 200)
        var slow = soloMoveFighter(slowID, speed: 10)
        slow.side.pp[0] = 0
        var battle = try MultiplayerBattle(fighters: [fast, slow], mode: .freeForAll, seed: 7)
        let fullHP = battle.fighters.map(\.side.hp)

        XCTAssertThrowsError(try battle.resolveRound([
            MultiplayerAction(attackerID: fastID, targetID: slowID, moveIndex: 0),
            MultiplayerAction(attackerID: slowID, targetID: fastID, moveIndex: 0),
        ])) { XCTAssertEqual($0 as? MultiplayerBattleError, .invalidMove) }

        XCTAssertEqual(battle.fighters.map(\.side.hp), fullHP, "거절된 라운드는 데미지를 남기지 않는다")
        XCTAssertEqual(battle.fighters.first { $0.id == fastID }?.side.pp, [20], "PP 도 소모되지 않는다")
        XCTAssertTrue(battle.events.isEmpty, "버려진 라운드의 이벤트가 남으면 안 된다")
    }

    /// `MultiplayerFighter` 의 JSON 모양은 와이어 계약이다. 배틀 상태를 내부에서 어떻게 묶든 키는
    /// 평면으로 남는다. 키가 늘거나 줄면 고칠 것은 테스트가 아니라 `protocolVersion` 이다 —
    /// 상태이상(protocolVersion 4)이 status 3종을 더했다.
    func testMultiplayerFighterWireShapeStaysFlat() throws {
        let id = UUID()
        let snapshot = BattleSnapshot(speciesID: 25, name: "Pika", trainer: "T", level: 50, nature: nil,
                                      isShiny: false, types: [.electric],
                                      base: BattleStats(hp: 35, atk: 55, def: 40, spa: 50, spd: 50, spe: 90),
                                      moves: [MoveSpec(id: 85, names: [:], type: .electric, power: 90,
                                                       damageClass: .special, accuracy: 100, pp: 15)])
        var fighter = MultiplayerFighter(participant: LobbyParticipant(id: id, trainerName: "T", speciesID: 25,
                                                                        team: .solo, isReady: true, isHost: true),
                                        snapshot: snapshot)
        fighter.side.hp = 42
        fighter.side.pp = [7]
        var rng = SplitMix64(seed: 3)
        BattleEngine.inflict(.toxic, on: &fighter.side, actor: .fighter(id), rng: &rng)
        let encoded = try JSONEncoder().encode(fighter)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual(Set(json?.keys.sorted() ?? []),
                       ["id", "trainerName", "team", "snapshot", "hp", "pp",
                        "status", "statusCounter", "confusionTurns", "stages"])
        XCTAssertEqual(json?["hp"] as? Int, 42)
        XCTAssertEqual(json?["pp"] as? [Int], [7])
        XCTAssertEqual(json?["status"] as? String, "toxic")
        // 왕복 — 받은 쪽이 hp/pp/상태를 복원한다(스냅샷 기본값으로 되돌아가지 않는다).
        XCTAssertEqual(try JSONDecoder().decode(MultiplayerFighter.self, from: encoded), fighter)

        // 상태가 없으면 `status` 키 자체가 나가지 않는다 — 배지를 그릴 때 "없음"과 구분된다.
        var healthy = fighter
        healthy.side.status = nil
        let healthyJSON = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(healthy)) as? [String: Any]
        XCTAssertNil(healthyJSON?["status"])
    }

    // MARK: 멀티 턴 순서 — 우선도 → 스피드 → 무작위

    /// 스피드가 같은 두 명. UUID 를 사전순 양 끝으로 고정해 "UUID 로 갈리는지" 를 직접 본다.
    private func tiedSpeedFighters(priorities: [Int?]) -> ([UUID], [MultiplayerFighter]) {
        let ids = [UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                   UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!]
        let fighters = ids.indices.map { index in
            let move = MoveSpec(id: 10 + index, names: [:], type: .normal, power: 40,
                                damageClass: .physical, accuracy: 100, pp: 20,
                                priority: priorities[index])
            let snapshot = BattleSnapshot(speciesID: index + 1, name: "M\(index)", trainer: "P\(index)",
                                          level: 20, nature: nil, isShiny: false, types: [.normal],
                                          base: BattleStats(hp: 80, atk: 60, def: 60, spa: 60, spd: 60,
                                                            spe: 100), moves: [move])
            return MultiplayerFighter(participant: LobbyParticipant(id: ids[index], trainerName: "P\(index)",
                                                                    speciesID: index + 1, team: .solo,
                                                                    isReady: true, isHost: index == 0),
                                      snapshot: snapshot)
        }
        return (ids, fighters)
    }

    /// 회귀: 동률을 `attackerID.uuidString` 순으로 갈랐다. 앱을 켠 동안 사전순으로 앞선 참가자가
    /// 동률 때마다 선공을 가져가는데, 실력과 무관한 데다 화면에 드러나지도 않는다.
    /// 이제 무작위로 갈리므로 시드를 바꾸면 양쪽 모두 선공을 잡는다.
    func testTiedSpeedDoesNotAlwaysFavourTheSmallerUUID() throws {
        let (ids, fighters) = tiedSpeedFighters(priorities: [nil, nil])
        let actions = [MultiplayerAction(attackerID: ids[0], targetID: ids[1], moveIndex: 0),
                       MultiplayerAction(attackerID: ids[1], targetID: ids[0], moveIndex: 0)]
        var firstAttackers = Set<BattleActor>()
        for seed in UInt64(0)..<40 {
            var battle = try MultiplayerBattle(fighters: fighters, mode: .freeForAll, seed: seed)
            if let first = try battle.resolveRound(actions).moveActors.first { firstAttackers.insert(first) }
        }
        XCTAssertEqual(firstAttackers, Set(ids.map(BattleActor.fighter)),
                       "두 참가자 모두 선공을 잡는 시드가 있어야 한다")
    }

    /// 무작위로 갈려도 **같은 시드면 같은 순서**여야 한다 — 두 피어가 각자 계산하는 구조라
    /// 이게 깨지면 곧 desync 다. tie-break 난수를 정렬 비교 안에서 뽑으면 비교 횟수에 딸려가 깨진다.
    func testTiedSpeedOrderStaysDeterministicForTheSameSeed() throws {
        let (ids, fighters) = tiedSpeedFighters(priorities: [nil, nil])
        let actions = [MultiplayerAction(attackerID: ids[0], targetID: ids[1], moveIndex: 0),
                       MultiplayerAction(attackerID: ids[1], targetID: ids[0], moveIndex: 0)]
        var left = try MultiplayerBattle(fighters: fighters, mode: .freeForAll, seed: 4_242)
        var right = try MultiplayerBattle(fighters: fighters, mode: .freeForAll, seed: 4_242)
        XCTAssertEqual(try left.resolveRound(actions), try right.resolveRound(actions))
    }

    /// 멀티의 순서 계산도 마비를 본다. 1v1 만 `effectiveSpeed` 로 고치고 여기를 `stats.spe` 로 두면
    /// **같은 상태가 모드마다 다르게 굴러간다** — 이 계획이 상태를 `BattleSide` 하나로 모은 것이
    /// 바로 이렇게 조용히 갈라지는 걸 막기 위해서다. 스피드가 동률인 두 참가자로 잡아 마비만
    /// 차이가 되게 한다.
    func testParalysisSlowsTheAttackerInMultiplayerToo() throws {
        let (ids, fighters) = tiedSpeedFighters(priorities: [nil, nil])
        let actions = [MultiplayerAction(attackerID: ids[0], targetID: ids[1], moveIndex: 0),
                       MultiplayerAction(attackerID: ids[1], targetID: ids[0], moveIndex: 0)]
        // 마비 전에는 이쪽이 확실히 빠르다 — 순서가 뒤집히는 게 마비 때문임을 못 박는다.
        var paralyzed = fighters
        paralyzed[0].side.snapshot.base.spe = 200
        paralyzed[0] = MultiplayerFighter(
            participant: LobbyParticipant(id: ids[0], trainerName: "P0", speciesID: 1,
                                          team: .solo, isReady: true, isHost: true),
            snapshot: paralyzed[0].side.snapshot)
        XCTAssertGreaterThan(paralyzed[0].side.stats.spe, paralyzed[1].side.stats.spe)

        // 대조군 — 마비가 없으면 빠른 쪽이 선공이다.
        var healthy = try MultiplayerBattle(fighters: paralyzed, mode: .freeForAll, seed: 1)
        XCTAssertEqual(try healthy.resolveRound(actions).moveActors.first, .fighter(ids[0]))

        paralyzed[0].side.status = .paralysis
        XCTAssertLessThan(paralyzed[0].side.effectiveSpeed, paralyzed[1].side.effectiveSpeed)
        for seed in UInt64(0)..<20 {
            var battle = try MultiplayerBattle(fighters: paralyzed, mode: .freeForAll, seed: seed)
            XCTAssertEqual(try battle.resolveRound(actions).moveActors.first, .fighter(ids[1]),
                           "seed \(seed): 마비된 쪽이 후공이어야 한다")
        }
    }

    /// 턴 끝 잔뎀도 멀티에 있어야 한다 — 1v1 에만 넣으면 같은 화상이 방에서는 아무 일도 하지 않는다.
    func testResidualDamageAlsoRunsAtTheEndOfAMultiplayerRound() throws {
        let (ids, fighters) = tiedSpeedFighters(priorities: [nil, nil])
        var burning = fighters
        burning[0].side.status = .burn
        var battle = try MultiplayerBattle(fighters: burning, mode: .freeForAll, seed: 3)

        let events = try battle.resolveRound(
            [MultiplayerAction(attackerID: ids[0], targetID: ids[1], moveIndex: 0),
             MultiplayerAction(attackerID: ids[1], targetID: ids[0], moveIndex: 0)])

        XCTAssertTrue(events.contains { event in
            if case .damage(.fighter(ids[0]), _, .burn) = event { return true } else { return false }
        }, "화상 잔뎀이 라운드 끝에 실려야 한다")
        XCTAssertFalse(events.contains { event in
            if case .damage(.fighter(ids[1]), _, .burn) = event { return true } else { return false }
        }, "화상이 없는 쪽은 깎이지 않는다")
    }

    /// 멀티도 1v1 과 같은 규칙이다 — 우선도가 스피드·UUID 보다 앞선다.
    /// 여기서는 스피드가 같으므로 우선도 +1 을 든 두 번째 참가자가 항상 먼저다.
    func testPriorityOutranksTheTieBreakInMultiplayer() throws {
        let (ids, fighters) = tiedSpeedFighters(priorities: [nil, 1])
        let actions = [MultiplayerAction(attackerID: ids[0], targetID: ids[1], moveIndex: 0),
                       MultiplayerAction(attackerID: ids[1], targetID: ids[0], moveIndex: 0)]
        for seed in UInt64(0)..<20 {
            var battle = try MultiplayerBattle(fighters: fighters, mode: .freeForAll, seed: seed)
            XCTAssertEqual(try battle.resolveRound(actions).moveActors.first, .fighter(ids[1]),
                           "seed \(seed): 우선도 +1 이 먼저 나가야 한다")
        }
    }

    func testTeamBattleRejectsFriendlyFire() throws {
        func fighter(_ id: UUID, team: BattleTeam) -> MultiplayerFighter {
            let snapshot = BattleSnapshot(speciesID: 25, name: "Pika", trainer: nil, level: 10,
                                          nature: nil, isShiny: false, types: [.electric],
                                          base: BattleStats(hp: 50, atk: 50, def: 50, spa: 50, spd: 50, spe: 50))
            return MultiplayerFighter(participant: LobbyParticipant(id: id, trainerName: "P", speciesID: 25,
                                                                      team: team, isReady: true, isHost: false),
                                      snapshot: snapshot)
        }
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var battle = try MultiplayerBattle(fighters: [fighter(a, team: .red), fighter(b, team: .red),
                                                       fighter(c, team: .blue), fighter(d, team: .blue)],
                                           mode: .teams, seed: 1)
        let bad = [MultiplayerAction(attackerID: a, targetID: b, moveIndex: 0),
                   MultiplayerAction(attackerID: b, targetID: c, moveIndex: 0),
                   MultiplayerAction(attackerID: c, targetID: a, moveIndex: 0),
                   MultiplayerAction(attackerID: d, targetID: a, moveIndex: 0)]
        XCTAssertThrowsError(try battle.resolveRound(bad)) {
            XCTAssertEqual($0 as? MultiplayerBattleError, .invalidTarget)
        }
    }

    func testMultiplayerWireMessageRoundTrips() throws {
        let id = UUID()
        let message = MultiplayerWireMessage.ready(participantID: id, ready: true)
        let data = try JSONEncoder().encode(message)
        XCTAssertEqual(try JSONDecoder().decode(MultiplayerWireMessage.self, from: data), message)
        // 3 = 라운드 결과가 타입된 이벤트 스트림. 버전을 올려야 옛 빌드가 레이스·배틀 중간이
        // 아니라 핸드셰이크에서 거절된다 — 값을 바꿀 땐 그 거절 동작도 같이 확인한다.
        // 5 = 랭크(파이터에 stages 필드, 스트림에 `.boost` case), 6 = 방 채팅, 7 = 포켓몬 OX 퀴즈,
        // 8 = 드레인·반동·다단·풀린치, 9 = 특성(스냅샷에 ability 필드),
        // 11 = 토너먼트 팀·대진·관전 상태 동기화, 12 = 공유 체육관(도전·거절·상태·행동·승계).
        XCTAssertEqual(MultiplayerWireMessage.protocolVersion, 12)
    }

    /// 라운드 결과는 호스트가 게스트에게 **브로드캐스트**하는 유일한 배틀 페이로드다. 이벤트가
    /// 타입된 스트림이 되면서 이 JSON 모양이 바뀌었으므로(그래서 protocolVersion 3), 왕복이
    /// 되는지 직접 본다 — 깨지면 게스트 화면에 라운드가 아예 안 뜬다.
    func testRoundResolvedCarriesTheEventStreamOverTheWire() throws {
        let attacker = UUID(), target = UUID()
        let events: [BattleEvent] = [.turn(4), .move(.fighter(attacker), moveID: 57),
                                     .crit(.fighter(target)), .superEffective(.fighter(target)),
                                     .damage(.fighter(target), amount: 122, cause: .move), .faint(.fighter(target))]
        let message = MultiplayerWireMessage.roundResolved(round: 4, fighters: [], events: events)
        let data = try JSONEncoder().encode(message)
        XCTAssertEqual(try JSONDecoder().decode(MultiplayerWireMessage.self, from: data), message)
    }

    func testPokeathlonObstacleRequiresJumpAndSupportsFourRacers() {
        let racers = (0..<4).map { PokeathlonRacer(id: UUID(), trainerName: "P\($0)", speciesID: $0 + 1) }
        var race = PokeathlonRace(racers: racers)
        let id = racers[0].id
        race.startsAt = .distantPast
        var now = Date()
        for _ in 0..<7 {
            race.apply(.run, racerID: id, now: now)
            now = now.addingTimeInterval(0.2)
        }
        XCTAssertEqual(race.racers[0].distance, 28)
        race.apply(.run, racerID: id, now: now)
        XCTAssertEqual(race.racers[0].distance, 32)
        now = now.addingTimeInterval(0.2)
        race.apply(.run, racerID: id, now: now)
        XCTAssertEqual(race.racers[0].distance, 29)
        race.apply(.dodgeLeft, racerID: id, now: now)
        now = now.addingTimeInterval(0.2)
        race.apply(.run, racerID: id, now: now)
        XCTAssertGreaterThan(race.racers[0].distance, 29)
        XCTAssertEqual(race.racers.count, 4)
    }

    func testForfeitCanFinishFreeForAllBattle() throws {
        func fighter(_ id: UUID) -> MultiplayerFighter {
            let snapshot = BattleSnapshot(speciesID: 1, name: "Mon", trainer: nil, level: 5,
                                          nature: nil, isShiny: false, types: [.grass],
                                          base: BattleStats(hp: 45, atk: 49, def: 49, spa: 65, spd: 65, spe: 45))
            return MultiplayerFighter(participant: LobbyParticipant(id: id, trainerName: "T", speciesID: 1,
                                                                      team: .solo, isReady: true, isHost: false),
                                      snapshot: snapshot)
        }
        let a = UUID(), b = UUID()
        var battle = try MultiplayerBattle(fighters: [fighter(a), fighter(b)], mode: .freeForAll, seed: 1)
        battle.forfeit(participantID: b)
        XCTAssertTrue(battle.isFinished)
        XCTAssertEqual(battle.winningIDs, [a])
    }

    func testTimeoutActionsAvoidTeammatesAndUseStruggleWithoutPP() {
        func fighter(_ id: UUID, team: BattleTeam, pp: Int) -> MultiplayerFighter {
            let move = MoveSpec(id: 1, names: [:], type: .normal, power: 40,
                                damageClass: .physical, accuracy: 100, pp: pp)
            let snapshot = BattleSnapshot(speciesID: 1, name: "Mon", trainer: nil, level: 5,
                                          nature: nil, isShiny: false, types: [.normal],
                                          base: BattleStats(hp: 45, atk: 49, def: 49, spa: 65, spd: 65, spe: 45),
                                          moves: [move])
            return MultiplayerFighter(participant: LobbyParticipant(id: id, trainerName: "T", speciesID: 1,
                                                                      team: team, isReady: true, isHost: false),
                                      snapshot: snapshot)
        }
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let fighters = [fighter(a, team: .red, pp: 0), fighter(b, team: .red, pp: 1),
                        fighter(c, team: .blue, pp: 1), fighter(d, team: .blue, pp: 1)]
        let actions = MultiplayerBattle.automaticActions(fighters: fighters, mode: .teams, excluding: [b])
        XCTAssertEqual(actions.count, 3)
        XCTAssertEqual(actions.first(where: { $0.attackerID == a })?.moveIndex, -1)
        for action in actions {
            let attacker = fighters.first { $0.id == action.attackerID }!
            let target = fighters.first { $0.id == action.targetID }!
            XCTAssertNotEqual(attacker.team, target.team)
        }
    }

    func testMultiplayerValidationRejectsForgedLevelAndMismatchedSpecies() {
        let id = UUID()
        let participant = LobbyParticipant(id: id, trainerName: "Trainer", speciesID: 25,
                                           team: .solo, isReady: true, isHost: false)
        let base = BattleStats(hp: 35, atk: 55, def: 40, spa: 50, spd: 50, spe: 90)
        let valid = BattleSnapshot(speciesID: 25, name: "Pika", trainer: "Trainer", level: 50,
                                   nature: nil, isShiny: false, types: [.electric], base: base)
        XCTAssertTrue(MultiplayerValidation.valid(participant: participant, snapshot: valid))
        var forged = valid; forged.level = 999
        XCTAssertFalse(MultiplayerValidation.valid(participant: participant, snapshot: forged))
        var mismatch = valid; mismatch.speciesID = 1
        XCTAssertFalse(MultiplayerValidation.valid(participant: participant, snapshot: mismatch))
    }

    func testHistorySanitizationBoundsAndSortsRecords() {
        var state = CompanionState()
        let now = Date()
        state.adventureHistory = (0..<35).map { index in
            AdventureRecord(id: UUID(), zone: .forest, companionSpeciesID: 25,
                            completedAt: now.addingTimeInterval(Double(index)), stardust: index,
                            foundRareCandy: false)
        }
        state.adventureHistory.append(AdventureRecord(id: UUID(), zone: .cave,
                                                      companionSpeciesID: -1, completedAt: now,
                                                      stardust: Int.max, foundRareCandy: true))
        state.battleHistory = [BattleRecord(playedAt: now, mode: .freeForAll,
                                            participantCount: 99, won: true, reward: 10,
                                            opponentNames: [])]
        let clean = SaveTransfer.sanitized(state)
        XCTAssertEqual(clean.adventureHistory.count, 30)
        XCTAssertEqual(clean.adventureHistory.first?.stardust, 34)
        XCTAssertTrue(clean.battleHistory.isEmpty)
    }

    /// 빈 기록은 canonical 에 아무것도 붙이지 않는다 — 기록이 없던 세이브의 서명이 그대로 유효해야 한다.
    /// 해시끼리 비교하면 기본값 상태를 자기 자신과 대조하게 돼 무조건 append 로 바꿔도 통과한다.
    func testEmptyHistoriesAddNothingToTheIntegrityCanonical() {
        let canonical = SaveTransfer.canonicalString(CompanionState())
        XCTAssertFalse(canonical.contains("|ah"))
        XCTAssertFalse(canonical.contains("|bh"))
    }
}

@MainActor
final class FocusTimerTests: XCTestCase {
    func testFocusAutomaticallyMovesToBreakAndRewardsOnce() {
        let start = Date(timeIntervalSince1970: 80_000)
        let timer = FocusTimer()
        var rewards = 0
        timer.onFocusCompleted = { minutes in
            rewards += 1
            return FocusRewardRules.reward(minutes: minutes, roll: 9_999)
        }
        timer.startFocus(minutes: 1, now: start)
        timer.tick(now: start.addingTimeInterval(60))
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(timer.completedSessions, 1)
        XCTAssertEqual(rewards, 1)
        timer.tick(now: start.addingTimeInterval(61))
        XCTAssertEqual(rewards, 1)
    }

    func testLongFocusPaysMorePerMinuteAndRaisesEggChance() {
        XCTAssertGreaterThan(FocusRewardRules.stardust(minutes: 90) / 90,
                             FocusRewardRules.stardust(minutes: 25) / 25)
        XCTAssertGreaterThan(FocusRewardRules.eggChanceBasisPoints(minutes: 90),
                             FocusRewardRules.eggChanceBasisPoints(minutes: 25))
        XCTAssertTrue(FocusRewardRules.reward(minutes: 90, roll: 699).foundEgg)
        XCTAssertFalse(FocusRewardRules.reward(minutes: 90, roll: 700).foundEgg)
    }

    func testPokemonLevelUsesFocusExperienceAndCapsAtOneHundred() {
        let levelOne = MonState(baseID: 10, pathIDs: [10], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 3)
        var leveled = levelOne
        leveled.levelExperience = 40_000_000
        XCTAssertEqual(levelOne.level, 1)
        XCTAssertEqual(leveled.level, 5)
        leveled.levelExperience = Int.max
        XCTAssertEqual(leveled.level, 100)
    }

    func testLearnedMovesSurviveEvolutionStateChange() throws {
        let tackle = MoveSpec(id: 33, names: ["ko": "몸통박치기"], type: .normal,
                              power: 40, damageClass: .physical, accuracy: 100, pp: 35)
        var mon = MonState(baseID: 10, pathIDs: [10], plannedPathIDs: [10, 11, 12],
                           stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)
        mon.learnedMoves = [tackle]
        mon.pathIDs.append(11)
        mon.stageIndex = 1
        let restored = try JSONDecoder().decode(MonState.self, from: JSONEncoder().encode(mon))
        XCTAssertEqual(restored.currentID, 11)
        XCTAssertEqual(restored.learnedMoves, [tackle])
    }
}
