import Foundation

/// 마을에서 **만드는 것**의 규칙 전부. 표는 여기 하나다 — 화면·가방·상점·터미널·테스트가 같은
/// 값을 읽는다(`PokopiaTown` 이 지형·서식 표를 한 파일에 두는 것과 같은 규칙).
///
/// **판정 세 축을 모른다.** 서식 문턱·이사·정원·복합·전설은 이 파일을 부르지 않고, 이 파일도
/// 그것들을 부르지 않는다. 포만감이 이사에 끼면 "내가 만들어서 왔다" 가 요리라는 다른 축에
/// 덮인다 — 날씨를 문구 전용으로 둔 것과 같은 판단이다. 주석은 다음 사람이 지울 수 있으므로
/// **소스 가드 둘**(`PokopiaCraftingTests`)이 양방향으로 센다.
///
/// 재료는 **상점에서만** 온다. 세션 보상은 지운 티켓 경제와 구조가 같고(`docs/reference/
/// pokopia-town-design.md` 의 티켓 절), 주민 특기 파생은 로드맵이 4b 로 보류한 "특기 → 보상"
/// 그대로다. 지갑은 `starPieces` 하나이고 두 번째 화폐를 만들지 않는다.
///
/// 파일 이름이 `Pokopia` 로 시작하는 것은 취향이 아니다 — 조사 가드(`PokopiaParticleGuardTests`)가
/// 그 접두를 가진 파일만 훑는다.
enum PokopiaCrafting {

    // MARK: - 무엇이 무엇인가 (세 목록)

    /// 상점에서 사는 재료 10종.
    ///
    /// **열 종 전부가 최소 한 레시피에 쓰인다** — 테스트가 센다. 안 쓰이는 재료는 사는 순간
    /// 별의조각을 버리는 함정 구매가 된다(`ItemKind` 의 진화 아이템 주석이 "대상 종이 획득 가능
    /// 목록 안에 있어야 한다" 를 같은 이유로 못 박는다).
    static let materials: [ItemKind] = [
        .townWood, .townStone, .townClay, .townSandGrain, .townSpringWater,
        .townPetal, .townHerb, .townFruit, .townHoney, .townOre,
    ]

    /// 설비 3종. **격자에 놓지 않는다** — 갖고 있으면 그 레시피가 열리는 소유물이다. 설계 문서의
    /// "건물·가구 배치" 범위 밖 규칙을 지킨 형태다(192칸에 두 번째 레이어를 얹으면 `normalized`·
    /// 되돌리기·아이소메트릭 그리기·LAN 와이어가 전부 들어온다).
    static let facilities: [ItemKind] = [.townKitchen, .townFurnace, .townMixer]

    /// 요리 20종. 쓰면 **지금 보고 있는 마을**이 먹는다 — 동행이 아니라 마을에 가는 유일한 아이템이다.
    static let dishes: [ItemKind] = [
        .dishFruitSalad, .dishHoneyToast, .dishHerbSoup, .dishPetalTea, .dishRoastedFruit,
        .dishHoneyPickle, .dishHerbPorridge, .dishPetalDango, .dishWildGreens, .dishFruitCompote,
        .dishSpringShaved, .dishFlowerPie, .dishHerbBath, .dishTricolorDango, .dishFruitJam,
        .dishHoneySteam, .dishWildflowerBowl, .dishFruitStew, .dishMixedSkewer, .dishPokopiaSet,
    ]

    // MARK: - 값 (재료만 상점에 오른다)

