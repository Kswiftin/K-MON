import XCTest
@testable import PokeTokenBar

// 기술 행 라벨 현지화 회귀(#10).
// 증상: 언어를 영어/일본어로 바꿔도 기술 행만 "변화 / 위력 90 / 명중 100 / 필중" 이 한국어로 나왔다.
// 원인: 행 라벨이 L 을 안 거치고 한국어 리터럴로 박혀 있었다(같은 단어를 쓰는 툴팁은 정상 현지화).
final class MoveLocalizationTests: XCTestCase {

    private func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }

    /// 트리거 재현: ko 는 한국어여야 한다(대조군 — 없으면 아래 "한글 없음" 검증이 무의미).
    func testKoreanLabelsStayKorean() {
        let l = L(.ko)
        XCTAssertTrue(containsHangul(l.moveCategoryStatus))
        XCTAssertTrue(containsHangul(l.movePowerShort(90)))
        XCTAssertTrue(containsHangul(l.moveAccuracyShort(100)))
        XCTAssertTrue(containsHangul(l.moveAlwaysHits))
    }

    /// en/ja 에서는 어떤 기술 행 라벨에도 한글이 남으면 안 된다.
    func testNonKoreanMoveLabelsHaveNoHangul() {
        for lang in [AppLanguage.en, .ja] {
            let l = L(lang)
            let labels = [l.movesTitle, l.movesLoading, l.movesEmpty,
                          l.moveCategoryStatus, l.moveCategoryPhysical, l.moveCategorySpecial,
                          l.movePowerLabel, l.moveAccuracyLabel, l.moveAlwaysHits,
                          l.movePowerShort(90), l.moveAccuracyShort(100), l.movePP(15)]
            for label in labels {
                XCTAssertFalse(containsHangul(label), "\(lang) 라벨에 한글이 남아 있다: \(label)")
            }
        }
    }

    /// 행 라벨과 툴팁이 같은 어휘를 쓴다 — 예전엔 둘이 서로 다른 언어로 나왔다.
    func testRowAndTooltipShareTheSameVocabulary() {
        for lang in [AppLanguage.ko, .en, .ja] {
            let l = L(lang)
            XCTAssertEqual(l.moveCategory(.status), l.moveCategoryStatus)
            XCTAssertTrue(l.movePowerShort(90).contains("90"))
            XCTAssertTrue(l.moveAccuracyShort(100).contains("100"))
        }
    }

    /// 부류 스윕(#10): 언어 분기 없이 한국어가 박혀 있던 다른 자리 — 집중 타이머 재화 줄, 랭크 판돈.
    func testSweptHardcodedKoreanLabelsAreLocalized() {
        for lang in [AppLanguage.en, .ja] {
            let l = L(lang)
            XCTAssertFalse(containsHangul(l.focusStash(eggs: 1, fragments: 3, weekly: 4)))
            XCTAssertFalse(containsHangul(l.battleFixedStake("1.2M")))
        }
        XCTAssertTrue(containsHangul(L(.ko).focusStash(eggs: 1, fragments: 3, weekly: 4)))
        XCTAssertTrue(L(.en).focusStash(eggs: 1, fragments: 3, weekly: 4).contains("4/10"))
    }
}
