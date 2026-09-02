import Testing
@testable import PokeTokenBar

// 터미널은 픽셀이 아니라 **칸(cell)** 으로 배치한다. 한글·이모지는 한 글자가 두 칸을 먹으므로
// `String.count` 로 자르거나 채우면 파트너 이름이 한글일 때만 테두리가 어긋난다 — 개발자가 영어
// 이름으로만 확인하면 못 보는 부류라 폭 계산을 따로 검증한다.
@Suite("TUITextTests")
struct TUITextTests {

    // MARK: 표시 폭

    @Test func testASCIICountsOneCellPerCharacter() {
        #expect(TUIText.displayWidth("Pikachu") == 7)
    }

    /// 한글 음절은 두 칸이다. 여기가 1로 세지면 모든 목록의 오른쪽 정렬이 이름 길이만큼 밀린다.
    @Test func testHangulCountsTwoCellsPerCharacter() {
        #expect(TUIText.displayWidth("피카츄") == 6)
    }

    @Test func testMixedScriptSumsBothWidths() {
        #expect(TUIText.displayWidth("Lv.5 피카츄") == 5 + 6)
    }

    /// 이모지도 두 칸이다 — 이로치 표식으로 쓰므로 목록마다 등장한다.
    @Test func testEmojiCountsTwoCells() {
        #expect(TUIText.displayWidth("✨") == 2)
    }

    // MARK: 자르기

    @Test func testTruncateKeepsShorterStringUntouched() {
        #expect(TUIText.truncate("abc", to: 10) == "abc")
    }

    @Test func testTruncateCutsToRequestedCellCount() {
        #expect(TUIText.truncate("abcdef", to: 3) == "abc")
    }

    /// 경계에 두 칸짜리 글자가 걸리면 **자른다**. 반쪽만 내보내면 그 줄부터 커서 위치가 어긋나
    /// 이후 화면 전체가 밀린다(터미널은 반 칸을 되돌릴 방법이 없다).
    @Test func testTruncateDropsWideCharacterStraddlingTheBoundary() {
        #expect(TUIText.truncate("가나다", to: 3) == "가")
    }

    @Test func testTruncateToZeroYieldsEmptyString() {
        #expect(TUIText.truncate("가나다", to: 0) == "")
    }

    // MARK: 채우기

    @Test func testPadFillsToRequestedCellCount() {
        #expect(TUIText.pad("ab", to: 5) == "ab   ")
    }

    /// 넓은 글자로 채울 때도 결과의 **폭**이 맞아야 한다 — 글자 수가 아니다.
    @Test func testPadAccountsForWideCharacters() {
        #expect(TUIText.displayWidth(TUIText.pad("가나", to: 7)) == 7)
    }

    /// 이미 넘치면 잘라서 폭을 지킨다. 넘친 채로 두면 테두리가 깨진다.
    @Test func testPadTruncatesWhenAlreadyTooWide() {
        #expect(TUIText.pad("abcdef", to: 3) == "abc")
    }
}
