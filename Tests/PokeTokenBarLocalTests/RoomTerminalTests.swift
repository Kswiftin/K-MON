import Foundation
import Testing
@testable import PokeTokenBar

/// LAN 방(협동 레이드와 방 대전)을 터미널에서 보고 턴을 내는 자리.
///
/// PvP 대전(5-2)과 **같은 통로**를 쓴다 — 방 상태도 세이브에 없고 `MultiplayerRoomCenter` 에만
/// 살기 때문이다. 그래서 새 채널을 만들지 않고 생산자만 하나 더 붙인다.
///
/// **대상을 UUID 로 지목하지 않는다.** 방 참가자는 UUID 로 식별되지만 그 값은 사람이 칠 수 없다 —
/// 화면이 찍는 번호를 받아 실행기가 UUID 로 접는다(경매를 목록 인덱스로 지목하기로 한 것과 같은 규칙).
@Suite("RoomTerminalTests")
struct RoomTerminalTests {

    // MARK: 명령 어휘

    @Test func testEveryRoomSubcommandParsesIntoItsRequest() throws {
        #expect(try PokedoroCommandParser.parse(["room"]) == .room)
        #expect(try PokedoroCommandParser.parse(["room", "move", "2"]) == .roomMove(move: 2, target: nil))
        #expect(try PokedoroCommandParser.parse(["room", "move", "2", "3"]) == .roomMove(move: 2, target: 3))
        #expect(try PokedoroCommandParser.parse(["room", "start"]) == .roomStart)
        #expect(try PokedoroCommandParser.parse(["room", "leave"]) == .roomLeave(confirmed: false))
    }

    /// 방을 떠나는 것은 **되돌릴 수 없다** — 그 판의 정산을 못 받고(게스트는 판돈만 환불),
    /// 다시 들어가려면 호스트가 방을 유지하고 있어야 한다.
    @Test func testLeavingNeedsConfirmation() throws {
        #expect(try PokedoroCommandParser.parse(["room", "leave"]).request == nil)
        #expect(try PokedoroCommandParser.parse(["room", "leave", "--yes"]).request == .roomLeave)
    }

    /// `raid` 는 여전히 앱 전용이다 — **방을 만들고 찾는 일은 소켓**이라 터미널이 할 수 없다.
    /// `room` 은 이미 들어간 방을 보고 턴을 내는 명령이다.
    @Test func testOpeningARoomStaysInTheApp() {
        #expect(PokedoroCommandParser.appOnlyCommands.contains("raid"))
    }

    @Test func testRoomActionNamesAreNamespaced() {
        #expect(PokedoroRequest.Action.roomMove(move: 1, target: nil).name == "room.move")
        #expect(PokedoroRequest.Action.roomStart.name == "room.start")
        #expect(PokedoroRequest.Action.roomLeave.name == "room.leave")
    }

    @Test func testEveryRoomActionSurvivesTheRoundTripThroughTheFile() throws {
        let actions: [PokedoroRequest.Action] = [
            .roomMove(move: 2, target: nil), .roomMove(move: 2, target: 4),
            .roomStart, .roomLeave
        ]
        for action in actions {
            let sent = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
            let back = try JSONDecoder().decode(PokedoroRequest.self,
                                                from: try JSONEncoder().encode(sent))
            #expect(back.action == action, "\(action.name) 이 왕복에서 달라졌다")
        }
    }

    @Test func testAHandEditedFileCannotSmuggleAnImpossibleRoomNumber() {
        #expect(PokedoroRequest.Action(name: "room.move", argument: "0") == nil)
        #expect(PokedoroRequest.Action(name: "room.move", argument: "1 0") == nil)
        #expect(PokedoroRequest.Action(name: "room.start", argument: "1") == nil)
        #expect(PokedoroRequest.Action(name: "room.leave", argument: "1") == nil)
    }

    // MARK: 화면 투영

    @Test func testNoRoomSaysWhereToOpenOne() {
        let idle = RoomTerminalState(phase: .idle, myID: UUID())
        #expect(RoomScreen.kind(idle) == .none)
        #expect(RoomScreen.numbers(idle).isEmpty)
        #expect(RoomScreen.lines(idle, language: .ko, width: 60).contains { $0.contains("앱") })
    }

