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

    init(dayKey: String, isIssued: Bool = true, isBlocked: Bool = false, issuedCount: Int = 0,
         requests: [PokopiaResidentRequest] = [], focusMinutes: Int = 0,
         mealsByRegion: [String: Int] = [:], claimedCount: Int = 0) {
        self.dayKey = dayKey
        self.isIssued = isIssued
        self.isBlocked = isBlocked
        self.issuedCount = issuedCount
        self.requests = requests
        self.focusMinutes = focusMinutes
        self.mealsByRegion = mealsByRegion
        self.claimedCount = claimedCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        isIssued = try c.decode(Bool.self, forKey: .isIssued)
        isBlocked = try c.decode(Bool.self, forKey: .isBlocked)
        issuedCount = try c.decode(Int.self, forKey: .issuedCount)
        requests = try c.decode([CommunityLossyRequest].self, forKey: .requests).compactMap(\.value)
        focusMinutes = try c.decode(Int.self, forKey: .focusMinutes)
        mealsByRegion = try c.decode([String: Int].self, forKey: .mealsByRegion)
        claimedCount = try c.decode(Int.self, forKey: .claimedCount)
    }
}

private struct CommunityLossyRequest: Decodable {
    let value: PokopiaResidentRequest?
    init(from decoder: Decoder) throws { value = try? PokopiaResidentRequest(from: decoder) }
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

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        daily = try c.decodeIfPresent(PokopiaDailyBoard.self, forKey: .daily)
        friendships = try c.decode([String: Int].self, forKey: .friendships)
        totalCompleted = try c.decode(Int.self, forKey: .totalCompleted)
        milestones = Set(try c.decode([PokopiaMilestone].self, forKey: .milestones))
        needsRecovery = try c.decode(Bool.self, forKey: .needsRecovery)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(daily, forKey: .daily)
        try c.encode(friendships, forKey: .friendships)
        try c.encode(totalCompleted, forKey: .totalCompleted)
        try c.encode(milestones.sorted { $0.rawValue < $1.rawValue }, forKey: .milestones)
        try c.encode(needsRecovery, forKey: .needsRecovery)
    }

    private enum CodingKeys: String, CodingKey {
        case daily, friendships, totalCompleted, milestones, needsRecovery
    }
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
    static func merged(_ imported: PokopiaCommunityState, current: PokopiaCommunityState) -> PokopiaCommunityState {
        let incoming = normalized(imported), local = normalized(current)
        var result = incoming
        result.friendships.merge(local.friendships, uniquingKeysWith: max)
        result.totalCompleted = max(incoming.totalCompleted, local.totalCompleted)
        result.milestones.formUnion(local.milestones)
        result.needsRecovery = incoming.needsRecovery || local.needsRecovery
        guard let currentBoard = local.daily else { return result }
        guard let importedBoard = incoming.daily else { result.daily = currentBoard; return result }
        guard importedBoard.dayKey == currentBoard.dayKey else {
            result.daily = importedBoard.dayKey > currentBoard.dayKey ? importedBoard : currentBoard
            return result
        }
        // 이미 이 기기에 발급된 목록은 고정한다. 다른 기기의 완료와 격리 슬롯도 상한에 포함한다.
        var board = currentBoard
        let localClaims = Set(currentBoard.requests.filter(\.isClaimed).map(\.id))
        let importedClaims = Set(importedBoard.requests.filter(\.isClaimed).map(\.id))
        let claims = localClaims.union(importedClaims)
        let unknownClaims = max(currentBoard.claimedCount - localClaims.count,
                                importedBoard.claimedCount - importedClaims.count)
        board.issuedCount = max(currentBoard.issuedCount, importedBoard.issuedCount)
        board.claimedCount = min(board.issuedCount, claims.count + max(0, unknownClaims))
        for index in board.requests.indices { board.requests[index].isClaimed = claims.contains(board.requests[index].id) }
        board.isIssued = currentBoard.isIssued || importedBoard.isIssued
        board.isBlocked = currentBoard.isBlocked || importedBoard.isBlocked
        board.focusMinutes = max(currentBoard.focusMinutes, importedBoard.focusMinutes)
        board.mealsByRegion.merge(importedBoard.mealsByRegion, uniquingKeysWith: max)
        result.daily = board
        return result
    }

    static func canonicalPayload(_ state: PokopiaCommunityState) -> String? {
        guard state != PokopiaCommunityState() else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return "invalid-community" }
        return String(decoding: data, as: UTF8.self)
    }

    static func normalized(_ state: PokopiaCommunityState) -> PokopiaCommunityState {
        var result = state
        result.totalCompleted = max(0, result.totalCompleted)
        result.friendships = result.friendships.reduce(into: [:]) { output, entry in
            let parts = entry.key.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let region = TownRegion(rawValue: String(parts[0])),
                  let species = Int(parts[1]), PokemonAssets.hasAnimatedSprite(speciesID: species),
                  entry.key == friendshipKey(region: region, speciesID: species) else { return }
            output[entry.key] = min(10, max(0, entry.value))
        }
        guard var daily = result.daily else { return result }
        guard validDayKey(daily.dayKey) else {
            result.daily = nil
            result.needsRecovery = true
            return result
        }
        daily.issuedCount = min(3, max(0, daily.issuedCount))
        daily.claimedCount = min(daily.issuedCount, max(0, daily.claimedCount))
        daily.focusMinutes = min(20, max(0, daily.focusMinutes))
        daily.mealsByRegion = daily.mealsByRegion.reduce(into: [:]) { output, entry in
            if TownRegion(rawValue: entry.key) != nil { output[entry.key] = min(1, max(0, entry.value)) }
        }
        var seen: Set<String> = []
        daily.requests = Array(daily.requests.filter { request in
            guard request.id == "\(daily.dayKey)|\(request.region.rawValue)|\(request.speciesID)|\(request.kind.rawValue)",
                  PokemonAssets.hasAnimatedSprite(speciesID: request.speciesID),
                  request.arrivedAt.timeIntervalSinceReferenceDate.isFinite,
                  PokopiaCrafting.materials.contains(request.reward),
                  request.target == (request.kind == .focus ? 20 : request.kind == .habitat ? 6 : 1),
                  (request.kind == .habitat) == (request.terrain != nil),
                  seen.insert(friendshipKey(region: request.region, speciesID: request.speciesID)).inserted else { return false }
            return true
        }.prefix(daily.issuedCount))
        daily.claimedCount = max(daily.claimedCount, daily.requests.filter(\.isClaimed).count)
        // 발급 수와 격리된 항목은 복구 시에도 줄이지 않는다.
        if !daily.isIssued { daily.isBlocked = true }
        result.daily = daily
        return result
    }

    private static func validDayKey(_ key: String) -> Bool {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              year > 0, (1...12).contains(month), (1...31).contains(day) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        return calendar.dateComponents([.year, .month, .day], from: date) == components
    }

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
