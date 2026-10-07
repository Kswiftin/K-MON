import Foundation

/// 레이드 안내는 일반 개체 HP가 아니라 티어 HP와 현재 방어 타입을 사용한다.
struct RaidBossInfo {
    struct Matchup: Identifiable {
        let multiplier: Double
        let types: [PokemonType]
        var id: Double { multiplier }
        var label: String {
            switch multiplier {
            case 4: "약점 · 4배"
            case 2: "약점 · 2배"
            case 0.5: "반감 · ½배"
            case 0.25: "반감 · ¼배"
            default: "면역 · 0배"
            }
        }
    }

    let speciesID: Int
    let name: String
    let level: Int
    let maxHP: Int
    let types: [PokemonType]
    let abilitySlug: String?

    init(speciesID: Int, name: String, profile: PokemonBattleProfile, tier: RaidTier) {
        self.speciesID = speciesID
        self.name = name
        level = tier.bossLevel
        maxHP = tier.bossHP
        types = profile.types
        abilitySlug = profile.abilitySlug
    }

    init(side: BattleSide, maxHP: Int) {
        speciesID = side.snapshot.speciesID
        name = side.snapshot.name
        level = side.snapshot.level
        self.maxHP = maxHP
        types = side.activeTypes
        abilitySlug = side.abilityOverride?.rawValue ?? side.snapshot.ability
    }

    var groups: [Matchup] { Self.matchups(types: types) }

    /// 배율은 기존 상성표에서 구한다. 특성·기술별 예외와 피해량 보정은 이 표에 섞지 않는다.
    static func matchups(types: [PokemonType]) -> [Matchup] {
        guard !types.isEmpty else { return [] }
        return [4.0, 2, 0.5, 0.25, 0].compactMap { multiplier in
            let attacks = PokemonType.allCases.filter {
                TypeChart.effectiveness($0, against: types) == multiplier
            }
            return attacks.isEmpty ? nil : Matchup(multiplier: multiplier, types: attacks)
        }
    }
}
