import Foundation

enum BattleRankTier: Int, Codable, Sendable, CaseIterable, Comparable {
    case iron, bronze, silver, gold, platinum, emerald, diamond, master, grandmaster, challenger

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var name: String {
        switch self {
        case .iron: "Iron"
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        case .emerald: "Emerald"
        case .diamond: "Diamond"
        case .master: "Master"
        case .grandmaster: "Grandmaster"
        case .challenger: "Challenger"
        }
    }
}

struct BattleRank: Codable, Sendable, Equatable {
    static let maximumPoints = 3_999
    var points = 0

    var tier: BattleRankTier {
        BattleRankTier(rawValue: min(9, max(0, points) / 400)) ?? .iron
    }
    var division: Int? { tier < .master ? 4 - ((max(0, points) % 400) / 100) : nil }
    var lp: Int { max(0, points) % 100 }
    var displayName: String {
        division.map { "\(tier.name) \($0) · \(lp) LP" } ?? "\(tier.name) · \(lp) LP"
    }

    mutating func apply(win: Bool, opponent: BattleRank) -> Int {
        let before = points
        if win {
            let gap = max(0, opponent.tier.rawValue - tier.rawValue)
            points = min(Self.maximumPoints, points + 25 + gap * 5)
        } else if tier > opponent.tier {
            let gap = tier.rawValue - opponent.tier.rawValue
            points = max(0, points - (25 + gap * 5))
        }
        return points - before
    }

    /// 낮은 랭크가 높은 랭크에 도전할 때만 발생하는 고정 판돈.
    static func stake(challenger: BattleRank, defender: BattleRank) -> Int {
        guard challenger.tier < defender.tier else { return 0 }
        return min(50_000, max(5_000, (defender.tier.rawValue - challenger.tier.rawValue) * 5_000))
    }
}

struct BattleRankProfile: Codable, Sendable, Equatable {
    var rank: BattleRank
    var stardust: Int
}
