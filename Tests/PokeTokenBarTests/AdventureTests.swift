import XCTest
@testable import PokeTokenBar

final class AdventureTests: XCTestCase {
    func testCareDecaysAndActionsStayWithinBounds() {
        let start = Date(timeIntervalSince1970: 0)
        var care = PetCareState(energy: 50, lastUpdatedAt: start)
        care.advance(to: start.addingTimeInterval(3600))
        XCTAssertEqual(care.hunger, 96)
        XCTAssertEqual(care.happiness, 98)
        XCTAssertEqual(care.energy, 70, "에너지는 감소가 아니라 시간당 회복이다")
        for index in 0..<10 {
            care.feed(); care.play()
            _ = care.rest(at: start.addingTimeInterval(Double(index) * PetCareState.restCooldown))
        }
        XCTAssertTrue((0...100).contains(care.hunger))
        XCTAssertTrue((0...100).contains(care.happiness))
        XCTAssertTrue((0...100).contains(care.energy))
    }

    /// 재우기 연타 방지 — 대기 없이 회복되면 에너지가 무한이 되어 모험 소모 설계가 통째로 무의미해진다.
    func testRestIsRateLimitedByCooldown() {
        let start = Date(timeIntervalSince1970: 0)
        var care = PetCareState(energy: 0, lastUpdatedAt: start)
        XCTAssertTrue(care.rest(at: start))
        XCTAssertEqual(care.energy, PetCareState.restRecovery)
        XCTAssertFalse(care.rest(at: start.addingTimeInterval(PetCareState.restCooldown - 1)))
        XCTAssertEqual(care.energy, PetCareState.restRecovery, "대기 중에는 회복되지 않는다")
        XCTAssertTrue(care.rest(at: start.addingTimeInterval(PetCareState.restCooldown)))
        XCTAssertEqual(care.energy, PetCareState.restRecovery * 2)
    }

    /// 에너지 소모도 구간 길이에 비례해야 한다 — 고정 비용이면 시간당 소모가 짧은 구간에 불리해져
    /// 별의모래 밸런스(짧을수록 유리)와 정반대로 작용하고, 최장 구간이 다시 유일한 선택지가 된다.
    func testEnergyCostPerHourIsEqualAcrossZones() {
        for zone in AdventureZone.allCases {
            XCTAssertEqual(zone.energyCost / (zone.duration / 3600),
                           PetCareState.adventureEnergyPerHour, accuracy: 1e-9,
                           "\(zone.rawValue) 구간의 시간당 에너지 소모가 다르다")
        }
    }

    /// 자동 회복이 모험 소모를 넘으면 에너지가 사실상 무제한이 되어 제약 역할을 못 한다.
    func testEnergyRecoveryStaysBelowAdventureDrain() {
        XCTAssertLessThan(PetCareState.recoveryPerHour, PetCareState.adventureEnergyPerHour)
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

    /// 구간 지배 방지 — 짧은 구간일수록 시간당 별의모래가 많아야 한다. 대소가 뒤집히면 최장 구간이
    /// 효율·수고 양쪽에서 우월해져 나머지 두 구간이 고를 이유 없는 죽은 선택지가 된다(도입 시 실제로 그랬다).
    func testShorterZonesPayMoreStardustPerHour() {
        func stardustPerHour(_ zone: AdventureZone) -> Double {
            let start = Date(timeIntervalSince1970: 0)
            let run = AdventureRun(zone: zone, startedAt: start,
                                   endsAt: start.addingTimeInterval(zone.duration),
                                   companionSpeciesID: 25)
            return Double(AdventureRules.reward(for: run).stardust) / (zone.duration / 3600)
        }
        XCTAssertGreaterThan(stardustPerHour(.forest), stardustPerHour(.cave))
        XCTAssertGreaterThan(stardustPerHour(.cave), stardustPerHour(.coast))
    }

    /// 사탕 기대치는 구간마다 같아야 한다 — 한쪽이 유리하면 구간 선택이 별의모래가 아니라 사탕으로 쏠린다.
    func testRareCandyOddsAreEqualPerHourAcrossZones() {
        func rareCandyPerHour(_ zone: AdventureZone) -> Double {
            (3600 / zone.duration) / Double(zone.rareCandyDenominator)
        }
        for zone in AdventureZone.allCases {
            XCTAssertEqual(rareCandyPerHour(zone), rareCandyPerHour(.forest), accuracy: 1e-9,
                           "\(zone.rawValue) 구간의 시간당 사탕 기대치가 다르다")
        }
    }

    /// 도감 보너스가 방치 생산에만 붙고 모험엔 안 붙으면, 종을 모을수록 모험이 상대적으로 무가치해진다.
    func testRewardScalesWithDexProductionMultiplier() {
        let start = Date(timeIntervalSince1970: 0)
        let run = AdventureRun(zone: .cave, startedAt: start,
                               endsAt: start.addingTimeInterval(AdventureZone.cave.duration),
                               companionSpeciesID: 25)
        let withoutDexBonus = AdventureRules.reward(for: run).stardust
        let withDexBonus = AdventureRules.reward(for: run, productionMultiplier: 2).stardust
        XCTAssertEqual(withDexBonus, withoutDexBonus * 2)
    }

    /// 모험 중에도 방치 생산은 계속 돈다 — 보상이 같은 시간 방치분을 넘으면 "모험 안 하면 손해"가 되어
    /// 방치형 전제가 무너진다. 보너스는 방치분의 일부여야 한다.
    func testZoneRewardStaysBelowSameDurationIdleProduction() {
        for zone in AdventureZone.allCases {
            XCTAssertLessThan(zone.idleProductionShare, 1.0, "\(zone.rawValue) 보상이 방치 생산을 넘는다")
        }
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
