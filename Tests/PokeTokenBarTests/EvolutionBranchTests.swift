import XCTest
@testable import PokeTokenBar

// MARK: 갈라지는 진화 — 화면이 갈래를 다 보여주는가

/// 슈륙챙이는 물의돌로 강챙이, 왕의징표석으로 왕구리가 된다. **둘 다 실제로 열린다** —
/// `useEvolutionItem` 은 계획을 보지 않고 그 아이템이 여는 갈래로 간다.
///
/// 그런데 화면 안내(`nextEvolutionItem`)는 **계획된 갈래 하나만** 말했다. 계획이 왕구리인 개체에는
/// "왕의징표석을 쓰면 진화" 만 떠서, 물의돌은 가방에서 멀쩡히 쓸 수 있는데도 존재 자체가 화면에
/// 없었다. 이브이는 갈래가 여덟이라 일곱이 숨는다.
///
/// 예전 테스트가 왜 못 걸렀나: 안내를 **갈래가 하나인 라인**으로만 확인했다. 갈래가 여럿일 때
/// 안내가 무엇을 빠뜨리는지는 한 번도 묻지 않았다.

private func chainNames(_ tree: EvoNode) -> [Int: [String: String]] {
    func ids(_ node: EvoNode) -> [Int] { [node.speciesID] + node.children.flatMap(ids) }
    var out: [Int: [String: String]] = [:]
    for id in ids(tree) { out[id] = ["ko": "포\(id)", "en": "P\(id)", "ja": "ポ\(id)"] }
    return out
}
private func line(base: Int, tree: EvoNode) -> EvoLine {
    EvoLine(baseID: base, tree: tree, rarity: .common, names: chainNames(tree))
}

/// 슈륙챙이 → 강챙이(물의돌) / 왕구리(교환 + 왕의징표석).
private let poliwhirlTree = EvoNode(speciesID: 61, children: [
    EvoNode(speciesID: 62, children: [], evolutionTrigger: "use-item", evolutionItem: "water-stone"),
    EvoNode(speciesID: 186, children: [], evolutionTrigger: "trade", evolutionHeldItem: "kings-rock"),
])
private let poliwhirlLine = line(base: 61, tree: poliwhirlTree)

/// 갈래가 하나뿐인 라인(대조군). 여기서 갈래 목록이 채워지면 모든 종에 메뉴가 붙는다.
private let singlePathLine = line(base: 1, tree: EvoNode(speciesID: 1, children: [
    EvoNode(speciesID: 2, children: [], evolutionLevel: 16),
]))

/// 조건을 못 밝히는 갈래가 섞인 경우 — 한쪽은 돌, 한쪽은 우리가 판정 못 하는 조건.
private let mixedConditionTree = EvoNode(speciesID: 133, children: [
    EvoNode(speciesID: 134, children: [], evolutionTrigger: "use-item", evolutionItem: "water-stone"),
    EvoNode(speciesID: 470, children: [], evolutionTrigger: "level-up"),
])
private let mixedConditionLine = line(base: 133, tree: mixedConditionTree)

private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@MainActor
final class EvolutionBranchTests: XCTestCase {

