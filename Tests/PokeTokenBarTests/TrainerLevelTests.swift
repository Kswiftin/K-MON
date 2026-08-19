import XCTest
@testable import PokeTokenBar

// 트레이너 레벨 — 졸업해도 남는 유일한 성장 값.
// 파트너는 졸업하면 도감으로 가고 새 알부터 다시 시작하지만, 이 포인트는 계정에 남는다.
final class TrainerLevelTests: XCTestCase {

    // MARK: 레벨 곡선 (순수 로직)

    /// 도달선은 `25 × (n-1)²` — 25분 세션 한 번이면 2레벨이 되게 잡았다.
    /// 경계 바로 아래/위를 둘 다 확인한다(반올림으로 한 칸 밀리는 사고 방지).
    func testLevelBoundaries() {
        XCTAssertEqual(TrainerLevel(points: 0).level, 1)
        XCTAssertEqual(TrainerLevel(points: 24).level, 1)
        XCTAssertEqual(TrainerLevel(points: 25).level, 2)
        XCTAssertEqual(TrainerLevel(points: 99).level, 2)
        XCTAssertEqual(TrainerLevel(points: 100).level, 3)
        XCTAssertEqual(TrainerLevel(points: 2_025).level, 10)
        XCTAssertEqual(TrainerLevel(points: 9_025).level, 20)
    }

    /// 관대 디코드·손편집이 통과시킨 말이 안 되는 값이 레벨 계산을 깨뜨리면 안 된다.
    func testLevelClampsNegativeAndSaturatesAtMaximum() {
        XCTAssertEqual(TrainerLevel(points: -1).level, 1)
        XCTAssertEqual(TrainerLevel(points: Int.max / 2).level, TrainerLevel.maximumLevel)
        XCTAssertEqual(TrainerLevel(points: 240_100).level, TrainerLevel.maximumLevel)
    }

    func testLevelIsMonotonic() {
        var previous = 0
        for points in stride(from: 0, through: 12_000, by: 37) {
            let level = TrainerLevel(points: points).level
            XCTAssertGreaterThanOrEqual(level, previous)
            previous = level
        }
    }

    /// 한 번에 여러 레벨이 오를 수 있다 — 90분 모험이 낮은 레벨 구간에서 두 칸을 넘긴다.
    func testAddReturnsLevelsGained() {
        var trainer = TrainerLevel()
        XCTAssertEqual(trainer.add(24), 0, "경계 아래면 레벨은 그대로")
        XCTAssertEqual(trainer.add(1), 1, "25p 에서 2레벨")
        XCTAssertEqual(trainer.points, 25)

        var jumper = TrainerLevel(points: 20)
        XCTAssertEqual(jumper.add(90), 2, "20p(1레벨) → 110p(3레벨) = 두 칸")
    }

    func testAddIgnoresNonPositiveAmounts() {
        var trainer = TrainerLevel(points: 100)
        XCTAssertEqual(trainer.add(0), 0)
        XCTAssertEqual(trainer.add(-50), 0)
        XCTAssertEqual(trainer.points, 100, "음수 적립으로 되감기지 않는다")
    }

    /// 보상은 기존 재화(별의조각). 사탕 5,000·알 20,000 과 비교해 과하지 않은 규모여야 한다.
    func testLevelUpRewardIsModestAgainstShopPrices() {
        XCTAssertEqual(TrainerLevel.reward(forReaching: 2), 1_000)
        XCTAssertEqual(TrainerLevel.reward(forReaching: 10), 5_000)
        XCTAssertLessThan(TrainerLevel.reward(forReaching: 10), FreshEgg.price(guaranteeing: nil))
        XCTAssertGreaterThan(TrainerLevel.reward(forReaching: 3), TrainerLevel.reward(forReaching: 2))
    }

    func testProgressWithinLevel() {
        XCTAssertEqual(TrainerLevel(points: 25).progress, 0, accuracy: 0.001, "레벨 도달 직후는 0")
        let mid = TrainerLevel(points: 62)   // 2레벨 구간 25..<100
        XCTAssertGreaterThan(mid.progress, 0)
        XCTAssertLessThan(mid.progress, 1)
        XCTAssertEqual(TrainerLevel(points: 25).pointsToNextLevel, 75)
        XCTAssertNil(TrainerLevel(points: 240_100).pointsToNextLevel, "최고 레벨에는 다음이 없다")
        XCTAssertEqual(TrainerLevel(points: 240_100).progress, 1, accuracy: 0.001, "최고 레벨은 게이지가 가득 찬다")
    }
}

