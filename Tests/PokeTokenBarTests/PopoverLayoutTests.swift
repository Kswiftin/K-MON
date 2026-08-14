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

    /// 수정 후: 스크롤 컨테이너 + maxHeight 조합이 요청 높이를 상한으로 자른다.
    func testScrollViewWithCapNeverExceedsTheCap() {
        let cap = PopoverMetrics.maxHeight(screenHeight: 900)
        let capped = ScrollView { Color.clear.frame(height: 3_000) }
            .frame(maxHeight: cap).fixedSize(horizontal: false, vertical: true)
        XCTAssertLessThanOrEqual(renderedHeight(capped), cap)
    }

    /// 짧은 콘텐츠는 상한만큼 부풀지 않는다(스크롤을 붙였다고 팝오버가 커지면 안 된다).
    func testShortContentKeepsItsNaturalHeight() {
        let cap = PopoverMetrics.maxHeight(screenHeight: 900)
        let short = ScrollView { Color.clear.frame(height: 120) }
            .frame(maxHeight: cap).fixedSize(horizontal: false, vertical: true)
        XCTAssertEqual(renderedHeight(short), 120, accuracy: 1)
    }

    /// 상한은 화면 높이에서 파생된다 — 작은 화면일수록 낮게, 큰 화면에서도 하드 상한을 안 넘게.
    func testMaxHeightDerivesFromScreenHeight() {
        XCTAssertEqual(PopoverMetrics.maxHeight(screenHeight: 700),
                       700 - PopoverMetrics.verticalChrome)
        XCTAssertEqual(PopoverMetrics.maxHeight(screenHeight: 4_000), PopoverMetrics.hardMaxHeight)
        XCTAssertEqual(PopoverMetrics.maxHeight(screenHeight: 200), PopoverMetrics.minHeight)
        XCTAssertLessThan(PopoverMetrics.maxHeight(screenHeight: 600),
                          PopoverMetrics.maxHeight(screenHeight: 760))
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

    /// 로딩 자리표시자 높이가 완성본(4행)과 같아야 팝오버가 한 번만 리사이즈된다.
    /// 상수(rowHeight)가 실제 렌더 높이와 어긋나면 자리표시자가 거짓말을 하므로 여기서 잠근다.
    func testLoadingPlaceholderMatchesFinalHeight() {
        let maxWidth = PopoverMetrics.contentWidth - 16
        let loaded = moveStore(longMoves)
        let loading = moveStore([])
        loading.debugSetDisplayedMoves([], loading: true)

        let loadedHeight = renderedHeight(MoveListView(store: loaded, maxWidth: maxWidth),
                                          proposingWidth: maxWidth)
        let loadingHeight = renderedHeight(MoveListView(store: loading, maxWidth: maxWidth),
                                           proposingWidth: maxWidth)
        XCTAssertEqual(loadingHeight, loadedHeight, accuracy: 6,
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
