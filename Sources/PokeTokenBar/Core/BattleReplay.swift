import Foundation

/// 재생 속도 — Showdown 에도 있는 설정이다. **끄기가 필수인 이유**는 저전력·접근성이다:
/// 움직임에 민감한 사용자와 배터리로 도는 기기 모두에게 "안 움직이는 화면" 이 있어야 한다.
enum ReplaySpeed: String, Codable, Sendable, CaseIterable {
    case normal, fast, off

    /// 기본 지속시간에 곱하는 배수. 0 이면 기다림이 없다(결과가 즉시 보인다).
    var scale: Double {
        switch self {
        case .normal: return 1
        case .fast:   return 0.45
        case .off:    return 0
        }
    }
}

/// 이벤트 하나를 화면에 보여 주는 한 스텝.
struct ReplayStep: Equatable, Sendable {
    let event: BattleEvent
    /// 이 스텝을 보여 준 뒤 다음 스텝까지 기다리는 시간.
    let duration: TimeInterval
    /// 이 스텝까지 반영한 **표시** HP. 스트림 끝의 값은 엔진이 계산한 HP 와 같다 —
    /// 어긋나면 바가 엉뚱한 데서 멈췄다가 다음 턴에 튀면서 보정된다.
    let hp: [BattleActor: Int]
}

/// 재생 중 화면에 얹히는 것 — 필드가 이 값만 보고 흔들림·문구를 그린다.
/// 재생이 없으면 `.idle` 이라 예전과 같은 화면이다(연출이 꺼져도 화면이 달라지지 않는다).
struct ReplayOverlay: Equatable, Sendable {
    /// 재생 중인가 — 입력 잠금의 근거다.
    var isPlaying = false
    /// 지금 맞은 쪽 — 이 스프라이트만 흔들리고 번쩍인다.
    var hit: BattleActor?
    /// 지금 떠 있는 팝의 **원인 이벤트**. 문구가 아니라 이벤트를 들고 있는 이유는 언어다 —
    /// 뷰가 자기 `L` 로 푼다(`BattleReplay.popup`).
    var popped: BattleEvent?

    static let idle = ReplayOverlay()
}

/// 이벤트 스트림을 재생 큐로 바꾸는 순수 계층 (계획 §6 Phase 7).
///
/// 지금까지는 턴이 해상되면 HP 가 **즉시** 최종값으로 튀어 무엇이 일어났는지 볼 시간이 없었다.
/// 애니메이션 자체는 뷰가 그리지만, 큐(무엇을 · 얼마나 · 그때 HP 는 얼마인가)는 여기 순수 함수로
/// 두어야 테스트가 붙는다 — UI 결함은 컴파일과 단위 테스트를 통과한다(defect-log).
enum BattleReplay {
    /// 한 배치(대개 한 턴)의 재생 상한(초). 턴 타이머가 30초라 재생이 그 시간을 잡아먹으면 안 된다.
    /// 이벤트가 많은 턴(혼란 자멸 + 양쪽 잔뎀 + 기절)은 이 상한에 맞춰 비율대로 줄어든다.
    static let budget: TimeInterval = 2.4

    /// 이벤트 종류별 기본 지속시간 — 보통 속도 기준이다. HP바 보간이 가장 길고(값이 실제로
    /// 움직이는 유일한 이벤트다), 문구만 뜨는 것들은 짧다.
    static func duration(of event: BattleEvent) -> TimeInterval {
        switch event {
        case .turn:                                             return 0.15
        case .move:                                             return 0.35
        case .damage:                                           return 0.45
        case .faint:                                            return 0.60
        case .crit, .superEffective, .resisted, .miss, .immune: return 0.30
        case .status, .cureStatus, .cant:                       return 0.40
        }
    }

    static func totalDuration(_ steps: [ReplayStep]) -> TimeInterval {
        steps.reduce(0) { $0 + $1.duration }
    }

    /// 스트림을 큐로. **이벤트 하나가 스텝 하나다** — 접거나 건너뛰면 로그를 재생 진행도만큼
    /// 잘라 보여 줄 수 없다(로그도 이벤트 순서로 접힌다).
    ///
    /// `hp` 는 이 배치가 시작할 때의 표시 HP다. 각 스텝의 HP 는 거기서부터 `.damage` 를 순서대로
    /// 적용해 만든다 — 최종값에서 거꾸로 빼면 오버킬(남은 HP 보다 큰 데미지)에서 엔진과 갈라진다.
    static func steps(_ events: [BattleEvent], from hp: [BattleActor: Int],
                      speed: ReplaySpeed) -> [ReplayStep] {
        let base = events.map(duration(of:))
        let total = base.reduce(0, +) * speed.scale
        // 예산 안에 드는 턴은 그대로 둔다 — 전부 압축하면 데미지 두 방이 같은 프레임에 겹친다.
        let scale = total > budget ? speed.scale * budget / total : speed.scale
        var running = hp
        return zip(events, base).map { event, seconds in
            // 엔진과 같은 자리에서 자른다(`side.hp = max(0, …)`). 모르는 actor 는 만들지 않는다 —
            // 없는 쪽의 바를 0 으로 그리는 것보다 안 그리는 쪽이 낫다.
            if case .damage(let actor, let amount, _) = event, let current = running[actor] {
                running[actor] = max(0, current - amount)
            }
            return ReplayStep(event: event, duration: seconds * scale, hp: running)
        }
    }

    /// 저전력 모드면 재생하지 않는다 — `FloatingPetController.shouldAnimate(lowPower:)` 와 같은 가드다.
    /// 설정값 자체는 바꾸지 않는다: 저전력이 풀리면 사용자가 고른 속도로 돌아와야 한다.
    static func effectiveSpeed(_ setting: ReplaySpeed, lowPower: Bool) -> ReplaySpeed {
        lowPower ? .off : setting
    }

    /// 이번 턴 입력을 받아도 되는가. 재생이 끝나기 전에 다음 기술을 고르면 무엇이 일어났는지 보지
    /// 못한 채 턴이 넘어간다 — 계획 Phase 7 이 지목한 "체감되는 조잡함" 이 이것이다.
    static func acceptsInput(isWaitingForOpponent: Bool, isReplaying: Bool) -> Bool {
        !isWaitingForOpponent && !isReplaying
    }

    /// 재생 중 화면에 한 번 뜨는 문구. 로그는 재생이 그 줄에 닿아야 나오므로, 이 팝이 없으면
    /// 급소가 화면 어디에도 안 보인 채 HP 만 크게 깎인다.
    /// 여기 없는 이벤트는 팝이 없다 — 전부 팝으로 만들면 화면이 문구로 덮여 정작 급소가 묻힌다.
    static func popup(for event: BattleEvent, l: L) -> String? {
        switch event {
        case .crit:           return l.battleCritical
        case .superEffective: return l.battleSuperEffective
        case .resisted:       return l.battleNotVeryEffective
        case .miss:           return l.battleMissed
        case .immune:         return l.battleNoEffect
        default:              return nil
        }
    }

    /// 이 이벤트로 **맞은** 쪽 — shake·flash 를 거는 대상이다. 때린 쪽에 걸면 누가 맞았는지
    /// 반대로 읽힌다. `.damage` 는 원인(기술·화상·자멸)과 무관하게 맞은 쪽을 가리킨다.
    static func struck(by event: BattleEvent) -> BattleActor? {
        guard case .damage(let actor, _, _) = event else { return nil }
        return actor
    }
}
