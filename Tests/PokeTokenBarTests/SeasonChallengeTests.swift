import XCTest
@testable import PokeTokenBar

// 시즌 순환 챌린지 — 달력 월마다 만료되고 갱신되는 기간 한정 목표.
// 콘텐츠는 저작하지 않는다: 세트 3개를 시즌 인덱스로 고르는 로테이션이라 서버도, 시즌마다 앱 업데이트도
// 필요 없다. 갱신은 자정 타이머가 아니라 `yyyy-MM` 키 비교이고, 재지급은 목표값 클램프가 막는다.
final class SeasonBoardTests: XCTestCase {

    private let season = "2026-08"
    private let nextSeason = "2026-09"

    private func challenge(_ event: MissionEvent, in key: String) -> SeasonChallenge {
        SeasonBoard.challenges(forSeasonKey: key).first { $0.event == event }!
    }

    private func ids(_ key: String) -> [String] {
        SeasonBoard.challenges(forSeasonKey: key).map(\.id)
    }

    // MARK: 로테이션 표 (조절 손잡이가 하나뿐인지)

    /// 세트마다 총액이 같아야 시즌 운에 따라 수입이 달라지지 않는다. 상한은 알 한 개(20,000⭐) —
    /// 넘으면 상점·판돈 경제가 시즌 하나로 흔들린다.
    func testEverySetPaysTheSameAndStaysUnderOneEgg() {
        let totals = SeasonBoard.rotation.map { $0.reduce(0) { $0 + $1.reward } }
        XCTAssertEqual(Set(totals).count, 1, "세트마다 총액이 다르면 시즌 운이 곧 수입 차이가 된다")
        for total in totals {
            XCTAssertLessThanOrEqual(total, FreshEgg.price(guaranteeing: nil))
        }
        XCTAssertTrue(SeasonBoard.rotation.allSatisfy { $0.allSatisfy { $0.target > 0 && $0.reward > 0 } })
    }

    /// 세트는 세 이벤트를 정확히 하나씩 다룬다 — 한 이벤트가 빠지면 그 시즌엔 그 축을 아무리 해도
    /// 채울 칸이 없고, 두 번 들어가면 한 정산이 같은 세트에서 두 칸을 민다.
    func testEverySetCoversEachEventExactlyOnce() {
        for (index, set) in SeasonBoard.rotation.enumerated() {
            XCTAssertEqual(set.count, 3, "세트 \(index)")
            for event in [MissionEvent.focusMinutes, .adventures, .graduations] {
                XCTAssertEqual(set.filter { $0.event == event }.count, 1, "세트 \(index) / \(event)")
            }
        }
    }

    /// id 는 진행도 사전의 키이자 무결성 canonical 의 일부다 — 한 세트 안에서 겹치면 두 챌린지가
    /// 서로를 덮어쓴다. 세트를 넘나드는 같은 id 는 허용하되 **목표·보상이 같아야** 한다:
    /// 다르면 정규화 클램프가 시즌마다 다른 값을 남긴다.
    func testChallengeIDsAreUniquePerSetAndConsistentAcrossSets() {
        var known: [String: (target: Int, reward: Int)] = [:]
        for set in SeasonBoard.rotation {
            XCTAssertEqual(Set(set.map(\.id)).count, set.count)
            for challenge in set {
                if let seen = known[challenge.id] {
                    XCTAssertEqual(seen.target, challenge.target, challenge.id)
                    XCTAssertEqual(seen.reward, challenge.reward, challenge.id)
                }
                known[challenge.id] = (challenge.target, challenge.reward)
            }
        }
    }

    // MARK: 시즌 선택 (콘텐츠 = 표가 아니라 공식)

    func testTheSameSeasonAlwaysGetsTheSameSet() {
        XCTAssertEqual(ids(season), ids(season))
    }

