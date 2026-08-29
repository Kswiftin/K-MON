import Foundation
import Network
import Observation
import UserNotifications

struct TradePeer: Identifiable, Equatable {
    var id: String { serviceName }
    let name: String
    let serviceName: String
    let endpoint: NWEndpoint

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.serviceName == rhs.serviceName }
}

struct TradePokemonSnapshot: Codable, Sendable {
    let mon: MonState
    let displayName: String
}

/// 교환으로 넘어가는 추억 한 줄. 앨범 레코드가 아니라 **와이어 전용 값**이다 — `id`·`companionID`·
/// `eventID`·`isHidden` 은 싣지 않는다. 넷 다 받는 쪽이 로컬에서 다시 지어야 하는 값이고,
/// 상대가 부르는 대로 받으면 남의 앨범을 열거나(`companionID`) 이후 진짜 이벤트를 막는다(`eventID`).
struct TradeMemoryEntry: Codable, Sendable, Equatable {
    let body: String
    let source: PokemonMemorySource
    let createdAt: Date
}

/// 한 개체를 따라가는 추억 묶음. `monID` 는 **바인딩 검사용**이다 — 받는 쪽이 지금 받고 있는
/// 개체와 다르면 통째로 버린다.
struct TradeMemoryPayload: Codable, Sendable, Equatable {
    /// 앨범은 개체당 200칸이다. 한 번의 교환이 그 칸을 다 밀어 버리지 못하게 건수를 막는다.
    static let maxEntries = 30
    /// `PokemonMemoryAlbum.record` 의 비-손글씨 계약과 **같은 숫자**여야 한다. 여기만 넓히면
    /// 경계를 통과한 줄이 앨범에서 조용히 버려진다.
    static let bodyLimit = 180
    static let summaryLimit = 280
    /// 교환으로 들어오는 날짜가 놓일 수 있는 창. 앱은 이보다 오래되지 않았고, 아득한 과거는
    /// `daysTogether`(= 친밀도 하트)를 즉시 만점으로 만든다.
    static let maxAge: TimeInterval = 3650 * 24 * 60 * 60

    let monID: UUID
    let summary: String?
    let entries: [TradeMemoryEntry]

    /// 교환으로 들어오는 **모든** 날짜가 같은 창을 쓴다 — 추억의 `createdAt` 과 개체의
    /// `firstMetAt` 이 규칙을 따로 가지면 한쪽은 반드시 빠진다.
    static func clampedDate(_ date: Date, now: Date) -> Date {
        min(max(date, now.addingTimeInterval(-maxAge)), now)
    }

    /// 신뢰경계 클램프다 — `private` 로 두면 원격 페이로드 검증이 무테스트로 남는다.
    /// (`MemoryHomeVisitCenter.valid` 를 열어 둔 이유와 같다.)
    static func sanitized(_ payload: TradeMemoryPayload, now: Date = Date()) -> TradeMemoryPayload {
        TradeMemoryPayload(
            monID: payload.monID,
            summary: payload.summary.flatMap { cleanBody($0, limit: summaryLimit) },
            entries: payload.entries.prefix(maxEntries).compactMap { entry in
                // 손글씨는 트레이너가 직접 쓴 글이라 양방향 모두 오가지 않는다. 앨범의
                // `record` 도 같은 이유로 `.manual` 을 거부하지만, 경계에서도 명시적으로 막는다.
                guard entry.source != .manual,
                      let body = cleanBody(entry.body, limit: bodyLimit) else { return nil }
                return TradeMemoryEntry(body: body, source: entry.source,
                                        createdAt: clampedDate(entry.createdAt, now: now))
            })
    }

    /// 길이만 재고 끝내면 줄바꿈·제어문자가 그대로 통과한다 — 일기와 방문 시트는 고정 높이 칸이라
    /// 넘친 내용을 숨기지 않는다. 공백은 살리고(문장이다) 개행류만 한 칸으로 접는다.
    private static func cleanBody(_ value: String, limit: Int) -> String? {
        let folded = String(String.UnicodeScalarView(value.unicodeScalars.map {
            CharacterSet.newlines.contains($0) || CharacterSet.controlCharacters.contains($0) ? " " : $0
        })).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folded.isEmpty, folded.count <= limit else { return nil }
        return folded
    }
}