    private func store(_ evoLine: EvoLine) -> CompanionStore {
        let url = storeStateURL("branch")
        return CompanionStore(provider: StubProvider(value: evoLine), clock: { fixedNow },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    // MARK: 갈래 목록

    /// 갈래를 **하나도 빠뜨리지 않는다.** 이게 이 변경의 전부다.
    func testEveryBranchIsListed() async {
        let companion = store(poliwhirlLine)
        await companion.hatch(baseID: 61)
        XCTAssertEqual(companion.evolutionBranches.map(\.id).sorted(), [62, 186])
    }

    /// 갈래마다 **무엇을 하면 되는지**가 붙어 있어야 한다. 이름만 나열하면 "어느 쪽이 물의돌이지" 가 남는다.
    func testEachBranchCarriesTheThingThatOpensIt() async {
        let companion = store(poliwhirlLine)
        await companion.hatch(baseID: 61)
        let byID = Dictionary(uniqueKeysWithValues: companion.evolutionBranches.map { ($0.id, $0) })
        XCTAssertEqual(byID[62]?.item, .waterStone)
        XCTAssertEqual(byID[186]?.item, .kingsRock, "교환 + 지닌물건 갈래도 아이템으로 잡혀야 한다")
    }

    /// 갈래가 하나면 빈 배열 — 그때는 기존 한 줄 안내가 맡는다.
    /// 대조군이 없으면 "항상 메뉴를 띄운다" 는 오구현도 초록이다.
    func testASinglePathListsNoBranches() async {
        let companion = store(singlePathLine)
        await companion.hatch(baseID: 1)
        XCTAssertTrue(companion.evolutionBranches.isEmpty)
        XCTAssertEqual(companion.nextEvolutionLevel, 16, "기존 안내는 그대로 나와야 한다")
    }

    /// 조건을 못 밝히는 갈래도 **목록에는 남는다.** 빼 버리면 그 갈래는 다시 화면에서 사라진다 —
    /// 그게 애초에 고치려던 것이다.
    func testABranchWeCannotJudgeStaysInTheList() async {
        let companion = store(mixedConditionLine)
        await companion.hatch(baseID: 133)
        let byID = Dictionary(uniqueKeysWithValues: companion.evolutionBranches.map { ($0.id, $0) })
        XCTAssertEqual(byID.count, 2)
        XCTAssertEqual(byID[134]?.item, .waterStone)
        XCTAssertNil(byID[470]?.item)
        XCTAssertNil(byID[470]?.level, "조건을 지어내면 그걸 채우려다 시간을 버린다")
    }

    /// 이름은 지금 언어로 나온다 — 갈래 목록이 종 번호만 보여주면 무엇으로 가는지 모른다.
    func testBranchesAreNamedInTheCurrentLanguage() async {
        let companion = store(poliwhirlLine)
        await companion.hatch(baseID: 61)
        for branch in companion.evolutionBranches {
            XCTAssertEqual(branch.targetName,
                           poliwhirlLine.localizedName(branch.id, companion.language))
        }
    }

    // MARK: 목록과 실제 동작이 어긋나지 않는가

    /// **목록에 있으면 실제로 열려야 한다.** 안 열리는 갈래를 보여주면 안내가 거짓말이 된다.
    func testEveryListedItemBranchActuallyOpens() async {
        for branch in await branchesOfAFreshPoliwhirl() {
            guard let item = branch.item else { continue }
            let companion = store(poliwhirlLine)
            await companion.hatch(baseID: 61)
            companion.debugAddItem(item)
            XCTAssertTrue(companion.useEvolutionItem(item), "\(item) 갈래가 안 열린다")
            XCTAssertEqual(companion.currentSpeciesID, branch.id)
        }
    }

    /// **계획과 무관하다.** 아이템 사용은 계획을 보지 않는데 안내만 계획을 봐서 어긋나 있었다 —
    /// 계획이 왕구리인 개체에 물의돌을 써도 강챙이가 된다.
    func testAnItemOpensItsBranchEvenWhenThePlanPointsElsewhere() async {
        let companion = store(poliwhirlLine)
        await companion.hatch(baseID: 61)
        // 계획이 어느 쪽을 가리키든, 목록은 둘 다 들고 있어야 하고 둘 다 열려야 한다.
        let plannedItem = companion.nextEvolutionItem
        let otherItem: ItemKind = plannedItem == .waterStone ? .kingsRock : .waterStone
        companion.debugAddItem(otherItem)
        XCTAssertTrue(companion.canUseEvolutionItem(otherItem),
                      "계획에 없는 갈래도 가방에서는 쓸 수 있다 — 안내만 그걸 숨겼다")
        XCTAssertTrue(companion.useEvolutionItem(otherItem))
        XCTAssertNotEqual(companion.currentSpeciesID, 61)
    }

    private func branchesOfAFreshPoliwhirl() async -> [CompanionStore.EvolutionBranch] {
        let companion = store(poliwhirlLine)
        await companion.hatch(baseID: 61)
        return companion.evolutionBranches
    }

    // MARK: 문구

    func testBranchCopyExistsInAllThreeLanguages() {
        for language in AppLanguage.allCases {
            let localized = L(language)
            XCTAssertFalse(localized.evolutionBranchCount(2).isEmpty, "\(language) 개수 문구 누락")
            XCTAssertFalse(localized.evolutionBranchUnknownCondition.isEmpty, "\(language) 조건불명 문구 누락")
        }
        XCTAssertNotEqual(L(.ko).evolutionBranchCount(2), L(.en).evolutionBranchCount(2))
        XCTAssertNotEqual(L(.ko).evolutionBranchCount(2), L(.ja).evolutionBranchCount(2))
    }

    /// 갈래 한 줄은 조건과 대상이 **붙어** 있어야 한다 — 따로 놓으면 어느 쪽이 짝인지 모른다.
    func testABranchRowKeepsTheConditionNextToItsTarget() {
        let row = L(.ko).evolutionBranchRow(condition: "물의돌", target: "강챙이")
        XCTAssertTrue(row.contains("물의돌"))
        XCTAssertTrue(row.contains("강챙이"))
        XCTAssertLessThan(try XCTUnwrap(row.range(of: "물의돌")).lowerBound,
                          try XCTUnwrap(row.range(of: "강챙이")).lowerBound,
                          "조건이 앞, 대상이 뒤 — 읽는 순서가 곧 하는 순서다")
    }
}
