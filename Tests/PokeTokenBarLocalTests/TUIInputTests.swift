import Testing
@testable import PokeTokenBar

// 키 입력은 세이브를 바꾸는 입구다. 읽기 전용으로 뜬 세션이 조용히 아무 일도 안 하면
// 사용자는 키가 안 먹는다고 생각한다 — 거절은 **거절로** 돌아와야 화면이 이유를 띄운다.
@Suite("TUIInputTests")
struct TUIInputTests {

    /// `writable` 기본값은 참이다 — 표 자체는 두 경우를 다 답해야 하고, 지금 터미널이 붙이는
    /// 값(거짓)은 아래 "읽기 전용" 절이 따로 본다.
    private func action(_ key: TUIKey, screen: TUIScreen = .home, writable: Bool = true) -> TUIAction {
        TUIKeymap.action(for: key, screen: screen, canWrite: writable)
    }

    // MARK: 이동

    @Test func testScreenKeysSwitchScreens() {
        #expect(action(.char("p")) == .show(.party))
        #expect(action(.char("d")) == .show(.dex))
        #expect(action(.char("h"), screen: .dex) == .show(.home))
    }

    @Test func testQuitAndReloadWorkOnEveryScreen() {
        for screen in TUIScreen.allCases {
            #expect(action(.char("q"), screen: screen) == .quit)
            #expect(action(.char("r"), screen: screen) == .reload)
        }
    }

    /// 새 조회 화면도 키 하나로 간다. `c` 를 도전 화면에 배정하지 않는 이유는 그 키가 홈에서
    /// 정산이라서다 — 같은 키가 화면에 따라 조회와 상태 변경으로 갈리면 손이 먼저 움직인다.
    @Test func testReadOnlyScreenKeysSwitchScreens() {
        #expect(action(.char("b")) == .show(.bag))
        #expect(action(.char("m")) == .show(.challenge))
        #expect(action(.char("g")) == .show(.goals))
    }

    /// 새 화면은 전부 목록이다 — 스크롤을 못 받으면 첫 창 밖의 행을 영영 못 본다.
    @Test func testReadOnlyScreensScroll() {
        for screen in [TUIScreen.bag, .challenge, .goals] {
            #expect(action(.down, screen: screen) == .scroll(1))
            #expect(action(.char("k"), screen: screen) == .scroll(-1))
        }
    }

    /// 모험 키는 여전히 홈 전용이다. 가방을 넘기다 `c` 를 눌러 정산이 돌면 안 된다.
    @Test func testAdventureKeysStayHomeOnlyOnTheNewScreens() {
        for screen in [TUIScreen.bag, .challenge, .goals] {
            #expect(action(.char("c"), screen: screen) == .ignored)
            #expect(action(.char("1"), screen: screen) == .ignored)
        }
    }

    /// ESC 는 목록에서 홈으로 돌아온다 — 화면이 늘어도 나가는 길은 하나여야 한다.
    @Test func testEscapeLeavesEveryListScreenForHome() {
        for screen in TUIScreen.allCases where screen.isList {
            #expect(action(.escape, screen: screen) == .show(.home))
        }
    }

    /// 모르는 시퀀스(Home·PageUp·잘려 온 UTF-8)는 **아무 동작도 아니다.** 어떤 화면에서도
    /// 동작으로 새면 안 된다 — 디코더가 `.unknown` 으로 돌려주는 이유가 바로 그것이고, 그 값을
    /// 여기서 문자처럼 다루면 진짜 입력과 구분되지 않는다.
    @Test func testUnknownKeysDoNothingOnEveryScreen() {
        for screen in TUIScreen.allCases {
            #expect(action(.unknown, screen: screen) == .ignored)
        }
    }

    // MARK: 모험

    @Test func testDigitKeysStartTheMatchingSessionLength() {
        #expect(action(.char("1")) == .startAdventure(minutes: 25))
        #expect(action(.char("2")) == .startAdventure(minutes: 50))
        #expect(action(.char("3")) == .startAdventure(minutes: 90))
    }

