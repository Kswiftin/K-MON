import Foundation
import Testing
@testable import PokeTokenBar

/// 체육관·토너먼트·포켓슬론·퀴즈 요청이 **어느 창구 함수로 가는지**를 고정한다 (Phase 5-7).
///
/// 이 스위트의 존재 이유가 결함 둘이다.
/// 1. `room start` 는 활동을 안 보고 `startRaid()` 를 불렀다 — 레이드가 아니면 센터가 조용히
///    돌아 나오는데 실행기는 "판을 시작했다" 고 답했다. **없던 성공을 보고했다.**
/// 2. `room move` 는 `submitAction(targetID:moveIndex:)` 만 불렀다 — 그 함수는
///    `phase == .battling` 을 먼저 보므로 체육관·토너먼트에서는 아무 일도 하지 않는다.
///
/// 그래서 창구가 **활동별 함수를 하나로 접는다**(`startActivity`·`submitDuelMove`) — 라우팅을
/// 실행기에 두면 활동을 더할 때마다 두 곳을 고쳐야 하고, 한쪽만 고치는 부류가 그대로 생긴다.
@Suite("ArenaExecutorTests")
struct ArenaExecutorTests {

    private final class FakeRoomControl: TerminalRoomControl {
        var terminalState: RoomTerminalState
        var submitted: [(target: UUID, move: Int)] = []
        var duelMoves: [Int] = []
        var duelSwitches: [Int] = []
        var trackInputs: [ArenaTrackInput] = []
        var bets: [(runner: UUID, amount: Int)] = []
        var started = 0
        var left = 0

        init(_ state: RoomTerminalState) { terminalState = state }
        func submitAction(targetID: UUID, moveIndex: Int) { submitted.append((targetID, moveIndex)) }
        func submitDuelMove(index: Int) { duelMoves.append(index) }
        func submitDuelSwitch(slot: Int) { duelSwitches.append(slot) }
        func submitTrackInput(_ input: ArenaTrackInput) { trackInputs.append(input) }
        func placeArenaBet(runnerID: UUID, stardust: Int) { bets.append((runnerID, stardust)) }
        func startActivity() { started += 1 }
        func leaveRoom() { left += 1 }
    }

    private func makeDirectory() -> URL { storeFixtureDirectory("arena-exec") }

    private func makeStore(in directory: URL, starPieces: Int = 0) -> CompanionStore {
        let store = CompanionStore(clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                   fileURL: directory.appendingPathComponent("state.json"))
        store.setLanguage(.ko)
        if starPieces > 0 { store.creditStarPieces(starPieces) }
        return store
    }

    private func execute(_ action: PokedoroRequest.Action, on store: CompanionStore,
                         room: FakeRoomControl?) async -> PokedoroReply {
        let request = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
        return await PokedoroRequestExecutor(timer: FocusTimer(), companion: store,
                                             room: room).execute(request)
    }

    // MARK: 시작 — 활동마다 다른 함수다

    /// 결함 1의 회귀. 토너먼트 로비에서 시작을 눌러도 예전에는 `startRaid()` 가 조용히 돌아
    /// 나왔는데 답은 성공이었다.
    @Test func testStartingATournamentGoesThroughTheActivityRouter() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = RoomTerminalState(phase: .hosting, activity: .tournament, myID: UUID())
        state.isHost = true
        state.canStart = true
        let control = FakeRoomControl(state)

