import XCTest
@testable import PokeTokenBar

// 업적 사다리 — 집중·진화·배틀·레이스 네 트랙에 각 4단계 문턱.
//
// 세이브에는 카운터 사전 하나만 담고 도달 단계는 계산한다. "이번에 넘은 문턱" 만 반환하니
// 재지급 기억이 필요 없다(`TrainerLevel.add` 와 같은 계약).
// 체육관 배지(`state.gymBadges`)와 층이 다르다 — 그쪽은 컨텐츠 첫 승리, 이쪽은 누적 행동이다.
final class AchievementLadderTests: XCTestCase {

    private func achievement(_ track: AchievementTrack) -> Achievement {
        AchievementLadder.catalog.first { $0.track == track }!
    }

    // MARK: 카탈로그

    /// 트랙마다 정확히 한 칸 — 두 개면 서로의 카운터를 덮고, 없으면 그 트랙이 조용히 죽는다.
    func testCatalogCoversEveryTrackExactlyOnce() {
        XCTAssertEqual(AchievementLadder.catalog.map(\.track).sorted { $0.rawValue < $1.rawValue },
                       AchievementTrack.allCases.sorted { $0.rawValue < $1.rawValue })
    }

    /// id 는 진행도 사전의 키이자 무결성 canonical 의 일부다 — 중복되면 두 업적이 서로를 덮어쓴다.
    func testCatalogIDsAreUnique() {
        XCTAssertEqual(Set(AchievementLadder.catalog.map(\.id)).count, AchievementLadder.catalog.count)
    }

    /// 문턱은 오름차순이어야 한다. 뒤섞이면 "도달 단계 수"와 "다음 문턱"이 서로 다른 칸을 가리킨다.
    func testCatalogTiersAscendAndPairWithRewards() {
        for entry in AchievementLadder.catalog {
            XCTAssertFalse(entry.tiers.isEmpty, "\(entry.id) 에 문턱이 하나도 없다")
            XCTAssertEqual(entry.tiers, entry.tiers.sorted(), "\(entry.id) 문턱이 오름차순이 아니다")
            XCTAssertTrue(entry.tiers.allSatisfy { $0 > 0 })
            // 보상은 `rewards[tier - 1]` 로 꺼낸다 — 길이가 어긋나면 그 자리에서 인덱스 범위를 넘는다.
            XCTAssertEqual(entry.rewards.count, entry.tiers.count, "\(entry.id) 보상 개수가 문턱과 다르다")
            XCTAssertTrue(entry.rewards.allSatisfy { $0 > 0 }, "\(entry.id) 에 0원 단계가 있다")
        }
    }

    /// 1단계는 **첫날에 닿아야** 한다 — 사다리는 첫 칸이 보여야 오른다.
    /// 25분 모험 한 번(집중 25분·진화 1·배틀 1·레이스 1) 안쪽이 기준선이다.
    func testTheFirstTierIsReachableOnDayOne() {
        XCTAssertLessThanOrEqual(achievement(.focus).tiers[0], 60)
        for track in [AchievementTrack.evolve, .battle, .race] {
            XCTAssertLessThanOrEqual(achievement(track).tiers[0], 3, "\(track) 첫 칸이 너무 멀다")
        }
    }

    /// 평생 총액이 알 세 개를 넘으면 상점·판돈 경제가 흔들린다. 조절 손잡이는 카탈로그 표 하나뿐이다.
    /// (미션은 주당 상한이 기준이었지만 업적은 **평생 1회**라 총액으로 잰다.)
    func testLifetimeRewardsStayUnderThreeEggs() {
        let lifetime = AchievementLadder.catalog.reduce(0) { $0 + $1.rewards.reduce(0, +) }
        XCTAssertLessThan(lifetime, FreshEgg.price(guaranteeing: nil) * 3)
    }

