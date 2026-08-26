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
    // 업적 보상 — 상점 미판매(`AchievementLadder.catalog` 의 outfits).
    case hairMessy = "hair_messy", cloakWorn = "cloak_worn", bootsLong = "boots_long", helmetExplorer = "helmet_explorer"

    var slot: OutfitSlot {
        switch self {
        case .capRed, .strawHat, .helmetExplorer: return .hat
        case .hairBob, .hairPony, .hairMessy: return .hair
        case .jacketBlue, .teeWhite, .cloakWorn: return .top
        case .shortsKhaki, .bootsLong: return .bottom
        case .backpack: return .accessory
        }
    }

    /// 별의조각. nil = 상점에 없다(업적 보상).
    var shopPrice: Int? {
        switch self {
        case .capRed: return 300
        case .strawHat: return 400
        case .hairBob, .hairPony: return 300
        case .jacketBlue: return 500
        case .teeWhite: return 300
        case .shortsKhaki: return 300
        case .backpack: return 800
        case .hairMessy, .cloakWorn, .bootsLong, .helmetExplorer: return nil
        }
    }
}

struct TrainerOutfit: Codable, Equatable, Sendable {
    var worn: [OutfitSlot: OutfitItem]

    init(worn: [OutfitSlot: OutfitItem] = [:]) { self.worn = worn }

    /// 세이브 신뢰경계 — 소유하지 않은 것은 벗긴다(슬롯이 맞지 않는 것도).
    func normalized(owned: Set<OutfitItem>) -> TrainerOutfit {
        TrainerOutfit(worn: worn.filter { owned.contains($0.value) && $0.value.slot == $0.key })
    }

    private var sortedPairs: [String] {
        worn.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue):\($0.value.rawValue)" }
    }

    /// 무결성·와이어 공용 문자열. **정렬**해야 같은 상태가 같은 문자열을 낸다.
    var canonical: String { sortedPairs.joined(separator: ",") }

    /// TXT 레코드 값. 비었으면 nil — 키를 싣지 않는다(`PeerAdvertisement` 규칙).
    var wireString: String? { worn.isEmpty ? nil : canonical }

    /// 관대 파싱 — 모르는 슬롯·아이템·슬롯 불일치·형식 오류는 건너뛴다. 실패하지 않는다.
    init(wireString: String) {
        var worn: [OutfitSlot: OutfitItem] = [:]
        for pair in wireString.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let slot = OutfitSlot(rawValue: parts[0]),
                  let item = OutfitItem(rawValue: parts[1]), item.slot == slot else { continue }
            worn[slot] = item
        }
        self.worn = worn
    }
}
