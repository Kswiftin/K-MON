import Foundation
import Testing
@testable import PokeTokenBar

/// 체육관·토너먼트·포켓슬론·OX 퀴즈를 터미널에서 보고 손을 내는 자리 (Phase 5-7).
///
/// **계획서의 전제가 틀렸다.** "#252 의 `RoomScreen` 이 이미 이 넷의 전투 턴을 덮는다" 고 적혀
/// 있었지만, 덮은 것은 `case` 열거뿐이었다 — 그 넷의 판은 `combatFighters` 에 없다. 체육관은
/// `gymMatch`, 토너먼트는 `tournamentState.currentMatch`, 포켓슬론은 `pokeathlonRace`, 퀴즈는
/// `pokemonQuizGame` 에 산다. 그래서 화면은 판이 끝날 때까지 "판을 준비하는 중이다" 만 찍었다.
///
/// 넷을 넷으로 다루지 않는다 — **두 형태다.**
/// - **결투**(체육관·토너먼트): 두 사람, 각자 팀, 기술과 교체. 두 상태가 구조적으로 같다.
/// - **트랙**(포켓슬론·퀴즈): 참가자 여럿, 각자 위치, 방향 입력. 퀴즈의 O/X 가 레인과 같은 축이다.
///
/// 그래서 새 화면도 새 키도 없다 — 넷 다 LAN 방에서 벌어지므로 `TUIScreen.room` 이고, 숫자
/// 키(`1`–`4`)의 뜻만 국면이 정한다(`RoomScreen.action(number:in:)` 한 곳).
@Suite("ArenaTerminalTests")
struct ArenaTerminalTests {

    // MARK: 결함 — 열거는 컴파일러만 만족시켰다

    /// 토너먼트 턴이 "준비 중" 으로 찍히던 자리. `phase` 가 `.tournament` 이고 `fighters` 가 비어
    /// 있으면 예전 코드는 `.waiting` → `standingLine` 의 `default` 로 떨어졌다.
    @Test func testATournamentTurnIsNotReportedAsPreparing() {
        let state = Self.duelling(activity: .tournament, phase: .tournament)

        #expect(RoomScreen.kind(state) == .duelMove)
        let lines = RoomScreen.lines(state, language: .ko, width: 60)
        #expect(!lines.contains { $0.contains("판을 준비하는 중") })
        #expect(lines.contains { $0.contains("타격") }, "내 기술이 줄에 없다: \(lines)")
    }

