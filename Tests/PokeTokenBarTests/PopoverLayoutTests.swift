import XCTest
import SwiftUI
@testable import PokeTokenBar

// 팝오버 세로 오버플로 가드(#9).
// 증상: "기술 보기" 를 펼치면 팝오버 위(타이머)가 잘리고 기술 4행 중 2행만 보이며 푸터가 사라졌다.
// 원인: 팝오버 콘텐츠에 가로 폭만 있고 높이 상한도 스크롤도 없었다 — NSPopover 는 넘친 만큼을
// 스크롤이 아니라 클리핑으로 처리한다.
//
// 트리거 브랜치를 재현한다: 상한 없는 긴 콘텐츠가 실제로 화면 가용 높이를 넘는지까지 확인해야
// "상한 어서션이 애초에 통과할 조건이었다" 는 false confidence 를 막는다.
@MainActor
final class PopoverLayoutTests: XCTestCase {

    private func renderedHeight(_ view: some View, proposingWidth: CGFloat = PopoverMetrics.width) -> CGFloat {
        NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: proposingWidth, height: .greatestFiniteMagnitude)).height
    }

    private func renderedWidth(_ view: some View, proposing: CGFloat) -> CGFloat {
        NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: proposing, height: 900)).width
    }

    // MARK: 높이 상한

    /// 트리거 재현: 상한이 없으면 긴 콘텐츠는 그대로 자기 높이만큼 요청한다(= 잘리던 조건).
    func testUnboundedContentRequestsMoreThanTheCap() {
        let tall = VStack { Color.clear.frame(height: 3_000) }
        XCTAssertGreaterThan(renderedHeight(tall), PopoverMetrics.maxHeight(screenHeight: 900))
    }

    /// 수정 후: 창 높이가 고정이라 긴 콘텐츠도 그 높이를 넘지 않는다(넘는 부분은 안에서 스크롤).
    func testFixedHeightNeverExceedsItself() {
        let h = PopoverMetrics.height(for: .home, screenHeight: 900)
        let tall = ScrollView { Color.clear.frame(height: 3_000) }.frame(height: h)
        XCTAssertEqual(renderedHeight(tall), h, accuracy: 1)
    }

    /// 짧은 콘텐츠도 같은 높이를 유지한다 — 탭을 바꾸거나 기술 목록을 접었다 펴도 창이 안 흔들린다.
    /// (예전엔 `.fixedSize` 로 자연 높이를 따라가서 펼칠 때마다 팝오버가 커졌다 작아지며 떨렸다.)
    func testShortContentKeepsTheSameHeightAsTallContent() {
        let h = PopoverMetrics.height(for: .home, screenHeight: 900)
        let short = ScrollView { Color.clear.frame(height: 120) }.frame(height: h)
        let tall = ScrollView { Color.clear.frame(height: 3_000) }.frame(height: h)
        XCTAssertEqual(renderedHeight(short), renderedHeight(tall), accuracy: 1)
    }

    /// 상한은 화면 높이에서만 파생된다 — 작은 화면일수록 낮게, 큰 화면에선 화면만큼 커진다.
    func testMaxHeightDerivesFromScreenHeight() {
        XCTAssertEqual(PopoverMetrics.maxHeight(screenHeight: 700),
                       700 - PopoverMetrics.verticalChrome)
        XCTAssertEqual(PopoverMetrics.maxHeight(screenHeight: 1_440),
                       1_440 - PopoverMetrics.verticalChrome)
        XCTAssertEqual(PopoverMetrics.maxHeight(screenHeight: 200), PopoverMetrics.minHeight)
        XCTAssertLessThan(PopoverMetrics.maxHeight(screenHeight: 600),
                          PopoverMetrics.maxHeight(screenHeight: 760))
    }

    /// 탭별 고정 높이는 화면이 넉넉하면 그대로, 좁으면 화면에 맞춰 줄어든다.
    /// 회귀(#9 2차): 720pt 고정 천장 시절엔 1440pt 화면에서도 펼친 홈 탭이 상한을 넘겨
    /// 헤더 첫 줄과 아래 카드가 잘려 보였다 — 화면엔 두 배 넘는 자리가 남아 있는데도.
    func testTabHeightIsFixedOnBigScreensAndClampsOnSmallOnes() {
        XCTAssertEqual(PopoverMetrics.height(for: .home, screenHeight: 1_440),
                       PopoverTab.home.contentHeight)
        XCTAssertEqual(PopoverMetrics.height(for: .collection, screenHeight: 700),
                       700 - PopoverMetrics.verticalChrome)
        // 탭을 옮겨도 창이 뛰지 않도록 모든 탭이 같은 높이를 쓴다.
        XCTAssertEqual(PopoverTab.home.contentHeight, PopoverTab.collection.contentHeight)
        XCTAssertEqual(PopoverTab.battle.contentHeight, PopoverTab.collection.contentHeight)
        XCTAssertEqual(PopoverTab.shop.contentHeight, PopoverTab.collection.contentHeight)
    }

    // MARK: 기술 목록 행 — 가로 폭 · 자리표시자 높이

    private func moveStore(_ moves: [MoveSpec]) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-moves-\(UUID().uuidString).json")
        let store = CompanionStore(provider: StubProvider(value: moveTestLine),
                                   clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                   fileURL: url, rng: SeededRNG(seed: 3))
        store.debugSetDisplayedMoves(moves)
        return store
    }

    /// 이름이 긴 기술 4개 — 실제로 넘치는 최악 케이스.
    private var longMoves: [MoveSpec] {
        (0..<MoveListView.maxRows).map { index in
            MoveSpec(id: index, names: ["ko": String(repeating: "폭발", count: 8),
                                        "en": String(repeating: "Hyper", count: 6),
                                        "ja": String(repeating: "ばくれつ", count: 6)],
                     type: .fire, power: 250, damageClass: .special, accuracy: 100, pp: 40)
        }
    }

    /// 트리거 재현: 폭 제한이 없으면 기술 행이 팝오버 콘텐츠 폭을 넘는다.
    func testMoveRowsWithoutMaxWidthOverflow() {
        let store = moveStore(longMoves)
        // 제안 폭이 아니라 "이상 폭"(넉넉한 제안)으로 잰다 — 행이 얼마나 원하는지를 봐야
        // 폭 제한이 실제로 일하는지 알 수 있다.
        let width = renderedWidth(MoveListView(store: store), proposing: 4_000)
        XCTAssertGreaterThan(width, PopoverMetrics.contentWidth,
                             "안 넘치면 아래 fit 검증이 무의미해진다")
    }

    /// 수정 후: 주어진 폭 안에 들어온다.
    func testMoveRowsFitGivenWidth() {
        let store = moveStore(longMoves)
        let maxWidth = PopoverMetrics.contentWidth - 16
        XCTAssertLessThanOrEqual(renderedWidth(MoveListView(store: store, maxWidth: maxWidth), proposing: 4_000),
                                 maxWidth, "이상 폭도 상한 이하")
        XCTAssertLessThanOrEqual(renderedWidth(MoveListView(store: store, maxWidth: maxWidth), proposing: maxWidth),
                                 maxWidth)
    }

    /// 긴 라틴 문자 이름(영문 UI 의 실제 최악 케이스)이 행 높이를 키우면 안 된다.
    /// 예전엔 이름에 밀린 타입 배지 글자가 줄바꿈돼 행이 통째로 커졌다 — 한국어 이름은 짧아
    /// 로컬에선 안 걸리고 영어로 도는 CI 에서만 4행이 78pt 대신 118pt 로 잡혔다.
    func testLongLatinNameDoesNotGrowRowHeight() {
        let maxWidth = PopoverMetrics.contentWidth - 16
        let latin = (0..<MoveListView.maxRows).map { index in
            MoveSpec(id: 100 + index, names: ["en": String(repeating: "Hyper", count: 6)],
                     type: .fire, power: 250, damageClass: .special, accuracy: 100, pp: 40)
        }
        let short = moveStore((0..<MoveListView.maxRows).map { index in
            MoveSpec(id: index, names: ["en": "Tackle"], type: .normal, power: 40,
                     damageClass: .physical, accuracy: 100, pp: 35)
        })
        XCTAssertEqual(renderedHeight(MoveListView(store: moveStore(latin), maxWidth: maxWidth),
                                      proposingWidth: maxWidth),
                       renderedHeight(MoveListView(store: short, maxWidth: maxWidth),
                                      proposingWidth: maxWidth),
                       accuracy: 2, "이름 길이에 따라 행 높이가 달라지면 안 된다")
    }

    /// 로딩 자리표시자 높이가 완성본(4행)과 같아야 팝오버가 한 번만 리사이즈된다.
    /// 자리표시자는 같은 행 뷰를 투명하게 깔아 높이를 잡는다 — 숫자 상수로 두면 폰트·OS 에 따라
    /// 실제 행 높이와 어긋나 이 검증이 기계마다 다른 결과를 낸다(CI 118pt vs 로컬 78pt 회귀).
    func testLoadingPlaceholderMatchesFinalHeight() {
        let maxWidth = PopoverMetrics.contentWidth - 16
        // 언어에 상관없이 같은(긴 라틴) 이름을 쓴다 — CI 는 영어, 로컬은 한국어로 돌아
        // 언어별 이름을 쓰면 두 환경이 서로 다른 케이스를 검증하게 된다.
        let loaded = moveStore((0..<MoveListView.maxRows).map { index in
            MoveSpec(id: 200 + index, names: ["en": String(repeating: "Hyper", count: 6)],
                     type: .fire, power: 250, damageClass: .special, accuracy: 100, pp: 40)
        })
        let loading = moveStore([])
        loading.debugSetDisplayedMoves([], loading: true)

        let loadedHeight = renderedHeight(MoveListView(store: loaded, maxWidth: maxWidth),
                                          proposingWidth: maxWidth)
        let loadingHeight = renderedHeight(MoveListView(store: loading, maxWidth: maxWidth),
                                           proposingWidth: maxWidth)
        XCTAssertEqual(loadingHeight, loadedHeight, accuracy: 2,
                       "자리표시자와 완성본 높이가 다르면 펼친 직후 팝오버가 두 번 리사이즈된다")
    }
}

private let moveTestLine: EvoLine = {
    var names: [Int: [String: String]] = [:]
    for id in [1, 2, 3] { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: 1,
                   tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                   rarity: .common, names: names)
}()
