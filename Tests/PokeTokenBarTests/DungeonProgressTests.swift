import XCTest
@testable import PokeTokenBar

/// 던전 진행 저장(#79). 리셋은 자정 타이머가 아니라 **날짜 키 비교**다(`MissionBoard` 와 같은 방식).
final class DungeonProgressTests: XCTestCase {

    /// 날짜 키가 바뀌면 기억·클리어·정산 플래그가 **모두** 리셋된다.
    /// 하나만 남으면 어제 정산 플래그가 오늘 보상을 막는다.
    func testDayRolloverResetsEverything() {
        var progress = DungeonProgress()
        progress.roll(dayKey: "2026-08-21")
        progress.cleared = true
        progress.rewardPaid = true
        progress.remembered = [3: .encounter]
        progress.looted = [7]
        progress.roll(dayKey: "2026-08-22")
        XCTAssertFalse(progress.cleared)
        XCTAssertFalse(progress.rewardPaid)
        XCTAssertTrue(progress.remembered.isEmpty)
        XCTAssertTrue(progress.looted.isEmpty, "어제 턴 보물방 번호가 오늘 보물을 막는다")
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

    /// 손편집 방어 — **그날 맵**에 없는 방 번호는 버리고, 정산됐으면 클리어도 참으로 맞춘다.
    /// 방 수가 날마다 다르므로 상한은 고정값이 아니라 그 날짜 맵의 방 수다 — 방 수가 정확히 그 값인
    /// 번호(첫 번째 없는 방)로 경계를 밟는다.
    func testNormalizeDropsOutOfRangeRoomsAndRepairsClearedFlag() {
        var progress = DungeonProgress()
        progress.roll(dayKey: "2026-08-21")
        let count = PuzzleDungeon.map(dayKey: "2026-08-21").rooms.count
        progress.remembered = [0: .empty, count - 1: .empty, count: .boss, 99: .boss, -1: .spring]
        progress.looted = [1, count, 999]
        progress.rewardPaid = true
        progress.cleared = false
        progress.normalize()
        XCTAssertEqual(Set(progress.remembered.keys), [0, count - 1])
        XCTAssertEqual(progress.looted, [1])
        XCTAssertTrue(progress.cleared, "정산됐는데 클리어가 거짓이면 화면이 보상을 다시 권한다")
    }

    /// `looted` 는 나중에 붙은 필드다 — 키가 없는 옛 세이브가 그대로 읽혀야 한다. 디코드가 실패해
    /// 기본값으로 떨어지면 업데이트 당일 클리어·정산 기록이 사라져 보상이 두 번 나간다.
    func testOldSaveWithoutLootedFieldStillDecodes() throws {
        let json = Data("""
        {"dayKey":"2026-08-21","cleared":true,"rewardPaid":true,"remembered":{"3":"encounter"}}
        """.utf8)
        let progress = try JSONDecoder().decode(DungeonProgress.self, from: json)
        XCTAssertTrue(progress.rewardPaid)
        XCTAssertEqual(progress.remembered, [3: .encounter])
        XCTAssertTrue(progress.looted.isEmpty)

        var full = progress
        full.looted = [4, 2]
        let again = try JSONDecoder().decode(DungeonProgress.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(again, full)
    }

    /// 턴 보물방 번호는 서명에 들어가되 **비어 있으면 붙지 않는다** — 이 필드가 없던 시절의 세이브와
    /// 같은 문자열을 내야 정상 세이브가 조작 판정되지 않는다.
    func testLootedJoinsCanonicalOnlyWhenPresent() {
        var progress = DungeonProgress()
        let before = progress.canonical
        progress.looted = []
        XCTAssertEqual(progress.canonical, before)
        progress.looted = [9, 2]
        XCTAssertNotEqual(progress.canonical, before, "턴 보물방이 서명 밖이면 그 줄을 지워 매일 다시 턴다")
        XCTAssertTrue(progress.canonical.hasSuffix("|l2,9"), "정렬돼야 한다: \(progress.canonical)")
    }

    /// 무결성 canonical 은 **키로 정렬**해야 한다. 사전 순회 순서에 기대면 같은 상태가 실행마다
    /// 다른 문자열을 내서 정상 세이브가 무작위로 조작 판정된다.
    func testCanonicalIsOrderIndependent() {
        var a = DungeonProgress(), b = DungeonProgress()
        a.remembered = [5: .encounter, 1: .empty, 9: .spring]
        b.remembered = [9: .spring, 1: .empty, 5: .encounter]
        XCTAssertEqual(a.canonical, b.canonical)
        XCTAssertTrue(a.canonical.contains("1:empty"), "정렬 결과가 문자열에 드러나야 한다")
        XCTAssertLessThan(a.canonical.range(of: "1:empty")!.lowerBound,
                          a.canonical.range(of: "5:encounter")!.lowerBound,
                          "작은 방 번호가 먼저 와야 한다")
    }

    /// 기본값이면 canonical 에 세그먼트가 붙지 않는다 — 붙이면 이 필드가 없던 시절의 정상 세이브가
    /// 전부 조작 판정된다(`integrityVersion` 을 올리지 않고 새 필드를 넣을 수 있는 유일한 방법).
    func testDefaultProgressDoesNotChangeCanonicalString() {
        var state = CompanionState()
        let before = SaveTransfer.canonicalString(state)
        state.dungeon = DungeonProgress()
        XCTAssertEqual(SaveTransfer.canonicalString(state), before)
        state.dungeon.rewardPaid = true
        XCTAssertNotEqual(SaveTransfer.canonicalString(state), before,
                          "정산 플래그가 서명 밖이면 그 한 줄을 고쳐 매일 보상을 다시 받는다")
        XCTAssertTrue(SaveTransfer.canonicalString(state).contains("dun"))
    }
}

// MARK: 정산 경로 (스토어)

@MainActor
final class DungeonSettlementTests: XCTestCase {

    /// `state` 는 `private(set)` 이라 테스트에서 직접 채울 수 없다 — 인벤토리는 세이브 파일로
    /// 시드한다(미션 테스트가 트레이너 포인트를 넣는 방식과 같다). `economyVersion` 을 현재 값으로
    /// 적어야 리셋 마이그레이션이 인벤토리를 비우지 않고, `integrityVersion` 을 빼면 0 으로 읽혀
    /// 서명 검사에서 면제된다.
    private func makeStore(_ clock: TestClock, freshWater: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-dungeon-\(UUID().uuidString).json")
        if freshWater > 0 {
            let json = """
            {"economyVersion":\(IdleEconomy.currentVersion),"forcedResetVersion":\(SaveTransfer.forcedResetVersion),\
            "inventory":{"freshWater":\(freshWater)}}
            """
            try? Data(json.utf8).write(to: url)
        }
        return CompanionStore(provider: StubProvider(value: dungeonTestLine), clock: clock.closure,
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    /// 보상은 그날 첫 클리어만. 두 번째 클리어는 0 이고 재플레이는 연습으로 열려 있다.
    func testFirstClearPaysOnceAndReplayIsFree() {
        let store = makeStore(TestClock())
        let before = store.state.starPieces
        XCTAssertEqual(store.settleDungeonClear(revealed: [0: .empty]), PuzzleDungeon.firstClearReward)
        XCTAssertEqual(store.state.starPieces, before + PuzzleDungeon.firstClearReward)
        XCTAssertEqual(store.settleDungeonClear(revealed: [0: .empty]), 0, "재플레이는 무보상 연습이다")
        XCTAssertEqual(store.state.starPieces, before + PuzzleDungeon.firstClearReward)
        XCTAssertTrue(store.dungeonCleared)
    }

    /// 날짜가 넘어가면 같은 스토어에서 다시 보상이 나간다 — 리셋이 정산 플래그까지 비우는지를
    /// 스토어 경로로 확인한다(구조체 단위 테스트만으로는 `roll` 호출 누락을 못 잡는다).
    func testNextDayPaysAgain() {
        let clock = TestClock()
        let store = makeStore(clock)
        XCTAssertEqual(store.settleDungeonClear(revealed: [:]), PuzzleDungeon.firstClearReward)
        clock.advance(24 * 60 * 60)
        XCTAssertFalse(store.dungeonCleared, "날짜가 바뀌었는데 어제 클리어가 남아 있다")
        XCTAssertEqual(store.settleDungeonClear(revealed: [:]), PuzzleDungeon.firstClearReward)
    }

    /// 곁방 보물 정산 — 하루 한 번만 별의조각이 나가고, 보물방이 아닌 번호나 화면이 보낸 액수는 믿지 않는다.
    func testCacheLootPaysOnceAndTrustsTheMapNotTheCaller() {
        let store = makeStore(TestClock())
        let map = store.dungeonMap
        guard let cache = map.rooms.first(where: { $0.kind == .cache }) else {
            // 이 날짜 맵에 보물방이 없으면 정산 가드만 본다.
            XCTAssertEqual(store.lootDungeonCache(room: 0, starPieces: 500), 0)
            return
        }
        let before = store.state.starPieces
        XCTAssertEqual(store.lootDungeonCache(room: cache.id, starPieces: 9_999), cache.damage, "액수는 맵이 정한다")
        XCTAssertEqual(store.state.starPieces, before + cache.damage)
        XCTAssertEqual(store.state.dungeon.looted, [cache.id])
        XCTAssertEqual(store.lootDungeonCache(room: cache.id, starPieces: cache.damage), 0, "같은 방을 두 번 털었다")
        XCTAssertEqual(store.state.starPieces, before + cache.damage)
        let notCache = map.rooms.first { $0.kind != .cache }!.id
        XCTAssertEqual(store.lootDungeonCache(room: notCache, starPieces: 100), 0, "보물방이 아닌데 별의조각이 나갔다")
        XCTAssertEqual(store.lootDungeonCache(room: 999, starPieces: 100), 0)
        // 다음 시도가 턴 방을 들고 시작한다 — 재도전으로 다시 털 수 없다.
        XCTAssertEqual(store.startDungeonRun().looted, [cache.id])
    }

    /// 실패·이탈은 시도만 버리고 맵 기억은 남긴다.
    func testRememberingSurvivesAFailedAttempt() {
        let store = makeStore(TestClock())
        let map = store.dungeonMap
        let neighbor = map.exits(from: 0)[0].room
        store.rememberDungeon([neighbor: map.room(neighbor).kind])
        XCTAssertEqual(store.state.dungeon.remembered[neighbor], map.room(neighbor).kind)
        XCTAssertFalse(store.state.dungeon.cleared, "기억만 남기는 경로가 클리어를 세우면 안 된다")
        // 다음 시도가 그 기억을 들고 시작한다.
        let session = store.startDungeonRun()
        XCTAssertEqual(session.exits.first { $0.room == neighbor }?.known, map.room(neighbor).kind)
    }

    /// 먹는샘물은 **시도 시작에서 한 병만** 줄고 예산이 +3 된다. 소모와 예산이 갈라지면
    /// 재고만 줄거나 그 반대가 된다.
    func testFreshWaterIsSpentOnceAndRaisesTheBudget() {
        let store = makeStore(TestClock(), freshWater: 1)
        XCTAssertEqual(store.itemCount(.freshWater), 1, "테스트 전제: 세이브 시드가 먹는샘물을 넣었다")
        let plain = store.startDungeonRun()
        XCTAssertEqual(store.itemCount(.freshWater), 1, "마시지 않았는데 재고가 줄었다")

        let boosted = store.startDungeonRun(drinkFreshWater: true)
        XCTAssertEqual(store.itemCount(.freshWater), 0)
        XCTAssertEqual(boosted.budget, plain.budget + 3)

        // 재고가 없으면 예산이 오르지 않고, 재고도 음수로 내려가지 않는다.
        let dry = store.startDungeonRun(drinkFreshWater: true)
        XCTAssertEqual(dry.budget, plain.budget)
        XCTAssertEqual(store.itemCount(.freshWater), 0)
    }

    /// 먹는샘물은 상점에서 살 수 있어야 한다 — 살 곳이 없으면 예산 +3 축이 존재하지 않는다.
    func testFreshWaterIsOnSale() {
        XCTAssertEqual(ItemKind.freshWater.shopPrice, PuzzleDungeon.freshWaterPrice)
        XCTAssertTrue(makeStore(TestClock()).purchasableItems.contains(.freshWater))
        XCTAssertNil(ItemKind.freshWater.evolutionRule, "진화 아이템으로 분류되면 값이 500 으로 덮인다")
    }
}

/// 스토어를 세우기 위한 최소 진화 라인 — 던전은 종·진화와 무관하므로 내용은 아무래도 좋다.
private let dungeonTestLine: EvoLine = {
    var names: [Int: [String: String]] = [:]
    for id in [1, 2, 3] { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: 1,
                   tree: EvoNode(speciesID: 1,
                                 children: [EvoNode(speciesID: 2,
                                                    children: [EvoNode(speciesID: 3, children: [])])]),
                   rarity: .common, names: names)
}()
