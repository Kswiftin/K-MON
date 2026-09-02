import XCTest
@testable import PokeTokenBar

/// 정산 **밖**의 별의조각 지급을 화면이 설명하는가(#200).
///
/// #192 는 정산 경로 하나만 고쳤다. 같은 부류가 진화 · 레이스 · 배틀 · 웨이브 런 · 졸업
/// 다섯 경로에 그대로 남아 있었다 — `recordAchievement` 형제 넷이 `@discardableResult` 라
/// 반환값(이미 지갑에 들어간 별의조각)을 버려도 경고 한 줄 안 났다. 지갑은 늘고 이유는
/// 어디에도 없었다.
///
/// 이 파일 전체가 "알림을 끈 사용자" 의 경로다 — `swift test` 안에서는 `AppEnv.isBundledApp`
/// 이 false 라 `notifyCompanionEvent` 가 **한 통도** 나갈 수 없다. 여기서 지급이 설명되면
/// 그 사용자에게도 설명된다.
@MainActor
final class StardustPayoutSurfaceTests: XCTestCase {

    // MARK: 다섯 경로 — 지갑 증가분이 배너 하나로 설명되는가

    /// 진화. 1단계 문턱이 **3회**라 한 개체를 4단 라인으로 세 번 진화시켜야 지급이 난다.
    func testEvolutionPayoutIsExplainedOnScreen() async throws {
        let store = makeStore(fourStageLine)
        await store.hatch(baseID: 1)
        advanceOneStage(store, totalForms: 4, stageIndex: 0)
        advanceOneStage(store, totalForms: 4, stageIndex: 1)
        XCTAssertNil(store.lastPayout, "전제: 문턱을 넘기 전에는 지급도 배너도 없다")

        let before = store.state.starPieces
        advanceOneStage(store, totalForms: 4, stageIndex: 2)   // 3회째 — 1단계 문턱

        try assertPayoutExplains(store, walletBefore: before, source: .evolve)
    }

    /// 포켓슬론 완주. 호출부가 스토어 밖(`MultiplayerRoomCenter`)이라 반환값을 받을 뷰가 없다 —
    /// 표면을 스토어에 둬야 하는 이유가 이 경로에 그대로 있다.
    func testRaceFinishPayoutIsExplainedOnScreen() async throws {
        let store = makeStore(fourStageLine)
        await store.hatch(baseID: 1)
        let before = store.state.starPieces

        store.recordRaceFinish()

        try assertPayoutExplains(store, walletBefore: before, source: .race)
    }

    /// LAN 배틀 승리. 1단계 문턱이 1승이라 첫 승리에서 바로 지급된다.
    func testBattleWinPayoutIsExplainedOnScreen() async throws {
        let store = makeStore(fourStageLine)
        await store.hatch(baseID: 1)
        let before = store.state.starPieces

        store.grantBattleReward(won: true, participantCount: 2, mode: .freeForAll,
                                opponentNames: ["Rival"])

        try assertPayoutExplains(store, walletBefore: before, source: .battle)
    }

    /// 웨이브 런 클리어.
    func testWaveRunClearPayoutIsExplainedOnScreen() async throws {
        let store = makeStore(fourStageLine)
        await store.hatch(baseID: 1)
        let before = store.state.starPieces

        store.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true)

