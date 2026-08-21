import Foundation

/// 방 하나의 정체. 들어가기 전까지 숨긴다(안개) — 처음부터 다 보이면 앉은 자리에서 답이 나와
/// 퍼즐이 성립하지 않는다.
enum RoomKind: String, Codable, Sendable, CaseIterable {
    case empty, encounter, spring, boss
}

struct DungeonRoom: Sendable, Equatable {
    let id: Int
    /// 교전·보스는 고정 데미지, 회복샘은 회복량, 빈 방은 0.
    let kind: RoomKind
    let damage: Int
}

/// 방 사이 통로. `cost` 는 지나갈 때 깎이는 체력(1~3)이고 좌표에서 나온다.
/// `a < b` 로 정규화해 같은 통로가 두 번 들어가지 않게 한다.
struct DungeonEdge: Hashable, Sendable {
    let a: Int, b: Int, cost: Int

    init(_ x: Int, _ y: Int, cost: Int) {
        self.a = min(x, y); self.b = max(x, y); self.cost = cost
    }

    func other(than room: Int) -> Int? { room == a ? b : (room == b ? a : nil) }
}

/// 하루치 맵. 좌표는 담지 않는다 — 통로 비용을 만드는 데만 쓰고 화면에 그리지 않는다.
struct DungeonMap: Sendable {
    let dayKey: String
    let rooms: [DungeonRoom]
    let edges: [DungeonEdge]
    /// 시작 방에서 보스까지 이어지는 경로. **클리어 가능성의 근거**라 생성 결과로 남긴다
    /// (기본 예산 100 으로 이 경로만 따라가면 여유를 남기고 도달한다). 화면에는 쓰지 않는다.
    let spine: [Int]
    /// 오늘의 상성 축 — 동행 파트너가 이 타입에 강하면 예산 +5.
    let affinity: PokemonType
    /// 최소 신장 트리가 쓴 간선 수(= 방 수 − 1). 여분 간선 비율을 검사할 기준.
    let mstEdgeCount: Int

    var bossRoom: Int { spine[spine.count - 1] }

    func room(_ id: Int) -> DungeonRoom { rooms[id] }

    func exits(from room: Int) -> [(room: Int, cost: Int)] {
        edges.compactMap { edge in edge.other(than: room).map { (room: $0, cost: edge.cost) } }
            .sorted { $0.room < $1.room }
    }

    func cost(from: Int, to: Int) -> Int? {
        edges.first { ($0.a == from && $0.b == to) || ($0.a == to && $0.b == from) }?.cost
    }
}

/// 날짜 키에서 하루치 맵을 만든다 — 무작위가 전혀 없어 같은 날이면 모두 같은 맵을 푼다.
///
/// 클리어 가능성은 **구조에서 나온다**: 시작 방에서 보스까지 이어지는 척추 경로를 먼저 깔고,
/// 그 경로만 따라가면 기본 예산 100 으로 `clearSlack` 만큼 여유를 남기고 도달하도록 데미지를
/// 배분한다. 최적 해를 계산하는 솔버가 필요 없는 이유다.
enum PuzzleDungeon {
    static let roomCount = 14
    static let baseBudget = 100
    /// 보스 한 줄의 데미지. 다른 방들과 급이 달라야 "가장 깊은 방"이 무게를 갖는다.
    static let bossDamage = 30
    static let springHeal = 20
    /// 척추 경로만 따라갔을 때 남기는 최소 여유. 보정 상한(+10)보다 커야 퍼즐이 남는다.
    static let clearSlack = 15
    static let firstClearReward = 1_000
    /// 좌표 격자 한 변. 14방을 담고 통로 길이에 편차를 주려면 방 수의 두 배 이상 칸이 필요하다.
    static let gridSide = 6

    static func seed(dayKey: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in dayKey.utf8 { h ^= UInt64(byte); h = h &* 0x100_0000_01b3 }
        return h
    }

    /// 체력 예산 — 기준선 100 에서 **더하기만** 한다. 불리한 조합도 기준선은 받는다.
    static func budget(partnerTypes: [PokemonType], against affinity: PokemonType,
                       usedItem: Bool, trainerLevel: Int) -> Int {
        var budget = baseBudget
        if partnerTypes.contains(where: { TypeChart.effectiveness($0, against: [affinity]) > 1 }) {
            budget += 5
        }
        if usedItem { budget += 3 }
        // 매일 같은 값이라 판단 요소가 아니다 — 존재감만 남긴다(상한 2).
        budget += min(2, max(0, trainerLevel / 25))
        return budget
    }

