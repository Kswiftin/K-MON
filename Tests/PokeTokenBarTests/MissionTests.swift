import XCTest
@testable import PokeTokenBar

// 일간·주간 미션 — 정해진 주기로 갱신되는 반복 목표.
// 갱신은 자정 타이머가 아니라 키 비교다(모험 주간 카운터와 같은 방식): 날짜/주 키가 바뀐 첫 기록에서
// 해당 주기만 비운다. 완료 보상은 그 순간 자동 지급되고, 진행도를 목표에서 클램프해 재지급을 막는다.
final class MissionBoardTests: XCTestCase {

    private let day = "2026-08-18"
    private let nextDay = "2026-08-19"
    private let week = "2026-W34"
    private let nextWeek = "2026-W35"

    private func mission(_ id: String) -> Mission {
        MissionBoard.catalog.first { $0.id == id }!
    }

    // MARK: 카탈로그

    /// 보상은 기존 재화(별의조각)다. 주간 상한이 알 한 개(20,000⭐)를 넘으면 상점 경제가 무너진다.
    func testCatalogRewardsStayUnderOneEggPerWeek() {
        let weeklyCeiling = MissionBoard.catalog.reduce(0) { total, mission in
            total + mission.reward * (mission.period == .daily ? 7 : 1)
        }
        XCTAssertLessThan(weeklyCeiling, FreshEgg.price(guaranteeing: nil))
        XCTAssertTrue(MissionBoard.catalog.allSatisfy { $0.target > 0 && $0.reward > 0 })
    }

    /// id 는 진행도 사전의 키이자 무결성 canonical 의 일부다 — 중복되면 두 미션이 서로를 덮어쓴다.
    func testCatalogIDsAreUnique() {
        XCTAssertEqual(Set(MissionBoard.catalog.map(\.id)).count, MissionBoard.catalog.count)
    }

    /// 미션 이름은 세 언어 모두에서 채워져야 한다 — 한 언어만 비면 그 언어 사용자에겐 빈 줄이 보인다.
    func testEveryMissionIsNamedInAllThreeLanguages() {
        for mission in MissionBoard.catalog {
            for lang in [AppLanguage.ko, .en, .ja] {
                XCTAssertFalse(L(lang).missionName(mission).isEmpty, "\(mission.id) / \(lang)")
            }
        }
    }

    // MARK: 기록·완료

    func testRecordingBelowTargetCompletesNothing() {
        var board = MissionBoard()
        XCTAssertTrue(board.record(.focusMinutes, 25, dayKey: day, weekKey: week).isEmpty)
        XCTAssertEqual(board.progress(mission("dailyFocus"), dayKey: day, weekKey: week), 25)
    }

    /// 한 이벤트가 일간·주간 미션을 동시에 민다 — 25분 정산은 두 집중 미션 모두에 들어간다.
    func testOneEventAdvancesBothDailyAndWeeklyMissions() {
        var board = MissionBoard()
        _ = board.record(.focusMinutes, 25, dayKey: day, weekKey: week)
        XCTAssertEqual(board.progress(mission("dailyFocus"), dayKey: day, weekKey: week), 25)
        XCTAssertEqual(board.progress(mission("weeklyFocus"), dayKey: day, weekKey: week), 25)
    }

    /// 완료는 목표를 **넘어서는 순간 한 번**만 보고된다. 계속 기록해도 다시 나오면 이중 지급이 된다.
    func testCompletionFiresExactlyOnceEvenWhenOvershooting() {
        var board = MissionBoard()
        let first = board.record(.focusMinutes, 90, dayKey: day, weekKey: week)
        XCTAssertEqual(first.map(\.id), ["dailyFocus"], "60분 목표를 처음 넘긴 순간에만 완료")

        let second = board.record(.focusMinutes, 90, dayKey: day, weekKey: week)
        XCTAssertFalse(second.contains { $0.id == "dailyFocus" }, "이미 완료된 미션은 다시 완료되지 않는다")
        XCTAssertEqual(board.progress(mission("dailyFocus"), dayKey: day, weekKey: week),
                       mission("dailyFocus").target, "진행도는 목표에서 클램프된다")
    }

    func testCompletionReportsEveryMissionCrossedByOneEvent() {
        var board = MissionBoard()
        _ = board.record(.focusMinutes, 280, dayKey: day, weekKey: week)   // 일간 완료, 주간 280/300
        let completed = board.record(.focusMinutes, 25, dayKey: day, weekKey: week)
        XCTAssertEqual(completed.map(\.id), ["weeklyFocus"])
    }

