import XCTest
@testable import PokeTokenBar

final class DungeonWalkerTests: XCTestCase {
    private let map = PuzzleDungeon.map(dayKey: "2026-08-21")
    private func walker() -> DungeonWalker { DungeonWalker(run: DungeonRun(map: map, budget: 100)) }
    private func settle(_ w: inout DungeonWalker, seconds: Double) { for _ in 0..<Int(seconds / 0.016) { w.tick(0.016) } }

    func testStartsInsideTheWestWallOfRoomZero() {
        let w = walker()
        XCTAssertEqual(w.run.current, 0); XCTAssertEqual(w.cell, GridPoint(x: 1, y: 4)); XCTAssertNil(w.motion)
    }

    func testPressingMovesOneCellAfterStepDuration() {
        var w = walker(); w.press(.right)
        w.tick(0.09); XCTAssertNotNil(w.motion); XCTAssertEqual(w.cell, GridPoint(x: 1, y: 4))
        w.release(.right); w.tick(0.1)
        XCTAssertEqual(w.cell, GridPoint(x: 2, y: 4)); XCTAssertNil(w.motion)
    }

    func testHoldingKeepsWalkingCellByCell() {
        // 3칸(0.54s) 뒤 딱 걸음 경계에 걸리면 부동소수 오차로 한 칸 더/덜 갈 수 있다 — 여유를 둔다.
        var w = walker(); w.press(.right); settle(&w, seconds: 0.18 * 3 + 0.1)
        XCTAssertEqual(w.cell.x, 4)
    }

    func testWallBlocksButTurnsTheTrainer() {
        var w = walker(); w.press(.left); w.tick(0.016)
        XCTAssertNil(w.motion); XCTAssertEqual(w.facing, .left); XCTAssertEqual(w.cell, GridPoint(x: 1, y: 4))
    }

    func testDeltaIsClampedSoAHiddenPopoverDoesNotTeleport() {
        var w = walker(); w.press(.right); w.tick(5)
        XCTAssertNotNil(w.motion, "0.1s 로 클램프되면 한 칸도 못 끝낸다")
        XCTAssertEqual(w.cell, GridPoint(x: 1, y: 4))
    }

    func testReachingADoorMovesTheRunExactlyOnceAndLocks() {
        var w = walker()
        let door = w.layout.doors.first { $0.side == .east }!
        w.walkTo(door: door); settle(&w, seconds: 0.18 * 14)
        XCTAssertEqual(w.run.current, door.target)
        XCTAssertEqual(w.run.events.filter { if case .entered = $0 { return true }; return false }.count, 1)
        XCTAssertTrue(w.locked)
        XCTAssertEqual(w.cell, GridPoint(x: 1, y: 4), "동쪽 문으로 나가면 다음 방 서쪽에서 시작")
        XCTAssertNotNil(w.consumeArrival()); XCTAssertNil(w.consumeArrival())
    }

    func testLockedWalkerIgnoresInput() {
        var w = walker(); w.locked = true; w.press(.right); settle(&w, seconds: 1)
        XCTAssertEqual(w.cell, GridPoint(x: 1, y: 4))
    }

    func testSpurDoorReturnsToParentAtTheOppositeSide() {
        var w = walker()
        // 시작 방에 곁방이 있는 날을 고른다 — 없으면 층을 하나 진행한다.
        var tries = 0
        while !w.layout.doors.contains(where: { $0.side != .east }) && tries < 12 {
            let east = w.layout.doors.first { $0.side == .east }!
            w.walkTo(door: east); settle(&w, seconds: 4); w.locked = false; _ = w.consumeArrival(); tries += 1
        }
        guard let spurDoor = w.layout.doors.first(where: { $0.side != .east }) else { return XCTFail("곁방 없는 날") }
        let parent = w.run.current
        w.walkTo(door: spurDoor); settle(&w, seconds: 4); w.locked = false; _ = w.consumeArrival()
        XCTAssertTrue(w.run.map.isSpur(w.run.current))
        let back = w.layout.doors[0]
        w.walkTo(door: back); settle(&w, seconds: 4)
        XCTAssertEqual(w.run.current, parent)
        XCTAssertEqual(w.cell, DungeonRoomLayout.entryCell(from: DungeonRoomLayout.opposite(back.side)))
    }

