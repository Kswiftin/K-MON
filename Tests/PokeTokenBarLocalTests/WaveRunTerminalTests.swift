import Foundation
import Testing
@testable import PokeTokenBar

/// 웨이브 런을 터미널에서 도는 자리 — **명령 어휘 · 요청 왕복 · 화면 투영 · 키 배정**의 순수 부분.
///
/// 실행(앱이 세이브를 바꾸는 쪽)은 `WaveRunExecutorTests` 에 있다. 여기가 따로 있는 이유는
/// 나머지 터미널 코어와 같다 — 이 네 층은 프로세스를 띄우지 않고 전수 검증할 수 있어야 하고,
/// 그래야 "안내에 있는 키가 안 먹는다" 부류가 테스트에 잡힌다.
@Suite("WaveRunTerminalTests")
struct WaveRunTerminalTests {

    // MARK: 명령 어휘

    /// 하위 명령이 **하나의 접두어 아래** 산다. `move`·`pick` 같은 흔한 낱말을 최상위에 두면
    /// 다음 라이브 기능(레이드·PvP)이 같은 낱말을 쓰고 싶을 때 이름이 이미 팔려 있다.
    @Test func testEveryWaveSubcommandParsesIntoItsRequest() throws {
        #expect(try PokedoroCommandParser.parse(["wave"]) == .wave)
        #expect(try PokedoroCommandParser.parse(["wave", "start"]) == .waveStart(starter: nil))
        #expect(try PokedoroCommandParser.parse(["wave", "start", "3"]) == .waveStart(starter: 3))
        #expect(try PokedoroCommandParser.parse(["wave", "move", "2"]) == .waveMove(move: 2, target: nil))
        #expect(try PokedoroCommandParser.parse(["wave", "move", "2", "1"]) == .waveMove(move: 2, target: 1))
        #expect(try PokedoroCommandParser.parse(["wave", "switch", "2"]) == .waveSwitch(number: 2))
        #expect(try PokedoroCommandParser.parse(["wave", "ball"]) == .waveBall(target: nil))
        #expect(try PokedoroCommandParser.parse(["wave", "ball", "2"]) == .waveBall(target: 2))
        #expect(try PokedoroCommandParser.parse(["wave", "pick", "1"]) == .wavePick(number: 1))
        #expect(try PokedoroCommandParser.parse(["wave", "route", "risky"]) == .waveRoute(.risky))
    }

