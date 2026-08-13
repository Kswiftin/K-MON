import Foundation
import Network
import Observation

struct MultiplayerRoomPeer: Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

@MainActor
@Observable
final class MultiplayerRoomCenter {
    enum Phase: Equatable { case idle, creating, hosting, joining(String), joined, battling }
    nonisolated static let serviceType = "_kmonroom._tcp"
    private nonisolated static let maxMessageBytes: UInt32 = 1_000_000

    private(set) var phase: Phase = .idle
    private(set) var rooms: [MultiplayerRoomPeer] = []
    private(set) var lobby: MultiplayerLobby?
    private(set) var combatFighters: [MultiplayerFighter] = []
    private(set) var combatRound = 0
    private(set) var combatEvents: [MultiplayerBattleEvent] = []
    private(set) var hasSubmittedAction = false
    private(set) var turnEndsAt: Date?
    private(set) var battleReward: Int?
    private(set) var lastError: String?
    let myID = UUID()

    private let companion: CompanionStore
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var hostConnection: NWConnection?
    private var guestConnections: [UUID: NWConnection] = [:]
    private var pendingGuestConnections: [ObjectIdentifier: NWConnection] = [:]
    private var mySnapshot: BattleSnapshot?
    private var hostingRole = false
    private var snapshots: [UUID: BattleSnapshot] = [:]
    private var battle: MultiplayerBattle?
    private var pendingActions: [UUID: MultiplayerAction] = [:]
    private var turnTimeoutTask: Task<Void, Never>?
    private var rewardedBattle = false
    private static let turnDuration: TimeInterval = 30

    init(companion: CompanionStore) { self.companion = companion }

    var isHost: Bool { hostingRole }
    var myParticipant: LobbyParticipant? { lobby?.participants.first { $0.id == myID } }

