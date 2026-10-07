import Foundation

struct PokopiaDialogue: Equatable, Sendable {
    let greeting: String
    let story: String
    let requestLine: String?
}

enum PokopiaResidentDialogue {
    static func make(resident: TownResident, terrain: [TownTerrain], season: MemoryHomeSeason,
                     timeOfDay: MemoryHomeTimeOfDay, friendship: PokopiaFriendshipLevel,
                     request: PokopiaResidentRequest?, status: PokopiaRequestStatus?) -> PokopiaDialogue {
        let seasonLine: String = switch season {
        case .spring: "새싹이 올라오는 봄이네요."
        case .summer: "햇살이 뜨거운 여름이네요."
        case .autumn: "바람에 가을 냄새가 나요."
        case .winter: "차가운 겨울 공기가 맑아요."
        }
        let timeLine: String = switch timeOfDay {
        case .morning: "좋은 아침! 오늘도 천천히 시작해요."
        case .day: "잠깐 쉬어 가요. 만나서 반가워요!"
        case .night: "늦은 시간이네요. 무리하지 말고 쉬어요."
        }
        let story: String
        if !PokopiaTown.isSettled(resident, terrain: terrain), let home = PokopiaTown.homeTerrains(resident).first {
            story = "아직 편히 머물 자리가 부족해요. \(home.name) 지형이 6칸 모이면 좋겠어요."
        } else if let specialty = PokopiaTown.specialty(of: resident) {
            story = stories(specialty)[friendship.rawValue]
        } else {
            story = "마을을 천천히 둘러보고 있어요. 함께 산책할까요?"
        }
        return .init(greeting: seasonLine + " " + timeLine, story: story,
                     requestLine: request.map { requestLine($0, status: status) }
                        ?? "오늘은 따로 부탁할 일이 없어요. 이야기하러 와 줘서 반가워요.")
    }

    private static func requestLine(_ request: PokopiaResidentRequest, status: PokopiaRequestStatus?) -> String {
        switch status {
        case .claimed: return "도와줘서 고마워요! 오늘 함께한 일은 오래 기억할게요."
        case .ready: return "부탁이 다 이루어졌네요! 준비한 작은 선물을 받아 주세요."
        case .residentLeft: return "이 부탁을 남긴 주민이 마을을 떠났어요."
        case .expired: return "어제 부탁은 마무리됐어요. 오늘 이야기를 새로 나눠요."
        case .blocked: return "오늘 부탁은 잠시 쉬고 있어요. 다음 날 다시 만나요."
        case .inProgress(let current, let target) where current > 0:
            return "벌써 \(current)/\(target)만큼 함께했네요. 조금만 더 도와줄 수 있나요?"
        default:
            switch request.kind {
            case .focus: return "오늘 집중을 20분 마치고 돌아와 주세요. 여기서 응원하며 기다릴게요."
            case .habitat: return "\(request.terrain?.name ?? "서식") 지형을 6칸 모아 주세요. 머물 자리가 더 편해질 거예요."
            case .meal: return "이 마을에서 요리를 한 번 나눠 먹을까요? 조리대에서 준비할 수 있어요."
            }
        }
    }

