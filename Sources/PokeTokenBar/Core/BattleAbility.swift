import Foundation

enum BattleWeather: String, Sendable { case clear, rain, sun, sand, hail }

/// 특성 — **엔진이 실제로 적용하는 것만** case 로 둔다. 타입·상태 면역과 결정론적인
/// 위력/스탯/데미지 보정까지 지원한다. 아직 날씨·필드·접촉 판정이나 추가 rng가 필요한 특성은 넣지 않는다.
///
/// 모르는 슬러그는 `nil` 이고, `nil` 은 특성이 없는 것과 **완전히 같게** 동작한다(ailment 14종과
/// 같은 규칙 — 조용히 삼키지 않되 배틀은 바꾸지 않는다).
/// 와이어에 실리는 건 **슬러그 문자열**(`BattleSnapshot.ability`)이라 이 타입은 `Codable` 이 아니다.
/// 여기에 case 를 늘려도 스냅샷 계약은 그대로다.
struct BattleAbility: RawRepresentable, Sendable, Equatable, Hashable {
    let rawValue: String

    init?(rawValue: String) {
        guard Self.generationFiveSlugs.contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    private init(_ rawValue: String) { self.rawValue = rawValue }

    // 기존 호출부가 `.guts` 같은 타입 안전 비교를 계속 쓰게 하는 대표 상수들.
    static let levitate = Self("levitate"), flashFire = Self("flash-fire")
    static let voltAbsorb = Self("volt-absorb"), waterAbsorb = Self("water-absorb")
    static let limber = Self("limber"), insomnia = Self("insomnia"), vitalSpirit = Self("vital-spirit")
    static let immunity = Self("immunity"), waterVeil = Self("water-veil"), waterBubble = Self("water-bubble")
    static let magmaArmor = Self("magma-armor"), ownTempo = Self("own-tempo")
    static let wonderGuard = Self("wonder-guard"), thickFat = Self("thick-fat"), heatproof = Self("heatproof")
    static let filter = Self("filter"), solidRock = Self("solid-rock"), technician = Self("technician")
    static let hugePower = Self("huge-power"), purePower = Self("pure-power"), guts = Self("guts")
    static let marvelScale = Self("marvel-scale")

    /// 전국도감 1~5세대에서 등장한 특성(PokéAPI ability id 1...164). 전투 밖 전용 특성도
    /// 목록에는 포함한다. 그런 특성은 배틀에서 원래 효과가 없지만 "미지원 특성"으로 오인하지 않는다.
    static let generationFiveSlugs: Set<String> = [
        "stench", "drizzle", "speed-boost", "battle-armor", "sturdy", "damp", "limber",
        "sand-veil", "static", "volt-absorb", "water-absorb", "oblivious", "cloud-nine",
        "compound-eyes", "insomnia", "color-change", "immunity", "flash-fire", "shield-dust",
        "own-tempo", "suction-cups", "intimidate", "shadow-tag", "rough-skin", "wonder-guard",
        "levitate", "effect-spore", "synchronize", "clear-body", "natural-cure", "lightning-rod",
        "serene-grace", "swift-swim", "chlorophyll", "illuminate", "trace", "huge-power",
        "poison-point", "inner-focus", "magma-armor", "water-veil", "magnet-pull", "soundproof",
        "rain-dish", "sand-stream", "pressure", "thick-fat", "early-bird", "flame-body", "run-away",
        "keen-eye", "hyper-cutter", "pickup", "truant", "hustle", "cute-charm", "plus", "minus",
        "forecast", "sticky-hold", "shed-skin", "guts", "marvel-scale", "liquid-ooze", "overgrow",
        "blaze", "torrent", "swarm", "rock-head", "drought", "arena-trap", "vital-spirit",
        "white-smoke", "pure-power", "shell-armor", "air-lock", "tangled-feet", "motor-drive",
        "rivalry", "steadfast", "snow-cloak", "gluttony", "anger-point", "unburden", "heatproof",
        "simple", "dry-skin", "download", "iron-fist", "poison-heal", "adaptability", "skill-link",
        "hydration", "solar-power", "quick-feet", "normalize", "sniper", "magic-guard", "no-guard",
        "stall", "technician", "leaf-guard", "klutz", "mold-breaker", "super-luck", "aftermath",
        "anticipation", "forewarn", "unaware", "tinted-lens", "filter", "slow-start", "scrappy",
        "storm-drain", "ice-body", "solid-rock", "snow-warning", "honey-gather", "frisk", "reckless",
        "multitype", "flower-gift", "bad-dreams", "pickpocket", "sheer-force", "contrary", "unnerve",
        "defiant", "defeatist", "cursed-body", "healer", "friend-guard", "weak-armor", "heavy-metal",
        "light-metal", "multiscale", "toxic-boost", "flare-boost", "harvest", "telepathy", "moody",
        "overcoat", "poison-touch", "regenerator", "big-pecks", "sand-rush", "wonder-skin", "analytic",
        "illusion", "imposter", "infiltrator", "mummy", "moxie", "justified", "rattled",
        "magic-bounce", "sap-sipper", "prankster", "sand-force", "iron-barbs", "zen-mode",
        "victory-star", "turboblaze", "teravolt"
    ]

    /// 0배로 접는 기술 타입 — 특성 하나가 막는 타입은 **하나뿐**이다. 한 표가 전 타입을 막으면
    /// 부유가 모든 기술을 무효로 만든다.
    ///
    /// ponytail: 타오르는불꽃의 불꽃기 강화는 넣지 않는다 — 면역만 들이는 단계다.
    ///           강화가 필요해지면 `resolveSingleHit` 의 위력 자리에 붙인다.
    var immuneMoveType: PokemonType? {
        switch rawValue {
        case "levitate":       return .ground
        case "flash-fire":     return .fire
        case "volt-absorb", "lightning-rod", "motor-drive": return .electric
        case "water-absorb", "storm-drain", "dry-skin": return .water
        case "sap-sipper":     return .grass
        default:           return nil
        }
    }

    /// 무효로 만들면서 최대 HP 의 1/4 을 회복하는가. 무효 전부를 회복으로 만들면 부유가 회복 특성이 된다.
    var absorbsIntoHP: Bool { self == .voltAbsorb || self == .waterAbsorb || rawValue == "dry-skin" }

    /// 이 타입의 기술을 흡수하는가 — 무효 판정과 회복 판정이 **같은 값**을 봐야 한다.
    func absorbs(_ type: PokemonType) -> Bool { absorbsIntoHP && immuneMoveType == type }

    var ignoresDefensiveAbilities: Bool { ["mold-breaker", "turboblaze", "teravolt"].contains(rawValue) }
    var preventsCriticalHits: Bool { rawValue == "battle-armor" || rawValue == "shell-armor" }
    var blocksSecondaryEffects: Bool { rawValue == "shield-dust" }
    var blocksFlinch: Bool { rawValue == "inner-focus" }
    var ignoresRecoil: Bool { rawValue == "rock-head" }
    var ignoresResidualDamage: Bool { rawValue == "magic-guard" }
    var forcesLastMove: Bool { rawValue == "stall" }
    var priorityBonusForStatus: Int { rawValue == "prankster" ? 1 : 0 }

    var summonedWeather: BattleWeather? {
        switch rawValue {
        case "drizzle": .rain
        case "drought": .sun
        case "sand-stream": .sand
        case "snow-warning": .hail
        default: nil
        }
    }

    func adjustedAccuracy(_ accuracy: Int, move: MoveSpec, weather: BattleWeather,
                          confused: Bool, defending: Bool) -> Int {
        var value = accuracy
        if !defending {
            if rawValue == "compound-eyes" { value = value * 13 / 10 }
            if rawValue == "hustle", move.damageClass == .physical { value = value * 4 / 5 }
            if rawValue == "victory-star" { value = value * 11 / 10 }
        } else {
            if rawValue == "sand-veil", weather == .sand { value = value * 4 / 5 }
            if rawValue == "snow-cloak", weather == .hail { value = value * 4 / 5 }
            if rawValue == "tangled-feet", confused { value /= 2 }
            if rawValue == "wonder-skin", move.damageClass == .status { value = min(value, 50) }
        }
        return value
    }

    /// 공격기 위력 보정. 테크니션은 실제 계산된 위력(가변 위력 포함)이 60 이하일 때 1.5배다.
    func adjustedPower(_ power: Int, move: MoveSpec) -> Int {
        var value = power
        if self == .technician, move.damageClass != .status, (1...60).contains(value) { value = value * 3 / 2 }
        if rawValue == "iron-fist", move.isPunch { value = value * 6 / 5 }
        if rawValue == "reckless", move.drainPercent < 0 { value = value * 6 / 5 }
        if rawValue == "water-bubble", move.type == .water { value *= 2 }
        return value
    }

    /// 공격 스탯 보정. 천하장사·순수한힘은 물리 공격 2배, 근성은 상태이상 중 물리 공격 1.5배다.
    func adjustedAttack(_ attack: Int, isPhysical: Bool, status: Status?) -> Int {
        guard isPhysical else { return attack }
        switch rawValue {
        case "huge-power", "pure-power": return attack * 2
        case "guts" where status != nil: return attack * 3 / 2
        default: return attack
        }
    }

    /// 방어 스탯 보정. 이상한비늘은 상태이상 중 물리 방어가 1.5배다.
    func adjustedDefense(_ defense: Int, isPhysical: Bool, status: Status?) -> Int {
        self == .marvelScale && isPhysical && status != nil ? defense * 3 / 2 : defense
    }

    /// 최종 데미지 보정. 두꺼운지방·내열은 해당 타입을 반감하고 필터·하드록은 약점 데미지를 3/4로 한다.
    func adjustedDamage(_ damage: Int, moveType: PokemonType, effectiveness: Double,
                        isAtFullHP: Bool = false) -> Int {
        switch rawValue {
        case "thick-fat" where moveType == .fire || moveType == .ice: return damage / 2
        case "heatproof" where moveType == .fire: return damage / 2
        case "water-bubble" where moveType == .fire: return damage / 2
        case "dry-skin" where moveType == .fire: return damage * 5 / 4
        case "filter" where effectiveness > 1, "solid-rock" where effectiveness > 1:
            return damage * 3 / 4
        case "multiscale" where isAtFullHP: return damage / 2
        default: return damage
        }
    }

    /// 이 상태를 막는가. 기술 타입이 아니라 **걸리는 상태**로 판정한다 — `canBeAfflicted` 와 같은
    /// 기준이라(강철의 독 면역이 이미 거기 있다) 상성표를 안 타는 변화기도 같이 막힌다.
    func blocks(_ status: Status) -> Bool {
        switch rawValue {
        case "limber":                  return status == .paralysis
        case "insomnia", "vital-spirit": return status == .sleep
        case "immunity":                return status == .poison || status == .toxic
        case "water-veil", "water-bubble": return status == .burn
        case "magma-armor":             return status == .freeze
        case "own-tempo":               return status == .confusion
        case "inner-focus":             return status == .flinch
        default:                       return false
        }
    }

    /// 슬러그 → 특성. 모르는 이름은 `nil` 이고 배틀을 바꾸지 않는다.
    ///
    /// **로그는 여기서 남기지 않는다** — 이 함수는 턴마다 불린다. 미구현 슬러그 한 줄은
    /// `PokeAPIClient.battleProfile`(종당 한 번, 캐시된다) 에서 남긴다. ailment 와 같은 자리다.
    static func resolve(_ slug: String?) -> BattleAbility? {
        slug.flatMap(BattleAbility.init(rawValue:))
    }

    /// 와이어 상한(**UTF-8 바이트**) — 특성은 상대가 보내오는 **문자열**이라 숫자와 같은 경계가
    /// 필요하다. 도감 최장 슬러그(`as-one-shadow-rider`, 19바이트)의 두 배로 잡는다.
    static let maxSlugLength = 40
}