// MARK: 적립 경로

@MainActor
final class TrainerLevelAccrualTests: XCTestCase {

    /// 시작 포인트는 세이브 파일에 심는다 — `state` 세터는 비공개고, 테스트 편의로 그걸 열면
    /// 프로덕션에서도 상태를 통째로 갈아 끼울 수 있다.
    private func makeStore(_ clock: TestClock, trainerPoints: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-trainer-\(UUID().uuidString).json")
        if trainerPoints > 0 {
            let json = #"{"economyVersion":2,"forcedResetVersion":1,"trainer":{"points":\#(trainerPoints)}}"#
            try? Data(json.utf8).write(to: url)
        }
        return CompanionStore(provider: StubProvider(value: trainerTestLine), clock: clock.closure,
                              fileURL: url, rng: SeededRNG(seed: 11))
    }

    private func hatchedStore(_ clock: TestClock, trainerPoints: Int = 0) async -> CompanionStore {
        let store = makeStore(clock, trainerPoints: trainerPoints)
        await store.hatch(baseID: 1)
        XCTAssertNotNil(store.state.active, "테스트 전제: 활성 포켓몬이 있어야 모험을 보낼 수 있다")
        XCTAssertEqual(store.trainerLevel.points, trainerPoints, "시드 포인트가 로드돼야 한다")
        return store
    }

    /// 모험 정산 경로(A) — 정산된 분만큼 포인트가 오른다.
    func testClaimingAnAdventureAddsPointsEqualToItsMinutes() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        XCTAssertEqual(store.trainerLevel.points, 0)

        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        XCTAssertNotNil(store.claimAdventure())

        XCTAssertEqual(store.trainerLevel.points, 25)
        XCTAssertEqual(store.trainerLevel.level, 2)
    }

    /// 정산되지 않은 모험은 적립도 없다 — 시작만으로 오르면 타이머를 악용할 수 있다.
    func testStartingAnAdventureAloneAddsNothing() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        XCTAssertTrue(store.startFocusAdventure(minutes: 90))
        clock.advance(10 * 60)
        XCTAssertNil(store.claimAdventure(), "미완료 모험은 정산되지 않는다")
        XCTAssertEqual(store.trainerLevel.points, 0)
    }

    /// 졸업 경로(B) 단독 — 모험을 **한 번도 하지 않고** 졸업만 해도 오른다.
    /// `A || B` 게이트에서 B 만 참인 조건을 실제로 밟는다.
    func testGraduationAloneAddsPointsWithoutAnyAdventure() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))
        XCTAssertNil(store.activeAdventure, "이 경로엔 모험이 전혀 없다")

        XCTAssertTrue(store.graduateCompanion())

        XCTAssertEqual(store.trainerLevel.points, TrainerLevel.graduationPoints)
    }

    /// 이 마일스톤의 핵심 — 파트너가 도감으로 떠나도 트레이너 포인트는 남는다.
    func testPointsSurviveGraduation() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        XCTAssertNotNil(store.claimAdventure())
        let earned = store.trainerLevel.points

        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))
        XCTAssertTrue(store.graduateCompanion())

        XCTAssertNil(store.state.active, "졸업하면 파트너는 떠난다")
        XCTAssertGreaterThan(store.trainerLevel.points, earned, "포인트는 초기화되지 않고 오히려 늘어난다")
    }

    /// 레벨업 보상은 오른 레벨마다 지급되고 합산된다 — 두 칸을 한 번에 넘겨 검증.
    func testLevelUpPaysStarPiecesForEveryLevelGained() async throws {
        let clock = TestClock()
        let store = await hatchedStore(clock, trainerPoints: 20)   // 1레벨, 다음 도달선 25
        let before = store.state.starPieces

        XCTAssertTrue(store.startFocusAdventure(minutes: 90))
        clock.advance(90 * 60)
        let reward = try XCTUnwrap(store.claimAdventure())

        XCTAssertEqual(store.trainerLevel.level, 3, "20p + 90p = 110p → 3레벨")
        let bonus = TrainerLevel.reward(forReaching: 2) + TrainerLevel.reward(forReaching: 3)
        // 90분 정산은 일간 집중 미션(60분)도 함께 완료시킨다 — 지갑에는 그 몫도 들어온다.
        // 트레이너 지급액의 정확성은 아래 `reward.trainerBonus` 비교가 따로 잡는다.
        XCTAssertEqual(store.state.starPieces - before, reward.starPieces + bonus + reward.missionBonus,
                       "모험 보상 + 레벨 2·3 보상이 모두 들어와야 한다")
        XCTAssertEqual(reward.trainerBonus, bonus, "지급액을 보상 객체가 그대로 설명해야 한다")
    }

    /// 레벨이 안 오르면 보너스도 없다(모험 보상만).
    func testNoBonusWhenLevelDoesNotChange() async throws {
        let clock = TestClock()
        let store = await hatchedStore(clock, trainerPoints: 9_025)   // 20레벨, 다음 도달선 10,000
        let before = store.state.starPieces

        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        let reward = try XCTUnwrap(store.claimAdventure())

        XCTAssertEqual(store.trainerLevel.level, 20)
        XCTAssertEqual(store.state.starPieces - before, reward.starPieces, "레벨업이 없으면 모험 보상뿐")
        XCTAssertEqual(reward.trainerBonus, 0)
    }
}

