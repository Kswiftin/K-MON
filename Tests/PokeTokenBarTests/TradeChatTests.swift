import Network
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// 교환 협상 중 자유 채팅. 배틀 채팅의 정책·UI 를 그대로 쓰고, 여기서 검증하는 것은 **교환 쪽에만
/// 있는 세 가지**다 — 구버전과의 호환 협상(`chatSupported`), 상대가 보낸 값의 신뢰경계,
/// 세션이 끝날 때 대화가 남지 않는지.
final class TradeChatTests: XCTestCase {
    @MainActor
    private func makeStore() -> CompanionStore {
        CompanionStore(
            provider: StubProvider(value: EvoLine(baseID: 1, tree: .init(speciesID: 1, children: []),
                                                  rarity: .common, names: [:])),
            clock: { Date() },
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            rng: SeededRNG(seed: 1))
    }

    @MainActor
    private func makeCenter() -> PokemonTradeCenter { PokemonTradeCenter(companion: makeStore()) }

    /// 신청을 **거는** 쪽. `request` 는 소켓을 열어야 `.requesting` 으로 가므로, 아무도 듣지 않는
    /// 루프백 포트로 연다 — Bonjour 이름은 영영 안 풀리는 mDNS 조회를 돌리고, 최근 macOS 에서는
    /// 테스트 러너에 로컬 네트워크 권한 프롬프트까지 띄운다(게이트가 번들을 두 번 돌린다).
    @MainActor
    private func afterAccept(chatSupported: Bool?, trainer: String = "Blue") -> PokemonTradeCenter {
        let center = makeCenter()
        center.request(TradePeer(name: "Blue", serviceName: "Blue#000000",
                                 endpoint: .hostPort(host: "127.0.0.1", port: 9)))
        XCTAssertEqual(center.phase, .requesting(peer: "Blue"))
        center.receive(.accept(trainer: trainer, chatSupported: chatSupported))
        return center
    }

    /// 협상까지 진행된 세션. 신청을 받는 쪽(비-initiator)이라 소켓 없이도 상태가 진행된다.
    @MainActor
    private func negotiating(peerSupportsChat: Bool,
                             store: CompanionStore? = nil) -> PokemonTradeCenter {
        let center = PokemonTradeCenter(companion: store ?? makeStore())
        center.receive(.request(version: TradeWireMessage.protocolVersion, trainer: "Blue",
                                chatSupported: peerSupportsChat ? true : nil))
        center.accept()
        return center
    }

    // MARK: - 호환 협상

