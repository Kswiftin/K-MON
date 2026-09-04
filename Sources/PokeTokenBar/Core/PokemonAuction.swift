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
    enum Status: Equatable {
        case pending, accepted, declined, completed, failed

        /// 아직 결과가 나지 않은 제안 — **내놓은 것이 여전히 걸려 있다.** 개체를 두 번 걸지
        /// 못하게 막는 판정과 별의모래 미결분 합계가 둘 다 이 질문을 한다.
        var isLive: Bool { self == .pending || self == .accepted }
    }
    let id: UUID
    let listingID: UUID
    let trainerName: String
    let value: AuctionOfferValue
    var status: Status
}

enum AuctionOfferValue: Codable {
    case pokemon(TradePokemonSnapshot)
    case stardust(Int)
}

/// 내가 남의 게시물에 건 제안 하나. 예전에는 이 값들이 센터의 스칼라 필드였고, 그래서 제안도
/// **한 번에 하나만** 걸 수 있었다 — 답 없는 제안 하나가 제한 시간(90초) 동안 다른 기회를 전부
/// 막았다. 국면이 제안별로 서야 여러 건이 서로의 상태·타임아웃·에스크로를 덮지 않는다.
///
/// 실패 이유(`error`)도 제안별이다. 전역 한 줄로 두면 제안이 여럿일 때 어느 제안의 실패인지
/// 알 수 없고, 잘못 붙은 이유는 없는 것보다 나쁘다.
struct OutgoingAuctionOffer: Identifiable {
    let id: UUID
    /// 이 제안이 쓰는 연결. 들어온 프레임은 **연결과 제안 ID 가 둘 다** 맞을 때만 받아들인다.
    let connectionID: UUID
    let listing: AuctionListing
    /// 내가 내놓은 개체. `nil` 이면 별의모래 제안이다.
    let monID: UUID?
    let stardust: Int
    var stardustEscrowed = false
    /// 게시자가 잠근 개체. 게시자 커밋이 끝났다는 프레임을 받고서야 이 값으로 교환한다.
    var received: TradePokemonSnapshot?
    var status: AuctionOffer.Status = .pending
    var error: String?
}

/// 경매 프레임. **`PokemonTrade` 와 같은 두 단계 커밋**을 탄다 — 자세한 순서는
/// `PokemonAuctionCenter.receive(_:connectionID:)` 주석에 있다.
///
/// `version` 은 `.apply` 에만 싣는다. 구버전 앱은 이 프레임을 아예 디코딩하지 못해 제안이 서지
/// 않고(신청자는 타임아웃으로 실패를 본다), 신버전끼리만 커밋 순서를 공유한다. 개체가 오가는
/// 프로토콜이라 "모르는 필드는 넘긴다" 로 섞이게 두는 쪽이 더 위험하다.
enum AuctionWireMessage: Codable {
    /// 커밋 순서가 바뀌었다(1: 신청자가 수락 즉시 먼저 넘김 → 2: 게시자가 먼저 넘김).
    static let protocolVersion = 3

    case apply(version: Int, offerID: UUID, listingID: UUID, trainer: String, value: AuctionOfferValue)
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

/// 같은 네트워크의 포켓몬 경매 게시판. 게시자는 여러 마리를 올리고, 각 신청은 별도 TCP
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
    /// 동시에 걸 수 있는 제안 수. 포켓몬 제안은 "한 개체는 한 제안" 이라 보유 수가 자연 상한이지만
    /// 별의모래 제안은 그렇지 않다 — 지갑이 크면 작은 제안을 무한히 걸어 연결을 그만큼 연다.
    /// `nonisolated` 인 이유는 **터미널 화면 투영이 이 값을 읽기** 때문이다 — 순수 함수라
    /// 메인 액터가 아니고, 정원을 화면에 다시 적으면 두 벌이 되어 한쪽만 바뀐다.
    nonisolated static let maxOutgoingOffers = 8

    /// 장부에 동시에 올릴 수 있는 연결의 수. **유휴 수신 연결은 회수 판정이 아예 안 돈다** —
    /// `reclaimIfIdle` 은 프레임을 읽은 뒤에만 걸리므로 붙어서 아무것도 보내지 않는 피어는
    /// 판정에 걸리지 않고, `#227` 이 자동 시간 제한을 걷어내 시간이 끊어 줄 것도 없다. 남은
    /// 방어는 수를 막는 것 하나다. 나가는 제안 정원(8)과 한 집의 피어 수를 넉넉히 덮는 값이라
    /// 정상 사용은 이 문에 닿지 않는다.
    static let maxConnections = 64

    private(set) var listings: [AuctionListing] = []
    private(set) var offers: [AuctionOffer] = []
    /// 내가 건 제안들. 등록 순서를 유지한다 — 화면이 그 순서로 카드를 쌓는다.
    private(set) var outgoingOffers: [OutgoingAuctionOffer] = []
    private(set) var lastError: String?
    private(set) var localListings: [UUID: TradePokemonSnapshot] = [:]

    private let companion: CompanionStore
    private let trainerName: String
    private let serviceName: String
    private var listeners: [UUID: NWListener] = [:]
    private var browser: NWBrowser?
    private var connections: [UUID: NWConnection] = [:]
    private var connectionOfferIDs: [UUID: UUID] = [:]
    /// 회수를 관찰할 수 있는 유일한 창이다. `connections` 를 통째로 `private` 로 두면 "끝난 제안의
    /// 연결이 새는지" 를 검증할 방법이 없어 이 부류가 조용히 돌아온다(#228 이 그렇게 살아남았다).
    /// 파생값이라 상태가 갈라지지 않는다 — 형제 `MemoryHomeVisitCenter.trackedConnectionCount`
    /// 와 같은 이유로 `internal` 이다.
    var trackedConnectionCount: Int { connections.count }

    init(companion: CompanionStore) {
        self.companion = companion
        let configured = companion.trainerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = NSFullUserName().isEmpty ? (Host.current().localizedName ?? "Trainer") : NSFullUserName()
        trainerName = configured.isEmpty ? fallback : configured
        serviceName = LANServiceName.make(base: trainerName, suffix: "#\(String(UUID().uuidString.prefix(6)))")
    }

    func start() { startBrowser() }

