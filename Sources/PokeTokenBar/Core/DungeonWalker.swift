import Foundation

/// 화면 격자에서 사람이 누르는 네 방향. `Facing` 과 분리한 이유는 이동 방향과 바라보는 방향이
/// 걷는 동안은 같지만 벽에 막혀도 방향만 바뀌는 경우가 있어서다(`testWallBlocksButTurnsTheTrainer`).
enum WalkDirection: CaseIterable, Sendable {
    case up, down, left, right

    var delta: (dx: Int, dy: Int) {
        switch self {
        case .up: return (0, -1)
        case .down: return (0, 1)
        case .left: return (-1, 0)
        case .right: return (1, 0)
        }
    }

    var facing: Facing {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}

/// 한 칸 이동 중의 보간 상태. 진행률(`progress`)이 1 에 닿으면 `to` 로 확정된다.
struct DungeonWalkerMotion: Equatable, Sendable {
    let from: GridPoint
    let to: GridPoint
    var progress: Double
}

/// 던전 방 화면에서 트레이너를 칸 단위로 걷게 하는 상태 기계. `DungeonRun` 은 방 그래프 위의
/// 이동만 알고, 그 이동을 화면 격자에서 발로 걷는 것처럼 보이게 하는 계층이 이것이다 —
/// 문 칸에 도착하는 순간에만 `run.move(to:)` 를 부른다(설계: `docs/reference/layered-dungeon-design.md`).
struct DungeonWalker: Sendable {
    /// 한 칸을 걷는 데 걸리는 시간(초).
    static let stepDuration: TimeInterval = 0.18
    /// `tick` 에 들어오는 델타의 상한 — 팝오버가 숨겨진 동안 쌓인 큰 델타가 한 번에 여러 칸을
    /// 텔레포트시키지 않게 자른다.
    static let maxDelta: TimeInterval = 0.1

    private(set) var run: DungeonRun
    private(set) var layout: DungeonRoomLayout
    private(set) var cell: GridPoint
    private(set) var facing: Facing = .down
    private(set) var motion: DungeonWalkerMotion?
    private(set) var held: Set<WalkDirection> = []
    /// 가장 최근에 누른 방향이 우선하도록 누른 순서를 따로 기억한다(`held` 는 `Set` 이라 순서가 없다).
    private var heldOrder: [WalkDirection] = []
    private(set) var arrival: [DungeonEvent]?
    var locked = false
    private(set) var autoPath: [GridPoint] = []
    /// 걸음마다 번갈아 1/2 을 내는 토글 — 연속한 두 칸이 같은 스텝으로 안 보이게 한다.
    private var stepParity = false

    init(run: DungeonRun) {
        self.run = run
        self.layout = DungeonRoomLayout(map: run.map, room: run.current)
        self.cell = GridPoint(x: 1, y: 4)
        self.facing = .right
    }

    mutating func press(_ direction: WalkDirection) {
        guard !locked else { return }
        held.insert(direction)
        heldOrder.removeAll { $0 == direction }
        heldOrder.append(direction)
    }

    mutating func release(_ direction: WalkDirection) {
        held.remove(direction)
        heldOrder.removeAll { $0 == direction }
    }

    /// 마우스로 찍은 문까지 가는 경로 — 가로로 문의 x 까지, 그다음 세로로 문의 y 까지(L자).
    mutating func walkTo(door: RoomDoor) {
        guard !locked else { return }
        // 동쪽 문(x=13)은 벽 칸이라 가로 이동은 안쪽 칸(12)까지만 가고, 세로로 문 높이에 맞춘 뒤
        // 마지막 한 걸음으로 문 칸 자체에 들어간다. 북/남 문은 x=6 이 이미 안쪽이라 그대로 쓴다.
        let interiorX = door.side == .east ? min(door.cell.x, DungeonRoomLayout.columns - 2) : door.cell.x
        var path: [GridPoint] = []
        var x = cell.x
        while x != interiorX {
            x += x < interiorX ? 1 : -1
            path.append(GridPoint(x: x, y: cell.y))
        }
        var y = cell.y
        while y != door.cell.y {
            y += y < door.cell.y ? 1 : -1
            path.append(GridPoint(x: x, y: y))
        }
        while x != door.cell.x {
            x += x < door.cell.x ? 1 : -1
            path.append(GridPoint(x: x, y: y))
        }
        autoPath = path
    }

