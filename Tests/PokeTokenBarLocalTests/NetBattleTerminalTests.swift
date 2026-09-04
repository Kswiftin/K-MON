import Foundation
import Testing
@testable import PokeTokenBar

/// LAN 1대1 대전을 터미널에서 보고 턴을 내는 자리.
///
/// 웨이브 런과 **다른 통로**를 쓴다: 대전 판은 세이브에 없고 앱 메모리(`BattleCenter`)에만 살아서,
/// 터미널이 세이브를 다시 읽어도 알 수 없다. 그래서 앱이 화면 채널(`pokedoro-view.json`)로
/// 지금 판을 내놓고 터미널은 그리기만 한다 — Phase 5-0 이 집중 타이머로 만들어 둔 자리의 첫
/// 라이브 사용처다.
///
/// 여기서 재는 것은 순수 부분(투영·키·명령·요청)이다. 소켓은 여전히 앱만 든다 — 터미널이 소켓을
/// 잡으면 두 프로세스가 같은 상대에게 각자 말한다.
@Suite("NetBattleTerminalTests")
struct NetBattleTerminalTests {

    // MARK: 명령 어휘

    /// `battle` 은 이제 **앱 전용 목록에서 빠진다.** 이름만 알아보고 "앱에서 하라" 고 답하던
    /// 자리를 실제 기능이 대신한다.
    @Test func testBattleIsNoLongerAnAppOnlyCommand() {
        #expect(!PokedoroCommandParser.appOnlyCommands.contains("battle"))
    }

    @Test func testEveryBattleSubcommandParsesIntoItsRequest() throws {
        #expect(try PokedoroCommandParser.parse(["battle"]) == .battle)
        #expect(try PokedoroCommandParser.parse(["battle", "move", "2"]) == .battleMove(move: 2))
        #expect(try PokedoroCommandParser.parse(["battle", "switch", "3"]) == .battleSwitch(number: 3))
        #expect(try PokedoroCommandParser.parse(["battle", "decline"]) == .battleDecline)
        #expect(try PokedoroCommandParser.parse(["battle", "forfeit"]) == .battleForfeit(confirmed: false))
    }

    /// 조회(`battle`)만 터미널에 남는다. 다만 웨이브 런과 달리 **세이브가 아니라 화면 채널**에서
    /// 읽는다 — 그래서 조회도 앱이 떠 있어야 한다.
    @Test func testOnlyTheBattleOverviewStaysInTheTerminal() throws {
        #expect(try PokedoroCommandParser.parse(["battle"]).request == nil)
        for arguments in [["battle", "move", "1"], ["battle", "switch", "2"], ["battle", "decline"]] {
            #expect(try PokedoroCommandParser.parse(arguments).request != nil)
        }
    }

    /// 항복은 **되돌릴 수 없다** — 그 판을 지고 랭크 판돈도 넘어간다. 방생·판 포기와 같은 규칙이다.
    @Test func testForfeitingNeedsConfirmation() throws {
        #expect(try PokedoroCommandParser.parse(["battle", "forfeit"]).request == nil)
        #expect(try PokedoroCommandParser.parse(["battle", "forfeit", "--yes"]).request == .battleForfeit)
    }

    /// 거절은 확인을 받지 않는다 — **되돌릴 수 있는 일**이다(상대가 다시 걸 수 있다). 확인을
    /// 요구하면 급히 치우려는 사용자가 두 번 눌러야 한다.
    @Test func testDecliningDoesNotAskForConfirmation() throws {
        #expect(try PokedoroCommandParser.parse(["battle", "decline"]).request == .battleDecline)
    }

    @Test func testBattleActionNamesAreNamespaced() {
        #expect(PokedoroRequest.Action.battleMove(move: 1).name == "battle.move")
        #expect(PokedoroRequest.Action.battleSwitch(number: 1).name == "battle.switch")
        #expect(PokedoroRequest.Action.battleForfeit.name == "battle.forfeit")
        #expect(PokedoroRequest.Action.battleDecline.name == "battle.decline")
    }

    @Test func testEveryBattleActionSurvivesTheRoundTripThroughTheFile() throws {
        let actions: [PokedoroRequest.Action] = [
            .battleMove(move: 3), .battleSwitch(number: 2), .battleForfeit, .battleDecline
        ]
        for action in actions {
            let sent = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
            let back = try JSONDecoder().decode(PokedoroRequest.self,
                                                from: try JSONEncoder().encode(sent))
            #expect(back.action == action, "\(action.name) 이 왕복에서 달라졌다")
        }
    }