    func startBrowsing() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: Self.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let peers = results.compactMap { result -> MultiplayerRoomPeer? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return MultiplayerRoomPeer(id: name, name: Self.displayName(name), endpoint: result.endpoint)
            }
            Task { @MainActor in self?.rooms = peers.sorted { $0.name < $1.name } }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor in self?.lastError = error.localizedDescription; self?.restartBrowser() }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func createRoom(mode: MultiplayerBattleMode) {
        guard phase == .idle else { return }
        phase = .creating; lastError = nil
        Task {
            guard let snapshot = await buildSnapshot() else { phase = .idle; lastError = "포켓몬 정보를 불러오지 못했습니다."; return }
            mySnapshot = snapshot
            snapshots[myID] = snapshot
            let team: BattleTeam = mode == .teams ? .red : .solo
            let host = LobbyParticipant(id: myID, trainerName: trainerName, speciesID: snapshot.speciesID,
                                        team: team, isReady: false, isHost: true)
            do {
                lobby = try MultiplayerLobby(host: host)
                hostingRole = true
                try startHosting()
                phase = .hosting
            } catch {
                hostingRole = false; phase = .idle; lobby = nil; lastError = error.localizedDescription
            }
        }
    }

    func join(_ room: MultiplayerRoomPeer) {
        guard phase == .idle else { return }
        phase = .joining(room.name); lastError = nil
        hostingRole = false
        Task {
            guard let snapshot = await buildSnapshot() else { phase = .idle; lastError = "포켓몬 정보를 불러오지 못했습니다."; return }
            mySnapshot = snapshot
            snapshots[myID] = snapshot
            let connection = NWConnection(to: room.endpoint, using: Self.parameters())
            hostConnection = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                Task { @MainActor in
                    guard let self, let connection, connection === self.hostConnection else { return }
                    switch state {
                    case .ready:
                        let participant = LobbyParticipant(id: self.myID, trainerName: self.trainerName,
                                                           speciesID: snapshot.speciesID, team: .solo,
                                                           isReady: false, isHost: false)
                        self.send(.join(version: MultiplayerWireMessage.protocolVersion,
                                        participant: participant, snapshot: snapshot), over: connection)
                        self.receiveGuestLoop(connection)
                    case .failed(let error): self.lastError = error.localizedDescription; self.leaveRoom()
                    case .cancelled: if self.phase != .idle { self.leaveRoom() }
                    default: break
                    }
                }
            }
            connection.start(queue: .main)
        }
    }

    func toggleReady() {
        guard let me = myParticipant else { return }
        if isHost {
            lobby?.setReady(!me.isReady, participantID: myID); broadcastLobby()
        } else if let hostConnection { send(.ready(participantID: myID, ready: !me.isReady), over: hostConnection) }
    }

    func selectTeam(_ team: BattleTeam) {
        guard lobby?.mode == .teams || team != .solo else { return }
        if isHost { lobby?.setTeam(team, participantID: myID); broadcastLobby() }
        else if let hostConnection { send(.team(participantID: myID, team: team), over: hostConnection) }
    }

    func startBattle() {
        guard isHost, let lobby, lobby.canStart else { return }
        let fighters = lobby.participants.compactMap { participant -> MultiplayerFighter? in
            guard let snapshot = snapshots[participant.id] else { return nil }
            return MultiplayerFighter(participant: participant, snapshot: snapshot)
        }
        guard fighters.count == lobby.participants.count else { lastError = "참가자 정보를 준비하지 못했습니다."; return }
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        do {
            battle = try MultiplayerBattle(fighters: fighters, mode: lobby.mode, seed: seed)
            combatFighters = fighters; combatRound = 1; combatEvents = []
            pendingActions.removeAll(); hasSubmittedAction = false; phase = .battling
            rewardedBattle = false; battleReward = nil; scheduleTurnTimeout()
            let message = MultiplayerWireMessage.start(seed: seed, fighters: fighters, mode: lobby.mode)
            for connection in guestConnections.values { send(message, over: connection) }
        } catch { lastError = error.localizedDescription }
    }

    func submitAction(targetID: UUID, moveIndex: Int) {
        guard phase == .battling, !hasSubmittedAction,
              combatFighters.contains(where: { $0.id == myID && $0.isAlive }),
              combatFighters.contains(where: { $0.id == targetID && $0.isAlive }) else { return }
        let action = MultiplayerAction(attackerID: myID, targetID: targetID, moveIndex: moveIndex)
        hasSubmittedAction = true
        if isHost { acceptAction(action, from: myID) }
        else if let hostConnection { send(.action(round: combatRound, action: action), over: hostConnection) }
    }

    var isBattleFinished: Bool {
        guard !combatFighters.isEmpty else { return false }
        let living = combatFighters.filter(\.isAlive)
        let mode = lobby?.mode ?? (Set(living.map(\.team)).contains(.solo) ? .freeForAll : .teams)
        return mode == .freeForAll ? living.count <= 1 : Set(living.map(\.team)).count <= 1
    }

    var didIWin: Bool { isBattleFinished && combatFighters.first(where: { $0.id == myID })?.isAlive == true }

    func leaveRoom() {
        if !isHost, let hostConnection { send(.leave(participantID: myID), over: hostConnection) }
        hostConnection?.cancel(); hostConnection = nil
        guestConnections.values.forEach { $0.cancel() }; guestConnections.removeAll()
        pendingGuestConnections.values.forEach { $0.cancel() }; pendingGuestConnections.removeAll()
        listener?.cancel(); listener = nil
        turnTimeoutTask?.cancel(); turnTimeoutTask = nil
        lobby = nil; mySnapshot = nil; snapshots.removeAll(); battle = nil
        pendingActions.removeAll(); combatFighters = []; combatEvents = []; combatRound = 0
        turnEndsAt = nil; battleReward = nil; rewardedBattle = false
        hasSubmittedAction = false; hostingRole = false; phase = .idle
    }

    private func startHosting() throws {
        let listener = try NWListener(using: Self.parameters())
        listener.service = NWListener.Service(name: "\(trainerName)'s room#\(String(myID.uuidString.prefix(6)))",
                                              type: Self.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.acceptGuest(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { Task { @MainActor in self?.lastError = error.localizedDescription; self?.leaveRoom() } }
        }
        listener.start(queue: .main); self.listener = listener
    }

    private func acceptGuest(_ connection: NWConnection) {
        guard isHost, guestConnections.count + pendingGuestConnections.count < 3 else { connection.cancel(); return }
        let key = ObjectIdentifier(connection); pendingGuestConnections[key] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor in
                    guard let self, let connection else { return }
                    self.guestDisconnected(connection, pendingKey: key)
                }
            default: break
            }
        }
        connection.start(queue: .main)
        receiveHostLoop(connection, key: key, participantID: nil)
    }

    private func receiveHostLoop(_ connection: NWConnection, key: ObjectIdentifier, participantID: UUID?) {
        receive(over: connection) { [weak self, weak connection] message in
            guard let self, let connection, self.isHost else { return }
            var id = participantID
            switch message {
            case .join(let version, let participant, let snapshot):
                guard id == nil, version == MultiplayerWireMessage.protocolVersion else {
                    self.send(.rejected(reason: "호환되지 않는 방입니다."), over: connection); connection.cancel(); return
                }
                guard MultiplayerValidation.valid(participant: participant, snapshot: snapshot) else {
                    self.send(.rejected(reason: "잘못된 참가자 정보입니다."), over: connection); connection.cancel(); return
                }
                do {
                    try self.lobby?.join(participant)
                    id = participant.id
                    self.snapshots[participant.id] = snapshot
                    self.pendingGuestConnections.removeValue(forKey: key)
                    self.guestConnections[participant.id] = connection
                    self.broadcastLobby()
                } catch {
                    self.send(.rejected(reason: "방이 가득 찼습니다."), over: connection); connection.cancel(); return
                }
            case .ready(let pid, let ready) where pid == id:
                self.lobby?.setReady(ready, participantID: pid); self.broadcastLobby()
            case .team(let pid, let team) where pid == id:
                self.lobby?.setTeam(team, participantID: pid); self.broadcastLobby()
            case .leave(let pid) where pid == id:
                if self.phase == .battling {
                    self.battle?.forfeit(participantID: pid)
                    self.combatFighters = self.battle?.fighters ?? self.combatFighters
                    self.finishRoundIfReady()
                } else { try? self.lobby?.leave(participantID: pid) }
                self.snapshots.removeValue(forKey: pid); self.guestConnections.removeValue(forKey: pid)
                connection.cancel(); self.broadcastLobby(); return
            case .action(let round, let action) where action.attackerID == id && round == self.combatRound:
                if let id { self.acceptAction(action, from: id) }
            default: break
            }
            self.receiveHostLoop(connection, key: key, participantID: id)
        }
    }

    private func receiveGuestLoop(_ connection: NWConnection) {
        receive(over: connection) { [weak self, weak connection] message in
            guard let self, let connection, connection === self.hostConnection else { return }
            switch message {
            case .lobby(let lobby): self.lobby = lobby; self.phase = .joined
            case .start(let seed, let fighters, let mode):
                guard MultiplayerValidation.validStart(fighters: fighters, mode: mode),
                      let started = try? MultiplayerBattle(fighters: fighters, mode: mode, seed: seed) else {
                    self.lastError = "잘못된 배틀 정보입니다."; self.leaveRoom(); return
                }
                self.battle = started; self.combatFighters = fighters; self.combatRound = 1
                self.combatEvents = []; self.hasSubmittedAction = false; self.rewardedBattle = false
                self.battleReward = nil; self.turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
                self.phase = .battling
            case .roundResolved(let round, let fighters, let events):
                guard self.phase == .battling, round == self.combatRound else { return }
                self.combatFighters = fighters; self.combatEvents = events
                self.combatRound += 1; self.hasSubmittedAction = false
                self.turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
                self.grantRewardIfFinished()
            case .rejected(let reason): self.lastError = reason; self.leaveRoom(); return
            default: break
            }
            self.receiveGuestLoop(connection)
        }
    }

    private func broadcastLobby() {
        guard let lobby else { return }
        for connection in guestConnections.values { send(.lobby(lobby), over: connection) }
    }

    private func acceptAction(_ action: MultiplayerAction, from participantID: UUID) {
        guard phase == .battling, action.attackerID == participantID,
              pendingActions[participantID] == nil else { return }
        pendingActions[participantID] = action
        finishRoundIfReady()
    }

    private func finishRoundIfReady() {
        guard isHost, var battle else { return }
        let livingIDs = Set(battle.livingFighters.map(\.id))
        pendingActions = pendingActions.filter { livingIDs.contains($0.key) }
        guard Set(pendingActions.keys) == livingIDs else { return }
        do {
            let resolvedRound = combatRound
            let events = try battle.resolveRound(Array(pendingActions.values))
            self.battle = battle; combatFighters = battle.fighters; combatEvents = events
            pendingActions.removeAll(); combatRound += 1; hasSubmittedAction = false
            let message = MultiplayerWireMessage.roundResolved(round: resolvedRound,
                                                               fighters: battle.fighters, events: events)
            for connection in guestConnections.values { send(message, over: connection) }
            if battle.isFinished {
                turnTimeoutTask?.cancel(); turnEndsAt = nil; grantRewardIfFinished()
            } else { scheduleTurnTimeout() }
        } catch {
            lastError = error.localizedDescription; pendingActions.removeAll(); hasSubmittedAction = false
        }
    }

    private func scheduleTurnTimeout() {
        turnTimeoutTask?.cancel()
        let round = combatRound
        turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
        turnTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.turnDuration))
            guard !Task.isCancelled else { return }
            self?.fillTimedOutActions(round: round)
        }
    }

    private func fillTimedOutActions(round: Int) {
        guard isHost, phase == .battling, combatRound == round, let battle else { return }
        for action in MultiplayerBattle.automaticActions(fighters: battle.fighters, mode: battle.mode,
                                                          excluding: Set(pendingActions.keys)) {
            pendingActions[action.attackerID] = action
        }
        finishRoundIfReady()
    }

    private func guestDisconnected(_ connection: NWConnection, pendingKey: ObjectIdentifier) {
        pendingGuestConnections.removeValue(forKey: pendingKey)
        guard let id = guestConnections.first(where: { $0.value === connection })?.key else { return }
        guestConnections.removeValue(forKey: id); snapshots.removeValue(forKey: id)
        if phase == .battling {
            battle?.forfeit(participantID: id)
            combatFighters = battle?.fighters ?? combatFighters
            pendingActions.removeValue(forKey: id)
            if battle?.isFinished == true {
                turnTimeoutTask?.cancel(); turnEndsAt = nil; grantRewardIfFinished()
                broadcastCombatState()
            } else { finishRoundIfReady() }
        } else {
            try? lobby?.leave(participantID: id); broadcastLobby()
        }
    }

    private func grantRewardIfFinished() {
        guard isBattleFinished, !rewardedBattle else { return }
        rewardedBattle = true
        let won = didIWin, count = combatFighters.count
        battleReward = max(20, count * (won ? 40 : 15))
        let mode = lobby?.mode ?? .freeForAll
        let opponents = combatFighters.filter { $0.id != myID }.map(\.trainerName)
        companion.grantBattleReward(won: won, participantCount: count, mode: mode,
                                    opponentNames: opponents)
    }

    private func broadcastCombatState() {
        let message = MultiplayerWireMessage.roundResolved(round: combatRound,
                                                           fighters: combatFighters, events: [])
        for connection in guestConnections.values { send(message, over: connection) }
    }

    private func send(_ message: MultiplayerWireMessage, over connection: NWConnection) {
        guard let payload = try? JSONEncoder().encode(message), payload.count <= Self.maxMessageBytes else { return }
        var frame = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }; frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receive(over connection: NWConnection, completion: @escaping @MainActor (MultiplayerWireMessage) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, _ in
            guard let data, data.count == 4 else { Task { @MainActor in connection.cancel() }; return }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            guard length > 0, length <= Self.maxMessageBytes else { connection.cancel(); return }
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { data, _, _, _ in
                guard let data, data.count == Int(length),
                      let message = try? JSONDecoder().decode(MultiplayerWireMessage.self, from: data) else { connection.cancel(); return }
                Task { @MainActor in completion(message) }
            }
        }
    }

    private var trainerName: String {
        let value = companion.trainerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Trainer" : value
    }

    private func buildSnapshot() async -> BattleSnapshot? {
        guard let active = companion.state.active, let speciesID = companion.currentSpeciesID,
              let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID) else { return nil }
        let level = BattleSnapshot.level(stageIndex: active.stageIndex, totalForms: active.totalForms,
                                         stageProgress: companion.progress)
        let moves = await PokeAPIClient.shared.moveSet(speciesID: speciesID, level: level, types: profile.types)
        return BattleSnapshot(speciesID: speciesID, name: companion.displayName, trainer: trainerName,
                              level: level, nature: active.nature, isShiny: active.isShiny,
                              types: profile.types, base: profile.stats, moves: moves)
    }

    private func restartBrowser() { browser?.cancel(); browser = nil; startBrowsing() }
    private nonisolated static func parameters() -> NWParameters { let p = NWParameters.tcp; p.includePeerToPeer = true; return p }
    private nonisolated static func displayName(_ service: String) -> String {
        service.split(separator: "#", maxSplits: 1).first.map(String.init) ?? service
    }
}
