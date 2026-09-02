import XCTest
@testable import PokeTokenBar

/// 만렙(Lv.100) 경계(#81). 990,000,000 이 정확히 Lv.100 이라 **구간 나머지가 0** 이다 —
/// 만렙 가드가 없으면 다 키운 개체의 경험치 막대가 텅 빈 채로 그려졌다.
///
/// 경험치 누적은 클램프가 붙은 `MonState.gainExperience(_:)` 한 곳으로만 들어간다. 예전엔 누적
/// 지점이 세 곳이고 그중 이상한 사탕 경로만 클램프를 빠뜨려, 상한 위의 값이 저장되고
/// `SaveTransfer` 가 그 값을 조용히 되돌려 세이브를 옮긴 사람과 안 옮긴 사람의 데이터가 갈렸다.
@MainActor
final class MaxLevelTests: XCTestCase {

    private func tempURL() -> URL { stubStoreURL("maxlevel") }

    /// 저장 파일을 직접 지정하는 경로(세이브 왕복 검증). 시계는 실제 시각으로 둔다 — 이 테스트들은
    /// 시간을 전진시키지 않는다.
    private func store(at url: URL? = nil) -> CompanionStore {
        CompanionStore(provider: StubProvider(value: stubMaxLevelLine), clock: { Date() },
                       fileURL: url ?? tempURL(), rng: SeededRNG(seed: 7))
    }

    private func store(_ clock: TestClock) -> CompanionStore { stubStore(clock, tag: "maxlevel") }

    private func maxedStore(_ clock: TestClock) async -> CompanionStore {
        await maxLevelStore(clock, tag: "maxlevel")
    }

    // MARK: 클램프 (MonState.gainExperience)

    func testExperienceStopsAtTheCap() {
        var mon = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1)
        XCTAssertEqual(mon.gainExperience(PokemonBalance.maxLevelExperience - 1), 0,
                       "상한 아래에서는 넘치는 몫이 없다")
        XCTAssertEqual(mon.level, 99, "전제: 상한 직전은 Lv.99 다")

