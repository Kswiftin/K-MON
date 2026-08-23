import XCTest
@testable import PokeTokenBar

/// 시도 진행 상태기계. 판정과 클램프는 `move(to:)` **한 곳**에만 있어야 한다 —
/// 입구가 여러 개면 한 곳만 고치고 끝난다(경험치 클램프 입구를 하나로 모은 #81 과 같은 이유).
final class DungeonRunTests: XCTestCase {
    private let map = PuzzleDungeon.map(dayKey: "2026-08-21")

    private func makeRun(budget: Int = PuzzleDungeon.baseBudget,
                         remembered: [Int: RoomKind] = [:]) -> DungeonRun {
        DungeonRun(map: map, budget: budget, remembered: remembered)
    }

    // MARK: 안개

    /// 들어가기 전에는 방 종류가 밝혀지지 않는다. 처음부터 보이면 퍼즐이 성립하지 않는다.
    func testUnvisitedRoomsStayHidden() {
        let session = makeRun()
        XCTAssertEqual(session.revealed.count, 1, "밝혀진 건 시작 방뿐이어야 한다")
        XCTAssertEqual(session.revealed[0], map.room(0).kind)
        for exit in session.exits { XCTAssertNil(exit.known, "인접한 방의 정체가 미리 보인다") }
    }

    /// 기억한 방은 다시 들어가지 않아도 정체가 보인다(실패해도 맵 기억은 남는다).
    func testRememberedRoomsAreVisibleWithoutEntering() {
        let neighbor = map.exits(from: 0)[0].room
        let session = makeRun(remembered: [neighbor: map.room(neighbor).kind])
        XCTAssertEqual(session.exits.first { $0.room == neighbor }?.known, map.room(neighbor).kind)
    }

    /// 세이브를 손으로 고쳐 거짓 정체·범위 밖 방 번호를 심어도 시도가 그걸 믿지 않는다.
    /// 믿으면 "보스인 줄 알고 피한 방이 빈 방" 처럼 안개가 거짓말을 한다.
    func testTamperedMemoryIsDiscarded() {
        let neighbor = map.exits(from: 0)[0].room
        let lie: RoomKind = map.room(neighbor).kind == .boss ? .empty : .boss
        let session = makeRun(remembered: [neighbor: lie, 99: .spring, -1: .empty])
        XCTAssertNil(session.revealed[99])
        XCTAssertNil(session.revealed[-1])
        XCTAssertNil(session.revealed[neighbor], "실제와 다른 정체가 그대로 남았다")
    }

    // MARK: 이동 판정

    /// 인접하지 않은 방으로는 못 간다 — 상태도 변하지 않는다.
    func testMoveToNonAdjacentRoomIsRejected() {
        var session = makeRun()
        let adjacent = Set(map.exits(from: 0).map(\.room))
        guard let far = (1..<PuzzleDungeon.roomCount).first(where: { !adjacent.contains($0) }) else {
            return XCTFail("시작 방이 모든 방과 붙어 있어 검사할 수 없다")
        }
        let before = session.hp
        XCTAssertFalse(session.move(to: far))
        XCTAssertEqual(session.current, 0)
        XCTAssertEqual(session.hp, before)
    }

    /// 체력 0 은 실패다. **경계값**이라 1 이 남는 경우와 따로 밟는다.
    func testHitPointsReachingZeroFails() {
        var session = makeRun(budget: 1)              // 통로 비용만으로 바닥난다
        let neighbor = map.exits(from: 0)[0].room
        XCTAssertTrue(session.move(to: neighbor))
        XCTAssertEqual(session.stage, .failed)
        XCTAssertEqual(session.hp, 0, "체력은 음수로 내려가지 않는다")
        XCTAssertTrue(session.events.contains(.collapsed))
    }