    static func map(dayKey: String) -> DungeonMap {
        var rng = SplitMix64(seed: seed(dayKey: dayKey))
        let coords = pickCoordinates(&rng)
        let spine = pickSpine(&rng)
        var edges = Set<DungeonEdge>()
        for step in 0..<(spine.count - 1) {
            edges.insert(DungeonEdge(spine[step], spine[step + 1],
                                     cost: corridorCost(coords, spine[step], spine[step + 1])))
        }
        // 척추를 씨앗으로 최소 신장 트리를 키운다 — 척추 간선을 나중에 붙이면 트리가 그걸 버릴 수 있다.
        connectAll(&edges, coords: coords, seeded: Set(spine))
        let mstEdgeCount = edges.count
        addExtraEdges(&edges, coords: coords, &rng)

        let rooms = placeRooms(spine: spine, coords: coords, &rng)
        let affinity = PokemonType.allCases[Int(rng.next() % UInt64(PokemonType.allCases.count))]
        return DungeonMap(dayKey: dayKey, rooms: rooms,
                          edges: edges.sorted { ($0.a, $0.b) < ($1.a, $1.b) },
                          spine: spine, affinity: affinity, mstEdgeCount: mstEdgeCount)
    }

    // MARK: 좌표·통로

    private static func pickCoordinates(_ rng: inout SplitMix64) -> [(x: Int, y: Int)] {
        var cells = Array(0..<(gridSide * gridSide))
        for i in stride(from: cells.count - 1, to: 0, by: -1) {
            cells.swapAt(i, Int(rng.next() % UInt64(i + 1)))
        }
        return cells.prefix(roomCount).map { (x: $0 % gridSide, y: $0 / gridSide) }
    }

    /// 통로 길이 1~3. 격자 거리를 그대로 쓰면 최대 10 이라 통로만으로 예산이 사라진다.
    private static func corridorCost(_ coords: [(x: Int, y: Int)], _ a: Int, _ b: Int) -> Int {
        let distance = abs(coords[a].x - coords[b].x) + abs(coords[a].y - coords[b].y)
        return min(3, max(1, (distance + 1) / 3))
    }

    /// 척추 경로 — 시작 방 0 에서 6~8방. 그래프를 만든 뒤 최단경로로 찾지 않는다:
    /// 여분 간선이 지름을 3~4방으로 줄여 6방을 못 만든다. **경로를 먼저 정하고 그래프를 거기 맞춘다.**
    private static func pickSpine(_ rng: inout SplitMix64) -> [Int] {
        let length = 6 + Int(rng.next() % 3)          // 6...8
        var rest = Array(1..<roomCount)
        for i in stride(from: rest.count - 1, to: 0, by: -1) {
            rest.swapAt(i, Int(rng.next() % UInt64(i + 1)))
        }
        return [0] + rest.prefix(length - 1)
    }

    /// 척추에 없는 방을 최소 비용으로 붙인다(Prim). 씨앗은 척추 전체다.
    private static func connectAll(_ edges: inout Set<DungeonEdge>,
                                   coords: [(x: Int, y: Int)], seeded: Set<Int>) {
        var inTree = seeded
        while inTree.count < roomCount {
            var best: (from: Int, to: Int, cost: Int)?
            for outside in (0..<roomCount).filter({ !inTree.contains($0) }) {
                for inside in inTree.sorted() {
                    let cost = corridorCost(coords, inside, outside)
                    // 동점은 방 번호가 작은 쪽 — 순회 순서에 기대면 같은 seed 가 다른 맵을 낸다.
                    if best == nil || cost < best!.cost
                        || (cost == best!.cost && (outside, inside) < (best!.to, best!.from)) {
                        best = (inside, outside, cost)
                    }
                }
            }
            guard let pick = best else { break }
            edges.insert(DungeonEdge(pick.from, pick.to, cost: pick.cost))
            inTree.insert(pick.to)
        }
    }

    /// 버린 간선의 10~20% 를 되살린다. 트리만 두면 순환이 없어 모든 가지가 막다른 길이고
    /// 되돌아오기밖에 할 게 없다 — 순환이 있어야 경로 선택이 판단이 된다.
    private static func addExtraEdges(_ edges: inout Set<DungeonEdge>,
                                      coords: [(x: Int, y: Int)], _ rng: inout SplitMix64) {
        var discarded: [DungeonEdge] = []
        for a in 0..<roomCount {
            for b in (a + 1)..<roomCount {
                let edge = DungeonEdge(a, b, cost: corridorCost(coords, a, b))
                if !edges.contains(where: { $0.a == edge.a && $0.b == edge.b }) { discarded.append(edge) }
            }
        }
        for i in stride(from: discarded.count - 1, to: 0, by: -1) {
            discarded.swapAt(i, Int(rng.next() % UInt64(i + 1)))
        }
        // 11~19% 를 뽑고 **가까운 정수로 반올림**한다. 10·20 을 뽑아 버림하면 실측 비율이 띠 밖으로
        // 나간다(78개 중 10% 는 7.8 → 버림 7 → 실측 8.97%). 띠 안에 남는 폭만 뽑는다.
        let percent = 11 + Int(rng.next() % 9)                   // 11...19
        let count = max(1, (discarded.count * percent + 50) / 100)
        for edge in discarded.prefix(count) { edges.insert(edge) }
    }

    // MARK: 방 배치 — 클리어 가능성이 나오는 곳