    func testNonPositiveAmountsChangeNothing() {
        var board = MissionBoard()
        _ = board.record(.adventures, 1, dayKey: day, weekKey: week)
        let before = board
        XCTAssertTrue(board.record(.adventures, 0, dayKey: day, weekKey: week).isEmpty)
        XCTAssertTrue(board.record(.adventures, -5, dayKey: day, weekKey: week).isEmpty)
        XCTAssertEqual(board, before, "0·음수 기록으로 되감기지 않는다")
    }

    // MARK: 주기 갱신 (트리거 브랜치를 각각 밟는다)

    /// 날짜가 바뀌면 일간만 비운다. 주간까지 같이 비우면 주간 목표가 매일 초기화돼 도달 불가능해진다.
    func testDayRolloverClearsDailyButKeepsWeekly() {
        var board = MissionBoard()
        _ = board.record(.focusMinutes, 50, dayKey: day, weekKey: week)

        _ = board.record(.focusMinutes, 10, dayKey: nextDay, weekKey: week)

        XCTAssertEqual(board.progress(mission("dailyFocus"), dayKey: nextDay, weekKey: week), 10,
                       "일간은 새 날짜에 쌓은 것만 남는다")
        XCTAssertEqual(board.progress(mission("weeklyFocus"), dayKey: nextDay, weekKey: week), 60,
                       "주간은 날짜가 바뀌어도 이어진다")
    }

    /// 주가 바뀌면 주간만 비운다. 같은 날 안에서 주 경계가 넘어가는 경우를 직접 밟는다.
    func testWeekRolloverClearsWeeklyButKeepsDaily() {
        var board = MissionBoard()
        _ = board.record(.focusMinutes, 50, dayKey: day, weekKey: week)

        _ = board.record(.focusMinutes, 10, dayKey: day, weekKey: nextWeek)

        XCTAssertEqual(board.progress(mission("weeklyFocus"), dayKey: day, weekKey: nextWeek), 10)
        XCTAssertEqual(board.progress(mission("dailyFocus"), dayKey: day, weekKey: nextWeek), 60)
    }

    /// 만료는 **읽는 순간** 보인다 — 아무 기록 없이 날이 바뀌어도 화면은 0을 보여야 한다.
    /// (표시 때문에 상태를 바꾸면 팝오버를 여는 것만으로 세이브가 더러워진다.)
    func testExpiredProgressReadsZeroWithoutMutating() {
        var board = MissionBoard()
        _ = board.record(.focusMinutes, 50, dayKey: day, weekKey: week)
        let snapshot = board

        XCTAssertEqual(board.progress(mission("dailyFocus"), dayKey: nextDay, weekKey: week), 0)
        XCTAssertEqual(board, snapshot, "읽기만으로 상태가 바뀌면 안 된다")
    }

    // MARK: 경계 정규화 (손편집·구버전 방어)

    func testNormalizeDropsUnknownIDsAndClampsToTarget() {
        var board = MissionBoard()
        board.dayKey = day
        board.daily = ["dailyFocus": 999_999, "someRemovedMission": 5, "dailyAdventures": -3]
        board.normalize()

        XCTAssertEqual(board.daily["dailyFocus"], mission("dailyFocus").target)
        XCTAssertNil(board.daily["someRemovedMission"], "카탈로그에 없는 키는 버린다")
        XCTAssertEqual(board.daily["dailyAdventures"], 0)
    }

    /// 클램프된 값은 곧 "완료 상태"라 재지급되지 않는다 — 손편집으로 목표를 넘겨도 이득이 없다.
    func testClampedProgressCannotBeCompletedAgain() {
        var board = MissionBoard()
        board.dayKey = day
        board.daily = ["dailyFocus": 999_999]
        board.normalize()

        XCTAssertTrue(board.record(.focusMinutes, 100, dayKey: day, weekKey: week).isEmpty)
    }

    /// canonical 은 정렬돼야 한다 — 순회 순서에 기대면 같은 상태가 다른 해시를 내서 무작위로 조작 판정된다.
    func testCanonicalIsSortedAndStable() {
        var forward = MissionBoard()
        _ = forward.record(.focusMinutes, 25, dayKey: day, weekKey: week)
        _ = forward.record(.adventures, 1, dayKey: day, weekKey: week)

        var reversed = MissionBoard()
        _ = reversed.record(.adventures, 1, dayKey: day, weekKey: week)
        _ = reversed.record(.focusMinutes, 25, dayKey: day, weekKey: week)

        XCTAssertEqual(forward.canonical, reversed.canonical)
        XCTAssertTrue(forward.canonical.contains("dailyAdventures:1"))
        XCTAssertTrue(forward.canonical.contains(day))
    }
}

