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

    // MARK: 앱에만 있는 명령

    /// 터미널은 세이브를 **읽기만** 한다. 이름을 알아보고 이유를 말해야 한다 — "알 수 없는 명령"
    /// 으로 답하면 사용자는 오타를 의심하며 같은 명령을 다시 친다.
    @Test func testWriteCommandsExplainThatTheyLiveInTheApp() {
        for name in ["start", "go", "claim", "cancel", "stop"] {
            #expect(throws: PokedoroCommandError.readOnlyFrontEnd(name)) {
                try parse([name, "25"])
            }
        }
    }

    /// 그 이유가 화면에 실제로 나가는 문장인지 본다 — 오류 타입만 맞고 문구가 비면 사용자는
    /// 왜 거절됐는지 알 수 없다.
    @Test func testTheRefusalSaysWhereTheCommandLives() {
        #expect(PokedoroCommandError.readOnlyFrontEnd("claim").message.contains("앱에서"))
        #expect(PokedoroCommandParser.usage.contains("읽기만"))
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
