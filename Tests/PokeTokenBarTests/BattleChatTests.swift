import XCTest
@testable import PokeTokenBar

final class BattleChatTests: XCTestCase {
    func testMessageRoundTripAndInputNormalization() throws {
        let id = UUID(), sender = UUID()
        let message = BattleChatMessage(id: id, senderID: sender, senderName: "Ash", body: "hello", sentAt: .distantPast)
        XCTAssertEqual(try JSONDecoder().decode(BattleChatMessage.self, from: JSONEncoder().encode(message)), message)
        XCTAssertEqual(BattleChatPolicy.normalizedBody("  hello\n  world  "), "hello world")
        XCTAssertNil(BattleChatPolicy.normalizedBody(" \n\t "))
        XCTAssertNil(BattleChatPolicy.normalizedBody(String(repeating: "a", count: 201)))
    }

    func testBurstLimitRecoveryAndHistoryCap() {
        let sender = UUID(), start = Date(timeIntervalSinceReferenceDate: 1_000)
        var limiter = BattleChatRateLimiter()
        XCTAssertTrue(limiter.allows(sender, now: start))
        XCTAssertTrue(limiter.allows(sender, now: start))
        XCTAssertTrue(limiter.allows(sender, now: start))
        XCTAssertFalse(limiter.allows(sender, now: start))
        XCTAssertTrue(limiter.allows(sender, now: start.addingTimeInterval(1)))

        var history = BattleChatHistory()
        for number in 0...50 {
            history.append(BattleChatMessage(senderID: sender, senderName: "A", body: "\(number)"))
        }
        XCTAssertEqual(history.messages.count, 50)
        XCTAssertEqual(history.messages.first?.body, "1")
        history.reset()
        XCTAssertTrue(history.messages.isEmpty)
    }

    func testChatWireRoundTripAndRoomProtocolVersion() throws {
        let chat = NetMessage.chat(BattleChatMessage(senderID: UUID(), senderName: "A", body: "hi"))
        guard case .chat(let decoded) = try JSONDecoder().decode(NetMessage.self, from: JSONEncoder().encode(chat)) else {
            return XCTFail("chat wire case")
        }
        XCTAssertEqual(decoded.body, "hi")
        XCTAssertEqual(MultiplayerWireMessage.protocolVersion, 7)
    }
}