    /// 실패한 뒤에는 어떤 이동도 받지 않는다 — 죽은 시도가 계속 진행되면 로그가 거짓이 된다.
    func testFailedRunRejectsFurtherMoves() {
        var session = makeRun(budget: 1)
        _ = session.move(to: map.exits(from: 0)[0].room)
        XCTAssertEqual(session.stage, .failed)
        guard let onward = map.exits(from: session.current).first?.room else {
            return XCTFail("출구 없는 방")
        }
        XCTAssertFalse(session.move(to: onward))
    }

    // MARK: 보스

    /// 보스 방에서 살아남으면 클리어다.
    func testSurvivingTheBossClears() {
        var session = makeRun(budget: 10_000)
        for step in 1..<map.spine.count { XCTAssertTrue(session.move(to: map.spine[step])) }
        XCTAssertEqual(session.stage, .cleared)
        XCTAssertTrue(session.events.contains(.bossFelled))
    }

    /// 보스에게 못 버티면 실패다 — 보스 방 **진입 자체**가 클리어 조건이 아니다.
    /// 결함을 되넣으면(진입만으로 클리어 처리하면) 이 단정이 깨진다.
    func testDyingToTheBossFails() {
        var session = makeRun(budget: 10_000)
        for step in 1..<map.spine.count {
            // 매 방 진입 전 체력을 보스 데미지와 같게 맞춰 둔다 — 보스 방에서 정확히 0 이 된다.
            session.debugSetHitPoints(PuzzleDungeon.bossDamage)
            _ = session.move(to: map.spine[step])
        }
        XCTAssertEqual(session.stage, .failed)
        XCTAssertFalse(session.events.contains(.bossFelled))
    }

    /// 척추 경로를 `move(to:)` 로 실제로 걸어 365일 전부 클리어되는지 — 생성기 쪽 계산이 아니라
    /// 이동 판정을 거친 결과를 본다. 두 곳의 계산이 어긋나면 여기서 갈린다.
    func testEveryDaySpineWalkClearsThroughMoveEntry() {
        for offset in 0..<365 {
            let daily = PuzzleDungeon.map(dayKey: PuzzleDungeonTests.dayKey(offset))
            var session = DungeonRun(map: daily, budget: PuzzleDungeon.baseBudget)
            for step in 1..<daily.spine.count { _ = session.move(to: daily.spine[step]) }
            XCTAssertEqual(session.stage, .cleared, "\(daily.dayKey): hp=\(session.hp)")
        }
    }

    // MARK: 회복의 샘

    /// 회복의 샘은 한 번만 쓰인다 — 아니면 샘과 옆 방을 왕복하며 체력을 무한히 채운다.
    func testSpringHealsOnlyOnce() {
        guard let spring = map.rooms.first(where: { $0.kind == .spring }),
              let approach = map.exits(from: spring.id).first else {
            return XCTFail("이 날짜 맵에 회복샘이 없다")
        }
        var session = makeRun(budget: 10_000)
        session.debugTeleport(to: approach.room)
        session.debugSetHitPoints(10)
        XCTAssertTrue(session.move(to: spring.id))
        let healed = session.hp
        XCTAssertGreaterThan(healed, 10 - approach.cost, "첫 방문은 회복해야 한다")
        XCTAssertTrue(session.move(to: approach.room))
        XCTAssertTrue(session.move(to: spring.id))
        XCTAssertLessThan(session.hp, healed, "두 번째 방문이 또 회복하면 무한 회복이 된다")
        XCTAssertTrue(session.events.contains(.springAlreadyUsed(spring.id)))
    }

    /// 회복은 예산을 넘지 않는다 — 넘으면 척추 배분이 보장한 여유 계산이 무의미해진다.
    func testHealingIsClampedToBudget() {
        guard let spring = map.rooms.first(where: { $0.kind == .spring }),
              let approach = map.exits(from: spring.id).first else {
            return XCTFail("이 날짜 맵에 회복샘이 없다")
        }
        var session = makeRun(budget: 60)
        session.debugTeleport(to: approach.room)
        session.debugSetHitPoints(60)
        _ = session.move(to: spring.id)
        XCTAssertLessThanOrEqual(session.hp, 60)
    }
}
