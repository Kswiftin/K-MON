import XCTest
@testable import PokeTokenBar

// companion 표시 상태(displayState) 전이 — refreshLifecycle() 의 규칙을 고정한다.
//
// 2026-08-13 게임 구조 개편으로 표시 상태는 더 이상 사용량/burn tier 입력이 아니라, 매 tick() 마다
// refreshLifecycle() 이 활성 여부·이벤트 창(eventUntil)·돌봄 에너지(care.energy)만으로 정한다:
//   active == nil                          → .egg
//   justGraduated != nil || 이벤트 창 안    → .levelUp
//   care.energy < 20                       → .tired
//   care.energy < 45                       → .sleep
//   그 외                                   → .idle
// SeededRNG / StubProvider 는 CompanionTests.swift 의 내부 헬퍼를 재사용한다.

private func dnode(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }
private func dline(base: Int, rarity: Rarity = .common) -> EvoLine {
    EvoLine(baseID: base, tree: dnode(base, [dnode(base + 1, [dnode(base + 2)])]),
            rarity: rarity, names: [:])
}
private let dNow = Date(timeIntervalSince1970: 1_700_000_000)

/// 테스트에서 시계를 전진시키기 위한 가변 박스 (이벤트 윈도우 만료 제어용).
private final class ClockBox: @unchecked Sendable {
    nonisolated(unsafe) var now: Date
    init(_ d: Date) { now = d }
}

@MainActor
final class CompanionDisplayStateTests: XCTestCase {
    private func hatchedStore(rarity: Rarity = .common) async -> (CompanionStore, ClockBox) {
        let clock = ClockBox(dNow)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-disp-\(UUID().uuidString).json")
        let s = CompanionStore(provider: StubProvider(value: dline(base: 1, rarity: rarity)),
                               clock: { clock.now }, fileURL: url, rng: SeededRNG(seed: 5))
        await s.hatch(baseID: 1)
        return (s, clock)
    }

    /// 활성 개체가 하나도 없으면(알 상태) 항상 .egg — 에너지·이벤트 창과 무관.
    func testEggWhenNoActiveCompanion() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-disp-\(UUID().uuidString).json")
        let s = CompanionStore(provider: StubProvider(value: dline(base: 1)),
                               clock: { dNow }, fileURL: url, rng: SeededRNG(seed: 1))
        s.tick()
        XCTAssertEqual(s.displayState, .egg)
    }

    /// hatch() 직후엔 tick 없이도 이미 .levelUp — hatch 가 직접 이벤트 창을 연다.
    func testLevelUpImmediatelyAfterHatch() async {
        let (s, _) = await hatchedStore()
        XCTAssertEqual(s.displayState, .levelUp)
    }

    /// 회귀(#4): 이벤트 창이 열려 있는 동안의 tick 은 .levelUp 을 유지해야 한다. 과거엔 표시 갱신이
    /// 매 갱신 초입에서 이벤트 관련 상태를 무조건 정리해, 창 도중 갱신이 끼면 .levelUp 이 조기에
    /// 풀렸다. 지금은 refreshLifecycle 이 만료 여부(clock() > eventUntil)만 보고 판단한다.
    func testLevelUpSurvivesATickWithinTheEventWindow() async {
        let (s, _) = await hatchedStore()
        s.tick()   // 시계 미전진 — 창이 아직 살아있다
        XCTAssertEqual(s.displayState, .levelUp)
    }

    /// 창이 끝나면(기본 에너지 100 ≥ 45) .idle 로 돌아간다.
    func testIdleAfterEventWindowExpires() async {
        let (s, clock) = await hatchedStore()
        clock.now = dNow.addingTimeInterval(10)   // hatch 가 연 4초 창을 넘긴다
        s.tick()
        XCTAssertEqual(s.displayState, .idle)
    }

    /// 이벤트 창이 없고 에너지가 20~44 구간이면 .sleep.
    func testSleepWhenEnergyIsModerate() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-disp-\(UUID().uuidString).json")
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":0,"#
            + #""rarity":"common","totalForms":3},"care":{"energy":30}}"#
        try Data(json.utf8).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: dline(base: 1)),
                               clock: { dNow }, fileURL: url, rng: SeededRNG(seed: 1))
        s.tick()
        XCTAssertEqual(s.displayState, .sleep)
    }

    /// 에너지가 20 미만이면 .tired — .sleep 보다 우선한다.
    func testTiredWhenEnergyIsLow() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-disp-\(UUID().uuidString).json")
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":0,"#
            + #""rarity":"common","totalForms":3},"care":{"energy":10}}"#
        try Data(json.utf8).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: dline(base: 1)),
                               clock: { dNow }, fileURL: url, rng: SeededRNG(seed: 1))
        s.tick()
        XCTAssertEqual(s.displayState, .tired)
    }

    // MARK: 알(egg) 인큐베이션 파생값

    func testEggProgressAndTokensToHatch() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-disp-\(UUID().uuidString).json")
        let s = CompanionStore(provider: StubProvider(value: dline(base: 1)),
                               clock: { dNow }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertTrue(s.isEgg)
        XCTAssertEqual(s.eggProgress, 0)
        XCTAssertEqual(s.eggTokensToHatch, PokemonBalance.eggHatchThreshold)

        // 임계의 40% 생산 — 방치 경제 전환 후 인큐베이션은 tick()/accrue 경로로만 쌓인다(displayState 갱신과는 별개).
        let part = PokemonBalance.eggHatchThreshold * 2 / 5
        s.debugAccrue(part)
        XCTAssertEqual(s.eggProgress, 0.4, accuracy: 0.001)
        XCTAssertEqual(s.eggTokensToHatch, PokemonBalance.eggHatchThreshold - part)
        XCTAssertTrue(s.eggStarted)
    }
}
