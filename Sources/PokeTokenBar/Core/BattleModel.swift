import Foundation

// MARK: - 타입

/// 본가 18타입 — rawValue 는 PokéAPI type name 과 동일(직렬화·차트 키 겸용).
enum PokemonType: String, Codable, Sendable, CaseIterable {
    case normal, fire, water, electric, grass, ice
    case fighting, poison, ground, flying, psychic, bug
    case rock, ghost, dragon, dark, steel, fairy

    /// 본가 공식 번역 명칭 (ko/en/ja).
    func name(_ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch self {
        case .normal:   names = ("노말", "Normal", "ノーマル")
        case .fire:     names = ("불꽃", "Fire", "ほのお")
        case .water:    names = ("물", "Water", "みず")
        case .electric: names = ("전기", "Electric", "でんき")
        case .grass:    names = ("풀", "Grass", "くさ")
        case .ice:      names = ("얼음", "Ice", "こおり")
        case .fighting: names = ("격투", "Fighting", "かくとう")
        case .poison:   names = ("독", "Poison", "どく")
        case .ground:   names = ("땅", "Ground", "じめん")
        case .flying:   names = ("비행", "Flying", "ひこう")
        case .psychic:  names = ("에스퍼", "Psychic", "エスパー")
        case .bug:      names = ("벌레", "Bug", "むし")
        case .rock:     names = ("바위", "Rock", "いわ")
        case .ghost:    names = ("고스트", "Ghost", "ゴースト")
        case .dragon:   names = ("드래곤", "Dragon", "ドラゴン")
        case .dark:     names = ("악", "Dark", "あく")
        case .steel:    names = ("강철", "Steel", "はがね")
        case .fairy:    names = ("페어리", "Fairy", "フェアリー")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}

/// 타입 상성표 (Gen 6+) — 1.0 이 아닌 칸만 기록. 조회는 `TypeChart.effectiveness`.
enum TypeChart {
    /// [공격타입: [방어타입: 배율]]
    static let multipliers: [PokemonType: [PokemonType: Double]] = [
        .normal:   [.rock: 0.5, .ghost: 0, .steel: 0.5],
        .fire:     [.fire: 0.5, .water: 0.5, .grass: 2, .ice: 2, .bug: 2, .rock: 0.5, .dragon: 0.5, .steel: 2],
        .water:    [.fire: 2, .water: 0.5, .grass: 0.5, .ground: 2, .rock: 2, .dragon: 0.5],
        .electric: [.water: 2, .electric: 0.5, .grass: 0.5, .ground: 0, .flying: 2, .dragon: 0.5],
        .grass:    [.fire: 0.5, .water: 2, .grass: 0.5, .poison: 0.5, .ground: 2, .flying: 0.5,
                    .bug: 0.5, .rock: 2, .dragon: 0.5, .steel: 0.5],
        .ice:      [.fire: 0.5, .water: 0.5, .grass: 2, .ice: 0.5, .ground: 2, .flying: 2,
                    .dragon: 2, .steel: 0.5],
        .fighting: [.normal: 2, .ice: 2, .poison: 0.5, .flying: 0.5, .psychic: 0.5, .bug: 0.5,
                    .rock: 2, .ghost: 0, .dark: 2, .steel: 2, .fairy: 0.5],
        .poison:   [.grass: 2, .poison: 0.5, .ground: 0.5, .rock: 0.5, .ghost: 0.5, .steel: 0, .fairy: 2],
        .ground:   [.fire: 2, .electric: 2, .grass: 0.5, .poison: 2, .flying: 0, .bug: 0.5,
                    .rock: 2, .steel: 2],
        .flying:   [.electric: 0.5, .grass: 2, .fighting: 2, .bug: 2, .rock: 0.5, .steel: 0.5],
        .psychic:  [.fighting: 2, .poison: 2, .psychic: 0.5, .dark: 0, .steel: 0.5],
        .bug:      [.fire: 0.5, .grass: 2, .fighting: 0.5, .poison: 0.5, .flying: 0.5, .psychic: 2,
                    .ghost: 0.5, .dark: 2, .steel: 0.5, .fairy: 0.5],
        .rock:     [.fire: 2, .ice: 2, .fighting: 0.5, .ground: 0.5, .flying: 2, .bug: 2, .steel: 0.5],
        .ghost:    [.normal: 0, .psychic: 2, .ghost: 2, .dark: 0.5],
        .dragon:   [.dragon: 2, .steel: 0.5, .fairy: 0],
        .dark:     [.fighting: 0.5, .psychic: 2, .ghost: 2, .dark: 0.5, .fairy: 0.5],
        .steel:    [.fire: 0.5, .water: 0.5, .electric: 0.5, .ice: 2, .rock: 2, .steel: 0.5, .fairy: 2],
        .fairy:    [.fire: 0.5, .fighting: 2, .poison: 0.5, .dragon: 2, .dark: 2, .steel: 0.5],
    ]

    /// 공격타입 → 방어타입 조합(단일/복합) 배율. 복합타입은 곱.
    static func effectiveness(_ attacking: PokemonType, against defending: [PokemonType]) -> Double {
        defending.reduce(1.0) { $0 * (multipliers[attacking]?[$1] ?? 1.0) }
    }
}

// MARK: - 스탯

/// 종족값(base stats) — PokéAPI `/pokemon/{id}` stats 순서와 무관하게 이름으로 매핑.
struct BattleStats: Codable, Sendable, Equatable {
    var hp: Int
    var atk: Int
    var def: Int
    var spa: Int
    var spd: Int
    var spe: Int
}

/// 성격의 스탯 보정 — 본가 공식 표(오른 스탯 ×1.1, 내린 스탯 ×0.9, 중립 5종은 무보정).
enum NatureEffect {
    /// (오르는 스탯, 내리는 스탯). nil = 중립.
    static func modifiers(_ nature: PokemonNature) -> (up: WritableKeyPath<BattleStats, Int>, down: WritableKeyPath<BattleStats, Int>)? {
        switch nature {
        case .lonely:  return (\.atk, \.def)
        case .brave:   return (\.atk, \.spe)
        case .adamant: return (\.atk, \.spa)
        case .naughty: return (\.atk, \.spd)
        case .bold:    return (\.def, \.atk)
        case .relaxed: return (\.def, \.spe)
        case .impish:  return (\.def, \.spa)
        case .lax:     return (\.def, \.spd)
        case .timid:   return (\.spe, \.atk)
        case .hasty:   return (\.spe, \.def)
        case .jolly:   return (\.spe, \.spa)
        case .naive:   return (\.spe, \.spd)
        case .modest:  return (\.spa, \.atk)
        case .mild:    return (\.spa, \.def)
        case .quiet:   return (\.spa, \.spe)
        case .rash:    return (\.spa, \.spd)
        case .calm:    return (\.spd, \.atk)
        case .gentle:  return (\.spd, \.def)
        case .sassy:   return (\.spd, \.spe)
        case .careful: return (\.spd, \.spa)
        case .hardy, .docile, .serious, .bashful, .quirky: return nil
        }
    }

    static func multiplier(_ nature: PokemonNature?, for stat: WritableKeyPath<BattleStats, Int>) -> Double {
        guard let nature, let m = modifiers(nature) else { return 1.0 }
        if m.up == stat { return 1.1 }
        if m.down == stat { return 0.9 }
        return 1.0
    }
}

// MARK: - 기술 (네트워크 대전용)

enum MoveDamageClass: String, Codable, Sendable { case physical, special, status }

/// 대전에서 고르는 기술 하나 — PokéAPI move 에서 필요한 것만. 스냅샷에 실려 상대에게 전달되므로
/// 이름은 다국어 맵(수신 측이 자기 언어로 표시).
struct MoveSpec: Codable, Sendable, Equatable, Identifiable {
    var id: Int                     // PokéAPI move id. 음수 = 로컬 합성 기술(fetch 실패 폴백)
    var names: [String: String]     // langCode → 이름
    var type: PokemonType
    var power: Int
    var damageClass: MoveDamageClass
    var accuracy: Int?              // nil = 필중
    var pp: Int
    var descriptions: [String: String]? = nil
    /// 기술 우선도(PokéAPI `priority`). 전광석화 +1, 축지법 −6 처럼 스피드보다 먼저 보는 값이다.
    /// 옵셔널인 이유는 호환이다 — 구버전 세이브의 학습 기술과 구버전 피어가 보내온 무브셋에는
    /// 이 키가 없다. 없으면 보통 기술(0)로 읽는다.
    var priority: Int? = nil

    /// 턴 순서 비교용 우선도 — 값이 없으면 0.
    var turnPriority: Int { priority ?? 0 }

    func name(_ lang: AppLanguage) -> String { lang.resolveName(names) ?? names.values.first ?? "?" }
    func description(_ lang: AppLanguage) -> String? {
        guard let descriptions else { return nil }
        return lang.resolveName(descriptions) ?? descriptions["en"] ?? descriptions.values.first
    }

    /// 발버둥 — PP 전부 소진 시 폴백(무속성 취급은 엔진에서 id 로 판정).
    static let struggleID = -999
    static func struggle() -> MoveSpec {
        MoveSpec(id: struggleID,
                 names: ["ko": "발버둥", "en": "Struggle", "ja": "わるあがき"],
                 type: .normal, power: 50, damageClass: .physical, accuracy: nil, pp: 999)
    }

    /// 기술 fetch 실패 시 합성 무브셋 — 자기 타입 기반 4개(대전 자체는 항상 가능해야 한다).
    static func fallbackSet(types: [PokemonType]) -> [MoveSpec] {
        let t1 = types.first ?? .normal
        let t2 = types.count > 1 ? types[1] : t1
        func synth(_ id: Int, _ ko: String, _ en: String, _ ja: String,
                   _ type: PokemonType, _ power: Int, _ cls: MoveDamageClass, _ acc: Int?, _ pp: Int) -> MoveSpec {
            MoveSpec(id: id, names: ["ko": ko, "en": en, "ja": ja],
                     type: type, power: power, damageClass: cls, accuracy: acc, pp: pp)
        }
        return [
            synth(-1, "몸통박치기", "Tackle", "たいあたり", .normal, 40, .physical, 100, 35),
            synth(-2, "속이기", "Fake Out", "ねこだまし", .normal, 40, .physical, 100, 10),
            synth(-3, "\(t1.name(.ko)) 일격", "\(t1.name(.en)) Strike", "\(t1.name(.ja))のいちげき", t1, 80, .physical, 100, 15),
            synth(-4, "\(t2.name(.ko)) 파동", "\(t2.name(.en)) Pulse", "\(t2.name(.ja))のはどう", t2, 70, .special, 100, 20),
        ]
    }
}

// MARK: - 배틀 스냅샷 (교환 단위)

/// 대전 상대와 교환되는 포켓몬 스냅샷 — 수신 측이 추가 조회 없이 배틀할 수 있게 스탯·타입을 내장한다.
struct BattleSnapshot: Codable, Sendable, Equatable {
    var v: Int = 1
    var speciesID: Int
    /// 표시 이름 — 내보내는 쪽 언어의 현지화 이름(수신 측은 그대로 표시).
    var name: String
    var trainer: String?
    var level: Int
    var nature: PokemonNature?
    var isShiny: Bool
    var types: [PokemonType]
    /// 종족값 — 유효 스탯은 배틀 시점에 level·nature 로 계산(레벨만 바꾸는 변조 방지 폭 축소).
    var base: BattleStats
    /// 네트워크 대전용 무브셋(최대 4).
    var moves: [MoveSpec]? = nil

    /// 레벨 유도 — 성장 진행도(단계 + 단계 내 진행)를 5~100 레벨로 사상.
    /// stageProgress 는 0~1 로 클램프, totalForms ≥ 1 보장.
    static func level(stageIndex: Int, totalForms: Int, stageProgress: Double) -> Int {
        let k = max(1, totalForms)
        let p = min(1.0, max(0.0, stageProgress))
        let overall = min(1.0, (Double(stageIndex) + p) / Double(k))
        return min(100, max(5, 5 + Int((overall * 95.0).rounded())))
    }

    /// 유효 스탯 (IV 31 고정, EV 0, 성격 보정 포함) — 본가 공식.
    func effectiveStats() -> BattleStats {
        let l = level
        func other(_ base: Int, _ stat: WritableKeyPath<BattleStats, Int>) -> Int {
            let raw = (2 * base + 31) * l / 100 + 5
            return Int(Double(raw) * NatureEffect.multiplier(nature, for: stat))
        }
        return BattleStats(
            hp: (2 * base.hp + 31) * l / 100 + l + 10,
            atk: other(base.atk, \.atk),
            def: other(base.def, \.def),
            spa: other(base.spa, \.spa),
            spd: other(base.spd, \.spd),
            spe: other(base.spe, \.spe))
    }

}

// MARK: - 배틀 엔진

/// 결정적 RNG — 같은 seed 면 같은 배틀(두 참가자가 각자 실행해도 동일 결과).
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum BattleEngine {
    static let critDenominator: UInt64 = 16

    /// 대전 규칙 버전 — 턴 순서나 데미지 계산을 바꿀 때마다 올린다. 두 피어가 결과를 주고받지 않고
    /// 각자 계산하므로, 규칙이 다른 앱끼리 붙으면 같은 배틀을 서로 다르게 본다. 1 = 우선도 도입.
    static let rulesVersion = 1

    /// 공격 1회의 결과. 1v1 과 멀티가 같은 값을 내야 하므로 계산은 `resolveAttack` 한 곳에만 둔다.
    struct AttackOutcome: Sendable {
        var missed: Bool
        var damage: Int
        /// 빗나갔으면 1 — 화면이 "효과가 굉장했다" 를 띄우지 않게 한다.
        var effectiveness: Double
        var isCritical: Bool
    }

    /// 공격 1회 해상. **rng 소비 순서가 프로토콜의 일부다** — 명중 → 급소 → 난수 폭 순서로 소비하며,
    /// 빗나가면 뒤의 둘을 소비하지 않는다. 두 피어가 같은 입력이면 같은 분기를 타므로 소비량도 같다.
    ///
    /// 예전엔 이 계산이 1v1(`resolveTurn`)과 멀티(`resolveAttack`)에 각각 복사돼 있었다. 한쪽만
    /// 고치면 두 모드가 조용히 갈라지고, 새 기전을 넣을 때마다 같은 코드를 두 번 써야 했다.
    static func resolveAttack(attacker: BattleSnapshot, attackerStats: BattleStats,
                              defender: BattleSnapshot, defenderStats: BattleStats,
                              move: MoveSpec, rng: inout SplitMix64) -> AttackOutcome {
        if let accuracy = move.accuracy, Int(rng.next() % 100) >= accuracy {
            return AttackOutcome(missed: true, damage: 0, effectiveness: 1, isCritical: false)
        }
        // 발버둥은 무속성(상성·STAB 미적용).
        let isStruggle = move.id == MoveSpec.struggleID
        let effectiveness = isStruggle ? 1.0 : TypeChart.effectiveness(move.type, against: defender.types)
        let stab = (!isStruggle && attacker.types.contains(move.type)) ? 1.5 : 1.0
        let attack = move.damageClass == .physical ? attackerStats.atk : attackerStats.spa
        let defense = move.damageClass == .physical ? defenderStats.def : defenderStats.spd
        let isCritical = rng.next() % critDenominator == 0
        let roll = 0.85 + Double(rng.next() % 16) / 100.0
        let base = Double((2 * attacker.level / 5 + 2) * move.power * attack / max(1, defense)) / 50.0 + 2.0
        let damage = effectiveness == 0 ? 0
            : max(1, Int(base * stab * effectiveness * (isCritical ? 1.5 : 1.0) * roll))
        return AttackOutcome(missed: false, damage: damage,
                             effectiveness: effectiveness, isCritical: isCritical)
    }

    /// 두 공격자 중 누가 먼저인가 — 본가와 같은 순서로 본다: **기술 우선도 → 스피드 → 무작위**.
    ///
    /// 무작위는 앞의 둘이 모두 같을 때만 소비한다(예전 1v1 규칙 그대로). 멀티는 이 자리에서
    /// UUID 문자열 순서로 갈랐는데, 그러면 앱을 켠 동안 사전순으로 앞선 참가자가 동점 때마다
    /// 선공을 가져간다 — 실력과 무관한 데다 화면에 드러나지도 않는다.
    static func firstMoverIsA(priorityA: Int, priorityB: Int, speedA: Int, speedB: Int,
                              rng: inout SplitMix64) -> Bool {
        if priorityA != priorityB { return priorityA > priorityB }
        if speedA != speedB { return speedA > speedB }
        return rng.next() & 1 == 0
    }
}

// MARK: - 네트워크 대전 턴 해상

/// 네트워크 대전에서 한 쪽의 공격 시도 1건(한 턴 = 최대 2건).
struct NetBattleEvent: Codable, Sendable, Equatable {
    var attackerIsA: Bool
    var moveID: Int
    var missed: Bool
    var damage: Int
    var effectiveness: Double   // 0 = 효과 없음(무효), missed 면 1
    var isCritical: Bool
    var defenderHPAfter: Int
}

extension BattleEngine {
    /// 양쪽 기술 선택이 모이면 한 턴 해상. 순수·결정적 — 같은 rng 상태·입력이면 두 피어가 같은 결과를
    /// 각자 계산한다(결과 자체는 네트워크로 보내지 않는다 → 변조 여지 축소).
    /// rng 소비 순서가 프로토콜의 일부다 — 브랜치를 바꾸면 두 피어 결과가 갈라진다.
    static func resolveTurn(a: BattleSnapshot, b: BattleSnapshot,
                            statsA: BattleStats, statsB: BattleStats,
                            hpA: inout Int, hpB: inout Int,
                            moveA: MoveSpec, moveB: MoveSpec,
                            rng: inout SplitMix64) -> [NetBattleEvent] {
        var events: [NetBattleEvent] = []
        let aIsFirst = firstMoverIsA(priorityA: moveA.turnPriority, priorityB: moveB.turnPriority,
                                     speedA: statsA.spe, speedB: statsB.spe, rng: &rng)
        for attackerIsA in aIsFirst ? [true, false] : [false, true] {
            guard hpA > 0 && hpB > 0 else { break }   // 선공에 기절하면 후공 없음
            let (atk, atkStats, move) = attackerIsA ? (a, statsA, moveA) : (b, statsB, moveB)
            let (def, defStats) = attackerIsA ? (b, statsB) : (a, statsA)

            let outcome = resolveAttack(attacker: atk, attackerStats: atkStats,
                                        defender: def, defenderStats: defStats,
                                        move: move, rng: &rng)

            if attackerIsA { hpB = max(0, hpB - outcome.damage) } else { hpA = max(0, hpA - outcome.damage) }
            events.append(NetBattleEvent(attackerIsA: attackerIsA, moveID: move.id, missed: outcome.missed,
                                         damage: outcome.damage, effectiveness: outcome.effectiveness,
                                         isCritical: outcome.isCritical,
                                         defenderHPAfter: attackerIsA ? hpB : hpA))
        }
        return events
    }
}
