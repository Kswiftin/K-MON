import Foundation
import Network
import Observation

struct AuctionListing: Identifiable, Equatable {
    let id: UUID
    let trainerName: String
    let serviceName: String
    let endpoint: NWEndpoint
    let speciesID: Int
    let displayName: String
    let level: Int
    let isShiny: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.serviceName == rhs.serviceName && lhs.speciesID == rhs.speciesID
            && lhs.displayName == rhs.displayName && lhs.level == rhs.level && lhs.isShiny == rhs.isShiny
    }
}

struct AuctionOffer: Identifiable {
    enum Status: Equatable { case pending, accepted, declined, completed, failed }
    let id: UUID
    let trainerName: String
    let pokemon: TradePokemonSnapshot
    var status: Status
}

/// 경매 프레임. **`PokemonTrade` 와 같은 두 단계 커밋**을 탄다 — 자세한 순서는
/// `PokemonAuctionCenter.receive(_:connectionID:)` 주석에 있다.
///
/// `version` 은 `.apply` 에만 싣는다. 구버전 앱은 이 프레임을 아예 디코딩하지 못해 제안이 서지
/// 않고(신청자는 타임아웃으로 실패를 본다), 신버전끼리만 커밋 순서를 공유한다. 개체가 오가는
/// 프로토콜이라 "모르는 필드는 넘긴다" 로 섞이게 두는 쪽이 더 위험하다.
enum AuctionWireMessage: Codable {
    /// 커밋 순서가 바뀌었다(1: 신청자가 수락 즉시 먼저 넘김 → 2: 게시자가 먼저 넘김).
    static let protocolVersion = 2

    case apply(version: Int, offerID: UUID, listingID: UUID, trainer: String, pokemon: TradePokemonSnapshot)
    /// 게시자가 이 제안을 **잠갔다.** 아직 아무 개체도 움직이지 않았다.
    case accepted(offerID: UUID, pokemon: TradePokemonSnapshot)
    case declined(offerID: UUID)
    /// 신청자가 "내 개체는 그대로 있다, 먼저 넘겨라" 라고 답한다. 추억은 여기 실린다 —
    /// 게시자가 커밋하는 순간 앨범에 얹혀야 하기 때문이다.
    case commit(offerID: UUID, memories: TradeMemoryPayload?)
    /// 게시자 쪽 이전이 끝났다. 이 프레임을 받고서야 신청자가 자기 개체를 넘긴다.
    case completed(offerID: UUID, memories: TradeMemoryPayload?)
    case failed(offerID: UUID)
}

/// 같은 네트워크의 포켓몬 경매 게시판. 게시자는 한 마리만 올리고, 각 신청은 별도 TCP
/// 연결을 유지하므로 여러 트레이너의 제안을 동시에 받을 수 있다.
///
/// 소유권 이전은 `PokemonTradeCenter` 와 **같은 커밋 프로토콜**을 쓴다. 처음에는 여기만 따로
/// 짰다가 신청자가 수락 직후 자기 개체를 먼저 넘기는 순서가 됐고, 게시자 쪽 커밋이 실패하면
/// 신청자 개체가 사라지고 게시자 개체는 복제됐다. 새 프로토콜을 짜지 말고 교환의 순서를
/// 그대로 따를 것.
@MainActor @Observable
final class PokemonAuctionCenter {
    nonisolated static let serviceType = "_kmonauct._tcp"
    private nonisolated static let maxMessageBytes: UInt32 = 1_000_000
    /// 게시자가 응답하지 않는 제안을 언제까지 붙들고 있을지. 이 시간이 지나면 신청자 쪽에서
    /// 실패로 끝낸다 — 그러지 않으면 상대가 앱을 닫아도 화면이 영영 "대기 중" 이고, 신청자는
    /// 새 제안도 못 건다(동시에 하나만 걸 수 있다).
    static let offerTimeout: TimeInterval = 90

