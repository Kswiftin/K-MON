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

    /// 모든 방이 시작 방에서 도달 가능해야 한다 — 고립된 방의 내용은 존재하지 않는 것과 같다.
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

    /// **이 파일의 핵심.** 하루에 맵이 하나뿐이라 클리어 불가능한 맵 하나가 그날을 통째로 없앤다.
    /// 척추 경로만 따라가면 기본 예산 100 으로 `clearSlack` 이상 남기고 보스를 넘어야 한다.
    ///
    /// 도중 최저 체력도 함께 본다 — 마지막 값만 보면 중간에 0 을 찍고 회복으로 살아난 맵을
    /// 통과시킨다(실제로는 그 자리에서 실패로 끝난다).
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

    /// 회복샘은 **척추 밖에만** 둔다. 척추에 놓으면 회복량 20 이 공짜로 얹혀 여유가 15 가 아니라
    /// 35 가 되고(그 상태로 한 번 돌렸다) 방문 순서를 고민할 이유가 사라진다.
    func testSpringsStayOffTheSpineAndAlwaysExist() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            for room in map.spine {
                XCTAssertNotEqual(map.room(room).kind, .spring, "\(map.dayKey): 척추에 샘이 있다")
            }
            XCTAssertGreaterThanOrEqual(map.rooms.filter { $0.kind == .spring }.count, 1,
                                        "\(map.dayKey): 샘 없는 맵 — 방 종류 하나가 그날 사라진다")
        }
    }

    /// 되살린 간선이 버린 간선의 10~20% 안이어야 한다. 0% 면 전부 막다른 길, 과하면 지름길뿐이다.
    /// 버림 나눗셈으로 뽑으면 실측이 8.97% 까지 내려간다 — 반올림으로 띠 안에 잠근 자리다.
    func testExtraEdgeRatioStaysInBand() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            let allPairs = PuzzleDungeon.roomCount * (PuzzleDungeon.roomCount - 1) / 2
            let discarded = allPairs - map.mstEdgeCount
            let extra = map.edges.count - map.mstEdgeCount
            XCTAssertGreaterThanOrEqual(extra * 100 / discarded, 10, "\(map.dayKey): 여분 간선 \(extra)")
            XCTAssertLessThanOrEqual(extra * 100 / discarded, 20, "\(map.dayKey): 여분 간선 \(extra)")
            XCTAssertEqual(map.mstEdgeCount, PuzzleDungeon.roomCount - 1, "트리가 방 수 − 1 이 아니다")
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
        // 타입을 못 불러온 개체(오프라인 첫 실행)도 기준선을 받는다 — 보정이 0 이지 벌점이 아니다.
        XCTAssertEqual(PuzzleDungeon.budget(partnerTypes: [], against: affinity,
                                            usedItem: false, trainerLevel: 0),
                       PuzzleDungeon.baseBudget)
    }

    /// 여유 예산 배분 — 생성기를 통해서는 밟히지 않는 분기까지 직접 검사한다.
    /// 커버리지 퍼센트로는 이 분기가 도는지 알 수 없다(줄 커버리지는 조건 평가만으로 세므로).
    func testAllowanceSplitSpendsEverythingAndDegradesGracefully() {
        // 나머지는 버리지 않고 앞쪽에 1씩 얹는다 — 합이 예산과 정확히 같아야 여유가 15 로 남는다.
        let split = PuzzleDungeon.splitAllowance(37, among: 3)
        XCTAssertEqual(split, [13, 12, 12])
        XCTAssertEqual(split.reduce(0, +), 37, "예산을 남기면 척추 여유가 설계값보다 커진다")

        // 예산이 교전 수보다 적으면 교전 수를 예산까지 줄인다(각 1 데미지) — 남는 교전은 빈 방이 된다.
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

    /// 척추 밖 방이 항상 남는다는 불변식 — 회복샘 보장이 이걸 전제로 빈 배열 가드를 두지 않는다.
    func testSpineNeverSwallowsEveryRoom() {
        for offset in 0..<365 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            XCTAssertLessThanOrEqual(map.spine.count, 8)
            XCTAssertGreaterThanOrEqual(PuzzleDungeon.roomCount - map.spine.count, 6,
                                        "\(map.dayKey): 척추 밖 방이 6개 미만")
        }
    }

    static func dayKey(_ offset: Int) -> String {
        let day = Date(timeIntervalSince1970: 1_767_225_600 + Double(offset) * 86_400)
        return CompanionStore.dayKey(day)
    }
}
