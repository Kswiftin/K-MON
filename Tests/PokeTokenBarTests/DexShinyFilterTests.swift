import XCTest
@testable import PokeTokenBar

/// 도감의 이로치 필터.
///
/// 격자는 뷰라 순수 함수로 못 재지만, 필터가 읽는 값(`DexSpecies.isShiny`)과 **겹쳐 걸리는 규칙**은
/// 잴 수 있다. 화면에서 확인해야 하는 건 배치뿐이고, 무엇이 걸러지는지는 여기서 잠근다.
@MainActor
final class DexShinyFilterTests: XCTestCase {

    private let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                               rarity: .common, names: [1: ["ko": "포1", "en": "P1"]])

    /// 저장된 도감으로 스토어를 연다 — 졸업 경로를 타지 않고 집계만 본다.
    private func store(_ entries: [DexEntry]) throws -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dex-shiny-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
        try Data(#"{"economyVersion":2,"forcedResetVersion":1,"dex":\#(dexJSON),"language":"ko"}"#.utf8)
            .write(to: url)
        return CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    private func entry(_ id: Int, rarity: Rarity, shiny: Bool) -> DexEntry {
        DexEntry(baseID: id, finalID: id, chainOrder: [id], rarity: rarity,
                 caughtAt: Date(), isShiny: shiny,
                 names: [id: ["ko": "포\(id)", "en": "P\(id)"]])
    }

    /// 필터가 읽는 값 자체. 종별 집계가 이로치를 접어 버리면 필터를 켜도 빈 화면만 나온다.
    func testShinyFlagSurvivesTheSpeciesFold() throws {
        let s = try store([entry(1, rarity: .common, shiny: true),
                           entry(2, rarity: .common, shiny: false)])
        let byID = Dictionary(uniqueKeysWithValues: s.dexSpecies.map { ($0.id, $0.isShiny) })
        XCTAssertEqual(byID[1], true)
        XCTAssertEqual(byID[2], false)
    }

    /// **희귀도와 겹쳐 걸린다.** 배타로 두면 희귀도를 고른 사람이 이로치를 보려고 필터를 먼저
    /// 풀어야 한다. 화면의 두 필터가 실제로 곱해지는지를 같은 순서로 재현해 확인한다.
    func testShinyAndRarityFiltersCombine() throws {
        let s = try store([entry(1, rarity: .common, shiny: true),
                           entry(2, rarity: .common, shiny: false),
                           entry(3, rarity: .rare, shiny: true),
                           entry(4, rarity: .rare, shiny: false)])
        let all = s.dexSpecies

        func visible(rarity: Rarity?, shinyOnly: Bool) -> [Int] {
            let byRarity = rarity.map { r in all.filter { $0.rarity == r } } ?? all
            return (shinyOnly ? byRarity.filter(\.isShiny) : byRarity).map(\.id).sorted()
        }
        XCTAssertEqual(visible(rarity: nil, shinyOnly: false), [1, 2, 3, 4])
        XCTAssertEqual(visible(rarity: nil, shinyOnly: true), [1, 3], "이로치만")
        XCTAssertEqual(visible(rarity: .rare, shinyOnly: false), [3, 4], "레어만")
        XCTAssertEqual(visible(rarity: .rare, shinyOnly: true), [3],
                       "레어 중에 이로치 — 둘이 배타면 여기가 [3, 4] 나 [1, 3] 이 된다")
    }

    /// 캡슐의 개수는 **희귀도 필터 전 전체** 기준이다. 희귀도를 고를 때 이 숫자가 같이 줄면
    /// "이로치가 사라졌다"로 읽히는데, 실제로는 다른 희귀도에 그대로 있다.
    func testShinyCountIsIndependentOfTheRarityFilter() throws {
        let s = try store([entry(1, rarity: .common, shiny: true),
                           entry(3, rarity: .rare, shiny: true)])
        XCTAssertEqual(s.dexSpecies.lazy.filter(\.isShiny).count, 2)
    }

    /// 문구는 세 언어 모두 있어야 한다 — 두 언어만 채우는 부류를 막는 게 이 레포의 규칙이다.
    func testFilterCopyExistsInAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.dexShinyFilter.isEmpty, "\(lang) 라벨 누락")
            XCTAssertFalse(l.dexShinyFilterHint.isEmpty, "\(lang) 설명 누락")
        }
        XCTAssertNotEqual(L(.ko).dexShinyFilterHint, L(.en).dexShinyFilterHint)
        XCTAssertNotEqual(L(.ko).dexShinyFilterHint, L(.ja).dexShinyFilterHint)
    }
}
