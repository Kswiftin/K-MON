import XCTest
import SwiftUI
@testable import PokeTokenBar

// 기술 호버 설명(#40).
// 증상: 기술 행에 마우스를 올려도 아무것도 안 뜬다.
// 원인: 설명이 `.help()` 네이티브 툴팁에만 실려 있었다 — SwiftUI 의 help 는 팝오버 안에서
// NSView.toolTip 도 툴팁 rect 도 남기지 않아(프로브로 확인) 사실상 표시 경로가 없었다.
// 수정: 목록 아래 고정 높이 슬롯에 호버한 기술의 설명을 직접 그린다.
@MainActor
final class MoveHoverTests: XCTestCase {

    private func move(descriptions: [String: String]? = nil) -> MoveSpec {
        MoveSpec(id: 53, names: ["ko": "화염방사", "en": "Flamethrower", "ja": "かえんほうしゃ"],
                 type: .fire, power: 90, damageClass: .special, accuracy: 100, pp: 15,
                 descriptions: descriptions)
    }

    private func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }

    private func renderedHeight(_ view: some View, width: CGFloat = 250) -> CGFloat {
        NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    // MARK: 표시 문구

    /// 아무것도 안 올렸을 때는 빈칸이 아니라 안내 문구가 나온다 — 슬롯이 왜 비었는지 알 수 있어야 한다.
    func testShowsHintWhenNothingHovered() {
        let text = L(.ko).moveHoverText(nil)
        XCTAssertFalse(text.isEmpty)
        XCTAssertEqual(text, L(.ko).moveHoverHint)
    }

    /// 설명이 있으면 그대로 보여준다.
    func testUsesDescriptionWhenPresent() {
        let m = move(descriptions: ["ko": "강렬한 불꽃을 발사해 공격한다.", "en": "The target is scorched."])
        XCTAssertEqual(L(.ko).moveHoverText(m), "강렬한 불꽃을 발사해 공격한다.")
        XCTAssertEqual(L(.en).moveHoverText(m), "The target is scorched.")
    }

    /// 트리거 브랜치 ①: descriptions 자체가 nil(합성 기술·fetch 실패). 빈칸 대신 스탯 요약이 나와야 한다.
    func testFallsBackToStatsWhenDescriptionsAreNil() {
        let text = L(.ko).moveHoverText(move(descriptions: nil))
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("90"), "위력이 빠졌다: \(text)")
        XCTAssertTrue(text.contains("100"), "명중이 빠졌다: \(text)")
        XCTAssertTrue(text.contains("15"), "PP 가 빠졌다: \(text)")
    }

    /// 트리거 브랜치 ②: 키는 있는데 값이 빈 문자열. 빈 슬롯이 되면 안 된다.
    func testFallsBackWhenDescriptionIsEmptyString() {
        let text = L(.ko).moveHoverText(move(descriptions: ["ko": "", "en": ""]))
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("90"), "빈 설명인데 스탯 폴백이 없다: \(text)")
    }

    /// 필중 기술(accuracy nil)도 명중란이 비지 않는다.
    func testAlwaysHitsMoveKeepsAccuracySlot() {
        var m = move()
        m.accuracy = nil
        let text = L(.ko).moveHoverText(m)
        XCTAssertTrue(text.contains(L(.ko).moveAlwaysHits), text)
    }

    /// 변화기는 위력이 0이라 "위력 0"이 아니라 "—"로 나와야 한다.
    /// (커버리지 게이트는 통과했지만 이 분기는 `^0` 이었다 — 라인 커버리지는 증거가 아니다.)
    func testStatusMoveShowsDashInsteadOfZeroPower() {
        let status = MoveSpec(id: 45, names: ["ko": "울음소리", "en": "Growl", "ja": "なきごえ"],
                              type: .normal, power: 0, damageClass: .status, accuracy: 100, pp: 40)
        let text = L(.ko).moveHoverText(status)
        XCTAssertTrue(text.contains("—"), "변화기인데 위력 자리가 —가 아니다: \(text)")
        XCTAssertFalse(text.contains("위력 0"), text)
    }

    /// en/ja 에서는 어떤 분기에서도 한글이 남으면 안 된다(#10 부류).
    func testNoHangulInNonKoreanLanguages() {
        for lang in [AppLanguage.en, .ja] {
            let l = L(lang)
            XCTAssertFalse(containsHangul(l.moveHoverHint), "\(lang) 안내에 한글: \(l.moveHoverHint)")
            XCTAssertFalse(containsHangul(l.moveHoverText(move(descriptions: nil))),
                           "\(lang) 폴백에 한글: \(l.moveHoverText(move(descriptions: nil)))")
            XCTAssertFalse(containsHangul(l.moveHoverText(nil)))
        }
        XCTAssertTrue(containsHangul(L(.ko).moveHoverHint))   // 대조군
    }

    // MARK: 호버 상태 전이

    /// 행에 들어가면 그 행이 선택된다.
    func testEnteringRowSelectsIt() {
        XCTAssertEqual(MoveListView.hoverState(current: nil, moveID: 7, isInside: true), 7)
    }

    /// 트리거 브랜치: A→B 로 옮길 때 B 진입이 먼저 오고 A 이탈이 뒤늦게 온다.
    /// 이탈 이벤트가 무조건 nil 로 지우면 방금 고른 B 가 사라져 슬롯이 깜빡인다.
    func testLeavingAnotherRowKeepsTheCurrentSelection() {
        XCTAssertEqual(MoveListView.hoverState(current: 8, moveID: 7, isInside: false), 8)
    }

    /// 이탈해도 마지막 기술을 유지한다.
    /// 60초 방치 틱이 팝오버를 다시 그리면 AppKit 이 트래킹 영역을 재설치하는데, 커서가 그대로면
    /// `mouseExited` 만 오고 재진입은 안 온다 — 이탈에서 지우면 마우스를 올려둔 채 설명이 사라진다.
    func testLeavingKeepsTheLastHoveredMove() {
        XCTAssertEqual(MoveListView.hoverState(current: 7, moveID: 7, isInside: false), 7)
        XCTAssertEqual(MoveListView.hoverState(current: 8, moveID: 7, isInside: false), 8)
    }

    /// 다른 행에 올리면 그 행으로 바뀐다 — 유지가 "안 바뀐다"가 되면 안 된다.
    func testEnteringAnotherRowReplacesTheSelection() {
        XCTAssertEqual(MoveListView.hoverState(current: 7, moveID: 9, isInside: true), 9)
    }

    // MARK: 호버 배선 (원래 결함 그 자체)

    /// 근본원인 회귀: `.help()` 는 AppKit 에 마우스 트래킹 영역을 하나도 안 만든다 —
    /// 그래서 팝오버 안에서 아무리 올려놔도 이벤트가 오지 않았다(프로브: help 0개 / onHover 1개).
    /// 기술 행마다 트래킹 영역이 실제로 설치되는지 본다. 툴팁만으로 되돌리면 여기서 걸린다.
    func testMoveRowsInstallHoverTracking() {
        let moves = (0..<MoveListView.maxRows).map {
            MoveSpec(id: 300 + $0, names: ["en": "Tackle", "ko": "몸통박치기"], type: .normal,
                     power: 40, damageClass: .physical, accuracy: 100, pp: 35)
        }
        let host = NSHostingController(rootView: MoveListView(store: hoverTestStore(moves),
                                                              maxWidth: 250))
        host.view.frame = CGRect(x: 0, y: 0, width: 250, height: 260)
        host.view.layoutSubtreeIfNeeded()
        _ = host.view.fittingSize
        // SwiftUI 는 호버 영역을 호스팅 뷰 하나의 트래킹 영역으로 합쳐 자체 히트테스트한다 —
        // 그래서 행 수를 세는 게 아니라 걸려 있느냐 없느냐를 본다.
        XCTAssertGreaterThanOrEqual(trackingAreaCount(host.view), 1,
                                    "기술 행에 마우스 트래킹이 안 걸려 있다 — 호버가 아예 안 온다")

        // 대조군: 툴팁만 단 뷰는 트래킹 영역이 0개다. 이게 원래 결함의 정체이자
        // 위 어서션이 통과만 하는 빈 검증이 아니라는 증거다.
        let helpOnly = NSHostingController(rootView:
            Text(verbatim: "Tackle").frame(width: 250, height: 30).help("설명"))
        helpOnly.view.frame = CGRect(x: 0, y: 0, width: 250, height: 30)
        helpOnly.view.layoutSubtreeIfNeeded()
        _ = helpOnly.view.fittingSize
        XCTAssertEqual(trackingAreaCount(helpOnly.view), 0,
                       ".help() 가 트래킹을 걸어준다면 이 테스트는 아무것도 지키지 않는다")
    }

    private func trackingAreaCount(_ view: NSView) -> Int {
        view.trackingAreas.count + view.subviews.reduce(0) { $0 + trackingAreaCount($1) }
    }

    private func hoverTestStore(_ moves: [MoveSpec]) -> CompanionStore {
        let url = storeStateURL("hover")
        let store = CompanionStore(provider: StubProvider(value: hoverTestLine),
                                   clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                   fileURL: url, rng: SeededRNG(seed: 3))
        store.debugSetDisplayedMoves(moves)
        return store
    }

    // MARK: 설명 출처 (PokéAPI flavor text)

    private let koNotice = "사용할 수 없는 기술입니다.\n다시 배우게 할 수 없지만\n기술을 잊게 하는 것을 권장합니다."
    private let enNotice = "This move can\u{2019}t be used.\nIt\u{2019}s recommended that this move is forgotten."
    private let jaNotice = "この技は\u{3000}使えません\n思い出すことが\u{3000}できなくなりますが"

    /// 트리거 재현: 삭제된 기술은 *최신* 버전 항목이 설명이 아니라 안내문이다(실측: move/return).
    /// 마지막 항목을 그대로 쓰면 "사용할 수 없는 기술입니다"가 설명 자리에 뜬다.
    func testSkipsUnusableNoticeAndKeepsTheRealDescription() {
        let picked = PokeAPIClient.flavorTexts([
            (language: "ko", text: "트레이너를 위해 전력으로 상대를 공격한다."),
            (language: "ko", text: koNotice),
        ], languages: ["ko", "en", "ja"])
        XCTAssertEqual(picked["ko"], "트레이너를 위해 전력으로 상대를 공격한다.")
    }

    /// 안내문이 없으면 종전대로 최신(마지막) 항목을 쓴다.
    func testKeepsTheNewestEntryWhenAllAreUsable() {
        let picked = PokeAPIClient.flavorTexts([
            (language: "ko", text: "옛 설명"), (language: "ko", text: "새 설명"),
        ], languages: ["ko"])
        XCTAssertEqual(picked["ko"], "새 설명")
    }

    /// 전부 안내문이면 그 언어는 아예 비운다 — 다른 언어/스탯 폴백으로 넘어가야 한다.
    func testDropsLanguageWhenEveryEntryIsANotice() {
        let picked = PokeAPIClient.flavorTexts([(language: "ko", text: koNotice)], languages: ["ko"])
        XCTAssertNil(picked["ko"])
    }

    /// en/ja 안내문도 잡는다 — 굽은 따옴표(’)와 전각 공백(U+3000)이 그대로 온다.
    func testDetectsNoticeInEnglishAndJapanese() {
        XCTAssertTrue(PokeAPIClient.isUnusableMoveNotice(enNotice))
        XCTAssertTrue(PokeAPIClient.isUnusableMoveNotice(jaNotice))
        XCTAssertTrue(PokeAPIClient.isUnusableMoveNotice("このわざは\u{3000}つかえません"))
    }

    /// 거짓양성 가드: 진짜 설명에도 "사용할 수 없"이 들어간다(금지어·트집). 부분일치로 판정하면
    /// 멀쩡한 설명이 통째로 사라진다 — 그래서 접두사로만 본다.
    func testRealDescriptionsMentioningUnusableAreNotDropped() {
        let disable = "상대가 마지막으로 사용한 기술을 4턴 동안 사용할 수 없게 만든다."
        XCTAssertFalse(PokeAPIClient.isUnusableMoveNotice(disable))
        XCTAssertEqual(PokeAPIClient.flavorTexts([(language: "ko", text: disable)],
                                                 languages: ["ko"])["ko"], disable)
    }

    /// 줄바꿈·폼피드는 한 줄로 편다(설명 슬롯은 줄 수가 고정이라 원문 개행이 그대로 오면 잘린다).
    func testFlattensLineBreaks() {
        let picked = PokeAPIClient.flavorTexts([(language: "en", text: "A move\nthat hits\u{000C}hard.")],
                                               languages: ["en"])
        XCTAssertEqual(picked["en"], "A move that hits hard.")
    }

    /// 세이브에 이미 안내문이 저장된 사용자는 다시 받아야 한다 — 없을 때만 받으면 영영 안 고쳐진다.
    func testStoredNoticeCountsAsMissingDescription() {
        // `statChanges: []`·`targetsUser` 는 "그 축까지 받아봤다" 는 뜻이다. 이 테스트가 보는 축은
        // 설명뿐인데, 다른 축을 nil 로 두면 그 이유로 다시 받게 되어 설명 판정이 죽어도 초록이 된다.
        // 축을 더할 때 이 고정값도 같이 늘린다(`CompanionStore.needsDetailRefresh`).
        var bad = MoveSpec(id: 216, names: ["ko": "은혜갚기"], type: .normal, power: 102,
                           damageClass: .physical, accuracy: 100, pp: 20,
                           descriptions: ["ko": koNotice])
        bad.statChanges = []
        bad.targetsUser = false
        bad.drain = 0
        var good = MoveSpec(id: 33, names: ["ko": "몸통박치기"], type: .normal, power: 40,
                            damageClass: .physical, accuracy: 100, pp: 35,
                            descriptions: ["ko": "몸 전체로 부딪쳐 공격한다."])
        good.statChanges = []
        good.targetsUser = false
        good.drain = 0
        good.healing = 0
        good.target = "selected-pokemon"
        XCTAssertTrue(CompanionStore.needsDetailRefresh(bad))
        XCTAssertFalse(CompanionStore.needsDetailRefresh(good))
        XCTAssertTrue(CompanionStore.needsDetailRefresh(good.withoutDescriptions()))
    }

    /// 트리거 브랜치: 모든 언어 항목이 안내문이면 flavorTexts 는 빈 dict 를 만든다.
    /// 그걸 "없음"으로 보면 로드할 때마다 다시 받아 영원히 수렴하지 않는다 —
    /// "안 받아봤다(nil)"와 "받아봤지만 쓸 게 없다([:])"는 다른 상태다.
    func testFetchedButEmptyDescriptionsDoNotRefetchForever() {
        var fetchedEmpty = MoveSpec(id: 216, names: ["ko": "은혜갚기"], type: .normal, power: 102,
                                    damageClass: .physical, accuracy: 100, pp: 20, descriptions: [:])
        fetchedEmpty.statChanges = []   // 랭크 축도 "받아봤고 없다" — 보는 축은 설명이다
        fetchedEmpty.targetsUser = false
        fetchedEmpty.drain = 0          // Phase 5 축도 같은 이유로 고정한다
        fetchedEmpty.healing = 0
        fetchedEmpty.target = "selected-pokemon"
        XCTAssertFalse(CompanionStore.needsDetailRefresh(fetchedEmpty),
                       "조회 결과가 빈 것뿐인데 매번 다시 받는다")
    }

    /// 전각 공백이 두 번 이상 와도 안내문으로 잡아야 한다 — 1:1 치환만 하면 "この技は　　使えません"을 놓친다.
    func testDetectsNoticeWithRepeatedIdeographicSpaces() {
        XCTAssertTrue(PokeAPIClient.isUnusableMoveNotice("この技は\u{3000}\u{3000}使えません\n思い出すことが"))
        XCTAssertTrue(PokeAPIClient.isUnusableMoveNotice("사용할 수  없는  기술입니다."))
    }

    // MARK: 슬롯 배선 (id → 기술 → 문구)

    /// 호버 id 를 실제 기술로 되짚는 단계까지 한 함수에 두고 검증한다.
    /// 이게 뷰 안에만 있으면 "되짚기를 통째로 지워도 테스트 전부 통과"가 된다(#40과 같은 false confidence).
    func testPanelTextResolvesTheHoveredMove() {
        let moves = [move(descriptions: ["ko": "첫 번째 설명"]),
                     MoveSpec(id: 99, names: ["ko": "다른 기술"], type: .water, power: 60,
                              damageClass: .special, accuracy: 100, pp: 20,
                              descriptions: ["ko": "두 번째 설명"])]
        XCTAssertEqual(MoveListView.panelText(hoveredID: 99, moves: moves, l: L(.ko)), "두 번째 설명")
        XCTAssertEqual(MoveListView.panelText(hoveredID: nil, moves: moves, l: L(.ko)), L(.ko).moveHoverHint)
    }

    /// 목록이 바뀐 뒤(레벨업 재로드) 남은 옛 id 는 엉뚱한 기술이 아니라 안내 문구로 떨어진다.
    func testStaleHoveredIDFallsBackToHint() {
        XCTAssertEqual(MoveListView.panelText(hoveredID: 12_345, moves: [move()], l: L(.ko)),
                       L(.ko).moveHoverHint)
    }

    // MARK: 레이아웃 (팝오버 흔들림 방지 — #9 부류)

    /// 호버 대상이 바뀌어도 슬롯 높이는 그대로다. 길이에 따라 늘어나면 마우스를 옮길 때마다
    /// 아래 콘텐츠가 밀려 올라갔다 내려간다.
    func testPanelHeightDoesNotChangeWithTextLength() {
        let short = renderedHeight(MoveHoverPanel(text: "짧다"))
        let long = renderedHeight(MoveHoverPanel(
            text: String(repeating: "아주 긴 기술 설명이 여기에 들어간다. ", count: 12)))
        XCTAssertEqual(short, long, accuracy: 0.5, "설명 길이에 따라 슬롯 높이가 변한다")
    }

    /// 슬롯 줄 예산이 **실제 최장 설명**을 담는지 — 못 담으면 뒷부분이 통째로 사라지는데
    /// 나머지를 볼 경로가 없다(`.help()` 는 팝오버 안에서 안 뜬다. 이 화면의 원래 결함).
    /// 예전 2줄 예산은 이 문자열(PokéAPI 그래스필드, 157자 = 3줄)에서 마지막 줄을 잘라먹었다.
    /// 실제 호출부 폭(`PopoverMetrics.contentWidth - 16`)으로 재야 의미가 있다.
    func testLongestRealDescriptionIsNotTruncated() {
        let longest = "The user turns the ground into Grassy Terrain for five turns. This restores "
            + "the HP of Pok\u{e9}mon on the ground a little every turn and powers up Grass-type moves."
        let panelWidth = PopoverMetrics.contentWidth - 16
        let needed = renderedHeight(Text(longest).font(.caption2)
                                        .frame(maxWidth: .infinity, alignment: .leading),
                                    width: panelWidth - 12)      // 패널 좌우 패딩 6+6
        let budget = renderedHeight(MoveHoverPanel(text: longest), width: panelWidth) - 12
        XCTAssertLessThanOrEqual(needed, budget + 0.5,
                                 "슬롯 \(MoveHoverPanel.lines)줄 예산이 실제 최장 설명(\(needed)pt)을 못 담는다")
    }

    /// 안내 문구 상태와 설명 상태의 높이도 같다 — 처음 호버하는 순간에도 안 흔들려야 한다.
    func testPanelHeightMatchesHintState() {
        for lang in [AppLanguage.ko, .en, .ja] {
            let l = L(lang)
            XCTAssertEqual(renderedHeight(MoveHoverPanel(text: l.moveHoverHint)),
                           renderedHeight(MoveHoverPanel(text: l.moveHoverText(move(descriptions: nil)))),
                           accuracy: 0.5, "\(lang) 에서 안내/설명 높이가 다르다")
        }
    }
}

private let hoverTestLine: EvoLine = {
    var names: [Int: [String: String]] = [:]
    for id in [1, 2, 3] { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: 1,
                   tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                   rarity: .common, names: names)
}()

private extension MoveSpec {
    func withoutDescriptions() -> MoveSpec {
        var copy = self; copy.descriptions = nil; return copy
    }
}
