import XCTest
@testable import PokeTokenBar

/// 플로팅에 그릴 대상 선택 규칙 — 설정에서 고른 도감 종 vs 지금 키우는 파트너.
@MainActor
final class FloatingPetSubjectTests: XCTestCase {

    private func makeStore() -> CompanionStore {
        let url = storeStateURL("floating")
        return CompanionStore(provider: NoLineProvider(), clock: { Date(timeIntervalSince1970: 1_000) },
                              fileURL: url, rng: SeededRNG(seed: 1))
    }

    /// 라인 제공 실패 — 알 유지(부화 억제)용. 대상 선택은 라인과 무관하다.
    private struct NoLineProvider: PokeProviding {
        struct Unavailable: Error {}
        func line(baseSpeciesID: Int) async throws -> EvoLine { throw Unavailable() }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    }

    private func dexEntry(base: Int, final: Int, chain: [Int], shiny: Bool = false) -> DexEntry {
        DexEntry(baseID: base, finalID: final, chainOrder: chain, rarity: .common,
                 caughtAt: Date(timeIntervalSince1970: 0), isShiny: shiny)
    }

    func testNoPinFollowsTheCurrentPartner() {
        let store = makeStore()
        store.debugSetDex([dexEntry(base: 1, final: 3, chain: [1, 2, 3])])
        let subject = store.floatingPetSubject(pinnedSpeciesID: nil)
        XCTAssertEqual(subject.speciesID, store.currentSpeciesID)
        XCTAssertEqual(subject.isShiny, store.currentIsShiny)
    }

    func testPinnedDexSpeciesIsDrawnInsteadOfThePartner() {
        let store = makeStore()
        store.debugSetDex([dexEntry(base: 1, final: 3, chain: [1, 2, 3])])
        // 체인 중간 단계도 도감에 수록되므로 고를 수 있어야 한다.
        XCTAssertEqual(store.floatingPetSubject(pinnedSpeciesID: 2).speciesID, 2)
        XCTAssertEqual(store.floatingPetSubject(pinnedSpeciesID: 3).speciesID, 3)
    }

    /// 이로치로 보유한 종은 이로치 색으로 그려야 한다 — 도감 표기와 바탕화면이 어긋나면 안 된다.
    func testPinnedSpeciesKeepsItsShinyColouring() {
        let store = makeStore()
        store.debugSetDex([dexEntry(base: 1, final: 3, chain: [1, 2, 3], shiny: true),
                           dexEntry(base: 4, final: 6, chain: [4, 5, 6])])
        XCTAssertTrue(store.floatingPetSubject(pinnedSpeciesID: 3).isShiny)
        XCTAssertFalse(store.floatingPetSubject(pinnedSpeciesID: 6).isShiny)
    }

    /// 도감에 없는 종을 고정해 두면 파트너로 되돌아간다 — 졸업 전 개체만 근거였던 칸은 그 개체를
    /// 놓아주면 사라지므로, 그대로 두면 보유한 적 없는 종이 바탕화면에 남는다.
    func testSpeciesMissingFromTheDexFallsBackToThePartner() {
        let store = makeStore()
        store.debugSetDex([dexEntry(base: 1, final: 3, chain: [1, 2, 3])])
        let subject = store.floatingPetSubject(pinnedSpeciesID: 999)
        XCTAssertEqual(subject.speciesID, store.currentSpeciesID)
        XCTAssertEqual(subject.isShiny, store.currentIsShiny)
    }

    // MARK: 진화 라인 묶기 (선택 메뉴)

    func testLinesGroupEachChainUnderItsBaseForm() {
        let store = makeStore()
        store.debugSetDex([dexEntry(base: 1, final: 3, chain: [1, 2, 3]),
                           dexEntry(base: 4, final: 6, chain: [4, 5, 6])])
        let lines = store.dexLines
        XCTAssertEqual(lines.map(\.id), [1, 4], "기본형 번호순")
        XCTAssertEqual(lines.first?.species.map(\.id), [1, 2, 3], "초기→최종 순서 유지")
    }

    /// 분기 진화는 한 줄로 합친다 — 기본형 이름이 메뉴에 여러 번 뜨면 어느 쪽인지 구분할 수 없다.
    func testBranchingEvolutionsShareOneLine() {
        let store = makeStore()
        store.debugSetDex([dexEntry(base: 133, final: 134, chain: [133, 134]),
                           dexEntry(base: 133, final: 136, chain: [133, 136])])
        let lines = store.dexLines
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.species.map(\.id), [133, 134, 136])
    }

    /// 메뉴에 있는 항목은 전부 고를 수 있어야 하고, 같은 종이 두 줄에 나오면 안 된다.
    func testLinesCoverEveryDexSpeciesExactlyOnce() {
        let store = makeStore()
        store.debugSetDex([dexEntry(base: 1, final: 3, chain: [1, 2, 3]),
                           dexEntry(base: 133, final: 134, chain: [133, 134]),
                           dexEntry(base: 133, final: 136, chain: [133, 136], shiny: true)])
        let listed = store.dexLines.flatMap { $0.species.map(\.id) }
        XCTAssertEqual(listed.sorted(), store.dexSpecies.map(\.id).sorted())
        XCTAssertEqual(Set(listed).count, listed.count, "같은 종이 두 줄에 걸쳐 나오면 안 된다")
    }

    /// 고를 수 있는 목록과 실제로 그려지는 종이 같은 출처여야 한다 — 규칙이 갈라지면 목록에 보이는데
    /// 골라도 안 바뀌는 칸이 생긴다.
    func testEverySpeciesOfferedByTheDexCanBeDrawn() {
        let store = makeStore()
        store.debugSetDex([dexEntry(base: 1, final: 3, chain: [1, 2, 3]),
                           dexEntry(base: 4, final: 6, chain: [4, 5, 6], shiny: true)])
        for species in store.dexSpecies {
            let subject = store.floatingPetSubject(pinnedSpeciesID: species.id)
            XCTAssertEqual(subject.speciesID, species.id, "도감 \(species.id) 칸을 골랐는데 다른 종이 그려진다")
            XCTAssertEqual(subject.isShiny, species.isShiny)
        }
    }
}