    /// 연속한 달은 서로 다른 세트를 받고, 로테이션 길이만큼 지나면 되돌아온다.
    /// 주기를 테스트에 못박아 둔다 — 세트를 더하면 여기가 먼저 실패해 주기가 늘어난 걸 알린다.
    func testConsecutiveSeasonsDifferAndCycleAtTheRotationLength() {
        let keys = ["2026-08", "2026-09", "2026-10", "2026-11"]
        let sets = keys.map(ids)
        XCTAssertEqual(SeasonBoard.rotation.count, 3, "주기가 바뀌면 아래 기대값도 함께 바뀐다")
        XCTAssertNotEqual(sets[0], sets[1])
        XCTAssertNotEqual(sets[1], sets[2])
        XCTAssertNotEqual(sets[0], sets[2])
        XCTAssertEqual(sets[3], sets[0], "로테이션 길이만큼 지나면 첫 세트로 돌아온다")
    }

    /// 12월 → 1월은 인덱스가 `year * 12` 를 넘는 유일한 경계다. 연도만 보고 계산하면 여기서 멈춘다.
    func testTheYearBoundaryAdvancesTheRotationByExactlyOne() {
        XCTAssertEqual(SeasonBoard.seasonIndex("2027-01") - SeasonBoard.seasonIndex("2026-12"), 1)
        XCTAssertNotEqual(ids("2026-12"), ids("2027-01"))
    }

    /// 빈 키·손상된 키도 세트를 돌려줘야 한다 — 새 세이브는 `seasonKey` 가 `""` 인 채로 시작하는데
    /// 표시 경로가 그 상태에서도 세트를 물어본다.
    func testUnparseableSeasonKeysFallBackToTheFirstSet() {
        for key in ["", "garbage", "2026", "abcd-08", "2026-13", "2026-00"] {
            XCTAssertEqual(SeasonBoard.seasonIndex(key), 0, key)
            XCTAssertEqual(ids(key), SeasonBoard.rotation[0].map(\.id), key)
        }
    }

    // MARK: 기록·완료

    func testRecordingBelowTargetCompletesNothing() {
        var board = SeasonBoard()
        let focus = challenge(.focusMinutes, in: season)
        XCTAssertTrue(board.record(.focusMinutes, 25, seasonKey: season).isEmpty)
        XCTAssertEqual(board.progress(focus, seasonKey: season), 25)
    }

    /// 한 이벤트는 그 이벤트의 칸만 민다 — 집중 정산이 졸업 칸까지 채우면 시즌이 하루에 끝난다.
    func testRecordingOnlyAdvancesItsOwnEvent() {
        var board = SeasonBoard()
        _ = board.record(.focusMinutes, 25, seasonKey: season)
        XCTAssertEqual(board.progress(challenge(.focusMinutes, in: season), seasonKey: season), 25)
        XCTAssertEqual(board.progress(challenge(.adventures, in: season), seasonKey: season), 0)
        XCTAssertEqual(board.progress(challenge(.graduations, in: season), seasonKey: season), 0)
    }

    /// 완료는 목표를 넘어서는 **순간 한 번**만 보고된다. 계속 기록해도 다시 나오면 이중 지급이 된다.
    func testCompletionFiresExactlyOnceEvenWhenOvershooting() {
        var board = SeasonBoard()
        let graduations = challenge(.graduations, in: season)

        let first = board.record(.graduations, graduations.target + 5, seasonKey: season)
        XCTAssertEqual(first.map(\.id), [graduations.id])

        let second = board.record(.graduations, 3, seasonKey: season)
        XCTAssertTrue(second.isEmpty, "이미 완료된 챌린지는 다시 완료되지 않는다")
        XCTAssertEqual(board.progress(graduations, seasonKey: season), graduations.target,
                       "진행도는 목표에서 클램프된다")
    }

    func testNonPositiveAmountsChangeNothing() {
        var board = SeasonBoard()
        _ = board.record(.adventures, 1, seasonKey: season)
        let before = board

        XCTAssertTrue(board.record(.adventures, 0, seasonKey: season).isEmpty)
        XCTAssertTrue(board.record(.adventures, -5, seasonKey: season).isEmpty)
        XCTAssertEqual(board, before, "0·음수 기록으로 되감기지 않는다")
    }

    // MARK: 시즌 갱신 (트리거 브랜치를 직접 밟는다)

