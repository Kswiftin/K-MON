import Foundation

/// 특성 — **엔진이 실제로 적용하는 것만** case 로 둔다(#24 Phase 5 / PR 9).
///
/// 1단계는 면역뿐이다. 면역은 표 조회라 rng 를 한 번도 안 쓰므로 두 피어의 소비 순서가 흔들릴 수
/// 없다 — 특성 축에서 desync 위험이 가장 낮은 지점이다. 스탯·데미지 보정과 접촉 특성(rng 소비가
/// 늘어나는 유일한 부류)은 다음 단계로 미룬다.
///
/// 모르는 슬러그는 `nil` 이고, `nil` 은 특성이 없는 것과 **완전히 같게** 동작한다 — ailment 14종과
/// 같은 규칙이다(조용히 삼키지 않되 배틀은 바꾸지 않는다).
/// 와이어에 실리는 건 **슬러그 문자열**(`BattleSnapshot.ability`)이라 이 타입은 `Codable` 이 아니다 —
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
    case magmaArmor = "magma-armor"
    case ownTempo = "own-tempo"

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

    /// 이 상태를 막는가. 기술 타입이 아니라 **걸리는 상태**로 판정한다 — `canBeAfflicted` 와 같은
    /// 기준이고(강철의 독 면역이 이미 거기 있다), 그래서 상성표를 안 타는 상태기도 같이 막힌다.
    func blocks(_ status: Status) -> Bool {
        switch self {
        case .limber:                  return status == .paralysis
        case .insomnia, .vitalSpirit:  return status == .sleep
        case .immunity:                return status == .poison || status == .toxic
        case .waterVeil:               return status == .burn
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
