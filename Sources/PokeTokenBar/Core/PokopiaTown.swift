import Foundation

/// 마을 지형 한 칸.
///
/// **rawValue 가 세이브 ID 다** — 바꾸면 기존 마을이 기본 지형으로 되돌아간다(`normalized` 가
/// 모르는 키를 버린다). 식별자라서 영문 소문자를 유지하고, 화면에 쓰는 이름은 `name` 이 답한다.
enum TownTerrain: String, Codable, Sendable, CaseIterable {
    case grass, soil, water, sand, path, flower, tree, rock

    /// 화면에 그리는 이름. 브러시 배너와 문구가 같은 값을 쓰게 여기 한 곳에 둔다.
    var name: String {
        switch self {
        case .grass:  "풀밭"
        case .soil:   "흙"
        case .water:  "물"
        case .sand:   "모래"
        case .path:   "길"
        case .flower: "꽃밭"
        case .tree:   "나무"
        case .rock:   "바위"
        }
    }
}

/// 마을이 서는 지역 다섯 곳. **rawValue 가 세이브 키다** — `PokopiaState.towns` 의 딕셔너리
/// 키로 그대로 굽히므로, 바꾸면 그 지역의 마을이 통째로 사라진다(정규화가 모르는 키를 버린다).
/// 식별자라서 영문 소문자를 유지하고, 화면에 쓰는 이름은 `name` 이 답한다(`TownTerrain` 과 같다).
///
/// **지역을 나눈 이유는 바탕이 다르기 때문이다.** 기본 지형이 다섯 곳 다 풀이면 첫날 같은 타입을
/// 부르고, 그러면 마을을 나눈 것이 이름표 다섯 개가 된다.
enum TownRegion: String, Codable, Sendable, CaseIterable {
    case waste, coast, ridge, ashen, isle

    /// 화면에 쓰는 이름. 보간 뒤에 조사를 붙이지 않는다(`PokopiaParticleGuardTests`) —
    /// 받침이 갈린다(황야·해안·산지는 없고 회색·부유섬은 있다).
    var name: String {
        switch self {
        case .waste: "황야"
        case .coast: "해안"
        case .ridge: "산지"
        case .ashen: "회색"
        case .isle:  "부유섬"
        }
    }

    /// 이 지역의 바탕 지형. **이것이 다섯 마을을 만든 이유다** — 기본 지형 176칸이 이미 문턱
    /// (`PokopiaTown.habitatThreshold` = 6)을 넘으므로 1일차 마을이 지역마다 다른 타입을 부른다.
    ///
    /// 다섯 다 부르는 지형이다(`PokopiaTown.terrain(for:)` 이 8 지형 전부에 최소 한 타입을 준다):
    /// 모래←불꽃·독 · 물←물·얼음 · 바위←격투·악 · 길←노말·전기·고스트 · 풀←풀·벌레.
    var base: TownTerrain {
        switch self {
        case .waste: .sand
        case .coast: .water
        case .ridge: .rock
        case .ashen: .path
        case .isle:  .grass
        }
    }
}

/// 주민의 특기. 원작 32종 중 **타입에 붙일 근거가 있는 18종**만 옮겼다 — 타입마다 하나(`PokopiaTown.specialty(for:)`).
/// **문구 전용**이다: 주민 줄과 아침 문장만 읽고, 보상·정원·레벨·이사 판정은 읽지 않는다.
///
/// 저장하지 않는다(타입에서 파생). 그래서 `TownTerrain` 과 달리 `rawValue`·`Codable` 이 없다 — 세이브에 안 들어가는
/// 식별자를 동결할 이유가 없다. 옮기지 않은 14종과 이유는 `docs/reference/pokopia-town-design.md` 의 특기 절에 있다.
enum TownSpecialty: CaseIterable, Sendable {
    case ignition, watering, farming, generating, leveling, flight, teleporting, honeyGathering,
         recycling, cutting, polishing, crushing, messing, exploring, sorting, moodMaking, rareHunting, yawning

    /// 화면에 쓰는 이름. 원작 표기 그대로다 — 주민 줄과 아침 문장이 같은 값을 읽는다.
    var name: String {
        switch self {
        case .ignition:        "점화"
        case .watering:        "급수"
        case .farming:         "재배"
        case .generating:      "발전"
        case .leveling:        "땅고르기"
        case .flight:          "공중날기"
        case .teleporting:     "순간이동"
        case .honeyGathering:  "꿀모으기"
        case .recycling:       "리사이클"
        case .cutting:         "절삭"
        case .polishing:       "연마"
        case .crushing:        "분쇄"
        case .messing:         "어지르기"
        case .exploring:       "탐색"
        case .sorting:         "분류"
        case .moodMaking:      "분위기메이킹"
        case .rareHunting:     "레어수집"
        case .yawning:         "하품"
        }
    }
}

/// 마을에 사는 포켓몬 하나. **소유 개체가 아니다** — 파티·박스와 무관하고 잡히지 않는다.
///
/// 이름과 타입을 **도착할 때 저장한다.** 도감에 없는 종이라 나중에 조회할 근거가 없고
/// (종 번호로 이름을 주는 인덱스가 `PokeProviding` 에 없다), 매 렌더 조회는 오프라인에서
/// 이름을 통째로 지운다 — `MonState.names`·`DexEntry.types` 가 같은 이유로 같은 값을 저장한다.
struct TownResident: Codable, Sendable, Equatable, Identifiable {
    var speciesID: Int
    var name: String
    var types: [PokemonType]
    var arrivedAt: Date
    /// 종이 곧 정체다 — **같은 종은 두 번 이사 오지 않는다**. 이 성질이 이사의 멱등이라
    /// 세션 단위 가드가 필요 없다(이사는 비동기 조회 뒤에 결정되므로 동기 가드에 못 태운다).
    var id: Int { speciesID }
}

