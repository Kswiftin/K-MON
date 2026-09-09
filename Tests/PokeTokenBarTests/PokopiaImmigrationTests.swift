import XCTest
@testable import PokeTokenBar

// MARK: 포코피아 마을 — 이사 (집중 세션이 부르는 사건)

@MainActor
final class PokopiaImmigrationTests: XCTestCase {

    /// 물 타입 종 넷을 담은 풀. 종 번호는 실제 물 계열이지만 타입은 스텁이 정한다.
    private static let waterPool = [7, 60, 72, 116]

    private func makeStore(seed: UInt64 = 7, tag: String = "pokopia-immigration",
                           pool: [Int] = waterPool,
                           types: [Int: [PokemonType]]? = nil,
                           lines: [Int: EvoLine]? = nil) -> CompanionStore {
        let base = EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                           names: [25: ["ko": "피카츄"]])
        // 풀의 모든 종이 이름을 얻을 수 있게 라인을 만들어 둔다 — 이름을 못 얻으면 이사가
        // 거절되므로, 그 경로를 따로 시험하는 테스트만 이 표를 비운다.
        let namedLines = lines ?? pool.reduce(into: [Int: EvoLine]()) { table, id in
            table[id] = EvoLine(baseID: id, tree: EvoNode(speciesID: id, children: []),
                                rarity: .common, names: [id: ["ko": "이웃\(id)"]])
        }
        let typeTable = types ?? pool.reduce(into: [Int: [PokemonType]]()) { $0[$1] = [.water] }
        let provider = TownAssemblyProvider(line: base, basePool: pool,
                                            types: typeTable, linesBySpecies: namedLines)
        return CompanionStore(provider: provider, clock: { Date(timeIntervalSince1970: 1_000) },
                              fileURL: storeStateURL(tag), rng: SeededRNG(seed: seed))
    }

    /// 물 지형을 문턱 이상 깔아 물 타입을 부르는 마을로 만든다.
    private func makeWatery(_ store: CompanionStore) {
        for col in 0..<PokopiaTown.habitatThreshold {
            XCTAssertTrue(store.memoryAlbum.shapeTownTile(col: col, row: 0, to: .water))
        }
    }

    /// 8지형 전부를 문턱까지 밀어 **정원을 절대 상한까지 연다**(개발도 8 → 16자리).
    ///
    /// 정원 게이트가 아닌 것을 세는 테스트는 이 픽스처를 쓴다. `makeWatery` 만 쓰면 개발도 3
    /// (물·풀·길 = 6자리)에서 막혀 "풀을 다 채운다" 같은 전제가 조용히 깨진다 — 실제로
    /// 정원 게이트를 넣을 때 그 두 테스트가 그렇게 깨졌다.
    private func makeDeveloped(_ store: CompanionStore) {
        for (row, terrain) in TownTerrain.allCases.enumerated() {
            for col in 0..<PokopiaTown.habitatThreshold {
                _ = store.memoryAlbum.shapeTownTile(col: col, row: row, to: terrain)
            }
        }
        // 결과를 센다 — `shapeTownTile` 은 이미 그 지형이면 false 라, 반환값을 단정하면
        // 기본 지형과 겹치는 줄(풀·길)에서 픽스처가 죽는다.
        let development = PokopiaTown.development(store.memoryAlbum.town.terrain)
        XCTAssertEqual(development.habitats, TownTerrain.allCases.count)
        XCTAssertEqual(development.capacity, PokopiaTown.populationLimit)
    }

    // MARK: 기본 경로

    func testAnImmigrantArrivesWithANameAndTypes() async throws {
        let store = makeStore()
        makeWatery(store)

        let arrived = await store.rollTownImmigration()
        let resident = try XCTUnwrap(arrived)

        XCTAssertTrue(Self.waterPool.contains(resident.speciesID))
        XCTAssertEqual(resident.name, "이웃\(resident.speciesID)",
                       "이름을 라인에서 안 가져왔다 — 오프라인에서 종 번호로 뜬다")
        XCTAssertEqual(resident.types, [.water])
        XCTAssertEqual(resident.arrivedAt, Date(timeIntervalSince1970: 1_000),
                       "`clock()` 이 아니라 `Date()` 를 썼다 — 테스트가 시계를 고정할 수 없다")
        XCTAssertEqual(store.memoryAlbum.town.residents.map(\.speciesID), [resident.speciesID],
                       "돌려주기만 하고 앨범에 안 넣었다")
    }

    // MARK: 결정성

    /// **결정성은 한 판 비교로 충분하지 않다** — 후보가 N개면 우연히 같아질 확률이 1/N 이다.
    /// 같은 시드로 여러 판을 돌려 결과 집합이 1개인지 본다(`defect-log.md` 의 규칙).
    func testImmigrationIsDeterministicForASeed() async {
        var results = Set<Int>()
        for round in 0..<10 {
            let store = makeStore(seed: 7, tag: "pokopia-immigration-det-\(round)")
            makeWatery(store)
            results.insert(await store.rollTownImmigration()?.speciesID ?? -1)
        }
        XCTAssertEqual(results.count, 1, "같은 시드가 다른 종을 뽑았다: \(results.sorted())")
        XCTAssertFalse(results.contains(-1), "결정적이긴 한데 아무도 안 왔다")
    }

    /// 다른 시드는 (대개) 다른 종을 뽑는다. 위 테스트만 있으면 "항상 첫 종" 인 구현도 통과한다.
    func testDifferentSeedsCanPickDifferentSpecies() async {
        var results = Set<Int>()
        for seed in UInt64(1)...UInt64(12) {
            let store = makeStore(seed: seed, tag: "pokopia-immigration-seed-\(seed)")
            makeWatery(store)
            if let picked = await store.rollTownImmigration()?.speciesID { results.insert(picked) }
        }
        XCTAssertGreaterThan(results.count, 1, "시드를 바꿔도 늘 같은 종이다 — 굴림을 안 쓰고 있다")
    }

    /// **굴림은 실패한 세션에서도 소비된다.**
    ///
    /// 조건부로 굴리면 같은 시드가 상황에 따라 다른 미래를 낸다. 이 함수에서 굴림이 조건에
    /// 걸릴 수 있는 자리는 **provider 실패 하나뿐**이다 — `roll` 이 `PokopiaTown.immigrant` 의
    /// **파라미터**라 후보 판정 이후로는 굴림을 미룰 방법이 구조적으로 없고, 꽉 찬 격자는
    /// 언제나 누군가를 부르므로 `welcomingTypes` 가 비는 분기도 실전에서 안 밟힌다
    /// (`PokopiaTownTests.testAFullGridAlwaysWelcomesSomebody` 가 그 사실을 못 박는다).
    ///
    /// 관측 방법: **같은 스토어**에서 한 번 실패시킨 뒤 성공시켜, 실패 없이 굴린 스토어와
    /// **도착 순서 전체**를 비교한다. 굴림 하나가 밀렸으면 순서가 달라진다. 한 판만 비교하면
    /// 후보가 N개일 때 1/N 로 우연히 같아지므로 순서열을 본다.
    ///
    /// `let roll` 을 `guard` 뒤로 옮기면 여기가 빨개진다(결함 주입으로 확인함).
    func testTheRollIsConsumedEvenWhenTheProviderFails() async {
        let pool = Array(1...8)
        let types = pool.reduce(into: [Int: [PokemonType]]()) { $0[$1] = [.water] }
        let lines = pool.reduce(into: [Int: EvoLine]()) { table, id in
            table[id] = EvoLine(baseID: id, tree: EvoNode(speciesID: id, children: []),
                                rarity: .common, names: [id: ["ko": "이웃\(id)"]])
        }

        // ① 한 번 실패시킨 뒤 성공으로 돌린다 — 실패한 세션이 굴림 하나를 태웠다.
        let toggling = TogglingTownProvider(pool: pool, types: types, lines: lines)
        toggling.failing = true
        let burned = CompanionStore(provider: toggling,
                                    clock: { Date(timeIntervalSince1970: 1_000) },
                                    fileURL: storeStateURL("pokopia-roll-burned"),
                                    rng: SeededRNG(seed: 7))
        makeDeveloped(burned)
        let refused = await burned.rollTownImmigration()
        XCTAssertNil(refused, "조회가 실패했는데 주민이 왔다")
        toggling.failing = false
        for _ in pool.indices { _ = await burned.rollTownImmigration() }
        let burnedOrder = burned.memoryAlbum.town.residents.map(\.speciesID)

        // ② 실패 없이 같은 시드로 굴린다.
        let clean = TogglingTownProvider(pool: pool, types: types, lines: lines)
        let control = CompanionStore(provider: clean,
                                     clock: { Date(timeIntervalSince1970: 1_000) },
                                     fileURL: storeStateURL("pokopia-roll-clean"),
                                     rng: SeededRNG(seed: 7))
        makeDeveloped(control)
        for _ in pool.indices { _ = await control.rollTownImmigration() }
        let cleanOrder = control.memoryAlbum.town.residents.map(\.speciesID)

        XCTAssertFalse(burnedOrder.isEmpty, "아무도 안 왔다 — 전제가 깨졌다")
        XCTAssertEqual(Set(burnedOrder), Set(cleanOrder), "둘 다 풀을 다 채워야 한다")
        XCTAssertNotEqual(burnedOrder, cleanOrder,
                          "굴림이 조건부로 소비되고 있다 — 실패한 세션이 굴림을 안 썼다")
    }

    /// 조회가 실패하면 조용히 넘어간다 — 매 세션 "아무도 안 왔어요" 를 띄우면 잔소리가 된다.
    func testAFailedLookupAdmitsNobodyAndKeepsTheTownIntact() async {
        let base = EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []),
                           rarity: .common, names: [25: ["ko": "피카츄"]])
        let store = CompanionStore(provider: FailingTownProvider(line: base),
                                   clock: { Date(timeIntervalSince1970: 1_000) },
                                   fileURL: storeStateURL("pokopia-immigration-fail-intact"),
                                   rng: SeededRNG(seed: 7))
        makeWatery(store)
        let nobody = await store.rollTownImmigration()
        XCTAssertNil(nobody)
        XCTAssertTrue(store.memoryAlbum.town.residents.isEmpty)
        // 지형은 그대로다 — 실패가 마을을 건드리지 않는다.
        XCTAssertEqual(PokopiaTown.tileCounts(store.memoryAlbum.town.terrain)[.water],
                       PokopiaTown.habitatThreshold)
    }

    // MARK: 멱등 · 상한

    /// **같은 종은 두 번 오지 않는다.** 이것이 이사의 멱등이고, 세션 단위 가드가 없는 근거다.
    func testTheSameSpeciesNeverArrivesTwice() async {
        let store = makeStore(pool: [7], types: [7: [.water]])
        makeWatery(store)

        let first = await store.rollTownImmigration()
        XCTAssertNotNil(first)
        let second = await store.rollTownImmigration()

        XCTAssertNil(second, "같은 종이 두 번 이사 왔다")
        XCTAssertEqual(store.memoryAlbum.town.residents.count, 1)
    }

    /// 여러 세션을 돌리면 풀이 마를 때까지 하나씩 온다 — 굴려도 인구가 두 배가 되지 않는다.
    func testRepeatedRollsFillTheTownWithoutDuplicates() async {
        let store = makeStore()
        makeWatery(store)
        for _ in 0..<(Self.waterPool.count + 3) { _ = await store.rollTownImmigration() }

        let residents = store.memoryAlbum.town.residents
        XCTAssertEqual(residents.count, Self.waterPool.count, "풀보다 많이 왔다")
        XCTAssertEqual(Set(residents.map(\.speciesID)).count, residents.count, "중복 종")
    }

    /// 절대 천장. 개발도를 끝까지 열어도 `populationLimit` 을 넘지 않는다.
    func testImmigrationStopsAtThePopulationLimit() async {
        let pool = Array(1...(PokopiaTown.populationLimit + 4))
        let store = makeStore(pool: pool,
                              types: pool.reduce(into: [:]) { $0[$1] = [.water] })
        makeDeveloped(store)
        for _ in 0..<(pool.count + 2) { _ = await store.rollTownImmigration() }

        XCTAssertEqual(store.memoryAlbum.town.residents.count, PokopiaTown.populationLimit)
        let overflow = await store.rollTownImmigration()
        XCTAssertNil(overflow, "꽉 찼는데 또 받았다")
    }

    /// **개발도가 정원이다 — 이 기능의 보상이 실제로 도는지 세는 가드.**
    ///
    /// 물·풀·길 3종만 넘긴 마을은 6자리에서 멈춘다. 거기서 지형 한 종을 더 만들면 **곧바로**
    /// 두 자리가 열려 다시 받는다. 앞부분만 세면 "그냥 6에서 막히는 기능" 과 구별되지 않는다.
    func testDiversityOpensMoreRoomAndTheGateReopensImmediately() async {
        let pool = Array(1...12)
        let store = makeStore(pool: pool,
                              types: pool.reduce(into: [:]) { $0[$1] = [.water] })
        makeWatery(store)   // 물·풀·길 = 3종 → 6자리

        let before = PokopiaTown.development(store.memoryAlbum.town.terrain)
        XCTAssertEqual(before.habitats, 3)
        XCTAssertEqual(before.capacity, 3 * PokopiaTown.residentsPerHabitat)

        for _ in 0..<(pool.count) { _ = await store.rollTownImmigration() }
        XCTAssertEqual(store.memoryAlbum.town.residents.count, before.capacity,
                       "개발도 3인데 정원을 넘겨 받았다")
        let refused = await store.rollTownImmigration()
        XCTAssertNil(refused, "정원이 찼는데 또 받았다")

        // 모래 6칸 — 한 종이 늘면 두 자리가 열린다.
        for col in 0..<PokopiaTown.habitatThreshold {
            XCTAssertTrue(store.memoryAlbum.shapeTownTile(col: col, row: 4, to: .sand))
        }
        let after = PokopiaTown.development(store.memoryAlbum.town.terrain)
        XCTAssertEqual(after.habitats, 4)
        XCTAssertEqual(after.capacity, before.capacity + PokopiaTown.residentsPerHabitat)

        let admitted = await store.rollTownImmigration()
        XCTAssertNotNil(admitted, "자리가 열렸는데 아무도 안 왔다")
        XCTAssertEqual(store.memoryAlbum.town.residents.count, before.capacity + 1)
    }

    /// 내보내면 다시 자리가 생긴다 — 상한이 영구 벽이 아니라는 것이 내보내기의 존재 이유다.
    func testEvictingMakesRoomForAnotherImmigrant() async {
        let store = makeStore(pool: [7, 60], types: [7: [.water], 60: [.water]])
        makeWatery(store)
        let first = await store.rollTownImmigration()
        XCTAssertNotNil(first)
        _ = await store.rollTownImmigration()
        XCTAssertEqual(store.memoryAlbum.town.residents.count, 2)

        XCTAssertTrue(store.memoryAlbum.evictTownResident(speciesID: 7))
        XCTAssertEqual(store.memoryAlbum.town.residents.count, 1)
    }

    // MARK: 실패 경로 (조용히 넘어간다)

    /// 서식이 안 되면 아무도 안 온다 — 기본 마을은 물 타입을 부르지 않는다.
    func testNobodyComesWhenTheHabitatIsNotThere() async {
        let store = makeStore()
        let nobody = await store.rollTownImmigration()
        XCTAssertNil(nobody)
        XCTAssertTrue(store.memoryAlbum.town.residents.isEmpty)
    }

    /// **이름을 못 얻으면 받지 않는다** — 이름 없는 주민은 결함처럼 보이는 줄이다.
    /// 라인에 그 종의 이름이 없는 상태를 흉내낸다.
    func testAnImmigrantWithoutAKoreanNameIsRefused() async {
        let nameless = EvoLine(baseID: 7, tree: EvoNode(speciesID: 7, children: []),
                               rarity: .common, names: [:])
        let store = makeStore(pool: [7], types: [7: [.water]], lines: [7: nameless])
        makeWatery(store)

        let refused = await store.rollTownImmigration()
        XCTAssertNil(refused, "이름 없는 주민을 받았다")
        XCTAssertTrue(store.memoryAlbum.town.residents.isEmpty)
    }

    /// 타입 인덱스가 그 종을 모르면 받지 않는다 — 자기 지형을 못 찾는 주민이 된다.
    func testAnImmigrantWithoutTypesIsRefused() async {
        // 후보 판정은 통과시키되(다른 종으로 부름) 뽑힌 종의 타입만 비운다 —
        // 실제로는 판정 자체가 타입을 보므로 이 경로는 풀 전체가 타입 없는 경우다.
        let store = makeStore(pool: [7], types: [:])
        makeWatery(store)
        let refused = await store.rollTownImmigration()
        XCTAssertNil(refused)
    }

    /// 그릴 수 없는 종은 풀에 들어오지 않는다 — `BaseSpecies.hatchable` 이 걷어낸다.
    func testSpritelessSpeciesNeverImmigrate() async {
        let spriteless = PokemonAssets.spriteGaps.min() ?? 990
        let store = makeStore(pool: [spriteless], types: [spriteless: [.water]])
        makeWatery(store)
        let refused = await store.rollTownImmigration()
        XCTAssertNil(refused, "스프라이트 없는 종이 이사 왔다 — 마을에 빈 자리가 그려진다")
    }

    // MARK: 서식이 화면에 보인다

    /// 찾아온 주민은 **자기를 부른 지형 위에** 선다. 이것이 "내가 만들어서 왔다" 의 시각적 증거다.
    func testTheImmigrantStandsOnTheTerrainThatCalledIt() async throws {
        let store = makeStore()
        makeWatery(store)
        let arrived = await store.rollTownImmigration()
        let resident = try XCTUnwrap(arrived)

        let spot = PokopiaTown.residentSpot(resident, terrain: store.memoryAlbum.town.terrain,
                                            dayKey: "2026-09-08")
        let index = try XCTUnwrap(PokopiaTown.index(col: spot.col, row: spot.row))
        XCTAssertEqual(store.memoryAlbum.town.terrain[index], .water,
                       "물 타입이 물이 아닌 칸에 섰다")
        XCTAssertTrue(PokopiaTown.isSettled(resident, terrain: store.memoryAlbum.town.terrain))
    }

    /// 부른 지형을 없애면 `isSettled` 가 false 가 되고 문구가 갈린다 — 주민은 사라지지 않는다.
    func testRemovingTheHabitatLeavesTheResidentUnsettledNotGone() async throws {
        let store = makeStore()
        makeWatery(store)
        let arrived = await store.rollTownImmigration()
        let resident = try XCTUnwrap(arrived)

        for col in 0..<PokopiaTown.habitatThreshold {
            _ = store.memoryAlbum.shapeTownTile(col: col, row: 0, to: .rock)
        }

        XCTAssertEqual(store.memoryAlbum.town.residents.map(\.speciesID), [resident.speciesID],
                       "지형을 없앴더니 주민이 사라졌다 — 자동 퇴거는 이해할 수 없는 상실이다")
        XCTAssertFalse(PokopiaTown.isSettled(resident, terrain: store.memoryAlbum.town.terrain))
    }
}