    private(set) var listings: [AuctionListing] = []
    private(set) var offers: [AuctionOffer] = []
    private(set) var outgoingStatus: AuctionOffer.Status?
    private(set) var outgoingListingName: String?
    private(set) var lastError: String?
    private(set) var localListing: TradePokemonSnapshot?
    private(set) var localListingID: UUID?

    private let companion: CompanionStore
    private let trainerName: String
    private let serviceName: String
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [UUID: NWConnection] = [:]
    private var connectionOfferIDs: [UUID: UUID] = [:]
    private var outgoingConnectionID: UUID?
    private var outgoingPokemonID: UUID?
    /// 진행 중인 내 제안의 ID. 들어오는 프레임이 **이 제안 것인지** 대조하는 데 쓴다.
    private(set) var outgoingOfferID: UUID?
    /// 신청한 게시물의 **광고값**. 수락 프레임으로 실제 개체가 올 때 대조한다.
    private var outgoingListing: AuctionListing?
    /// 게시자가 잠근 개체. 게시자 커밋이 끝났다는 프레임을 받고서야 이 값으로 교환한다.
    private var outgoingReceived: TradePokemonSnapshot?
    private var outgoingTimeout: Task<Void, Never>?

    init(companion: CompanionStore) {
        self.companion = companion
        let configured = companion.trainerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = NSFullUserName().isEmpty ? (Host.current().localizedName ?? "Trainer") : NSFullUserName()
        trainerName = configured.isEmpty ? fallback : configured
        serviceName = LANServiceName.make(base: trainerName, suffix: "#\(String(UUID().uuidString.prefix(6)))")
    }

    func start() { startListener(); startBrowser() }

    func publish(_ mon: MonState?) {
        guard let mon else { cancelListing(); return }
        // 즐겨찾기는 잃는 동작을 막는 자물쇠다 — 화면이 목록에서 걸러 주지만 여기서도 막는다.
        guard companion.deployableMons.contains(where: { $0.id == mon.id }),
              !companion.isFavorite(mon.id) else { return }
        let snapshot = TradePokemonSnapshot(mon: mon, displayName: displayName(mon))
        localListing = snapshot
        localListingID = UUID()
        dropIncomingConnections()
        refreshService()
    }

    /// 게시를 내린다. **내가 남에게 건 제안은 건드리지 않는다** — 그 연결은 상대 게시물의
    /// 것이라, 여기서 같이 끊으면 진행 중인 내 교환이 이유 없이 끊긴다.
    func cancelListing() {
        localListing = nil; localListingID = nil
        dropIncomingConnections()
        refreshService()
    }

