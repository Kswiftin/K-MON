import Foundation
import Network
import UserNotifications

// MARK: - 프로토콜

/// 피어 간 대전 메시지. 와이어 포맷 = 4바이트 길이(big-endian) + JSON.
/// 턴 결과는 보내지 않는다 — 양쪽이 (스냅샷, seed, 기술 선택)만 교환하고 각자 같은 결정적
/// 엔진으로 해상한다. 결과 필드가 없으니 결과 변조도 없다.
/// 1:1 LAN 대전은 맞짱(턴제 기술 대전) 하나다. 여러 명이 달리는 레이스는 포켓애슬론
/// (`MultiplayerRoomCenter` + `PokeathlonRace`)이 담당한다 — 호스트가 판정하는 방식.
enum NetMessage: Codable, Sendable {
    /// `rulesVersion` 은 대전 규칙(턴 순서·데미지 계산)의 버전이다. 이 대전은 결과를 주고받지 않고
    /// **두 피어가 각자 계산**하므로, 규칙이 다르면 같은 배틀을 서로 다르게 본다(HP·승패가 어긋난다).
    /// 옵셔널인 이유는 이 필드가 없던 버전이 보낸 메시지도 읽어서 "구버전이라 못 붙는다"고
    /// 알려주기 위해서다 — 필수 필드로 두면 디코딩이 실패해 아무 설명 없이 조용히 무시된다.
    case challenge(snapshot: BattleSnapshot, seed: UInt64, profile: BattleRankProfile, rulesVersion: Int?)
    case accept(snapshot: BattleSnapshot, profile: BattleRankProfile, rulesVersion: Int?)
    case decline
    case move(turn: Int, moveIndex: Int)   // moveIndex -1 = 발버둥(PP 소진)
    case forfeit
}

/// 발견된 대전 상대.
struct BattlePeer: Identifiable, Equatable {
    let name: String            // 표시 이름(고유 접미 제거)
    let serviceName: String     // Bonjour 광고 원본(고유) — id·self 판정용
    let endpoint: NWEndpoint
    let rank: BattleRank?
    var id: String { serviceName }
    static func == (l: Self, r: Self) -> Bool { l.serviceName == r.serviceName }
}

/// 진행 중 대전 상태(뷰 렌더 소스).
struct NetBattleState {
    var iAmA: Bool                      // challenger = A (엔진 좌변)
    var my: BattleSnapshot
    var opp: BattleSnapshot
    var myStats: BattleStats
    var oppStats: BattleStats
    var myHP: Int
    var oppHP: Int
    var myMoves: [MoveSpec]
    var oppMoves: [MoveSpec]
    var myPP: [Int]
    var oppPP: [Int]
    var rng: SplitMix64
    var turn = 1
    var myChoice: Int?
    var oppChoice: Int?
    var events: [NetBattleEvent] = []

    /// 내가 고를 수 있는 기술이 하나도 없으면 발버둥.
    var mustStruggle: Bool { !myPP.contains { $0 > 0 } }

    func move(forIndex idx: Int, mine: Bool) -> MoveSpec {
        if idx < 0 { return .struggle() }
        let set = mine ? myMoves : oppMoves
        return idx < set.count ? set[idx] : .struggle()
    }
}

// MARK: - BattleCenter

/// LAN 대전 허브 — Bonjour 광고/탐색, 신청/수락, 턴 교환까지 전 상태를 들고 있는 단일 소스.
/// 앱 기동 시 start() — 팝오버가 닫혀 있어도 신청을 받아 알림을 쏠 수 있어야 한다.
@MainActor
@Observable
final class BattleCenter {
    nonisolated static let serviceType = "_ptbbattle._tcp"
    private nonisolated static let maxMessageBytes: UInt32 = 1_000_000

    enum Phase: Equatable {
        case ready                          // 대기(광고/탐색 중)
        case preparing                      // 내 스냅샷·무브셋 로딩
        case challenging(peer: String)      // 신청 보냄
        case incoming(peer: String)         // 신청 받음
        case battling
        case finished(iWon: Bool?, byForfeit: Bool)
    }

