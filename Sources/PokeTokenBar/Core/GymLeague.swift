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
    /// 체육관 타입 밖에서 마지막에 나오는 전설 에이스. 단일 약점 타입으로 팀을 쓸어버리는 것을
    /// 막기 위한 예외이며, 있으면 반드시 `teamSpeciesIDs`의 마지막 종과 같다.
    let aceSpeciesID: Int?
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
    /// 관장 팀의 최소 레벨. 실제 전투에서는 선택 팀 평균보다 3 높은 값과 이 값 중 큰 쪽을 쓴다.
    let level: Int
    /// 첫 승리에만 나가는 보상. 재도전은 연습이지 수입이 아니다.
    let firstClearReward: GymReward

    init(type: PokemonType, names: [String: String], teamSpeciesIDs: [Int],
         aceSpeciesID: Int? = nil, teamMoveNames: [[String]], level: Int,
         firstClearReward: GymReward) {
        self.type = type
        self.names = names
        self.teamSpeciesIDs = teamSpeciesIDs
        self.aceSpeciesID = aceSpeciesID
        self.teamMoveNames = teamMoveNames
        self.level = level
        self.firstClearReward = firstClearReward
    }

    func leaderName(_ language: AppLanguage) -> String {
        language.resolveName(names) ?? names["en"] ?? names.values.first ?? "?"
    }
}

/// 체육관 목록. 여덟 타입으로 시작한다 — 구조가 자리를 잡으면 이 배열에 항목만 더하면 되고,
/// 배지 키가 타입에서 나오므로 뒤에 끼워 넣어도 기존 배지에 영향이 없다.
/// 체육관 첫 승리 보상. 난이도 점검 릴리즈에서는 알·배지·완주 보상을 빼고 별의조각만 지급한다.
struct GymReward: Sendable, Equatable {
    var starPieces: Int = 0
    /// 지급할 알 개수. 보관 알로 들어가 5분 뒤 부화한다.
    var eggs: Int = 0
    /// 그 알에 걸 등급 하한. nil = 보증 없음.
    var eggGuarantee: Rarity? = nil
    /// 이로치 확정 부화 횟수. 알과 별개로 쌓이며 다음 부화부터 하나씩 쓰인다.
    var shinyCharges: Int = 0

    var isEmpty: Bool { starPieces == 0 && eggs == 0 && shinyCharges == 0 }

    /// 두 보상을 합친다 — 마지막 체육관을 깨면 그 보상과 완주 보상이 함께 나간다.
    /// 등급 보증은 더하지 않고 **높은 쪽을 남긴다**(보증은 하나만 걸리므로).
    func merging(_ other: GymReward) -> GymReward {
        GymReward(starPieces: starPieces + other.starPieces,
                  eggs: eggs + other.eggs,
                  eggGuarantee: [eggGuarantee, other.eggGuarantee]
                      .compactMap { $0 }
                      .max { $0.sortRank < $1.sortRank },
                  shinyCharges: shinyCharges + other.shinyCharges)
    }
}

