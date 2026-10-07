import Foundation
import Testing
@testable import PokeTokenBar

@Suite struct PokopiaCommunityBoardTests {
    // 지역마다 발급하거나 다시 여는 순간 목록을 재생성하면 일일 상한이 사라진다.
    @Test func fiveRegionsShareThreeFrozenSlots() throws {
        let context = CommunityFixture.context(residents: 5)
        var state = PokopiaCommunityState()
        #expect(PokopiaCommunity.prepare(&state, context: context))
        let board = try #require(state.daily)
        #expect(board.requests.count == 3)
        #expect(board.issuedCount == 3)
        #expect(board.requests.allSatisfy { $0.kind == .focus && $0.target == 20 })
        #expect(Set(board.requests.map { "\($0.region.rawValue):\($0.speciesID)" }).count == 3)
        #expect(board.requests.allSatisfy { PokopiaCrafting.materials.contains($0.reward) })
        let frozen = state
        #expect(!PokopiaCommunity.prepare(&state, context: context))
        #expect(state == frozen)
    }

    @Test func oneResidentGetsOneSlot() {
        var state = PokopiaCommunityState()
        _ = PokopiaCommunity.prepare(&state, context: CommunityFixture.context())
        #expect(state.daily?.requests.count == 1)
        #expect(state.daily?.requests.first?.speciesID == 1)
        #expect(state.daily?.requests.first?.region == .waste)
    }

    @Test func emptyIssueDoesNotRefillAfterImmigration() {
        var state = PokopiaCommunityState()
        _ = PokopiaCommunity.prepare(&state, context: CommunityFixture.context(residents: 0))
        #expect(state.daily?.isIssued == true)
        #expect(state.daily?.requests.isEmpty == true)
        #expect(!PokopiaCommunity.prepare(&state, context: CommunityFixture.context(residents: 5)))
        #expect(state.daily?.requests.isEmpty == true)
    }

    @Test func eligibilityExcludesUnknownBrushAndFinishedHabitat() throws {
        var context = CommunityFixture.context()
        let resident = try #require(context.towns["waste"]?.residents.first)
        #expect(PokopiaCommunity.eligibleKinds(region: .waste, resident: resident, context: context) == [.focus])
        context.availableBrushes = [.grass]
        #expect(PokopiaCommunity.eligibleKinds(region: .waste, resident: resident, context: context) == [.focus, .habitat])
        for index in 0..<5 { context.towns["waste"]?.terrain[index] = .grass }
        #expect(PokopiaCommunity.eligibleKinds(region: .waste, resident: resident, context: context) == [.focus, .habitat])
        context.towns["waste"]?.terrain[5] = .grass
        #expect(PokopiaCommunity.eligibleKinds(region: .waste, resident: resident, context: context) == [.focus])
    }

    @Test func foodEligibilityRequiresAnActualPath() throws {
        var context = CommunityFixture.context()
        let resident = try #require(context.towns["waste"]?.residents.first)
        #expect(PokopiaCommunity.eligibleKinds(region: .waste, resident: resident, context: context) == [.focus])
        context.canShareFood = true
        #expect(PokopiaCommunity.eligibleKinds(region: .waste, resident: resident, context: context) == [.focus, .meal])
    }

    @Test func dictionaryOrderDoesNotChangeAssignment() {
        let forward = CommunityFixture.context(residents: 5)
        var reversed = forward
        reversed.towns = Dictionary(uniqueKeysWithValues: forward.towns.sorted { $0.key > $1.key })
        var first = PokopiaCommunityState(), second = PokopiaCommunityState()
        _ = PokopiaCommunity.prepare(&first, context: forward)
        _ = PokopiaCommunity.prepare(&second, context: reversed)
        #expect(first == second)
    }
}