    /// 로비에서는 **호스트만** 시작할 수 있고, 그 사실이 화면에 보인다 — 게스트에게 시작 키를
    /// 권하면 눌러도 아무 일이 없다.
    @Test func testOnlyTheHostIsOfferedTheStartKey() {
        var host = RoomTerminalState(phase: .hosting, activity: .raid, myID: UUID())
        host.isHost = true
        host.canStart = true
        #expect(RoomScreen.kind(host) == .lobby)
        #expect(RoomScreen.keys(host).contains { $0.contains("시작") })

        var guest = host
        guest.isHost = false
        guest.phase = .joined
        #expect(!RoomScreen.keys(guest).contains { $0.contains("시작") })
        #expect(RoomScreen.hints(guest).contains("호스트"))
    }

    /// 사람이 덜 모였으면 시작 키도 없다 — `canStart` 가 거짓인데 권하면 그건 함정이다.
    @Test func testTheStartKeyWaitsForEnoughRunners() {
        var host = RoomTerminalState(phase: .hosting, activity: .raid, myID: UUID())
        host.isHost = true
        host.canStart = false
        #expect(!RoomScreen.keys(host).contains { $0.contains("시작") })
    }

    /// 내 차례면 숫자 키가 기술이다. 대상은 **번호로** 찍는다 — UUID 는 사람이 칠 수 없다.
    @Test func testOnMyTurnTheNumbersAreMovesAndTargetsAreNumbered() throws {
        let state = Self.fighting()
        #expect(RoomScreen.kind(state) == .move)
        #expect(RoomScreen.numbers(state) == [1, 2])
        #expect(RoomScreen.action(number: 1, in: state) == .roomMove(move: 1, target: nil))

        let targets = RoomScreen.targets(state)
        #expect(targets.count == 1, "나를 뺀 살아 있는 전투원이 대상이다")
        #expect(targets.first?.number == 1, "번호는 1부터다")
        #expect(targets.contains { $0.label.contains("보스") })
        // 대상 번호 → UUID 는 **여기 한 곳**에서만 접힌다.
        #expect(RoomScreen.targetID(number: 1, in: state) == targets.first?.id)
        #expect(RoomScreen.targetID(number: 9, in: state) == nil)
    }

    /// 이미 낸 라운드에는 누를 것이 없다.
    @Test func testAfterSubmittingThereIsNothingToPress() {
        var state = Self.fighting()
        state.hasSubmitted = true
        #expect(RoomScreen.kind(state) == .waiting)
        #expect(RoomScreen.numbers(state).isEmpty)
    }

    /// 쓰러진 전투원은 **행동하지 못한다**(`submitAction` 이 거절한다) — 관전과 같은 상태다.
    @Test func testAFaintedFighterIsNotOfferedMoves() {
        var state = Self.fighting()
        state.fighters[0].side.hp = 0
        #expect(RoomScreen.numbers(state).isEmpty)
    }

    /// 끝난 판은 결과와 **정산액**을 말한다 — 레이드는 기여도에 따라 갈리므로 숫자가 없으면
    /// 무엇을 얻었는지 알 수 없다.
    @Test func testAFinishedRoomShowsTheOutcomeAndPayout() {
        var state = Self.fighting()
        state.outcome = .win
        state.payout = 1_200
        #expect(RoomScreen.kind(state) == .finished)
        let lines = RoomScreen.lines(state, language: .ko, width: 60)
        #expect(lines.contains { $0.contains("이겼") })
        #expect(lines.contains { $0.contains("1,200") }, "정산액이 안 보이면 기여도가 의미를 잃는다")
    }

    /// 레이드는 티어를 머리글에 싣는다 — 1★ 와 5★ 는 같은 화면이지만 전혀 다른 판이다.
    @Test func testARaidNamesItsTier() {
        var state = Self.fighting()
        state.activity = .raid
        state.raidTier = .five
        #expect(RoomScreen.title(state).contains("5"))
    }

    @Test func testEveryLineFitsTheRequestedWidth() {
        for state in [Self.fighting(), RoomTerminalState(phase: .idle, myID: UUID())] {
            for width in [20, 40, 80] {
                for line in RoomScreen.lines(state, language: .ko, width: width) {
                    #expect(TUIText.displayWidth(line) <= width, "폭 \(width) 에서 넘친 줄: \(line)")
                }
            }
        }
    }

