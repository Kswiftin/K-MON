import Foundation

/// 시도 중 일어난 일. **문자열이 아니라 값**이다 — 문구는 화면이 `Localization` 으로 만든다.
/// 코어가 문자열을 만들면 언어를 바꿀 때 로그만 이전 언어로 남는다.
enum DungeonEvent: Sendable, Equatable {
    case entered(room: Int, kind: RoomKind)
    case damaged(Int)
    case healed(Int)
    case springAlreadyUsed(Int)
    /// 보물방을 털었다 — 별의조각 액수. 정산은 스토어가 한다(코어는 값만 남긴다).
    case looted(room: Int, starPieces: Int)
    /// 오늘 이미 턴 보물방에 다시 들어왔다 — 왕복 통로 비용만 낸 꽝.
    case cacheAlreadyLooted(Int)
    case bossFelled
    case collapsed
}

/// 한 번의 시도. 순수 구조체이고 시각(`Date`)을 쓰지 않는다 — 맵은 날짜 키로, 시도는 순수 함수로
/// 결정된다. 시도 중 상태는 세이브에 남지 않는다(팝오버를 닫으면 시도만 버려진다).
struct DungeonRun: Sendable {
    enum Stage: Sendable, Equatable { case exploring, cleared, failed }

    let map: DungeonMap
    let budget: Int
    private(set) var hp: Int
    private(set) var current = 0
    /// 정체가 밝혀진 방 — 이번 시도에서 밟은 방 + 지난 시도가 남긴 기억.
    private(set) var revealed: [Int: RoomKind]
    private(set) var usedSprings: Set<Int> = []
    /// 이번 시도에서 이미 치른 교전. **교전은 방마다 한 번**이다 — 곁방에서 본선 방으로 되나올 때
    /// 그 방의 교전이 다시 붙으면 곁방 왕복 비용이 "통로 두 번"이 아니라 "통로 두 번 + 재전투"가 되어
    /// 설계의 기대값 계산과 "층 교전은 정확히 한 번" 보장이 깨진다(구현 중 실측으로 잡힌 결함).
    private(set) var fought: Set<Int> = []
    /// 턴 보물방 — 오늘 앞선 시도에서 턴 것 + 이번 시도. **보물은 하루 한 번만**이라 시도를 넘어 든다.
    private(set) var looted: Set<Int>
    private(set) var events: [DungeonEvent] = []
    private(set) var stage: Stage = .exploring

    init(map: DungeonMap, budget: Int, remembered: [Int: RoomKind] = [:], looted: Set<Int> = []) {
        self.map = map
        self.budget = budget
        self.hp = budget
        // 손편집·구맵 잔재 방어: 오늘 맵에 없는 방 번호와 실제와 다른 정체는 버린다.
        // 방 수는 날마다 다르므로 고정 상한이 아니라 **오늘 맵의 방 수**로 검사한다.
        self.revealed = remembered.filter { entry in
            map.rooms.indices.contains(entry.key) && map.room(entry.key).kind == entry.value
        }
        self.revealed[0] = map.room(0).kind
        self.looted = looted.filter { map.rooms.indices.contains($0) && map.room($0).kind == .cache }
    }

    /// 지금 있는 층(0 시작). 화면은 `층 + 1 / 층 수` 로 그린다.
    var layer: Int { map.layerOf[current] }

    /// 오늘 맵의 보물방을 전부 털었나 — 업적 `dungeonSweep` 의 판정. 보물방이 없는 날은 참이 아니다
    /// (거저 주지 않는다).
    var sweptAllCaches: Bool {
        let caches = Set(map.rooms.filter { $0.kind == .cache }.map(\.id))
        return !caches.isEmpty && caches.isSubset(of: looted)
    }

    /// 출구 목록 — 정체는 밝혀진 방만 딸려 나간다(안개).
    var exits: [(room: Int, cost: Int, known: RoomKind?)] {
        map.exits(from: current).map { (room: $0.room, cost: $0.cost, known: revealed[$0.room]) }
    }

    /// **이동 입구는 이것 하나다.** 인접 검증 → 통로 비용 차감 → 방 내용 적용 → 판정.
    /// 판정과 클램프가 여기 한 곳에만 있어야 한다(경험치 클램프 입구를 하나로 모은 #81 과 같은 이유 —
    /// 입구가 여러 개면 한 곳만 고치고 끝난다).
    @discardableResult
    mutating func move(to room: Int) -> Bool {
        guard stage == .exploring, let cost = map.cost(from: current, to: room) else { return false }
        spend(cost)
        guard stage == .exploring else { return true }   // 통로에서 쓰러졌다
        current = room
        let entered = map.room(room)
        revealed[room] = entered.kind
        events.append(.entered(room: room, kind: entered.kind))
        switch entered.kind {
        case .empty:
            break
        case .encounter:
            if !fought.contains(room) {
                fought.insert(room)
                spend(entered.damage)
            }
        case .spring:
            // 한 번만 쓰인다. 아니면 샘과 옆 방을 왕복하며 체력을 무한히 채운다.
            if usedSprings.contains(room) {
                events.append(.springAlreadyUsed(room))
            } else {
                usedSprings.insert(room)
                let healed = min(budget, hp + entered.damage) - hp
                hp += healed
                events.append(.healed(healed))
            }
        case .cache:
            // 하루 한 번만. 아니면 재도전마다 같은 보물방을 털어 하루 상한이 무의미해진다.
            if looted.contains(room) {
                events.append(.cacheAlreadyLooted(room))
            } else {
                looted.insert(room)
                events.append(.looted(room: room, starPieces: entered.damage))
            }
        case .boss:
            spend(entered.damage)
            if stage == .exploring {
                stage = .cleared
                events.append(.bossFelled)
            }
        }
        return true
    }

    /// 체력 차감의 유일한 경로 — 클램프와 실패 판정이 여기 붙어 있다.
    private mutating func spend(_ amount: Int) {
        guard amount > 0 else { return }
        hp = max(0, hp - amount)
        events.append(.damaged(amount))
        if hp == 0 {
            stage = .failed
            events.append(.collapsed)
        }
    }
}

#if DEBUG
extension DungeonRun {
    /// 테스트 전용 — 특정 방·체력에서 시작하는 상황을 만든다. 프로덕션 경로는 `move(to:)` 뿐이다.
    /// 도착한 것으로 친다 — 정체를 밝히고 교전 방이면 치른 것으로 둔다(실제 진입은 늘 `move` 를 지나 교전을 치른다).
    mutating func debugTeleport(to room: Int) {
        current = room
        revealed[room] = map.room(room).kind
        if map.room(room).kind == .encounter { fought.insert(room) }
    }
    mutating func debugSetHitPoints(_ value: Int) { hp = max(0, min(budget, value)) }
    /// 테스트 전용 — 보물방을 턴 것으로 친다(`move(to:)` 없이 `sweptAllCaches` 경계를 밟는다).
    mutating func debugLoot(_ room: Int) { looted.insert(room) }
}
#endif