    private(set) var phase: Phase = .ready
    private(set) var peers: [BattlePeer] = []
    /// 수동(IP) 연결용 — 사내망 등 mDNS 멀티캐스트가 막힌 네트워크에선 자동 탐색이 안 되므로
    /// 이 주소를 상대에게 알려주고 직접 연결받는다.
    private(set) var listeningPort: UInt16?
    private(set) var battle: NetBattleState?
    private(set) var incomingSnapshot: BattleSnapshot?   // 수락 화면에서 상대 미리보기
    private(set) var opponentRankProfile: BattleRankProfile?
    private(set) var rankedStake = 0
    private(set) var lastRankDelta = 0
    private(set) var lastError: String?
    /// 팝오버가 열려 있을 때 배틀 탭으로 유도하기 위한 신호(뷰가 소비).
    var pendingAttention = false
    /// 배틀이 잡히거나 걸릴 때 창을 자동으로 열고 고정하게 하는 신호(AppDelegate 가 관찰).
    /// 배틀 관련 phase 면 true — 창을 띄우고 닫히지 않게 유지한다.
    var wantsPinnedWindow: Bool {
        switch phase {
        case .ready: return false
        default: return true   // preparing/challenging/incoming/battling/finished
        }
    }
    private let companion: CompanionStore
    let multiplayer: MultiplayerRoomCenter
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var incomingSeed: UInt64 = 0
    private var myName: String          // 표시 이름(상대 카드·스냅샷 trainer)
    private var didSettleRankedBrawl = false
    private(set) var isPracticeBattle = false
    private(set) var teamPractice: TeamPracticeBattle?
    var rankedTeamSize = 1
    private let myServiceName: String   // Bonjour 광고 이름 — 고유 접미로 같은 계정명 두 기기 충돌 방지

    init(companion: CompanionStore) {
        self.companion = companion
        self.multiplayer = MultiplayerRoomCenter(companion: companion)
        // 표시 이름 우선순위: 사용자가 정한 트레이너 이름 → 계정 풀네임 → 호스트명 → "Trainer".
        let trainer = companion.trainerName.trimmingCharacters(in: .whitespaces)
        let name = !trainer.isEmpty ? trainer
            : (NSFullUserName().isEmpty ? (Host.current().localizedName ?? "Trainer") : NSFullUserName())
        self.myName = name
        // 고유 접미(#xxxxxx) — 같은 사람 이름의 두 Mac이 서로를 "자기"로 오인 필터링하지 않게 한다.
        // 표시할 땐 접미를 떼고, self·id 판정은 이 전체 문자열로 한다.
        self.myServiceName = "\(name)#\(String(UUID().uuidString.prefix(6)))"
    }

    /// 현재 트레이너 표시 이름 — 스냅샷 trainer 필드에 넣는다(설정 후 바뀌어도 최신값).
    private var trainerDisplayName: String {
        let trainer = companion.trainerName.trimmingCharacters(in: .whitespaces)
        return !trainer.isEmpty ? trainer : myName
    }

    /// Bonjour 광고 이름에서 표시 이름 복원 — 마지막 "#고유접미"를 뗀다.
    private nonisolated static func displayName(fromService service: String) -> String {
        guard let hash = service.lastIndex(of: "#") else { return service }
        return String(service[service.startIndex..<hash])
    }

    private var l: L { companion.l }

    var incomingRankedStake: Int {
        guard let opponentRankProfile else { return 0 }
        return BattleRank.stake(challenger: opponentRankProfile.rank, defender: companion.battleRank)
    }

    // MARK: 기동/정지

    func start() {
        startListener()
        startBrowser()
        multiplayer.startBrowsing()
    }

    /// Bonjour 광고/탐색 파라미터 — `includePeerToPeer` 로 AWDL(피어투피어)까지 켠다.
    /// 사내·게스트 Wi-Fi 처럼 AP 가 클라이언트 간 mDNS 멀티캐스트를 막는 망에선 이게 없으면
    /// 자동 탐색이 조용히 빈다(직접 IP 연결은 unicast 라 되는데 탐색만 안 되는 전형 증상).
    private nonisolated static func discoveryParameters() -> NWParameters {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        return params
    }