    /// 업적 이름은 세 언어 모두 채워져야 한다 — 한 언어만 비면 그 사용자에겐 빈 줄이 보인다.
    /// 트랙 추가는 `achievementName` 의 exhaustive switch 가 컴파일에서 막으니, 여기서 잡는 건
    /// `t()` 인자 하나를 빈 문자열로 두고 넘어가는 경우다.
    func testEveryTrackIsNamedInAllThreeLanguages() {
        for track in AchievementTrack.allCases {
            for lang in [AppLanguage.ko, .en, .ja] {
                XCTAssertFalse(L(lang).achievementName(track).isEmpty, "\(track) / \(lang)")
            }
        }
    }

    // MARK: 기록 · 단계 통과

    func testRecordingBelowTheFirstTierCrossesNothing() {
        var ladder = AchievementLadder()
        XCTAssertTrue(ladder.record(.focus, 25).isEmpty)
        XCTAssertEqual(ladder.count(.focus), 25)
        XCTAssertEqual(ladder.tier(.focus), 0)
    }

    /// 트랙은 서로 독립이다 — 집중을 쌓아도 배틀 카운터는 움직이지 않는다.
    /// (혼자 쓰는 사용자가 배틀 업적에서 막혀도 사다리 전체가 멈추지 않는 근거.)
    func testTracksAdvanceIndependently() {
        var ladder = AchievementLadder()
        _ = ladder.record(.focus, 60)
        XCTAssertEqual(ladder.count(.focus), 60)
        for track in [AchievementTrack.evolve, .battle, .race] {
            XCTAssertEqual(ladder.count(track), 0, "\(track) 가 딸려 올라갔다")
        }
    }

    /// 문턱을 **넘어서는 순간 한 번**만 보고된다. 계속 기록해도 다시 나오면 이중 지급이 된다.
    func testATierIsReportedExactlyOnceEvenWhenOvershooting() {
        var ladder = AchievementLadder()
        let first = ladder.record(.evolve, achievement(.evolve).tiers[0])
        XCTAssertEqual(first.map(\.tier), [1])

        let second = ladder.record(.evolve, 1)
        XCTAssertTrue(second.isEmpty, "이미 넘은 단계가 다시 보고되면 이중 지급이 된다")
        XCTAssertEqual(ladder.tier(.evolve), 1)
    }

    /// 한 번에 두 단계를 넘기면 **둘 다** 보고돼야 한다 — 마지막 하나만 주면 그만큼이 손실된다.
    func testCrossingTwoTiersAtOnceReportsBoth() {
        var ladder = AchievementLadder()
        let tiers = achievement(.focus).tiers

        let crossed = ladder.record(.focus, tiers[1])

        XCTAssertEqual(crossed.map(\.tier), [1, 2], "\(tiers[1])분 한 방으로 1·2단계를 함께 넘는다")
        XCTAssertEqual(ladder.tier(.focus), 2)
    }

    /// 마지막 문턱에서 카운터가 클램프된다 — 그 상한이 곧 재지급 차단이다.
    func testCountsClampAtTheLastTierAndPayNoMore() {
        var ladder = AchievementLadder()
        let ceiling = achievement(.race).tiers.last!

        let crossed = ladder.record(.race, ceiling * 10)
        XCTAssertEqual(crossed.map(\.tier), Array(1...achievement(.race).tiers.count))
        XCTAssertEqual(ladder.count(.race), ceiling, "카운터가 마지막 문턱을 넘어 자라면 안 된다")

        let again = ladder.record(.race, ceiling)
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(ladder.count(.race), ceiling)
    }

    func testNonPositiveAmountsChangeNothing() {
        var ladder = AchievementLadder()
        _ = ladder.record(.battle, 1)
        let before = ladder

        XCTAssertTrue(ladder.record(.battle, 0).isEmpty)
        XCTAssertTrue(ladder.record(.battle, -5).isEmpty)
        XCTAssertEqual(ladder, before, "0·음수 기록으로 되감기지 않는다")
    }

    // MARK: 단계 합계 (LAN 카드가 보여주는 한 숫자)

