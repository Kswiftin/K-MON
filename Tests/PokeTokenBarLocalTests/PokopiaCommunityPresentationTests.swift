import Foundation
import Testing
@testable import PokeTokenBar

@Suite struct PokopiaCommunityPresentationTests {
    private func state() -> PokopiaCommunityState {
        var state = PokopiaCommunityState()
        _ = PokopiaCommunity.prepare(&state, context: CommunityFixture.context())
        return state
    }

    @Test func conversationKeepsItsOwnerAcrossRegionChanges() throws {
        var context = CommunityFixture.context()
        let selection = PokopiaConversationSelection(region: .waste, speciesID: 1, arrivedAt: CommunityFixture.now)
        var coast = PokopiaTownState(region: .coast)
        coast.residents = [.init(speciesID: 1, name: "해안 주민", types: [.water], arrivedAt: CommunityFixture.now)]
        context.towns["coast"] = coast
        var state = state()
        let content = PokopiaCommunityPresentation.conversation(selection: selection, state: state, context: context,
            season: .autumn, timeOfDay: .day)
        #expect(content.resident?.name == "주민1")
        #expect(content.request?.region == .waste)
        context.towns["waste"]?.residents = []
        let gone = PokopiaCommunityPresentation.conversation(selection: selection, state: state, context: context,
            season: .autumn, timeOfDay: .day)
        #expect(gone.resident == nil && gone.dialogue == nil)
        let id = try #require(state.daily?.requests.first?.id)
        state.daily?.focusMinutes = 20
        #expect(PokopiaCommunity.claim(requestID: id, context: context, in: &state) == nil)
    }

    @Test func cardsShowOnlyTheSelectedRegion() throws {
        let context = CommunityFixture.context(residents: 5)
        var state = PokopiaCommunityState()
        _ = PokopiaCommunity.prepare(&state, context: context)
        for region in TownRegion.allCases {
            let cards = PokopiaCommunityPresentation.cards(state: state, context: context, region: region)
            #expect(cards.allSatisfy { $0.region == region })
            let expected = try #require(state.daily?.requests.filter { $0.region == region }.map(\.id))
            #expect(cards.map(\.id) == expected)
        }
    }

    @Test func completedCardKeepsItsClaimedState() throws {
        var state = state(), context = CommunityFixture.context()
        let id = try #require(state.daily?.requests.first?.id)
        state.daily?.focusMinutes = 20
        _ = PokopiaCommunity.claim(requestID: id, context: context, in: &state)
        context.towns["waste"]?.residents = []
        let card = try #require(PokopiaCommunityPresentation.cards(state: state, context: context, region: .waste).first)
        #expect(card.status == .claimed)
        #expect(card.residentName == "#1")
    }

    @Test func missingResidentUsesSpeciesFallbackName() throws {
        var context = CommunityFixture.context()
        context.towns["waste"]?.residents = []
        let card = try #require(PokopiaCommunityPresentation.cards(state: state(), context: context, region: .waste).first)
        #expect(card.residentName == "#1")
        #expect(card.status == .residentLeft)
    }

    @Test func replacedResidentIsNotTheSelectedConversation() {
        var context = CommunityFixture.context()
        let selection = PokopiaConversationSelection(region: .waste, speciesID: 1, arrivedAt: CommunityFixture.now)
        context.towns["waste"]?.residents[0].arrivedAt = CommunityFixture.now.addingTimeInterval(1)
        let content = PokopiaCommunityPresentation.conversation(selection: selection, state: state(), context: context,
            season: .autumn, timeOfDay: .day)
        #expect(content.resident == nil && content.dialogue == nil)
    }
}