    /// 채팅 프레임은 왕복해야 하고, **`chatSupported` 를 모르는 구버전이 보낸 신청**도 그대로
    /// 디코드돼야 한다. 이 케이스가 깨지면 구버전과는 교환 자체가 성립하지 않는다.
    func testChatFrameRoundTripAndLegacyRequestWithoutChatSupported() throws {
        let chat = TradeWireMessage.chat(BattleChatMessage(senderID: UUID(), senderName: "Blue", body: "hi"))
        guard case .chat(let decoded) = try JSONDecoder().decode(TradeWireMessage.self,
                                                                 from: JSONEncoder().encode(chat)) else {
            return XCTFail("chat wire case")
        }
        XCTAssertEqual(decoded.body, "hi")

        // 구버전 빌드가 실제로 내보내던 바이트 — `chatSupported` 키가 아예 없다.
        let legacy = Data(#"{"request":{"version":2,"trainer":"Blue"}}"#.utf8)
        guard case .request(let version, let trainer, let chatSupported) =
                try JSONDecoder().decode(TradeWireMessage.self, from: legacy) else {
            return XCTFail("legacy request case")
        }
        XCTAssertEqual(version, 2)
        XCTAssertEqual(trainer, "Blue")
        XCTAssertNil(chatSupported)

        // 프로토콜 버전은 그대로 2 다 — 채팅은 버전이 아니라 협상으로 가른다.
        XCTAssertEqual(TradeWireMessage.protocolVersion, 2)
    }

    /// 상대가 지원을 알리지 않으면 입력이 잠기고, 우리가 프레임을 **보내지 않는다**.
    /// (구버전은 알 수 없는 프레임을 만나면 교환 세션이 통째로 무너진다.)
    @MainActor
    func testChatStaysLockedUntilPeerAdvertisesSupport() {
        let legacyPeer = negotiating(peerSupportsChat: false)
        XCTAssertFalse(legacyPeer.peerSupportsChat)
        legacyPeer.sendChat("안녕")
        XCTAssertTrue(legacyPeer.chatMessages.isEmpty)

        let modernPeer = negotiating(peerSupportsChat: true)
        XCTAssertTrue(modernPeer.peerSupportsChat)
        modernPeer.sendChat("  안녕   하세요 ")
        XCTAssertEqual(modernPeer.chatMessages.map(\.body), ["안녕 하세요"])
        XCTAssertEqual(modernPeer.chatMessages.first?.senderID, modernPeer.chatSenderID)
    }

    /// 협상은 두 경로로 열린다 — 신청을 **받는** 쪽은 `.request`, **거는** 쪽은 `.accept` 로
    /// 상대의 지원 여부를 듣는다. 같은 플래그를 두 군데서 세우므로 형제 경로도 밟는다(위 테스트들은
    /// 받는 쪽만 밟아서, 거는 쪽이 `true` 로 굳어 있어도 전부 통과했다).
    @MainActor
    func testInitiatorLearnsChatSupportFromTheAcceptFrame() {
        let legacyPeer = afterAccept(chatSupported: nil)
        XCTAssertEqual(legacyPeer.phase, .negotiating(peer: "Blue"))
        XCTAssertFalse(legacyPeer.peerSupportsChat)
        legacyPeer.sendChat("보내면 상대 세션이 멈춘다")
        XCTAssertTrue(legacyPeer.chatMessages.isEmpty)
        legacyPeer.cancel()

        let modernPeer = afterAccept(chatSupported: true)
        XCTAssertEqual(modernPeer.phase, .negotiating(peer: "Blue"))
        XCTAssertTrue(modernPeer.peerSupportsChat)
        modernPeer.sendChat("반가워")
        XCTAssertEqual(modernPeer.chatMessages.map(\.body), ["반가워"])
        modernPeer.cancel()
    }

    // MARK: - 상대가 조용히 나갔을 때

    /// 상대가 앱을 **정상 종료**하면 소켓은 FIN 만 남기고 `.failed` 로 가지 않는다. `attach` 의
    /// 상태 감시는 `.failed` 만 보므로, 이 경로를 끝내는 건 읽기 루프뿐이다 — 예전엔 그냥 리턴해
    /// 죽은 소켓 위에 "교환 중" 이 영영 남았다(확정도 커밋도 오지 않는다).
    @MainActor
    func testTheSessionEndsWhenThePeerClosesTheSocketWithoutFailing() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { peer in
            // 연결이 서면 곧바로 정상 종료한다. `cancel()` 은 FIN 이라 우리 쪽 상태는 `.ready` 다.
            peer.stateUpdateHandler = { if case .ready = $0 { peer.cancel() } }
            peer.start(queue: .main)
        }
        listener.start(queue: .main)
        addTeardownBlock { listener.cancel() }
        // 리스너가 `.ready` 가 되기 전의 `port` 는 아직 `.any`(0) 다 — 실제로 배정된 포트를 기다린다.
        guard let port = pump(until: { listener.port.flatMap { $0 == .any ? nil : $0 } }) else {
            return XCTFail("루프백 리스너가 서지 않았다")
        }

        let center = makeCenter()
        center.attachForTesting(NWConnection(to: .hostPort(host: "127.0.0.1", port: port), using: .tcp))
        // 우리 쪽에서는 **아무것도 보내지 않는다**. 이미 닫힌 소켓에 프레임을 밀면 RST 가 돌아와
        // 상태가 `.failed` 로 가고, 그러면 세션을 끝낸 게 `attach` 의 상태 감시인지 읽기 루프인지
        // 구별할 수 없다 — 실제로 `accept()` 를 부르던 판본은 결함을 되주입해도 통과했다.
        center.receive(.request(version: TradeWireMessage.protocolVersion, trainer: "Blue", chatSupported: true))
        XCTAssertEqual(center.phase, .incoming(peer: "Blue"))

        let ended = pump(until: { if case .failed = center.phase { return true } else { return nil } })
        XCTAssertEqual(ended, true, "상대가 소켓을 닫으면 세션도 끝나야 한다 — 지금 국면: \(center.phase)")
    }

