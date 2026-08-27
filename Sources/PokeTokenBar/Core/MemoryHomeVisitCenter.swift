import Foundation
import Network
import Observation

/// Deliberately tiny, separate LAN protocol for Memory Home.  A peer ID is an access-control
/// hint, not authentication; never treat it as proof of a person's identity.
struct MemoryHomeProfileCard: Codable, Sendable, Equatable {
    var displayName: String
    var speciesID: Int
    var isShiny: Bool
    var sharedMemoryBody: String?
}

enum MemoryHomeVisitRequest: Codable, Sendable, Equatable {
    case profileRequest(protocolVersion: Int, peerID: UUID, displayName: String)
}

enum MemoryHomeVisitResponse: Codable, Sendable, Equatable {
    case profileCard(protocolVersion: Int, card: MemoryHomeProfileCard)
    case rejected(protocolVersion: Int)
}

struct MemoryHomePeer: Identifiable, Equatable {
    let id: String
    let displayName: String
    let endpoint: NWEndpoint
}

@MainActor @Observable
final class MemoryHomeVisitCenter {
    nonisolated static let serviceType = "_kmonhome._tcp"
    nonisolated static let protocolVersion = 1
    nonisolated static let maxFrameBytes: UInt32 = 16 * 1024

    private(set) var homes: [MemoryHomePeer] = []
    private(set) var selectedProfile: MemoryHomeProfileCard?
    private(set) var lastError: String?
    private(set) var isActive = false
    private let companion: CompanionStore
    private let peerID: UUID
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(companion: CompanionStore, peerID: UUID) { self.companion = companion; self.peerID = peerID }

