import Observation
import XCTest
@testable import PokeTokenBar

// MARK: 헬퍼 (CompanionTests 의 private 라인 헬퍼와 독립)

private func rcNode(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }
private func rcLine(base: Int, tree: EvoNode, rarity: Rarity = .common) -> EvoLine {
    func ids(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(ids) }
    var names: [Int: [String: String]] = [:]
    for id in ids(tree) { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: base, tree: tree, rarity: rarity, names: names)
}
private let rcLinear3 = rcLine(base: 1, tree: rcNode(1, [rcNode(2, [rcNode(3)])]))   // 커먼 3형태: 125M/250M/375M
private let rcNoEvo = rcLine(base: 20, tree: rcNode(20))                              // 커먼 1형태: 750M 단일
private let rcNow = Date(timeIntervalSince1970: 1_700_000_000)

/// line() 이 throw 하는 provider — 라인 미로딩(오프라인/재시작 직후) 상태 재현용.
private struct RCLineThrows: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

// MARK: 하위호환 디코딩

final class InventoryDecodeTests: XCTestCase {
    /// 구버전 저장(인벤토리 키 없음)도 깨지지 않고 기본값으로 로드.
    func testDecodesWithoutInventoryFields() throws {
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"usedSinceInstall":5,"dex":[],"language":"ko"}"#
        let s = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(s.inventory, [:])
    }

    func testInventoryRoundTrip() throws {
        var st = CompanionState()
        st.inventory = ["rareCandy": 3]
        let round = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(round.inventory, ["rareCandy": 3])
    }
}

// MARK: 사용 (useRareCandy)

@MainActor
final class RareCandyStoreTests: XCTestCase {
    private func store(_ line: EvoLine, seed: UInt64 = 7) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rc-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { rcNow }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    /// 사탕 n개 주입 — 일일 지급 경로를 우회하는 테스트 헬퍼(사용 로직만 검증).
    private func giveCandies(_ s: CompanionStore, _ n: Int) { s.debugAddCandy(n) }

    // MARK: 홈 헤더 바로가기