    /// 재료 등급 세 단. 설비·요리는 **값이 없다** — 사는 것이 아니라 만드는 것이고,
    /// `ItemKind.shopPrice` 가 그 23종에 `nil` 을 명시한다.
    ///
    /// `switch` + `default: nil` 이 아니라 **표**인 이유는 커버리지다. 부르는 자리
    /// (`ItemKind.shopPrice`)가 이미 재료 열 종으로 좁혀 놓고 부르므로 `default:` 가 한 번도
    /// 실행되지 않아 `^0` 으로 남는다(실측 확인, 2026-09-16) — 아무도 안 밟는 분기는 다음 사람이
    /// 고쳐도 아무 테스트가 안 깨진다. 표는 그 분기 자체를 만들지 않는다.
    ///
    /// **키 집합이 `materials` 와 같아야 한다** — 테스트가 양방향으로 센다. 갈리면 목록에는 있는데
    /// 값이 없는 재료(상점에서 사라진다)나 그 반대가 생긴다.
    static let materialPrice: [ItemKind: Int] = [
        .townWood: 40, .townStone: 40, .townClay: 40, .townSandGrain: 40, .townSpringWater: 40,
        .townPetal: 80, .townHerb: 80, .townFruit: 80,
        .townHoney: 150, .townOre: 150,
    ]

    // MARK: - 레시피 (설비 3 + 요리 20 = 23)

    /// 레시피 하나가 먹는 재료 한 줄. 튜플이 아니라 이름 있는 값인 이유는 `Equatable`·`Sendable`
    /// 합성 때문이다 — 튜플 배열을 담으면 `==` 를 손으로 적어야 하고, 손으로 적은 `==` 는
    /// 필드를 늘릴 때 조용히 낡는다.
    struct Ingredient: Equatable, Sendable {
        let item: ItemKind
        let count: Int
        init(_ item: ItemKind, _ count: Int) { self.item = item; self.count = count }
    }

    /// 레시피 하나. **제작 표와 요리 표를 하나로 둔다** — 요리는 "조리대가 여는 제작 갈래" 이고,
    /// 표를 둘로 두면 재료 소비·타이머·수령이 두 벌이 된다.
    struct Recipe: Equatable, Sendable, Identifiable {
        /// 만들어지는 물건. 이것이 곧 id 다 — 같은 물건을 두 레시피로 만들지 않는다(테스트가 센다).
        let output: ItemKind
        /// 재료와 개수. 배열 순서가 곧 화면 순서다.
        let inputs: [Ingredient]
        /// 필요한 설비. `nil` = 맨손이다 — **설비 3종이 그렇다**. 아니면 설비 없이 첫 설비를
        /// 만들 길이 없어 사슬이 시작되지 않는다.
        let facility: ItemKind?
        /// 만드는 데 걸리는 분.
        let minutes: Int
        /// 요리일 때 마을에 서는 포만감 시간. 설비는 `nil`.
        let satietyHours: Int?

        var id: ItemKind { output }
    }