    private func startListener() {
        do {
            let listener = try NWListener(using: Self.discoveryParameters())
            let rankRecord = NWTXTRecord(["rankPoints": String(companion.battleRank.points)])
            listener.service = NWListener.Service(name: myServiceName, type: Self.serviceType,
                                                  domain: nil, txtRecord: rankRecord)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.acceptConnection(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = listener.port?.rawValue
                    Task { @MainActor in
                        self?.listeningPort = port
                        AppLog.write("battle listener ready port=\(port ?? 0) advertising=\(Self.serviceType)")
                    }
                case .waiting(let e):
                    // 로컬 네트워크 권한 거부·mDNS 차단 → .failed 가 아니라 .waiting 으로 조용히 멈춘다.
                    // 사용자에게 원인(자동 탐색 불가)을 노출해 수동 연결로 유도한다.
                    Task { @MainActor in
                        AppLog.write("battle listener waiting: \(e) — local network blocked?")
                        self?.lastError = self?.l.battleDiscoveryBlocked
                    }
                case .failed(let e):
                    Task { @MainActor in
                        AppLog.write("battle listener failed: \(e) — restarting")
                        self?.listener = nil
                        self?.listeningPort = nil
                        // 슬립 복귀 등 일시 실패 재시도(1회성 지연).
                        try? await Task.sleep(for: .seconds(5))
                        self?.startListener()
                    }
                default:
                    break
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            AppLog.write("battle listener start failed: \(error)")
        }
    }

    private func startBrowser() {
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil),
                                using: Self.discoveryParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.updatePeers(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in AppLog.write("battle browser ready — scanning \(Self.serviceType)") }
            case .waiting(let e):
                // 권한 거부·차단 → 조용한 무한 대기. 원인을 노출하고 계속 대기(권한을 켜면 자동 복구).
                Task { @MainActor in
                    AppLog.write("battle browser waiting: \(e) — local network blocked?")
                    self?.lastError = self?.l.battleDiscoveryBlocked
                }
            case .failed:
                Task { @MainActor in
                    self?.browser = nil
                    try? await Task.sleep(for: .seconds(5))
                    self?.startBrowser()
                }
            default:
                break
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func updatePeers(_ results: Set<NWBrowser.Result>) {
        peers = results.compactMap { r in
            guard case .service(let name, _, _, _) = r.endpoint else { return nil }
            guard name != myServiceName else { return nil }   // 내 광고만 제외(고유 접미로 정확히 판정)
            let points: Int?
            if case .bonjour(let record) = r.metadata,
               let raw = record["rankPoints"], let value = Int(raw) {
                points = min(BattleRank.maximumPoints, max(0, value))
            } else {
                points = nil   // 업데이트 전 클라이언트도 목록에서 숨기지 않는다.
            }
            return BattlePeer(name: Self.displayName(fromService: name), serviceName: name,
                              endpoint: r.endpoint, rank: points.map { BattleRank(points: $0) })
        }.sorted { $0.name < $1.name }
        AppLog.write("battle peers updated: \(results.count) result(s), \(peers.count) after self-filter")
        if !peers.isEmpty { lastError = nil }   // 상대가 보이면 이전 차단 경고 해제
    }

    // MARK: 신청 (challenger = A)

    func startRankedPractice() {
        guard case .ready = phase else { return }
        guard companion.ownedMons.count >= rankedTeamSize else {
            lastError = "출전할 포켓몬이 부족합니다."
            return
        }
        phase = .preparing
        Task {
            var myTeam: [BattleSnapshot] = []
            for mon in companion.ownedMons.prefix(rankedTeamSize) {
                if let snapshot = await companion.battleSnapshot(for: mon, level: 50) { myTeam.append(snapshot) }
            }
            guard myTeam.count == rankedTeamSize else {
                phase = .ready; lastError = l.battleStatsFailed; return
            }
            var cpuTeam: [BattleSnapshot] = []
            for opponentID in Array([25, 59, 94, 130, 143, 149].shuffled().prefix(rankedTeamSize)) {
                guard let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: opponentID) else { continue }
                let moves = await PokeAPIClient.shared.moveSet(speciesID: opponentID, level: 50, types: profile.types)
                cpuTeam.append(BattleSnapshot(speciesID: opponentID, name: "CPU #\(opponentID)", trainer: "CPU",
                                              level: 50, nature: nil, isShiny: false, types: profile.types,
                                              base: profile.stats, moves: moves))
            }
            guard cpuTeam.count == rankedTeamSize else { phase = .ready; lastError = l.battleStatsFailed; return }
            isPracticeBattle = true
            teamPractice = TeamPracticeBattle(mine: myTeam.map(TeamBattleSlot.init),
                                              opponents: cpuTeam.map(TeamBattleSlot.init),
                                              rng: SplitMix64(seed: UInt64.random(in: UInt64.min...UInt64.max)))
            opponentRankProfile = BattleRankProfile(rank: companion.battleRank, stardust: 0)
            phase = .battling; rankedStake = 0; pendingAttention = true
        }
    }

