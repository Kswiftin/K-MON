import XCTest
@testable import PokeTokenBar

// MARK: 포코피아 9단계 — 사슬(구매 → 제작 → 수령 → 먹이기)과 저장
//
// 순수 표는 `PokopiaCraftingTests`(swift-testing)가 잠근다. 여기서는 **스토어와 앨범을 지나는
// 것**만 본다 — 재고가 언제 빠지는지, 예정 시각이 무엇을 막는지, 되돌리기가 요리를 건드리는지,
// 옛 세이브가 열리는지.
//
// 마을 상태는 앨범에, 인벤토리는 스토어에 있어서 **소비와 쓰기가 갈려 있다.** `feedTown` 의
// 순서(앨범 거절이 먼저)가 계약이고, 이 파일이 그 순서를 검증한다.

private struct CraftNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class PokopiaCraftStoreTests: XCTestCase {

    private let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
    private var now: Date { clock.now }

    /// 지갑이 넉넉한 빈 스토어. 재료는 테스트가 `debugSetItemCount` 로 심는다 — 구매 경로를
    /// 따로 보는 테스트가 하나 있고, 나머지는 구매를 전제로 두면 실패 원인이 둘이 된다.
    private func store(tag: String = "pokopia-craft") -> CompanionStore {
        store(at: storeStateURL(tag))
    }

