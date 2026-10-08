import Foundation
import Testing
@testable import PokeTokenBar

@Suite("트레이너 외형과 의상 데이터")
struct TrainerAppearanceTests {
    @Test func legacyDictionaryAndUnknownEntries() throws {
        let json = #"{"worn":["hat","cap_red","future_slot","future_item","top",17,"hair","hair_bob","bottom"],"appearance":{"baseHair":"future","skinTone":"tan","hairColor":17},"tints":{"hat":"blue","hair":"red","future":"pink"}}"#
        let outfit = try JSONDecoder().decode(TrainerOutfit.self, from: Data(json.utf8))
        #expect(outfit.worn == [.hat: .capRed, .hair: .hairBob])
        #expect(outfit.appearance.baseHair == .classic)
        #expect(outfit.appearance.skinTone == .tan)
        #expect(outfit.appearance.hairColor == .brown)
        #expect(outfit.tints == [.hat: .blue])
        let keyed = try JSONDecoder().decode(TrainerOutfit.self, from: Data(#"{"worn":{"hat":"cap_red","top":"future","hair":"hair_pony"},"appearance":false}"#.utf8))
        #expect(keyed.worn == [.hat: .capRed, .hair: .hairPony])
        #expect(keyed.appearance == TrainerAppearance())
    }

    @Test func legacyDefaultsAndRoundTrip() throws {
        let old = try JSONDecoder().decode(TrainerOutfit.self, from: Data(#"{"worn":["hat","cap_red"]}"#.utf8))
        #expect(old.appearance.baseHair == .classic)
        #expect(old.appearance.skinTone == .apricot)
        #expect(old.appearance.hairColor == .brown)
        #expect(old.tints.isEmpty)
        let outfit = TrainerOutfit(worn: [.hat: .beanie], appearance: .creationDefault, tints: [.hat: .pink])
        #expect(try JSONDecoder().decode(TrainerOutfit.self, from: JSONEncoder().encode(outfit)) == outfit)
        #expect(TrainerAppearance.creationDefault.baseHair == .short)
    }

    @Test func missingOrMalformedWardrobeDoesNotDiscardAppearance() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(TrainerOutfit.self, from: Data("{}".utf8)) == TrainerOutfit())
        for json in [
            #"{"appearance":{"baseHair":"curly","skinTone":"tan","hairColor":"silver"}}"#,
            #"{"worn":42,"appearance":{"baseHair":"curly","skinTone":"tan","hairColor":"silver"},"tints":false}"#
        ] {
            let outfit = try decoder.decode(TrainerOutfit.self, from: Data(json.utf8))
            #expect(outfit.worn.isEmpty)
            #expect(outfit.tints.isEmpty)
            #expect(outfit.appearance == TrainerAppearance(baseHair: .curly, skinTone: .tan, hairColor: .silver))
        }
    }

    @Test func normalizationKeepsAppearanceAndOnlyValidTints() {
        let outfit = TrainerOutfit(worn: [.hat: .beanie, .top: .hoodie, .hair: .hairBob],
            appearance: .creationDefault, tints: [.hat: .pink, .top: .green, .hair: .blue, .bottom: .black])
        let normalized = outfit.normalized(owned: [.beanie, .hairBob])
        #expect(normalized.worn == [.hat: .beanie, .hair: .hairBob])
        #expect(normalized.tints == [.hat: .pink])
        #expect(normalized.appearance == .creationDefault)
    }

    @Test func wireStringsRemainCompatibleAndDeterministic() {
        let outfit = TrainerOutfit(worn: [.top: .jacketBlue, .hat: .capRed],
            appearance: TrainerAppearance(baseHair: .curly, skinTone: .tan, hairColor: .silver),
            tints: [.top: .green, .hat: .pink])
        #expect(outfit.wireString == "hat:cap_red,top:jacket_blue")
        #expect(outfit.canonical == "hat:cap_red,top:jacket_blue")
        #expect(outfit.appearance.wireString == "hair:curly,skin:tan,hairColor:silver")
        #expect(outfit.tintWireString == "hat:pink,top:green")
        #expect(TrainerOutfit(wireString: outfit.wireString!, appearanceWireString: outfit.appearance.wireString,
            tintWireString: outfit.tintWireString) == outfit)
        #expect(TrainerAppearance().wireString == nil)
        #expect(TrainerOutfit().tintWireString == nil)
        let remote = TrainerOutfit(wireString: "hat:cap_red", appearanceWireString: "hair:curly,skin:future,hairColor:blue,garbage",
            tintWireString: "hat:pink,top:green,hair:red,unknown:black")
        #expect(remote.appearance == TrainerAppearance(baseHair: .curly, hairColor: .blue))
        #expect(remote.tints == [.hat: .pink])
    }

    @Test func newCatalogHasStableSlotsPricesAndNames() {
        let expected: [(OutfitItem, OutfitSlot, Int, String)] = [
            (.beanie, .hat, 300, "beanie"), (.beret, .hat, 400, "beret"),
            (.hoodie, .top, 500, "hoodie"), (.stripedTee, .top, 300, "striped_tee"),
            (.longPants, .bottom, 400, "long_pants"), (.crossbodyBag, .accessory, 800, "crossbody_bag")]
        for (item, slot, price, id) in expected {
            #expect(item.slot == slot)
            #expect(item.shopPrice == price)
            #expect(item.rawValue == id)
            #expect(!L().outfitItemName(item).isEmpty)
        }
        #expect(OutfitItem.allCases.count == 18)
        #expect(OutfitItem.allCases.filter { $0.shopPrice != nil }.count == 14)
        #expect(OutfitItem.allCases.filter { $0.shopPrice == nil }.count == 4)
    }
}
