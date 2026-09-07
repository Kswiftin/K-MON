import Foundation

/// 웨이브 런의 표시 이름 — **보상 한 장과 길 하나의 이름표가 여기 한 벌뿐이다.**
///
/// 예전엔 `RogueRunView` 의 `private static` 이었다. 그래서 터미널이 같은 목록을 보여 주려면
/// 자기 이름표를 새로 쓸 수밖에 없었고, 그 순간 보상을 하나 더할 때 **한쪽만 고쳐지는** 자리가
/// 생긴다(아이템 이름을 `ItemKind.named` 로 모은 것과 같은 이유다).
///
/// 자세한 설명(무엇이 얼마나 오르는지)은 화면에 남겼다 — 터미널은 폭이 귀해 한 줄에 문단을
/// 실을 수 없고, 목록에서 고를 때 필요한 것은 이름과 지속 여부다.
extension RunModifier {
    var name: String {
        switch self {
        case .potion:  "상처약"
        case .revive:  "기력의조각"
        case .candy:   "이상한사탕"
        case .elixir:  "엘릭서"
        case .cleanse: "만병통치제"
        case .typeBoost: "타입 강화판"
        case .focusLens: "초점렌즈"
        case .leftovers: "먹다남은음식"
        case .ballPouch: "몬스터볼 보충"
        case .xAttack:   "플러스파워"
        case .xDefense:  "디펜드업"
        case .xSpeed:    "스피드업"
        }
    }
}

extension RunRoute {
    var name: String {
        switch self {
        case .safe:  "평탄한 길"
        case .risky: "험한 길"
        }
    }
}
