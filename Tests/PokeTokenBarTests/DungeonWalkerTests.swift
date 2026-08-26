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
        var w = walker(); w.press(.right); settle(&w, seconds: 0.18 * 3 + 0.05)
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

    func testWalkCycleAlternatesBetweenStepsOnConsecutiveCells() {
        var w = walker(); w.press(.right)
        w.tick(0.05); let first = w.animationStep
        settle(&w, seconds: 0.18); w.tick(0.05); let second = w.animationStep
        XCTAssertTrue([1, 2].contains(first)); XCTAssertNotEqual(first, second)
    }
}