    func testSeasonRolloverClearsProgress() {
        var board = SeasonBoard()
        _ = board.record(.adventures, 4, seasonKey: season)

        _ = board.record(.adventures, 1, seasonKey: nextSeason)

        XCTAssertEqual(board.progress(challenge(.adventures, in: nextSeason), seasonKey: nextSeason), 1,
                       "새 시즌엔 이번 달에 쌓은 것만 남는다")
    }

    /// 연말 경계도 같은 갱신을 밟는다 — 키 비교라 12월→1월도 다른 문자열이면 그만이다.
    func testTheYearBoundaryAlsoClearsProgress() {
        var board = SeasonBoard()
        _ = board.record(.adventures, 4, seasonKey: "2026-12")

        _ = board.record(.adventures, 1, seasonKey: "2027-01")

        XCTAssertEqual(board.progress(challenge(.adventures, in: "2027-01"), seasonKey: "2027-01"), 1)
    }

    /// 만료는 **읽는 순간** 보인다 — 아무 기록 없이 달이 바뀌어도 화면은 0을 보여야 한다.
    /// (표시 때문에 상태를 바꾸면 팝오버를 여는 것만으로 세이브가 더러워진다.)
    func testExpiredProgressReadsZeroWithoutMutating() {
        var board = SeasonBoard()
        _ = board.record(.adventures, 4, seasonKey: season)
        let snapshot = board

        XCTAssertEqual(board.progress(challenge(.adventures, in: nextSeason), seasonKey: nextSeason), 0)
        XCTAssertEqual(board, snapshot, "읽기만으로 상태가 바뀌면 안 된다")
    }

    // MARK: 경계 정규화 (손편집·구버전 방어)

    func testNormalizeDropsUnknownIDsAndClampsToTarget() {
        let focus = challenge(.focusMinutes, in: season)
        let adventures = challenge(.adventures, in: season)
        var board = SeasonBoard()
        board.seasonKey = season
        board.counts = [focus.id: 999_999, "ghostChallenge": 5, adventures.id: -3]

        board.normalize()

        XCTAssertEqual(board.counts[focus.id], focus.target)
        XCTAssertNil(board.counts["ghostChallenge"], "이번 시즌 세트에 없는 키는 버린다")
        XCTAssertEqual(board.counts[adventures.id], 0)
    }

    /// 클램프된 값은 곧 "완료 상태"라 재지급되지 않는다 — 손편집으로 목표를 넘겨도 이득이 없다.
    func testClampedProgressCannotBeCompletedAgain() {
        let focus = challenge(.focusMinutes, in: season)
        var board = SeasonBoard()
        board.seasonKey = season
        board.counts = [focus.id: 999_999]
        board.normalize()

        XCTAssertTrue(board.record(.focusMinutes, 100, seasonKey: season).isEmpty)
    }

    /// canonical 은 정렬돼야 한다 — 순회 순서에 기대면 같은 상태가 다른 해시를 내서 정상 세이브가
    /// 무작위로 조작 판정된다. 시즌 키도 들어가야 지난 시즌 진행도를 그대로 옮겨 붙이지 못한다.
    func testCanonicalIsSortedAndCarriesTheSeasonKey() {
        var forward = SeasonBoard()
        _ = forward.record(.focusMinutes, 25, seasonKey: season)
        _ = forward.record(.adventures, 1, seasonKey: season)

        var reversed = SeasonBoard()
        _ = reversed.record(.adventures, 1, seasonKey: season)
        _ = reversed.record(.focusMinutes, 25, seasonKey: season)

        XCTAssertEqual(forward.canonical, reversed.canonical)
        XCTAssertTrue(forward.canonical.contains(season))
        XCTAssertTrue(forward.canonical.contains("\(challenge(.adventures, in: season).id):1"))
    }

    // MARK: 남은 일수 (카드 헤더가 읽는 값)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// 오늘을 포함해 센다 — 말일에 0이 되면 "이미 끝난 시즌"으로 읽힌다.
    func testDaysRemainingCountsTodayAndBottomsOutAtOne() {
        XCTAssertEqual(SeasonBoard.daysRemaining(at: date(2026, 8, 1), calendar: utc), 31)
        XCTAssertEqual(SeasonBoard.daysRemaining(at: date(2026, 8, 20), calendar: utc), 12)
        XCTAssertEqual(SeasonBoard.daysRemaining(at: date(2026, 8, 31), calendar: utc), 1)
    }

