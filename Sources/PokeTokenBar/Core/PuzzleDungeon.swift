import Foundation

/// 방 하나의 정체. 들어가기 전까지 숨긴다(안개) — 처음부터 다 보이면 앉은 자리에서 답이 나와
/// 퍼즐이 성립하지 않는다.
enum RoomKind: String, Codable, Sendable, CaseIterable {
    case empty, encounter, spring, boss
    /// 보물 — 별의조각. 곁방에만 놓이고 하루 한 번만 준다.
    case cache
}

struct DungeonRoom: Sendable, Equatable {
    let id: Int
    /// 교전·보스는 고정 데미지, 회복샘은 회복량, 보물은 별의조각, 빈 방은 0.
    let kind: RoomKind
    let damage: Int
}

/// 격자 위 방 위치. **화면에 지도를 그리기 위한 값이 아니다** — 출구 방위(`DungeonNarration`)를
/// 만드는 데 쓴다. `x` 가 곧 층이라 오른쪽(→)이 전진, 위아래(↑↓)가 곁방이다.
/// `y` 는 아래로 증가한다(북쪽이 `y` 가 작은 쪽).
struct DungeonCoord: Hashable, Sendable {
    let x: Int, y: Int
}

/// 방 사이 통로. `cost` 는 지나갈 때 깎이는 체력(1~3).
/// `a < b` 로 정규화해 같은 통로가 두 번 들어가지 않게 한다. **방향은 여기 없다** — 본선 통로를
/// 왼쪽으로 못 가는 규칙은 `DungeonMap.exits(from:)` 가 층 번호로 건다.
struct DungeonEdge: Hashable, Sendable {
    let a: Int, b: Int, cost: Int

    init(_ x: Int, _ y: Int, cost: Int) {
        self.a = min(x, y); self.b = max(x, y); self.cost = cost
    }

    func other(than room: Int) -> Int? { room == a ? b : (room == b ? a : nil) }
}

/// 하루치 맵 — 왼쪽에서 오른쪽으로만 가는 층 그래프(`layered-dungeon-design.md`).
///
/// 판 길이는 **구조에서 나온다.** 본선 통로는 다음 층으로만 이어지고 곁방은 본선 방에 매달린
/// 막다른 방이라, 보스로 가는 지름길이 존재할 수 없고 최단 클릭 수 = 층 수 − 1 로 고정된다.
/// (이전 구조는 여분 간선이 척추를 통째로 우회해 365일 평균 2.1 클릭에 끝났다.)
struct DungeonMap: Sendable {
    let dayKey: String
    let rooms: [DungeonRoom]
    /// 방 번호 순 격자 좌표. `x` 가 층이다.
    let coords: [DungeonCoord]
    let edges: [DungeonEdge]
    /// 층별 본선 방 번호. `layers[0]` 은 시작 방 하나, 마지막 층은 보스 하나.
    let layers: [[Int]]
    /// 방 번호 → 층. 곁방은 매달린 본선 방과 같은 층이다.
    let layerOf: [Int]
    /// 곁방 번호 → 매달린 본선 방 번호.
    let spurParent: [Int: Int]
    /// **가장 비싼 전진 경로.** 클리어 가능성의 근거라 생성 결과로 남긴다 — 이 경로로도 기본
    /// 예산 100 으로 `clearSlack` 을 남기고 보스에 닿는다. 화면에는 쓰지 않는다.
    let spine: [Int]
    /// 오늘의 상성 축 — 동행 파트너가 이 타입에 강하면 예산 +5.
    let affinity: PokemonType

    var bossRoom: Int { layers[layers.count - 1][0] }
    var layerCount: Int { layers.count }

    func room(_ id: Int) -> DungeonRoom { rooms[id] }
    func isSpur(_ id: Int) -> Bool { spurParent[id] != nil }

    /// 갈 수 있는 출구만. 본선은 **다음 층으로만**, 곁방은 들어간 길로 되나오기만 한다.
    /// 통로 하나가 양방향으로 쓰이는 곳은 곁방 통로뿐이다.
    func exits(from room: Int) -> [(room: Int, cost: Int)] {
        edges.compactMap { edge -> (room: Int, cost: Int)? in
            guard let other = edge.other(than: room) else { return nil }
            let passable = layerOf[other] > layerOf[room]      // 본선 전진
                || spurParent[other] == room                    // 곁방으로
                || spurParent[room] == other                    // 곁방에서 되나오기
            return passable ? (room: other, cost: edge.cost) : nil
        }
        .sorted { $0.room < $1.room }
    }

