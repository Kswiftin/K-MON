import XCTest
@testable import PokeTokenBar

/// 로스터 정렬·필터(#87). 60마리가 넘는 박스에서 찾을 방법이 저장 순서뿐이었다.
final class RosterOrderingTests: XCTestCase {

    private func mon(_ id: Int, level: Int = 1, name: String? = nil) -> MonState {
        var mon = MonState(baseID: id, pathIDs: [id], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1,
                           names: name.map { [id: ["en": $0, "ko": $0]] })
        mon.levelExperience = (level - 1) * 10_000_000
        return mon
    }

    func testCaughtSortKeepsStoredOrder() {
        let box = [mon(3), mon(1), mon(2)]
        let arranged = RosterOrdering.arrange(box, sort: .caught)
        XCTAssertEqual(arranged.map(\.currentID), [3, 1, 2])
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .caught, ascending: false).map(\.currentID),
                       [2, 1, 3], "내림차순은 저장 순서를 뒤집는다")
    }

    func testNameSortUsesTheNameTheCardDraws() {
        // 개체에 저장된 다국어 이름으로 정렬한다 — 카드가 그리는 값과 같아야 한다.
        let box = [mon(3, name: "Venusaur"), mon(1, name: "Bulbasaur"), mon(2, name: "Ivysaur")]
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .name).map(\.currentID), [1, 2, 3])
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .name, ascending: false).map(\.currentID),
                       [3, 2, 1])
    }

    /// 이름이 없는 구버전 개체는 `#종번호` 로 그려진다 — 정렬 키도 그 문자열이라야 화면과 맞는다.
    /// 뷰가 조회해 넘긴 이름(`names`)이 있으면 그게 우선이다.
    func testResolvedNamesOverrideTheNumberFallback() {
        let box = [mon(25), mon(4)]
        XCTAssertEqual(RosterOrdering.displayName(box[0], language: .en), "#25")
        let arranged = RosterOrdering.arrange(box, sort: .name, names: [25: "Pikachu", 4: "Charmander"])
        XCTAssertEqual(arranged.map(\.currentID), [4, 25], "Charmander < Pikachu")
    }

    func testLevelSortIsStableWithinTheSameLevel() {
        let box = [mon(1, level: 5), mon(2, level: 40), mon(3, level: 5)]
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .level).map(\.currentID), [1, 3, 2])
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .level, ascending: false).map(\.currentID),
                       [2, 3, 1], "만렙부터 보려면 내림차순")
    }

    func testTypeFilterKeepsOnlyMatchingSpecies() {
        let box = [mon(1), mon(4), mon(7)]
        let types: [Int: [PokemonType]] = [1: [.grass, .poison], 4: [.fire], 7: [.water]]
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .caught, typeFilter: .fire, types: types)
                        .map(\.currentID), [4])
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .caught, typeFilter: .poison, types: types)
                        .map(\.currentID), [1], "두 번째 타입도 걸린다")
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .caught, typeFilter: nil, types: types)
                        .count, 3)
    }

    /// 타입은 네트워크로 온다. 아직(또는 영영) 해석되지 않은 개체를 숨기면 내 박스의 포켓몬이
    /// 조용히 사라진 것처럼 보인다 — 로딩 상태가 필터 결과를 바꾸지 않게 통과시킨다.
    func testUnresolvedTypesStayVisibleUnderAFilter() {
        let box = [mon(4), mon(999)]
        let types: [Int: [PokemonType]] = [4: [.fire]]   // 999 는 미해석
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .caught, typeFilter: .water, types: types)
                        .map(\.currentID), [999],
                       "해석된 개체만 걸러지고, 미해석 개체는 남는다")
        XCTAssertTrue(RosterOrdering.passesTypeFilter(mon(999), type: .water, types: [999: []]),
                      "빈 배열도 미해석과 같다")
    }

    /// 18종을 다 열어 두면 대부분이 고르는 순간 빈 화면이 되는 항목이다.
    func testAvailableTypesOnlyListsWhatTheBoxHas() {
        let box = [mon(1), mon(4)]
        let types: [Int: [PokemonType]] = [1: [.grass, .poison], 4: [.fire]]
        XCTAssertEqual(RosterOrdering.availableTypes(box, types: types), [.fire, .grass, .poison],
                       "도감 순서(allCases)로 낸다")
        XCTAssertTrue(RosterOrdering.availableTypes(box, types: [:]).isEmpty,
                      "해석 전엔 필터에 올릴 게 없다")
    }
}
