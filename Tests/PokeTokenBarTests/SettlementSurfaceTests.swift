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

    private let line = EvoLine(baseID: 20, tree: EvoNode(speciesID: 20, children: []),
                               rarity: .common, names: [20: ["en": "P20", "ko": "포20", "ja": "ポ20"]])

    private func store(_ clock: TestClock) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-settlement-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: clock.closure,
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    /// 만렙 파트너 — 상한에 **정확히** 닿게 시드하므로 시드 자체로는 초과분이 없다. 뒤에 오는
    /// 환산은 전부 정산이 만든 것이다.
    private func maxedStore(_ clock: TestClock) async -> CompanionStore {
        let s = store(clock)
        await s.hatch(baseID: 20)
        s.debugAccrueLevelExperience(PokemonBalance.maxLevelExperience)
        XCTAssertEqual(s.currentLevel, PokemonBalance.maxLevel, "테스트 전제: 만렙에 닿았다")
        return s
    }

    // MARK: 배너 (화면이 읽는 마지막 정산)

    /// 수동 "보상 받기" 경로. 예전엔 `FocusTimerView` 가 `_ = companion.claimAdventure()` 로 결과를
    /// 통째로 버려서, 환산분은커녕 기본 별의조각조차 화면에 뜨지 않았다.
    func testBannerExplainsTheWholeWalletIncreaseWhenExperienceIsConverted() async throws {
        XCTAssertFalse(AppEnv.isBundledApp, "테스트 전제: 여기서는 알림이 나갈 수 없다 — 배너가 유일한 설명이다")
        let clock = TestClock()
        let s = await maxedStore(clock)
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
        let s = await maxedStore(clock)
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
        let s = await maxedStore(clock)
        let seqBefore = s.claimFeedbackSeq

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)
        XCTAssertNotNil(s.claimAdventure())

        XCTAssertEqual(s.claimFeedbackSeq, seqBefore + 1, "정산마다 seq 가 올라야 뷰가 새 배너를 감지한다")
        XCTAssertNotNil(s.lastClaim)
        s.consumeClaimFeedback()
        XCTAssertNil(s.lastClaim, "소비 후에는 남지 않는다")
    }

    /// 정산할 게 없으면(미완료 · 모험 없음) 배너도 안 뜬다 — "항상 뜬다" 구현을 가른다.
    func testNothingToClaimLeavesTheBannerEmpty() async {
        let clock = TestClock()
        let s = await maxedStore(clock)

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(10 * 60)   // 아직 안 끝났다
        XCTAssertNil(s.claimAdventure())

        XCTAssertNil(s.lastClaim, "정산이 없으면 설명할 것도 없다")
    }

    // MARK: 히스토리 (지갑과 맞아야 하는 기록)

    /// `AdventureRecord.stardust` 는 `reward.starPieces` 만 담아서, 환산분·트레이너·미션·업적·시즌
    /// 몫이 전부 빠진 채 기록됐다. 기록만 보면 지급액이 실제보다 적게 보인다.
    func testHistoryRecordsTheWholePayoutNotJustTheBaseStardust() async throws {
        let clock = TestClock()
        let s = await maxedStore(clock)
        let before = s.state.starPieces

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)
        let reward = try XCTUnwrap(s.claimAdventure())

        XCTAssertGreaterThan(reward.overflowBonus, 0, "전제: 이 정산은 환산할 초과분을 만든다")
        let record = try XCTUnwrap(s.recentAdventures.first)
        XCTAssertEqual(record.stardust, s.state.starPieces - before,
                       "기록의 지급액이 지갑 증가분과 맞아야 한다")
        XCTAssertGreaterThan(record.stardust, reward.starPieces,
                             "기본 별의조각만 담으면 환산분만큼 과소보고다")
    }

    /// 대조군 — 상한 아래에서도 같은 등식이 성립한다. 만렙 케이스만 두면 "환산분을 늘 더한다"는
    /// 구현도 통과한다.
    func testHistoryMatchesTheWalletBelowTheCapToo() async throws {
        let clock = TestClock()
        let s = store(clock)
        await s.hatch(baseID: 20)
        let before = s.state.starPieces

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)
        let reward = try XCTUnwrap(s.claimAdventure())

        XCTAssertEqual(reward.overflowBonus, 0, "전제: 상한 아래에서는 환산분이 없다")
        let record = try XCTUnwrap(s.recentAdventures.first)
        XCTAssertEqual(record.stardust, s.state.starPieces - before)
    }
}
