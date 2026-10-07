import Testing
@testable import PokeTokenBar

@Suite("Shop search")
struct ShopSearchTests {
    private let l = L()

    @Test("items can be found by partial Korean names and descriptions")
    func itemNamesAndDescriptions() {
        let items: [ItemKind] = [.rareCandy, .mint, .fireStone, .leftovers]
        #expect(items.filter { ShopSearch("사탕").matches($0, l: l) } == [.rareCandy])
        #expect(items.filter { ShopSearch("경험치").matches($0, l: l) } == [.rareCandy])
        #expect(items.filter { ShopSearch("불꽃의돌").matches($0, l: l) } == [.fireStone])
        #expect(items.filter { ShopSearch("먹다남은").matches($0, l: l) } == [.leftovers])
    }

    @Test("blank queries keep the original order and unknown queries return no results")
    func blankAndUnknownQueries() {
        let items: [ItemKind] = [.mint, .rareCandy, .fireStone]
        #expect(items.filter { ShopSearch(" \n\t ").matches($0, l: l) } == items)
        #expect(items.filter { ShopSearch("존재하지않는상품").matches($0, l: l) }.isEmpty)
        #expect(items.filter { ShopSearch(" 사탕 \n").matches($0, l: l) } == [.rareCandy])
    }

    @Test("egg search uses the displayed name and description")
    func eggs() {
        let tiers: [Rarity?] = [nil, .uncommon, .rare]
        #expect(tiers.filter { ShopSearch("희귀").matches(egg: $0, l: l) } == [.rare])
        #expect(tiers.filter { ShopSearch("소유 포켓몬").matches(egg: $0, l: l) } == [nil])
        #expect(tiers.filter { ShopSearch("").matches(egg: $0, l: l) } == tiers)
    }

    @Test("outfit search uses both names and slots")
    func outfits() {
        let items: [OutfitItem] = [.capRed, .strawHat, .jacketBlue]
        #expect(items.filter { ShopSearch("빨간").matches($0, l: l) } == [.capRed])
        #expect(items.filter { ShopSearch("모자").matches($0, l: l) } == [.capRed, .strawHat])
        #expect(items.filter { ShopSearch("").matches($0, l: l) } == items)
    }

    @Test("machine search supports TM labels, numbers, slugs, localized names and descriptions")
    func machines() {
        let machine = TechnicalMachine(number: 13, moveID: 58, slug: "ice-beam", price: 1_000)
        for query in ["tm13", "13", "ICE BEAM", "ice-beam", "냉동", "얼려"] {
            #expect(ShopSearch(query).matches(machine, name: "냉동빔", description: "상대를 얼려요."))
        }
        #expect(!ShopSearch("화염방사").matches(machine, name: "냉동빔", description: "상대를 얼려요."))
    }

    @Test("machine labels and slugs work before metadata arrives")
    func unresolvedMachines() {
        let machine = TechnicalMachine(number: 13, moveID: 58, slug: "ice-beam", price: 1_000)
        #expect(ShopSearch("TM13").matches(machine))
        #expect(ShopSearch("ice beam").matches(machine))
        #expect(ShopSearch("").matches(machine))
    }

    @Test("search ignores case and diacritics")
    func normalizedMachineName() {
        let machine = TechnicalMachine(number: 1, moveID: 468, slug: "hone-claws", price: 1_000)
        #expect(ShopSearch(" cafe ").matches(machine, name: "Café"))
    }
}
