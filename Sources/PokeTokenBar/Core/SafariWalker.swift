import Foundation

/// 격자 칸 좌표. `(x: Int, y: Int)` 튜플로 두지 않는 이유는 튜플이 `Codable` 을 준수할 수 없어서다
/// — `SafariWalker` 를 그대로 저장해야 하므로 칸도 이름 있는 타입이어야 한다.
struct SafariCell: Sendable, Codable, Equatable, Hashable {
    var x: Int
    var y: Int
}

/// 벌판의 경계 — 바깥 테두리는 전부 벽이다(문이 없다). `room-walk-dungeon-design.md` 의
/// `DungeonRoomLayout` 과 같은 치수(14×9)를 쓴다.
struct SafariFieldBounds: Sendable, Equatable {
    let width: Int
    let height: Int

    /// 사파리존 벌판의 표준 크기. 팝오버 `contentWidth` 안에 들어가는 값이 접힌 설계에서 이미
    /// 검증돼 있다(칸 24pt × 14 = 336pt).
    static let standard = SafariFieldBounds(width: 14, height: 9)

    func contains(_ cell: SafariCell) -> Bool {
        (0..<width).contains(cell.x) && (0..<height).contains(cell.y)
    }
}

/// 그 순간 눌려 있는 방향키(WASD 겸용은 UI 레이어가 이 값으로 매핑해 넘긴다). 여러 방향이 동시에
/// 눌려 있으면 `allCases` 순서(위→아래→왼쪽→오른쪽)로 하나만 고른다 — 대각선 이동은 없다.
enum SafariDirectionKey: CaseIterable, Sendable {
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

/// 격자 이동 상태기계 — `room-walk-dungeon-design.md` 의 `DungeonWalker` 설계에서 문·방 전환만
/// 뺀 것. 사파리존은 방-대-방 탐색이 없는 단일 열린 벌판이라 벽 충돌 판정만 있으면 된다.
/// `SafariZone`/`SafariEncounter` 와 마찬가지로 뷰·소켓 의존 0.
struct SafariWalker: Sendable, Codable, Equatable {
    private(set) var cell: SafariCell
    private(set) var facing: Facing
    /// 0 = 정지, (0,1] = 이동 중(1 에서 도착).
    private(set) var moveProgress: Double = 0
    /// 이동 중일 때의 출발·목표 칸 — 애니메이션 보간에 화면이 직접 쓴다(`moveProgress` 와 함께).
    private(set) var moveOrigin: SafariCell?
    private(set) var moveTarget: SafariCell?

    /// 칸 하나를 건너는 데 걸리는 시간(초) — 접힌 설계와 같은 값(0.18s/칸).
    static let secondsPerCell = 0.18
    /// 팝오버가 숨었다 돌아올 때 한 틱에 순간이동하지 않도록 거는 `dt` 상한.
    static let maxDeltaTime = 0.1

    init(startingAt cell: SafariCell, facing: Facing = .down) {
        self.cell = cell
        self.facing = facing
    }

    /// 매 프레임 호출. 칸에 **새로 도착한 순간**(스냅 시점)이면 `true` 를 돌려준다 — 호출부
    /// (`SafariVisit.advance`)가 걸음 소모·인카운터 굴림을 정확히 한 번 실행해야 한다는 신호다.
    /// `obstacles` 칸은 벽과 같은 방식으로 막힌다(방향만 바뀌고 제자리) — 기본값 `[]` 라 장애물
    /// 없는 기존 호출부·테스트는 그대로 컴파일된다.
    @discardableResult
    mutating func tick(dt: Double, heldKeys: Set<SafariDirectionKey>, bounds: SafariFieldBounds,
                       obstacles: Set<SafariCell> = []) -> Bool {
        let clampedDelta = min(Self.maxDeltaTime, max(0, dt))
        if moveProgress > 0 {
            moveProgress = min(1, moveProgress + clampedDelta / Self.secondsPerCell)
            guard moveProgress >= 1, let target = moveTarget else { return false }
            cell = target
            moveProgress = 0
            moveOrigin = nil
            moveTarget = nil
            return true
        }
        // 정지 상태 — 눌린 방향이 있으면 그쪽으로 새 이동을 시작한다.
        guard let direction = SafariDirectionKey.allCases.first(where: heldKeys.contains) else {
            return false
        }
        facing = direction.facing
        let candidate = SafariCell(x: cell.x + direction.delta.dx, y: cell.y + direction.delta.dy)
        guard bounds.contains(candidate), !obstacles.contains(candidate) else {
            // 벽 또는 장애물 — 방향만 바꾸고(이미 위에서 바꿨다) 제자리에 머문다.
            return false
        }
        moveOrigin = cell
        moveTarget = candidate
        moveProgress = min(1, clampedDelta / Self.secondsPerCell)
        guard moveProgress >= 1 else { return false }
        cell = candidate
        moveProgress = 0
        moveOrigin = nil
        moveTarget = nil
        return true
    }
}
