import XCTest
@testable import PokeTokenBar

final class PokemonTournamentTests: XCTestCase {
    private func participant(_ id: UUID = UUID()) -> LobbyParticipant {
        LobbyParticipant(id: id, trainerName: "Trainer", speciesID: 25, team: .solo,
                         isReady: true, isHost: false)
    }

    func testTournamentLobbyAcceptsEightRunners() throws {
        let host = participant()
        var lobby = try MultiplayerLobby(host: host, capacity: 8, activity: .tournament)
        for _ in 1..<8 { try lobby.join(participant()) }
        XCTAssertEqual(lobby.runners.count, 8)
        XCTAssertTrue(lobby.canStart)
        XCTAssertThrowsError(try lobby.join(participant()))
    }

    func testRewardTierRisesWithEntrantsAndStopsBeforeLegendary() {
        XCTAssertEqual(TournamentEggReward.forParticipants(2), .standard)
        XCTAssertEqual(TournamentEggReward.forParticipants(3), .standard)
        XCTAssertEqual(TournamentEggReward.forParticipants(4), .standard)
        XCTAssertEqual(TournamentEggReward.forParticipants(5), .uncommon)
        XCTAssertEqual(TournamentEggReward.forParticipants(6), .uncommon)
        XCTAssertEqual(TournamentEggReward.forParticipants(7), .rare)
        XCTAssertEqual(TournamentEggReward.forParticipants(8), .rare)
        XCTAssertEqual(TournamentEggReward.rare.guarantee, .rare)
    }

    func testTournamentNeedsAtLeastThreeReadyEntrants() throws {
        var host = participant(); host.isReady = true
        var lobby = try MultiplayerLobby(host: host, capacity: 8, activity: .tournament)
        try lobby.join(participant())
        XCTAssertFalse(lobby.canStart)
        try lobby.join(participant())
        XCTAssertTrue(lobby.canStart)
    }

    func testBracketProducesOneChampionForEverySupportedSize() throws {
        for count in 2...8 {
            let ids = (0..<count).map { _ in UUID() }
            var bracket = TournamentBracket(participantIDs: ids, seed: UInt64(count))
            var safety = 0
            while bracket.championID == nil, safety < 20 {
                safety += 1
                guard let pair = bracket.nextPair() else { continue }
                bracket.record(match: TournamentBracketMatch(id: UUID(), round: bracket.round,
                                                              playerA: pair.0, playerB: pair.1,
                                                              winnerID: pair.0))
            }
            XCTAssertNotNil(bracket.championID, "\(count)명 대진이 끝나지 않았다")
            XCTAssertLessThan(safety, 20)
        }
    }

    func testOnlyCurrentPlayersCanSubmitWhileOthersSpectate() {
        let a = TournamentEntrant(id: UUID(), trainerName: "A", speciesID: 1)
        let b = TournamentEntrant(id: UUID(), trainerName: "B", speciesID: 4)
        let spectator = UUID()
        let move = MoveSpec(id: 33, names: ["en": "Tackle"], type: .normal, power: 40,
                            damageClass: .physical, accuracy: nil, pp: 35)
        func snapshot(_ id: Int, _ name: String) -> BattleSnapshot {
            BattleSnapshot(speciesID: id, name: name, level: 50, isShiny: false, types: [.normal],
                           base: BattleStats(hp: 60, atk: 60, def: 60, spa: 60, spd: 60, spe: 60),
                           moves: [move])
        }
        var engine = TournamentMatchEngine(round: 1, playerA: a, playerB: b,
                                           teamA: [snapshot(1, "A1"), snapshot(2, "A2"), snapshot(3, "A3")],
                                           teamB: [snapshot(4, "B1"), snapshot(5, "B2"), snapshot(6, "B3")], seed: 1)
        XCTAssertFalse(engine.submit(.move(index: 0), from: spectator))
        XCTAssertTrue(engine.submit(.move(index: 0), from: a.id))
        XCTAssertTrue(engine.snapshot().submitted.contains(a.id))
        XCTAssertFalse(engine.snapshot().submitted.contains(spectator))
    }