    func publish(_ mon: MonState?) {
        guard let mon else { return }
        // 즐겨찾기는 잃는 동작을 막는 자물쇠다 — 화면이 목록에서 걸러 주지만 여기서도 막는다.
        guard sellableMons.contains(where: { $0.id == mon.id }),
              !companion.isFavorite(mon.id), !isCommitted(mon.id) else { return }
        let id = UUID()
        localListings[id] = TradePokemonSnapshot(mon: mon, displayName: displayName(mon))
        startListener(for: id)
    }

    /// 게시를 내린다. **내가 남에게 건 제안은 건드리지 않는다** — 그 연결은 상대 게시물의
    /// 것이라, 여기서 같이 끊으면 진행 중인 내 교환이 이유 없이 끊긴다.
    func cancelListing(_ listingID: UUID) {
        guard localListings.removeValue(forKey: listingID) != nil else { return }
        listeners[listingID]?.cancel(); listeners[listingID] = nil
        for offer in offers where offer.listingID == listingID && offer.status == .pending { reject(offer.id) }
        offers.removeAll { $0.listingID == listingID }
        // 제안이 사라진 연결은 더 나를 것이 없다. **`.accepted` 였던 제안**이 여기서 안 접히면
        // 신청자는 자동 시간 제한이 없어(#227) 영구히 "교환 처리 중" 이고 에스크로도 안 돌아온다 —
        // 접으면 상대 읽기 루프가 EOF 로 그것을 안다. 판정은 `reclaimIfIdle` 하나뿐이라 여기서도
        // 그것을 부른다(살아 있는 제안이 붙은 다른 게시물의 연결은 그 판정이 지킨다).
        for id in Array(connectionOfferIDs.keys) { reclaimIfIdle(id) }
    }

    /// 아직 어느 제안에도 약속하지 않은 별의모래. 에스크로는 **수락 시점**에 걷히므로 잔액만
    /// 보면 지킬 수 없는 제안을 여러 건 걸게 된다. **등록 가드와 화면이 같은 이 값을 본다** —
    /// 두 벌로 두면 한쪽만 넓어져 버튼은 켜지는데 센터가 조용히 거절한다.
    var unpledgedTokens: Int {
        let pledged = outgoingOffers
            .filter { !$0.stardustEscrowed && $0.status.isLive }
            .reduce(0) { $0 + $1.stardust }
        return max(0, companion.availableTokens - pledged)
    }

    /// 제안을 하나 더 걸 수 있는가. 정원은 **살아 있는 제안만** 센다 — 치우지 않은 결과 카드가
    /// 자리를 먹으면 화면이 이유 없이 잠긴다(끝난 제안은 연결도 곧 닫힌다).
    var canRegisterOffer: Bool {
        outgoingOffers.filter { $0.status.isLive }.count < Self.maxOutgoingOffers
    }

    /// 이 개체가 **이미 어딘가에 걸려 있는가** — 내 게시물이든, 내가 건 제안이든.
    ///
    /// 같은 개체가 두 자리를 받치면 둘 다 수락됐을 때 같은 포켓몬이 두 번 커밋된다(하나는
    /// 실패로 끝나지만 그 실패가 어느 쪽인지는 순서 나름이다). 제안이 하나뿐이던 때부터 있던
    /// 구멍인데, 제안이 여러 건 서면 훨씬 쉽게 밟힌다. 호출부마다 가드를 두면 새 호출부가
    /// 무검사로 남으므로 판정은 여기 하나다. 화면도 후보를 이 판정으로 거른다.
    func isCommitted(_ monID: UUID) -> Bool {
        localListings.values.contains { $0.mon.id == monID }
            || outgoingOffers.contains { $0.monID == monID && $0.status.isLive }
    }

    /// 경매로 내보낼 수 있는 개체 — **동행(active)은 빠진다.**
    ///
    /// 동행을 팔면 모험 정산이 경험치 전량을 별의조각으로 환산해(받을 개체가 없다) 총수입이
    /// 1.5배가 된다 — 사유는 `CompanionStore.completeAuctionSale` 주석에 있다. 그래서
    /// **게시·제안·수락·커밋이 전부 이 값을 본다**: 게시한 뒤에 그 개체를 동행으로 들이는 길이
    /// 있어(박스에서 파트너 교체) 출품 시점만 보면 뒷문이 남는다. 즐겨찾기를 게시 뒤에 켤 수
    /// 있어 수락에서 한 번 더 보는 것과 같은 부류다.
    var sellableMons: [MonState] {
        companion.deployableMons.filter { $0.id != companion.activeMonID }
    }

    /// 돌려주는 값은 이 제안이 쓰는 연결 ID 다 — 프레임은 그 ID 로만 받아들인다.
    @discardableResult
    func apply(to listing: AuctionListing, offering mon: MonState) -> UUID? {
        // 제안도 성사되면 그 개체를 내주는 자리다 — 게시와 같은 자물쇠가 걸린다.
        guard sellableMons.contains(where: { $0.id == mon.id }),
              !companion.isFavorite(mon.id), !isCommitted(mon.id) else { return nil }
        return register(on: listing, monID: mon.id, stardust: 0,
                        value: .pokemon(TradePokemonSnapshot(mon: mon, displayName: displayName(mon))))
    }

    @discardableResult
    func apply(to listing: AuctionListing, offeringStardust amount: Int) -> UUID? {
        // 게시자의 `isValid` 는 상한을 넘는 별의모래를 무조건 거절한다. 보내기 전에 잘라야
        // 왕복 한 번을 거절로 버리지 않는다 — 지갑 자체가 상한을 넘은 세이브에서만 밟힌다.
        let amount = min(amount, SaveTransfer.maxTokenValue)
        guard amount > 0, unpledgedTokens >= amount else { return nil }
        return register(on: listing, monID: nil, stardust: amount, value: .stardust(amount))
    }