    @Test func testAHandEditedFileCannotSmuggleAnImpossibleBattleNumber() {
        #expect(PokedoroRequest.Action(name: "battle.move", argument: "0") == nil)
        #expect(PokedoroRequest.Action(name: "battle.switch", argument: "-1") == nil)
        #expect(PokedoroRequest.Action(name: "battle.forfeit", argument: "1") == nil)
        #expect(PokedoroRequest.Action(name: "battle.decline", argument: "1") == nil)
    }

    // MARK: 화면 투영

    /// 대전이 없으면 **없다고 말하고 어디서 시작하는지 알려 준다.** 대전 신청은 상대를 찾는
    /// 일이라 터미널에서 할 수 없다(소켓을 앱이 든다).
    @Test func testNoBattleSaysWhereToStartOne() {
        let idle = BattleTerminalState(phase: .ready, battle: nil)
        #expect(NetBattleScreen.kind(idle) == .none)
        #expect(NetBattleScreen.numbers(idle).isEmpty)
        #expect(NetBattleScreen.lines(idle, language: .ko, width: 60)
            .contains { $0.contains("앱") })
    }

    /// 내 차례면 숫자 키가 **기술**이고, 남은 시간을 함께 보여 준다 — 턴 마감이 지나면 첫 기술이
    /// 자동으로 나가므로(`BattleCenter.automaticMoveIndex`) 남은 초는 곧 사용자의 예산이다.
    @Test func testOnMyTurnTheNumbersAreMovesAndTheClockIsShown() throws {
        let state = Self.battling(remaining: 23)
        #expect(NetBattleScreen.kind(state) == .move)
        let choices = NetBattleScreen.choices(state, language: .ko)
        #expect(choices.count == 2)
        #expect(choices.first?.number == 1)
        #expect(choices.first?.label.contains("타격") == true)
        #expect(NetBattleScreen.action(number: 1, in: state) == .battleMove(move: 1))
        #expect(NetBattleScreen.lines(state, language: .ko, width: 60)
            .contains { $0.contains("23") }, "남은 시간이 안 보이면 자동 제출을 예측할 수 없다")
    }

    /// 이미 낸 턴에는 **누를 것이 없다.** 기술을 계속 권하면 사용자는 자기 입력이 씹혔다고 읽는다.
    @Test func testAfterSubmittingTheTurnThereIsNothingToPress() {
        var state = Self.battling()
        state.battle?.myAction = .move(index: 0)
        #expect(NetBattleScreen.kind(state) == .waiting)
        #expect(NetBattleScreen.numbers(state).isEmpty)
        #expect(NetBattleScreen.hints(state).contains("상대"))
    }

    /// 쓰러진 자리는 **먼저 메운다.** 그 국면에서 기술을 권하면 눌러도 아무 일이 없다
    /// (`NetBattleState.canChoose` 가 죽은 개체의 기술을 거절한다).
    @Test func testAFaintedActiveAsksForAReplacementFirst() {
        var state = Self.battling(teamSize: 2)
        state.battle?.myTeam[0].hp = 0
        #expect(NetBattleScreen.kind(state) == .sendOut)
        // 번호는 **팀 번호**다 — 목록 순번을 따로 매기면 화면과 명령이 다른 번호를 쓴다.
        #expect(NetBattleScreen.numbers(state) == [2])
        #expect(NetBattleScreen.action(number: 2, in: state) == .battleSwitch(number: 2))
        #expect(NetBattleScreen.action(number: 1, in: state) == nil, "쓰러진 자기 자신으로는 못 바꾼다")
    }

    /// 신청을 받은 국면에서는 **거절만** 할 수 있다 — 수락은 6마리 후보를 고르는 화면으로
    /// 이어지고 그 화면은 앱에만 있다. 수락 키를 권하면 누른 뒤 아무 일도 안 일어난다.
    @Test func testAnIncomingChallengeOffersOnlyDecline() {
        let state = BattleTerminalState(phase: .incoming(peer: "옆자리"), battle: nil)
        #expect(NetBattleScreen.kind(state) == .incoming)
        #expect(NetBattleScreen.numbers(state).isEmpty)
        #expect(NetBattleScreen.hints(state).contains("거절"))
        #expect(NetBattleScreen.hints(state).contains("앱"), "수락은 앱에서 한다고 말해야 한다")
        #expect(NetBattleScreen.lines(state, language: .ko, width: 60)
            .contains { $0.contains("옆자리") }, "누가 걸었는지 안 보이면 수락 판단이 불가능하다")
    }

    /// 파티를 편성하는 국면들은 **앱에서만** 한다. 진행 중이라는 사실과 어디서 하는지를 말한다 —
    /// 빈 화면을 그리면 사용자는 대전이 끊긴 줄 안다.
    @Test func testTeamBuildingPhasesSayTheyBelongToTheApp() {
        for phase: BattleCenter.Phase in [.preparing, .poolSelecting(peer: "P"),
                                          .poolBuilding(peer: "P"), .teamBuilding(peer: "P"),
                                          .waitingTeam(peer: "P"), .challenging(peer: "P")] {
            let state = BattleTerminalState(phase: phase, battle: nil)
            #expect(NetBattleScreen.kind(state) == .appOnly, "\(phase) 가 앱 전용으로 안 잡혔다")
            #expect(NetBattleScreen.numbers(state).isEmpty)
        }
    }

    /// 끝난 대전은 결과를 말한다. 승패와 항복을 갈라 말한다 — 같은 "졌다" 라도 사용자가 한 일이 다르다.
    @Test func testAFinishedBattleSaysHowItEnded() {
        let won = BattleTerminalState(phase: .finished(iWon: true, byForfeit: false), battle: nil)
        let forfeited = BattleTerminalState(phase: .finished(iWon: false, byForfeit: true), battle: nil)
        #expect(NetBattleScreen.kind(won) == .finished)
        #expect(NetBattleScreen.lines(won, language: .ko, width: 60).contains { $0.contains("이겼") })
        #expect(NetBattleScreen.lines(forfeited, language: .ko, width: 60)
            .contains { $0.contains("항복") })
    }

    @Test func testEveryLineFitsTheRequestedWidth() {
        for state in [Self.battling(remaining: 30), Self.battling(teamSize: 3),
                      BattleTerminalState(phase: .incoming(peer: "아주아주긴이름을가진트레이너"), battle: nil)] {
            for width in [20, 40, 80] {
                for line in NetBattleScreen.lines(state, language: .ko, width: width) {
                    #expect(TUIText.displayWidth(line) <= width, "폭 \(width) 에서 넘친 줄: \(line)")
                }
            }
        }
    }

    // MARK: 화면 채널 — 바뀐 게 없어도 살아 있다고 말해야 한다

    /// **이 부류가 5-2 에서 드러났다.** 집중 타이머는 매초 글자가 바뀌어 늘 다시 쓰였지만, 대전은
    /// 상대를 기다리는 30초 동안 화면이 한 글자도 안 바뀐다. 내용만 비교하면 그 사이 파일이
    /// 갱신되지 않아 **낡은 것으로 판정되고**(`isStale`, 5초) 터미널이 진행 중인 대전을 지운다.
    @Test func testAnUnchangedScreenIsRefreshedBeforeItGoesStale() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let written = PokedoroViewSnapshot(screen: "battle", title: "대전", lines: ["HP 30/30"],
                                           keys: ["1 기술"], writtenAt: now)
        var same = written
        // 갱신 주기 전에는 다시 쓰지 않는다 — 연출 프레임마다 쓰면 디스크가 갈린다.
        same.writtenAt = now.addingTimeInterval(PokedoroViewChannel.refreshInterval - 0.1)
        #expect(!PokedoroViewChannel.shouldWrite(same, lastWritten: written))
        // 주기를 넘기면 **내용이 같아도** 다시 쓴다. 그래야 낡음 판정에 걸리지 않는다.
        same.writtenAt = now.addingTimeInterval(PokedoroViewChannel.refreshInterval)
        #expect(PokedoroViewChannel.shouldWrite(same, lastWritten: written))
    }

    /// 갱신 주기는 **낡음 한계보다 짧아야 한다.** 같거나 길면 안 바뀌는 화면이 반드시 한 번은
    /// 낡은 상태를 지나고, 그 순간 터미널이 진행 중인 대전을 지운다.
    @Test func testTheRefreshIntervalStaysUnderTheStaleLimit() {
        #expect(PokedoroViewChannel.refreshInterval < PokedoroViewChannel.snapshotTimeout)
    }

    /// 생산자가 여럿이면 **하나를 고른다.** 대전이 집중 타이머보다 앞이다 — 라이브 판이 도는 동안
    /// 타이머 줄을 그리면 사용자는 자기 차례를 놓친다.
    @Test func testALiveBattleOutranksTheFocusTimer() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let focus = try #require(PokedoroViewChannel.focusSnapshot(phase: .focus, clockText: "12:34",
                                                                    completed: 1, now: now))
        let battle = PokedoroViewChannel.battleSnapshot(Self.battling(remaining: 10),
                                                        language: .ko, width: 60, now: now)
        #expect(battle != nil)
        #expect(PokedoroViewChannel.preferred([battle, focus])?.screen == "battle")
        // 대전이 없으면 타이머가 그려진다 — 우선순위는 있음/없음을 덮어쓰지 않는다.
        #expect(PokedoroViewChannel.preferred([nil, focus])?.screen == "focus")
        #expect(PokedoroViewChannel.preferred([nil, nil]) == nil)
    }

    /// 아무 대전도 없으면 **화면을 내놓지 않는다** — 빈 스냅샷을 쓰면 터미널이 빈 줄을 그리고
    /// 타이머 생산자까지 덮는다.
    @Test func testAnIdleBattleCenterProducesNoSnapshot() {
        #expect(PokedoroViewChannel.battleSnapshot(BattleTerminalState(phase: .ready, battle: nil),
                                                    language: .ko, width: 60, now: Date()) == nil)
    }

    /// 키 안내는 **앱이 보낸다**(채널의 규칙). 내 차례가 아니면 기술 키가 실리지 않아야 한다.
    @Test func testTheSnapshotCarriesOnlyThePressableKeys() throws {
        var mine = Self.battling(remaining: 20)
        let onMyTurn = try #require(PokedoroViewChannel.battleSnapshot(mine, language: .ko,
                                                                        width: 60, now: Date()))
        #expect(onMyTurn.keys.contains { $0.contains("기술") })

        mine.battle?.myAction = .move(index: 0)
        let waiting = try #require(PokedoroViewChannel.battleSnapshot(mine, language: .ko,
                                                                       width: 60, now: Date()))
        #expect(!waiting.keys.contains { $0.contains("기술") },
                "낸 뒤에도 기술 키를 권하면 누른 사용자는 입력이 씹혔다고 읽는다")
    }

    /// 국면마다 **키 안내와 한 줄 안내가 함께 바뀐다.** 하나만 바뀌면 화면 아래와 채널이
    /// 서로 다른 키를 권한다.
    @Test func testEveryPhaseAdvertisesOnlyWhatItCanDo() {
        var faint = Self.battling(teamSize: 2)
        faint.battle?.myTeam[0].hp = 0
        #expect(NetBattleScreen.keys(faint).contains { $0.contains("교체") })
        #expect(NetBattleScreen.hints(faint).contains("battle switch"))

        let incoming = BattleTerminalState(phase: .incoming(peer: "P"), battle: nil)
        #expect(NetBattleScreen.keys(incoming) == ["n 거절"])

        let mine = Self.battling()
        #expect(NetBattleScreen.hints(mine).contains("battle move"))

        // 앱 전용 국면과 끝난 판은 **누를 키가 없다** — 있으면 그건 안내가 아니라 함정이다.
        for state in [BattleTerminalState(phase: .teamBuilding(peer: "P"), battle: nil),
                      BattleTerminalState(phase: .finished(iWon: nil, byForfeit: false), battle: nil),
                      BattleTerminalState(phase: .ready, battle: nil)] {
            #expect(NetBattleScreen.keys(state).isEmpty, "\(state.phase) 가 키를 권했다")
            #expect(!NetBattleScreen.hints(state).isEmpty, "무엇을 기다리는지는 말해야 한다")
        }
    }

    /// 교체 목록은 **팀 번호와 남은 HP**를 함께 찍는다 — 누구로 바꿀지는 HP 로 정한다.
    @Test func testTheReplacementListShowsWhoIsLeft() throws {
        var state = Self.battling(teamSize: 2)
        state.battle?.myTeam[0].hp = 0
        let only = try #require(NetBattleScreen.choices(state, language: .ko).first)
        #expect(only.number == 2)
        #expect(only.label.contains("내2"))
        #expect(only.label.contains("/"), "남은 HP 가 안 보이면 교체 판단이 감이 된다")
    }

    /// 신청을 보낸 쪽과 편성 중인 국면도 **무엇을 기다리는지 한 줄로** 말한다.
    @Test func testWaitingPhasesNameWhatTheyWaitFor() {
        let sent = BattleTerminalState(phase: .challenging(peer: "옆자리"), battle: nil)
        #expect(NetBattleScreen.lines(sent, language: .ko, width: 60)
            .contains { $0.contains("옆자리") })
        let building = BattleTerminalState(phase: .teamBuilding(peer: "옆자리"), battle: nil)
        #expect(NetBattleScreen.lines(building, language: .ko, width: 60)
            .contains { $0.contains("앱") })
    }

    /// 턴이 돌면 로그가 판에 남는다 — HP 숫자만 바뀌면 무엇에 맞았는지 알 수 없다.
    @Test func testThePanelCarriesTheTurnLog() throws {
        var state = Self.battling()
        // 스트림을 직접 놓는다. 실제로 턴을 돌리려면 상대 행동까지 필요하고, 그 규칙은
        // `MultiplayerBattle` 쪽 테스트가 이미 든다 — 여기서 재는 것은 **투영**이다.
        let mine: BattleActor = .a
        var battle = try #require(state.battle)
        let stream: [BattleEvent] = [.turn(1), .move(mine, moveID: 1)]
        battle.events = stream
        battle.eventBatches = [NetBattleEventBatch(events: stream, a: battle.me, b: battle.opp)]
        state.battle = battle
        #expect(!NetBattleScreen.log(battle, language: .ko).isEmpty)
        #expect(NetBattleScreen.lines(state, language: .ko, width: 80)
            .contains { $0.contains("타격") })
    }

    // MARK: 키 배정

    @Test func testTheBattleScreenHasItsOwnKey() throws {
        let screen = try #require(TUIScreen.screen(for: "v"))
        #expect(screen == .battle)
        #expect(!screen.isList, "대전 화면은 목록이 아니다 — 커서가 없다")
    }

    /// 웨이브 화면에서 배운 부류를 다시 밟지 않는다 — 새 판 화면이 홈의 숫자 키를 물려받으면
    /// 대전 중에 기술을 고르려다 집중 세션이 시작된다.
    @Test func testNumbersOnTheBattleScreenAreNotFocusLengths() {
        for key: Character in ["1", "2", "3"] {
            #expect(TUIKeymap.action(for: .char(key), screen: .battle, canWrite: true)
                    == .battleChoice(Int(String(key)) ?? 0))
        }
    }

    @Test func testTheBattleScreenKeysAreItsOwn() {
        #expect(TUIKeymap.action(for: .char("f"), screen: .battle, canWrite: true) == .forfeitBattle)
        #expect(TUIKeymap.action(for: .char("n"), screen: .battle, canWrite: true) == .declineBattle)
        // 웨이브 화면의 키가 여기서 먹으면 안 된다 — 볼 던지기는 이 화면에 없는 동작이다.
        #expect(TUIKeymap.action(for: .char("t"), screen: .battle, canWrite: true) == .ignored)
    }

    @Test func testBattleKeysAreRefusedNotIgnoredWithoutWriteAccess() {
        #expect(TUIKeymap.action(for: .char("1"), screen: .battle, canWrite: false)
                == .rejected(.readOnly))
    }

    // MARK: 픽스처

    /// 내 차례인 대전. 팀 크기를 키우면 교체 후보가 생긴다.
    static func battling(teamSize: Int = 1, remaining: Int? = nil) -> BattleTerminalState {
        BattleTerminalState(
            phase: .battling,
            battle: NetBattleState(iAmA: true,
                                   myTeam: (0..<teamSize).map { BattleSide(snapshot(name: "내\($0 + 1)")) },
                                   oppTeam: [BattleSide(snapshot(name: "상대"))],
                                   rng: SplitMix64(seed: 3)),
            remainingSeconds: remaining)
    }

    static func snapshot(name: String) -> BattleSnapshot {
        BattleSnapshot(
            speciesID: 1, name: name, trainer: "T", level: 50, nature: nil, isShiny: false,
            types: [.normal],
            base: BattleStats(hp: 100, atk: 100, def: 50, spa: 100, spd: 50, spe: 100),
            moves: [MoveSpec(id: 1, names: ["ko": "타격", "en": "Hit"], type: .normal, power: 40,
                             damageClass: .physical, accuracy: nil, pp: 20),
                    MoveSpec(id: 2, names: ["ko": "울음", "en": "Growl"], type: .normal, power: 0,
                             damageClass: .status, accuracy: nil, pp: 40)])
    }
}