    /// 돌려주는 값은 이 제안이 쓰는 연결 ID 다 — 프레임은 그 ID 로만 받아들인다.
    @discardableResult
    func apply(to listing: AuctionListing, offering mon: MonState) -> UUID? {
        // 제안도 성사되면 그 개체를 내주는 자리다 — 게시와 같은 자물쇠가 걸린다.
        guard outgoingConnectionID == nil,
              companion.deployableMons.contains(where: { $0.id == mon.id }),
              !companion.isFavorite(mon.id) else { return nil }
        let connectionID = UUID(), offerID = UUID()
        let connection = NWConnection(to: listing.endpoint, using: Self.parameters())
        connections[connectionID] = connection
        outgoingConnectionID = connectionID
        outgoingPokemonID = mon.id
        outgoingOfferID = offerID
        outgoingListing = listing
        outgoingReceived = nil
        outgoingListingName = listing.displayName
        outgoingStatus = .pending
        lastError = nil
        startOutgoingTimeout(offerID)
        attach(connection, id: connectionID)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.send(.apply(version: AuctionWireMessage.protocolVersion, offerID: offerID,
                                     listingID: listing.id, trainer: self.trainerName,
                                     pokemon: TradePokemonSnapshot(mon: mon, displayName: self.displayName(mon))),
                              on: connection, id: connectionID)
                // `.cancelled` 도 본다. 여기서 안 보면 상대가 정상 종료한 연결이 좀비로 남아
                // 제안이 영영 `.pending` 이고 새 제안도 못 건다.
                case .failed, .cancelled: self.drop(connectionID, failed: true)
                default: break
                }
            }
        }
        connection.start(queue: .main)
        return connectionID
    }

    /// 아직 답을 못 받은 제안을 신청자가 거둬들인다. 게시자에게도 알려 잠긴 자리를 풀어 준다.
    func cancelOutgoingOffer() {
        guard outgoingStatus == .pending, let offerID = outgoingOfferID,
              let connectionID = outgoingConnectionID, let connection = connections[connectionID] else { return }
        send(.failed(offerID: offerID), on: connection, id: connectionID)
        // 화면에는 아무 결과도 남기지 않는다 — 거둬들인 제안은 거절당한 것도 실패한 것도 아니다.
        clearOutgoingResult()
    }

    func clearOutgoingResult() {
        outgoingTimeout?.cancel(); outgoingTimeout = nil
        if let id = outgoingConnectionID { connections[id]?.cancel(); connections[id] = nil }
        outgoingConnectionID = nil; outgoingPokemonID = nil; outgoingOfferID = nil
        outgoingListing = nil; outgoingReceived = nil
        outgoingStatus = nil; outgoingListingName = nil; lastError = nil
    }

    /// 제안을 잠근다. **개체는 아직 움직이지 않는다** — 신청자가 자기 개체를 그대로 들고 있다고
    /// 답하는 `.commit` 을 받고서야 넘긴다.
    func accept(_ offerID: UUID) {
        // 게시한 **뒤에** 별을 켰을 수도 있다 — 수락이 소유권을 넘기는 지점이라 여기서 한 번 더 본다.
        guard let listing = localListing,
              companion.deployableMons.contains(where: { $0.id == listing.mon.id }),
              !companion.isFavorite(listing.mon.id),
              // 이미 잠긴 제안이 있으면 두 번째 수락을 받지 않는다. 없으면 같은 개체가 두
              // 트레이너에게 커밋된다(하나는 실패로 끝나지만 그 실패가 어느 쪽인지는 순서 나름이다).
              !offers.contains(where: { $0.status == .accepted || $0.status == .completed }),
              let connectionID = connectionOfferIDs.first(where: { $0.value == offerID })?.key,
              let connection = connections[connectionID],
              let index = offers.firstIndex(where: { $0.id == offerID && $0.status == .pending }) else {
            lastError = companion.l.t("게시한 포켓몬을 확인할 수 없습니다.",
                                    "The listed Pokémon is no longer available.",
                                    "出品したポケモンを確認できません。")
            return
        }
        offers[index].status = .accepted
        send(.accepted(offerID: offerID, pokemon: listing), on: connection, id: connectionID)
    }

    func reject(_ offerID: UUID) {
        guard let index = offers.firstIndex(where: { $0.id == offerID }) else { return }
        offers[index].status = .declined
        if let connectionID = connectionOfferIDs.first(where: { $0.value == offerID })?.key,
           let connection = connections[connectionID] {
            send(.declined(offerID: offerID), on: connection, id: connectionID)
        }
    }

    /// 커밋은 **두 단계**다. 신청자가 `.commit` 으로 "내 개체는 그대로 있다" 를 알리면 게시자가
    /// 먼저 넘기고, 그 사실을 `.completed` 로 받은 신청자가 마지막에 넘긴다. 순서를 뒤집으면
    /// (신청자가 수락 즉시 넘기던 옛 순서) 게시자 쪽 커밋 실패가 신청자 개체 유실이 된다.
    ///
    /// 마지막 커밋은 **미리 물어본 판정**(`canPerformTrade`)을 통과한 뒤에만 시작한다. 그래야
    /// 마지막 단계에서 거절될 값이 두 번째 단계 앞에서 걸린다.
    func receive(_ message: AuctionWireMessage, connectionID: UUID) {
        guard let connection = connections[connectionID] else { return }
        switch message {
        case .apply(let version, let offerID, let listingID, let trainer, let pokemon):
            guard version == AuctionWireMessage.protocolVersion,
                  listingID == localListingID, let listing = localListing,
                  companion.deployableMons.contains(where: { $0.id == listing.mon.id }),
                  companion.canPerformTrade(offeredID: listing.mon.id, received: pokemon.mon),
                  let safeName = BattleChatPolicy.displayName(trainer),
                  // 한 연결은 제안 하나만 나른다. 덮어쓰게 두면 앞 제안의 거절·수락 프레임이
                  // 상대에게 못 나간다(연결을 못 찾는다).
                  connectionOfferIDs[connectionID] == nil,
                  !offers.contains(where: { $0.id == offerID }) else {
                send(.declined(offerID: offerID), on: connection, id: connectionID); return
            }
            connectionOfferIDs[connectionID] = offerID
            offers.append(AuctionOffer(id: offerID, trainerName: safeName, pokemon: pokemon, status: .pending))
        case .accepted(let offerID, let pokemon):
            guard connectionID == outgoingConnectionID, offerID == outgoingOfferID,
                  outgoingStatus == .pending, let mineID = outgoingPokemonID,
                  companion.deployableMons.contains(where: { $0.id == mineID }),
                  companion.canPerformTrade(offeredID: mineID, received: pokemon.mon) else {
                failOutgoing(offerID, on: connection, id: connectionID,
                             reason: companion.l.t("교환을 완료하지 못했습니다.",
                                                   "Trade could not be completed.",
                                                   "交換を完了できませんでした。"))
                return
            }
            // 광고(TXT)와 실제로 온 개체를 대조한다. 목록에서 본 것과 다른 개체가 오면 화면은
            // 그대로 성사되고 상자에만 다른 포켓몬이 앉는다 — 그건 교환이 아니라 바꿔치기다.
            guard let advertised = outgoingListing, matches(advertised, pokemon) else {
                failOutgoing(offerID, on: connection, id: connectionID,
                             reason: companion.l.t("목록에 올라온 포켓몬과 다른 개체가 왔습니다.",
                                                   "The Pokémon offered does not match the listing.",
                                                   "出品と異なるポケモンが届きました。"))
                return
            }
            outgoingTimeout?.cancel(); outgoingTimeout = nil
            outgoingReceived = pokemon
            outgoingStatus = .accepted
            send(.commit(offerID: offerID, memories: companion.tradeMemoryPayload(for: mineID)),
                 on: connection, id: connectionID)
        case .commit(let offerID, let memories):
            guard let index = offers.firstIndex(where: { $0.id == offerID && $0.status == .accepted }),
                  connectionOfferIDs[connectionID] == offerID,
                  let listing = localListing else {
                send(.failed(offerID: offerID), on: connection, id: connectionID); return
            }
            // 앨범은 `performTrade` 가 지운다 — 보낼 값을 미리 만들어 두고 성사 뒤에 보낸다.
            let outgoing = companion.tradeMemoryPayload(for: listing.mon.id)
            guard companion.performTrade(offeredID: listing.mon.id, received: offers[index].pokemon.mon,
                                         incomingMemories: memories.map {
                                             TradeMemoryPayload.sanitized($0, now: companion.now)
                                         }) else {
                offers[index].status = .failed
                send(.failed(offerID: offerID), on: connection, id: connectionID)
                return
            }
            offers[index].status = .completed
            localListing = nil; localListingID = nil
            send(.completed(offerID: offerID, memories: outgoing), on: connection, id: connectionID)
            refreshService()
            // 게시물이 사라졌으니 남은 제안은 답을 기다릴 이유가 없다.
            for other in offers.indices where offers[other].status == .pending { reject(offers[other].id) }
        case .completed(let offerID, let memories):
            guard connectionID == outgoingConnectionID, offerID == outgoingOfferID,
                  outgoingStatus == .accepted, let mineID = outgoingPokemonID,
                  let received = outgoingReceived,
                  companion.performTrade(offeredID: mineID, received: received.mon,
                                         incomingMemories: memories.map {
                                             TradeMemoryPayload.sanitized($0, now: companion.now)
                                         }) else {
                outgoingStatus = .failed
                lastError = companion.l.t("교환을 완료하지 못했습니다.",
                                          "Trade could not be completed.",
                                          "交換を完了できませんでした。")
                return
            }
            outgoingStatus = .completed
        case .declined:
            if connectionID == outgoingConnectionID, outgoingStatus == .pending { outgoingStatus = .declined }
        case .failed(let offerID):
            if let index = offers.firstIndex(where: { $0.id == offerID }), offers[index].status != .completed {
                offers[index].status = .failed
            }
            if connectionID == outgoingConnectionID, outgoingStatus != .completed { outgoingStatus = .failed }
        }
    }

    /// 광고값은 TXT 레코드라 이름이 30자에서 잘린다 — 종·레벨·이로치만 대조한다.
    private func matches(_ listing: AuctionListing, _ snapshot: TradePokemonSnapshot) -> Bool {
        listing.speciesID == snapshot.mon.currentID
            && listing.level == snapshot.mon.level
            && listing.isShiny == snapshot.mon.isShiny
    }

    private func failOutgoing(_ offerID: UUID, on connection: NWConnection, id: UUID, reason: String) {
        outgoingTimeout?.cancel(); outgoingTimeout = nil
        outgoingStatus = .failed
        lastError = reason
        send(.failed(offerID: offerID), on: connection, id: id)
    }

    private func startOutgoingTimeout(_ offerID: UUID) {
        outgoingTimeout?.cancel()
        outgoingTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.offerTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.expireOutgoingOffer(offerID) }
        }
    }

    /// 답 없는 제안을 실패로 끝낸다. `.pending` 일 때만 — 커밋이 시작된 뒤에는 시간이 지나도
    /// 개체가 이미 움직이는 중이라 여기서 끊으면 안 된다.
    func expireOutgoingOffer(_ offerID: UUID) {
        guard outgoingStatus == .pending, offerID == outgoingOfferID else { return }
        outgoingStatus = .failed
        lastError = companion.l.t("상대가 응답하지 않았습니다.", "The other trainer did not respond.",
                                  "相手から応答がありませんでした。")
        if let id = outgoingConnectionID { connections[id]?.cancel(); connections[id] = nil }
    }

    private func dropIncomingConnections() {
        for (id, connection) in connections where id != outgoingConnectionID {
            connection.cancel(); connections[id] = nil; connectionOfferIDs[id] = nil
        }
        offers.removeAll()
    }

    private func displayName(_ mon: MonState) -> String {
        if let nickname = mon.nickname, !nickname.isEmpty { return nickname }
        return mon.names?[mon.currentID]?[companion.language.rawValue] ?? "#\(mon.currentID)"
    }

    private func startListener() {
        listener?.cancel()
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = service()
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self else { connection.cancel(); return }
                    let id = UUID(); self.connections[id] = connection
                    self.attach(connection, id: id)
                    connection.stateUpdateHandler = { [weak self] state in
                        switch state {
                        case .failed, .cancelled: Task { @MainActor in self?.drop(id, failed: true) }
                        default: break
                        }
                    }
                    connection.start(queue: .main)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state { Task { @MainActor in self?.startListener() } }
            }
            listener.start(queue: .main); self.listener = listener
        } catch { lastError = error.localizedDescription }
    }

    private func refreshService() { listener?.service = service() }

    private func service() -> NWListener.Service {
        var entries: [String: String] = [:]
        if let id = localListingID, let listing = localListing {
            entries = ["id": id.uuidString, "sid": String(listing.mon.currentID),
                       "name": String(listing.displayName.prefix(30)), "lv": String(listing.mon.level),
                       "shiny": listing.mon.isShiny ? "1" : "0"]
        }
        return NWListener.Service(name: serviceName, type: Self.serviceType, domain: nil,
                                  txtRecord: NWTXTRecord(entries))
    }

    private func startBrowser() {
        browser?.cancel()
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: Self.serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: Self.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.updateListings(results) }
        }
        browser.start(queue: .main); self.browser = browser
    }

    private func updateListings(_ results: Set<NWBrowser.Result>) {
        listings = results.compactMap { result in
            guard case .service(let name, _, _, _) = result.endpoint, name != serviceName,
                  case .bonjour(let txt) = result.metadata,
                  let rawID = txt["id"], let id = UUID(uuidString: rawID),
                  let species = txt["sid"].flatMap(Int.init), let level = txt["lv"].flatMap(Int.init),
                  let display = txt["name"] else { return nil }
            let trainer = name.split(separator: "#").dropLast().joined(separator: "#")
            return AuctionListing(id: id, trainerName: trainer.isEmpty ? name : trainer,
                                  serviceName: name, endpoint: result.endpoint, speciesID: species,
                                  displayName: display, level: level, isShiny: txt["shiny"] == "1")
        }.sorted { $0.trainerName.localizedCaseInsensitiveCompare($1.trainerName) == .orderedAscending }
    }

    private nonisolated static func parameters() -> NWParameters {
        let parameters = NWParameters.tcp; parameters.includePeerToPeer = true; return parameters
    }

    private func attach(_ connection: NWConnection, id: UUID) { receiveLength(on: connection, id: id) }

    /// 테스트가 소켓 없이 국면을 세우는 자리. 붙인 연결의 ID 를 돌려준다 — `receive` 가 그 ID 로
    /// 온 프레임만 받기 때문이다.
    @discardableResult
    func attachForTesting(_ connection: NWConnection) -> UUID {
        let id = UUID(); connections[id] = connection; return id
    }

    /// 전송 실패는 **연결이 끊긴 것으로 다룬다.** 버리면 상대는 이미 사라졌는데 이쪽 화면만
    /// 이유 없이 대기 상태로 남는다.
    private func send(_ message: AuctionWireMessage, on connection: NWConnection, id: UUID) {
        guard let payload = try? JSONEncoder().encode(message) else { return }
        var frame = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.drop(id, failed: true) }
        })
    }

    private func receiveLength(on connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self, weak connection] data, _, _, _ in
            guard let self, let connection, let data, data.count == 4 else { return }
            let length = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
            guard length > 0, length <= Self.maxMessageBytes else { Task { @MainActor in self.drop(id, failed: true) }; return }
            Task { @MainActor in self.receiveBody(Int(length), on: connection, id: id) }
        }
    }

    private func receiveBody(_ length: Int, on connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self, weak connection] data, _, _, _ in
            guard let self, let connection, let data, data.count == length else { return }
            let message = try? JSONDecoder().decode(AuctionWireMessage.self, from: data)
            Task { @MainActor in
                if let message { self.receive(message, connectionID: id) }
                if self.connections[id] === connection { self.receiveLength(on: connection, id: id) }
            }
        }
    }

    private func drop(_ id: UUID, failed: Bool) {
        connections[id]?.cancel(); connections[id] = nil
        // 커밋을 기다리던 제안이면 실패로 남긴다. 그냥 지우면 게시자 화면에 "교환 처리 중" 이
        // 영영 남고, 잠긴 자리 때문에 다른 제안도 수락할 수 없다.
        if let offerID = connectionOfferIDs[id],
           let index = offers.firstIndex(where: { $0.id == offerID }),
           offers[index].status == .pending || offers[index].status == .accepted {
            offers[index].status = .failed
        }
        connectionOfferIDs[id] = nil
        if outgoingConnectionID == id {
            if failed, outgoingStatus == .pending || outgoingStatus == .accepted {
                outgoingStatus = .failed
                outgoingTimeout?.cancel(); outgoingTimeout = nil
            }
            if outgoingStatus == nil {
                outgoingConnectionID = nil; outgoingPokemonID = nil
                outgoingOfferID = nil; outgoingListing = nil; outgoingReceived = nil
            }
        }
    }
}
