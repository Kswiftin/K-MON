import Foundation
@testable import PokeTokenBar

enum CommunityFixture {
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