    func start() {
        guard !isActive else { return }; isActive = true; lastError = nil
        guard companion.memoryAlbum.memoryHomeAccess.visibility == .open else { return }
        startBrowsing(); startHosting()
    }
    func stop() {
        isActive = false; homes = []; selectedProfile = nil
        browser?.cancel(); browser = nil; listener?.cancel(); listener = nil
        connections.values.forEach { $0.cancel() }; connections.removeAll()
    }
    func refreshAccess() {
        guard isActive else { return }
        if companion.memoryAlbum.memoryHomeAccess.visibility == .blocked { stop(); isActive = true }
        else if listener == nil { startBrowsing(); startHosting() }
    }
    func visit(_ peer: MemoryHomePeer) {
        guard isActive else { return }; selectedProfile = nil; lastError = nil
        let connection = NWConnection(to: peer.endpoint, using: Self.parameters())
        let key = ObjectIdentifier(connection); connections[key] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard case .ready = state, let self, let connection else { return }
            Task { @MainActor in
                self.send(MemoryHomeVisitRequest.profileRequest(protocolVersion: Self.protocolVersion, peerID: self.peerID,
                          displayName: self.localDisplayName), over: connection) { [weak self, weak connection] in
                    guard let self, let connection else { return }
                    Task { @MainActor in self.receiveResponse(on: connection, key: key) }
                }
            }
        }
        connection.start(queue: .main)
    }
    private func startBrowsing() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: Self.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let peers = results.compactMap { result -> MemoryHomePeer? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return .init(id: name, displayName: Self.clean(name, limit: 40) ?? "Memory Home", endpoint: result.endpoint)
            }
            Task { @MainActor in self?.homes = peers.sorted { $0.displayName < $1.displayName } }
        }
        browser.stateUpdateHandler = { [weak self] state in if case .failed(let error) = state { Task { @MainActor in self?.lastError = error.localizedDescription } } }
        browser.start(queue: .main); self.browser = browser
    }
    private func startHosting() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = .init(name: localDisplayName, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
            listener.stateUpdateHandler = { [weak self] state in if case .failed(let error) = state { Task { @MainActor in self?.lastError = error.localizedDescription } } }
            listener.start(queue: .main); self.listener = listener
        } catch { lastError = error.localizedDescription }
    }
    private func accept(_ connection: NWConnection) {
        guard isActive, companion.memoryAlbum.memoryHomeAccess.visibility == .open else { connection.cancel(); return }
        let key = ObjectIdentifier(connection); connections[key] = connection
        connection.start(queue: .main)
        receiveRequest(on: connection, key: key)
    }
    private func receiveRequest(on connection: NWConnection, key: ObjectIdentifier) {
        receive(MemoryHomeVisitRequest.self, on: connection) { [weak self, weak connection] request in
            guard let self, let connection else { return }
            guard case let .profileRequest(version, visitorID, name) = request,
                  version == Self.protocolVersion, Self.clean(name, limit: 40) != nil,
                  self.companion.memoryAlbum.memoryHomeAccess.visibility == .open,
                  self.companion.state.active != nil,
                  !self.companion.memoryAlbum.memoryHomeAccess.blockedPeerIDs.contains(visitorID) else {
                self.send(MemoryHomeVisitResponse.rejected(protocolVersion: Self.protocolVersion), over: connection) { connection.cancel() }; return
            }
            self.companion.memoryAlbum.recordMemoryHomeRequester(displayName: name, peerID: visitorID)
            self.send(MemoryHomeVisitResponse.profileCard(protocolVersion: Self.protocolVersion, card: self.profileCard()), over: connection) { connection.cancel() }
            self.connections.removeValue(forKey: key)
        }
    }
    private func receiveResponse(on connection: NWConnection, key: ObjectIdentifier) {
        receive(MemoryHomeVisitResponse.self, on: connection) { [weak self] response in
            defer { connection.cancel(); self?.connections.removeValue(forKey: key) }
            guard let self else { return }
            switch response {
            case let .profileCard(version, card) where version == Self.protocolVersion && Self.valid(card): self.selectedProfile = card
            case .rejected: self.lastError = "This home is not accepting visits."
            default: self.lastError = "Invalid Memory Home response."
            }
        }
    }
    private var localDisplayName: String { Self.clean(companion.trainerName, limit: 40) ?? "Memory Home" }
    private func profileCard() -> MemoryHomeProfileCard {
        guard let mon = companion.state.active else { return .init(displayName: localDisplayName, speciesID: 1, isShiny: false, sharedMemoryBody: nil) }
        return .init(displayName: localDisplayName, speciesID: mon.currentID, isShiny: mon.isShiny,
                     sharedMemoryBody: companion.memoryAlbum.sharedPinnedMemory(for: mon.id)?.body)
    }
    private static func valid(_ card: MemoryHomeProfileCard) -> Bool {
        guard clean(card.displayName, limit: 40) != nil, card.speciesID > 0, card.speciesID <= 10_000 else { return false }
        return card.sharedMemoryBody.map { clean($0, limit: 280) != nil } ?? true
    }
    nonisolated static func clean(_ value: String, limit: Int) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= limit, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }
    private static func parameters() -> NWParameters { NWParameters.tcp }
    private func send<T: Encodable>(_ value: T, over connection: NWConnection, completion: @escaping () -> Void = {}) {
        guard let data = try? JSONEncoder().encode(value), data.count <= Int(Self.maxFrameBytes) else { connection.cancel(); return }
        var length = UInt32(data.count).bigEndian; let header = Data(bytes: &length, count: 4)
        connection.send(content: header + data, completion: .contentProcessed { _ in completion() })
    }
    private func receive<T: Decodable>(_ type: T.Type, on connection: NWConnection, completion: @escaping (T) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, _, error in
            guard let self, error == nil, let header, header.count == 4 else { connection.cancel(); return }
            let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length <= Self.maxFrameBytes else { connection.cancel(); return }
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { data, _, _, error in
                guard error == nil, let data, data.count == Int(length), let value = try? JSONDecoder().decode(T.self, from: data) else { connection.cancel(); return }
                completion(value)
            }
        }
    }
}