        try assertPayoutExplains(store, walletBefore: before, source: .dungeon)
    }

    /// **트리거 브랜치 — 두 트랙이 한 판에 함께 터진다.** 갈림길을 전부 위험한 길로 온 클리어는
    /// `dungeon` 과 `dungeonSweep` 을 같이 올린다. 지급마다 배너를 띄우면 같은 판을 두 번
    /// 말하게 되므로(`mergedCompletion` 이 미션에서 막은 그 문제), 한 통으로 합산해야 한다.
    func testARiskyOnlyClearReportsBothTracksInOneBanner() async throws {
        let store = makeStore(fourStageLine)
        await store.hatch(baseID: 1)
        let before = store.state.starPieces
        let seqBefore = store.payoutFeedbackSeq

        store.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true,
                              tookOnlyRiskyRoutes: true)

        let payout = try assertPayoutExplains(store, walletBefore: before, source: .dungeon)
        XCTAssertEqual(store.payoutFeedbackSeq, seqBefore + 1,
                       "두 트랙이 함께 올랐어도 배너는 한 통이다")
        let plain = makeStore(fourStageLine)
        await plain.hatch(baseID: 1)
        plain.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true)
        let plainPayout = try XCTUnwrap(plain.lastPayout).stardust
        XCTAssertGreaterThan(payout, plainPayout, "전제: 스윕이 실제로 더 준다 — 합산이 한쪽을 지웠다면 같아진다")
    }

    /// 졸업. 한 함수 안에서 **넷**이 같은 지갑에 넣는다 — 트레이너 포인트 · 주간 미션 ·
    /// 시즌 챌린지 · 도감 목표. 하나만 배너에 실으면 나머지는 여전히 무설명이다.
    func testGraduationPayoutIsExplainedOnScreen() async throws {
        let store = makeStore(threeStageLine)
        await store.hatch(baseID: 1)
        advanceOneStage(store, totalForms: 3, stageIndex: 0)
        advanceOneStage(store, totalForms: 3, stageIndex: 1)
        XCTAssertTrue(store.canGraduate, "전제: 최종형에 닿아 졸업 버튼이 뜬다")

        let before = store.state.starPieces
        XCTAssertTrue(store.graduateCompanion())

        try assertPayoutExplains(store, walletBefore: before, source: .graduation)
    }

    // MARK: 계약 — 정산과 겹치지 않고, 한 번만 건네지고, 남의 세이브로 넘어가지 않는다

    /// 정산 경로는 이 배너를 **쓰지 않는다** — 지급을 `AdventureReward` 에 실어 이미 설명한다.
    /// 여기서 함께 띄우면 같은 별의조각을 두 번 말하게 된다.
    func testASettlementDoesNotAlsoFireThePayoutBanner() async {
        let clock = TestClock()
        let store = await maxLevelStore(clock, tag: "payout")
        XCTAssertTrue(store.startFocusAdventure(minutes: 120))
        clock.advance(120 * 60)

        XCTAssertNotNil(store.claimAdventure())

        XCTAssertNotNil(store.lastClaim, "전제: 정산은 정산 배너로 설명된다")
        XCTAssertNil(store.lastPayout, "정산분을 지급 배너가 또 말하면 같은 값이 두 번 보고된다")
    }

    /// 지급이 없으면 배너도 없다 — "항상 띄운다" 구현을 가른다. 진 배틀은 아무것도 주지 않는다.
    func testALostBattleLeavesTheBannerEmpty() async {
        let store = makeStore(fourStageLine)
        await store.hatch(baseID: 1)

        store.grantBattleReward(won: false, participantCount: 2, mode: .freeForAll,
                                opponentNames: ["Rival"])

        XCTAssertNil(store.lastPayout, "0 을 띄우면 문턱을 못 넘은 판마다 배너가 뜬다")
    }

    /// 1회성 계약 — 기존 피드백(`consumeClaimFeedback`·`consumeCandyFeedback`)과 같은 형태다.
    /// 소비하지 않으면 다른 탭에 갔다 돌아올 때 같은 배너가 다시 떠오른다.
    func testThePayoutBannerIsHandedOverOnlyOnce() async {
        let store = makeStore(fourStageLine)
        await store.hatch(baseID: 1)
        let seqBefore = store.payoutFeedbackSeq

        store.recordRaceFinish()

        XCTAssertEqual(store.payoutFeedbackSeq, seqBefore + 1, "seq 가 올라야 뷰가 새 배너를 감지한다")
        XCTAssertNotNil(store.lastPayout)
        store.consumePayoutFeedback()
        XCTAssertNil(store.lastPayout, "소비 후에는 남지 않는다")
    }

    /// 세이브를 불러오면 이전 세이브 기준의 지급은 설명할 대상이 아니다. 값만 비우면 뷰가 이미
    /// 건네받아 들고 있는 사본에 닿지 못하므로 seq 까지 올려 "비었다" 를 알려야 한다(#192).
    func testImportingASaveDropsThePayoutBanner() async throws {
        let clock = TestClock()
        let store = makeStore(fourStageLine, clock: clock)
        await store.hatch(baseID: 1)
        store.recordRaceFinish()
        XCTAssertNotNil(store.lastPayout, "전제: 불러오기 전에 배너가 떠 있다")
        let seqAfterPayout = store.payoutFeedbackSeq

        let data = try SaveTransfer.encode(state: CompanionState(), appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: clock.now)
        try store.applySave(try SaveTransfer.decode(data))

        XCTAssertNil(store.lastPayout, "남의 세이브를 불러왔으면 이전 지급은 설명할 대상이 아니다")
        XCTAssertNotEqual(store.payoutFeedbackSeq, seqAfterPayout,
                          "seq 가 그대로면 뷰는 남의 세이브 지급액을 계속 그린다")
    }

    // MARK: 도구

    /// 이 파일의 유일한 단정 형태 — **지갑 증가분 전부**가 배너 하나로 설명되는가.
    /// 금액 상수를 적지 않는다: 사다리 표가 바뀌어도 계약은 그대로여야 한다.
    @discardableResult
    private func assertPayoutExplains(_ store: CompanionStore, walletBefore: Int,
                                      source: StardustPayout.Source,
                                      file: StaticString = #filePath, line: UInt = #line) throws -> Int {
        XCTAssertFalse(AppEnv.isBundledApp,
                       "테스트 전제: 여기서는 알림이 나갈 수 없다 — 배너가 유일한 설명이다",
                       file: file, line: line)
        let delta = store.state.starPieces - walletBefore
        XCTAssertGreaterThan(delta, 0, "전제: 이 경로가 실제로 지갑을 늘렸다", file: file, line: line)
        let payout = try XCTUnwrap(store.lastPayout, "지갑이 늘었는데 화면에 남긴 게 없다", file: file, line: line)
        XCTAssertEqual(payout.source, source, file: file, line: line)
        XCTAssertEqual(payout.stardust, delta,
                       "배너 하나로 지갑 증가분이 전부 설명돼야 한다", file: file, line: line)
        return payout.stardust
    }

    private func advanceOneStage(_ store: CompanionStore, totalForms: Int, stageIndex: Int) {
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: totalForms,
                                                       stageIndex: stageIndex))
    }

    private func makeStore(_ line: EvoLine, clock: TestClock = TestClock()) -> CompanionStore {
        CompanionStore(provider: StubProvider(value: line), clock: clock.closure,
                       fileURL: stubStoreURL("payout"), rng: SeededRNG(seed: 11))
    }
}

// 진화 3회(= `evolve` 1단계 문턱)를 한 개체로 밟기 위한 4단 라인.
private let fourStageLine = payoutLine(
    base: 1, tree: EvoNode(speciesID: 1, children: [
        EvoNode(speciesID: 2, children: [
            EvoNode(speciesID: 3, children: [EvoNode(speciesID: 4, children: [])])
        ])
    ]))

// 졸업용 — 레벨 관문이 없어 최종형에 닿으면 면제로 졸업할 수 있다.
private let threeStageLine = payoutLine(
    base: 1, tree: EvoNode(speciesID: 1, children: [
        EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])
    ]))

private func payoutLine(base: Int, tree: EvoNode) -> EvoLine {
    func ids(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(ids) }
    var names: [Int: [String: String]] = [:]
    for id in ids(tree) { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: base, tree: tree, rarity: .common, names: names)
}
