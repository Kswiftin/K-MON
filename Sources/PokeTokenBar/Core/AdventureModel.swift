import Foundation

enum AdventureZone: String, Codable, Sendable, CaseIterable, Identifiable {
    case forest, cave, coast
    var id: String { rawValue }
    var duration: TimeInterval {
        switch self { case .forest: 10 * 60; case .cave: 30 * 60; case .coast: 2 * 60 * 60 }
    }
    /// 같은 시간 방치했을 때의 생산량 대비 지급 비율 — **짧은 구간일수록 높다**(자주 확인하는 쪽을 보상).
    /// 긴 구간의 이점은 시간당 효율이 아니라 "한 번에 큰 덩어리 + 손이 덜 감"이다.
    /// 이 대소가 뒤집히면(길수록 높으면) 최장 구간이 효율·수고 양쪽에서 우월해져 나머지 구간이 죽는다.
    var idleProductionShare: Double {
        switch self { case .forest: 0.30; case .cave: 0.22; case .coast: 0.15 }
    }
    /// 이상한 사탕 당첨 분모 — 구간 길이에 비례시켜 **시간당 기대 개수를 세 구간 모두 동일**하게 맞춘다
    /// (모험 20시간당 1개). 사탕은 구간 선택 기준이 아니라 배경 보상이고, 구간 차이는 별의모래로만 낸다.
    /// 값을 손보면 세 구간의 (회차/시간 ÷ 분모)가 여전히 같은지 확인할 것.
    var rareCandyDenominator: UInt64 {
        switch self { case .forest: 120; case .cave: 40; case .coast: 10 }
    }
    var symbol: String {
        switch self { case .forest: "leaf.fill"; case .cave: "mountain.2.fill"; case .coast: "water.waves" }
    }
    /// 출발에 드는 에너지 — **구간 길이에 비례**해 모험 1시간당 소모를 세 구간 모두 같게 맞춘다.
    /// 고정 비용이면 짧은 구간일수록 시간당 소모가 커져(숲 90 : 해안 7.5) `idleProductionShare` 와
    /// 정반대 방향이 된다 — 두 값이 어긋나면 구간 선택이 다시 한쪽으로 쏠린다.
    var energyCost: Double { duration / 3600 * PetCareState.adventureEnergyPerHour }
}

struct PetCareState: Codable, Sendable, Equatable {
    /// 모험 1시간당 에너지 소모 — 구간별 비용(`AdventureZone.energyCost`)의 단일 기준.
    static let adventureEnergyPerHour = 30.0
    /// 시간당 자동 회복. 별의모래 생산과 달리 **앱을 꺼 둔 시간도 인정한다**(`advance` 가 경과 시간을
    /// 24시간까지 그대로 센다) — 모험은 실시간이 흘러야 끝나고 한 번에 하나뿐이라 몰아서 돌릴 수 없어,
    /// 꺼 둔 사이 회복돼도 이득이 생기지 않는다. 돌아왔을 때 바로 출발할 수 있는 쪽이 방치형에 맞다.
    /// 회복(20) < 모험 소모(30) 라 쉬지 않고 계속 모험할 수는 없다.
    static let recoveryPerHour = 20.0
    /// 재우기 회복량과 재사용 대기. 대기가 없으면 버튼 연타로 에너지가 무한이 되어
    /// 소모 설계가 통째로 무의미해진다(도입 시 실제로 그랬다).
    static let restRecovery = 15.0
    static let restCooldown: TimeInterval = 3600

    var hunger = 100.0
    var happiness = 100.0
    var energy = 100.0
    var lastUpdatedAt: Date?
    var lastRestedAt: Date?

    /// 배고픔·행복도는 시간이 지나면 나빠지고, 에너지는 반대로 차오른다(쉬는 동안 회복).
    mutating func advance(to now: Date) {
        guard let lastUpdatedAt else { self.lastUpdatedAt = now; return }
        let hours = min(max(0, now.timeIntervalSince(lastUpdatedAt)) / 3600, 24)
        hunger = max(0, hunger - hours * 4)
        happiness = max(0, happiness - hours * 2)
        energy = min(100, energy + hours * Self.recoveryPerHour)
        self.lastUpdatedAt = now
    }
    mutating func feed() { hunger = min(100, hunger + 25); happiness = min(100, happiness + 3) }
    mutating func play() { happiness = min(100, happiness + 20); energy = max(0, energy - 8) }
    /// 자동 회복의 보조 — 대기 중이면 아무 일도 일어나지 않는다(false).
    mutating func rest(at now: Date) -> Bool {
        if let lastRestedAt, now.timeIntervalSince(lastRestedAt) < Self.restCooldown { return false }
        energy = min(100, energy + Self.restRecovery)
        lastRestedAt = now
        return true
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

struct AdventureReward: Sendable, Equatable { let stardust: Int; let foundRareCandy: Bool }

struct AdventureRecord: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var zone: AdventureZone
    var companionSpeciesID: Int
    var completedAt: Date
    var stardust: Int
    var foundRareCandy: Bool
}

enum AdventureRules {
    /// 보상 = (같은 시간 방치 생산) × 구간 비율. 방치와 **같은 상수**(`dustPerSecond`)·**같은 배율**
    /// (도감 보너스)을 태우므로 기본 생산 속도를 조정하면 모험 보상도 자동으로 따라온다 —
    /// 고정 계수를 따로 두면 한쪽만 조정됐을 때 모험이 조용히 무가치해진다.
    /// 모험 중에도 방치 생산은 계속 돌므로 이 값은 대체가 아니라 **덧붙는 보너스**다.
    static func reward(for run: AdventureRun, productionMultiplier: Double = 1) -> AdventureReward {
        let seconds = run.endsAt.timeIntervalSince(run.startedAt)
        let idleProduction = seconds * IdleEconomy.dustPerSecond * productionMultiplier
        let stardust = max(1, Int((idleProduction * run.zone.idleProductionShare).rounded()))
        var seed = UInt64(bitPattern: Int64(run.companionSpeciesID))
        for byte in run.id.uuidString.utf8 { seed = (seed ^ UInt64(byte)) &* 1_099_511_628_211 }
        return AdventureReward(stardust: stardust,
                               foundRareCandy: seed % run.zone.rareCandyDenominator == 0)
    }
}