/// 마을 상태 전부. `PokopiaState.towns` 의 값 하나다(7단계 전에는 `MemoryHomeAccessSettings.town`
/// 한 키였다).
///
/// 필드가 셋뿐이다. 아바타 자리·주민 자리·화면 문구는 **전부 파생**이라 저장하지 않는다
/// (`docs/reference/memory-home-plan.md` 의 "새 저장 필드를 만들지 않는다" 원칙을 지킬 수
/// 있는 만큼 지킨 형태다 — 지형·변신·주민만 사용자 의도라 저장을 피할 수 없다).
struct PokopiaTownState: Codable, Sendable, Equatable {
    /// 행 우선 평탄 배열, 길이 `PokopiaTown.tileCount`. 2차원 배열로 두면 JSON 이 중첩되고
    /// 길이 검증이 두 축이 된다.
    var terrain: [TownTerrain]
    /// 변신 중인 종 id. **nil 이면 아무것도 밀 수 없다** — 변신이 유일한 도구다.
    var dittoForm: Int?
    /// 도착 순서를 지킨다 — 상한에 걸릴 때 누가 남는지가 실행마다 바뀌면 안 된다.
    var residents: [TownResident] = []
    /// 마을이 배부른 시각까지(9단계). **이 단계가 더한 유일한 마을 저장 필드다** — 요리 결과는
    /// 파생할 수 없다(지형과 주민만 보면 답이 안 나온다). nil = 한 번도 안 먹였거나 다 지났다.
    ///
    /// 마을당 하나다. 주민별로 두면 16 × 5 = 80개 상태가 되고, 8단계가 잰 LAN 와이어 예산
    /// (카드 + 마을 한 채 6,762 B / 상한 16,384 B)을 다시 계산해야 한다.
    ///
    /// 옵셔널이라 **옛 세이브가 그대로 열린다** — 합성 `Codable` 이 없는 키를 nil 로 받는다.
    var fedUntil: Date?

    /// 그 지역의 빈 마을. **지역이 바탕을 정한다** — 지형을 인자로 받지 않는 이유는 그 둘이
    /// 갈리면 해안 마을이 풀밭으로 시작할 수 있기 때문이다.
    ///
    /// 기본값이 `.waste` 인 것은 `PokopiaState.home` 의 기본값과 같은 값이라서다 — 아무 인자
    /// 없이 만든 마을은 곧 "창을 처음 열었을 때 보이는 마을" 이다.
    init(region: TownRegion = .waste, dittoForm: Int? = nil, residents: [TownResident] = []) {
        self.terrain = PokopiaTown.defaultTerrain(for: region)
        self.dittoForm = dittoForm
        self.residents = residents
    }
}

/// 포코피아 전체. **앨범 최상위 키다** — 싸이월드 미니홈피 설정(`MemoryHomeAccessSettings`) 안이
/// 아니다. 두 기능이 공유하는 것은 "같은 파일에 저장한다" 뿐이고, 그것은 같은 구조체에 살 이유가
/// 되지 않는다(창을 가른 Phase 0 이 화면에서 한 일을 7단계가 저장에서 한다).
struct PokopiaState: Codable, Sendable, Equatable {
    /// 지역 rawValue → 그 지역의 마을. **`[TownRegion: …]` 이 아니다.** String rawValue 를 가진
    /// enum 을 딕셔너리 키로 쓰면 Swift Codable 이 객체가 아니라 **배열**로 굽고
    /// (`{"towns":["waste",{…}]}`), `CodingKeyRepresentable` 을 붙여 객체로 굽게 하면 모르는 키
    /// 하나에 `dataCorrupted` 를 던져 **앨범 전체가 `.corrupt`** 로 밀려난다. 둘 다 재봤다
    /// (2026-09-16). `[String: …]` 은 모르는 키를 그냥 담고 `normalized` 가 버린다.
    ///
    /// **안 만든 지역은 담기지 않는다.** 읽기는 `town(_:)` 이 기본 마을을 만들어 주므로,
    /// 포코피아를 한 번도 안 연 사용자의 세이브가 다섯 마을만큼 커지지 않는다.
    var towns: [String: PokopiaTownState] = [:]
    /// 지금 보고 있는 지역이자 **이사가 오는 지역**. 둘을 가르지 않는다 — 전역 상한이 "어느 마을을
    /// 키울지 고르게" 하는 장치인데, 보는 곳과 크는 곳이 다르면 그 선택이 화면에서 안 보인다.
    /// 사용자 의도라 시계에서 파생할 수 없고, 그래서 저장하는 유일한 새 필드다.
    var home: TownRegion = .waste

    /// 그 지역의 마을. 없으면 **그 지역의 기본 지형**으로 만든 새 마을이다(저장하지 않는다).
    func town(_ region: TownRegion) -> PokopiaTownState {
        towns[region.rawValue] ?? PokopiaTownState(region: region)
    }

    /// 다섯 마을을 합친 주민 수. `PokopiaTown.globalPopulationLimit` 의 입력이다. 파생이라
    /// 저장하지 않는다 — 저장하면 `towns` 와 어긋날 수 있는 두 번째 진실이 생긴다.
    var totalResidents: Int { towns.values.reduce(0) { $0 + $1.residents.count } }

    private enum CodingKeys: String, CodingKey { case towns, home }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        towns = try c.decodeIfPresent([String: PokopiaTownState].self, forKey: .towns) ?? [:]
        // **모르는 지역 이름에 던지지 않는다.** 합성 디코드는 `TownRegion(rawValue:)` 가 nil 이면
        // `dataCorrupted` 를 던지고, 그 예외 하나가 앨범 파일을 `.corrupt` 로 밀어내 기존 사용자
        // 전원의 기억을 백업 파일로 보낸다(`PokemonMemoryAlbum.init` 의 catch 가 그 자리다).
        home = (try? c.decodeIfPresent(TownRegion.self, forKey: .home)).flatMap { $0 } ?? .waste
    }
}

/// 마을의 규칙. **표는 전부 여기 하나다** — 화면·테스트·나중의 터미널이 같은 값을 읽는다.
/// 판정표가 하나여도 그 **입력을 조립하는 코드**가 프런트엔드마다 복사되면 같은 부류가 되므로,
/// 조립은 `CompanionStore` 의 `townBrush`·`rollTownImmigration` 두 곳으로만 모은다.
enum PokopiaTown {
    static let columns = 16
    static let rows = 12
    static let tileCount = columns * rows   // 192

    /// 마을 인구의 **절대 천장**. 격자 192칸에 16마리면 12칸당 하나다 — 스프라이트가 서로
    /// 가리지 않는 밀도의 상한으로 잡았다. **소유가 아니므로** 룸메이트 3명 같은 소유 상한과는
    /// 축이 다르다.
    ///
    /// 실제로 지금 몇 마리가 살 수 있는지는 `development(_:residents:).capacity` 가 정한다(지형 다양성이
    /// 자리를 연다). 이 값은 그 위의 벽이고, **신뢰경계(`normalized`)만 이 값을 쓴다** —
    /// 정원을 신뢰경계에 넣으면 지형을 지울 때 주민이 잘려 나간다(금지한 자동 퇴거다).
    static let populationLimit = 16

