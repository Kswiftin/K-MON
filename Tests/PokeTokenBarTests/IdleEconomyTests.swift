import XCTest
@testable import PokeTokenBar

/// 방치 경제 코어(tick) — 시간 → 별의모래 적립의 규칙을 고정한다.
/// 트리거 브랜치 지침(결함 프로토콜): 캡 초과·역행 시계·배율·알/활성 분기를 각각 단독으로 밟는다.
@MainActor
final class IdleEconomyTests: XCTestCase {

    private func tempURL() -> URL {
        storeStateURL("idle")
    }

    private func makeStore(_ clock: TestClock) -> CompanionStore {
        // linear3 등 공용 픽스처는 CompanionTests 에 있다 — 여기선 라인이 필요 없는 알 상태만 쓰므로
        // 부화가 일어나지 않도록 임계 미만 생산만 하거나, 라인 로드 실패 프로바이더를 쓴다.
        let store = CompanionStore(provider: NoLineProvider(), clock: clock.closure,
                                   fileURL: tempURL(), rng: SeededRNG(seed: 1))
        store.debugMarkStarterChosen()
        return store
    }

    /// 라인 제공 실패 — 알 유지(부화 억제)용. 적립 로직 자체는 라인과 무관하다.
    private struct NoLineProvider: PokeProviding {
        struct Unavailable: Error {}
        func line(baseSpeciesID: Int) async throws -> EvoLine { throw Unavailable() }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    }

    // MARK: 기준점·적립

    func testFirstTickSeedsWithoutAccruing() {
        let clock = TestClock()
        let s = makeStore(clock)
        s.tick()
        XCTAssertEqual(s.state.usedSinceInstall, 0, "첫 틱은 기준점만 — 설치 이전 시간 소급 금지")
        XCTAssertNotNil(s.state.lastTickAt)
    }

    func testTickAccruesElapsedTimesRate() {
        let clock = TestClock()
        let s = makeStore(clock)
        s.tick()                      // 시드
        clock.advance(60)
        s.tick()
        XCTAssertEqual(s.state.usedSinceInstall, 0, "생산 틱은 집중 세션 보상만 기록한다")
        XCTAssertEqual(s.state.activeSecondsTotal, 60, accuracy: 0.001)
    }

    // MARK: 캡 — 슬립/시계 점프 방어 (B 단독 브랜치)

    func testElapsedBeyondCapIsClamped() {
        let clock = TestClock()
        let s = makeStore(clock)
        s.tick()
        clock.advance(8 * 3600)       // 밤새 슬립
        s.tick()
        XCTAssertEqual(s.state.usedSinceInstall, 0)
        XCTAssertEqual(s.state.activeSecondsTotal, IdleEconomy.maxTickInterval, accuracy: 0.001)
    }

    func testBackwardClockAccruesNothingAndRebases() {
        let clock = TestClock()
        let s = makeStore(clock)
        s.tick()
        clock.advance(-3600)          // 시계 역행(수동 변경·NTP 보정)
        s.tick()
        XCTAssertEqual(s.state.usedSinceInstall, 0, "음수 경과는 0 으로 — 마이너스 적립 금지")
        clock.advance(60)
        s.tick()
        XCTAssertEqual(s.state.usedSinceInstall, 0)
        XCTAssertEqual(s.state.activeSecondsTotal, 60, accuracy: 0.001)
    }

    // MARK: 도감 배율