// MARK: 적립 경로 (스토어)

@MainActor
final class MissionAccrualTests: XCTestCase {

    /// `trainerPoints` 는 미션 보상만 떼어 보기 위한 손잡이다. 모험 정산·졸업은 미션과 트레이너
    /// 레벨 **양쪽**에 지급하므로, 지갑 증가분만 보면 어느 쪽 몫인지 구분되지 않는다. 상한값으로
    /// 시드하면 트레이너는 더 오를 곳이 없어 0을 지급하고, 남는 증가분이 곧 미션 보상이다.
    private func makeStore(_ clock: TestClock, trainerPoints: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-mission-\(UUID().uuidString).json")
        if trainerPoints > 0 {
            let json = #"{"economyVersion":2,"forcedResetVersion":1,"trainer":{"points":\#(trainerPoints)}}"#
            try? Data(json.utf8).write(to: url)
        }
        return CompanionStore(provider: StubProvider(value: missionTestLine), clock: clock.closure,
                              fileURL: url, rng: SeededRNG(seed: 11))
    }

    private func hatchedStore(_ clock: TestClock, trainerPoints: Int = 0) async -> CompanionStore {
        let store = makeStore(clock, trainerPoints: trainerPoints)
        await store.hatch(baseID: 1)
        XCTAssertNotNil(store.state.active, "테스트 전제: 활성 포켓몬이 있어야 모험을 보낼 수 있다")
        return store
    }

    private func progress(_ store: CompanionStore, _ id: String) -> Int {
        store.missionRows.first { $0.mission.id == id }?.progress ?? -1
    }

    /// 모험 정산 하나가 집중 분과 모험 횟수를 동시에 민다.
    func testClaimingAnAdventureAdvancesFocusAndAdventureMissions() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)

        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        XCTAssertNotNil(store.claimAdventure())

        XCTAssertEqual(progress(store, "dailyFocus"), 25)
        XCTAssertEqual(progress(store, "dailyAdventures"), 1)
        XCTAssertEqual(progress(store, "weeklyFocus"), 25)
    }

    /// 정산되지 않은 모험은 기록도 없다 — 시작만으로 오르면 타이머를 켜 두는 것이 곧 미션 진행이 된다.
    func testStartingAnAdventureAloneRecordsNothing() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        XCTAssertTrue(store.startFocusAdventure(minutes: 90))
        clock.advance(10 * 60)
        XCTAssertNil(store.claimAdventure())

        XCTAssertEqual(progress(store, "dailyFocus"), 0)
        XCTAssertEqual(progress(store, "dailyAdventures"), 0)
    }

    /// 완료 보상은 별의조각으로, 미션당 한 번만 들어온다.
    func testCompletedMissionPaysStarPiecesOnce() async throws {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        let dailyFocus = MissionBoard.catalog.first { $0.id == "dailyFocus" }!
        let dailyAdventures = MissionBoard.catalog.first { $0.id == "dailyAdventures" }!

        var before = store.state.starPieces
        XCTAssertTrue(store.startFocusAdventure(minutes: 90))
        clock.advance(90 * 60)
        let first = try XCTUnwrap(store.claimAdventure())
        XCTAssertEqual(first.missionBonus, dailyFocus.reward, "90분 정산으로 일간 집중 미션이 완료된다")
        // 같은 정산이 트레이너 레벨도 올린다 — 지갑 증가분은 두 지급의 합이다.
        XCTAssertEqual(store.state.starPieces - before,
                       first.starPieces + first.trainerBonus + first.missionBonus
                           + first.achievementBonus)

        before = store.state.starPieces
        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        let second = try XCTUnwrap(store.claimAdventure())
        XCTAssertEqual(second.missionBonus, dailyAdventures.reward,
                       "두 번째 정산으로는 모험 횟수 미션만 완료된다 — 집중 미션은 재지급되지 않는다")
        XCTAssertEqual(store.state.starPieces - before,
                       second.starPieces + second.trainerBonus + second.missionBonus
                           + second.achievementBonus)
    }

    /// 졸업 단독 경로 — 모험을 **한 번도 하지 않고** 졸업만 해도 주간 미션이 완료된다.
    func testGraduationAloneCompletesTheWeeklyGraduationMission() async {
        let clock = TestClock()
        // 졸업은 트레이너 포인트도 적립한다. 상한으로 시드해 그쪽 지급을 0으로 묶고 미션 몫만 남긴다.
        let store = await hatchedStore(clock, trainerPoints: TrainerLevel.maximumPoints)
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))
        XCTAssertNil(store.activeAdventure, "이 경로엔 모험이 전혀 없다")
        let before = store.state.starPieces
        let reward = MissionBoard.catalog.first { $0.id == "weeklyGraduation" }!.reward

        XCTAssertTrue(store.graduateCompanion())

        XCTAssertEqual(progress(store, "weeklyGraduation"), 1)
        XCTAssertEqual(store.state.starPieces - before, reward,
                       "졸업만으로 주간 미션 보상이 들어온다")
    }

    /// 날이 바뀌면 일간 진행도가 스스로 비고 다시 완료할 수 있다.
    func testDailyMissionsRefreshOnTheNextDay() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        XCTAssertNotNil(store.claimAdventure())
        XCTAssertEqual(progress(store, "dailyFocus"), 25)

        clock.advance(24 * 60 * 60)

        XCTAssertEqual(progress(store, "dailyFocus"), 0, "표시부터 새 날짜 기준으로 비어야 한다")
        XCTAssertEqual(progress(store, "weeklyFocus"), 25, "주간은 이어진다")
    }
}