    /// 방 화면도 채널로 온다 — 진행 중이 아니면 스냅샷을 내놓지 않는다(빈 줄이 타이머를 덮는다).
    @Test func testTheChannelOnlyPublishesALiveRoom() throws {
        let now = Date()
        #expect(PokedoroViewChannel.roomSnapshot(RoomTerminalState(phase: .idle, myID: UUID()),
                                                  language: .ko, width: 60, now: now) == nil)
        let live = try #require(PokedoroViewChannel.roomSnapshot(Self.fighting(), language: .ko,
                                                                  width: 60, now: now))
        #expect(live.screen == "room")
        #expect(live.keys.contains { $0.contains("기술") })
    }

    /// 국면마다 **키와 한 줄 안내가 함께** 바뀐다. 하나만 바뀌면 화면 아래와 채널이 서로 다른
    /// 키를 권한다.
    @Test func testEveryPhaseAdvertisesOnlyWhatItCanDo() {
        let mine = Self.fighting()
        #expect(RoomScreen.hints(mine).contains("room move"))
        #expect(RoomScreen.keys(mine).contains { $0.contains("기술") })

        var submitted = mine
        submitted.hasSubmitted = true
        #expect(RoomScreen.keys(submitted) == ["l 나가기"], "낸 뒤에는 나가기만 남는다")
        #expect(RoomScreen.hints(submitted).contains("기다린다"))

        var done = mine
        done.outcome = .loss
        #expect(RoomScreen.keys(done).isEmpty)
        #expect(RoomScreen.hints(done).contains("끝났다"))

        let idle = RoomTerminalState(phase: .idle, myID: UUID())
        #expect(RoomScreen.keys(idle).isEmpty)
        #expect(RoomScreen.hints(idle).contains("앱"))
    }

    /// 대상이 둘 이상일 때만 **대상 목록을 찍는다** — 보스 하나짜리 레이드에서는 고를 것이 없고,
    /// 방 대전에서는 그 목록이 없으면 번호를 어디서 얻는지 알 수 없다.
    @Test func testTheTargetListAppearsOnlyWhenThereIsAChoice() {
        let raid = Self.fighting()
        #expect(!RoomScreen.lines(raid, language: .ko, width: 80).contains { $0.hasPrefix("대상") })

        var brawl = raid
        brawl.activity = .battle
        brawl.fighters.append(Self.fighter(id: UUID(), name: "옆자리"))
        let lines = RoomScreen.lines(brawl, language: .ko, width: 80)
        #expect(lines.contains { $0.hasPrefix("대상") })
        #expect(RoomScreen.targets(brawl).count == 2)
    }

    /// PP 가 다 떨어지면 발버둥 하나다 — 목록을 비우면 낼 것이 없는 것처럼 보인다.
    @Test func testWithNoPPLeftTheOnlyChoiceIsStruggle() throws {
        var state = Self.fighting()
        for index in state.fighters[0].side.pp.indices { state.fighters[0].side.pp[index] = 0 }
        #expect(RoomScreen.numbers(state) == [1])
        let only = try #require(RoomScreen.choices(state, language: .ko).first)
        #expect(only.label == MoveSpec.struggle().name(.ko))
    }

    // MARK: 키 배정

    @Test func testTheRoomScreenHasItsOwnKey() throws {
        let screen = try #require(TUIScreen.screen(for: "o"))
        #expect(screen == .room)
        #expect(!screen.isList)
        // 판 화면이 셋이 됐어도 각자 자기 표를 쓴다 — 홈의 숫자 키가 새지 않는다.
        #expect(TUIKeymap.action(for: .char("1"), screen: .room, canWrite: true)
                == .roomChoice(1))
        #expect(TUIKeymap.action(for: .char("s"), screen: .room, canWrite: true) == .startRoom)
        #expect(TUIKeymap.action(for: .char("l"), screen: .room, canWrite: true) == .leaveRoom)
    }

    // MARK: 픽스처

    /// 내 차례인 협동 레이드. 전투원은 나 + 보스 둘이다.
    static func fighting() -> RoomTerminalState {
        let mine = UUID()
        var state = RoomTerminalState(phase: .battling, activity: .raid, myID: mine)
        state.round = 2
        state.fighters = [Self.fighter(id: mine, name: "나"),
                          Self.fighter(id: UUID(), name: "보스")]
        return state
    }

    static func fighter(id: UUID, name: String) -> MultiplayerFighter {
        MultiplayerFighter(
            participant: LobbyParticipant(id: id, trainerName: name, speciesID: 1, team: .solo,
                                          isReady: true, isHost: false),
            snapshot: BattleSnapshot(
                speciesID: 1, name: name, trainer: name, level: 50, nature: nil, isShiny: false,
                types: [.normal],
                base: BattleStats(hp: 100, atk: 100, def: 50, spa: 100, spd: 50, spe: 100),
                moves: [MoveSpec(id: 1, names: ["ko": "타격"], type: .normal, power: 40,
                                 damageClass: .physical, accuracy: nil, pp: 20),
                        MoveSpec(id: 2, names: ["ko": "울음"], type: .normal, power: 0,
                                 damageClass: .status, accuracy: nil, pp: 40)]))
    }
}
