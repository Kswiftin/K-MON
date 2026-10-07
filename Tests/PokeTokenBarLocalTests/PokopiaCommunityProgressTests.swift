import Foundation
import Testing
@testable import PokeTokenBar

@Suite struct PokopiaCommunityProgressTests {
    private func issued(_ kind: PokopiaRequestKind = .focus) -> PokopiaCommunityState {
        var state = PokopiaCommunityState()
        state.daily = PokopiaDailyBoard(dayKey: "2026-10-07", issuedCount: 1, requests: [
            .init(id: "test", region: .waste, speciesID: 1, arrivedAt: CommunityFixture.now,
                  kind: kind, terrain: kind == .habitat ? .grass : nil,
                  target: kind == .focus ? 20 : kind == .habitat ? 6 : 1, reward: .townWood)
        ])
        return state
    }

    @Test func focusRewardCanOnlyBeClaimedOnce() {
        let context = CommunityFixture.context()
        var state = issued()
        #expect(PokopiaCommunity.recordFocusMinutes(19, dayKey: context.dayKey, in: &state))
        #expect(PokopiaCommunity.claim(requestID: "test", context: context, in: &state) == nil)
        #expect(PokopiaCommunity.recordFocusMinutes(1, dayKey: context.dayKey, in: &state))
        #expect(PokopiaCommunity.claim(requestID: "test", context: context, in: &state)?.item == .townWood)
        let claimed = state
        #expect(PokopiaCommunity.claim(requestID: "test", context: context, in: &state) == nil)
        #expect(state == claimed)
        #expect(state.totalCompleted == 1)
        #expect(state.friendships["waste:1"] == 1)
        #expect(state.milestones.contains(.firstThanks))
    }

    @Test func invalidMinutesDoNotAdvance() {
        var state = issued()
        for amount in [0, -1, FocusSessionLog.maxSessionMinutes + 1, Int.max] {
            #expect(!PokopiaCommunity.recordFocusMinutes(amount, dayKey: "2026-10-07", in: &state))
        }
        #expect(state.daily?.focusMinutes == 0)
        var empty = PokopiaCommunityState()
        #expect(!PokopiaCommunity.recordFocusMinutes(20, dayKey: "2026-10-07", in: &empty))
    }

    @Test func habitatTracksFiveSixAndUndo() throws {
        var state = issued(.habitat), context = CommunityFixture.context()
        let request = try #require(state.daily?.requests.first)
        for index in 0..<5 { context.towns["waste"]?.terrain[index] = .grass }
        #expect(PokopiaCommunity.status(request, state: state, context: context) == .inProgress(current: 5, target: 6))
        context.towns["waste"]?.terrain[5] = .grass
        #expect(PokopiaCommunity.status(request, state: state, context: context) == .ready)
        context.towns["waste"]?.terrain[5] = .sand
        #expect(PokopiaCommunity.claim(requestID: "test", context: context, in: &state) == nil)
        context.towns["waste"]?.terrain[5] = .grass
        #expect(PokopiaCommunity.claim(requestID: "test", context: context, in: &state) != nil)
        context.towns["waste"]?.terrain[5] = .sand
        context.towns["waste"]?.residents = []
        let claimed = try #require(state.daily?.requests.first)
        #expect(PokopiaCommunity.status(claimed, state: state, context: context) == .claimed)
        #expect(PokopiaCommunity.claim(requestID: "test", context: context, in: &state) == nil)
    }

    @Test func mealIsScopedToItsRegion() throws {
        var state = issued(.meal)
        let context = CommunityFixture.context()
        let request = try #require(state.daily?.requests.first)
        #expect(PokopiaCommunity.recordMeal(region: .coast, dayKey: context.dayKey, in: &state))
        #expect(PokopiaCommunity.status(request, state: state, context: context) == .inProgress(current: 0, target: 1))
        #expect(PokopiaCommunity.recordMeal(region: .waste, dayKey: context.dayKey, in: &state))
        #expect(!PokopiaCommunity.recordMeal(region: .waste, dayKey: context.dayKey, in: &state))
        #expect(PokopiaCommunity.claim(requestID: "test", context: context, in: &state) != nil)
    }

