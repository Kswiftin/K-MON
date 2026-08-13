import Foundation
import Network
import UserNotifications

// MARK: - 프로토콜

/// 피어 간 대전 메시지. 와이어 포맷 = 4바이트 길이(big-endian) + JSON.
/// 턴 결과는 보내지 않는다 — 양쪽이 (스냅샷, seed, 기술 선택)만 교환하고 각자 같은 결정적
/// 엔진으로 해상한다. 결과 필드가 없으니 결과 변조도 없다.
enum NetMessage: Codable, Sendable {
    case challenge(snapshot: BattleSnapshot, seed: UInt64)
    case accept(snapshot: BattleSnapshot)
    case decline
    case move(turn: Int, moveIndex: Int)   // moveIndex -1 = 발버둥(PP 소진)
    case forfeit
}

/// 발견된 대전 상대.
struct BattlePeer: Identifiable, Equatable {
    let name: String
    let endpoint: NWEndpoint
    var id: String { name }
    static func == (l: Self, r: Self) -> Bool { l.name == r.name }
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
    private(set) var lastError: String?
    /// 팝오버가 열려 있을 때 배틀 탭으로 유도하기 위한 신호(뷰가 소비).
    var pendingAttention = false

    private let companion: CompanionStore
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var incomingSeed: UInt64 = 0
    private var myName: String

    init(companion: CompanionStore) {
        self.companion = companion
        self.myName = NSFullUserName().isEmpty ? Host.current().localizedName ?? "Trainer" : NSFullUserName()
    }

    private var l: L { companion.l }

    // MARK: 기동/정지

    func start() {
        startListener()
        startBrowser()
    }

    private func startListener() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: myName, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.acceptConnection(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = listener.port?.rawValue
                    Task { @MainActor in self?.listeningPort = port }
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
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.updatePeers(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in
                    self?.browser = nil
                    try? await Task.sleep(for: .seconds(5))
                    self?.startBrowser()
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func updatePeers(_ results: Set<NWBrowser.Result>) {
        peers = results.compactMap { r in
            guard case .service(let name, _, _, _) = r.endpoint else { return nil }
            guard name != myName else { return nil }   // 내 광고 제외
            return BattlePeer(name: name, endpoint: r.endpoint)
        }.sorted { $0.name < $1.name }
    }

    // MARK: 신청 (challenger = A)

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
            guard let snapshot = await buildMySnapshot() else {
                phase = .ready
                lastError = l.battleStatsFailed
                return
            }
            guard case .preparing = phase else { return }   // 준비 중 취소/신청 수신
            let seed = UInt64.random(in: .min ... .max)
            incomingSeed = seed
            let conn = NWConnection(to: endpoint, using: .tcp)
            connection = conn
            phase = .challenging(peer: displayName)
            conn.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.connectionState(state, conn: conn) }
            }
            conn.start(queue: .main)
            send(.challenge(snapshot: snapshot, seed: seed), over: conn)
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
            let ip = String(cString: host)
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
            guard let mine = await buildMySnapshot() else {
                send(.decline, over: conn)
                dropConnection()
                phase = .ready
                lastError = l.battleStatsFailed
                return
            }
            send(.accept(snapshot: mine), over: conn)
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
        guard case .battling = phase, var b = battle, b.myChoice == nil, let conn = connection else { return }
        let idx = b.mustStruggle ? -1 : index
        if idx >= 0 {
            guard idx < b.myPP.count, b.myPP[idx] > 0 else { return }
        }
        b.myChoice = idx
        battle = b
        send(.move(turn: b.turn, moveIndex: idx), over: conn)
        resolveIfReady()
    }

    func forfeit() {
        if let conn = connection { send(.forfeit, over: conn) }
        dropConnection()
        phase = .finished(iWon: false, byForfeit: true)
    }

    func dismissResult() {
        battle = nil
        if case .finished = phase { phase = .ready }
    }

    private var pendingMySnapshot: BattleSnapshot?

    private func beginBattle(my: BattleSnapshot, opp: BattleSnapshot, iAmA: Bool, seed: UInt64) {
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
        }
    }

    // MARK: 메시지 처리

    private func handle(_ message: NetMessage) {
        switch message {
        case .challenge(let snapshot, let seed):
            guard case .ready = phase else { return }   // 자기 연결로 challenge 재수신 등 비정상
            guard !snapshot.types.isEmpty, (1...100).contains(snapshot.level) else {
                send(.decline, over: connection)
                dropConnection()
                return
            }
            incomingSnapshot = snapshot
            incomingSeed = seed
            phase = .incoming(peer: snapshot.trainer ?? snapshot.name)
            pendingAttention = true
            postChallengeNotification(snapshot)
        case .accept(let snapshot):
            guard case .challenging = phase, let mine = pendingMySnapshot else { return }
            guard !snapshot.types.isEmpty, (1...100).contains(snapshot.level) else {
                dropConnection(); phase = .ready; return
            }
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
            }
        }
    }

    private func connectionState(_ state: NWConnection.State, conn: NWConnection) {
        guard conn === connection else { return }
        switch state {
        case .failed, .cancelled:
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

    private func buildMySnapshot() async -> BattleSnapshot? {
        guard let active = companion.state.active, let speciesID = companion.currentSpeciesID else { return nil }
        guard let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID) else { return nil }
        let level = BattleSnapshot.level(stageIndex: active.stageIndex,
                                         totalForms: active.totalForms,
                                         stageProgress: companion.progress)
        let moves = await PokeAPIClient.shared.moveSet(speciesID: speciesID, level: level, types: profile.types)
        return BattleSnapshot(speciesID: speciesID,
                              name: companion.displayName,
                              trainer: myName,
                              level: level,
                              nature: active.nature,
                              isShiny: active.isShiny,
                              types: profile.types,
                              base: profile.stats,
                              moves: moves)
    }

    // MARK: 알림

    private func postChallengeNotification(_ snapshot: BattleSnapshot) {
        guard AppEnv.isBundledApp else { return }
        let content = UNMutableNotificationContent()
        content.title = l.battleChallengeNotifTitle
        content.body = l.battleChallengeNotifBody(snapshot.trainer ?? "?",
                                                  pokemon: snapshot.name, level: snapshot.level)
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "battle-challenge-\(snapshot.speciesID)-\(incomingSeed)",
                                  content: content, trigger: nil))
    }
}