    /// 상한은 카탈로그에서 계산한다. 16 을 박아 두면 트랙이나 단계를 더한 날 카드의 분모와
    /// 광고 클램프가 조용히 어긋난다.
    func testTierCeilingIsDerivedFromTheCatalog() {
        XCTAssertEqual(AchievementLadder.tierCeiling,
                       AchievementLadder.catalog.reduce(0) { $0 + $1.tiers.count })
        XCTAssertGreaterThan(AchievementLadder.tierCeiling, 0)
    }

    /// 합계는 네 트랙의 도달 단계를 더한 값이다. 한 트랙만 세면 카드가 진행을 축소해 보여준다.
    func testTierTotalSumsEveryTrack() {
        var ladder = AchievementLadder()
        XCTAssertEqual(ladder.tierTotal, 0)

        _ = ladder.record(.focus, achievement(.focus).tiers[1])    // 2단계
        XCTAssertEqual(ladder.tierTotal, 2)

        _ = ladder.record(.battle, achievement(.battle).tiers[0])   // +1단계
        XCTAssertEqual(ladder.tierTotal, 3)
        XCTAssertEqual(ladder.tierTotal,
                       AchievementTrack.allCases.reduce(0) { $0 + ladder.tier($1) })
    }

    /// 전부 최고 단계면 합계가 상한과 같다. 카드가 `16/16` 에 닿을 수 있다는 증거다.
    func testTierTotalReachesTheCeilingWhenEveryTrackIsMaxed() {
        var ladder = AchievementLadder()
        for entry in AchievementLadder.catalog {
            _ = ladder.record(entry.track, entry.tiers.last! * 2)
        }
        XCTAssertEqual(ladder.tierTotal, AchievementLadder.tierCeiling)
    }

    // MARK: 표시용 파생값

    /// 다음 문턱은 "아직 안 넘은 첫 칸" 이다. 최고 단계면 nil — 화면이 ✓ 로 바꾼다.
    func testNextTierPointsAtTheFirstUnclearedThreshold() {
        var ladder = AchievementLadder()
        let tiers = achievement(.battle).tiers

        XCTAssertEqual(ladder.next(.battle)?.goal, tiers[0])
        XCTAssertEqual(ladder.next(.battle)?.tier, 1)

        _ = ladder.record(.battle, tiers[0])
        XCTAssertEqual(ladder.next(.battle)?.goal, tiers[1])
        XCTAssertEqual(ladder.next(.battle)?.tier, 2)

        _ = ladder.record(.battle, tiers.last!)
        XCTAssertNil(ladder.next(.battle), "최고 단계에는 다음 문턱이 없다")
        XCTAssertEqual(ladder.tier(.battle), tiers.count)
    }

    /// 화면 행은 카탈로그 순서를 그대로 따른다 — 순서가 흔들리면 선반이 렌더마다 뒤바뀐다.
    func testRowsFollowCatalogOrder() {
        var ladder = AchievementLadder()
        _ = ladder.record(.evolve, 3)

        let rows = ladder.rows

        XCTAssertEqual(rows.map(\.achievement.id), AchievementLadder.catalog.map(\.id))
        XCTAssertEqual(rows.first { $0.achievement.track == .evolve }?.count, 3)
    }

    // MARK: 경계 정규화 (손편집 · 구버전 방어)

    func testNormalizeDropsUnknownKeysAndClampsToTheLastTier() {
        var ladder = AchievementLadder()
        ladder.counts = ["focus": Int.max, "someRemovedTrack": 5, "battle": -3]

        ladder.normalize()

        XCTAssertEqual(ladder.counts["focus"], achievement(.focus).tiers.last)
        XCTAssertNil(ladder.counts["someRemovedTrack"], "카탈로그에 없는 키는 버린다")
        XCTAssertEqual(ladder.counts["battle"], 0)
    }

    /// 클램프된 값은 곧 "최고 단계 도달" 이라 재지급되지 않는다 — 손편집으로 넘겨도 이득이 없다.
    func testClampedCountsCannotCrossATierAgain() {
        var ladder = AchievementLadder()
        ladder.counts = ["focus": Int.max]
        ladder.normalize()

        XCTAssertTrue(ladder.record(.focus, 10_000).isEmpty)
    }

