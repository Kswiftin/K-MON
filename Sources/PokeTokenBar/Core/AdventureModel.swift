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

enum CareNeed: String, Codable, Sendable, Equatable {
    case hungry, lonely, tired
}

enum CareFood: String, Codable, Sendable, CaseIterable, Identifiable {
    case apple, berry, biscuit
    var id: String { rawValue }
    var symbol: String { switch self { case .apple: "🍎"; case .berry: "🫐"; case .biscuit: "🍪" } }

    static func favorite(for speciesID: Int) -> CareFood {
        allCases[abs(speciesID) % allCases.count]
    }
}

enum CareAdvanceEvent: Sendable, Equatable {
    case requested(CareNeed)
    case missed(CareNeed)
    case becameSick
}

enum CareTrainingResult: Sendable, Equatable { case trained, cooldown, tooTired }

struct PetCareState: Codable, Sendable, Equatable {
    var hunger = 100.0
    var happiness = 100.0
    var energy = 100.0
    var affection = 50.0
    var hygiene = 100.0
    var isSick = false
    var messCount = 0
    var lastMessAt: Date?
    var careMistakes = 0
    var pendingNeed: CareNeed?
    var needDeadline: Date?
    var lastNeedAt: Date?
    var lastUpdatedAt: Date?
    var lastPettedAt: Date?
    var discipline = 0.0
    var lastTrainedAt: Date?
    var isSleeping = false
    var sleepStartedAt: Date?

    @discardableResult
    mutating func advance(to now: Date) -> CareAdvanceEvent? {
        guard let lastUpdatedAt else {
            self.lastUpdatedAt = now
            if lastNeedAt == nil { lastNeedAt = now }
            return nil
        }
        let hours = min(max(0, now.timeIntervalSince(lastUpdatedAt)) / 3600, 24)
        hunger = max(0, hunger - hours * (isSleeping ? 2 : 4))
        happiness = max(0, happiness - hours * (isSleeping ? 0.5 : 2))
        energy = isSleeping ? min(100, energy + hours * 15) : max(0, energy - hours * 3)
        hygiene = max(0, hygiene - hours * 2)
        if lastMessAt == nil { lastMessAt = lastUpdatedAt }
        if let lastMessAt {
            let newMess = min(3 - messCount, max(0, Int(now.timeIntervalSince(lastMessAt) / (4 * 3600))))
            if newMess > 0 {
                messCount += newMess
                hygiene = max(0, hygiene - Double(newMess * 12))
                self.lastMessAt = lastMessAt.addingTimeInterval(Double(newMess) * 4 * 3600)
            }
        }
        self.lastUpdatedAt = now
        if isSleeping, energy >= 100 {
            isSleeping = false
            sleepStartedAt = nil
        }

        // 낮은 위생과 허기가 겹치면 질병이 발생한다. 무작위가 아니라 상태 기반이라 예측·회복 가능하다.
        if !isSick, hygiene <= 20, hunger <= 30 {
            isSick = true
            happiness = max(0, happiness - 10)
            return .becameSick
        }

        if let need = pendingNeed, let deadline = needDeadline, now >= deadline {
            careMistakes += 1
            affection = max(0, affection - 5)
            pendingNeed = nil
            needDeadline = nil
            lastNeedAt = now
            return .missed(need)
        }
        if lastNeedAt == nil { lastNeedAt = now }
        guard pendingNeed == nil else { return nil }
        guard !isSleeping else { return nil }
        let sinceLastNeed = now.timeIntervalSince(lastNeedAt ?? now)
        let urgent: CareNeed?
        if hunger <= 35 { urgent = .hungry }
        else if energy <= 30 { urgent = .tired }
        else if happiness <= 35 { urgent = .lonely }
        else { urgent = nil }
        let need: CareNeed?
        if let urgent, sinceLastNeed >= 3600 {
            need = urgent
        } else if sinceLastNeed >= 2 * 3600 {
            // 상태가 좋아도 가끔 관심을 요청한다. 가장 낮은 게이지에 맞춰 행동이 자연스럽게 이어진다.
            need = hunger <= happiness && hunger <= energy ? .hungry
                : (happiness <= energy ? .lonely : .tired)
        } else {
            need = nil
        }
        guard let need else { return nil }
        pendingNeed = need
        needDeadline = now.addingTimeInterval(30 * 60)
        lastNeedAt = now
        return .requested(need)
    }

    mutating func feed(favorite: Bool = false) {
        hunger = min(100, hunger + (favorite ? 35 : 25))
        happiness = min(100, happiness + (favorite ? 8 : 3))
        respond(to: .hungry, affectionGain: favorite ? 7 : 4)
    }
    mutating func play() { happiness = min(100, happiness + 20); energy = max(0, energy - 8); respond(to: .lonely) }
    mutating func rest() { energy = min(100, energy + 30); respond(to: .tired) }
    mutating func clean() {
        hygiene = min(100, hygiene + Double(45 + messCount * 10))
        messCount = 0
    }

    @discardableResult
    mutating func giveMedicine() -> Bool {
        guard isSick, hygiene >= 40 else { return false }
        isSick = false
        energy = min(100, energy + 10)
        happiness = min(100, happiness + 5)
        return true
    }