    /// 다섯 마을을 합친 인구의 **절대 천장**. `< TownRegion.allCases.count × populationLimit`
    /// (= 80) 이어야 한다 — 같거나 크면 다섯 마을을 전부 꽉 채울 수 있고, 그러면 "어느 마을을
    /// 키울지 고른다" 가 사라져 지역이 그냥 격자 다섯 개가 된다. 테스트가 그 부등식을 센다.
    ///
    /// 60 은 마을 셋 반쯤이다. 두 마을은 마음껏 키우고 세 번째부터 고르게 된다.
    ///
    /// **신뢰경계(`normalized`)는 이 값을 읽지 않는다** — 읽으면 배열을 자르는 자리가 되어
    /// 지역을 옮길 때마다 주민이 사라진다. 그건 이 기능이 금지한 자동 퇴거다. 거절은 받는 자리
    /// (`admitTownResident`)가 한다.
    static let globalPopulationLimit = 60

    /// 한 지형이 타입을 부르기 시작하는 칸 수. 6칸은 한 줄(16칸)의 3분의 1 남짓이다 —
    /// 실수로 두 칸 밀었다고 포켓몬이 오면 "내가 만들어서 왔다" 가 아니라 우연이 된다.
    ///
    /// **기본 지형이 이미 바탕 176칸이라 새 마을도 그 타입을 부른다.** 의도다 — 1일차 마을이
    /// 아무도 부르지 않으면 첫 세션의 이사 판정이 영영 빈손이고, 사용자는 이 기능이 도는지도
    /// 모른다. 문턱을 올려 막으려 하면 반대로 6칸을 밀어도 아무 일이 없어진다.
    static let habitatThreshold = 6

    /// 편집 되돌리기 깊이. 방 편집(`beginRoomEdit`)과 같은 값이다 — 두 편집기의 감각이
    /// 다르면 사용자가 어느 쪽에서 몇 번 되돌릴 수 있는지 알 수 없다.
    static let undoDepth = 30

    /// 그 지역의 첫 마을. 바탕은 지역이 정하고(`TownRegion.base`) **맨 아래 줄은 언제나 길**이다 —
    /// 아바타가 서는 자리라서 지역마다 다르면 아바타가 물 위나 바위 위에 선다. 빈 격자로 열지
    /// 않는 이유도 그대로다: 길이 있으면 그 자체로 장소로 읽힌다.
    ///
    /// 회색(`.ashen`)은 바탕도 길이라 격자 전체가 길이 된다 — 의도다(노말·전기·고스트를 부른다).
    static func defaultTerrain(for region: TownRegion) -> [TownTerrain] {
        (0..<tileCount).map { $0 / columns == rows - 1 ? .path : region.base }
    }

    /// 주민이 설 수 있는 칸. **맨 아래 길 줄을 뺀다** — 아바타 자리라 겹친다.
    /// 176칸이므로 **절대 비지 않는다**(`residentSpot` 의 `%` 가 0으로 나누지 않는 근거).
    static let residentSpotIndices: [Int] = Array(0..<(tileCount - columns))

    /// 좌표 → 배열 첨자. 범위 밖은 nil — 호출부가 클램프하지 않게 여기서 거절한다.
    /// 클램프하면 화면 밖 탭이 가장자리 타일을 밀어, 사용자가 안 누른 칸이 바뀐다.
    static func index(col: Int, row: Int) -> Int? {
        guard (0..<columns).contains(col), (0..<rows).contains(row) else { return nil }
        return row * columns + col
    }

    // MARK: - 타입 ↔ 지형 (표는 하나다)

    /// **포코피아의 핵심 표** — 포켓몬 타입이 어떤 지형을 만드는가. 곧 변신했을 때의 브러시다.
    ///
    /// 18 타입 전부가 답을 가지며(전수 `switch` — `default:` 를 쓰지 않는 이유는 타입이
    /// 늘어날 때 컴파일 에러로 알려 주게 하려는 것이다), 8 지형 전부가 최소 한 타입에서
    /// 도달 가능하다. `PokopiaTownTests` 가 **양방향**을 못 박는다 — 도달 불가 지형은 어떤
    /// 변신으로도 만들 수 없는 채 남고, 그 분기는 아무 호출부가 없어 라인 커버리지에 안 잡힌다.
    static func terrain(for type: PokemonType) -> TownTerrain {
        switch type {
        case .ground, .rock, .steel:      .soil
        case .water, .ice:                .water
        case .grass, .bug:                .grass
        case .fairy, .psychic:            .flower
        case .dragon, .flying:            .tree
        case .fire, .poison:              .sand
        case .fighting, .dark:            .rock
        case .normal, .electric, .ghost:  .path
        }
    }

    // MARK: - 타입 ↔ 특기 (표는 하나다 · 문구 전용)

    /// **타입이 특기다.** 18 타입 전부가 답을 가지며(전수 `switch` — `default:` 금지, 이유는 `terrain(for:)` 와 같다)
    /// 18 특기 전부가 **정확히 한** 타입에서 온다 — `testEverySpecialtyComesFromExactlyOneType` 이 양방향을 센다.
    /// 지형 표는 8 ← 18 이라 "최소 하나" 였지만 여기는 18 ← 18 이라 겹치면 어느 특기 하나가 화면에서 영영 사라진다.
    ///
    /// 배정 근거는 원작이 아니라 직관이다(불꽃이 점화, 물이 급수). 다음 사람이 다시 판단해도 된다 — 지킬 것은 전수와
    /// 유일 둘뿐이다. 가장 약한 배정은 얼음→하품이다(느긋하다는 인상 하나).
    ///
    /// 특기는 **문구에만** 쓴다. 세션 보상에 연결하면 지갑이 `starPieces` 하나라 보상은 그 배율이 되고, 그 순간 마을이
    /// 파밍 대상이 된다 — 티켓 경제가 방향만 바꿔 돌아온다(로드맵 4b 보류).
    static func specialty(for type: PokemonType) -> TownSpecialty {
        switch type {
        case .fire:     .ignition
        case .water:    .watering
        case .grass:    .farming
        case .electric: .generating
        case .ground:   .leveling
        case .flying:   .flight
        case .psychic:  .teleporting
        case .bug:      .honeyGathering
        case .poison:   .recycling
        case .steel:    .cutting
        case .rock:     .polishing
        case .fighting: .crushing
        case .dark:     .messing
        case .ghost:    .exploring
        case .normal:   .sorting
        case .fairy:    .moodMaking
        case .dragon:   .rareHunting
        case .ice:      .yawning
        }
    }

    // MARK: - 서식

