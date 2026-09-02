import XCTest
@testable import PokeTokenBar

/// 정산을 **알림 밖에서** 설명하는가(#192).
///
/// `awardExperience` 는 만렙에 걸린 경험치를 별의조각으로 되돌리지만(#82), 그 사실을 알리는 곳이
/// `notifyCompanionEvent` 하나뿐이었다. 그 함수는 번들앱 · 방해금지 해제 · 알림 토글 **셋 다** 참일
/// 때만 나간다(`CompanionStore.notifyCompanionEvent`). 알림을 끈 사용자는 만렙 모험을 마치고
/// 7,200 대신 10,800 ⭐ 를 받고도 그 차이를 화면 어디에서도 볼 수 없었다.
///
/// 이 테스트들은 `swift test` 안에서 돈다 — `AppEnv.isBundledApp` 이 false 라 알림은 **한 통도
/// 나갈 수 없다.** 즉 이 파일 전체가 "알림을 끈 사용자" 의 경로다. 여기서 정산이 설명되면 그
/// 사용자에게도 설명된다.
@MainActor
final class SettlementSurfaceTests: XCTestCase {

    // MARK: 배너 (화면이 읽는 마지막 정산)

    /// 수동 "보상 받기" 경로. 예전엔 `FocusTimerView` 가 `_ = companion.claimAdventure()` 로 결과를
    /// 통째로 버려서, 환산분은커녕 기본 별의조각조차 화면에 뜨지 않았다.
    func testBannerExplainsTheWholeWalletIncreaseWhenExperienceIsConverted() async throws {
        XCTAssertFalse(AppEnv.isBundledApp, "테스트 전제: 여기서는 알림이 나갈 수 없다 — 배너가 유일한 설명이다")
        let clock = TestClock()
        let s = await maxLevelStore(clock, tag: "settlement")
        let before = s.state.starPieces

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)
        XCTAssertNotNil(s.claimAdventure())

