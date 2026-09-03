import Testing
@testable import PokeTokenBar

// 명령 파싱은 **어느 프런트엔드가 뜰지** 가르는 입구다. 잘못 해석하면 오타가 조용히 메뉴바 앱을
// 띄우고(사용자는 오타를 알 방법이 없다), 앱에만 있는 명령이 "알 수 없는 명령" 으로 뭉개진다.
@Suite("PokedoroCommandTests")
struct PokedoroCommandTests {

    private func parse(_ arguments: [String]) throws -> PokedoroCommand {
        try PokedoroCommandParser.parse(arguments)
    }

    // MARK: 기본

    /// 인자 없이 친 사용자가 가장 원하는 것은 현재 상태다. 도움말을 띄우면 매번 한 번 더 쳐야 한다.
    @Test func testNoArgumentsMeansStatus() throws {
        #expect(try parse([]) == .status(oneline: false))
    }

    @Test func testStatusAcceptsOnelineOption() throws {
        #expect(try parse(["status", "--oneline"]) == .status(oneline: true))
    }

    @Test func testShortAliasesResolveToTheSameCommands() throws {
        #expect(try parse(["st"]) == .status(oneline: false))
        #expect(try parse(["mons"]) == .party)
        #expect(try parse(["top"]) == .watch)
    }

    // MARK: 집중 세션 명령

    /// 세 동작은 터미널에서 **직접 요청한다**. 세이브를 바꾸는 쪽은 여전히 앱이지만
    /// (`PokedoroRequestBus`), 사용자에게는 그냥 되는 명령이어야 한다.
    @Test func testFocusSessionCommandsParse() throws {
        #expect(try parse(["start", "25"]) == .start(minutes: 25))
        #expect(try parse(["claim"]) == .claim)
        #expect(try parse(["stop"]) == .stop)
    }

    /// 분을 안 적으면 실행기가 기본 길이를 고른다. 여기서 25 를 박으면 기본값이 두 곳이 되고,
    /// 한쪽만 바뀌면 화면과 터미널이 다른 길이를 켠다.
    @Test func testStartWithoutMinutesLeavesTheChoiceToTheExecutor() throws {
        #expect(try parse(["start"]) == .start(minutes: nil))
    }

    /// 별칭. `go` 는 시작, `cancel` 은 종료다 — 앱 버튼의 이름("모험 취소")을 기억하는 사용자가
    /// 그대로 쳐도 통해야 한다.
    @Test func testFocusSessionAliases() throws {
        #expect(try parse(["go", "50"]) == .start(minutes: 50))
        #expect(try parse(["cancel"]) == .stop)
    }

    /// 숫자가 아닌 인자를 **조용히 무시하면 안 된다.** `start 5o` 를 25분으로 접으면 사용자는
    /// 자기가 무엇을 켰는지 모른 채 오타를 반복한다.
    @Test func testANonNumericLengthIsRejectedByName() {
        #expect(throws: PokedoroCommandError.invalidMinutes("5o")) {
            try parse(["start", "5o"])
        }
        #expect(PokedoroCommandError.invalidMinutes("5o").message.contains("25"),
                "쓸 수 있는 길이를 알려 줘야 사용자가 다음에 무엇을 칠지 안다")
    }

    // MARK: 세이브를 여는가, 요청을 보내는가

    /// **이 표가 뒤집히면 피하려던 일이 그대로 일어난다.** 요청으로 가야 할 명령이 세이브를 열면
    /// 여는 것만으로 정산이 돌고(`ReadOnlyStoreTests`), 조회 명령이 요청을 보내면 앱이 꺼져
    /// 있을 때 `status` 가 3초 멈췄다 실패한다.
    @Test func testOnlySessionCommandsBecomeRequests() {
        #expect(PokedoroCommand.start(minutes: 25).request == .start)
        #expect(PokedoroCommand.claim.request == .claim)
        #expect(PokedoroCommand.stop.request == .stop)
    }

    @Test func testReadOnlyCommandsNeverBecomeRequests() {
        let readOnly: [PokedoroCommand] = [.status(oneline: false), .status(oneline: true),
                                           .party, .dex, .watch, .help]
        for command in readOnly {
            #expect(command.request == nil, "\(command) 가 앱에 요청을 보낸다")
        }
    }

    // MARK: 앱에만 있는 명령

    /// 터미널이 다루는 것은 집중 세션뿐이다. 배틀·교환처럼 앱 화면에만 있는 것은 이름을
    /// 알아보고 **어디서 하는지** 답해야 한다 — "알 수 없는 명령" 으로 뭉개면 사용자는 오타를
    /// 의심하며 같은 명령을 다시 친다.
    @Test func testAppOnlyCommandsExplainWhereTheyLive() {
        for name in ["battle", "trade", "auction", "home", "raid", "shop"] {
            #expect(throws: PokedoroCommandError.appOnlyFeature(name)) {
                try parse([name])
            }
        }
    }

    /// 그 이유가 화면에 실제로 나가는 문장인지 본다 — 오류 타입만 맞고 문구가 비면 사용자는
    /// 왜 거절됐는지 알 수 없다.
    @Test func testTheRefusalSaysWhereTheCommandLives() {
        #expect(PokedoroCommandError.appOnlyFeature("battle").message.contains("앱"))
        #expect(PokedoroCommandParser.usage.contains("start"),
                "도움말이 이제 쓸 수 있는 세션 명령을 알려 줘야 한다")
    }

    // MARK: 오타

    /// 모르는 명령은 **거절**이어야 한다. 예전엔 파싱 실패가 곧 "터미널 호출이 아님" 으로 읽혀
    /// 오타를 치면 메뉴바 앱이 떴고, 사용자는 오타를 알 방법이 없었다.
    @Test func testUnknownCommandIsRejectedByName() {
        #expect(throws: PokedoroCommandError.unknownCommand("bogus")) {
            try parse(["bogus"])
        }
    }

    /// 진입 플래그는 명령 이름 앞뒤 어디에 붙어도 명령 해석을 방해하지 않아야 한다 —
    /// 앱 번들 실행 파일을 직접 부르는 경로가 이 플래그를 앞에 붙인다.
    @Test func testEntryFlagsAreStrippedBeforeParsing() throws {
        #expect(try parse(["--tui", "party"]) == .party)
        #expect(try parse(["--cli", "status", "--oneline"]) == .status(oneline: true))
    }

    // MARK: 진입 판별

    /// 셸에서 친 인자는 `-` 로 시작하지 않는다. 오타여도 터미널로 보내야 오류가 보인다.
    @Test func testShellStyleArgumentsRouteToTheTerminal() {
        #expect(PokedoroCommandParser.isTerminalInvocation(["status"]))
        #expect(PokedoroCommandParser.isTerminalInvocation(["bogus"]))
        #expect(PokedoroCommandParser.isTerminalInvocation(["--tui"]))
        #expect(PokedoroCommandParser.isTerminalInvocation(["--help"]))
    }

    /// macOS 가 앱 번들에 붙이는 인자는 항상 `-` 로 시작한다. 이것 때문에 앱이 안 뜨면
    /// 훨씬 나쁜 고장이므로 모르는 `-` 인자는 메뉴바 앱으로 보낸다.
    @Test func testSystemInjectedFlagsStillLaunchTheMenuBarApp() {
        #expect(!(PokedoroCommandParser.isTerminalInvocation([])))
        #expect(!(PokedoroCommandParser.isTerminalInvocation(["-NSDocumentRevisionsDebugMode", "YES"])))
        #expect(!(PokedoroCommandParser.isTerminalInvocation(["-psn_0_12345"])))
    }
}