    func chooseTeamPracticeMove(_ index: Int) {
        guard var practice = teamPractice, practice.useMove(index) else { return }
        teamPractice = practice
        if let result = practice.result { phase = .finished(iWon: result, byForfeit: false) }
    }

    func switchTeamPractice(to index: Int) {
        guard var practice = teamPractice, practice.switchMine(to: index) else { return }
        teamPractice = practice
        // 교체는 이제 턴을 쓰므로 상대가 그 사이 공격한다 — 마지막 한 마리가 거기서 쓰러질 수 있다.
        if let result = practice.result { phase = .finished(iWon: result, byForfeit: false) }
    }

    func challenge(_ peer: BattlePeer) {
        challengeEndpoint(peer.endpoint, displayName: peer.name)
    }

    /// mDNS 가 막힌 네트워크(사내망 등)용 — "IP:포트" 직접 입력 신청.
    func challengeManual(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2, !parts[0].isEmpty,
              let rawPort = UInt16(parts[1]), let port = NWEndpoint.Port(rawValue: rawPort) else {
            lastError = l.battleBadAddress
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(String(parts[0])), port: port)
        challengeEndpoint(endpoint, displayName: trimmed)
    }

    /// 내 수동 연결 주소("IP:포트") — 리스너 준비 전/IP 미확인이면 nil.
    var myManualAddress: String? {
        guard let port = listeningPort, let ip = Self.localIPv4() else { return nil }
        return "\(ip):\(port)"
    }