    /// canonical 은 정렬돼야 한다 — 순회 순서에 기대면 같은 상태가 실행마다 다른 문자열을 내고,
    /// 정상 세이브가 무작위로 조작 판정된다.
    func testCanonicalIsSortedAndStable() {
        var forward = AchievementLadder()
        _ = forward.record(.focus, 30)
        _ = forward.record(.battle, 2)

        var reversed = AchievementLadder()
        _ = reversed.record(.battle, 2)
        _ = reversed.record(.focus, 30)

        XCTAssertEqual(forward.canonical, reversed.canonical)
        XCTAssertEqual(forward.canonical, "battle:2,focus:30")
    }
}

// MARK: 세이브 (하위호환 · 무결성)

final class AchievementSaveTests: XCTestCase {

    /// 업적 필드가 없던 시절의 세이브는 빈 사다리로 읽히고, 나머지 진행은 그대로 살아야 한다.
    func testLegacySaveWithoutAchievementsDecodesToAnEmptyLadder() throws {
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"starPieces":1234}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))

        XCTAssertEqual(state.achievements, AchievementLadder())
        XCTAssertEqual(state.starPieces, 1234, "새 필드 부재가 다른 진행을 날리지 않는다")
    }

    /// 타입이 어긋난 값(손편집·손상)도 기본값으로 흡수돼야 한다 — 한 필드가 깨져도 상태 전체를
    /// 날리지 않는 관대 디코딩 계약(`c.lenient`).
    func testACorruptAchievementFieldFallsBackWithoutLosingTheRest() throws {
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"starPieces":77,"achievements":"nope"}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))

        XCTAssertEqual(state.achievements, AchievementLadder())
        XCTAssertEqual(state.starPieces, 77)
    }

    /// 기본값이면 canonical 문자열에 아무것도 붙지 않는다 — 기존 세이브의 서명이 그대로 유효해야 한다.
    /// (조건부 append 를 무조건 append 로 바꾸면 정상 세이브가 전부 조작 판정 → 진행 초기화된다.)
    ///
    /// 해시끼리 비교하면 **안 된다**: 기본값 상태를 자기 자신과 대조하게 돼 무조건 append 로 바꿔도
    /// 양쪽이 똑같이 바뀌어 통과한다. 조각이 실제로 없는지를 문자열에서 직접 본다.
    func testDefaultAchievementsAddNothingToTheIntegrityCanonical() {
        XCTAssertFalse(SaveTransfer.canonicalString(CompanionState()).contains("|ach"))
        XCTAssertFalse(SaveTransfer.isTampered(SaveTransfer.signed(CompanionState())))
    }

    /// 대조군 — 값이 들어가면 세그먼트가 실제로 붙는다. 위 테스트만 있으면 canonical 에서 업적을
    /// 통째로 빼먹어도 통과한다.
    func testAPopulatedLadderDoesAppendItsCanonicalSegment() {
        var state = CompanionState()
        _ = state.achievements.record(.battle, 2)

        XCTAssertTrue(SaveTransfer.canonicalString(state).contains("|achbattle:2"),
                      "실제: \(SaveTransfer.canonicalString(state))")
    }

    /// 접두가 `ac` 였을 때 위의 "기본값엔 안 붙는다" 가 **거짓 통과**했다 — 기본값 canonical 에도
    /// 활성 포켓몬 세그먼트 `|act-` 가 있어 `contains("|ac")` 가 항상 참이었다. 세그먼트 유무를
    /// 보는 테스트는 다른 세그먼트 접두에 걸리지 않는 접두를 써야 한다.
    func testTheAchievementPrefixDoesNotCollideWithTheActivePokemonSegment() {
        let canonical = SaveTransfer.canonicalString(CompanionState())
        XCTAssertTrue(canonical.contains("|act"), "활성 포켓몬 세그먼트가 여전히 `act` 를 쓴다")
        XCTAssertFalse(canonical.contains("|ach"), "업적 접두가 `act` 와 겹치면 안 된다")
    }

    /// 가드가 실제로 지키는지 — 서명 후 카운터를 손으로 올리면 조작으로 잡혀야 한다.
    /// 카운터가 곧 단계 판정이라, 서명 밖에 있으면 값을 올려 적는 것만으로 단계 보상을 받을 수 있다.
    func testEditingAchievementCountsAfterSigningIsDetected() {
        var state = CompanionState()
        _ = state.achievements.record(.focus, 10)
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed), "테스트 전제: 서명 직후는 정상이어야 한다")

        signed.achievements.counts["focus"] = 3_000
        XCTAssertTrue(SaveTransfer.isTampered(signed), "카운터가 무결성 해시에 들어가 있어야 한다")
    }

    /// 경계에서 한 번만 정규화한다 — 손편집으로 넣은 거대한 값이 그대로 저장되면 계속 상한 위에 앉는다.
    func testExtremeAchievementCountsAreClampedAtTheBoundary() {
        var state = CompanionState()
        state.achievements.counts = ["focus": Int.max, "ghostTrack": 7]

        let sanitized = SaveTransfer.sanitized(state)

        XCTAssertEqual(sanitized.achievements.counts["focus"],
                       AchievementLadder.catalog.first { $0.track == .focus }!.tiers.last)
        XCTAssertNil(sanitized.achievements.counts["ghostTrack"])
    }

    /// **새 필드**라 값이 든 기존 세이브가 없다 — 조건부 append 만으로 충분하고 `integrityVersion`
    /// 은 올리지 않는다. `gymBadges` 는 이전 배포에 이미 있던 필드라 버전 상향이 필요했다
    /// (`testASaveSignedBeforeTheCanonicalChangeIsNotJudgedTampered`).
    /// 버전을 올리면 그 배포의 **모든** 세이브가 검사를 한 번 면제받아 다른 필드 조작도 통과한다.
    func testTheAchievementSegmentDoesNotRequireAnIntegrityVersionBump() {
        XCTAssertEqual(SaveTransfer.integrityVersion, 7)

        // 업적이 없는 상태로 현재 버전에서 서명된 세이브는 그대로 유효하다.
        var old = CompanionState()
        old.starPieces = 5_000
        let signed = SaveTransfer.signed(old)
        XCTAssertFalse(SaveTransfer.isTampered(signed))
    }
}

