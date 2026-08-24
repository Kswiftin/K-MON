import Foundation

/// 출구가 놓인 방위. 격자 좌표에서 나오고, `y` 는 아래로 증가한다(북쪽이 `y` 가 작은 쪽).
enum DungeonDirection: String, Sendable, CaseIterable {
    case north, northEast, east, southEast, south, southWest, west, northWest

    /// 화살표는 세 언어가 같으므로 문구 파일이 아니라 여기 둔다.
    var arrow: String {
        switch self {
        case .north: return "↑"
        case .northEast: return "↗"
        case .east: return "→"
        case .southEast: return "↘"
        case .south: return "↓"
        case .southWest: return "↙"
        case .west: return "←"
        case .northWest: return "↖"
        }
    }
}

/// 한 출구의 판단 재료. **문자열이 아니라 값**이다 — 문구는 화면이 `Localization` 으로 만든다.
struct DungeonExitChoice: Sendable, Equatable {
    let room: Int
    let cost: Int
    /// 좌표가 겹치면(격자 칸은 유일하므로 정상 맵에서는 없다) 방위를 만들지 않는다.
    let direction: DungeonDirection?
    /// 밝혀진 정체. `nil` 이면 안개 — 이름만 보이고 종류는 숨는다.
    let known: RoomKind?
    /// 이미 마신 회복의 샘인가. 정체가 샘으로 밝혀진 출구에만 의미가 있다.
    let springSpent: Bool
    /// 통로 비용만으로 쓰러지는 길. 방 내용은 들어가야 알 수 있으니 통로만 본다.
    let isLethal: Bool

    /// 이미 밟아 본 방으로 되돌아가는 길.
    var isBacktrack: Bool { known != nil }
}

/// 현재 방에서 화면이 말할 수 있는 것. **밝혀진 사실만 담는다** — 안개를 새는 값은 만들지 않는다.
struct DungeonSceneNote: Sendable, Equatable {
    let kind: RoomKind
    /// 아직 마시지 않은 회복의 샘이 인접해 **밝혀져 있을 때만** 방위가 들어간다("물소리가 난다").
    let springDirection: DungeonDirection?
    /// 정체가 아직 안 밝혀진 인접 출구 수.
    let darkExitCount: Int
}

/// 지나온 길 한 줄 — 이벤트를 방 단위로 묶는다. 낱개 이벤트를 그대로 그리면 `−24` 가 어느 방에서
/// 나온 값인지 안 보인다(#79 로그 결함).
struct DungeonTrailStep: Sendable, Equatable {
    let room: Int
    let kind: RoomKind
    /// 이 방에 들어오며 겪은 체력 변화. 통로 비용과 방 내용이 순서대로 들어간다(음수는 소모).
    var deltas: [Int] = []
    var springWasDry = false
    var felledBoss = false
    var collapsed = false
}

/// 던전 화면이 쓰는 순수 계산 — 방위·방 이름 슬롯·체력 게이지·출구 분류·서술 재료.
///
/// **뷰가 아니라 여기 있는 이유:** 순수 코어(`PuzzleDungeon`·`DungeonRun`)만 테스트로 잠그고 화면을
/// 뷰에 두면, 설계 목업이 있는 줄들이 무테스트로 남아 화면만 설계의 절반인 채 게이트를 통과한다
/// (#79 실측: 설계 목업 6줄 중 온전히 구현된 것이 0개였다). 이 파일은 `test-gate.sh` 의
/// `LOGIC_CORE` 에 들어간다.
enum DungeonNarration {
    /// 방 이름 슬롯 수. **방 수보다 커야** 한 맵에 같은 이름이 두 번 나오지 않는다.
    static let roomNameSlots = 16

    /// 격자 좌표에서 방위를 만든다. 주축이 뚜렷하면(다른 축의 두 배 이상) 한 방위로 줄인다 —
    /// 여덟 방위를 다 쓰면 "북동"·"북"이 사실상 같은 길인데 다르게 읽힌다.
    static func direction(from: DungeonCoord, to: DungeonCoord) -> DungeonDirection? {
        let dx = to.x - from.x, dy = to.y - from.y
        guard dx != 0 || dy != 0 else { return nil }
        if dx == 0 { return dy < 0 ? .north : .south }
        if dy == 0 { return dx > 0 ? .east : .west }
        if abs(dy) >= abs(dx) * 2 { return dy < 0 ? .north : .south }
        if abs(dx) >= abs(dy) * 2 { return dx > 0 ? .east : .west }
        if dy < 0 { return dx > 0 ? .northEast : .northWest }
        return dx > 0 ? .southEast : .southWest
    }

    /// 방 번호 → 이름 슬롯. 날짜 seed 에서 결정론으로 섞으므로 같은 날이면 어느 기기에서나 같은
    /// 이름이고, **정체와 무관하다** — 이름은 안개를 새지 않으므로 미탐사 방도 이름은 보여 준다.
    /// (이름 없이 방위만 두면 오늘 맵처럼 "남동쪽" 출구가 세 개 나와 구분이 안 된다.)
    static func nameSlots(dayKey: String) -> [Int] {
        // 맵 생성과 다른 seed 를 쓴다 — 같은 스트림을 나눠 쓰면 이름을 바꿀 때 맵이 따라 바뀐다.
        var rng = SplitMix64(seed: PuzzleDungeon.seed(dayKey: dayKey) ^ 0x5EED_D00D_5EED_D00D)
        var pool = Array(0..<roomNameSlots)
        for i in stride(from: pool.count - 1, to: 0, by: -1) {
            pool.swapAt(i, Int(rng.next() % UInt64(i + 1)))
        }
        return Array(pool.prefix(PuzzleDungeon.roomCount))
    }