    private static func stories(_ specialty: TownSpecialty) -> [String] {
        switch specialty {
        case .ignition:
            ["작은 불씨를 다루는 연습을 해요. 가까이 오면 따뜻할 거예요.",
             "오늘은 불씨를 오래 지켜 봤어요. 함께 쉬는 시간이 생겨서 좋아요.",
             "추운 날에는 여기로 와요. 함께 나눈 온기를 기억하고 있어요."]
        case .watering:
            ["물길을 따라 걸으면 조용한 자리를 찾을 수 있어요.",
             "물방울 소리가 들리면 당신이 올 때가 됐나 생각해요.",
             "우리만 아는 쉬는 자리를 찾았어요. 물소리를 함께 듣고 싶어요."]
        case .farming:
            ["새싹을 살펴보는 게 좋아요. 자라는 속도는 저마다 다르더라고요.",
             "어제보다 잎이 조금 커졌어요. 이 작은 변화를 함께 보고 싶었어요.",
             "우리도 새싹처럼 조금씩 가까워졌네요. 당신이 오면 마음이 편해져요."]
        case .generating:
            ["작은 전기를 모아 보고 있어요. 깜짝 놀라지 않게 조심할게요.",
             "오늘은 반짝임을 일정하게 만들었어요. 보여 주고 싶어서 기다렸어요.",
             "당신의 발걸음을 보면 마음도 반짝여요. 오래 함께 지내고 싶어요."]
        case .leveling:
            ["울퉁불퉁한 곳을 천천히 고르고 있어요. 걷기 편한 길이 좋죠.",
             "발이 걸리던 자리를 기억해 두었어요. 다음 산책은 더 편할 거예요.",
             "함께 걸었던 길이 제일 소중해요. 앞으로도 나란히 걸어요."]
        case .flight:
            ["높은 곳에서 마을을 보면 길이 한눈에 들어와요.",
             "하늘에서 익숙한 발걸음을 찾았어요. 당신이 와서 내려왔죠.",
             "멀리 날아도 돌아올 곳을 알아요. 여기에는 당신이 있으니까요."]
        case .teleporting:
            ["새로운 자리를 찾으면 잠깐 이동해서 둘러봐요.",
             "금방 갈 수 있어도 오늘은 천천히 걸었어요. 마주칠지도 모르니까요.",
             "어디든 갈 수 있지만 함께 있는 이 자리가 가장 좋아요."]
        case .honeyGathering:
            ["꽃 주변을 살펴보고 있어요. 달콤한 향기가 나는 곳이 좋아요.",
             "오늘 찾은 향기를 기억했어요. 다음에 함께 찾아가요.",
             "달콤한 순간은 혼자보다 함께가 좋아요. 당신 몫의 이야기도 남겨 뒀어요."]
        case .recycling:
            ["버려진 것에서도 쓸모를 찾아봐요. 한 번 더 살펴보면 달라 보여요.",
             "지난번 알려 준 자리를 다시 정리했어요. 작은 변화가 보이나요?",
             "함께하면 낡은 것도 새롭게 보여요. 우리 이야기는 오래 간직할게요."]
        case .cutting:
            ["표면을 조금씩 다듬어요. 서두르지 않으면 더 반듯해져요.",
             "오늘은 손이 덜 떨렸어요. 곁에서 지켜봐 주니 마음이 놓여요.",
             "당신과 나눈 시간처럼 정성껏 다듬은 자리를 오래 지키고 싶어요."]
        case .polishing:
            ["돌마다 다른 무늬가 있어요. 천천히 닦으면 잘 보이죠.",
             "반짝이는 무늬를 하나 찾았어요. 제일 먼저 보여 주고 싶었어요.",
             "익숙한 돌도 새로 빛나네요. 오래된 친구와 보는 풍경은 특별해요."]
        case .crushing:
            ["단단한 덩어리를 잘게 나누는 연습을 해요. 쉬는 시간도 챙겨요.",
             "큰 일도 조금씩 나누니 끝났어요. 당신의 응원이 도움이 됐어요.",
             "힘든 일이 있으면 함께 나눠요. 혼자 감당하지 않아도 괜찮아요."]
        case .messing:
            ["가끔 순서를 바꿔 봐요. 뜻밖의 재미를 찾을 수 있거든요.",
             "오늘도 작은 장난을 생각했어요. 당신이 웃으면 좋겠어요.",
             "마음 놓고 장난칠 수 있는 친구가 생겼네요. 소중한 것은 건드리지 않을게요."]
        case .exploring:
            ["조용한 구석을 살펴봐요. 잘 안 보이는 곳에 이야기가 숨어 있어요.",
             "새로운 길을 찾으면 당신에게 알려 주고 싶어져요.",
             "어둑한 길도 함께라면 든든해요. 다음 탐색도 같이 가요."]
        case .sorting:
            ["비슷한 것끼리 모으면 찾기 쉬워요. 오늘은 작은 것부터 정리해요.",
             "당신이 자주 찾는 것들을 기억했어요. 다음에는 더 쉽게 찾을 거예요.",
             "정리한 것보다 함께한 기억이 더 많아졌어요. 하나도 잊고 싶지 않아요."]
        case .moodMaking:
            ["편히 쉴 수 있는 분위기를 만들고 싶어요. 좋아하는 풍경이 있나요?",
             "당신이 오면 마을이 조금 더 밝아지는 것 같아요.",
             "말이 없어도 편안한 사이가 됐네요. 오늘은 곁에서 같이 쉬어요."]
        case .rareHunting:
            ["눈에 잘 안 띄는 작은 차이를 찾아봐요. 자세히 보면 재미있어요.",
             "특별한 흔적을 찾았어요. 함께 볼 사람을 떠올리니 당신이 생각났죠.",
             "가장 귀한 발견은 좋은 친구였어요. 당신과 함께 찾은 시간도 소중해요."]
        case .yawning:
            ["하품이 나면 잠깐 쉬어요. 쉬고 나면 풍경도 새롭게 보여요.",
             "당신 옆에서는 졸아도 괜찮을 것 같아요. 잠깐만 쉬어 갈게요.",
             "눈을 감아도 곁에 있다는 걸 알아요. 이렇게 편한 친구가 생겨서 좋아요."]
        }
    }
}