    /// 홈 헤더의 사탕 버튼은 **가방과 같은 판정**(`canUseRareCandy`)으로 나타나야 한다.
    /// 조건을 따로 쓰면 가방에선 회색인데 홈에선 눌리는(또는 그 반대) 두 화면이 생긴다.
    /// 뷰 계층이라 순수 함수로 못 재서 소스에서 본다 — 주석은 뺀다(가드가 자기 설명에 걸린다).
    func testHomeCandyShortcutSharesTheBagsEligibilityCheck() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func code(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let comment = line.range(of: "//") else { return String(line) }
                    return String(line[..<comment.lowerBound])
                }
                .joined(separator: "\n")
        }
        let home = try code("Sources/PokeTokenBar/UI/CompanionView.swift")
        XCTAssertTrue(home.contains("store.canUseRareCandy"),
                      "재고·알 상태 판정을 여기서 다시 쓰면 가방과 갈린다")
        XCTAssertTrue(home.contains("store.useRareCandy()"), "실제 소비는 스토어가 한다")
        // 확인 없이 바로 먹으면 되돌릴 수 없는 소비가 오탭 한 번으로 일어난다.
        XCTAssertTrue(home.contains("confirmationDialog"), "한 번 물어야 한다")
        // 확인창은 버튼이 아니라 사라지지 않는 부모에 붙어야 한다. 마지막 사탕을 쓰면 버튼이
        // 없어지는데, 창을 그 버튼에 매달면 자기 액션 때문에 창의 주인이 사라진다.
        let buttonBody = try XCTUnwrap(home.range(of: "private var rareCandyButton"))
        let afterButton = home[buttonBody.upperBound...].prefix(400)
        XCTAssertFalse(afterButton.contains("confirmationDialog"),
                       "확인창을 사라질 뷰에 매달면 안 된다")
        XCTAssertTrue(home.contains("l.useOnCurrent"), "확인 문구도 가방과 같은 것을 쓴다")
    }

    /// 재고가 없으면 버튼이 나오지 않아야 한다 — 판정 자체를 잠근다(위 가드가 보는 그 값).
    func testEligibilityFollowsStockAndHatchState() async {
        let s = store(rcLinear3)
        XCTAssertFalse(s.canUseRareCandy, "부화 전에는 버튼이 없어야 한다")
        await s.hatch(baseID: 1)
        XCTAssertFalse(s.canUseRareCandy, "재고가 없으면 버튼이 없어야 한다")
        giveCandies(s, 2)
        XCTAssertTrue(s.canUseRareCandy)
    }

    /// **마지막 하나를 쓰면 그 자리에서 사라진다.** 남은 개수가 0 인데 아이콘이 남아 있으면
    /// 눌렀을 때 아무 일도 안 나는 버튼이 된다 — 이 파일이 여러 번 밟은 "무반응" 부류다.
    func testTheShortcutDisappearsAfterSpendingTheLastCandy() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        giveCandies(s, 2)

        // 결과 종류(진행/진화)는 이 테스트의 관심사가 아니다 — 다른 테스트가 잠근다.
        // 여기서 보는 건 **재고와 노출 판정**뿐이다.
        _ = s.useRareCandy()
        XCTAssertEqual(s.rareCandyCount, 1)
        XCTAssertTrue(s.canUseRareCandy, "아직 하나 남았으면 그대로 보인다")

        _ = s.useRareCandy()
        XCTAssertEqual(s.rareCandyCount, 0)
        XCTAssertFalse(s.canUseRareCandy, "다 쓰면 아이콘이 사라져야 한다")
        XCTAssertEqual(s.useRareCandy(), .unavailable, "그래도 눌렀다면 아무 일도 없어야 한다")
    }


    /// 사탕 XP(100M) < 최소 임계(125M) → 진화 못 시키는 케이스는 부분 진행(.progressed), 통계 불변.
    func testUseProgressesWithoutEvolution() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        giveCandies(s, 1)
        XCTAssertEqual(s.rareCandyCount, 1)
        let before = s.state.usedSinceInstall
        let result = s.useRareCandy()
        XCTAssertEqual(result, .progressed)
        XCTAssertEqual(s.state.active?.usedAtStage, RareCandy.xp)
        XCTAssertEqual(s.state.active?.stageIndex, 0)
        XCTAssertEqual(s.rareCandyCount, 0, "재고 1 소모")
        XCTAssertEqual(s.state.usedSinceInstall, before, "사탕 XP 는 생산 통계에 안 잡힘")
    }

    /// 잔여가 사탕XP 이하인 단계에서 사용 → 정확히 1단계 진화.
    func testUseEvolvesWhenCrossingThreshold() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        s.applyUsage(50_000_000)   // stage0(125M) 잔여 75M ≤ 100M
        giveCandies(s, 1)
        let result = s.useRareCandy()
        XCTAssertEqual(result, .evolved)
        XCTAssertEqual(s.currentSpeciesID, 2)
        XCTAssertEqual(s.state.active?.stageIndex, 1)
    }

    /// [불변식] 사탕 1개 = 최대 1단계 — 임계 직전(124M)에서 써도 2단계 연쇄 안 됨.
    func testSingleCandyAdvancesAtMostOneStage() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        s.applyUsage(124_000_000)   // stage0 임계 직전
        giveCandies(s, 1)
        _ = s.useRareCandy()        // +100M → 224M: stage0(125M) 1회만, stage1(250M) 미달
        XCTAssertEqual(s.state.active?.stageIndex, 1, "최대 1단계")
    }

    /// 최종단계에서 사탕을 써도 졸업은 자동으로 안 된다(#19) — 성장만 반영되고, 졸업은 별도 액션이다.
    func testUseOnFinalStageProgressesAndLeavesGraduationToThePlayer() async {
        let s = store(rcNoEvo)
        await s.hatch(baseID: 20)
        s.applyUsage(700_000_000)   // 졸업 총량 750M 잔여 50M ≤ 100M
        s.debugAccrueLevelExperience(200_000_000)   // 졸업은 레벨 30 게이트도 넘어야 한다(#19) — 사탕 XP(100M)와 합쳐 31
        giveCandies(s, 1)
        XCTAssertEqual(s.useRareCandy(), .progressed, "사탕은 성장만 시킨다")
        XCTAssertNotNil(s.state.active, "졸업은 사용자가 누르기 전까진 일어나지 않는다")
        XCTAssertTrue(s.canGraduate, "대신 졸업 버튼 조건은 충족된다")
        XCTAssertTrue(s.graduateCompanion())
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.dexEntries.count, 1)
    }

    /// [회귀] 졸업은 store 폴링 틱 없이도 스프라이트 정체성(currentSpeciesID/currentIsShiny)
    /// 관찰을 발화해야 한다 — AppDelegate.observeCompanionSprite 가 이 발화로 메뉴바 스프라이트를 즉시
    /// 갱신한다. 발화가 없으면 메뉴바가 다음 폴링(기본 120s)까지 이전 포켓몬으로 남는다
    /// (리포트: 사탕 졸업 직후 메뉴바 잔상). 진화(.evolved)도 같은 applyUsage 경로라 함께 보호된다.
    func testCandyGraduationFiresSpriteIdentityObservation() async {
        let s = store(rcNoEvo)
        await s.hatch(baseID: 20)
        s.applyUsage(700_000_000)   // 졸업 총량 750M 잔여 50M ≤ 100M
        s.debugAccrueLevelExperience(200_000_000)   // 졸업은 레벨 30 게이트도 넘어야 한다(#19) — 사탕 XP(100M)와 합쳐 31
        giveCandies(s, 1)
        let fired = expectation(description: "sprite identity observation fired")
        withObservationTracking {
            _ = s.currentSpeciesID
            _ = s.currentIsShiny
        } onChange: { fired.fulfill() }
        XCTAssertEqual(s.useRareCandy(), .progressed)
        XCTAssertTrue(s.graduateCompanion(), "졸업은 사용자 액션(#19)")
        await fulfillment(of: [fired], timeout: 1)
        XCTAssertNil(s.currentSpeciesID, "졸업 → 알(메뉴바 스프라이트 키 nil)")
    }

    /// 알(부화 전)에는 사용 불가 — 재고가 있어도 소모되지 않는다.
    func testCannotUseOnEgg() {
        let s = store(rcLinear3)
        giveCandies(s, 2)
        XCTAssertTrue(s.isEgg)
        XCTAssertFalse(s.canUseRareCandy)
        XCTAssertEqual(s.useRareCandy(), .unavailable)
        XCTAssertEqual(s.rareCandyCount, 2, "알 상태에선 소모 안 됨")
    }

    /// 재고 0이면 사용 불가.
    func testCannotUseWithoutStock() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.rareCandyCount, 0)
        XCTAssertFalse(s.canUseRareCandy)
        XCTAssertEqual(s.useRareCandy(), .unavailable)
    }

    /// [회귀 가드] 활성 포켓몬이 있어도 라인 미로딩(재시작 직후·오프라인)이면 사용 불가 —
    /// 진화 없이 XP만 적립되는 것 방지. 재고가 있어도 소모되지 않는다.
    func testCannotUseWhileLineUnloaded() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rc-unloaded-\(UUID().uuidString).json")
        // 활성 포켓몬 + 사탕 1 을 저장 → RCLineThrows 로 로드하면 currentLine 이 nil.
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":3},"inventory":{"rareCandy":1},"dex":[],"collectedFinals":[]}"#
        try? json.data(using: .utf8)!.write(to: url)
        let s = CompanionStore(provider: RCLineThrows(), clock: { rcNow }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertNotNil(s.state.active, "활성 포켓몬 로드")
        XCTAssertNil(s.currentLine, "라인 미로딩(throws)")
        XCTAssertEqual(s.rareCandyCount, 1)
        XCTAssertFalse(s.canUseRareCandy)
        XCTAssertEqual(s.useRareCandy(), .unavailable)
        XCTAssertEqual(s.rareCandyCount, 1, "라인 미로딩 시 사탕 소모 안 됨")
    }

    /// 사용 시 "+XP" 피드백 seq 가 증가(진화 없이 부분 진행이어도).
    func testUseBumpsCandyFeedback() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        giveCandies(s, 1)
        let before = s.candyFeedbackSeq
        _ = s.useRareCandy()
        XCTAssertEqual(s.candyFeedbackSeq, before + 1)
        XCTAssertEqual(s.candyFeedbackXP, RareCandy.xp)
    }

    /// ownedItems 는 개수>0 아이템만 노출.
    func testOwnedItemsReflectsStock() async {
        let s = store(rcLinear3)
        XCTAssertTrue(s.ownedItems.isEmpty)
        giveCandies(s, 3)
        XCTAssertEqual(s.ownedItems.map(\.kind), [.rareCandy])
        XCTAssertEqual(s.ownedItems.first?.count, 3)
    }

    /// 데모 시나리오(구구 3형태, usedAtStage 100M, 사탕 3): 진화 → 부분성장 → 진화, 그 뒤 재고 0.
    func testSequentialCandyUseMatchesDemo() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        s.applyUsage(100_000_000)                      // stage0(125M) 도달 전
        giveCandies(s, 3)
        XCTAssertEqual(s.useRareCandy(), .evolved)     // 200M ≥125M → stage1, 이월 75M
        XCTAssertEqual(s.state.active?.stageIndex, 1)
        XCTAssertEqual(s.useRareCandy(), .progressed)  // 175M <250M → 부분성장
        XCTAssertEqual(s.state.active?.stageIndex, 1)
        XCTAssertEqual(s.useRareCandy(), .evolved)     // 275M ≥250M → stage2
        XCTAssertEqual(s.state.active?.stageIndex, 2)
        XCTAssertEqual(s.rareCandyCount, 0)
    }

    /// "+XP" 1회성 store 계약 — 사용 후 amount>0, consume 후 0(재렌더 재생 방지의 핵심).
    func testConsumeCandyFeedbackResets() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        giveCandies(s, 1)
        _ = s.useRareCandy()
        XCTAssertEqual(s.candyFeedbackXP, RareCandy.xp)
        s.consumeCandyFeedback()
        XCTAssertEqual(s.candyFeedbackXP, 0, "consume 후 0 — CompanionHeader 재마운트 시 재생 안 됨")
        XCTAssertEqual(s.candyFeedbackStardust, 0, "환산분도 함께 비운다 — 한쪽만 비우면 다시 떠오른다")
    }
}

