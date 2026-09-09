import XCTest
@testable import PokeTokenBar

// MARK: 포코피아 마을 — 스토어의 조립 입력
//
// 판정표는 `PokopiaTown` 하나지만, 그 **입력을 조립하는 코드**가 프런트엔드마다 복사되면
// 같은 부류의 결함이 된다(`defect-log.md` "판정표는 하나인데 그 입력을 조립하는 코드가
// 프런트엔드마다 복사돼 있는 부류"). 조립을 스토어 두 곳(`townBrush`·`rollTownImmigration`)
// 으로만 모은 것이 그 예방이고, 이 파일이 그 두 곳을 검증한다.

@MainActor
final class PokopiaStoreAssemblyTests: XCTestCase {

    private func makeStore(seed: UInt64 = 1, tag: String = "pokopia-assembly") -> CompanionStore {
        let line = EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                           names: [25: ["ko": "피카츄"]])
        return CompanionStore(provider: TownAssemblyProvider(line: line),
                              clock: { Date(timeIntervalSince1970: 1_000) },
                              fileURL: storeStateURL(tag), rng: SeededRNG(seed: seed))
    }

    private func dex(_ finalID: Int, chain: [Int], types: [PokemonType]?) -> DexEntry {
        DexEntry(baseID: chain.first ?? finalID, finalID: finalID, chainOrder: chain,
                 rarity: .common, caughtAt: Date(timeIntervalSince1970: 500), types: types)
    }

    // MARK: 변신 후보

    /// 후보는 도감 `finalID` 집합이다. 시트와 `setDittoForm` 이 같은 값을 읽어야 목록에
    /// 뜨는데 못 고르는 종이 생기지 않는다.
    func testTransformCandidatesAreDexFinalIDs() {
        let store = makeStore()
        store.debugSetDex([dex(3, chain: [1, 2, 3], types: [.grass]),
                           dex(9, chain: [7, 8, 9], types: [.water])])

        let candidates = store.townTransformCandidates

        XCTAssertTrue(candidates.contains(3))
        XCTAssertTrue(candidates.contains(9))
        XCTAssertFalse(candidates.contains(1), "중간 단계는 후보가 아니다 — 한 칸이 셋으로 불어난다")
    }

    func testEmptyDexYieldsNoCandidates() {
        XCTAssertTrue(makeStore().townTransformCandidates.isEmpty)
    }

    /// 키우는 중인 개체도 후보가 된다(`dexEntries` 가 활성·박스를 합치므로). 졸업만 세면
    /// 1일차 사용자가 아무것으로도 변신할 수 없고, 그러면 마을을 만들 수 없다.
    func testLivingCompanionIsAlsoACandidate() async {
        let store = makeStore()
        await store.hatch(baseID: 25)
        XCTAssertTrue(store.townTransformCandidates.contains(25),
                      "키우는 중인 개체가 후보에서 빠졌다 — 1일차에 마을을 만들 수 없다")
    }

    // MARK: 브러시 조립

    /// **변신하지 않으면 아무것도 못 민다.** 이 판정이 무너지면 변신이 다시 장식이 된다.
    func testBrushIsNilUntilTransformed() {
        let store = makeStore()
        store.debugSetDex([dex(9, chain: [7, 8, 9], types: [.water])])
        XCTAssertNil(store.townBrush, "변신하지 않았는데 밀 수 있다")

        XCTAssertTrue(store.memoryAlbum.setDittoForm(9,
                                                     registeredSpecies: store.townTransformCandidates))
        XCTAssertEqual(store.townBrush, .water)
    }

    /// 변신 대상의 `types` 가 아직 백필되지 않았으면 브러시도 없다 — 조용히 남의 지형을
    /// 밀게 하는 것보다 낫다. 다음 도감 열람이 타입을 채우면 풀린다.
    func testBrushIsNilWhenTheFormHasNoTypesYet() {
        let store = makeStore()
        store.debugSetDex([dex(9, chain: [7, 8, 9], types: nil)])
        XCTAssertTrue(store.memoryAlbum.setDittoForm(9,
                                                     registeredSpecies: store.townTransformCandidates))
        XCTAssertNil(store.townBrush)
    }

    /// 해제하면 브러시가 사라진다.
    func testUnsettingTheFormClearsTheBrush() {
        let store = makeStore()
        store.debugSetDex([dex(9, chain: [7, 8, 9], types: [.water])])
        _ = store.memoryAlbum.setDittoForm(9, registeredSpecies: store.townTransformCandidates)
        XCTAssertNotNil(store.townBrush)
        _ = store.memoryAlbum.setDittoForm(nil, registeredSpecies: [])
        XCTAssertNil(store.townBrush)
    }
}

/// 이사가 쓰는 세 조회를 전부 답하는 스텁.
///
/// **`speciesTypeIndex()` 를 반드시 덮는다.** `PokeProviding` 에 기본 구현이 있고
/// (`PokeAPIClient.swift:61-63`) 그 주석이 "기본값은 실 클라이언트 — 타입을 쓰지 않는 스텁은
/// 그대로 두면 된다" 고 적어 두었다. 이사는 타입을 쓰므로 덮지 않으면 테스트가 네트워크를 탄다.
struct TownAssemblyProvider: PokeProviding {
    let line: EvoLine
    /// 이사 후보 풀. `baseSpeciesIndex()` 가 답하는 값이다.
    var basePool: [Int] = []
    /// 종 → 타입. 비어 있으면 이사 판정이 후보를 못 찾는다.
    var types: [Int: [PokemonType]] = [:]
    /// 종 → 그 종의 이름을 담은 라인. 없으면 `line` 을 돌려준다(이름 조회 실패를 흉내낼 때 쓴다).
    var linesBySpecies: [Int: EvoLine] = [:]

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        linesBySpecies[baseSpeciesID] ?? line
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        let ids = basePool.isEmpty ? [line.baseID] : basePool
        return ids.map { BaseSpecies(id: $0, captureRate: 255) }
    }
    func speciesTypeIndex() async throws -> [Int: [PokemonType]] { types }
}
