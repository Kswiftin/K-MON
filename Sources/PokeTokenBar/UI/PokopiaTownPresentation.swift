import Foundation

/// 화면에 필요한 값만 파생한다. 저장 상태와 게임 규칙은 기존 마을·도감 모델이 소유한다.
struct PokopiaTransformCandidate: Identifiable, Equatable {
    let id: Int
    let name: String
    let isShiny: Bool
    let brush: TownTerrain?
}

enum PokopiaTownPresentation {
    enum Arrival: Equatable {
        case globalLimit
        case full(canExpand: Bool)
        case noHabitat
        case welcoming(types: [PokemonType])
    }

    static func candidates(entries: [DexEntry], registeredSpecies: Set<Int>) -> [PokopiaTransformCandidate] {
        var seen = Set<Int>()
        return entries.compactMap { entry in
            guard registeredSpecies.contains(entry.finalID), seen.insert(entry.finalID).inserted else { return nil }
            return PokopiaTransformCandidate(
                id: entry.finalID,
                name: entry.names?[entry.finalID].flatMap { PokemonNaming.name($0) } ?? "#\(entry.finalID)",
                isShiny: entry.isShiny,
                brush: PokopiaTown.brush(dittoFormTypes: entry.types))
        }.sorted { $0.id < $1.id }
    }

    static func filtered(_ candidates: [PokopiaTransformCandidate], query: String,
                         terrain: TownTerrain?) -> [PokopiaTransformCandidate] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates.filter { candidate in
            let matchesName = query.isEmpty
                || candidate.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || "#\(candidate.id)".contains(query)
            return matchesName && (terrain == nil || candidate.brush == terrain)
        }
    }

    static func arrival(town: PokopiaTownState, totalResidents: Int) -> Arrival {
        if totalResidents >= PokopiaTown.globalPopulationLimit { return .globalLimit }
        let habitats = PokopiaTown.habitats(town.terrain).filter(\.isWelcoming)
        guard !habitats.isEmpty else { return .noHabitat }
        let development = PokopiaTown.development(town.terrain, residents: town.residents)
        if town.residents.count >= development.capacity {
            return .full(canExpand: town.residents.count < PokopiaTown.populationLimit
                         && development.habitats < TownTerrain.allCases.count)
        }
        return .welcoming(types: habitats.flatMap(\.types))
    }
}