    @Test func testClaimAndCancelKeys() {
        #expect(action(.char("c")) == .claimAdventure)
        #expect(action(.char("x")) == .cancelAdventure)
    }

    /// 목록 화면에서 숫자 키가 모험을 시작하면 안 된다 — 도감을 넘기다 실수로 세션이 시작된다.
    @Test func testAdventureKeysAreHomeOnly() {
        #expect(action(.char("1"), screen: .dex) == .ignored)
        #expect(action(.char("c"), screen: .party) == .ignored)
    }

    // MARK: 읽기 전용

    /// 쓰기 권한이 없으면 상태를 바꾸는 키는 **거절**로 돌아온다. `.ignored` 로 뭉개면
    /// "키가 안 먹는 것" 과 "권한이 없는 것" 을 화면이 구분해 알릴 수 없다.
    @Test func testStateChangingKeysAreRejectedWithoutWriteAccess() {
        #expect(action(.char("1"), writable: false) == .rejected(.readOnly))
        #expect(action(.char("c"), writable: false) == .rejected(.readOnly))
        #expect(action(.char("x"), writable: false) == .rejected(.readOnly))
    }

    /// 쓰기 권한이 있으면 같은 키가 **동작으로** 돌아온다. 위 거절 테스트만 있으면 "언제나
    /// 거절" 하는 구현도 통과한다 — 두 방향을 함께 봐야 이 표가 실제로 무언가를 가른다.
    ///
    /// 지금 `watch` 는 `canWrite: true` 로 돈다(요청은 앱이 실행한다). 그래도 거절 축을 지우지
    /// 않는 이유는, 권한 없는 실행이 다시 생길 때 침묵 대신 이유를 띄우는 자리가 여기뿐이라서다.
    @Test func testStateChangingKeysBecomeActionsWithWriteAccess() {
        #expect(action(.char("1"), writable: true) == .startAdventure(minutes: 25))
        #expect(action(.char("c"), writable: true) == .claimAdventure)
        #expect(action(.char("x"), writable: true) == .cancelAdventure)
    }

    /// 읽기 전용이어도 보기·나가기는 막지 않는다. 뷰어로서의 쓸모가 그대로 남아야 한다.
    @Test func testReadOnlySessionCanStillNavigateAndQuit() {
        #expect(action(.char("d"), writable: false) == .show(.dex))
        #expect(action(.char("q"), writable: false) == .quit)
        #expect(action(.char("r"), writable: false) == .reload)
    }

    // MARK: 목록 스크롤

    @Test func testArrowsAndViKeysScrollLists() {
        #expect(action(.down, screen: .dex) == .scroll(1))
        #expect(action(.up, screen: .dex) == .scroll(-1))
        #expect(action(.char("j"), screen: .party) == .scroll(1))
        #expect(action(.char("k"), screen: .party) == .scroll(-1))
    }

    /// 홈에는 목록이 없다. 여기서 스크롤을 받으면 아무 데도 안 쓰이는 선택 인덱스가 움직인다.
    @Test func testHomeIgnoresScroll() {
        #expect(action(.down) == .ignored)
    }

    // MARK: 선택 인덱스 클램프

    /// 목록 끝에서 더 내려도 범위를 벗어나면 안 된다 — 렌더가 배열 밖을 읽고 크래시한다.
    @Test func testSelectionClampsToBounds() {
        #expect(TUIKeymap.clamp(selection: 9, delta: 1, count: 10) == 9)
        #expect(TUIKeymap.clamp(selection: 0, delta: -1, count: 10) == 0)
        #expect(TUIKeymap.clamp(selection: 4, delta: 1, count: 10) == 5)
    }

