import Foundation

/// 재생 속도 — Showdown 에도 있는 설정이다. **끄기가 필수인 이유**는 저전력·접근성이다:
/// 움직임에 민감한 사용자와 배터리로 도는 기기 모두에게 "안 움직이는 화면" 이 있어야 한다.
enum ReplaySpeed: String, Sendable, CaseIterable {
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

/// 재생이 도달한 **한쪽의** 표시 상태 — 엔진의 최종 상태와 다를 수 있다는 것이 이 타입의 존재
/// 이유다. 활성 칸까지 들고 있어야 기절·교체 턴에 새로 나온 개체를 이전 개체 HP 로 그리지 않는다.
///
/// 팀 전체를 드는 이유는 둘이다 — 교체 스트립의 미니 바도 같은 진행도를 읽어야 하고,
/// `.sendOut` 이 팀 인덱스만 실으므로 들어오는 개체의 상태를 여기서 읽어야 한다. 벤치에 있던
/// 개체는 그 턴에 바뀌지 않으므로 **지난 배치 끝의 값이 곧 출전 시점의 값**이다(엔진의 최종 팀에서
/// 읽으면 새로 나온 개체가 그 턴에 맞은 데미지까지 이미 반영돼 결과가 샌다).
struct ReplaySide: Equatable, Sendable {
    var team: [BattleSide]
    var active: Int

