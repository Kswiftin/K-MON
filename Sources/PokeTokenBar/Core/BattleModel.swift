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

    /// 공격타입 → 방어타입 조합(단일/복합) 배율. 복합타입은 곱. **표시용**이다 —
    /// "효과가 굉장했다" 를 띄울지 판단하는 값이고, 데미지 계산은 `apply(_:of:against:)` 를 쓴다.
    static func effectiveness(_ attacking: PokemonType, against defending: [PokemonType]) -> Double {
        defending.reduce(1.0) { $0 * (multipliers[attacking]?[$1] ?? 1.0) }
    }

    /// 상성을 **정수 연산**으로 적용한다 — 방어 타입을 하나씩 곱하거나 나눈다(Gen 2 방식).
    /// 배율을 Double 로 한 번에 곱하면 두 피어가 각자 계산하는 이 대전에서 부동소수 오차가
    /// 결과를 가를 여지가 남는다. 표의 값은 0 / 0.5 / 2 뿐이라 정수 곱·나눗셈으로 정확히 옮겨진다.
    static func apply(_ damage: Int, of attacking: PokemonType, against defending: [PokemonType]) -> Int {
        var out = damage
        for type in defending {
            let multiplier = multipliers[attacking]?[type] ?? 1
            if multiplier == 0 { return 0 }
            if multiplier > 1 { out *= Int(multiplier) }
            else if multiplier < 1 { out /= Int(1 / multiplier) }
        }
        return out
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

    /// 급소율 보정(PokéAPI `meta.crit_rate`). 베어가르기·잎날가르기처럼 급소가 잘 나는 기술은
    /// 여기에 양수가 온다. `priority` 와 같은 이유로 옵셔널이다 — 이 키가 없던 시절의 세이브와
    /// 구버전 피어의 무브셋에는 값이 아예 없다. 그런 기술은 보통 급소율로 읽는다.
    var critRate: Int? = nil

    /// 이 기술이 거는 상태이상(PokéAPI `meta.ailment` 의 이름). `priority`·`critRate` 와 같은 이유로
    /// 옵셔널이다 — 이 키가 없던 시절의 세이브와 구버전 피어의 무브셋에는 값이 아예 없다.
    var ailment: String? = nil
    /// 상태를 걸 확률(PokéAPI `meta.ailment_chance`). 0 은 "확률이 아니다" 라는 뜻이다.
    var ailmentChance: Int? = nil

    /// 턴 순서 비교용 우선도 — 값이 없으면 0.
    var turnPriority: Int { priority ?? 0 }

    /// 급소 단계 — Gen 2 의 고급소기는 **+2 단계**(1/4)다. PokéAPI 의 `crit_rate` 는 세대에 따라
    /// 뜻이 달라(Gen 6+ 는 +1 단계) 값을 그대로 쓰지 않고, 고급소기인지만 보고 Gen 2 단계로 옮긴다.
    var critStage: Int { (critRate ?? 0) > 0 ? 2 : 0 }

    /// 실제로 걸 수 있는 상태 — 구현한 6종만. 나머지 14종은 `nil` 이라 부여 시도가 그냥 지나간다
    /// (무엇을 건너뛰었는지는 스펙을 만들 때 `AppLog` 에 한 번 남긴다).
    ///
    /// 맹독은 PokéAPI 가 별도 ailment 로 주지 않는다 — 맹독(id 92)도 `ailment` 는 `poison` 이다.
    /// 그래서 이 기술만 id 로 가른다.
    var inflictedStatus: Status? {
        if id == Self.toxicMoveID { return .toxic }
        return ailment.flatMap(Status.init(ailment:))
    }

    /// 상태를 거는 확률(%) — 2차효과는 `ailment_chance` 를 그대로 쓰고, 위력 없는 변화기는
    /// 상태 부여가 기술 **본체**라 늘 건다(PokéAPI 가 그런 기술에 0 을 준다).
    var ailmentChancePercent: Int {
        let chance = ailmentChance ?? 0
        if chance > 0 { return chance }
        return damageClass == .status ? 100 : 0
    }

    /// 맹독 — PokéAPI move id.
    static let toxicMoveID = 92

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

// MARK: - 상태이상

/// 상태이상 — Gen 2 의 6종 + 혼란. PokéAPI `/move-ailment` 20종 중 6종만 쓰고 나머지는 무시한다
/// (맹독은 이름이 없어 기술 id 로 가른다 — `MoveSpec.inflictedStatus`).
/// 앞 6종은 주 상태(한 번에 하나), 혼란은 volatile 이다. 화면 어휘를 하나로 두려고 한 enum 에 있고,
/// 어느 쪽인지는 `BattleSide` 가 필드로 가른다.
enum Status: String, Codable, Sendable, Equatable, CaseIterable {
    case burn, poison, toxic, paralysis, sleep, freeze, confusion

    /// PokéAPI `/move-ailment` 이름 → 구현한 상태. `none`·`unknown` 을 포함해 모르는 이름은 `nil` 이다.
    init?(ailment: String) {
        switch ailment {
        case "burn":      self = .burn
        case "poison":    self = .poison
        case "paralysis": self = .paralysis
        case "sleep":     self = .sleep
        case "freeze":    self = .freeze
        case "confusion": self = .confusion
        default:          return nil   // toxic 은 ailment 이름이 없다 — `MoveSpec.inflictedStatus` 참조
        }
    }

    /// HP바 옆 배지 — Showdown 과 같은 약어라 언어를 타지 않는다.
    var badge: String {
        switch self {
        case .burn:      return "BRN"
        case .poison:    return "PSN"
        case .toxic:     return "TOX"
        case .paralysis: return "PAR"
        case .sleep:     return "SLP"
        case .freeze:    return "FRZ"
        case .confusion: return "CNF"
        }
    }
}

/// 데미지가 어디서 왔는가. 로그·연출은 "기술을 맞았다" 와 "화상으로 깎였다" 를 갈라야 하는데,
/// 원인이 없으면 잔뎀이 직전 `.move` 에 접혀 **쓰지도 않은 기술 이름**이 붙는다.
enum DamageCause: String, Codable, Sendable, Equatable {
    case move, burn, poison, toxic, confusion
}

// MARK: - 배틀 중 한쪽의 상태

/// 대전 중 한쪽이 들고 있는 것 전부 — 스냅샷은 *교환 단위*고, 이쪽은 **턴을 넘어 사는 상태**다.
/// 세 모드(`NetBattleState`·`TeamPracticeBattle`·`MultiplayerFighter`)가 각자 `hp`/`pp` 를 나열하던
/// 자리다. 상태를 한 타입에 모아야 상태이상·랭크업 같은 기전을 세 번 쓰지 않는다.
struct BattleSide: Sendable, Equatable {
    var snapshot: BattleSnapshot
    /// 유효 스탯 — 배틀에 들어올 때 1회 계산한다. `effectiveStats()` 를 그때그때 부르면 정렬
    /// 비교자 안에서 비교 횟수만큼 다시 계산되고(멀티가 그랬다), 랭크업이 들어오는 순간
    /// "부스트 없는 원래 스피드로 정렬" 이라는 오답이 된다.
    let stats: BattleStats
    var hp: Int
    /// 이 배틀에서 쓸 무브셋 — 스냅샷에 없으면(구버전 세이브·fetch 실패) 합성 무브셋.
    /// 세 모드가 각자 `snapshot.moves ?? fallbackSet(...)` 를 반복하던 자리다.
    let moves: [MoveSpec]
    var pp: [Int]
    /// 주 상태이상 — 한 번에 하나. 혼란은 volatile 이라 여기가 아니라 `confusionTurns` 에 둔다.
    var status: Status?
    /// 상태마다 뜻이 다른 한 칸 — 맹독은 누적 배수(1, 2, 3…), 잠듦은 남은 카운터다.
    /// 주 상태가 하나뿐이라 두 값이 동시에 필요할 일이 없어 칸을 나누지 않는다.
    var statusCounter = 0
    /// 남은 혼란 턴 — 이 수만큼 자멸 판정을 굴린다.
    var confusionTurns = 0

    init(_ snapshot: BattleSnapshot) {
        self.snapshot = snapshot
        stats = snapshot.effectiveStats()
        hp = stats.hp
        moves = snapshot.moves ?? MoveSpec.fallbackSet(types: snapshot.types)
        pp = moves.map(\.pp)
    }

    var isAlive: Bool { hp > 0 }
    var isConfused: Bool { confusionTurns > 0 }

    /// 턴 순서에 쓰는 스피드 — 마비면 Gen 2 기준 25%(Gen 7 부터 50%).
    /// 순서 계산이 `stats.spe` 를 직접 읽으면 마비가 스탯 화면에만 보이고 실제 선공은 그대로다.
    var effectiveSpeed: Int { status == .paralysis ? max(1, stats.spe / 4) : stats.spe }

    /// 이 상태가 붙을 수 있는가. 타입 면역은 **Gen 2 것만** 가져온다 —
    /// 전기 타입의 마비 면역, 풀 타입의 가루 면역은 Gen 6 규칙이라 여기 없다.
    func canBeAfflicted(by status: Status) -> Bool {
        guard isAlive else { return false }
        if status == .confusion { return !isConfused }
        guard self.status == nil else { return false }   // 주 상태는 하나
        let types = snapshot.types
        switch status {
        case .burn:            return !types.contains(.fire)
        case .freeze:          return !types.contains(.ice)
        case .poison, .toxic:  return !types.contains(.poison) && !types.contains(.steel)
        default:               return true
        }
    }

    /// 고를 수 있는 기술이 하나도 없으면 발버둥.
    var mustStruggle: Bool { !pp.contains { $0 > 0 } }

    /// 인덱스로 기술 — 범위 밖이거나 음수면 발버둥(PP 소진 선택은 −1 로 온다).
    func move(at index: Int) -> MoveSpec {
        moves.indices.contains(index) ? moves[index] : .struggle()
    }

    /// 이번 턴에 이 인덱스의 기술을 쓸 수 있는가 — 인덱스 범위와 남은 PP 를 **같이** 본다.
    /// `pp` 는 와이어로 들어오는 값이라 `moves` 와 길이가 어긋날 수 있다(경계에서 함께 막는다).
    func canUse(moveAt index: Int) -> Bool {
        moves.indices.contains(index) && pp.indices.contains(index) && pp[index] > 0
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

/// 끝난 배틀의 승패. **무승부가 값으로 있어야 한다** — 없으면 동시 전멸을 어느 한쪽 승리로 접게 되고
/// (팀 연습이 그랬다) 보상·배지가 이기지 않은 판에서 나간다. 세 모드가 같은 enum 을 쓴다.
enum BattleOutcome: Sendable { case win, loss, draw }

enum BattleEngine {
    /// 급소 배율 — Gen 2 는 ×2(Gen 6+ 는 ×1.5). 상수인 건 밸런스 재조정 여지를 남기려는 것이다.
    static let critMultiplier = 2

    /// 급소 확률의 분자(분모 256) — Gen 2 단계표. 0단계 17/256, +1 은 1/8, +2 는 1/4, +3 이상은 85/256.
    /// 단계를 올리는 건 지금은 고급소기뿐이다(기술·특성 보정은 Phase 3·5).
    static func critThreshold(stage: Int) -> UInt64 {
        switch max(0, stage) {
        case 0: return 17
        case 1: return 32
        case 2: return 64
        default: return 85
        }
    }

    /// 얼음이 매턴 녹을 확률(%) — Gen 2 의 10% 는 평균 10턴이라 사실상 사망 선고다.
    /// Gen 3 값(20%)을 기본으로 두고 상수로 노출한다(계획 §7 리스크 표).
    static let thawChance = 20
    /// 마비로 행동이 막힐 확률(%) — Gen 2 는 25%(Gen 7 부터 50%).
    static let paralysisFailChance = 25
    /// 혼란일 때 자기를 때릴 확률(%).
    static let confusionSelfHitChance = 50
    /// 혼란 자멸의 위력 — 무속성 물리 40.
    static let confusionPower = 40

    /// 대전 규칙 버전 — 턴 순서나 데미지 계산을 바꿀 때마다 올린다. 두 피어가 결과를 주고받지 않고
    /// 각자 계산하므로, 규칙이 다른 앱끼리 붙으면 같은 배틀을 서로 다르게 본다.
    /// 1 = 우선도 도입, 2 = Gen 2 데미지 파이프라인(정수 난수·급소 ×2·`+2` 위치),
    /// 3 = 상태이상 6종 + 혼란(행동 가능 판정·화상 반감·마비 스피드·턴 끝 잔뎀),
    /// 4 = 위력 0(변화기) 데미지 0, 5 = 연결 끊김을 남은 HP 비율로 판정(무조건 몰수승 폐지),
    /// 6 = 개시 시점 판돈 에스크로(구버전은 이탈로 판돈을 회피하므로 총량이 어긋난다).
    static let rulesVersion = 6

    /// 연결이 끊긴 배틀의 승패 — 남은 HP **비율**이 앞선 쪽이 이기고, 같으면 `nil`(무효)이다.
    ///
    /// 예전엔 끊김을 무조건 `iWon: true` 로 접었다. 두 피어가 각자 자기 연결의 죽음을 보므로
    /// 네트워크가 한 번 끊기면 **양쪽이 동시에 승리**했고, 양쪽 다 `settleRankedBrawl(won: true)` 로
    /// 판돈 ★ 과 LP 를 받았다 — 어느 지갑에서도 빠져나가지 않고 총량만 늘었다. 그래서 지고 있으면
    /// 네트워크를 끊는 게 이득이었다.
    ///
    /// 두 피어는 같은 배틀 상태를 각자 계산해 들고 있으므로, 판정을 **상태에서** 뽑으면 두 쪽 결론이
    /// 자동으로 반대가 된다.
    ///
    /// ponytail: 단, 상태가 같다는 전제는 **턴 경계에서만** 성립한다. `resolveIfReady` 는 두 선택이
    /// 모이는 즉시 각자 해상하므로, 한쪽 `.move` 만 도착한 채 링크가 죽으면 한 피어는 턴 N 을 접고
    /// 다른 피어는 못 접어 상태가 한 턴 어긋난다 — 그 창에서는 양쪽이 모두 "내가 앞선다"를 볼 수
    /// 있고, 그러면 판돈이 두 지갑에 동시에 들어간다. 닫으려면 턴별 ack(또는 합의된 턴 인덱스 기준
    /// 판정)가 필요해 와이어 계약을 바꿔야 한다 — 미해결(defect-log 참조).
    ///
    /// 명시적 `.forfeit` 메시지를 받은 몰수승은 이 판정을 타지 않는다 — 그건 상대가 스스로 진 것이다.
    ///
    /// 비교는 교차곱이다. `Double` 나눗셈은 최대 HP 가 다른 두 종에서 반올림 방향이 갈릴 수 있고,
    /// 승패는 두 피어가 **같은 값**으로 봐야 하는 판정이다(`resolveRound` 의 tie-break 와 같은 이유).
    static func disconnectOutcome(me: BattleSide, opp: BattleSide) -> Bool? {
        let mine = me.hp * max(1, opp.stats.hp)
        let theirs = opp.hp * max(1, me.stats.hp)
        return mine == theirs ? nil : mine > theirs
    }

    /// 공격 1회의 결과. 1v1 과 멀티가 같은 값을 내야 하므로 계산은 `resolveAttack` 한 곳에만 둔다.
    struct AttackOutcome: Sendable {
        var missed: Bool
        var damage: Int
        /// 빗나갔으면 1 — 화면이 "효과가 굉장했다" 를 띄우지 않게 한다.
        var effectiveness: Double
        var isCritical: Bool
    }

    /// Gen 2 데미지 식의 앞부분 — 배율이 붙기 전의 뼈대. 기술 공격과 혼란 자멸이 같은 값을 쓴다.
    static func baseDamage(level: Int, power: Int, attack: Int, defense: Int) -> Int {
        (2 * level / 5 + 2) * power * attack / max(1, defense) / 50
    }

    /// 혼란 자멸 데미지 — 무속성 물리 위력 40. 급소도 난수도 타지 않으므로 **rng 를 소비하지 않는다**
    /// (분기마다 소비량이 달라지면 두 피어가 갈라진다). 물리라서 화상 반감은 그대로 받는다(Gen 2).
    static func confusionDamage(_ side: BattleSide) -> Int {
        let attack = side.status == .burn ? side.stats.atk / 2 : side.stats.atk
        return max(1, baseDamage(level: side.snapshot.level, power: confusionPower,
                                 attack: attack, defense: side.stats.def) + 2)
    }

    /// 공격 1회 해상. **rng 소비 순서가 프로토콜의 일부다** — 명중 → 급소 → 난수 폭 순서고,
    /// 빗나가면 뒤의 둘을 소비하지 않는다. 세 모드가 이 함수 하나만 쓴다(예전엔 복사돼 있었다).
    static func resolveAttack(attacker: BattleSide, defender: BattleSide,
                              move: MoveSpec, rng: inout SplitMix64) -> AttackOutcome {
        if let accuracy = move.accuracy, Int(rng.next() % 100) >= accuracy {
            return AttackOutcome(missed: true, damage: 0, effectiveness: 1, isCritical: false)
        }
        // 발버둥은 무속성(상성·STAB 미적용).
        let isStruggle = move.id == MoveSpec.struggleID
        // Phase 5(특성·지닌물건)의 타입 면역 특성(부유·타오르는불꽃·저수)이 들어올 자리다.
        // 상성 배율을 계산하는 지점이 여기 한 곳뿐이다. 지금은 코드를 넣지 않는다.
        let effectiveness = isStruggle ? 1.0
            : TypeChart.effectiveness(move.type, against: defender.snapshot.types)
        let isPhysical = move.damageClass == .physical
        // 화상은 **물리** 공격만 절반이다(Gen 2 는 공격 스탯을 반으로 깎는다). 특수기는 그대로다 —
        // 여기서 분류를 안 보면 화상이 공격 전체를 깎는 다른 게임이 된다.
        var attack = isPhysical ? attacker.stats.atk : attacker.stats.spa
        if isPhysical, attacker.status == .burn { attack /= 2 }
        let defense = isPhysical ? defender.stats.def : defender.stats.spd
        let isCritical = rng.next() % 256 < critThreshold(stage: move.critStage)
        // Gen 2 난수는 217~255 균등 **정수**를 뽑아 255 로 정수 나눗셈한다. 예전엔
        // `0.85 + (rng % 16)/100` 이라 0.01 간격 Double 이었다 — 두 피어가 각자 계산하는
        // 구조에서는 정수 연산이 유리하다(부동소수 오차가 끼어들 자리가 없다).
        let random = 217 + Int(rng.next() % 39)

        // Gen 2 의 계산 **순서** 그대로다. `+2` 가 급소 배율 뒤에 오고, STAB·상성은 그 뒤에 곱한다.
        // 예전 식은 `+2` 를 먼저 더한 뒤 급소 ×1.5 를 곱해 급소 데미지가 다르게 나왔다.
        // (배지·트레이너킥·날씨·기술보정은 §3.3 대로 안 가져온다.)
        var damage = baseDamage(level: attacker.snapshot.level, power: move.power,
                                attack: attack, defense: defense)
        damage = damage * (isCritical ? critMultiplier : 1) + 2
        if !isStruggle {
            if attacker.snapshot.types.contains(move.type) { damage = damage * 3 / 2 }   // STAB ×1.5
            damage = TypeChart.apply(damage, of: move.type, against: defender.snapshot.types)
        }
        damage = damage * random / 255
        // 위력 0(변화기)은 데미지가 없다. `max(1, …)` 만 두면 식의 `+2` 가 살아남아 상태기가 2 데미지를
        // 넣었다 — `learnedMoves` 는 변화기를 걸러내지 않으므로 실제로 밟히는 경로다.
        // rng 소비는 그대로다(명중 → 급소 → 난수) — 값만 바뀌므로 `rulesVersion` 으로 막는다.
        let dealt = (effectiveness == 0 || move.power <= 0) ? 0 : max(1, damage)
        return AttackOutcome(missed: false, damage: dealt,
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

// MARK: - 이벤트 스트림

/// 이벤트가 가리키는 쪽. 1v1 LAN·연습 배틀은 좌우 두 자리뿐이고(엔진 좌변이 항상 challenger),
/// 2~4인 방은 참가자가 여럿이라 UUID 로 가른다.
enum BattleActor: Codable, Sendable, Equatable, Hashable {
    case a, b
    case fighter(UUID)
}

/// 배틀에서 일어난 일 하나 — Showdown 의 `|move|`·`|-damage|`·`|-crit|` 처럼 **타입된** 이벤트다.
/// 로그·HP바·애니메이션은 전부 이 스트림의 렌더러다. 플래그 묶음(`missed`/`damage`/…)으로는
/// "화상으로 깎였다"·"마비로 못 움직였다" 를 표현할 수 없어 case 로 바꿨다.
/// 새 case 는 **그것을 내보내는 코드와 함께** 추가한다 — 아무도 밟지 않는 분기를 미리 두지 않는다.
enum BattleEvent: Codable, Sendable, Equatable {
    case turn(Int)
    case move(BattleActor, moveID: Int)
    case miss(BattleActor)
    case immune(BattleActor)
    case crit(BattleActor)
    case superEffective(BattleActor)
    case resisted(BattleActor)
    /// 실제로 깎인 양. 남은 HP 는 싣지 않는다 — 뷰는 `BattleSide.hp` 를 그대로 읽으므로 읽는 데가
    /// 없다. 재생 애니메이션(Phase 7)이 바를 보간할 때 필요해지면 그때 붙인다.
    case damage(BattleActor, amount: Int, cause: DamageCause)
    case faint(BattleActor)
    /// 상태가 붙었다 / 나았다 / 그 상태 때문에 이번 턴을 못 썼다.
    case status(BattleActor, Status)
    case cureStatus(BattleActor, Status)
    case cant(BattleActor, Status)
}

// MARK: - 네트워크 대전 턴 해상

extension BattleEngine {
    /// 상태를 실제로 붙인다. 붙지 않으면(면역·이미 다른 주 상태·기절) 빈 배열이다.
    ///
    /// **rng 는 카운터가 필요한 상태(잠듦·혼란)에서만 소비한다.** 붙을 수 있는지를 먼저 보고
    /// 그 뒤에만 뽑으므로, 두 피어가 같은 상태를 보고 있으면 소비량도 같다.
    @discardableResult
    static func inflict(_ status: Status, on side: inout BattleSide, actor: BattleActor,
                        rng: inout SplitMix64) -> [BattleEvent] {
        guard side.canBeAfflicted(by: status) else { return [] }
        switch status {
        case .confusion:
            side.confusionTurns = 2 + Int(rng.next() % 4)      // 2~5턴
        case .sleep:
            side.status = .sleep
            side.statusCounter = 2 + Int(rng.next() % 7)       // 카운터 2~8 → 행동불능 1~7턴
        case .toxic:
            side.status = .toxic
            side.statusCounter = 1                             // 1/16 부터 매턴 1/16 누적
        default:
            side.status = status
            side.statusCounter = 0
        }
        return [.status(actor, status)]
    }

    /// 턴 끝 잔뎀 — 화상·독은 최대 HP 의 1/8, 맹독은 n/16 으로 매턴 커진다.
    /// rng 를 쓰지 않으므로 호출 순서만 고정하면 두 피어가 같은 값을 본다.
    static func endOfTurnResidual(_ side: inout BattleSide, actor: BattleActor) -> [BattleEvent] {
        guard side.isAlive, let status = side.status else { return [] }
        let full = side.stats.hp
        let amount: Int
        let cause: DamageCause
        switch status {
        case .burn:
            amount = max(1, full / 8);  cause = .burn
        case .poison:
            amount = max(1, full / 8);  cause = .poison
        case .toxic:
            amount = max(1, full * side.statusCounter / 16); cause = .toxic
            side.statusCounter += 1
        case .paralysis, .sleep, .freeze, .confusion:
            return []
        }
        side.hp = max(0, side.hp - amount)
        var events: [BattleEvent] = [.damage(actor, amount: amount, cause: cause)]
        if !side.isAlive { events.append(.faint(actor)) }
        return events
    }

    /// 행동 가능 판정 — **잠듦 → 얼음 → 혼란 → 마비** 순서로 본다(Gen 2 의 검사 순서).
    /// 분기마다 rng 소비량이 달라지므로 이 순서가 곧 프로토콜이다. 상태는 스냅샷에 실려 오는 값이
    /// 아니라 배틀 중 파생값이라, `(스냅샷, seed, 행동열)` 만으로 두 피어가 같은 분기를 밟는다.
    private static func canAct(_ side: inout BattleSide, actor: BattleActor,
                               rng: inout SplitMix64, into events: inout [BattleEvent]) -> Bool {
        if side.status == .sleep {
            // 카운터를 먼저 줄이고 0 이면 그 턴에 바로 움직인다 — Gen 1 처럼 깬 턴을 버리지 않는다.
            side.statusCounter -= 1
            if side.statusCounter <= 0 {
                side.status = nil
                side.statusCounter = 0
                events.append(.cureStatus(actor, .sleep))
            } else {
                events.append(.cant(actor, .sleep))
                return false
            }
        }
        if side.status == .freeze {
            if Int(rng.next() % 100) < thawChance {
                side.status = nil
                events.append(.cureStatus(actor, .freeze))
            } else {
                events.append(.cant(actor, .freeze))
                return false
            }
        }
        if side.isConfused {
            let hurtsItself = Int(rng.next() % 100) < confusionSelfHitChance
            side.confusionTurns -= 1                 // 남은 턴 수만큼 판정을 굴린다(2~5회)
            // 쓰러진 뒤에는 "혼란이 풀렸다" 를 쓰지 않는다 — 기절 다음 줄로 붙어 읽히기만 한다.
            defer { if side.confusionTurns == 0, side.isAlive { events.append(.cureStatus(actor, .confusion)) } }
            if hurtsItself {
                events.append(.cant(actor, .confusion))
                let damage = confusionDamage(side)
                side.hp = max(0, side.hp - damage)
                events.append(.damage(actor, amount: damage, cause: .confusion))
                if !side.isAlive { events.append(.faint(actor)) }
                return false
            }
        }
        if side.status == .paralysis, Int(rng.next() % 100) < paralysisFailChance {
            events.append(.cant(actor, .paralysis))
            return false
        }
        return true
    }

    /// 공격 1회를 해상해 양쪽 상태를 갱신하고, 그 결과를 이벤트로 남긴다.
    /// 1v1·연습·멀티가 전부 이 함수를 지나므로 **세 모드의 이벤트 어휘가 같다** — 데미지 함수를
    /// 하나로 모은 것(#46)과 배틀 상태를 `BattleSide` 로 모은 것(Phase 0)과 같은 이유다.
    /// 행동 가능 판정도 여기 있어야 세 모드가 상태이상을 같은 규칙으로 받는다.
    ///
    /// ponytail: 못 움직인 턴에도 PP 는 이미 호출부에서 깎인 뒤다(본가는 안 깎는다). 되돌리려면
    ///           기술 선택 자체를 엔진 안으로 옮겨야 하는데, 그건 교체(Phase 4)와 같이 할 일이다.
    ///           양쪽 피어가 똑같이 깎으므로 desync 는 없다.
    static func applyAttack(attacker: inout BattleSide, defender: inout BattleSide,
                            attackerActor: BattleActor, defenderActor: BattleActor,
                            move: MoveSpec, rng: inout SplitMix64) -> [BattleEvent] {
        var events: [BattleEvent] = []
        // 못 움직이면 `.move` 자체가 나가지 않는다 — Showdown 도 `|move|` 대신 `|cant|` 를 보낸다.
        guard canAct(&attacker, actor: attackerActor, rng: &rng, into: &events) else { return events }
        events.append(.move(attackerActor, moveID: move.id))
        let outcome = resolveAttack(attacker: attacker, defender: defender, move: move, rng: &rng)
        if outcome.missed { return events + [.miss(attackerActor)] }
        if outcome.effectiveness == 0 { return events + [.immune(defenderActor)] }
        // 급소·상성 문구가 데미지보다 먼저 온다(Showdown 순서) — 재생할 때 "급소!" 뒤에 HP 가 줄어든다.
        if outcome.isCritical { events.append(.crit(defenderActor)) }
        if outcome.effectiveness > 1 { events.append(.superEffective(defenderActor)) }
        else if outcome.effectiveness < 1 { events.append(.resisted(defenderActor)) }
        // 데미지 0(변화기)은 `.damage` 를 내보내지 않는다 — "0 데미지" 줄은 맞았는데 안 깎인 것처럼 읽힌다.
        if outcome.damage > 0 {
            defender.hp = max(0, defender.hp - outcome.damage)
            events.append(.damage(defenderActor, amount: outcome.damage, cause: .move))
            if !defender.isAlive { return events + [.faint(defenderActor)] }
        }
        // 2차효과는 데미지 뒤다 — 쓰러진 상대에게는 붙지 않는다.
        return events + applySecondaryEffect(of: move, to: &defender, actor: defenderActor, rng: &rng)
    }

    /// 기술의 2차효과(상태 부여). 붙을 수 있는지를 **확률 판정보다 먼저** 보므로, 이미 다른 상태가
    /// 걸려 있거나 면역인 상대에게는 rng 를 쓰지 않는다 — 두 피어의 소비량이 같아야 한다.
    private static func applySecondaryEffect(of move: MoveSpec, to side: inout BattleSide,
                                             actor: BattleActor, rng: inout SplitMix64) -> [BattleEvent] {
        guard let status = move.inflictedStatus, side.canBeAfflicted(by: status) else { return [] }
        guard Int(rng.next() % 100) < move.ailmentChancePercent else { return [] }
        return inflict(status, on: &side, actor: actor, rng: &rng)
    }

    /// 양쪽 기술 선택이 모이면 한 턴 해상. 순수·결정적 — 같은 rng 상태·입력이면 두 피어가 같은 결과를
    /// 각자 계산한다(결과 자체는 네트워크로 보내지 않는다 → 변조 여지 축소).
    /// rng 소비 순서가 프로토콜의 일부다 — 브랜치를 바꾸면 두 피어 결과가 갈라진다.
    static func resolveTurn(a: inout BattleSide, b: inout BattleSide,
                            moveA: MoveSpec, moveB: MoveSpec, turn: Int,
                            rng: inout SplitMix64) -> [BattleEvent] {
        var events: [BattleEvent] = [.turn(turn)]
        // 마비가 스피드를 깎으므로 순서 계산이 상태를 봐야 한다 — `stats.spe` 를 그대로 넘기면
        // 마비가 스탯 표시에만 남고 선공은 그대로다.
        let aIsFirst = firstMoverIsA(priorityA: moveA.turnPriority, priorityB: moveB.turnPriority,
                                     speedA: a.effectiveSpeed, speedB: b.effectiveSpeed, rng: &rng)
        for attackerIsA in aIsFirst ? [true, false] : [false, true] {
            guard a.isAlive && b.isAlive else { break }   // 선공에 기절하면 후공 없음
            let move = attackerIsA ? moveA : moveB
            events += attackerIsA
                ? applyAttack(attacker: &a, defender: &b, attackerActor: .a, defenderActor: .b,
                              move: move, rng: &rng)
                : applyAttack(attacker: &b, defender: &a, attackerActor: .b, defenderActor: .a,
                              move: move, rng: &rng)
        }
        // 잔뎀은 두 공격이 **모두 끝난 뒤**다. 앞에 두면 그 턴의 데미지 계산과 기절 시점이 달라진다.
        // 좌변부터 고정 순서 — 순서가 흔들리면 동시 기절 때 두 피어의 승패가 갈린다.
        events += endOfTurnResidual(&a, actor: .a)
        events += endOfTurnResidual(&b, actor: .b)
        return events
    }
}
