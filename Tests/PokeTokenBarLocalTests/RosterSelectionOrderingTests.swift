import Testing
@testable import PokeTokenBar

@Suite("Roster selection ordering")
struct RosterSelectionOrderingTests {
    private func mon(_ id: Int, name: String, nickname: String? = nil) -> MonState {
        var value = MonState(baseID: id, pathIDs: [id], stageIndex: 0, usedAtStage: 0,
                             rarity: .common, totalForms: 1,
                             names: [id: ["en": name, "ko": name]])
        value.nickname = nickname
        return value
    }

    @Test("duplicate filter keeps every individual from repeated species")
    func duplicateSpeciesKeepsEveryIndividual() {
        let mons = [mon(25, name: "피카츄"), mon(4, name: "파이리"),
                    mon(25, name: "피카츄"), mon(7, name: "꼬부기"),
                    mon(7, name: "꼬부기")]
        let duplicateIDs = RosterOrdering.duplicateEvolutionFamilyIDs(in: mons)

        #expect(duplicateIDs == Set([7, 25]))
        #expect(mons.filter { duplicateIDs.contains($0.baseID) }.map(\.currentID)
                == [25, 25, 7, 7])
    }

    @Test("selection lists use the visible localized name")
    func selectionListsAreAlphabetical() {
        let mons = [mon(25, name: "피카츄"), mon(1, name: "이상해씨"),
                    mon(4, name: "파이리"), mon(7, name: "꼬부기", nickname: "나리")]
        let arranged = RosterOrdering.alphabetizedForSelection(mons)

        #expect(arranged.map { $0.nickname ?? RosterOrdering.displayName($0) }
                == ["나리", "이상해씨", "파이리", "피카츄"])
    }
}