        let banner = try XCTUnwrap(s.lastClaim, "정산했으면 화면이 읽을 마지막 정산이 남아야 한다")
        XCTAssertGreaterThan(banner.overflowBonus, 0, "전제: 이 정산은 환산할 초과분을 만든다")
        XCTAssertEqual(banner.totalStardust, s.state.starPieces - before,
                       "배너 하나로 지갑 증가분이 전부 설명돼야 한다")
    }

    /// **트리거 브랜치 — 자동 정산.** 앱이 꺼진 사이 끝났거나 정산 UI 를 못 본 모험은 다음 모험을
    /// 시작할 때 `startFocusAdventure` 안에서 조용히 정산된다. 배너 상태를 뷰의 `@State` 에 두면
    /// 이 경로는 영영 아무것도 못 보여준다 — 그래서 스토어에 둔다.
    func testAutoClaimWhenStartingAnotherRunAlsoFillsTheBanner() async throws {
        let clock = TestClock()
        let s = await maxLevelStore(clock, tag: "settlement")
        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(6 * 3600)   // 몇 시간 방치 — 정산하지 않은 채로 둔다
        let before = s.state.starPieces

        XCTAssertTrue(s.startFocusAdventure(minutes: 25), "밀린 보상이 시작을 막으면 안 된다")

        let banner = try XCTUnwrap(s.lastClaim, "자동 정산도 설명을 남겨야 한다")
        XCTAssertGreaterThan(banner.overflowBonus, 0, "전제: 밀린 모험도 환산분을 만들었다")
        XCTAssertEqual(banner.totalStardust, s.state.starPieces - before)
    }

    /// 1회성 계약 — 기존 피드백(`consumeCandyFeedback`·`consumeCelebration`)과 같은 형태다.
    /// 소비하지 않으면 다른 탭에 갔다 돌아올 때 같은 배너가 다시 떠오른다.
    func testBannerIsHandedOverOnlyOnce() async {
        let clock = TestClock()
        let s = await maxLevelStore(clock, tag: "settlement")
        let seqBefore = s.claimFeedbackSeq

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)
        XCTAssertNotNil(s.claimAdventure())

        XCTAssertEqual(s.claimFeedbackSeq, seqBefore + 1, "정산마다 seq 가 올라야 뷰가 새 배너를 감지한다")
        XCTAssertNotNil(s.lastClaim)
        s.consumeClaimFeedback()
        XCTAssertNil(s.lastClaim, "소비 후에는 남지 않는다")
    }

    /// **트리거 브랜치 — 세이브 가져오기.** 배너는 뷰가 *건네받아* 들고 있으므로(`claimBanner`),
    /// 스토어의 `lastClaim` 만 비우면 이미 화면에 떠 있는 남의 세이브 정산액에는 닿지 못한다.
    /// seq 를 함께 올려야 뷰가 "빈 정산" 을 건네받아 배너를 내린다 — `lastClaim = nil` 만 두고
    /// 이 줄을 지우면 이 테스트만 빨개진다.
    func testImportingASaveTellsTheViewToDropTheBanner() async throws {
        let clock = TestClock()
        let s = await maxLevelStore(clock, tag: "settlement")
        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)
        XCTAssertNotNil(s.claimAdventure())
        let seqAfterClaim = s.claimFeedbackSeq

        let data = try SaveTransfer.encode(state: CompanionState(), appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: clock.now)
        try s.applySave(try SaveTransfer.decode(data))

        XCTAssertNil(s.lastClaim, "남의 세이브를 불러왔으면 이전 정산은 설명할 대상이 아니다")
        XCTAssertNotEqual(s.claimFeedbackSeq, seqAfterClaim,
                          "seq 가 그대로면 뷰는 자기가 들고 있는 남의 정산액을 계속 그린다")
    }

    /// 정산할 게 없으면(미완료 · 모험 없음) 배너도 안 뜬다 — "항상 뜬다" 구현을 가른다.
    func testNothingToClaimLeavesTheBannerEmpty() async {
        let clock = TestClock()
        let s = await maxLevelStore(clock, tag: "settlement")

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(10 * 60)   // 아직 안 끝났다
        XCTAssertNil(s.claimAdventure())

        XCTAssertNil(s.lastClaim, "정산이 없으면 설명할 것도 없다")
    }

    // MARK: 히스토리 (저장된 필드의 뜻)

    /// `AdventureRecord.stardust` 는 **기본 별의조각만** 담는다. 전부 담는 쪽이 더 옳아 보여 한 번
    /// 바꿨다가 되돌렸다 — 저장된 배열이라 마이그레이션 없이 의미만 바꾸면 옛 행과 새 행이 다른 것을
    /// 뜻한 채 섞이고, 읽는 화면은 아직 하나도 없어 바꿀 이유도 없었다. 이 테스트는 그 결정을
    /// 못 박는다: 히스토리 화면을 붙일 때 마이그레이션과 **함께** 정한다.
    func testHistoryStoresTheBaseStardustOnlyUntilAMigrationSaysOtherwise() async throws {
        let clock = TestClock()
        let s = await maxLevelStore(clock, tag: "settlement")

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)
        let reward = try XCTUnwrap(s.claimAdventure())

        XCTAssertGreaterThan(reward.overflowBonus, 0, "전제: 이 정산은 환산할 초과분을 만든다")
        let record = try XCTUnwrap(s.recentAdventures.first)
        XCTAssertEqual(record.stardust, reward.starPieces, "기록은 기본 지급액만 담는다")
        XCTAssertLessThan(record.stardust, reward.totalStardust,
                          "전제: 이 정산의 지갑 증가분은 기본 지급액보다 크다 — 둘이 다름을 아는 채로 고정한다")
    }

    // MARK: 배너 줄 조립 (화면이 실제로 그리는 것)

    /// 뷰 안 `if` 로만 존재하던 조립을 `AdventureReward.bannerLines` 로 뺐다. 여기서 지급 하나가
    /// 빠지면 화면에서도 빠진다 — 예전엔 사탕 · 알 개수가 빠져도 테스트가 전부 초록이었다.
    func testEveryPayoutOnOneClaimGetsItsOwnBannerLine() {
        let reward = AdventureReward(experience: 1_000, starPieces: 40, foundRareCandy: true,
                                     foundEgg: true, eggFragments: 6, bonusEggs: 3,
                                     overflowExperience: PokemonBalance.experiencePerOverflowStarPiece * 7)

        XCTAssertEqual(reward.bannerLines,
                       [.eggs(3), .settled(reward.totalStardust), .overflowConverted(reward.overflowBonus), .rareCandy],
                       "네 지급이 각자 한 줄씩 — 하나로 뭉치면 나머지가 화면에서 사라진다")
    }

    /// 대조군 — 아무 부가 지급도 없으면 정산액 한 줄뿐이다. "늘 네 줄" 구현을 가른다.
    func testAPlainClaimShowsOnlyTheSettledLine() {
        let reward = AdventureReward(experience: 1_000, starPieces: 40,
                                     foundRareCandy: false, foundEgg: false)

        XCTAssertEqual(reward.bannerLines, [.settled(40)])
    }

    /// 알이 하나여도 줄은 뜬다(개수만 1). `> 1` 로 개수를 적는 판단은 뷰에 남아 있으므로, 여기서는
    /// **줄이 존재하는가**를 고정한다.
    func testASingleEggStillGetsItsLine() {
        let reward = AdventureReward(experience: 1, starPieces: 1, foundRareCandy: false,
                                     foundEgg: true, bonusEggs: 1)

        XCTAssertEqual(reward.bannerLines.first, .eggs(1))
    }

    // MARK: 배너를 내리는 계기 (새 세션 시작)

    /// 배너에는 자동 소멸도 닫기 버튼도 없다 — 다음 집중을 시작할 때 내려간다. 뷰는 `sessionStartSeq`
    /// 를 자기가 들고 있는 값과 **비교**해서 판단하므로, 이 수가 시작마다 오르지 않으면 배너가
    /// 영영 붙어 있는다.
    func testStartingAFocusSessionAdvancesTheSequenceThatDropsTheBanner() {
        let timer = FocusTimer()
        let start = Date(timeIntervalSince1970: 80_000)
        let before = timer.sessionStartSeq

        timer.startFocus(minutes: 25, now: start)
        XCTAssertEqual(timer.sessionStartSeq, before + 1)

        // 완료(→휴식)는 계기가 아니다. 여기서 올리면 방금 정산한 배너가 뜨자마자 지워진다.
        timer.tick(now: start.addingTimeInterval(25 * 60))
        XCTAssertEqual(timer.phase, .rest, "전제: 완료 후 휴식으로 넘어갔다")
        XCTAssertEqual(timer.sessionStartSeq, before + 1, "완료는 배너를 내리는 계기가 아니다")

        timer.startFocus(minutes: 25, now: start.addingTimeInterval(60 * 60))
        XCTAssertEqual(timer.sessionStartSeq, before + 2, "다음 집중 시작이 계기다")
    }
}
