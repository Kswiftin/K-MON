import XCTest
@testable import PokeTokenBar

// MARK: 지닌물건 진화 (#89)

/// 지닌물건(왕의징표석·금속코트 …) 진화는 PokéAPI 에서 `trigger=trade`(또는 level-up) + `held_item`
/// 으로 온다. 앱이 `held_item` 을 읽지 않던 동안 그 조건은 "교환 진화" 하나로 뭉개졌고, 연결의끈
/// 하나로 야도킹·킹크로스까지 진화됐다. 여기 테스트는 두 가지를 지킨다 —
/// (1) 전용 아이템으로만 열리는 진화가 실제로 열린다, (2) 연결의끈으로는 열리지 않는다.
///
/// 조건이 뭉개진 것을 예전 테스트가 못 걸러낸 이유: 픽스처가 `held_item` 이 없는 순수 교환 노드만
/// 썼다 — 연결의끈이 통하는 것만 확인해서, 통하면 안 되는 경로를 한 번도 밟지 않았다.

// MARK: 픽스처

private func names(_ tree: EvoNode) -> [Int: [String: String]] {
    func ids(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(ids) }
    var out: [Int: [String: String]] = [:]
    for id in ids(tree) { out[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return out
}
private func heldLine(base: Int, tree: EvoNode) -> EvoLine {
    EvoLine(baseID: base, tree: tree, rarity: .common, names: names(tree))
}

/// 야돈 → 야도킹: 교환 + 왕의징표석. 순수 교환 진화와 겉보기 트리거가 같아(둘 다 trade)
/// 연결의끈이 잘못 통하던 바로 그 형태다.
private let kingsRockLine = heldLine(base: 79, tree: EvoNode(speciesID: 79, children: [
    EvoNode(speciesID: 199, children: [], evolutionTrigger: "trade", evolutionHeldItem: "kings-rock"),
]))

/// 알통몬 → 괴력몬: 지닌물건 없는 순수 교환 진화 — 연결의끈 담당. 대조군이 없으면 "연결의끈을
/// 아예 무력화" 로 고쳐 놓고도 위 테스트들이 초록이다.
private let plainTradeLine = heldLine(base: 67, tree: EvoNode(speciesID: 67, children: [
    EvoNode(speciesID: 68, children: [], evolutionTrigger: "trade"),
]))

/// 포푸니 → 포푸니라: 예리한손톱을 지닌 채 **레벨업**(밤). 트리거가 trade 도 use-item 도 아니라,
/// 트리거만 보는 코드에서는 조용히 빠진다 — 졸업 면제 가드가 특히 그렇다.
private let razorClawLine = heldLine(base: 215, tree: EvoNode(speciesID: 215, children: [
    EvoNode(speciesID: 461, children: [], evolutionTrigger: "level-up", evolutionHeldItem: "razor-claw"),
]))

/// 진화 조건 없는 3단 라인(레벨 진화 대조군).
private let levelLine = heldLine(base: 1, tree: EvoNode(speciesID: 1, children: [
    EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])]),
]))