/// 신청·수락에 실린 `chatSupported` 가 채팅 지원 여부를 협상한다. 구버전은 그 키를 아예 보내지
/// 않으므로 `nil`(= 미지원)이고, 그때는 `.chat` 프레임을 **보내지 않는다** — 알 수 없는 프레임은
/// 상대의 수신 루프를 세우기 때문이다. 그래서 `protocolVersion` 은 2 그대로다: 채팅이 없다고
/// 교환까지 막을 이유가 없다.
///
/// `.memories` 도 같은 이유로 버전을 올리지 않는다 — **기존 케이스의 모양을 하나도 안 바꾸고**
/// 프레임만 더했다. 구버전은 모르는 프레임을 건너뛰고 수신 루프를 다시 걸므로(`receiveBody`),
/// 추억 없이 교환만 성립한다. 기존 케이스에 인자를 더하면 합성 `Codable` 의 키(`_0`)가 바뀌어
/// 구버전이 커밋 프레임을 못 읽는다 — 그래서 별도 프레임이다.
enum TradeWireMessage: Codable {
    static let protocolVersion = 2

    case request(version: Int, trainer: String, chatSupported: Bool?)
    case rosterRequest(trainer: String)
    case roster([TradePokemonSnapshot])
    case accept(trainer: String, chatSupported: Bool?)
    case chat(BattleChatMessage)
    case decline(reason: String)
    case offer(TradePokemonSnapshot?)
    case confirm(Bool)
    case wish(UUID?)
    case memories(TradeMemoryPayload)
    case commit(UUID)
    case committed(UUID)
    case cancel
}

/// 배틀과 소켓을 분리한 근거리 1:1 교환 허브. 제시 포켓몬이 바뀌면 양쪽 확인을 모두
/// 취소하고, 양쪽이 같은 제안을 확인한 뒤에만 신청자가 커밋을 시작한다.
@MainActor
@Observable
final class PokemonTradeCenter {
    nonisolated static let serviceType = "_kmontrade._tcp"
    private nonisolated static let maxMessageBytes: UInt32 = 1_000_000

    enum Phase: Equatable {
        case ready
        case browsing(peer: String)
        case roster(peer: String)
        case requesting(peer: String)
        case incoming(peer: String)
        case negotiating(peer: String)
        case committing
        case animating
        case completed
        case failed(String)
    }

    private(set) var phase: Phase = .ready
    private(set) var peers: [TradePeer] = []
    private(set) var localOffer: TradePokemonSnapshot?
    private(set) var remoteOffer: TradePokemonSnapshot?
    private(set) var remoteRoster: [TradePokemonSnapshot] = []
    private(set) var requestedRemoteMonID: UUID?
    private(set) var remoteRequestedLocalMonID: UUID?
    private(set) var localConfirmed = false
    private(set) var remoteConfirmed = false
    private(set) var chatMessages: [BattleChatMessage] = []
    private(set) var peerSupportsChat = false
    /// 커밋 직전에 도착한 상대의 추억. TCP 는 순서를 지키므로 `.memories` 는 항상 커밋 프레임보다
    /// 먼저 온다 — 여기 담아 뒀다가 **교환이 실제로 성사된 뒤에만** 앨범에 넣는다.
    /// `private(set)` 인 이유는 "협상 밖 프레임은 버퍼에도 안 들어간다" 를 테스트가 봐야 해서다.
    private(set) var pendingIncomingMemories: TradeMemoryPayload?

    /// 화면이 "내 말풍선"을 가리는 키. 상대가 부르는 ID 를 믿지 않으려고 양쪽 모두 **우리가**
    /// 정한다 — `remoteChatSenderID` 는 상대가 ID 를 갈아 끼워도 속도 제한을 못 벗어나게 한다.
    let chatSenderID = UUID()
    private let remoteChatSenderID = UUID()
    private var chatHistory = BattleChatHistory()
    private var chatRateLimiter = BattleChatRateLimiter()

    private let companion: CompanionStore
    private let myName: String
    private let myServiceName: String
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var isInitiator = false
    private(set) var activeTransaction: UUID?

    init(companion: CompanionStore) {
        self.companion = companion
        let trainer = companion.trainerName.trimmingCharacters(in: .whitespaces)
        let fallback = NSFullUserName().isEmpty ? (Host.current().localizedName ?? "Trainer") : NSFullUserName()
        myName = trainer.isEmpty ? fallback : trainer
        myServiceName = "\(trainer.isEmpty ? fallback : trainer)#\(String(UUID().uuidString.prefix(6)))"
    }

    func start() {
        startListener()
        startBrowser()
    }

