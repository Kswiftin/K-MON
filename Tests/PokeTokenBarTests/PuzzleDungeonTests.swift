import XCTest
@testable import PokeTokenBar

/// 하루 한 판 퍼즐 던전(#79)의 맵 생성 — 층 그래프(`layered-dungeon-design.md`).
/// 이 콘텐츠는 하루에 맵이 하나뿐이라 **클리어 불가능한 맵 하나가 그날을 통째로 없앤다** —
/// 365일 전수 검사가 이 파일의 핵심이다. 판 길이도 같은 이유로 전수로 잠근다(이전 구조는
/// 판 길이 테스트가 없어 평균 2.1 클릭에 끝나는 맵이 365일 그대로 나갔다).
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

    // MARK: 구조

    /// 층 12개, 시작 층과 보스 층은 방 하나, 사이 층은 1~2개. 방 수는 이름 풀 안에 든다.
    func testLayerShape() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            XCTAssertEqual(map.layers.count, PuzzleDungeon.layerCount)
            XCTAssertEqual(map.layers[0], [0], "\(map.dayKey): 시작 층은 방 0 하나")
            XCTAssertEqual(map.layers[map.layers.count - 1].count, 1, "\(map.dayKey): 보스 층은 하나")
            for layer in map.layers.dropFirst().dropLast() {
                XCTAssertTrue((1...2).contains(layer.count), "\(map.dayKey): 층 폭 \(layer.count)")
            }
            XCTAssertLessThanOrEqual(map.rooms.count, PuzzleDungeon.maxRoomCount, "\(map.dayKey)")
            XCTAssertLessThanOrEqual(map.rooms.count, DungeonNarration.roomNameSlots,
                                     "\(map.dayKey): 방이 이름 풀보다 많다 — 같은 이름이 두 번 나온다")
            XCTAssertEqual(map.room(map.bossRoom).kind, .boss)
            XCTAssertEqual(map.rooms.filter { $0.kind == .boss }.count, 1, "보스는 하나뿐")
        }
    }

    /// **모든 간선이 층을 정확히 하나 넘는다** — 층을 건너뛰는 간선이 없고, 곁방 통로는 같은 층 안의
    /// 매달린 본선 방과만 이어진다. 통로 비용은 1~3.
    func testEveryEdgeCrossesExactlyOneLayerOrHangsASpur() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            for edge in map.edges {
                XCTAssertTrue((1...3).contains(edge.cost), "\(map.dayKey): 통로 비용 \(edge.cost)")
                if map.isSpur(edge.a) || map.isSpur(edge.b) {
                    let (spur, parent) = map.isSpur(edge.a) ? (edge.a, edge.b) : (edge.b, edge.a)
                    XCTAssertEqual(map.spurParent[spur], parent, "\(map.dayKey): 곁방이 다른 방에 붙었다")
                    XCTAssertEqual(map.layerOf[spur], map.layerOf[parent])
                } else {
                    XCTAssertEqual(abs(map.layerOf[edge.a] - map.layerOf[edge.b]), 1,
                                   "\(map.dayKey): 층을 건너뛰는 간선 \(edge)")
                }
            }
        }
    }

    /// **곁방은 막다른 길이다** — 나가는 출구가 들어온 통로 하나뿐. 본선에서는 **왼쪽으로 못 간다.**
    func testSpursAreDeadEndsAndMainlineNeverGoesBack() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            for (spur, parent) in map.spurParent {
                XCTAssertEqual(map.exits(from: spur).map(\.room), [parent], "\(map.dayKey): 곁방에 다른 출구")
            }
            for room in map.rooms.indices where !map.isSpur(room) {
                for exit in map.exits(from: room) where map.spurParent[exit.room] != room {
                    XCTAssertEqual(map.layerOf[exit.room], map.layerOf[room] + 1,
                                   "\(map.dayKey): 본선 \(room) 에서 뒤로 가는 출구 \(exit.room)")
                }
            }
        }
    }

    /// **이 파일의 핵심 하나.** 모든 방이 시작 방에서 도달 가능하고, 보스까지 최단 클릭 수가
    /// **층 수 − 1 로 고정**된다. 지름길이 하나라도 생기면 여기서 갈린다 — 이전 구조의 결함
    /// (평균 2.1 클릭)을 직접 겨냥하는 테스트다.
    func testShortestPathToBossIsLockedToLayerCount() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            var hops = [0: 0], queue = [0], head = 0
            while head < queue.count {
                let room = queue[head]; head += 1
                for exit in map.exits(from: room) where hops[exit.room] == nil {
                    hops[exit.room] = hops[room]! + 1
                    queue.append(exit.room)
                }
            }
            XCTAssertEqual(hops.count, map.rooms.count, "\(map.dayKey): 고립된 방")
            XCTAssertEqual(hops[map.bossRoom], PuzzleDungeon.layerCount - 1,
                           "\(map.dayKey): 보스까지 \(hops[map.bossRoom] ?? -1) 클릭 — 지름길이 생겼다")
        }
    }

    // MARK: 클리어 가능성

    /// **이 파일의 핵심 둘.** 하루에 맵이 하나뿐이라 클리어 불가능한 맵 하나가 그날을 통째로 없앤다.
    /// 본선의 **어느 경로로 가도** 기본 예산 100 으로 보스를 넘어야 한다 — 가장 싼 경로만 보면
    /// 비싼 경로를 고른 날이 죽는다. 도중 최저 체력으로 판정한다(0 을 찍으면 그 자리에서 끝이다).
    func test365DaysAreClearableOnEveryMainlinePath() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            // 층 순서가 위상 순서라 한 번 훑으면 "그 방에 닿는 최악의 남은 체력"이 나온다.
            var worst = [0: PuzzleDungeon.baseBudget]
            for layer in map.layers {
                for room in layer {
                    guard let hp = worst[room] else { continue }
                    for exit in map.exits(from: room) where !map.isSpur(exit.room) {
                        var after = hp - exit.cost
                        let entered = map.room(exit.room)
                        if after > 0, entered.kind == .encounter || entered.kind == .boss { after -= entered.damage }
                        if worst[exit.room] == nil || after < worst[exit.room]! { worst[exit.room] = after }
                    }
                }
            }
            XCTAssertGreaterThan(worst[map.bossRoom] ?? 0, 0, "\(map.dayKey): 어떤 본선 경로로는 보스를 못 넘는다")
        }
    }

    /// `spine` 은 가장 비싼 전진 경로다 — 그 길로 갔을 때 남는 체력이 정확히 `clearSlack` 이어야
    /// 곁방 밑천이 설계값이다. 남는 체력이 크면 곁방 판단이 느슨해진다(실측 25 가 나왔던 결함).
    func testSpineIsTheDearestPathAndLeavesExactlyTheSlack() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            XCTAssertEqual(map.spine.count, PuzzleDungeon.layerCount, "\(map.dayKey): 척추가 층마다 한 방이 아니다")
            XCTAssertEqual(map.spine.first, 0)
            XCTAssertEqual(map.spine.last, map.bossRoom)
            var hp = PuzzleDungeon.baseBudget
            for step in 1..<map.spine.count {
                hp -= map.cost(from: map.spine[step - 1], to: map.spine[step]) ?? 999
                let room = map.room(map.spine[step])
                if room.kind == .encounter || room.kind == .boss { hp -= room.damage }
            }
            XCTAssertEqual(hp, PuzzleDungeon.clearSlack, "\(map.dayKey): 최악 경로 남는 체력 \(hp)")
            let dear = PuzzleDungeon.dearestCorridorSums(map)
            let spineCorridor = (1..<map.spine.count).reduce(0) { $0 + (map.cost(from: map.spine[$1 - 1], to: map.spine[$1]) ?? 0) }
            XCTAssertEqual(dear[map.bossRoom], spineCorridor, "\(map.dayKey): 척추가 가장 비싼 경로가 아니다")
        }
    }

    /// 본선 교전은 **층 단위**다 — 한 층 안에서 교전을 피해 가는 방이 없다. 일부 방에만 두면
    /// 교전 없는 쪽으로 새어 예산 압박이 사라진다.
    func testMainlineEncountersCoverWholeLayers() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            for (index, layer) in map.layers.enumerated() {
                let kinds = Set(layer.map { map.room($0).kind })
                XCTAssertEqual(kinds.count, 1, "\(map.dayKey): \(index)층 종류가 섞였다 \(kinds)")
                let damages = Set(layer.map { map.room($0).damage })
                XCTAssertEqual(damages.count, 1, "\(map.dayKey): \(index)층 데미지가 방마다 다르다")
            }
            let fightLayers = map.layers.indices.filter { map.room(map.layers[$0][0]).kind == .encounter }
            XCTAssertEqual(fightLayers, PuzzleDungeon.encounterLayers, "\(map.dayKey)")
        }
    }

    // MARK: 곁방

    /// 회복샘과 보물은 **곁방에만** 있다. 본선에 있으면 지나가다 공짜로 받는 것이라 판단이 없다.
    func testSpringsAndCachesLiveOnlyInSpurs() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            for room in map.rooms where room.kind == .spring || room.kind == .cache {
                XCTAssertTrue(map.isSpur(room.id), "\(map.dayKey): 본선에 \(room.kind)")
            }
            for room in map.rooms where room.kind == .cache {
                XCTAssertTrue(PuzzleDungeon.cacheRewardRange.contains(room.damage), "\(map.dayKey): 보물 \(room.damage)")
            }
        }
    }

    /// 곁방 내용 분포 — 샘 25 / 보물 30 / 빈 방 20 / 교전 25 (%) 에서 ±5%p 안. 365일 집계다.
    /// 꽝(빈 방·교전)이 없으면 판단이 아니고, 보물이 없으면 열 이유가 없다.
    func testSpurContentDistributionMatchesDesign() {
        var counts: [RoomKind: Int] = [:]
        var spurs = 0
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            for spur in map.spurParent.keys {
                spurs += 1
                counts[map.room(spur).kind, default: 0] += 1
            }
        }
        XCTAssertGreaterThan(spurs, 365 * 5, "곁방이 하루 5개 미만이면 매 층 판단이 없다")
        let expected: [RoomKind: Int] = [.spring: 25, .cache: 30, .empty: 20, .encounter: 25]
        for (kind, percent) in expected {
            let actual = counts[kind, default: 0] * 100 / spurs
            XCTAssertLessThanOrEqual(abs(actual - percent), 5, "\(kind): \(actual)% (목표 \(percent)%)")
        }
        XCTAssertEqual(counts[.boss, default: 0], 0, "곁방에 보스")
    }

    // MARK: 예산

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
        // 타입을 못 불러온 개체(오프라인 첫 실행)도 기준선을 받는다 — 보정이 0 이지 벌점이 아니다.
        XCTAssertEqual(PuzzleDungeon.budget(partnerTypes: [], against: affinity,
                                            usedItem: false, trainerLevel: 0),
                       PuzzleDungeon.baseBudget)
    }

    /// 여유 예산 배분 — 생성기를 통해서는 밟히지 않는 분기까지 직접 검사한다.
    /// 커버리지 퍼센트로는 이 분기가 도는지 알 수 없다(줄 커버리지는 조건 평가만으로 세므로).
    func testAllowanceSplitSpendsEverythingAndDegradesGracefully() {
        // 나머지는 버리지 않고 앞쪽에 1씩 얹는다 — 합이 예산과 정확히 같아야 남는 체력이 설계값이다.
        let split = PuzzleDungeon.splitAllowance(37, among: 3)
        XCTAssertEqual(split, [13, 12, 12])
        XCTAssertEqual(split.reduce(0, +), 37, "예산을 남기면 남는 체력이 설계값보다 커진다")

        // 예산이 층 수보다 적으면 교전 층 수를 예산까지 줄인다(각 1 데미지) — 남는 층은 빈 방이 된다.
        XCTAssertEqual(PuzzleDungeon.splitAllowance(2, among: 5), [1, 1])
        XCTAssertEqual(PuzzleDungeon.splitAllowance(0, among: 3), [])
        XCTAssertEqual(PuzzleDungeon.splitAllowance(-5, among: 3), [], "음수 예산도 교전 0 개로 접힌다")
        XCTAssertEqual(PuzzleDungeon.splitAllowance(10, among: 0), [])
        // 배분된 데미지는 항상 1 이상이다 — 0 데미지 교전은 빈 방과 구별되지 않는다.
        for count in 1...6 {
            for allowance in 1...60 {
                let values = PuzzleDungeon.splitAllowance(allowance, among: count)
                XCTAssertTrue(values.allSatisfy { $0 >= 1 }, "\(allowance)/\(count): \(values)")
                XCTAssertLessThanOrEqual(values.reduce(0, +), allowance, "예산을 넘겨 배분했다")
            }
        }
    }

    static func dayKey(_ offset: Int) -> String {
        let day = Date(timeIntervalSince1970: 1_767_225_600 + Double(offset) * 86_400)
        return CompanionStore.dayKey(day)
    }
}