private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@MainActor
final class HeldItemEvolutionTests: XCTestCase {
    private func store(_ line: EvoLine) -> CompanionStore {
        let url = storeStateURL("held")
        return CompanionStore(provider: StubProvider(value: line), clock: { fixedNow },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    // MARK: (a) 전용 아이템은 통한다

    func testKingsRockEvolvesItsHeldItemTrade() async {
        let s = store(kingsRockLine)
        await s.hatch(baseID: 79)
        s.debugAddItem(.kingsRock)

        XCTAssertTrue(s.canUseEvolutionItem(.kingsRock))
        XCTAssertTrue(s.useEvolutionItem(.kingsRock))
        XCTAssertEqual(s.currentSpeciesID, 199)
        XCTAssertEqual(s.itemCount(.kingsRock), 0, "쓰면 소모된다")
    }

    /// 트리거가 level-up 인 지닌물건 진화도 같은 아이템으로 열려야 한다 — 앱엔 '지닌물건을 들린 채
    /// 레벨업' 축이 없어, 이 경로가 막히면 포푸니라·엘레키블 등은 진화할 방법이 아예 없다.
    func testRazorClawEvolvesItsLevelUpHeldItemNode() async {
        let s = store(razorClawLine)
        await s.hatch(baseID: 215)
        s.debugAddItem(.razorClaw)

        XCTAssertTrue(s.useEvolutionItem(.razorClaw))
        XCTAssertEqual(s.currentSpeciesID, 461)
    }

    /// 파트너 카드 안내도 전용 아이템을 가리켜야 한다 — 예전엔 trade 트리거만 보고 "연결의끈 필요"
    /// 라고 안내해, 사서 쓸 수 없는 아이템을 사게 만들었다.
    func testNextEvolutionItemNamesTheHeldItem() async {
        let s = store(kingsRockLine)
        await s.hatch(baseID: 79)
        XCTAssertEqual(s.nextEvolutionItem, .kingsRock)

        let level = store(razorClawLine)
        await level.hatch(baseID: 215)
        XCTAssertEqual(level.nextEvolutionItem, .razorClaw)
    }

    // MARK: (b) 연결의끈은 지닌물건 진화에 통하지 않는다 (트리거 브랜치)

    func testLinkingCordCannotEvolveAHeldItemTrade() async {
        let s = store(kingsRockLine)
        await s.hatch(baseID: 79)
        s.debugAddItem(.linkingCord)

        XCTAssertFalse(s.canUseEvolutionItem(.linkingCord), "지닌물건이 필요한 교환 진화다")
        XCTAssertFalse(s.useEvolutionItem(.linkingCord))
        XCTAssertEqual(s.currentSpeciesID, 79, "진화하지 않았고")
        XCTAssertEqual(s.itemCount(.linkingCord), 1, "재고도 줄지 않는다")
    }

    /// 대조군: 지닌물건이 없는 순수 교환 진화는 연결의끈으로 그대로 열린다.
    func testLinkingCordStillEvolvesPlainTrades() async {
        let s = store(plainTradeLine)
        await s.hatch(baseID: 67)
        s.debugAddItem(.linkingCord)

        XCTAssertTrue(s.useEvolutionItem(.linkingCord))
        XCTAssertEqual(s.currentSpeciesID, 68)
        XCTAssertEqual(s.nextEvolutionItem, nil, "최종형이라 더 쓸 아이템이 없다")
    }

    // MARK: (c) 엉뚱한 아이템은 실패하고 재고도 줄지 않는다

    func testWrongHeldItemNeitherEvolvesNorConsumes() async {
        let s = store(kingsRockLine)
        await s.hatch(baseID: 79)
        s.debugAddItem(.metalCoat)
        s.debugAddItem(.fireStone)

        XCTAssertFalse(s.useEvolutionItem(.metalCoat), "다른 지닌물건은 통하지 않는다")
        XCTAssertFalse(s.useEvolutionItem(.fireStone), "돌도 통하지 않는다")
        XCTAssertEqual(s.currentSpeciesID, 79)
        XCTAssertEqual(s.itemCount(.metalCoat), 1)
        XCTAssertEqual(s.itemCount(.fireStone), 1)
    }

    /// 재고 0이면 조건이 맞아도 못 쓴다(음수 재고 방지).
    func testCannotUseHeldItemWithoutStock() async {
        let s = store(kingsRockLine)
        await s.hatch(baseID: 79)

        XCTAssertFalse(s.canUseEvolutionItem(.kingsRock))
        XCTAssertFalse(s.useEvolutionItem(.kingsRock))
        XCTAssertEqual(s.itemCount(.kingsRock), 0)
    }

    // MARK: (d) 졸업 면제 착취 회귀 가드

    /// 500 짜리 아이템 하나로 레벨 1 개체를 최종형으로 만들어 졸업 보상(알·도감·트레이너 포인트)을
    /// 받아 가는 경로(#19)는 지닌물건 아이템에도 닫혀 있어야 한다.
    func testHeldItemEvolvedFinalGetsNoLevelExemption() async {
        let s = store(kingsRockLine)
        await s.hatch(baseID: 79)
        let eggsBefore = s.focusEggCount
        s.debugAddItem(.kingsRock)

        XCTAssertTrue(s.useEvolutionItem(.kingsRock), "진화 자체는 막지 않는다")
        XCTAssertLessThan(s.state.active!.level, PokemonBalance.graduationRequiredLevel)
        XCTAssertFalse(s.canGraduate, "레벨 관문을 지나온 개체가 아니다")
        XCTAssertFalse(s.graduateCompanion())
        XCTAssertTrue(s.state.dex.isEmpty)
        XCTAssertEqual(s.focusEggCount, eggsBefore)
    }

    /// level-up + 지닌물건 경로가 특히 위험하다 — trigger 가 use-item/trade 가 아니라서, 트리거만
    /// 보는 가드에서는 "레벨로 진화해 온 개체" 로 오인돼 면제를 그대로 받아 간다.
    func testRazorClawEvolvedFinalGetsNoLevelExemption() async {
        let s = store(razorClawLine)
        await s.hatch(baseID: 215)
        s.debugAddItem(.razorClaw)

        XCTAssertTrue(s.useEvolutionItem(.razorClaw))
        XCTAssertLessThan(s.state.active!.level, PokemonBalance.graduationRequiredLevel)
        XCTAssertFalse(s.canGraduate, "지닌물건 진화도 아이템 진화다")
        XCTAssertEqual(s.graduationLevelRequirement, PokemonBalance.graduationRequiredLevel,
                       "왜 졸업이 안 되는지 화면에 뜬다")
    }

    /// 금지가 아니라 관문이다 — 레벨 30 을 채우면 졸업된다.
    func testHeldItemEvolvedGraduatesOnceItReachesLevelThirty() async {
        let s = store(kingsRockLine)
        await s.hatch(baseID: 79)
        s.debugAddItem(.kingsRock)
        XCTAssertTrue(s.useEvolutionItem(.kingsRock))

        s.debugAccrueLevelExperience(300_000_000)
        XCTAssertTrue(s.canGraduate)
        XCTAssertTrue(s.graduateCompanion())
        XCTAssertEqual(s.dexEntries.count, 1)
    }

    /// 대조군: 레벨로 진화해 온 개체의 면제는 그대로다(면제를 전면 폐지한 게 아니다).
    func testLevelEvolvedCompanionKeepsItsExemption() async {
        let s = store(levelLine)
        await s.hatch(baseID: 1)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))

        XCTAssertEqual(s.currentSpeciesID, 3)
        XCTAssertLessThan(s.state.active!.level, PokemonBalance.graduationRequiredLevel)
        XCTAssertTrue(s.canGraduate)
    }

