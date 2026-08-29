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
    /// 대문 문구. `Optional` 이라 합성 `Codable` 이 `decodeIfPresent` 를 쓴다 → 이 키가 없는
    /// R4 이전 피어의 페이로드도 그대로 디코드되므로 `protocolVersion` 은 1 을 유지한다.
    /// 여기를 "기본값 있는 비옵셔널"로 바꾸면 그 경로는 **throw 한다** — 옵셔널로 남겨야 한다.
    var profileMessage: String?
    /// A deliberately small, read-only home showcase. It excludes notes, aliases, guestbook and
    /// exact placements; a LAN visit should reveal a home's personality, not its private data.
    var roomTheme: PokemonMemoryRoomTheme? = nil
    var showcaseFurniture: [ItemKind] = []
    /// v2 is an explicitly published, read-only showroom. No diary, aliases, guestbook or
    /// local counters are represented here.
    var roomStyle: MemoryHomeRoomStyle? = nil
    var placedDecor: [MemoryHomePlacedDecor] = []
    var featuredPhoto: MemoryHomePhoto? = nil

    private enum CodingKeys: String, CodingKey { case displayName, speciesID, isShiny, sharedMemoryBody, profileMessage, roomTheme, showcaseFurniture, roomStyle, placedDecor, featuredPhoto }
    init(displayName: String, speciesID: Int, isShiny: Bool, sharedMemoryBody: String?, profileMessage: String?,
         roomTheme: PokemonMemoryRoomTheme? = nil, showcaseFurniture: [ItemKind] = [], roomStyle: MemoryHomeRoomStyle? = nil,
         placedDecor: [MemoryHomePlacedDecor] = [], featuredPhoto: MemoryHomePhoto? = nil) {
        self.displayName = displayName; self.speciesID = speciesID; self.isShiny = isShiny
        self.sharedMemoryBody = sharedMemoryBody; self.profileMessage = profileMessage
        self.roomTheme = roomTheme; self.showcaseFurniture = showcaseFurniture
        self.roomStyle = roomStyle; self.placedDecor = placedDecor; self.featuredPhoto = featuredPhoto
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decode(String.self, forKey: .displayName)
        speciesID = try c.decode(Int.self, forKey: .speciesID)
        isShiny = try c.decode(Bool.self, forKey: .isShiny)
        sharedMemoryBody = try c.decodeIfPresent(String.self, forKey: .sharedMemoryBody)
        profileMessage = try c.decodeIfPresent(String.self, forKey: .profileMessage)
        roomTheme = try c.decodeIfPresent(PokemonMemoryRoomTheme.self, forKey: .roomTheme)
        showcaseFurniture = try c.decodeIfPresent([ItemKind].self, forKey: .showcaseFurniture) ?? []
        roomStyle = try c.decodeIfPresent(MemoryHomeRoomStyle.self, forKey: .roomStyle)
        placedDecor = try c.decodeIfPresent([MemoryHomePlacedDecor].self, forKey: .placedDecor) ?? []
        featuredPhoto = try c.decodeIfPresent(MemoryHomePhoto.self, forKey: .featuredPhoto)
    }

    /// Shown in the visit sheet. This was inline in the view with the interpolation backslash
    /// missing — Swift accepts that as a plain literal, so it shipped printing the expression
    /// source verbatim. It is a tested pure property now; `test-gate.sh` greps for the typo class.
    var speciesLabel: String { "#\(speciesID)" + (isShiny ? " ✨" : "") }
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
    nonisolated static let protocolVersion = 2
    nonisolated static let maxFrameBytes: UInt32 = 16 * 1024

    private(set) var homes: [MemoryHomePeer] = []
    private(set) var selectedProfile: MemoryHomeProfileCard?
    private(set) var lastError: String?
    /// `isActive` is the visit-browser state. Hosting has a separate app-lifetime.
    private(set) var isActive = false
    private(set) var isHosting = false
    private let companion: CompanionStore
    private let peerID: UUID
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var visitHomeIDs: [ObjectIdentifier: String] = [:]

    init(companion: CompanionStore, peerID: UUID) { self.companion = companion; self.peerID = peerID }

    /// Starts discovery only: private visitors may still browse public homes.
    func start() {
        guard !isActive else { return }; isActive = true; lastError = nil
        startBrowsing()
    }
    func stop() {
        isActive = false; homes = []; selectedProfile = nil
        browser?.cancel(); browser = nil
        cancelVisitConnections()
    }
    func startHostingIfEligible() {
        guard companion.memoryAlbum.memoryHomeAccess.visibility == .open else { return }
        startHosting()
    }
    /// The feature being disabled or the app ending is the only normal host teardown path.
    func shutdown() {
        stop()
        listener?.cancel(); listener = nil; isHosting = false
        cancelConnections()
    }
    func refreshAccess() {
        if companion.memoryAlbum.memoryHomeAccess.visibility == .blocked {
            listener?.cancel(); listener = nil; isHosting = false
            cancelConnections()
            return
        }
        // Recreate only the advertised service after a nickname edit; browse results stay up.
        listener?.cancel(); listener = nil; isHosting = false
        startHosting()
    }
    func visit(_ peer: MemoryHomePeer) {
        guard isActive else { return }; selectedProfile = nil; lastError = nil
        let connection = NWConnection(to: peer.endpoint, using: Self.parameters())
        let key = ObjectIdentifier(connection); connections[key] = connection; visitHomeIDs[key] = peer.id
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
        let ownServiceName = localDisplayName
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let peers = results.compactMap { result -> MemoryHomePeer? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                guard name != ownServiceName else { return nil }
                return .init(id: name, displayName: Self.clean(name, limit: 40) ?? "Memory Home", endpoint: result.endpoint)
            }
            Task { @MainActor in self?.homes = peers.sorted { $0.displayName < $1.displayName } }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor in self?.lastError = self?.networkFailureMessage(error) }
            }
        }
        browser.start(queue: .main); self.browser = browser
    }
    private func startHosting() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = .init(name: localDisplayName, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    Task { @MainActor in self?.lastError = self?.networkFailureMessage(error) }
                }
            }
            listener.start(queue: .main); self.listener = listener; isHosting = true
        } catch { lastError = error.localizedDescription }
    }
    private func accept(_ connection: NWConnection) {
        // A visibility change can race an already accepted TCP connection. Let its request reach
        // `receiveRequest`, which responds with the explicit protocol rejection instead of
        // accidentally serving a profile or silently treating the peer as accepted.
        guard isHosting else { connection.cancel(); return }
        let key = ObjectIdentifier(connection); connections[key] = connection
        connection.start(queue: .main)
        receiveRequest(on: connection, key: key)
    }
    private func receiveRequest(on connection: NWConnection, key: ObjectIdentifier) {
        receive(MemoryHomeVisitRequest.self, on: connection) { [weak self, weak connection] request in
            guard let self, let connection else { return }
            guard case let .profileRequest(version, visitorID, name) = request,
                  (1...Self.protocolVersion).contains(version), Self.clean(name, limit: 40) != nil,
                  self.companion.memoryAlbum.memoryHomeAccess.visibility == .open,
                  self.companion.state.active != nil,
                  !self.companion.memoryAlbum.memoryHomeAccess.blockedPeerIDs.contains(visitorID) else {
                self.send(MemoryHomeVisitResponse.rejected(protocolVersion: Self.protocolVersion), over: connection) { connection.cancel() }; return
            }
            self.companion.memoryAlbum.recordMemoryHomeRequester(displayName: name, peerID: visitorID)
            self.send(MemoryHomeVisitResponse.profileCard(protocolVersion: version, card: self.profileCard(version: version)), over: connection) { connection.cancel() }
            self.connections.removeValue(forKey: key)
        }
    }
    private func receiveResponse(on connection: NWConnection, key: ObjectIdentifier) {
        receive(MemoryHomeVisitResponse.self, on: connection) { [weak self] response in
            defer { connection.cancel(); self?.connections.removeValue(forKey: key); self?.visitHomeIDs.removeValue(forKey: key) }
            guard let self else { return }
            switch response {
            case let .profileCard(version, card) where (1...Self.protocolVersion).contains(version) && Self.valid(card):
                self.selectedProfile = card
                if let homeID = self.visitHomeIDs[key] { self.companion.memoryAlbum.recordMemoryHomeVisitStamp(homeID: homeID) }
            case let .rejected(version) where (1...Self.protocolVersion).contains(version):
                self.lastError = "This home is not accepting visits."
            default: self.lastError = "Invalid Memory Home response."
            }
        }
    }
    /// Do not fall back to the trainer name: malformed/legacy payloads still get a safe album
    /// fallback, never an accidental disclosure.
    private var localDisplayName: String { companion.memoryAlbum.memoryHomePublicNickname }
    /// 대문 문구는 `profileMessageForSharing` 만 읽는다 — 공유를 명시적으로 켠 경우에만 값이
    /// 나오는 프로퍼티다. `memoryHomeAccess.profileMessage` 를 직접 읽으면 동의 없이 새어 나간다.
    private func profileCard(version: Int = protocolVersion) -> MemoryHomeProfileCard {
        let sharedMessage = companion.memoryAlbum.profileMessageForSharing
        guard let mon = companion.state.active else {
            return .init(displayName: localDisplayName, speciesID: 1, isShiny: false,
                         sharedMemoryBody: nil, profileMessage: sharedMessage)
        }
        let access = companion.memoryAlbum.memoryHomeAccess
        let base = MemoryHomeProfileCard(displayName: localDisplayName, speciesID: mon.currentID, isShiny: mon.isShiny,
                     sharedMemoryBody: companion.memoryAlbum.sharedPinnedMemory(for: mon.id)?.body,
                     profileMessage: sharedMessage, roomTheme: companion.memoryAlbum.theme(for: mon.id),
                     showcaseFurniture: access.placedDecor.map(\.item))
        guard version >= 2 else { return base }
        return .init(displayName: base.displayName, speciesID: base.speciesID, isShiny: base.isShiny,
                     sharedMemoryBody: base.sharedMemoryBody, profileMessage: base.profileMessage,
                     roomTheme: base.roomTheme, showcaseFurniture: base.showcaseFurniture,
                     roomStyle: access.roomStyle, placedDecor: access.placedDecor,
                     featuredPhoto: access.featuredPhotoID.flatMap { id in access.photos.first { $0.id == id } })
    }
    /// 신뢰경계 클램프다 — `private` 로 두면 원격 페이로드 검증이 무테스트로 남는다.
    nonisolated static func valid(_ card: MemoryHomeProfileCard) -> Bool {
        guard clean(card.displayName, limit: 40) != nil, card.speciesID > 0, card.speciesID <= 10_000 else { return false }
        guard card.sharedMemoryBody.map({ clean($0, limit: 280) != nil }) ?? true else { return false }
        // 문구는 내부 공백을 허용하므로 `clean` 이 아니라 앨범과 같은 검증기를 쓴다 — 두 곳이
        // 규칙을 따로 가지면 내가 저장할 수 있는 문구를 상대가 거부하게 된다.
        return card.profileMessage.map { PokemonMemoryAlbum.validProfileMessage($0) != nil } ?? true
            && card.showcaseFurniture.allSatisfy { ItemKind.memoryHomeFurniture.contains($0) }
            && card.placedDecor.count <= 12
            && card.placedDecor.allSatisfy { ItemKind.memoryHomeFurniture.contains($0.item) && (0...1).contains($0.position.x) && (0...1).contains($0.position.y) }
            && (card.featuredPhoto.map { $0.speciesID > 0 && $0.speciesID <= 10_000 && $0.caption.count <= 60 } ?? true)
    }
    nonisolated static func clean(_ value: String, limit: Int) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= limit,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
              }) else { return nil }
        return value
    }
    private static func parameters() -> NWParameters { NWParameters.tcp }

    /// Bonjour 권한 거부를 Network 프레임워크의 내부 코드로 노출하지 않는다. 특히 `NoAuth` 는
    /// 홈 계정 인증이 아니라 macOS의 로컬 네트워크 서비스 권한을 뜻한다.
    private func networkFailureMessage(_ error: NWError) -> String {
        guard error.localizedDescription.localizedCaseInsensitiveContains("noauth") else {
            return error.localizedDescription
        }
        return companion.l.t("주변 홈을 찾을 수 없어요. 앱을 다시 열어 로컬 네트워크 접근을 허용해 주세요.",
                             "Nearby homes are unavailable. Reopen the app and allow local network access.",
                             "近くのホームを探せません。アプリを開き直してローカルネットワークへのアクセスを許可してください。")
    }
    private func cancelConnections() {
        connections.values.forEach { $0.cancel() }
        connections.removeAll(); visitHomeIDs.removeAll()
    }
    private func cancelVisitConnections() {
        for key in visitHomeIDs.keys { connections.removeValue(forKey: key)?.cancel() }
        visitHomeIDs.removeAll()
    }
    /// 완료 핸들러를 `@MainActor` 함수 타입으로 못 박는다. 이유가 둘 있다:
    /// 1) 전역 액터 격리 함수 타입은 암묵적으로 `Sendable` 이라, `@Sendable` 인 Network 콜백에
    ///    캡처될 수 있다 — 그냥 `() -> Void` 로 두면 Swift 6 concurrency warning 이 남는다.
    /// 2) 호출부(`receiveRequest` 등)는 앨범·상태 같은 MainActor 상태를 직접 만진다. 파라미터를
    ///    `@Sendable` 로 바꾸면 그 호출부가 전부 깨지므로, 격리를 없애는 게 아니라 **명시**해야 한다.
    /// 그래서 Network 콜백 안에서는 `Task { @MainActor in }` 로 한 번 홉한다.
    /// 프레임은 요청→응답 1회 왕복뿐이라 이 홉이 순서를 바꾸지 않는다.
    private func send<T: Encodable & Sendable>(_ value: T, over connection: NWConnection,
                                              completion: @escaping @MainActor () -> Void = {}) {
        guard let data = try? JSONEncoder().encode(value), data.count <= Int(Self.maxFrameBytes) else { connection.cancel(); return }
        var length = UInt32(data.count).bigEndian; let header = Data(bytes: &length, count: 4)
        connection.send(content: header + data, completion: .contentProcessed { _ in
            Task { @MainActor in completion() }
        })
    }
    /// `T: Sendable` 은 메타타입(`T.Type`)이 격리 클로저로 넘어갈 수 있게 하려고 붙인다.
    /// 이 전송로의 페이로드 두 종은 이미 `Sendable` 이라 실질 제약이 아니다.
    private func receive<T: Decodable & Sendable>(_ type: T.Type, on connection: NWConnection,
                                                 completion: @escaping @MainActor (T) -> Void) {
        // `self` 를 쓰지 않는다 — 프레임 상한은 `Self` 로 읽으므로 weak 캡처가 필요 없었다.
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
            guard error == nil, let header, header.count == 4 else { connection.cancel(); return }
            let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length <= Self.maxFrameBytes else { connection.cancel(); return }
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { data, _, _, error in
                guard error == nil, let data, data.count == Int(length),
                      let value = try? JSONDecoder().decode(T.self, from: data) else { connection.cancel(); return }
                Task { @MainActor in completion(value) }
            }
        }
    }
}
