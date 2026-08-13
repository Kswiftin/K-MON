import XCTest
@testable import PokeTokenBar

final class AdventureTests: XCTestCase {
    func testCareDecaysAndActionsStayWithinBounds() {
        var care = PetCareState(lastUpdatedAt: Date(timeIntervalSince1970: 0))
        care.advance(to: Date(timeIntervalSince1970: 3600))
        XCTAssertEqual(care.hunger, 96)
        XCTAssertEqual(care.happiness, 98)
        XCTAssertEqual(care.energy, 97)
        for _ in 0..<10 { care.feed(); care.play(); care.rest() }
        XCTAssertTrue((0...100).contains(care.hunger))
        XCTAssertTrue((0...100).contains(care.happiness))
        XCTAssertTrue((0...100).contains(care.energy))
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
        XCTAssertThrowsError(try lobby.join(player(5))) { XCTAssertEqual($0 as? LobbyError, .full) }
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
            let move = MoveSpec(id: 10 + index, names: [:], type: .normal, power: 40,
                                damageClass: .physical, accuracy: 100, pp: 20)
            let snapshot = BattleSnapshot(speciesID: index, name: "M\(index)", trainer: "P\(index)",
                                          level: 20, nature: nil, isShiny: false, types: [.normal],
                                          base: BattleStats(hp: 80, atk: 60, def: 60, spa: 60, spd: 60,
                                                            spe: 40 + index), moves: [move])
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
        XCTAssertEqual(a.first?.attackerID, ids[3], "가장 빠른 참가자가 먼저 행동")
        XCTAssertEqual(first.round, 2)
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
        XCTAssertEqual(MultiplayerWireMessage.protocolVersion, 1)
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

    func testEmptyHistoriesKeepLegacyIntegrityCanonicalForm() {
        var state = CompanionState()
        let before = SaveTransfer.integrityHash(state)
        state.adventureHistory = []
        state.battleHistory = []
        XCTAssertEqual(SaveTransfer.integrityHash(state), before)
    }
}