    func testIdleWhenNothingIsHappening() {
        var w = walker(); XCTAssertTrue(w.isIdle); w.press(.right); XCTAssertFalse(w.isIdle)
    }

    /// 도착 이벤트를 아직 안 읽었으면 멈추면 안 된다 — 화면이 루프를 세우면 연출도, 잠금 해제도 없다.
    func testPendingArrivalIsNeverIdle() {
        var w = walker()
        let door = w.layout.doors.first { $0.side == .east }!
        w.walkTo(door: door); settle(&w, seconds: 0.18 * 14)
        XCTAssertNotNil(w.arrival)
        XCTAssertTrue(w.locked)
        XCTAssertFalse(w.isIdle)
    }

    /// 잠긴 walker 의 `tick` 은 아무것도 하지 않는다 — 키가 눌려 있고 걷던 중이어도 화면이 루프를
    /// 멈춰야 한다. 잠금은 `locked` 로 바깥에서도 걸 수 있으니(판정이 끝난 시도를 세워 두는 용도)
    /// "눌린 키가 남은 채 잠긴" 조합을 직접 만들어 검증한다.
    func testLockedWalkerIsIdleEvenWithAKeyHeldMidStep() {
        var w = walker()
        w.press(.right); w.tick(0.05)
        XCTAssertNotNil(w.motion); XCTAssertFalse(w.isIdle)
        w.locked = true
        XCTAssertTrue(w.isIdle, "잠긴 walker 를 계속 틱하면 60fps 로 헛돈다")
        w.tick(0.2)
        XCTAssertEqual(w.cell, GridPoint(x: 1, y: 4), "잠긴 동안엔 한 칸도 나아가지 않는다")
    }

    /// 도착을 이미 읽었고 잠금만 남은 상태(연출 중)도 걷기 계산은 없다 — 그림은 연출이 그린다.
    func testConsumedArrivalWithTheLockStillOnIsIdle() {
        var w = walker()
        let door = w.layout.doors.first { $0.side == .east }!
        w.walkTo(door: door); settle(&w, seconds: 0.18 * 14)
        XCTAssertNotNil(w.consumeArrival())
        XCTAssertTrue(w.locked)
        XCTAssertTrue(w.isIdle)
    }

    /// 걷는 중간(`motion.progress` 가 0 도 1 도 아닐 때)에 문을 클릭하면 아직 확정 안 된 `motion.to`
    /// 에서 경로가 이어야 한다 — `cell`(마지막 확정 칸)에서 이으면 진행 중인 한 걸음을 건너뛰어
    /// 두 칸이 한 번에 미끄러진다.
    func testWalkToMidStepStartsFromMotionDestinationNotConfirmedCell() {
        var w = walker(); w.press(.right); w.tick(0.05)
        guard let motion = w.motion else { return XCTFail("걷는 중이어야 한다") }
        let door = w.layout.doors.first { $0.side == .east }!
        w.walkTo(door: door)
        guard let first = w.autoPath.first else { return XCTFail("경로가 비어 있다") }
        let dx = abs(first.x - motion.to.x), dy = abs(first.y - motion.to.y)
        XCTAssertEqual(dx + dy, 1, "경로 첫 칸은 motion.to 의 바로 옆이어야 한다")
    }

    /// `KeyCaptureModifier` 가 재현하는 시나리오 — press → 한 틱 → release → 진행 마무리.
    /// `release` 가 `held`/`heldOrder` 를 제대로 비워야 다음 프레임부터 `isIdle` 이 true 로 돌아온다.
    func testReleaseClearsHeldAndRestoresIdle() {
        var w = walker(); w.press(.right); w.tick(0.016)
        w.release(.right)
        settle(&w, seconds: 0.2)
        XCTAssertTrue(w.isIdle)
        XCTAssertTrue(w.held.isEmpty)
    }

    func testWalkCycleAlternatesBetweenStepsOnConsecutiveCells() {
        var w = walker(); w.press(.right)
        w.tick(0.05); let first = w.animationStep
        settle(&w, seconds: 0.18); w.tick(0.05); let second = w.animationStep
        XCTAssertTrue([1, 2].contains(first)); XCTAssertNotEqual(first, second)
    }
}
