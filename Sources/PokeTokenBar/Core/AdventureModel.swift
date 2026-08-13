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

struct PetCareState: Codable, Sendable, Equatable {
    var hunger = 100.0
    var happiness = 100.0
    var energy = 100.0
    var lastUpdatedAt: Date?

    mutating func advance(to now: Date) {
        guard let lastUpdatedAt else { self.lastUpdatedAt = now; return }
        let hours = min(max(0, now.timeIntervalSince(lastUpdatedAt)) / 3600, 24)
        hunger = max(0, hunger - hours * 4)
        happiness = max(0, happiness - hours * 2)
        energy = max(0, energy - hours * 3)
        self.lastUpdatedAt = now
    }
    mutating func feed() { hunger = min(100, hunger + 25); happiness = min(100, happiness + 3) }
    mutating func play() { happiness = min(100, happiness + 20); energy = max(0, energy - 8) }
    mutating func rest() { energy = min(100, energy + 30) }
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
    static func reward(for run: AdventureRun) -> AdventureReward {
        let minutes = run.endsAt.timeIntervalSince(run.startedAt) / 60
        let dust = max(1, Int((minutes * 8 * run.zone.rewardMultiplier).rounded()))
        var seed = UInt64(bitPattern: Int64(run.companionSpeciesID))
        for byte in run.id.uuidString.utf8 { seed = (seed ^ UInt64(byte)) &* 1_099_511_628_211 }
        let chance: UInt64 = run.zone == .coast ? 3 : (run.zone == .cave ? 7 : 15)
        return AdventureReward(stardust: dust, foundRareCandy: seed % chance == 0)
    }
}