    @discardableResult
    mutating func tick(_ rawDelta: TimeInterval) -> Bool {
        let dt = min(rawDelta, Self.maxDelta)
        guard !locked else { return false }
        var changed = false

        // 서 있는 상태면 이번 프레임에 새 모션을 만들 수 있다 — 방향 입력 처리는 여기서 끝나지 않고,
        // 아래에서 바로 그 모션에 이번 프레임의 dt 를 적용한다. 그래야 "누른 프레임"이 낭비되지 않고
        // `stepDuration` 초 뒤 딱 한 칸 이동한다(`testPressingMovesOneCellAfterStepDuration`).
        if motion == nil {
            if let next = autoPath.first {
                autoPath.removeFirst()
                beginMoveIfWalkable(to: next)
                changed = true
            } else if let direction = heldOrder.last(where: { held.contains($0) }) {
                let delta = direction.delta
                let target = GridPoint(x: cell.x + delta.dx, y: cell.y + delta.dy)
                facing = direction.facing
                if layout.isWalkable(target) {
                    motion = DungeonWalkerMotion(from: cell, to: target, progress: 0)
                }
                changed = true
            }
        }

        if var current = motion {
            current.progress += dt / Self.stepDuration
            if current.progress >= 1 {
                cell = current.to
                motion = nil
                stepParity.toggle()
                if let door = layout.door(at: cell) {
                    transition(through: door)
                }
            } else {
                motion = current
            }
            changed = true
        }

        return changed
    }

    private mutating func beginMoveIfWalkable(to target: GridPoint) {
        if target.x > cell.x { facing = .right }
        else if target.x < cell.x { facing = .left }
        else if target.y > cell.y { facing = .down }
        else if target.y < cell.y { facing = .up }
        guard layout.isWalkable(target) else { return }
        motion = DungeonWalkerMotion(from: cell, to: target, progress: 0)
    }

    /// 문 칸에 도착했을 때의 유일한 방 전환 경로. `run.move` 실패는 벽 계산과 방 그래프가 어긋난
    /// 것이라 정상 경로에서는 일어나지 않는다 — 로그만 남기고 그 자리에 세워둔다.
    private mutating func transition(through door: RoomDoor) {
        let before = run.events.count
        guard run.move(to: door.target) else {
            AppLog.write("DungeonWalker: room \(run.current) 문 \(door.side) 이동 실패 — 방 그래프와 벽 계산 불일치")
            return
        }
        layout = DungeonRoomLayout(map: run.map, room: run.current)
        let enteredSide = DungeonRoomLayout.opposite(door.side)
        cell = DungeonRoomLayout.entryCell(from: enteredSide)
        facing = door.side == .east ? .right : door.side == .west ? .left : door.side == .north ? .up : .down
        arrival = Array(run.events[before...])
        locked = true
        autoPath = []
        held = []
        heldOrder = []
    }

    mutating func consumeArrival() -> [DungeonEvent]? {
        defer { arrival = nil }
        return arrival
    }

    /// 그릴 것도 계산할 것도 없는 상태 — 화면이 게임루프를 멈춰도 되는지의 판단이다.
    ///
    /// 잠긴 walker 는 키가 눌려 있어도 `tick` 이 아무것도 하지 않으므로 멈춘 것으로 센다.
    /// 판정이 끝난 시도(클리어·실패)는 영구 잠금이라, 이걸 빼면 손가락을 올린 채 두기만 해도
    /// 60fps 루프가 계속 헛돈다. **단 `arrival` 이 남아 있으면 멈추지 않는다** — 도착 이벤트를
    /// 아직 아무도 읽지 않은 상태에서 루프가 서면 연출도 잠금 해제도 오지 않는다.
    var isIdle: Bool {
        guard arrival == nil else { return false }
        return locked || (motion == nil && held.isEmpty && autoPath.isEmpty)
    }

    /// 서 있으면 0, 걷는 중이면 진행률 절반을 기준으로 1/2 를 내되 `stepParity` 로 번갈아 순서를 뒤집는다
    /// (연속한 두 칸이 같은 스텝 프레임으로 안 보이게).
    var animationStep: Int {
        guard let motion else { return 0 }
        let stepA = stepParity ? 2 : 1
        let stepB = stepParity ? 1 : 2
        return motion.progress < 0.5 ? stepA : stepB
    }

    var visualPosition: (x: Double, y: Double) {
        guard let motion else { return (Double(cell.x), Double(cell.y)) }
        let t = min(motion.progress, 1)
        let x = Double(motion.from.x) + (Double(motion.to.x) - Double(motion.from.x)) * t
        let y = Double(motion.from.y) + (Double(motion.to.y) - Double(motion.from.y)) * t
        return (x, y)
    }
}
