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

    /// 도감 번호순 — 도감 격자와 같은 순서다. 두 화면이 같은 순서라야 "도감의 그 칸" 을 박스에서
    /// 같은 자리로 찾는다.
    func testDexNumberSortOrdersByTheNumberOnTheCard() {
        let box = [mon(25), mon(1), mon(150)]
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .dexNumber).map(\.currentID), [1, 25, 150])
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .dexNumber, ascending: false).map(\.currentID),
                       [150, 25, 1])
    }

    /// **현재 형태의 번호**로 센다. 기본형 번호로 묶으면 이상해꽃이 3번이 아니라 1번 자리에 서서,
    /// 카드가 그리는 스프라이트·이름과 순서가 어긋난다.
    func testDexNumberSortFollowsTheCurrentFormNotTheBaseForm() {
        var venusaur = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 2, usedAtStage: 0,
                                rarity: .common, totalForms: 3)
        venusaur.levelExperience = 0
        let box = [venusaur, mon(2)]
        XCTAssertEqual(venusaur.currentID, 3, "이 개체는 카드에 3번으로 그려진다")
        XCTAssertEqual(RosterOrdering.arrange(box, sort: .dexNumber).map(\.currentID), [2, 3])
    }

    /// 같은 종이 여러 마리면 저장 순서를 지킨다 — 안 그러면 볼 때마다 자리가 바뀐다.
    func testDexNumberSortIsStableWithinTheSameSpecies() {
        let box = [mon(25, level: 9), mon(4), mon(25, level: 3)]
        let arranged = RosterOrdering.arrange(box, sort: .dexNumber)
        XCTAssertEqual(arranged.map(\.currentID), [4, 25, 25])
        XCTAssertEqual(arranged.map(\.level), [1, 9, 3], "같은 번호끼리는 넣은 순서 그대로")
    }

    /// 세이브에 rawValue 로 남는다 — case 이름을 바꾸면 예전 세이브가 조용히 기본값으로 되돌아간다.
    func testTheStoredSortKeyStaysStable() {
        XCTAssertEqual(RosterSort.dexNumber.rawValue, "dexNumber")
        XCTAssertEqual(RosterSort(rawValue: "dexNumber"), .dexNumber)
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

    /// 출전 팀 고르기 줄의 레벨 정렬 버튼. 오름·내림 **두 상태만** 두면 이 줄의 원래 순서인
    /// 부화순으로 돌아갈 길이 없어진다 — 사이클이 기본을 지나야 정렬을 되돌릴 수 있다.
    func testTeamPickerLevelOrderCyclesBackToTheCaughtOrder() {
        XCTAssertEqual(TeamPickerLevelOrder.caught.next, .ascending)
        XCTAssertEqual(TeamPickerLevelOrder.ascending.next, .descending)
        XCTAssertEqual(TeamPickerLevelOrder.descending.next, .caught,
                       "되돌릴 수 없으면 한 번 누른 사용자는 부화순을 잃는다")
    }

    /// 정렬은 **탭을 떠나도 남아야 한다.** 뷰의 `@State` 에 있던 동안 홈에 갔다 오는 것만으로
    /// 기본값으로 돌아갔다 — 60마리 박스에서 매번 다시 고르게 된다.
    @MainActor
    func testRosterSortSurvivesLeavingTheTab() {
        let suiteName = "roster-sort-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.rosterSort, .caught, "기본은 부화순")
        XCTAssertTrue(settings.rosterSortAscending)

        settings.rosterSort = .level
        settings.rosterSortAscending = false

        // 탭을 떠났다 오면 화면은 새로 만들어진다 — 설정을 다시 읽는 것과 같다.
        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.rosterSort, .level)
        XCTAssertFalse(reopened.rosterSortAscending)
    }

    /// 아이콘이 방향을 말한다 — 세 상태가 같은 그림이면 지금 어느 정렬인지 화면에서 알 수 없다.
    func testEachTeamPickerLevelOrderShowsItsOwnIcon() {
        let icons = TeamPickerLevelOrder.allCases.map(\.iconName)
        XCTAssertEqual(Set(icons).count, TeamPickerLevelOrder.allCases.count)
        XCTAssertEqual(TeamPickerLevelOrder.ascending.iconName, "arrow.up")
        XCTAssertEqual(TeamPickerLevelOrder.descending.iconName, "arrow.down")
    }
}