    func request(_ peer: TradePeer) {
        guard phase == .ready else { return }
        resetSession()
        isInitiator = true
        phase = .requesting(peer: peer.name)
        let connection = NWConnection(to: peer.endpoint, using: Self.parameters())
        attach(connection)
        connection.start(queue: .main)
        send(.request(version: TradeWireMessage.protocolVersion, trainer: myName, chatSupported: true))
    }

    func viewRoster(_ peer: TradePeer) {
        guard phase == .ready else { return }
        resetSession()
        phase = .browsing(peer: peer.name)
        let connection = NWConnection(to: peer.endpoint, using: Self.parameters())
        attach(connection)
        connection.start(queue: .main)
        send(.rosterRequest(trainer: myName))
    }

    func accept() {
        guard case .incoming(let peer) = phase else { return }
        phase = .negotiating(peer: peer)
        send(.accept(trainer: myName, chatSupported: true))
        send(.roster(localRoster))
    }

    func decline() {
        send(.decline(reason: "declined"))
        finishConnection()
    }

    func cancel() {
        send(.cancel)
        finishConnection()
    }

    func selectOffer(_ mon: MonState?) {
        guard case .negotiating = phase else { return }
        localOffer = mon.map { TradePokemonSnapshot(mon: $0, displayName: displayName(for: $0)) }
        localConfirmed = false
        remoteConfirmed = false
        send(.offer(localOffer))
        send(.confirm(false))
    }

    func requestRemotePokemon(_ id: UUID?) {
        guard case .negotiating = phase else { return }
        requestedRemoteMonID = id
        send(.wish(id))
    }

    func offerRequestedPokemon() {
        guard let id = remoteRequestedLocalMonID,
              let mon = companion.ownedMons.first(where: { $0.id == id }) else { return }
        selectOffer(mon)
    }

    private var localRoster: [TradePokemonSnapshot] {
        companion.ownedMons.map { TradePokemonSnapshot(mon: $0, displayName: displayName(for: $0)) }
    }

    func confirm() {
        guard case .negotiating = phase, localOffer != nil, remoteOffer != nil else { return }
        localConfirmed = true
        send(.confirm(true))
        beginCommitIfReady()
    }

    func finishAnimation() {
        guard phase == .animating else { return }
        phase = .completed
    }

    func closeCompleted() { finishConnection() }

    /// 협상 중이고 상대가 채팅을 지원할 때만 나간다. 내 발신 예산은 상대 것과 분리돼 있다.
    func sendChat(_ body: String) {
        guard case .negotiating = phase, peerSupportsChat,
              let text = BattleChatPolicy.normalizedBody(body),
              chatRateLimiter.allows(chatSenderID) else { return }
        let message = BattleChatMessage(senderID: chatSenderID, senderName: myName, body: text)
        appendChat(message)
        send(.chat(message))
    }

    /// 상대 프레임의 네 필드는 전부 상대가 부르는 값이다 — 길이·정규형을 다시 재고, 이름은 우리가
    /// 아는 상대 이름으로 덮고, 속도 제한은 상대가 못 바꾸는 키로 세고, `id` 는 새로 짓는다.
    /// (`id` 는 `Identifiable` 키라 상대가 같은 값을 두 번 보내면 화면의 `ForEach` 가 무너진다.)
    private func acceptChat(_ incoming: BattleChatMessage) {
        guard case .negotiating(let peer) = phase,
              let body = BattleChatPolicy.normalizedBody(incoming.body), body == incoming.body,
              chatRateLimiter.allows(remoteChatSenderID) else { return }
        appendChat(BattleChatMessage(senderID: remoteChatSenderID, senderName: peer, body: body))
    }

    private func appendChat(_ message: BattleChatMessage) {
        chatHistory.append(message)
        chatMessages = chatHistory.messages
    }

    private func displayName(for mon: MonState) -> String {
        if let nickname = mon.nickname, !nickname.isEmpty { return nickname }
        let code = companion.language.rawValue
        return mon.names?[mon.currentID]?[code] ?? "#\(mon.currentID)"
    }

    private func beginCommitIfReady() {
        guard isInitiator, localConfirmed, remoteConfirmed,
              let mine = localOffer, remoteOffer != nil else { return }
        let id = UUID()
        activeTransaction = id
        phase = .committing
        sendMemories(for: mine.mon.id)
        send(.commit(id))
    }

    /// 추억은 **커밋 직전 한 번만** 나간다. 확인 단계에서 보내면 취소·확인 철회로 끝난 협상에도
    /// 이미 상대 손에 가 있게 된다 — 되돌릴 방법이 없다.
    private func sendMemories(for monID: UUID) {
        guard let payload = companion.tradeMemoryPayload(for: monID) else { return }
        send(.memories(payload))
    }

