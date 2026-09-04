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
    func name(_ l: L) -> String {
        switch self {
        case .potion:  l.t("상처약", "Potion", "きずぐすり")
        case .revive:  l.t("기력의조각", "Revive", "げんきのかけら")
        case .candy:   l.t("이상한사탕", "Rare Candy", "ふしぎなアメ")
        case .elixir:  l.t("엘릭서", "Elixir", "エリキシル")
        case .cleanse: l.t("만병통치제", "Full Heal", "なんでもなおし")
        case .typeBoost: l.t("타입 강화판", "Type Booster", "タイプ強化板")
        case .focusLens: l.t("초점렌즈", "Scope Lens", "ピントレンズ")
        case .leftovers: l.t("먹다남은음식", "Leftovers", "たべのこし")
        case .ballPouch: l.t("몬스터볼 보충", "Ball Pouch", "モンスターボール補充")
        case .xAttack:   l.t("플러스파워", "X Attack", "プラスパワー")
        case .xDefense:  l.t("디펜드업", "X Defense", "ディフェンダー")
        case .xSpeed:    l.t("스피드업", "X Speed", "スピーダー")
        }
    }
}

extension RunRoute {
    func name(_ l: L) -> String {
        switch self {
        case .safe:  l.t("평탄한 길", "Even path", "平らな道")
        case .risky: l.t("험한 길", "Rough path", "険しい道")
        }
    }
}
