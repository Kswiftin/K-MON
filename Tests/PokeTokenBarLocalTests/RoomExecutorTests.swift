import Foundation
import Testing
@testable import PokeTokenBar

/// 터미널이 부탁한 LAN 방 동작을 **앱이** 실행하는 자리.
///
/// 가짜 창구를 끼우는 이유는 대전과 같다 — `MultiplayerRoomCenter` 를 그대로 쓰면 listener·
/// browser 가 살아나 실제 LAN 으로 나간다.
///
/// 이 파일의 핵심은 **대상 번호 → 참가자 id** 다. 센터는 UUID 로 받고 사용자는 번호를 치므로,
/// 그 변환이 어긋나면 사용자가 고른 것과 다른 상대를 때린다.
@MainActor
@Suite("RoomExecutorTests")
struct RoomExecutorTests {
    private final class FakeRoomControl: TerminalRoomControl {
        var terminalState: RoomTerminalState
        var terminalRaidRooms: [TerminalRaidRoom] = []
        var terminalRaidBrowsing = true
        var terminalRaidError: String?
        var submitted: [(target: UUID, move: Int)] = []
        var created: [RaidTier] = []
        var joined: [(number: Int, role: LobbyRole)] = []
        var readied = 0
        var started = 0
        var left = 0

        init(_ state: RoomTerminalState) { terminalState = state }
        func createRaidFromTerminal(tier: RaidTier) -> Bool {
            created.append(tier); terminalState.phase = .creating; return true
        }
        func joinRaidFromTerminal(number: Int, role: LobbyRole) -> Bool {
            guard terminalRaidRooms.contains(where: { $0.number == number }) else { return false }
            joined.append((number, role)); terminalState.phase = .joining("방"); return true
        }
        func toggleReadyFromTerminal() -> Bool { readied += 1; return true }
        func submitAction(targetID: UUID, moveIndex: Int) {
            submitted.append((targetID, moveIndex))
        }
        // 결투·트랙 창구는 이 스위트가 쓰지 않는다 — 레이드·방 대전만 본다.
        func submitDuelMove(index: Int) {}
        func submitDuelSwitch(slot: Int) {}
        func submitTrackInput(_ input: ArenaTrackInput) {}
        func placeArenaBet(runnerID: UUID, stardust: Int) {}
        /// `startRaid` 에서 이름이 바뀌었다 — 시작 함수가 활동마다 다르고 그 라우팅은 이제
        /// 센터 안에 있다(예전엔 터미널이 레이드 것만 불러서 다른 방은 눌러도 안 됐다).
        func startActivity() { started += 1 }
        func leaveRoom() { left += 1 }
    }

    private func makeDirectory() -> URL { storeFixtureDirectory("room-exec") }

    private func makeStore(in directory: URL) -> CompanionStore {
        let store = CompanionStore(clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                   fileURL: directory.appendingPathComponent("state.json"))
        return store
    }

    private func execute(_ action: PokedoroRequest.Action, on store: CompanionStore,
                         room: FakeRoomControl?) async -> PokedoroReply {
        let request = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
        return await PokedoroRequestExecutor(timer: FocusTimer(), companion: store,
                                             room: room).execute(request)
    }

    // MARK: 기술과 대상

