import Foundation
import Testing
@testable import PokeTokenBar

@Suite("Regional forms, abilities and auction persistence")
struct RegionalAbilityPersistenceTests {
    @Test func regionalFormSurvivesSaveAndUsesItsPokemonID() throws {
        let mon = MonState(baseID: 37, pathIDs: [37, 38], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 2, regionalForm: .alola)
        #expect(mon.presentationID == 10096)
        #expect(mon.formQualifiedName("식스테일") == "알로라 식스테일")

        let restored = try JSONDecoder().decode(MonState.self, from: JSONEncoder().encode(mon))
        #expect(restored.regionalForm == .alola)
        #expect(restored.presentationID == 10096)
        #expect(PokemonAssets.clampedID(10096) == 10096)
    }

    @Test func abilityItemsAreIntentionallyExpensive() {
        #expect(ItemKind.abilityCapsule.shopPrice == 50_000)
        #expect(ItemKind.abilityPatch.shopPrice == 150_000)
        #expect(ItemKind.abilityPatch.shopPrice! > ItemKind.abilityCapsule.shopPrice!)
    }

    @MainActor @Test func auctionListingsSurviveAStoreRelaunch() async throws {
        let fileURL = storeFixtureDirectory("auction-persist").appendingPathComponent("state.json")
        let store = AuctionFixtures.makeStore("auction-persist", fileURL: fileURL)
        let listed = try await AuctionFixtures.sellableMon(store, baseID: 25)
        let first = PokemonAuctionCenter(companion: store)
        first.publish(listed)
        #expect(first.localListings.count == 1)

        let reopened = AuctionFixtures.makeStore("auction-persist", fileURL: fileURL)
        let restored = PokemonAuctionCenter(companion: reopened)
        #expect(restored.localListings.values.map(\.mon.id).contains(listed.id))
    }
}