// MARK: 세이브 (하위호환·무결성)

final class MissionSaveTests: XCTestCase {

    /// 미션 필드가 없던 시절의 세이브는 빈 보드로 읽히고, 나머지 진행은 그대로 살아야 한다.
    func testLegacySaveWithoutMissionsDecodesToEmptyBoard() throws {
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"starPieces":1234}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))

        XCTAssertEqual(state.missions, MissionBoard())
        XCTAssertEqual(state.starPieces, 1234, "새 필드 부재가 다른 진행을 날리지 않는다")
    }

    /// 기본값이면 canonical 문자열에 아무것도 붙지 않는다 — 기존 세이브의 서명이 그대로 유효해야 한다.
    /// (조건부 append 를 무조건 append 로 바꾸면 정상 세이브가 전부 조작 판정 → 진행 초기화된다.)
    ///
    /// 해시끼리 비교하면 **안 된다**: 기본값 상태를 자기 자신과 대조하게 돼 무조건 append 로 바꿔도
    /// 양쪽이 똑같이 바뀌어 통과한다. 조각이 실제로 없는지를 문자열에서 직접 본다.
    func testDefaultMissionsAddNothingToTheIntegrityCanonical() {
        XCTAssertFalse(SaveTransfer.canonicalString(CompanionState()).contains("|ms"))
        XCTAssertFalse(SaveTransfer.isTampered(SaveTransfer.signed(CompanionState())))
    }

    /// 가드가 실제로 지키는지 — 서명 후 진행도를 손으로 올리면 조작으로 잡혀야 한다.
    /// 이 테스트가 없으면 canonical 에서 미션을 통째로 빼먹어도 아무도 모른다.
    func testEditingMissionProgressAfterSigningIsDetected() {
        var state = CompanionState()
        _ = state.missions.record(.focusMinutes, 10, dayKey: "2026-08-18", weekKey: "2026-W34")
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed))

        _ = signed.missions.record(.focusMinutes, 20, dayKey: "2026-08-18", weekKey: "2026-W34")
        XCTAssertTrue(SaveTransfer.isTampered(signed), "진행도가 무결성 해시에 들어가 있어야 한다")
    }

    /// 경계에서 한 번만 정규화한다 — 손편집으로 넣은 거대한 값이 그대로 저장되면 재지급 대상이 된다.
    func testExtremeMissionProgressIsClampedAtTheBoundary() {
        var state = CompanionState()
        state.missions.dayKey = "2026-08-18"
        state.missions.daily = ["dailyFocus": Int.max, "ghostMission": 7]

        let sanitized = SaveTransfer.sanitized(state)

        XCTAssertEqual(sanitized.missions.daily["dailyFocus"],
                       MissionBoard.catalog.first { $0.id == "dailyFocus" }!.target)
        XCTAssertNil(sanitized.missions.daily["ghostMission"])
    }
}

// 부화용 최소 진화 라인(1 → 2 → 3).
private let missionTestLine: EvoLine = {
    var names: [Int: [String: String]] = [:]
    for id in [1, 2, 3] { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: 1,
                   tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                   rarity: .common, names: names)
}()