    /// 지금 필드에 서 있는 개체 — 활성 칸이 범위 밖이면 `nil` 이다. 0번으로 대신하면 엉뚱한 개체의
    /// 바를 그린다(`.sendOut` 이 범위를 검사하고 넘어가므로 정상 경로에선 언제나 값이 있다).
    var side: BattleSide? { team.indices.contains(active) ? team[active] : nil }
}

/// 이벤트 하나를 화면에 보여 주는 한 스텝.
struct ReplayStep: Equatable, Sendable {
    let event: BattleEvent
    /// 이 스텝을 보여 준 뒤 다음 스텝까지 기다리는 시간.
    let duration: TimeInterval
    /// 이 스텝까지 반영한 **표시** 상태. 움직이는 건 HP 와 활성 칸 둘뿐이다 — 상태이상·PP 는 여기서
    /// 재구성하지 않는다(엔진 규칙이 두 벌이 되고, `statusCounter` 처럼 이벤트만 보고는 알 수 없는
    /// 값이 있다). 대신 **배치가 끝날 때 엔진 값으로 한 번에 맞춘다**: 그래서 화상 배지·줄어든 PP 가
    /// 재생 첫 프레임부터 결과를 알려 주지 않는다. 스트림 끝의 HP 는 엔진이 계산한 HP 와 같다 —
    /// 어긋나면 바가 엉뚱한 데서 멈췄다가 다음 턴에 튀면서 보정된다.
    let sides: [BattleActor: ReplaySide]
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
        // 교체·자동 출전은 한 박자 — 새 개체가 나오는 걸 보고 나서 다음 일이 일어나야 한다.
        case .sendOut:                                          return 0.40
        case .crit, .superEffective, .resisted, .miss, .immune: return 0.30
        case .status, .cureStatus, .cant:                       return 0.40
        // 랭크는 **로그 줄만** 늘린다 — 팝 문구가 없고(`popupKey` 가 nil), 랭크 배지는 배치 끝에
        // 엔진 값으로 스냅하므로 재생 중 화면이 바뀌지 않는다. 상태이상과 같은 0.40 을 주면
        // 다축 한 방(고대의힘 부류, 다섯 축)이 2.0초로 예산을 혼자 채워 같은 턴의 HP 보간과
        // 급소 문구가 비례 압축된다.
        case .boost:                                            return 0.20
        }
    }

    static func totalDuration(_ steps: [ReplayStep]) -> TimeInterval {
        steps.reduce(0) { $0 + $1.duration }
    }

    /// 스트림을 큐로. **이벤트 하나가 스텝 하나다** — 접거나 건너뛰면 로그를 재생 진행도만큼
    /// 잘라 보여 줄 수 없다(로그도 이벤트 순서로 접힌다).
    ///
    /// `sides` 는 이 배치가 시작할 때의 표시 상태다. 각 스텝은 거기서부터 이벤트를 순서대로 적용해
    /// 만든다 — 최종값에서 거꾸로 빼면 오버킬(남은 HP 보다 큰 데미지)에서 엔진과 갈라진다.
    static func steps(_ events: [BattleEvent], from sides: [BattleActor: ReplaySide],
                      speed: ReplaySpeed) -> [ReplayStep] {
        let base = events.map(duration(of:))
        let total = base.reduce(0, +) * speed.scale
        // 예산 안에 드는 턴은 그대로 둔다 — 전부 압축하면 데미지 두 방이 같은 프레임에 겹친다.
        let scale = total > budget ? speed.scale * budget / total : speed.scale
        var running = sides
        return zip(events, base).map { event, seconds in
            apply(event, to: &running)
            return ReplayStep(event: event, duration: seconds * scale, sides: running)
        }
    }

    /// 표시 상태를 한 이벤트만큼 앞으로 민다. **HP 와 활성 칸만 움직인다**(이유는 `ReplayStep.sides`).
    /// 모르는 actor·범위 밖 인덱스는 만들지 않는다: 없는 쪽의 바를 0 으로 그리는 것보다 안 그리는
    /// 쪽이 낫고, 엉뚱한 개체로 갈아타는 것보다 안 갈아타는 쪽이 낫다.
    private static func apply(_ event: BattleEvent, to sides: inout [BattleActor: ReplaySide]) {
        switch event {
        case .damage(let actor, let amount, _):
            guard var one = sides[actor], one.team.indices.contains(one.active) else { return }
            // 엔진과 같은 자리에서 자른다(`side.hp = max(0, …)`) — 오버킬에서 갈라지지 않는다.
            one.team[one.active].hp = max(0, one.team[one.active].hp - amount)
            sides[actor] = one
        case .sendOut(let actor, let index):
            guard var one = sides[actor], one.team.indices.contains(index) else { return }
            one.active = index
            sides[actor] = one
        // 표시 상태를 움직이지 않는 이벤트. **`default:` 를 두지 않는다** — 새 이벤트가 HP 를
        // 움직이는데 여기 빠지면 바가 배틀 내내 어긋난 채로 남는다. 컴파일이 깨지는 편이
        // `reconcile()` 로그를 한참 뒤에 발견하는 편보다 낫다.
        case .turn, .move, .miss, .immune, .crit, .superEffective, .resisted,
             .faint, .status, .cureStatus, .cant, .boost:
            return
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

    /// 재생 중 화면에 뜨는 문구의 자리. 로그는 재생이 그 줄에 닿아야 나오므로, 이 팝이 없으면
    /// 급소가 화면 어디에도 안 보인 채 HP 만 크게 깎인다.
    ///
    /// 문구가 아니라 `KeyPath` 인 이유는 언어다 — 뷰가 자기 `L` 로 푼다. `default:` 를 두지 않는
    /// 이유는 새 이벤트가 문구 없이 지나가는 것(이 함수가 있는 이유와 정반대다)을 컴파일로 막기
    /// 위해서다. `duration(of:)` 가 같은 이유로 전 case 를 나열한다.
    static func popupKey(for event: BattleEvent) -> KeyPath<L, String>? {
        switch event {
        case .crit:           return \.battleCritical
        case .superEffective: return \.battleSuperEffective
        case .resisted:       return \.battleNotVeryEffective
        case .miss:           return \.battleMissed
        case .immune:         return \.battleNoEffect
        // 팝이 없는 이벤트 — 전부 팝으로 만들면 화면이 문구로 덮여 정작 급소가 묻힌다.
        // 교체(`.sendOut`)는 스프라이트가 바뀌는 것이 곧 문구다.
        case .turn, .move, .damage, .faint, .sendOut, .status, .cureStatus, .cant, .boost:
            return nil
        }
    }

    static func popup(for event: BattleEvent, l: L) -> String? {
        popupKey(for: event).map { l[keyPath: $0] }
    }

    /// 팝은 **다음 팝이 뜰 때까지** 남는다. 자기 스텝(0.3초)만 뜨면 '급소에 맞았다!' 가 사라진 뒤에
    /// 바가 움직여(엔진 순서가 `.crit` → `.damage` 다) 원인과 결과가 화면에 같이 있는 순간이 없다 —
    /// 이벤트가 많은 턴은 예산 압축으로 문구가 60ms 도 못 뜬다.
    static func popped(_ event: BattleEvent, carrying previous: BattleEvent?) -> BattleEvent? {
        popupKey(for: event) != nil ? event : previous
    }

    /// 이 이벤트로 **맞은** 쪽 — shake·flash 를 거는 대상이다. 때린 쪽에 걸면 누가 맞았는지
    /// 반대로 읽힌다. `.damage` 는 원인(기술·화상·자멸)과 무관하게 맞은 쪽을 가리킨다.
    static func struck(by event: BattleEvent) -> BattleActor? {
        guard case .damage(let actor, _, _) = event else { return nil }
        return actor
    }
}