    func receive(_ message: TradeWireMessage) {
        switch message {
        case .rosterRequest(let trainer):
            guard phase == .ready else { return }
            send(.roster(localRoster))
            AppLog.write("trade roster preview sent to \(BattleChatPolicy.displayName(trainer) ?? "?")")
        case .roster(let roster):
            remoteRoster = Array(roster.prefix(100))
            if case .browsing(let peer) = phase { phase = .roster(peer: peer) }
        // 트레이너 이름은 상대가 부르는 값이고 프레임 상한(1MB)까지 채울 수 있다. 그 이름은 협상
        // 헤더와 **채팅 행마다** 박히는데 두 곳 다 `lineLimit` 이 없다 — 국면에 넣기 전에 자른다.
        // 같은 클램프를 두 분기에 건다: 신청을 받는 쪽(`.request`)과 거는 쪽(`.accept`).
        case .request(let version, let trainer, let chatSupported):
            guard version == TradeWireMessage.protocolVersion, phase == .ready,
                  let peer = BattleChatPolicy.displayName(trainer) else {
                send(.decline(reason: "busy-or-incompatible")); return
            }
            isInitiator = false
            peerSupportsChat = chatSupported == true
            phase = .incoming(peer: peer)
            postPrivateMessageNotification()
        case .accept(let trainer, let chatSupported):
            // 이름이 비면 브라우저가 이미 보여 준 이름을 그대로 쓴다 — 여기서 세션을 깰 이유는 없다.
            guard case .requesting(let browsed) = phase else { return }
            peerSupportsChat = chatSupported == true
            phase = .negotiating(peer: BattleChatPolicy.displayName(trainer) ?? browsed)
            send(.roster(localRoster))
        case .chat(let message):
            acceptChat(message)
        case .decline:
            phase = .failed("교환 신청이 거절되었습니다.")
            connection?.cancel(); connection = nil
        case .offer(let offer):
            remoteOffer = offer
            localConfirmed = false
            remoteConfirmed = false
        case .confirm(let confirmed):
            remoteConfirmed = confirmed
            if !confirmed { localConfirmed = false }
            beginCommitIfReady()
        case .wish(let id):
            remoteRequestedLocalMonID = id
        // 협상 밖에서 온 추억은 버퍼에도 안 넣는다 — 아무 때나 받아 두면 다음 교환에 실린다.
        // 담는 순간 클램프한다: 버퍼에 원본이 앉아 있으면 적용 경로마다 검증을 다시 걸어야 한다.
        case .memories(let payload):
            switch phase {
            case .negotiating, .committing: pendingIncomingMemories = .sanitized(payload)
            default: AppLog.write("trade memories frame dropped — no active negotiation")
            }
        case .commit(let id):
            guard !isInitiator, localConfirmed, remoteConfirmed,
                  let mine = localOffer, let theirs = remoteOffer else {
                send(.decline(reason: "trade-changed")); return
            }
            phase = .committing
            // 내 추억은 상대가 교환을 반영하기 **전에** 보내야 한다. 성사 뒤에 보내면
            // `.committed` 를 받은 상대가 이미 앨범을 다 만든 뒤라 넣을 자리가 없다.
            sendMemories(for: mine.mon.id)
            guard companion.performTrade(offeredID: mine.mon.id, received: theirs.mon,
                                         incomingMemories: pendingIncomingMemories) else {
                send(.decline(reason: "invalid-trade")); phase = .failed("교환 정보를 확인할 수 없습니다."); return
            }
            activeTransaction = id
            send(.committed(id))
            phase = .animating
        case .committed(let id):
            guard isInitiator, activeTransaction == id,
                  let mine = localOffer, let theirs = remoteOffer,
                  companion.performTrade(offeredID: mine.mon.id, received: theirs.mon,
                                         incomingMemories: pendingIncomingMemories) else {
                phase = .failed("교환을 완료하지 못했습니다."); return
            }
            phase = .animating
        case .cancel:
            finishConnection()
        }
    }

    private func resetSession() {
        localOffer = nil; remoteOffer = nil
        remoteRoster = []
        requestedRemoteMonID = nil; remoteRequestedLocalMonID = nil
        localConfirmed = false; remoteConfirmed = false
        activeTransaction = nil
        chatHistory.reset(); chatRateLimiter.reset()
        chatMessages = []; peerSupportsChat = false
        pendingIncomingMemories = nil
    }

