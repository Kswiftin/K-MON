import XCTest
@testable import PokeTokenBar

/// 던전 화면이 쓰는 순수 계산(#79 사용성 보강). 이 파일이 없던 동안 설계 목업 6줄 중 온전히
/// 구현된 줄이 0개였고, 순수 코어만 테스트로 잠겨 있어 게이트가 그걸 잡지 못했다.
final class DungeonNarrationTests: XCTestCase {

    private static func dayKey(_ offset: Int) -> String {
        let day = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_760_000_000))!
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: day)
    }

    // MARK: 방위

    func testDirectionUsesGridAxes() {
        let origin = DungeonCoord(x: 3, y: 3)
        XCTAssertEqual(DungeonNarration.direction(from: origin, to: DungeonCoord(x: 3, y: 0)), .north,
                       "y 는 아래로 증가한다 — y 가 작은 쪽이 북")
        XCTAssertEqual(DungeonNarration.direction(from: origin, to: DungeonCoord(x: 3, y: 5)), .south)
        XCTAssertEqual(DungeonNarration.direction(from: origin, to: DungeonCoord(x: 5, y: 3)), .east)
        XCTAssertEqual(DungeonNarration.direction(from: origin, to: DungeonCoord(x: 0, y: 3)), .west)
        XCTAssertEqual(DungeonNarration.direction(from: origin, to: DungeonCoord(x: 5, y: 1)), .northEast)
        XCTAssertEqual(DungeonNarration.direction(from: origin, to: DungeonCoord(x: 1, y: 5)), .southWest)
    }

    /// 주축이 다른 축의 두 배 이상이면 한 방위로 줄인다 — 여덟 방위를 다 쓰면 사실상 같은 길이
    /// "북"과 "북동"으로 갈려 읽힌다.
    func testDirectionCollapsesDominantAxis() {
        let origin = DungeonCoord(x: 0, y: 5)
        XCTAssertEqual(DungeonNarration.direction(from: origin, to: DungeonCoord(x: 1, y: 0)), .north)
        XCTAssertEqual(DungeonNarration.direction(from: origin, to: DungeonCoord(x: 4, y: 4)), .east)
    }

    /// 격자 칸은 유일하므로 정상 맵에는 없는 경우다. `nil` 을 내야 화면이 화살표를 그리지 않는다.
    func testDirectionOfSameCellIsNil() {
        XCTAssertNil(DungeonNarration.direction(from: DungeonCoord(x: 2, y: 2),
                                                to: DungeonCoord(x: 2, y: 2)))
    }

    // MARK: 방 이름

    func testNameSlotsAreDeterministicPerDayKey() {
        XCTAssertEqual(DungeonNarration.nameSlots(dayKey: "2026-08-24"),
                       DungeonNarration.nameSlots(dayKey: "2026-08-24"))
    }

    func testNameSlotsDifferAcrossDays() {
        XCTAssertNotEqual(DungeonNarration.nameSlots(dayKey: "2026-08-24"),
                          DungeonNarration.nameSlots(dayKey: "2026-08-25"),
                          "이름이 매일 같으면 어제 기억이 오늘 맵의 이름을 오염시킨다")
    }

    /// 한 맵에 같은 이름이 두 번 나오면 이름으로 방을 구분하는 이 화면의 전제가 깨진다.
    func testNameSlotsAreUniqueWithinADay() {
        XCTAssertGreaterThanOrEqual(DungeonNarration.roomNameSlots, PuzzleDungeon.maxRoomCount)
        for offset in 0..<365 {
            let slots = DungeonNarration.nameSlots(dayKey: Self.dayKey(offset))
            let roomCount = PuzzleDungeon.map(dayKey: Self.dayKey(offset)).rooms.count
            XCTAssertGreaterThanOrEqual(slots.count, roomCount, "\(Self.dayKey(offset)): 방보다 이름이 적다")
            XCTAssertEqual(Set(slots.prefix(roomCount)).count, roomCount, "\(Self.dayKey(offset)): 이름 중복")
        }
    }

    /// 이름 슬롯은 맵 생성 스트림과 갈라져 있어야 한다 — 같은 난수를 나눠 쓰면 이름을 바꿀 때
    /// 맵(방 배치·상성)이 따라 바뀌어 그날 난이도가 흔들린다.
    func testNameSlotsDoNotDisturbMapGeneration() {
        let before = PuzzleDungeon.map(dayKey: "2026-08-24")
        _ = DungeonNarration.nameSlots(dayKey: "2026-08-24")
        let after = PuzzleDungeon.map(dayKey: "2026-08-24")
        XCTAssertEqual(before.rooms, after.rooms)
        XCTAssertEqual(before.spine, after.spine)
    }

    // MARK: 체력 게이지

    /// 0 과 만피는 반올림이 흐려서는 안 된다 — 죽기 직전과 여유가 같은 그림이면 게이지가 없는 것과 같다.
    func testGaugeKeepsBothEnds() {
        XCTAssertEqual(DungeonNarration.gauge(hp: 0, budget: 100, width: 10), String(repeating: "░", count: 10))
        XCTAssertEqual(DungeonNarration.gauge(hp: 100, budget: 100, width: 10), String(repeating: "▓", count: 10))
        XCTAssertEqual(DungeonNarration.gauge(hp: 1, budget: 100, width: 10).prefix(1), "▓",
                       "살아 있으면 한 칸은 차 있어야 한다")
        XCTAssertTrue(DungeonNarration.gauge(hp: 99, budget: 100, width: 10).contains("░"),
                      "만피가 아니면 한 칸은 비어 있어야 한다")
    }

    func testGaugeWidthIsStable() {
        for hp in 0...105 {
            XCTAssertEqual(DungeonNarration.gauge(hp: hp, budget: 105, width: 12).count, 12)
        }
    }

    // MARK: 출구 분류

    /// 첫 시도의 인접 방은 전부 안개여야 한다 — 정체가 새면 앉은 자리에서 답이 나온다.
    func testFreshRunLeaksNoRoomKinds() {
        for offset in 0..<40 {
            let map = PuzzleDungeon.map(dayKey: Self.dayKey(offset))
            let run = DungeonRun(map: map, budget: PuzzleDungeon.baseBudget)
            let choices = DungeonNarration.choices(for: run)
            XCTAssertTrue(choices.back.isEmpty, "첫 시도에는 되돌아갈 방이 없다")
            for choice in choices.fresh {
                XCTAssertNil(choice.known, "\(map.dayKey): 인접한 방의 정체가 미리 보인다")
                XCTAssertFalse(choice.springSpent)
            }
            XCTAssertEqual(DungeonNarration.scene(for: run).darkExitCount, choices.fresh.count)
            XCTAssertNil(DungeonNarration.scene(for: run).springDirection,
                         "밝혀지지 않은 샘이 물소리로 새어 나온다")
        }
    }

    /// 곁방에서 나오는 길이 되돌아가기로 갈라지고, 두 목록 모두 비용 오름차순이어야 한다.
    /// 본선은 되돌아갈 수 없으니 되돌아가기 줄은 곁방에서만 나온다.
    func testChoicesSplitBacktrackAndSortByCost() {
        let map = PuzzleDungeon.map(dayKey: "2026-08-24")
        guard let (spur, parent) = map.spurParent.min(by: { $0.key < $1.key }) else {
            return XCTFail("이 날짜 맵에 곁방이 없다")
        }
        var run = DungeonRun(map: map, budget: 200)
        run.debugTeleport(to: parent)
        let atParent = DungeonNarration.choices(for: run)
        XCTAssertTrue(atParent.back.isEmpty, "본선 방에는 되돌아갈 길이 없다")
        XCTAssertEqual(atParent.fresh.first { $0.room == spur }?.isSpur, true, "곁방 줄에 왕복 표시가 없다")
        XCTAssertTrue(atParent.fresh.filter { $0.room != spur }.allSatisfy { !$0.isSpur }, "전진 통로가 곁방으로 표시됐다")
        run.move(to: spur)

        let choices = DungeonNarration.choices(for: run)
        XCTAssertTrue(choices.back.contains { $0.room == parent }, "왔던 방이 되돌아가기에 없다")
        XCTAssertTrue(choices.fresh.isEmpty, "곁방은 막다른 길이다")
        XCTAssertTrue(choices.fresh.allSatisfy { $0.known == nil })
        XCTAssertTrue(choices.back.allSatisfy { $0.known != nil })
        XCTAssertEqual(choices.fresh.map(\.cost), choices.fresh.map(\.cost).sorted())
        XCTAssertEqual(choices.back.map(\.cost), choices.back.map(\.cost).sorted())
        XCTAssertEqual(choices.fresh.count + choices.back.count, run.exits.count)
    }

    /// 통로 비용만으로 쓰러지는 길에는 경고가 붙어야 한다. 방 내용은 들어가야 알 수 있으니 통로만 본다.
    func testLethalExitIsFlaggedWhenCorridorAloneWouldFell() {
        let map = PuzzleDungeon.map(dayKey: "2026-08-24")
        var run = DungeonRun(map: map, budget: 100)
        run.debugSetHitPoints(1)
        let choices = DungeonNarration.choices(for: run)
        XCTAssertFalse(choices.fresh.isEmpty)
        XCTAssertTrue(choices.fresh.allSatisfy(\.isLethal), "HP 1 이면 통로 비용 1 도 치명이다")

        var healthy = DungeonRun(map: map, budget: 100)
        healthy.debugSetHitPoints(100)
        XCTAssertTrue(DungeonNarration.choices(for: healthy).fresh.allSatisfy { !$0.isLethal })
    }

    /// 이미 마신 샘은 물소리를 내지 않는다 — 되돌아갈 값이 없는 길로 사람을 부른다.
    func testSpentSpringDoesNotMurmur() throws {
        let map = PuzzleDungeon.map(dayKey: "2026-08-24")
        guard let spring = map.rooms.first(where: { $0.kind == .spring }),
              let approach = map.exits(from: spring.id).first else {
            return XCTFail("샘이 없는 맵 — 생성기가 하나는 보장한다")
        }
        var run = DungeonRun(map: map, budget: 200)
        run.debugTeleport(to: approach.room)
        run.move(to: spring.id)                    // 샘을 마신다
        run.move(to: approach.room)                // 옆 방으로 물러난다

        let note = DungeonNarration.scene(for: run)
        XCTAssertNil(note.springDirection, "마신 샘이 아직 물소리를 낸다")
        let choices = DungeonNarration.choices(for: run)
        XCTAssertTrue(choices.back.first { $0.room == spring.id }?.springSpent == true,
                      "사용됨 표시가 붙지 않는다")
    }

    // MARK: 지나온 길

    /// `.damaged` 는 통로 비용과 방 내용 둘 다다. 방에 들어선 직후 한 건만 그 방 것이고, 그 뒤
    /// 데미지는 다음 방으로 가는 통로다 — 갈리지 않으면 `−24` 가 엉뚱한 방에 붙는다.
    func testTrailAttributesCorridorCostToTheRoomBeingEntered() {
        let events: [DungeonEvent] = [
            .damaged(2),                                  // 방 7 로 가는 통로
            .entered(room: 7, kind: .encounter),
            .damaged(24),                                 // 방 7 의 교전
            .damaged(1),                                  // 방 3 으로 가는 통로
            .entered(room: 3, kind: .empty),
        ]
        let trail = DungeonNarration.trail(events, start: .empty)
        XCTAssertEqual(trail.count, 3)
        XCTAssertEqual(trail[0].room, 0)
        XCTAssertEqual(trail[0].deltas, [], "시작 방은 아무 비용도 내지 않았다")
        XCTAssertEqual(trail[1].room, 7)
        XCTAssertEqual(trail[1].deltas, [-2, -24], "통로 2 와 교전 24 가 같은 줄에 있어야 한다")
        XCTAssertEqual(trail[2].room, 3)
        XCTAssertEqual(trail[2].deltas, [-1])
    }

    /// **결함 트리거 회귀** — 빈 방은 내용 이벤트를 하나도 내지 않는다. "들어선 직후 한 건이 방
    /// 내용"으로 가르면 빈 방 다음 통로 비용이 빈 방 줄에 붙어, 다음 방이 공짜로 보인다.
    func testTrailDoesNotChargeEmptyRoomForTheNextCorridor() {
        let trail = DungeonNarration.trail([
            .damaged(1), .entered(room: 2, kind: .empty),
            .damaged(3), .entered(room: 9, kind: .empty),
        ], start: .empty)
        XCTAssertEqual(trail.map(\.deltas), [[], [-1], [-3]],
                       "빈 방 줄이 다음 통로 비용까지 물고 있다")
    }

    func testTrailMarksSpringHealAndDryReuse() {
        let trail = DungeonNarration.trail([
            .damaged(1), .entered(room: 5, kind: .spring), .healed(20),
            .damaged(1), .entered(room: 2, kind: .empty),
            .damaged(1), .entered(room: 5, kind: .spring), .springAlreadyUsed(5),
        ], start: .empty)
        XCTAssertEqual(trail[1].deltas, [-1, 20])
        XCTAssertFalse(trail[1].springWasDry)
        XCTAssertTrue(trail[3].springWasDry)
        XCTAssertEqual(trail[3].deltas, [-1], "두 번째 방문은 회복이 없다")
    }

    func testTrailMarksBossAndCollapse() {
        let cleared = DungeonNarration.trail([
            .damaged(2), .entered(room: 4, kind: .boss), .damaged(30), .bossFelled,
        ], start: .empty)
        XCTAssertTrue(cleared.last?.felledBoss == true)
        XCTAssertEqual(cleared.last?.deltas, [-2, -30])

        // 통로에서 쓰러지면 새 방 줄이 없다 — 비용이 사라지지 않고 마지막 줄에 남아야 한다.
        let fell = DungeonNarration.trail([.damaged(3), .collapsed], start: .empty)
        XCTAssertEqual(fell.count, 1)
        XCTAssertTrue(fell[0].collapsed)
        XCTAssertEqual(fell[0].deltas, [-3])
    }

    /// 보물은 줄에 액수로 붙고, 이미 턴 방은 빈 손 표시가 붙는다. 체력 변화가 아니라 `deltas` 에는 안 들어간다.
    func testTrailMarksLootAndEmptyCache() {
        let events: [DungeonEvent] = [
            .damaged(2), .entered(room: 5, kind: .cache), .looted(room: 5, starPieces: 90),
            .damaged(2), .entered(room: 3, kind: .empty),
            .damaged(2), .entered(room: 5, kind: .cache), .cacheAlreadyLooted(5),
        ]
        let trail = DungeonNarration.trail(events, start: .empty)
        XCTAssertEqual(trail.map(\.room), [0, 5, 3, 5])
        XCTAssertEqual(trail[1].looted, 90)
        XCTAssertEqual(trail[1].deltas, [-2], "보물 액수가 체력 변화에 섞였다")
        XCTAssertFalse(trail[1].cacheWasEmpty)
        XCTAssertTrue(trail[3].cacheWasEmpty)
        XCTAssertEqual(trail[3].looted, 0)
    }

    /// 실제 시도에서 나온 이벤트로도 방 수가 맞아야 한다 — 손으로 만든 배열만 통과하면
    /// 코어가 이벤트를 다른 순서로 쌓기 시작해도 눈치채지 못한다.
    func testTrailMatchesRoomsWalkedInARealRun() {
        let map = PuzzleDungeon.map(dayKey: "2026-08-24")
        var run = DungeonRun(map: map, budget: 200)
        for step in 1..<4 { run.move(to: map.spine[step]) }
        let trail = DungeonNarration.trail(run.events, start: map.room(0).kind)
        XCTAssertEqual(trail.map(\.room), [0] + Array(map.spine[1..<4]))
        XCTAssertEqual(trail.map(\.kind), trail.map { map.room($0.room).kind })
        // 모든 체력 변화가 어느 줄에든 붙었는지 — 합이 실제 소모·회복과 같아야 한다.
        let accounted = trail.flatMap(\.deltas).reduce(0, +)
        XCTAssertEqual(run.hp - run.budget, accounted, "이벤트 하나가 어느 방에도 안 붙었다")
    }
}