    /// 빈 목록에서의 선택은 0 이다. -1 을 돌려주면 그대로 인덱싱에 쓰여 크래시한다.
    @Test func testSelectionOnEmptyListStaysZero() {
        #expect(TUIKeymap.clamp(selection: 0, delta: 1, count: 0) == 0)
    }

    // MARK: 바이트 해석

    private func decode(_ bytes: [UInt8]) -> (keys: [TUIKey], leftover: [UInt8]) {
        var buffer = bytes
        var keys: [TUIKey] = []
        while let key = TUIKeyDecoder.decode(&buffer) { keys.append(key) }
        return (keys, buffer)
    }

    @Test func testArrowSequencesBecomeArrowKeys() {
        #expect(decode([0x1B, 0x5B, 0x41]).keys == [.up])
        #expect(decode([0x1B, 0x5B, 0x42]).keys == [.down])
    }

    /// 아직 다루지 않는 시퀀스(Home·PageUp)는 **문자로 흘리지 않는다.** 예전엔 NUL 문자로 접어서
    /// 진짜 NUL 입력과 구분되지 않았다.
    @Test func testUnhandledSequencesAreTheirOwnKey() {
        #expect(decode([0x1B, 0x5B, 0x48]).keys == [.unknown])
        #expect(decode([0x00]).keys == [.char("\u{0}")], "진짜 NUL 은 문자로 남는다")
    }

    /// 한글 한 글자는 세 바이트로 온다. 조각으로 흩어지면 그중 하나가 화면 전환 키로 먹힌다.
    @Test func testMultiByteCharactersArriveAsOneKey() {
        #expect(decode(Array("가".utf8)).keys == [.char("가")])
    }

    /// read 경계에서 잘려 오는 것이 정상이다 — 남은 바이트는 되돌려 두고 다음 read 를 기다린다.
    @Test func testASplitCharacterWaitsForTheRestOfItsBytes() {
        let bytes = Array("가".utf8)
        var buffer = Array(bytes.prefix(2))
        #expect(TUIKeyDecoder.decode(&buffer) == nil)
        buffer.append(bytes[2])
        #expect(TUIKeyDecoder.decode(&buffer) == .char("가"))
    }

    /// 앞이 잘린 이어지는 바이트를 Latin-1 문자로 읽으면 한글 한 글자가 알파벳 여러 개로 흩어져
    /// 그중 하나가 화면 전환 키로 먹힌다.
    @Test func testStrayContinuationBytesAreNotReadAsLatin1() {
        #expect(decode([0xEA, 0xB0, 0x80][1...].map { $0 }).keys.allSatisfy { $0 == .unknown })
    }

    /// ESC 한 바이트만으로는 화살표의 첫 바이트와 구분할 수 없어 `decode` 가 판단을 미룬다.
    /// 뒤 바이트가 안 오는 것이 정상(사용자가 ESC 를 눌렀다)이므로 `flush` 가 확정한다 —
    /// 그러지 않으면 ESC 키가 영영 죽는다.
    @Test func testALoneEscapeResolvesOnFlush() {
        var buffer: [UInt8] = [0x1B]
        #expect(TUIKeyDecoder.decode(&buffer) == nil)
        #expect(TUIKeyDecoder.flush(&buffer) == .escape)
        #expect(buffer.isEmpty)
    }

    /// ESC 다음이 `[` 가 아니면 시퀀스가 아니다 — 그 자리에서 ESC 로 확정한다.
    @Test func testEscapeFollowedByAPlainCharacterIsAnEscape() {
        var buffer: [UInt8] = [0x1B, 0x61]
        #expect(TUIKeyDecoder.decode(&buffer) == .escape)
        #expect(TUIKeyDecoder.decode(&buffer) == .char("a"))
    }

    /// ESC 가 목록에서는 홈으로, 홈에서는 종료로 간다.
    @Test func testEscapeLeavesTheListThenQuits() {
        #expect(action(.escape, screen: .dex) == .show(.home))
        #expect(action(.escape) == .quit)
    }
}
