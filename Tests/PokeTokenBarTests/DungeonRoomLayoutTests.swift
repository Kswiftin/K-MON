import XCTest
@testable import PokeTokenBar

final class DungeonRoomLayoutTests: XCTestCase {
    private func days() -> [String] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = cal.timeZone
        return (0..<365).map { f.string(from: cal.date(byAdding: .day, value: $0, to: start)!) }
    }

    func testEveryExitHasExactlyOneDoorAndNoWestDoorAllYear() {
        for day in days() {
            let map = PuzzleDungeon.map(dayKey: day)
            for room in map.rooms.indices {
                let layout = DungeonRoomLayout(map: map, room: room)
                let exits = map.exits(from: room)
                XCTAssertEqual(layout.doors.count, exits.count, "\(day) 방 \(room)")
                XCTAssertEqual(Set(layout.doors.map(\.target)), Set(exits.map(\.room)), "\(day) 방 \(room)")
                XCTAssertFalse(layout.doors.contains { $0.side == .west }, "\(day) 방 \(room) 서쪽 문")
                XCTAssertEqual(Set(layout.doors.map(\.cell)).count, layout.doors.count, "\(day) 방 \(room) 문이 겹친다")
                for door in layout.doors {
                    XCTAssertTrue(layout.isWalkable(door.cell)); XCTAssertFalse(layout.isWall(door.cell))
                    XCTAssertEqual(door.cost, map.cost(from: room, to: door.target))
                }
            }
        }
    }

    func testForwardExitsAreEastAndSpursAreNorthOrSouth() {
        let map = PuzzleDungeon.map(dayKey: "2026-08-21")
        for room in map.rooms.indices {
            for door in DungeonRoomLayout(map: map, room: room).doors {
                if map.layerOf[door.target] > map.layerOf[room] { XCTAssertEqual(door.side, .east, "방 \(room)→\(door.target)") }
                else { XCTAssertTrue([.north, .south].contains(door.side), "방 \(room)→\(door.target)") }
            }
        }
    }

    func testSpurRoomHasExactlyOneDoor() {
        let map = PuzzleDungeon.map(dayKey: "2026-08-21")
        for room in map.rooms.indices where map.isSpur(room) {
            XCTAssertEqual(DungeonRoomLayout(map: map, room: room).doors.count, 1)
        }
    }

    func testSpurReturnDoorFacesTheParent() {
        // 곁방이 부모의 북쪽(y 작음)에 있으면 부모로 돌아가는 문은 남쪽이다.
        let map = PuzzleDungeon.map(dayKey: "2026-08-21")
        for (spur, parent) in map.spurParent {
            let door = DungeonRoomLayout(map: map, room: spur).doors[0]
            XCTAssertEqual(door.side, map.coords[spur].y < map.coords[parent].y ? .south : .north, "곁방 \(spur)")
        }
    }

    func testDecorIsDeterministicAndOnlyOnFloor() {
        let map = PuzzleDungeon.map(dayKey: "2026-08-21")
        let a = DungeonRoomLayout(map: map, room: 3), b = DungeonRoomLayout(map: map, room: 3)
        XCTAssertEqual(a.decor, b.decor)
        for p in a.decor.keys { XCTAssertFalse(a.isWall(p)); XCTAssertNil(a.door(at: p)) }
    }

    func testEntryCellIsJustInsideTheOppositeDoor() {
        XCTAssertEqual(DungeonRoomLayout.opposite(.east), .west)
        XCTAssertEqual(DungeonRoomLayout.entryCell(from: .west), GridPoint(x: 1, y: 4))
        XCTAssertEqual(DungeonRoomLayout.entryCell(from: .north), GridPoint(x: 6, y: 1))
        XCTAssertEqual(DungeonRoomLayout.entryCell(from: .south), GridPoint(x: 6, y: 7))
        XCTAssertEqual(DungeonRoomLayout.entryCell(from: .east), GridPoint(x: 12, y: 4))
    }

    func testHomeFlagOnlyOnRoomZero() {
        let map = PuzzleDungeon.map(dayKey: "2026-08-21")
        XCTAssertTrue(DungeonRoomLayout(map: map, room: 0).isHome)
        XCTAssertFalse(DungeonRoomLayout(map: map, room: 1).isHome)
    }
}