    /// 같은 파일을 두 번 열어야 하는 테스트(재시작·세이브 이전)를 위해 경로를 받는 갈래.
    /// `storeStateURL` 은 부를 때마다 **새 디렉토리**를 파므로 두 번 부르면 다른 세이브가 된다
    /// (`TeraShardTests` 가 같은 이유로 갈래를 둘 둔다).
    private func store(at url: URL) -> CompanionStore {
        if !FileManager.default.fileExists(atPath: url.path) {
            let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,"
                + "\"installBaselineSet\":true,\"usedSinceInstall\":1000000000,\"spentTokens\":0,"
                + "\"starPieces\":1000000000,\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]}"
            try? json.data(using: .utf8)!.write(to: url)
        }
        return CompanionStore(provider: CraftNoProvider(), clock: clock.closure,
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    private func recipe(_ output: ItemKind) -> PokopiaCrafting.Recipe {
        PokopiaCrafting.recipe(making: output)!
    }

    /// 그 레시피를 걸 수 있게 재료(와 필요한 설비)를 정확히 채운다.
    private func stock(_ store: CompanionStore, for recipe: PokopiaCrafting.Recipe) {
        for input in recipe.inputs { store.debugSetItemCount(input.item, input.count) }
        if let facility = recipe.facility { store.debugSetItemCount(facility, 1) }
    }

    /// 요리 하나를 재고에 바로 심는다(제작 사슬을 안 태우는 테스트용).
    private func giveDish(_ store: CompanionStore, _ dish: ItemKind, _ count: Int = 1) {
        store.debugSetItemCount(dish, count)
    }

    // MARK: 구매 — 재료만 상점에 있다

    func testBuyingAMaterialSpendsStarPiecesAndFillsTheBag() {
        let s = store()
        let price = try! XCTUnwrap(ItemKind.townWood.shopPrice)

        XCTAssertTrue(s.buy(.townWood, quantity: 3))

        XCTAssertEqual(s.itemCount(.townWood), 3)
        XCTAssertEqual(s.state.starPieces, 1_000_000_000 - price * 3)
    }

    /// 상점 목록은 `shopPrice != nil` 로 자동 집계된다(`ShopCatalog.all`) — 값을 안 적은 재료는
    /// **아무 말 없이** 목록에서 빠지고, 그 사실은 컴파일러도 리뷰도 못 잡는다.
    func testTheShopListsEveryMaterialAndNothingYouMake() {
        let slugs = Set(ShopCatalog.all.map(\.slug))
        for material in PokopiaCrafting.materials {
            XCTAssertTrue(slugs.contains(material.rawValue), "\(material.rawValue) 이 상점에 없다")
        }
        for made in PokopiaCrafting.facilities + PokopiaCrafting.dishes {
            XCTAssertFalse(slugs.contains(made.rawValue), "\(made.rawValue) 를 상점에서 판다")
        }
    }

    /// 이름으로도 살 수 있어야 터미널 `buy` 가 쓸 수 있다(`ShopCatalog.named`).
    func testAMaterialCanBeFoundByItsDisplayName() {
        XCTAssertEqual(ShopCatalog.named("나무"), .item(.townWood))
        XCTAssertEqual(ShopCatalog.named("townWood"), .item(.townWood))
        XCTAssertNil(ShopCatalog.named("약초죽"), "요리는 파는 물건이 아니다")
    }

    // MARK: 제작 — 재료는 걸 때 빠진다

    func testStartingACraftConsumesTheInputsImmediately() {
        let s = store()
        let kitchen = recipe(.townKitchen)
        stock(s, for: kitchen)

        XCTAssertTrue(s.startTownCraft(kitchen))

        XCTAssertEqual(s.itemCount(.townWood), 0, "재료가 끝날 때 빠지면 그 사이에 버린 사람이 공짜다")
        XCTAssertEqual(s.itemCount(.townStone), 0)
        XCTAssertEqual(s.state.inventory["townWood"], nil, "0 을 남기면 가방이 빈 줄을 그린다")
        XCTAssertEqual(s.state.townCraft?.output, .townKitchen)
        XCTAssertEqual(s.state.townCraft?.readyAt,
                       now.addingTimeInterval(TimeInterval(kitchen.minutes) * 60))
        XCTAssertEqual(s.itemCount(.townKitchen), 0, "아직 안 받았는데 산출물이 들어왔다")
    }

    func testACraftIsRefusedWhenAnInputIsShort() {
        let s = store()
        let kitchen = recipe(.townKitchen)
        stock(s, for: kitchen)
        s.debugSetItemCount(.townStone, 1)      // 2 필요

        XCTAssertFalse(s.canStartTownCraft(kitchen))
        XCTAssertFalse(s.startTownCraft(kitchen))
        XCTAssertEqual(s.itemCount(.townWood), 3, "거절했는데 재료가 빠졌다")
        XCTAssertNil(s.state.townCraft)
    }

    /// **트리거 브랜치 — 재료는 다 있고 설비만 없다.** 재료 부족과 같은 거절로 뭉뚱그리면
    /// 설비 게이트가 있는지 없는지 테스트가 구별하지 못한다.
    func testADishIsRefusedWithoutTheKitchenEvenWithEveryIngredient() {
        let s = store()
        let soup = recipe(.dishHerbSoup)
        for input in soup.inputs { s.debugSetItemCount(input.item, input.count) }
        XCTAssertEqual(s.itemCount(.townKitchen), 0, "전제: 조리대가 없어야 한다")

        XCTAssertFalse(s.canStartTownCraft(soup))
        XCTAssertFalse(s.startTownCraft(soup))

        s.debugSetItemCount(.townKitchen, 1)
        XCTAssertTrue(s.canStartTownCraft(soup), "조리대만 주면 걸려야 한다")
    }

    /// 설비는 **소모되지 않는다** — 갖고 있는 것이 곧 효과다.
    func testTheFacilityIsNotConsumedByCooking() {
        let s = store()
        let soup = recipe(.dishHerbSoup)
        stock(s, for: soup)

        XCTAssertTrue(s.startTownCraft(soup))

        XCTAssertEqual(s.itemCount(.townKitchen), 1, "설비가 소모됐다 — 한 번 쓰고 사라지는 물건이 됐다")
    }

    func testOnlyOneCraftRunsAtATime() {
        let s = store()
        let kitchen = recipe(.townKitchen)
        let furnace = recipe(.townFurnace)
        stock(s, for: kitchen)
        stock(s, for: furnace)

        XCTAssertTrue(s.startTownCraft(kitchen))
        XCTAssertFalse(s.canStartTownCraft(furnace))
        XCTAssertFalse(s.startTownCraft(furnace))
        XCTAssertEqual(s.state.townCraft?.output, .townKitchen, "뒤에 건 것이 앞의 것을 덮었다")
        XCTAssertEqual(s.itemCount(.townOre), furnace.inputs.first { $0.item == .townOre }!.count,
                       "거절했는데 두 번째 레시피의 재료가 빠졌다")
    }

    // MARK: 수령 — 예정 시각이 문이다

    func testCollectingOneSecondEarlyDoesNothing() {
        let s = store()
        let kitchen = recipe(.townKitchen)
        stock(s, for: kitchen)
        s.startTownCraft(kitchen)

        clock.advance(TimeInterval(kitchen.minutes) * 60 - 1)

        XCTAssertNil(s.collectTownCraft())
        XCTAssertEqual(s.itemCount(.townKitchen), 0)
        XCTAssertNotNil(s.state.townCraft, "안 줬는데 주문이 사라졌다")
    }

    func testCollectingOnTheDeadlineGivesTheOutput() {
        let s = store()
        let kitchen = recipe(.townKitchen)
        stock(s, for: kitchen)
        s.startTownCraft(kitchen)

        clock.advance(TimeInterval(kitchen.minutes) * 60)

        XCTAssertEqual(s.collectTownCraft(), .townKitchen)
        XCTAssertEqual(s.itemCount(.townKitchen), 1)
        XCTAssertNil(s.state.townCraft)
        XCTAssertNil(s.collectTownCraft(), "두 번 받으면 하나로 둘이 나온다")
    }

    /// 앱을 껐다 켜도 예정 시각이 살아 있다 — 오프라인 타이머라는 것이 이 테스트의 내용이다.
    func testACraftInFlightSurvivesAReload() throws {
        let url = storeStateURL("pokopia-craft-reload")
        let first = store(at: url)
        let kitchen = recipe(.townKitchen)
        stock(first, for: kitchen)
        first.startTownCraft(kitchen)
        let readyAt = try XCTUnwrap(first.state.townCraft?.readyAt)

        let second = store(at: url)

        XCTAssertEqual(second.state.townCraft?.output, .townKitchen)
        XCTAssertEqual(second.state.townCraft?.readyAt, readyAt)
    }

    // MARK: 먹이기

    func testFeedingADishSetsTheTownsSatietyAndSpendsTheDish() {
        let s = store()
        giveDish(s, .dishHerbSoup)
        let hours = try! XCTUnwrap(recipe(.dishHerbSoup).satietyHours)

        let until = s.feedTown(.dishHerbSoup)

        XCTAssertEqual(until, now.addingTimeInterval(TimeInterval(hours) * 3600))
        XCTAssertEqual(s.memoryAlbum.town.fedUntil, until)
        XCTAssertEqual(s.itemCount(.dishHerbSoup), 0)
        XCTAssertNil(s.state.inventory["dishHerbSoup"], "0 을 남기면 가방이 빈 줄을 그린다")
    }

    func testFeedingWithoutTheDishChangesNothing() {
        let s = store()

        XCTAssertNil(s.feedTown(.dishHerbSoup))
        XCTAssertNil(s.memoryAlbum.town.fedUntil)
    }

    /// 재료는 요리가 아니다 — `satietyHours` 가 없으면 먹일 수 없다.
    func testAMaterialCannotBeFedToTheTown() {
        let s = store()
        s.debugSetItemCount(.townFruit, 5)

        XCTAssertNil(s.feedTown(.townFruit))
        XCTAssertEqual(s.itemCount(.townFruit), 5, "먹이지도 않았는데 재료가 빠졌다")
        XCTAssertNil(s.memoryAlbum.town.fedUntil)
    }

    /// **앨범이 거절하면 재고도 안 깎인다.** 짧은 요리로 긴 포만감을 덮어쓰려 할 때의 경로다 —
    /// 순서가 뒤집히면 요리는 사라지고 마을은 그대로다.
    func testAShorterMealIsRefusedAndTheDishIsNotSpent() {
        let s = store()
        giveDish(s, .dishPokopiaSet)        // 12시간
        giveDish(s, .dishHerbSoup)          // 3시간
        let long = try! XCTUnwrap(s.feedTown(.dishPokopiaSet))

        // 아직 12시간이 남은 상태에서 3시간짜리를 먹이면 **더 길어지므로** 받아들여진다.
        let stacked = try! XCTUnwrap(s.feedTown(.dishHerbSoup))
        XCTAssertGreaterThan(stacked, long, "쌓지 않고 덮어썼다")
        XCTAssertEqual(s.itemCount(.dishHerbSoup), 0)

        // 상한까지 채운 뒤에는 더 먹여도 늘지 않으므로 거절되고 재고가 남는다.
        giveDish(s, .dishPokopiaSet, 3)
        while s.feedTown(.dishPokopiaSet) != nil { giveDish(s, .dishPokopiaSet, 3) }
        let before = s.itemCount(.dishPokopiaSet)
        XCTAssertNil(s.feedTown(.dishPokopiaSet), "상한에 닿았는데 또 받아들였다")
        XCTAssertEqual(s.itemCount(.dishPokopiaSet), before, "거절했는데 요리가 사라졌다")
        XCTAssertEqual(s.memoryAlbum.town.fedUntil,
                       now.addingTimeInterval(PokopiaCrafting.maxSatiety))
    }

    /// **먹이기는 편집이 아니라 사건이다** — 되돌리기 스택에 안 들어간다. 들어가면 되돌리기 한
    /// 번이 요리를 지우고 재료는 안 돌아온다.
    func testFeedingIsNotUndoable() {
        let s = store()
        giveDish(s, .dishHerbSoup)
        // 지형을 한 번 밀어 되돌릴 것을 만든다 — 스택이 비어 있으면 undo 가 no-op 이라
        // 이 테스트가 아무것도 증명하지 못한다.
        s.memoryAlbum.shapeTownTile(col: 0, row: 0, to: .water)
        let until = try! XCTUnwrap(s.feedTown(.dishHerbSoup))
        XCTAssertTrue(s.memoryAlbum.canUndoTownEdit, "전제: 되돌릴 편집이 있어야 한다")

        s.memoryAlbum.undoTownEdit()

        XCTAssertEqual(s.memoryAlbum.town.fedUntil, until, "되돌리기가 요리를 되돌렸다")
        XCTAssertEqual(s.memoryAlbum.town.terrain[0], PokopiaTown.defaultTerrain(for: .waste)[0],
                       "전제: 지형은 되돌아가야 한다")
    }

    /// 포만감은 **마을마다**다(7단계의 지역 분리 계약). 한 마을을 먹였다고 다섯이 배부르면
    /// "어느 마을을 키울까" 가 사라진다.
    func testSatietyIsPerRegion() {
        let s = store()
        giveDish(s, .dishHerbSoup)
        s.feedTown(.dishHerbSoup)
        XCTAssertNotNil(s.memoryAlbum.town.fedUntil)

        s.memoryAlbum.selectRegion(.coast)

        XCTAssertNil(s.memoryAlbum.town.fedUntil, "해안까지 배불러졌다")
    }

    // MARK: 환경 레벨 축 C

    /// 포만감이 레벨을 한 단 올린다 — 정원·이사는 그대로다.
    func testSatietyLiftsTheLevelByOneWithoutTouchingCapacity() {
        let terrain = Array(repeating: TownTerrain.water, count: PokopiaTown.tileCount)
        let hungry = PokopiaTown.development(terrain, residents: [])
        let full = PokopiaTown.development(terrain, residents: [], fed: true)

        XCTAssertEqual(full.level, hungry.level + 1)
        XCTAssertEqual(full.capacity, hungry.capacity, "축 C 가 정원을 열었다 — 되먹임이다")
        XCTAssertEqual(full.habitats, hungry.habitats)
        XCTAssertTrue(full.fed)
        XCTAssertFalse(hungry.fed)
    }

    /// **천장은 그대로다.** 지형 여덟 종 + 정원을 채운 전원 정착이면 축 A(8) + 축 B(2) 만으로
    /// 이미 `maxLevel` 이고, 포만감을 더해 **11 이 되는 입력**에서도 10 에서 멈춘다.
    ///
    /// 이 테스트는 **잘리는 입력을 직접 만들어야 한다.** 축 B 가 한 계단만 오른 마을로 재면
    /// 8 + 1 + 1 = 10 이라 `min` 을 `maxLevel + 1` 로 바꿔도 통과한다(결함 주입 4번으로 확인,
    /// 2026-09-16 — 처음 쓴 테스트가 실제로 그 상태였다).
    func testSatietyDoesNotRaiseTheCeiling() {
        // 여덟 지형을 돌려 깐 마을 — 어떤 타입도 정착한다(`PokopiaTownTests` 의 등식 테스트와 같은 격자).
        let field = (0..<PokopiaTown.tileCount).map {
            TownTerrain.allCases[$0 % TownTerrain.allCases.count]
        }
        let everyone = (1...PokopiaTown.populationLimit).map {
            TownResident(speciesID: $0, name: "테스트\($0)", types: [.water], arrivedAt: now)
        }
        let hungry = PokopiaTown.development(field, residents: everyone)
        XCTAssertEqual(hungry.habitats, TownTerrain.allCases.count, "전제: 지형 여덟 종")
        XCTAssertEqual(hungry.settled, PokopiaTown.populationLimit, "전제: 전원 정착")
        XCTAssertEqual(hungry.level, PokopiaTown.maxLevel,
                       "전제: 포만감 없이도 이미 천장이어야 잘리는 입력이 된다")

        let fed = PokopiaTown.development(field, residents: everyone, fed: true)

        // 8(축 A) + 2(축 B) + 1(축 C) = 11 이 들어왔는데 10 으로 잘려야 한다.
        XCTAssertEqual(fed.level, PokopiaTown.maxLevel, "축 C 가 천장을 넘겼다 — Lv.1~10 이 깨진다")
        XCTAssertEqual(fed.name, hungry.name, "구간 이름까지 바뀌면 화면이 없는 단계를 말한다")
        XCTAssertEqual(fed.capacity, hungry.capacity)
    }

    /// 천장 **아래**에서는 실제로 한 단 오른다 — 위 테스트만 있으면 축 C 가 아무 일도 안 해도
    /// (`if fed` 를 통째로 지워도) 초록이다.
    func testSatietyActuallyLiftsBelowTheCeiling() {
        // 지형 여섯 종 · 주민 없음 → 축 A 6, 축 B 0. 포만감이 7 로 올린다.
        var field = PokopiaTown.defaultTerrain(for: .waste)
        for (index, tile) in TownTerrain.allCases.prefix(6).enumerated() {
            for offset in 0..<PokopiaTown.habitatThreshold {
                field[index * PokopiaTown.habitatThreshold + offset] = tile
            }
        }
        let hungry = PokopiaTown.development(field, residents: [])
        XCTAssertLessThan(hungry.level, PokopiaTown.maxLevel, "전제: 천장 아래여야 한다")

        let fed = PokopiaTown.development(field, residents: [], fed: true)

        XCTAssertEqual(fed.level, hungry.level + 1)
    }

    /// 이사 판정은 포만감을 **안 본다.** `immigrant` 가 부르는 `development` 는 기본값 `false` 라
    /// 정원이 그대로이고, 그것이 "판정 세 축을 안 건드린다" 의 실체다.
    func testImmigrationIgnoresSatiety() {
        let terrain = Array(repeating: TownTerrain.water, count: PokopiaTown.tileCount)
        let types: [Int: [PokemonType]] = [7: [.water], 116: [.water], 129: [.water]]
        let pool = [7, 116, 129]

        let a = PokopiaTown.immigrant(terrain: terrain, pool: pool, typeIndex: types,
                                      residents: [], roll: 1)
        let b = PokopiaTown.immigrant(terrain: terrain, pool: pool, typeIndex: types,
                                      residents: [], roll: 1)

        XCTAssertEqual(a, b, "같은 입력이 다른 종을 줬다")
        XCTAssertNotNil(a)
    }

    // MARK: 저장 — 옛 세이브와 왕복

    /// **9단계 이전 세이브**(`fedUntil`·`townCraft` 키가 없다)가 그대로 열린다.
    /// 손으로 쓴 JSON 이 아니라 **지금 코드로 굽고 그 키만 지운다** — 손으로 쓰면 `[UUID: …]` 가
    /// 배열로 굽혀 조용히 통과하는 초록 테스트가 된다(`PokopiaTownMigrationTests` 의 규칙).
    func testASaveWithoutTheNewKeysOpensWithNothingInFlight() throws {
        let seedURL = storeStateURL("pokopia-craft-seed")
        let seeded = store(at: seedURL)
        stock(seeded, for: recipe(.townKitchen))
        seeded.startTownCraft(recipe(.townKitchen))
        let data = try Data(contentsOf: seedURL)
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(root.removeValue(forKey: "townCraft"),
                        "굽힌 JSON 에 townCraft 키가 없다 — 이 테스트가 지울 것이 없다")
        let url = storeStateURL("pokopia-craft-legacy")
        try JSONSerialization.data(withJSONObject: root).write(to: url)

        let reopened = store(at: url)

        XCTAssertNil(reopened.state.townCraft)
        XCTAssertNil(reopened.memoryAlbum.town.fedUntil)
        XCTAssertEqual(reopened.state.starPieces, seeded.state.starPieces,
                       "세이브가 손상 처리됐다 — 기존 사용자의 지갑이 날아가는 경로다")
    }

    /// 포만감이 앨범 파일을 왕복한다. 저장이 안 되면 창을 닫는 순간 레벨이 한 단 떨어진다.
    func testSatietySurvivesAnAlbumRoundTrip() {
        let file = memoryAlbumURL("pokopia-craft-album")
        let album = PokemonMemoryAlbum(fileURL: file)
        let until = now.addingTimeInterval(6 * 3600)
        XCTAssertTrue(album.feedTown(until: until))

        let reopened = PokemonMemoryAlbum(fileURL: file)

        XCTAssertEqual(reopened.town.fedUntil, until)
    }

    // MARK: 공유 실행 경로 (대화·터미널이 같은 표를 읽는다)

    func testUsingADishThroughTheSharedPathFeedsTheTown() {
        let s = store()
        giveDish(s, .dishHerbSoup)

        let outcome = CompanionAction.useItem(.dishHerbSoup, companion: s)

        let hours = try! XCTUnwrap(recipe(.dishHerbSoup).satietyHours)
        XCTAssertEqual(outcome, .townFed(until: now.addingTimeInterval(TimeInterval(hours) * 3600)))
        XCTAssertEqual(s.itemCount(.dishHerbSoup), 0)
    }

    /// 재고가 없으면 `.unavailable`(사러 가야 한다)이지 `.refused` 가 아니다 — 두 사유를 뭉개면
    /// 부르는 쪽이 사용자에게 무엇을 하라고 말해야 할지 모른다.
    func testUsingADishYouDoNotHaveIsUnavailable() {
        XCTAssertEqual(CompanionAction.useItem(.dishHerbSoup, companion: store()), .unavailable)
    }

    /// 재료·설비는 `.notUsedThisWay` 다 — 재고가 있어도 그렇다(쓰는 물건이 아니다).
    func testMaterialsAndFacilitiesAreNotUsedFromTheBag() {
        let s = store()
        s.debugSetItemCount(.townWood, 9)
        s.debugSetItemCount(.townKitchen, 1)

        XCTAssertEqual(CompanionAction.useItem(.townWood, companion: s), .notUsedThisWay)
        XCTAssertEqual(CompanionAction.useItem(.townKitchen, companion: s), .notUsedThisWay)
        XCTAssertEqual(s.itemCount(.townWood), 9, "쓰지도 않았는데 재료가 빠졌다")
    }

    // MARK: 네임드 NPC 배율 (10단계 — 켜진 쪽과 꺼진 쪽을 함께 센다)

    /// 두드리짱 거장(용광로)이 없으면 레시피 시간 그대로다. **꺼진 쪽을 먼저 못 박는다** — 켜진 쪽만
    /// 보면 배율을 상수 1 로 바꿔도 초록이다(#56 회귀의 부류).
    func testACraftTakesItsRecipeTimeWithoutTheArtisan() {
        let s = store()
        let dish = recipe(.dishFruitSalad)
        stock(s, for: dish)
        XCTAssertFalse(s.townNPCs.contains(.artisan), "용광로가 없는데 장인이 있다")

        XCTAssertTrue(s.startTownCraft(dish))
        XCTAssertEqual(s.state.townCraft?.readyAt,
                       now.addingTimeInterval(TimeInterval(dish.minutes) * 60))
    }

    /// 용광로를 가지면 두드리짱이 서고, 그 뒤 거는 제작이 짧아진다. 용광로 자체는 소모되지 않는다.
    func testTheArtisanShortensTheCraftThatIsStartedAfterHim() {
        let s = store()
        let dish = recipe(.dishFruitSalad)
        stock(s, for: dish)
        s.debugSetItemCount(.townFurnace, 1)
        XCTAssertTrue(s.townNPCs.contains(.artisan))

        XCTAssertTrue(s.startTownCraft(dish))
        let expected = PokopiaTownNPC.craftMinutes(dish.minutes, artisan: true)
        XCTAssertEqual(s.state.townCraft?.readyAt, now.addingTimeInterval(TimeInterval(expected) * 60))
        XCTAssertLessThan(try! XCTUnwrap(s.state.townCraft?.readyAt),
                          now.addingTimeInterval(TimeInterval(dish.minutes) * 60))
    }

    /// 요씽셰프(조리대)가 없으면 포만감이 레시피 값 그대로다.
    func testFeedingWithoutTheChefUsesTheRecipeHours() {
        let s = store()
        giveDish(s, .dishHerbSoup)
        XCTAssertFalse(s.townNPCs.contains(.chef), "조리대가 없는데 셰프가 있다")
        let hours = try! XCTUnwrap(recipe(.dishHerbSoup).satietyHours)

        XCTAssertEqual(s.feedTown(.dishHerbSoup), now.addingTimeInterval(TimeInterval(hours) * 3600))
    }

    /// 조리대를 가지면 요씽셰프가 서고, 같은 요리가 더 오래 먹인다.
    func testTheChefMakesTheSameDishFeedTheTownLonger() {
        let s = store()
        giveDish(s, .dishHerbSoup)
        s.debugSetItemCount(.townKitchen, 1)
        XCTAssertTrue(s.townNPCs.contains(.chef))
        let hours = try! XCTUnwrap(recipe(.dishHerbSoup).satietyHours)
        let lifted = PokopiaTownNPC.satietyHours(hours, chef: true)

        let until = s.feedTown(.dishHerbSoup)

        XCTAssertEqual(until, now.addingTimeInterval(TimeInterval(lifted) * 3600))
        XCTAssertGreaterThan(try! XCTUnwrap(until), now.addingTimeInterval(TimeInterval(hours) * 3600))
    }

    /// 셰프가 있어도 **상한은 그대로다.** 배율이 상한 위로 새면 축 C 가 한 번 켜고 잊는 스위치가 된다.
    func testTheChefCannotPushSatietyPastTheCeiling() {
        let s = store()
        s.debugSetItemCount(.townKitchen, 1)
        giveDish(s, .dishPokopiaSet, 10)
        for _ in 0..<10 { _ = s.feedTown(.dishPokopiaSet) }

        let fedUntil = try! XCTUnwrap(s.memoryAlbum.town.fedUntil)
        XCTAssertLessThanOrEqual(fedUntil, now.addingTimeInterval(PokopiaCrafting.maxSatiety))
    }
}
