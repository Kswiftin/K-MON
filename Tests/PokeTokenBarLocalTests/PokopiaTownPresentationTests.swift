import Foundation
import Testing
@testable import PokeTokenBar

@Suite struct PokopiaTownPresentationTests {
    private let choices: [PokopiaTransformCandidate] = [
        .init(id: 1, name: "이상해씨", isShiny: false, brush: .grass),
        .init(id: 25, name: "피카츄", isShiny: false, brush: .path),
        .init(id: 26, name: "라이츄", isShiny: true, brush: .path),
        .init(id: 999, name: "Unknown", isShiny: false, brush: nil),
    ]

    // 검색 조건을 무시하거나 OR 로 합치면 필요 없는 변신 후보가 나타난다.
    @Test func searchTrimsWhitespaceAndMatchesPartOfAName() {
        let result = PokopiaTownPresentation.filtered(choices, query: "  피카  ", terrain: nil)
        #expect(result.map(\.id) == [25])
    }

    @Test func searchCanFindASpeciesNumber() {
        #expect(PokopiaTownPresentation.filtered(choices, query: "#26", terrain: nil).map(\.id) == [26])
    }

    @Test func searchIsCaseInsensitive() {
        #expect(PokopiaTownPresentation.filtered(choices, query: "unknown", terrain: nil).map(\.id) == [999])
    }

    @Test func terrainFilterAndSearchMustBothMatch() {
        #expect(PokopiaTownPresentation.filtered(choices, query: "츄", terrain: .path).map(\.id) == [25, 26])
        #expect(PokopiaTownPresentation.filtered(choices, query: "피카", terrain: .grass).isEmpty)
    }

    @Test func clearingFiltersRestoresAllCandidatesInOrder() {
        #expect(PokopiaTownPresentation.filtered(choices, query: " \n", terrain: nil).map(\.id) == [1, 25, 26, 999])
        #expect(PokopiaTownPresentation.filtered(choices, query: "", terrain: .path).map(\.id) == [25, 26])
    }

    // 도감 중복의 첫 항목이 store.townBrush 와 같은 타입을 쓰고, 등록 집합 밖 종은 보이지 않아야 한다.
    @Test func candidatesRespectRegistrationAndTheStoresFirstEntry() {
        let entries = [entry(25, name: "피카츄", types: [.electric]),
                       entry(1, name: "이상해씨", types: [.grass]),
                       entry(25, name: "다른 기록", types: [.water]),
                       entry(7, name: "꼬부기", types: [.water])]
        let result = PokopiaTownPresentation.candidates(entries: entries, registeredSpecies: [1, 25])
        #expect(result.map(\.id) == [1, 25])
        #expect(result.last?.name == "피카츄")
        #expect(result.last?.brush == .path)
    }

    @Test func candidatesKeepUnknownTypesAndAFallbackName() {
        let result = PokopiaTownPresentation.candidates(entries: [entry(999, name: nil, types: nil)],
                                                       registeredSpecies: [999])
        #expect(result.first?.name == "#999")
        #expect(result.first?.brush == nil)
    }

    // 상한 상태를 잘못된 순서로 판정하면 불가능한 이사나 확장을 안내한다.
    @Test func globalLimitTakesPriorityOverAvailableLocalSpace() {
        let town = PokopiaTownState()
        #expect(PokopiaTownPresentation.arrival(town: town, totalResidents: 60) == .globalLimit)
        #expect(PokopiaTownPresentation.arrival(town: town, totalResidents: 61) == .globalLimit)
    }

    @Test func fullTownCanExpandOnlyWhenAHabitatIsMissing() {
        var town = PokopiaTownState()
        town.terrain = Array(repeating: .grass, count: 192)
        town.residents = residents(2)
        #expect(PokopiaTownPresentation.arrival(town: town, totalResidents: 2) == .full(canExpand: true))

        town.terrain = TownTerrain.allCases.flatMap { Array(repeating: $0, count: 24) }
        town.residents = residents(16)
        #expect(PokopiaTownPresentation.arrival(town: town, totalResidents: 16) == .full(canExpand: false))
    }

    @Test func availableTownReportsOnlyWelcomingTypes() {
        var town = PokopiaTownState()
        town.terrain = Array(repeating: .grass, count: 188) + Array(repeating: .water, count: 4)
        let arrival = PokopiaTownPresentation.arrival(town: town, totalResidents: 59)
        guard case let .welcoming(types) = arrival else {
            Issue.record("자리가 있는 마을을 이사 불가로 표시한다")
            return
        }
        #expect(Set(types) == [.grass, .bug])
    }

    @Test func populationLimitTownCannotOpenArrivalSpaceByAddingAHabitat() {
        var town = PokopiaTownState()
        town.terrain = Array(repeating: .grass, count: 192)
        town.residents = residents(16)
        #expect(PokopiaTownPresentation.arrival(town: town, totalResidents: 16) == .full(canExpand: false))
    }

    @Test func emptyHabitatDoesNotPromiseAnArrival() {
        var town = PokopiaTownState()
        town.terrain = []
        #expect(PokopiaTownPresentation.arrival(town: town, totalResidents: 0) == .noHabitat)
    }

    private func entry(_ id: Int, name: String?, types: [PokemonType]?) -> DexEntry {
        DexEntry(baseID: id, finalID: id, chainOrder: [id], rarity: .common, caughtAt: nil,
                 names: name.map { [id: ["ko": $0, "en": $0]] }, types: types)
    }

    private func residents(_ count: Int) -> [TownResident] {
        (1...count).map { TownResident(speciesID: $0, name: "주민 \($0)", types: [.grass],
                                      arrivedAt: Date(timeIntervalSince1970: 0)) }
    }
}