    /// 제안 하나를 세우고 연결을 연다. 두 `apply` 가 이 몸통을 공유한다 — 따로 두었을 때는
    /// 국면 필드를 한쪽에만 더하면 다른 쪽이 조용히 옛 값을 들고 갔다.
    private func register(on listing: AuctionListing, monID: UUID?, stardust: Int,
                          value: AuctionOfferValue) -> UUID? {
        guard canRegisterOffer else { return nil }
        // 새 동작은 앞선 실패의 자국을 지운다. 이 줄이 없으면 `accept` 가 남긴 전역 한 줄이
        // 지울 방법 없이 화면 아래 영영 붙어 있다.
        lastError = nil
        let connectionID = UUID(), offerID = UUID()
        let connection = NWConnection(to: listing.endpoint, using: Self.parameters())
        connections[connectionID] = connection
        outgoingOffers.append(OutgoingAuctionOffer(id: offerID, connectionID: connectionID,
                                                   listing: listing, monID: monID, stardust: stardust))
        attach(connection, id: connectionID)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.send(.apply(version: AuctionWireMessage.protocolVersion, offerID: offerID,
                                     listingID: listing.id, trainer: self.trainerName, value: value),
                              on: connection, id: connectionID)
                // `.cancelled` 도 본다. 여기서 안 보면 상대가 정상 종료한 연결이 좀비로 남아
                // 제안이 영영 `.pending` 이고 그 개체는 다른 제안에도 못 쓴다.
                case .failed, .cancelled: self.drop(connectionID)
                default: break
                }
            }
        }
        connection.start(queue: .main)
        return connectionID
    }

    /// 아직 답을 못 받은 제안을 신청자가 거둬들인다. 게시자에게도 알려 잠긴 자리를 풀어 준다.
    ///
    /// **자동 시간 제한은 없다**(#227). 90초가 지나면 자동으로 실패시키던 때는, 게시자가 그 안에
    /// 못 보고 늦게 수락하면 이미 제안이 끝난 뒤라 커밋이 무조건 실패했다. 상대가 진짜로 앱을
    /// 닫으면 `.failed`/`.cancelled` 연결 상태가 `drop` 을 불러 이미 정리하므로, 시간 제한은
    /// "둘 다 켜져 있는데 게시자가 느린" 정상적인 경우만 억울하게 끊었다. 제안이 여러 건 서게
    /// 되면서 "대기 중인 제안 하나가 다음 기회를 막는다" 는 나머지 근거도 사라졌다.
    func cancelOutgoingOffer(_ offerID: UUID) {
        guard let offer = outgoingOffers.first(where: { $0.id == offerID && $0.status == .pending }),
              let connection = connections[offer.connectionID] else { return }
        send(.failed(offerID: offerID), on: connection, id: offer.connectionID)
        // 화면에는 아무 결과도 남기지 않는다 — 거둬들인 제안은 거절당한 것도 실패한 것도 아니다.
        clearOutgoingResult(offerID)
    }

    /// 끝난 제안을 화면에서 치운다. 에스크로 환불과 연결까지 이 자리에서 함께 끝낸다.
    func clearOutgoingResult(_ offerID: UUID) {
        // 커밋이 시작된 제안(`.accepted`)은 치우지 않는다. 여기서 에스크로를 돌려주면 게시자는
        // 이미 넘긴 뒤라 별의모래가 복제되고 개체는 아무에게도 가지 않는다.
        guard let offer = outgoing(offerID), offer.status != .accepted else { return }
        refundStardustIfNeeded(offerID)
        // 제안을 먼저 지우고 접는다. `cancelOutgoingOffer` 는 방금 `.failed` 를 보냈고, 즉시
        // `cancel()` 하면 그 프레임이 버려져 게시자 카드가 영구히 `.pending` 에 남는다(#228).
        // 지우는 것은 **첨자가 아니라 ID 로** 한다 — 환불이 저장을 돌렸으므로 자리를 기억해
        // 두면 여기서 남의 제안을 지운다(#234). `connectionID` 는 그 이전 사본에서 읽는데
        // 제안의 연결은 바뀌지 않으므로 안전하다.
        outgoingOffers.removeAll { $0.id == offerID }
        closeWhenFlushed(offer.connectionID)
    }

    /// 제안을 잠근다. **개체는 아직 움직이지 않는다** — 신청자가 자기 개체를 그대로 들고 있다고
    /// 답하는 `.commit` 을 받고서야 넘긴다.
    func accept(_ offerID: UUID) {
        // 게시한 **뒤에** 별을 켰을 수도 있다 — 수락이 소유권을 넘기는 지점이라 여기서 한 번 더 본다.
        guard let offer = offers.first(where: { $0.id == offerID && $0.status == .pending }),
              let listing = localListings[offer.listingID],
              sellableMons.contains(where: { $0.id == listing.mon.id }),
              !companion.isFavorite(listing.mon.id),
              // 이미 잠긴 제안이 있으면 두 번째 수락을 받지 않는다. 없으면 같은 개체가 두
              // 트레이너에게 커밋된다(하나는 실패로 끝나지만 그 실패가 어느 쪽인지는 순서 나름이다).
              !offers.contains(where: { $0.listingID == offer.listingID
                  && ($0.status == .accepted || $0.status == .completed) }),
              let connectionID = connectionOfferIDs.first(where: { $0.value == offerID })?.key,
              let connection = connections[connectionID] else {
            lastError = companion.l.t("게시한 포켓몬을 확인할 수 없습니다.",
                                    "The listed Pokémon is no longer available.",
                                    "出品したポケモンを確認できません。")
            return
        }
        lastError = nil
        setStatus(.accepted, for: offerID)
        send(.accepted(offerID: offerID, pokemon: listing), on: connection, id: connectionID)
    }

    func reject(_ offerID: UUID) {
        guard offers.contains(where: { $0.id == offerID }) else { return }
        setStatus(.declined, for: offerID)
        if let connectionID = connectionOfferIDs.first(where: { $0.value == offerID })?.key,
           let connection = connections[connectionID] {
            send(.declined(offerID: offerID), on: connection, id: connectionID)
            // `receive` 의 `defer` 가 아니라 여기서 본다 — 이 함수는 화면·`cancelListing`·
            // 커밋 연쇄 셋에서 오고, 뒤 둘은 다른 연결의 프레임을 처리하는 중이다.
            reclaimIfIdle(connectionID)
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
        // 프레임을 처리한 뒤 회수를 **한 번** 본다. `defer` 인 것은 조기 반환이 여럿이기
        // 때문이다(가드 실패·재전송·커밋 실패·반려된 `.apply`) — 꼬리에만 적으면 그 갈래들이
        // 통째로 빠지고, 그중 `.apply` 반려는 정원조차 없는 무제한 누수다.
        defer { reclaimIfIdle(connectionID) }
        switch message {
        case .apply(let version, let offerID, let listingID, let trainer, let value):
            guard version == AuctionWireMessage.protocolVersion,
                  let listing = localListings[listingID],
                  sellableMons.contains(where: { $0.id == listing.mon.id }),
                  isValid(value, for: listing),
                  let safeName = BattleChatPolicy.displayName(trainer),
                  // 한 연결은 제안 하나만 나른다. 덮어쓰게 두면 앞 제안의 거절·수락 프레임이
                  // 상대에게 못 나간다(연결을 못 찾는다).
                  connectionOfferIDs[connectionID] == nil,
                  !offers.contains(where: { $0.id == offerID }) else {
                send(.declined(offerID: offerID), on: connection, id: connectionID); return
            }
            connectionOfferIDs[connectionID] = offerID
            offers.append(AuctionOffer(id: offerID, listingID: listingID, trainerName: safeName,
                                       value: value, status: .pending))
        case .accepted(let offerID, let pokemon):
            // 프레임은 **연결과 제안 ID 가 둘 다** 맞는 제안에만 닿는다. 제안이 여럿이라
            // 연결만 보면 남의 제안 국면을 움직인다.
            guard let offer = outgoing(offerID, on: connectionID) else {
                failOutgoing(offerID, on: connection, id: connectionID,
                             reason: companion.l.t("교환을 완료하지 못했습니다.",
                                                   "Trade could not be completed.",
                                                   "交換を完了できませんでした。"))
                return
            }
            // 같은 `.accepted` 가 또 오면 **무시한다.** 커밋이 시작된 제안을 여기서 실패로
            // 끌어내리면 게시자는 이미 넘긴 뒤라 에스크로만 돌아오고 개체는 사라진다.
            guard offer.status == .pending else { return }
            guard canCommitOutgoing(offerID, received: pokemon) else {
                failOutgoing(offerID, on: connection, id: connectionID,
                             reason: companion.l.t("교환을 완료하지 못했습니다.",
                                                   "Trade could not be completed.",
                                                   "交換を完了できませんでした。"))
                return
            }
            // 광고(TXT)와 실제로 온 개체를 대조한다. 목록에서 본 것과 다른 개체가 오면 화면은
            // 그대로 성사되고 상자에만 다른 포켓몬이 앉는다 — 그건 교환이 아니라 바꿔치기다.
            guard matches(offer.listing, pokemon) else {
                failOutgoing(offerID, on: connection, id: connectionID,
                             reason: companion.l.t("목록에 올라온 포켓몬과 다른 개체가 왔습니다.",
                                                   "The Pokémon offered does not match the listing.",
                                                   "出品と異なるポケモンが届きました。"))
                return
            }
            withOutgoing(offerID, on: connectionID) { $0.received = pokemon; $0.status = .accepted }
            if offer.stardust > 0 {
                guard companion.escrowStarPieces(offer.stardust) else {
                    failOutgoing(offerID, on: connection, id: connectionID,
                                 reason: companion.l.t("별의모래가 부족합니다.", "Not enough Stardust.",
                                                       "ほしのすなが足りません。"))
                    return
                }
                // 에스크로가 저장을 돌렸다 — 이 자리가 #229 의 결함 지점이다. 첨자를 들고
                // 있었다면 관측자 하나가 앞 제안을 치우는 순간 표시가 옆 제안에 찍혔고,
                // 별의모래를 낸 제안은 환불 대상에서 빠져 그대로 사라졌다.
                //
                // 표시를 적을 자리가 없으면(제안이 사라졌으면) 지갑은 이미 비었는데 표시는
                // 어디에도 없어 환불 경로가 이 별의모래를 영원히 못 찾는다. 지금은 위에서
                // `.accepted` 를 먼저 적어 유일한 제거 경로(`clearOutgoingResult`)가 막혀 있어
                // 도달하지 않는다 — 그러나 "도달 경로가 없다" 는 판단이 정확히 #229 를 놓친
                // 근거였다. 순서가 뒤집히면 여기서 돌려준다. (제안이 없으니 `failOutgoing` 의
                // 환불은 걸리지 않는다 — 지갑을 직접 되돌린다.)
                if withOutgoing(offerID, on: connectionID, { $0.stardustEscrowed = true }) == nil {
                    companion.creditStarPieces(offer.stardust)
                    send(.failed(offerID: offerID), on: connection, id: connectionID)
                    return
                }
            }
            send(.commit(offerID: offerID,
                         memories: offer.monID.flatMap(companion.tradeMemoryPayload(for:))),
                 on: connection, id: connectionID)
        case .commit(let offerID, let memories):
            guard let offer = offers.first(where: { $0.id == offerID && $0.status == .accepted }),
                  connectionOfferIDs[connectionID] == offerID,
                  let listing = localListings[offer.listingID] else {
                send(.failed(offerID: offerID), on: connection, id: connectionID); return
            }
            // 앨범은 `performTrade` 가 지운다 — 보낼 값을 미리 만들어 두고 성사 뒤에 보낸다.
            let outgoingMemories = companion.tradeMemoryPayload(for: listing.mon.id)
            let committed: Bool
            switch offer.value {
            case .pokemon(let pokemon):
                committed = companion.performTrade(offeredID: listing.mon.id, received: pokemon.mon,
                                                    incomingMemories: memories.map {
                                                        TradeMemoryPayload.sanitized($0, now: companion.now)
                                                    })
            case .stardust(let amount):
                committed = companion.completeAuctionSale(offeredID: listing.mon.id, stardust: amount)
            }
            guard committed else {
                setStatus(.failed, for: offerID)
                send(.failed(offerID: offerID), on: connection, id: connectionID)
                return
            }
            setStatus(.completed, for: offerID)
            let listingID = offer.listingID
            localListings[listingID] = nil
            listeners[listingID]?.cancel(); listeners[listingID] = nil
            send(.completed(offerID: offerID, memories: outgoingMemories),
                 on: connection, id: connectionID)
            // 게시물이 사라졌으니 남은 제안은 답을 기다릴 이유가 없다. 도는 값은 **배열 사본**이라
            // (`cancelListing` 과 같은 형태) `reject` 가 `offers` 를 고쳐도 순회가 흔들리지 않는다.
            for other in offers where other.listingID == listingID && other.status == .pending {
                reject(other.id)
            }
        case .completed(let offerID, let memories):
            guard let offer = outgoing(offerID, on: connectionID), offer.status == .accepted,
                  let received = offer.received else { return }
            let committed: Bool
            if let mineID = offer.monID {
                committed = companion.performTrade(offeredID: mineID, received: received.mon,
                                                    incomingMemories: memories.map {
                                                        TradeMemoryPayload.sanitized($0, now: companion.now)
                                                    })
            } else {
                committed = companion.receiveAuctionPokemon(received.mon,
                                                             incomingMemories: memories.map {
                    TradeMemoryPayload.sanitized($0, now: companion.now)
                })
            }
            guard committed else {
                // 교환은 스토어를 통째로 흔든다(세이브·앨범·대화). 이유 문구를 **미리** 만들고
                // 국면은 한 번에 적는다 — 여는 본문 안에서 `companion` 을 부르지 않는다.
                let reason = companion.l.t("교환을 완료하지 못했습니다.",
                                           "Trade could not be completed.",
                                           "交換を完了できませんでした。")
                refundStardustIfNeeded(offerID)
                withOutgoing(offerID, on: connectionID) { $0.status = .failed; $0.error = reason }
                return
            }
            withOutgoing(offerID, on: connectionID) {
                $0.status = .completed
                // 별의모래는 상대에게 건너갔다 — 여기서 환불 대상에서 뺀다.
                $0.stardustEscrowed = false
            }
        case .declined(let offerID):
            withOutgoing(offerID, on: connectionID) { if $0.status == .pending { $0.status = .declined } }
        case .failed(let offerID):
            if let offer = offers.first(where: { $0.id == offerID }), offer.status != .completed {
                setStatus(.failed, for: offerID)
            }
            if let offer = outgoing(offerID, on: connectionID), offer.status != .completed {
                withOutgoing(offerID, on: connectionID) { $0.status = .failed }
                refundStardustIfNeeded(offerID)
            }
        }
    }

    /// 내가 건 제안 하나를 **열어 고친다.** 첨자를 밖으로 내보내지 않는 것이 요점이다(#229):
    /// 조회와 쓰기 사이에 스토어를 건드리면 그 호출이 저장·관측을 깨우고, 관측자 하나가
    /// `outgoingOffers` 를 건드리는 순간 첨자는 그 자리에서 낡는다 — 남의 제안이 고쳐지거나
    /// (배열이 짧아지는 방향이면) 첨자가 그대로 터진다. **본문 안에서 `companion` 을 부르지
    /// 않는다**: 그 호출이 여기로 되돌아오면 같은 원소를 두 번 잡는다.
    ///
    /// `connectionID` 를 주면 **연결과 제안 ID 가 둘 다** 맞아야 연다 — 프레임이 여는 자리는
    /// 전부 이쪽이다. 연결만 보면 지연 도착·재사용 프레임이 남의 제안 국면을 움직인다.
    @discardableResult
    private func withOutgoing<T>(_ offerID: UUID, on connectionID: UUID? = nil,
                                 _ body: (inout OutgoingAuctionOffer) -> T) -> T? {
        guard let index = outgoingOffers.firstIndex(where: {
            $0.id == offerID && (connectionID == nil || $0.connectionID == connectionID)
        }) else { return nil }
        return body(&outgoingOffers[index])
    }

    /// 읽기만 하는 짝. 돌려주는 것은 **사본**이라, 스토어를 건드린 뒤에도 이 값으로 첨자를
    /// 되짚을 수 없다 — 그것이 목적이다.
    private func outgoing(_ offerID: UUID, on connectionID: UUID? = nil) -> OutgoingAuctionOffer? {
        withOutgoing(offerID, on: connectionID) { $0 }
    }

    /// 받은 제안의 국면을 적는다. 여기도 첨자를 들고 있지 않는다 — `performTrade` 를 지나고
    /// 나면 `offers` 가 그대로라는 보장이 없다. (이쪽은 조회 뒤에 바뀌는 필드가 `status`
    /// 하나뿐이라 여는 헬퍼 대신 setter 하나면 된다.)
    private func setStatus(_ status: AuctionOffer.Status, for offerID: UUID) {
        guard let index = offers.firstIndex(where: { $0.id == offerID }) else { return }
        offers[index].status = status
    }

    private func isValid(_ value: AuctionOfferValue, for listing: TradePokemonSnapshot) -> Bool {
        switch value {
        case .pokemon(let pokemon):
            return companion.canPerformTrade(offeredID: listing.mon.id, received: pokemon.mon)
        case .stardust(let amount): return amount > 0 && amount <= SaveTransfer.maxTokenValue
        }
    }

    private func canCommitOutgoing(_ offerID: UUID, received: TradePokemonSnapshot) -> Bool {
        guard let offer = outgoing(offerID) else { return false }
        if let mineID = offer.monID {
            // 내놓은 개체가 아직 내 것인지 매번 다시 본다 — 다른 제안이 먼저 성사됐거나
            // 체육관에 배치됐으면 여기서 멈춰야 한다.
            return sellableMons.contains(where: { $0.id == mineID })
                && companion.canPerformTrade(offeredID: mineID, received: received.mon)
        }
        return offer.stardust > 0 && companion.availableTokens >= offer.stardust
            && !companion.ownedMons.contains(where: { $0.id == received.mon.id })
    }

    private func refundStardustIfNeeded(_ offerID: UUID) {
        guard let offer = outgoing(offerID), offer.stardustEscrowed, offer.stardust > 0 else { return }
        // 표시를 **먼저** 지우고 지급한다. 지급이 저장을 돌리고 그 저장을 본 관측자가 같은 제안을
        // 다시 실패·정리로 끌면(`clearOutgoingResult`·`drop` → 여기) 표시가 아직 서 있어 같은
        // 에스크로가 두 번 나간다 — 첨자 결함과 같은 부류의 재진입이고, 이쪽은 **화폐 복제**다.
        withOutgoing(offerID) { $0.stardustEscrowed = false }
        companion.creditStarPieces(offer.stardust)
    }

    /// 광고값은 TXT 레코드라 이름이 30자에서 잘린다 — 종·레벨·이로치만 대조한다.
    private func matches(_ listing: AuctionListing, _ snapshot: TradePokemonSnapshot) -> Bool {
        listing.speciesID == snapshot.mon.currentID
            && listing.level == snapshot.mon.level
            && listing.isShiny == snapshot.mon.isShiny
    }

    /// 실패 이유는 **제안 자리에** 적는다. 전역 한 줄로 두면 제안이 여럿일 때 어느 제안의
    /// 실패인지 알 수 없고, 잘못 붙은 이유는 없는 것보다 나쁘다.
    private func failOutgoing(_ offerID: UUID, on connection: NWConnection, id: UUID, reason: String) {
        // 환불은 **이 연결의 제안**에만 한다. 국면은 연결로 걸러 놓고 환불만 ID 로 하면, 같은
        // 상대에게 걸어 둔 다른 제안의 ID 를 실은 프레임 한 장이 **아직 살아 있는** 그 제안의
        // 에스크로를 풀어 준다 — 지갑은 돌려받고 제안은 그대로 성사돼 별의모래가 복제된다.
        if outgoing(offerID, on: id) != nil {
            withOutgoing(offerID, on: id) { $0.status = .failed; $0.error = reason }
            refundStardustIfNeeded(offerID)
        }
        send(.failed(offerID: offerID), on: connection, id: id)
    }

    private func displayName(_ mon: MonState) -> String {
        if let nickname = mon.nickname, !nickname.isEmpty { return nickname }
        return mon.names?[mon.currentID]?[companion.language.rawValue] ?? "#\(mon.currentID)"
    }

    private func startListener(for listingID: UUID) {
        listeners[listingID]?.cancel()
        guard let listing = localListings[listingID] else { return }
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = service(for: listingID, listing: listing)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self else { connection.cancel(); return }
                    self.acceptConnection(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state { Task { @MainActor in self?.startListener(for: listingID) } }
            }
            listener.start(queue: .main); listeners[listingID] = listener
        } catch { lastError = error.localizedDescription }
    }

    private func service(for id: UUID, listing: TradePokemonSnapshot) -> NWListener.Service {
        let entries = ["id": id.uuidString, "sid": String(listing.mon.currentID),
                       "name": String(listing.displayName.prefix(30)), "lv": String(listing.mon.level),
                       "shiny": listing.mon.isShiny ? "1" : "0"]
        let name = LANServiceName.make(base: serviceName,
                                       suffix: "#\(String(id.uuidString.prefix(6)))")
        return NWListener.Service(name: name, type: Self.serviceType, domain: nil,
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
            guard case .service(let name, _, _, _) = result.endpoint,
                  !listeners.values.contains(where: { $0.service?.name == name }),
                  case .bonjour(let txt) = result.metadata,
                  let rawID = txt["id"], let id = UUID(uuidString: rawID),
                  let species = txt["sid"].flatMap(Int.init), let level = txt["lv"].flatMap(Int.init),
                  let display = txt["name"] else { return nil }
            let trainer = name.split(separator: "#").dropLast(2).joined(separator: "#")
            return AuctionListing(id: id, trainerName: trainer.isEmpty ? name : trainer,
                                  serviceName: name, endpoint: result.endpoint, speciesID: species,
                                  displayName: display, level: level, isShiny: txt["shiny"] == "1")
        }.sorted { $0.trainerName.localizedCaseInsensitiveCompare($1.trainerName) == .orderedAscending }
    }

    private nonisolated static func parameters() -> NWParameters {
        let parameters = NWParameters.tcp; parameters.includePeerToPeer = true; return parameters
    }

    private func attach(_ connection: NWConnection, id: UUID) { receiveLength(on: connection, id: id) }

    /// 들어온 연결을 장부에 올리고 읽기를 시작한다. **정원 가드는 이 문 안쪽에 있다** —
    /// 호출부에 두면 나중에 생긴 수락 경로가 무제한으로 남는다(회수 규칙을 `reclaimIfIdle`
    /// 하나로 모아 둔 것과 같은 이유다).
    func acceptConnection(_ connection: NWConnection) {
        guard connections.count < Self.maxConnections else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        attach(connection, id: id)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: Task { @MainActor in self?.drop(id) }
            default: break
            }
        }
        connection.start(queue: .main)
    }

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
            Task { @MainActor in self?.drop(id) }
        })
    }

    /// 실패 분기는 **소리 내어 끝낸다.** 조용히 리턴하면 상대가 앱을 정상 종료했을 때 아무도
    /// 그것을 모른다 — TCP 는 FIN 만 남기고 상태는 `.ready` 에 머무르므로 `stateUpdateHandler`
    /// 의 `.failed`/`.cancelled` 가 영영 안 뜬다. 죽은 소켓이 그대로 남고 그 개체는 다른 제안에도
    /// 못 쓴다. 형제 넷(`PokemonTrade`·`BattleNet`·`MultiplayerRoomCenter`·`MemoryHomeVisitCenter`)
    /// 이 전부 이 모양이고, 경매만 남아 있었다(defect-log: 소켓을 정상 종료하면 `.failed` 는 오지
    /// 않는다).
    private func receiveLength(on connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self, weak connection] data, _, _, _ in
            guard let self, let connection else { return }
            guard let data, data.count == 4 else { Task { @MainActor in self.drop(id) }; return }
            let length = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
            guard length > 0, length <= Self.maxMessageBytes else { Task { @MainActor in self.drop(id) }; return }
            Task { @MainActor in self.receiveBody(Int(length), on: connection, id: id) }
        }
    }

    private func receiveBody(_ length: Int, on connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self, weak connection] data, _, _, _ in
            guard let self, let connection else { return }
            guard let data, data.count == length else { Task { @MainActor in self.drop(id) }; return }
            let message = try? JSONDecoder().decode(AuctionWireMessage.self, from: data)
            Task { @MainActor in
                // 못 읽는 프레임은 **건너뛰되 루프는 다시 건다**(형제 `PokemonTrade` 와 같다) —
                // 길이 프리픽스라 스트림이 어긋나지 않고 뒤 버전의 선택적 프레임에 길을 열어 둔다.
                // 다만 회수는 여기서 한 번 봐야 한다: `receive` 를 안 거치므로 `defer` 가 안 돌고,
                // 제안이 안 선 연결(디코드가 안 되는 구버전 `.apply`)은 어느 정원에도 안 세어져
                // 무제한으로 쌓인다. 살아 있는 제안이 붙은 연결은 `reclaimIfIdle` 이 지킨다.
                if let message { self.receive(message, connectionID: id) } else { self.reclaimIfIdle(id) }
                if self.connections[id] === connection { self.receiveLength(on: connection, id: id) }
            }
        }
    }

    /// 이 연결에 아직 나를 것이 남았는가를 보고, 없으면 접는다. **회수 규칙은 여기 하나다** —
    /// 호출부마다 두면 나중에 생긴 종료 경로가 무회수로 남는다(형제 `MemoryHomeVisitCenter` 가
    /// 정확히 그 부류로 물렸다: 끝나는 길이 다섯인데 하나에만 적어 둬서 넷이 샜다).
    ///
    /// 연결은 제안 하나를 나르므로 판정도 하나다 — 그 제안이 끝났으면 연결도 끝났다. 제안이
    /// 아예 안 선 연결(반려된 `.apply`)도 끝난 것이다: 어느 정원에도 세어지지 않아 회수하지
    /// 않으면 무제한으로 쌓인다.
    private func reclaimIfIdle(_ id: UUID) {
        guard connections[id] != nil else { return }
        if let offerID = connectionOfferIDs[id],
           let offer = offers.first(where: { $0.id == offerID }), offer.status.isLive { return }
        if let offer = outgoingOffers.first(where: { $0.connectionID == id }), offer.status.isLive { return }
        closeWhenFlushed(id)
    }

    /// **큐에 남은 프레임을 흘린 뒤에** 접는다. 빈 `.finalMessage` 를 큐 뒤에 붙이면 전송이
    /// 순서를 지키므로 그 완료가 곧 "앞의 것이 다 나갔다" 다 — 보낸 게 있는지 없는지를 호출부가
    /// 알 필요가 없어 부기 상태가 생기지 않는다.
    ///
    /// **왜 즉시 `cancel()` 이 아닌가 — 정직하게 적는다.** 이 경로에서 즉시 `cancel()` 이 프레임을
    /// 버리는 것은 **재현하지 못했다**(루프백에서 3회 모두 두 프레임이 다 도착). 별도 측정에서는
    /// 같은 모양이 20/20 유실됐지만 그 실험은 `NWParameters` 가 달라 이 경로를 충실히 모델링하지
    /// 못했다. 그래서 이 두 줄은 재현된 결함의 수정이 아니라 **순서 보장**이다.
    ///
    /// 그럼에도 남기는 이유: `send` 는 비동기이고 API 에 `forceCancel()` 이 따로 있다는 것은
    /// `cancel()` 의 flush 여부가 계약으로 못 박힌 값이 아니라는 뜻이다. 여기서 종료 프레임 하나를
    /// 잃으면 상대 카드는 `#227` 이후 자동 시간 제한이 없어 **영구히** `.pending` 이고, 그 자리는
    /// 개체 소유권이 오가는 두 단계 커밋이다. 두 줄로 사는 보장이면 싸다.
    /// **테스트는 이 순서를 지키지 않는다** — 루프백이 어느 쪽으로도 전달하기 때문이다.
    private func closeWhenFlushed(_ id: UUID) {
        // 딕셔너리에서 먼저 뺀다 — 같은 연결에 회수가 두 번 걸려도 한 번만 접힌다.
        guard let connection = forget(id) else { return }
        // `.ready` 가 아니면 **흘릴 것도 없고 완료 콜백도 오지 않는다.** `.waiting` 은 실패로
        // 승격되지 않고 무한 재시도라(상대가 사라진 게시물에 제안하고 바로 거둬들이면 그 상태다),
        // 큐에 넣고 기다리면 이 연결은 장부에서 빠진 채 영구히 살아 회수 자체가 없어진다 —
        // 이 파일이 고치려는 부류 그대로다. 아직 안 나간 프레임은 상대도 못 받았으므로 버려도
        // 상대 카드가 `.pending` 에 남지 않는다.
        guard case .ready = connection.state else { connection.cancel(); return }
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: 터미널

    /// 번호 → 내놓을 수 있는 개체. **사유를 갈라 돌려준다** — 후보에서 빠지는 이유가 다섯이고
    /// 사용자가 풀어야 하는 것이 전부 다르다(별을 끄는 것과 파트너를 바꾸는 것은 다른 일이다).
    ///
    /// 판정은 센터가 이미 들고 있는 것들과 **같은 값**을 본다(`sellableMons`·`isFavorite`·
    /// `isCommitted`) — 여기서 따로 세면 한쪽만 넓어져 안내는 되는데 게시가 조용히 안 된다.
    private func sellable(number: Int) -> (mon: MonState?, refusal: String?) {
        let index = TUIRender.rosterIndex(printed: number)
        guard let entry = companion.chatRosterEntries.first(where: { $0.index == index }),
              let mon = companion.ownedMons.first(where: { $0.id == entry.id }) else {
            return (nil, "\(number)번 포켓몬이 없다 — party 로 번호를 확인한다.")
        }
        if companion.isFavorite(mon.id) {
            return (nil, "\(entry.name)은 즐겨찾기라 경매에 낼 수 없다 — 앱에서 별을 먼저 끈다.")
        }
        guard companion.deployableMons.contains(where: { $0.id == mon.id }) else {
            return (nil, "\(entry.name)은 체육관을 지키는 중이라 경매에 낼 수 없다.")
        }
        // 동행을 팔면 모험 정산이 경험치 전량을 별의조각으로 환산해 총수입이 1.5배가 된다 —
        // `sellableMons` 가 동행을 빼는 이유이고, 여기서는 그 사유를 사람 말로 옮긴다.
        guard mon.id != companion.activeMonID else {
            return (nil, "\(entry.name)은 함께 다니는 중이라 경매에 낼 수 없다 — "
                    + "switch 로 다른 개체를 먼저 세운다.")
        }
        if isCommitted(mon.id) {
            return (nil, "\(entry.name)은 이미 게시나 제안에 걸려 있다 — "
                    + "auction 이 찍는 목록을 본다.")
        }
        return (mon, nil)
    }

    private func displayLine(_ snapshot: TradePokemonSnapshot) -> String {
        "\(snapshot.displayName) Lv.\(snapshot.mon.level)"
    }

    /// 제안에 실린 값 한 줄.
    private func valueLine(_ value: AuctionOfferValue) -> String {
        switch value {
        case .pokemon(let pokemon): displayLine(pokemon)
        case .stardust(let amount): "별의모래 \(TUIRender.number(amount))"
        }
    }

    /// 내가 그 제안에 무엇을 걸었는지. 성사되면 그 개체는 이미 내 것이 아니라 목록에서 못
    /// 찾는다 — 그때는 이름만 비운다(앱 카드와 같은 규칙).
    private func offeredLine(_ offer: OutgoingAuctionOffer) -> String {
        guard let monID = offer.monID else {
            return "별의모래 \(TUIRender.number(offer.stardust))"
        }
        return companion.chatRosterEntries.first { $0.id == monID }
            .map { "\($0.name) Lv.\($0.level)" } ?? "내 포켓몬"
    }

    /// 게시한 개체의 `party` 번호. **없을 수 있다** — 경매에 올려 둔 개체를 교환으로 넘기면
    /// 게시물은 남고 개체는 내 것이 아니게 된다.
    private func partyNumber(of monID: UUID) -> Int? {
        companion.chatRosterEntries.first { $0.id == monID }
            .map { TUIRender.printedRosterNumber(index: $0.index) }
    }

    private func drop(_ id: UUID) { forget(id)?.cancel() }

    /// 장부에서 빼는 것과 소켓을 접는 것은 다른 일이다. 즉시 접는 `drop` 과 흘린 뒤 접는
    /// `closeWhenFlushed` 가 앞쪽 절반을 공유한다.
    private func forget(_ id: UUID) -> NWConnection? {
        let connection = connections.removeValue(forKey: id)
        // 커밋을 기다리던 제안이면 실패로 남긴다. 그냥 지우면 게시자 화면에 "교환 처리 중" 이
        // 영영 남고, 잠긴 자리 때문에 다른 제안도 수락할 수 없다.
        if let offerID = connectionOfferIDs[id],
           let offer = offers.first(where: { $0.id == offerID }), offer.status.isLive {
            setStatus(.failed, for: offerID)
        }
        connectionOfferIDs[id] = nil
        // 이 연결을 쓰던 **내 제안 하나만** 실패로 남긴다. 연결이 제안별이라 남의 제안은
        // 그대로 살아 있어야 한다.
        if let offer = outgoingOffers.first(where: { $0.connectionID == id }), offer.status.isLive {
            withOutgoing(offer.id) { $0.status = .failed }
            refundStardustIfNeeded(offer.id)
        }
        return connection
    }
}