    /// **체육관은 `phase` 로 가릴 수 없다.** 판이 도는 동안 국면은 `.hosting` 그대로다
    /// (`MultiplayerRoomCenter.fillTimedOutActions`: "체육관은 `phase` 가 `.hosting` 인 채로 판이
    /// 돈다 — 국면이 아니라 판의 유무로 가른다"). 그래서 예전 화면은 판 중에 로비를 그렸고
    /// `s 시작` 을 권했다.
    @Test func testAGymMatchIsNotReportedAsALobby() {
        var state = Self.duelling(activity: .gym, phase: .hosting)
        state.isHost = true
        state.canStart = true

        #expect(RoomScreen.kind(state) == .duelMove)
        #expect(!RoomScreen.keys(state).contains { $0.contains("시작") },
                "판이 도는 중에 시작을 권했다: \(RoomScreen.keys(state))")
    }

    /// 퀴즈 문항이 화면에 없으면 터미널로는 풀 수 없다 — 그게 이 컨텐츠의 전부다.
    @Test func testAQuizQuestionReachesTheTerminal() {
        let state = Self.racing(activity: .pokemonQuiz)

        #expect(RoomScreen.kind(state) == .trackMove)
        let lines = RoomScreen.lines(state, language: .ko, width: 70)
        #expect(lines.contains { $0.contains("불꽃타입 기술은") }, "문항이 없다: \(lines)")
    }

    /// 시작 버튼은 **활동마다 다른 함수**다(`startRaid`·`startBattle`·`startPokeathlon`·
    /// `startPokemonQuiz`·`startTournament`). 체육관만 호스트가 시작하지 않는다 — 도전이 와야
    /// 판이 선다. 그 사실을 표 하나에 둔다.
    @Test func testOnlyTheGymIsNotStartedByItsHost() {
        for activity in RoomActivity.allCases {
            #expect(activity.isHostStarted == (activity != .gym), "\(activity.rawValue)")
        }
    }

    /// 체육관 로비에서 `s` 를 권하면 **눌러도 아무 일이 없다** — 시작할 함수가 없다.
    @Test func testAGymLobbyDoesNotOfferAStartKey() {
        var state = RoomTerminalState(phase: .hosting, activity: .gym, myID: UUID())
        state.isHost = true
        state.canStart = true

        #expect(RoomScreen.kind(state) == .lobby)
        #expect(!RoomScreen.keys(state).contains { $0.contains("시작") })
        #expect(RoomScreen.keys(state).contains { $0.contains("나가기") })
    }

    // MARK: 결투 — 기술과 교체는 한 번에 하나만 산다

    /// 번호는 **엔진의 기술 순번**이다. PP 가 떨어진 자리를 빼면서 번호를 다시 매기면 사용자가
    /// 고른 것과 다른 기술이 나간다 — 그래서 구멍을 남긴다(웨이브·방 대전과 같은 규칙).
    @Test func testSpentMovesLeaveHolesInTheNumbering() {
        var state = Self.duelling(activity: .gym, phase: .hosting)
        state.duel?.moves = [ArenaScreen.Move(number: 1, label: "타격", pp: 3, maxPP: 20),
                             ArenaScreen.Move(number: 3, label: "몸통박치기", pp: 1, maxPP: 15)]

        #expect(ArenaScreen.moveNumbers(state) == [1, 3])
        #expect(RoomScreen.action(number: 3, in: state) == .roomMove(move: 3, target: nil))
        #expect(RoomScreen.action(number: 2, in: state) == nil, "PP 가 없는 번호가 요청이 됐다")
    }

    /// 발버둥은 **번호가 하나**다. 목록에 남은 기술 번호를 그대로 권하면 낼 수 없는 것을 권한다.
    @Test func testStrugglingLeavesExactlyOneNumber() {
        var state = Self.duelling(activity: .tournament, phase: .tournament)
        state.duel?.moves = []
        state.duel?.mustStruggle = true

        #expect(ArenaScreen.moveNumbers(state) == [1])
        #expect(RoomScreen.action(number: 1, in: state) == .roomMove(move: 1, target: nil))
    }

    /// 앞자리가 쓰러지면 **기술이 아니라 자리**를 고른다. 두 번호 공간이 한 화면에 동시에
    /// 살면 숫자 한 자리로는 어느 것인지 정할 수 없어, 두 국면을 배타로 둔다.
    @Test func testAFaintedFrontRankAsksForASlotInsteadOfAMove() {
        var state = Self.duelling(activity: .gym, phase: .hosting)
        state.duel?.mine = [ArenaScreen.Slot(number: 1, id: UUID(), label: "이브이", hp: 0, maxHP: 90,
                                             isActive: true),
                            ArenaScreen.Slot(number: 2, id: UUID(), label: "피카츄", hp: 50, maxHP: 80,
                                             isActive: false)]

        #expect(RoomScreen.kind(state) == .duelReplace)
        #expect(ArenaScreen.replaceNumbers(state) == [2], "쓰러진 자기 자리를 후보로 냈다")
        #expect(RoomScreen.action(number: 2, in: state) == .roomSwitch(slot: 2))
        #expect(RoomScreen.action(number: 1, in: state) == nil, "쓰러진 자리로 교체했다")
        #expect(RoomScreen.keys(state).contains { $0.contains("교체") })
    }

    /// 이미 냈으면 누를 것이 없다 — 상대를 기다리는 국면이다.
    @Test func testASubmittedDuelTurnHasNothingToPress() {
        var state = Self.duelling(activity: .tournament, phase: .tournament)
        state.duel?.hasSubmitted = true

        #expect(RoomScreen.kind(state) == .waiting)
        #expect(ArenaScreen.moveNumbers(state).isEmpty)
        #expect(RoomScreen.action(number: 1, in: state) == nil)
    }

    /// 끝난 판은 결과다. 승패는 **앱이 판정한 값**을 싣는다 — 터미널이 HP 로 다시 세면
    /// 무승부·관전이 갈라진다(방 대전에서 같은 규칙을 이미 지킨다).
    @Test func testAFinishedDuelShowsWhoWon() {
        var state = Self.duelling(activity: .gym, phase: .hosting)
        state.duel?.winnerName = "관장 민"
        state.duel?.iWon = false

        #expect(RoomScreen.kind(state) == .finished)
        let lines = RoomScreen.lines(state, language: .ko, width: 60)
        #expect(lines.contains { $0.contains("졌다") }, "\(lines)")
        #expect(lines.contains { $0.contains("관장 민") }, "\(lines)")
        #expect(RoomScreen.keys(state).isEmpty)
    }

    /// 양쪽 팀이 줄에 다 나온다 — 상대의 남은 마릿수를 모르면 교체를 고를 수 없다.
    @Test func testBothTeamsAppearInTheLines() {
        let state = Self.duelling(activity: .tournament, phase: .tournament)
        let lines = RoomScreen.lines(state, language: .ko, width: 70)

        #expect(lines.contains { $0.contains("이브이") })
        #expect(lines.contains { $0.contains("고라파덕") })
    }

    // MARK: 트랙 — 방향은 한 축, 러너 번호는 명령에만

    /// 퀴즈에서 누를 것은 **둘**이다. 포켓슬론의 전진·교체를 같이 권하면 눌러도 아무 일이 없다.
    @Test func testAQuizOffersOnlyTheTwoAnswers() {
        let state = Self.racing(activity: .pokemonQuiz)

        #expect(ArenaScreen.trackInputs(state) == [.left, .right])
        #expect(RoomScreen.action(number: 1, in: state) == .roomTrack(.left))
        #expect(RoomScreen.action(number: 2, in: state) == .roomTrack(.right))
        #expect(RoomScreen.action(number: 3, in: state) == nil, "퀴즈에서 전진이 요청이 됐다")
        #expect(ArenaScreen.trackName(.left, quiz: true).contains("O"))
        #expect(ArenaScreen.trackName(.right, quiz: true).contains("X"))
    }

    /// 포켓슬론은 넷 다 뜻이 있다.
    @Test func testARaceOffersAllFourInputs() {
        let state = Self.racing(activity: .pokeathlon)

        #expect(ArenaScreen.trackInputs(state) == [.left, .right, .run, .swap])
        #expect(RoomScreen.action(number: 3, in: state) == .roomTrack(.run))
        #expect(RoomScreen.action(number: 4, in: state) == .roomTrack(.swap))
        #expect(RoomScreen.action(number: 5, in: state) == nil)
        #expect(ArenaScreen.trackName(.left, quiz: false).contains("왼"))
    }

    /// **번호 → 입력 변환은 한 곳**이다. 화면과 키 표가 각자 접으면 안내에 있는 번호가
    /// 다른 방향으로 간다.
    @Test func testTheDirectionFoldHasOneHome() {
        #expect(ArenaScreen.trackInput(number: 1) == .left)
        #expect(ArenaScreen.trackInput(number: 4) == .swap)
        #expect(ArenaScreen.trackInput(number: 0) == nil)
        #expect(ArenaScreen.trackInput(number: 5) == nil)
        #expect(ArenaScreen.trackOrder.count == ArenaTrackInput.allCases.count,
                "표에서 빠진 방향이 있으면 그 방향은 영영 눌리지 않는다")
    }

    /// 관전자는 **달리지 않는다** — 방향을 권하면 눌러도 아무 일이 없고, 대신 베팅이 있다.
    @Test func testASpectatorGetsBettingInsteadOfDirections() {
        var state = Self.racing(activity: .pokeathlon)
        state.track?.amRacing = false
        state.track?.canBet = true

        #expect(RoomScreen.kind(state) == .waiting)
        #expect(ArenaScreen.trackInputs(state).isEmpty)
        #expect(RoomScreen.action(number: 1, in: state) == nil)
        #expect(RoomScreen.hints(state).contains("bet"), "\(RoomScreen.hints(state))")
    }

    /// 러너 번호는 순위 줄에 찍히고 **베팅 명령만** 그 번호를 받는다 — 방향 키와 같은 숫자
    /// 공간에 두면 3 이 "전진" 이자 "3번 러너" 가 된다.
    @Test func testStandingsCarryTheRunnerNumbersUsedByBet() throws {
        var state = Self.racing(activity: .pokeathlon)
        state.track?.amRacing = false
        state.track?.canBet = true
        let second = try #require(state.track?.standings.last)

        #expect(state.track?.standings.map(\.number) == [1, 2])
        #expect(ArenaScreen.runnerID(number: 2, in: state) == second.id)
        #expect(ArenaScreen.runnerID(number: 3, in: state) == nil)
        let lines = RoomScreen.lines(state, language: .ko, width: 70)
        #expect(lines.contains { $0.contains("2 ") && $0.contains("이웃") }, "\(lines)")
    }

    /// 판돈과 내 베팅이 보인다 — 안 보이면 이미 걸었는지 알 방법이 없어 두 번 건다.
    @Test func testThePotAndMyOwnBetAreVisible() {
        var state = Self.racing(activity: .pokeathlon)
        state.track?.amRacing = false
        state.track?.pot = 1_200
        state.track?.myBet = ArenaScreen.Bet(runnerName: "이웃", amount: 400)

        let lines = RoomScreen.lines(state, language: .ko, width: 70)
        #expect(lines.contains { $0.contains(TUIRender.number(1_200)) }, "\(lines)")
        #expect(lines.contains { $0.contains(TUIRender.number(400)) }, "\(lines)")
    }

    /// 내 자리에 표시가 있다 — 여덟 명이 달리는 트랙에서 내 줄을 못 찾으면 아무 소용이 없다.
    @Test func testMyOwnLaneIsMarked() throws {
        let state = Self.racing(activity: .pokeathlon)
        let lines = RoomScreen.lines(state, language: .ko, width: 70)
        let mine = try #require(lines.first { $0.contains("나") })

        #expect(mine.contains(TUIRender.activeMark), "\(lines)")
    }

    // MARK: 명령 어휘

    @Test func testEveryNewRoomSubcommandParsesIntoItsRequest() throws {
        #expect(try PokedoroCommandParser.parse(["room", "switch", "2"]) == .roomSwitch(slot: 2))
        #expect(try PokedoroCommandParser.parse(["room", "left"]) == .roomTrack(.left))
        #expect(try PokedoroCommandParser.parse(["room", "right"]) == .roomTrack(.right))
        #expect(try PokedoroCommandParser.parse(["room", "run"]) == .roomTrack(.run))
        #expect(try PokedoroCommandParser.parse(["room", "swap"]) == .roomTrack(.swap))
        #expect(try PokedoroCommandParser.parse(["room", "bet", "2", "400"])
                == .roomBet(runner: 2, stardust: 400, confirmed: false))
        #expect(try PokedoroCommandParser.parse(["gym"]) == .gym)
    }

    /// 베팅은 **되돌릴 수 없다** — 별의조각이 원장으로 넘어가고 경기가 끝나야 정산된다.
    @Test func testBettingNeedsConfirmation() throws {
        #expect(try PokedoroCommandParser.parse(["room", "bet", "2", "400"]).request == nil)
        #expect(try PokedoroCommandParser.parse(["room", "bet", "2", "400", "--yes"]).request
                == .roomBet(runner: 2, stardust: 400))
    }

    /// **거절은 다시 볼 목록을 말한다.** 경매의 오류를 재사용했을 때 `room bet` 이 "경매 번호가
    /// 아니다 — `pokedoro auction` 을 본다" 로 답했고, `room switch` 는 `party` 번호를 가리켰다.
    /// 둘 다 사용자를 엉뚱한 화면으로 보낸다(순수 테스트는 통과했고 바이너리가 잡았다).
    @Test func testBadBettingNumbersAreRefusedByName() {
        #expect(throws: PokedoroCommandError.invalidBetAmount("0")) {
            try PokedoroCommandParser.parse(["room", "bet", "2", "0", "--yes"])
        }
        #expect(throws: PokedoroCommandError.invalidRunnerNumber("0")) {
            try PokedoroCommandParser.parse(["room", "bet", "0", "400", "--yes"])
        }
        #expect(throws: PokedoroCommandError.missingArgument("room bet")) {
            try PokedoroCommandParser.parse(["room", "bet", "2"])
        }
        #expect(throws: PokedoroCommandError.invalidSlotNumber("0")) {
            try PokedoroCommandParser.parse(["room", "switch", "0"])
        }
    }

    /// 경매 쪽 문구는 **그대로다** — 두 목록이 한 오류를 쓰면 한쪽을 고칠 때 다른 쪽이 틀린다.
    @Test func testTheAuctionKeepsItsOwnWording() {
        #expect(throws: PokedoroCommandError.invalidStardust("0")) {
            try PokedoroCommandParser.parse(["auction", "bid", "1", "0", "--yes"])
        }
        #expect(throws: PokedoroCommandError.invalidAuctionNumber("0")) {
            try PokedoroCommandParser.parse(["auction", "bid", "0", "400", "--yes"])
        }
    }

    @Test func testNewRoomActionNamesAreNamespaced() {
        #expect(PokedoroRequest.Action.roomSwitch(slot: 1).name == "room.switch")
        #expect(PokedoroRequest.Action.roomTrack(.run).name == "room.track")
        #expect(PokedoroRequest.Action.roomBet(runner: 1, stardust: 5).name == "room.bet")
    }

    @Test func testEveryNewRoomActionSurvivesTheRoundTripThroughTheFile() throws {
        var actions: [PokedoroRequest.Action] = [.roomSwitch(slot: 3),
                                                 .roomBet(runner: 2, stardust: 400)]
        actions += ArenaTrackInput.allCases.map { PokedoroRequest.Action.roomTrack($0) }
        for action in actions {
            let sent = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
            let back = try JSONDecoder().decode(PokedoroRequest.self,
                                                from: try JSONEncoder().encode(sent))
            #expect(back.action == action, "\(action.name) 이 왕복에서 달라졌다")
        }
    }

    /// 손으로 고친 파일이 없는 방향·0 번호를 밀어 넣지 못한다.
    @Test func testAHandEditedFileCannotSmuggleAnImpossibleArenaValue() {
        #expect(PokedoroRequest.Action(name: "room.track", argument: "sideways") == nil)
        #expect(PokedoroRequest.Action(name: "room.track", argument: nil) == nil)
        #expect(PokedoroRequest.Action(name: "room.switch", argument: "0") == nil)
        #expect(PokedoroRequest.Action(name: "room.bet", argument: "2") == nil)
        #expect(PokedoroRequest.Action(name: "room.bet", argument: "0 400") == nil)
        #expect(PokedoroRequest.Action(name: "room.bet", argument: "2 0") == nil)
    }

    /// 이 넷은 이제 앱 전용이 아니다 — 남은 것은 방을 만들고 찾는 일뿐이다.
    @Test func testOnlyOpeningARoomStaysInTheApp() {
        #expect(PokedoroCommandParser.appOnlyCommands == ["raid"])
    }

    // MARK: 픽스처

    static func duelling(activity: RoomActivity,
                         phase: MultiplayerRoomCenter.Phase) -> RoomTerminalState {
        var state = RoomTerminalState(phase: phase, activity: activity, myID: UUID())
        var duel = DuelTerminalState(
            myName: "나", theirName: "관장 민",
            mine: [ArenaScreen.Slot(number: 1, id: UUID(), label: "이브이", hp: 70, maxHP: 90,
                                    isActive: true),
                   ArenaScreen.Slot(number: 2, id: UUID(), label: "피카츄", hp: 80, maxHP: 80,
                                    isActive: false)],
            theirs: [ArenaScreen.Slot(number: 1, id: UUID(), label: "고라파덕", hp: 60, maxHP: 100,
                                      isActive: true)])
        duel.turn = 3
        duel.moves = [ArenaScreen.Move(number: 1, label: "타격", pp: 12, maxPP: 20),
                      ArenaScreen.Move(number: 2, label: "울음", pp: 40, maxPP: 40)]
        state.duel = duel
        return state
    }

    static func racing(activity: RoomActivity) -> RoomTerminalState {
        let mine = UUID()
        var state = RoomTerminalState(phase: activity == .pokemonQuiz ? .pokemonQuiz : .pokeathlon,
                                      activity: activity, myID: mine)
        var track = TrackTerminalState(standings: [
            ArenaScreen.Runner(number: 1, id: mine, label: "나", right: "120m", isMine: true),
            ArenaScreen.Runner(number: 2, id: UUID(), label: "이웃", right: "96m", isMine: false)
        ])
        track.amRacing = true
        track.secondsLeft = 4
        if activity == .pokemonQuiz {
            track.question = "불꽃타입 기술은 이상해씨에게 효과가 굉장하다."
        }
        state.track = track
        return state
    }
}
