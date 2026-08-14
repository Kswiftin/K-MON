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

    func testCareRequestCanBeAnsweredAndBuildsAffection() {
        let start = Date(timeIntervalSince1970: 1_000)
        var care = PetCareState(hunger: 30, lastNeedAt: start.addingTimeInterval(-3600), lastUpdatedAt: start)
        XCTAssertEqual(care.advance(to: start.addingTimeInterval(60)), .requested(.hungry))
        XCTAssertEqual(care.pendingNeed, .hungry)
        let before = care.affection
        care.feed()
        XCTAssertNil(care.pendingNeed)
        XCTAssertGreaterThan(care.affection, before)
        XCTAssertEqual(care.careMistakes, 0)
    }

    func testMissedCareRequestReducesAffectionOnce() {
        let start = Date(timeIntervalSince1970: 2_000)
        var care = PetCareState(energy: 20, lastNeedAt: start.addingTimeInterval(-3600), lastUpdatedAt: start)
        XCTAssertEqual(care.advance(to: start.addingTimeInterval(60)), .requested(.tired))
        let deadline = try! XCTUnwrap(care.needDeadline)
        XCTAssertEqual(care.advance(to: deadline), .missed(.tired))
        XCTAssertEqual(care.careMistakes, 1)
        XCTAssertEqual(care.affection, 45)
        XCTAssertNil(care.advance(to: deadline.addingTimeInterval(60)), "쿨다운 중 같은 요구가 반복되면 안 됨")
    }

    func testLegacyCareStateGetsNewFieldDefaults() throws {
        let data = Data(#"{"hunger":80,"happiness":70,"energy":60}"#.utf8)
        let care = try JSONDecoder().decode(PetCareState.self, from: data)
        XCTAssertEqual(care.affection, 50)
        XCTAssertEqual(care.careMistakes, 0)
        XCTAssertNil(care.pendingNeed)
    }

    func testHealthyCompanionStillAsksForAttentionEveryTwoHours() {
        let start = Date(timeIntervalSince1970: 3_000)
        var care = PetCareState(lastNeedAt: start, lastUpdatedAt: start)
        XCTAssertNil(care.advance(to: start.addingTimeInterval(2 * 3600 - 1)))
        XCTAssertEqual(care.advance(to: start.addingTimeInterval(2 * 3600)), .requested(.hungry))
    }

    func testCareQualityChangesGrowthWithoutStoppingIt() {
        XCTAssertEqual(PetCareState().growthMultiplier, 1, accuracy: 0.0001)
        let neglected = PetCareState(hunger: 0, happiness: 0, energy: 0, affection: 0)
        let bonded = PetCareState(affection: 100)
        XCTAssertGreaterThanOrEqual(neglected.growthMultiplier, 0.7)
        XCTAssertLessThan(neglected.growthMultiplier, 1)
        XCTAssertGreaterThan(bonded.growthMultiplier, 1)
    }

    func testFavoriteFoodGivesLargerCareReward() {
        var normal = PetCareState(hunger: 20, happiness: 20)
        var favorite = normal
        normal.feed()
        favorite.feed(favorite: true)
        XCTAssertGreaterThan(favorite.hunger, normal.hunger)
        XCTAssertGreaterThan(favorite.happiness, normal.happiness)
        XCTAssertEqual(CareFood.favorite(for: 25), CareFood.favorite(for: 25))
    }

    func testPettingHasFiveMinuteCooldown() {
        let now = Date(timeIntervalSince1970: 10_000)
        var care = PetCareState(happiness: 50)
        XCTAssertTrue(care.pet(at: now))
        let afterFirst = care.happiness
        XCTAssertFalse(care.pet(at: now.addingTimeInterval(299)))
        XCTAssertEqual(care.happiness, afterFirst)
        XCTAssertTrue(care.pet(at: now.addingTimeInterval(300)))
    }

    func testNeglectCausesSicknessAndCleanMedicineRecovers() {
        let start = Date(timeIntervalSince1970: 20_000)
        var care = PetCareState(hunger: 25, hygiene: 20, lastUpdatedAt: start)
        XCTAssertEqual(care.advance(to: start.addingTimeInterval(60)), .becameSick)
        XCTAssertTrue(care.isSick)
        XCTAssertFalse(care.giveMedicine(), "더러운 상태에서는 약만으로 회복할 수 없음")
        care.clean()
        XCTAssertTrue(care.giveMedicine())
        XCTAssertFalse(care.isSick)
    }

    func testSicknessCapsGrowth() {
        let sick = PetCareState(affection: 100, isSick: true)
        XCTAssertLessThanOrEqual(sick.growthMultiplier, 0.75)
    }

    func testMessAccumulatesEveryFourHoursAndCleaningClearsIt() {
        let start = Date(timeIntervalSince1970: 30_000)
        var care = PetCareState(lastMessAt: start, lastUpdatedAt: start)
        care.advance(to: start.addingTimeInterval(8 * 3600))
        XCTAssertEqual(care.messCount, 2)
        XCTAssertLessThan(care.hygiene, 100)
        care.clean()
        XCTAssertEqual(care.messCount, 0)
        XCTAssertGreaterThan(care.hygiene, 80)
    }

    func testMessIsCappedAfterLongOfflinePeriod() {
        let start = Date(timeIntervalSince1970: 40_000)
        var care = PetCareState(lastMessAt: start, lastUpdatedAt: start)
        care.advance(to: start.addingTimeInterval(48 * 3600))
        XCTAssertEqual(care.messCount, 3)
    }

    func testTrainingCostsEnergyAndHasCooldown() {
        let now = Date(timeIntervalSince1970: 50_000)
        var care = PetCareState(energy: 50)
        XCTAssertEqual(care.train(at: now), .trained)
        XCTAssertEqual(care.energy, 40)
        XCTAssertEqual(care.discipline, 10)
        XCTAssertEqual(care.train(at: now.addingTimeInterval(1_799)), .cooldown)
        XCTAssertEqual(care.train(at: now.addingTimeInterval(1_800)), .trained)
    }

    func testTrainingRequiresEnoughEnergy() {
        var care = PetCareState(energy: 9)
        XCTAssertEqual(care.train(at: Date()), .tooTired)
        XCTAssertEqual(care.discipline, 0)
    }

    func testSleepRecoversEnergyAndAutoWakesAtFull() {
        let now = Date(timeIntervalSince1970: 60_000)
        var care = PetCareState(energy: 70, lastUpdatedAt: now)
        XCTAssertTrue(care.sleep(at: now))
        care.advance(to: now.addingTimeInterval(2 * 3600))
        XCTAssertEqual(care.energy, 100)
        XCTAssertFalse(care.isSleeping)
    }

    func testManualWakeKeepsPartialRecovery() {
        let now = Date(timeIntervalSince1970: 70_000)
        var care = PetCareState(energy: 50, lastUpdatedAt: now)
        XCTAssertTrue(care.sleep(at: now))
        XCTAssertTrue(care.wake(at: now.addingTimeInterval(3600)))
        XCTAssertEqual(care.energy, 65)
        XCTAssertFalse(care.isSleeping)
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

    func testEmptyHistoriesKeepLegacyIntegrityCanonicalForm() {
        var state = CompanionState()
        let before = SaveTransfer.integrityHash(state)
        state.adventureHistory = []
        state.battleHistory = []
        XCTAssertEqual(SaveTransfer.integrityHash(state), before)
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