// MARK: 적립 경로 (스토어)

@MainActor
final class AchievementAccrualTests: XCTestCase {

    private func tiers(_ track: AchievementTrack) -> [Int] {
        AchievementLadder.catalog.first { $0.track == track }!.tiers
    }
    private func rewards(_ track: AchievementTrack) -> [Int] {
        AchievementLadder.catalog.first { $0.track == track }!.rewards
    }

    private func makeStore(_ line: EvoLine, _ clock: TestClock) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-achievement-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: clock.closure,
                              fileURL: url, rng: SeededRNG(seed: 11))
    }

    private func count(_ store: CompanionStore, _ track: AchievementTrack) -> Int {
        store.achievementRows.first { $0.achievement.track == track }?.count ?? -1
    }

    // MARK: 집중 — 정산된 분만

    /// 모험을 정산하면 **정산된 분**이 집중 카운터로 들어간다.
    func testClaimingAnAdventureAdvancesTheFocusTrack() async {
        let clock = TestClock()
        let store = makeStore(achievementAutoLine, clock)
        await store.hatch(baseID: 1)

        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        XCTAssertNotNil(store.claimAdventure())

        XCTAssertEqual(count(store, .focus), 25)
        XCTAssertEqual(count(store, .battle), 0, "다른 트랙이 딸려 오르면 안 된다")
    }

    /// 정산하지 않은 모험은 아무것도 적립하지 않는다 — 시작만으로 오르면 타이머를 켜 두는 것이
    /// 곧 업적 진행이 되어 목표가 집중과 무관해진다.
    func testStartingAnAdventureAloneAccruesNothing() async {
        let clock = TestClock()
        let store = makeStore(achievementAutoLine, clock)
        await store.hatch(baseID: 1)

        XCTAssertTrue(store.startFocusAdventure(minutes: 90))
        clock.advance(10 * 60)
        XCTAssertNil(store.claimAdventure())

        XCTAssertEqual(count(store, .focus), 0)
    }

    /// 지급액은 **보상 객체가 설명해야 한다** — 지갑에만 더하고 보고하지 않으면 화면이 알려준 값과
    /// 실제 잔액이 어긋난다(`trainerBonus`·`missionBonus` 와 같은 계약).
    func testTheReportedAchievementBonusMatchesTheWalletIncrease() async throws {
        let clock = TestClock()
        let store = makeStore(achievementAutoLine, clock)
        await store.hatch(baseID: 1)
        let before = store.state.starPieces

        XCTAssertTrue(store.startFocusAdventure(minutes: 90))
        clock.advance(90 * 60)
        let reward = try XCTUnwrap(store.claimAdventure())

        XCTAssertEqual(reward.achievementBonus, rewards(.focus)[0],
                       "90분 정산이 집중 1단계(\(tiers(.focus)[0])분)를 넘긴다")
        XCTAssertEqual(store.state.starPieces - before,
                       reward.starPieces + reward.trainerBonus + reward.missionBonus
                           + reward.achievementBonus + reward.seasonBonus,
                       "보고한 합과 실제 지갑 증가가 어긋난다")
    }

    /// 최고 단계를 넘긴 뒤로는 더 지급되지 않는다 — 카운터 클램프가 곧 재지급 차단이다.
    func testNoFurtherPayoutOnceTheLastFocusTierIsCleared() async throws {
        let clock = TestClock()
        let store = makeStore(achievementAutoLine, clock)
        await store.hatch(baseID: 1)
        store.debugSetAchievementCount(.focus, tiers(.focus).last!)
        let before = store.state.starPieces

        XCTAssertTrue(store.startFocusAdventure(minutes: 90))
        clock.advance(90 * 60)
        let reward = try XCTUnwrap(store.claimAdventure())

        XCTAssertEqual(reward.achievementBonus, 0)
        XCTAssertEqual(store.state.starPieces - before,
                       reward.starPieces + reward.trainerBonus + reward.missionBonus
                           + reward.seasonBonus)
    }

    /// 한 정산이 두 단계를 넘기면 **둘 다** 지급되고, 보고액도 두 몫의 합이다 — 마지막 하나만
    /// 실어 보내면 그만큼이 설명되지 않는다.
    ///
    /// 0 에서 2단계 문턱(300분)까지 한 번에 가야 두 칸을 함께 넘는다. 1단계 위에서 출발하면 한
    /// 칸만 넘는다 — 처음엔 그렇게 세워 두고 1,300 을 기대했다가 1,000 을 받았다.
    func testOneClaimCanPayTwoFocusTiersAtOnce() async throws {
        let clock = TestClock()
        let store = makeStore(achievementAutoLine, clock)
        await store.hatch(baseID: 1)
        let spanBothTiers = tiers(.focus)[1]
        XCTAssertEqual(store.achievementRows.first { $0.achievement.track == .focus }?.count, 0,
                       "테스트 전제: 0 에서 출발해야 1단계도 함께 넘는다")

        XCTAssertTrue(store.startFocusAdventure(minutes: spanBothTiers))
        clock.advance(TimeInterval(spanBothTiers * 60))
        let reward = try XCTUnwrap(store.claimAdventure())

        XCTAssertEqual(reward.achievementBonus, rewards(.focus)[0] + rewards(.focus)[1])
        XCTAssertEqual(count(store, .focus), spanBothTiers)
    }

    // MARK: 진화 — 세 경로를 각각 단독으로

    /// 경로 ① 자동 진화(`applyUsage` 안의 성장치 게이트). 레벨 메타데이터가 없는 라인이 이 경로를 탄다.
    func testAutomaticEvolutionAdvancesTheEvolveTrack() async {
        let clock = TestClock()
        let store = makeStore(achievementAutoLine, clock)
        await store.hatch(baseID: 1)
        XCTAssertEqual(count(store, .evolve), 0, "테스트 전제: 부화만으로는 오르지 않는다")

        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))

        XCTAssertEqual(count(store, .evolve), 1)
    }

    /// 경로 ② 진화 프롬프트 수락(`acceptEvolution`). 레벨 관문이 있는 라인만 이 경로를 탄다.
    func testAcceptingAnEvolutionPromptAdvancesTheEvolveTrack() async {
        let clock = TestClock()
        let store = makeStore(achievementPromptLine, clock)
        await store.hatch(baseID: 40)
        store.debugAccrueLevelExperience(300_000_000)
        store.applyUsage(0)
        XCTAssertNotNil(store.evolutionPrompt, "테스트 전제: 프롬프트가 떠야 이 경로를 밟는다")
        XCTAssertEqual(count(store, .evolve), 0, "프롬프트가 뜨는 것만으로는 오르지 않는다")

        store.acceptEvolution()

        XCTAssertEqual(count(store, .evolve), 1)
    }

    /// 경로 ③ 돌 진화(`useEvolutionItem`). 레벨을 보지 않는 유일한 경로다.
    func testStoneEvolutionAdvancesTheEvolveTrack() async {
        let clock = TestClock()
        let store = makeStore(achievementStoneLine, clock)
        await store.hatch(baseID: 30)
        store.debugAddItem(.fireStone)

        XCTAssertTrue(store.useEvolutionItem(.fireStone))

        XCTAssertEqual(count(store, .evolve), 1)
    }

    /// 진화가 아닌 연출(`.hatch`·`.dittoReveal`)은 세지 않는다 — 적립을 `fireCelebration` 단일
    /// 퍼널에 걸었으므로, case 를 안 가리면 부화마다 진화 카운터가 오른다.
    func testHatchingDoesNotAdvanceTheEvolveTrack() async {
        let clock = TestClock()
        let store = makeStore(achievementAutoLine, clock)
        await store.hatch(baseID: 1)
        await store.hatch(baseID: 1)

        XCTAssertEqual(count(store, .evolve), 0, "부화 연출이 진화로 세어졌다")
    }

    // MARK: 배틀 — 승리만

    func testAWonBattleAdvancesTheBattleTrack() async {
        let clock = TestClock()
        let store = makeStore(achievementAutoLine, clock)
        await store.hatch(baseID: 1)
        let before = store.state.starPieces

        store.grantBattleReward(won: true, participantCount: 2, mode: .freeForAll,
                                opponentNames: ["Rival"])

        XCTAssertEqual(count(store, .battle), 1)
        XCTAssertEqual(store.state.starPieces - before, rewards(.battle)[0],
                       "1단계 문턱이 1승이라 첫 승리에서 바로 보상이 나간다")
    }

    func testALostBattleAdvancesNothing() async {
        let clock = TestClock()
        let store = makeStore(achievementAutoLine, clock)
        await store.hatch(baseID: 1)
        let before = store.state.starPieces

        store.grantBattleReward(won: false, participantCount: 2, mode: .freeForAll,
                                opponentNames: ["Rival"])

        XCTAssertEqual(count(store, .battle), 0)
        XCTAssertEqual(store.state.starPieces, before)
    }

    // MARK: 레이스 — 완주

    func testFinishingARaceAdvancesTheRaceTrack() async {
        let clock = TestClock()
        let store = makeStore(achievementAutoLine, clock)
        await store.hatch(baseID: 1)

        store.recordRaceFinish()

        XCTAssertEqual(count(store, .race), 1)
    }
}