    mutating func train(at now: Date) -> CareTrainingResult {
        guard energy >= 10 else { return .tooTired }
        if let lastTrainedAt, now.timeIntervalSince(lastTrainedAt) < 30 * 60 { return .cooldown }
        lastTrainedAt = now
        energy = max(0, energy - 10)
        discipline = min(100, discipline + 10)
        happiness = min(100, happiness + 4)
        affection = min(100, affection + 1)
        return .trained
    }

    @discardableResult
    mutating func sleep(at now: Date) -> Bool {
        guard !isSleeping, energy < 100 else { return false }
        isSleeping = true
        sleepStartedAt = now
        lastUpdatedAt = now
        return true
    }

    @discardableResult
    mutating func wake(at now: Date) -> Bool {
        guard isSleeping else { return false }
        _ = advance(to: now)
        isSleeping = false
        sleepStartedAt = nil
        return true
    }

    @discardableResult
    mutating func pet(at now: Date) -> Bool {
        if let lastPettedAt, now.timeIntervalSince(lastPettedAt) < 5 * 60 { return false }
        lastPettedAt = now
        happiness = min(100, happiness + 8)
        respond(to: .lonely, affectionGain: 3)
        return true
    }

    var careScore: Double {
        let condition = (hunger + happiness + energy + hygiene) / 4
        return min(100, max(0, condition * 0.65 + affection * 0.25 + discipline * 0.1))
    }

    /// 기본 상태는 1배. 컨디션 저하는 감속되고, 쌓인 친밀도는 최대 약 8% 보너스를 준다.
    var growthMultiplier: Double {
        let condition = (hunger + happiness + energy + hygiene) / 4
        let healthy = min(1.1, max(0.7, 1 + (condition - 100) * 0.0023
            + (affection - 50) * 0.0013 + discipline * 0.0002))
        return isSick ? min(0.75, healthy) : healthy
    }

    private mutating func respond(to need: CareNeed, affectionGain: Double = 4) {
        if pendingNeed == need {
            affection = min(100, affection + affectionGain)
            pendingNeed = nil
            needDeadline = nil
        } else {
            affection = min(100, affection + 0.5)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case hunger, happiness, energy, affection, hygiene, isSick, messCount, lastMessAt,
             careMistakes, pendingNeed, needDeadline, lastNeedAt, lastUpdatedAt, lastPettedAt,
             discipline, lastTrainedAt, isSleeping, sleepStartedAt
    }

    init(hunger: Double = 100, happiness: Double = 100, energy: Double = 100,
         affection: Double = 50, hygiene: Double = 100, isSick: Bool = false,
         messCount: Int = 0, lastMessAt: Date? = nil, careMistakes: Int = 0, pendingNeed: CareNeed? = nil,
         needDeadline: Date? = nil, lastNeedAt: Date? = nil, lastUpdatedAt: Date? = nil,
         lastPettedAt: Date? = nil, discipline: Double = 0, lastTrainedAt: Date? = nil,
         isSleeping: Bool = false, sleepStartedAt: Date? = nil) {
        self.hunger = hunger; self.happiness = happiness; self.energy = energy
        self.affection = affection; self.hygiene = hygiene; self.isSick = isSick
        self.messCount = messCount; self.lastMessAt = lastMessAt
        self.careMistakes = careMistakes; self.pendingNeed = pendingNeed
        self.needDeadline = needDeadline; self.lastNeedAt = lastNeedAt; self.lastUpdatedAt = lastUpdatedAt
        self.lastPettedAt = lastPettedAt
        self.discipline = discipline; self.lastTrainedAt = lastTrainedAt
        self.isSleeping = isSleeping; self.sleepStartedAt = sleepStartedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hunger = (try? c.decode(Double.self, forKey: .hunger)) ?? 100
        happiness = (try? c.decode(Double.self, forKey: .happiness)) ?? 100
        energy = (try? c.decode(Double.self, forKey: .energy)) ?? 100
        affection = (try? c.decode(Double.self, forKey: .affection)) ?? 50
        hygiene = (try? c.decode(Double.self, forKey: .hygiene)) ?? 100
        isSick = (try? c.decode(Bool.self, forKey: .isSick)) ?? false
        messCount = (try? c.decode(Int.self, forKey: .messCount)) ?? 0
        lastMessAt = try? c.decode(Date.self, forKey: .lastMessAt)
        careMistakes = (try? c.decode(Int.self, forKey: .careMistakes)) ?? 0
        pendingNeed = try? c.decode(CareNeed.self, forKey: .pendingNeed)
        needDeadline = try? c.decode(Date.self, forKey: .needDeadline)
        lastNeedAt = try? c.decode(Date.self, forKey: .lastNeedAt)
        lastUpdatedAt = try? c.decode(Date.self, forKey: .lastUpdatedAt)
        lastPettedAt = try? c.decode(Date.self, forKey: .lastPettedAt)
        discipline = (try? c.decode(Double.self, forKey: .discipline)) ?? 0
        lastTrainedAt = try? c.decode(Date.self, forKey: .lastTrainedAt)
        isSleeping = (try? c.decode(Bool.self, forKey: .isSleeping)) ?? false
        sleepStartedAt = try? c.decode(Date.self, forKey: .sleepStartedAt)
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
    var stardust: Int { starPieces }
}

struct FocusSessionReward: Sendable, Equatable {
    let minutes: Int
    let stardust: Int
    let foundEgg: Bool
    var trainerBonus = 0
    var missionBonus = 0
    var achievementBonus = 0
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