    // MARK: (e) 상점 노출

    func testHeldItemsAreOnSaleAtStonePrice() {
        let url = storeStateURL("held-shop")
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,\"installBaselineSet\":true,"
            + "\"usedSinceInstall\":100000,\"spentTokens\":0,\"starPieces\":100000,\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        let s = CompanionStore(provider: StubProvider(value: kingsRockLine), clock: { fixedNow },
                              fileURL: url, rng: SeededRNG(seed: 7))

        for kind in ItemKind.allCases where kind.isEvolutionItem {
            XCTAssertTrue(s.purchasableItems.contains(kind), "\(kind) 가 상점 목록에 없다")
            XCTAssertTrue(s.canBuy(kind), "\(kind) 를 살 수 없다")
        }
        XCTAssertTrue(s.buy(.kingsRock))
        XCTAssertEqual(s.itemCount(.kingsRock), 1)
        XCTAssertEqual(s.availableTokens, 100_000 - ItemKind.evolutionItemPrice)
    }

    /// 같은 값 아이템이 28종이라 가격만으로는 순서가 안 정해진다 — 목록이 열 때마다 뒤바뀌면
    /// 사용자가 아이템을 찾을 수 없다. 두 번 읽어 같은 순서인지 확인한다.
    func testShopOrderIsDeterministic() {
        let s = store(kingsRockLine)
        XCTAssertEqual(s.purchasableItems, s.purchasableItems)
        XCTAssertEqual(s.shopEntries, s.shopEntries)
        let prices = s.shopEntries.map(\.price)
        XCTAssertEqual(prices, prices.sorted(), "가격 오름차순 불변식은 유지")
    }

    // MARK: (f) held_item 파싱이 EvoNode 까지 도달한다

    /// 필드를 안 읽으면 조건이 조용히 뭉개진다 — 파싱 단계에서 값이 살아 있는지 직접 본다.
    func testHeldItemSurvivesChainParsing() throws {
        let json = """
        {"species":{"name":"slowpoke","url":"https://pokeapi.co/api/v2/pokemon-species/79/"},
         "evolution_details":[],
         "evolves_to":[
           {"species":{"name":"slowbro","url":"https://pokeapi.co/api/v2/pokemon-species/80/"},
            "evolves_to":[],
            "evolution_details":[{"min_level":37,"trigger":{"name":"level-up","url":null},"item":null,"held_item":null}]},
           {"species":{"name":"slowking","url":"https://pokeapi.co/api/v2/pokemon-species/199/"},
            "evolves_to":[],
            "evolution_details":[{"min_level":null,"trigger":{"name":"trade","url":null},"item":null,
                                  "held_item":{"name":"kings-rock","url":null}}]}
         ]}
        """
        let link = try JSONDecoder().decode(ChainLink.self, from: Data(json.utf8))
        let tree = PokeAPIClient.evoNode(from: link)

        let slowking = try XCTUnwrap(tree.node(withID: 199))
        XCTAssertEqual(slowking.evolutionTrigger, "trade")
        XCTAssertEqual(slowking.evolutionHeldItem, "kings-rock")
        XCTAssertNil(slowking.evolutionItem, "held_item 은 item 자리에 오지 않는다")
        XCTAssertNil(try XCTUnwrap(tree.node(withID: 80)).evolutionHeldItem, "레벨 진화엔 지닌물건이 없다")

        // 트리를 다시 만드는 경로에서 필드가 조용히 nil 로 떨어지지 않아야 한다 —
        // 부화 라인은 항상 이 필터를 지나므로, 여기서 빠지면 진화 조건이 앱 전체에서 사라진다.
        let filtered = try XCTUnwrap(tree.keepingAnimatedSprites())
        XCTAssertEqual(try XCTUnwrap(filtered.node(withID: 199)).evolutionHeldItem, "kings-rock")

        // 저장/복원(Codable)에서도 유지된다.
        let round = try JSONDecoder().decode(EvoNode.self, from: JSONEncoder().encode(tree))
        XCTAssertEqual(try XCTUnwrap(round.node(withID: 199)).evolutionHeldItem, "kings-rock")
    }

    /// 구작 PokéAPI 조건(특정 장소 레벨업)을 앱이 지원하는 현행 본가 조건(천둥의돌)으로 바꾼다.
    /// 이 보정이 없으면 레어코일은 레벨·아이템 어느 경로에서도 자포코일로 진화할 수 없다.
    func testMagnetonEvolutionNormalizesToThunderStone() throws {
        let json = """
        {"species":{"name":"magneton","url":"https://pokeapi.co/api/v2/pokemon-species/82/"},
         "evolution_details":[],
         "evolves_to":[
           {"species":{"name":"magnezone","url":"https://pokeapi.co/api/v2/pokemon-species/462/"},
            "evolves_to":[],
            "evolution_details":[{"min_level":null,"min_happiness":null,
              "trigger":{"name":"level-up","url":null},"item":null,"held_item":null}]}
         ]}
        """
        let tree = PokeAPIClient.evoNode(from: try JSONDecoder().decode(ChainLink.self, from: Data(json.utf8)))
        let magnezone = try XCTUnwrap(tree.node(withID: 462))
        XCTAssertEqual(magnezone.evolutionTrigger, "use-item")
        XCTAssertEqual(magnezone.evolutionItem, "thunder-stone")
        XCTAssertTrue(ItemKind.thunderStone.evolutionRule?.opens(magnezone) == true)
    }

    func testEvolutionGenderSurvivesChainParsing() throws {
        let json = """
        {"species":{"name":"combee","url":"https://pokeapi.co/api/v2/pokemon-species/415/"},
         "evolution_details":[],"evolves_to":[
          {"species":{"name":"vespiquen","url":"https://pokeapi.co/api/v2/pokemon-species/416/"},
           "evolves_to":[],"evolution_details":[{"min_level":21,"min_happiness":null,
            "trigger":{"name":"level-up","url":null},"item":null,"held_item":null,"gender":1}]}
         ]}
        """
        let tree = PokeAPIClient.evoNode(from: try JSONDecoder().decode(ChainLink.self, from: Data(json.utf8)))
        XCTAssertEqual(try XCTUnwrap(tree.node(withID: 416)).evolutionGender, .female)
    }

    func testKnownMoveSurvivesChainParsing() throws {
        let json = """
        {"species":{"name":"lickitung","url":"https://pokeapi.co/api/v2/pokemon-species/108/"},
         "evolution_details":[],"evolves_to":[
          {"species":{"name":"lickilicky","url":"https://pokeapi.co/api/v2/pokemon-species/463/"},
           "evolves_to":[],"evolution_details":[{"min_level":null,"min_happiness":null,
            "trigger":{"name":"level-up","url":null},"item":null,"held_item":null,"gender":null,
            "known_move":{"name":"rollout","url":"https://pokeapi.co/api/v2/move/205/"}}]}
         ]}
        """
        let tree = PokeAPIClient.evoNode(from: try JSONDecoder().decode(ChainLink.self, from: Data(json.utf8)))
        XCTAssertEqual(try XCTUnwrap(tree.node(withID: 463)).evolutionKnownMoveID, 205)
        XCTAssertEqual(try XCTUnwrap(tree.keepingAnimatedSprites()?.node(withID: 463)).evolutionKnownMoveID, 205)
    }

    /// 지닌물건 노드는 자동 진화로 넘어가지 않는다 — 아이템을 요구하는 진화가 레벨만으로 열리면
    /// 아이템 17종이 전부 무의미해지고, 졸업 면제 판정도 흔들린다.
    func testHeldItemNodeDoesNotAutoEvolve() async {
        let s = store(kingsRockLine)
        await s.hatch(baseID: 79)
        s.applyUsage(PokemonBalance.graduationTotal(.common))
        s.debugAccrueLevelExperience(300_000_000)

        XCTAssertEqual(s.currentSpeciesID, 79, "아이템 없이는 진화하지 않는다")
    }
}
