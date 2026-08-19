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

    /// 아무것도 안 올렸을 때는 빈칸이 아니라 안내가 나온다 — 슬롯이 왜 비었는지 알 수 있어야 한다.
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

    /// 선택된 그 행에서 빠져나오면 비운다.
    func testLeavingTheSelectedRowClearsIt() {
        XCTAssertNil(MoveListView.hoverState(current: 7, moveID: 7, isInside: false))
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
