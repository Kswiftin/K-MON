import XCTest
@testable import PokeTokenBar

private struct TechnicalMachineProvider: PokeProviding {
    let compatible: Bool
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func canLearnMachine(speciesID: Int, moveID: Int) async -> Bool { compatible }
    func moveDetail(id: Int) async -> MoveSpec? {
        MoveSpec(id: id, names: ["ko": "화염방사", "en": "Flamethrower"], type: .fire,
                 power: 90, damageClass: .special, accuracy: 100, pp: 15)
    }
}

@MainActor
final class TechnicalMachineTests: XCTestCase {
    private let machine = TechnicalMachine.catalog[0]

    func testGenerationFiveCatalogContainsEveryTMExactlyOnce() {
        XCTAssertEqual(TechnicalMachine.catalog.count, 95)
        XCTAssertEqual(TechnicalMachine.catalog.map(\.number), Array(1...95))
        XCTAssertEqual(Set(TechnicalMachine.catalog.map(\.moveID)).count, 95)
        XCTAssertEqual(TechnicalMachine.catalog.first?.slug, "hone-claws")
        XCTAssertEqual(TechnicalMachine.catalog.last?.slug, "snarl")
    }

    private func store(compatible: Bool = true, learned: [Int] = []) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm-\(UUID().uuidString).json")
        let moves = learned.map {
            "{\"id\":\($0),\"names\":{\"en\":\"m\($0)\"},\"type\":\"normal\",\"power\":40,"
            + "\"damageClass\":\"physical\",\"accuracy\":100,\"pp\":35}"
        }.joined(separator: ",")
        let active = "{\"baseID\":4,\"pathIDs\":[4],\"stageIndex\":0,\"usedAtStage\":0,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"learnedMoves\":[\(moves)]}"
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,"
            + "\"installBaselineSet\":true,\"starPieces\":10000,\"lastDate\":\"d\","
            + "\"active\":\(active),\"dex\":[],\"collectedFinals\":[]}"
        try? Data(json.utf8).write(to: url)
        return CompanionStore(provider: TechnicalMachineProvider(compatible: compatible),
                              fileURL: url, rng: SeededRNG(seed: 1))
    }

    func testOldSaveWithoutMachineInventoryDecodesEmpty() throws {
        let state = try JSONDecoder().decode(CompanionState.self, from: Data("{}".utf8))
        XCTAssertTrue(state.technicalMachines.isEmpty)
    }

    func testMachineInventoryParticipatesInIntegrityOnlyWhenOwned() {
        var state = CompanionState()
        let oldCompatible = SaveTransfer.canonicalString(state)
        XCTAssertFalse(oldCompatible.components(separatedBy: "|").contains { $0.hasPrefix("tm") })
        state.technicalMachines[machine.moveID] = 2
        XCTAssertTrue(SaveTransfer.canonicalString(state).contains("tm\(machine.moveID):2"))
    }

    func testBuyingMachineDebitsWalletAndPersistsInventory() {
        let s = store()
        XCTAssertTrue(s.buyTechnicalMachine(machine))
        XCTAssertEqual(s.technicalMachineCount(machine.moveID), 1)
        XCTAssertEqual(s.availableTokens, 10_000 - machine.price)
    }

    /// 한 번에 여러 장 — 총액을 한 번에 차감하고 재고를 그만큼 올린다.
    func testBuyingMultipleMachinesDebitsTotalAtOnce() {
        let s = store()
        XCTAssertEqual(s.maxPurchasableTechnicalMachines(machine), 10_000 / machine.price)
        XCTAssertTrue(s.buyTechnicalMachine(machine, quantity: 3))
        XCTAssertEqual(s.technicalMachineCount(machine.moveID), 3)
        XCTAssertEqual(s.availableTokens, 10_000 - machine.price * 3)
    }

    /// 전량 구매 — 상한을 넘기면 부분 구매 없이 통째로 no-op.
    func testBuyingMoreMachinesThanAffordableIsNoOp() {
        let s = store()
        let overBudget = 10_000 / machine.price + 1
        XCTAssertFalse(s.buyTechnicalMachine(machine, quantity: overBudget))
        XCTAssertEqual(s.technicalMachineCount(machine.moveID), 0)
        XCTAssertEqual(s.availableTokens, 10_000)
    }

    func testCompatibleMachineOpensLearningAndConsumesOnlyAfterAccept() async {
        let s = store()
        XCTAssertTrue(s.buyTechnicalMachine(machine))
        let opened = await s.useTechnicalMachine(machine)
        XCTAssertTrue(opened)
        XCTAssertEqual(s.technicalMachineCount(machine.moveID), 1)
        XCTAssertEqual(s.moveLearningPrompt?.move.id, machine.moveID)
        s.acceptMoveLearning()
        XCTAssertEqual(s.technicalMachineCount(machine.moveID), 0)
        XCTAssertTrue(s.state.active?.learnedMoves.contains(where: { $0.id == machine.moveID }) == true)
    }

    func testIncompatibleMachineIsNotConsumed() async {
        let s = store(compatible: false)
        XCTAssertTrue(s.buyTechnicalMachine(machine))
        let opened = await s.useTechnicalMachine(machine)
        XCTAssertFalse(opened)
        XCTAssertEqual(s.technicalMachineCount(machine.moveID), 1)
        XCTAssertNil(s.moveLearningPrompt)
    }

    func testFourMovePokemonChoosesReplacementBeforeConsumption() async {
        let s = store(learned: [1, 2, 3, 4])
        XCTAssertTrue(s.buyTechnicalMachine(machine))
        let opened = await s.useTechnicalMachine(machine)
        XCTAssertTrue(opened)
        s.acceptMoveLearning(replacing: 2)
        XCTAssertEqual(s.state.active?.learnedMoves.map(\.id), [1, 2, machine.moveID, 4])
        XCTAssertEqual(s.technicalMachineCount(machine.moveID), 0)
    }
}
