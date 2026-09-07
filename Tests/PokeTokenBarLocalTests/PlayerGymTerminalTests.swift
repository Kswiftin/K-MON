import Foundation
import Testing
@testable import PokeTokenBar

@MainActor
@Suite("PlayerGymTerminalTests")
struct PlayerGymTerminalTests {
    private final class FakeControl: TerminalPlayerGymControl {
        var terminalState: PlayerGymTerminalState
        var challenged: [[UUID]] = []
        var opened: [[UUID]] = []
        var defenses: [[UUID]] = []
        var refreshed = 0

        init(_ state: PlayerGymTerminalState) { terminalState = state }
        func refreshForTerminal() { refreshed += 1 }
        func openFromTerminal(defenseTeam: [UUID]) -> Bool { opened.append(defenseTeam); return true }
        func challengeFromTerminal(team: [UUID]) -> Bool { challenged.append(team); return true }
        func spectateFromTerminal() -> Bool { true }
        func setDefenseTeamFromTerminal(_ team: [UUID]) -> Bool { defenses.append(team); return true }
        func setAIFromTerminal(_ enabled: Bool) -> Bool { true }
        func resignFromTerminal() {}
        func takeOverFromTerminal() -> Bool { true }
    }

    private func state(leader: String? = "관장") -> PlayerGymTerminalState {
        PlayerGymTerminalState(isLeader: false, phase: .idle, visibleLeader: leader,
                               canChallengeVisibleGym: leader != nil,
                               discoveryUnavailable: false, hasScannedOnce: true,
                               needsAppUpdate: false, defenseTeam: [], usesAI: false,
                               consecutiveDefenses: 0, earnedToday: 0, defenseLog: [],
                               setupSecondsRemaining: nil, takeoverAvailable: false)
    }

    private func store(_ directory: URL) -> CompanionStore {
        let store = CompanionStore(fileURL: directory.appendingPathComponent("state.json"))
        let mons = (1...4).map { id in
            MonState(baseID: id, pathIDs: [id], stageIndex: 0, usedAtStage: 0,
                     rarity: .common, totalForms: 1)
        }
        store.debugSetBoxedMons(mons)
        return store
    }

    @Test func testContestCommandsParseAndRoundTrip() throws {
        #expect(try PokedoroCommandParser.parse(
            ["gym", "team", "4", "2", "1", "3"])
            == .gymTeam(team: [4, 2, 1, 3]))
        #expect(try PokedoroCommandParser.parse(
            ["gym", "contest", "challenge", "1", "2", "3", "4"])
            == .playerGymChallenge(team: [1, 2, 3, 4]))
        #expect(try PokedoroCommandParser.parse(
            ["gym", "contest", "open", "4", "3", "2", "1"])
            == .playerGymOpen(team: [4, 3, 2, 1]))
        let action = PokedoroRequest.Action.playerGymDefense(team: [1, 2, 3, 4])
        #expect(PokedoroRequest.Action(name: action.name, argument: action.argument) == action)
        #expect(PokedoroRequest.Action(name: "gym.contest.challenge", argument: "1 1 2 3") == nil)
    }

    @Test func testChallengeUsesPartyNumbersInThePrintedOrder() async {
        let directory = storeFixtureDirectory("player-gym-terminal")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store(directory)
        let entries = PokedoroCLI.partyEntries(store)
        let control = FakeControl(state())
        let request = PokedoroRequest(id: UUID(), action: .playerGymChallenge(team: [4, 2, 1, 3]),
                                      requestedAt: Date())

        let reply = await PokedoroRequestExecutor(timer: FocusTimer(), companion: store,
                                                  playerGym: control).execute(request)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(control.challenged == [[entries[3].id, entries[1].id, entries[0].id, entries[2].id]])
    }

    @Test func testStatusDistinguishesTheContestGym() async {
        let directory = storeFixtureDirectory("player-gym-status")
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeControl(state())
        let request = PokedoroRequest(id: UUID(), action: .playerGymStatus, requestedAt: Date())

        let reply = await PokedoroRequestExecutor(timer: FocusTimer(), companion: store(directory),
                                                  playerGym: control).execute(request)

        #expect(reply.succeeded)
        #expect(reply.message.contains("관장"), "\(reply.message)")
        #expect(control.refreshed == 1)
    }

    @Test func testLeaderCanReorderTheAlreadyLockedDefenseTeam() async {
        let directory = storeFixtureDirectory("player-gym-defense")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store(directory)
        let entries = PokedoroCLI.partyEntries(store)
        let team = entries.map(\.id)
        store.becomeGymLeader()
        store.setGymDefenseTeam(team)
        var leaderState = state(leader: nil)
        leaderState.isLeader = true
        leaderState.defenseTeam = team
        let control = FakeControl(leaderState)
        let request = PokedoroRequest(id: UUID(), action: .playerGymDefense(team: [4, 3, 2, 1]),
                                      requestedAt: Date())

        let reply = await PokedoroRequestExecutor(timer: FocusTimer(), companion: store,
                                                  playerGym: control).execute(request)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(control.defenses == [[team[3], team[2], team[1], team[0]]])
    }
}