    /// 체력 게이지. 숫자만 두면 남은 여유가 감으로 안 온다(설계 목업의 `▓▓▓▓▓▓░░`).
    /// **0 은 반드시 빈 칸, 만피는 반드시 꽉 찬 칸**이다 — 반올림이 그 두 끝을 흐리면 죽기 직전과
    /// 여유가 같은 그림이 된다.
    static func gauge(hp: Int, budget: Int, width: Int = 12) -> String {
        guard budget > 0, width > 0 else { return String(repeating: "░", count: max(0, width)) }
        let clamped = max(0, min(budget, hp))
        var filled = (clamped * width + budget / 2) / budget
        if clamped == 0 { filled = 0 }
        if clamped > 0 { filled = max(1, filled) }
        if clamped < budget { filled = min(width - 1, filled) }
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: width - filled)
    }

    /// 출구를 **새 길 / 되돌아가기**로 나누고 비용 오름차순으로 정렬한다. 오늘 맵의 시작 방은
    /// 출구가 8개라, 섞어서 나열하면 목록이 화면 절반을 먹고도 무엇이 새 길인지 안 보인다.
    static func choices(for run: DungeonRun) -> (fresh: [DungeonExitChoice], back: [DungeonExitChoice]) {
        let coords = run.map.coords
        let rows = run.exits.map { exit in
            DungeonExitChoice(room: exit.room, cost: exit.cost,
                              direction: direction(from: coords[run.current], to: coords[exit.room]),
                              known: exit.known,
                              springSpent: run.usedSprings.contains(exit.room),
                              isLethal: exit.cost >= run.hp)
        }
        // 동점은 방 번호 순 — 순서가 흔들리면 같은 화면에서 버튼이 매번 자리를 바꾼다.
        let ordered = rows.sorted { ($0.cost, $0.room) < ($1.cost, $1.room) }
        return (ordered.filter { !$0.isBacktrack }, ordered.filter(\.isBacktrack))
    }

    /// 서술 재료. 마신 샘은 물소리를 내지 않고, 밝혀지지 않은 방은 아무것도 흘리지 않는다.
    static func scene(for run: DungeonRun) -> DungeonSceneNote {
        let coords = run.map.coords
        let spring = run.exits.first {
            $0.known == .spring && !run.usedSprings.contains($0.room)
        }
        return DungeonSceneNote(
            kind: run.map.room(run.current).kind,
            springDirection: spring.flatMap { direction(from: coords[run.current], to: coords[$0.room]) },
            darkExitCount: run.exits.filter { $0.known == nil }.count)
    }

    /// 이벤트를 방 단위로 묶는다. `.entered` 앞에 붙은 통로 비용은 **그 방으로 들어가며 낸 값**이라
    /// 다음 줄에 얹는다 — 앞 줄에 붙이면 이미 지나온 방이 더 비싸 보인다.
    ///
    /// `.damaged` 는 통로 비용과 방 내용 둘 다라 이벤트 값만으로는 구분되지 않는다. 가르는 규칙은
    /// **다음 이벤트가 입장(`.entered`)이면 그 데미지는 통로 비용**이라는 것 하나다 — 통로 비용은
    /// 항상 1 이상이라 방 내용 뒤에 입장이 바로 붙는 경우가 없다.
    ///
    /// "방에 들어선 직후 한 건이 방 내용"으로 가르면 안 된다. 빈 방은 내용 이벤트를 하나도 내지
    /// 않아서 다음 통로 비용이 빈 방 줄에 붙는다(구현 중 실측으로 잡힌 결함).
    static func trail(_ events: [DungeonEvent], start: RoomKind) -> [DungeonTrailStep] {
        var steps = [DungeonTrailStep(room: 0, kind: start)]
        var pending: [Int] = []
        for (index, event) in events.enumerated() {
            switch event {
            case .entered(let room, let kind):
                steps.append(DungeonTrailStep(room: room, kind: kind, deltas: pending))
                pending = []
            case .damaged(let amount):
                let nextIsEntry: Bool
                if index + 1 < events.count, case .entered = events[index + 1] { nextIsEntry = true }
                else { nextIsEntry = false }
                if nextIsEntry {
                    pending.append(-amount)                       // 다음 방으로 가는 통로
                } else {
                    steps[steps.count - 1].deltas.append(-amount) // 지금 방의 내용
                }
            case .healed(let amount):
                steps[steps.count - 1].deltas.append(amount)
            case .springAlreadyUsed:
                steps[steps.count - 1].springWasDry = true
            case .bossFelled:
                steps[steps.count - 1].felledBoss = true
            case .collapsed:
                // 통로에서 쓰러지면 새 방 줄이 없다 — 비용은 위 규칙에 따라 이미 마지막 줄에 붙어 있다.
                steps[steps.count - 1].collapsed = true
            }
        }
        return steps
    }
}
