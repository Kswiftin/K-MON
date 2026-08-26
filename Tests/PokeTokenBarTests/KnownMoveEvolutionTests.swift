import XCTest
@testable import PokeTokenBar

// MARK: 막혀 있던 진화 — 기술 조건과 뒤쪽 줄의 돌

/// 진화 조건 열세 개가 **영영 열리지 않는 상태**였다. 두 원인이 겹쳐 있었다.
///
/// (1) 성장치 게이트가 `evolutionTrigger == nil` 을 요구했다. 의도는 "돌이 필요한 진화가 공짜로
///     열리면 안 된다" 였지만, 트리거는 장소·기술 조건 진화에도 `level-up` 으로 채워져 온다.
///     레벨 값이 없으니 레벨 게이트도 못 타고, 트리거가 있으니 성장치 게이트도 못 탄다.
/// (2) 진화 아이템을 `evolution_details[0]` 에서만 읽었다. 자포코일·대코파스·리피아·글레이시아는
///     첫 줄이 "특정 장소에서 레벨업" 이고 돌 줄은 목록 뒤쪽에 있다 — 앱에 장소가 없으니 막다른 길.
///
/// 예전 테스트가 왜 못 걸렀나: 픽스처가 전부 **첫 줄에 조건이 다 들어 있는** 형태였다. 한 노드에
/// 여러 줄이 오고 그중 뒤쪽만 우리가 열 수 있는 경우를 한 번도 만들지 않았다.

// MARK: 픽스처

