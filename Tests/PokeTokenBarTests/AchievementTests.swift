import XCTest
@testable import PokeTokenBar

// 업적 사다리 — 집중·진화·배틀·레이스 네 트랙에 각 4단계 문턱.
//
// 세이브에 담기는 건 **누적 카운터 사전 하나**뿐이다. 도달 단계는 저장하지 않는다 — 카운터가
// 단조 증가라 단계가 파생값이고, "이번에 넘은 문턱"만 반환하면 재지급 기억이 필요 없다
// (`TrainerLevel.add` 가 오른 레벨 수를 돌려주는 것과 같은 계약).
//
// 체육관 배지(`state.gymBadges`)와는 다른 층이다 — 그쪽은 컨텐츠 첫 승리 기록이고 이쪽은 누적 행동이다.
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

    /// 업적 이름은 세 언어 모두에서 채워져야 한다 — 한 언어만 비면 그 언어 사용자에겐 빈 줄이 보인다.
    /// (트랙 추가 자체는 `achievementName` 의 exhaustive switch 가 컴파일에서 막는다. 이 테스트가
    ///  잡는 건 `t()` 인자 중 하나를 빈 문자열로 두고 넘어가는 경우다.)
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
        XCTAssertFalse(SaveTransfer.canonicalString(CompanionState()).contains("|ac"))
        XCTAssertFalse(SaveTransfer.isTampered(SaveTransfer.signed(CompanionState())))
    }

    /// 대조군 — 값이 들어가면 세그먼트가 실제로 붙는다. 위 테스트만 있으면 canonical 에서 업적을
    /// 통째로 빼먹어도 통과한다.
    func testAPopulatedLadderDoesAppendItsCanonicalSegment() {
        var state = CompanionState()
        _ = state.achievements.record(.battle, 2)

        XCTAssertTrue(SaveTransfer.canonicalString(state).contains("|acbattle:2"),
                      "실제: \(SaveTransfer.canonicalString(state))")
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

    /// 업적은 **새 필드**라 값이 든 기존 세이브가 존재하지 않는다 — 그래서 조건부 append 만으로
    /// 충분하고 `integrityVersion` 을 올릴 필요가 없다(`gymBadges` 는 이전 배포에 이미 있던 필드라
    /// 버전 상향이 필요했다 — `testASaveSignedBeforeTheCanonicalChangeIsNotJudgedTampered`).
    /// 버전을 올리면 그 배포에서 **모든** 세이브가 한 번 검사 면제를 받아 다른 필드의 조작도 통과한다.
    func testTheAchievementSegmentDoesNotRequireAnIntegrityVersionBump() {
        XCTAssertEqual(SaveTransfer.integrityVersion, 7)

        // 업적이 없는 상태로 현재 버전에서 서명된 세이브는 그대로 유효하다.
        var old = CompanionState()
        old.starPieces = 5_000
        let signed = SaveTransfer.signed(old)
        XCTAssertFalse(SaveTransfer.isTampered(signed))
    }
}