    /// 레시피 표 23종.
    ///
    /// 포만감 3단(3h · 6h · 12h)과 만드는 시간 3단(15 · 30 · 60분)이 짝이다 — 오래 배부른 요리가
    /// 오래 걸린다. 짝을 깨면 값싼 요리 하나를 반복하는 것이 늘 최적이 된다.
    static let recipes: [Recipe] = [
        // 설비 — 맨손이다. 조리대가 가장 싸고 빠른 것이 사슬의 시작점이라서다.
        Recipe(output: .townKitchen,
               inputs: [Ingredient(.townWood, 3), Ingredient(.townStone, 2)],
               facility: nil, minutes: 60, satietyHours: nil),
        Recipe(output: .townFurnace,
               inputs: [Ingredient(.townWood, 4), Ingredient(.townOre, 2), Ingredient(.townClay, 1)],
               facility: nil, minutes: 120, satietyHours: nil),
        Recipe(output: .townMixer,
               inputs: [Ingredient(.townStone, 4), Ingredient(.townClay, 3), Ingredient(.townSandGrain, 2)],
               facility: nil, minutes: 120, satietyHours: nil),
        // 요리 3시간
        Recipe(output: .dishFruitSalad,
               inputs: [Ingredient(.townFruit, 2), Ingredient(.townHerb, 1)],
               facility: .townKitchen, minutes: 15, satietyHours: 3),
        Recipe(output: .dishHoneyToast,
               inputs: [Ingredient(.townHoney, 1), Ingredient(.townFruit, 1)],
               facility: .townKitchen, minutes: 15, satietyHours: 3),
        Recipe(output: .dishHerbSoup,
               inputs: [Ingredient(.townHerb, 2), Ingredient(.townSpringWater, 1)],
               facility: .townKitchen, minutes: 15, satietyHours: 3),
        Recipe(output: .dishPetalTea,
               inputs: [Ingredient(.townPetal, 2), Ingredient(.townSpringWater, 1)],
               facility: .townKitchen, minutes: 15, satietyHours: 3),
        Recipe(output: .dishRoastedFruit,
               inputs: [Ingredient(.townFruit, 2)],
               facility: .townKitchen, minutes: 15, satietyHours: 3),
        // 요리 6시간
        Recipe(output: .dishHoneyPickle,
               inputs: [Ingredient(.townHoney, 2), Ingredient(.townFruit, 1)],
               facility: .townKitchen, minutes: 30, satietyHours: 6),
        Recipe(output: .dishHerbPorridge,
               inputs: [Ingredient(.townHerb, 2), Ingredient(.townFruit, 1), Ingredient(.townSpringWater, 1)],
               facility: .townKitchen, minutes: 30, satietyHours: 6),
        Recipe(output: .dishPetalDango,
               inputs: [Ingredient(.townPetal, 2), Ingredient(.townHoney, 1)],
               facility: .townKitchen, minutes: 30, satietyHours: 6),
        Recipe(output: .dishWildGreens,
               inputs: [Ingredient(.townHerb, 3)],
               facility: .townKitchen, minutes: 30, satietyHours: 6),
        Recipe(output: .dishFruitCompote,
               inputs: [Ingredient(.townFruit, 3), Ingredient(.townHoney, 1)],
               facility: .townKitchen, minutes: 30, satietyHours: 6),
        Recipe(output: .dishSpringShaved,
               inputs: [Ingredient(.townSpringWater, 2), Ingredient(.townHoney, 1)],
               facility: .townKitchen, minutes: 30, satietyHours: 6),
        // 요리 12시간
        Recipe(output: .dishFlowerPie,
               inputs: [Ingredient(.townPetal, 2), Ingredient(.townHoney, 2), Ingredient(.townFruit, 1)],
               facility: .townKitchen, minutes: 60, satietyHours: 12),
        Recipe(output: .dishHerbBath,
               inputs: [Ingredient(.townHerb, 3), Ingredient(.townSpringWater, 2)],
               facility: .townKitchen, minutes: 60, satietyHours: 12),
        Recipe(output: .dishTricolorDango,
               inputs: [Ingredient(.townPetal, 1), Ingredient(.townHerb, 1),
                        Ingredient(.townFruit, 2), Ingredient(.townHoney, 1)],
               facility: .townKitchen, minutes: 60, satietyHours: 12),
        Recipe(output: .dishFruitJam,
               inputs: [Ingredient(.townFruit, 4), Ingredient(.townHoney, 2)],
               facility: .townKitchen, minutes: 60, satietyHours: 12),
        Recipe(output: .dishHoneySteam,
               inputs: [Ingredient(.townHoney, 3), Ingredient(.townHerb, 1)],
               facility: .townKitchen, minutes: 60, satietyHours: 12),
        Recipe(output: .dishWildflowerBowl,
               inputs: [Ingredient(.townPetal, 3), Ingredient(.townHerb, 2)],
               facility: .townKitchen, minutes: 60, satietyHours: 12),
        Recipe(output: .dishFruitStew,
               inputs: [Ingredient(.townFruit, 3), Ingredient(.townHerb, 2), Ingredient(.townSpringWater, 1)],
               facility: .townKitchen, minutes: 60, satietyHours: 12),
        Recipe(output: .dishMixedSkewer,
               inputs: [Ingredient(.townFruit, 2), Ingredient(.townHerb, 2), Ingredient(.townPetal, 2)],
               facility: .townKitchen, minutes: 60, satietyHours: 12),
        Recipe(output: .dishPokopiaSet,
               inputs: [Ingredient(.townHoney, 2), Ingredient(.townFruit, 3), Ingredient(.townHerb, 2),
                        Ingredient(.townPetal, 2), Ingredient(.townSpringWater, 1)],
               facility: .townKitchen, minutes: 60, satietyHours: 12),
    ]