    @Test func testRaidRoomsCanBeListedCreatedJoinedAndSpectated() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let listed = FakeRoomControl(RoomTerminalState(phase: .idle, myID: UUID()))
        listed.terminalRaidRooms = [TerminalRaidRoom(number: 1, trainerName: "이웃", tier: .three,
                                                      bossSpeciesID: 25)]
        let status = await execute(.raidStatus, on: store, room: listed)
        #expect(status.succeeded)
        #expect(status.message.contains("1. 3★"))
        #expect(status.message.contains("보스 ") && status.message.contains("25"),
                "이름 조회 성공·실패와 무관하게 입장 전에 보스 종을 식별할 수 있다")

        let creator = FakeRoomControl(RoomTerminalState(phase: .idle, myID: UUID()))
        #expect(await execute(.raidCreate(tier: .three), on: store, room: creator).succeeded)
        #expect(creator.created == [.three])

        for role in [LobbyRole.runner, .spectator] {
            let joiner = FakeRoomControl(RoomTerminalState(phase: .idle, myID: UUID()))
            joiner.terminalRaidRooms = listed.terminalRaidRooms
            #expect(await execute(.raidJoin(number: 1, role: role), on: store, room: joiner).succeeded)
            #expect(joiner.joined.first?.role == role)
        }
    }

    @Test func testReadyReachesTheLobby() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = RoomTerminalState(phase: .joined, activity: .raid, myID: UUID())
        state.isReady = false
        let control = FakeRoomControl(state)

        let reply = await execute(.roomReady, on: makeStore(in: directory), room: control)

        #expect(reply.succeeded)
        #expect(control.readied == 1)
        #expect(reply.message.contains("준비했다"))
    }

    @Test func testRaidMonUsesThePrintedPartyNumber() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        let mon = MonState(baseID: 7, pathIDs: [7], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1,
                           names: [7: ["ko": "꼬부기", "en": "Squirtle"]])
        store.debugSetBoxedMons([mon])
        let entry = try #require(PokedoroCLI.partyEntries(store).first { $0.id == mon.id })
        let number = TUIRender.printedRosterNumber(index: entry.index)
        let control = FakeRoomControl(RoomTerminalState(phase: .idle, myID: UUID()))

        let reply = await execute(.raidMon(number: number), on: store, room: control)

        #expect(reply.succeeded)
        #expect(store.battleRepresentative?.id == mon.id)
    }

    /// 대상을 안 적으면 **첫 상대**다. 협동 레이드는 보스 하나라 그것으로 끝난다.
    @Test func testAMoveWithoutATargetHitsTheFirstOpponent() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = RoomTerminalTests.fighting()
        let control = FakeRoomControl(state)
        let boss = try #require(state.fighters.first { $0.id != state.myID })

        let reply = await execute(.roomMove(move: 2, target: nil),
                                  on: makeStore(in: directory), room: control)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(control.submitted.count == 1)
        #expect(control.submitted.first?.target == boss.id, "번호가 엉뚱한 참가자로 접혔다")
        #expect(control.submitted.first?.move == 1, "2번 기술은 인덱스 1이다")
    }

    /// 목록 밖 대상 번호는 **거절이고 첫 상대로 접지 않는다** — 조용히 다른 상대를 때리면
    /// 사용자는 자기가 고른 것과 다른 일이 벌어진 걸 로그에서야 본다.
    @Test func testATargetNumberOutsideTheListIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeRoomControl(RoomTerminalTests.fighting())

        let reply = await execute(.roomMove(move: 1, target: 5),
                                  on: makeStore(in: directory), room: control)

        #expect(!reply.succeeded)
        #expect(control.submitted.isEmpty, "거절이 창구를 불렀다")
        #expect(reply.message.contains("1"), "몇 명이 서 있는지 말해야 다음 값을 고를 수 있다")
    }

    /// 이미 낸 라운드는 거절이다.
    @Test func testAMoveAfterSubmittingIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = RoomTerminalTests.fighting()
        state.hasSubmitted = true
        let control = FakeRoomControl(state)

        let reply = await execute(.roomMove(move: 1, target: nil),
                                  on: makeStore(in: directory), room: control)

        #expect(!reply.succeeded)
        #expect(control.submitted.isEmpty)
    }

    // MARK: 시작

    /// 시작 거절은 **호스트가 아닌 것과 사람이 덜 모인 것**을 갈라 말한다 — 다음에 할 일이 다르다.
    @Test func testStartRefusalsAreToldApart() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        var guest = RoomTerminalState(phase: .joined, activity: .raid, myID: UUID())
        guest.canStart = true
        let asGuest = FakeRoomControl(guest)
        let guestReply = await execute(.roomStart, on: store, room: asGuest)
        #expect(!guestReply.succeeded)
        #expect(guestReply.message.contains("호스트"))
        #expect(asGuest.started == 0)

        var lonely = RoomTerminalState(phase: .hosting, activity: .raid, myID: UUID())
        lonely.isHost = true
        lonely.canStart = false
        let alone = FakeRoomControl(lonely)
        let lonelyReply = await execute(.roomStart, on: store, room: alone)
        #expect(!lonelyReply.succeeded)
        #expect(lonelyReply.message.contains("사람"))
        #expect(alone.started == 0)
    }

    @Test func testTheHostCanStartOnceEveryoneIsIn() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = RoomTerminalState(phase: .hosting, activity: .raid, myID: UUID())
        state.isHost = true
        state.canStart = true
        let control = FakeRoomControl(state)

        #expect(await execute(.roomStart, on: makeStore(in: directory), room: control).succeeded)
        #expect(control.started == 1)
    }

    // MARK: 나가기

    @Test func testLeavingReachesTheCenter() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeRoomControl(RoomTerminalTests.fighting())

        #expect(await execute(.roomLeave, on: makeStore(in: directory), room: control).succeeded)
        #expect(control.left == 1)
    }

    /// 방에 없는데 온 나가기는 거절이다 — 부르면 센터가 세션 번호를 올려 **막 만든 방을 닫는다.**
    @Test func testLeavingWithoutARoomIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeRoomControl(RoomTerminalState(phase: .idle, myID: UUID()))

        let reply = await execute(.roomLeave, on: makeStore(in: directory), room: control)

        #expect(!reply.succeeded)
        #expect(control.left == 0)
    }

    /// 창구가 없으면 **방에 없는 것과 같다.**
    @Test func testWithoutAControlEverythingReadsAsNoRoom() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        for action: PokedoroRequest.Action in [.roomMove(move: 1, target: nil), .roomStart,
                                               .roomReady, .roomLeave, .raidStatus,
                                               .raidCreate(tier: .one),
                                               .raidJoin(number: 1, role: .runner)] {
            let reply = await execute(action, on: store, room: nil)
            #expect(!reply.succeeded)
            #expect(reply.message.contains("방에 없다"), "\(action.name) 의 사유가 다르다")
        }
    }
}
