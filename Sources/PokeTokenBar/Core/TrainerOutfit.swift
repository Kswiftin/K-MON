import Foundation

/// 합성 순서가 곧 `allCases` 순서다 — body < bottom < top < hair < hat < accessory.
/// 모자가 머리카락 위에 오도록 hair 가 hat 앞이다.
enum OutfitSlot: String, CaseIterable, Codable, Sendable {
    case bottom, top, hair, hat, accessory
}

/// **rawValue 가 세이브·와이어 ID 다.** 바꾸면 기존 소유 목록이 사라지고 상대 카드가 base 로 보인다.
enum OutfitItem: String, CaseIterable, Codable, Sendable {
    case capRed = "cap_red", strawHat = "straw_hat"
    case hairBob = "hair_bob", hairPony = "hair_pony"
    case jacketBlue = "jacket_blue", teeWhite = "tee_white"
    case shortsKhaki = "shorts_khaki"
    case backpack
    case beanie, beret, hoodie, stripedTee = "striped_tee", longPants = "long_pants", crossbodyBag = "crossbody_bag"
    // 업적 보상 — 상점 미판매(`AchievementLadder.catalog` 의 outfits).
    case hairMessy = "hair_messy", cloakWorn = "cloak_worn", bootsLong = "boots_long", helmetExplorer = "helmet_explorer"

    var slot: OutfitSlot {
        switch self {
        case .capRed, .strawHat, .helmetExplorer, .beanie, .beret: return .hat
        case .hairBob, .hairPony, .hairMessy: return .hair
        case .jacketBlue, .teeWhite, .cloakWorn, .hoodie, .stripedTee: return .top
        case .shortsKhaki, .bootsLong, .longPants: return .bottom
        case .backpack, .crossbodyBag: return .accessory
        }
    }

    /// 별의조각. nil = 상점에 없다(업적 보상).
    var shopPrice: Int? {
        switch self {
        case .capRed, .beanie, .stripedTee: return 300
        case .strawHat, .beret, .longPants: return 400
        case .hairBob, .hairPony: return 300
        case .jacketBlue, .hoodie: return 500
        case .teeWhite: return 300
        case .shortsKhaki: return 300
        case .backpack, .crossbodyBag: return 800
        case .hairMessy, .cloakWorn, .bootsLong, .helmetExplorer: return nil
        }
    }
}

struct TrainerOutfit: Codable, Equatable, Sendable {
    var worn: [OutfitSlot: OutfitItem]
    var appearance: TrainerAppearance
    var tints: [OutfitSlot: OutfitTint]

    init(worn: [OutfitSlot: OutfitItem] = [:], appearance: TrainerAppearance = TrainerAppearance(),
         tints: [OutfitSlot: OutfitTint] = [:]) {
        self.worn = worn; self.appearance = appearance; self.tints = tints
    }

    /// 表示外형은 무료다. 착용과 염색만 소유·슬롯 경계를 적용한다.
    func normalized(owned: Set<OutfitItem>) -> TrainerOutfit {
        let valid = worn.filter { owned.contains($0.value) && $0.value.slot == $0.key }
        return TrainerOutfit(worn: valid, appearance: appearance,
            tints: tints.filter { valid[$0.key] != nil && $0.key != .hair })
    }

    var canonical: String {
        worn.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue):\($0.value.rawValue)" }.joined(separator: ",")
    }
    var wireString: String? { worn.isEmpty ? nil : canonical }
    var tintWireString: String? {
        let pairs = tints.filter { worn[$0.key]?.slot == $0.key && $0.key != .hair }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue):\($0.value.rawValue)" }
        return pairs.isEmpty ? nil : pairs.joined(separator: ",")
    }

    init(wireString: String) {
        self.init(wireString: wireString, appearanceWireString: nil, tintWireString: nil)
    }
    init(wireString: String, appearanceWireString: String?, tintWireString: String?) {
        self.init()
        for pair in wireString.split(separator: ",") {
            let p = pair.split(separator: ":", maxSplits: 1).map(String.init)
            guard p.count == 2, let slot = OutfitSlot(rawValue: p[0]),
                  let item = OutfitItem(rawValue: p[1]), item.slot == slot else { continue }
            worn[slot] = item
        }
        if let appearanceWireString { appearance = TrainerAppearance(wireString: appearanceWireString) }
        for pair in (tintWireString ?? "").split(separator: ",") {
            let p = pair.split(separator: ":", maxSplits: 1).map(String.init)
            guard p.count == 2, let slot = OutfitSlot(rawValue: p[0]), slot != .hair,
                  worn[slot] != nil, let tint = OutfitTint(rawValue: p[1]) else { continue }
            tints[slot] = tint
        }
    }

    private enum CodingKeys: String, CodingKey { case worn, appearance, tints }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(appearance: (try? c.decode(TrainerAppearance.self, forKey: .appearance)) ?? TrainerAppearance())
        let pairs = (try? c.decode(OutfitStringPairs.self, forKey: .worn))?.values ?? [:]
        for (key, value) in pairs {
            guard let slot = OutfitSlot(rawValue: key), let item = OutfitItem(rawValue: value), item.slot == slot else { continue }
            worn[slot] = item
        }
        let colors = (try? c.decode(OutfitStringPairs.self, forKey: .tints))?.values ?? [:]
        for (key, value) in colors {
            guard let slot = OutfitSlot(rawValue: key), slot != .hair, worn[slot] != nil,
                  let tint = OutfitTint(rawValue: value) else { continue }
            tints[slot] = tint
        }
    }
}

/// enum 키 사전의 교대 배열과 문자열 키 객체를 모두 읽고 손상은 항목별로 건너뛴다.
private struct OutfitStringPairs: Decodable {
    var values: [String: String] = [:]
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: Key.self) {
            for key in c.allKeys { if let value = try? c.decode(String.self, forKey: key) { values[key.stringValue] = value } }
        } else {
            var c = try decoder.unkeyedContainer()
            while !c.isAtEnd {
                let key = try? String(from: c.superDecoder())
                guard !c.isAtEnd else { break }
                let value = try? String(from: c.superDecoder())
                if let key, let value { values[key] = value }
            }
        }
    }
}