    /// 산출물 → 레시피. 표를 **그 자리에서 뒤집는다** — 저장된 역표를 두면 두 표가 어긋날 수 있다
    /// (`PokopiaTown.typesMaking(_:)` 이 같은 이유로 파생이다).
    static func recipe(making output: ItemKind) -> Recipe? {
        recipes.first { $0.output == output }
    }

    // MARK: - 포만감 (환경 레벨의 세 번째 축)

    /// 포만감이 설 수 있는 최대 폭. 요리를 겹쳐 쓸 때의 천장이자 **읽는 자리의 상한**이다 —
    /// 손으로 고친 세이브나 옛 전송이 먼 미래를 담아 와도 하루치까지만 뜻을 갖는다.
    ///
    /// `PokopiaTown.normalized` 는 이 값을 읽지 않는다. 그 함수는 `now` 를 모르고, 시계를 들이면
    /// 신뢰경계가 실행 시각에 따라 다른 답을 낸다 — 대신 아래 `isFed` 가 밖을 거짓으로 읽는다.
    /// 읽는 자리가 하나라서 성립하는 형태다(두 번째 독자가 생기면 그때 이 판단을 다시 한다).
    static let maxSatiety: TimeInterval = 60 * 60 * 24

    /// 지금 이 마을이 배부른가. **읽는 자리가 하나다** — 화면과 환경 레벨이 같은 술어를 쓰므로
    /// "배부른 마을" 이라 적힌 줄과 레벨이 어긋날 수 없다(`isSettled` 를 화면과 개발도가 함께
    /// 읽는 것과 같은 규칙).
    ///
    /// `now` 를 **인자로 받는다**(`PokopiaTownLife.line` 과 같은 이유) — 함수 안에서 시계를 읽으면
    /// 테스트가 실행 시각에 따라 다른 가지를 밟는다.
    static func isFed(fedUntil: Date?, now: Date) -> Bool {
        guard let fedUntil else { return false }
        return fedUntil > now && fedUntil <= now.addingTimeInterval(maxSatiety)
    }

    /// 요리를 하나 썼을 때의 새 만료 시각. **누적하되 상한에 걸린다** — 상한이 없으면 요리 스무
    /// 개로 몇 달치 포만감을 세울 수 있고, 그러면 축 C 가 한 번 켜고 잊는 스위치가 된다.
    ///
    /// 이미 지난 값에는 **얹지 않는다**(`max(current, now)`) — 얹으면 한 달 전에 먹인 마을이
    /// 요리 하나로 그때부터 계산돼 지금은 여전히 배고픈 채로 남는다.
    static func fedUntil(after current: Date?, hours: Int, now: Date) -> Date {
        let base = max(current ?? now, now)
        let ceiling = now.addingTimeInterval(maxSatiety)
        return min(base.addingTimeInterval(TimeInterval(hours) * 3600), ceiling)
    }
}

/// 제작 주문 하나. **세이브에 들어간다** — `output` 의 rawValue 가 ID 다.
///
/// 큐가 아니라 옵셔널 하나로 들고 있는다(`CompanionState.townCraft`) — 동시 여러 건은 상한·정렬·
/// 설비별 병렬을 부르고, 이 기능이 주려는 것은 병렬 생산 최적화가 아니라 기다림 하나다.
/// 오프라인 타이머 형태는 `focusEggReadyDates` 와 같다(예정 시각을 저장하고 화면이 비교한다).
struct TownCraftOrder: Codable, Sendable, Equatable {
    var output: ItemKind
    var readyAt: Date
}