        let reply = await execute(.roomStart, on: makeStore(in: directory), room: control)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(control.started == 1)
    }

    /// 체육관은 호스트가 시작하지 않는다 — **성공이라고 답하면 안 된다.** 사용자는 몇 번이고
    /// 다시 누르며 왜 안 서는지 모른다.
    @Test func testAGymRoomRefusesToBeStartedAndSaysWhy() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = RoomTerminalState(phase: .hosting, activity: .gym, myID: UUID())
        state.isHost = true
        state.canStart = true
        let control = FakeRoomControl(state)

        let reply = await execute(.roomStart, on: makeStore(in: directory), room: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("도전"), "\(reply.message)")
        #expect(control.started == 0)
    }

    // MARK: 결투 — 같은 명령이 다른 창구로 간다

    /// 결함 2의 회귀. `room move` 는 체육관에서 `submitDuelMove` 로 가야 한다 —
    /// `submitAction` 은 `phase == .battling` 을 먼저 보므로 아무 일도 하지 않는다.
    @Test func testAGymMoveGoesToTheDuelSeamNotTheFighterSeam() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeRoomControl(ArenaTerminalTests.duelling(activity: .gym, phase: .hosting))

        let reply = await execute(.roomMove(move: 2, target: nil),
                                  on: makeStore(in: directory), room: control)

        #expect(reply.succeeded, "\(reply.message)")
        // 창구는 **엔진 순번**(0부터)으로 받는다 — 화면 번호를 그대로 넘기면 옆 기술이 나간다.
        #expect(control.duelMoves == [1])
        #expect(control.submitted.isEmpty, "전투원 창구로 갔다 — 그쪽은 방 대전 전용이다")
    }

    /// 방 대전·레이드는 **그대로다.** 결투 창구를 더하면서 이 경로가 흔들리지 않았는지 본다.
    @Test func testARaidMoveStillGoesToTheFighterSeam() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeRoomControl(RoomTerminalTests.fighting())

        let reply = await execute(.roomMove(move: 1, target: nil),
                                  on: makeStore(in: directory), room: control)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(control.submitted.count == 1)
        #expect(control.duelMoves.isEmpty)
    }

    @Test func testADuelRefusesAMoveWithNoPPLeft() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = ArenaTerminalTests.duelling(activity: .tournament, phase: .tournament)
        state.duel?.moves = [ArenaScreen.Move(number: 1, label: "타격", pp: 4, maxPP: 20)]
        let control = FakeRoomControl(state)

        let reply = await execute(.roomMove(move: 2, target: nil),
                                  on: makeStore(in: directory), room: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("PP"), "\(reply.message)")
        #expect(control.duelMoves.isEmpty)
    }

    /// 교체는 **쓰러진 자리를 메울 때도, 살아 있는 채 바꿀 때도** 된다(`GymMatchEngine.submit` 이
    /// 그 둘을 스스로 가른다). 그래서 안내에 없어도 실행은 막지 않는다 — 제안 ⊆ 실행 가능.
    @Test func testSwitchingWorksOnANormalTurnToo() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeRoomControl(ArenaTerminalTests.duelling(activity: .gym, phase: .hosting))

        let reply = await execute(.roomSwitch(slot: 2), on: makeStore(in: directory), room: control)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(control.duelSwitches == [1], "자리 번호를 엔진 순번으로 접지 않았다")
    }

    /// 쓰러진 자리로는 못 바꾼다. 지금 나온 자리로도 못 바꾼다 — 둘 다 아무 일이 없는 입력이다.
    @Test func testSwitchingRefusesFaintedAndActiveSlots() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = ArenaTerminalTests.duelling(activity: .gym, phase: .hosting)
        state.duel?.mine = [ArenaScreen.Slot(number: 1, id: UUID(), label: "이브이", hp: 70,
                                             maxHP: 90, isActive: true),
                            ArenaScreen.Slot(number: 2, id: UUID(), label: "피카츄", hp: 0,
                                             maxHP: 80, isActive: false)]
        let store = makeStore(in: directory)
        let control = FakeRoomControl(state)

        let fainted = await execute(.roomSwitch(slot: 2), on: store, room: control)
        let active = await execute(.roomSwitch(slot: 1), on: store, room: control)

        #expect(!fainted.succeeded)
        #expect(fainted.message.contains("쓰러져"), "\(fainted.message)")
        #expect(!active.succeeded)
        #expect(active.message.contains("이미"), "\(active.message)")
        #expect(control.duelSwitches.isEmpty)
    }

    /// 결투가 없는 방에서 결투 명령을 치면 **무엇이 도는 중인지** 말한다.
    @Test func testDuelCommandsInARaidSayWhatIsRunning() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeRoomControl(RoomTerminalTests.fighting())

        let reply = await execute(.roomSwitch(slot: 2), on: makeStore(in: directory), room: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("협동 레이드"), "\(reply.message)")
    }

    // MARK: 트랙 — 없는 방향은 이름을 대며 거절한다

    @Test func testAQuizAnswerReachesTheTrackSeam() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeRoomControl(ArenaTerminalTests.racing(activity: .pokemonQuiz))

        let reply = await execute(.roomTrack(.right), on: makeStore(in: directory), room: control)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(control.trackInputs == [.right])
    }

    /// 퀴즈에는 전진이 없다. 조용히 흘리면 사용자는 입력이 씹혔다고 읽는다.
    @Test func testAQuizRefusesRunningAndNamesTheTwoAnswers() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeRoomControl(ArenaTerminalTests.racing(activity: .pokemonQuiz))

        let reply = await execute(.roomTrack(.run), on: makeStore(in: directory), room: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("O"), "\(reply.message)")
        #expect(control.trackInputs.isEmpty)
    }

    /// 관전자는 달리지 않는다 — 대신 무엇을 할 수 있는지 말한다.
    @Test func testASpectatorIsToldToBetInsteadOfRun() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = ArenaTerminalTests.racing(activity: .pokeathlon)
        state.track?.amRacing = false
        state.track?.canBet = true
        let control = FakeRoomControl(state)

        let reply = await execute(.roomTrack(.run), on: makeStore(in: directory), room: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("bet"), "\(reply.message)")
        #expect(control.trackInputs.isEmpty)
    }

    // MARK: 베팅 — 번호를 접는 자리가 하나다

    @Test func testABetFoldsTheRunnerNumberIntoAnID() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = ArenaTerminalTests.racing(activity: .pokeathlon)
        state.track?.amRacing = false
        state.track?.canBet = true
        let neighbour = try #require(state.track?.standings.last)
        let control = FakeRoomControl(state)

        let reply = await execute(.roomBet(runner: 2, stardust: 400),
                                  on: makeStore(in: directory, starPieces: 1_000), room: control)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(control.bets.count == 1)
        #expect(control.bets.first?.runner == neighbour.id)
        #expect(control.bets.first?.amount == 400)
    }

    /// 없는 번호는 **몇 명이 달리는지** 말한다 — 목록을 다시 띄우지 않고 고칠 수 있다.
    @Test func testABetOnAnAbsentRunnerSaysHowManyAreRacing() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = ArenaTerminalTests.racing(activity: .pokeathlon)
        state.track?.amRacing = false
        state.track?.canBet = true
        let control = FakeRoomControl(state)

        let reply = await execute(.roomBet(runner: 9, stardust: 400),
                                  on: makeStore(in: directory, starPieces: 1_000), room: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("2"), "\(reply.message)")
        #expect(control.bets.isEmpty)
    }

    /// 잔액을 **먼저** 본다. 센터도 보지만(`placeBet`), 거절 사유가 화면까지 오는 길이 비동기라
    /// 터미널은 답을 못 싣는다 — 알 수 있는 것은 여기서 답한다.
    @Test func testABetBeyondMyWalletIsRefusedWithTheBalance() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = ArenaTerminalTests.racing(activity: .pokeathlon)
        state.track?.amRacing = false
        state.track?.canBet = true
        let control = FakeRoomControl(state)

        let reply = await execute(.roomBet(runner: 2, stardust: 400),
                                  on: makeStore(in: directory, starPieces: 120), room: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains(TUIRender.number(120)), "\(reply.message)")
        #expect(control.bets.isEmpty)
    }

    /// 러너는 자기 경기에 걸 수 없다 — 승부를 조작해 이득 보는 경로다
    /// (`PokeathlonPool.rejection` 의 `.notSpectator`). 사유를 그대로 옮긴다.
    @Test func testARacerCannotBetOnItsOwnRace() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeRoomControl(ArenaTerminalTests.racing(activity: .pokeathlon))

        let reply = await execute(.roomBet(runner: 2, stardust: 400),
                                  on: makeStore(in: directory, starPieces: 1_000), room: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("관전"), "\(reply.message)")
        #expect(control.bets.isEmpty)
    }

    /// 출발한 뒤에는 원장이 닫힌다(`PokeathlonPool.isClosed`).
    @Test func testAClosedPoolRefusesNewBets() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = ArenaTerminalTests.racing(activity: .pokeathlon)
        state.track?.amRacing = false
        state.track?.canBet = false
        let control = FakeRoomControl(state)

        let reply = await execute(.roomBet(runner: 2, stardust: 400),
                                  on: makeStore(in: directory, starPieces: 1_000), room: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("닫혔다"), "\(reply.message)")
        #expect(control.bets.isEmpty)
    }

    /// 퀴즈에는 원장이 없다 — 베팅을 거절할 때 그 사실을 말한다.
    @Test func testBettingInAQuizIsRefusedByName() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeRoomControl(ArenaTerminalTests.racing(activity: .pokemonQuiz))

        let reply = await execute(.roomBet(runner: 1, stardust: 400),
                                  on: makeStore(in: directory, starPieces: 1_000), room: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("포켓슬론"), "\(reply.message)")
        #expect(control.bets.isEmpty)
    }

    /// 방에 없으면 전부 같은 사유다 — 그 사유는 이미 한 곳에 있다.
    @Test func testArenaCommandsWithoutARoomSayWhereRoomsAreOpened() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        let actions: [PokedoroRequest.Action] = [.roomSwitch(slot: 1), .roomTrack(.left),
                                                 .roomBet(runner: 1, stardust: 10)]

        for action in actions {
            let reply = await execute(action, on: store, room: nil)
            #expect(!reply.succeeded, "\(action.name)")
            #expect(reply.message.contains("앱"), "\(action.name): \(reply.message)")
        }
    }
}
