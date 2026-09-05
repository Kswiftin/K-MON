import Foundation
import Testing
@testable import PokeTokenBar

/// 터미널이 부탁한 대전 동작을 **앱이** 실행하는 자리.
///
/// 가짜 창구(`FakeBattleControl`)를 끼운다. `BattleCenter` 를 그대로 쓰면 Bonjour 광고와 소켓이
/// 살아나 실제 네트워크로 나가므로, 창구를 좁혀 둔 이유가 정확히 이것이다
/// (`TerminalBattleControl` 의 주석).
///
/// 재는 것은 둘이다: **거절을 갈라 말하는가**, 그리고 **실제로 그 호출이 나갔는가.** 성공으로
/// 뭉갠 무동작은 사용자가 일어나지 않은 일을 믿게 만들고, 뭉뚱그린 거절은 같은 명령을 반복하게 만든다.
@MainActor
@Suite("NetBattleExecutorTests")
struct NetBattleExecutorTests {
    /// 창구 하나만 흉내 낸다 — 상태는 테스트가 세우고, 어떤 호출이 나갔는지만 기록한다.
    private final class FakeBattleControl: TerminalBattleControl {
        var terminalState: BattleTerminalState
        var chosenMoves: [Int] = []
        var switchedTo: [Int] = []
        var forfeited = 0
        var declined = 0

        init(_ state: BattleTerminalState) { terminalState = state }
        func chooseMove(_ index: Int) { chosenMoves.append(index) }
        func switchLAN(to index: Int) { switchedTo.append(index) }
        func forfeit() { forfeited += 1 }
        func declineIncoming() { declined += 1 }
    }

    private func makeDirectory() -> URL { storeFixtureDirectory("net-battle-exec") }

    private func makeStore(in directory: URL) -> CompanionStore {
        let store = CompanionStore(clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                   fileURL: directory.appendingPathComponent("state.json"))
        // 언어를 못 박는다 — 답 문구가 세이브 언어로 나오고 신규 세이브는 호스트 로케일을 따른다.
        store.setLanguage(.ko)
        return store
    }

    private func execute(_ action: PokedoroRequest.Action, on store: CompanionStore,
                         battle: FakeBattleControl?) async -> PokedoroReply {
        let request = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
        return await PokedoroRequestExecutor(timer: FocusTimer(), companion: store,
                                             battle: battle).execute(request)
    }

    // MARK: 기술

    /// 번호는 **1부터**이고 창구는 인덱스를 받는다. 접는 자리가 실행기 하나여야 한다 — 두 곳이
    /// 각자 세면 사용자가 고른 것과 다른 기술이 나간다.
    @Test func testAMoveNumberIsFoldedToAnIndexExactlyOnce() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeBattleControl(Self.battling())

