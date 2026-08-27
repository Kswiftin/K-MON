import Foundation

/// 특성 — **엔진이 실제로 적용하는 것만** case 로 둔다. 타입·상태 면역과 결정론적인
/// 위력/스탯/데미지 보정까지 지원한다. 아직 날씨·필드·접촉 판정이나 추가 rng가 필요한 특성은 넣지 않는다.
///
/// 모르는 슬러그는 `nil` 이고, `nil` 은 특성이 없는 것과 **완전히 같게** 동작한다(ailment 14종과
/// 같은 규칙 — 조용히 삼키지 않되 배틀은 바꾸지 않는다).
/// 와이어에 실리는 건 **슬러그 문자열**(`BattleSnapshot.ability`)이라 이 타입은 `Codable` 이 아니다.
/// 여기에 case 를 늘려도 스냅샷 계약은 그대로다.
enum BattleAbility: String, Sendable {
    case levitate
    case flashFire = "flash-fire"
    case voltAbsorb = "volt-absorb"
    case waterAbsorb = "water-absorb"
    case limber
    case insomnia
    case vitalSpirit = "vital-spirit"
    case immunity
    case waterVeil = "water-veil"
    case waterBubble = "water-bubble"
    case magmaArmor = "magma-armor"
    case ownTempo = "own-tempo"
    case wonderGuard = "wonder-guard"
    case thickFat = "thick-fat"
    case heatproof
    case filter
    case solidRock = "solid-rock"
    case technician
    case hugePower = "huge-power"
    case purePower = "pure-power"
    case guts
    case marvelScale = "marvel-scale"

    /// 0배로 접는 기술 타입 — 특성 하나가 막는 타입은 **하나뿐**이다. 한 표가 전 타입을 막으면
    /// 부유가 모든 기술을 무효로 만든다.
    ///
    /// ponytail: 타오르는불꽃의 불꽃기 강화는 넣지 않는다 — 면역만 들이는 단계다.
    ///           강화가 필요해지면 `resolveSingleHit` 의 위력 자리에 붙인다.
    var immuneMoveType: PokemonType? {
        switch self {
        case .levitate:    return .ground
        case .flashFire:   return .fire
        case .voltAbsorb:  return .electric
        case .waterAbsorb: return .water
        default:           return nil
        }
    }

    /// 무효로 만들면서 최대 HP 의 1/4 을 회복하는가. 무효 전부를 회복으로 만들면 부유가 회복 특성이 된다.
    var absorbsIntoHP: Bool { self == .voltAbsorb || self == .waterAbsorb }

    /// 이 타입의 기술을 흡수하는가 — 무효 판정과 회복 판정이 **같은 값**을 봐야 한다.
    func absorbs(_ type: PokemonType) -> Bool { absorbsIntoHP && immuneMoveType == type }

    /// 공격기 위력 보정. 테크니션은 실제 계산된 위력(가변 위력 포함)이 60 이하일 때 1.5배다.
    func adjustedPower(_ power: Int, move: MoveSpec) -> Int {
        self == .technician && move.damageClass != .status && (1...60).contains(power)
            ? power * 3 / 2 : power
    }

    /// 공격 스탯 보정. 천하장사·순수한힘은 물리 공격 2배, 근성은 상태이상 중 물리 공격 1.5배다.
    func adjustedAttack(_ attack: Int, isPhysical: Bool, status: Status?) -> Int {
        guard isPhysical else { return attack }
        switch self {
        case .hugePower, .purePower: return attack * 2
        case .guts where status != nil: return attack * 3 / 2
        default: return attack
        }
    }

    /// 방어 스탯 보정. 이상한비늘은 상태이상 중 물리 방어가 1.5배다.
    func adjustedDefense(_ defense: Int, isPhysical: Bool, status: Status?) -> Int {
        self == .marvelScale && isPhysical && status != nil ? defense * 3 / 2 : defense
    }

    /// 최종 데미지 보정. 두꺼운지방·내열은 해당 타입을 반감하고 필터·하드록은 약점 데미지를 3/4로 한다.
    func adjustedDamage(_ damage: Int, moveType: PokemonType, effectiveness: Double) -> Int {
        switch self {
        case .thickFat where moveType == .fire || moveType == .ice: return damage / 2
        case .heatproof where moveType == .fire: return damage / 2
        case .filter where effectiveness > 1, .solidRock where effectiveness > 1:
            return damage * 3 / 4
        default: return damage
        }
    }

    /// 이 상태를 막는가. 기술 타입이 아니라 **걸리는 상태**로 판정한다 — `canBeAfflicted` 와 같은
    /// 기준이라(강철의 독 면역이 이미 거기 있다) 상성표를 안 타는 변화기도 같이 막힌다.
    func blocks(_ status: Status) -> Bool {
        switch self {
        case .limber:                  return status == .paralysis
        case .insomnia, .vitalSpirit:  return status == .sleep
        case .immunity:                return status == .poison || status == .toxic
        case .waterVeil, .waterBubble: return status == .burn
        case .magmaArmor:              return status == .freeze
        case .ownTempo:                return status == .confusion
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