/// 인덱스 조회가 실패하는 스텁 — 네트워크가 죽은 세션을 흉내낸다.
private struct FailingTownProvider: PokeProviding {
    struct Offline: Error {}
    let line: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { line }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw Offline() }
    func speciesTypeIndex() async throws -> [Int: [PokemonType]] { throw Offline() }
}

/// 실패를 켜고 끌 수 있는 스텁. **같은 스토어**에서 실패 뒤 성공을 재현하려면 참조 타입이어야
/// 한다 — 구조체 스텁은 스토어에 복사돼 들어가 나중에 바꿀 수 없다.
private final class TogglingTownProvider: PokeProviding, @unchecked Sendable {
    struct Offline: Error {}
    let pool: [Int]
    let types: [Int: [PokemonType]]
    let lines: [Int: EvoLine]
    var failing = false

    init(pool: [Int], types: [Int: [PokemonType]], lines: [Int: EvoLine]) {
        self.pool = pool; self.types = types; self.lines = lines
    }

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        guard let line = lines[baseSpeciesID] else { throw Offline() }
        return line
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if failing { throw Offline() }
        return pool.map { BaseSpecies(id: $0, captureRate: 255) }
    }
    func speciesTypeIndex() async throws -> [Int: [PokemonType]] {
        if failing { throw Offline() }
        return types
    }
}
