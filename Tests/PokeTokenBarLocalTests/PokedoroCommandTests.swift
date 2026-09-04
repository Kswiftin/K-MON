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

    // MARK: 조회 명령

    /// 가방·도전·목표는 세이브만 읽는다. 앱에 요청을 보내는 명령으로 만들면 앱이 꺼져 있을 때
    /// 조회가 3초 멈췄다 실패한다 — 조회는 앱 없이도 되는 것이 이 프런트엔드의 쓸모다.
    @Test func testReadOnlyScreenCommandsParse() throws {
        #expect(try parse(["bag"]) == .bag)
        #expect(try parse(["challenge"]) == .challenge)
        #expect(try parse(["goals"]) == .goals)
    }

    @Test func testReadOnlyScreenAliases() throws {
        #expect(try parse(["items"]) == .bag)
        #expect(try parse(["ch"]) == .challenge)
        #expect(try parse(["goal"]) == .goals)
    }

    /// 번호를 안 적으면 파트너다 — 가장 자주 보는 개체에 인자를 강제하지 않는다.
    @Test func testMonWithoutANumberMeansThePartner() throws {
        #expect(try parse(["mon"]) == .mon(number: nil))
    }

    /// 번호는 `party` 가 찍는 값 그대로(1부터)다. 0 부터 받으면 화면이 찍은 번호와 입력이 한 칸
    /// 어긋나 사용자가 다른 개체를 본다.
    @Test func testMonTakesThePrintedNumber() throws {
        #expect(try parse(["mon", "3"]) == .mon(number: 3))
    }

    /// 숫자가 아닌 번호를 조용히 파트너로 접으면 사용자는 자기 오타를 영영 못 본다
    /// (`start 5o` 와 같은 부류다).
    @Test func testANonNumericMonNumberIsRejectedByName() {
        #expect(throws: PokedoroCommandError.invalidMonNumber("2번")) {
            try parse(["mon", "2번"])
        }
        #expect(PokedoroCommandError.invalidMonNumber("2번").message.contains("party"),
                "번호를 어디서 얻는지 알려 줘야 사용자가 다음에 무엇을 칠지 안다")
    }

    /// 도움말에 없는 기능은 있어도 없는 것이다 — 사용자가 알 방법이 없다.
    @Test func testUsageListsTheReadOnlyScreens() {
        for name in ["bag", "challenge", "goals", "mon"] {
            #expect(PokedoroCommandParser.usage.contains(name), "도움말에 \(name) 이 없다")
        }
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

    // MARK: 파트너를 바꾸는 명령

    /// 아이템 이름은 **파서가 닫힌 목록으로 대조한다.** 여기서 걸러야 화면이 이유를 말할 수 있고,
    /// 통과한 명령은 늘 실행할 수 있는 종류를 든다(`nil` 요청은 조용한 무동작이 된다).
    @Test func testCompanionCommandsParse() throws {
        #expect(try parse(["use", "rare candy"]) == .use(item: .rareCandy))
        #expect(try parse(["evolve"]) == .evolve)
        #expect(try parse(["switch", "2"]) == .switchCompanion(number: 2))
        #expect(try parse(["name", "리자몽"]) == .rename(nickname: "리자몽"))
    }

    /// 셸에서 띄어쓴 이름을 따옴표 없이 쳐도 통해야 한다 — `use 이상한 사탕` 은 인자 두 개로
    /// 들어온다. 첫 조각만 읽으면 아이템 이름의 절반으로 목록을 뒤지고 늘 실패한다.
    @Test func testAMultiWordArgumentIsJoinedBackTogether() throws {
        #expect(try parse(["use", "이상한", "사탕"]) == .use(item: .rareCandy))
        #expect(try parse(["name", "불꽃", "도마뱀"]) == .rename(nickname: "불꽃 도마뱀"))
    }

    /// 목록 밖 아이템은 이름으로 거절하고 **어디서 이름을 얻는지** 말한다 — "알 수 없는 명령" 으로
    /// 뭉개면 사용자는 오타를 의심하며 같은 값을 다시 친다.
    @Test func testAnItemOutsideTheNameTableIsRejectedByName() {
        #expect(throws: PokedoroCommandError.unknownItem("masterball")) {
            try parse(["use", "masterball"])
        }
        #expect(PokedoroCommandError.unknownItem("masterball").message.contains("bag"))
    }

    /// 인자가 필요한 명령을 인자 없이 치면 **이름으로 거절한다.** 조용히 아무것도 안 하면
    /// 사용자는 명령이 먹었는지조차 모른다.
    @Test func testACommandMissingItsArgumentIsRejectedByName() {
        for name in ["use", "switch", "name"] {
            #expect(throws: PokedoroCommandError.missingArgument(name)) { try parse([name]) }
        }
        #expect(PokedoroCommandError.missingArgument("use").message.contains("use"))
    }

    /// 번호 자리에 숫자가 아닌 값을 치면 거절이다 — `mon` 과 같은 부류이므로 같은 오류를 쓴다.
    @Test func testSwitchNeedsARosterNumber() {
        #expect(throws: PokedoroCommandError.invalidMonNumber("두번째")) {
            try parse(["switch", "두번째"])
        }
    }

    /// `party` 가 찍지 않는 번호(0·음수)는 **여기서** 걸러야 한다. 요청으로 내보내면 앱까지 갔다가
    /// 거절로 돌아오고, 앱이 꺼져 있으면 "응답 없음" 으로 끝나 사용자는 자기 오타를 영영 못 본다
    /// (실제로 `switch 0` 이 그렇게 나갔다).
    @Test func testARosterNumberBelowOneIsRejectedBeforeItBecomesARequest() {
        #expect(throws: PokedoroCommandError.invalidMonNumber("0")) { try parse(["switch", "0"]) }
        #expect(throws: PokedoroCommandError.invalidMonNumber("0")) { try parse(["mon", "0"]) }
    }

    /// 진화는 인자를 받지 않는다. 붙여 온 값을 조용히 버리면 사용자는 그 값이 뭔가 했다고 믿는다.
    @Test func testEvolveTakesNoArgument() {
        #expect(throws: PokedoroCommandError.unexpectedArgument("evolve")) {
            try parse(["evolve", "2"])
        }
        // 오류 타입만 맞고 문구가 비면 사용자는 왜 거절됐는지 알 수 없다.
        #expect(PokedoroCommandError.unexpectedArgument("evolve").message.contains("evolve"))
    }

    /// 네 명령 모두 **앱에 부탁한다** — 세이브를 여는 것만으로 정산이 돌 수 있어서다.
    @Test func testCompanionCommandsBecomeRequests() {
        #expect(PokedoroCommand.evolve.request == .evolve)
        #expect(PokedoroCommand.switchCompanion(number: 2).request == .switchCompanion(number: 2))
        #expect(PokedoroCommand.rename(nickname: "피카").request == .rename(nickname: "피카"))
        #expect(PokedoroCommand.use(item: .rareCandy).request == .use(item: .rareCandy))
    }

    /// 도움말이 새 명령을 알린다.
    @Test func testUsageListsTheCompanionCommands() {
        for name in ["use", "evolve", "switch", "name"] {
            #expect(PokedoroCommandParser.usage.contains(name), "도움말에 \(name) 이 없다")
        }
    }

    // MARK: 상점·부화·방생

    @Test func testShopCommandsParse() throws {
        #expect(try parse(["shop"]) == .shop)
        #expect(try parse(["buy", "이상한", "사탕"]) == .buy(good: .item(.rareCandy), quantity: 1))
        #expect(try parse(["buy", "egg"]) == .buy(good: .egg, quantity: 1))
        #expect(try parse(["hatch"]) == .hatch)
    }

    /// 수량은 이름 **뒤**에 붙는다. 이름이 여러 조각이어도 마지막 숫자만 수량이다.
    @Test func testAQuantityFollowsTheGoodName() throws {
        #expect(try parse(["buy", "이상한", "사탕", "3"]) == .buy(good: .item(.rareCandy), quantity: 3))
    }

    /// 상점은 이제 앱 전용이 아니다 — 목록도 구매도 터미널에서 된다.
    @Test func testShopIsNoLongerAnAppOnlyFeature() {
        #expect(!PokedoroCommandParser.appOnlyCommands.contains("shop"))
    }

    @Test func testAGoodTheShopDoesNotSellIsRejectedByName() {
        #expect(throws: PokedoroCommandError.unknownGood("masterball")) {
            try parse(["buy", "masterball"])
        }
        #expect(PokedoroCommandError.unknownGood("masterball").message.contains("shop"))
    }

    // MARK: 방생 — 되돌릴 수 없는 동작

    /// `--yes` 없이는 **요청이 되지 않는다.** 방생은 개체가 영영 사라지므로, 확인 없이 보내면
    /// 오타 한 번이 복구 불가능한 손실이 된다.
    @Test func testReleaseWithoutConfirmationNeverBecomesARequest() throws {
        let unconfirmed = try parse(["release", "2"])
        #expect(unconfirmed == .release(number: 2, confirmed: false))
        #expect(unconfirmed.request == nil, "확인 없는 방생이 앱까지 갔다")
    }

    /// `--yes` 를 붙이면 그때 요청이 된다.
    @Test func testReleaseWithConfirmationBecomesARequest() throws {
        let confirmed = try parse(["release", "2", "--yes"])
        #expect(confirmed == .release(number: 2, confirmed: true))
        #expect(confirmed.request == .release(number: 2))
    }

    /// 확인 플래그는 번호 해석을 방해하지 않는다 — 순서를 바꿔 쳐도 같아야 한다.
    @Test func testTheConfirmationFlagCanComeBeforeTheNumber() throws {
        #expect(try parse(["release", "--yes", "3"]) == .release(number: 3, confirmed: true))
    }

    /// 번호 없는 방생은 거절이다. 조용히 "아무거나" 를 놓아주면 안 된다.
    @Test func testReleaseNeedsARosterNumber() {
        #expect(throws: PokedoroCommandError.missingArgument("release")) { try parse(["release"]) }
        #expect(throws: PokedoroCommandError.invalidMonNumber("0")) { try parse(["release", "0"]) }
    }

    @Test func testUsageListsTheShopAndReleaseCommands() {
        for name in ["shop", "buy", "hatch", "release"] {
            #expect(PokedoroCommandParser.usage.contains(name), "도움말에 \(name) 이 없다")
        }
        #expect(PokedoroCommandParser.usage.contains("--yes"), "확인 플래그를 안 알려 주면 못 쓴다")
    }

    // MARK: 세이브를 여는가, 요청을 보내는가

    /// **이 표가 뒤집히면 피하려던 일이 그대로 일어난다.** 요청으로 가야 할 명령이 세이브를 열면
    /// 여는 것만으로 정산이 돌고(`ReadOnlyStoreTests`), 조회 명령이 요청을 보내면 앱이 꺼져
    /// 있을 때 `status` 가 3초 멈췄다 실패한다.
    @Test func testOnlySessionCommandsBecomeRequests() {
        #expect(PokedoroCommand.start(minutes: 25).request == .start(minutes: 25))
        #expect(PokedoroCommand.claim.request == .claim)
        #expect(PokedoroCommand.stop.request == .stop)
    }

    /// 명령이 든 인자가 **요청에 그대로 실린다.** 여기서 떨어지면 사용자가 고른 길이가 조용히
    /// 사라지고 앱은 기본 길이를 켠다 — 화면에는 아무 오류도 안 뜬다.
    @Test func testTheLengthTheUserTypedRidesAlongWithTheRequest() {
        #expect(PokedoroCommand.start(minutes: 90).request == .start(minutes: 90))
        #expect(PokedoroCommand.start(minutes: nil).request == .start(minutes: nil))
    }

    @Test func testReadOnlyCommandsNeverBecomeRequests() {
        let readOnly: [PokedoroCommand] = [.status(oneline: false), .status(oneline: true),
                                           .party, .dex, .watch, .help,
                                           .bag, .challenge, .goals,
                                           .mon(number: nil), .mon(number: 2)]
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
