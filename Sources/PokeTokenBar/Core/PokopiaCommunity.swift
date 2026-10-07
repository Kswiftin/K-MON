import Foundation

enum PokopiaRequestKind: String, Codable, CaseIterable, Sendable {
    case focus, habitat, meal
}

struct PokopiaResidentRequest: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var region: TownRegion
    var speciesID: Int
    var arrivedAt: Date
    var kind: PokopiaRequestKind
    var terrain: TownTerrain?
    var target: Int
    var reward: ItemKind
    var isClaimed = false
}

struct PokopiaDailyBoard: Codable, Sendable, Equatable {
    var dayKey: String
    var isIssued = true
    var isBlocked = false
    var issuedCount = 0
    var requests: [PokopiaResidentRequest] = []
    var focusMinutes = 0
    var mealsByRegion: [String: Int] = [:]
    var claimedCount = 0
}

enum PokopiaMilestone: String, Codable, CaseIterable, Sendable {
    case firstThanks, dependableNeighbor, townBestFriend
    case settledHome, sharedScenery, diverseTown
}

struct PokopiaCommunityState: Codable, Sendable, Equatable {
    var daily: PokopiaDailyBoard?
    var friendships: [String: Int] = [:]
    var totalCompleted = 0
    var milestones: Set<PokopiaMilestone> = []
    var needsRecovery = false
}

struct PokopiaCommunityContext: Sendable {
    var dayKey: String
    var towns: [String: PokopiaTownState]
    var availableBrushes: Set<TownTerrain>
    var canShareFood: Bool
}

enum PokopiaCommunity {
    static func prepare(_ state: inout PokopiaCommunityState, context: PokopiaCommunityContext) -> Bool {
        if let daily = state.daily, daily.dayKey >= context.dayKey { return false }
        if state.needsRecovery {
            state.daily = PokopiaDailyBoard(dayKey: context.dayKey, isBlocked: true)
            state.needsRecovery = false
            return true
        }
        var candidates: [(TownRegion, TownResident)] = []
        for region in TownRegion.allCases {
            for resident in (context.towns[region.rawValue]?.residents ?? []).sorted(by: { $0.speciesID < $1.speciesID }) {
                guard PokopiaTown.isAdmissible(resident),
                      !candidates.contains(where: { $0.0 == region && $0.1.speciesID == resident.speciesID }) else { continue }
                candidates.append((region, resident))
            }
        }
        if !candidates.isEmpty {
            let offset = Int(hash(context.dayKey) % UInt64(candidates.count))
            candidates = Array(candidates[offset...]) + Array(candidates[..<offset])
        }
        let requests = candidates.prefix(3).map { region, resident in
            let key = "\(context.dayKey)|\(region.rawValue)|\(resident.speciesID)"
            let kinds = eligibleKinds(region: region, resident: resident, context: context)
            let kind = kinds[Int(hash(key) % UInt64(kinds.count))]
            let terrains = missingTerrains(region: region, resident: resident, context: context)
            let terrain: TownTerrain? = kind == .habitat ? terrains[Int(hash(key + "|habitat") % UInt64(terrains.count))] : nil
            let rewardKey = "\(context.dayKey)|\(kind.rawValue)|\(terrain?.rawValue ?? "")"
            let reward = PokopiaCrafting.materials[Int(hash(rewardKey) % UInt64(PokopiaCrafting.materials.count))]
            return PokopiaResidentRequest(id: key + "|" + kind.rawValue, region: region, speciesID: resident.speciesID,
                arrivedAt: resident.arrivedAt, kind: kind, terrain: terrain,
                target: kind == .focus ? 20 : kind == .habitat ? PokopiaTown.habitatThreshold : 1, reward: reward)
        }
        state.daily = PokopiaDailyBoard(dayKey: context.dayKey, issuedCount: requests.count, requests: requests)
        return true
    }

    static func eligibleKinds(region: TownRegion, resident: TownResident, context: PokopiaCommunityContext) -> [PokopiaRequestKind] {
        var kinds: [PokopiaRequestKind] = [.focus]
        if !missingTerrains(region: region, resident: resident, context: context).isEmpty { kinds.append(.habitat) }
        if context.canShareFood { kinds.append(.meal) }
        return kinds
    }

    private static func missingTerrains(region: TownRegion, resident: TownResident, context: PokopiaCommunityContext) -> [TownTerrain] {
        let counts = PokopiaTown.tileCounts(context.towns[region.rawValue]?.terrain ?? [])
        return PokopiaTown.homeTerrains(resident).filter {
            context.availableBrushes.contains($0) && counts[$0, default: 0] < PokopiaTown.habitatThreshold
        }
    }

    private static func hash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }
}
