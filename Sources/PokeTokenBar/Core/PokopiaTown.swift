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

/// 마을 상태 전부. `MemoryHomeAccessSettings.town` **한 키**에 들어간다.
///
/// 필드가 셋뿐이다. 아바타 자리·주민 자리·화면 문구는 **전부 파생**이라 저장하지 않는다
/// (`docs/reference/memory-home-plan.md` 의 "새 저장 필드를 만들지 않는다" 원칙을 지킬 수
/// 있는 만큼 지킨 형태다 — 지형·변신·주민만 사용자 의도라 저장을 피할 수 없다).
struct PokopiaTownState: Codable, Sendable, Equatable {
    /// 행 우선 평탄 배열, 길이 `PokopiaTown.tileCount`. 2차원 배열로 두면 JSON 이 중첩되고
    /// 길이 검증이 두 축이 된다.
    var terrain: [TownTerrain] = PokopiaTown.defaultTerrain
    /// 변신 중인 종 id. **nil 이면 아무것도 밀 수 없다** — 변신이 유일한 도구다.
    var dittoForm: Int?
    /// 도착 순서를 지킨다 — 상한에 걸릴 때 누가 남는지가 실행마다 바뀌면 안 된다.
    var residents: [TownResident] = []
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

    /// 한 지형이 타입을 부르기 시작하는 칸 수. 6칸은 한 줄(16칸)의 3분의 1 남짓이다 —
    /// 실수로 두 칸 밀었다고 포켓몬이 오면 "내가 만들어서 왔다" 가 아니라 우연이 된다.
    ///
    /// **기본 지형이 이미 풀 176칸이라 새 마을도 풀·벌레를 부른다.** 의도다 — 1일차 마을이
    /// 아무도 부르지 않으면 첫 세션의 이사 판정이 영영 빈손이고, 사용자는 이 기능이 도는지도
    /// 모른다. 문턱을 올려 막으려 하면 반대로 6칸을 밀어도 아무 일이 없어진다.
    static let habitatThreshold = 6

    /// 편집 되돌리기 깊이. 방 편집(`beginRoomEdit`)과 같은 값이다 — 두 편집기의 감각이
    /// 다르면 사용자가 어느 쪽에서 몇 번 되돌릴 수 있는지 알 수 없다.
    static let undoDepth = 30

    /// 첫 마을. 전부 풀이고 맨 아래 줄만 길이다 — 빈 격자로 열면 "아직 아무것도 아닌 화면" 이
    /// 되고, 길이 있으면 그 자체로 장소로 읽힌다. 그 줄은 아바타가 서는 자리이기도 하다.
    static let defaultTerrain: [TownTerrain] = (0..<tileCount).map {
        $0 / columns == rows - 1 ? .path : .grass
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
    static func development(_ terrain: [TownTerrain], residents: [TownResident]) -> TownDevelopment {
        let count = habitats(terrain).filter(\.isWelcoming).count
        let capacity = min(populationLimit, count * residentsPerHabitat)
        let settled = residents.filter { isSettled($0, terrain: terrain) }.count
        var lift = 0
        if !residents.isEmpty && settled * 2 >= residents.count { lift += 1 }
        if !residents.isEmpty && settled == residents.count && residents.count >= capacity { lift += 1 }
        let level = max(1, min(maxLevel, count + lift))
        let name: String
        switch level {
        case 1:     name = "빈 터"
        case 2...3: name = "작은 마을"
        case 4...5: name = "마을"
        case 6...7: name = "큰 마을"
        default:    name = "포코피아"     // 8...maxLevel
        }
        return TownDevelopment(habitats: count, capacity: capacity, settled: settled, level: level, name: name)
    }

    /// 이번 세션에 찾아올 종. **순수 함수다** — 판정과 발송(알림)을 가른다.
    ///
    /// 후보를 **정렬한다**. 집합·딕셔너리 순회 순서는 실행마다 달라서, 정렬하지 않으면 같은
    /// 시드가 다른 종을 뽑는다(`docs/reference/defect-log.md` 의 "테스트가 시스템 RNG 를
    /// 밟고 있는 부류").
    ///
    /// 후보가 없으면 nil 이고, **그때도 호출부는 굴림을 소비해야 한다** — 조건부로 굴리면
    /// 같은 시드가 마을 상태에 따라 다른 미래를 낸다.
    static func immigrant(terrain: [TownTerrain], pool: [Int],
                          typeIndex: [Int: [PokemonType]],
                          residents: [TownResident], roll: UInt64) -> Int? {
        // **정원은 개발도가 정한다** — `populationLimit` 은 절대 천장이고, 지형을 다양하게
        // 만들지 않으면 그 천장까지 열리지 않는다. 풀 172칸짜리 마을이 16마리를 다 받으면
        // "다양하게 만들 이유" 가 없어진다.
        guard residents.count < development(terrain, residents: residents).capacity else { return nil }
        let welcoming = welcomingTypes(terrain)
        guard !welcoming.isEmpty else { return nil }
        let living = Set(residents.map(\.speciesID))
        let candidates = pool.filter { id in
            guard !living.contains(id) else { return false }
            return typeIndex[id]?.contains(where: { welcoming.contains($0) }) ?? false
        }.sorted()
        guard !candidates.isEmpty else { return nil }
        return candidates[Int(roll % UInt64(candidates.count))]
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

    /// 주민의 타입들이 만드는 지형. **`types` 순서를 지키고 중복을 뺀다** — 땅·바위 종은 둘 다
    /// 흙이라 하나다. `Set` 을 쓰면 순서가 실행마다 바뀌어 `settledTerrain` 의 답이 흔들린다.
    static func homeTerrains(_ resident: TownResident) -> [TownTerrain] {
        var out: [TownTerrain] = []
        for type in resident.types {
            let tile = terrain(for: type)
            if !out.contains(tile) { out.append(tile) }
        }
        return out
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

    static func normalized(_ state: PokopiaTownState) -> PokopiaTownState {
        var out = state

        // 길이가 틀리면 기본 지형으로 되돌린다. 잘라 쓰거나 채워 쓰면 격자가 한 칸씩 밀린
        // 채로 남아, 화면은 그려지는데 사용자가 민 자리와 다른 곳이 바뀐다.
        if out.terrain.count != tileCount { out.terrain = defaultTerrain }

        var seen = Set<Int>()
        out.residents = out.residents
            .filter { isAdmissible($0) && seen.insert($0.speciesID).inserted }
            .prefix(populationLimit).map { $0 }

        // 변신 대상은 양수만 본다. 도감 대조는 쓰기 자리(`setDittoForm`)가 한다 — 앨범은
        // 도감을 들고 있지 않고, 등록 안 된 종으로 남은 변신은 브러시가 한 종류 다른 것뿐이다.
        if let form = out.dittoForm, form <= 0 { out.dittoForm = nil }
        return out
    }
}