// MARK: 레이스 완주 판정 (순수)

/// 완주 적립은 `pokeathlonRace` 의 **nil → 우승자 확정 전이**에서만 일어나야 한다.
/// 경기 중에도 상태가 계속 대입되니(호스트 반영·게스트 수신) 판정을 순수 함수로 떼어 네트워크
/// 없이 전 분기를 밟는다 — `MultiplayerBattle.outcome` 이 static 인 것과 같은 이유다.
final class RaceFinishCreditTests: XCTestCase {

    private let me = UUID()
    private let other = UUID()

    private func race(winner: UUID?, racers: [UUID]) -> PokeathlonRace {
        PokeathlonRace(racers: racers.map {
            PokeathlonRacer(id: $0, trainerName: "T", speciesID: 1)
        }, winnerID: winner)
    }

    func testCreditsWhenAWinnerIsFirstDecidedAndIRaced() {
        XCTAssertTrue(MultiplayerRoomCenter.creditsRaceFinish(
            old: race(winner: nil, racers: [me, other]),
            new: race(winner: other, racers: [me, other]), myID: me),
            "우승하지 않아도 완주는 완주다")
    }

    /// 관전자는 `racers` 에 없다 — 세면 싸우지도 않은 경기가 업적이 된다.
    func testDoesNotCreditASpectator() {
        XCTAssertFalse(MultiplayerRoomCenter.creditsRaceFinish(
            old: race(winner: nil, racers: [other]),
            new: race(winner: other, racers: [other]), myID: me))
    }

