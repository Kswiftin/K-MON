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
    /// 교환으로 들어오는 추억이 놓일 수 있는 창. 앱은 이보다 오래되지 않았고, 아득한 과거는
    /// 일기의 맨 아래(미래는 맨 위)에 영원히 박힌다.
    ///
    /// 개체의 `firstMetAt` 은 **이 창을 쓰지 않는다.** 잘라 봐야 3650일까지 열려 있는데 친밀도
    /// 하트는 120일이면 이미 만점이라 아무것도 막지 못한다 — 방금 받은 개체가 "함께한 3650일 ·
    /// ♥♥♥♥♥" 로 뜬다. 받은 개체의 첫 만남은 `CompanionStore.performTrade` 가 로컬 시각으로 짓는다.
    static let maxAge: TimeInterval = 3650 * 24 * 60 * 60

    let monID: UUID
    let entries: [TradeMemoryEntry]

    static func clampedDate(_ date: Date, now: Date) -> Date {
        min(max(date, now.addingTimeInterval(-maxAge)), now)
    }

    /// 신뢰경계 클램프다 — `private` 로 두면 원격 페이로드 검증이 무테스트로 남는다.
    /// (`MemoryHomeVisitCenter.valid` 를 열어 둔 이유와 같다.)
    ///
    /// 본문 정규화는 같은 소켓의 형제 경계(`BattleChatPolicy.normalizedBody`)를 그대로 쓴다.
    /// 여기서 따로 접다가 스칼라 단위로 훑는 판을 썼고, ZWJ 가 제어문자로 잡혀 이모지 가족이
    /// 쪼개지면서 길이가 부풀어 정상 추억이 통째로 버려졌다 — 보낸 쪽은 같은 교환에서 앨범을
    /// 지우므로 그 줄은 영구 소실이었다.
    static func sanitized(_ payload: TradeMemoryPayload, now: Date = Date()) -> TradeMemoryPayload {
        TradeMemoryPayload(
            monID: payload.monID,
            entries: payload.entries.prefix(maxEntries).compactMap { entry in
                // 손글씨는 트레이너가 직접 쓴 글이라 양방향 모두 오가지 않는다. 앨범의
                // `record` 도 같은 이유로 `.manual` 을 거부하지만, 경계에서도 명시적으로 막는다.
                guard entry.source != .manual,
                      let body = BattleChatPolicy.normalizedBody(entry.body, limit: bodyLimit) else { return nil }
                return TradeMemoryEntry(body: body, source: entry.source,
                                        createdAt: clampedDate(entry.createdAt, now: now))
            })
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
    /// 한 세션이 받아들이는 `.memories` 프레임 수. 정상 교환은 **한 번**이면 끝난다(신청자는
    /// `.committed` 뒤에, 수신자는 성사 뒤에 한 번씩 보낸다) — 여유를 두되 열어 두지는 않는다.
    /// 형제 프레임은 전부 상한이 있다: `.chat` 은 토큰 버킷, `.roster` 는 `prefix(100)`,
    /// 트레이너 이름은 길이 클램프. 여기만 없으면 1MB 프레임을 끝없이 밀어 `sanitized` 를
    /// 메인 스레드에서 계속 돌릴 수 있다.
    nonisolated static let maxMemoriesFramesPerSession = 4

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
    /// 수신자가 성사 직후 보낸 추억. 그 프레임은 `.committed` 보다 **앞서** 오므로(TCP 는 순서를
    /// 지킨다) 여기 담아 뒀다가 신청자 쪽 `performTrade` 가 성공할 때 함께 넣는다.
    /// `private(set)` 인 이유는 "협상 밖 프레임은 버퍼에도 안 들어간다" 를 테스트가 봐야 해서다.
    private(set) var pendingIncomingMemories: TradeMemoryPayload?
    private var memoriesFramesSeen = 0

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
    /// `private(set)` 인 이유는 "확인 프레임이 두 번 와도 트랜잭션이 재발급되지 않는다" 를 테스트가
    /// 봐야 해서다 — 재발급되면 상대의 `.committed(앞선 ID)` 가 거부돼 한쪽만 교환된다.
    private(set) var activeTransaction: UUID?

    init(companion: CompanionStore) {
        self.companion = companion
        let trainer = companion.trainerName.trimmingCharacters(in: .whitespaces)
        let fallback = NSFullUserName().isEmpty ? (Host.current().localizedName ?? "Trainer") : NSFullUserName()
        myName = trainer.isEmpty ? fallback : trainer
        // 길이는 `LANServiceName` 이 바이트로 자른다 — 한글 이름은 21자에 Bonjour 상한(63바이트)을
        // 넘고, 잘리는 건 꼬리라 고유 접미가 먼저 사라진다.
        myServiceName = LANServiceName.make(base: trainer.isEmpty ? fallback : trainer,
                                            suffix: "#\(String(UUID().uuidString.prefix(6)))")
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
        // 즐겨찾기는 잃는 동작을 막는 자물쇠다 — 목록이 잠긴 줄로 보여 주지만 여기서도 막는다.
        if let mon, companion.isFavorite(mon.id) { return }
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
              let mon = companion.deployableMons.first(where: { $0.id == id }) else { return }
        selectOffer(mon)
    }

    /// 체육관에 배치한 넷은 교환 후보가 아니다 — 관장이 지키는 동안 남에게 넘어가면 방어팀에
    /// 구멍이 난다.
    private var localRoster: [TradePokemonSnapshot] {
        companion.deployableMons.map { TradePokemonSnapshot(mon: $0, displayName: displayName(for: $0)) }
    }

    /// 고른 **뒤에** 별을 켰을 수도 있다 — 선택 시점만 보면 그 개체가 그대로 나간다.
    /// 확정이 내 쪽 마지막 되돌릴 수 있는 지점이라 여기서 한 번 더 본다.
    func confirm() {
        guard case .negotiating = phase, let offeredID = localOffer?.mon.id, remoteOffer != nil,
              !companion.isFavorite(offeredID) else { return }
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

    /// **국면을 반드시 본다.** `.confirm(true)` 는 상대가 부르는 프레임이라 두 번 올 수 있는데
    /// (구현이 다른 클라이언트·재전송·의도적 재생), 국면을 안 보면 이미 `.committing` 인 세션이
    /// 트랜잭션 ID 를 새로 발급하고 커밋을 한 번 더 보낸다. 그러면 정직한 상대가 앞선 ID 로 교환을
    /// 마치고 보낸 `.committed(앞선 ID)` 가 `activeTransaction == id` 에서 거부된다 — 상대는
    /// 개체를 내줬는데 나는 그대로 들고 있는, 한쪽만 성사된 교환이 된다.
    private func beginCommitIfReady() {
        guard case .negotiating = phase,
              isInitiator, localConfirmed, remoteConfirmed,
              localOffer != nil, remoteOffer != nil else { return }
        let id = UUID()
        activeTransaction = id
        phase = .committing
        send(.commit(id))
    }

    /// 추억은 **교환이 실제로 성사된 뒤에만** 나간다. 그 전에 보내면 거절·취소로 끝난 협상에도
    /// 이미 상대 손에 가 있고 되돌릴 방법이 없다 — 상대는 아무것도 내주지 않고 앨범만 가져갈 수
    /// 있게 된다(내 명부는 수락 직후 건너가므로 거절당할 제안을 만드는 건 어렵지 않다).
    ///
    /// 페이로드는 `performTrade` 가 **앨범을 지우기 전에** 미리 만들어 둬야 한다. 그래서 부르는
    /// 쪽이 값을 들고 있다가 성사 뒤에 이 함수로 넘긴다.
    private func send(memories payload: TradeMemoryPayload?) {
        guard let payload else { return }
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
        // 클램프의 "지금"은 저장소의 시계여야 한다 — 여기서 벽시계를 쓰면 같은 페이로드가 경계와
        // 적용부에서 서로 다른 창으로 잘린다.
        case .memories(let payload):
            guard memoriesFramesSeen < Self.maxMemoriesFramesPerSession else {
                AppLog.write("trade memories frame dropped — session cap reached"); return
            }
            memoriesFramesSeen += 1
            let clean = TradeMemoryPayload.sanitized(payload, now: companion.now)
            switch phase {
            case .negotiating, .committing:
                pendingIncomingMemories = clean
            // 성사 **뒤에** 온 추억은 버퍼가 아니라 곧바로 앨범으로 간다. 상대는 교환이 실제로
            // 일어난 걸 확인한 뒤에야 보내므로(그게 거절로 끝난 협상에 추억이 남지 않는 유일한
            // 방법이다), 수신자 쪽에서 이 프레임은 항상 `performTrade` 다음에 도착한다.
            // 버퍼에만 넣고 끝내면 수신자는 영영 빈 앨범을 받는다.
            case .animating, .completed:
                guard let received = remoteOffer?.mon.id else { return }
                companion.adoptTradedMemories(clean, for: received)
            default:
                AppLog.write("trade memories frame dropped — no active negotiation")
            }
        case .commit(let id):
            // 국면을 본다 — 성사 뒤에 `.commit` 이 한 번 더 오면(재전송·재생) 확인 플래그가 그대로
            // 남아 있어 아래 가드를 통과하고, 이미 끝난 교환이 `performTrade` 재실패로 실패 화면이
            // 된다(받은 개체는 이미 내 것이라 `ownedMons` 검사에 걸린다).
            guard case .negotiating = phase else { return }
            guard !isInitiator, localConfirmed, remoteConfirmed,
                  let mine = localOffer, let theirs = remoteOffer else {
                send(.decline(reason: "trade-changed")); return
            }
            phase = .committing
            // 앨범은 `performTrade` 가 지운다 — 보낼 값은 미리 만들어 두고, 전송은 성사 뒤에 한다.
            let outgoing = companion.tradeMemoryPayload(for: mine.mon.id)
            guard companion.performTrade(offeredID: mine.mon.id, received: theirs.mon,
                                         incomingMemories: pendingIncomingMemories) else {
                send(.decline(reason: "invalid-trade")); phase = .failed("교환 정보를 확인할 수 없습니다."); return
            }
            activeTransaction = id
            // `.committed` 보다 **먼저** 나가야 한다. 상대는 커밋 확인을 보고 화면을 닫을 수 있고,
            // 그 뒤에 보낸 프레임이 도착한다는 보장은 없다.
            send(memories: outgoing)
            send(.committed(id))
            phase = .animating
        case .committed(let id):
            // `.committing` 일 때만 받는다 — 그러지 않으면 중복 `.committed` 가 이미 끝난 교환을
            // `performTrade` 재실패로 실패 화면에 앉힌다.
            guard isInitiator, case .committing = phase, activeTransaction == id,
                  let mine = localOffer, let theirs = remoteOffer else {
                phase = .failed("교환을 완료하지 못했습니다."); return
            }
            let outgoing = companion.tradeMemoryPayload(for: mine.mon.id)
            guard companion.performTrade(offeredID: mine.mon.id, received: theirs.mon,
                                         incomingMemories: pendingIncomingMemories) else {
                phase = .failed("교환을 완료하지 못했습니다."); return
            }
            phase = .animating
            // 여기가 신청자가 교환 성사를 **처음 아는** 지점이다. 이 전에 보내면 상대가 `.decline`
            // 로 끝낸 협상에도 앨범이 이미 건너가 있다.
            send(memories: outgoing)
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
        pendingIncomingMemories = nil; memoriesFramesSeen = 0
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
        // 전송 실패는 연결이 끊긴 것으로 다룬다 — 그러지 않으면 상대가 사라진 뒤에도 화면이
        // 협상 중인 채로 멈춰 있고, 교환은 어느 쪽에서도 끝나지 않는다.
        connection.send(content: frame, completion: .contentProcessed { [weak self, weak connection] error in
            guard error != nil, let connection else { return }
            Task { @MainActor in self?.connectionDropped(connection) }
        })
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