    /// 지형별 칸 수. 문턱 판정과 화면 요약이 같은 값을 읽는다.
    static func tileCounts(_ terrain: [TownTerrain]) -> [TownTerrain: Int] {
        terrain.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// 이 마을이 부르는 타입. **문턱을 넘은 지형만** 센다.
    ///
    /// 타입을 훑고 그 타입이 만드는 지형의 칸 수를 본다 — **뒤집은 표를 따로 두지 않는다.**
    /// 표를 둘 두면 "불꽃이 모래를 만드는데 모래는 불꽃을 안 부른다" 같은 어긋남이 생기고,
    /// 표에서 값을 읽는 폴백(`?? []`·`default:`)은 표가 전수라 절대 실행되지 않아 커버리지에
    /// `^0` 으로 영원히 남는다(실측으로 확인하고 이 형태로 바꿨다).
    ///
    /// 여기서 `default: 0` 은 **실제로 실행된다** — 한 칸도 없는 지형이 흔하다.
    static func welcomingTypes(_ terrain: [TownTerrain]) -> Set<PokemonType> {
        let counts = tileCounts(terrain)
        return Set(PokemonType.allCases.filter {
            counts[Self.terrain(for: $0), default: 0] >= habitatThreshold
        })
    }

    /// 이 지형을 만드는 타입들. `terrain(for:)` 을 그 자리에서 뒤집는다 — 저장된 표가 아니라
    /// 파생이라 두 표가 어긋날 수 없다. 화면 안내와 테스트가 쓴다.
    static func typesMaking(_ tile: TownTerrain) -> [PokemonType] {
        PokemonType.allCases.filter { terrain(for: $0) == tile }
    }

    /// 지형 한 줄의 서식 현황. **화면이 자기 계산을 하면 문턱·타입 표가 둘이 된다** —
    /// 배너·현황표·문구가 전부 이 값을 읽는다.
    struct HabitatStatus: Equatable, Identifiable {
        let terrain: TownTerrain
        /// 지금 마을에 깔린 칸 수.
        let tiles: Int
        /// 이 지형이 부르는 타입들. 비지 않는다 — 8지형 전부가 최소 한 타입에서 도달 가능하다
        /// (`PokopiaTownTests` 가 양방향을 못 박는다).
        let types: [PokemonType]

        var id: TownTerrain { terrain }
        /// 문턱을 넘어 실제로 타입을 부르는가.
        var isWelcoming: Bool { tiles >= habitatThreshold }
        /// 문턱까지 남은 칸. 넘었으면 0 — **음수를 주지 않는다**, 화면이 "-14칸 남음" 을 쓴다.
        var remaining: Int { max(0, habitatThreshold - tiles) }
    }

    /// 8지형 전부의 서식 현황. **문턱을 넘은 것을 위로**, 그 안에서 칸이 많은 순이다 —
    /// "지금 무엇이 오고 있나" 가 먼저고 "다음 목표가 무엇인가" 가 그 아래다.
    ///
    /// 칸 수가 같을 때는 `allCases` 순서로 갈린다. 딕셔너리 순회에 맡기면 같은 마을이 열 때마다
    /// 다른 순서로 보인다(`immigrant` 가 후보를 정렬하는 것과 같은 이유).
    static func habitats(_ terrain: [TownTerrain]) -> [HabitatStatus] {
        let counts = tileCounts(terrain)
        return TownTerrain.allCases.enumerated()
            .map { order, tile in
                (order, HabitatStatus(terrain: tile, tiles: counts[tile, default: 0],
                                      types: typesMaking(tile)))
            }
            .sorted { left, right in
                if left.1.isWelcoming != right.1.isWelcoming { return left.1.isWelcoming }
                if left.1.tiles != right.1.tiles { return left.1.tiles > right.1.tiles }
                return left.0 < right.0
            }
            .map(\.1)
    }

    // MARK: - 복합 서식지 (두 서식이 맞닿으면 2타입 종을 먼저 부른다)

    /// 복합 서식지 한 조합. 원작의 "나무 그늘의 풀숲 = 큰 나무 + 초록 풀" 을 격자로 접은 것이다 — 두 지형이
    /// 다 문턱을 넘고 **맞닿아** 있으면 성립한다. **표는 `compositeRecipes` 하나다.**
    ///
    /// 성립 규칙은 대칭이라 `first`·`second` 의 순서는 판정에 뜻이 없다. 화면의 견본 순서와 문장의 타입 순서만
    /// 이 순서를 따른다.
    struct CompositeRecipe: Equatable, Identifiable {
        let name: String
        let first: TownTerrain
        let second: TownTerrain
        /// 이름이 곧 id 다 — 겹치면 현황표 두 줄이 하나로 접힌다(`ForEach` 는 id 가 겹치면 조용히 하나만 그린다).
        /// `testCompositeRecipesAreWellFormed` 가 유일성을 센다.
        var id: String { name }
    }

    /// 복합 서식지 조합표. **여덟 지형이 전부 한 번 이상 든다**(테스트가 센다) — 빠진 지형은 어떤 조합에도 못 끼는
    /// 채 남는다. 원작 250종은 옮기지 않는다: 표가 화면에 안 들어간다. 조합을 더하는 것은 이 배열 한 줄이다.
    ///
    /// 각 조합이 부르는 것은 `typesMaking(first) × typesMaking(second)` 의 **두 타입을 함께 가진 종**이다. 그런 기본형이
    /// 실제 PokéAPI 에 있는지는 여기서 알 수 없다(타입표는 네트워크에서 온다) — 없는 조합은 화면에 "성립" 이 떠도
    /// 아무도 먼저 오지 않는 빈 약속이 된다. 설계 문서의 표가 조합마다 예시 종을 적어 두었다.
    static let compositeRecipes: [CompositeRecipe] = [
        .init(name: "물가 나무",     first: .water,  second: .tree),
        .init(name: "연못 풀숲",     first: .water,  second: .grass),
        .init(name: "꽃밭 물가",     first: .flower, second: .water),
        .init(name: "나무 그늘 풀숲", first: .tree,   second: .grass),
        .init(name: "꽃 핀 풀밭",    first: .flower, second: .grass),
        .init(name: "모래 언덕",     first: .sand,   second: .soil),
        .init(name: "흙 벼랑",       first: .soil,   second: .tree),
        .init(name: "길가 바위",     first: .path,   second: .rock),
    ]

    /// 조합 하나의 현황. `HabitatStatus` 와 같은 자리다 — 화면·이사 판정이 같은 값을 읽는다.
    struct CompositeStatus: Equatable, Identifiable {
        let recipe: CompositeRecipe
        /// 두 지형이 다 문턱을 넘었는가(`HabitatStatus.isWelcoming` 과 같은 판정).
        let bothWelcoming: Bool
        /// 두 지형이 상하좌우로 맞닿은 칸 쌍이 하나라도 있는가.
        let touching: Bool
        var id: String { recipe.id }
        var isFormed: Bool { bothWelcoming && touching }
    }

    /// 두 지형이 **상하좌우**로 맞닿은 칸 쌍이 하나라도 있는가. 대각선은 맞닿음이 아니다. 인자 순서는 답을 바꾸지 않는다.
    ///
    /// **가장자리를 감싸지 않는다.** 평탄 배열에서 15번과 16번은 이웃 첨자지만 화면에서는 오른쪽 끝과 다음 줄 왼쪽 끝이다 —
    /// `here + 1` 로 이웃을 세면 반대편 끝의 물과 나무가 "맞닿은" 것으로 읽힌다. 이웃 좌표는 전부 `index(col:row:)` 를
    /// 지나고, 그 함수가 범위 밖을 nil 로 거절하는 것이 근거다.
    ///
    /// 길이가 틀린 지형(잘린 세이브)은 격자가 아니라 맞닿음도 없다 — 이 가드 덕에 아래 첨자는 전부 안전하다.
    static func touches(_ a: TownTerrain, _ b: TownTerrain, in terrain: [TownTerrain]) -> Bool {
        guard terrain.count == tileCount else { return false }
        for here in terrain.indices {
            let (col, row) = (here % columns, here / columns)
            // 오른쪽·아래만 본다 — 왼쪽·위는 그 칸이 자기 차례에 본다.
            for next in [index(col: col + 1, row: row), index(col: col, row: row + 1)].compactMap({ $0 }) {
                let pair = (terrain[here], terrain[next])
                if pair == (a, b) || pair == (b, a) { return true }
            }
        }
        return false
    }

    /// 조합 여덟의 현황. **성립한 것을 위로**, 그 안에서는 표 순서다 — `habitats(_:)` 와 같은 이유로 순회 순서에 맡기지 않는다.
    static func compositeHabitats(_ terrain: [TownTerrain]) -> [CompositeStatus] {
        let counts = tileCounts(terrain)
        return compositeRecipes.enumerated()
            .map { order, recipe in
                (order, CompositeStatus(
                    recipe: recipe,
                    bothWelcoming: counts[recipe.first, default: 0] >= habitatThreshold
                        && counts[recipe.second, default: 0] >= habitatThreshold,
                    touching: touches(recipe.first, recipe.second, in: terrain)))
            }
            .sorted { left, right in
                if left.1.isFormed != right.1.isFormed { return left.1.isFormed }
                return left.0 < right.0
            }
            .map(\.1)
    }

    // MARK: - 마을 개발도 · 환경 레벨 (지형 다양성이 정원을, 정착이 마지막 레벨을 연다)

    /// 지형 한 종이 문턱을 넘을 때 열리는 주민 자리. **8종 × 2 = 16 = `populationLimit`** 이
    /// 성립해야 한다 — 어긋나면 모든 지형을 다 밀어도 상한에 못 닿거나(영영 안 끝나는 목표),
    /// 절반만 밀어도 상한에 닿는다(다양하게 만들 이유가 사라진다). 테스트가 그 등식을 센다.
    static let residentsPerHabitat = 2

    /// 환경 레벨의 최고치. 원작도 마을당 Lv.1~10 이다. **8 + 2 = 10** — 지형 여덟 종이 Lv.8 까지
    /// 열고, 주민 정착(아래 `development`)이 마지막 두 레벨을 준다. 등식은 테스트가 센다
    /// (`testFullDiversityAndFullSettlementReachTheMaxLevel`) — 어긋나면 Lv.10 이 도달 불가가 되거나
    /// 지형만으로 닿아 주민을 지킬 이유가 사라진다.
    static let maxLevel = 10

    /// 마을 개발도. **파생이다** — 저장 필드가 없다. 지형과 주민만 보면 답이 나오므로 저장하면
    /// 그 둘과 어긋날 수 있는 두 번째 진실이 생긴다(`memory-home-plan.md` 의 원칙).
    struct TownDevelopment: Equatable {
        /// 문턱을 넘은 지형 **종수**(0...8). 타입 수가 아니다 — 보상의 축이 "얼마나 다양한가" 다.
        let habitats: Int
        /// 지금 살 수 있는 주민 수.
        let capacity: Int
        /// 자리를 지키고 있는 주민 수(`isSettled`). 화면이 "정착 s/r" 로 쓴다 — 화면이 세면 술어가 둘이 된다.
        let settled: Int
        /// 환경 레벨 1...`maxLevel`. **두 축**이다 — 지형 종수(축 A)가 레벨 하나씩을 열고, 정착 비율(축 B)이
        /// 위에 최대 둘을 얹는다. 정원(`capacity`)은 축 A 만 본다 — 축 B 가 정원을 열면 주민이 주민을
        /// 부르는 되먹임이 된다. 원작처럼 **내려갈 수 있다** — 지형을 지워 주민이 자리를 잃으면 비율이 떨어진다.
        /// 내려가는 것은 레벨만이다: 정원·주민·`normalized` 는 레벨을 읽지 않는다(자동 퇴거 금지).
        let level: Int
        /// 화면에 쓰는 **레벨 구간** 이름. 숫자만 보여 주면 10이 무엇의 끝인지 읽히지 않는다.
        let name: String
        /// 지금 배부른가(9단계, 축 C). 화면이 "배부른 마을" 을 그리는 술어와 **같은 값**이다.
        let fed: Bool

        /// 꿈섬 전설 다섯 종(`PokopiaTown.dreamIslandSpecies`)이 후보에 드는 조건 — **지형 여덟 종 전부**가 문턱을 넘었다.
        /// 원작은 흔들풍손 특기로 별도 장소(꿈섬)에 가지만 앱엔 장소가 없어 개발도 최고 단계로 접었다.
        ///
        /// 레벨(`level`)이 아니라 종수(`habitats`)를 본다. 여덟 종이면 18 타입이 전부 부르는 타입이라 다섯 종이 단일 판정
        /// (`immigrant` 의 "타입 하나라도 부르는가")을 **자동으로** 통과한다 — 면제 분기가 없다. 레벨 8 은 6종 + 정착으로도
        /// 닿아, 그 마을에서 뮤츠(꽃밭 0칸)는 단일 판정에 막히거나 면제를 받아야 한다. 판정은 이 한 곳이다 — 화면(`legendLine`)과
        /// `immigrant` 가 같은 값을 읽는다.
        var callsLegends: Bool { habitats == TownTerrain.allCases.count }
    }

    /// 이 마을의 개발도. 종수는 `habitats(_:)` 에서 온다 — 현황표와 **같은 판정**을 쓰므로
    /// "부르는 중" 이라 적힌 줄 수와 개발도가 어긋날 수 없다. 정착은 `isSettled` 에서 온다 —
    /// 주민 줄의 붉은 배경과 같은 술어라 "정착 2/3" 와 붉은 줄 수가 어긋날 수 없다.
    ///
    /// `capacity` 를 `populationLimit` 로 클램프한다. 상한은 **여전히 절대 천장**이고,
    /// 개발도는 그 아래에서 열리는 자리를 정한다 — `normalized` 는 개발도를 보지 않는다.
    /// (보면 지형을 지울 때 주민이 잘려 나가고, 그것은 이 기능이 금지한 자동 퇴거다.)
    ///
    /// 축 B 의 두 계단: 주민 **절반 이상**이 정착하면 +1, **정원이 차고 전원** 정착하면 +1 더.
    /// 비율(정착/주민)이지 정원 대비가 아니다 — 주민이 적은 마을과 주민이 불행한 마을은 다른
    /// 상태다. 주민이 없으면 0 이다(0/0 을 만족으로 읽지 않는다). 정수 비교만 쓴다(`settled * 2 >=
    /// residents.count`) — 규칙표에 부동소수를 들이지 않는다.
    /// - Parameter fed: 이 마을이 지금 배부른가(9단계, 축 C). **`Date` 를 받지 않는다** — 이
    ///   함수가 시계를 읽으면 밤에 돌린 CI 만 빨개지고, `Date` 를 인자로 받으면 기존 호출부가
    ///   전부 시각을 들고 다녀야 한다. 판정은 `PokopiaCrafting.isFed(fedUntil:now:)` 하나이고
    ///   여기서는 그 답만 받는다(`townBrush` 가 조립을 한 곳에 모으는 것과 같은 형태다).
    ///
    ///   축 C 는 **천장을 올리지 않는다.** `8 + 2 = maxLevel(10)` 등식은 그대로이고(테스트가
    ///   센다) 포만감은 아래 `min(maxLevel, …)` 에 잘린다 — 지형이 덜 다양한 마을이 같은 레벨에
    ///   닿는 **두 번째 길**이다. 천장을 11 로 올리면 "원작도 Lv.1~10" 근거가 깨지고, 축 B 의
    ///   계단 하나를 뺏어 오면 오늘 Lv.10 인 마을이 요리를 하기 전까지 Lv.9 로 내려간다.
    ///
    ///   `capacity` 는 축 C 를 **안 본다** — 축 B 를 안 보는 이유와 같다(되먹임).
    static func development(_ terrain: [TownTerrain], residents: [TownResident],
                            fed: Bool = false) -> TownDevelopment {
        let count = habitats(terrain).filter(\.isWelcoming).count
        let capacity = min(populationLimit, count * residentsPerHabitat)
        let settled = residents.filter { isSettled($0, terrain: terrain) }.count
        var lift = 0
        if !residents.isEmpty && settled * 2 >= residents.count { lift += 1 }
        if !residents.isEmpty && settled == residents.count && residents.count >= capacity { lift += 1 }
        if fed { lift += 1 }                                        // 축 C — 천장은 아래 min 이 지킨다
        let level = max(1, min(maxLevel, count + lift))
        let name: String
        switch level {
        case 1:     name = "빈 터"
        case 2...3: name = "작은 마을"
        case 4...5: name = "마을"
        case 6...7: name = "큰 마을"
        default:    name = "포코피아"     // 8...maxLevel
        }
        return TownDevelopment(habitats: count, capacity: capacity, settled: settled,
                               level: level, name: name, fed: fed)
    }

    // MARK: - 꿈섬 전설 (지형 여덟 종이 다 되면 다섯 종이 먼저 온다)

    /// 꿈섬 손님 다섯 종 — 뮤츠(150)·라이코(243)·앤테이(244)·스이쿤(245)·피오네(489). 원작 위키(2026-09-08 fetch)의 목록이다.
    /// **표는 이 파일 하나다**(`terrain(for:)`·`compositeRecipes` 와 같은 규칙). 이름은 적지 않는다 — 도착할 때 PokéAPI
    /// 라인에서 받아 `TownResident.name` 에 저장한다(주민 이름의 유일한 출처).
    ///
    /// **다섯 종은 원래부터 이사 풀에 있다.** 풀은 `BaseSpecies.hatchable(index)` 이고 base 인덱스는 `evolves_from IS NULL`
    /// 전부라 전설을 거르지 않는다(`is_legendary` 가 인덱스에 없다 — `StarterRules.legendaryExclusions` 가 id 로 거르는 이유와
    /// 같다). 그래서 이 표의 일은 **더하기가 아니라 막기와 순서**다: 여덟 종 미만이면 후보에서 빼고(라이코는 전기라 1일차 길 줄
    /// 16칸에도 온다), 여덟 종이면 복합보다 먼저 뽑는다. 그 밖의 전설(루기아·칠색조·뮤 …)은 이 표에 없고 오늘과 같이 단일 풀에
    /// 남는다 — 전설 전부를 가르려면 인덱스에 플래그를 실어야 하고, 그것은 디스크 캐시 형태를 바꾸는 별도 결정이다.
    ///
    /// `RaidBoss.legendarySpeciesPool`(10종)을 재사용하지 않는다 — 레이드 보스 큐레이션이고 다섯 종과 셋만 겹친다. 이름을
    /// `legendary…` 로 짓지 않은 이유도 같다: "전설 전부" 로 읽혀 누가 루기아를 더한다. 다섯 종 전부 `hasAnimatedSprite` 를
    /// 통과한다(`testDreamIslandGuestsSurviveNormalization`) — 통과 못 하는 종은 도착해도 다음 실행의 정규화에서 사라진다.
    static let dreamIslandSpecies: [Int] = [150, 243, 244, 245, 489]

    /// 아직 안 온(살고 있지 않은) 꿈섬 손님. 화면의 "N종이 먼저 찾아와요" 가 읽는다. `immigrant` 는 후보(이미 사는 종을 뺀 것)에서
    /// 같은 표를 거르므로 두 값은 같다 — 화면이 자기 계산을 하면 표가 둘이 된다. 내보낸 종은 다시 여기 든다(같은 종은 살고 있을
    /// 때만 안 온다).
    static func awaitingLegends(_ residents: [TownResident]) -> [Int] {
        let living = Set(residents.map(\.speciesID))
        return dreamIslandSpecies.filter { !living.contains($0) }
    }

    /// 이번 세션에 찾아올 종. **순수 함수다** — 판정과 발송(알림)을 가른다.
    ///
    /// 후보를 **정렬한다**. 집합·딕셔너리 순회 순서는 실행마다 달라서, 정렬하지 않으면 같은
    /// 시드가 다른 종을 뽑는다(`docs/reference/defect-log.md` 의 "테스트가 시스템 RNG 를
    /// 밟고 있는 부류").
    ///
    /// 후보가 없으면 nil 이고, **그때도 호출부는 굴림을 소비해야 한다** — 조건부로 굴리면
    /// 같은 시드가 마을 상태에 따라 다른 미래를 낸다.
    ///
    /// **복합 서식지는 순서만 바꾼다.** 성립한 조합(`compositeHabitats`)의 두 지형을 모두 만드는 종이 후보에
    /// 남아 있으면 그중에서 뽑고, 없으면 후보 전체에서 뽑는다. 복합 후보는 늘 단일 후보의 **부분집합**이다 —
    /// 두 지형이 다 문턱을 넘었으니 그 타입은 이미 부르는 타입이다. 그래서 "후보를 더한다" 가 아니라 "먼저 뽑는다" 이고,
    /// 정원(`capacity`)·굴림 소비는 건드리지 않는다.
    ///
    /// **꿈섬 전설은 막기와 순서다.** 다섯 종(`dreamIslandSpecies`)은 원래 풀에 있다 — 지형 여덟 종 미만이면 후보에서 **빼고**,
    /// 여덟 종이면(`callsLegends`) 안 온 종이 남아 있는 한 그중에서 **먼저** 뽑는다. 전설 > 복합 > 단일. 다섯이 다 왔으면 복합·
    /// 단일로 떨어진다. 여덟 종이면 18 타입이 전부 부르는 타입이라 단일 판정을 자동 통과한다 — 면제 분기가 없다.
    static func immigrant(terrain: [TownTerrain], pool: [Int],
                          typeIndex: [Int: [PokemonType]],
                          residents: [TownResident], roll: UInt64) -> Int? {
        // **정원은 개발도가 정한다** — `populationLimit` 은 절대 천장이고, 지형을 다양하게
        // 만들지 않으면 그 천장까지 열리지 않는다. 풀 172칸짜리 마을이 16마리를 다 받으면
        // "다양하게 만들 이유" 가 없어진다.
        let development = Self.development(terrain, residents: residents)
        guard residents.count < development.capacity else { return nil }
        let welcoming = welcomingTypes(terrain)
        guard !welcoming.isEmpty else { return nil }
        let living = Set(residents.map(\.speciesID))
        // 꿈섬 손님은 지형 여덟 종이 다 될 때까지 후보에서 **뺀다** — 단일 판정만으로는 라이코(전기·길)가 1일차에 온다.
        let legends = Set(dreamIslandSpecies)
        // 단일 서식 — 안 사는 종 · 타입표에 있는 종 · 타입 하나라도 부르는 지형이 있는 종. 판정은 전과 같고, 타입을
        // **함께 들고 가는 것**만 바뀌었다: 아래 복합 판정이 같은 값을 읽는다. 여기서 버리고 다시 조회하면 `?? []` 폴백이
        // 생기고 그 분기는 절대 돌지 않는다(`welcomingTypes` 주석의 `^0` 부류).
        let candidates = pool.compactMap { id -> (id: Int, types: [PokemonType])? in
            guard !living.contains(id), let types = typeIndex[id],
                  types.contains(where: { welcoming.contains($0) }),
                  development.callsLegends || !legends.contains(id) else { return nil }
            return (id, types)
        }.sorted { $0.id < $1.id }
        guard !candidates.isEmpty else { return nil }
        // 꿈섬 손님이 후보에 남아 있으면 그중에서 **먼저** 뽑는다 — 복합보다 앞이다. 여덟 종 미만에서는 위 가드가 비워
        // 두므로 이 배열은 `callsLegends` 일 때만 비지 않는다. 다섯이 다 왔으면 아래 복합 → 단일로 떨어진다.
        let legendDraw = candidates.filter { legends.contains($0.id) }
        // 복합 서식 — 성립한 조합의 두 지형을 **모두** 만드는 종이 남아 있으면 그중에서 먼저 뽑는다. 단일 후보는 그대로
        // 남는다: 복합 후보가 없을 때(미성립 · 그 종이 다 왔음) 그리로 떨어진다.
        let formed = compositeHabitats(terrain).filter(\.isFormed).map(\.recipe)
        let preferred = candidates.filter { candidate in
            let homes = homeTerrains(of: candidate.types)
            return formed.contains { homes.contains($0.first) && homes.contains($0.second) }
        }
        let draw = !legendDraw.isEmpty ? legendDraw : (preferred.isEmpty ? candidates : preferred)
        return draw[Int(roll % UInt64(draw.count))].id
    }

    // MARK: - 변신 = 브러시

    /// 지금 밀 수 있는 지형. **변신하지 않으면 nil** — 변신이 유일한 도구라는 규칙이
    /// 이 함수 하나에 있다. 화면이 자기 판정을 더하면 표가 둘이 된다.
    static func brush(dittoFormTypes: [PokemonType]?) -> TownTerrain? {
        dittoFormTypes?.first.map(terrain(for:))
    }

    // MARK: - 주민 자리 (파생)

    /// 주민이 오늘 서 있는 칸. **자기 타입들이 부르는 지형 위**를 고른다 — 물 타입이 모래에 서
    /// 있으면 "이 마을이 마음에 들어서 왔다" 가 화면에서 거짓이 된다.
    ///
    /// 그 지형들이 모두 마을에 없으면(사용자가 없앴다) 길 줄을 뺀 격자 전체에서 고른다 —
    /// 주민을 화면에서 지우지 않는다. 자동 퇴거는 사용자가 이해할 수 없는 상실이다.
    ///
    /// **저장 필드가 없다.** `hashValue` 를 쓸 수 없다: Swift 해시는 프로세스마다 시드가 달라
    /// 앱을 재시작하면 같은 날의 답이 바뀐다(`MemoryHomeCompanionTrace` 가 같은 이유로
    /// 스칼라 합을 쓴다).
    static func residentSpot(_ resident: TownResident, terrain: [TownTerrain],
                             dayKey: String) -> (col: Int, row: Int) {
        let seed = "\(resident.speciesID)-\(dayKey)".unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let homes = homeTerrains(resident)
        let onHome = residentSpotIndices.filter { index in
            terrain.indices.contains(index) && homes.contains(terrain[index])
        }
        // `residentSpotIndices` 는 176칸이라 비지 않는다 — 0으로 나누는 길이 없다.
        let pool = onHome.isEmpty ? residentSpotIndices : onHome
        let index = pool[seed % pool.count]
        return (col: index % columns, row: index / columns)
    }

    /// 타입 목록이 만드는 지형. **순서를 지키고 중복을 뺀다** — 땅·바위 종은 둘 다 흙이라 하나다.
    /// `Set` 을 쓰면 순서가 실행마다 바뀌어 `settledTerrain` 의 답이 흔들린다.
    /// 주민(`homeTerrains(_:)`)과 이사 후보(`immigrant` 의 복합 판정)가 **같은 사상**을 읽는다 — 두 번 적으면 어긋난다.
    static func homeTerrains(of types: [PokemonType]) -> [TownTerrain] {
        var out: [TownTerrain] = []
        for type in types {
            let tile = terrain(for: type)
            if !out.contains(tile) { out.append(tile) }
        }
        return out
    }

    /// 주민의 타입들이 만드는 지형. `homeTerrains(of:)` 를 주민의 타입으로 부른다.
    static func homeTerrains(_ resident: TownResident) -> [TownTerrain] { homeTerrains(of: resident.types) }

    /// 주민의 특기 — **첫 타입**의 것이다. 지형(`settledTerrain`)은 "그 지형이 마을에 있는가" 라 두 타입을 다 봐야 했지만,
    /// 특기는 마을 상태가 아니라 종의 정체라 주 타입 하나가 답이다(물·비행 갈모매의 특기는 급수다). 타입이 없는 주민은
    /// `nil` — `normalized` 가 막지만 순수 함수는 어떤 입력에도 안전해야 한다(`residentSpot` 이 같은 입력을 받는다).
    static func specialty(of resident: TownResident) -> TownSpecialty? {
        resident.types.first.map(specialty(for:))
    }

    /// 주민을 **정착시킨 지형** — 자기 지형 중 문턱을 넘은 첫 것. `nil` 이면 자리를 잃은 주민이다.
    /// 자리(`residentSpot`)·정착(`isSettled`)·문구(`PokopiaTownLife`)·주민 줄(`residentRow`)이
    /// 전부 이 값을 읽는다. 네 자리가 각자 첫 타입 하나만 읽던 동안 2타입 종은 두 번째 타입의
    /// 지형이 넉넉해도 "살던 자리를 찾는 중" 이었고, 정착해도 첫 타입 지형의 문장을 말했다.
    static func settledTerrain(_ resident: TownResident, terrain: [TownTerrain]) -> TownTerrain? {
        let counts = tileCounts(terrain)
        return homeTerrains(resident).first { counts[$0, default: 0] >= habitatThreshold }
    }

    /// 주민이 원하던 환경이 아직 마을에 있는가. 화면 문구가 이 값으로 갈린다.
    static func isSettled(_ resident: TownResident, terrain: [TownTerrain]) -> Bool {
        settledTerrain(resident, terrain: terrain) != nil
    }

    // MARK: - 신뢰경계

    /// 세이브·전송에서 온 못 믿을 마을. 신뢰경계 검증기는 **자기가 말한 필드를 다 봐야** 한다.
    ///
    /// 인자가 없다. 이전 판은 유효 개체 목록을 받았는데, 주민이 소유 개체가 아니게 되면서
    /// **외부 지식이 필요 없어졌다** — 그래서 "이 자리에서는 모른다" 를 명시할 통과 인자도
    /// 사라졌다. 부르는 세 자리(파일 열기·`prune`·`replace`)가 전부 같은 한 줄이다.
    /// 주민 **하나**가 마을에 있을 수 있는가. 종 id 는 양수이고 그릴 수 있어야 하며, 이름이
    /// 빈 주민은 화면에서 결함처럼 보이는 줄이 되므로 아예 받지 않는다.
    ///
    /// **받는 자리(`admitTownResident`)와 거르는 자리(`normalized`)가 같은 술어를 쓴다.** 조건을
    /// 두 자리에 각각 적어 두었을 때 스프라이트 검사가 받는 자리에만 빠져 있었다 — 그 경로로
    /// 들어온 주민은 저장되고 다음 실행의 정규화에서 소리 없이 사라진다(`defect-log.md` 의
    /// "신뢰경계 검사를 한 경로에만 두면 형제 경로가 무검사로 남는다" 부류). 중복·인구 상한은
    /// **집합**의 성질이라 여기 없다 — 각 자리가 자기 집합을 보고 판단한다.
    static func isAdmissible(_ resident: TownResident) -> Bool {
        resident.speciesID > 0
            && PokemonAssets.hasAnimatedSprite(speciesID: resident.speciesID)
            && !resident.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !resident.types.isEmpty
    }

    static func normalized(_ state: PokopiaTownState, region: TownRegion) -> PokopiaTownState {
        var out = state

        // 길이가 틀리면 **그 지역의** 기본 지형으로 되돌린다. 잘라 쓰거나 채워 쓰면 격자가 한 칸씩
        // 밀린 채로 남아, 화면은 그려지는데 사용자가 민 자리와 다른 곳이 바뀐다. 전역 기본으로
        // 되돌리면 해안이 풀밭이 되어 사용자가 만들지도 않은 바탕이 남는다.
        if out.terrain.count != tileCount { out.terrain = defaultTerrain(for: region) }

        var seen = Set<Int>()
        out.residents = out.residents
            .filter { isAdmissible($0) && seen.insert($0.speciesID).inserted }
            .prefix(populationLimit).map { $0 }

        // 변신 대상은 양수만 본다. 도감 대조는 쓰기 자리(`setDittoForm`)가 한다 — 앨범은
        // 도감을 들고 있지 않고, 등록 안 된 종으로 남은 변신은 브러시가 한 종류 다른 것뿐이다.
        if let form = out.dittoForm, form <= 0 { out.dittoForm = nil }

        // `fedUntil` 은 **여기서 안 자른다.** 이 함수는 `now` 를 모르고, 시계를 들이면 신뢰경계가
        // 실행 시각에 따라 다른 답을 낸다. 먼 미래는 **읽는 자리**가 거짓으로 만든다
        // (`PokopiaCrafting.isFed` 의 `<= now + maxSatiety`). 읽는 자리가 하나라서 성립하는
        // 형태다 — 두 번째 독자가 생기면 그때 이 판단을 다시 한다.

        return out
    }

    /// 포코피아 전체의 신뢰경계. **모르는 지역 키를 버린다** — 손으로 고친 세이브나 옛 전송이
    /// 담아 온 키가 지역 여섯 번째로 화면에 뜨지 않게 한다. 마을마다의 검사는 위 `normalized` 가
    /// 그대로 하고, 여기서 딴 검사를 쓰면 한 경로에만 검사를 두는 부류가 된다.
    ///
    /// **전역 상한(`globalPopulationLimit`)을 여기서 적용하지 않는다.** 이 함수는 배열을 자르는
    /// 자리이고, 전역 상한을 자르기로 강제하면 지역을 옮길 때마다 주민이 사라진다 — 받는 자리
    /// (`admitTownResident`)가 거절하는 것이 맞는 형태다(정원을 여기 안 넣는 이유와 같다).
    static func normalized(_ state: PokopiaState) -> PokopiaState {
        var out = state
        out.towns = state.towns.reduce(into: [:]) { result, entry in
            guard let region = TownRegion(rawValue: entry.key) else { return }
            result[entry.key] = normalized(entry.value, region: region)
        }
        return out
    }
}
