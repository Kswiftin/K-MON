import Foundation

enum BattleRankTier: Int, Codable, Sendable, CaseIterable, Comparable {
    /// Pokémon Champions의 랭크 순서. 각 볼 티어는 Rank 4 → 1, 이후 Champion 단일 티어다.
    case pokeBall, greatBall, ultraBall, masterBall, champion

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var name: String {
        switch self {
        case .pokeBall: "Poké Ball"
        case .greatBall: "Great Ball"
        case .ultraBall: "Ultra Ball"
        case .masterBall: "Master Ball"
        case .champion: "Champion"
        }
    }
}

struct BattleRank: Codable, Sendable, Equatable {
    static let maximumPoints = 3_999
    var points = 0

    /// 랭크는 와이어로도 온다(`BattleRankProfile` — **상대가 채우는 값**). 그래서 값이 들어오는
    /// 경계 한 곳에서 자른다. 세이브 경로는 `SaveTransfer.sanitized` 가 이미 자르지만 와이어
    /// 경로엔 가드가 없었다 — 파생값(`tier`·`lp`)마다 `max(0, ·)` 를 흩뿌리는 대신 여기서 끝낸다.
    ///
    /// 다만 클램프는 위생 조치일 뿐이다 — **자기 랭크를 스스로 신고한다는 사실은 못 막는다.**
    /// 높은 티어를 주장하면 내 승리 LP(최대 +70)와 판돈(최대 45,000)이 정상 범위 안에서 커진다.
    /// 공유 원장 없는 P2P 의 한계라 서명·서버가 필요하다(defect-log 참조).
    static func clamped(_ points: Int) -> Int { min(maximumPoints, max(0, points)) }

    init(points: Int = 0) { self.points = Self.clamped(points) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = Self.clamped(try c.decodeIfPresent(Int.self, forKey: .points) ?? 0)
    }

    var tier: BattleRankTier {
        BattleRankTier(rawValue: min(BattleRankTier.champion.rawValue, max(0, points) / 400)) ?? .pokeBall
    }
    var division: Int? { tier < .champion ? 4 - ((max(0, points) % 400) / 100) : nil }
    var lp: Int { max(0, points) % 100 }
    var displayName: String {
        if let division { return "\(tier.name) R\(division) · \(lp) LP" }
        return "\(tier.name) · \(max(0, points - 1_600)) RP"
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

    /// 판돈 상한 — `stake` 가 낼 수 있는 최대치다(티어 격차 최대 4 × 5,000). 세이브에 실려 오는
    /// 에스크로(`PendingRankedBattle`)도 이 값으로 자른다. 승리 정산이 `escrowed * 2` 를 지급하므로
    /// 일반 수치 상한(`SaveTransfer.maxTokenValue`, 10^15)까지 허용하면 손으로 만든 세이브 한 장이
    /// 별의조각을 찍어낸다.
    static let maximumStake = 20_000

    /// 낮은 랭크가 높은 랭크에 도전할 때만 발생하는 고정 판돈.
    static func stake(challenger: BattleRank, defender: BattleRank) -> Int {
        guard challenger.tier < defender.tier else { return 0 }
        return min(maximumStake, max(5_000, (defender.tier.rawValue - challenger.tier.rawValue) * 5_000))
    }
}

struct BattleRankProfile: Codable, Sendable, Equatable {
    var rank: BattleRank
    var stardust: Int
    var beginnerMode: Bool

    init(rank: BattleRank, stardust: Int, beginnerMode: Bool = false) {
        self.rank = rank
        self.stardust = stardust
        self.beginnerMode = beginnerMode
    }

    private enum CodingKeys: String, CodingKey { case rank, stardust, beginnerMode }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try c.decode(BattleRank.self, forKey: .rank)
        stardust = try c.decode(Int.self, forKey: .stardust)
        beginnerMode = try c.decodeIfPresent(Bool.self, forKey: .beginnerMode) ?? false
    }
}