    private func challengeEndpoint(_ endpoint: NWEndpoint, displayName: String) {
        guard case .ready = phase else { return }
        phase = .preparing
        lastError = nil
        Task { @MainActor in
            guard let snapshot = await buildMySnapshot(levelOverride: 50) else {
                phase = .ready
                lastError = l.battleStatsFailed
                return
            }
            guard case .preparing = phase else { return }   // 준비 중 취소/신청 수신
            let seed = UInt64.random(in: .min ... .max)
            incomingSeed = seed
            // includePeerToPeer 파라미터로 연결 — 브라우저가 AWDL(피어투피어)로 찾은 상대는
            // 평범한 .tcp 로는 연결이 안 붙는다(수동 IP 는 직접 hostPort 라 됐던 이유). 리스너/브라우저와
            // 같은 파라미터를 써야 mDNS·AWDL 어느 경로로 발견됐든 연결이 성립한다.
            let conn = NWConnection(to: endpoint, using: Self.discoveryParameters())
            connection = conn
            phase = .challenging(peer: displayName)
            conn.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.connectionState(state, conn: conn) }
            }
            conn.start(queue: .main)
            send(.challenge(snapshot: snapshot, seed: seed,
                            profile: companion.battleRankProfile,
                            rulesVersion: BattleEngine.rulesVersion), over: conn)
            receiveLoop(conn)
            pendingMySnapshot = snapshot
        }
    }

    /// en0 우선 IPv4 — 수동 연결 주소 표기용.
    nonisolated static func localIPv4() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var fallback: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            // String(cString:) 의 배열 오버로드만 Swift 6 에서 deprecated 이다 — 포인터 오버로드로 넘긴다.
            let ip = host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            if name == "en0" { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }

    func cancelChallenge() {
        if case .challenging = phase { dropConnection(); phase = .ready }
        if case .preparing = phase { phase = .ready }
    }

    // MARK: 수신 (defender = B)

    private func acceptConnection(_ conn: NWConnection) {
        guard case .ready = phase, connection == nil else {
            // 대전 중 새 신청 — 정중히 거절하고 닫는다.
            conn.start(queue: .main)
            send(.decline, over: conn)
            conn.cancel()
            return
        }
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.connectionState(state, conn: conn) }
        }
        conn.start(queue: .main)
        receiveLoop(conn)
    }

    func acceptIncoming() {
        guard case .incoming = phase, let conn = connection, let oppSnapshot = incomingSnapshot else { return }
        phase = .preparing
        Task { @MainActor in
            guard let mine = await buildMySnapshot(levelOverride: 50) else {
                send(.decline, over: conn)
                dropConnection()
                phase = .ready
                lastError = l.battleStatsFailed
                return
            }
            let mineProfile = companion.battleRankProfile
            let stake = BattleRank.stake(challenger: opponentRankProfile?.rank ?? BattleRank(),
                                         defender: mineProfile.rank)
            guard stake == 0 || (mineProfile.stardust >= stake && (opponentRankProfile?.stardust ?? 0) >= stake) else {
                send(.decline, over: conn)
                dropConnection(); phase = .ready; lastError = "랭크전 판돈이 부족합니다."
                return
            }
            send(.accept(snapshot: mine, profile: mineProfile,
                         rulesVersion: BattleEngine.rulesVersion), over: conn)
            beginBattle(my: mine, opp: oppSnapshot, iAmA: false, seed: incomingSeed)
        }
    }

    func declineIncoming() {
        guard case .incoming = phase, let conn = connection else { return }
        send(.decline, over: conn)
        dropConnection()
        phase = .ready
    }

    // MARK: 대전 진행

    func chooseMove(_ index: Int) {
        guard case .battling = phase, var b = battle, b.myChoice == nil else { return }
        let idx = b.mustStruggle ? -1 : index
        if idx >= 0 {
            guard idx < b.myPP.count, b.myPP[idx] > 0 else { return }
        }
        b.myChoice = idx
        if isPracticeBattle {
            let available = b.oppPP.indices.filter { b.oppPP[$0] > 0 }
            b.oppChoice = available.randomElement() ?? -1
            battle = b
            resolveIfReady()
            return
        }
        guard let conn = connection else { return }
        battle = b
        send(.move(turn: b.turn, moveIndex: idx), over: conn)
        resolveIfReady()
    }

    func forfeit() {
        if isPracticeBattle {
            phase = .finished(iWon: false, byForfeit: true)
            return
        }
        if let conn = connection { send(.forfeit, over: conn) }
        dropConnection()
        phase = .finished(iWon: false, byForfeit: true)
        settleRankedBrawlIfNeeded(won: false)
    }

    func dismissResult() {
        battle = nil
        teamPractice = nil
        if case .finished = phase { phase = .ready }
        isPracticeBattle = false
    }

    private var pendingMySnapshot: BattleSnapshot?

    private func beginBattle(my: BattleSnapshot, opp: BattleSnapshot, iAmA: Bool, seed: UInt64) {
        didSettleRankedBrawl = false
        lastRankDelta = 0
        if let opponentRankProfile {
            rankedStake = iAmA
                ? BattleRank.stake(challenger: companion.battleRank, defender: opponentRankProfile.rank)
                : BattleRank.stake(challenger: opponentRankProfile.rank, defender: companion.battleRank)
        } else {
            rankedStake = 0
        }
        let myStats = my.effectiveStats(), oppStats = opp.effectiveStats()
        let myMoves = my.moves ?? MoveSpec.fallbackSet(types: my.types)
        let oppMoves = opp.moves ?? MoveSpec.fallbackSet(types: opp.types)
        battle = NetBattleState(iAmA: iAmA, my: my, opp: opp,
                                myStats: myStats, oppStats: oppStats,
                                myHP: myStats.hp, oppHP: oppStats.hp,
                                myMoves: myMoves, oppMoves: oppMoves,
                                myPP: myMoves.map(\.pp), oppPP: oppMoves.map(\.pp),
                                rng: SplitMix64(seed: seed))
        phase = .battling
        pendingAttention = true
    }

    /// 양쪽 선택이 모이면 턴 해상 — challenger 를 A 로 고정해 양쪽이 같은 좌변으로 계산.
    private func resolveIfReady() {
        guard var b = battle, let myIdx = b.myChoice, let oppIdx = b.oppChoice else { return }
        let myMove = b.move(forIndex: myIdx, mine: true)
        let oppMove = b.move(forIndex: oppIdx, mine: false)
        if myIdx >= 0 { b.myPP[myIdx] = max(0, b.myPP[myIdx] - 1) }
        if oppIdx >= 0 { b.oppPP[oppIdx] = max(0, b.oppPP[oppIdx] - 1) }

        var hpA = b.iAmA ? b.myHP : b.oppHP
        var hpB = b.iAmA ? b.oppHP : b.myHP
        let events = BattleEngine.resolveTurn(
            a: b.iAmA ? b.my : b.opp, b: b.iAmA ? b.opp : b.my,
            statsA: b.iAmA ? b.myStats : b.oppStats, statsB: b.iAmA ? b.oppStats : b.myStats,
            hpA: &hpA, hpB: &hpB,
            moveA: b.iAmA ? myMove : oppMove, moveB: b.iAmA ? oppMove : myMove,
            rng: &b.rng)
        b.myHP = b.iAmA ? hpA : hpB
        b.oppHP = b.iAmA ? hpB : hpA
        b.events.append(contentsOf: events)
        b.turn += 1
        b.myChoice = nil
        b.oppChoice = nil
        battle = b

        if b.myHP <= 0 || b.oppHP <= 0 {
            let iWon: Bool? = b.myHP > 0 ? true : (b.oppHP > 0 ? false : nil)
            dropConnection()
            phase = .finished(iWon: iWon, byForfeit: false)
            if let iWon, !isPracticeBattle { settleRankedBrawlIfNeeded(won: iWon) }
        }
    }

    // MARK: 메시지 처리

    private func handle(_ message: NetMessage) {
        switch message {
        case .challenge(let snapshot, let seed, let profile, let rulesVersion):
            guard case .ready = phase else { return }   // 자기 연결로 challenge 재수신 등 비정상
            guard rulesVersion == BattleEngine.rulesVersion else {
                send(.decline, over: connection)
                dropConnection()
                phase = .ready
                lastError = l.battleRulesMismatch
                AppLog.write("battle challenge declined: rules version \(rulesVersion.map(String.init) ?? "none")")
                return
            }
            if UserDefaults.standard.object(forKey: "doNotDisturb") as? Bool ?? false {
                send(.decline, over: connection)
                dropConnection()
                phase = .ready
                AppLog.write("battle challenge declined: do not disturb enabled")
                return
            }
            guard !snapshot.types.isEmpty, (1...100).contains(snapshot.level) else {
                send(.decline, over: connection)
                dropConnection()
                return
            }
            incomingSnapshot = snapshot
            incomingSeed = seed
            opponentRankProfile = profile
            phase = .incoming(peer: snapshot.trainer ?? snapshot.name)
            pendingAttention = true
            postChallengeNotification(snapshot)
        case .accept(let snapshot, let profile, let rulesVersion):
            guard case .challenging = phase, let mine = pendingMySnapshot else { return }
            guard rulesVersion == BattleEngine.rulesVersion else {
                dropConnection(); phase = .ready; lastError = l.battleRulesMismatch
                return
            }
            guard !snapshot.types.isEmpty, (1...100).contains(snapshot.level) else {
                dropConnection(); phase = .ready; return
            }
            let stake = BattleRank.stake(challenger: companion.battleRank, defender: profile.rank)
            guard stake == 0 || (companion.availableTokens >= stake && profile.stardust >= stake) else {
                dropConnection(); phase = .ready; lastError = "랭크전 판돈이 부족합니다."
                return
            }
            opponentRankProfile = profile
            beginBattle(my: mine, opp: snapshot, iAmA: true, seed: incomingSeed)
        case .decline:
            if case .challenging = phase {
                dropConnection()
                phase = .ready
                lastError = l.battleDeclined
            }
        case .move(let turn, let moveIndex):
            guard case .battling = phase, var b = battle, b.oppChoice == nil, turn == b.turn else { return }
            guard moveIndex >= -1, moveIndex < 4 else { return }
            b.oppChoice = moveIndex
            battle = b
            resolveIfReady()
        case .forfeit:
            if case .battling = phase {
                dropConnection()
                phase = .finished(iWon: true, byForfeit: true)
                settleRankedBrawlIfNeeded(won: true)
            }
        }
    }

    private func connectionState(_ state: NWConnection.State, conn: NWConnection) {
        guard conn === connection else { return }
        switch state {
        case .ready:
            AppLog.write("battle connection ready")
        case .waiting(let e):
            AppLog.write("battle connection waiting: \(e)")   // 경로 못 붙음(p2p 파라미터·권한·방화벽)
        case .preparing:
            break
        case .failed(let e):
            AppLog.write("battle connection failed: \(e)")
            connectionDropped()
        case .cancelled:
            connectionDropped()
        default:
            break
        }
    }

    private func connectionDropped() {
        guard connection != nil else { return }
        connection = nil
        switch phase {
        case .battling:
            // 상대 이탈 = 몰수승.
            phase = .finished(iWon: true, byForfeit: true)
            settleRankedBrawlIfNeeded(won: true)
        case .challenging, .incoming, .preparing:
            phase = .ready
            lastError = l.battleConnectionLost
        default:
            break
        }
        incomingSnapshot = nil
    }

    private func dropConnection() {
        let conn = connection
        connection = nil          // connectionDropped 재진입 차단(cancel 콜백)
        conn?.cancel()
        incomingSnapshot = nil
    }

    private func settleRankedBrawlIfNeeded(won: Bool) {
        guard battle != nil, !didSettleRankedBrawl, let opponent = opponentRankProfile else { return }
        didSettleRankedBrawl = true
        lastRankDelta = companion.settleRankedBrawl(won: won, opponent: opponent.rank, stake: rankedStake)
    }

    // MARK: 전송/수신 (길이 프리픽스 프레이밍)

    private func send(_ message: NetMessage, over conn: NWConnection?) {
        guard let conn else { return }
        guard let payload = try? JSONEncoder().encode(message) else { return }
        var frame = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        frame.append(payload)
        conn.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, _ in
            guard let data, data.count == 4 else {
                Task { @MainActor in self?.connectionDropped() }
                return
            }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            guard length > 0, length <= Self.maxMessageBytes else {
                Task { @MainActor in self?.connectionDropped() }
                return
            }
            conn.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { data, _, _, _ in
                guard let data, data.count == Int(length),
                      let message = try? JSONDecoder().decode(NetMessage.self, from: data) else {
                    Task { @MainActor in self?.connectionDropped() }
                    return
                }
                Task { @MainActor in
                    guard let self, conn === self.currentConnection() else { return }
                    self.handle(message)
                    self.receiveLoop(conn)
                }
            }
        }
    }

    private func currentConnection() -> NWConnection? { connection }

    // MARK: 내 스냅샷 (무브셋 포함)

    private func buildMySnapshot(levelOverride: Int? = nil) async -> BattleSnapshot? {
        await companion.ensureInheritedMoves()
        guard let active = companion.state.active, let speciesID = companion.currentSpeciesID else { return nil }
        guard let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID) else { return nil }
        let level = levelOverride ?? active.level
        let moves = active.learnedMoves.isEmpty
            ? await PokeAPIClient.shared.moveSet(speciesID: speciesID, level: level, types: profile.types)
            : active.learnedMoves
        return BattleSnapshot(speciesID: speciesID,
                              name: companion.displayName,
                              trainer: trainerDisplayName,
                              level: level,
                              nature: active.nature,
                              isShiny: active.isShiny,
                              types: profile.types,
                              base: profile.stats,
                              moves: moves)
    }

    // MARK: 알림

    private func postChallengeNotification(_ snapshot: BattleSnapshot) {
        guard !(UserDefaults.standard.object(forKey: "doNotDisturb") as? Bool ?? false) else { return }
        AppLog.write("battle challenge received from \(snapshot.trainer ?? "?") — posting notification")
        guard AppEnv.isBundledApp else { AppLog.write("battle notif skipped: not bundled app"); return }
        let content = UNMutableNotificationContent()
        content.title = l.battleChallengeNotifTitle
        content.body = l.battleChallengeNotifBody(snapshot.trainer ?? "?",
                                                  pokemon: snapshot.name, level: snapshot.level)
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        // completion 은 시스템이 **백그라운드 큐**에서 부른다 — @MainActor 문맥에서 만든 클로저가 격리를
        // 상속하면 런타임 executor 검사에 걸려 SIGTRAP(_dispatch_assert_queue_fail). @Sendable 로 격리 차단.
        // 앱이 포그라운드여도 배틀 신청 알림이 보이도록 권한을 요청한다.
        center.getNotificationSettings { @Sendable settings in
            AppLog.write("battle notif auth status=\(settings.authorizationStatus.rawValue) (0=notDetermined 1=denied 2=authorized 3=provisional)")
        }
        center.add(
            UNNotificationRequest(identifier: "battle-challenge-\(snapshot.speciesID)-\(incomingSeed)",
                                  content: content, trigger: nil)) { @Sendable error in
            if let error { AppLog.write("battle notif add failed: \(error)") }
            else { AppLog.write("battle notif posted") }
        }
    }
}
