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

private enum AuctionWireMessage: Codable {
    case apply(offerID: UUID, listingID: UUID, trainer: String, pokemon: TradePokemonSnapshot)
    case accepted(offerID: UUID, pokemon: TradePokemonSnapshot)
    case declined(offerID: UUID)
    case committed(offerID: UUID)
    case completed(offerID: UUID)
    case failed(offerID: UUID)
}

/// 같은 네트워크의 포켓몬 경매 게시판. 게시자는 한 마리만 올리고, 각 신청은 별도 TCP
/// 연결을 유지하므로 여러 트레이너의 제안을 동시에 받을 수 있다. 실제 소유권 이전은
/// 수락 시점에 양쪽이 `performTrade`로 다시 검증한다.
@MainActor @Observable
final class PokemonAuctionCenter {
    nonisolated static let serviceType = "_kmonauct._tcp"
    private nonisolated static let maxMessageBytes: UInt32 = 1_000_000

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
        guard companion.deployableMons.contains(where: { $0.id == mon.id }) else { return }
        let snapshot = TradePokemonSnapshot(mon: mon, displayName: displayName(mon))
        localListing = snapshot
        localListingID = UUID()
        offers.removeAll()
        refreshService()
    }

    func cancelListing() {
        localListing = nil; localListingID = nil; offers.removeAll()
        for connection in connections.values { connection.cancel() }
        connections.removeAll(); connectionOfferIDs.removeAll()
        refreshService()
    }

    func apply(to listing: AuctionListing, offering mon: MonState) {
        guard outgoingConnectionID == nil,
              companion.deployableMons.contains(where: { $0.id == mon.id }) else { return }
        let connectionID = UUID(), offerID = UUID()
        let connection = NWConnection(to: listing.endpoint, using: Self.parameters())
        connections[connectionID] = connection
        outgoingConnectionID = connectionID
        outgoingPokemonID = mon.id
        outgoingListingName = listing.displayName
        outgoingStatus = .pending
        attach(connection, id: connectionID)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            Task { @MainActor in
                if case .ready = state {
                    self.send(.apply(offerID: offerID, listingID: listing.id,
                                     trainer: self.trainerName,
                                     pokemon: TradePokemonSnapshot(mon: mon, displayName: self.displayName(mon))),
                              on: connection)
                } else if case .failed = state { self.drop(connectionID, failed: true) }
            }
        }
        connection.start(queue: .main)
    }

    func clearOutgoingResult() {
        if let id = outgoingConnectionID { drop(id, failed: false) }
        outgoingConnectionID = nil; outgoingPokemonID = nil
        outgoingStatus = nil; outgoingListingName = nil; lastError = nil
    }

    func accept(_ offerID: UUID) {
        guard let listingID = localListingID, let listing = localListing,
              companion.deployableMons.contains(where: { $0.id == listing.mon.id }),
              let connectionID = connectionOfferIDs.first(where: { $0.value == offerID })?.key,
              let connection = connections[connectionID],
              let index = offers.firstIndex(where: { $0.id == offerID && $0.status == .pending }) else {
            lastError = companion.l.t("게시한 포켓몬을 확인할 수 없습니다.",
                                    "The listed Pokémon is no longer available.",
                                    "出品したポケモンを確認できません。")
            return
        }
        _ = listingID
        offers[index].status = .accepted
        send(.accepted(offerID: offerID, pokemon: listing), on: connection)
        // 하나를 수락한 후 나머지는 즉시 거절해 두 거래가 같은 게시물을 결제하지 못하게 한다.
        for other in offers.indices where offers[other].id != offerID && offers[other].status == .pending {
            reject(offers[other].id)
        }
    }

    func reject(_ offerID: UUID) {
        guard let index = offers.firstIndex(where: { $0.id == offerID }) else { return }
        offers[index].status = .declined
        if let connectionID = connectionOfferIDs.first(where: { $0.value == offerID })?.key,
           let connection = connections[connectionID] {
            send(.declined(offerID: offerID), on: connection)
        }
    }

    private func receive(_ message: AuctionWireMessage, connectionID: UUID) {
        guard let connection = connections[connectionID] else { return }
        switch message {
        case .apply(let offerID, let listingID, let trainer, let pokemon):
            guard listingID == localListingID, localListing != nil,
                  companion.deployableMons.contains(where: { $0.id == localListing?.mon.id }),
                  let safeName = BattleChatPolicy.displayName(trainer),
                  !offers.contains(where: { $0.id == offerID }) else {
                send(.declined(offerID: offerID), on: connection); return
            }
            connectionOfferIDs[connectionID] = offerID
            offers.append(AuctionOffer(id: offerID, trainerName: safeName, pokemon: pokemon, status: .pending))
        case .accepted(let offerID, let pokemon):
            guard connectionID == outgoingConnectionID, let mineID = outgoingPokemonID,
                  companion.performTrade(offeredID: mineID, received: pokemon.mon) else {
                outgoingStatus = .failed; send(.failed(offerID: offerID), on: connection); return
            }
            outgoingStatus = .accepted
            send(.committed(offerID: offerID), on: connection)
        case .committed(let offerID):
            guard let index = offers.firstIndex(where: { $0.id == offerID && $0.status == .accepted }),
                  let listing = localListing,
                  companion.performTrade(offeredID: listing.mon.id, received: offers[index].pokemon.mon) else {
                send(.failed(offerID: offerID), on: connection); return
            }
            offers[index].status = .completed
            localListing = nil; localListingID = nil
            send(.completed(offerID: offerID), on: connection)
            refreshService()
        case .completed:
            outgoingStatus = .completed
        case .declined:
            outgoingStatus = .declined
        case .failed(let offerID):
            if let index = offers.firstIndex(where: { $0.id == offerID }) { offers[index].status = .failed }
            if connectionID == outgoingConnectionID { outgoingStatus = .failed }
        }
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
                        if case .failed = state { Task { @MainActor in self?.drop(id, failed: false) } }
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

    private func send(_ message: AuctionWireMessage, on connection: NWConnection) {
        guard let payload = try? JSONEncoder().encode(message) else { return }
        var frame = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        frame.append(payload); connection.send(content: frame, completion: .contentProcessed { _ in })
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
        connections[id]?.cancel(); connections[id] = nil; connectionOfferIDs[id] = nil
        if outgoingConnectionID == id {
            if failed, outgoingStatus == .pending { outgoingStatus = .failed }
            if outgoingStatus == nil { outgoingConnectionID = nil; outgoingPokemonID = nil }
        }
    }
}
