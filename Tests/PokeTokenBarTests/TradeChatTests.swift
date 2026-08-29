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
        func afterAccept(chatSupported: Bool?) -> PokemonTradeCenter {
            let center = makeCenter()
            center.request(TradePeer(name: "Blue", serviceName: "Blue#000000",
                                     endpoint: .service(name: "Blue#000000",
                                                        type: PokemonTradeCenter.serviceType,
                                                        domain: "local.", interface: nil)))
            XCTAssertEqual(center.phase, .requesting(peer: "Blue"))
            center.receive(.accept(trainer: "Blue", chatSupported: chatSupported))
            XCTAssertEqual(center.phase, .negotiating(peer: "Blue"))
            return center
        }

        let legacyPeer = afterAccept(chatSupported: nil)
        XCTAssertFalse(legacyPeer.peerSupportsChat)
        legacyPeer.sendChat("보내면 상대 세션이 멈춘다")
        XCTAssertTrue(legacyPeer.chatMessages.isEmpty)
        legacyPeer.cancel()

        let modernPeer = afterAccept(chatSupported: true)
        XCTAssertTrue(modernPeer.peerSupportsChat)
        modernPeer.sendChat("반가워")
        XCTAssertEqual(modernPeer.chatMessages.map(\.body), ["반가워"])
        modernPeer.cancel()
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