    @Test func replacementResidentCannotClaim() throws {
        var state = issued(), context = CommunityFixture.context()
        state.daily?.focusMinutes = 20
        context.towns["waste"]?.residents[0].arrivedAt = CommunityFixture.now.addingTimeInterval(1)
        #expect(PokopiaCommunity.status(try #require(state.daily?.requests.first), state: state, context: context) == .residentLeft)
        #expect(PokopiaCommunity.claim(requestID: "test", context: context, in: &state) == nil)
    }

    @Test func friendshipThresholdsAndRegionIdentity() {
        #expect(PokopiaCommunity.friendshipLevel(points: 2) == .newNeighbor)
        #expect(PokopiaCommunity.friendshipLevel(points: 3) == .familiarNeighbor)
        #expect(PokopiaCommunity.friendshipLevel(points: 9) == .familiarNeighbor)
        #expect(PokopiaCommunity.friendshipLevel(points: 10) == .trustedFriend)
        var state = issued()
        state.daily?.focusMinutes = 20
        state.friendships = ["waste:1": 10, "coast:1": 2]
        _ = PokopiaCommunity.claim(requestID: "test", context: CommunityFixture.context(), in: &state)
        #expect(state.friendships == ["waste:1": 10, "coast:1": 2])
    }

    @Test func nextDayKeepsFriendshipAndMilestones() {
        var state = issued()
        state.friendships = ["waste:1": 3]
        state.milestones = [.firstThanks]
        state.totalCompleted = 7
        #expect(PokopiaCommunity.prepare(&state, context: CommunityFixture.context(dayKey: "2026-10-08")))
        #expect(state.daily?.focusMinutes == 0)
        #expect(state.friendships == ["waste:1": 3])
        #expect(state.milestones == [.firstThanks])
        #expect(state.totalCompleted == 7)
    }

    @Test func clockRollbackDoesNotOpenRewards() throws {
        var state = issued()
        state.daily?.focusMinutes = 20
        let context = CommunityFixture.context(dayKey: "2026-10-06")
        let frozen = state
        #expect(!PokopiaCommunity.prepare(&state, context: context))
        #expect(!PokopiaCommunity.recordFocusMinutes(20, dayKey: context.dayKey, in: &state))
        #expect(PokopiaCommunity.status(try #require(state.daily?.requests.first), state: state, context: context) == .blocked)
        #expect(PokopiaCommunity.claim(requestID: "test", context: context, in: &state) == nil)
        #expect(state == frozen)
    }

    @Test func milestonesLatchExistingTownConditions() {
        var context = CommunityFixture.context(), state = PokopiaCommunityState()
        context.towns["waste"]?.terrain = TownTerrain.allCases.flatMap { Array(repeating: $0, count: 24) }
        // 물 한 칸을 풀밭 안에 놓아 실제로 맞닿은 연못 풀숲을 만든다.
        context.towns["waste"]?.terrain[0] = .water
        state.totalCompleted = 30
        #expect(PokopiaCommunity.refreshMilestones(&state, towns: context.towns))
        #expect(state.milestones == Set(PokopiaMilestone.allCases))
        #expect(!PokopiaCommunity.refreshMilestones(&state, towns: [:]))
        #expect(state.milestones == Set(PokopiaMilestone.allCases))
    }

    @Test func completionAtIntMaxDoesNotOverflow() {
        var state = issued()
        state.daily?.focusMinutes = 20
        state.totalCompleted = Int.max
        state.friendships["waste:1"] = Int.max
        #expect(PokopiaCommunity.claim(requestID: "test", context: CommunityFixture.context(), in: &state) != nil)
        #expect(state.totalCompleted == Int.max)
        #expect(state.friendships["waste:1"] == 10)
    }
}
