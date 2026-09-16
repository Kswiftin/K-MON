import Foundation

/// 마을의 네임드 NPC 여섯. 원작 《Pokémon Pokopia》의 이름 있는 이웃들이다.
///
/// **주민이 아니다.** 이사 풀에서 오지 않고(여섯 중 넷은 base 종이 아니라 애초에 풀에 없다),
/// 정원·인구 상한을 먹지 않고, 세이브에 한 글자도 안 들어간다. 지금 마을 상태에서 파생하는
/// 해금 게이트 여섯으로 등장한다 — 그래서 `rawValue`·`Codable` 이 없다(`TownSpecialty` 와 같은
/// 이유: 세이브에 안 들어가는 식별자를 동결할 이유가 없다).
///
/// **특기가 타입 파생이 아니다.** 4단계가 옮긴 18 특기는 타입마다 하나지만, 이 여섯의 특기
/// (감정·페인팅·DJ·파티·장인·발광)는 타입에 붙일 근거가 없다 — 그래서 NPC 에 직접 붙는다
/// (`docs/reference/pokopia-town-design.md` 의 특기 절).
///
/// 종 번호는 원작 위키(namu.wiki 《Pokémon Pokopia》 본문·등장 포켓몬·특기, 2026-09-16 fetch)와
/// 전국도감(poke-korea.com, 같은 날 확인)에서 왔다. **표는 이 파일 하나다**
/// (`PokopiaTown.dreamIslandSpecies` 와 같은 규칙).
///
/// 이름은 **적는다.** 주민 이름은 도착할 때 PokéAPI 에서 받아 저장하지만(그래서
/// `dreamIslandSpecies` 는 이름을 안 적는다), NPC 이름은 종 이름이 아니라 직함이고
/// ("덩쿠림보 박사") PokéAPI 에 그 값이 없다.
enum TownNPC: Sendable, Hashable, CaseIterable, Identifiable {
    case professor, painter, dj, chef, artisan, glow

    var id: Self { self }

    /// 화면에 쓰는 이름. 받침이 갈리므로 **뒤에 조사를 붙이지 않는다**
    /// (`PokopiaParticleGuardTests` — 덩쿠림보·로토무·카츄는 받침이 없고 셰프·거장은 있다).
    var name: String {
        switch self {
        case .professor: "덩쿠림보 박사"
        case .painter:   "루브도 선생"
        case .dj:        "DJ 로토무"
        case .chef:      "요씽셰프"
        case .artisan:   "두드리짱 거장"
        case .glow:      "창백카츄"
        }
    }

    /// 특기 이름. 원작 표기 그대로다 — 4단계가 옮기지 않은 여섯이 여기 있다.
    var specialtyName: String {
        switch self {
        case .professor: "감정"
        case .painter:   "페인팅"
        case .dj:        "DJ"
        case .chef:      "파티"
        case .artisan:   "장인"
        case .glow:      "발광"
        }
    }

    /// 그릴 종. 여섯 전부 `PokemonAssets.hasAnimatedSprite` 를 통과한다
    /// (`testEverySpeciesIDSurvivesTheSpriteCheck` 가 센다) — 통과 못 하는 종은 화면에서 빈다.
    ///
    /// 창백카츄는 **창백한 색 피카츄**지만 앱에 그 팔레트가 없어 보통 피카츄가 선다.
    /// `isShiny` 로 대신하지 않는다 — 이로치는 이 앱에서 다른 뜻을 가진 표시다.
    var speciesID: Int {
        switch self {
        case .professor: 465     // 덩쿠림보
        case .painter:   235     // 루브도
        case .dj:        479     // 로토무
        case .chef:      820     // 요씽리스
        case .artisan:   959     // 두드리짱
        case .glow:      25      // 피카츄
        }
    }

    /// 잠겼을 때의 한 줄 — **무엇을 하면 되는가**를 담는다(`PokopiaTownLife.emptyLine` 과 같은 규칙).
    var unlockHint: String {
        switch self {
        case .professor: "주민이 한 명이라도 살면 찾아와요"
        case .painter:   "지형 \(PokopiaTownNPC.painterHabitats)종을 만들면 찾아와요"
        case .dj:        "복합 서식지가 한 곳이라도 성립하면 찾아와요"
        case .chef:      "조리대를 만들면 찾아와요"
        case .artisan:   "용광로를 만들면 찾아와요"
        case .glow:      "지형 \(TownTerrain.allCases.count)종을 모두 만들면 찾아와요"
        }
    }

    /// 해금됐을 때의 한 줄. **효과가 있는 셋은 그 효과를 말한다** — 나머지 셋은 앱에 대응 동사가
    /// 없어(유실물·가구 염색·음원) 문구만 갖는다. 4단계가 특기 32종 중 14종을 문구로도 안 옮긴
    /// 것과 같은 선이다.
    var unlockedLine: String {
        switch self {
        case .professor: "마을에 자리를 잡고 유실물을 살펴봐요"
        case .painter:   "마을 여기저기에 색을 입히고 다녀요"
        case .dj:        "오늘 틀 곡을 고르고 있어요"
        case .chef:      "요리가 마을을 더 오래 먹여요"
        case .artisan:   "만드는 시간이 줄어요"
        case .glow:      "밤에도 마을이 낮처럼 밝아요"
        }
    }
}

/// NPC 의 게이트·자리·배율 전부. **판정 축을 인자로 받는다** — 설비 보유는 `Bool` 이고 이 파일은
/// `PokopiaCrafting` 을 부르지 않는다(`PokopiaTown.development(_:residents:fed:)` 가 `fed` 를 받는
/// 것과 같은 형태). 축이 섞이면 "내가 만들어서 왔다" 가 다른 축에 덮인다 —
/// `PokopiaCraftingTests` 의 소스 가드 **셋**이 양방향으로 센다.
///
/// 파일 이름이 `Pokopia` 로 시작하는 것은 취향이 아니다 — 조사 가드(`PokopiaParticleGuardTests`)가
/// 그 접두를 가진 파일만 훑는다.
enum PokopiaTownNPC {