private func chainNames(_ tree: EvoNode) -> [Int: [String: String]] {
    func ids(_ node: EvoNode) -> [Int] { [node.speciesID] + node.children.flatMap(ids) }
    var out: [Int: [String: String]] = [:]
    for id in ids(tree) { out[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return out
}
private func line(base: Int, tree: EvoNode) -> EvoLine {
    EvoLine(baseID: base, tree: tree, rarity: .common, names: chainNames(tree))
}

private let ancientPowerID = 246
private let rolloutID = 205

/// 메꾸리 → 맘모꾸리: 원시의힘을 배운 채로 자라야 한다. 레벨 조건은 **없다**.
private let knownMoveLine = line(base: 221, tree: EvoNode(speciesID: 221, children: [
    EvoNode(speciesID: 473, children: [], evolutionTrigger: "level-up",
            evolutionKnownMoveID: ancientPowerID),
]))

/// 레어코일 → 자포코일: 첫 줄은 장소, 우리가 읽는 건 뒤쪽의 천둥의돌 줄.
///
/// **노드를 손으로 적지 않고 파서에 통과시킨다.** 손으로 적으면 파서가 무엇을 내놓든 이 테스트는
/// 초록이라, 정작 확인하려던 "장소 줄 뒤의 돌을 찾아 실제로 진화까지 이어지는가" 를 못 본다.
private let stoneAfterLocationLine: EvoLine = {
    func row(item: String? = nil) -> ChainLink.EvolutionDetail {
        ChainLink.EvolutionDetail(min_level: nil, min_happiness: nil,
                                  trigger: NamedRef(name: item == nil ? "level-up" : "use-item", url: nil),
                                  item: item.map { NamedRef(name: $0, url: nil) },
                                  held_item: nil, gender: nil, known_move: nil,
                                  time_of_day: nil, relative_physical_stats: nil,
                                  party_species: nil, trade_species: nil)
    }
    let magnezone = ChainLink(species: NamedRef(name: "magnezone",
                                                url: "https://pokeapi.co/api/v2/pokemon-species/462/"),
                              evolves_to: [],
                              evolution_details: [row(), row(), row(item: "thunder-stone"), row()])
    let magneton = ChainLink(species: NamedRef(name: "magneton",
                                               url: "https://pokeapi.co/api/v2/pokemon-species/82/"),
                             evolves_to: [magnezone], evolution_details: [])
    return line(base: 82, tree: PokeAPIClient.evoNode(from: magneton))
}()

/// 타만타 → 만타인: 파티에 총어가 있어야 한다. **앱에 그 축이 없다** — 열리면 안 된다.
/// 대조군이 없으면 "트리거가 있으면 다 열어준다" 는 오구현도 초록이다.
private let partyConditionLine = line(base: 458, tree: EvoNode(speciesID: 458, children: [
    EvoNode(speciesID: 226, children: [], evolutionTrigger: "level-up"),
]))

private func move(_ id: Int) -> MoveSpec {
    MoveSpec(id: id, names: ["ko": "기술\(id)", "en": "m\(id)"], type: .rock, power: 60,
             damageClass: .special, accuracy: 100, pp: 5)
}

private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@MainActor
final class KnownMoveEvolutionTests: XCTestCase {

    private func store(_ evoLine: EvoLine) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("known-move-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: evoLine), clock: { fixedNow },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    /// 한 단계 넘기고도 남을 성장치. 조건이 맞으면 진화가 일어나고, 아니면 그대로다.
    private func growPastOneStage(_ store: CompanionStore) {
        store.debugAccrue(500_000_000)
    }

    // MARK: 기술 조건

    /// 기술이 없으면 아무리 키워도 진화하지 않는다 — 본가와 같은 규칙이다.
    func testAKnownMoveEvolutionStaysShutWithoutTheMove() async {
        let companion = store(knownMoveLine)
        await companion.hatch(baseID: 221)
        companion.debugSetActiveLearnedMoves([move(33)])
        growPastOneStage(companion)
        XCTAssertEqual(companion.currentSpeciesID, 221, "조건 없이 열리면 기술 조건이 무의미해진다")
    }

    /// 기술을 들고 있으면 열린다. **이게 이 변경의 전부다** — 예전엔 이 경우에도 안 열렸다.
    func testAKnownMoveEvolutionOpensOnceTheMoveIsLearned() async {
        let companion = store(knownMoveLine)
        await companion.hatch(baseID: 221)
        companion.debugSetActiveLearnedMoves([move(33), move(ancientPowerID)])
        growPastOneStage(companion)
        XCTAssertEqual(companion.currentSpeciesID, 473)
    }

    /// 다른 기술로는 안 열린다 — id 를 안 보고 "기술이 있기만 하면" 열면 이 단언이 깨진다.
    func testAnotherMoveDoesNotSatisfyTheRequirement() async {
        let companion = store(knownMoveLine)
        await companion.hatch(baseID: 221)
        companion.debugSetActiveLearnedMoves([move(rolloutID)])
        growPastOneStage(companion)
        XCTAssertEqual(companion.currentSpeciesID, 221)
    }

    /// 우리가 판정할 수 없는 조건(파티 구성·장소·shed)은 **여전히 닫아 둔다.**
    /// 트리거가 채워져 있으면 우리가 모르는 조건이라는 뜻이다.
    func testConditionsWeCannotJudgeStayShut() async {
        let companion = store(partyConditionLine)
        await companion.hatch(baseID: 458)
        companion.debugSetActiveLearnedMoves([move(ancientPowerID)])
        growPastOneStage(companion)
        XCTAssertEqual(companion.currentSpeciesID, 458, "성장치만으로 열면 조건이 사라진다")
    }

    // MARK: 화면이 조건을 밝히는가

    /// 조건을 안 밝히면 지금(영영 안 됨)보다 나을 뿐 "왜 안 되지" 는 그대로다.
    /// 기술을 배우면 안내가 **사라져야** 한다 — 안 그러면 조건을 채운 뒤에도 계속 요구한다.
    func testTheScreenNamesTheMoveUntilItIsLearned() async {
        let companion = store(knownMoveLine)
        await companion.hatch(baseID: 221)
        XCTAssertEqual(companion.nextEvolutionKnownMoveID, ancientPowerID)
        // 이름 문자열을 박으면 로케일을 탄다 — 게이트가 영어로도 한 번 더 돌린다.
        // 확인할 건 "무엇으로 진화하는지 말하는가" 이지 어느 언어로 말하는가가 아니다.
        XCTAssertEqual(companion.nextEvolutionName,
                       knownMoveLine.localizedName(473, companion.language),
                       "무엇으로 진화하는지도 말해야 한다")

        companion.debugSetActiveLearnedMoves([move(ancientPowerID)])
        await companion.loadEvolutionRequiredMove()
        XCTAssertNil(companion.evolutionRequiredMove, "조건을 채웠는데도 요구가 남으면 안 된다")
    }

    /// 안내를 다시 받을 시점을 정하는 값 — 기술이 바뀌면 달라져야 한다.
    /// 종만 보면 기술을 배운 뒤에도 "이 기술이 필요해요" 가 화면에 남는다.
    func testTheMoveSetIdentityChangesWhenAMoveIsLearned() async {
        let companion = store(knownMoveLine)
        await companion.hatch(baseID: 221)
        companion.debugSetActiveLearnedMoves([move(33)])
        let before = companion.currentMoveSetIdentity
        companion.debugSetActiveLearnedMoves([move(33), move(ancientPowerID)])
        XCTAssertNotEqual(before, companion.currentMoveSetIdentity)
    }

    // MARK: 뒤쪽 줄의 돌

    /// 첫 줄이 장소라 막다른 길이던 진화가 돌로 열린다. 상점은 이미 천둥의돌을 판다.
    func testTheStoneBehindALocationRowStillEvolves() async {
        let companion = store(stoneAfterLocationLine)
        await companion.hatch(baseID: 82)
        companion.debugAddItem(.thunderStone)

        XCTAssertEqual(companion.nextEvolutionItem, .thunderStone, "무엇을 사야 하는지 화면이 말해야 한다")
        XCTAssertTrue(companion.useEvolutionItem(.thunderStone))
        XCTAssertEqual(companion.currentSpeciesID, 462)
    }

    /// 돌이 붙었다고 성장치만으로 열리면 안 된다 — 돌 진화의 값어치가 사라진다.
    func testTheStoneEvolutionDoesNotOpenOnGrowthAlone() async {
        let companion = store(stoneAfterLocationLine)
        await companion.hatch(baseID: 82)
        growPastOneStage(companion)
        XCTAssertEqual(companion.currentSpeciesID, 82)
    }
}

// MARK: 파서 — 어느 줄에서 아이템을 읽는가

/// `evolution_details` 는 한 노드에 여러 줄이 온다. 어느 줄을 읽느냐가 곧 어떤 종이 진화하느냐다.
final class EvolutionItemRowTests: XCTestCase {

    private func detail(level: Int? = nil, happiness: Int? = nil, trigger: String = "level-up",
                        item: String? = nil, held: String? = nil,
                        knownMove: String? = nil) -> ChainLink.EvolutionDetail {
        ChainLink.EvolutionDetail(
            min_level: level, min_happiness: happiness,
            trigger: NamedRef(name: trigger, url: nil),
            item: item.map { NamedRef(name: $0, url: nil) },
            held_item: held.map { NamedRef(name: $0, url: nil) },
            gender: nil,
            known_move: knownMove.map { NamedRef(name: $0, url: "https://pokeapi.co/api/v2/move/246/") },
            time_of_day: nil, relative_physical_stats: nil,
            party_species: nil, trade_species: nil)
    }

    /// 보통은 첫 줄이다.
    func testTheFirstRowWins() {
        XCTAssertEqual(PokeAPIClient.evolutionCondition([detail(trigger: "use-item", item: "fire-stone")])?.item?.name,
                       "fire-stone")
    }

    /// **자포코일**: 장소 줄 다섯 개 뒤에 천둥의돌. 첫 줄만 읽으면 영영 못 찾는다.
    func testAStoneRowBehindLocationRowsIsFound() {
        let details = [detail(), detail(), detail(trigger: "use-item", item: "thunder-stone"), detail()]
        XCTAssertEqual(PokeAPIClient.evolutionCondition(details)?.item?.name, "thunder-stone")
        XCTAssertEqual(PokeAPIClient.evolutionCondition(details)?.trigger.name, "use-item",
                       "트리거도 같은 줄에서 와야 한다 — 갈리면 돌을 써도 안 열린다")
    }

    /// **모래두지**: 레벨 22 로 이미 진화하고, 뒤쪽 얼음의돌 줄은 **알로라 폼**으로 가는 길이다.
    /// 그걸 읽으면 표준 폼에 엉뚱한 돌이 붙어 얼음의돌로 고지가 나온다.
    func testALaterRegionalFormRowIsIgnoredWhenLevelAlreadyOpensIt() {
        let details = [detail(level: 22), detail(trigger: "use-item", item: "ice-stone")]
        XCTAssertNil(PokeAPIClient.evolutionCondition(details)?.item)
    }

    /// 친밀도 진화도 같다 — 레벨로 환산해 이미 열리므로 뒤쪽 줄을 볼 이유가 없다.
    func testALaterRowIsIgnoredWhenHappinessAlreadyOpensIt() {
        let details = [detail(happiness: 220), detail(trigger: "use-item", item: "sun-stone")]
        XCTAssertNil(PokeAPIClient.evolutionCondition(details)?.item)
    }

    /// **야도킹**: 지닌물건으로 이미 열린다. 뒤쪽에 리전폼용 돌 줄이 있어도 건드리지 않는다.
    func testALaterRowIsIgnoredWhenAHeldItemAlreadyOpensIt() {
        let details = [detail(trigger: "trade", held: "kings-rock"),
                       detail(trigger: "use-item", item: "galarica-cuff")]
        XCTAssertNil(PokeAPIClient.evolutionCondition(details)?.item)
    }

    /// 기술 조건은 노드에 실려야 한다 — 안 실리면 게이트가 그 조건을 못 본다.
    func testTheKnownMoveIsCarriedOntoTheNode() {
        let link = ChainLink(species: NamedRef(name: "piloswine",
                                              url: "https://pokeapi.co/api/v2/pokemon-species/221/"),
                             evolves_to: [], evolution_details: [detail(knownMove: "ancient-power")])
        XCTAssertEqual(PokeAPIClient.evoNode(from: link).evolutionKnownMoveID, 246)
    }

    /// 조건이 없는 보통 진화는 nil 이다 — 늘 채우면 모든 진화가 기술을 요구하게 된다.
    func testAnOrdinaryEvolutionCarriesNoMoveRequirement() {
        let link = ChainLink(species: NamedRef(name: "ivysaur",
                                              url: "https://pokeapi.co/api/v2/pokemon-species/2/"),
                             evolves_to: [], evolution_details: [detail(level: 16)])
        XCTAssertNil(PokeAPIClient.evoNode(from: link).evolutionKnownMoveID)
    }
}