    func testFaintedPokemonWaitsForThePlayerToChooseItsReplacement() {
        let a = TournamentEntrant(id: UUID(), trainerName: "A", speciesID: 1)
        let b = TournamentEntrant(id: UUID(), trainerName: "B", speciesID: 4)
        let knockout = MoveSpec(id: 33, names: ["en": "Knockout"], type: .normal, power: 10_000,
                                damageClass: .physical, accuracy: nil, pp: 35)
        let weak = MoveSpec(id: 45, names: ["en": "Weak"], type: .normal, power: 1,
                            damageClass: .physical, accuracy: nil, pp: 40)
        func snapshot(_ id: Int, _ name: String, speed: Int, move: MoveSpec) -> BattleSnapshot {
            BattleSnapshot(speciesID: id, name: name, level: 50, isShiny: false, types: [.normal],
                           base: BattleStats(hp: 60, atk: 60, def: 60, spa: 60, spd: 60, spe: speed),
                           moves: [move])
        }
        var engine = TournamentMatchEngine(round: 1, playerA: a, playerB: b,
                                           teamA: [snapshot(1, "A1", speed: 200, move: knockout)],
                                           teamB: [snapshot(4, "B1", speed: 1, move: weak),
                                                   snapshot(5, "B2", speed: 1, move: weak)], seed: 1)

        XCTAssertTrue(engine.submit(.move(index: 0), from: a.id))
        XCTAssertTrue(engine.submit(.move(index: 0), from: b.id))
        XCTAssertNil(engine.resolveIfReady())
        XCTAssertEqual(engine.snapshot().activeB, 0)
        XCTAssertEqual(engine.snapshot().teamB[0].hp, 0)
        XCTAssertFalse(engine.submit(.move(index: 0), from: a.id),
                       "상대의 교체 포켓몬이 나오기 전에는 기술을 미리 고를 수 없다")
        XCTAssertTrue(engine.submit(.switchTo(index: 1), from: b.id))
        XCTAssertEqual(engine.snapshot().activeB, 1)
        XCTAssertFalse(engine.snapshot().submitted.contains(b.id),
                       "기절 뒤 강제 교체는 행동 제출로 세지 않는다")
        XCTAssertTrue(engine.submit(.move(index: 0), from: b.id),
                      "교체해 나온 포켓몬은 같은 턴에 기술을 선택할 수 있다")
    }

    func testTournamentNormalizesEveryEntrantToLevelFifty() {
        let a = TournamentEntrant(id: UUID(), trainerName: "A", speciesID: 1)
        let b = TournamentEntrant(id: UUID(), trainerName: "B", speciesID: 4)
        let move = MoveSpec(id: 33, names: ["en": "Tackle"], type: .normal, power: 40,
                            damageClass: .physical, accuracy: nil, pp: 35)
        func snapshot(_ id: Int, level: Int) -> BattleSnapshot {
            BattleSnapshot(speciesID: id, name: "Mon", level: level, isShiny: false, types: [.normal],
                           base: BattleStats(hp: 60, atk: 60, def: 60, spa: 60, spd: 60, spe: 60),
                           moves: [move])
        }
        let engine = TournamentMatchEngine(round: 1, playerA: a, playerB: b,
                                           teamA: [snapshot(1, level: 5)],
                                           teamB: [snapshot(4, level: 100)], seed: 1)

        XCTAssertEqual(engine.snapshot().teamA.map(\.snapshot.level), [50])
        XCTAssertEqual(engine.snapshot().teamB.map(\.snapshot.level), [50])
    }

    func testTournamentSnapshotKeepsTheWholeEventStreamForSpectatorEffects() {
        let a = TournamentEntrant(id: UUID(), trainerName: "A", speciesID: 1)
        let b = TournamentEntrant(id: UUID(), trainerName: "B", speciesID: 4)
        let move = MoveSpec(id: 33, names: ["en": "Tackle"], type: .normal, power: 1,
                            damageClass: .physical, accuracy: nil, pp: 35)
        func snapshot(_ id: Int) -> BattleSnapshot {
            BattleSnapshot(speciesID: id, name: "Mon", level: 50, isShiny: false, types: [.normal],
                           base: BattleStats(hp: 500, atk: 10, def: 500, spa: 10, spd: 500, spe: id),
                           moves: [move])
        }
        var engine = TournamentMatchEngine(round: 1, playerA: a, playerB: b,
                                           teamA: [snapshot(1)], teamB: [snapshot(4)], seed: 7)

        XCTAssertTrue(engine.submit(.move(index: 0), from: a.id))
        XCTAssertTrue(engine.submit(.move(index: 0), from: b.id))
        XCTAssertNil(engine.resolveIfReady())
        let firstTurnCount = engine.snapshot().events.count
        XCTAssertGreaterThan(firstTurnCount, 0)

        XCTAssertTrue(engine.submit(.move(index: 0), from: a.id))
        XCTAssertTrue(engine.submit(.move(index: 0), from: b.id))
        XCTAssertNil(engine.resolveIfReady())
        XCTAssertGreaterThan(engine.snapshot().events.count, firstTurnCount,
                             "관전자 재생기는 이전 턴 뒤에 추가된 이벤트를 받아야 한다")
    }
}
