import Foundation
import Network
import Observation
import UserNotifications

struct MultiplayerRoomPeer: Identifiable, Equatable {
    let id: String
    /// 사람에게 보여줄 이름 — `#식별자` 를 떼어 낸 값이다.
    let name: String
    /// Bonjour 서비스 이름 **원문**. 식별자(`#앞6자리`)와 체육관이 실어 보낸 재임 시각이 여기 있다.
    ///
    /// `name` 은 `#` 앞에서 잘려 있으므로 **판정에 쓰면 안 된다.** 실제로 그렇게 썼다가 내 방을
    /// 남의 방으로 읽어(식별자가 잘려 비교가 늘 실패) 자기 체육관에 "이미 열린 체육관이 있습니다"
    /// 를 띄웠다.
    let serviceName: String
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
    /// 방 하나의 수명 번호. `leaveRoom()` 이 올린다.
    ///
    /// 개설·참가는 `await` 를 지나 끝나는데, 그 사이 사용자는 나가기를 누를 수 있고 체육관 타이머도
    /// `leaveRoom()` 을 부른다. 깨어난 작업이 국면만 보면 정리가 끝난 뒤에 새 listener 를 세워
    /// **닫았다고 믿는 방이 LAN 에 그대로 남는다**(이후 개설·참가는 `guard phase == .idle` 에서 전부
    /// 조용히 거절된다). 국면 대신 이 번호를 비교하는 이유는, 나갔다가 곧바로 다시 개설하면 국면이
    /// 같은 값으로 돌아와 옛 작업이 새 작업을 덮어쓰기 때문이다.
    private var sessionEpoch = 0
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
    var tournamentFinalTeam: [UUID] = []
    private(set) var tournamentState: PokemonTournamentState?
    private(set) var tournamentPools: [UUID: [BattleSnapshot]] = [:]
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

    // MARK: 공유 체육관

    /// 도전할 때 데려갈 넷. 토너먼트 선택(3마리)과 정원이 달라 배열을 따로 둔다 — 하나로 묶으면
    /// 한쪽 화면에서 고른 것이 다른 쪽 정원에 맞지 않아 조용히 잘린다.
    var gymPickedTeam: [UUID] = []
    /// 지금 진행 중인 체육관 한 판 — 관장·도전자·관전자가 모두 이 값을 그린다.
    private(set) var gymMatch: GymMatchState?
    /// 호스트(관장)만 드는 권위형 엔진. 게스트는 위 스냅샷만 본다.
    private var gymEngine: GymMatchEngine?
    /// 도전자가 보내온 출전팀 — 관장이 수락할 때까지 들고 있는다.
    private var gymChallengerLineup: [BattleSnapshot]?
    /// 도전이 거절된 사유(게스트 쪽 표시용).
    private(set) var gymRejection: GymChallengeRejection?
    /// 배틀 중 관장이 사라졌다 — 도전자에게 "이어받기"를 제안하는 신호.
    private(set) var gymLeaderAbandonedMatch = false
    /// 직전 방어로 받은 별의조각. 0 이면 하루 상한에 걸린 것이다(지키지 못한 것이 아니다).
    private(set) var lastGymDefensePayout: Int?
    /// 끝난 판을 치우는 예약. 결과 화면을 잠깐 보여 준 뒤 다음 도전을 받을 수 있게 한다.
    private var gymMatchClearTask: Task<Void, Never>?
    /// 입장하자마자 도전을 보낼 것인가 — 입장은 비동기라 로비를 받은 뒤에 보내야 한다.
    private var pendingGymChallenge = false
    /// 체육관 방을 연 직후 호출된다. 동시 개설 경합 확인을 이 훅으로 건다(화면이 붙인다).
    var onGymRoomOpened: (() -> Void)?
    /// 관장 자리를 넘겨받았다 — 화면이 자기 세이브에 자격을 쓰도록 알린다.
    var onGymLeadershipWon: ((UUID) -> Void)?
    /// 관장 자리를 잃었다.
    var onGymLeadershipLost: (() -> Void)?

    // MARK: LAN 협동 레이드 (#80)

    /// 이 방의 티어. 호스트는 방을 열 때, 게스트는 `.raidStart` 를 받을 때 채운다.
    private(set) var raidTier: RaidTier?
    /// 참가자별 보스에게 넣은 피해. 호스트는 매 라운드 갱신하고, 게스트는 정산 메시지로 한 번 받는다.
    private(set) var raidContributions: [UUID: Int] = [:]
    /// 내 정산 내역 — 화면이 항목별로 그린다(지갑을 바꾼 값은 그 자리에서 설명돼야 한다).
    private(set) var raidSettlement: RaidSettlement?
    /// 이번 판이 실제로 지급한 금액. 하루 한 번 게이트에 걸리면 0 이고, 화면은 그 사실을 말한다.
    private(set) var raidPayout: Int?
    /// 보스가 죽은(혹은 파티가 전멸한) 라운드. 남은 턴 보너스가 이 값을 읽는다.
    private var raidFinishedRound: Int?
    private var settledRaid = false
    /// 이미 알림을 낸 레이드 방 이름 — 브라우저가 같은 목록을 반복해서 주므로 필요하다.
    private var announcedRaidRooms: [String] = []
    /// 부화 알림을 이미 건 조합(날짜 키 + 토글 상태). 60초 틱이 부르는 자리라 재작업을 막는다.
    private var scheduledHatchKey = ""

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

    /// 지금 방이 무엇을 하고 있나. 화면 갈림길이 이 값을 본다 — `phase` 만 보면 방이 켜졌다는 것만
    /// 알 뿐 토너먼트인지 체육관인지 알 수 없어 한쪽이 다른 쪽 화면을 가로챈다.
    var roomActivity: RoomActivity? { lobby?.activity }
    var isGymRoom: Bool { lobby?.activity == .gym }

    var isHost: Bool { hostingRole }
    var myParticipant: LobbyParticipant? { lobby?.participants.first { $0.id == myID } }
    var amSpectator: Bool { myParticipant?.role == .spectator }
    var myBet: PokeathlonBet? { pokeathlonPool.bets[myID] }

    /// 방 탐색이 돌고 있나. 꺼져 있으면(설정에서 LAN 배틀을 끈 경우) 아무리 기다려도 방이
    /// 나타나지 않으므로, 화면이 "검색 중" 대신 그 사실을 말해야 한다.
    var isBrowsing: Bool { browser != nil }

    /// LAN 에 **새로 뜬 남의 레이드 방**. 알림을 낼지 정하는 자리다.
    ///
    /// 이슈가 "discovery is the real gate" 라고 부른 지점 — 알림이 없으면 기본 경험은 방을 열고
    /// 혼자 시간이 초과되는 것이다. 세 가지를 걸러야 한다: 레이드가 아닌 방, **내 방**,
    /// 그리고 **이미 알린 방**(브라우저는 인터페이스가 흔들릴 때마다 같은 목록을 다시 준다).
    ///
    /// `nonisolated static` 인 이유는 `creditsRaceFinish` 와 같다 — 네트워크 없이 전 분기를
    /// 검증하려고 순수 함수로 떼어 둔다.
    nonisolated static func newlyVisibleRaidRooms(previous: [String], current: [String],
                                                  myIDTag: String) -> [String] {
        let seen = Set(previous)
        return current.filter { name in
            guard RaidRoomName.isRaidRoomName(name), !seen.contains(name) else { return false }
            // **원문으로 본다.** `name`(표시용)은 `#` 앞에서 잘려 있어 내 방을 걸러낼 수 없다.
            return RaidRoomName.parse(name)?.idTag != myIDTag
        }
    }

    func startBrowsing() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: Self.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let peers = results.compactMap { result -> MultiplayerRoomPeer? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return MultiplayerRoomPeer(id: name, name: Self.displayName(name),
                                           serviceName: name, endpoint: result.endpoint)
            }
            Task { @MainActor in
                guard let self else { return }
                self.rooms = peers.sorted { $0.name < $1.name }
                self.announceNewRaidRooms(self.rooms.map(\.serviceName))
            }
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

    /// 체육관을 연다 — **이미 열린 체육관이 보이면 열지 않는다.** 중앙 권위가 없어 프로토콜로는
    /// 못 막지만, 개설 경로에서 걸러 내면 정상 사용에서는 하나로 유지된다.
    ///
    /// 발견은 즉시가 아니므로 둘이 동시에 눌러 둘 다 열릴 수 있다. 그 경합은 개설 직후
    /// `resolveGymRoomConflict()` 가 흡수한다.
    func createGymRoom() {
        guard gymRoomHoldingTheSlot == nil else { lastError = companion.l.playerGymAlreadyOpen; return }
        createRoom(mode: .freeForAll, activity: .gym)
    }

