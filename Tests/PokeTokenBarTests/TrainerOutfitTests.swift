import XCTest
@testable import PokeTokenBar

final class TrainerOutfitTests: XCTestCase {
    func testEveryItemHasOneSlotAndShopItemsHavePositivePrices() {
        for item in OutfitItem.allCases {
            XCTAssertTrue(OutfitSlot.allCases.contains(item.slot))
            if let price = item.shopPrice { XCTAssertGreaterThan(price, 0, "\(item)") }
        }
        XCTAssertEqual(OutfitItem.allCases.filter { $0.shopPrice != nil }.count, 8)
        XCTAssertEqual(OutfitItem.allCases.filter { $0.shopPrice == nil }.count, 4)
    }

    func testRawValuesAreFrozenSnakeCase() {
        // 세이브·와이어 ID 다. 바꾸면 기존 세이브의 소유 목록이 사라진다.
        XCTAssertEqual(OutfitItem.capRed.rawValue, "cap_red")
        XCTAssertEqual(OutfitItem.helmetExplorer.rawValue, "helmet_explorer")
    }

    func testNormalizedDropsUnownedItems() {
        let outfit = TrainerOutfit(worn: [.hat: .capRed, .top: .jacketBlue])
        XCTAssertEqual(outfit.normalized(owned: [.capRed]).worn, [.hat: .capRed])
    }

    func testWireStringRoundTripsAndIsSorted() {
        let outfit = TrainerOutfit(worn: [.top: .jacketBlue, .hat: .capRed])
        XCTAssertEqual(outfit.wireString, "hat:cap_red,top:jacket_blue")
        XCTAssertEqual(TrainerOutfit(wireString: outfit.wireString!), outfit)
    }

    func testEmptyOutfitHasNoWireString() {
        XCTAssertNil(TrainerOutfit().wireString)
    }

    func testWireParsingSkipsUnknownAndMalformedEntries() {
        let parsed = TrainerOutfit(wireString: "hat:cap_red,wings:dragon,top:unknown_item,garbage")
        XCTAssertEqual(parsed.worn, [.hat: .capRed])
    }

    func testWireParsingRejectsItemInWrongSlot() {
        XCTAssertEqual(TrainerOutfit(wireString: "hat:jacket_blue").worn, [:])
    }

    func testCodableRoundTrip() throws {
        let outfit = TrainerOutfit(worn: [.hair: .hairPony])
        let data = try JSONEncoder().encode(outfit)
        XCTAssertEqual(try JSONDecoder().decode(TrainerOutfit.self, from: data), outfit)
    }

    func testCanonicalIsSortedAndStable() {
        let a = TrainerOutfit(worn: [.top: .teeWhite, .hat: .strawHat])
        XCTAssertEqual(a.canonical, "hat:straw_hat,top:tee_white")
    }

    func testEveryItemAndSlotIsNamedInAllThreeLanguages() {
        for lang in [AppLanguage.ko, .en, .ja] {
            for item in OutfitItem.allCases { XCTAssertFalse(L(lang).outfitItemName(item).isEmpty, "\(item) \(lang)") }
            for slot in OutfitSlot.allCases { XCTAssertFalse(L(lang).outfitSlotName(slot).isEmpty, "\(slot) \(lang)") }
        }
    }
}