/// 이 conformance 가 **이 파일 안에 있는 이유**는 `companion` 이 `private` 이기 때문이다 —
/// 로스터를 봐야 번호를 개체로 접고 사유를 만들 수 있다(교환 창구와 같은 사정).
extension PokemonAuctionCenter: TerminalAuctionControl {
    var terminalState: AuctionTerminalState {
        var state = AuctionTerminalState()
        state.market = listings.enumerated().map { index, listing in
            AuctionScreen.Listed(
                number: index + 1, id: listing.id,
                label: "\(listing.displayName) Lv.\(listing.level)"
                    + (listing.isShiny ? " ✨" : "") + "  \(listing.trainerName)")
        }
        // **앱 카드와 같은 순서**로 센다(`PokemonAuctionView.myListing`). 딕셔너리는 순서가
        // 없으므로 두 화면이 각자 정렬하면 같은 게시물이 화면마다 다른 번호를 갖는다.
        state.mine = localListings.keys.sorted { $0.uuidString < $1.uuidString }
            .compactMap { id -> AuctionScreen.Posted? in
                guard let listing = localListings[id] else { return nil }
                return AuctionScreen.Posted(
                    number: partyNumber(of: listing.mon.id),
                    label: displayLine(listing),
                    offers: offers.filter { $0.listingID == id && $0.status == .pending }.count)
            }
        state.incoming = offers.enumerated().map { index, offer in
            AuctionScreen.Card(number: index + 1, id: offer.id,
                               label: "\(offer.trainerName)  \(valueLine(offer.value))",
                               status: offer.status)
        }
        state.outgoing = outgoingOffers.enumerated().map { index, offer in
            AuctionScreen.Card(number: index + 1, id: offer.id,
                               label: "\(offer.listing.displayName) ← \(offeredLine(offer))",
                               status: offer.status)
        }
        state.unpledged = unpledgedTokens
        state.canOffer = canRegisterOffer
        state.lastError = lastError
        return state
    }