    /// 조회(`wave`)만 세이브를 읽고 나머지는 **전부 앱에 부탁한다** — 터미널이 세이브에 쓰는 경로는
    /// 이 기능에서도 늘지 않는다.
    @Test func testOnlyTheWaveOverviewStaysInTheTerminal() throws {
        #expect(try PokedoroCommandParser.parse(["wave"]).request == nil)
        for arguments in [["wave", "start"], ["wave", "move", "1"], ["wave", "switch", "2"],
                          ["wave", "ball"], ["wave", "pick", "1"], ["wave", "route", "safe"]] {
            #expect(try PokedoroCommandParser.parse(arguments).request != nil,
                    "\(arguments) 가 요청이 되지 않으면 조용한 무동작이 된다")
        }
    }

    /// 판을 버리는 것은 **되돌릴 수 없다** — 방생과 같은 규칙으로 `--yes` 없이는 요청이 되지 않는다.
    /// 웨이브 런은 세이브에 남는 유일한 진행이라 오타 한 번에 사라지면 안 된다.
    @Test func testForfeitingARunNeedsTheSameConfirmationAsReleasing() throws {
        #expect(try PokedoroCommandParser.parse(["wave", "forfeit"]) == .waveForfeit(confirmed: false))
        #expect(try PokedoroCommandParser.parse(["wave", "forfeit"]).request == nil)
        #expect(try PokedoroCommandParser.parse(["wave", "forfeit", "--yes"]).request == .waveForfeit)
    }

    /// 모르는 하위 명령은 **오타로 말한다** — `wave` 를 통째로 모르는 명령으로 접으면 사용자는
    /// 기능 자체가 없다고 읽는다.
    @Test func testAnUnknownSubcommandNamesWhatWasTyped() {
        #expect(throws: PokedoroCommandError.unknownCommand("wave bogus")) {
            try PokedoroCommandParser.parse(["wave", "bogus"])
        }
    }

    /// 번호가 필요한 하위 명령은 인자 없이 통과하지 않는다.
    @Test func testSubcommandsThatNeedANumberSayItIsMissing() {
        for name in ["move", "switch", "pick", "route"] {
            #expect(throws: PokedoroCommandError.missingArgument("wave \(name)")) {
                try PokedoroCommandParser.parse(["wave", name])
            }
        }
    }

    /// 숫자가 아닌 번호는 **웨이브 런의 안내로** 답한다 — `party` 번호를 보라고 하면 다른 목록을
    /// 뒤지게 된다(개체 번호와 오류를 나눠 둔 이유와 같다).
    @Test func testANonNumberIsRejectedWithWaveSpecificAdvice() {
        #expect(throws: PokedoroCommandError.invalidWaveNumber("2x")) {
            try PokedoroCommandParser.parse(["wave", "move", "2x"])
        }
        // 0 은 목록에 없는 번호다. 그대로 인덱스로 접으면 배열 밖을 읽거나 엉뚱한 칸을 건드린다.
        #expect(throws: PokedoroCommandError.invalidWaveNumber("0")) {
            try PokedoroCommandParser.parse(["wave", "pick", "0"])
        }
    }

    /// 길은 **닫힌 목록**이다(`RunRoute`). 모르는 이름을 안전한 길로 접으면 사용자는 위험한 길을
    /// 골랐다고 믿은 채 보상 한 장을 잃는다.
    @Test func testAnUnknownRouteIsRejectedInsteadOfFallingBackToSafe() {
        #expect(throws: PokedoroCommandError.unknownRoute("hard")) {
            try PokedoroCommandParser.parse(["wave", "route", "hard"])
        }
    }

    /// 도움말은 표에서 나온다 — 명령을 더하고 표를 빠뜨리면 사용자가 그 명령을 알 길이 없다.
    @Test func testTheUsageTextListsTheWaveCommands() {
        #expect(PokedoroCommandParser.usage.contains("wave"))
        #expect(PokedoroCommandParser.usage.contains("--yes"))
    }

    // MARK: 요청 왕복

    /// 요청 파일은 **평평한 JSON** 이고 손으로 고칠 수 있다. 왕복이 값을 보존하지 않으면
    /// 사용자가 적은 것과 앱이 실행하는 것이 갈라진다.
    @Test func testEveryWaveActionSurvivesTheRoundTripThroughTheFile() throws {
        let actions: [PokedoroRequest.Action] = [
            .waveStart(starter: nil), .waveStart(starter: 3),
            .waveMove(move: 2, target: nil), .waveMove(move: 2, target: 1),
            .waveSwitch(number: 4), .waveBall(target: nil), .waveBall(target: 2),
            .wavePick(number: 3), .waveRoute(.risky), .waveForfeit
        ]
        for action in actions {
            let sent = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
            let data = try JSONEncoder().encode(sent)
            let back = try JSONDecoder().decode(PokedoroRequest.self, from: data)
            #expect(back.action == action, "\(action.name) 이 왕복에서 달라졌다")
        }
    }

    /// 이름은 **접두어로 묶는다**. 집중 세션의 `start`·`stop` 과 같은 이름을 쓰면 손으로 고친
    /// 파일에서 어느 기능의 동작인지 알 수 없다.
    @Test func testWaveActionNamesAreNamespaced() {
        #expect(PokedoroRequest.Action.waveStart(starter: nil).name == "wave.start")
        #expect(PokedoroRequest.Action.waveMove(move: 1, target: nil).name == "wave.move")
        #expect(PokedoroRequest.Action.waveRoute(.safe).name == "wave.route")
    }

    /// 인자 없는 `wave.start` 는 **무작위 스타터**다 — 0 이나 1 을 채워 적으면 기본값이 두 곳이 되고,
    /// 한쪽만 바뀌는 날 터미널과 앱이 다른 판을 연다(집중 길이와 같은 규칙).
    @Test func testStartingWithoutAStarterWritesNoArgument() {
        #expect(PokedoroRequest.Action.waveStart(starter: nil).argument == nil)
        #expect(PokedoroRequest.Action.waveBall(target: nil).argument == nil)
        // 타겟 1 은 안 적는다 — 같은 요청이 두 모양으로 존재하면 손으로 고친 파일과 프로그램이
        // 쓴 파일이 달라 보인다(`buy` 의 수량 1 과 같은 규칙).
        #expect(PokedoroRequest.Action.waveMove(move: 2, target: nil).argument == "2")
    }

    /// 파일에 적힌 0·음수·글자는 **동작이 되지 않는다.** 요청 파일이 신뢰경계라 명령 파서만
    /// 검사하면 손으로 고친 경로가 통째로 빈다.
    @Test func testAHandEditedFileCannotSmuggleAnImpossibleNumber() {
        #expect(PokedoroRequest.Action(name: "wave.move", argument: "0") == nil)
        #expect(PokedoroRequest.Action(name: "wave.move", argument: "1 0") == nil)
        #expect(PokedoroRequest.Action(name: "wave.pick", argument: "-1") == nil)
        #expect(PokedoroRequest.Action(name: "wave.switch", argument: "two") == nil)
        #expect(PokedoroRequest.Action(name: "wave.route", argument: "hard") == nil)
        // 인자를 받지 않는 동작에 인자가 붙었으면 추측하지 않는다.
        #expect(PokedoroRequest.Action(name: "wave.forfeit", argument: "1") == nil)
    }

    // MARK: 화면 투영

    /// 진행 중인 판이 없으면 **없다고 말하고 여는 법을 알려 준다.** 빈 화면을 그리면 고장으로 읽힌다.
    @Test func testTheScreenTellsYouHowToOpenARunWhenThereIsNone() {
        let lines = WaveRunScreen.lines(nil, language: .korean, width: 60)
        #expect(!lines.isEmpty)
        #expect(lines.contains { $0.contains("wave start") })
        #expect(WaveRunScreen.choices(nil, language: .korean).isEmpty)
    }

    /// 전투 중에는 숫자 키가 **기술**이다. PP 와 함께 찍는 이유는 남은 PP 가 곧 이 판의 자원이라
    /// 보이지 않으면 발버둥에 몰리는 순간을 예측할 수 없어서다.
    @Test func testDuringABattleTheNumbersAreMoves() throws {
        let run = Self.battlingRun()
        #expect(WaveRunScreen.kind(run) == .move)
        let choices = WaveRunScreen.choices(run, language: .korean)
        #expect(choices.count == 2, "기술 수만큼 찍는다")
        #expect(choices.first?.number == 1, "번호는 1부터다 — 0번 기술을 보여 주면 무엇을 칠지 모른다")
        #expect(choices.first?.label.contains("타격") == true)
        #expect(choices.first?.label.contains("20") == true, "남은 PP 가 보여야 한다")
    }

    /// 보상 화면에서는 같은 숫자 키가 **보상**이다. 화면마다 표를 새로 쓰지 않는다 —
    /// 숫자 → 요청 변환이 한 곳(`WaveRunScreen.action`)이라야 안내와 실행이 갈라지지 않는다.
    @Test func testWhilePickingTheNumbersAreRewards() {
        var run = Self.battlingRun()
        run.debugSetStagePicking(offering: [.potion])
        #expect(WaveRunScreen.kind(run) == .offer)
        #expect(WaveRunScreen.choices(run, language: .korean).count == 1)
        #expect(WaveRunScreen.action(number: 1, in: run) == .wavePick(number: 1))
    }

    /// 길 고르기에서는 두 숫자가 두 길이다. 순서는 `RunRoute.allCases` 에서 나온다 —
    /// 손으로 적으면 길을 더할 때 번호와 실제 길이 어긋난다.
    @Test func testWhileRoutingTheNumbersAreRoutes() {
        var run = Self.battlingRun()
        run.debugSetStageRouting()
        #expect(WaveRunScreen.kind(run) == .route)
        #expect(WaveRunScreen.action(number: 1, in: run) == .waveRoute(RunRoute.allCases[0]))
        #expect(WaveRunScreen.action(number: 2, in: run) == .waveRoute(RunRoute.allCases[1]))
    }

    /// **제안은 실행 가능한 것의 부분집합이다.** 목록에 없는 번호는 요청이 되지 않는다 — 안 그러면
    /// 눌러도 거절만 돌아오는 키를 화면이 권하게 된다.
    @Test func testANumberThatIsNotOfferedProducesNoRequest() {
        let run = Self.battlingRun()
        #expect(WaveRunScreen.action(number: 3, in: run) == nil, "기술이 둘인데 3번이 요청이 됐다")
        #expect(WaveRunScreen.action(number: 1, in: nil) == nil)
    }

    /// 쓰러진 칸이 있으면 **먼저 채워야 한다**(`slotsNeedingSendOut`). 그 상태에서 기술을 권하면
    /// 눌러도 아무 일이 안 일어나고, 사용자는 키가 죽은 줄 안다.
    @Test func testAFaintedSlotAsksToBeFilledBeforeAnythingElse() {
        var run = Self.battlingRun(partySize: 2)
        run.debugFaintInBattle(0)
        #expect(WaveRunScreen.kind(run) == .sendOut)
        #expect(WaveRunScreen.action(number: 1, in: run) == nil,
                "채워야 할 칸이 있는 동안 숫자 키는 기술이 아니다")
        #expect(WaveRunScreen.hints(run).contains("switch"))
    }

    /// 끝난 판은 결과를 말한다 — 아무 말도 안 하면 사용자는 왜 키가 안 먹는지 모른다.
    @Test func testAFinishedRunSaysHowItEnded() {
        var run = Self.battlingRun()
        run.debugFaintInBattle(0)
        run.useMove(0)   // 전멸 판정을 지난다
        #expect(run.stage == .failed)
        #expect(WaveRunScreen.kind(run) == .none)
        #expect(WaveRunScreen.lines(run, language: .korean, width: 60)
            .contains { $0.contains("전멸") })
    }

    /// 모든 줄이 요청한 폭 안에 든다. 넘치면 터미널이 줄을 접어 다음 줄을 밀어내고, 전체 다시
    /// 그리기 방식에서는 그 밀림이 복구되지 않는다.
    @Test func testEveryLineFitsTheRequestedWidth() {
        let run = Self.battlingRun()
        for width in [20, 40, 80] {
            for line in WaveRunScreen.lines(run, language: .korean, width: width) {
                #expect(TUIText.displayWidth(line) <= width, "폭 \(width) 에서 넘친 줄: \(line)")
            }
        }
    }

    // MARK: 키 배정

    /// 웨이브 화면에도 자기 키가 있다. `TUIScreen` 의 표 하나에서 키와 이름이 함께 나오므로
    /// 안내와 실제 이동이 갈라지지 않는다.
    @Test func testTheWaveScreenHasItsOwnKey() throws {
        let screen = try #require(TUIScreen.screen(for: "w"))
        #expect(screen == .wave)
        #expect(TUIKeymap.action(for: .char("w"), screen: .home, canWrite: true) == .show(.wave))
    }

    /// 화면 키는 **서로 달라야 한다.** 겹치면 뒤에 선언된 화면에 영영 못 간다.
    @Test func testNoTwoScreensShareAKey() {
        #expect(Set(TUIScreen.allCases.map(\.key)).count == TUIScreen.allCases.count)
    }

    /// **웨이브 화면의 숫자 키는 집중 세션을 켜지 않는다.** 홈의 1·2·3 이 그대로 살아 있으면
    /// 대전 중에 기술을 고르려다 25분 집중이 시작된다 — 새 화면이 홈의 키를 조용히 물려받는 부류다.
    @Test func testNumbersOnTheWaveScreenAreNotFocusLengths() {
        for key: Character in ["1", "2", "3"] {
            let action = TUIKeymap.action(for: .char(key), screen: .wave, canWrite: true)
            #expect(action == .waveChoice(Int(String(key)) ?? 0),
                    "웨이브 화면의 \(key) 가 홈의 동작으로 샜다: \(action)")
        }
    }

    /// 볼 던지기 키가 `b` 가 아닌 이유는 **`b` 가 가방 화면 키**라서다 — 화면 이동 키가 먼저
    /// 잡히므로 `b` 를 배정하면 아무 데서도 안 먹는 키가 된다.
    @Test func testThrowingABallDoesNotCollideWithTheBagScreenKey() {
        #expect(TUIKeymap.action(for: .char("b"), screen: .wave, canWrite: true) == .show(.bag))
        #expect(TUIKeymap.action(for: .char("t"), screen: .wave, canWrite: true) == .throwWaveBall)
    }

    /// 판을 버리는 키는 **확인을 거친다** — 되돌릴 수 없는 동작이라 방생과 같은 규칙이다.
    @Test func testForfeitingFromTheScreenAsksFirst() {
        #expect(TUIKeymap.action(for: .char("f"), screen: .wave, canWrite: true) == .forfeitWaveRun)
        // 확인을 기다리는 동안은 `y` 외의 모든 키가 취소다(방생과 같은 표를 지난다).
        #expect(TUIKeymap.action(for: .char("1"), screen: .wave, canWrite: true,
                                 awaitingConfirmation: true) == .cancelConfirmation)
    }

    /// 쓰기 권한이 없으면 침묵이 아니라 **거절**이다 — `.ignored` 로 접으면 "키가 안 먹는다" 와
    /// 구분되지 않는다.
    @Test func testWaveKeysAreRefusedNotIgnoredWithoutWriteAccess() {
        #expect(TUIKeymap.action(for: .char("1"), screen: .wave, canWrite: false)
                == .rejected(.readOnly))
        #expect(TUIKeymap.action(for: .char("t"), screen: .wave, canWrite: false)
                == .rejected(.readOnly))
    }

    /// 웨이브 화면은 목록이 아니다 — 커서가 없으므로 스크롤 키를 받으면 아무 데도 안 쓰이는
    /// 값이 움직인다(홈과 같은 규칙).
    @Test func testTheWaveScreenTakesNoCursorKeys() {
        #expect(TUIKeymap.action(for: .up, screen: .wave, canWrite: true) == .ignored)
        #expect(TUIKeymap.action(for: .char("j"), screen: .wave, canWrite: true) == .ignored)
    }

    // MARK: 픽스처

    /// 전투 중인 판 하나. 상대는 한 마리, 내 파티는 `partySize` 마리다.
    static func battlingRun(partySize: Int = 1) -> RogueRun {
        RogueRun(party: (0..<partySize).map { snapshot(name: "내\($0)") },
                 opponents: [snapshot(name: "야생")], seed: 7)
    }

    static func snapshot(name: String, level: Int = 5) -> BattleSnapshot {
        BattleSnapshot(
            speciesID: 1, name: name, trainer: nil, level: level, nature: nil, isShiny: false,
            types: [.normal],
            base: BattleStats(hp: 100, atk: 100, def: 50, spa: 100, spd: 50, spe: 100),
            moves: [MoveSpec(id: 1, names: ["ko": "타격", "en": "Hit"], type: .normal, power: 40,
                             damageClass: .physical, accuracy: nil, pp: 20),
                    MoveSpec(id: 2, names: ["ko": "울음", "en": "Growl"], type: .normal, power: 0,
                             damageClass: .status, accuracy: nil, pp: 40)])
    }
}