        // 1 만 들어가고 나머지는 넘친다 — 반환값이 그 나머지를 정확히 알려줘야 환산이 성립한다.
        XCTAssertEqual(mon.gainExperience(RareCandy.xp), RareCandy.xp - 1,
                       "적립되지 못한 몫을 반환한다")
        XCTAssertEqual(mon.levelExperience, PokemonBalance.maxLevelExperience,
                       "상한을 넘겨 저장하지 않는다")
        XCTAssertEqual(mon.level, PokemonBalance.maxLevel)
    }

    /// 손편집·구버전 세이브로 상한 위의 값이 들어와 있어도 더하는 순간 오버플로 트랩이 나면 안 된다.
    func testGainFromAnOverCapValueDoesNotOverflow() {
        var mon = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1)
        mon.levelExperience = Int.max
        // 넘친 몫은 **손상된 저장값이 아니라 이번에 넣은 양** 기준이다. 저장값 기준으로 세면
        // Int.max 어치를 환산해 지갑이 폭발한다.
        XCTAssertEqual(mon.gainExperience(RareCandy.xp), RareCandy.xp)
        XCTAssertEqual(mon.levelExperience, PokemonBalance.maxLevelExperience)
    }

    func testNonPositiveGainIsIgnored() {
        var mon = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1)
        XCTAssertEqual(mon.gainExperience(5_000_000), 0)
        XCTAssertEqual(mon.gainExperience(-1_000_000), 0, "음수는 넘친 몫으로도 세지 않는다")
        XCTAssertEqual(mon.levelExperience, 5_000_000, "음수 적립으로 레벨이 되감기지 않는다")
    }

    // MARK: 진행도 표시

    func testProgressIsFullAtMaxLevel() async {
        let s = store()
        await s.hatch(baseID: 20)
        s.debugAccrueLevelExperience(PokemonBalance.maxLevelExperience)

        XCTAssertEqual(s.currentLevel, PokemonBalance.maxLevel, "전제: 만렙에 닿았다")
        XCTAssertEqual(s.levelProgress, 1, "만렙 막대는 꽉 찬다 — 나머지가 0 이라고 빈 막대가 되면 안 된다")
        XCTAssertEqual(s.experienceToNextLevel, 0, "다음 레벨은 없다")
    }

    /// 대조군 — 구간 중간은 그 구간의 비율이어야 한다. 만렙 케이스만 두면 "항상 1" 도 통과한다.
    func testProgressIsProportionalBelowMaxLevel() async {
        let s = store()
        await s.hatch(baseID: 20)
        s.debugAccrueLevelExperience(PokemonBalance.experiencePerLevel * 2 + 5_000_000)

        XCTAssertEqual(s.currentLevel, 3)
        XCTAssertEqual(s.levelProgress, 0.5, accuracy: 0.0001)
    }

    // MARK: 누적 경로 (트리거 브랜치 = 상한 근처에서의 사탕 사용)

    func testRareCandyNearTheCapDoesNotStoreAnOverCapValue() async {
        let s = store()
        await s.hatch(baseID: 20)
        s.debugAccrueLevelExperience(PokemonBalance.maxLevelExperience - 1)
        s.debugAddCandy(1)

        _ = s.useRareCandy()

        XCTAssertEqual(s.state.active?.levelExperience, PokemonBalance.maxLevelExperience,
                       "사탕도 다른 누적 경로와 같은 상한을 지킨다")
        XCTAssertEqual(s.currentLevel, PokemonBalance.maxLevel)
    }

    // MARK: 외부 세이브 경계 (부류 스윕)

    /// `SaveTransfer.sanitized` 는 박스 개체만 자르고 **활성 개체의 경험치는 자르지 않았다.**
    /// 그 값에 사탕 XP 를 더하는 순간 오버플로 트랩으로 프로세스가 죽는다.
    func testSanitizeClampsTheActiveMonsExperience() throws {
        var state = CompanionState()
        var active = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                              rarity: .common, totalForms: 1)
        active.levelExperience = Int.max
        state.active = active
        var boxed = active
        boxed.levelExperience = Int.max
        state.boxedMons = [boxed]

        let clean = SaveTransfer.sanitized(state)

        XCTAssertEqual(clean.active?.levelExperience, PokemonBalance.maxLevelExperience)
        XCTAssertEqual(clean.boxedMons.first?.levelExperience, PokemonBalance.maxLevelExperience)
    }

    // MARK: 상한 초과분 환산 (#82)
    //
    // 상한에 걸린 경험치는 **말없이 사라졌다.** 해안 모험 10회면 상한에 닿으므로 정상 플레이로
    // 도달하고, 그 뒤로 모험은 파트너에게 아무 의미가 없다. 초과분을 별의조각으로 되돌린다.
    // 환율은 모험 보상이 이미 쓰는 비(분당 120,000 XP : 8 ⭐ = 15,000 : 1)의 절반이다.

    /// 이 테스트들이 기대하는 환율. 구현 상수를 그대로 읽지 않고 여기 한 번 더 적는다 —
    /// 상수를 읽으면 상수를 바꾸는 순간 테스트도 같이 따라가 아무것도 지키지 않는다.
    private let expectedExperiencePerStarPiece = 30_000

    /// 환율의 **근거**를 고정한다. 30,000 은 임의의 숫자가 아니라 모험 보상이 이미 쓰는 비율의
    /// 절반이다. 존 배율은 경험치·별의조각 양쪽에 똑같이 곱해져 약분되므로 이 비는 모든 존·모든
    /// 길이에서 15,000 : 1 로 같다 — 모험 계수를 재조정하면서 이 상수를 안 따라가면 여기서 걸린다.
    func testOverflowRateIsHalfTheRateAdventuresAlreadyPay() {
        for minutes in [25, 50, 90, 120] {
            let amounts = AdventureRules.amounts(minutes: minutes)
            XCTAssertEqual(amounts.experience / amounts.starPieces, 15_000,
                           "\(minutes)분 모험은 15,000 XP 마다 별의조각 1을 준다")
        }
        XCTAssertEqual(PokemonBalance.experiencePerOverflowStarPiece, 15_000 * 2,
                       "초과분 환율은 모험 환율의 절반이다 — 동등 환율이면 만렙 수입이 두 배가 된다")
        XCTAssertEqual(PokemonBalance.experiencePerOverflowStarPiece, expectedExperiencePerStarPiece)
    }

    /// 환산 함수의 경계 — 1 별의조각에 못 미치는 몫과 음수는 0 이다(음수가 지갑을 깎으면 안 된다).
    func testOverflowConversionFloorsAndRefusesNegatives() {
        XCTAssertEqual(PokemonBalance.starPieces(forOverflowExperience: 0), 0)
        XCTAssertEqual(PokemonBalance.starPieces(forOverflowExperience: 29_999), 0, "1 ⭐ 에 못 미치면 0")
        XCTAssertEqual(PokemonBalance.starPieces(forOverflowExperience: 30_000), 1)
        XCTAssertEqual(PokemonBalance.starPieces(forOverflowExperience: -90_000), 0, "음수는 지갑을 깎지 않는다")
    }

    /// 만렙 파트너의 모험 경험치는 통째로 버려졌다. 이제 별의조각으로 돌아와야 한다.
    func testMaxLevelAdventureConvertsDiscardedExperienceIntoStardust() async throws {
        let clock = TestClock()
        let s = await maxedStore(clock)
        let before = s.state.starPieces

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)
        let reward = try XCTUnwrap(s.claimAdventure())

        XCTAssertEqual(s.state.active?.levelExperience, PokemonBalance.maxLevelExperience,
                       "전제: 경험치는 상한에 묶여 한 톨도 오르지 않는다")
        let converted = reward.experience / expectedExperiencePerStarPiece
        XCTAssertGreaterThan(converted, 0, "전제: 이 정산은 환산할 초과분을 만든다")
        XCTAssertEqual(s.state.starPieces - before,
                       reward.stardust + reward.trainerBonus + reward.missionBonus
                           + reward.achievementBonus + reward.seasonBonus + converted,
                       "버려진 경험치가 별의조각으로 돌아와야 한다")
        // 보상 객체가 그 몫을 실제로 **들고 있어야** 한다. 지갑만 맞고 객체가 모르면 화면과
        // 대화가 설명하지 못하는 증가분이 된다(완전설명 계약).
        XCTAssertEqual(reward.overflowExperience, reward.experience, "전량이 초과분이다")
        XCTAssertEqual(reward.overflowBonus, converted)
        XCTAssertEqual(reward.appliedExperience, 0, "만렙에 들어간 경험치는 0 이다")
        XCTAssertEqual(reward.totalStardust, s.state.starPieces - before,
                       "totalStardust 하나로 지갑 증가분이 전부 설명돼야 한다")
    }

    /// 상한을 **걸치는** 정산 — 일부는 경험치로 들어가고 나머지만 환산된다. 만렙 시드와 상한 아래
    /// 시드만 두면 "전부 아니면 전무" 구현도 통과한다.
    func testAdventureStraddlingTheCapSplitsBetweenExperienceAndStardust() async throws {
        let clock = TestClock()
        let s = store(clock)
        await s.hatch(baseID: 20)
        let room = 5_000_000
        s.debugAccrueLevelExperience(PokemonBalance.maxLevelExperience - room)
        let before = s.state.starPieces

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)
        let reward = try XCTUnwrap(s.claimAdventure())

        XCTAssertEqual(reward.appliedExperience, room, "빈 자리만큼만 경험치로 들어간다")
        XCTAssertEqual(reward.overflowExperience, reward.experience - room, "나머지가 초과분이다")
        XCTAssertEqual(s.state.active?.levelExperience, PokemonBalance.maxLevelExperience)
        XCTAssertEqual(reward.totalStardust, s.state.starPieces - before)
    }

    /// **받을 개체가 아예 없는 정산.** 모험 중에 알을 부화기에 넣으면 파트너가 비는데
    /// (`beginIncubatingFocusEgg` 는 모험을 막지 않는다) 모험은 그대로 정산된다. 예전엔
    /// `claimAdventure` 가 `if state.active != nil` 로 경험치 블록을 통째로 건너뛰어 전량이 조용히
    /// 사라졌고, 그러면서 `appliedExperience` 는 전량 적립됐다고 보고했다 — 대화 도구가 그 값을
    /// 그대로 싣는다. 상한 초과분과 **같은 부류**라 처분도 같아야 한다.
    func testAdventureWithoutAPartnerConvertsInsteadOfDroppingExperience() async throws {
        let clock = TestClock()
        let s = store(clock)
        await s.hatch(baseID: 20)
        // 알 하나를 모은다 — 120분 모험 2회면 조각(6+1, 6)이 10을 넘어 알 1개가 된다.
        for _ in 0..<2 {
            XCTAssertTrue(s.startFocusAdventure(minutes: 120))
            clock.advance(120 * 60)
            _ = s.claimAdventure()
        }
        XCTAssertGreaterThan(s.focusEggCount, 0, "테스트 전제: 알이 생겼다")

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        XCTAssertTrue(s.beginIncubatingFocusEgg(), "테스트 전제: 모험 중에도 부화기에 넣을 수 있다")
        XCTAssertNil(s.state.active, "테스트 전제: 정산 시점에 파트너가 없다")
        let before = s.state.starPieces

        clock.advance(120 * 60)
        let reward = try XCTUnwrap(s.claimAdventure())

        XCTAssertEqual(reward.appliedExperience, 0, "받을 개체가 없으면 들어간 경험치는 0 이다")
        XCTAssertEqual(reward.overflowExperience, reward.experience, "전량이 초과분이다")
        XCTAssertEqual(reward.totalStardust, s.state.starPieces - before,
                       "파트너가 없어도 지갑 증가분이 전부 설명돼야 한다")
    }

    /// 대조군 — 상한 아래에서는 환산이 일어나지 않는다. 만렙 케이스만 두면 "항상 환산한다" 는
    /// 구현도 통과한다.
    func testAdventureBelowTheCapConvertsNothing() async throws {
        let clock = TestClock()
        let s = store(clock)
        await s.hatch(baseID: 20)
        let before = s.state.starPieces

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)
        let reward = try XCTUnwrap(s.claimAdventure())

        XCTAssertEqual(s.state.active?.levelExperience, reward.experience, "전제: 전량 적립됐다")
        XCTAssertEqual(s.state.starPieces - before,
                       reward.stardust + reward.trainerBonus + reward.missionBonus
                           + reward.achievementBonus + reward.seasonBonus,
                       "상한 아래에서는 환산분이 붙지 않는다")
    }

    /// 만렙에서 이상한 사탕은 소모만 되고 **아무 일도 일어나지 않았다.** 상점에서 5,000 별의조각에
    /// 파는 아이템이라 함정 구매가 된다(defect-log: 쓸 수 없는 대상에만 쓰이는 아이템 부류).
    ///
    /// 막지 않고 환산하는 이유: 사탕은 `usedAtStage` 도 밀어서, 레벨 메타데이터가 없는 진화
    /// (`applyUsage` 의 `usedAtStage >= threshold` 분기)의 유일한 공급원이다. 만렙에서 막으면
    /// 그 개체의 진화 경로가 영영 닫힌다.
    func testRareCandyAtMaxLevelPaysStardustInsteadOfNothing() async {
        let clock = TestClock()
        let s = await maxedStore(clock)
        s.debugAddCandy(1)
        let before = s.state.starPieces

        XCTAssertEqual(s.useRareCandy(), .progressed)

        XCTAssertEqual(s.rareCandyCount, 0, "전제: 사탕은 소모됐다")
        XCTAssertEqual(s.state.starPieces - before, RareCandy.xp / expectedExperiencePerStarPiece,
                       "만렙 사탕은 사라지지 않고 별의조각으로 돌아와야 한다")
        // 피드백 배너가 단위를 알아야 한다 — 같은 숫자를 "+XP" 로 그리면 오르지도 않은 경험치를
        // 올랐다고 보여 준다.
        XCTAssertEqual(s.candyFeedbackXP, 0, "만렙에서는 경험치로 들어간 몫이 없다")
        XCTAssertEqual(s.candyFeedbackStardust, RareCandy.xp / expectedExperiencePerStarPiece,
                       "배너 금액도 XP 가 아니라 환산된 별의조각이다")
    }

    /// 대조군 — 상한 아래의 사탕은 경험치로 들어가고 별의조각을 주지 않는다.
    func testRareCandyBelowTheCapPaysNoStardust() async {
        let clock = TestClock()
        let s = store(clock)
        await s.hatch(baseID: 20)
        s.debugAddCandy(1)
        let before = s.state.starPieces

        XCTAssertEqual(s.useRareCandy(), .progressed)

        XCTAssertEqual(s.state.active?.levelExperience, RareCandy.xp, "전제: 전량 적립됐다")
        XCTAssertEqual(s.state.starPieces, before, "상한 아래에서는 환산분이 없다")
        XCTAssertEqual(s.candyFeedbackXP, RareCandy.xp, "여전히 경험치 단위로 알린다")
        XCTAssertEqual(s.candyFeedbackStardust, 0)
    }

    /// **트리거 브랜치 — 사탕 하나가 상한을 걸친다.** 일부는 경험치로 들어가고 나머지만 환산되는데,
    /// 배너는 `converted > 0 ? converted : RareCandy.xp` 로 **둘 중 하나만 골랐다**(#192). 그래서
    /// 이 케이스에서 실제로 들어간 경험치가 통째로 화면에서 사라졌다.
    ///
    /// 만렙 시드와 상한 아래 시드만 두면 그 배타 선택도 계속 통과한다 — 위 두 대조군이 못 걸른
    /// 자리가 정확히 여기다.
    func testRareCandyStraddlingTheCapReportsBothUnits() async {
        let clock = TestClock()
        let s = store(clock)
        await s.hatch(baseID: 20)
        let room = 30_000_000                          // 사탕 100M 중 30M 만 들어갈 자리를 남긴다
        s.debugAccrueLevelExperience(PokemonBalance.maxLevelExperience - room)
        s.debugAddCandy(1)

        XCTAssertEqual(s.useRareCandy(), .progressed)

        XCTAssertEqual(s.candyFeedbackXP, room, "빈 자리만큼은 경험치로 들어갔다 — 숨기면 안 된다")
        XCTAssertEqual(s.candyFeedbackStardust, (RareCandy.xp - room) / expectedExperiencePerStarPiece,
                       "나머지는 환산분이다")
        XCTAssertGreaterThan(s.candyFeedbackStardust, 0, "전제: 이 사용은 환산할 초과분을 만든다")
    }

    /// **범위 밖 결정 고정** — 트레이너 레벨(99) 초과 포인트는 환산하지 않는다(#82, 2026-09-01).
    /// 포인트는 분 단위고 보상은 `500 × 레벨` 이라 경험치처럼 코드에서 유도되는 환율이 없고,
    /// 만렙 상태는 화면에 이미 드러난다(`progress == 1`, `pointsToNextLevel == nil`).
    /// 이 테스트가 빨개지면 그건 회귀가 아니라 **결정이 바뀐 것**이다.
    func testTrainerPointsAtMaxLevelAreNotConverted() async throws {
        let clock = TestClock()
        let url = tempURL()
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"trainer":{"points":\#(TrainerLevel.maximumPoints)}}"#
        try Data(json.utf8).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: stubMaxLevelLine), clock: clock.closure,
                               fileURL: url, rng: SeededRNG(seed: 7))
        await s.hatch(baseID: 20)
        XCTAssertEqual(s.trainerLevel.points, TrainerLevel.maximumPoints, "테스트 전제: 트레이너가 만렙이다")

        XCTAssertTrue(s.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)
        let reward = try XCTUnwrap(s.claimAdventure())

        XCTAssertEqual(s.trainerLevel.points, TrainerLevel.maximumPoints, "포인트는 상한에 머문다")
        XCTAssertEqual(reward.trainerBonus, 0, "환산하지 않으므로 보너스도 없다")
    }
}