// MARK: 일일 사탕 지급 (방치형 출석 보상 — tick 경로)

@MainActor
final class DailyCandyTests: XCTestCase {
    private func store(_ clock: TestClock) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("daily-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: rcLinear3), clock: clock.closure, fileURL: url, rng: SeededRNG(seed: 7))
    }

    func testFirstTickGrantsWelcomeCandy() {
        let s = store(TestClock())
        s.tick()
        XCTAssertEqual(s.rareCandyCount, RareCandy.dailyGrant)
    }

    func testSameDayNoRegrant() {
        let clock = TestClock()
        let s = store(clock)
        s.tick()
        clock.advance(3600)
        s.tick()
        XCTAssertEqual(s.rareCandyCount, RareCandy.dailyGrant, "같은 날 재지급 금지")
    }

    func testNextDayRegrants() {
        let clock = TestClock()
        let s = store(clock)
        s.tick()
        clock.advance(24 * 3600)
        s.tick()
        XCTAssertEqual(s.rareCandyCount, RareCandy.dailyGrant * 2)
    }

    /// [회귀] 지급 날짜는 영속 — 재시작(같은 파일 재로드) 후 같은 날 재지급 없음.
    func testGrantDatePersistsAcrossRestart() {
        let clock = TestClock()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("daily-persist-\(UUID().uuidString).json")
        let s1 = CompanionStore(provider: StubProvider(value: rcLinear3), clock: clock.closure, fileURL: url, rng: SeededRNG(seed: 1))
        s1.tick()
        XCTAssertEqual(s1.rareCandyCount, RareCandy.dailyGrant)
        let s2 = CompanionStore(provider: StubProvider(value: rcLinear3), clock: clock.closure, fileURL: url, rng: SeededRNG(seed: 1))
        s2.tick()
        XCTAssertEqual(s2.rareCandyCount, RareCandy.dailyGrant, "같은 날 재시작 — 재지급 금지")
    }
}

// MARK: 알림 문구 (제목 개수 · 일일 보상 본문)

final class CandyNotificationCopyTests: XCTestCase {
    /// 제목에 개수와 아이템명이 들어간다.
    func testTitleIncludesCountAndItem() {
        let l = L(.ko)
        let one = l.notifCandyTitle(item: l.itemName(.rareCandy), count: 1)
        XCTAssertTrue(one.contains("이상한 사탕"))
        XCTAssertTrue(one.contains("1개"), one)
    }

    /// 일일 보상 본문은 비어 있지 않고 3개 언어 모두 존재.
    func testDailyBodyLocalizedAllLanguages() {
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L(lang).notifDailyCandyBody.isEmpty, "\(lang)")
        }
    }

    /// 3개 언어 모두 개수 치환 + 비어있지 않음.
    func testTitleLocalizedAllLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            let title = l.notifCandyTitle(item: l.itemName(.rareCandy), count: 3)
            XCTAssertTrue(title.contains("3"), "\(lang): \(title)")
            XCTAssertFalse(title.isEmpty)
        }
    }

}
