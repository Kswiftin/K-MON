import XCTest
@testable import PokeTokenBar

/// 웨이브 런 클리어가 업적 사다리를 올리는가. 퍼즐 던전이 웨이브 런으로 갈릴 때 이 배선이 안
/// 따라와, `dungeon`·`dungeonSweep` 두 트랙 여덟 칸이 도달 불가인 채로 나갔다 — 업적 선반에
/// 보이는데 영영 안 차는 칸이었다. 옛 테스트는 퍼즐 던전 정산 함수를 **직접** 불러 통과하고
/// 있었다(플레이어가 못 가는 경로를 재고 있었다).
@MainActor
final class WaveRunAchievementTests: XCTestCase {

    private func makeStore() -> CompanionStore {
        let line = EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                           names: [25: ["ko": "피카츄", "en": "Pikachu"]])
        let url = storeStateURL("wave-run")
        return CompanionStore(provider: StubProvider(value: line),
                              clock: { Date(timeIntervalSince1970: 1_000) },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    func testClearingAWaveRunRecordsTheDungeonAchievement() {
        let store = makeStore()
        let before = store.state.starPieces
        store.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true)
        XCTAssertGreaterThan(store.state.starPieces, before, "클리어가 업적 보상을 안 냈다")
    }

    /// 반대편 — 실패한 판은 올리지 않는다. 이쪽을 안 재면 "무조건 올리는" 배선도 위를 통과한다.
    func testFailedRunRecordsNoAchievement() {
        let store = makeStore()
        let before = store.state.starPieces
        store.recordRunResult(reachedWave: 4, cleared: false)
        XCTAssertEqual(store.state.starPieces, before)
    }

    /// 갈림길을 전부 위험한 길로 온 클리어는 `dungeonSweep` 까지 올린다 — 두 트랙이 함께
    /// 지급되므로 안전한 길을 한 번이라도 고른 클리어보다 받는 값이 크다.
    func testRiskyOnlyClearAlsoRecordsTheSweepAchievement() {
        let plain = makeStore()
        plain.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true)
        let risky = makeStore()
        risky.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true,
                              tookOnlyRiskyRoutes: true)
        XCTAssertGreaterThan(risky.state.starPieces, plain.state.starPieces)
    }

    /// 안전한 길을 한 번이라도 고르면 그 판은 `dungeonSweep` 이 아니다.
    func testTakingASafeRouteClearsTheRiskyOnlyFlag() {
        var run = RogueRun(party: [waveRunSnapshot()], opponents: [waveRunSnapshot()], seed: 1)
        XCTAssertTrue(run.tookOnlyRiskyRoutes, "첫 웨이브는 고를 기회가 없었다")
        run.debugSetStageRouting()
        run.take(.safe)
        XCTAssertFalse(run.tookOnlyRiskyRoutes)
    }

    /// 클리어는 알 하나도 낸다 — 업적과 별개의 지급 경로다.
    func testClearingAWaveRunGrantsOneEgg() {
        let store = makeStore()
        XCTAssertEqual(store.state.focusEggs, 0)
        store.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true)
        XCTAssertEqual(store.state.focusEggs, 1, "클리어가 알 하나를 안 냈다")
    }

    /// 같은 날 두 번째 클리어는 알을 또 주지 않는다 — `waveRunEggRewardDate` 원장이 하루 한 번을 막는다.
    func testClearingTwiceInOneDayGrantsOnlyOneEgg() {
        let store = makeStore()
        store.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true)
        store.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true)
        XCTAssertEqual(store.state.focusEggs, 1)
    }

    /// 실패한 판은 알을 주지 않는다.
    func testFailedRunGrantsNoEgg() {
        let store = makeStore()
        store.recordRunResult(reachedWave: 4, cleared: false)
        XCTAssertEqual(store.state.focusEggs, 0)
    }

    /// 반환값은 화면(`RogueRunView`)이 "오늘의 알 보상을 받았습니다" 배너를 띄우는 유일한 신호다 —
    /// 두 번째 클리어에서 false 가 안 나오면 이미 받은 날에도 배너가 다시 뜬다.
    func testRecordRunResultReturnsWhetherTheDailyEggWasJustGranted() {
        let store = makeStore()
        XCTAssertTrue(store.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true))
        XCTAssertFalse(store.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true))
    }
}

private func waveRunSnapshot() -> BattleSnapshot {
    BattleSnapshot(speciesID: 1, name: "M", trainer: "T", level: 5, nature: nil,
                   isShiny: false, types: [.normal],
                   base: BattleStats(hp: 100, atk: 100, def: 50, spa: 100, spd: 50, spe: 100),
                   moves: [MoveSpec(id: 1, names: ["en": "Hit"], type: .normal, power: 40,
                                    damageClass: .physical, accuracy: nil, pp: 20)])
}
