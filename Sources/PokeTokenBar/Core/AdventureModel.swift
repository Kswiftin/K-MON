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

/// 정산 배너에 실리는 줄. **조립을 뷰 밖으로 뺀다** — 뷰 안 `if` 로만 존재하면 어떤 지급이 화면에서
/// 빠져도 테스트는 전부 초록이다. #192 의 사탕 · 알 누락이 정확히 그 자리였고, 커버리지도 못 걸렀다
/// (line coverage 는 `if x { y }` 를 조건 평가만으로 실행으로 센다).
enum ClaimBannerLine: Equatable {
    /// 이번 정산으로 들어온 알. **개수를 싣는다** — 조각 완성 · 주간 10회 · 희귀 알이 겹치면 둘
    /// 이상이 함께 들어오는데, "한 개 찾았다" 로 뭉치면 나머지가 화면에서 사라진다.
    case eggs(Int)
    /// 지갑에 더해진 별의조각 **전부**(`totalStardust`).
    case settled(Int)
    /// 위 금액 중 만렙에 걸린 경험치를 되돌린 몫(#82). 따로 더 받은 게 아니다.
    case overflowConverted(Int)
    /// 지갑이 아니라 **가방**이 느는 지급이라 합계에 안 잡힌다. 해안은 3회 중 1회꼴로 준다.
    case rareCandy
}

extension AdventureReward {
    /// 이 정산이 화면에 남겨야 하는 줄 **전부**. 지급 경로가 늘면 여기 한 곳만 늘린다 —
    /// 뷰가 각자 조립하면 새 경로가 어느 화면에서 빠졌는지 아무도 모른다.
    var bannerLines: [ClaimBannerLine] {
        var lines: [ClaimBannerLine] = []
        if bonusEggs > 0 { lines.append(.eggs(bonusEggs)) }
        lines.append(.settled(totalStardust))
        if overflowBonus > 0 { lines.append(.overflowConverted(overflowBonus)) }
        if foundRareCandy { lines.append(.rareCandy) }
        return lines
    }
}

/// 정산 **밖**에서 지갑을 늘린 지급 한 건(#200). 진화 · 레이스 · 배틀 · 웨이브 런 · 졸업이
/// 각자 자기 화면에 배너를 만들면 여섯 번째 경로가 생길 때 또 조용히 빠진다 — `ClaimBannerLine`
/// 과 같은 이유로 조립을 뷰 밖 한 곳에 둔다.
///
/// **경로마다 한 통이다.** 웨이브 런은 두 트랙(`dungeon`·`dungeonSweep`), 졸업은 넷(트레이너 ·
/// 미션 · 시즌 · 도감 목표)이 같은 사건에서 함께 터지는데, 지급마다 띄우면 같은 판을 여러 번
/// 말하게 된다(`mergedCompletion` 이 미션에서 막은 그 문제다).
struct StardustPayout: Equatable {
    /// 지급을 낳은 사건. 금액만으로는 "왜 늘었나" 에 답하지 못한다 — 그게 #200 의 증상이었다.
    enum Source: Equatable { case evolve, race, battle, dungeon, graduation }
    let source: Source
    let stardust: Int
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
    /// 그 모험이 **기본으로** 준 별의조각(`AdventureReward.starPieces`). 환산분 · 트레이너 · 미션 ·
    /// 업적 · 시즌 몫은 들어 있지 않으므로 **지갑 증가분과 같지 않다.**
    ///
    /// 전부 담는 쪽(`totalStardust`)이 더 옳아 보이지만, 이 배열은 이미 저장된 값이고 마이그레이션이
    /// 없다 — 의미만 바꾸면 옛 행과 새 행이 다른 것을 뜻한 채 한 배열에 섞인다. 읽는 화면은 아직
    /// 하나도 없으니(`CompanionStore.recentAdventures` 는 소비처가 없다) 지금 바꿀 이유도 없다.
    /// **히스토리 화면을 붙일 때** 그때 마이그레이션과 함께 정한다.
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
