import XCTest
@testable import PokeTokenBar

final class BattleFrontierTests: XCTestCase {
    func testFrontierUsesThreePokemonAtLevelFifty() {
        XCTAssertEqual(BattleFrontier.teamSize, 3)
        XCTAssertEqual(BattleFrontier.battleLevel, 50)
    }

    func testOpponentPoolGetsStrongerAndKeepsEnoughUniqueSpecies() {
        let early = BattleFrontier.opponentPool(for: 1)
        let late = BattleFrontier.opponentPool(for: 14)

        XCTAssertGreaterThanOrEqual(Set(early).count, BattleFrontier.teamSize)
        XCTAssertGreaterThanOrEqual(Set(late).count, BattleFrontier.teamSize)
        XCTAssertFalse(early.contains(150), "초반 풀에는 전설 포켓몬이 나오지 않는다")
        XCTAssertTrue(late.contains(150), "장기 연승 풀에는 강한 상대가 추가된다")
    }

    func testEverySeventhWinAddsBrainBonus() {
        XCTAssertGreaterThan(BattleFrontier.reward(for: 2), BattleFrontier.reward(for: 1))
        XCTAssertEqual(BattleFrontier.reward(for: 7) - BattleFrontier.reward(for: 6), 2_100)
        XCTAssertEqual(BattleFrontier.trainerName(for: 7), "프런티어 브레인")
        XCTAssertEqual(BattleFrontier.bpReward(for: 1), 2)
        XCTAssertEqual(BattleFrontier.bpReward(for: 7), 10)
    }

    func testPrizeCostsRiseWithGuaranteedRarity() {
        XCTAssertEqual(BattleFrontierPrize.egg.guarantee, nil)
        XCTAssertEqual(BattleFrontierPrize.uncommonEgg.guarantee, .uncommon)
        XCTAssertEqual(BattleFrontierPrize.rareEgg.guarantee, .rare)
        XCTAssertLessThan(BattleFrontierPrize.egg.cost, BattleFrontierPrize.uncommonEgg.cost)
        XCTAssertLessThan(BattleFrontierPrize.uncommonEgg.cost, BattleFrontierPrize.rareEgg.cost)
    }
}