    private static func placeRooms(spine: [Int], coords: [(x: Int, y: Int)],
                                   _ rng: inout SplitMix64) -> [DungeonRoom] {
        let boss = spine[spine.count - 1]
        let interior = Array(spine.dropFirst().dropLast())
        var kinds = [RoomKind](repeating: .empty, count: roomCount)
        kinds[boss] = .boss

        // 척추 내부는 교전과 빈 방만 둔다. **회복샘은 척추에 놓지 않는다** — 놓으면 회복량 20 이
        // 공짜로 얹혀 척추 여유가 15 가 아니라 35 가 되고(실측), 순서를 고민할 이유가 사라진다.
        // 샘을 척추 밖에만 두면 "샘까지 돌아갈 값이 있나" 가 판단거리로 남는다.
        var encounters: [Int] = []
        for (offset, room) in interior.enumerated() where offset % 2 == 0 {
            kinds[room] = .encounter
            encounters.append(room)
        }

        // 척추만 따라갔을 때 남는 예산. 회복샘 회복량은 **여기에 더하지 않는다** — 세지 않으면
        // 여유가 늘 뿐이고, 예산 상한(clamp)에 걸려 회복이 버려지는 경우까지 안전하다.
        let spineCost = (0..<(spine.count - 1))
            .reduce(0) { $0 + corridorCost(coords, spine[$1], spine[$1 + 1]) }
        let allowance = baseBudget - clearSlack - spineCost - bossDamage
        // 데미지 1 도 못 주는 교전은 교전이 아니다 — 예산이 모자라면 빈 방으로 되돌린다.
        while allowance < encounters.count, let demoted = encounters.popLast() {
            kinds[demoted] = .empty
        }

        var damages = [Int](repeating: 0, count: roomCount)
        damages[boss] = bossDamage
        if !encounters.isEmpty {
            // 나머지를 버리지 않고 앞쪽 교전에 1씩 얹는다. 버리면 척추 여유가 15 가 아니라 30 을
            // 넘어(실측 35) 순서를 고민할 이유가 사라진다 — 예산을 남기지 않고 다 쓴다.
            let each = max(1, allowance / encounters.count)
            var remainder = max(0, allowance - each * encounters.count)
            for room in encounters {
                damages[room] = each + (remainder > 0 ? 1 : 0)
                remainder -= 1
            }
        }

        // 척추 밖은 자유롭게 채운다 — 클리어 가능성이 척추에서 나오므로 여기 값은 난이도 장식이다.
        let offSpine = (0..<roomCount).filter { !spine.contains($0) }
        // 회복샘 **하나는 보장한다.** 확률에만 맡기면 365일 중 87일이 샘 없는 맵이었다(실측) —
        // 방 종류 넷 중 하나가 그날 아예 존재하지 않으면 그만큼 판단거리가 사라진다.
        if let guaranteed = offSpine.isEmpty ? nil : offSpine[Int(rng.next() % UInt64(offSpine.count))] {
            kinds[guaranteed] = .spring
            damages[guaranteed] = springHeal
        }
        for room in offSpine where kinds[room] == .empty {
            switch rng.next() % 5 {
            case 0, 1: break                                   // 빈 방
            case 2, 3:
                kinds[room] = .encounter
                damages[room] = 8 + Int(rng.next() % 18)        // 8...25
            default:
                kinds[room] = .spring
                damages[room] = springHeal
            }
        }
        return (0..<roomCount).map { DungeonRoom(id: $0, kind: kinds[$0], damage: damages[$0]) }
    }
}

/// 던전 진행 — 세이브에 남는 건 이것 하나다. **시도 중 상태(현재 방·남은 체력)는 넣지 않는다**:
/// 저장 대상을 늘리면 이상 상태 복구 경로가 그만큼 늘어난다.
struct DungeonProgress: Codable, Sendable, Equatable {
    var dayKey = ""
    var cleared = false
    /// 정산했나 — 재지급을 막는 유일한 가드다(그래서 무결성 서명에 들어간다).
    var rewardPaid = false
    /// 시도 사이 남는 맵 기억. 실패해도 밟은 방의 정체는 남는다.
    var remembered: [Int: RoomKind] = [:]

    /// 날짜 키 비교 리셋 — 자정 타이머가 아니다. 날짜가 바뀐 첫 기록에서 전부 비운다.
    /// 셋 중 하나만 남기면 어제 정산 플래그가 오늘 보상을 막는다.
    mutating func roll(dayKey: String) {
        guard self.dayKey != dayKey else { return }
        self.dayKey = dayKey
        cleared = false
        rewardPaid = false
        remembered = [:]
    }

    /// 신뢰경계 정규화 — 맵에 없는 방 번호를 버리고, 정산됐으면 클리어를 참으로 맞춘다.
    mutating func normalize() {
        remembered = remembered.filter { (0..<PuzzleDungeon.roomCount).contains($0.key) }
        if rewardPaid { cleared = true }
    }

    /// 무결성 해시 입력 — **키로 정렬**해야 한다(정렬 안 하면 정상 세이브가 무작위로 조작 판정된다).
    var canonical: String {
        let memory = remembered.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value.rawValue)" }.joined(separator: ",")
        return "d\(dayKey)|c\(cleared)|p\(rewardPaid)|\(memory)"
    }
}