    /// 지금 보이는 남의 체육관 방(내 것은 제외). **붙을 수 있는 방을 먼저** 고른다 — 구버전 방이
    /// 목록 앞에 있다고 그것만 보여 주면, 바로 옆에 있는 멀쩡한 체육관을 못 찾는다.
    var visibleGymRoom: MultiplayerRoomPeer? {
        // **원문**(`serviceName`)으로 본다. `name` 은 `#` 앞에서 잘려 있어 내 방을 걸러낼 수 없다.
        let gyms = rooms.filter { PlayerGym.isGymRoomName($0.serviceName) && !$0.serviceName.contains(myIDTag) }
        return gyms.first { compatibility(of: $0).allowsChallenge } ?? gyms.first
    }

    /// **체육관 한 자리를 이미 차지하고 있는 방.** 개설 차단·자격 양보·경합 판정이 모두 이걸 본다.
    ///
    /// 상대 앱이 낮은 방은 자리를 차지하지 못한다 — 그렇게 세면 구버전 한 대가 최신 사용자
    /// 전원의 체육관을 잠근다(붙지도 못하는 방 때문에 아무도 못 연다).
    var gymRoomHoldingTheSlot: MultiplayerRoomPeer? {
        rooms.first {
            PlayerGym.isGymRoomName($0.serviceName) && !$0.serviceName.contains(myIDTag)
                && compatibility(of: $0).blocksOpeningMyGym
        }
    }

    /// 화면에 보여 줄 방과 내 앱의 관계. 도전 버튼과 안내 문구가 이 값을 고른다.
    var visibleGymCompatibility: GymRoomCompatibility? {
        visibleGymRoom.map(compatibility(of:))
    }

    /// **내 앱이 체육관을 쓰기엔 낮은가.** 보이는 체육관 중 하나라도 나보다 높은 프로토콜을
    /// 광고하면 참이다 — 그 상태에서는 도전도 개설도 막고 업데이트를 안내한다.
    var isOutdatedForGym: Bool {
        rooms.contains {
            PlayerGym.isGymRoomName($0.serviceName) && !$0.serviceName.contains(myIDTag)
                && compatibility(of: $0) == .myAppIsOutdated
        }
    }

    private func compatibility(of room: MultiplayerRoomPeer) -> GymRoomCompatibility {
        PlayerGym.compatibility(roomVersion: PlayerGymRoomName.parse(room.serviceName)?.protocolVersion)
    }

    /// 내 방을 남의 목록에서 가려내는 꼬리표 — 방 이름에 이미 들어 있다(`startHosting`).
    private var myIDTag: String { "#\(myRoomTag)" }

    /// 방 이름 끝에 실리는 내 식별자(`#` 없이). 경합 판정이 남의 꼬리표(`PlayerGymRoomName.idTag`)와
    /// **같은 형식으로** 비교해야 해서 밖으로 낸다.
    var myRoomTag: String { String(myID.uuidString.prefix(6)) }

    func startSoloPokemonQuiz() {
        guard phase == .idle else { return }
        phase = .creating; lastError = nil
        let epoch = sessionEpoch
        Task {
            guard let snapshot = await buildSnapshot() else {
                guard sessionEpoch == epoch else { return }
                phase = .idle; lastError = "포켓몬 정보를 불러오지 못했습니다."; return
            }
            guard sessionEpoch == epoch else { return }
            hostingRole = true; lobby = nil
            await preparePokemonQuiz(players: [PokemonOXPlayer(id: myID, trainerName: trainerName,
                                                               speciesID: snapshot.speciesID)])
        }
    }

    func startSoloPokeathlon() {
        guard phase == .idle else { return }
        lastError = nil
        phase = .creating
        let epoch = sessionEpoch
        Task {
            guard let snapshot = await buildSnapshot() else {
                guard sessionEpoch == epoch else { return }
                phase = .idle
                lastError = "포켓몬 정보를 불러오지 못했습니다."
                return
            }
            guard sessionEpoch == epoch else { return }
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
        let epoch = sessionEpoch
        Task {
            guard let snapshot = await buildSnapshot() else {
                guard sessionEpoch == epoch else { return }
                phase = .idle; lastError = "포켓몬 정보를 불러오지 못했습니다."; return
            }
            guard sessionEpoch == epoch else { return }
            if activity == .tournament {
                guard let pool = await buildTournamentLineup(ids: tournamentPickedTeam, count: 6) else {
                    guard sessionEpoch == epoch else { return }
                    phase = .idle; lastError = "토너먼트 후보 포켓몬 6마리를 선택해 주세요."; return
                }
                guard sessionEpoch == epoch else { return }
                tournamentPools[myID] = pool
                tournamentTeams.removeValue(forKey: myID)
                tournamentFinalTeam = []
            }
            mySnapshot = snapshot
            snapshots[myID] = snapshot
            let team: BattleTeam = mode == .teams ? .red : .solo
            let host = LobbyParticipant(id: myID, trainerName: trainerName, speciesID: snapshot.speciesID,
                                        team: team, isReady: false, isHost: true, role: .runner,
                                        reportedStarPieces: companion.availableTokens)
            do {
                let capacity: Int
                switch activity {
                case .pokemonQuiz: capacity = MultiplayerLobby.quizCapacity
                case .tournament: capacity = 8
                // 관장과 도전자 둘이 러너다. 나머지는 관전자 정원으로 들어온다.
                case .gym: capacity = 2
                default: capacity = 4
                }
                lobby = try MultiplayerLobby(host: host, capacity: capacity, activity: activity)
                hostingRole = true
                try startHosting()
                phase = .hosting
                if activity == .gym { onGymRoomOpened?() }
            } catch {
                hostingRole = false; phase = .idle; lobby = nil; lastError = error.localizedDescription
            }
        }
    }

    // MARK: 레이드 — 방 열기부터 정산까지

    /// 오늘의 보스를 상대로 방을 연다. 티어는 사용자가 고른다(보스 자체는 못 고른다).
    func createRaidRoom(tier: RaidTier) {
        raidTier = tier
        createRoom(mode: .coopBoss, activity: .raid)
    }

    /// 오늘의 보스. 방을 열기 전 화면이 미리 그린다.
    nonisolated var todaysRaidSpeciesID: Int {
        RaidBoss.speciesID(dayKey: CompanionStore.dayKey(Date()))
    }

    /// 호스트가 판을 연다 — 러너를 파티 레벨로 눕히고 오늘의 보스를 세운다.
    ///
    /// **레벨을 여기서 눕히는 것이 중요하다.** 참가자가 보낸 스냅샷은 자기 레벨 그대로라
    /// (`buildSnapshot`), 눕히지 않으면 레벨 100 파티가 5★ 를 세 턴에 끝낸다. 체육관·토너먼트가
    /// 같은 자리에서 같은 일을 한다.
    func startRaid() {
        guard isHost, let lobby, lobby.activity == .raid, lobby.canStart,
              let tier = raidTier else { return }
        let dayKey = CompanionStore.dayKey(Date())
        Task {
            guard let bossSnapshot = await raidBossSnapshot(tier: tier, dayKey: dayKey) else {
                lastError = companion.l.raidBossLoadFailed; return
            }
            let runners = lobby.runners.compactMap { participant -> MultiplayerFighter? in
                guard var snapshot = snapshots[participant.id] else { return nil }
                snapshot.level = RaidBoss.partyLevel
                var raider = participant
                raider.team = .red
                return MultiplayerFighter(participant: raider, snapshot: snapshot)
            }
            let fighters = runners + [RaidBoss.bossFighter(tier: tier, snapshot: bossSnapshot)]
            let seed = UInt64.random(in: UInt64.min...UInt64.max)
            // 호스트도 자기가 만든 편성을 검사한다 — 여기가 통과 못 하면 게스트도 거절할 편성이라
            // 방이 절반만 시작된 상태로 갈라진다.
            guard RaidBoss.validRaidStart(fighters: fighters, tier: tier, dayKey: dayKey),
                  let started = try? MultiplayerBattle(fighters: fighters, mode: .coopBoss, seed: seed) else {
                lastError = companion.l.raidBossLoadFailed; return
            }
            battle = started
            beginRaidCombat(fighters: fighters)
            let message = MultiplayerWireMessage.raidStart(seed: seed, fighters: fighters, tier: tier)
            for connection in guestConnections.values { send(message, over: connection) }
            injectBossActionIfNeeded()
            scheduleTurnTimeout()
        }
    }

    /// 개시 상태를 세운다 — 호스트와 게스트가 **같은 자리**를 지나야 한 쪽만 초기화를 빠뜨리지 않는다.
    private func beginRaidCombat(fighters: [MultiplayerFighter]) {
        combatFighters = fighters; combatRound = 1; combatEvents = []
        hasSubmittedAction = false; rewardedBattle = false
        raidContributions = [:]; raidSettlement = nil; raidPayout = nil
        raidFinishedRound = nil; settledRaid = false
        chatHistory.reset(); chatMessages = []; chatRateLimiter.reset()
        turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
        phase = .battling
    }

    private func raidBossSnapshot(tier: RaidTier, dayKey: String) async -> BattleSnapshot? {
        let speciesID = RaidBoss.speciesID(dayKey: dayKey)
        guard let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID) else { return nil }
        let moves = await PokeAPIClient.shared.moveSet(speciesID: speciesID, level: tier.bossLevel,
                                                       types: profile.types)
        return BattleSnapshot(speciesID: speciesID, name: await companion.resolveSpeciesName(speciesID),
                              trainer: nil, level: tier.bossLevel, nature: nil, isShiny: false,
                              types: profile.types, base: profile.stats, moves: moves,
                              ability: profile.abilitySlug, weightHectograms: profile.weightHectograms)
    }