    /// 달마다 길이가 다르다 — 30/31 을 상수로 박으면 2월에서 음수가 나온다.
    func testDaysRemainingFollowsTheLengthOfEachMonth() {
        XCTAssertEqual(SeasonBoard.daysRemaining(at: date(2024, 2, 1), calendar: utc), 29, "윤년")
        XCTAssertEqual(SeasonBoard.daysRemaining(at: date(2026, 2, 1), calendar: utc), 28, "평년")
        XCTAssertEqual(SeasonBoard.daysRemaining(at: date(2026, 4, 15), calendar: utc), 16, "30일 달")
    }

    // MARK: 문구

    /// 목표 이름은 세 언어 모두에서 채워져야 한다 — 한 언어만 비면 그 언어 사용자에겐 빈 줄이 보인다.
    func testEveryChallengeIsNamedInAllThreeLanguages() {
        for set in SeasonBoard.rotation {
            for challenge in set {
                for lang in [AppLanguage.ko, .en, .ja] {
                    XCTAssertFalse(L(lang).goalName(challenge.event, challenge.target).isEmpty,
                                   "\(challenge.id) / \(lang)")
                }
            }
        }
    }

    /// 미션 이름은 같은 함수에 위임한다 — 두 곳에 같은 문구를 두면 한쪽만 고쳐진다.
    func testMissionNamesDelegateToTheSharedGoalName() {
        for mission in MissionBoard.catalog {
            XCTAssertEqual(L(.ko).missionName(mission), L(.ko).goalName(mission.event, mission.target))
        }
    }

    /// 시즌 졸업 목표는 2~5 라 영어 단수 문구가 그대로면 "Graduate 3 partner" 가 된다.
    func testEnglishGraduationCopyMatchesTheTargetCount() {
        XCTAssertTrue(L(.en).goalName(.graduations, 1).hasSuffix("partner"))
        XCTAssertTrue(L(.en).goalName(.graduations, 3).hasSuffix("partners"))
    }
}

// MARK: 적립 경로 (스토어)

@MainActor
final class SeasonAccrualTests: XCTestCase {

    private let clock = TestClock()

    private var currentSeason: String { CompanionStore.seasonKey(clock.now) }

    private func challenge(_ event: MissionEvent) -> SeasonChallenge {
        SeasonBoard.challenges(forSeasonKey: currentSeason).first { $0.event == event }!
    }

    /// `seeding` 은 이번 시즌 진행도를 목표 근처에 앉히는 손잡이다. 시즌 목표는 한 달치라
    /// (집중 900~1,200분) 테스트에서 정직하게 채울 수 없다 — 마지막 한 걸음만 실제로 밟는다.
    private func makeStore(seeding progress: [String: Int] = [:], trainerPoints: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-season-\(UUID().uuidString).json")
        if !progress.isEmpty || trainerPoints > 0 {
            let counts = progress.map { "\"\($0.key)\":\($0.value)" }.sorted().joined(separator: ",")
            let json = #"{"economyVersion":2,"forcedResetVersion":1,"#
                + #""trainer":{"points":\#(trainerPoints)},"#
                + #""seasons":{"seasonKey":"\#(currentSeason)","counts":{\#(counts)}}}"#
            try? Data(json.utf8).write(to: url)
        }
        return CompanionStore(provider: StubProvider(value: seasonTestLine), clock: clock.closure,
                              fileURL: url, rng: SeededRNG(seed: 13))
    }

    private func hatchedStore(seeding progress: [String: Int] = [:],
                              trainerPoints: Int = 0) async -> CompanionStore {
        let store = makeStore(seeding: progress, trainerPoints: trainerPoints)
        await store.hatch(baseID: 1)
        XCTAssertNotNil(store.state.active, "테스트 전제: 활성 포켓몬이 있어야 모험을 보낼 수 있다")
        return store
    }

