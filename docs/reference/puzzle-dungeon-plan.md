---
summary: "퍼즐 던전(#79) 구현 계획 — 태스크 6개, 각 단계에 실제 코드와 커밋 메시지까지."
read_when:
  - 퍼즐 던전(#79) 구현에 착수할 때(설계는 puzzle-dungeon-design.md)
  - 계획을 이어받아 남은 태스크를 진행할 때
---

# 하루 한 판 결정론 퍼즐 던전 (#79) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 날짜 키에서 결정론으로 생성되는 14방 던전을 하루 한 판 열고, 체력 예산 안에서 방문 순서를 푸는 퍼즐로 만든다(첫 클리어에만 별의조각 1,000).

**Architecture:** 순수 파일 두 개 + 화면 하나. `PuzzleDungeon` 이 날짜 키를 seed 로 맵을 만들고(좌표 → MST → 여분 간선 → 척추 경로에 구성적 배치), `DungeonRun` 이 `move(to:)` 단일 입구에서 이동·판정·클램프를 전부 처리한다. `CompanionStore` 는 `DungeonProgress` 하나만 들고 날짜 키 비교로 리셋한다. 시도 중 상태(현재 방·HP)는 저장하지 않는다.

**Tech Stack:** Swift 6 / SwiftUI(macOS, menu-bar 앱), XCTest, `swift build`·`scripts/test-gate.sh`

**Spec:** `docs/reference/puzzle-dungeon-design.md` (확정 설계 — 이 계획은 그 문서를 근거로 쓴다)

## Global Constraints

- 방 14개 고정 · 기본 체력 예산 100 · 보정 합계 상한 +10(타입 상성 +5 / 소모 아이템 +3 / 트레이너 레벨 +0~2) — 보정은 더하기만, 깎지 않는다.
- 첫 클리어 보상 별의조각 1,000 고정, 하루 1회. 이후 재플레이는 무보상.
- 보스는 가장 깊은 방의 결정론 데미지 한 줄 — 별도 배틀 화면·교전 상태를 만들지 않는다.
- 리셋은 자정 타이머가 아니라 **날짜 키 비교**(`MissionBoard` 와 같은 방식).
- 무결성 canonical 에 `remembered` 를 넣을 때 **키로 정렬**한다. 정렬 안 하면 정상 세이브가 무작위로 조작 판정된다.
- `DungeonProgress` 는 이번에 처음 나가는 필드라 canonical **조건부 append** 로 넣는다(기본값이면 아무것도 붙이지 않음) — `SaveTransfer.integrityVersion`(현재 7)은 올리지 않는다.
- 두 순수 파일(`PuzzleDungeon.swift`·`DungeonRun.swift`)을 `scripts/test-gate.sh` 의 `LOGIC_CORE` 배열에 넣는다.
- 문구는 `Localization.swift` 에 ko/en/ja 세 언어 전부.
- 커밋 메시지·PR 은 **영어**(저장소 규약). 커밋 트레일러에 `Claude-Session:` 을 넣지 않는다.
- **이 머신엔 Xcode 가 없다.** `swift test` 는 `no such module XCTest` 로 실패한다. 검증은 `swift build`(경고 0)까지만 하고, 테스트는 작성하되 "로컬에서 실행하지 못했다"를 항상 명시한다. 통과했다고 쓰지 않는다. 게이트는 PR CI(macos-15)가 돌린다.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `Sources/PokeTokenBar/Core/PuzzleDungeon.swift` (신규) | 날짜 키 → 맵 생성(순수). 방 종류·간선·척추 경로·체력 예산 계산 |
| `Sources/PokeTokenBar/Core/DungeonRun.swift` (신규) | 시도 진행 상태기계(순수). `move(to:)` 단일 입구 |
| `Sources/PokeTokenBar/Core/CompanionModel.swift` (수정) | `DungeonProgress` 저장 필드 추가 |
| `Sources/PokeTokenBar/Core/CompanionStore.swift` (수정) | 오늘 맵·예산 노출, 기억 저장, `settleDungeonClear()` |
| `Sources/PokeTokenBar/Core/SaveTransfer.swift` (수정) | canonical 에 조건부 `dun` 세그먼트 |
| `Sources/PokeTokenBar/Core/Localization.swift` (수정) | 던전 문구 ko/en/ja |
| `Sources/PokeTokenBar/UI/DungeonView.swift` (신규) | 화면(텍스트 로그 전용, 지도 없음) |
| `Sources/PokeTokenBar/UI/PopoverView.swift` (수정) | `nav.showDungeon` 오버레이 분기 |
| `Sources/PokeTokenBar/UI/BattleView.swift` (수정) | 배틀 탭 진입 버튼 |
| `scripts/test-gate.sh` (수정) | `LOGIC_CORE` 에 순수 파일 두 개 |
| `Tests/PokeTokenBarTests/PuzzleDungeonTests.swift` (신규) | 결정론·연결성·여분 간선 비율·365일 클리어 가능성·예산 보정 |
| `Tests/PokeTokenBarTests/DungeonRunTests.swift` (신규) | 안개·인접 검증·HP 0 실패·보스 클리어·샘 1회 |
| `Tests/PokeTokenBarTests/DungeonProgressTests.swift` (신규) | 보상 1회·날짜 리셋·normalize·canonical 정렬 |

---

### Task 1: 맵 생성 (`PuzzleDungeon`)

**Files:**
- Create: `Sources/PokeTokenBar/Core/PuzzleDungeon.swift`
- Test: `Tests/PokeTokenBarTests/PuzzleDungeonTests.swift`

**Interfaces:**
- Consumes: `SplitMix64`(`Core/BattleModel.swift:560`), `PokemonType`·`TypeChart.effectiveness(_:against:)`(같은 파일)
- Produces:
  - `enum RoomKind: String, Codable, Sendable { case empty, encounter, spring, boss }`
  - `struct DungeonRoom: Sendable, Equatable { let id: Int; let kind: RoomKind; let damage: Int }` (`damage` 는 교전·보스의 고정 데미지, 회복샘은 회복량, 빈 방은 0)
  - `struct DungeonEdge: Hashable, Sendable { let a: Int; let b: Int; let cost: Int }` (`a < b` 정규화)
  - `struct DungeonMap: Sendable { let dayKey: String; let rooms: [DungeonRoom]; let edges: [DungeonEdge]; let spine: [Int]; let affinity: PokemonType; var bossRoom: Int; var mstEdgeCount: Int; func room(_:) -> DungeonRoom; func exits(from:) -> [(room: Int, cost: Int)]; func cost(from:to:) -> Int? }`
  - `enum PuzzleDungeon { static let roomCount = 14; static let baseBudget = 100; static let bossDamage = 30; static let springHeal = 20; static let clearSlack = 15; static let firstClearReward = 1_000; static func seed(dayKey:) -> UInt64; static func map(dayKey:) -> DungeonMap; static func budget(partnerTypes:against:usedItem:trainerLevel:) -> Int }`

- [ ] **Step 1: 실패하는 테스트를 쓴다 — 결정론·연결성·척추 길이**

`Tests/PokeTokenBarTests/PuzzleDungeonTests.swift`:

```swift
import XCTest
@testable import PokeTokenBar

/// 하루 한 판 퍼즐 던전(#79)의 맵 생성. 이 콘텐츠는 하루에 맵이 하나뿐이라
/// **클리어 불가능한 맵 하나가 그날을 통째로 없앤다** — 365일 전수 검사가 이 파일의 핵심이다.
final class PuzzleDungeonTests: XCTestCase {

    /// 같은 날짜 키면 어느 기기에서나 같은 맵이어야 한다(1:1 레이스의 전제).
    func testSameDayKeyProducesIdenticalMap() {
        let a = PuzzleDungeon.map(dayKey: "2026-08-21")
        let b = PuzzleDungeon.map(dayKey: "2026-08-21")
        XCTAssertEqual(a.rooms, b.rooms)
        XCTAssertEqual(a.edges, b.edges)
        XCTAssertEqual(a.spine, b.spine)
        XCTAssertEqual(a.affinity, b.affinity)
    }

    func testDifferentDayKeysProduceDifferentMaps() {
        let a = PuzzleDungeon.map(dayKey: "2026-08-21")
        let b = PuzzleDungeon.map(dayKey: "2026-08-22")
        XCTAssertNotEqual(a.rooms, b.rooms, "하루가 지나도 같은 맵이면 어제 경로를 그대로 쓴다")
    }

    /// 모든 방이 시작 방에서 도달 가능해야 한다 — 고립된 방이 있으면 그 방의 내용은 존재하지 않는 것과 같다.
    func testEveryRoomIsReachableFromStart() {
        for offset in 0..<40 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            var seen: Set<Int> = [0], queue = [0]
            while let room = queue.popLast() {
                for exit in map.exits(from: room) where !seen.contains(exit.room) {
                    seen.insert(exit.room); queue.append(exit.room)
                }
            }
            XCTAssertEqual(seen.count, PuzzleDungeon.roomCount, "\(map.dayKey): 고립된 방")
        }
    }

    /// 척추 경로는 6~8방이고 보스가 그 끝이다 — 3방이면 판단할 게 없고 10방이면 5분을 넘긴다.
    func testSpineLengthAndBossPlacement() {
        for offset in 0..<40 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            XCTAssertTrue((6...8).contains(map.spine.count), "\(map.dayKey): 척추 \(map.spine.count)방")
            XCTAssertEqual(map.spine.first, 0)
            XCTAssertEqual(map.spine.last, map.bossRoom)
            XCTAssertEqual(map.room(map.bossRoom).kind, .boss)
            XCTAssertEqual(map.rooms.filter { $0.kind == .boss }.count, 1, "보스는 하나뿐")
        }
    }

    static func dayKey(_ offset: Int) -> String {
        let day = Date(timeIntervalSince1970: 1_767_225_600 + Double(offset) * 86_400)
        return CompanionStore.dayKey(day)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는 것을 확인한다**

Run: `swift build 2>&1 | tail -20`
Expected: 이 머신엔 Xcode 가 없어 `swift test` 는 `no such module XCTest` 로 실패한다. 대신 **테스트 파일이 참조하는 타입이 아직 없다**는 것을 컴파일로 확인한다 — `PuzzleDungeon` 미정의. 실행 결과를 보고할 때 "테스트를 실행하지 못했다"를 명시한다.

- [ ] **Step 3: 최소 구현 — 맵 생성**

`Sources/PokeTokenBar/Core/PuzzleDungeon.swift`:

```swift
import Foundation

/// 방 하나의 정체. 들어가기 전까지 숨긴다(안개) — 처음부터 다 보이면 앉은 자리에서 답이 나온다.
enum RoomKind: String, Codable, Sendable, CaseIterable {
    case empty, encounter, spring, boss
}

struct DungeonRoom: Sendable, Equatable {
    let id: Int
    let kind: RoomKind
    /// 교전·보스는 고정 데미지, 회복샘은 회복량, 빈 방은 0.
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
    /// 최소 신장 트리가 쓴 간선 수(= 방 수 - 1). 여분 간선 비율을 검사할 기준.
    let mstEdgeCount: Int

    var bossRoom: Int { spine[spine.count - 1] }

    func room(_ id: Int) -> DungeonRoom { rooms[id] }

    func exits(from room: Int) -> [(room: Int, cost: Int)] {
        edges.compactMap { edge in edge.other(than: room).map { ($0, edge.cost) } }
            .sorted { $0.0 < $1.0 }
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
        var h: UInt64 = 0xcbf29ce484222325
        for byte in dayKey.utf8 { h ^= UInt64(byte); h = h &* 0x100000001b3 }
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
        for i in 0..<(spine.count - 1) {
            edges.insert(DungeonEdge(spine[i], spine[i + 1], cost: corridorCost(coords, spine[i], spine[i + 1])))
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
        let percent = 10 + Int(rng.next() % 11)                  // 10...20
        let count = max(1, discarded.count * percent / 100)
        for edge in discarded.prefix(count) { edges.insert(edge) }
    }

    // MARK: 방 배치 — 클리어 가능성이 나오는 곳

    private static func placeRooms(spine: [Int], coords: [(x: Int, y: Int)],
                                   _ rng: inout SplitMix64) -> [DungeonRoom] {
        let boss = spine[spine.count - 1]
        let interior = Array(spine.dropFirst().dropLast())
        var kinds = [RoomKind](repeating: .empty, count: roomCount)
        kinds[boss] = .boss

        // 척추 내부: 가운데 하나를 회복샘, 짝수 번째를 교전으로 둔다.
        var encounters: [Int] = []
        for (offset, room) in interior.enumerated() {
            if offset == interior.count / 2 {
                kinds[room] = .spring
            } else if offset % 2 == 0 {
                kinds[room] = .encounter
                encounters.append(room)
            }
        }

        // 척추만 따라갔을 때 남는 예산. 회복샘 회복량은 **여기에 더하지 않는다** — 세지 않으면
        // 여유가 늘 뿐이고, 예산 상한(clamp)에 걸려 회복이 버려지는 경우까지 안전하다.
        let spineCost = (0..<(spine.count - 1))
            .reduce(0) { $0 + corridorCost(coords, spine[$1], spine[$1 + 1]) }
        var allowance = baseBudget - clearSlack - spineCost - bossDamage
        // 데미지 1 도 못 주는 교전은 교전이 아니다 — 예산이 모자라면 빈 방으로 되돌린다.
        while allowance < encounters.count, let demoted = encounters.popLast() {
            kinds[demoted] = .empty
        }

        var damages = [Int](repeating: 0, count: roomCount)
        damages[boss] = bossDamage
        if !encounters.isEmpty {
            let each = max(1, allowance / encounters.count)
            for room in encounters { damages[room] = each }
        }
        for room in interior where kinds[room] == .spring { damages[room] = springHeal }

        // 척추 밖은 자유롭게 채운다 — 클리어 가능성이 척추에서 나오므로 여기 값은 난이도 장식이다.
        for room in 0..<roomCount where kinds[room] == .empty && !spine.contains(room) {
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
```

- [ ] **Step 4: 빌드로 확인한다**

Run: `swift build 2>&1 | grep -E "warning|error" ; echo "exit=$?"`
Expected: 오류·경고 0. `swift test` 는 이 머신에서 돌지 않으므로 테스트 통과 여부는 보고하지 않는다.

- [ ] **Step 5: 365일 전수 클리어 가능성 테스트를 더한다 (핵심)**

`PuzzleDungeonTests.swift` 에 추가:

```swift
    /// **이 파일의 핵심.** 하루에 맵이 하나뿐이라 클리어 불가능한 맵 하나가 그날을 통째로 없앤다.
    /// 척추 경로만 따라가면 기본 예산 100 으로 `clearSlack` 이상 남기고 보스를 넘어야 한다.
    func test365DaysAreClearableOnTheBaseBudgetAlone() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            var hp = PuzzleDungeon.baseBudget
            var lowest = hp
            for step in 1..<map.spine.count {
                hp -= map.cost(from: map.spine[step - 1], to: map.spine[step]) ?? 99
                let room = map.room(map.spine[step])
                switch room.kind {
                case .encounter, .boss: hp -= room.damage
                case .spring: hp = min(PuzzleDungeon.baseBudget, hp + room.damage)
                case .empty: break
                }
                lowest = min(lowest, hp)
            }
            XCTAssertGreaterThan(lowest, 0, "\(map.dayKey): 척추 경로 도중에 쓰러진다")
            XCTAssertGreaterThanOrEqual(hp, PuzzleDungeon.clearSlack,
                                        "\(map.dayKey): 여유 \(hp) — 보정 상한(+10)보다 커야 퍼즐이 남는다")
        }
    }

    /// 되살린 간선이 버린 간선의 10~20% 안이어야 한다. 0% 면 전부 막다른 길, 과하면 지름길뿐이다.
    func testExtraEdgeRatioStaysInBand() {
        for offset in 0..<40 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            let allPairs = PuzzleDungeon.roomCount * (PuzzleDungeon.roomCount - 1) / 2
            let discarded = allPairs - map.mstEdgeCount
            let extra = map.edges.count - map.mstEdgeCount
            XCTAssertGreaterThanOrEqual(extra, discarded * 10 / 100, "\(map.dayKey): 여분 간선 \(extra)")
            XCTAssertLessThanOrEqual(extra, discarded * 20 / 100, "\(map.dayKey): 여분 간선 \(extra)")
            XCTAssertGreaterThan(map.edges.count, PuzzleDungeon.roomCount - 1, "순환이 없다")
        }
    }

    /// 예산 보정은 더하기만 하고 합계가 +10 을 넘지 않는다.
    func testBudgetBonusesNeverSubtractAndCapAtTen() {
        let affinity = PokemonType.water
        XCTAssertEqual(PuzzleDungeon.budget(partnerTypes: [.water], against: affinity,
                                            usedItem: false, trainerLevel: 1),
                       PuzzleDungeon.baseBudget, "불리한 조합도 기준선은 받는다")
        XCTAssertEqual(PuzzleDungeon.budget(partnerTypes: [.grass], against: affinity,
                                            usedItem: false, trainerLevel: 1),
                       PuzzleDungeon.baseBudget + 5, "상성 유리 +5")
        XCTAssertEqual(PuzzleDungeon.budget(partnerTypes: [.grass], against: affinity,
                                            usedItem: true, trainerLevel: 99),
                       PuzzleDungeon.baseBudget + 10, "합계 상한 +10")
        XCTAssertEqual(PuzzleDungeon.budget(partnerTypes: [], against: affinity,
                                            usedItem: false, trainerLevel: 50),
                       PuzzleDungeon.baseBudget + 2, "트레이너 레벨 상한 +2")
    }
```

- [ ] **Step 6: 빌드 + 회귀 여유 확인**

Run: `swift build 2>&1 | tail -5`
Expected: 오류 0. 테스트는 실행 불가(CI 가 돌린다)를 보고에 명시.

- [ ] **Step 7: 커밋**

```bash
git add Sources/PokeTokenBar/Core/PuzzleDungeon.swift Tests/PokeTokenBarTests/PuzzleDungeonTests.swift
git commit -m "$(cat <<'EOF'
feat: generate the daily puzzle dungeon map from the date key

Rooms, corridors and the start-to-boss spine come out of a SplitMix64 seed
hashed from the local day key, so everyone solves the same map. Clearability
is structural: the spine alone finishes on the base budget of 100 with at
least 15 points of slack, which is why no solver is needed.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 시도 진행 상태기계 (`DungeonRun`) + 게이트 등록

**Files:**
- Create: `Sources/PokeTokenBar/Core/DungeonRun.swift`
- Modify: `scripts/test-gate.sh` (`LOGIC_CORE` 배열)
- Test: `Tests/PokeTokenBarTests/DungeonRunTests.swift`

**Interfaces:**
- Consumes: Task 1 의 `DungeonMap`·`RoomKind`·`PuzzleDungeon.baseBudget`
- Produces:
  - `enum DungeonEvent: Sendable, Equatable { case entered(room: Int, kind: RoomKind), damaged(Int), healed(Int), springAlreadyUsed(Int), bossFelled, collapsed }`
  - `struct DungeonRun: Sendable { enum Stage { case exploring, cleared, failed }; init(map: DungeonMap, budget: Int, remembered: [Int: RoomKind]); var stage: Stage; var hp: Int; var budget: Int; var current: Int; var revealed: [Int: RoomKind]; var usedSprings: Set<Int>; var events: [DungeonEvent]; var exits: [(room: Int, cost: Int, known: RoomKind?)]; mutating func move(to room: Int) -> Bool }`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`Tests/PokeTokenBarTests/DungeonRunTests.swift`:

```swift
import XCTest
@testable import PokeTokenBar

/// 시도 진행 상태기계. 판정과 클램프는 `move(to:)` **한 곳**에만 있어야 한다 —
/// 입구가 여러 개면 한 곳만 고치고 끝난다(경험치 클램프 입구를 하나로 모은 #81 과 같은 이유).
final class DungeonRunTests: XCTestCase {
    private let map = PuzzleDungeon.map(dayKey: "2026-08-21")

    private func run(budget: Int = PuzzleDungeon.baseBudget,
                     remembered: [Int: RoomKind] = [:]) -> DungeonRun {
        DungeonRun(map: map, budget: budget, remembered: remembered)
    }

    /// 안개 — 들어가기 전에는 방 종류가 밝혀지지 않는다. 처음부터 보이면 퍼즐이 성립하지 않는다.
    func testUnvisitedRoomsStayHidden() {
        let session = run()
        XCTAssertEqual(session.revealed.count, 1, "밝혀진 건 시작 방뿐이어야 한다")
        XCTAssertEqual(session.revealed[0], map.room(0).kind)
        for exit in session.exits { XCTAssertNil(exit.known, "인접한 방의 정체가 미리 보인다") }
    }

    /// 기억한 방은 다시 들어가지 않아도 정체가 보인다(실패해도 맵 기억은 남는다).
    func testRememberedRoomsAreVisibleWithoutEntering() {
        let neighbor = map.exits(from: 0)[0].room
        let session = run(remembered: [neighbor: map.room(neighbor).kind])
        XCTAssertEqual(session.exits.first { $0.room == neighbor }?.known, map.room(neighbor).kind)
    }

    /// 인접하지 않은 방으로는 못 간다 — 상태도 변하지 않는다.
    func testMoveToNonAdjacentRoomIsRejected() {
        var session = run()
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
        var session = run(budget: 1)              // 통로 비용만으로 바닥난다
        let neighbor = map.exits(from: 0)[0].room
        XCTAssertTrue(session.move(to: neighbor))
        XCTAssertEqual(session.stage, .failed)
        XCTAssertEqual(session.hp, 0, "체력은 음수로 내려가지 않는다")
        XCTAssertTrue(session.events.contains(.collapsed))
    }

    /// 실패한 뒤에는 어떤 이동도 받지 않는다 — 죽은 시도가 계속 진행되면 로그가 거짓이 된다.
    func testFailedRunRejectsFurtherMoves() {
        var session = run(budget: 1)
        _ = session.move(to: map.exits(from: 0)[0].room)
        XCTAssertEqual(session.stage, .failed)
        XCTAssertFalse(session.move(to: map.exits(from: session.current)[0].room))
    }

    /// 보스 방에서 살아남으면 클리어다.
    func testSurvivingTheBossClears() {
        var session = run(budget: 10_000)
        for step in 1..<map.spine.count { XCTAssertTrue(session.move(to: map.spine[step])) }
        XCTAssertEqual(session.stage, .cleared)
        XCTAssertTrue(session.events.contains(.bossFelled))
    }

    /// 보스에게 못 버티면 실패다 — 보스 방 진입 자체가 클리어 조건이 아니다.
    func testDyingToTheBossFails() {
        var session = run(budget: PuzzleDungeon.bossDamage)
        // 보스 방 바로 앞까지 체력을 채워 둔 상태로 끌고 간다.
        for step in 1..<map.spine.count {
            session.debugSetHitPoints(PuzzleDungeon.bossDamage)
            _ = session.move(to: map.spine[step])
        }
        XCTAssertEqual(session.stage, .failed)
        XCTAssertFalse(session.events.contains(.bossFelled))
    }

    /// 회복의 샘은 한 번만 쓰인다 — 아니면 샘과 옆 방을 왕복하며 체력을 무한히 채운다.
    func testSpringHealsOnlyOnce() {
        guard let spring = map.rooms.first(where: { $0.kind == .spring }),
              let approach = map.exits(from: spring.id).first else {
            return XCTFail("이 날짜 맵에 회복샘이 없다 — 다른 날짜 키로 바꿔야 한다")
        }
        var session = run(budget: 10_000)
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
              let approach = map.exits(from: spring.id).first else { return }
        var session = run(budget: 60)
        session.debugTeleport(to: approach.room)
        session.debugSetHitPoints(60)
        _ = session.move(to: spring.id)
        XCTAssertLessThanOrEqual(session.hp, 60)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는 것을 확인한다**

Run: `swift build 2>&1 | tail -20`
Expected: `DungeonRun` 미정의. (테스트 실행은 이 머신에서 불가 — 보고에 명시.)

- [ ] **Step 3: 최소 구현**

`Sources/PokeTokenBar/Core/DungeonRun.swift`:

```swift
import Foundation

/// 시도 중 일어난 일. **문자열이 아니라 값**이다 — 문구는 화면이 `Localization` 으로 만든다.
/// 코어가 문자열을 만들면 언어를 바꿀 때 로그만 이전 언어로 남는다.
enum DungeonEvent: Sendable, Equatable {
    case entered(room: Int, kind: RoomKind)
    case damaged(Int)
    case healed(Int)
    case springAlreadyUsed(Int)
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
    private(set) var events: [DungeonEvent] = []
    private(set) var stage: Stage = .exploring

    init(map: DungeonMap, budget: Int, remembered: [Int: RoomKind] = [:]) {
        self.map = map
        self.budget = budget
        self.hp = budget
        // 손편집·구맵 잔재 방어: 오늘 맵에 없는 방 번호와 실제와 다른 정체는 버린다.
        self.revealed = remembered.filter { entry in
            (0..<PuzzleDungeon.roomCount).contains(entry.key) && map.room(entry.key).kind == entry.value
        }
        self.revealed[0] = map.room(0).kind
    }

    /// 출구 목록 — 정체는 밝혀진 방만 딸려 나간다(안개).
    var exits: [(room: Int, cost: Int, known: RoomKind?)] {
        map.exits(from: current).map { ($0.room, $0.cost, revealed[$0.room]) }
    }

    /// **이동 입구는 이것 하나다.** 인접 검증 → 통로 비용 차감 → 방 내용 적용 → 판정.
    /// 판정과 클램프가 여기 한 곳에만 있어야 한다.
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
            spend(entered.damage)
        case .spring:
            if usedSprings.contains(room) {
                events.append(.springAlreadyUsed(room))
            } else {
                usedSprings.insert(room)
                let healed = min(budget, hp + entered.damage) - hp
                hp += healed
                events.append(.healed(healed))
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
    mutating func debugTeleport(to room: Int) { current = room; revealed[room] = map.room(room).kind }
    mutating func debugSetHitPoints(_ value: Int) { hp = max(0, min(budget, value)) }
}
#endif
```

- [ ] **Step 4: 빌드로 확인한다**

Run: `swift build 2>&1 | grep -E "error|warning" || echo "clean"`
Expected: `clean`.

- [ ] **Step 5: 게이트에 순수 파일 두 개를 등록한다**

`scripts/test-gate.sh` 의 `LOGIC_CORE` 배열 마지막 항목 뒤에 추가:

```bash
  # 하루 한 판 퍼즐 던전(#79)의 순수 코어. 맵 생성과 이동 판정이 둘 다 여기 있고, 게이트 밖에
  # 두면 커버리지 집계에서 조용히 빠져 무테스트로 나갈 수 있다.
  "Sources/PokeTokenBar/Core/PuzzleDungeon.swift"
  "Sources/PokeTokenBar/Core/DungeonRun.swift"
```

- [ ] **Step 6: 커밋**

```bash
git add Sources/PokeTokenBar/Core/DungeonRun.swift Tests/PokeTokenBarTests/DungeonRunTests.swift scripts/test-gate.sh
git commit -m "$(cat <<'EOF'
feat: walk a dungeon attempt through a single move entry point

move(to:) is the only way state changes: it checks adjacency, spends the
corridor cost, applies the room, then decides failure or clear. Springs heal
once so a player cannot shuttle between two rooms for unlimited hit points.
Both pure files join LOGIC_CORE so the coverage gate actually sees them.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 저장 상태와 정산 (`DungeonProgress`)

**Files:**
- Modify: `Sources/PokeTokenBar/Core/CompanionModel.swift` (`CompanionState` 에 필드 하나)
- Modify: `Sources/PokeTokenBar/Core/CompanionStore.swift`
- Modify: `Sources/PokeTokenBar/Core/SaveTransfer.swift` (`canonicalString`)
- Test: `Tests/PokeTokenBarTests/DungeonProgressTests.swift`

**Interfaces:**
- Consumes: Task 1·2 의 `PuzzleDungeon`·`DungeonRun`·`RoomKind`
- Produces:
  - `struct DungeonProgress: Codable, Sendable, Equatable { var dayKey = ""; var cleared = false; var rewardPaid = false; var remembered: [Int: RoomKind] = [:]; mutating func roll(dayKey:); mutating func normalize(); var canonical: String }`
  - `CompanionState.dungeon: DungeonProgress`
  - `CompanionStore`: `var dungeonMap: DungeonMap`, `var dungeonBudget: Int`, `var dungeonCleared: Bool`, `func startDungeonRun() -> DungeonRun`, `func rememberDungeon(_ revealed: [Int: RoomKind])`, `@discardableResult func settleDungeonClear(revealed: [Int: RoomKind]) -> Int`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`Tests/PokeTokenBarTests/DungeonProgressTests.swift`:

```swift
import XCTest
@testable import PokeTokenBar

/// 던전 진행 저장. 리셋은 자정 타이머가 아니라 **날짜 키 비교**다(`MissionBoard` 와 같은 방식).
@MainActor
final class DungeonProgressTests: XCTestCase {

    /// 보상은 그날 첫 클리어만. 두 번째 클리어는 0 이고 연습으로 열려 있다.
    func testFirstClearPaysOnce() {
        let store = CompanionStore.makeForTesting()
        let first = store.settleDungeonClear(revealed: [0: .empty])
        XCTAssertEqual(first, PuzzleDungeon.firstClearReward)
        let second = store.settleDungeonClear(revealed: [0: .empty])
        XCTAssertEqual(second, 0, "재플레이는 보상 없는 연습이다")
        XCTAssertTrue(store.dungeonCleared)
    }

    /// 날짜 키가 바뀌면 기억·클리어·정산 플래그가 **모두** 리셋된다.
    /// 하나만 남으면 어제 정산 플래그가 오늘 보상을 막는다.
    func testDayRolloverResetsEverything() {
        var progress = DungeonProgress()
        progress.roll(dayKey: "2026-08-21")
        progress.cleared = true
        progress.rewardPaid = true
        progress.remembered = [3: .encounter]
        progress.roll(dayKey: "2026-08-22")
        XCTAssertFalse(progress.cleared)
        XCTAssertFalse(progress.rewardPaid)
        XCTAssertTrue(progress.remembered.isEmpty)
        XCTAssertEqual(progress.dayKey, "2026-08-22")
    }

    /// 같은 날짜 키로 다시 기록하면 아무것도 비우지 않는다 — 비우면 시도마다 기억이 사라진다.
    func testSameDayKeepsMemory() {
        var progress = DungeonProgress()
        progress.roll(dayKey: "2026-08-21")
        progress.remembered = [3: .encounter]
        progress.roll(dayKey: "2026-08-21")
        XCTAssertEqual(progress.remembered, [3: .encounter])
    }

    /// 손편집 방어 — 오늘 맵에 없는 방 번호는 버리고, 정산됐으면 클리어도 참으로 맞춘다.
    func testNormalizeDropsOutOfRangeRoomsAndRepairsClearedFlag() {
        var progress = DungeonProgress()
        progress.remembered = [0: .empty, 99: .boss, -1: .spring]
        progress.rewardPaid = true
        progress.cleared = false
        progress.normalize()
        XCTAssertEqual(Set(progress.remembered.keys), [0])
        XCTAssertTrue(progress.cleared, "정산됐는데 클리어가 거짓이면 화면이 보상을 다시 권한다")
    }

    /// 무결성 canonical 은 **키로 정렬**해야 한다. 사전 순회 순서에 기대면 같은 상태가 실행마다
    /// 다른 문자열을 내서 정상 세이브가 무작위로 조작 판정된다.
    func testCanonicalIsOrderIndependent() {
        var a = DungeonProgress(), b = DungeonProgress()
        a.remembered = [5: .encounter, 1: .empty, 9: .spring]
        b.remembered = [9: .spring, 1: .empty, 5: .encounter]
        XCTAssertEqual(a.canonical, b.canonical)
        XCTAssertTrue(a.canonical.contains("1:empty"), "정렬 결과가 문자열에 드러나야 한다")
    }

    /// 기본값이면 canonical 에 세그먼트가 붙지 않는다 — 붙이면 이 필드가 없던 시절의 정상 세이브가
    /// 전부 조작 판정된다(`integrityVersion` 을 올리지 않고 넣을 수 있는 유일한 방법).
    func testDefaultProgressDoesNotChangeCanonicalString() {
        var state = CompanionState()
        let before = SaveTransfer.canonicalString(state)
        state.dungeon = DungeonProgress()
        XCTAssertEqual(SaveTransfer.canonicalString(state), before)
        state.dungeon.rewardPaid = true
        XCTAssertNotEqual(SaveTransfer.canonicalString(state), before,
                          "정산 플래그가 서명 밖이면 한 줄 고쳐 매일 보상을 다시 받는다")
    }
}
```

> `CompanionStore.makeForTesting()` 이 없으면 기존 테스트가 쓰는 생성 방식을 그대로 따른다 —
> `Tests/PokeTokenBarTests/IdleTestSupport.swift` 를 먼저 읽고 같은 헬퍼를 쓴다.

- [ ] **Step 2: 테스트가 실패하는 것을 확인한다**

Run: `swift build 2>&1 | tail -20`
Expected: `DungeonProgress`·`settleDungeonClear` 미정의.

- [ ] **Step 3: `DungeonProgress` 를 만든다**

`Sources/PokeTokenBar/Core/PuzzleDungeon.swift` 맨 아래에 추가(생성과 같은 파일에 둔다 — 저장 형태가 방 종류에 붙어 있다):

```swift
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
```

- [ ] **Step 4: 세이브에 필드를 붙인다**

`Sources/PokeTokenBar/Core/CompanionModel.swift` — `CompanionState` 의 `var missions = MissionBoard()` 바로 아래:

```swift
    /// 하루 한 판 퍼즐 던전(#79). 리셋은 날짜 키 비교이고 시도 중 상태는 여기 없다.
    var dungeon = DungeonProgress()
```

`CompanionState` 가 손으로 쓴 `init(from:)` 을 갖고 있으므로(관용 디코딩) 같은 자리에 디코딩 한 줄을 더한다 — 파일에서 `missions` 디코딩 줄을 찾아 바로 아래에 같은 형태로 넣는다:

```swift
        dungeon = (try? c.decodeIfPresent(DungeonProgress.self, forKey: .dungeon)) ?? DungeonProgress()
```

`CodingKeys` 에도 `case dungeon` 을 더한다(키 목록이 명시돼 있으면).

- [ ] **Step 5: canonical 에 조건부로 넣는다**

`Sources/PokeTokenBar/Core/SaveTransfer.swift` 의 `canonicalString` — `missions` 줄 바로 아래:

```swift
        // 던전 첫 클리어 보상의 멱등 가드는 `rewardPaid` 하나뿐이다 — 서명 밖에 두면 한 줄 고쳐
        // 매일 1,000 을 다시 받는다. 이번에 처음 나가는 필드라 **조건부**로 붙인다
        // (기본값이면 세그먼트가 없어 구서명이 그대로 유효하다 → integrityVersion 상향 불필요).
        if s.dungeon != DungeonProgress() { p.append("dun\(s.dungeon.canonical)") }
```

- [ ] **Step 6: 스토어에 오늘 맵·정산을 붙인다**

`Sources/PokeTokenBar/Core/CompanionStore.swift` — `recordGymVictory` 근처(보상 정산이 모여 있는 자리)에:

```swift
    // MARK: 퍼즐 던전 (#79)

    /// 오늘의 맵. 날짜 키에서 나오므로 저장하지 않는다 — 매번 같은 값이 다시 계산된다.
    var dungeonMap: DungeonMap { PuzzleDungeon.map(dayKey: Self.dayKey(clock())) }

    /// 오늘 쓸 체력 예산. 기준선 100 에 보정만 더한다.
    var dungeonBudget: Int {
        PuzzleDungeon.budget(partnerTypes: currentTypes,
                             against: dungeonMap.affinity,
                             usedItem: state.dungeon.remembered.isEmpty ? false : false,
                             trainerLevel: state.trainer.level)
    }

    var dungeonCleared: Bool {
        var progress = state.dungeon
        progress.roll(dayKey: Self.dayKey(clock()))
        return progress.cleared
    }

    /// 새 시도 — 오늘 기억한 방을 들려 보낸다. 시도 중 상태는 저장되지 않는다.
    func startDungeonRun() -> DungeonRun {
        state.dungeon.roll(dayKey: Self.dayKey(clock()))
        return DungeonRun(map: dungeonMap, budget: dungeonBudget, remembered: state.dungeon.remembered)
    }

    /// 시도가 끝나거나 화면을 닫을 때 맵 기억만 남긴다(실패·이탈은 시도만 버린다).
    func rememberDungeon(_ revealed: [Int: RoomKind]) {
        state.dungeon.roll(dayKey: Self.dayKey(clock()))
        state.dungeon.remembered.merge(revealed) { _, new in new }
        state.dungeon.normalize()
        save()
    }

    /// 클리어 정산 — **여기 한 곳에서만** 보상이 나간다. 이미 정산했으면 0 을 돌려주고
    /// 그 뒤 재플레이는 보상 없는 연습으로 열려 있다.
    @discardableResult
    func settleDungeonClear(revealed: [Int: RoomKind]) -> Int {
        state.dungeon.roll(dayKey: Self.dayKey(clock()))
        state.dungeon.remembered.merge(revealed) { _, new in new }
        state.dungeon.cleared = true
        state.dungeon.normalize()
        guard !state.dungeon.rewardPaid else { save(); return 0 }
        state.dungeon.rewardPaid = true
        state.starPieces += PuzzleDungeon.firstClearReward
        save()
        notifyCompanionEvent(l.dungeonClearedTitle,
                             l.dungeonRewardBody(PuzzleDungeon.firstClearReward))
        return PuzzleDungeon.firstClearReward
    }
```

> `dungeonBudget` 의 소모 아이템 축(+3)은 Task 5 에서 화면이 실제 아이템을 쓸 때 붙인다.
> 지금은 `usedItem: false` 고정이고, Task 5 가 `state.dungeon` 밖의 1회성 플래그(뷰 상태)로 넘긴다 —
> 하루치 세이브에 새 플래그를 더하지 않기 위해 화면 진입 시점에 아이템을 소모하고 그 결과를
> `startDungeonRun(usedItem:)` 인자로 넘기도록 Task 5 에서 시그니처를 확장한다.

- [ ] **Step 7: 빌드로 확인한다**

Run: `swift build 2>&1 | grep -E "error|warning" || echo "clean"`
Expected: `clean`. (Task 4 의 문구를 아직 안 넣었다면 `l.dungeonClearedTitle` 미정의로 실패한다 —
그 경우 Task 4 를 먼저 하고 돌아온다.)

- [ ] **Step 8: 커밋**

```bash
git add Sources/PokeTokenBar/Core/PuzzleDungeon.swift Sources/PokeTokenBar/Core/CompanionModel.swift Sources/PokeTokenBar/Core/CompanionStore.swift Sources/PokeTokenBar/Core/SaveTransfer.swift Tests/PokeTokenBarTests/DungeonProgressTests.swift
git commit -m "$(cat <<'EOF'
feat: keep one day of dungeon progress in the save

DungeonProgress holds the day key, the clear and payout flags and the map
memory that survives a failed attempt. It resets by comparing day keys the
way the mission board does, and rewardPaid is the only guard against paying
the 1,000 Star Pieces twice, so it goes into the integrity signature with
the memory sorted by room number.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: 문구 (ko/en/ja)

**Files:**
- Modify: `Sources/PokeTokenBar/Core/Localization.swift`

**Interfaces:**
- Produces: `L` 의 던전 문구 — `dungeonTitle`, `dungeonRoomCounter(_:_:)`, `dungeonHitPoints(_:_:)`, `dungeonEnter`, `dungeonRetry`, `dungeonClose`, `dungeonAlreadyCleared`, `dungeonClearedTitle`, `dungeonRewardBody(_:)`, `dungeonFailed`, `dungeonExitUnknown`, `dungeonExitLabel(kind:)`, `dungeonEvent(_:)`, `dungeonBudgetBreakdown(_:_:)`

- [ ] **Step 1: 문구를 넣는다**

`Sources/PokeTokenBar/Core/Localization.swift` 의 `// MARK: 배틀 (네트워크 대전)` 섹션 뒤, 체육관 문구(`gymLeagueTitle`) 근처에 새 섹션으로:

```swift
    // MARK: 퍼즐 던전 (#79)
    var dungeonTitle: String { t("오늘의 던전", "Today's Dungeon", "きょうのダンジョン") }
    var dungeonEnter: String { t("들어가기", "Enter", "はいる") }
    var dungeonRetry: String { t("다시 도전", "Try again", "もういちど") }
    var dungeonLeave: String { t("나가기", "Leave", "でる") }
    var dungeonFailed: String { t("쓰러졌다… 맵은 기억에 남았다.", "You collapsed… the map stays remembered.", "たおれた… マップは記憶に残った。") }
    var dungeonClearedTitle: String { t("던전 클리어!", "Dungeon cleared!", "ダンジョンクリア！") }
    var dungeonAlreadyCleared: String {
        t("오늘 보상은 이미 받았어요 — 지금부터는 연습이에요.",
          "Today's reward is already paid — this is practice now.",
          "きょうの報酬は受け取りました — ここからは練習です。")
    }
    func dungeonRewardBody(_ amount: Int) -> String {
        t("별의조각 \(GameNumberFormatter.compact(amount))개를 받았어요.",
          "You received \(GameNumberFormatter.compact(amount)) Star Pieces.",
          "ほしのかけらを\(GameNumberFormatter.compact(amount))こ受け取りました。")
    }
    func dungeonRoomCounter(_ visited: Int, _ total: Int) -> String {
        t("방 \(visited)/\(total)", "Room \(visited)/\(total)", "へや \(visited)/\(total)")
    }
    func dungeonHitPoints(_ hp: Int, _ budget: Int) -> String { "\(hp)/\(budget)" }
    /// 오늘의 상성 축과 예산을 한 줄로 — 왜 내 예산이 105 인지 화면에서 읽혀야 한다.
    func dungeonBudgetLine(_ type: PokemonType, _ budget: Int) -> String {
        t("\(type.name(lang))에 강한 파트너면 유리 · 예산 \(budget)",
          "A partner strong against \(type.name(lang)) helps · budget \(budget)",
          "\(type.name(lang))に強いパートナーが有利 · 予算\(budget)")
    }
    var dungeonExitUnknown: String { t("미탐사", "Unexplored", "未探索") }
    func dungeonRoomName(_ kind: RoomKind) -> String {
        switch kind {
        case .empty: return t("빈 방", "Empty room", "空きへや")
        case .encounter: return t("교전", "Encounter", "せんとう")
        case .spring: return t("회복의 샘", "Healing spring", "かいふくのいずみ")
        case .boss: return t("가장 깊은 방", "Deepest room", "いちばん深いへや")
        }
    }
    func dungeonExitCost(_ cost: Int) -> String {
        t("통로 \(cost)", "corridor \(cost)", "通路 \(cost)")
    }
    var dungeonSpringSpent: String { t("(사용됨)", "(spent)", "（使用済み）") }
    /// 로그 한 줄 — 코어는 값(`DungeonEvent`)만 남기고 문구는 여기서 만든다.
    func dungeonEventLine(_ event: DungeonEvent) -> String {
        switch event {
        case .entered(_, let kind): return dungeonRoomName(kind)
        case .damaged(let amount): return t("−\(amount) 체력", "−\(amount) HP", "−\(amount) HP")
        case .healed(let amount): return t("+\(amount) 체력", "+\(amount) HP", "+\(amount) HP")
        case .springAlreadyUsed: return t("샘이 말랐다", "The spring is dry", "いずみは枯れている")
        case .bossFelled: return t("가장 깊은 방을 넘었다!", "You cleared the deepest room!", "いちばん深いへやを越えた！")
        case .collapsed: return t("쓰러졌다", "You collapsed", "たおれた")
        }
    }
```

- [ ] **Step 2: 빌드로 확인한다**

Run: `swift build 2>&1 | grep -E "error|warning" || echo "clean"`
Expected: `clean`. `PokemonType.name(_:)` 가 언어 인자를 받는 형태인지 먼저 확인하고(`GymRow` 가 `gym.type.name(store.language)` 로 쓴다) `lang` 을 그대로 넘긴다.

- [ ] **Step 3: 커밋**

```bash
git add Sources/PokeTokenBar/Core/Localization.swift
git commit -m "$(cat <<'EOF'
feat: word the puzzle dungeon in Korean, English and Japanese

The core emits DungeonEvent values instead of strings, so the log is worded
here; switching languages mid-run no longer leaves old lines behind.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: 화면과 진입 (`DungeonView`)

**Files:**
- Create: `Sources/PokeTokenBar/UI/DungeonView.swift`
- Modify: `Sources/PokeTokenBar/UI/PopoverView.swift:62,67,75,98` (`showDungeon` 플래그·오버레이 분기)
- Modify: `Sources/PokeTokenBar/UI/BattleView.swift:264` 근처(진입 버튼)
- Modify: `Sources/PokeTokenBar/Core/CompanionStore.swift` (`startDungeonRun(usedItem:)` 로 확장)
- Test: `Tests/PokeTokenBarTests/PopoverNavigationTests.swift` (기존 파일에 추가)

**Interfaces:**
- Consumes: Task 1~4 전부 — `DungeonRun`, `store.dungeonMap`, `store.dungeonBudget`, `store.startDungeonRun(usedItem:)`, `store.rememberDungeon(_:)`, `store.settleDungeonClear(revealed:)`, `l.dungeon*`
- Produces: `PopoverNavigation.showDungeon`, `struct DungeonView: View`

- [ ] **Step 1: 탐색 플래그 회귀 테스트를 쓴다**

`Tests/PokeTokenBarTests/PopoverNavigationTests.swift` 에 추가(기존 테스트 스타일을 그대로 따른다):

```swift
    /// 던전은 설정·체육관과 같은 층이다 — 배틀 신청이 오면 접혀야 하고, `reset()` 이 닫아야 한다.
    /// 접히지 않으면 신청이 온 줄 모른 채 던전만 보게 된다(체육관에서 겪은 그 함정).
    func testDungeonOverlayFoldsWithTheOthers() {
        let nav = PopoverNavigation()
        nav.showDungeon = true
        nav.goToBattle()
        XCTAssertFalse(nav.showDungeon)
        nav.showDungeon = true
        nav.reset()
        XCTAssertFalse(nav.showDungeon)
    }
```

- [ ] **Step 2: 테스트가 실패하는 것을 확인한다**

Run: `swift build 2>&1 | tail -10`
Expected: `showDungeon` 미정의.

- [ ] **Step 3: 탐색 플래그를 넣는다**

`Sources/PokeTokenBar/UI/PopoverView.swift` — `showGymLeague` 가 나오는 네 자리 모두에 같은 형태로 던전을 더한다:

```swift
    /// 던전 오버레이. 설정·체육관과 같은 층이라 한쪽을 열면 다른 쪽을 닫는다.
    var showDungeon = false
```

`reset()`·`goToBattle()` 에 `showDungeon = false` 를 더하고, `body` 의 분기에:

```swift
            } else if nav.showDungeon {
                DungeonView(store: companion, onClose: { nav.showDungeon = false })
```

- [ ] **Step 4: 화면을 만든다**

`Sources/PokeTokenBar/UI/DungeonView.swift`:

```swift
import SwiftUI

/// 하루 한 판 퍼즐 던전 화면. **타일 지도를 그리지 않는다** — 360pt 폭에 지도를 넣으면
/// 아무것도 읽히지 않는다. 헤더·서술·로그·출구 목록만으로 글로 그린다.
///
/// 시도 상태는 이 뷰가 들고 있다(세이브에 없다). 화면을 닫으면 시도는 버려지고
/// 맵 기억만 스토어로 넘어간다.
struct DungeonView: View {
    @Bindable var store: CompanionStore
    let onClose: () -> Void

    @State private var run: DungeonRun?

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let run {
                Text(l.dungeonBudgetLine(run.map.affinity, run.budget))
                    .font(.caption2).foregroundStyle(.secondary)
                logList(run)
                Spacer(minLength: 4)
                footer(run)
            } else {
                Spacer()
                Button(l.dungeonEnter) { start() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
        .onDisappear { if let run { store.rememberDungeon(run.revealed) } }
    }

    private var header: some View {
        HStack {
            Label(l.dungeonTitle, systemImage: "map.fill").font(.headline)
            Spacer()
            if let run {
                Text(l.dungeonRoomCounter(run.revealed.count, PuzzleDungeon.roomCount))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Text(l.dungeonHitPoints(run.hp, run.budget))
                    .font(.caption2.monospacedDigit())
            }
            Button(action: { close() }) { Image(systemName: "xmark") }
                .buttonStyle(.plain).help(l.dungeonLeave)
        }
    }

    private func logList(_ run: DungeonRun) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(run.events.enumerated()), id: \.offset) { entry in
                    Text(l.dungeonEventLine(entry.element))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func footer(_ run: DungeonRun) -> some View {
        switch run.stage {
        case .exploring:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(run.exits, id: \.room) { exit in
                    Button {
                        move(to: exit.room)
                    } label: {
                        HStack {
                            Text("› " + (exit.known.map(l.dungeonRoomName) ?? l.dungeonExitUnknown))
                            Spacer()
                            Text(l.dungeonExitCost(exit.cost))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .failed:
            Button(l.dungeonRetry) { start() }.buttonStyle(.borderedProminent)
        case .cleared:
            VStack(alignment: .leading, spacing: 4) {
                Text(l.dungeonClearedTitle).font(.caption.bold())
                if store.dungeonCleared { Text(l.dungeonAlreadyCleared).font(.caption2).foregroundStyle(.secondary) }
                Button(l.dungeonRetry) { start() }.controlSize(.small)
            }
        }
    }

    private func start() {
        if let run { store.rememberDungeon(run.revealed) }
        run = store.startDungeonRun()
    }

    private func move(to room: Int) {
        guard var session = run else { return }
        session.move(to: room)
        run = session
        // 정산은 클리어 순간 한 번만 부른다 — 스토어가 재지급을 막지만 알림이 겹치지 않게 한다.
        if session.stage == .cleared {
            store.settleDungeonClear(revealed: session.revealed)
        } else if session.stage == .failed {
            store.rememberDungeon(session.revealed)
        }
    }

    private func close() {
        if let run { store.rememberDungeon(run.revealed) }
        onClose()
    }
}
```

- [ ] **Step 5: 배틀 탭에 진입 버튼을 넣는다**

`Sources/PokeTokenBar/UI/BattleView.swift` — 체육관 버튼(`nav.showGymLeague = true`) 바로 뒤 같은 `HStack` 에:

```swift
                Button {
                    nav.showDungeon = true
                } label: {
                    Label(l.dungeonTitle, systemImage: "map.fill")
                }
                .controlSize(.small)
```

- [ ] **Step 6: 빌드로 확인한다**

Run: `swift build 2>&1 | grep -E "error|warning" || echo "clean"`
Expected: `clean`.

- [ ] **Step 7: 커밋**

```bash
git add Sources/PokeTokenBar/UI/DungeonView.swift Sources/PokeTokenBar/UI/PopoverView.swift Sources/PokeTokenBar/UI/BattleView.swift Tests/PokeTokenBarTests/PopoverNavigationTests.swift
git commit -m "$(cat <<'EOF'
feat: play the daily dungeon from the battle tab

The dungeon is an overlay next to settings and the gyms, drawn in text only:
a 360pt popover has no room for a tile map. Attempt state lives in the view,
so closing the popover throws the attempt away and keeps only the map memory.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: 게이트 확인과 마감

**Files:**
- Modify: `docs/reference/defect-log.md` (필요 시 새 부류만)
- Modify: `docs/reference/puzzle-dungeon-design.md` (설계와 구현이 갈린 지점만)

- [ ] **Step 1: 자체 코드 경고 0 을 cold build 로 확인한다**

Run: `swift package clean && swift build 2>&1 | grep -E "(Sources|Tests)/PokeTokenBar.*warning" || echo "no own warnings"`
Expected: `no own warnings`. warm build 는 경고를 다시 찍지 않으므로 clean 뒤에 본다.

- [ ] **Step 2: 게이트를 돌려 보고, 못 돌리면 그렇게 적는다**

Run: `./scripts/test-gate.sh 2>&1 | tail -20`
Expected: 이 머신에는 Xcode 가 없어 `swift test` 단계에서 `no such module XCTest` 로 멈춘다.
**이 결과를 그대로 보고한다** — 테스트·커버리지 게이트는 PR CI(macos-15)가 확인한다. 통과했다고 쓰지 않는다.

- [ ] **Step 3: 커버리지 블록 확인 방법을 PR 본문에 적는다**

CI 가 초록이 된 뒤, 새로 넣은 조건 분기(`placeRooms` 의 교전 강등 루프, `move(to:)` 의 샘 재방문 분기)가
`^0` 이 아닌지 확인해 달라고 PR 본문에 적는다:

```
xcrun llvm-cov show .build/debug/PokeTokenBarPackageTests.xctest/Contents/MacOS/PokeTokenBarPackageTests \
  -instr-profile .build/debug/codecov/default.profdata \
  Sources/PokeTokenBar/Core/PuzzleDungeon.swift --show-regions
```

커버리지 퍼센트는 증거가 아니다 — 줄 커버리지는 조건만 평가되면 실행으로 세므로 블록이 한 번도
돌지 않아도 통과한다.

- [ ] **Step 4: 설계 문서와 갈린 지점을 반영한다**

구현하며 설계와 달라진 것(예: 척추를 그래프 최단경로가 아니라 **먼저** 뽑는 순서, 여분 간선 비율의
기준 집합, 소모 아이템 축을 뷰에서 넘기는 방식)을 `docs/reference/puzzle-dungeon-design.md` 에
한두 줄로 반영한다. 설계 문서가 구현과 어긋나면 다음 사람이 설계를 믿고 틀린다.

- [ ] **Step 5: 커밋하고 push·PR 확인을 받는다**

```bash
git add docs/reference/puzzle-dungeon-design.md
git commit -m "$(cat <<'EOF'
docs: record where the dungeon implementation diverged from the design

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

push 와 PR 생성은 **사용자 확인을 받고** 한다(원격 반영은 자동화하지 않는다).
PR 제목·본문은 영어. 본문에 담을 것: 이 머신에서 테스트를 실행하지 못했다는 사실, CI 가 게이트를
돌린다는 것, Step 3 의 `llvm-cov` 확인 요청.

---

## 남은 판단 (구현자가 정할 것)

- **소모 아이템 축(+3)이 어떤 아이템을 쓰나.** `ItemKind` 에는 진화 아이템·이상한 사탕·민트·부적만
  있고 "던전용 소모품"이 없다. 선택지 둘: (a) 이상한 사탕을 소모(가치가 커서 +3 에 안 맞는다),
  (b) `ItemKind` 에 새 케이스를 더하고 상점에 싼값으로 올린다. 설계 문서는 정하지 않았다 —
  Task 5 에서 (b) 쪽이면 상점·인벤토리·문구가 함께 늘어난다는 것을 감안해 사용자에게 확인한다.
  확인 전까지는 `usedItem: false` 고정으로 두고 예산은 100~107 로 돌아간다(퍼즐은 그대로 성립한다).
- **파트너 타입 조회.** `store.currentTypes` 는 PokéAPI 조회 결과가 캐시된 값이라 오프라인 첫 실행에서
  비어 있다. 비면 보정이 0 이고 기준선 100 을 받는다 — 깎지 않으므로 그대로 두어도 안전하다.