    /// 루브도 선생이 오는 지형 종수. **서식 판정이 읽는 값이 아니라** 이 표만의 문턱이라
    /// `PokopiaTown` 이 아니라 여기 산다. 8종의 절반보다 하나 위다 — 절반(4)이면 1일차 마을에서
    /// 곧바로 열리고, 7이면 창백카츄(8종)와 구별이 안 된다.
    static let painterHabitats = 5

    /// 만드는 시간을 줄이는 비율의 분모·분자. 정수 나눗셈만 쓴다 — 규칙표에 부동소수를 안 들인다
    /// (`development` 의 `settled * 2 >= residents.count` 와 같은 선).
    static let artisanNumerator = 3
    static let artisanDenominator = 4

    /// 포만감을 늘리는 비율. 같은 이유로 정수다.
    static let chefNumerator = 3
    static let chefDenominator = 2

    /// 지금 이 마을에 있는 NPC. **파생이다** — 저장 필드가 없다. 그래서 지형을 지워 조건이 깨지면
    /// 다시 잠긴다(환경 레벨이 내려가는 것과 같은 선, `PokopiaTown.swift:471-472`). 주민과 다르다 —
    /// 주민은 자동 퇴거가 금지지만 NPC 는 소유가 아니다.
    ///
    /// - Parameters:
    ///   - hasKitchen: 조리대(`ItemKind.townKitchen`)를 갖고 있는가. **`PokopiaCrafting` 을 부르지
    ///     않는다** — 부르면 축이 섞이고 소스 가드가 빨개진다. 조립은 호출부(`CompanionStore.townNPCs`)
    ///     한 곳이다.
    ///   - hasFurnace: 용광로(`ItemKind.townFurnace`)를 갖고 있는가.
    ///
    /// **설비 둘은 전역이다**(`state.inventory`). 마을 다섯 채가 같은 조리대를 보므로 요씽셰프와
    /// 두드리짱은 다섯 마을에 동시에 선다 — 지형·주민 게이트 넷은 마을마다 갈린다. 의도한
    /// 비대칭이다: 설비는 소유물이고 지형은 그 마을의 것이다.
    static func unlocked(terrain: [TownTerrain], residents: [TownResident],
                         hasKitchen: Bool, hasFurnace: Bool) -> Set<TownNPC> {
        // 개발도를 **한 번만** 센다 — 두 게이트가 각자 부르면 192칸 집계가 두 번 돈다.
        // `fed` 는 기본값(false) 그대로다: 축 C 는 이 표가 읽는 값이 아니다.
        let development = PokopiaTown.development(terrain, residents: residents)
        var open: Set<TownNPC> = []
        if !residents.isEmpty { open.insert(.professor) }
        if development.habitats >= painterHabitats { open.insert(.painter) }
        if PokopiaTown.compositeHabitats(terrain).contains(where: \.isFormed) { open.insert(.dj) }
        if hasKitchen { open.insert(.chef) }
        if hasFurnace { open.insert(.artisan) }
        if development.callsLegends { open.insert(.glow) }
        return open
    }

    /// NPC 가 서는 칸. `PokopiaTown.residentSpot` 을 **복사하지 않는다** — 그 함수는
    /// `homeTerrains(resident)` 로 지형을 거르는데 NPC 는 타입이 없다(주민이 아니다).
    ///
    /// `hashValue` 를 **쓸 수 없다** — Swift 의 해시는 프로세스마다 시드가 달라 앱을 재시작하면
    /// 같은 날의 자리가 바뀐다(`TownWeather.today` 가 스칼라 합을 쓰는 이유와 같다).
    ///
    /// 주민과 자리가 겹칠 수 있다. 막지 않는다 — 주민끼리도 이미 겹친다(`residentSpot` 이 중복을
    /// 안 본다). 막으려면 배치가 순서에 의존하게 되고, 그러면 NPC 하나가 해금될 때 나머지가 전부
    /// 움직인다.
    static func spot(_ npc: TownNPC, dayKey: String) -> (col: Int, row: Int) {
        let seed = "npc-\(npc.speciesID)-\(dayKey)".unicodeScalars.reduce(0) { $0 + Int($1.value) }
        // `residentSpotIndices` 는 176칸이라 비지 않는다 — 0으로 나누는 길이 없다.
        let pool = PokopiaTown.residentSpotIndices
        let index = pool[seed % pool.count]
        return (col: index % PokopiaTown.columns, row: index / PokopiaTown.columns)
    }

    /// 두드리짱 거장이 있을 때 줄어드는 제작 시간(분). **0 분이 되지 않는다** — 0 이면 걸자마자
    /// 다 된 것이 되어 "기다림 하나" 라는 9단계의 의도가 사라진다.
    static func craftMinutes(_ minutes: Int, artisan: Bool) -> Int {
        guard artisan else { return minutes }
        return max(1, minutes * artisanNumerator / artisanDenominator)
    }

    /// 요씽셰프가 있을 때 늘어나는 포만감 시간. **상한을 여기서 걸지 않는다** —
    /// `PokopiaCrafting.fedUntil` 이 `maxSatiety` 로 자르고, 읽는 자리가 하나여야 "배부른 마을" 이라
    /// 적힌 줄과 환경 레벨이 어긋나지 않는다.
    static func satietyHours(_ hours: Int, chef: Bool) -> Int {
        guard chef else { return hours }
        return max(hours, hours * chefNumerator / chefDenominator)
    }
}
