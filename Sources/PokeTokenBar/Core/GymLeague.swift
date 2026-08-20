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
    /// 관장이 쓸 기술(PokéAPI move 이름), 팀 순서와 같다.
    ///
    /// 자동 선발(`moveSet`)에 맡기지 않는 이유: 그쪽은 "레벨 이하 습득 기술 중 최근 8개 → 변화기
    /// 제외 → 타입 겹치지 않게 4개" 라, 종에 따라 **두 개밖에 못 채우고** 위력 20 짜리가 섞였다.
    /// 라이츄가 스파크와 스위프트 둘만 들고 나오면 PP 가 금방 떨어져 발버둥으로 끝난다.
    /// 관장 팀을 손으로 고르면서 기술만 뽑기에 맡길 이유가 없다.
    ///
    /// 이름이 틀리면 그 종만 자동 선발로 돌아간다 — 배틀이 서지는 않는다.
    /// 이름·위력·상태이상은 `scripts/verify-gym-catalog.sh` 로 확인한다.
    let teamMoveNames: [[String]]
    /// 관장 팀 레벨 — 도전자에 맞춰 움직이지 않는다. 맞추면 언제 가도 같은 난이도라 키운 보람이
    /// 드러나지 않는다. 값은 `GymLeague.leaderLevel` 로 **모든 체육관이 같다**(그 상수의 주석 참고).
    let level: Int
    /// 첫 승리에만 나가는 별의조각. 재도전은 연습이지 수입이 아니다.
    let firstClearReward: Int

    func leaderName(_ language: AppLanguage) -> String {
        language.resolveName(names) ?? names["en"] ?? names.values.first ?? "?"
    }
}

/// 체육관 목록. 넷으로 시작한다 — 구조가 자리를 잡으면 이 배열에 항목만 더하면 되고,
/// 배지 키가 타입에서 나오므로 뒤에 끼워 넣어도 기존 배지에 영향이 없다.
enum GymLeague {
    /// 모든 관장이 서는 레벨. **체육관마다 다르게 두지 않는다.**
    ///
    /// 이 엔진에서 레벨은 데미지에 두 번 들어간다 — 레벨 계수 `(2*level/5+2)` 와 유효 스탯
    /// `(2*base+31)*level/100+5`. 둘이 곱해져 차이가 제곱에 가깝게 벌어진다: 종족값 100 기준
    /// Lv.12 팀이 Lv.36 관장을 치면 주고받는 데미지가 대략 2.5 대 44 로 **17배**다.
    /// 타입 상성 4배로도 뒤집히지 않고, HP 도 레벨에 비례해 실제로는 더 벌어진다.
    ///
    /// 그래서 레벨 사다리는 "권장 순서" 가 아니라 **순서 강제**이고, 이 컨텐츠의 공략인
    /// "상성 유리한 타입을 키워서 간다" 를 통째로 덮는다 — 상성은 레벨이 비슷할 때만 변수다.
    /// 레벨을 맞추고, 난이도는 관장 팀의 종족값·복합타입·기술로 낸다.
    ///
    /// 30 인 이유: 개체를 졸업시키고 다음으로 넘어가는 대역이 그쯤이라, 체육관에 데려갈 만한
    /// 개체가 쌓이는 시점과 맞는다(졸업한 개체도 박스에서 출전한다). 3마리를 모을 즈음이면
    /// 레벨도 그 근처다.
    ///
    /// 레벨 차가 10 이내면 상성이 여전히 작동한다 — Lv.20 팀이 Lv.30 관장을 치면 주고받는
    /// 데미지가 대략 6.9 대 20.3 으로 3배이고, 상성 4배가 그걸 뒤집는다. 위의 17배와 다른 점이다.
    static let leaderLevel = 30

    /// 순서는 관장 팀 **종족값 합의 대략적인 크기** 순이다 — 레벨이 같으니 난이도를 가르는 건
    /// 그쪽이다. 정확한 종족값은 PokéAPI 에서 오므로 여기 순서는 추정이고, 체감이 다르면
    /// 이 배열의 순서와 보상만 손보면 된다. 도전 순서를 막지는 않는다.
    /// 순서는 관장 팀 **종족값 합** 순이다 — 레벨이 같으니 난이도를 가르는 건 그쪽과 기술이다.
    /// 도전 순서를 막지는 않는다.
    static let catalog: [Gym] = [
        Gym(type: .bug,
            names: ["ko": "벌레 체육관", "en": "Bug Gym", "ja": "むしジム"],
            teamSpeciesIDs: [617, 589, 469],        // 어위르 · 슈바르고 · 메가야느
            teamMoveNames: [
                ["leech-life", "body-slam", "giga-drain", "swift"],
                ["bug-buzz", "take-down", "headbutt", "fury-cutter"],
                ["bug-buzz", "air-slash", "uproar", "night-slash"],
            ],
            level: leaderLevel, firstClearReward: 500),
        Gym(type: .rock,
            names: ["ko": "바위 체육관", "en": "Rock Gym", "ja": "いわジム"],
            teamSpeciesIDs: [526, 409, 476],        // 기가이어스 · 램펄드 · 대코파스
            teamMoveNames: [
                ["power-gem", "rock-slide", "headbutt", "smack-down"],
                ["rock-slide", "crunch", "iron-head", "headbutt"],
                ["power-gem", "rock-slide", "spark", "tri-attack"],
            ],
            level: leaderLevel, firstClearReward: 1_000),
        Gym(type: .electric,
            names: ["ko": "전기 체육관", "en": "Electric Gym", "ja": "でんきジム"],
            teamSpeciesIDs: [466, 405, 181],        // 에레키블 · 렌트라 · 전룡
            teamMoveNames: [
                ["wild-charge", "thunder-punch", "fire-punch", "swift"],
                ["crunch", "spark", "thunder-fang", "quick-attack"],
                ["zap-cannon", "thunder-punch", "dragon-pulse", "fire-punch"],
            ],
            level: leaderLevel, firstClearReward: 2_000),
        Gym(type: .water,
            names: ["ko": "물 체육관", "en": "Water Gym", "ja": "みずジム"],
            teamSpeciesIDs: [350, 260, 121],        // 밀로틱 · 대짱이 · 아쿠스타
            teamMoveNames: [
                ["aqua-tail", "water-pulse", "dragon-tail", "disarming-voice"],
                ["earthquake", "surf", "rock-slide", "water-pulse"],
                ["hydro-pump", "psychic", "power-gem", "psybeam"],
            ],
            level: leaderLevel, firstClearReward: 3_000),
    ]

    /// 배지 키로 되찾기 — 세이브에 남은 건 키뿐이라, 화면이 이름·타입을 그릴 때 거쳐 간다.
    static func gym(id: String) -> Gym? { catalog.first { $0.id == id } }

    /// 관장 팀 크기. 도전자도 같은 수로 맞춰 내보낸다 — 머릿수가 다르면 이겨도 진 것 같다.
    static let teamSize = 3
}
