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

    /// 결함 트리거: 배틀이 끝나는 순간 `dropConnection()` 이 도는데 화면은 아직 대전 화면이다
    /// (`resolveIfReady` → `deferFinish`, 연출 2.4~3.0초). 그 정리가 대화까지 지우면 사용자에겐
    /// "방금 한 말이 사라지고 채팅이 죽었다"로 보인다.
    @MainActor
    func testTheConversationSurvivesTheSocketTeardownAndDiesWithTheSession() {
        let (center, _) = centerInBattle(peerChatSupported: true)
        center.sendChat("잘 부탁해")
        XCTAssertEqual(center.chatMessages.count, 1, "대전 중 보낸 말은 화면에 남는다")

        center.forfeit()   // dropConnection() 을 지나는 공개 경로

        XCTAssertEqual(center.chatMessages.count, 1,
                       "연결 정리는 소켓만 닫는다 — 주고받은 대화를 지우는 자리가 아니다")

        center.dismissResult()
        XCTAssertTrue(center.chatMessages.isEmpty, "세션이 끝나면(결과 확인) 비운다")
    }

    /// 결정타는 `dropConnection()` 으로 입력을 닫지만, arena 는 마지막 배치를 재생하려고 아직
    /// `.battling` 이다. 이 창에는 채팅 사유 문구를 겹쳐 보이지 않는다.
    @MainActor
    func testFinalHitReplayHidesChatLockMessageUntilTheSessionEnds() {
        let (center, store) = centerInBattle(peerChatSupported: true)
        let state = terminalBattleWithLocalAction()
        center.stageBattleForTesting(state)

        center.handle(.action(turn: state.turn, action: .move(index: 0)))

        XCTAssertEqual(center.phase, .battling, "결정타 배치는 결과 화면 전에 재생한다")
        XCTAssertNotNil(center.pendingFinish, "결과는 재생이 따라잡을 때까지 미룬다")
        XCTAssertFalse(center.chatIsAvailable, "재생 중에는 새 대화를 보내지 않는다")
        XCTAssertNil(center.chatLockMessage, "재생 중에는 잠긴 이유를 겹쳐 보이지 않는다")

        center.commitPendingFinish()

        XCTAssertEqual(center.phase, .finished(iWon: true, byForfeit: false))
        XCTAssertEqual(center.chatLockMessage, store.l.battleChatSessionOver,
                       "재생이 끝난 뒤에는 정상적인 세션 종료 안내가 돌아온다")
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
    /// 대전이 성립하려면 `rulesVersion` 이 같아야 하므로(`handle(.challenge)`·`handle(.accept)`)
    /// **대전 중인 상대는 항상 채팅을 지원한다.** 연결이 닫혔다는 이유로 "상대 버전 미지원"을 그리면
    /// 사용자에게 없는 원인을 알려 주는 것이다 — 리포트된 증상이 정확히 이것이다.
    @MainActor
    func testAClosedSessionIsNotBlamedOnThePeerAppVersion() {
        let (center, store) = centerInBattle(peerChatSupported: true)
        XCTAssertTrue(center.chatIsAvailable, "대전 중에는 열려 있다")
        XCTAssertNil(center.chatLockMessage, "열려 있으면 안내 문구가 없다")

        center.forfeit()   // 배틀이 끝나는 순간과 같은 상태 — 소켓은 닫혔고 화면은 아직 대전 화면이다

        XCTAssertFalse(center.chatIsAvailable, "닫힌 세션에는 입력을 열지 않는다")
        XCTAssertEqual(center.chatLockMessage, store.l.battleChatSessionOver,
                       "세션이 닫힌 것을 상대 버전 탓으로 말하면 안 된다")
    }

    /// 반대 방향 — 옛 빌드는 `chatSupported` 를 아예 안 보낸다(옵셔널 필드). 그 경우에만 버전 문구다.
    @MainActor
    func testAPeerBuildWithoutChatKeepsTheVersionMessage() {
        let (center, store) = centerInBattle(peerChatSupported: nil)

        XCTAssertFalse(center.chatIsAvailable)
        XCTAssertEqual(center.chatLockMessage, store.l.battleChatUnavailable,
                       "핸드셰이크가 미지원이라고 말한 경우가 버전 문구의 유일한 자리다")
    }
}