    private func postPrivateMessageNotification() {
        guard !(UserDefaults.standard.object(forKey: "doNotDisturb") as? Bool ?? false), AppEnv.isBundledApp else { return }
        let content = UNMutableNotificationContent()
        content.title = companion.l.t("메시지가 왔습니다", "You have a message", "メッセージが届きました")
        content.body = companion.l.t("눌러서 확인하세요.", "Click to view it.", "クリックして確認してください。")
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "private-message-trade-\(UUID().uuidString)",
                                  content: content, trigger: nil))
    }

    private func finishConnection() {
        connection?.cancel(); connection = nil
        resetSession()
        phase = .ready
    }

    private nonisolated static func parameters() -> NWParameters {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        return params
    }

    private func startListener() {
        listener?.cancel()
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = .init(name: myServiceName, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.phase == .ready else { connection.cancel(); return }
                    self.resetSession()
                    self.isInitiator = false
                    self.attach(connection)
                    connection.start(queue: .main)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state { Task { @MainActor in self?.startListener() } }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch { phase = .failed("교환 수신을 시작하지 못했습니다.") }
    }

    private func startBrowser() {
        browser?.cancel()
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: Self.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.peers = results.compactMap { result in
                    guard case .service(let name, _, _, _) = result.endpoint,
                          name != self.myServiceName else { return nil }
                    let display = name.split(separator: "#").dropLast().joined(separator: "#")
                    return TradePeer(name: display.isEmpty ? name : display, serviceName: name,
                                     endpoint: result.endpoint)
                }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// 테스트가 소켓을 직접 쥐어 주는 자리. 읽기 루프의 종료 처리는 실제 소켓이 닫히는 순간에만
    /// 밟히는데(FIN 은 `.failed` 로 오지 않는다), 그 경로를 여는 진입점이 달리 없다.
    func attachForTesting(_ connection: NWConnection) {
        attach(connection)
        connection.start(queue: .main)
    }

    private func attach(_ connection: NWConnection) {
        self.connection?.cancel()
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard case .failed = state, let connection else { return }
            Task { @MainActor in self?.connectionDropped(connection) }
        }
        receiveLength(on: connection)
    }

    /// 소켓이 끝났다. `.failed` 뿐 아니라 **읽기 루프도 여기로 온다** — 상대가 앱을 정상 종료하면
    /// TCP 는 FIN 만 남기고 상태는 `.ready` 에 머무르므로 위 상태 감시가 영영 뜨지 않는다.
    /// 예전에는 읽기 콜백이 그냥 리턴했고, 죽은 소켓 위에 "교환 중" 이 그대로 남았다(확정도
    /// 커밋도 오지 않는다). 형제 경로인 `BattleCenter.connectionDropped` 와 같은 모양이다.
    private func connectionDropped(_ connection: NWConnection) {
        guard self.connection === connection else { return }
        connection.cancel()
        self.connection = nil
        if phase != .ready { phase = .failed("상대와 연결이 끊어졌습니다.") }
    }

    private func send(_ message: TradeWireMessage) {
        guard let connection, let payload = try? JSONEncoder().encode(message) else { return }
        var frame = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receiveLength(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self, weak connection] data, _, _, _ in
            guard let self, let connection else { return }
            guard let data, data.count == 4, case let length = data.withUnsafeBytes({
                $0.loadUnaligned(as: UInt32.self)
            }).bigEndian, length > 0, length <= Self.maxMessageBytes else {
                Task { @MainActor in self.connectionDropped(connection) }
                return
            }
            Task { @MainActor in
                guard self.connection === connection else { return }
                self.receiveBody(Int(length), on: connection)
            }
        }
    }

    private func receiveBody(_ length: Int, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self, weak connection] data, _, _, _ in
            guard let self, let connection else { return }
            guard let data, data.count == length else {
                Task { @MainActor in self.connectionDropped(connection) }
                return
            }
            // 못 읽는 프레임은 **건너뛰되 루프는 다시 건다**. 길이 프리픽스라 스트림이 어긋나지 않고,
            // 뒤 버전이 더한 선택적 프레임(채팅이 그랬다)에 길을 열어 둔다. 예전에는 여기서 그냥
            // 리턴해 수신을 다시 걸지 않았고, 세션은 살아 보이는 채 영영 귀를 닫았다.
            let message = try? JSONDecoder().decode(TradeWireMessage.self, from: data)
            Task { @MainActor in
                guard self.connection === connection else { return }
                if let message { self.receive(message) } else { AppLog.write("trade frame skipped — undecodable") }
                guard self.connection === connection else { return }
                self.receiveLength(on: connection)
            }
        }
    }
}
