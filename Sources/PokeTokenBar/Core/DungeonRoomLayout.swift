import Foundation

/// 방 벽면 방위. 서쪽은 절대 문이 없다 — 본선이 왼쪽으로 못 가는 규칙(`DungeonMap.exits`)이
/// 화면에도 그대로 드러난다.
enum RoomSide: CaseIterable, Sendable {
    case north, east, south, west
}

/// 한 방 화면의 격자 좌표. `x` 는 열, `y` 는 행이고 아래로 증가한다(북쪽이 `y` 가 작은 쪽) —
/// `DungeonCoord` 와 같은 축 방향이라 부호를 다시 뒤집을 필요가 없다.
struct GridPoint: Hashable, Sendable {
    let x: Int, y: Int
}

/// 문 하나 — 어느 벽면의 어느 칸이 다른 방(`target`)으로 통하는지.
struct RoomDoor: Equatable, Sendable {
    let side: RoomSide
    let cell: GridPoint
    let target: Int
    let cost: Int
}

/// 바닥 장식 — 순전히 시각용이라 걷기·문 판정에는 관여하지 않는다.
enum FloorDecor: UInt8, Sendable {
    case none = 0, crack, moss, pebble
}

/// 방 하나를 14×9 화면 격자로 편 결과. `DungeonMap` 의 그래프 정보(층·곁방·통로)를 화면에
/// 그릴 문 위치로 바꾸는 순수 매핑이다 — 상태를 갖지 않는다.
struct DungeonRoomLayout: Sendable {
    static let columns = 14, rows = 9

    let room: Int
    let doors: [RoomDoor]
    let decor: [GridPoint: FloorDecor]
    let isHome: Bool

    init(map: DungeonMap, room: Int) {
        self.room = room
        self.isHome = room == 0

        let exits = map.exits(from: room)
        let forward = exits.filter { map.layerOf[$0.room] > map.layerOf[room] }
            .sorted { map.coords[$0.room].y < map.coords[$1.room].y }
        let sideways = exits.filter { map.layerOf[$0.room] <= map.layerOf[room] }

        var placed: [RoomDoor] = []

        // 전진 문 — 동쪽. 하나면 (13,4), 둘이면 목표 y 가 작은 쪽(북쪽)이 (13,3), 나머지가 (13,5).
        if forward.count == 1 {
            placed.append(RoomDoor(side: .east, cell: GridPoint(x: 13, y: 4),
                                    target: forward[0].room, cost: forward[0].cost))
        } else {
            let rowsForCount = Self.eastRows(for: forward.count)
            for (offset, exit) in forward.enumerated() {
                placed.append(RoomDoor(side: .east, cell: GridPoint(x: 13, y: rowsForCount[offset]),
                                        target: exit.room, cost: exit.cost))
            }
        }

        // 곁방 문 — 북/남. 곁방으로 가는 문이든 곁방에서 부모로 돌아가는 문이든, 목표 방이 자신보다
        // y 가 작으면(북쪽에 있으면) 북쪽 문, 아니면 남쪽 문이다. 한 방에 곁방 통로는 최대 하나
        // (곁방은 부모당 하나, 곁방 자신은 나가는 길이 부모뿐)이라 칸이 겹치지 않는다.
        for exit in sideways {
            let side: RoomSide = map.coords[exit.room].y < map.coords[room].y ? .north : .south
            let cell = side == .north ? GridPoint(x: 6, y: 0) : GridPoint(x: 6, y: 8)
            placed.append(RoomDoor(side: side, cell: cell, target: exit.room, cost: exit.cost))
        }

        self.doors = placed

        // 바닥 장식 — 문·벽이 아닌 내부 칸 중 약 10%. 방 번호로 시드를 갈라 방마다 다른 배치를 준다.
        var rng = SplitMix64(seed: PuzzleDungeon.seed(dayKey: map.dayKey) ^ UInt64(room))
        var decor: [GridPoint: FloorDecor] = [:]
        let doorCells = Set(placed.map(\.cell))
        for y in 1..<(Self.rows - 1) {
            for x in 1..<(Self.columns - 1) {
                let point = GridPoint(x: x, y: y)
                guard !doorCells.contains(point) else { continue }
                guard rng.next() % 10 == 0 else { continue }
                switch rng.next() % 3 {
                case 0: decor[point] = .crack
                case 1: decor[point] = .moss
                default: decor[point] = .pebble
                }
            }
        }
        self.decor = decor
    }

    /// 동쪽 문 칸의 y — 하나면 가운데(4), 둘이면 (3,5) 로 벌린다. 셋 이상은 규칙에 없지만
    /// (본선 팬아웃 상한이 2 라 실제로 나오지 않는다) 같은 간격으로 균등하게 편다.
    private static func eastRows(for count: Int) -> [Int] {
        guard count > 1 else { return [4] }
        if count == 2 { return [3, 5] }
        let step = 6 / (count - 1)
        return (0..<count).map { 1 + $0 * step }
    }

    func isWall(_ p: GridPoint) -> Bool {
        let border = p.x == 0 || p.x == Self.columns - 1 || p.y == 0 || p.y == Self.rows - 1
        return border && door(at: p) == nil
    }

    func isWalkable(_ p: GridPoint) -> Bool {
        !isWall(p)
    }

    func door(at p: GridPoint) -> RoomDoor? {
        doors.first { $0.cell == p }
    }

    /// 문 `side` 를 막 들어온 사람이 서는 칸 — 항상 벽에서 한 칸 안쪽.
    static func entryCell(from side: RoomSide) -> GridPoint {
        switch side {
        case .north: return GridPoint(x: 6, y: 1)
        case .south: return GridPoint(x: 6, y: rows - 2)
        case .east: return GridPoint(x: columns - 2, y: 4)
        case .west: return GridPoint(x: 1, y: 4)
        }
    }

    /// 나간 문의 반대쪽 — 그 방향에서 걸어 들어온 것이다.
    static func opposite(_ side: RoomSide) -> RoomSide {
        switch side {
        case .north: return .south
        case .south: return .north
        case .east: return .west
        case .west: return .east
        }
    }
}