enum GymLeague {
    /// 모든 관장이 서는 최소 레벨. **체육관마다 다르게 두지 않는다.**
    ///
    /// 이 엔진에서 레벨은 데미지에 두 번 들어간다 — 레벨 계수 `(2*level/5+2)` 와 유효 스탯
    /// `(2*base+31)*level/100+5`. 둘이 곱해져 차이가 제곱에 가깝게 벌어진다: 종족값 100 기준
    /// Lv.12 팀이 Lv.36 관장을 치면 주고받는 데미지가 대략 2.5 대 44 로 **17배**다.
    /// 타입 상성 4배로도 뒤집히지 않고, HP 도 레벨에 비례해 실제로는 더 벌어진다.
    ///
    /// 그래서 레벨 사다리는 "권장 순서" 가 아니라 **순서 강제**이고, 이 컨텐츠의 공략인
    /// "상성 유리한 타입을 키워서 간다" 를 통째로 덮는다 — 상성은 레벨이 비슷할 때만 변수다.
    /// 다만 Lv.50 이상 팀이 Lv.30 관장을 한 방에 정리하는 것도 난이도가 아니다. 선택 팀 평균보다
    /// 3 높은 선에서 맞춰 키운 보람은 남기되, 타입 상성이 전부를 결정하지 않게 한다.
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
            // 아라콰나이드 · 불카모스 · 갑주무사 · 히드런(전설 에이스). 이전 팀은 넷 모두 불꽃에
            // 약해 불꽃 포켓몬 하나에게 끝났다. 앞 셋은 불꽃에 중립, 히드런은 불꽃을 흡수한다.
            teamSpeciesIDs: [752, 637, 768, 485],
            aceSpeciesID: 485,
            teamMoveNames: [
                ["liquidation", "leech-life", "crunch", "poison-jab"],
                ["fiery-dance", "bug-buzz", "psychic", "giga-drain"],
                ["liquidation", "leech-life", "sucker-punch", "drill-run"],
                ["magma-storm", "earth-power", "flash-cannon", "dark-pulse"],
            ],
            level: leaderLevel,
            firstClearReward: GymReward(starPieces: 500)),
        Gym(type: .rock,
            names: ["ko": "바위 체육관", "en": "Rock Gym", "ja": "いわジム"],
            // 기가이어스 · 램펄드 · 대코파스 · 레지락(전설). 레지락은 방어 200 에 공격 100 이라
            // 물리 위주 4기로 채운다 — 특공 50 짜리에게 특수기를 쥐어주는 건 낭비다.
            teamSpeciesIDs: [526, 409, 476, 377],
            teamMoveNames: [
                ["stone-edge", "earthquake", "iron-head", "rock-slide"],
                ["rock-slide", "earthquake", "zen-headbutt", "crunch"],
                ["power-gem", "flash-cannon", "thunderbolt", "earth-power"],
                ["stone-edge", "earthquake", "drain-punch", "ice-punch"],
            ],
            level: leaderLevel,
            firstClearReward: GymReward(starPieces: 500)),
        Gym(type: .electric,
            names: ["ko": "전기 체육관", "en": "Electric Gym", "ja": "でんきジム"],
            // 에레키블 · 렌트라 · 전룡 · 썬더(전설). 특공 125 로 셋 중 가장 높아 특수 위주로 채우되,
            // 비행 STAB(드릴부리)은 정확도가 안정적인 쪽을 골랐다 — 허리케인·번개는 명중 70 이라
            // 어렵게 만드는 건 위력이지 뽑기 운이 아니어야 한다.
            teamSpeciesIDs: [466, 405, 181, 145],
            teamMoveNames: [
                ["wild-charge", "earthquake", "ice-punch", "fire-punch"],
                ["wild-charge", "crunch", "psychic-fangs", "ice-fang"],
                ["thunderbolt", "dragon-pulse", "power-gem", "dazzling-gleam"],
                ["thunderbolt", "drill-peck", "heat-wave", "extrasensory"],
            ],
            level: leaderLevel,
            firstClearReward: GymReward(starPieces: 1_000)),
        Gym(type: .water,
            names: ["ko": "물 체육관", "en": "Water Gym", "ja": "みずジム"],
            // 밀로틱 · 대짱이 · 아쿠스타 · 수이쿤(전설). 방어·특방 115 로 오래 버티는 개체라
            // 특수 위주로 채워 높은 특방으로 오래 버티며 꾸준히 압박한다.
            teamSpeciesIDs: [350, 260, 121, 245],
            teamMoveNames: [
                ["surf", "ice-beam", "dragon-pulse", "psychic"],
                ["earthquake", "waterfall", "ice-punch", "rock-slide"],
                ["surf", "psychic", "thunderbolt", "ice-beam"],
                ["hydro-pump", "ice-beam", "extrasensory", "shadow-ball"],
            ],
            level: leaderLevel,
            firstClearReward: GymReward(starPieces: 2_000)),
        Gym(type: .fire,
            names: ["ko": "불꽃 체육관", "en": "Fire Gym", "ja": "ほのおジム"],
            // 나인테일 · 윈디 · 샹델라 · 히드런(전설). 특수·물리를 섞어 물 한 타입만으로
            // 쉽게 쓸어버리지 못하게 하고, 히드런은 마지막에 강철 STAB까지 꺼낸다.
            teamSpeciesIDs: [38, 59, 609, 485],
            teamMoveNames: [
                ["flamethrower", "energy-ball", "psyshock", "dark-pulse"],
                ["heat-wave", "wild-charge", "crunch", "play-rough"],
                ["shadow-ball", "flamethrower", "energy-ball", "psychic"],
                ["magma-storm", "earth-power", "flash-cannon", "dark-pulse"],
            ],
            level: leaderLevel,
            firstClearReward: GymReward(starPieces: 3_000)),
        Gym(type: .grass,
            names: ["ko": "풀 체육관", "en": "Grass Gym", "ja": "くさジム"],
            // 이상해꽃 · 나시 · 덩쿠림보 · 쉐이미(전설). 풀은 약점이 많아 기술 폭을 넓히고,
            // 마지막 쉐이미는 600 종족값의 특수 압박으로 단일 불꽃 대응을 버틴다.
            teamSpeciesIDs: [3, 103, 465, 492],
            teamMoveNames: [
                ["energy-ball", "sludge-bomb", "earth-power", "psychic"],
                ["energy-ball", "psychic", "flamethrower", "shadow-ball"],
                ["power-whip", "earthquake", "rock-slide", "sludge-bomb"],
                ["energy-ball", "earth-power", "psychic", "air-slash"],
            ],
            level: leaderLevel,
            firstClearReward: GymReward(starPieces: 4_000)),
        Gym(type: .psychic,
            names: ["ko": "에스퍼 체육관", "en": "Psychic Gym", "ja": "エスパージム"],
            // 후딘 · 메타그로스 · 엘레이드 · 뮤츠(전설). 내구·물리·특수를 나눠 악 타입 하나만
            // 들고 와도 끝나지 않게 하며, 마지막 뮤츠는 폭넓은 특수 기술로 마무리한다.
            teamSpeciesIDs: [65, 376, 475, 150],
            teamMoveNames: [
                ["psychic", "shadow-ball", "energy-ball", "dazzling-gleam"],
                ["meteor-mash", "zen-headbutt", "earthquake", "ice-punch"],
                ["psycho-cut", "leaf-blade", "night-slash", "x-scissor"],
                ["psychic", "aura-sphere", "ice-beam", "thunderbolt"],
            ],
            level: leaderLevel,
            firstClearReward: GymReward(starPieces: 5_000)),
        Gym(type: .dragon,
            names: ["ko": "드래곤 체육관", "en": "Dragon Gym", "ja": "ドラゴンジム"],
            // 킹드라 · 드래캄 · 두랄루돈 · 디아루가(전설). 이전 팀은 얼음·페어리에 전원이 약했다.
            // 강철 드래곤 둘은 두 타입을 중립으로 받아, 약점 하나로 끝나지 않는 막판전을 만든다.
            teamSpeciesIDs: [230, 691, 884, 483],
            teamMoveNames: [
                ["hydro-pump", "dragon-pulse", "ice-beam", "flash-cannon"],
                ["sludge-bomb", "dragon-pulse", "thunderbolt", "hydro-pump"],
                ["flash-cannon", "dragon-pulse", "thunderbolt", "dark-pulse"],
                ["dragon-pulse", "flash-cannon", "thunderbolt", "earth-power"],
            ],
            level: leaderLevel,
            firstClearReward: GymReward(starPieces: 6_000)),
    ]

    /// 배지 키로 되찾기 — 세이브에 남은 건 키뿐이라, 화면이 이름·타입을 그릴 때 거쳐 간다.
    static func gym(id: String) -> Gym? { catalog.first { $0.id == id } }

    /// 관장은 최소 Lv.30 이고, 그보다 높은 선택 팀에는 평균 레벨보다 3 높게 맞춘다. 평균은
    /// 특정 한 마리만 과도하게 키워 전체 관장을 끌어올리지 않도록 팀 전체에서 계산한다.
    static func opponentLevel(for challengerLevels: [Int]) -> Int {
        let levels = challengerLevels.filter { (1...100).contains($0) }
        guard !levels.isEmpty else { return leaderLevel }
        let average = levels.reduce(0, +) / levels.count
        return min(100, max(leaderLevel, average + 3))
    }

    /// 관장 팀 크기. 도전자도 같은 수로 맞춰 내보낸다 — 머릿수가 다르면 이겨도 진 것 같다.
    /// 3 → 4 (타입별 전설 포켓몬 추가, 2026-08). 마지막 자리를 전설이 차지하므로 도전자도
    /// 4마리를 갖춰야 도전할 수 있다(`startGymChallenge` 의 보유 마릿수 확인).
    static let teamSize = 4

}
