import XCTest
@testable import PokeTokenBar

/// 전체 도감 — 아직 안 잡은 종도 칸을 차지한다.
///
/// 도감이 보유 종만 그리던 시절엔 "내가 뭘 안 잡았는지" 를 볼 방법이 없었다. 칸을 열어 주는 대신
/// **필터마다 걸리는 범위가 달라진다** — 미포획 칸이 아는 건 번호와 타입뿐이라, 희귀도·이로치처럼
/// 잡아야 생기는 값으로는 판정할 수 없다. 그 갈림이 이 파일의 전부다.
@MainActor
final class DexFullListTests: XCTestCase {

    private let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                               rarity: .common, names: [1: ["ko": "포1", "en": "P1"]])

    private func store(_ entries: [DexEntry]) throws -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dex-full-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
        try Data(#"{"economyVersion":2,"forcedResetVersion":1,"dex":\#(dexJSON),"language":"ko"}"#.utf8)
            .write(to: url)
        return CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    private func entry(_ id: Int, rarity: Rarity = .common, shiny: Bool = false) -> DexEntry {
        DexEntry(baseID: id, finalID: id, chainOrder: [id], rarity: rarity,
                 caughtAt: Date(), isShiny: shiny,
                 names: [id: ["ko": "포\(id)", "en": "P\(id)"]])
    }

    private func slot(_ id: Int, caught: Bool, rarity: Rarity = .common, shiny: Bool = false)
        -> CompanionStore.DexSlot {
        CompanionStore.DexSlot(
            id: id,
            species: caught ? CompanionStore.DexSpecies(id: id, name: "포\(id)", rarity: rarity,
                                                        isShiny: shiny, isRaising: false)
                            : nil)
    }

    // MARK: 칸 만들기

    /// 격자가 획득 가능한 종 전체를 연다. 여기가 보유 종 수로 줄어 있으면 화면은 예전 그대로다.
    func testEveryObtainableSpeciesGetsACell() throws {
        let slots = try store([entry(1)]).dexSlots
        XCTAssertEqual(slots.count, PokemonAssets.animatedSpeciesIDs.count)
        XCTAssertEqual(slots.map(\.id), slots.map(\.id).sorted(), "도감 번호순")
        XCTAssertEqual(slots.filter(\.isCaught).map(\.id), [1])
    }

    /// **범위 밖 보유 종을 합집합으로 얹는다.** 이브이(#133) 라인은 님피아(#700)까지 뻗어 획득
    /// 가능 범위(1~649)를 넘어간다. 범위만 쓰면 실제로 가진 종이 자기 도감에서 빠진다.
    func testASpeciesCaughtOutsideTheRangeStillHasACell() throws {
        let outside = PokemonAssets.animatedSpeciesIDs.upperBound + 51
        let slots = try store([entry(outside)]).dexSlots
        XCTAssertEqual(slots.count, PokemonAssets.animatedSpeciesIDs.count + 1)
        XCTAssertEqual(slots.last?.id, outside)
        XCTAssertTrue(slots.last?.isCaught == true)
    }

    /// 미포획 칸은 종 정보를 통째로 비운다 — 이름·희귀도를 빈 값으로 채워 두면 화면이 그걸 진짜
    /// 정보처럼 그린다("#150 · 일반" 같은 칸).
    func testAnUncaughtCellCarriesNoSpeciesInformation() throws {
        let slots = try store([entry(1)]).dexSlots
        XCTAssertNil(slots.first(where: { $0.id == 2 })?.species)
        XCTAssertNotNil(slots.first(where: { $0.id == 1 })?.species)
    }

    // MARK: 필터가 걸리는 범위

    /// 기본은 잡은 것만이다. 처음 여는 사람에게 649칸 실루엣부터 보이면 자기 수집물이 묻힌다.
    func testTheDefaultIsCaughtOnly() {
        let filter = CompanionStore.DexFilter()
        XCTAssertTrue(filter.caughtOnly)
        XCTAssertFalse(filter.matches(slot(2, caught: false), typesBySpecies: [:]))
        XCTAssertTrue(filter.matches(slot(1, caught: true), typesBySpecies: [:]))
    }

    /// **타입은 미포획에도 걸린다.** 이게 안 되면 "아직 안 잡은 물타입" 을 못 보고, 타입 필터는
    /// 이미 잡은 것만 다시 훑는 도구가 된다(도감 타입 목표가 바로 그걸 묻는데).
    func testTheTypeFilterReachesUncaughtCells() {
        let filter = CompanionStore.DexFilter(caughtOnly: false, type: .water)
        let types: [Int: [PokemonType]] = [7: [.water], 4: [.fire]]
        XCTAssertTrue(filter.matches(slot(7, caught: false), typesBySpecies: types))
        XCTAssertFalse(filter.matches(slot(4, caught: false), typesBySpecies: types))
    }

    /// 이중 타입은 두 축 모두에 걸린다 — 주 타입만 보면 갸라도스가 비행 필터에서 빠진다.
    func testASecondaryTypeCountsToo() {
        let types: [Int: [PokemonType]] = [130: [.water, .flying]]
        for type in [PokemonType.water, .flying] {
            let filter = CompanionStore.DexFilter(caughtOnly: false, type: type)
            XCTAssertTrue(filter.matches(slot(130, caught: false), typesBySpecies: types),
                          "\(type) 로 못 찾는다")
        }
    }

    /// 타입 표를 아직 못 받았으면 타입 필터는 **아무것도** 통과시키지 못한다. 그 상태를 그대로
    /// 두면 화면이 빈 격자가 되므로 뷰가 필터를 잠근다 — 이 단언이 잠금의 근거다.
    func testAnEmptyTypeIndexMatchesNothing() {
        let filter = CompanionStore.DexFilter(type: .water)
        XCTAssertFalse(filter.matches(slot(7, caught: true), typesBySpecies: [:]))
    }

    /// **희귀도를 고르면 미포획이 빠진다.** 미포획 칸에는 희귀도가 없어 통과시킬 근거가 없다.
    /// 그냥 통과시키면 "전설만 보기" 가 실루엣 600칸을 함께 끌고 온다.
    func testChoosingARarityDropsUncaughtCells() {
        let filter = CompanionStore.DexFilter(caughtOnly: false, rarity: .rare)
        XCTAssertTrue(filter.caughtOnlyLocked, "잡은 것만 보기가 켜진 것과 같아진다")
        XCTAssertFalse(filter.matches(slot(2, caught: false), typesBySpecies: [:]))
        XCTAssertTrue(filter.matches(slot(3, caught: true, rarity: .rare), typesBySpecies: [:]))
        XCTAssertFalse(filter.matches(slot(1, caught: true, rarity: .common), typesBySpecies: [:]))
    }

    /// 이로치도 같은 이유로 미포획을 뺀다.
    func testTheShinyFilterDropsUncaughtCells() {
        let filter = CompanionStore.DexFilter(caughtOnly: false, shinyOnly: true)
        XCTAssertTrue(filter.caughtOnlyLocked)
        XCTAssertFalse(filter.matches(slot(2, caught: false), typesBySpecies: [:]))
        XCTAssertTrue(filter.matches(slot(1, caught: true, shiny: true), typesBySpecies: [:]))
    }

    /// 잠금은 희귀도·이로치가 걸렸을 때만이다 — 타입만 골랐는데 실루엣이 사라지면 안 된다.
    func testTypeAloneDoesNotLockCaughtOnly() {
        XCTAssertFalse(CompanionStore.DexFilter(caughtOnly: false, type: .water).caughtOnlyLocked)
        XCTAssertFalse(CompanionStore.DexFilter(caughtOnly: false).caughtOnlyLocked)
    }

    /// 축들은 **겹쳐 걸린다** — "희귀한 물타입 중 이로치" 가 나와야 한다. 배타로 두면 한 축을 고를
    /// 때마다 나머지가 풀린다.
    func testTheAxesCombineInsteadOfReplacingEachOther() {
        let types: [Int: [PokemonType]] = [1: [.water], 2: [.water], 3: [.fire]]
        let filter = CompanionStore.DexFilter(rarity: .rare, shinyOnly: true, type: .water)
        XCTAssertTrue(filter.matches(slot(1, caught: true, rarity: .rare, shiny: true),
                                     typesBySpecies: types))
        XCTAssertFalse(filter.matches(slot(2, caught: true, rarity: .rare, shiny: false),
                                      typesBySpecies: types), "이로치가 아니다")
        XCTAssertFalse(filter.matches(slot(3, caught: true, rarity: .rare, shiny: true),
                                      typesBySpecies: types), "물타입이 아니다")
    }

    // MARK: 타입 인덱스 싣기

    func testTheTypeIndexIsLoadedOnceAndKept() async throws {
        let provider = CountingTypeIndexProvider(value: line, types: [1: [.grass, .poison]])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dex-types-\(UUID().uuidString).json")
        try Data(#"{"economyVersion":2,"forcedResetVersion":1,"language":"ko"}"#.utf8).write(to: url)
        let store = CompanionStore(provider: provider, clock: { Date() },
                                   fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertTrue(store.speciesTypes.isEmpty, "받기 전엔 비어 있다 — 그때 필터가 잠긴다")

        await store.loadSpeciesTypeIndex()
        XCTAssertEqual(store.speciesTypes[1], [.grass, .poison])

        await store.loadSpeciesTypeIndex()
        let calls = await provider.callCount
        XCTAssertEqual(calls, 1, "이미 실었으면 다시 받지 않는다 — 도감을 열 때마다 요청이 나간다")
    }
}

/// 타입 인덱스 조회 횟수를 세는 스텁. `StubProvider` 는 기본 구현을 타 실제 네트워크로 나간다.
private actor CountingTypeIndexProvider: PokeProviding {
    private let value: EvoLine
    private let types: [Int: [PokemonType]]
    private(set) var callCount = 0

    init(value: EvoLine, types: [Int: [PokemonType]]) {
        self.value = value
        self.types = types
    }

    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        [BaseSpecies(id: value.baseID, captureRate: 255)]
    }
    func speciesTypeIndex() async throws -> [Int: [PokemonType]] {
        callCount += 1
        return types
    }
}