    func testProductionMultiplierGrowsWithUniqueFinals() {
        let clock = TestClock()
        let s = makeStore(clock)
        XCTAssertEqual(s.productionMultiplier, 1.0, accuracy: 0.0001)
        s.debugSetDex([
            DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: clock.now),
            DexEntry(baseID: 4, finalID: 6, chainOrder: [4, 5, 6], rarity: .common, caughtAt: clock.now),
            DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: clock.now),   // 중복 종
        ])
        XCTAssertEqual(s.productionMultiplier, 1.0 + 2 * IdleEconomy.dexBonusPerSpecies, accuracy: 0.0001,
                       "고유 최종체 기준 — 같은 종 중복 포획은 배율에 안 잡힌다")
        s.tick()
        clock.advance(100)
        s.tick()
        XCTAssertEqual(s.state.usedSinceInstall, 0)
        XCTAssertEqual(s.state.activeSecondsTotal, 100, accuracy: 0.001)
    }

    // MARK: 일일 사탕

    func testDailyCandyGrantedOncePerLocalDate() {
        let clock = TestClock()
        let s = makeStore(clock)
        s.tick()
        XCTAssertEqual(s.itemCount(.rareCandy), RareCandy.dailyGrant, "첫 틱 = 웰컴 사탕")
        clock.advance(3600)
        s.tick()
        XCTAssertEqual(s.itemCount(.rareCandy), RareCandy.dailyGrant, "같은 날짜 재지급 금지")
        clock.advance(24 * 3600)
        s.tick()
        XCTAssertEqual(s.itemCount(.rareCandy), RareCandy.dailyGrant * 2, "날짜가 바뀐 첫 틱에 재지급")
    }

    // MARK: 구세이브 마이그레이션 (경제 v0 → v2)

    func testTokenEraSaveResetsButKeepsCollection() {
        var old = CompanionState()
        old.economyVersion = 0
        old.usedSinceInstall = 999_000_000
        old.spentTokens = 100
        old.eggUsage = 4_000_000
        old.inventory = [ItemKind.rareCandy.rawValue: 7]
        old.dex = [DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: nil)]
        old.collectedFinals = ["1:3"]
        old.language = .ja
        let migrated = SaveTransfer.migratedToIdleEconomy(old)
        XCTAssertEqual(migrated.economyVersion, IdleEconomy.currentVersion)
        XCTAssertEqual(migrated.usedSinceInstall, 0)
        XCTAssertEqual(migrated.spentTokens, 0)
        XCTAssertEqual(migrated.eggUsage, 0)
        XCTAssertNil(migrated.active)
        XCTAssertTrue(migrated.inventory.isEmpty, "인벤토리도 새로 시작(전면 리셋 결정)")
        XCTAssertEqual(migrated.dex.count, 1, "도감은 계승")
        XCTAssertEqual(migrated.collectedFinals, ["1:3"], "수집(확률 가중)도 계승")
        XCTAssertEqual(migrated.language, .ja, "언어도 계승")
    }

    func testCurrentVersionSavePassesThroughUntouched() {
        var cur = CompanionState()
        cur.usedSinceInstall = 42
        let out = SaveTransfer.migratedToIdleEconomy(cur)
        XCTAssertEqual(out.usedSinceInstall, 42, "현행 버전은 마이그레이션 무개입")
    }

    /// 마이그레이션이 로드 경계(sanitized)에 실제로 물려 있는지 — 우회 경로 방지.
    func testSanitizedAppliesMigration() {
        var old = CompanionState()
        old.economyVersion = 0
        old.usedSinceInstall = 500
        let out = SaveTransfer.sanitized(old)
        XCTAssertEqual(out.economyVersion, IdleEconomy.currentVersion)
        XCTAssertEqual(out.usedSinceInstall, 0)
    }

    /// 구버전 세이브 JSON(economyVersion 키 없음)이 디코드에서 v0 으로 남는지 — 키 기본값이
    /// currentVersion 으로 잘못 잡히면 구세이브가 리셋 없이 토큰 값 그대로 통과한다.
    func testDecodeWithoutEconomyVersionDefaultsToZero() throws {
        let json = #"{"usedSinceInstall": 123, "dex": []}"#
        let decoded = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.economyVersion, 0)
        XCTAssertEqual(decoded.usedSinceInstall, 123, "마이그레이션 전 원값 유지(리셋은 sanitized 몫)")
    }

    // MARK: 기기 이전

    func testRebaseResetsTickBaselineAndKeepsNewerCandyDate() {
        var imported = CompanionState()
        imported.lastTickAt = Date(timeIntervalSince1970: 1_000)
        imported.lastCandyDate = "2026-08-10"
        var current = CompanionState()
        current.lastCandyDate = "2026-08-13"
        let out = SaveTransfer.rebasedForThisDevice(imported, current: current)
        XCTAssertNil(out.lastTickAt, "옛 기기 시각을 이 기기 가동 시간으로 오인하지 않게 리셋")
        XCTAssertEqual(out.lastCandyDate, "2026-08-13", "더 최근 날짜를 남겨 사탕 재지급 방지")
    }
}
