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
        XCTAssertEqual(MultiplayerWireMessage.protocolVersion, 10)
    }
}

// MARK: - 채팅 잠금 진단 (리포트: "첫 대화 뒤 갑자기 상대 버전 미지원 경고")
//
// 잠금 안내는 상대 빌드가 채팅을 지원하지 않는 경우만 가리킨다. 연결 종료와 결과 재생은 입력만
// 닫을 뿐, 상대 버전이나 세션 상태를 추측하는 별도 문구를 그리지 않는다.
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
    private func centerInBattle(peerChatSupported: Bool?) -> (BattleCenter, CompanionStore) {
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
        return (center, store)
    }

    /// 내 공격은 이미 고르고, 상대는 한 번 맞으면 쓰러진 상태. 상대 행동을 수신하면 실제
    /// `handle(.action)` → `resolveIfReady()` → `deferFinish()` 경로가 결정타를 처리한다.
    private func terminalBattleWithLocalAction() -> NetBattleState {
        let mine = chatSnapshot()
        let opponent = chatSnapshot()
        var state = NetBattleState(iAmA: true, myTeam: [BattleSide(mine)],
                                   oppTeam: [BattleSide(opponent)], rng: SplitMix64(seed: 7))
        state.myAction = .move(index: 0)
        state.opp.hp = 1
        return state
    }

    /// 결정타 경로에서 `dropConnection()` 은 입력만 닫는다. `resolveIfReady` 가 결과를 재생 뒤로
    /// 미루므로, 대화는 `dismissResult()` 가 `.ready` 로 돌아갈 때까지 남아야 한다.
    @MainActor
    func testTheConversationSurvivesTheSocketTeardownAndDiesWithTheSession() {
        let (center, _) = centerInBattle(peerChatSupported: true)
        center.sendChat("잘 부탁해")
        XCTAssertEqual(center.chatMessages.count, 1, "대전 중 보낸 말은 화면에 남는다")

        let state = terminalBattleWithLocalAction()
        center.stageBattleForTesting(state)
        center.handle(.action(turn: state.turn, action: .move(index: 0)))

        XCTAssertEqual(center.chatMessages.count, 1,
                       "결정타의 연결 정리는 소켓만 닫는다 — 주고받은 대화를 지우는 자리가 아니다")
        XCTAssertNotNil(center.pendingFinish, "실제 해상 경로는 결과를 재생 뒤로 미룬다")

        center.commitPendingFinish()
        center.dismissResult()
        XCTAssertTrue(center.chatMessages.isEmpty, "세션이 끝나면(결과 확인) 비운다")
    }

    /// 채팅 미지원 상대는 결정타 재생에서도 버전 안내를 계속 보여야 한다. 이 상태는 옛 피어가
    /// `.battling` 에 들어온 실제 호환 경로에서 가능하다.
    @MainActor
    func testFinalHitReplayKeepsVersionMessageForChatUnsupportedPeer() {
        let (center, store) = centerInBattle(peerChatSupported: nil)
        let state = terminalBattleWithLocalAction()
        center.stageBattleForTesting(state, peerSupportsChat: false)

        center.handle(.action(turn: state.turn, action: .move(index: 0)))

        XCTAssertEqual(center.phase, .battling, "결정타 배치는 결과 화면 전에 재생한다")
        XCTAssertNotNil(center.pendingFinish, "결과는 재생이 따라잡을 때까지 미룬다")
        XCTAssertFalse(center.chatIsAvailable, "재생 중에는 새 대화를 보내지 않는다")
        XCTAssertEqual(center.chatLockMessage, store.l.battleChatUnavailable,
                       "상대가 명시적으로 미지원이면 재생 중에도 올바른 안내를 유지한다")
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

extension BattleChatTests {
    /// 지원 피어의 결정타 재생은 연결이 닫혀 입력만 막힌 상태다. 이때는 안내 문구가 없어야 한다.
    @MainActor
    func testFinalHitReplayShowsNoLockMessageForChatSupportedPeer() {
        let (center, _) = centerInBattle(peerChatSupported: true)
        let state = terminalBattleWithLocalAction()
        center.stageBattleForTesting(state)
        center.handle(.action(turn: state.turn, action: .move(index: 0)))

        XCTAssertFalse(center.chatIsAvailable, "결정타 재생 중에는 입력을 열지 않는다")
        XCTAssertNil(center.chatLockMessage,
                     "지원 피어의 정상적인 연결 종료를 버전 미지원이나 세션 종료로 말하지 않는다")
    }

    /// 반대 방향 — 옛 빌드는 `chatSupported` 를 아예 안 보낸다(옵셔널 필드). 그 경우에만 버전 문구다.
    @MainActor
    func testAPeerBuildWithoutChatKeepsTheVersionMessage() {
        let (center, store) = centerInBattle(peerChatSupported: nil)

        XCTAssertFalse(center.chatIsAvailable)
        XCTAssertEqual(center.chatLockMessage, store.l.battleChatUnavailable,
                       "핸드셰이크가 미지원이라고 말한 경우가 버전 문구의 유일한 자리다")
    }

    /// 배틀을 시작하지 못한 신청 경로도 `.ready` 로 돌아오면 이전 세션의 채팅 사실을 전부 버린다.
    @MainActor
    func testNonBattleTeardownReturningToReadyResetsChatSessionState() {
        let (center, _) = centerInBattle(peerChatSupported: true)
        center.sendChat("hello")
        XCTAssertEqual(center.chatMessages.count, 1)
        XCTAssertTrue(center.peerSupportsChat)

        center.phase = .preparing
        center.cancelChallenge()

        XCTAssertEqual(center.phase, .ready)
        XCTAssertTrue(center.chatMessages.isEmpty)
        XCTAssertFalse(center.chatIsAvailable)
        XCTAssertFalse(center.peerSupportsChat)
    }
}
