import Foundation

/// 체육관 하나 — 한 타입을 대표하는 관장과 그 팀.
///
/// 관장 팀은 종 id 를 손으로 적는다. PokéAPI 에는 "이 타입의 종 목록" 조회가 없어 전수 확인이
/// 필요하기도 하고, 무엇보다 관장 팀은 뽑힌 게 아니라 **골라 놓은** 조합이어야 상대할 맛이 난다.
struct Gym: Identifiable, Sendable, Equatable {
    /// 세이브에 남는 배지 키. 종 구성이나 이름을 나중에 손봐도 이미 딴 배지가 사라지지 않도록
    /// 팀이 아니라 **타입**에서 딴다.
    var id: String { type.rawValue }
    let type: PokemonType
    /// langCode → 관장 이름.
    let names: [String: String]
    let teamSpeciesIDs: [Int]
    /// 관장 팀 레벨 — **고정이다.** 도전자에 맞춰 움직이면 언제 가도 같은 난이도라, 키운 만큼
    /// 쉬워지는 감각이 사라진다. 이기지 못하면 더 키우고 오는 게 이 컨텐츠의 목표다.
    let level: Int
    /// 첫 승리에만 나가는 별의조각. 재도전은 연습이지 수입이 아니다.
    let firstClearReward: Int

    func leaderName(_ language: AppLanguage) -> String {
        language.resolveName(names) ?? names["en"] ?? names.values.first ?? "?"
    }
}

/// 체육관 목록. 도전 순서는 강제하지 않는다 — 레벨이 곧 난이도라 순서는 자연히 정해진다.
///
/// 넷으로 시작한다. 구조가 자리를 잡으면 이 배열에 항목만 더하면 되고, 배지 키가 타입에서
/// 나오므로 뒤에 끼워 넣어도 기존 배지에 영향이 없다.
enum GymLeague {
    static let catalog: [Gym] = [
        Gym(type: .bug,
            names: ["ko": "벌레 체육관", "en": "Bug Gym", "ja": "むしジム"],
            teamSpeciesIDs: [12, 15, 123],          // 버터플 · 독침붕 · 스라크
            level: 12, firstClearReward: 500),
        Gym(type: .rock,
            names: ["ko": "바위 체육관", "en": "Rock Gym", "ja": "いわジム"],
            teamSpeciesIDs: [95, 111, 139],         // 롱스톤 · 코뿔코 · 암스타
            level: 20, firstClearReward: 1_000),
        Gym(type: .water,
            names: ["ko": "물 체육관", "en": "Water Gym", "ja": "みずジム"],
            teamSpeciesIDs: [134, 131, 130],        // 샤미드 · 라프라스 · 갸라도스
            level: 28, firstClearReward: 2_000),
        Gym(type: .electric,
            names: ["ko": "전기 체육관", "en": "Electric Gym", "ja": "でんきジム"],
            teamSpeciesIDs: [26, 125, 135],         // 라이츄 · 에레브 · 쥬피썬더
            level: 36, firstClearReward: 3_000),
    ]

    /// 배지 키로 되찾기 — 세이브에 남은 건 키뿐이라, 화면이 이름·타입을 그릴 때 거쳐 간다.
    static func gym(id: String) -> Gym? { catalog.first { $0.id == id } }

    /// 관장 팀 크기. 도전자도 같은 수로 맞춰 내보낸다 — 머릿수가 다르면 이겨도 진 것 같다.
    static let teamSize = 3
}