    func post(number: Int) -> String? {
        let (mon, refusal) = sellable(number: number)
        guard let mon else { return refusal }
        publish(mon)
        return nil
    }

    func unpost(number: Int) -> String? {
        let index = TUIRender.rosterIndex(printed: number)
        guard let entry = companion.chatRosterEntries.first(where: { $0.index == index }) else {
            return "\(number)번 포켓몬이 없다 — party 로 번호를 확인한다."
        }
        guard let listingID = localListings.first(where: { $0.value.mon.id == entry.id })?.key else {
            return "\(entry.name)은 경매에 올라 있지 않다 — auction 이 찍는 내 게시물을 본다."
        }
        cancelListing(listingID)
        return nil
    }

    func apply(listingID: UUID, number: Int) -> String? {
        guard let listing = listings.first(where: { $0.id == listingID }) else {
            return Self.listingGone
        }
        let (mon, refusal) = sellable(number: number)
        guard let mon else { return refusal }
        // **닿지 않는다** — 위 판정이 `apply(to:offering:)` 의 가드와 같은 값을 본다. 그래도
        // 조용한 무동작을 남기지 않는다: `nil` 이 오면 제안은 안 갔는데 화면엔 흔적이 없다.
        guard apply(to: listing, offering: mon) != nil else {
            return "제안을 걸지 못했다 — auction 으로 상태를 다시 본다."
        }
        return nil
    }

    func bid(listingID: UUID, stardust: Int) -> String? {
        guard let listing = listings.first(where: { $0.id == listingID }) else {
            return Self.listingGone
        }
        // 정원·미약속 잔액·상한은 실행기가 먼저 본다(같은 값을 본다) — 여기 오는 값은 걸 수
        // 있는 값이고, 그래도 센터가 거절하면 조용히 넘기지 않는다.
        guard apply(to: listing, offeringStardust: stardust) != nil else {
            return "별의모래 제안을 걸지 못했다 — auction 으로 미약속 잔액을 다시 본다."
        }
        return nil
    }

    func accept(offerID: UUID) { accept(offerID) }
    func reject(offerID: UUID) { reject(offerID) }
    func cancelOffer(offerID: UUID) { cancelOutgoingOffer(offerID) }
    func clearResult(offerID: UUID) { clearOutgoingResult(offerID) }

    /// 게시물은 Bonjour 목록이라 **명령을 치는 사이에 사라진다.** 번호를 다시 보라고 말한다 —
    /// 조용히 실패하면 사용자는 자기 번호가 틀린 줄 안다.
    private static let listingGone = "그 게시물이 사라졌다 — auction 으로 목록을 다시 본다."
}
