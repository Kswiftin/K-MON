import Foundation

struct PokopiaConversationSelection: Identifiable, Equatable {
    let region: TownRegion
    let speciesID: Int
    let arrivedAt: Date
    var id: String { "\(region.rawValue):\(speciesID):\(arrivedAt.timeIntervalSinceReferenceDate)" }
}

struct PokopiaRequestCard: Identifiable, Equatable {
    let id: String
    let region: TownRegion
    let residentName: String
    let title: String
    let status: PokopiaRequestStatus
    let reward: ItemKind
}

struct PokopiaConversationContent: Equatable {
    let resident: TownResident?
    let friendship: PokopiaFriendshipLevel
    let request: PokopiaResidentRequest?
    let status: PokopiaRequestStatus?
    let dialogue: PokopiaDialogue?
}

enum PokopiaCommunityPresentation {
    static func cards(state: PokopiaCommunityState, context: PokopiaCommunityContext, region: TownRegion) -> [PokopiaRequestCard] {
        (state.daily?.requests ?? []).filter { $0.region == region }.map { request in
            let resident = context.towns[region.rawValue]?.residents.first {
                $0.speciesID == request.speciesID && $0.arrivedAt == request.arrivedAt
            }
            return .init(id: request.id, region: region, residentName: resident?.name ?? "#\(request.speciesID)",
                         title: title(request), status: PokopiaCommunity.status(request, state: state, context: context), reward: request.reward)
        }
    }

    static func conversation(selection: PokopiaConversationSelection, state: PokopiaCommunityState,
                             context: PokopiaCommunityContext, season: MemoryHomeSeason,
                             timeOfDay: MemoryHomeTimeOfDay) -> PokopiaConversationContent {
        let town = context.towns[selection.region.rawValue]
        let resident = town?.residents.first { $0.speciesID == selection.speciesID && $0.arrivedAt == selection.arrivedAt }
        let friendship = PokopiaCommunity.friendshipLevel(points: state.friendships[
            PokopiaCommunity.friendshipKey(region: selection.region, speciesID: selection.speciesID), default: 0])
        let request = state.daily?.requests.first {
            $0.region == selection.region && $0.speciesID == selection.speciesID && $0.arrivedAt == selection.arrivedAt
        }
        let status = request.map { PokopiaCommunity.status($0, state: state, context: context) }
        let dialogue = resident.map {
            PokopiaResidentDialogue.make(resident: $0, terrain: town?.terrain ?? [], season: season,
                                         timeOfDay: timeOfDay, friendship: friendship, request: request, status: status)
        }
        return .init(resident: resident, friendship: friendship, request: request, status: status, dialogue: dialogue)
    }

    static func title(_ request: PokopiaResidentRequest) -> String {
        switch request.kind {
        case .focus: "집중 20분 마치기"
        case .habitat: "\(request.terrain?.name ?? "서식") 지형 6칸 모으기"
        case .meal: "이 마을에서 요리 나누기"
        }
    }

    static func statusText(_ status: PokopiaRequestStatus) -> String {
        switch status {
        case .inProgress(let current, let target): "진행 \(current)/\(target)"
        case .ready: "선물을 받을 수 있어요"
        case .claimed: "오늘의 감사 인사를 받았어요"
        case .residentLeft: "주민이 마을을 떠났어요"
        case .expired: "지난 날짜의 부탁이에요"
        case .blocked: "날짜가 맞을 때 다시 확인해 주세요"
        }
    }

    static func milestoneName(_ milestone: PokopiaMilestone) -> String {
        switch milestone {
        case .firstThanks: "첫 감사 인사 · 부탁 1회"
        case .dependableNeighbor: "믿음직한 이웃 · 부탁 10회"
        case .townBestFriend: "마을의 단짝 · 부탁 30회"
        case .settledHome: "편안한 집 · 주민 1명 정착"
        case .sharedScenery: "함께 만든 풍경 · 복합 서식지"
        case .diverseTown: "다채로운 마을 · 한 지역의 서식지 8종"
        }
    }
}
