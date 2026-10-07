import Foundation
@testable import PokeTokenBar

enum CommunityFixture {
    @MainActor static func store(at url: URL, clock: @escaping () -> Date) -> CompanionStore {
        if !FileManager.default.fileExists(atPath: url.path) {
            let state = SaveTransfer.signed(CompanionState())
            try! JSONEncoder().encode(state).write(to: url)
        }
        return CompanionStore(provider: CommunityNoProvider(), clock: clock, fileURL: url,
                              rng: CommunityRNG(), dittoDisguiseRollingEnabled: false)
    }
    static let now = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")!

    static func context(dayKey: String = "2026-10-07", residents: Int = 1,
                        availableBrushes: Set<TownTerrain> = [],
                        canShareFood: Bool = false) -> PokopiaCommunityContext {
        let species = [1, 4, 7, 25, 133]
        var towns: [String: PokopiaTownState] = [:]
        for (index, region) in TownRegion.allCases.prefix(residents).enumerated() {
            var town = PokopiaTownState(region: region)
            town.terrain = Array(repeating: .sand, count: PokopiaTown.tileCount)
            town.residents = [.init(speciesID: species[index], name: "주민\(index + 1)",
                                    types: [.grass], arrivedAt: now)]
            towns[region.rawValue] = town
        }
        return .init(dayKey: dayKey, towns: towns, availableBrushes: availableBrushes,
                     canShareFood: canShareFood)
    }
}

private struct CommunityNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private struct CommunityRNG: RandomNumberGenerator {
    private var value: UInt64 = 7
    mutating func next() -> UInt64 {
        value = value &* 6364136223846793005 &+ 1442695040888963407
        return value
    }
}
