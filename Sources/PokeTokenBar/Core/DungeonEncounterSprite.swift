import Foundation

/// 던전 방에 나타나는 야생 포켓몬 종을 정한다. **무작위가 아니라 결정적**이다 — 같은 날 같은 방은
/// 누가 몇 번을 다시 들어가도 같은 포켓몬을 만난다(`PuzzleDungeon` 과 같은 설계 원칙).
/// 스프라이트 다운로드는 다른 곳의 책임이고, 여기는 어떤 종인지만 고른다.
enum DungeonEncounterSprite {
    /// 1~5 세대 종 id, 타입별. 전부 `PokemonAssets.animatedSpeciesIDs`(1...649) 안이다.
    static let speciesByType: [PokemonType: [Int]] = [
        .normal: [19, 52, 161, 399],
        .fire: [4, 58, 155, 255],
        .water: [7, 54, 158, 258],
        .electric: [25, 81, 179, 309],
        .grass: [1, 43, 152, 252],
        .ice: [86, 220, 361, 459],
        .fighting: [56, 66, 236, 296],
        .poison: [23, 41, 88, 316],
        .ground: [27, 50, 104, 328],
        .flying: [16, 21, 163, 396],
        .psychic: [63, 96, 177, 280],
        .bug: [10, 13, 165, 265],
        .rock: [74, 95, 299, 304],
        .ghost: [92, 200, 353, 355],
        .dragon: [147, 371, 443, 633],
        .dark: [198, 228, 261, 509],
        .steel: [81, 227, 304, 436],
        .fairy: [35, 39, 173, 183],
    ]

    /// 보스 방 전용 후보 — 준전설·강한 개체 위주.
    static let bossSpecies = [149, 248, 373, 376, 445, 635]

    /// 교전 방의 야생 포켓몬 종. `room` 마다 씨앗을 갈라 같은 날이라도 방마다 달라진다.
    static func species(dayKey: String, room: Int, affinity: PokemonType) -> Int {
        let candidates = speciesByType[affinity] ?? speciesByType[.normal]!
        var rng = SplitMix64(seed: PuzzleDungeon.seed(dayKey: dayKey) &+ UInt64(room) &* 0x9E37_79B9)
        return candidates[Int(rng.next() % UInt64(candidates.count))]
    }

    /// 오늘의 보스 종 — 날짜별로 고정, 방 번호와 무관하다.
    static func boss(dayKey: String) -> Int {
        var rng = SplitMix64(seed: PuzzleDungeon.seed(dayKey: dayKey))
        return bossSpecies[Int(rng.next() % UInt64(bossSpecies.count))]
    }
}
