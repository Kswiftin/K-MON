import Foundation

enum AdventureZone: String, Codable, Sendable, CaseIterable, Identifiable {
    case forest, cave, coast
    var id: String { rawValue }
    var duration: TimeInterval {
        switch self { case .forest: 10 * 60; case .cave: 30 * 60; case .coast: 2 * 60 * 60 }
    }
    var rewardMultiplier: Double {
        switch self { case .forest: 1; case .cave: 2.4; case .coast: 7.5 }
    }
    var symbol: String {
        switch self { case .forest: "leaf.fill"; case .cave: "mountain.2.fill"; case .coast: "water.waves" }
    }
}

struct AdventureRun: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var zone: AdventureZone
    var startedAt: Date
    var endsAt: Date
    var companionSpeciesID: Int
    func isComplete(at date: Date) -> Bool { date >= endsAt }
    func progress(at date: Date) -> Double {
        let total = max(1, endsAt.timeIntervalSince(startedAt))
        return min(1, max(0, date.timeIntervalSince(startedAt) / total))
    }
}

struct AdventureReward: Sendable, Equatable {
    let experience: Int
    let starPieces: Int
    let foundRareCandy: Bool
    let foundEgg: Bool
    var eggFragments = 0
    var bonusEggs = 0
    /// 이 정산으로 트레이너 레벨이 올라 함께 지급된 별의조각. 보상 객체가 실제 지급액을 전부
    /// 설명해야 한다 — 밖에서 몰래 더하면 UI 가 알려준 값과 지갑이 어긋난다.
    var trainerBonus = 0
    /// 이 정산으로 완료된 미션이 함께 지급한 별의조각. `trainerBonus` 와 같은 이유로 여기 실린다 —
    /// 지갑에 더하는 경로가 하나 더 생겼는데 보상 객체가 모르면 그만큼이 설명되지 않는다.
    var missionBonus = 0
    /// 이번 정산에서 넘은 업적 단계가 지급한 별의조각. 위 둘과 같은 계약이다.
    var achievementBonus = 0
    /// 이번 정산으로 완료된 시즌 챌린지가 지급한 별의조각. 위 셋과 같은 계약이다.
    var seasonBonus = 0
    /// 만렙에 걸려 개체에 적립되지 못한 경험치(원 단위). 위 넷과 같은 계약으로 이 몫도 지갑에
    /// 들어가 있다 — 다만 지급 단위가 경험치가 아니라 그 환산분(`overflowBonus`)이다.
    var overflowExperience = 0
    /// 위 초과분을 되돌린 별의조각. 저장하지 않고 계산한다 — 원 단위와 환산분을 각각 저장하면
    /// 둘이 어긋난 상태가 표현 가능해진다.
    var overflowBonus: Int { PokemonBalance.starPieces(forOverflowExperience: overflowExperience) }
    /// 실제로 개체에 들어간 경험치. 만렙이면 `experience` 보다 작다 — 굴린 값을 그대로 "얻은
    /// 경험치" 로 보고하면 오르지도 않은 레벨을 올랐다고 말하게 된다.
    var appliedExperience: Int { experience - overflowExperience }
    var stardust: Int { starPieces }
    /// 이 정산이 지갑에 더한 별의조각 **전부**. 지급 경로가 하나 늘 때 합산 지점(대화 도구·
    /// 테스트)이 따라오지 않는 부류를 이 한 곳으로 막는다 — 실제로 미션 몫이 그렇게 빠졌었다.
    var totalStardust: Int {
        starPieces + overflowBonus + trainerBonus + missionBonus + achievementBonus + seasonBonus
    }
}

struct FocusSessionReward: Sendable, Equatable {
    let minutes: Int
    let stardust: Int
    let foundEgg: Bool
    var trainerBonus = 0
    var missionBonus = 0
    var achievementBonus = 0
    var seasonBonus = 0
    /// `AdventureReward.overflowExperience` 를 그대로 옮겨 싣는다 — 집중 세션도 같은 정산을
    /// 지나므로 완전설명 계약이 여기서 끊기면 안 된다.
    var overflowExperience = 0
    var overflowBonus: Int { PokemonBalance.starPieces(forOverflowExperience: overflowExperience) }
    var totalStardust: Int {
        stardust + overflowBonus + trainerBonus + missionBonus + achievementBonus + seasonBonus
    }
}

enum FocusRewardRules {
    /// 긴 세션은 분당 보상이 증가한다: 25분 10M, 50분 24M, 90분 50.4M.
    static func stardust(minutes: Int) -> Int {
        let m = max(1, minutes)
        let longBonus = 1 + min(0.6, Double(max(0, m - 25)) / 100)
        return Int((Double(m) * 400_000 * longBonus).rounded())
    }

    /// 25/50/90분 기준 알 확률 1%/3%/7%. roll은 0..<10,000.
    static func eggChanceBasisPoints(minutes: Int) -> Int {
        if minutes >= 90 { return 700 }
        if minutes >= 50 { return 300 }
        return 100
    }

    static func reward(minutes: Int, roll: Int) -> FocusSessionReward {
        FocusSessionReward(minutes: minutes, stardust: stardust(minutes: minutes),
                           foundEgg: max(0, roll) % 10_000 < eggChanceBasisPoints(minutes: minutes))
    }
}

struct AdventureRecord: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var zone: AdventureZone
    var companionSpeciesID: Int
    var completedAt: Date
    var stardust: Int
    var foundRareCandy: Bool
}

enum AdventureRules {
    static func amounts(minutes: Int) -> (experience: Int, starPieces: Int) {
        let m = Double(max(1, minutes))
        let multiplier = minutes >= 90 ? AdventureZone.coast.rewardMultiplier
            : (minutes >= 50 ? AdventureZone.cave.rewardMultiplier : AdventureZone.forest.rewardMultiplier)
        return (max(1, Int((m * 120_000 * multiplier).rounded())),
                max(1, Int((m * 8 * multiplier).rounded())))
    }

    static func reward(for run: AdventureRun) -> AdventureReward {
        let minutes = run.endsAt.timeIntervalSince(run.startedAt) / 60
        let amounts = amounts(minutes: Int(minutes.rounded()))
        var seed = UInt64(bitPattern: Int64(run.companionSpeciesID))
        for byte in run.id.uuidString.utf8 { seed = (seed ^ UInt64(byte)) &* 1_099_511_628_211 }
        let chance: UInt64 = run.zone == .coast ? 3 : (run.zone == .cave ? 7 : 15)
        let eggChance = UInt64(max(1, 10_000 / FocusRewardRules.eggChanceBasisPoints(minutes: Int(minutes.rounded()))))
        return AdventureReward(experience: amounts.experience, starPieces: amounts.starPieces,
                               foundRareCandy: seed % chance == 0,
                               foundEgg: (seed / 17) % eggChance == 0)
    }
}