    /// 우승자가 확정된 뒤에도 상태 브로드캐스트가 이어진다 — 매번 세면 한 경기가 여러 번 적립된다.
    func testDoesNotCreditARepeatedFinishedState() {
        XCTAssertFalse(MultiplayerRoomCenter.creditsRaceFinish(
            old: race(winner: other, racers: [me, other]),
            new: race(winner: other, racers: [me, other]), myID: me))
    }

    /// 경기 중 갱신(우승자 없음 → 없음)은 적립하지 않는다.
    func testDoesNotCreditAnInProgressUpdate() {
        XCTAssertFalse(MultiplayerRoomCenter.creditsRaceFinish(
            old: race(winner: nil, racers: [me, other]),
            new: race(winner: nil, racers: [me, other]), myID: me))
    }

    /// 방을 닫을 때의 `= nil` 대입도 적립하지 않는다.
    func testDoesNotCreditARoomTeardown() {
        XCTAssertFalse(MultiplayerRoomCenter.creditsRaceFinish(
            old: race(winner: other, racers: [me, other]), new: nil, myID: me))
        XCTAssertFalse(MultiplayerRoomCenter.creditsRaceFinish(
            old: nil, new: nil, myID: me))
    }

    /// 방에 처음 들어설 때(nil → 경기 시작)도 적립하지 않는다.
    func testDoesNotCreditRaceStart() {
        XCTAssertFalse(MultiplayerRoomCenter.creditsRaceFinish(
            old: nil, new: race(winner: nil, racers: [me]), myID: me))
    }
}

