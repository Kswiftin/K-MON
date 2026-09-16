import Foundation
import Testing
@testable import PokeTokenBar

// MARK: 포코피아 9단계 — 제작·요리 표와 포만감 판정
//
// 표는 `PokopiaCrafting` 한 파일이고, 여기서 **전수·유일·도달성** 셋을 센다. 문장을 리터럴로
// 기대하지 않는다(`PokopiaTownWeatherTests` 머리의 규칙) — 게이트가 영어 로케일로 재실행한다.
//
// 마지막 두 테스트는 **소스 가드**다. "판정 세 축을 안 건드린다" 는 주석으로만 두면 다음 사람이
// 지울 수 있고, 지워진 뒤에는 포만감이 이사 확률에 붙어도 아무 테스트가 안 깨진다.

@Suite struct PokopiaCraftingTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: 표 — 전수·유일

    /// 산출물이 겹치면 그 레시피 하나가 화면에서 **영영 사라진다**(`recipe(making:)` 가 앞의 것만
    /// 준다). `specialty(for:)` 의 18←18 유일성과 같은 부류다.
    @Test func everyRecipeMakesADifferentThing() {
        let outputs = PokopiaCrafting.recipes.map(\.output)
        #expect(Set(outputs).count == outputs.count, "산출물이 겹친다: \(outputs)")
        #expect(outputs.count == 23, "설비 3 + 요리 20 = 23 이어야 한다 — 실제 \(outputs.count)")
    }

    /// 산출물 집합 == 설비 3 + 요리 20. 목록과 표가 갈리면 "만들 수 있는데 목록에 없는" 물건이나
    /// 그 반대가 생긴다.
    @Test func theRecipeOutputsAreExactlyTheFacilitiesAndDishes() {
        let outputs = Set(PokopiaCrafting.recipes.map(\.output))
        let declared = Set(PokopiaCrafting.facilities).union(PokopiaCrafting.dishes)
        #expect(outputs == declared, "표와 목록이 갈린다: \(outputs.symmetricDifference(declared))")
    }

    /// **재료 10종 전부**가 어느 레시피의 입력이다. 안 쓰이는 재료는 사는 순간 별의조각을 버리는
    /// 함정 구매가 된다 — 진화 아이템이 "대상 종이 획득 가능 목록 안에 있어야 한다" 를 같은
    /// 이유로 못 박는다.
    @Test func everyMaterialIsUsedByAtLeastOneRecipe() {
        let used = Set(PokopiaCrafting.recipes.flatMap { $0.inputs.map(\.item) })
        let unused = PokopiaCrafting.materials.filter { !used.contains($0) }
        #expect(unused.isEmpty, "어느 레시피에도 안 쓰이는 재료: \(unused.map(\.rawValue))")
    }

    /// 거꾸로 — 입력이 전부 **살 수 있는 재료**다. 못 사는 물건이 입력이면 그 레시피는 영영
    /// 걸 수 없고, 화면은 그 사실을 말할 방법이 없다.
    @Test func everyRecipeInputIsAMaterialYouCanBuy() {
        for recipe in PokopiaCrafting.recipes {
            for input in recipe.inputs {
                #expect(PokopiaCrafting.materials.contains(input.item),
                        "\(recipe.output.rawValue) 의 입력 \(input.item.rawValue) 이 재료 목록 밖이다")
                #expect(input.item.shopPrice != nil,
                        "\(input.item.rawValue) 에 값이 없어 상점에 안 뜬다")
                #expect(input.count > 0, "\(recipe.output.rawValue) 의 입력 개수가 0 이하다")
            }
            #expect(!recipe.inputs.isEmpty, "\(recipe.output.rawValue) 에 입력이 없다 — 공짜로 나온다")
            #expect(recipe.minutes > 0, "\(recipe.output.rawValue) 의 소요 시간이 0 이하다")
        }
    }

    /// 설비 3종은 **맨손**이다. 아니면 설비 없이 첫 설비를 만들 길이 없어 사슬이 시작되지 않는다.
    @Test func facilitiesAreMadeWithBareHands() {
        for facility in PokopiaCrafting.facilities {
            let recipe = PokopiaCrafting.recipe(making: facility)
            #expect(recipe != nil, "\(facility.rawValue) 를 만드는 레시피가 없다")
            #expect(recipe?.facility == nil, "\(facility.rawValue) 가 설비를 요구한다 — 사슬이 안 시작된다")
            #expect(recipe?.satietyHours == nil, "설비에 포만감이 붙어 있다 — 설비를 먹일 수 있게 된다")
        }
    }

    /// 요리 20종은 조리대가 필요하고 포만감을 싣는다. 포만감이 없는 요리는 쓰면 아무 일도 안 하는
    /// 물건이 된다(`feedTown` 이 `satietyHours` 로 요리 여부를 판정한다).
    @Test func everyDishNeedsTheKitchenAndCarriesSatiety() {
        for dish in PokopiaCrafting.dishes {
            let recipe = PokopiaCrafting.recipe(making: dish)
            #expect(recipe?.facility == .townKitchen, "\(dish.rawValue) 가 조리대를 안 쓴다")
            #expect((recipe?.satietyHours ?? 0) > 0, "\(dish.rawValue) 에 포만감이 없다")
            #expect(dish.bagUse == .dish, "\(dish.rawValue) 의 가방 갈래가 요리가 아니다")
        }
    }

    // MARK: 값 — 컴파일러가 못 잡는 유일한 자리

    /// 재료만 상점에 오르고 **설비·요리 23종은 안 오른다**. `ItemKind.shopPrice` 의 `default:` 가
    /// 이 파일에서 컴파일러가 못 잡는 유일한 자리라, 새 케이스를 안 적으면 조용히 `nil` 이 되어
    /// 상점에서 영영 빠진다(하트비늘·테라피스가 걸린 부류).
    @Test func onlyMaterialsCarryAShopPrice() {
        #expect(Set(PokopiaCrafting.materialPrice.keys) == Set(PokopiaCrafting.materials),
                "값 표와 재료 목록이 갈린다 — 한쪽에만 있는 재료는 상점에서 사라지거나 값이 없다")
        for material in PokopiaCrafting.materials {
            #expect((material.shopPrice ?? 0) > 0, "\(material.rawValue) 에 값이 없다 — 상점에 안 뜬다")
            #expect(material.bagUse == .townGood, "\(material.rawValue) 의 가방 갈래가 마을 물건이 아니다")
        }
        for made in PokopiaCrafting.facilities + PokopiaCrafting.dishes {
            #expect(made.shopPrice == nil, "\(made.rawValue) 를 상점에서 판다 — 만드는 물건이다")
        }
    }

    /// 마을 물건 33종 전부가 **진화 아이템이 아니다.** 하나라도 진화 갈래로 새면 `default:` 가
    /// 500 별의조각 값을 붙이고 가방이 "진화 가능할 때 사용" 을 띄운다.
    @Test func noTownGoodLeaksIntoTheEvolutionBranch() {
        for kind in PokopiaCrafting.materials + PokopiaCrafting.facilities + PokopiaCrafting.dishes {
            #expect(kind.evolutionRule == nil, "\(kind.rawValue) 에 진화 규칙이 붙어 있다")
            #expect(kind.bagUse != .evolutionItem, "\(kind.rawValue) 가 진화 갈래로 샌다")
        }
    }

    // MARK: 이름표 — 먼저 받아들이고 실패하지 않는다

    /// 요리는 이름으로 부를 수 있고 **재료·설비는 없다.** 이름표에 넣으면 `use 나무` 가 먼저
    /// 받아들여진 뒤 실패해, 사용자에겐 자기가 시킨 일이 안 된 것으로 보인다(가구와 같은 이유).
    @Test func nameLookupTakesDishesButNotMaterialsOrFacilities() {
        #expect(ItemKind.named("dishHerbSoup") == .dishHerbSoup)
        #expect(ItemKind.named("약초수프") == .dishHerbSoup)
        #expect(ItemKind.named("약초죽") == .dishHerbPorridge)
        #expect(ItemKind.named("나무") == nil, "재료가 이름표에 들어 있다")
        #expect(ItemKind.named("townWood") == nil, "재료가 이름표에 들어 있다")
        #expect(ItemKind.named("조리대") == nil, "설비가 이름표에 들어 있다")
    }

    /// **표시 이름이 겹치면 한쪽을 영영 못 부른다** — `ItemKind.match` 는 `first` 를 준다.
    /// 요리 20종을 한 번에 넣으면서 "약초수프/약초죽" 처럼 닮은 이름이 여럿 생겼고, 겹침은
    /// 컴파일러도 리뷰도 못 잡는다(이름은 서로 다른 case 의 값일 뿐이다).
    ///
    /// **`nameable` 안에서만 센다.** 이름표 밖 물건(가구·재료·설비)은 애초에 이름으로 안 부르므로
    /// 겹쳐도 해가 없고, 전체로 넓히면 오늘 main 이 빨개진다(가구에 겹치는 이름이 있다).
    @Test func noTwoNameableItemsShareADisplayName() {
        var seen: [String: ItemKind] = [:]
        var clashes: [String] = []
        for kind in ItemKind.nameable {
            let name = L().itemName(kind).lowercased()
            if let previous = seen[name] {
                clashes.append("\(name): \(previous.rawValue) vs \(kind.rawValue)")
            }
            seen[name] = kind
        }
        #expect(clashes.isEmpty, "표시 이름이 겹쳐 한쪽을 이름으로 못 부른다 — \(clashes)")
    }

    // MARK: 포만감

    /// 안 먹였거나 지났으면 거짓. `nil` 을 참으로 읽으면 모든 마을이 처음부터 한 단 높다.
    @Test func satietyIsFalseWithoutAFreshMeal() {
        #expect(PokopiaCrafting.isFed(fedUntil: nil, now: now) == false)
        #expect(PokopiaCrafting.isFed(fedUntil: now.addingTimeInterval(-1), now: now) == false)
        #expect(PokopiaCrafting.isFed(fedUntil: now, now: now) == false, "만료 순간은 지난 것이다")
        #expect(PokopiaCrafting.isFed(fedUntil: now.addingTimeInterval(1), now: now) == true)
    }

    /// **먼 미래는 거짓이다.** 손으로 고친 세이브나 옛 전송이 9999년을 담아 와도 하루치까지만
    /// 뜻을 갖는다 — `normalized` 가 `now` 를 모르므로 읽는 자리가 이 검사를 한다.
    @Test func satietyIgnoresAFarFutureValue() {
        let ceiling = now.addingTimeInterval(PokopiaCrafting.maxSatiety)
        #expect(PokopiaCrafting.isFed(fedUntil: ceiling, now: now) == true, "상한 자체는 유효하다")
        #expect(PokopiaCrafting.isFed(fedUntil: ceiling.addingTimeInterval(1), now: now) == false)
        #expect(PokopiaCrafting.isFed(fedUntil: .distantFuture, now: now) == false)
    }

    /// 겹쳐 먹이면 누적하되 **상한에 걸린다.** 상한이 없으면 요리 스무 개로 몇 달치를 세울 수 있고,
    /// 그러면 축 C 가 한 번 켜고 잊는 스위치가 된다.
    @Test func eatingAgainExtendsButStopsAtTheCeiling() {
        var until: Date? = nil
        for _ in 0..<8 {
            until = PokopiaCrafting.fedUntil(after: until, hours: 3, now: now)
        }
        #expect(until == now.addingTimeInterval(PokopiaCrafting.maxSatiety),
                "8 × 3시간 = 24시간 — 상한에 정확히 닿아야 한다")
        let more = PokopiaCrafting.fedUntil(after: until, hours: 12, now: now)
        #expect(more == now.addingTimeInterval(PokopiaCrafting.maxSatiety), "상한을 넘지 않는다")
    }

    /// 지난 값에는 **얹지 않는다.** 얹으면 한 달 전에 먹인 마을이 요리 하나로 그때부터 계산돼
    /// 지금은 여전히 배고픈 채로 남는다.
    @Test func eatingFromAnExpiredStateStartsFromNow() {
        let expiredLongAgo = now.addingTimeInterval(-60 * 60 * 24 * 30)
        let until = PokopiaCrafting.fedUntil(after: expiredLongAgo, hours: 6, now: now)
        #expect(until == now.addingTimeInterval(6 * 3600))
        #expect(PokopiaCrafting.isFed(fedUntil: until, now: now) == true)
    }

    /// 아직 남아 있으면 그 위에 쌓는다 — 남은 시간을 덮어쓰면 짧은 요리로 긴 포만감을 깎게 된다.
    @Test func eatingWhileStillFedStacksOnTopOfWhatIsLeft() {
        let current = now.addingTimeInterval(2 * 3600)
        let until = PokopiaCrafting.fedUntil(after: current, hours: 3, now: now)
        #expect(until == now.addingTimeInterval(5 * 3600))
    }

    // MARK: 소스 가드 — 판정 세 축과의 분리

    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // Tests/PokeTokenBarLocalTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // 저장소 루트
            .appendingPathComponent("Sources/PokeTokenBar/Core")
    }

    /// 줄 주석을 뗀 소스. 주석 안의 이름은 참조가 아니다 — 두 파일의 머리 주석이 서로를 언급한다.
    private static func code(_ name: String) throws -> String {
        let raw = try String(contentsOf: sourcesDirectory.appendingPathComponent(name), encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : String($0) }
            .joined(separator: "\n")
    }

    /// 제작 표가 **판정 세 축을 부르지 않는다.** 부르면 포만감이 서식 문턱·이사 확률에 붙을 수
    /// 있고, 그 순간 "내가 만들어서 왔다" 가 요리라는 다른 축에 덮인다.
    @Test func theCraftingTableDoesNotReachIntoTheHabitatRules() throws {
        let code = try Self.code("PokopiaCrafting.swift")
        #expect(!code.contains("PokopiaTown."), "PokopiaCrafting 이 PokopiaTown 을 부른다 — 축이 섞였다")
    }

    /// 거꾸로 — 서식 규칙이 제작 표를 부르지 않는다. `development` 는 포만감을 **`Bool` 로만**
    /// 받는다(시계도 레시피 표도 모른다).
    @Test func theHabitatRulesDoNotReachIntoCrafting() throws {
        let code = try Self.code("PokopiaTown.swift")
        #expect(!code.contains("PokopiaCrafting"), "PokopiaTown 이 PokopiaCrafting 을 부른다 — 축이 섞였다")
    }

    /// NPC 표도 제작 축을 **모른다**(10단계). 설비 보유는 `Bool` 인자로 받는다 — 이 가드가 없으면
    /// 분리가 파일 하나 건너로 샌다: NPC 가 `PokopiaCrafting` 을 부르고 뷰가 NPC 를 부르면, 위 두
    /// 가드는 초록인 채로 축이 섞인다.
    @Test func theNamedNPCsDoNotReachIntoCrafting() throws {
        let code = try Self.code("PokopiaTownNPC.swift")
        #expect(!code.contains("PokopiaCrafting"), "PokopiaTownNPC 가 PokopiaCrafting 을 부른다 — 축이 섞였다")
    }

    /// 가드가 실제로 잡는지 가드가 스스로 증명한다. 위 셋만 있으면 파일 읽기가 빈 문자열을
    /// 돌려줘도 초록이라, 가드가 일하는지와 일하지 않는지를 구별할 수 없다.
    @Test func theSourceGuardsActuallyReadTheFiles() throws {
        #expect(try Self.code("PokopiaCrafting.swift").contains("static let recipes"))
        #expect(try Self.code("PokopiaTown.swift").contains("static func development"))
        #expect(try Self.code("PokopiaTownNPC.swift").contains("static func unlocked"))
    }
}
