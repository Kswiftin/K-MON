import Foundation

/// 집중 세션의 길이 프리셋. **집중 분과 휴식 분을 한 자리에서 묶는다** — 둘이 떨어져 있던 동안
/// 휴식은 어떤 길이를 골라도 5분 고정이었다(90분을 집중하고 5분 쉬었다).
///
/// 목록이 여기 한 벌인 이유는 `PokemonChatTool.focusMinutes` 의 계약과 같다: 화면 피커와 대화
/// 도구가 각자 목록을 들면 화면이 제시하지 않는 길이를 대화만 켤 수 있다.
enum FocusPreset: String, CaseIterable, Sendable, Identifiable {
    case warmup, sprint, classic, deep, longDeep

    var id: String { rawValue }

    var minutes: Int {
        switch self {
        case .warmup: 15
        case .sprint: 20
        case .classic: 25
        case .deep: 50
        case .longDeep: 90
        }
    }

    /// 집중이 끝난 뒤 이어지는 휴식. 대략 집중의 1/5 — 짧은 세션은 흐름을 끊지 않게, 긴 세션은
    /// 회복이 되게.
    var restMinutes: Int {
        switch self {
        case .warmup: 3
        case .sprint: 4
        case .classic: 5
        case .deep: 10
        case .longDeep: 15
        }
    }

    /// 임의의 분을 목록 안으로 접는다. 같은 거리면 먼저 만난 쪽(짧은 쪽)이 이긴다.
    ///
    /// `min(by:)` + `?? .classic` 대신 `reduce` 를 쓴다 — `allCases` 는 비지 않으므로 그 fallback 은
    /// **영영 실행되지 않는 분기**가 되고, 실행되지 않는 분기는 검증할 방법도 없다.
    static func nearest(toMinutes minutes: Int) -> FocusPreset {
        allCases.reduce(.classic) { abs($1.minutes - minutes) < abs($0.minutes - minutes) ? $1 : $0 }
    }
}
