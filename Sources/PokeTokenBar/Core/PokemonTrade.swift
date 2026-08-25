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

private enum TradeWireMessage: Codable {
    case request(version: Int, trainer: String)
    case accept(trainer: String)
    case decline(reason: String)
    case offer(TradePokemonSnapshot?)
    case confirm(Bool)
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
    private nonisolated static let protocolVersion = 1
    private nonisolated static let maxMessageBytes: UInt32 = 1_000_000

    enum Phase: Equatable {
        case ready
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
    private(set) var localConfirmed = false
    private(set) var remoteConfirmed = false

    private let companion: CompanionStore
    private let myName: String
    private let myServiceName: String
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var isInitiator = false
    private var activeTransaction: UUID?

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
        send(.request(version: Self.protocolVersion, trainer: myName))
    }

    func accept() {
        guard case .incoming(let peer) = phase else { return }
        phase = .negotiating(peer: peer)
        send(.accept(trainer: myName))
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

    private func displayName(for mon: MonState) -> String {
        if let nickname = mon.nickname, !nickname.isEmpty { return nickname }
        let code = companion.language.rawValue
        return mon.names?[mon.currentID]?[code] ?? "#\(mon.currentID)"
    }

    private func beginCommitIfReady() {
        guard isInitiator, localConfirmed, remoteConfirmed,
              localOffer != nil, remoteOffer != nil else { return }
        let id = UUID()
        activeTransaction = id
        phase = .committing
        send(.commit(id))
    }

    private func receive(_ message: TradeWireMessage) {
        switch message {
        case .request(let version, let trainer):
            guard version == Self.protocolVersion, phase == .ready else {
                send(.decline(reason: "busy-or-incompatible")); return
            }
            isInitiator = false
            phase = .incoming(peer: trainer)
            postPrivateMessageNotification()
        case .accept(let trainer):
            guard case .requesting = phase else { return }
            phase = .negotiating(peer: trainer)
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
        case .commit(let id):
            guard !isInitiator, localConfirmed, remoteConfirmed,
                  let mine = localOffer, let theirs = remoteOffer else {
                send(.decline(reason: "trade-changed")); return
            }
            phase = .committing
            guard companion.performTrade(offeredID: mine.mon.id, received: theirs.mon) else {
                send(.decline(reason: "invalid-trade")); phase = .failed("교환 정보를 확인할 수 없습니다."); return
            }
            activeTransaction = id
            send(.committed(id))
            phase = .animating
        case .committed(let id):
            guard isInitiator, activeTransaction == id,
                  let mine = localOffer, let theirs = remoteOffer,
                  companion.performTrade(offeredID: mine.mon.id, received: theirs.mon) else {
                phase = .failed("교환을 완료하지 못했습니다."); return
            }
            phase = .animating
        case .cancel:
            finishConnection()
        }
    }

    private func resetSession() {
        localOffer = nil; remoteOffer = nil
        localConfirmed = false; remoteConfirmed = false
        activeTransaction = nil
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

    private func attach(_ connection: NWConnection) {
        self.connection?.cancel()
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard case .failed = state else { return }
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                self.phase = .failed("상대와 연결이 끊어졌습니다.")
                self.connection = nil
            }
        }
        receiveLength(on: connection)
    }

    private func send(_ message: TradeWireMessage) {
        guard let connection, let payload = try? JSONEncoder().encode(message) else { return }
        var frame = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receiveLength(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self, weak connection] data, _, _, _ in
            guard let self, let connection, let data, data.count == 4 else { return }
            let length = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
            guard length > 0, length <= Self.maxMessageBytes else { connection.cancel(); return }
            Task { @MainActor in
                guard self.connection === connection else { return }
                self.receiveBody(Int(length), on: connection)
            }
        }
    }

    private func receiveBody(_ length: Int, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self, weak connection] data, _, _, _ in
            guard let self, let connection, let data, data.count == length,
                  let message = try? JSONDecoder().decode(TradeWireMessage.self, from: data) else { return }
            Task { @MainActor in
                guard self.connection === connection else { return }
                self.receive(message)
                self.receiveLength(on: connection)
            }
        }
    }
}
