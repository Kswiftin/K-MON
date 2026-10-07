import Foundation

/// 무료 외형. 기존 세이브의 기본형은 현재 본체 픽셀을 그대로 사용한다.
enum TrainerBaseHair: String, CaseIterable, Codable, Sendable {
    case classic, short, curly
    var name: String { switch self { case .classic: "기본형"; case .short: "짧은 머리"; case .curly: "곱슬머리" } }
}

enum TrainerSkinTone: String, CaseIterable, Codable, Sendable {
    case lightApricot, apricot, tan, darkBrown
    var name: String { ["밝은 살구", "살구", "황갈색", "짙은 갈색"][Self.allCases.firstIndex(of: self)!] }
    var colors: (base: UInt32, shade: UInt32) {
        switch self {
        case .lightApricot: (0xFFE0C5, 0xE6B99A)
        case .apricot: (0xF3C9A6, 0xD9A07A)
        case .tan: (0xC98E60, 0xA66A42)
        case .darkBrown: (0x85563D, 0x613C2B)
        }
    }
}

enum TrainerHairColor: String, CaseIterable, Codable, Sendable {
    case brown, black, blond, auburn, silver, blue
    var name: String { ["갈색", "검정", "금색", "밤색", "은색", "파랑"][Self.allCases.firstIndex(of: self)!] }
    var colors: (base: UInt32, shade: UInt32) {
        switch self {
        case .brown: (0x5A3A2A, 0x3A241A)
        case .black: (0x343440, 0x20202A)
        case .blond: (0xE3C55A, 0xA58A34)
        case .auburn: (0xA65338, 0x713625)
        case .silver: (0xCECEDB, 0x9696A6)
        case .blue: (0x3B6ED8, 0x284791)
        }
    }
}

enum OutfitTint: String, CaseIterable, Codable, Sendable {
    case red, blue, green, yellow, purple, pink, white, black
    var name: String { ["빨강", "파랑", "초록", "노랑", "보라", "분홍", "흰색", "검정"][Self.allCases.firstIndex(of: self)!] }
    var colors: (base: UInt32, shade: UInt32) {
        switch self {
        case .red: (0xD83A3A, 0x942828)
        case .blue: (0x3B6ED8, 0x284791)
        case .green: (0x4A9C68, 0x306944)
        case .yellow: (0xE3C55A, 0xA58A34)
        case .purple: (0x9361C4, 0x613E85)
        case .pink: (0xE988B0, 0xA85179)
        case .white: (0xF6F6F6, 0xBBBBCC)
        case .black: (0x3C3C50, 0x272735)
        }
    }
}

struct TrainerAppearance: Codable, Equatable, Sendable {
    var baseHair: TrainerBaseHair
    var skinTone: TrainerSkinTone
    var hairColor: TrainerHairColor
    static let creationDefault = TrainerAppearance(baseHair: .short)

    init(baseHair: TrainerBaseHair = .classic, skinTone: TrainerSkinTone = .apricot, hairColor: TrainerHairColor = .brown) {
        self.baseHair = baseHair; self.skinTone = skinTone; self.hairColor = hairColor
    }

    private enum CodingKeys: String, CodingKey { case baseHair, skinTone, hairColor }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseHair = (try? c.decode(TrainerBaseHair.self, forKey: .baseHair)) ?? .classic
        skinTone = (try? c.decode(TrainerSkinTone.self, forKey: .skinTone)) ?? .apricot
        hairColor = (try? c.decode(TrainerHairColor.self, forKey: .hairColor)) ?? .brown
    }

    var wireString: String? {
        var pairs: [String] = []
        if baseHair != .classic { pairs.append("hair:\(baseHair.rawValue)") }
        if skinTone != .apricot { pairs.append("skin:\(skinTone.rawValue)") }
        if hairColor != .brown { pairs.append("hairColor:\(hairColor.rawValue)") }
        return pairs.isEmpty ? nil : pairs.joined(separator: ",")
    }

    init(wireString: String) {
        self.init()
        for pair in wireString.split(separator: ",") {
            let p = pair.split(separator: ":", maxSplits: 1).map(String.init)
            guard p.count == 2 else { continue }
            switch p[0] {
            case "hair": if let v = TrainerBaseHair(rawValue: p[1]) { baseHair = v }
            case "skin": if let v = TrainerSkinTone(rawValue: p[1]) { skinTone = v }
            case "hairColor": if let v = TrainerHairColor(rawValue: p[1]) { hairColor = v }
            default: break
            }
        }
    }
}
