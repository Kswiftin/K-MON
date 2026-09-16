import Foundation
import Testing
@testable import PokeTokenBar

@Suite struct PokemonTFTTests {
    @Test func threeCopiesCombineIntoTwoStarUnit() {
        var game = PokemonTFTGame(seed: 1)
        game.gold = 20
        game.shop = [1, 1, 1, nil, nil, nil]

        let first = game.buy(shopIndex: 0)
        let second = game.buy(shopIndex: 1)
        let third = game.buy(shopIndex: 2)
        #expect(first && second && third)
        #expect(game.units.count == 1)
        #expect(game.units.first?.definitionID == 1)
        #expect(game.units.first?.star == 2)
    }

    @Test func deploymentRespectsLevelLimitAndCanMoveBetweenSlots() {
        var game = PokemonTFTGame(seed: 2)
        game.gold = 20
        game.shop = [1, 4, 7, 25, nil, nil]
        for index in 0..<4 { _ = game.buy(shopIndex: index) }
        for unit in game.units { game.toggleDeployment(unit.id) }

        #expect(game.deployedCount == 3)
        let first = game.units.first!
        game.move(first.id, to: 8)
        #expect(game.units.first(where: { $0.id == first.id })?.boardSlot == 8)
    }

    @Test func battleAdvancesRoundAndRefreshesShop() {
        var game = PokemonTFTGame(seed: 3)
        game.gold = 20
        game.shop = [610, nil, nil, nil, nil, nil]
        let bought = game.buy(shopIndex: 0)
        #expect(bought)
        game.toggleDeployment(game.units[0].id)
        game.fight()

        #expect(game.round == 2)
        #expect(game.shop.count == 6)
        #expect(game.health > 0)
    }

    @Test func replayMovesAttacksAndFinishesWithOneResult() {
        var game = PokemonTFTGame(seed: 4)
        game.gold = 20
        game.shop = [610, 610, 610, nil, nil, nil]
        _ = game.buy(shopIndex: 0)
        _ = game.buy(shopIndex: 1)
        _ = game.buy(shopIndex: 2)
        game.toggleDeployment(game.units[0].id)

        let replay = game.makeBattleReplay()
        #expect(replay.frames.count > 2)
        #expect(replay.frames.allSatisfy { frame in
            frame.fighters.allSatisfy {
                (0..<PokemonTFTGame.combatColumns).contains($0.x) &&
                (0..<PokemonTFTGame.combatRows).contains($0.y) && $0.hp >= 0 && (0...100).contains($0.mana)
            }
        })
        let final = replay.frames.last!
        #expect(replay.frames.count <= 2 + 36 * 12)
        #expect(final.message != "전투 시작!")
        #expect(replay.frames.dropFirst(2).contains { $0.action != nil })
        #expect(replay.frames.contains { $0.action?.kind == .attack || $0.action?.kind == .critical })
        #expect(replay.frames.contains { $0.action?.kind == .skill })
    }

    @Test func synergyGuideShowsMembersThresholdAndActiveEffect() {
        var game = PokemonTFTGame(seed: 5)
        game.level = 3
        game.units = [
            PokemonTFTUnit(definitionID: 66, boardSlot: 0),
            PokemonTFTUnit(definitionID: 447, boardSlot: 1)
        ]

        let fighting = game.synergyInfo(for: .fighting)
        #expect(fighting.deployed == 2)
        #expect(fighting.members.contains("알통몬"))
        #expect(fighting.members.contains("리오르"))
        #expect(fighting.effectText.contains("+10%"))
    }

    @Test func multiplayerArmyBecomesTheActualEnemyTeam() {
        var game = PokemonTFTGame(seed: 6)
        game.units = [PokemonTFTUnit(definitionID: 7, boardSlot: 0)]
        let opponent = PokemonTFTArmy(units: [
            PokemonTFTArmyUnit(definitionID: 25, star: 2, boardSlot: 4),
            PokemonTFTArmyUnit(definitionID: 92, star: 1, boardSlot: 5)
        ])

        let replay = game.makeBattleReplay(opponent: opponent)
        let enemies = replay.frames[0].fighters.filter { $0.team == .enemy }
        #expect(Set(enemies.map(\.speciesID)) == Set([25, 92]))
        #expect(enemies.first(where: { $0.speciesID == 25 })?.maxHP ?? 0 > 88)
    }

    @Test func tftLobbyAcceptsEightPlayersAndCanStart() throws {
        func player(_ number: Int) -> LobbyParticipant {
            LobbyParticipant(id: UUID(), trainerName: "P\(number)", speciesID: 25,
                             team: .solo, isReady: true, isHost: number == 1)
        }
        var lobby = try MultiplayerLobby(host: player(1), capacity: 8, activity: .pokemonTFT)
        for number in 2...8 { try lobby.join(player(number)) }

        #expect(lobby.runners.count == 8)
        #expect(lobby.canStart)
        #expect(MultiplayerRoomCenter.maxGuestConnections(activity: .pokemonTFT) == 7)
    }

    @Test func multiplayerDoesNotStopAtSoloRoundTwelve() {
        var game = PokemonTFTGame(seed: 7)
        game.round = PokemonTFTGame.finalRound
        game.units = [PokemonTFTUnit(definitionID: 25, boardSlot: 0)]

        game.settleMultiplayerBattle(playerWon: true)

        #expect(game.round == PokemonTFTGame.finalRound + 1)
        #expect(game.phase == .shopping)
    }

    @Test func simultaneousEliminationStillLeavesOneWinner() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let players = [
            PokemonTFTPlayerState(id: firstID, trainerName: "A", health: 8),
            PokemonTFTPlayerState(id: secondID, trainerName: "B", health: 8)
        ]

        let settled = PokemonTFTRoundSettlement.apply(
            players: players, results: [firstID: false, secondID: false], damage: 8)

        #expect(settled.filter { !$0.isEliminated }.count == 1)
        #expect(settled.first(where: { $0.id == firstID })?.health == 1)
    }
}
