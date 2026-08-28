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
        XCTAssertEqual(TournamentEggReward.forParticipants(4), .uncommon)
        XCTAssertEqual(TournamentEggReward.forParticipants(5), .uncommon)
        XCTAssertEqual(TournamentEggReward.forParticipants(6), .rare)
        XCTAssertEqual(TournamentEggReward.forParticipants(8), .rare)
        XCTAssertEqual(TournamentEggReward.rare.guarantee, .rare)
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
}
