import XCTest
@testable import PokeTokenBar

final class DungeonEncounterSpriteTests: XCTestCase {
    func testEveryTypeHasAtLeastFourSpecies() {
        for type in PokemonType.allCases {
            let ids = DungeonEncounterSprite.speciesByType[type]
            XCTAssertNotNil(ids, "\(type) 항목 누락")
            XCTAssertGreaterThanOrEqual(ids?.count ?? 0, 4, "\(type) 는 4종 이상이어야 한다")
        }
    }

    func testEveryIDIsValidAnimatedSpecies() {
        for (type, ids) in DungeonEncounterSprite.speciesByType {
            for id in ids {
                XCTAssertTrue(PokemonAssets.animatedSpeciesIDs.contains(id), "\(type) 의 \(id) 가 범위 밖")
                XCTAssertTrue(PokemonAssets.hasAnimatedSprite(speciesID: id), "\(type) 의 \(id) 애니메이션 없음")
            }
        }
    }

    func testSameInputsProduceSameSpecies() {
        let a = DungeonEncounterSprite.species(dayKey: "2026-08-26", room: 5, affinity: .fire)
        let b = DungeonEncounterSprite.species(dayKey: "2026-08-26", room: 5, affinity: .fire)
        XCTAssertEqual(a, b)
    }

    func testResultBelongsToAffinityTable() {
        for type in PokemonType.allCases {
            let species = DungeonEncounterSprite.species(dayKey: "2026-08-26", room: 3, affinity: type)
            XCTAssertTrue(DungeonEncounterSprite.speciesByType[type]?.contains(species) ?? false,
                          "\(type) 결과 \(species) 가 표에 없다")
        }
    }

    func testBossIsStableForSameDayKey() {
        let a = DungeonEncounterSprite.boss(dayKey: "2026-08-26")
        let b = DungeonEncounterSprite.boss(dayKey: "2026-08-26")
        XCTAssertEqual(a, b)
        XCTAssertTrue(DungeonEncounterSprite.bossSpecies.contains(a))
    }

    func testDifferentRoomsCanProduceDifferentSpecies() {
        let species = (0..<20).map {
            DungeonEncounterSprite.species(dayKey: "2026-08-26", room: $0, affinity: .water)
        }
        XCTAssertGreaterThan(Set(species).count, 1, "room 이 달라도 항상 같은 종이면 결정적 다양성이 없다")
    }
}