    /// 보스 몫을 채운다. **호스트만** 부르고, 라운드가 열릴 때마다 지나야 한다 — 안 채우면
    /// `finishRoundIfReady` 가 영원히 "행동이 덜 모였다"로 빠져 방이 마감 타이머에만 의존한다.
    private func injectBossActionIfNeeded() {
        guard isHost, phase == .battling, combatMode == .coopBoss,
              pendingActions[RaidBoss.bossID] == nil,
              let action = MultiplayerBattle.bossAction(fighters: combatFighters) else { return }
        pendingActions[RaidBoss.bossID] = action
    }

    /// 턴 상한을 지났으면 판을 닫는다. 호스트 전용이고, 라운드가 해상된 직후에 지난다.
    private func endRaidIfTurnCapReached() {
        guard isHost, var battle, battle.reachedTurnCap, !battle.isFinished else { return }
        battle.endByTurnCap()
        self.battle = battle
        combatFighters = battle.fighters
        turnTimeoutTask?.cancel(); turnEndsAt = nil
        settleRaidIfFinished()
        grantRewardIfFinished()
        broadcastCombatState()
    }

    /// 정산 — 호스트가 기여도를 확정해 뿌리고, 각 클라이언트가 **자기 지갑에** 넣는다.
    ///
    /// 지급을 호스트가 대신 하지 않는 이유는 애초에 못 하기 때문이다(남의 세이브를 못 건드린다).
    /// 그래서 각자 자기 몫을 계산하고, 그 계산이 정직하려면 받은 보스가 오늘의 그 보스여야 한다 —
    /// 그 검사는 개시 시점(`RaidBoss.validRaidStart`)에 이미 끝나 있다.
    private func settleRaidIfFinished() {
        guard combatMode == .coopBoss, !settledRaid,
              MultiplayerBattle.isFinished(fighters: combatFighters, mode: .coopBoss) else { return }
        settledRaid = true
        if raidFinishedRound == nil { raidFinishedRound = combatRound }
        if isHost {
            raidContributions = battle?.damageDealt ?? [:]
            let message = MultiplayerWireMessage.raidSettlement(contributions: raidContributions)
            for connection in guestConnections.values { send(message, over: connection) }
        }
        applyRaidSettlement()
    }

    /// 내 몫을 계산하고 지급한다. 진 판은 정산 자체를 만들지 않는다 — 그래야 그날의 지급 기회가
    /// 살아 있다(`creditRaidReward(0)` 이 원장을 안 쓰는 것과 같은 이유를 양쪽에서 지킨다).
    private func applyRaidSettlement() {
        guard let tier = raidTier,
              MultiplayerBattle.outcome(for: myID, fighters: combatFighters, mode: .coopBoss) == .win
        else { return }
        let survivors = combatFighters.filter { $0.team == .red && $0.isAlive }.count
        let settlement = RaidBoss.settlement(
            tier: tier,
            myDamage: raidContributions[myID] ?? 0,
            totalDamage: raidContributions.values.reduce(0, +),
            turnsRemaining: max(0, RaidBoss.turnCap - (raidFinishedRound ?? RaidBoss.turnCap)),
            survivingRunners: survivors)
        raidSettlement = settlement
        raidPayout = companion.creditRaidReward(settlement.total)
    }

    private func announceNewRaidRooms(_ serviceNames: [String]) {
        let fresh = Self.newlyVisibleRaidRooms(previous: announcedRaidRooms,
                                               current: serviceNames, myIDTag: myRoomTag)
        // 사라진 방은 목록에서 뺀다 — 안 빼면 껐다 켠 같은 방을 영영 다시 못 알린다.
        announcedRaidRooms = serviceNames.filter { RaidRoomName.isRaidRoomName($0) }
        guard !fresh.isEmpty, phase == .idle else { return }
        for name in fresh.prefix(1) { postRaidRoomNotification(RaidRoomName.parse(name)) }
    }