    /// 메인 큐에 걸린 `NWConnection` 콜백을 돌리며 `probe` 가 값을 낼 때까지 기다린다.
    @MainActor
    private func pump<T>(until probe: () -> T?, timeout: TimeInterval = 5) -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = probe() { return value }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return probe()
    }

    // MARK: - 신뢰경계 (부류 스윕: 상대가 부르는 값이 화면에 닿는 나머지 자리)

    /// `id` 는 `BattleChatMessage` 의 `Identifiable` 키 — 화면의 `ForEach` 가 이 값으로 행을 가른다.
    /// 상대가 고른 값을 그대로 쓰면 같은 값을 두 번 보내는 것만으로 목록이 무너진다.
    @MainActor
    func testPeerChosenMessageIDsCannotCollideOnScreen() {
        let center = negotiating(peerSupportsChat: true)
        let reused = UUID()
        center.receive(.chat(BattleChatMessage(id: reused, senderID: UUID(), senderName: "Blue", body: "하나")))
        center.receive(.chat(BattleChatMessage(id: reused, senderID: UUID(), senderName: "Blue", body: "둘")))
        XCTAssertEqual(center.chatMessages.map(\.body), ["하나", "둘"])
        XCTAssertEqual(Set(center.chatMessages.map(\.id)).count, 2, "화면 키는 상대가 정하지 않는다")
    }

    /// 핸드셰이크의 트레이너 이름도 상대가 부르는 값이고, 프레임 상한(1MB)까지 채울 수 있다.
    /// 그 이름은 협상 헤더와 **채팅 행마다** 박히는데 두 곳 다 `lineLimit` 이 없다.
    @MainActor
    func testPeerTrainerNameIsClampedOnBothHandshakeBranches() {
        let huge = String(repeating: "괴", count: 5_000)
        let clamped = String(repeating: "괴", count: BattleChatPolicy.maximumNameLength)

        // 받는 쪽 — `.request`
        let incoming = makeCenter()
        incoming.receive(.request(version: TradeWireMessage.protocolVersion, trainer: huge, chatSupported: true))
        XCTAssertEqual(incoming.phase, .incoming(peer: clamped))

        // 거는 쪽 — `.accept`. 같은 클램프를 두 군데서 걸므로 형제 분기도 밟는다.
        let initiator = afterAccept(chatSupported: true, trainer: huge)
        XCTAssertEqual(initiator.phase, .negotiating(peer: clamped))
        initiator.cancel()

        // 이름이 통째로 비어 있으면 협상을 열지 않는다(빈 이름은 화면에서 발신자를 지운다).
        let empty = makeCenter()
        empty.receive(.request(version: TradeWireMessage.protocolVersion, trainer: "   ", chatSupported: true))
        XCTAssertEqual(empty.phase, .ready)
    }

    /// 협상 밖에서는 어느 방향으로도 대화가 열리지 않는다.
    @MainActor
    func testChatIgnoredOutsideNegotiation() {
        let center = makeCenter()
        center.sendChat("아직 아무와도 연결되지 않았다")
        center.receive(.chat(BattleChatMessage(senderID: UUID(), senderName: "Blue", body: "hi")))
        XCTAssertTrue(center.chatMessages.isEmpty)
    }

    // MARK: - 신뢰경계 (상대가 보낸 값)

    /// 상대 프레임의 `body`·`senderName`·`senderID` 는 전부 상대가 부르는 값이다. 길이·정규형을
    /// 다시 재고, 이름은 우리가 아는 상대 이름으로 덮고, 속도 제한은 상대가 못 바꾸는 키로 센다.
    @MainActor
    func testIncomingChatIsRevalidatedAttributedAndRateLimited() {
        let center = negotiating(peerSupportsChat: true)
        func incoming(_ body: String, name: String = "Blue", sender: UUID = UUID()) {
            center.receive(.chat(BattleChatMessage(senderID: sender, senderName: name, body: body)))
        }

        incoming(String(repeating: "a", count: BattleChatPolicy.maximumLength + 1))
        incoming("   ")
        incoming("  앞뒤가 안 다듬어진 문장  ")   // 정규형이 아니면 그대로 버린다
        XCTAssertTrue(center.chatMessages.isEmpty)

        incoming("반가워", name: "관리자")
        XCTAssertEqual(center.chatMessages.map(\.senderName), ["Blue"])
        XCTAssertNotEqual(center.chatMessages.first?.senderID, center.chatSenderID)

        // 보낸 사람 ID 를 매번 새로 지어내도 상대 몫의 토큰 버킷 하나만 소비한다.
        incoming("2", sender: UUID())
        incoming("3", sender: UUID())
        incoming("4", sender: UUID())
        XCTAssertEqual(center.chatMessages.count, 3, "상대는 연속 3개까지만 받는다")

        // 내 전송 예산은 상대가 다 써도 그대로 남아 있어야 한다.
        center.sendChat("내 차례")
        XCTAssertEqual(center.chatMessages.last?.body, "내 차례")
    }

    // MARK: - 수명

    /// 교환이 끝나거나 취소되면 대화도 협상 결과처럼 통째로 사라진다.
    @MainActor
    func testChatAndSupportFlagClearWhenSessionEnds() {
        let center = negotiating(peerSupportsChat: true)
        center.sendChat("잘 부탁해")
        XCTAssertFalse(center.chatMessages.isEmpty)

        center.cancel()
        XCTAssertEqual(center.phase, .ready)
        XCTAssertTrue(center.chatMessages.isEmpty)
        XCTAssertFalse(center.peerSupportsChat)
    }

    // MARK: - 화면 도달 가능성

    /// 코어만 맞고 **화면엔 없는** 부류(테스트 게이트가 grep 으로 쫓는 그것)를 여기서 막는다.
    /// 잠긴 세션은 안내 한 줄이 더 그려지므로 협상 화면이 더 높아야 한다 — 두 높이가 같아지는
    /// 순간은 패널이 교환 화면에 아예 안 붙었다는 뜻이다.
    @MainActor
    func testNegotiationScreenActuallyDrawsTheChatPanel() {
        func height(peerSupportsChat: Bool) -> CGFloat {
            let store = makeStore()
            let center = negotiating(peerSupportsChat: peerSupportsChat, store: store)
            let view = PokemonTradeView(store: store, center: center)
            return NSHostingController(rootView: view.frame(width: PopoverMetrics.contentWidth))
                .sizeThatFits(in: CGSize(width: PopoverMetrics.contentWidth,
                                         height: .greatestFiniteMagnitude)).height
        }
        let locked = height(peerSupportsChat: false)
        let open = height(peerSupportsChat: true)
        XCTAssertGreaterThan(locked, open,
                             "채팅 패널이 협상 화면에 실제로 그려져야 한다 (잠금 안내 한 줄만큼 더 높다)")
        XCTAssertGreaterThan(open, 0)
    }
}