    private func progress(_ store: CompanionStore, _ id: String) -> Int {
        store.seasonRows.first { $0.challenge.id == id }?.progress ?? -1
    }

    /// 모험 정산 하나가 집중 분과 모험 횟수를 동시에 민다.
    func testClaimingAnAdventureAdvancesFocusAndAdventureChallenges() async {
        let store = await hatchedStore()

        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        XCTAssertNotNil(store.claimAdventure())

        XCTAssertEqual(progress(store, challenge(.focusMinutes).id), 25)
        XCTAssertEqual(progress(store, challenge(.adventures).id), 1)
        XCTAssertEqual(progress(store, challenge(.graduations).id), 0)
    }

    /// 정산되지 않은 모험은 기록도 없다 — 시작만으로 오르면 타이머를 켜 두는 것이 곧 진행이 된다.
    func testStartingAnAdventureAloneRecordsNothing() async {
        let store = await hatchedStore()
        XCTAssertTrue(store.startFocusAdventure(minutes: 90))
        clock.advance(10 * 60)
        XCTAssertNil(store.claimAdventure())

        XCTAssertEqual(progress(store, challenge(.focusMinutes).id), 0)
        XCTAssertEqual(progress(store, challenge(.adventures).id), 0)
    }

    /// 완료 보상은 별의조각으로, 챌린지당 한 번만 들어오고 보상 객체가 그 값을 보고한다.
    func testCompletedChallengePaysStarPiecesOnceAndReportsIt() async throws {
        let focus = challenge(.focusMinutes)
        let store = await hatchedStore(seeding: [focus.id: focus.target - 10])

        var before = store.state.starPieces
        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        let first = try XCTUnwrap(store.claimAdventure())

        XCTAssertEqual(first.seasonBonus, focus.reward, "목표를 넘긴 정산이 시즌 보상을 지급한다")
        // 같은 정산이 트레이너 레벨·미션·업적에도 지급한다 — 지갑 증가분은 보고된 값들의 합이어야 한다.
        XCTAssertEqual(store.state.starPieces - before,
                       first.starPieces + first.trainerBonus + first.missionBonus
                           + first.achievementBonus + first.seasonBonus)

        before = store.state.starPieces
        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        let second = try XCTUnwrap(store.claimAdventure())

        XCTAssertEqual(second.seasonBonus, 0, "완료된 챌린지는 재지급되지 않는다")
        XCTAssertEqual(progress(store, focus.id), focus.target)
    }

    /// 졸업 단독 경로 — 모험을 **한 번도 하지 않고** 졸업만 해도 시즌 챌린지가 완료된다.
    func testGraduationAloneCompletesTheSeasonGraduationChallenge() async {
        let graduations = challenge(.graduations)
        // 졸업은 트레이너 포인트·주간 미션에도 지급한다. 트레이너는 상한으로 묶고, 남는 증가분을
        // 주간 미션 + 시즌 보상의 합과 대조한다.
        let store = await hatchedStore(seeding: [graduations.id: graduations.target - 1],
                                       trainerPoints: TrainerLevel.maximumPoints)
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))
        XCTAssertNil(store.activeAdventure, "이 경로엔 모험이 전혀 없다")
        let before = store.state.starPieces
        let weeklyMission = MissionBoard.catalog.first { $0.id == "weeklyGraduation" }!.reward

        XCTAssertTrue(store.graduateCompanion())

        XCTAssertEqual(progress(store, graduations.id), graduations.target)
        XCTAssertEqual(store.state.starPieces - before, weeklyMission + graduations.reward,
                       "졸업만으로 시즌 보상이 들어온다")
    }

    /// 달이 바뀌면 진행도가 스스로 비고 세트도 교체된다.
    func testTheNextSeasonStartsEmpty() async {
        let store = await hatchedStore()
        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        XCTAssertNotNil(store.claimAdventure())
        let firstSeasonIDs = store.seasonRows.map(\.challenge.id)
        XCTAssertEqual(progress(store, challenge(.focusMinutes).id), 25)

        clock.advance(31 * 24 * 60 * 60)

        XCTAssertEqual(progress(store, challenge(.focusMinutes).id), 0,
                       "표시부터 새 시즌 기준으로 비어야 한다")
        XCTAssertNotEqual(store.seasonRows.map(\.challenge.id), firstSeasonIDs, "세트가 교체된다")
    }

    /// 카드 헤더가 읽는 값 — 시즌이 끝나기 전에는 항상 하루 이상 남아 있다.
    func testTheStoreReportsDaysLeftInTheCurrentSeason() async {
        let store = await hatchedStore()
        XCTAssertGreaterThanOrEqual(store.seasonDaysRemaining, 1)
        XCTAssertLessThanOrEqual(store.seasonDaysRemaining, 31)
    }
}