// 부화용 최소 진화 라인들 — 진화 경로마다 다른 라인이 필요하다.
private func achievementLine(base: Int, tree: EvoNode) -> EvoLine {
    func ids(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(ids) }
    var names: [Int: [String: String]] = [:]
    for id in ids(tree) { names[id] = ["en": "A\(id)", "ko": "업\(id)", "ja": "ア\(id)"] }
    return EvoLine(baseID: base, tree: tree, rarity: .common, names: names)
}

// 레벨 메타데이터 없음 → `applyUsage` 안의 성장치 게이트로 자동 진화한다.
private let achievementAutoLine = achievementLine(
    base: 1, tree: EvoNode(speciesID: 1, children: [
        EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])
    ]))

// 레벨 관문 있음 → 프롬프트가 뜨고 `acceptEvolution` 으로만 넘어간다.
private let achievementPromptLine = achievementLine(
    base: 40, tree: EvoNode(speciesID: 40, children: [
        EvoNode(speciesID: 41, children: [], evolutionLevel: 5)
    ]))

// 돌 진화 → `useEvolutionItem` 만 통한다.
private let achievementStoneLine = achievementLine(
    base: 30, tree: EvoNode(speciesID: 30, children: [
        EvoNode(speciesID: 31, children: [], evolutionTrigger: "use-item", evolutionItem: "fire-stone")
    ]))
