import Foundation
import Testing
@testable import PokeTokenBar

@Suite struct PokopiaResidentDialogueTests {
    private func resident(_ type: PokemonType = .grass) -> TownResident {
        .init(speciesID: 1, name: "이상해씨", types: [type], arrivedAt: CommunityFixture.now)
    }

    @Test func everySpecialtyHasThreeRelationshipStories() {
        let types: [PokemonType] = [.fire, .water, .grass, .electric, .ground, .flying, .psychic, .bug,
            .poison, .steel, .rock, .fighting, .dark, .ghost, .normal, .fairy, .dragon, .ice]
        #expect(types.count == 18)
        for type in types {
            let stories = PokopiaFriendshipLevel.allCases.map {
                PokopiaResidentDialogue.make(resident: resident(type),
                    terrain: Array(repeating: PokopiaTown.terrain(for: type), count: 192),
                    season: .autumn, timeOfDay: .day, friendship: $0, request: nil, status: nil).story
            }
            #expect(stories.allSatisfy { !$0.isEmpty })
            #expect(Set(stories).count == 3)
        }
    }

    @Test func sameSituationKeepsTheSameDialogue() {
        for season in MemoryHomeSeason.allCases {
            for time in MemoryHomeTimeOfDay.allCases {
                let first = PokopiaResidentDialogue.make(resident: resident(), terrain: Array(repeating: .grass, count: 192),
                    season: season, timeOfDay: time, friendship: .newNeighbor, request: nil, status: nil)
                let repeated = PokopiaResidentDialogue.make(resident: resident(), terrain: Array(repeating: .grass, count: 192),
                    season: season, timeOfDay: time, friendship: .newNeighbor, request: nil, status: nil)
                #expect(first == repeated)
                #expect(!first.greeting.isEmpty && !first.story.isEmpty)
            }
        }
    }

    @Test func unsettledResidentDoesNotDescribeAMissingHome() {
        let dialogue = PokopiaResidentDialogue.make(resident: resident(), terrain: Array(repeating: .sand, count: 192),
            season: .autumn, timeOfDay: .day, friendship: .trustedFriend, request: nil, status: nil)
        #expect(dialogue.story.contains("풀밭"))
        #expect(dialogue.story.contains("6칸"))
        #expect(dialogue.story.contains("아직"))
    }

    @Test func requestsHaveProgressReadyAndThanksLines() throws {
        let statuses: [PokopiaRequestStatus] = [.inProgress(current: 0, target: 20), .ready, .claimed]
        for kind in PokopiaRequestKind.allCases {
            let request = PokopiaResidentRequest(id: "test", region: .waste, speciesID: 1,
                arrivedAt: CommunityFixture.now, kind: kind, terrain: kind == .habitat ? .grass : nil,
                target: kind == .focus ? 20 : kind == .habitat ? 6 : 1, reward: .townWood)
            var lines: Set<String> = []
            for status in statuses {
                let dialogue = PokopiaResidentDialogue.make(resident: resident(), terrain: Array(repeating: .grass, count: 192),
                    season: .autumn, timeOfDay: .day, friendship: .newNeighbor, request: request, status: status)
                let line = try #require(dialogue.requestLine)
                #expect(!line.isEmpty)
                lines.insert(line)
                if status == .claimed { #expect(line.contains("고마워")) }
            }
            #expect(lines.count == 3)
        }
    }
}
