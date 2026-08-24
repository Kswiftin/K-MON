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

// MARK: - 채팅 잠금 진단 (리포트: "첫 대화 뒤 갑자기 상대 버전 미지원 경고")
//
// 잠금 사유는 두 개다 — ① 상대 빌드에 채팅이 없다 ② 대전 세션이 닫혔다. 하나의 Bool 로 합치면
// 연결 정리가 지나간 뒤 ②를 ①로 말한다(= 상대 버전을 탓하는 거짓 진단). `rulesVersion` 이 같아야
// 대전이 성립하므로 대전 중인 상대는 항상 채팅을 지원한다 — 그 문구는 그 자리에서 나올 수 없다.
extension BattleChatTests {
    @MainActor
    private final class SilentTimeoutScheduler: BattleChallengeTimeoutScheduling {
        func schedule(_ action: @escaping @MainActor () -> Void) -> BattleChallengeTimeout {
            BattleChallengeTimeout {}
        }
    }

    private func chatSnapshot() -> BattleSnapshot {
        BattleSnapshot(speciesID: 1, name: "#1", trainer: "Trainer", level: 50,
                       nature: nil, isShiny: false, types: [.normal],
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 80),
                       moves: [MoveSpec(id: 1, names: ["en": "Move 1"], type: .normal, power: 20,
                                        damageClass: .physical, accuracy: nil, pp: 20)])
    }

    /// 신청을 받아 대전에 들어간 상태. `beginBattle` 은 `NWConnection` 이 필요해 국면만 맞춘다.
    @MainActor
    private func centerInBattle(peerChatSupported: Bool?) -> BattleCenter {
        let previous = UserDefaults.standard.object(forKey: "doNotDisturb")
        UserDefaults.standard.set(false, forKey: "doNotDisturb")
        addTeardownBlock {
            if let previous { UserDefaults.standard.set(previous, forKey: "doNotDisturb") }
            else { UserDefaults.standard.removeObject(forKey: "doNotDisturb") }
        }
        let store = CompanionStore(
            provider: StubProvider(value: EvoLine(baseID: 1, tree: .init(speciesID: 1, children: []),
                                                  rarity: .common, names: [:])),
            clock: { Date() },
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            rng: SeededRNG(seed: 1))
        let center = BattleCenter(companion: store, challengeTimeoutScheduler: SilentTimeoutScheduler())
        let lead = chatSnapshot()
        center.handle(.challenge(snapshot: lead, lineup: [lead], teamSize: 1, seed: 7,
                                 profile: BattleRankProfile(rank: BattleRank(points: 100), stardust: 10_000),
                                 rulesVersion: BattleEngine.rulesVersion,
                                 chatSupported: peerChatSupported))
        XCTAssertEqual(center.phase, .incoming(peer: "Trainer"), "신청이 들어와야 이후 단계가 성립한다")
        center.phase = .battling
        return center
    }

    /// 결함 트리거: 배틀이 끝나는 순간 `dropConnection()` 이 도는데 화면은 아직 대전 화면이다
    /// (`resolveIfReady` → `deferFinish`, 연출 2.4~3.0초). 그 정리가 대화까지 지우면 사용자에겐
    /// "방금 한 말이 사라지고 채팅이 죽었다"로 보인다.
    @MainActor
    func testTheConversationSurvivesTheSocketTeardownAndDiesWithTheSession() {
        let center = centerInBattle(peerChatSupported: true)
        center.sendChat("잘 부탁해")
        XCTAssertEqual(center.chatMessages.count, 1, "대전 중 보낸 말은 화면에 남는다")

        center.forfeit()   // dropConnection() 을 지나는 공개 경로

        XCTAssertEqual(center.chatMessages.count, 1,
                       "연결 정리는 소켓만 닫는다 — 주고받은 대화를 지우는 자리가 아니다")

        center.dismissResult()
        XCTAssertTrue(center.chatMessages.isEmpty, "세션이 끝나면(결과 확인) 비운다")
    }

    /// 새 메시지 버튼이 개수를 그린다. 보간 백슬래시가 빠져 리터럴 "(count)" 가 나가고 있었다.
    func testTheNewMessageButtonShowsTheActualCount() {
        for lang in [AppLanguage.ko, .en, .ja] {
            let text = L(lang).battleChatNewMessages(3)
            XCTAssertTrue(text.contains("3"), "\(lang): 개수가 들어가야 한다 — \(text)")
            XCTAssertFalse(text.contains("(count)"), "\(lang): 보간이 빠졌다 — \(text)")
        }
    }
}