// MARK: 세이브 (이전·무결성)

final class TrainerLevelSaveTests: XCTestCase {

    /// 트레이너 필드가 없던 시절의 세이브는 0으로 읽히고, 나머지 진행은 그대로 살아야 한다.
    func testLegacySaveWithoutTrainerDecodesToZero() throws {
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"starPieces":1234,"#
            + #""dex":[{"baseID":1,"finalID":3,"chainOrder":[1,2,3],"rarity":"common"}]}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))

        XCTAssertEqual(state.trainer.points, 0)
        XCTAssertEqual(state.starPieces, 1234, "새 필드 부재가 다른 진행을 날리지 않는다")
        XCTAssertEqual(state.dex.count, 1)
    }

    /// 기본값이면 canonical 문자열에 아무것도 붙지 않는다 — 기존 세이브의 서명이 그대로 유효해야 한다.
    /// (조건부 append 를 무조건 append 로 바꾸면 정상 세이브가 전부 조작 판정 → 진행 초기화된다.)
    func testDefaultTrainerKeepsLegacyIntegrityCanonicalForm() {
        var state = CompanionState()
        let before = SaveTransfer.integrityHash(state)
        state.trainer = TrainerLevel()
        XCTAssertEqual(SaveTransfer.integrityHash(state), before)
        XCTAssertFalse(SaveTransfer.isTampered(SaveTransfer.signed(state)))
    }

    /// 가드가 실제로 지키는지 — 서명 후 포인트를 손으로 올리면 조작으로 잡혀야 한다.
    /// 이 테스트가 없으면 canonical 에서 트레이너를 통째로 빼먹어도 아무도 모른다.
    func testEditingTrainerPointsAfterSigningIsDetected() {
        var state = CompanionState()
        state.trainer = TrainerLevel(points: 100)
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed))

        signed.trainer = TrainerLevel(points: 999_999)
        XCTAssertTrue(SaveTransfer.isTampered(signed), "포인트가 무결성 해시에 들어가 있어야 한다")
    }

    /// 경계에서 한 번만 정규화한다 — 손편집 거대값이 그대로 저장되면 이후 산술이 트랩이 된다.
    func testExtremeTrainerPointsAreClampedAtTheBoundary() {
        var state = CompanionState()
        state.trainer = TrainerLevel(points: Int.max)
        XCTAssertLessThanOrEqual(SaveTransfer.sanitized(state).trainer.points, SaveTransfer.maxTokenValue)

        state.trainer = TrainerLevel(points: -5_000)
        XCTAssertEqual(SaveTransfer.sanitized(state).trainer.points, 0)
    }
}

// 부화용 최소 진화 라인(1 → 2 → 3).
private let trainerTestLine: EvoLine = {
    var names: [Int: [String: String]] = [:]
    for id in [1, 2, 3] { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: 1,
                   tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                   rarity: .common, names: names)
}()
