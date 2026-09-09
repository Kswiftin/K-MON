import XCTest
@testable import PokeTokenBar

/// `SafariWalker` — 격자 이동 상태기계. `room-walk-dungeon-design.md` 의 `DungeonWalkerTests`
/// 계획을 벽·문 로직만 빼고 옮긴다.
final class SafariWalkerTests: XCTestCase {

    private let bounds = SafariFieldBounds.standard

    // MARK: 벽 거부

    /// 경계 밖으로 나가려 하면 방향(바라보는 쪽)만 바뀌고 칸은 그대로다 — 문이 없는 사파리존
    /// 벌판이라 사방이 막혀 있다.
    func testWalkerRejectsWallAndOnlyTurnsFacing() {
        let tinyBounds = SafariFieldBounds(width: 1, height: 1)
        var walker = SafariWalker(startingAt: SafariCell(x: 0, y: 0))
        let arrived = walker.tick(dt: 0.1, heldKeys: [.up], bounds: tinyBounds)
        XCTAssertFalse(arrived)
        XCTAssertEqual(walker.cell, SafariCell(x: 0, y: 0))
        XCTAssertEqual(walker.facing, .up, "막혀도 바라보는 방향은 바뀌어야 한다")
        XCTAssertEqual(walker.moveProgress, 0, "제자리에 머물면 이동 진행도가 없어야 한다")
    }

    // MARK: 도착 타이밍 — 정확히 한 번만

    /// 칸 하나(0.18s)를 건너는 데 `dt=0.1` 로 두 번이 필요하다 — 첫 틱은 아직 도착 전, 두 번째
    /// 틱에서 정확히 도착(`true`)한다. 세 번째 이후(다음 칸으로 새 이동을 시작하는 시점)엔 다시
    /// 미도착이어야 한다 — 도착 신호가 중복되거나 안 나는 프레임이 없는지 확인.
    func testArrivalIsReportedExactlyOnceAtTheMoment() {
        var walker = SafariWalker(startingAt: SafariCell(x: 5, y: 5))
        let first = walker.tick(dt: 0.1, heldKeys: [.down], bounds: bounds)
        XCTAssertFalse(first, "첫 틱은 아직 칸 중간이어야 한다")
        XCTAssertEqual(walker.cell, SafariCell(x: 5, y: 5), "도착 전엔 칸이 안 바뀐다")
        let second = walker.tick(dt: 0.1, heldKeys: [.down], bounds: bounds)
        XCTAssertTrue(second, "두 번째 틱에서 정확히 도착해야 한다")
        XCTAssertEqual(walker.cell, SafariCell(x: 5, y: 6))
        let third = walker.tick(dt: 0.0, heldKeys: [], bounds: bounds)
        XCTAssertFalse(third, "도착 직후 정지 틱은 다시 도착으로 세면 안 된다")
    }

    // MARK: dt 클램프

    /// 큰 `dt`(팝오버가 숨었다 오래 있다 돌아온 경우)를 줘도 한 틱에 여러 칸을 건너뛰지 않는다
    /// — 클램프가 없다면 `dt=100` 은 즉시 도착(`true`)이었을 것이다.
    func testDeltaTimeIsClampedSoALargeGapDoesNotTeleport() {
        var walker = SafariWalker(startingAt: SafariCell(x: 5, y: 5))
        let arrived = walker.tick(dt: 100.0, heldKeys: [.down], bounds: bounds)
        XCTAssertFalse(arrived, "dt 클램프가 없으면 한 틱에 바로 도착했을 것이다")
        XCTAssertEqual(walker.cell, SafariCell(x: 5, y: 5))
    }

    // MARK: 홀드 연속 이동

    /// 방향키를 계속 누르고 있으면 칸 단위로 이어서 간다 — 여러 번의 "정확히 두 틱마다 도착"이
    /// 반복돼야 한다.
    func testHoldingDirectionContinuesMovingCellByCell() {
        var walker = SafariWalker(startingAt: SafariCell(x: 0, y: 0))
        var arrivals = 0
        for _ in 0..<10 {
            if walker.tick(dt: 0.1, heldKeys: [.right], bounds: bounds) { arrivals += 1 }
        }
        XCTAssertEqual(arrivals, 5, "0.1s 틱 10번(1.0s)이면 칸당 0.18s 를 5번 다 건너야 한다")
        XCTAssertEqual(walker.cell, SafariCell(x: 5, y: 0))
    }

    // MARK: 장애물 거부

    /// 장애물 칸으로 이동하려 하면 벽과 같은 방식으로 막힌다 — 방향만 바뀌고 제자리.
    func testWalkerRejectsObstacleAndOnlyTurnsFacing() {
        var walker = SafariWalker(startingAt: SafariCell(x: 5, y: 5))
        let obstacles: Set<SafariCell> = [SafariCell(x: 5, y: 6)]
        let arrived = walker.tick(dt: 0.1, heldKeys: [.down], bounds: bounds, obstacles: obstacles)
        XCTAssertFalse(arrived)
        XCTAssertEqual(walker.cell, SafariCell(x: 5, y: 5), "장애물 칸으로 들어가면 안 된다")
        XCTAssertEqual(walker.facing, .down, "막혀도 바라보는 방향은 바뀌어야 한다")
    }

    /// `obstacles` 파라미터가 있어도 목표 칸과 무관하면 정상적으로 이동한다 — 장애물 판정이
    /// 엉뚱한 칸까지 막지 않는지 확인.
    func testWalkerMovesNormallyWhenTargetIsNotAnObstacle() {
        var walker = SafariWalker(startingAt: SafariCell(x: 5, y: 5))
        let obstacles: Set<SafariCell> = [SafariCell(x: 9, y: 9)]
        _ = walker.tick(dt: 0.1, heldKeys: [.down], bounds: bounds, obstacles: obstacles)
        let arrived = walker.tick(dt: 0.1, heldKeys: [.down], bounds: bounds, obstacles: obstacles)
        XCTAssertTrue(arrived, "장애물과 무관한 칸으로는 정상 도착해야 한다")
        XCTAssertEqual(walker.cell, SafariCell(x: 5, y: 6))
    }
}
