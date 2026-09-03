import XCTest
@testable import PokeTokenBar

/// 출전 팀 고르기의 **선택 규칙**. 화면(`TeamPicker`)은 못 밟지만 누를 때마다 목록이 어떻게
/// 바뀌는지는 순수 함수라 여기서 전 분기를 검증한다.
final class TeamPickerTests: XCTestCase {

    /// **트리거 브랜치 — 정원이 1 인 자리.** 레이드 피커는 한 마리만 고른다.
    ///
    /// "정원이 찼으면 무시" 규칙만 두면 정원이 6 일 땐 예외인 상태가 정원 1 에선 기본 상태가 된다 —
    /// 첫 선택 뒤로 다른 개체를 아무리 눌러도 선택이 안 바뀐다. 기술 미리보기만 펼쳐져서 눌린
    /// 것처럼 보이는 탓에 고장으로도 안 읽힌다. 정원이 1 이면 갈아탄다.
    func testPickingAnotherMonSwapsWhenOnlyOneFits() {
        let pikachu = UUID(), dragonite = UUID()
        XCTAssertEqual(TeamPicker.toggled([pikachu], monID: dragonite, limit: 1), [dragonite])
    }

    /// 같은 개체를 다시 누르면 뺀다 — 정원이 1 이어도 "해제" 는 남아 있어야 한다.
    func testTappingThePickedMonAgainClearsIt() {
        let pikachu = UUID()
        XCTAssertEqual(TeamPicker.toggled([pikachu], monID: pikachu, limit: 1), [])
    }

    /// 정원이 여럿인 자리(체육관 4·토너먼트 6)는 예전 그대로다 — 차기 전엔 넣고, 차면 무시한다.
    /// 여기서 갈아타면 여섯째를 누를 때 첫째가 조용히 빠진다.
    func testAFullTeamIgnoresNewPicks() {
        let team = (0..<4).map { _ in UUID() }
        let extra = UUID()
        XCTAssertEqual(TeamPicker.toggled(team, monID: extra, limit: 4), team)

        let room = Array(team.prefix(3))
        XCTAssertEqual(TeamPicker.toggled(room, monID: extra, limit: 4), room + [extra])
    }

    /// 뺄 때는 순서가 유지된다 — 배지 숫자가 출전 순서라 가운데를 빼면 뒤가 당겨져야 한다.
    func testRemovingFromTheMiddleKeepsTheOrder() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(TeamPicker.toggled([a, b, c], monID: b, limit: 4), [a, c])
    }
}