// MARK: 세이브 (하위호환·무결성)

final class SeasonSaveTests: XCTestCase {

    private let season = "2026-08"

    /// 시즌 필드가 없던 시절의 세이브는 빈 보드로 읽히고, 나머지 진행은 그대로 살아야 한다.
    func testLegacySaveWithoutSeasonsDecodesToAnEmptyBoard() throws {
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"starPieces":1234}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))

        XCTAssertEqual(state.seasons, SeasonBoard())
        XCTAssertEqual(state.starPieces, 1234, "새 필드 부재가 다른 진행을 날리지 않는다")
    }

    /// 기본값이면 canonical 문자열에 아무것도 붙지 않는다 — 기존 세이브의 서명이 그대로 유효해야 한다.
    /// 해시끼리 비교하면 **안 된다**: 무조건 append 로 바꿔도 양쪽이 똑같이 바뀌어 통과한다.
    func testDefaultSeasonsAddNothingToTheIntegrityCanonical() {
        XCTAssertFalse(SaveTransfer.canonicalString(CompanionState()).contains("|sn"))
        XCTAssertFalse(SaveTransfer.isTampered(SaveTransfer.signed(CompanionState())))
    }

    /// 가드가 실제로 지키는지 — 서명 후 진행도를 손으로 올리면 조작으로 잡혀야 한다.
    /// 이 테스트가 없으면 canonical 에서 시즌을 통째로 빼먹어도 아무도 모른다.
    func testEditingSeasonProgressAfterSigningIsDetected() {
        var state = CompanionState()
        _ = state.seasons.record(.adventures, 1, seasonKey: season)
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed))

        _ = signed.seasons.record(.adventures, 5, seasonKey: season)
        XCTAssertTrue(SaveTransfer.isTampered(signed), "진행도가 무결성 해시에 들어가 있어야 한다")
    }

    /// 지난 시즌의 완료 상태를 이번 시즌 키에 옮겨 붙이는 것도 서명이 막는다.
    func testEditingTheSeasonKeyAfterSigningIsDetected() {
        var state = CompanionState()
        _ = state.seasons.record(.adventures, 1, seasonKey: season)
        var signed = SaveTransfer.signed(state)

        signed.seasons.seasonKey = "2026-09"
        XCTAssertTrue(SaveTransfer.isTampered(signed), "시즌 키도 서명에 들어가 있어야 한다")
    }

    /// 경계에서 한 번만 정규화한다 — 손편집으로 넣은 거대한 값이 그대로 저장되면 재지급 대상이 된다.
    func testExtremeSeasonProgressIsClampedAtTheBoundary() {
        let focus = SeasonBoard.challenges(forSeasonKey: season).first { $0.event == .focusMinutes }!
        var state = CompanionState()
        state.seasons.seasonKey = season
        state.seasons.counts = [focus.id: Int.max, "ghostChallenge": 7]

        let sanitized = SaveTransfer.sanitized(state)

        XCTAssertEqual(sanitized.seasons.counts[focus.id], focus.target)
        XCTAssertNil(sanitized.seasons.counts["ghostChallenge"])
    }
}

// 부화용 최소 진화 라인(1 → 2 → 3).
private let seasonTestLine: EvoLine = {
    var names: [Int: [String: String]] = [:]
    for id in [1, 2, 3] { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: 1,
                   tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                   rarity: .common, names: names)
}()
