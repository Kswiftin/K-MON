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

enum PokopiaRequestStatus: Equatable, Sendable {
    case inProgress(current: Int, target: Int), ready, claimed, residentLeft, expired, blocked
}

enum PokopiaFriendshipLevel: Int, CaseIterable, Sendable {
    case newNeighbor, familiarNeighbor, trustedFriend

    var name: String {
        switch self {
        case .newNeighbor: "처음 만난 이웃"
        case .familiarNeighbor: "익숙한 이웃"
        case .trustedFriend: "든든한 친구"
        }
    }
}

struct PokopiaReward: Sendable, Equatable {
    let requestID: String
    let region: TownRegion
    let speciesID: Int
    let item: ItemKind
}

enum PokopiaCommunity {
    static func status(_ request: PokopiaResidentRequest, state: PokopiaCommunityState,
                       context: PokopiaCommunityContext) -> PokopiaRequestStatus {
        guard let daily = state.daily else { return .expired }
        if daily.dayKey > context.dayKey { return .blocked }
        if daily.dayKey < context.dayKey { return .expired }
        if daily.isBlocked || state.needsRecovery || !daily.isIssued { return .blocked }
        if request.isClaimed { return .claimed }
        guard context.towns[request.region.rawValue]?.residents.contains(where: {
            $0.speciesID == request.speciesID && $0.arrivedAt == request.arrivedAt
        }) == true else { return .residentLeft }
        let current: Int
        switch request.kind {
        case .focus: current = daily.focusMinutes
        case .meal: current = daily.mealsByRegion[request.region.rawValue, default: 0]
        case .habitat:
            guard let terrain = request.terrain else { return .blocked }
            current = PokopiaTown.tileCounts(context.towns[request.region.rawValue]?.terrain ?? [])[terrain, default: 0]
        }
        return current >= request.target ? .ready : .inProgress(current: max(0, current), target: request.target)
    }

    static func recordFocusMinutes(_ amount: Int, dayKey: String, in state: inout PokopiaCommunityState) -> Bool {
        guard amount > 0, amount <= FocusSessionLog.maxSessionMinutes,
              let daily = state.daily, daily.dayKey == dayKey, daily.isIssued,
              !daily.isBlocked, !state.needsRecovery, daily.focusMinutes < 20 else { return false }
        state.daily?.focusMinutes = min(20, max(0, daily.focusMinutes) + amount)
        return true
    }

    static func recordMeal(region: TownRegion, dayKey: String, in state: inout PokopiaCommunityState) -> Bool {
        guard let daily = state.daily, daily.dayKey == dayKey, daily.isIssued,
              !daily.isBlocked, !state.needsRecovery, daily.mealsByRegion[region.rawValue, default: 0] == 0 else { return false }
        state.daily?.mealsByRegion[region.rawValue] = 1
        return true
    }

    static func claim(requestID: String, context: PokopiaCommunityContext, in state: inout PokopiaCommunityState) -> PokopiaReward? {
        guard let daily = state.daily, daily.dayKey == context.dayKey, daily.isIssued,
              !daily.isBlocked, !state.needsRecovery, daily.claimedCount < 3,
              daily.claimedCount < daily.issuedCount,
              let index = daily.requests.firstIndex(where: { $0.id == requestID }),
              status(daily.requests[index], state: state, context: context) == .ready else { return nil }
        let request = daily.requests[index]
        state.daily?.requests[index].isClaimed = true
        state.daily?.claimedCount = daily.claimedCount + 1
        let key = friendshipKey(region: request.region, speciesID: request.speciesID)
        state.friendships[key] = min(10, max(0, min(10, state.friendships[key, default: 0])) + 1)
        if state.totalCompleted < Int.max { state.totalCompleted += 1 }
        _ = refreshMilestones(&state, towns: context.towns)
        return .init(requestID: request.id, region: request.region, speciesID: request.speciesID, item: request.reward)
    }

    static func friendshipKey(region: TownRegion, speciesID: Int) -> String { "\(region.rawValue):\(speciesID)" }

    static func friendshipLevel(points: Int) -> PokopiaFriendshipLevel {
        points >= 10 ? .trustedFriend : points >= 3 ? .familiarNeighbor : .newNeighbor
    }

    static func refreshMilestones(_ state: inout PokopiaCommunityState, towns: [String: PokopiaTownState]) -> Bool {
        let previous = state.milestones
        if state.totalCompleted >= 1 { state.milestones.insert(.firstThanks) }
        if state.totalCompleted >= 10 { state.milestones.insert(.dependableNeighbor) }
        if state.totalCompleted >= 30 { state.milestones.insert(.townBestFriend) }
        for town in towns.values {
            if town.residents.contains(where: { PokopiaTown.isSettled($0, terrain: town.terrain) }) {
                state.milestones.insert(.settledHome)
            }
            if PokopiaTown.compositeHabitats(town.terrain).contains(where: \.isFormed) {
                state.milestones.insert(.sharedScenery)
            }
            if PokopiaTown.habitats(town.terrain).filter(\.isWelcoming).count >= 8 {
                state.milestones.insert(.diverseTown)
            }
        }
        return previous != state.milestones
    }

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