    /// 오늘 남은 5★ 부화의 **15분 전 알림**을 건다.
    ///
    /// 이 알림은 선택이 아니다 — 시각이 무작위라 습관이 대신해 주지 못하고, 알림이 없으면
    /// 마침 화면을 보고 있던 사람만 참여한다. 하루 셋을 두는 이유도 같다(하나를 놓쳐도 둘 남는다).
    ///
    /// 60초 방치 틱이 부른다. 날짜 키와 토글 상태가 그대로면 즉시 빠지므로 실제 작업은 하루 한 번이다
    /// (토글을 키에 넣는 이유: 안 넣으면 오늘 켠 알림이 내일에야 걸린다).
    func refreshRaidHatchReminders(now: Date = Date()) {
        let enabled = AppEnv.isBundledApp
            && !(UserDefaults.standard.object(forKey: "doNotDisturb") as? Bool ?? false)
            && UserDefaults.standard.object(forKey: "raidNotifications") as? Bool ?? true
        let key = "\(CompanionStore.dayKey(now))|\(enabled)"
        guard scheduledHatchKey != key else { return }
        scheduledHatchKey = key

        let center = UNUserNotificationCenter.current()
        let identifiers = (0..<RaidBoss.weekdayBlocks.count).map { "raid-hatch-\($0)" }
        // 먼저 지운다 — 안 지우면 토글을 껐다 켤 때마다 같은 시각에 알림이 겹쳐 쌓인다.
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard enabled else { return }

        for (index, reminder) in RaidSchedule.upcomingReminders(after: now).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = companion.l.raidHatchSoonTitle(minutes: RaidSchedule.reminderLeadMinutes)
            content.body = companion.l.raidHatchSoonBody
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, reminder.timeIntervalSince(now)), repeats: false)
            center.add(UNNotificationRequest(identifier: "raid-hatch-\(index)",
                                             content: content, trigger: trigger))
        }
    }

    private func postRaidRoomNotification(_ room: RaidRoomName?) {
        guard let room, AppEnv.isBundledApp,
              !(UserDefaults.standard.object(forKey: "doNotDisturb") as? Bool ?? false),
              UserDefaults.standard.object(forKey: "raidNotifications") as? Bool ?? true else { return }
        let content = UNMutableNotificationContent()
        content.title = companion.l.raidRoomOpenedTitle(tier: room.tier.rawValue)
        content.body = companion.l.raidRoomOpenedBody(trainer: room.trainerName)
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "raid-room-\(room.idTag)", content: content, trigger: nil))
    }

    func join(_ room: MultiplayerRoomPeer, as role: LobbyRole = .runner) {
        guard phase == .idle else { return }
        phase = .joining(room.name); lastError = nil
        hostingRole = false
        let epoch = sessionEpoch
        Task {
            guard let snapshot = await buildSnapshot() else {
                guard sessionEpoch == epoch else { return }
                phase = .idle; lastError = "포켓몬 정보를 불러오지 못했습니다."; return
            }
            guard sessionEpoch == epoch else { return }
            let isTournament = room.name.hasPrefix("TOUR ·")
            if isTournament {
                guard let pool = await buildTournamentLineup(ids: tournamentPickedTeam, count: 6) else {
                    guard sessionEpoch == epoch else { return }
                    phase = .idle; lastError = "토너먼트 후보 포켓몬 6마리를 선택해 주세요."; return
                }
                guard sessionEpoch == epoch else { return }
                tournamentPools[myID] = pool
                tournamentTeams.removeValue(forKey: myID)
                tournamentFinalTeam = []
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
                        if isTournament, let pool = self.tournamentPools[self.myID] {
                            self.send(.tournamentPool(participantID: self.myID, lineup: pool), over: connection)
                        }
                        self.receiveGuestLoop(connection)
                    // 관장이 배틀 도중 사라지면 그 판은 복구할 수 없다(상태가 관장 메모리에 있었다).
                    // 무효로 닫되 **이어받기**를 제안한다 — 불리할 때 앱을 꺼서 패배를 피하는 것이
                    // 이득이 되지 않게 하는 유일한 수단이다.
                    case .failed(let error):
                        let abandoned = self.isGymMatchAbandonedByLeader
                        self.lastError = error.localizedDescription; self.leaveRoom()
                        if abandoned { self.gymLeaderAbandonedMatch = true }
                    case .cancelled:
                        if self.phase != .idle {
                            let abandoned = self.isGymMatchAbandonedByLeader
                            self.leaveRoom()
                            if abandoned { self.gymLeaderAbandonedMatch = true }
                        }
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

    /// 지금 **화면을 띄워야 하는** 방 컨텐츠가 도는가 — 창을 열지 정하는 신호다.
    /// 붙들지는 않는다(닫기는 언제나 된다).
    ///
    /// 체육관은 `phase` 가 `.hosting` 인 채로 판이 돌아 `isInPlay` 에 안 잡힌다. 그래서 이 값이
    /// 따로 있다. 진행 중인 판만 본다 — 관장이 도전을 기다리는 동안까지 창을 띄우면 성가시다.
    var wantsForegroundWindow: Bool { (hasLiveGymMatch && !isGymDefenseFoughtByAI) || isInPlay }

    /// AI 가 대신 싸우는 내 방어전인가. 관장이 고를 것이 없는데도 도전 시작·교체·기술 선택마다
    /// `gymMatch` 스냅샷이 갱신되고, 그때마다 창이 강제로 열려 하던 일이 끊겼다. 이 경우엔
    /// 창 대신 알림 하나만 띄운다(`postGymBattleNotification`).
    var isGymDefenseFoughtByAI: Bool {
        guard let match = gymMatch, match.winnerID == nil, match.leaderID == myID else { return false }
        return companion.gymLeadership?.usesAI == true
    }

    /// 턴 행동을 기다리는 방 컨텐츠가 도는가 — 체육관 판이거나 방 배틀·토너먼트다.
    /// 포켓슬론·퀴즈는 턴제가 아니지만 `isInPlay` 에 함께 묶여 있고, 그쪽은 아래
    /// `awaitsMyBattleAction` 이 `hasSubmittedAction` 으로 갈라 준다.
    var isAwaitingBattleTurn: Bool { hasLiveGymMatch || isInPlay }

    /// 지금 **내가 골라야 하는** 턴인가. 창이 닫혀 있으면 이 값이 참인 동안 다시 열어 준다 —
    /// 안 그러면 턴 마감이 대신 제출해 사람이 고를 기회를 잃는다.
    var awaitsMyBattleAction: Bool {
        if let match = gymMatch {
            guard match.winnerID == nil, match.leaderID == myID || match.challengerID == myID else { return false }
            // AI 가 대신 싸우는 판은 내 차례가 아니다. `submitted` 로만 가르면 턴이 해상된 직후
            // AI 가 채우기 **전에** 뿌려지는 스냅샷 한 장에 걸려 창이 매 턴 다시 열린다.
            guard !isGymDefenseFoughtByAI else { return false }
            return !match.submitted.contains(myID)
        }
        return isInPlay && !hasSubmittedAction
    }

    /// 체육관 판이 지금 돌고 있나. 도전이 들어오면 **화면을 그쪽으로 데려가야** 하는 유일한
    /// 방 컨텐츠라 따로 둔다 — 나머지(토너먼트·포켓슬론·퀴즈)는 사용자가 그 화면에서 직접
    /// 시작하므로 탭을 옮기면 오히려 엉뚱한 곳으로 간다.
    var hasLiveGymMatch: Bool {
        guard let match = gymMatch else { return false }
        return match.winnerID == nil
    }

    func toggleReady() {
        guard let me = myParticipant, !isInPlay else { return }
        if lobby?.activity == .tournament, tournamentTeams[myID]?.count != 3 {
            lastError = "공개된 6마리 중 실제 출전 포켓몬 3마리를 먼저 확정해 주세요."
            return
        }
        if isHost {
            lobby?.setReady(!me.isReady, participantID: myID); broadcastLobby()
        } else if let hostConnection { send(.ready(participantID: myID, ready: !me.isReady), over: hostConnection) }
    }

    func confirmTournamentTeam() {
        let allowed = Set(tournamentPickedTeam)
        let ids = tournamentFinalTeam.filter { allowed.contains($0) }
        guard phase == .hosting || phase == .joined, lobby?.activity == .tournament,
              ids.count == 3 else {
            lastError = "공개된 후보 중 출전 포켓몬 3마리를 선택해 주세요."; return
        }
        let epoch = sessionEpoch
        Task {
            guard let lineup = await buildTournamentLineup(ids: ids, count: 3) else {
                guard sessionEpoch == epoch else { return }
                lastError = "토너먼트 출전 파티를 준비하지 못했습니다."; return
            }
            guard sessionEpoch == epoch else { return }
            tournamentTeams[myID] = lineup
            if !isHost, let hostConnection {
                send(.tournamentTeam(participantID: myID, lineup: lineup), over: hostConnection)
            }
        }
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
        guard runners.count >= 3, runners.count <= 8,
              runners.allSatisfy({ tournamentTeams[$0.id]?.count == 3 }) else {
            lastError = "최소 3명이 참가하고 모두 포켓몬 3마리의 출전 파티를 준비해야 합니다."; return
        }
        let entrants = runners.map {
            TournamentEntrant(id: $0.id, trainerName: $0.trainerName, speciesID: $0.speciesID)
        }
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        let bracket = TournamentBracket(participantIDs: entrants.map(\.id), seed: seed)
        tournamentBracket = bracket
        tournamentState = PokemonTournamentState(entrants: entrants,
                                                  reward: TournamentEggReward.forParticipants(entrants.count),
                                                  openingMatches: bracket.previewMatches(),
                                                  bracketRevealUntil: Date().addingTimeInterval(10))
        tournamentRewarded = false; phase = .tournament
        // 호스트만 시계를 운영하고 같은 상태를 전원에게 먼저 보낸다. 바로 경기를 넣으면
        // SwiftUI가 초기 대진표를 한 프레임도 그리지 못한다.
        broadcastTournamentState(start: true)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.phase == .tournament,
                  self.tournamentState?.currentMatch == nil else { return }
            self.startNextTournamentMatch()
        }
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
        let snapshot = engine.snapshot()
        tournamentState?.currentMatch = snapshot
        broadcastTournamentState()
        if case .switchTo = action, !snapshot.submitted.contains(participantID) { scheduleTurnTimeout() }
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

    // MARK: 공유 체육관 — 관장이 호스트다

    /// 도전 신청. 게스트는 호스트에게 보내고, 판정(쿨다운·배틀 중·방어팀 유무)은 전부 호스트가 한다 —
    /// 클라이언트 시계를 믿지 않는다.
    /// 체육관에 들어가 **곧바로 도전한다.** 입장과 도전을 나누면 "도전" 버튼이 두 번 뜨고,
    /// 첫 번째를 누른 사람은 두 번째가 왜 또 필요한지 알 수 없다.
    func joinAndChallengeGym(_ room: MultiplayerRoomPeer) {
        // 프로토콜이 다르면 붙어 봐야 입장에서 거절된다 — 그 왕복을 돌기 전에 여기서 끊고
        // 이유를 말한다. 화면도 같은 판정으로 버튼을 잠그지만, 규칙은 여기 한 곳에 둔다.
        guard compatibility(of: room).allowsChallenge else {
            lastError = companion.l.gymVersionMismatch; return
        }
        pendingGymChallenge = true
        join(room, as: .runner)
    }

    func challengeGym() {
        guard phase == .joined else { return }
        // 이미 남의 판이 돌고 있으면 도전을 **보내지 않는다.** 예전엔 여기서 조용히 돌아서
        // 버튼을 눌러도 아무 일도 안 일어난 것처럼 보였다 — 관장에게 물어볼 것도 없이
        // 아는 사실이므로 그 자리에서 사유를 세운다.
        guard gymMatch == nil else { gymRejection = .busy; return }
        gymRejection = nil
        let epoch = sessionEpoch
        Task {
            guard let lineup = await buildGymLineup() else {
                guard sessionEpoch == epoch else { return }
                lastError = companion.l.gymNeedsMorePokemon(PlayerGym.defenseTeamSize); return
            }
            guard sessionEpoch == epoch, let hostConnection else { return }
            send(.gymChallenge(participantID: myID, lineup: lineup), over: hostConnection)
        }
    }

    /// 관장이 도전을 받는다. 거절 사유가 있으면 그것만 돌려보내고 판을 열지 않는다.
    private func acceptGymChallenge(_ lineup: [BattleSnapshot], from challengerID: UUID) {
        guard isHost, let leadership = companion.gymLeadership else { return }
        guard let connection = guestConnections[challengerID] else { return }

        // 남이 보낸 팀은 그대로 믿지 않는다. 레벨은 어차피 눕히지만 종족값·기술은 와이어에서 온다.
        guard validLineup(lineup, participantID: challengerID, size: PlayerGym.defenseTeamSize) else {
            send(.rejected(reason: "잘못된 도전 파티입니다."), over: connection); return
        }
        guard gymMatch == nil else { send(.gymRejected(reason: .busy), over: connection); return }
        guard leadership.hasFullDefenseTeam else {
            send(.gymRejected(reason: .notReady), over: connection); return
        }
        let now = Date()
        let last = leadership.challengeCooldowns[challengerID]
        guard PlayerGym.challengeAllowed(lastFinishedAt: last, now: now) else {
            let remaining = Int(PlayerGym.remainingCooldown(lastFinishedAt: last, now: now).rounded(.up))
            send(.gymRejected(reason: .cooldown(remainingSeconds: remaining)), over: connection)
            return
        }

        gymChallengerLineup = lineup
        Task { await startGymMatch(challengerID: challengerID, challengerLineup: lineup) }
    }

    private func startGymMatch(challengerID: UUID, challengerLineup: [BattleSnapshot]) async {
        let epoch = sessionEpoch
        guard isHost, let defense = await buildGymDefenseLineup(), sessionEpoch == epoch else { return }
        let challengerName = lobby?.participants.first { $0.id == challengerID }?.trainerName ?? "?"
        // 판을 시작할 때 **아무 행동도 미리 채우지 않는다.** 예전엔 여기서 양쪽을 채워 두는 바람에
        // 도전자가 무엇을 눌러도 `submit` 이 "이미 냈다" 로 거절됐다 — 그래서 `let` 이다.
        let engine = GymMatchEngine(leaderID: myID, challengerID: challengerID,
                                    leaderName: trainerName, challengerName: challengerName,
                                    leaderTeam: defense, challengerTeam: challengerLineup,
                                    seed: UInt64.random(in: UInt64.min...UInt64.max))
        gymEngine = engine
        gymMatch = engine.snapshot()
        broadcastGymState()
        scheduleTurnTimeout()
        if companion.gymLeadership?.usesAI == true { postGymBattleNotification(challengerName: challengerName) }
        applyGymLeaderAutoActionIfNeeded()
    }

    /// AI 방어는 창을 띄우지 않으므로(`isGymDefenseFoughtByAI`) 도전이 들어온 사실을 알릴 곳이
    /// 여기뿐이다. 판당 한 번만 띄운다 — 턴마다 띄우면 창이 열리던 때와 똑같이 성가시다.
    private func postGymBattleNotification(challengerName: String) {
        guard !(UserDefaults.standard.object(forKey: "doNotDisturb") as? Bool ?? false), AppEnv.isBundledApp else { return }
        guard let matchID = gymMatch?.matchID else { return }
        let content = UNMutableNotificationContent()
        content.title = companion.l.t("체육관 배틀 중입니다", "Gym battle in progress", "ジム戦が進行中です")
        content.body = companion.l.t("\(challengerName) 님의 도전을 AI 가 방어하고 있습니다.",
                                     "\(challengerName) is challenging — your AI is defending.",
                                     "\(challengerName) さんの挑戦を AI が防衛中です。")
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "gym-battle-\(matchID.uuidString)",
                                  content: content, trigger: nil))
    }

    /// 내 행동 제출 — 관장이든 도전자든 같은 입구다.
    func submitGymAction(_ action: NetBattleAction) {
        guard let match = gymMatch, match.winnerID == nil,
              match.leaderID == myID || match.challengerID == myID else { return }
        if isHost { acceptGymAction(action, from: myID, matchID: match.matchID) }
        else if let hostConnection {
            send(.gymAction(matchID: match.matchID, participantID: myID, action: action), over: hostConnection)
        }
    }

    private func acceptGymAction(_ action: NetBattleAction, from participantID: UUID, matchID: UUID) {
        guard isHost, var engine = gymEngine, engine.matchID == matchID,
              engine.submit(action, from: participantID) else { return }
        gymEngine = engine
        let snapshot = engine.snapshot()
        gymMatch = snapshot
        broadcastGymState()
        if case .switchTo = action, !snapshot.submitted.contains(participantID) { scheduleTurnTimeout() }
        finishGymTurnIfReady()
    }

    /// 관장이 AI 모드면 도전자를 기다리지 않고 자기 몫을 곧바로 채운다.
    private func applyGymLeaderAutoActionIfNeeded() {
        guard isHost, companion.gymLeadership?.usesAI == true,
              var engine = gymEngine, engine.battle.myAction == nil else { return }
        // **관장 몫만** 채운다 — 도전자까지 채우면 사람이 고르기도 전에 해상되어 AI 끼리 끝난다.
        engine.fillLeaderAction(usingAI: true)
        gymEngine = engine
        gymMatch = engine.snapshot()
        broadcastGymState()
        finishGymTurnIfReady()
    }

    private func finishGymTurnIfReady() {
        guard isHost, var engine = gymEngine, engine.isReady else { return }
        let winner = engine.resolveIfReady()
        gymEngine = engine
        gymMatch = engine.snapshot(winnerID: winner)
        broadcastGymState()
        if let winner {
            turnTimeoutTask?.cancel(); turnEndsAt = nil
            concludeGymMatch(winnerID: winner, challengerID: engine.challengerID)
        } else {
            scheduleTurnTimeout()
            applyGymLeaderAutoActionIfNeeded()
        }
    }

    /// 판을 닫는다. 관장이 이겼으면 쿨다운만 적고, 졌으면 **자리를 넘긴다.**
    private func concludeGymMatch(winnerID: UUID, challengerID: UUID) {
        companion.recordGymChallengeFinished(challengerID: challengerID)
        // 기록에 남길 이름은 판이 지워지기 전에 집어 둔다.
        let challengerName = gymMatch?.challengerName
            ?? lobby?.participants.first { $0.id == challengerID }?.trainerName ?? "?"
        guard winnerID == challengerID else {
            // 지켰다. 보상은 **방어에만** 나간다 — 점령에 붙이면 왕복 파밍이 된다.
            lastGymDefensePayout = companion.recordGymDefenseSuccess(challengerName: challengerName)
            gymChallengerLineup = nil
            // 결과를 잠깐 보여 준 뒤 판을 지운다. **안 지우면 다음 도전이 "이미 배틀 중" 으로
            // 거절되어 체육관이 한 번 방어하고 영구히 잠긴다.**
            scheduleGymMatchClear()
            return
        }
        // 자리를 내줬다. 이 줄이 기록에서 가장 궁금한 줄이라 반드시 남긴다.
        companion.recordGymDefenseLoss(challengerName: challengerName)
        if let gymID = companion.gymLeadership?.gymID,
           let connection = guestConnections[challengerID] {
            send(.gymHandoff(gymID: gymID), over: connection)
        }
        gymChallengerLineup = nil
        onGymLeadershipLost?()
        // 자리를 넘겼으니 이 방은 닫는다. 새 관장이 자기 기기에서 새로 연다.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.leaveRoom()
        }
    }

    private func broadcastGymState() {
        guard let match = gymMatch else { return }
        for connection in guestConnections.values { send(.gymState(match), over: connection) }
    }

    /// 테스트 전용 — 게스트가 `.gymState` 를 받은 것과 같은 자리를 지난다.
    /// 프로덕션 호출 경로는 없다(수신 루프가 같은 일을 한다).
    /// 테스트용 — 게스트가 `.raidStart` 를 받은 것과 같은 자리를 지난다. 소켓 없이 재생 배선의
    /// 전제(스트림이 자라는가·새 판이 비우는가)를 밟기 위한 통로다(`debugApplyGymState` 와 같은 관례).
    func debugBeginRaidCombat(fighters: [MultiplayerFighter], tier: RaidTier) {
        raidTier = tier
        beginRaidCombat(fighters: fighters)
    }

    /// 테스트용 — 라운드 하나가 해상돼 도착한 자리. **자기 사본을 두지 않고 실제 경로를 부른다** —
    /// 사본을 두었더니 게스트 경로를 `combatEvents = events` 로 되돌리는 결함을 주입해도 테스트가
    /// 초록이었다(defect-log: 테스트가 결함 트리거와 다른 경로로 통과해 false confidence 를 준다).
    func debugApplyResolvedRound(fighters: [MultiplayerFighter], events: [BattleEvent]) {
        applyResolvedRound(fighters: fighters, events: events)
    }

    func debugApplyGymState(_ match: GymMatchState) {
        gymMatch = match
        if match.challengerID == myID { gymRejection = nil }
        if match.winnerID != nil { scheduleGymMatchClear() }
    }

    /// 테스트 전용 — 게스트가 `.gymRejected` 를 받은 것과 같은 자리를 지난다.
    func debugApplyGymRejection(_ reason: GymChallengeRejection) { gymRejection = reason }

    /// 끝난 판을 잠시 뒤 치운다 — 관장은 다음 도전을 받을 수 있게, 도전자·관전자는 결과 화면에서
    /// 빠져나올 수 있게. 승계로 방이 닫히는 경우는 `leaveRoom()` 이 대신 정리한다.
    private func scheduleGymMatchClear() {
        gymMatchClearTask?.cancel()
        gymMatchClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PlayerGym.resultDisplaySeconds))
            guard !Task.isCancelled else { return }
            guard let self, self.gymMatch?.winnerID != nil else { return }
            self.gymMatch = nil
            self.gymEngine = nil
            self.lastGymDefensePayout = nil
            self.gymMatchClearTask = nil
        }
    }

    /// 판이 안 끝났는데 관장 연결이 끊겼나. **`leaveRoom()` 이 플래그를 지우므로** 호출부는 이 값을
    /// 먼저 읽어 두고, 방을 정리한 **뒤에** 세운다.
    private var isGymMatchAbandonedByLeader: Bool {
        guard !isHost, let match = gymMatch else { return false }
        return match.winnerID == nil && match.challengerID == myID
    }

    /// 이어받기 제안을 지운다(수락했거나 무시했을 때).
    func dismissGymTakeoverOffer() { gymLeaderAbandonedMatch = false }

    /// 도전자가 배틀 도중 사라졌다 — 관장 승리로 닫는다. 이걸 안 이으면 지는 도중 앱을 꺼서
    /// 결과를 흐릴 수 있다(토너먼트에 빠져 있는 처리다).
    private func retireGymChallenger(_ participantID: UUID) {
        guard isHost, let match = gymMatch, match.winnerID == nil,
              match.challengerID == participantID else { return }
        turnTimeoutTask?.cancel(); turnEndsAt = nil
        gymMatch = gymEngine?.snapshot(winnerID: match.leaderID)
        broadcastGymState()
        concludeGymMatch(winnerID: match.leaderID, challengerID: participantID)
    }

    private func buildGymLineup() async -> [BattleSnapshot]? {
        await companion.ensureInheritedMoves()
        let owned = companion.deployableMons
        let ids = gymPickedTeam.filter { id in owned.contains(where: { $0.id == id }) }
        guard ids.count == PlayerGym.defenseTeamSize else { return nil }
        var lineup: [BattleSnapshot] = []
        for id in ids {
            guard let mon = owned.first(where: { $0.id == id }),
                  let snapshot = await companion.battleSnapshot(for: mon, level: PlayerGym.battleLevel)
            else { return nil }
            lineup.append(snapshot)
        }
        return lineup
    }

    /// 관장의 방어팀 — 잠가 둔 넷을 그대로 세운다.
    private func buildGymDefenseLineup() async -> [BattleSnapshot]? {
        guard let leadership = companion.gymLeadership, leadership.hasFullDefenseTeam else { return nil }
        await companion.ensureInheritedMoves()
        var lineup: [BattleSnapshot] = []
        for id in leadership.defenseMonIDs {
            guard let mon = companion.ownedMons.first(where: { $0.id == id }),
                  let snapshot = await companion.battleSnapshot(for: mon, level: PlayerGym.battleLevel)
            else { return nil }
            lineup.append(snapshot)
        }
        return lineup
    }

    private func preparePokemonQuiz(players: [PokemonOXPlayer]) async {
        guard !players.isEmpty else { return }
        isPreparingPokemonQuiz = true; lastError = nil
        // 문제를 받아 오는 동안 방을 떠날 수 있다 — 그 뒤에 국면을 퀴즈로 올리면 이미 정리된
        // 방이 화면에 되살아난다.
        let epoch = sessionEpoch
        defer { isPreparingPokemonQuiz = false }
        guard let facts = try? await PokeAPIClient.shared.pokemonQuizFacts() else {
            guard sessionEpoch == epoch else { return }
            lastError = "PokéAPI에서 퀴즈 데이터를 불러오지 못했습니다. 네트워크를 확인해 주세요."
            if lobby == nil { hostingRole = false; phase = .idle }
            return
        }
        guard sessionEpoch == epoch else { return }
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
    ///
    /// 금액 0 은 **철회**다. 판돈을 실제로 내지 못한 관전자(로비에서 별조각을 쓴 뒤 베팅한 경우
    /// 호스트가 보는 신고 잔액은 아직 충분하다)가 자기 항목을 원장에서 빼는 유일한 경로다 —
    /// 남겨 두면 아무도 내지 않은 판돈이 배당에 섞여 별조각이 생성된다("이동만" 불변식 위반).
    private func acceptBet(_ bet: PokeathlonBet, from senderID: UUID) {
        guard isHost, let lobby, let race = pokeathlonRace else { return }
        guard bet.bettorID == senderID else { return }
        guard bet.amount != 0 else { withdrawBet(of: senderID); return }
        if let rejection = PokeathlonPool.rejection(for: bet, senderID: senderID, lobby: lobby,
                                                    race: race, pool: pokeathlonPool, now: Date()) {
            if senderID == myID { lastError = Self.betRejectionText(rejection) }
            return
        }
        pokeathlonPool.bets[bet.bettorID] = bet    // 같은 관전자의 이전 베팅을 대체
        // 내 판돈은 **원장에 남기기 전에** 실제로 빠져나가야 한다. 에스크로가 실패했는데 항목만
        // 남으면 배당이 없는 돈을 나눈다.
        if senderID == myID, !syncEscrow() {
            pokeathlonPool = pokeathlonPool.withoutUnfundedBet(of: bet.bettorID)
            lastError = "별조각이 부족합니다."
        }
        broadcastPool()
    }

    /// 잠기지 않은 원장에서 한 관전자의 베팅을 뺀다. 잠긴 뒤(출발 후)에는 뺄 수 없다 —
    /// 그때는 이미 배당 계산이 그 판돈을 세고 있다.
    private func withdrawBet(of bettorID: UUID) {
        guard isHost, !pokeathlonPool.isClosed, pokeathlonPool.bets[bettorID] != nil else { return }
        pokeathlonPool = pokeathlonPool.withoutUnfundedBet(of: bettorID)
        if bettorID == myID { _ = syncEscrow() }
        broadcastPool()
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
    /// 원장의 내 항목과 지갑을 맞춘다. 돌려주는 값은 **맞았는가** 다 — 원장에 내 베팅이 있는데
    /// 판돈을 못 냈으면 거짓이고, 그 항목은 원장에서 빠져야 한다.
    @discardableResult
    private func syncEscrow() -> Bool {
        let mine = pokeathlonPool.bets[myID]
        guard mine != escrowedBet else { return true }
        if let previous = escrowedBet { companion.creditStarPieces(previous.amount) }
        guard let mine else { escrowedBet = nil; return true }
        if companion.escrowStarPieces(mine.amount) { escrowedBet = mine; return true }
        escrowedBet = nil
        return false
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
        tournamentState = nil; tournamentTeams.removeAll(); tournamentPools.removeAll(); tournamentBracket = nil
        tournamentFinalTeam = []
        tournamentMatch = nil; tournamentRewarded = false
        gymMatchClearTask?.cancel(); gymMatchClearTask = nil
        gymMatch = nil; gymEngine = nil; gymChallengerLineup = nil; gymRejection = nil
        gymLeaderAbandonedMatch = false; lastGymDefensePayout = nil; pendingGymChallenge = false
        // `gymPickedTeam` 은 남긴다 — 방을 떠나도 "누구를 데려갈지"는 사용자의 설정이라
        // 다음 도전 때 다시 고르게 하면 성가시다(`tournamentPickedTeam` 과 같은 취급).
        pokeathlonPool = PokeathlonPool(); escrowedBet = nil; settlementPayout = nil; settledPool = false
        raidTier = nil; raidContributions = [:]; raidSettlement = nil; raidPayout = nil
        raidFinishedRound = nil; settledRaid = false
        pendingActions.removeAll(); combatFighters = []; combatEvents = []; combatRound = 0
        turnEndsAt = nil; rewardedBattle = false
        hasSubmittedAction = false; hostingRole = false; phase = .idle
        sessionEpoch &+= 1
        chatHistory.reset(); chatMessages = []; chatRateLimiter.reset()
    }

    private func startHosting() throws {
        let listener = try NWListener(using: Self.parameters())
        let prefix: String
        switch lobby?.activity {
        case .pokeathlon: prefix = "RUN"
        case .pokemonQuiz: prefix = "QUIZ"
        case .tournament: prefix = "TOUR"
        case .gym: prefix = PlayerGym.roomNamePrefix
        // 접두는 `RaidRoomName.make` 가 붙인다 — 여기 값은 위 분기에서 쓰이지 않는다.
        case .raid: prefix = RaidRoomName.prefix
        default: prefix = "BATTLE"
        }
        // 체육관만 이름에 재임 시작 시각을 함께 싣는다 — 방 광고에 TXT 가 없어, 목록에서
        // "누가 몇 분째 지키는지"를 접속 없이 보여줄 통로가 이름뿐이다.
        let idTag = myRoomTag
        let serviceName: String
        if lobby?.activity == .raid, let tier = raidTier {
            serviceName = RaidRoomName.make(trainerName: trainerName, idTag: idTag, tier: tier)
        } else if lobby?.activity == .gym {
            serviceName = PlayerGymRoomName.make(
                leaderName: trainerName, idTag: idTag,
                heldSince: companion.gymLeadership?.heldSince ?? Date())
        } else {
            // 자를 수 있는 건 트레이너 이름뿐이다 — 접두는 목록 분류에, 접미는 자기 판정에 쓰인다.
            serviceName = LANServiceName.make(base: "\(prefix) · \(trainerName)", suffix: "#\(idTag)")
        }
        listener.service = NWListener.Service(name: serviceName, type: Self.serviceType)
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
        // 도전자 하나 + 관전자들. 관장은 호스트라 게스트로 세지 않는다.
        case .gym: maxGuests = 1 + MultiplayerLobby.spectatorCapacity
        // 러너 넷 중 셋이 게스트고, 보스는 참가자가 아니라 자리를 쓰지 않는다.
        case .raid: maxGuests = 3 + MultiplayerLobby.spectatorCapacity
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
                    // 버전이 갈렸다는 사실만 말하면 무엇을 해야 할지 알 수 없다 — 이 문구가
                    // 구버전 상대의 화면에 그대로 뜨는 유일한 통로다.
                    self.send(.rejected(reason: self.companion.l.gymVersionMismatch), over: connection)
                    connection.cancel(); return
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
                    if self.lobby?.activity == .tournament {
                        self.send(.tournamentPools(self.tournamentPools), over: connection)
                        // 진행 중 들어온 관전자는 다음 턴 브로드캐스트까지 빈 로비에 머물면 채팅도
                        // 경기 화면도 열 수 없다. 현재 대진을 이 연결에 즉시 동기화한다.
                        if let state = self.tournamentState {
                            self.send(.tournamentStart(state: state), over: connection)
                        }
                    }
                    // 진행 중인 체육관 판이 있으면 **이 연결에만** 현재 상태를 보낸다. 브로드캐스트는
                    // 다음 행동 때나 오므로, 이게 없으면 방금 들어온 관전자는 판이 끝날 때까지
                    // 빈 화면을 본다.
                    if let match = self.gymMatch { self.send(.gymState(match), over: connection) }
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
                else if self.lobby?.activity == .gym { self.retireGymChallenger(pid); try? self.lobby?.leave(participantID: pid) }
                else { try? self.lobby?.leave(participantID: pid) }
                self.snapshots.removeValue(forKey: pid); self.guestConnections.removeValue(forKey: pid)
                self.tournamentPools.removeValue(forKey: pid)
                self.tournamentTeams.removeValue(forKey: pid)
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
            case .tournamentPool(let pid, let lineup) where pid == id:
                guard self.lobby?.activity == .tournament,
                      self.validLineup(lineup, participantID: pid, size: 6) else {
                    self.send(.rejected(reason: "잘못된 토너먼트 후보입니다."), over: connection); return
                }
                self.tournamentPools[pid] = lineup
                for guest in self.guestConnections.values {
                    self.send(.tournamentPools(self.tournamentPools), over: guest)
                }
            case .tournamentAction(let matchID, let pid, let action) where pid == id:
                self.acceptTournamentAction(action, from: pid, matchID: matchID)
            case .gymChallenge(let pid, let lineup) where pid == id:
                guard self.lobby?.activity == .gym else { break }
                self.acceptGymChallenge(lineup, from: pid)
            case .gymAction(let matchID, let pid, let action) where pid == id:
                self.acceptGymAction(action, from: pid, matchID: matchID)
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
            case .lobby(let lobby):
                self.lobby = lobby; self.phase = .joined
                // 입장하자마자 도전하기로 하고 들어왔으면 여기서 보낸다 — 입장이 비동기라
                // 로비를 받은 이 시점이 도전을 보낼 수 있는 첫 자리다.
                if self.pendingGymChallenge {
                    self.pendingGymChallenge = false
                    self.challengeGym()
                }
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
            case .raidStart(let seed, let fighters, let tier):
                // **오늘의 보스가 맞는지 내가 직접 확인한다.** 보상은 내 지갑에 내가 넣으므로,
                // 호스트를 믿으면 조작된 방이 약한 보스에 5★ 딱지를 붙여 방 전원에게 5★ 를 뿌린다.
                let dayKey = CompanionStore.dayKey(Date())
                guard RaidBoss.validRaidStart(fighters: fighters, tier: tier, dayKey: dayKey),
                      let started = try? MultiplayerBattle(fighters: fighters, mode: .coopBoss, seed: seed) else {
                    self.lastError = self.companion.l.raidBossMismatch; self.leaveRoom(); return
                }
                self.battle = started
                self.raidTier = tier
                self.beginRaidCombat(fighters: fighters)
            case .raidSettlement(let contributions):
                guard self.combatMode == .coopBoss else { return }
                self.raidContributions = contributions
                self.applyRaidSettlement()
            case .roundResolved(let round, let fighters, let events):
                guard self.phase == .battling, round == self.combatRound else { return }
                self.applyResolvedRound(fighters: fighters, events: events)
                self.turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
                // 정산이 보상보다 **먼저** 와야 한다 — `grantRewardIfFinished` 는 전적만 남기고,
                // 지갑을 늘리는 건 정산 쪽이다. 순서가 바뀌면 결과 화면이 한 프레임 빈 채로 뜬다.
                self.settleRaidIfFinished()
                self.grantRewardIfFinished()
            case .chat(let message): self.acceptRelayedChat(message)
            case .pokeathlonStart(let race): self.pokeathlonRace = race; self.phase = .pokeathlon
            case .pokeathlonState(let race) where self.phase == .pokeathlon: self.pokeathlonRace = race
            case .pokeathlonPool(let pool):
                self.pokeathlonPool = pool
                // 판돈을 못 냈으면 호스트 원장에서 내 항목을 빼 달라고 알린다(금액 0 = 철회).
                // 그러지 않으면 내지 않은 판돈이 남의 배당에 섞인다.
                if !self.syncEscrow(), let hostConnection = self.hostConnection,
                   let mine = pool.bets[self.myID] {
                    self.lastError = "별조각이 부족해 베팅이 취소됐습니다."
                    self.send(.pokeathlonBet(participantID: self.myID, runnerID: mine.runnerID, amount: 0),
                              over: hostConnection)
                }
            case .pokeathlonSettlement(let pool, let winnerID):
                self.applySettlement(pool: pool, winnerID: winnerID)
            case .pokemonQuizStart(let game): self.pokemonQuizGame = game; self.phase = .pokemonQuiz
            case .pokemonQuizState(let game) where self.phase == .pokemonQuiz: self.pokemonQuizGame = game
            case .tournamentPools(let pools):
                self.tournamentPools = pools
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
            // 체육관 상태는 `phase` 로 거르지 않는다 — 진행 중인 판에 관전으로 들어온 게스트도
            // 곧바로 화면을 그려야 한다(호스트가 입장 직후 현재 상태를 개별 전송한다).
            case .gymState(let match):
                let previousTurn = self.gymMatch?.turn
                self.gymMatch = match
                // **내 도전이 받아들여졌을 때만** 사유를 지운다. 관장은 남의 판이 도는 내내
                // 상태를 뿌리므로, 무조건 지우면 방금 받은 "이미 도전 중입니다" 가 다음 턴
                // 방송에 곧바로 덮여 화면에서 사라졌다.
                if match.challengerID == self.myID { self.gymRejection = nil }
                if match.turn != previousTurn {
                    self.turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
                }
                // 승패가 났으면 게스트도 결과를 잠깐 보고 빠져나온다 — 안 치우면 관전자·도전자가
                // 끝난 판 화면에 갇힌다(관장 쪽은 호스트 경로가 따로 치운다).
                if match.winnerID != nil { self.scheduleGymMatchClear() }
            case .gymRejected(let reason):
                self.gymRejection = reason
            case .gymHandoff(let gymID):
                // 이겼다. 이 방은 곧 닫히고, 내 기기에서 새 체육관을 연다.
                self.onGymLeadershipWon?(gymID)
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
        guard (phase == .battling || phase == .tournament), incoming.senderID == participantID,
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
        guard (phase == .battling || phase == .tournament),
              let normalized = BattleChatPolicy.normalizedBody(body) else { return }
        let message = BattleChatMessage(senderID: myID, senderName: trainerName, body: normalized)
        if isHost { acceptChat(message, from: myID) }
        else if let hostConnection { send(.chat(message), over: hostConnection) }
    }

    private func finishRoundIfReady() {
        guard isHost, var battle else { return }
        // 보스에겐 클라이언트가 없다 — 사람 행동이 들어올 때마다 여기서 보스 몫을 채운다.
        // 이 자리에 두는 이유는 진입로가 셋(사람 행동·마감·이탈)인데 전부 이 함수를 지나서다.
        injectBossActionIfNeeded()
        let livingIDs = Set(battle.livingFighters.map(\.id))
        pendingActions = pendingActions.filter { livingIDs.contains($0.key) }
        guard Set(pendingActions.keys) == livingIDs else { return }
        do {
            let resolvedRound = combatRound
            let events = try battle.resolveRound(Array(pendingActions.values))
            self.battle = battle
            applyResolvedRound(fighters: battle.fighters, events: events)
            pendingActions.removeAll()
            let message = MultiplayerWireMessage.roundResolved(round: resolvedRound,
                                                               fighters: battle.fighters, events: events)
            for connection in guestConnections.values { send(message, over: connection) }
            if battle.isFinished {
                turnTimeoutTask?.cancel(); turnEndsAt = nil
                raidFinishedRound = resolvedRound
                settleRaidIfFinished(); grantRewardIfFinished()
            } else {
                // 상한을 넘겼으면 여기서 닫는다 — 넘긴 판에 다음 턴을 열면 상한이 뜻을 잃는다.
                endRaidIfTurnCapReached()
                if battle.isFinished { return }
                injectBossActionIfNeeded()
                scheduleTurnTimeout()
            }
        } catch {
            lastError = error.localizedDescription; pendingActions.removeAll(); hasSubmittedAction = false
            // 거절된 라운드에도 마감을 다시 건다. 이게 없으면 게스트가 보낸 엉뚱한 targetID 하나로
            // 방이 영구히 멈춘다(마감 경로에서 throw 가 나면 다시 걸릴 타이머가 없다).
            scheduleTurnTimeout()
        }
    }

    /// 해상된 라운드 하나를 화면 상태에 반영한다. **호스트와 게스트가 같은 자리를 지난다.**
    ///
    /// 갈라 두면 한쪽만 고치는 부류가 그대로 생긴다(defect-log: 같은 기전을 한 모드에서만
    /// 고치는 부류). 실제로 이 함수를 만들기 전에는 테스트가 자기 사본을 밟아, 게스트 경로를
    /// 덮어쓰기로 되돌리는 결함을 주입해도 초록이었다.
    ///
    /// **이벤트는 덮어쓰지 않고 이어 붙인다.** 재생기(`BattleAnimator`)는 자라는 스트림을 전제한다
    /// (`stream.count >= playedCount`) — 매 라운드 갈아 끼우면 전부 "새 배틀"로 읽혀 재생 없이
    /// seed 만 되고 화면이 결과로 스냅한다.
    private func applyResolvedRound(fighters: [MultiplayerFighter], events: [BattleEvent]) {
        combatFighters = fighters
        combatEvents += events
        combatRound += 1
        hasSubmittedAction = false
    }

    private func scheduleTurnTimeout() {
        turnTimeoutTask?.cancel()
        let round: Int
        if let match = gymMatch { round = match.turn }
        else if phase == .tournament { round = tournamentState?.currentMatch?.turn ?? 0 }
        else { round = combatRound }
        turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
        turnTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.turnDuration))
            guard !Task.isCancelled else { return }
            self?.fillTimedOutActions(round: round)
        }
    }

    private func fillTimedOutActions(round: Int) {
        // 체육관은 `phase` 가 `.hosting` 인 채로 판이 돈다 — 국면이 아니라 판의 유무로 가른다.
        if gymMatch != nil {
            guard isHost, var engine = gymEngine, gymMatch?.turn == round,
                  gymMatch?.winnerID == nil else { return }
            // 마감에서는 양쪽을 채우는 것이 맞다 — 시간 안에 안 고른 것을 대신하는 자리다.
            engine.fillTimedOutActions(leaderUsesAI: companion.gymLeadership?.usesAI == true)
            let needsFreshTurn = !engine.isReady
            gymEngine = engine
            gymMatch = engine.snapshot()
            finishGymTurnIfReady()
            if needsFreshTurn { scheduleTurnTimeout() }
            return
        }
        if phase == .tournament {
            guard isHost, var engine = tournamentMatch,
                  tournamentState?.currentMatch?.turn == round else { return }
            engine.fillMissingActions()
            let needsFreshTurn = !engine.isReady
            tournamentMatch = engine
            tournamentState?.currentMatch = engine.snapshot()
            finishTournamentTurnIfReady()
            if needsFreshTurn { scheduleTurnTimeout() }
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
        tournamentPools.removeValue(forKey: id); tournamentTeams.removeValue(forKey: id)
        if phase == .battling {
            retireFighter(id)
        } else {
            // 체육관은 `phase` 가 `.hosting` 인 채로 판이 돈다(방 배틀과 국면이 다르다). 그래서
            // 여기서 따로 몰수를 걸어야 도전자가 지는 도중 앱을 꺼서 결과를 흐리는 걸 막는다.
            if lobby?.activity == .gym { retireGymChallenger(id) }
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
            // 이탈로 끝난 판도 정산을 지난다 — 끝나는 길은 하나가 아니다(defect-log: 회수를
            // 성공 분기에만 걸어 두는 부류). 파티가 전멸해 끝났으면 `applyRaidSettlement` 가
            // 승리가 아니라서 아무것도 지급하지 않는다.
            settleRaidIfFinished()
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
        // 참가자 수는 **사람 수**다. 협동전에서 보스까지 세면 4인 파티가 `5P` 로 남고,
        // 불러오기 정규화(`SaveTransfer.sanitized` 의 1...4)에 걸려 그 기록이 통째로 사라진다.
        let won = outcome == .win
        let count = combatMode == .coopBoss
            ? combatFighters.filter { $0.team == .red }.count
            : combatFighters.count
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
            guard let error else { return }
            AppLog.write("multiplayer send failed: \(error)")
            // 접어야 상태 핸들러(`.failed`/`.cancelled`)가 방을 정리한다. 로그만 남기면 상대가
            // 사라진 방이 계속 차례를 기다린다.
            connection.cancel()
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

    /// 방에 들고 들어갈 내 대표 스냅샷.
    ///
    /// **동행이 알이어도 막지 않는다.** 예전엔 `state.active` 를 요구해서, 알을 품는 동안에는
    /// 박스에 키워 둔 개체가 아무리 많아도 방 계열(토너먼트·포켓슬론·퀴즈·체육관)에 못 들어갔다.
    /// 내보낼 개체가 하나라도 있으면 그걸로 만든다.
    private func buildSnapshot() async -> BattleSnapshot? {
        await companion.ensureInheritedMoves()
        guard let mon = companion.battleFacadeMon else { return nil }
        // 동행이면 지금 화면에 뜬 이름·레벨을 그대로 쓰고, 박스 개체면 그 개체 기준으로 만든다.
        if let active = companion.state.active, active.id == mon.id,
           let speciesID = companion.currentSpeciesID,
           let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID) {
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
        return await companion.battleSnapshot(for: mon, level: mon.level)
    }

    private func buildTournamentLineup(ids requestedIDs: [UUID], count: Int) async -> [BattleSnapshot]? {
        await companion.ensureInheritedMoves()
        let owned = companion.deployableMons
        let ids = requestedIDs.filter { id in owned.contains(where: { $0.id == id }) }
        guard ids.count == count, Set(ids).count == count else { return nil }
        var lineup: [BattleSnapshot] = []
        for id in ids {
            guard let mon = owned.first(where: { $0.id == id }),
                  let snapshot = await companion.battleSnapshot(for: mon, level: 50) else { return nil }
            lineup.append(snapshot)
        }
        return lineup
    }

    private func validTournamentLineup(_ lineup: [BattleSnapshot], participantID: UUID) -> Bool {
        validLineup(lineup, participantID: participantID, size: 3)
    }

    /// 남이 보낸 출전팀을 그대로 믿지 않는다 — 레벨은 눕히지만 종족값·기술은 와이어에서 온다.
    /// 토너먼트(3마리)와 체육관(4마리)이 머릿수만 다르고 검사는 같다.
    private func validLineup(_ lineup: [BattleSnapshot], participantID: UUID, size: Int) -> Bool {
        guard lineup.count == size, lineup.allSatisfy({ $0.level == 50 }),
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
