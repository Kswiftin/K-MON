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
    enum Phase: Equatable { case idle, creating, hosting, joining(String), joined, battling, pokeathlon, pokemonQuiz, tournament }
    nonisolated static let serviceType = "_kmonroom._tcp"
    private nonisolated static let maxMessageBytes: UInt32 = 1_000_000

    private(set) var phase: Phase = .idle
    private(set) var rooms: [MultiplayerRoomPeer] = []
    private(set) var lobby: MultiplayerLobby?
    private(set) var combatFighters: [MultiplayerFighter] = []
    private(set) var combatRound = 0
    private(set) var combatEvents: [BattleEvent] = []
    private(set) var hasSubmittedAction = false
    private(set) var turnEndsAt: Date?
    private(set) var lastError: String?
    private(set) var chatMessages: [BattleChatMessage] = []
    private var chatHistory = BattleChatHistory()
    private var chatRateLimiter = BattleChatRateLimiter()
    /// 경기 중에도 매 입력마다 대입된다(호스트 반영·게스트 수신). 그래서 완주 적립은
    /// **nil → 우승자 확정 전이**에서만 발화한다 — 판정은 아래 순수 함수가 한다.
    private(set) var pokeathlonRace: PokeathlonRace? {
        didSet {
            guard Self.creditsRaceFinish(old: oldValue, new: pokeathlonRace, myID: myID) else { return }
            companion.recordRaceFinish()
        }
    }

    /// 이번 대입이 "내 완주" 인지. 네트워크 없이 전 분기를 검증하려고 순수 함수로 떼어 뒀다
    /// (`MultiplayerBattle.outcome` 과 같은 이유).
    ///
    /// 우승 확정 뒤에도 브로드캐스트가 이어지니 `old` 가 이미 확정이면 세지 않는다. 관전자는
    /// `racers` 에 없어 자동으로 빠진다. 이 한 곳이 호스트·게스트·솔로를 모두 덮는다 —
    /// `applySettlement` 에 걸면 베팅 없는 솔로 레이스가 조기 반환에 통째로 빠진다.
    /// `nonisolated` 가 없으면 클래스의 `@MainActor` 를 물려받아 동기 테스트에서 못 부른다
    /// (`parameters()`·`displayName(_:)` 도 같다).
    nonisolated static func creditsRaceFinish(old: PokeathlonRace?, new: PokeathlonRace?, myID: UUID) -> Bool {
        guard old?.winnerID == nil, let new, new.winnerID != nil,
              new.racers.contains(where: { $0.id == myID }) else { return false }
        return true
    }
    private(set) var pokeathlonPool = PokeathlonPool()
    private(set) var pokemonQuizGame: PokemonOXGame?
    var tournamentPickedTeam: [UUID] = []
    private(set) var tournamentState: PokemonTournamentState?
    private var tournamentTeams: [UUID: [BattleSnapshot]] = [:]
    private var tournamentBracket: TournamentBracket?
    private var tournamentMatch: TournamentMatchEngine?
    private var tournamentRewarded = false
    private(set) var isPreparingPokemonQuiz = false
    private var pokemonQuizTask: Task<Void, Never>?
    /// 방향키 입력마다 10명 전체 상태를 즉시 보내면 입력 수 × 접속자 수만큼 send 큐가 불어난다.
    /// 최신 상태 하나만 10Hz로 합쳐 보내 네트워크 역압으로 게스트 전원이 끊기는 일을 막는다.
    private var pokemonQuizBroadcastTask: Task<Void, Never>?
    private var lastPokemonQuizInputAt = Date.distantPast
    private(set) var settlementPayout: Int?
    /// 내가 이미 지갑에서 뺀 베팅. 원장이 바뀌면 차액만 조정하고, 정산 때 이 값으로 호스트 원장을 검증한다.
    private var escrowedBet: PokeathlonBet?
    private var settledPool = false
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
    /// 한 턴에 주는 시간. 1v1 LAN 도 같은 값을 쓴다(`BattleCenter.turnDuration`) — 두 모드의
    /// 체감이 갈리면 같은 앱에서 다른 게임을 하는 것처럼 느껴진다.
    static let turnDuration: TimeInterval = 30

    init(companion: CompanionStore) { self.companion = companion }

    var isHost: Bool { hostingRole }
    var myParticipant: LobbyParticipant? { lobby?.participants.first { $0.id == myID } }
    var amSpectator: Bool { myParticipant?.role == .spectator }
    var myBet: PokeathlonBet? { pokeathlonPool.bets[myID] }

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
        createRoom(mode: mode, activity: .battle)
    }

    func createPokeathlonRoom() { createRoom(mode: .freeForAll, activity: .pokeathlon) }
    func createPokemonQuizRoom() { createRoom(mode: .freeForAll, activity: .pokemonQuiz) }
    func createTournamentRoom() { createRoom(mode: .freeForAll, activity: .tournament) }

    func startSoloPokemonQuiz() {
        guard phase == .idle else { return }
        phase = .creating; lastError = nil
        Task {
            guard let snapshot = await buildSnapshot() else {
                phase = .idle; lastError = "포켓몬 정보를 불러오지 못했습니다."; return
            }
            hostingRole = true; lobby = nil
            await preparePokemonQuiz(players: [PokemonOXPlayer(id: myID, trainerName: trainerName,
                                                               speciesID: snapshot.speciesID)])
        }
    }

    func startSoloPokeathlon() {
        guard phase == .idle else { return }
        lastError = nil
        phase = .creating
        Task {
            guard let snapshot = await buildSnapshot() else {
                phase = .idle
                lastError = "포켓몬 정보를 불러오지 못했습니다."
                return
            }
            hostingRole = true
            lobby = nil
            pokeathlonRace = PokeathlonRace(racers: [
                PokeathlonRacer(id: myID, trainerName: trainerName, speciesID: snapshot.speciesID,
                                teamSpeciesIDs: relayTeamSpeciesIDs())
            ])
            phase = .pokeathlon
        }
    }

    private func createRoom(mode: MultiplayerBattleMode, activity: RoomActivity) {
        guard phase == .idle else { return }
        phase = .creating; lastError = nil
        Task {
            guard let snapshot = await buildSnapshot() else { phase = .idle; lastError = "포켓몬 정보를 불러오지 못했습니다."; return }
            if activity == .tournament {
                guard let lineup = await buildTournamentLineup() else {
                    phase = .idle; lastError = "토너먼트에 출전할 포켓몬 3마리를 선택해 주세요."; return
                }
                tournamentTeams[myID] = lineup
            }
            mySnapshot = snapshot
            snapshots[myID] = snapshot
            let team: BattleTeam = mode == .teams ? .red : .solo
            let host = LobbyParticipant(id: myID, trainerName: trainerName, speciesID: snapshot.speciesID,
                                        team: team, isReady: false, isHost: true, role: .runner,
                                        reportedStarPieces: companion.availableTokens)
            do {
                let capacity = activity == .pokemonQuiz ? MultiplayerLobby.quizCapacity : (activity == .tournament ? 8 : 4)
                lobby = try MultiplayerLobby(host: host, capacity: capacity, activity: activity)
                hostingRole = true
                try startHosting()
                phase = .hosting
            } catch {
                hostingRole = false; phase = .idle; lobby = nil; lastError = error.localizedDescription
            }
        }
    }

    func join(_ room: MultiplayerRoomPeer, as role: LobbyRole = .runner) {
        guard phase == .idle else { return }
        phase = .joining(room.name); lastError = nil
        hostingRole = false
        Task {
            guard let snapshot = await buildSnapshot() else { phase = .idle; lastError = "포켓몬 정보를 불러오지 못했습니다."; return }
            let isTournament = room.name.hasPrefix("TOUR ·")
            if isTournament {
                guard let lineup = await buildTournamentLineup() else {
                    phase = .idle; lastError = "토너먼트에 출전할 포켓몬 3마리를 선택해 주세요."; return
                }
                tournamentTeams[myID] = lineup
            }
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
                                                           isReady: role == .spectator, isHost: false,
                                                           role: role,
                                                           reportedStarPieces: self.companion.availableTokens)
                        self.send(.join(version: MultiplayerWireMessage.protocolVersion,
                                        participant: participant, snapshot: snapshot), over: connection)
                        if isTournament, let lineup = self.tournamentTeams[self.myID] {
                            self.send(.tournamentTeam(participantID: self.myID, lineup: lineup), over: connection)
                        }
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

    /// 경기가 시작된 뒤엔 로비 편성을 건드리지 않는다 — `lobby.mode` 는 편성에서 파생되므로
    /// 배틀 중에 바뀌면 승패 판정의 근거가 흔들린다(호스트 자기 자신도 예외가 아니다).
    var isInPlay: Bool { phase == .battling || phase == .pokeathlon || phase == .pokemonQuiz || phase == .tournament }

    func toggleReady() {
        guard let me = myParticipant, !isInPlay else { return }
        if isHost {
            lobby?.setReady(!me.isReady, participantID: myID); broadcastLobby()
        } else if let hostConnection { send(.ready(participantID: myID, ready: !me.isReady), over: hostConnection) }
    }

    func selectTeam(_ team: BattleTeam) {
        guard !isInPlay, lobby?.mode == .teams || team != .solo else { return }
        if isHost { lobby?.setTeam(team, participantID: myID); broadcastLobby() }
        else if let hostConnection { send(.team(participantID: myID, team: team), over: hostConnection) }
    }

    func startBattle() {
        guard isHost, let lobby, lobby.canStart, lobby.activity == .battle else { return }
        let runners = lobby.runners
        let fighters = runners.compactMap { participant -> MultiplayerFighter? in
            guard let snapshot = snapshots[participant.id] else { return nil }
            return MultiplayerFighter(participant: participant, snapshot: snapshot)
        }
        guard fighters.count == runners.count else { lastError = "참가자 정보를 준비하지 못했습니다."; return }
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        do {
            battle = try MultiplayerBattle(fighters: fighters, mode: lobby.mode, seed: seed)
            combatFighters = fighters; combatRound = 1; combatEvents = []
            pendingActions.removeAll(); hasSubmittedAction = false; phase = .battling
            chatHistory.reset(); chatMessages = []; chatRateLimiter.reset()
            rewardedBattle = false; scheduleTurnTimeout()
            let message = MultiplayerWireMessage.start(seed: seed, fighters: fighters, mode: lobby.mode)
            for connection in guestConnections.values { send(message, over: connection) }
        } catch { lastError = error.localizedDescription }
    }

    func startPokeathlon() {
        guard isHost, let lobby, lobby.canStart, lobby.activity == .pokeathlon else { return }
        let race = PokeathlonRace(racers: lobby.runners.map {
            PokeathlonRacer(id: $0.id, trainerName: $0.trainerName, speciesID: $0.speciesID,
                            teamSpeciesIDs: [$0.speciesID, $0.speciesID, $0.speciesID])
        })
        pokeathlonRace = race; phase = .pokeathlon
        settlementPayout = nil; settledPool = false
        for connection in guestConnections.values { send(.pokeathlonStart(race: race), over: connection) }
    }

    func startPokemonQuiz() {
        guard isHost, let lobby, lobby.canStart, lobby.activity == .pokemonQuiz,
              !isPreparingPokemonQuiz else { return }
        let players = lobby.runners.map {
            PokemonOXPlayer(id: $0.id, trainerName: $0.trainerName, speciesID: $0.speciesID)
        }
        Task { await preparePokemonQuiz(players: players) }
    }

    func startTournament() {
        guard isHost, let lobby, lobby.canStart, lobby.activity == .tournament else { return }
        let runners = lobby.runners
        guard runners.count >= 2, runners.count <= 8,
              runners.allSatisfy({ tournamentTeams[$0.id]?.count == 3 }) else {
            lastError = "모든 참가자가 포켓몬 3마리의 출전 파티를 준비해야 합니다."; return
        }
        let entrants = runners.map {
            TournamentEntrant(id: $0.id, trainerName: $0.trainerName, speciesID: $0.speciesID)
        }
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        tournamentBracket = TournamentBracket(participantIDs: entrants.map(\.id), seed: seed)
        tournamentState = PokemonTournamentState(entrants: entrants,
                                                  reward: TournamentEggReward.forParticipants(entrants.count))
        tournamentRewarded = false; phase = .tournament
        startNextTournamentMatch()
    }

    func submitTournamentAction(_ action: NetBattleAction) {
        guard phase == .tournament, let match = tournamentState?.currentMatch,
              match.winnerID == nil, match.playerA == myID || match.playerB == myID else { return }
        if isHost { acceptTournamentAction(action, from: myID, matchID: match.id) }
        else if let hostConnection {
            send(.tournamentAction(matchID: match.id, participantID: myID, action: action), over: hostConnection)
        }
    }

    private func acceptTournamentAction(_ action: NetBattleAction, from participantID: UUID, matchID: UUID) {
        guard isHost, var engine = tournamentMatch, engine.id == matchID,
              engine.submit(action, from: participantID) else { return }
        tournamentMatch = engine
        tournamentState?.currentMatch = engine.snapshot()
        broadcastTournamentState()
        finishTournamentTurnIfReady()
    }

    private func finishTournamentTurnIfReady() {
        guard isHost, var engine = tournamentMatch, engine.isReady else { return }
        let winner = engine.resolveIfReady()
        tournamentMatch = engine
        tournamentState?.currentMatch = engine.snapshot(winnerID: winner)
        broadcastTournamentState()
        if let winner {
            let record = TournamentBracketMatch(id: engine.id, round: engine.round,
                                                playerA: engine.playerA.id, playerB: engine.playerB.id,
                                                winnerID: winner)
            tournamentBracket?.record(match: record)
            if let index = tournamentState?.matches.firstIndex(where: { $0.id == record.id }) {
                tournamentState?.matches[index] = record
            } else { tournamentState?.matches.append(record) }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.startNextTournamentMatch()
            }
        } else { scheduleTurnTimeout() }
    }

    private func startNextTournamentMatch() {
        guard isHost, var bracket = tournamentBracket, var state = tournamentState else { return }
        if let champion = bracket.championID {
            state.championID = champion; state.currentMatch = nil
            tournamentBracket = bracket; tournamentState = state; tournamentMatch = nil
            if champion == myID { grantTournamentRewardIfNeeded(state.reward) }
            broadcastTournamentState(); return
        }
        guard let pair = bracket.nextPair() else {
            tournamentBracket = bracket
            if let champion = bracket.championID {
                state.championID = champion; state.currentMatch = nil; tournamentState = state
                if champion == myID { grantTournamentRewardIfNeeded(state.reward) }
                broadcastTournamentState()
            }
            return
        }
        guard let a = state.entrants.first(where: { $0.id == pair.0 }),
              let b = state.entrants.first(where: { $0.id == pair.1 }),
              let teamA = tournamentTeams[a.id], let teamB = tournamentTeams[b.id] else { return }
        let engine = TournamentMatchEngine(round: bracket.round, playerA: a, playerB: b,
                                           teamA: teamA, teamB: teamB,
                                           seed: UInt64.random(in: UInt64.min...UInt64.max))
        state.currentMatch = engine.snapshot()
        state.matches.append(TournamentBracketMatch(id: engine.id, round: bracket.round,
                                                    playerA: a.id, playerB: b.id, winnerID: nil))
        tournamentBracket = bracket; tournamentState = state; tournamentMatch = engine
        phase = .tournament; scheduleTurnTimeout(); broadcastTournamentState(start: true)
    }

    private func grantTournamentRewardIfNeeded(_ reward: TournamentEggReward) {
        guard !tournamentRewarded else { return }
        tournamentRewarded = true; companion.grantTournamentEgg(reward)
    }

    private func broadcastTournamentState(start: Bool = false) {
        guard let state = tournamentState else { return }
        let message: MultiplayerWireMessage = start ? .tournamentStart(state: state) : .tournamentState(state)
        for connection in guestConnections.values { send(message, over: connection) }
    }

    private func preparePokemonQuiz(players: [PokemonOXPlayer]) async {
        guard !players.isEmpty else { return }
        isPreparingPokemonQuiz = true; lastError = nil
        defer { isPreparingPokemonQuiz = false }
        guard let facts = try? await PokeAPIClient.shared.pokemonQuizFacts() else {
            lastError = "PokéAPI에서 퀴즈 데이터를 불러오지 못했습니다. 네트워크를 확인해 주세요."
            if lobby == nil { hostingRole = false; phase = .idle }
            return
        }
        let questions = PokemonOXQuestionFactory.make(from: facts)
        guard questions.count == PokemonOXGame.questionCount else {
            lastError = "퀴즈 문제를 충분히 만들지 못했습니다. 다시 시도해 주세요."
            if lobby == nil { hostingRole = false; phase = .idle }
            return
        }
        let game = PokemonOXGame(players: players, questions: questions)
        pokemonQuizGame = game; phase = .pokemonQuiz
        broadcastPokemonQuiz(.pokemonQuizStart(game: game))
        schedulePokemonQuizTransition()
    }

    func pokemonQuizInput(_ input: PokemonOXInput) {
        guard phase == .pokemonQuiz else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPokemonQuizInputAt) >= 0.05 else { return }
        lastPokemonQuizInputAt = now
        if isHost { applyPokemonQuizInput(input, participantID: myID) }
        else if let hostConnection { send(.pokemonQuizInput(participantID: myID, input: input), over: hostConnection) }
    }

    private func applyPokemonQuizInput(_ input: PokemonOXInput, participantID: UUID) {
        guard isHost, var game = pokemonQuizGame, Date() < game.deadline else { return }
        game.move(input, playerID: participantID); pokemonQuizGame = game
        schedulePokemonQuizStateBroadcast()
    }

    private func schedulePokemonQuizStateBroadcast() {
        guard pokemonQuizBroadcastTask == nil else { return }
        pokemonQuizBroadcastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            self.pokemonQuizBroadcastTask = nil
            guard self.isHost, self.phase == .pokemonQuiz, let latest = self.pokemonQuizGame else { return }
            self.broadcastPokemonQuiz(.pokemonQuizState(game: latest))
        }
    }

    private func broadcastPokemonQuizStateImmediately(_ game: PokemonOXGame) {
        pokemonQuizBroadcastTask?.cancel(); pokemonQuizBroadcastTask = nil
        broadcastPokemonQuiz(.pokemonQuizState(game: game))
    }

    private func schedulePokemonQuizTransition() {
        pokemonQuizTask?.cancel()
        guard isHost, let game = pokemonQuizGame, !game.isFinished else { return }
        let delay = max(0, game.deadline.timeIntervalSinceNow)
        pokemonQuizTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.advancePokemonQuiz()
        }
    }

    private func advancePokemonQuiz() {
        guard isHost, var game = pokemonQuizGame else { return }
        if game.isRevealing { game.advance() } else { game.reveal() }
        pokemonQuizGame = game
        broadcastPokemonQuizStateImmediately(game)
        schedulePokemonQuizTransition()
    }

    private func broadcastPokemonQuiz(_ message: MultiplayerWireMessage) {
        for connection in guestConnections.values { send(message, over: connection) }
    }

    func pokeathlonInput(_ input: PokeathlonInput) {
        guard phase == .pokeathlon else { return }
        if isHost { applyPokeathlonInput(input, participantID: myID) }
        else if let hostConnection { send(.pokeathlonInput(participantID: myID, input: input), over: hostConnection) }
    }

    private func applyPokeathlonInput(_ input: PokeathlonInput, participantID: UUID) {
        guard isHost, var race = pokeathlonRace else { return }
        race.apply(input, racerID: participantID); pokeathlonRace = race
        closePoolIfStarted(race)
        for connection in guestConnections.values { send(.pokeathlonState(race: race), over: connection) }
        if race.winnerID != nil { settle(winnerID: race.winnerID) }
    }

    /// 관전자 베팅 전송. 호스트는 자기 검사기를 그대로 통과해야 하므로 같은 경로로 들어간다.
    ///
    /// 보내기 전에 **지금** 지갑을 확인한다. 호스트의 상한은 참가 시 신고한 잔액이라, 로비에서
    /// 별조각을 쓴 뒤 베팅하면 호스트는 통과시키지만 내 에스크로가 실패한다. 그러면 아무도 내지
    /// 않은 판돈이 배당에 섞여 별조각이 생성된다("이동만" 불변식 위반) — 여기서 먼저 막는다.
    func placeBet(runnerID: UUID, amount: Int) {
        guard phase == .pokeathlon || phase == .joined || phase == .hosting else { return }
        guard amount > 0, companion.availableTokens >= amount else {
            lastError = "별조각이 부족합니다."; return
        }
        if isHost { acceptBet(PokeathlonBet(bettorID: myID, runnerID: runnerID, amount: amount), from: myID) }
        else if let hostConnection {
            send(.pokeathlonBet(participantID: myID, runnerID: runnerID, amount: amount), over: hostConnection)
        }
    }

    /// 호스트 권위 검사 — 통과한 베팅만 원장에 들어가고, 원장 전체를 다시 브로드캐스트한다.
    private func acceptBet(_ bet: PokeathlonBet, from senderID: UUID) {
        guard isHost, let lobby, let race = pokeathlonRace else { return }
        if let rejection = PokeathlonPool.rejection(for: bet, senderID: senderID, lobby: lobby,
                                                    race: race, pool: pokeathlonPool, now: Date()) {
            if senderID == myID { lastError = Self.betRejectionText(rejection) }
            return
        }
        pokeathlonPool.bets[bet.bettorID] = bet    // 같은 관전자의 이전 베팅을 대체
        broadcastPool()
        syncEscrow()
    }

    private func broadcastPool() {
        let message = MultiplayerWireMessage.pokeathlonPool(pokeathlonPool)
        for connection in guestConnections.values { send(message, over: connection) }
    }

    private static func betRejectionText(_ rejection: PokeathlonBetRejection) -> String {
        switch rejection {
        case .identityMismatch: return "본인 ID 로만 베팅할 수 있습니다."
        case .notSpectator: return "관전자만 베팅할 수 있습니다."
        case .poolClosed: return "베팅이 마감되었습니다."
        case .invalidAmount: return "베팅 금액을 확인하세요."
        case .unknownRunner: return "이 경기에 없는 선수입니다."
        case .insufficientBalance: return "별조각이 부족합니다."
        }
    }

    /// 원장에서 내 베팅을 본 시점에 내 지갑에서 판돈을 뺀다(에스크로). 베팅을 바꿨으면
    /// 이전 판돈을 되돌리고 새 판돈을 뺀다 — 지갑이 부족해 실패하면 에스크로 기록을 남기지 않는다.
    private func syncEscrow() {
        let mine = pokeathlonPool.bets[myID]
        guard mine != escrowedBet else { return }
        if let previous = escrowedBet { companion.creditStarPieces(previous.amount) }
        if let mine, companion.escrowStarPieces(mine.amount) { escrowedBet = mine }
        else { escrowedBet = nil }
    }

    /// 출발 시각이 지나면 원장을 잠근다. 검사기도 시각을 보지만, 잠금 사실을 관전자 화면에
    /// 반영하려면 원장 플래그가 함께 브로드캐스트돼야 한다.
    private func closePoolIfStarted(_ race: PokeathlonRace) {
        guard isHost, !pokeathlonPool.isClosed, Date() >= race.startsAt else { return }
        pokeathlonPool.isClosed = true
        broadcastPool()
    }

    /// 호스트 정산 — 원장과 우승자를 함께 보내고, 각 클라이언트가 배당을 재계산한다.
    /// 우승자 없이 방이 닫히면 `winnerID: nil` 로 보내 전원 환불이 된다.
    private func settle(winnerID: UUID?) {
        guard isHost, !settledPool else { return }
        settledPool = true
        pokeathlonPool.isClosed = true
        let message = MultiplayerWireMessage.pokeathlonSettlement(pool: pokeathlonPool, winnerID: winnerID)
        for connection in guestConnections.values { send(message, over: connection) }
        applySettlement(pool: pokeathlonPool, winnerID: winnerID)
    }

    /// 정산 적용(호스트·게스트 공통). 호스트가 보낸 원장이 내가 본 내 베팅과 다르면 지급을 거부한다.
    private func applySettlement(pool: PokeathlonPool, winnerID: UUID?) {
        guard escrowedBet != nil || !pool.bets.isEmpty else { return }
        guard pool.agreesWithSeenBet(escrowedBet, bettorID: myID) else {
            lastError = "정산 내역이 내가 건 베팅과 다릅니다. 지급을 거부했습니다."
            return
        }
        pokeathlonPool = pool
        let payout = pool.payouts(winnerID: winnerID)[myID] ?? 0
        companion.creditStarPieces(payout)
        settlementPayout = payout
        escrowedBet = nil
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

    /// 판정에 쓸 모드 — **배틀이 시작될 때 정해진 모드**다. 호스트·게스트·관전자 모두 `.start` 시점의
    /// `battle` 을 들고 있어 같은 답이 나온다.
    ///
    /// `lobby.mode` 를 먼저 보면 안 된다 — 팀 편성에서 파생되는 **가변값**이라(`runners` 가 전부
    /// `solo` 인가) 배틀 중에 바뀔 수 있고, 바뀌면 승패 판정 자체가 흔들린다. 개인전 도중 누군가 팀을
    /// `red` 로 바꾸면 남은 `solo` 들이 "한 팀"으로 묶여 여럿이 살아 있는데 배틀이 끝난 것으로 판정되고
    /// 생존자 전원이 승리가 된다. 편성은 이제 경기 중엔 바뀌지 않지만(`isInPlay` 게이트) 판정의 근거는
    /// 애초에 불변인 쪽이어야 한다.
    ///
    /// 화면도 이 값을 쓴다 — 팀 배지·공격 대상 필터가 `lobby?.mode` 를 따로 보면 판정과 갈라진다.
    /// 폴백은 `battle` 을 못 만든 경우의 최후 수단이다(그 상태면 `combatFighters` 도 비어 있어
    /// 판정 자체가 성립하지 않는다).
    var combatMode: MultiplayerBattleMode {
        battle?.mode ?? lobby?.mode ?? .freeForAll
    }

    var isBattleFinished: Bool {
        MultiplayerBattle.isFinished(fighters: combatFighters, mode: combatMode)
    }

    /// 내 승패. `nil` 은 "줄 결과가 없다" — 아직 안 끝났거나 전투원이 아니다(관전자).
    /// 팀전은 내 생존이 아니라 **내 팀**이 이겼는지고, 동시 전멸은 `.draw` 다. 화면이 이 네 갈래를
    /// 그대로 쓴다 — `Bool` 하나로 갈랐을 때는 관전자와 무승부가 "패배"로 표시됐다.
    var myOutcome: BattleOutcome? {
        MultiplayerBattle.outcome(for: myID, fighters: combatFighters, mode: combatMode)
    }

    func leaveRoom() {
        if isHost, pokeathlonRace != nil, !settledPool { settle(winnerID: pokeathlonRace?.winnerID) }
        else if !isHost, let escrowed = escrowedBet {
            // 호스트 정산을 못 받고 방을 떠나면 자기 판돈은 스스로 되돌린다(경기 미완주 = 환불).
            companion.creditStarPieces(escrowed.amount); escrowedBet = nil
        }
        if !isHost, let hostConnection { send(.leave(participantID: myID), over: hostConnection) }
        hostConnection?.cancel(); hostConnection = nil
        guestConnections.values.forEach { $0.cancel() }; guestConnections.removeAll()
        pendingGuestConnections.values.forEach { $0.cancel() }; pendingGuestConnections.removeAll()
        listener?.cancel(); listener = nil
        turnTimeoutTask?.cancel(); turnTimeoutTask = nil
        pokemonQuizTask?.cancel(); pokemonQuizTask = nil
        pokemonQuizBroadcastTask?.cancel(); pokemonQuizBroadcastTask = nil
        lobby = nil; mySnapshot = nil; snapshots.removeAll(); battle = nil; pokeathlonRace = nil
        pokemonQuizGame = nil; isPreparingPokemonQuiz = false; lastPokemonQuizInputAt = .distantPast
        tournamentState = nil; tournamentTeams.removeAll(); tournamentBracket = nil
        tournamentMatch = nil; tournamentRewarded = false
        pokeathlonPool = PokeathlonPool(); escrowedBet = nil; settlementPayout = nil; settledPool = false
        pendingActions.removeAll(); combatFighters = []; combatEvents = []; combatRound = 0
        turnEndsAt = nil; rewardedBattle = false
        hasSubmittedAction = false; hostingRole = false; phase = .idle
        chatHistory.reset(); chatMessages = []; chatRateLimiter.reset()
    }

    private func startHosting() throws {
        let listener = try NWListener(using: Self.parameters())
        let prefix: String
        switch lobby?.activity {
        case .pokeathlon: prefix = "RUN"
        case .pokemonQuiz: prefix = "QUIZ"
        case .tournament: prefix = "TOUR"
        default: prefix = "BATTLE"
        }
        listener.service = NWListener.Service(name: "\(prefix) · \(trainerName)#\(String(myID.uuidString.prefix(6)))",
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
        let maxGuests: Int
        switch lobby?.activity {
        case .pokemonQuiz: maxGuests = MultiplayerLobby.quizCapacity - 1
        case .tournament: maxGuests = 7
        default: maxGuests = 3 + MultiplayerLobby.spectatorCapacity
        }
        guard isHost, guestConnections.count + pendingGuestConnections.count < maxGuests else {
            connection.cancel(); return
        }
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
            // 준비·팀 변경은 **로비에서만** 받는다. 경기 중에 받으면 `lobby.mode` 가 바뀌어 승패 판정이
            // 흔들린다 — 개인전 중 한 명이 팀을 바꾸면 남은 `solo` 들이 한 팀으로 묶여 살아 있는 채로
            // "종료 + 전원 승리"가 됐다. 편성은 상대가 보내오는 값이므로 화면에서 버튼을 감추는 것으로는
            // 막지 못한다.
            case .ready(let pid, let ready) where pid == id && !self.isInPlay:
                self.lobby?.setReady(ready, participantID: pid); self.broadcastLobby()
            case .team(let pid, let team) where pid == id && !self.isInPlay:
                self.lobby?.setTeam(team, participantID: pid); self.broadcastLobby()
            case .leave(let pid) where pid == id:
                if self.phase == .battling { self.retireFighter(pid) }
                else { try? self.lobby?.leave(participantID: pid) }
                self.snapshots.removeValue(forKey: pid); self.guestConnections.removeValue(forKey: pid)
                connection.cancel(); self.broadcastLobby(); return
            case .action(let round, let action) where action.attackerID == id && round == self.combatRound:
                if let id { self.acceptAction(action, from: id) }
            case .chat(let message) where message.senderID == id:
                if let id { self.acceptChat(message, from: id) }
            case .pokeathlonInput(let pid, let input) where pid == id:
                self.applyPokeathlonInput(input, participantID: pid)
            case .pokemonQuizInput(let pid, let input) where pid == id:
                self.applyPokemonQuizInput(input, participantID: pid)
            case .tournamentTeam(let pid, let lineup) where pid == id:
                guard self.lobby?.activity == .tournament,
                      self.validTournamentLineup(lineup, participantID: pid) else {
                    self.send(.rejected(reason: "잘못된 토너먼트 파티입니다."), over: connection); return
                }
                self.tournamentTeams[pid] = lineup
            case .tournamentAction(let matchID, let pid, let action) where pid == id:
                self.acceptTournamentAction(action, from: pid, matchID: matchID)
            case .pokeathlonBet(let pid, let runnerID, let amount) where pid == id:
                self.acceptBet(PokeathlonBet(bettorID: pid, runnerID: runnerID, amount: amount), from: pid)
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
                self.chatHistory.reset(); self.chatMessages = []; self.chatRateLimiter.reset()
                self.turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
                self.phase = .battling
            case .roundResolved(let round, let fighters, let events):
                guard self.phase == .battling, round == self.combatRound else { return }
                self.combatFighters = fighters; self.combatEvents = events
                self.combatRound += 1; self.hasSubmittedAction = false
                self.turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
                self.grantRewardIfFinished()
            case .chat(let message): self.acceptRelayedChat(message)
            case .pokeathlonStart(let race): self.pokeathlonRace = race; self.phase = .pokeathlon
            case .pokeathlonState(let race) where self.phase == .pokeathlon: self.pokeathlonRace = race
            case .pokeathlonPool(let pool):
                self.pokeathlonPool = pool
                self.syncEscrow()
            case .pokeathlonSettlement(let pool, let winnerID):
                self.applySettlement(pool: pool, winnerID: winnerID)
            case .pokemonQuizStart(let game): self.pokemonQuizGame = game; self.phase = .pokemonQuiz
            case .pokemonQuizState(let game) where self.phase == .pokemonQuiz: self.pokemonQuizGame = game
            case .tournamentStart(let state):
                self.tournamentState = state; self.phase = .tournament
                self.turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
            case .tournamentState(let state) where self.phase == .tournament:
                let previousTurn = self.tournamentState?.currentMatch?.turn
                self.tournamentState = state
                if state.championID == self.myID { self.grantTournamentRewardIfNeeded(state.reward) }
                if state.currentMatch?.turn != previousTurn {
                    self.turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
                }
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

    /// 호스트가 연결에 묶인 참가자 ID를 기준으로 발신자를 인증하고, 전투 중인 방에만 전달한다.
    private func acceptChat(_ incoming: BattleChatMessage, from participantID: UUID) {
        guard phase == .battling, incoming.senderID == participantID,
              let participant = lobby?.participants.first(where: { $0.id == participantID }),
              let body = BattleChatPolicy.normalizedBody(incoming.body),
              let name = BattleChatPolicy.displayName(participant.trainerName),
              chatRateLimiter.allows(participantID) else { return }
        // `id` 는 상대가 고른 값이라 새로 짓는다 — 같은 값을 두 번 보내면 `ForEach` 가 무너진다.
        let message = BattleChatMessage(senderID: participantID, senderName: name,
                                        body: body, sentAt: incoming.sentAt)
        chatHistory.append(message); chatMessages = chatHistory.messages
        for connection in guestConnections.values { send(.chat(message), over: connection) }
    }

    /// 호스트가 중계한 한 줄. **호스트도 상대다** — 우리는 호스트가 무엇을 걸렀는지 볼 수 없으므로
    /// 게스트 쪽에서도 같은 경계를 다시 친다. `senderID` 는 그대로 둔다(호스트가 참가자에 묶어
    /// 인증한 값이고, 내가 보낸 말도 이 중계로 되돌아온다). `id` 는 새로 짓는다 — 중계된 값이
    /// 되풀이되면 화면의 `ForEach` 가 중복 키로 무너진다.
    func acceptRelayedChat(_ incoming: BattleChatMessage) {
        guard let body = BattleChatPolicy.normalizedBody(incoming.body), body == incoming.body,
              let name = BattleChatPolicy.displayName(incoming.senderName) else { return }
        chatHistory.append(BattleChatMessage(senderID: incoming.senderID, senderName: name,
                                             body: body, sentAt: incoming.sentAt))
        chatMessages = chatHistory.messages
    }

    func sendChat(_ body: String) {
        guard phase == .battling, let normalized = BattleChatPolicy.normalizedBody(body) else { return }
        let message = BattleChatMessage(senderID: myID, senderName: trainerName, body: normalized)
        if isHost { acceptChat(message, from: myID) }
        else if let hostConnection { send(.chat(message), over: hostConnection) }
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
            // 거절된 라운드에도 마감을 다시 건다. 이게 없으면 게스트가 보낸 엉뚱한 targetID 하나로
            // 방이 영구히 멈춘다(마감 경로에서 throw 가 나면 다시 걸릴 타이머가 없다).
            scheduleTurnTimeout()
        }
    }

    private func scheduleTurnTimeout() {
        turnTimeoutTask?.cancel()
        let round = phase == .tournament ? (tournamentState?.currentMatch?.turn ?? 0) : combatRound
        turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
        turnTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.turnDuration))
            guard !Task.isCancelled else { return }
            self?.fillTimedOutActions(round: round)
        }
    }

    private func fillTimedOutActions(round: Int) {
        if phase == .tournament {
            guard isHost, var engine = tournamentMatch,
                  tournamentState?.currentMatch?.turn == round else { return }
            engine.fillMissingActions(); tournamentMatch = engine
            tournamentState?.currentMatch = engine.snapshot()
            finishTournamentTurnIfReady()
            return
        }
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
            retireFighter(id)
        } else {
            // 관전자가 떠나도 원장은 그대로 둔다 — 판돈은 이미 그 관전자 지갑에서 빠졌고,
            // 정산은 우승자 기준으로 계산되므로 남은 참가자들의 배당이 흔들리지 않는다.
            try? lobby?.leave(participantID: id); broadcastLobby()
        }
    }

    /// 배틀 중 이탈한 참가자를 쓰러진 것으로 처리한다 — 명시적 `.leave` 와 연결 끊김이 **같은 자리**를
    /// 지나야 한다. `.leave` 쪽에만 마감 처리가 없던 동안 상대가 "나가기"를 누르면 화면은 결과로
    /// 넘어가는데 전적이 남지 않았고(`grantRewardIfFinished` 미호출) 게스트에게 최종 상태도 가지 않았다.
    /// 게다가 내가 그 라운드에 행동을 안 냈으면 `finishRoundIfReady` 가 조용히 빠져 마감 타이머도
    /// 다시 걸리지 않아 방이 멈췄다.
    private func retireFighter(_ id: UUID) {
        battle?.forfeit(participantID: id)
        combatFighters = battle?.fighters ?? combatFighters
        pendingActions.removeValue(forKey: id)
        if battle?.isFinished == true {
            turnTimeoutTask?.cancel(); turnEndsAt = nil
            grantRewardIfFinished(); broadcastCombatState()
        } else { finishRoundIfReady() }
    }

    private func grantRewardIfFinished() {
        // 관전자는 전투원 목록에 없어 `outcome` 이 nil 이다 — 예전엔 관전자도 이 자리를 타서
        // 싸우지도 않은 배틀의 패배 기록이 남았다.
        guard !rewardedBattle,
              let outcome = MultiplayerBattle.outcome(for: myID, fighters: combatFighters,
                                                      mode: combatMode) else { return }
        rewardedBattle = true
        // 별의조각은 지급하지 않는다 — 전적만 남긴다. 예전엔 여기서 표시용 보상액을 계산해
        // 화면이 "+20 ✨"을 띄웠는데 `grantBattleReward` 는 아무것도 지급하지 않았다.
        let won = outcome == .win, count = combatFighters.count
        // 기록에 남는 모드도 판정과 **같은 근거**를 쓴다 — `lobby?.mode` 를 여기만 남겨 두면 판정은
        // 팀전인데 전적은 개인전으로 적히는 자리가 다시 생긴다.
        let mode = combatMode
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
        connection.send(content: frame, completion: .contentProcessed { error in
            if let error { AppLog.write("multiplayer send failed: \(error)") }
        })
    }

    private func receive(over connection: NWConnection, completion: @escaping @MainActor (MultiplayerWireMessage) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, _ in
            guard let data, data.count == 4 else { Task { @MainActor in connection.cancel() }; return }
            let length = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
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

    private func relayTeamSpeciesIDs() -> [Int] {
        var ids = companion.state.active.map { [$0.currentID] } ?? []
        ids.append(contentsOf: companion.boxedMons.prefix(2).map(\.currentID))
        guard let fallback = ids.first else { return [] }
        while ids.count < 3 { ids.append(fallback) }
        return Array(ids.prefix(3))
    }

    private func buildSnapshot() async -> BattleSnapshot? {
        await companion.ensureInheritedMoves()
        guard let active = companion.state.active, let speciesID = companion.currentSpeciesID,
              let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID) else { return nil }
        let level = active.level
        let moves = active.learnedMoves.isEmpty
            ? await PokeAPIClient.shared.moveSet(speciesID: speciesID, level: level, types: profile.types)
            : await companion.detailedMoves(of: active)
        return BattleSnapshot(speciesID: speciesID, name: companion.displayName, trainer: trainerName,
                              level: level, nature: active.nature, isShiny: active.isShiny,
                              types: profile.types, base: profile.stats, moves: moves,
                              ability: profile.abilitySlug,
                              weightHectograms: profile.weightHectograms)
    }

    private func buildTournamentLineup() async -> [BattleSnapshot]? {
        await companion.ensureInheritedMoves()
        let owned = companion.ownedMons
        let ids = tournamentPickedTeam.filter { id in owned.contains(where: { $0.id == id }) }
        guard ids.count == 3 else { return nil }
        var lineup: [BattleSnapshot] = []
        for id in ids {
            guard let mon = owned.first(where: { $0.id == id }),
                  let snapshot = await companion.battleSnapshot(for: mon, level: 50) else { return nil }
            lineup.append(snapshot)
        }
        return lineup
    }

    private func validTournamentLineup(_ lineup: [BattleSnapshot], participantID: UUID) -> Bool {
        guard lineup.count == 3, lineup.allSatisfy({ $0.level == 50 }),
              let participant = lobby?.participants.first(where: { $0.id == participantID }) else { return false }
        return lineup.allSatisfy { snapshot in
            MultiplayerValidation.valid(
                participant: LobbyParticipant(id: participant.id, trainerName: participant.trainerName,
                                              speciesID: snapshot.speciesID, team: .solo,
                                              isReady: true, isHost: false),
                snapshot: snapshot)
        }
    }

    private func restartBrowser() { browser?.cancel(); browser = nil; startBrowsing() }
    private nonisolated static func parameters() -> NWParameters { let p = NWParameters.tcp; p.includePeerToPeer = true; return p }
    private nonisolated static func displayName(_ service: String) -> String {
        service.split(separator: "#", maxSplits: 1).first.map(String.init) ?? service
    }
}