        let reply = await execute(.battleMove(move: 2), on: makeStore(in: directory), battle: control)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(control.chosenMoves == [1], "2번 기술은 인덱스 1이다")
    }

    /// 이미 낸 턴에 온 기술은 **거절이고 창구를 부르지 않는다.** 다시 부르면 `chooseMove` 의
    /// 가드가 조용히 무시하는데, 그 침묵을 성공으로 답하면 사용자는 기술을 바꿨다고 믿는다.
    @Test func testAMoveAfterSubmittingIsRefusedWithoutCallingTheCenter() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = Self.battling()
        state.battle?.myAction = .move(index: 0)
        let control = FakeBattleControl(state)

        let reply = await execute(.battleMove(move: 1), on: makeStore(in: directory), battle: control)

        #expect(!reply.succeeded)
        #expect(control.chosenMoves.isEmpty, "거절이 창구를 불렀다")
        #expect(reply.message.contains("이미"), "무엇을 기다리는지 말해야 한다")
    }

    /// 쓰러진 자리가 있으면 기술이 아니라 **교체가 먼저**라고 말한다.
    @Test func testAMoveWhileFaintedPointsAtTheReplacement() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = Self.battling(teamSize: 2)
        state.battle?.myTeam[0].hp = 0
        let control = FakeBattleControl(state)

        let reply = await execute(.battleMove(move: 1), on: makeStore(in: directory), battle: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("battle switch"))
        #expect(control.chosenMoves.isEmpty)
    }

    /// PP 가 없는 번호는 거절이다 — 조용히 다른 기술로 접으면 사용자는 자기가 쓰지 않은 기술이
    /// 나간 것을 로그에서야 본다(웨이브 런과 같은 규칙).
    @Test func testAMoveWithoutPPIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = Self.battling()
        state.battle?.myTeam[0].pp[1] = 0
        let control = FakeBattleControl(state)

        let reply = await execute(.battleMove(move: 2), on: makeStore(in: directory), battle: control)

        #expect(!reply.succeeded)
        #expect(control.chosenMoves.isEmpty)
    }

    // MARK: 교체

    @Test func testASwitchNumberIsFoldedToATeamIndex() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = Self.battling(teamSize: 2)
        state.battle?.myTeam[0].hp = 0
        let control = FakeBattleControl(state)

        let reply = await execute(.battleSwitch(number: 2), on: makeStore(in: directory),
                                  battle: control)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(control.switchedTo == [1])
    }

    /// 지금 나와 있는 개체로 바꾸는 것은 아무 일도 아니다 — `canChoose` 가 거절하므로 성공으로
    /// 답하면 사용자는 교체가 일어났다고 믿는다.
    @Test func testSwitchingToTheActiveMemberIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeBattleControl(Self.battling(teamSize: 2))

        let reply = await execute(.battleSwitch(number: 1), on: makeStore(in: directory),
                                  battle: control)

        #expect(!reply.succeeded)
        #expect(control.switchedTo.isEmpty)
    }

    // MARK: 항복·거절

    @Test func testForfeitingReachesTheCenter() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeBattleControl(Self.battling())

        let reply = await execute(.battleForfeit, on: makeStore(in: directory), battle: control)

        #expect(reply.succeeded)
        #expect(control.forfeited == 1)
    }

    /// 대전이 없는데 온 항복은 **거절이다.** 부르면 `forfeit` 이 국면을 `.finished` 로 옮겨
    /// 아무 판도 없던 사용자에게 패배 화면이 뜬다.
    @Test func testForfeitingWithoutABattleIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeBattleControl(BattleTerminalState(phase: .ready, battle: nil))

        let reply = await execute(.battleForfeit, on: makeStore(in: directory), battle: control)

        #expect(!reply.succeeded)
        #expect(control.forfeited == 0, "없는 판을 항복해 패배가 기록됐다")
    }

    @Test func testDecliningOnlyWorksOnAnIncomingChallenge() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let incoming = FakeBattleControl(BattleTerminalState(phase: .incoming(peer: "P"),
                                                              battle: nil))
        #expect(await execute(.battleDecline, on: store, battle: incoming).succeeded)
        #expect(incoming.declined == 1)

        // 진행 중인 대전에는 거절할 신청이 없다 — 성공으로 답하면 사용자는 치웠다고 믿는다.
        let fighting = FakeBattleControl(Self.battling())
        let reply = await execute(.battleDecline, on: store, battle: fighting)
        #expect(!reply.succeeded)
        #expect(fighting.declined == 0)
    }

    /// 창구가 없으면 **대전이 없는 것과 같다.** 사유를 따로 만들면 사용자에게 내부 배선을
    /// 설명하는 문구가 나간다.
    @Test func testWithoutAControlEverythingReadsAsNoBattle() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        for action: PokedoroRequest.Action in [.battleMove(move: 1), .battleSwitch(number: 2),
                                               .battleForfeit, .battleDecline] {
            let reply = await execute(action, on: store, battle: nil)
            #expect(!reply.succeeded)
            #expect(reply.message.contains("대전이 없다"), "\(action.name) 의 사유가 다르다")
        }
    }

    // MARK: 픽스처

    static func battling(teamSize: Int = 1) -> BattleTerminalState {
        BattleTerminalState(
            phase: .battling,
            battle: NetBattleState(iAmA: true,
                                   myTeam: (0..<teamSize).map { BattleSide(snapshot(name: "내\($0 + 1)")) },
                                   oppTeam: [BattleSide(snapshot(name: "상대"))],
                                   rng: SplitMix64(seed: 5)),
            remainingSeconds: 20)
    }

    static func snapshot(name: String) -> BattleSnapshot {
        BattleSnapshot(
            speciesID: 1, name: name, trainer: "T", level: 50, nature: nil, isShiny: false,
            types: [.normal],
            base: BattleStats(hp: 100, atk: 100, def: 50, spa: 100, spd: 50, spe: 100),
            moves: [MoveSpec(id: 1, names: ["ko": "타격"], type: .normal, power: 40,
                             damageClass: .physical, accuracy: nil, pp: 20),
                    MoveSpec(id: 2, names: ["ko": "울음"], type: .normal, power: 0,
                             damageClass: .status, accuracy: nil, pp: 40)])
    }
}
