import Foundation

/// 화면에 표시하는 이름·설명과 상품 식별자로 상점의 현재 탭을 좁힌다.
struct ShopSearch {
    private let query: String

    init(_ query: String) {
        self.query = Self.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func matches(_ item: ItemKind, l: L) -> Bool {
        matches([l.itemName(item), l.itemDescription(item), item.rawValue])
    }

    func matches(egg tier: Rarity?, l: L) -> Bool {
        matches([l.eggName(tier), l.eggDescription(tier)])
    }

    func matches(_ item: OutfitItem, l: L) -> Bool {
        matches([l.outfitItemName(item), l.outfitSlotName(item.slot), item.rawValue])
    }

    func matches(_ machine: TechnicalMachine, name: String = "", description: String = "") -> Bool {
        matches([machine.label, String(machine.number), machine.slug,
                 machine.slug.replacingOccurrences(of: "-", with: " "), name, description])
    }

    private func matches(_ fields: [String]) -> Bool {
        query.isEmpty || fields.contains { Self.normalize($0).contains(query) }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