    func cost(from: Int, to: Int) -> Int? {
        exits(from: from).first { $0.room == to }?.cost
    }
}

/// 날짜 키에서 하루치 맵을 만든다 — 무작위가 전혀 없어 같은 날이면 모두 같은 맵을 푼다.
///
/// 클리어 가능성은 **가장 비싼 전진 경로 기준**으로 배분한다. 가장 싼 경로 기준으로 잡으면 비싼
/// 경로를 고른 날 클리어 불가가 나온다. 본선 교전은 층 단위라 어느 경로로 가도 그 층의 교전을
/// 정확히 한 번 만난다 — 일부 방에만 두면 교전 없는 쪽으로 새어 예산 압박이 사라진다
/// (실측: 남는 체력이 5 목표인데 25).
enum PuzzleDungeon {
    static let layerCount = 12
    /// 방 수 상한 — 본선 최대 22 + 곁방 최대 20 = 42 인데 실측 상한이 32 라 40 에서 자른다.
    /// 방 이름 풀(`DungeonNarration.roomNameSlots`)이 이 값 이상이어야 한다.
    static let maxRoomCount = 40
    static let baseBudget = 100
    /// 보스 한 줄의 데미지. 다른 방들과 급이 달라야 "가장 깊은 방"이 무게를 갖는다.
    static let bossDamage = 30
    static let springHeal = 20
    /// 가장 비싼 전진 경로로 본선만 따라갔을 때 남는 체력. 남는 체력이 곧 곁방을 열 밑천이다.
    static let clearSlack = 5
    static let firstClearReward = 1_000
    /// 곁방 보물의 별의조각 범위.
    static let cacheRewardRange = 60...150
    /// 먹는샘물 상점가. 진화 아이템(500)보다 싸다 — 보정이 +3 뿐이라 값이 붙으면 아무도 안 산다.
    static let freshWaterPrice = 200

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

        // 본선 — 층마다 1~2방. 첫 층(시작)과 마지막 층(보스)은 하나.
        var layers: [[Int]] = []
        var layerOf: [Int] = []
        var coords: [DungeonCoord] = []
        for layer in 0..<layerCount {
            let width = (layer == 0 || layer == layerCount - 1) ? 1 : 1 + Int(rng.next() % 2)
            var ids: [Int] = []
            for slot in 0..<width {
                ids.append(layerOf.count)
                layerOf.append(layer)
                coords.append(DungeonCoord(x: layer, y: 1 + slot))
            }
            layers.append(ids)
        }

        // 전진 통로 — 다음 층의 방 1~2개로. 다음 층에서 아무 통로도 못 받은 방은 하나 이어 준다
        // (모든 방이 시작 방에서 도달 가능해야 한다).
        var edges = Set<DungeonEdge>()
        for layer in 0..<(layerCount - 1) {
            let here = layers[layer], there = layers[layer + 1]
            var covered = Set<Int>()
            for room in here {
                let fan = 1 + Int(rng.next() % UInt64(min(2, there.count)))
                var pool = there
                for i in stride(from: pool.count - 1, to: 0, by: -1) {
                    pool.swapAt(i, Int(rng.next() % UInt64(i + 1)))
                }
                for target in pool.prefix(fan) {
                    edges.insert(DungeonEdge(room, target, cost: 1 + Int(rng.next() % 3)))
                    covered.insert(target)
                }
            }
            for orphan in there where !covered.contains(orphan) {
                let from = here[Int(rng.next() % UInt64(here.count))]
                edges.insert(DungeonEdge(from, orphan, cost: 1 + Int(rng.next() % 3)))
            }
        }

        // 곁방 — 사이 층의 본선 방마다 1/2 확률. 위쪽 방(y=1)은 북쪽, 아래쪽 방(y=2)은 남쪽에 매단다.
        var spurParent: [Int: Int] = [:]
        for layer in 1..<(layerCount - 1) {
            for room in layers[layer] where rng.next() % 2 == 0 && layerOf.count < maxRoomCount {
                let spur = layerOf.count
                spurParent[spur] = room
                layerOf.append(layer)
                coords.append(DungeonCoord(x: layer, y: coords[room].y == 1 ? 0 : 3))
                edges.insert(DungeonEdge(room, spur, cost: 1 + Int(rng.next() % 2)))
            }
        }

