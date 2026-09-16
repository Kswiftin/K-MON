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
            frame.fighters.allSatisfy { (0..<6).contains($0.x) && (0..<6).contains($0.y) && $0.hp >= 0 }
        })
        let final = replay.frames.last!
        #expect(final.fighters.contains { $0.hp == 0 } || replay.frames.count == 29)
    }
}
