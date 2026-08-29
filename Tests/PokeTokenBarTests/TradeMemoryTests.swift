import XCTest
@testable import PokeTokenBar

/// 교환으로 넘어가는 추억. 검증하는 것은 네 가지다 — 보내는 쪽이 **무엇을 빼는가**(손글씨 메모·
/// 숨긴 기억·대화 원문), 받는 쪽이 **무엇을 안 믿는가**(개체 ID·날짜·길이·건수·출처),
/// 적용이 **두 방향(신청자/수신자) × 두 자리(동행/박스)** 에서 모두 도는가, 그리고 커밋 없이
/// 끝난 세션엔 아무것도 남지 않는가.
final class TradeMemoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 앨범·대화 파일은 상태 파일 **옆에** 산다. 테스트마다 디렉토리를 갈라 두지 않으면 서로의
    /// 앨범을 읽는다(`/tmp` 를 공유하게 된다).
    @MainActor
    private func makeStore() -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trade-memory-\(UUID().uuidString)")
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                           names: [1: ["ko": "포1", "en": "P1", "ja": "ポ1"]])
        return CompanionStore(provider: StubProvider(value: line), clock: { self.now },
                              fileURL: directory.appendingPathComponent("state.json"),
                              rng: SeededRNG(seed: 1))
    }

    private func incomingMon(baseID: Int = 20, firstMetAt: Date? = nil) -> MonState {
        MonState(baseID: baseID, pathIDs: [baseID], plannedPathIDs: [baseID], stageIndex: 0,
                 usedAtStage: 0, rarity: .common, totalForms: 1,
                 names: [baseID: ["ko": "포\(baseID)", "en": "P\(baseID)"]], firstMetAt: firstMetAt)
    }

    private func payload(for monID: UUID, bodies: [String],
                         source: PokemonMemorySource = .event,
                         summary: String? = nil) -> TradeMemoryPayload {
        TradeMemoryPayload(monID: monID, summary: summary,
                           entries: bodies.map { .init(body: $0, source: source, createdAt: now) })
    }

    // MARK: - 와이어

    /// 새 프레임은 왕복해야 하고, **기존 프레임의 모양은 한 바이트도 바뀌면 안 된다** — 구버전은
    /// 모르는 프레임을 건너뛰지만(수신 루프가 다시 걸린다), 아는 프레임의 키가 바뀌면 커밋에서 멎는다.
    func testMemoriesFrameRoundTripsAndExistingFramesKeepTheirWireShape() throws {
        let monID = UUID()
        let sent = payload(for: monID, bodies: ["함께 첫 배틀을 이겼다"], summary: "요약 한 줄")
        let data = try JSONEncoder().encode(TradeWireMessage.memories(sent))
        guard case .memories(let decoded) = try JSONDecoder().decode(TradeWireMessage.self, from: data) else {
            return XCTFail("memories wire case")
        }
        XCTAssertEqual(decoded.monID, monID)
        XCTAssertEqual(decoded.entries.map(\.body), ["함께 첫 배틀을 이겼다"])
        XCTAssertEqual(decoded.entries.map(\.source), [.event])
        XCTAssertEqual(decoded.summary, "요약 한 줄")
        XCTAssertEqual(decoded.entries[0].createdAt.timeIntervalSinceReferenceDate,
                       now.timeIntervalSinceReferenceDate, accuracy: 0.001)

        // `.commit` 의 인자 키는 레이블 없는 `_0` 이다. 여기에 레이블을 붙이는 순간 키가 바뀌고
        // 구버전은 커밋 프레임을 디코드하지 못한다 — 추억을 실으려고 기존 케이스를 건드리면 이게 깨진다.
        let commit = String(decoding: try JSONEncoder().encode(TradeWireMessage.commit(UUID())), as: UTF8.self)
        XCTAssertTrue(commit.contains("\"_0\""), commit)
        XCTAssertEqual(TradeWireMessage.protocolVersion, 2, "추억은 버전이 아니라 프레임 추가로 간다")
    }

    // MARK: - 보내는 쪽이 빼는 것

    /// 나가는 페이로드에 실리는 건 추억 본문과 요약뿐이다. 손글씨 메모·숨긴 기억·**내가 친 문장**은
    /// 나가지 않는다 — 대화 원문이 새면 되돌릴 방법이 없다(LAN 피어는 인증되지 않는다).
    @MainActor
    func testOutgoingPayloadCarriesMemoriesAndSummaryButNeverTheTranscript() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mon = try XCTUnwrap(store.state.active)
        let album = store.memoryAlbum

        album.record(companionID: mon.id, body: "함께 첫 배틀을 이겼다", source: .event, createdAt: now)
        album.record(companionID: mon.id, body: "이름을 지어 줬다", source: .conversation, createdAt: now)
        album.record(companionID: mon.id, body: "숨긴 기억", source: .event, createdAt: now)
        album.addManual(companionID: mon.id, body: "손글씨 메모")
        let hidden = try XCTUnwrap(album.entries(for: mon.id).first { $0.body == "숨긴 기억" })
        XCTAssertTrue(album.setHidden(hidden, isHidden: true))

        store.chatStore.appendLocalMessage("내 사번은 K12345 야", for: mon.id,
                                           profile: store.chatProfile(for: mon))

        let payload = try XCTUnwrap(store.tradeMemoryPayload(for: mon.id))
        XCTAssertEqual(payload.monID, mon.id)
        XCTAssertEqual(payload.entries.map(\.body), ["함께 첫 배틀을 이겼다", "이름을 지어 줬다"])
        XCTAssertNotNil(payload.summary, "대화가 있었으면 관계 요약이 실린다")

        let wire = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        XCTAssertFalse(wire.contains("K12345"), "대화 원문이 페이로드에 새면 안 된다: \(wire)")
        XCTAssertFalse(wire.contains("손글씨"), "손글씨 메모는 트레이너의 글이라 나가지 않는다")
        XCTAssertFalse(wire.contains("숨긴"), "숨긴 기억은 나가지 않는다")
    }

    /// 보낼 게 하나도 없으면 프레임 자체를 안 만든다.
    @MainActor
    func testAnEmptyAlbumProducesNoPayload() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mon = try XCTUnwrap(store.state.active)
        store.memoryAlbum.deleteAll(for: mon.id)
        XCTAssertNil(store.tradeMemoryPayload(for: mon.id))
    }

    // MARK: - 받는 쪽이 안 믿는 것

    /// 페이로드의 개체 ID 는 **바인딩 검사에만** 쓰고, 저장 키는 로컬이 받은 개체 ID 로 다시 짓는다.
    /// 상대가 내 다른 동행의 ID 를 불러도 그 앨범은 한 줄도 안 변해야 한다.
    @MainActor
    func testAdoptedMemoriesGetLocalIdentityAndAPayloadBoundToAnotherMonIsIgnored() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        let bystander = incomingMon(baseID: 30)
        store.debugSetBoxedMons([bystander])
        store.memoryAlbum.record(companionID: bystander.id, body: "박스 동료의 기억",
                                 source: .event, createdAt: now)

        let incoming = incomingMon()
        // 상대가 부르는 `monID` 가 **내 박스 동료**를 가리킨다.
        let hostile = payload(for: bystander.id, bodies: ["남의 앨범에 박히는 줄"])
        XCTAssertTrue(store.performTrade(offeredID: mine.id, received: incoming,
                                         incomingMemories: hostile))
        XCTAssertEqual(store.memoryAlbum.entries(for: bystander.id).map(\.body), ["박스 동료의 기억"],
                       "상대가 지목한 ID 로 남의 앨범이 열리면 안 된다")
        XCTAssertFalse(store.memoryAlbum.entries(for: incoming.id).contains { $0.body == "남의 앨범에 박히는 줄" },
                       "바인딩이 어긋난 페이로드는 받은 개체에도 적용되지 않는다")
    }

    /// 정상 페이로드는 받은 개체의 앨범으로 들어가되, 저장되는 `companionID` 는 로컬 값이다.
    @MainActor
    func testAdoptedMemoriesAreStoredUnderTheReceivedCompanion() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        let incoming = incomingMon()

        XCTAssertTrue(store.performTrade(
            offeredID: mine.id, received: incoming,
            incomingMemories: payload(for: incoming.id, bodies: ["이전 트레이너와 산을 넘었다"],
                                      summary: "오래 함께한 사이였다")))

        let adopted = store.memoryAlbum.entries(for: incoming.id)
        XCTAssertTrue(adopted.contains { $0.body == "이전 트레이너와 산을 넘었다" })
        XCTAssertTrue(adopted.allSatisfy { $0.companionID == incoming.id })
        XCTAssertTrue(adopted.allSatisfy { $0.eventID == nil },
                      "상대가 정한 eventID 는 record() 의 중복 가드를 오염시킨다 — 버려야 한다")
        XCTAssertTrue(adopted.allSatisfy { !$0.isHidden })
        XCTAssertEqual(store.chatStore.session(for: incoming.id)?.summary, "오래 함께한 사이였다")
        XCTAssertEqual(store.chatStore.messages(for: incoming.id), [],
                       "요약만 심는다 — 메시지는 애초에 오지 않는다")
    }

    /// 신뢰경계 클램프. 상대가 부르는 값은 **전부** 다시 잰다.
    func testHostilePayloadFieldsAreClampedAtTheBoundary() {
        let monID = UUID()
        let hostile = TradeMemoryPayload(
            monID: monID,
            summary: String(repeating: "요", count: TradeMemoryPayload.summaryLimit + 1),
            entries:
                (0..<100).map { .init(body: "정상 \($0)", source: .event, createdAt: now) }
                + [.init(body: String(repeating: "가", count: TradeMemoryPayload.bodyLimit + 1),
                         source: .event, createdAt: now),
                   .init(body: "   ", source: .event, createdAt: now),
                   .init(body: "손글씨는 나가지도 들어오지도 않는다", source: .manual, createdAt: now),
                   .init(body: "줄바꿈이\n박힌\u{0007}줄", source: .conversation, createdAt: now),
                   .init(body: "미래에서 온 기억", source: .event,
                         createdAt: now.addingTimeInterval(60 * 60 * 24 * 365)),
                   .init(body: "1970년에서 온 기억", source: .event,
                         createdAt: Date(timeIntervalSince1970: 0))])

        let clean = TradeMemoryPayload.sanitized(hostile, now: now)

        XCTAssertEqual(clean.monID, monID)
        XCTAssertLessThanOrEqual(clean.entries.count, TradeMemoryPayload.maxEntries,
                                 "건수가 열려 있으면 앨범 200칸이 한 번에 밀린다")
        XCTAssertNil(clean.summary, "상한을 넘은 요약은 자르지 않고 버린다")
        XCTAssertFalse(clean.entries.contains { $0.body.count > TradeMemoryPayload.bodyLimit })
        XCTAssertFalse(clean.entries.contains { $0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertFalse(clean.entries.contains { $0.source == .manual })
        XCTAssertFalse(clean.entries.contains { $0.body.contains("\n") || $0.body.contains("\u{0007}") },
                       "줄바꿈·제어문자는 고정 높이 칸을 넘치게 한다")
        XCTAssertFalse(clean.entries.contains { $0.createdAt > now },
                       "미래 날짜는 일기 맨 위에 영원히 박힌다")
        XCTAssertFalse(clean.entries.contains { $0.createdAt < now.addingTimeInterval(-TradeMemoryPayload.maxAge) },
                       "아득한 과거는 친밀도를 즉시 만점으로 만든다")
    }

    /// 상대가 보낸 `firstMetAt` 은 지금도 그대로 앨범에 들어간다(교환 전부터 있던 경로다).
    /// 1970년을 박아 보내면 `daysTogether` 가 2만 일이 되고 친밀도 하트가 즉시 5개가 된다.
    @MainActor
    func testAPeerSuppliedFirstMeetingDateIsClampedIntoTheSameWindow() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        let ancient = incomingMon(firstMetAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(store.performTrade(offeredID: mine.id, received: ancient))
        let floor = now.addingTimeInterval(-TradeMemoryPayload.maxAge)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(store.memoryAlbum.firstMetAt(for: ancient.id)), floor)

        let store2 = makeStore()
        await store2.hatch(baseID: 1)
        let mine2 = try XCTUnwrap(store2.state.active)
        let future = incomingMon(baseID: 21, firstMetAt: now.addingTimeInterval(60 * 60 * 24 * 400))
        XCTAssertTrue(store2.performTrade(offeredID: mine2.id, received: future))
        XCTAssertLessThanOrEqual(try XCTUnwrap(store2.memoryAlbum.firstMetAt(for: future.id)), now,
                                 "미래의 첫 만남은 함께한 날수를 음수로 만든다")
    }

    // MARK: - 적용되는 자리 (두 방향 × 두 자리)

    /// 동행을 내보내는 경로와 **박스 개체를 내보내는 경로**는 `performTrade` 안의 다른 분기다.
    /// 한쪽만 고치면 나머지 한쪽은 무테스트로 남는다.
    @MainActor
    func testBothTheActiveSlotAndTheBoxAdoptIncomingMemories() async throws {
        let activeStore = makeStore()
        await activeStore.hatch(baseID: 1)
        let active = try XCTUnwrap(activeStore.state.active)
        let toActive = incomingMon()
        XCTAssertTrue(activeStore.performTrade(offeredID: active.id, received: toActive,
                                               incomingMemories: payload(for: toActive.id,
                                                                         bodies: ["동행 자리로 들어온 기억"])))
        XCTAssertTrue(activeStore.memoryAlbum.entries(for: toActive.id)
            .contains { $0.body == "동행 자리로 들어온 기억" })

        let boxStore = makeStore()
        await boxStore.hatch(baseID: 1)
        let boxed = incomingMon(baseID: 30)
        boxStore.debugSetBoxedMons([boxed])
        let toBox = incomingMon(baseID: 40)
        XCTAssertTrue(boxStore.performTrade(offeredID: boxed.id, received: toBox,
                                            incomingMemories: payload(for: toBox.id,
                                                                      bodies: ["박스 칸으로 들어온 기억"])))
        XCTAssertTrue(boxStore.memoryAlbum.entries(for: toBox.id)
            .contains { $0.body == "박스 칸으로 들어온 기억" })
    }

    /// 커밋은 두 방향에서 온다 — 신청자는 `.committed` 를, 수신자는 `.commit` 을 받는다.
    /// 한 방향에만 적용을 걸면 다른 쪽 사용자는 빈 앨범을 받는다.
    @MainActor
    func testBothTradeDirectionsAdoptTheIncomingMemories() async throws {
        // 수신자 — `.commit` 을 받고 교환을 수행하는 쪽.
        let responderStore = makeStore()
        await responderStore.hatch(baseID: 1)
        let responderMon = try XCTUnwrap(responderStore.state.active)
        let responder = PokemonTradeCenter(companion: responderStore)
        responder.receive(.request(version: TradeWireMessage.protocolVersion, trainer: "Blue",
                                   chatSupported: true))
        responder.accept()
        let toResponder = incomingMon()
        responder.selectOffer(responderMon)
        responder.receive(.offer(TradePokemonSnapshot(mon: toResponder, displayName: "P20")))
        responder.confirm()
        responder.receive(.confirm(true))
        responder.receive(.memories(payload(for: toResponder.id, bodies: ["수신자가 받은 기억"])))
        responder.receive(.commit(UUID()))
        XCTAssertEqual(responder.phase, .animating)
        XCTAssertTrue(responderStore.memoryAlbum.entries(for: toResponder.id)
            .contains { $0.body == "수신자가 받은 기억" })

        // 신청자 — `.committed` 를 받고 교환을 수행하는 쪽.
        let initiatorStore = makeStore()
        await initiatorStore.hatch(baseID: 1)
        let initiatorMon = try XCTUnwrap(initiatorStore.state.active)
        let initiator = PokemonTradeCenter(companion: initiatorStore)
        initiator.request(TradePeer(name: "Blue", serviceName: "Blue#000000",
                                    endpoint: .hostPort(host: "127.0.0.1", port: 9)))
        initiator.receive(.accept(trainer: "Blue", chatSupported: true))
        let toInitiator = incomingMon(baseID: 21)
        initiator.selectOffer(initiatorMon)
        initiator.receive(.offer(TradePokemonSnapshot(mon: toInitiator, displayName: "P21")))
        initiator.receive(.confirm(true))
        initiator.confirm()
        initiator.receive(.memories(payload(for: toInitiator.id, bodies: ["신청자가 받은 기억"])))
        let transaction = try XCTUnwrap(initiator.activeTransaction)
        initiator.receive(.committed(transaction))
        XCTAssertEqual(initiator.phase, .animating)
        XCTAssertTrue(initiatorStore.memoryAlbum.entries(for: toInitiator.id)
            .contains { $0.body == "신청자가 받은 기억" })
        initiator.closeCompleted()
    }

    // MARK: - 커밋 없이 끝난 세션

    /// 협상 밖에서 온 프레임은 버퍼에도 들어가지 않는다 — 아무 때나 받아 두면 다음 교환에 실린다.
    @MainActor
    func testAMemoriesFrameOutsideANegotiationIsDropped() {
        let center = PokemonTradeCenter(companion: makeStore())
        XCTAssertEqual(center.phase, .ready)
        center.receive(.memories(payload(for: UUID(), bodies: ["아무 때나 밀어 넣는 줄"])))
        XCTAssertNil(center.pendingIncomingMemories)
    }

    /// 취소로 끝난 세션은 버퍼를 비운다. 커밋이 없었으면 앨범에도 아무것도 남지 않는다.
    @MainActor
    func testACancelledNegotiationAdoptsNothing() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let center = PokemonTradeCenter(companion: store)
        center.receive(.request(version: TradeWireMessage.protocolVersion, trainer: "Blue",
                                chatSupported: true))
        center.accept()
        let incoming = incomingMon()
        center.receive(.memories(payload(for: incoming.id, bodies: ["커밋 없이 온 기억"])))
        XCTAssertNotNil(center.pendingIncomingMemories)
        center.cancel()
        XCTAssertNil(center.pendingIncomingMemories)
        XCTAssertTrue(store.memoryAlbum.entries(for: incoming.id).isEmpty)
    }
}