        let sortedEdges = edges.sorted { ($0.a, $0.b) < ($1.a, $1.b) }
        let rooms = placeRooms(layers: layers, layerOf: layerOf, spurParent: spurParent,
                               edges: sortedEdges, &rng)
        let affinity = PokemonType.allCases[Int(rng.next() % UInt64(PokemonType.allCases.count))]
        let skeleton = DungeonMap(dayKey: dayKey, rooms: rooms, coords: coords, edges: sortedEdges,
                                  layers: layers, layerOf: layerOf, spurParent: spurParent,
                                  spine: [], affinity: affinity)
        return DungeonMap(dayKey: dayKey, rooms: rooms, coords: coords, edges: sortedEdges,
                          layers: layers, layerOf: layerOf, spurParent: spurParent,
                          spine: dearestPath(skeleton), affinity: affinity)
    }

    // MARK: 가장 비싼 전진 경로

    /// 시작 방에서 각 본선 방까지 **통로 비용이 가장 큰** 경로의 합. 본선은 층 순서가 곧 위상 순서라
    /// 층 순으로 한 번 훑으면 끝난다. 곁방은 세지 않는다(전진 경로가 아니다).
    static func dearestCorridorSums(_ map: DungeonMap) -> [Int: Int] {
        var dear = [0: 0]
        for layer in map.layers {
            for room in layer {
                guard let here = dear[room] else { continue }
                for exit in map.exits(from: room) where !map.isSpur(exit.room) {
                    if (dear[exit.room] ?? .min) < here + exit.cost { dear[exit.room] = here + exit.cost }
                }
            }
        }
        return dear
    }

    /// 가장 비싼 전진 경로를 방 번호 열로. 보스에서 거꾸로 "합이 정확히 맞는 앞 방"을 고른다.
    private static func dearestPath(_ map: DungeonMap) -> [Int] {
        let dear = dearestCorridorSums(map)
        var path = [map.bossRoom]
        while let current = path.last, current != 0 {
            let target = dear[current] ?? 0
            let previous = map.layers[map.layerOf[current] - 1].first { candidate in
                guard let sum = dear[candidate], let cost = map.cost(from: candidate, to: current) else { return false }
                return sum + cost == target
            }
            guard let previous else { break }
            path.append(previous)
        }
        return path.reversed()
    }

    // MARK: 방 배치 — 클리어 가능성이 나오는 곳

    /// 여유 예산을 교전 층에 나눈다 — **테스트가 직접 부를 수 있게 따로 뺐다.**
    ///
    /// - 나머지는 버리지 않고 앞쪽 층에 1씩 얹는다. 버리면 남는 체력이 설계값(5)보다 커지고
    ///   곁방 판단이 느슨해진다.
    /// - 반환 길이가 `count` 보다 짧으면 남는 층은 빈 방으로 둬야 한다는 뜻이다.
    static func splitAllowance(_ allowance: Int, among count: Int) -> [Int] {
        guard count > 0, allowance > 0 else { return [] }
        // 한 층에 1 도 못 주면 교전 층 수를 예산까지 줄인다(각 1 데미지).
        guard allowance >= count else { return [Int](repeating: 1, count: allowance) }
        let each = allowance / count
        let remainder = allowance - each * count
        return (0..<count).map { each + ($0 < remainder ? 1 : 0) }
    }

    /// 교전을 두는 층 — 사이 층의 절반(홀수 층). 나머지는 빈 방이라 숨 돌릴 구간이 남는다.
    static var encounterLayers: [Int] { (1..<(layerCount - 1)).filter { $0 % 2 == 1 } }

    private static func placeRooms(layers: [[Int]], layerOf: [Int], spurParent: [Int: Int],
                                   edges: [DungeonEdge], _ rng: inout SplitMix64) -> [DungeonRoom] {
        let count = layerOf.count
        var kinds = [RoomKind](repeating: .empty, count: count)
        var values = [Int](repeating: 0, count: count)
        let boss = layers[layerCount - 1][0]
        kinds[boss] = .boss
        values[boss] = bossDamage

        // 곁방 내용 — 샘 25% / 보물 30% / 빈 방 20% / 교전 25%. 체력 기준 기대값은 음수, 별의조각
        // 기준은 양수라 "체력을 팔아 별의조각을 산다"가 매 층의 판단이 된다. 꽝(빈 방·교전)이 있어야
        // 첫 판의 손해가 다음 판에 그 층을 지나칠 근거가 된다.
        // **회복샘은 본선에 두지 않는다** — 지나가다 공짜로 마시면 판단이 없다.
        for spur in spurParent.keys.sorted() {
            switch rng.next() % 20 {
            case 0..<5:
                kinds[spur] = .spring; values[spur] = springHeal
            case 5..<11:
                kinds[spur] = .cache
                values[spur] = cacheRewardRange.lowerBound
                    + Int(rng.next() % UInt64(cacheRewardRange.count))
            case 11..<15:
                break                                          // 빈 방
            default:
                kinds[spur] = .encounter; values[spur] = 8 + Int(rng.next() % 18)   // 8...25
            }
        }

        // 본선 교전 — 가장 비싼 전진 통로 합 기준으로 남는 예산을 교전 층에 나눈다.
        let skeleton = DungeonMap(dayKey: "", rooms: [], coords: [], edges: edges, layers: layers,
                                  layerOf: layerOf, spurParent: spurParent, spine: [], affinity: .normal)
        let corridorWorst = dearestCorridorSums(skeleton)[boss] ?? 0
        let allowance = baseBudget - clearSlack - corridorWorst - bossDamage
        let split = splitAllowance(allowance, among: encounterLayers.count)
        for (offset, layer) in encounterLayers.enumerated() where offset < split.count {
            for room in layers[layer] {
                kinds[room] = .encounter
                values[room] = split[offset]
            }
        }
        return (0..<count).map { DungeonRoom(id: $0, kind: kinds[$0], damage: values[$0]) }
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
    /// 오늘 이미 턴 보물방. **보물은 하루 한 번만** — 재도전으로 같은 방을 다시 털 수 있으면
    /// 하루 상한이 무의미해진다. 별의조각이 나가는 가드라 서명에 들어간다.
    var looted: Set<Int> = []

    init() {}

    /// `looted` 는 나중에 추가된 필드다 — 키가 없는 옛 세이브를 기본값으로 읽어야지, 디코드 실패로
    /// 진행 전체를 버리면 업데이트 당일 클리어 기록이 사라진다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try c.decodeIfPresent(String.self, forKey: .dayKey) ?? ""
        cleared = try c.decodeIfPresent(Bool.self, forKey: .cleared) ?? false
        rewardPaid = try c.decodeIfPresent(Bool.self, forKey: .rewardPaid) ?? false
        remembered = try c.decodeIfPresent([Int: RoomKind].self, forKey: .remembered) ?? [:]
        looted = try c.decodeIfPresent(Set<Int>.self, forKey: .looted) ?? []
    }

    /// 날짜 키 비교 리셋 — 자정 타이머가 아니다. 날짜가 바뀐 첫 기록에서 전부 비운다.
    /// 하나만 남기면 어제 정산 플래그가 오늘 보상을 막는다.
    mutating func roll(dayKey: String) {
        guard self.dayKey != dayKey else { return }
        self.dayKey = dayKey
        cleared = false
        rewardPaid = false
        remembered = [:]
        looted = []
    }

    /// 신뢰경계 정규화 — **그날 맵**에 없는 방 번호를 버리고, 정산됐으면 클리어를 참으로 맞춘다.
    /// 방 수가 날마다 다르므로 고정 상한으로 검사하지 않는다.
    mutating func normalize() {
        let valid = 0..<PuzzleDungeon.map(dayKey: dayKey).rooms.count
        remembered = remembered.filter { valid.contains($0.key) }
        looted = looted.filter { valid.contains($0) }
        if rewardPaid { cleared = true }
    }

    /// 무결성 해시 입력 — **키로 정렬**해야 한다(정렬 안 하면 정상 세이브가 무작위로 조작 판정된다).
    /// `looted` 는 비어 있으면 붙이지 않는다 — 이 필드가 없던 시절의 세이브가 같은 문자열을 내야 한다.
    var canonical: String {
        let memory = remembered.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value.rawValue)" }.joined(separator: ",")
        var text = "d\(dayKey)|c\(cleared)|p\(rewardPaid)|\(memory)"
        if !looted.isEmpty { text += "|l" + looted.sorted().map(String.init).joined(separator: ",") }
        return text
    }
}
