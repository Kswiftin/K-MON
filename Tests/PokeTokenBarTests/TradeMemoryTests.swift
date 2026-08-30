import Network
import XCTest
@testable import PokeTokenBar

/// 센터가 소켓에 **실제로 밀어 넣은** 프레임을 순서대로 읽는다.
///
/// `send()` 는 연결이 없으면 조용히 리턴한다 — 소켓을 안 붙인 테스트에서는 추억이 언제 무엇이
/// 나가든 아무 단언도 깨지지 않고 커버리지만 초록으로 남는다. 추억 유출은 **전부** 이 경계에서
/// 일어나므로 순서를 보려면 진짜 소켓이 있어야 한다. (`TradeChatTests` 의 루프백과 같은 모양.)
/// 콜백은 **전용 큐**에서 돈다. 메인 큐에 걸면 `async` 테스트에서 영영 안 돈다 — 테스트 본문이
/// `RunLoop.run(until:)` 로 메인 스레드를 잡고 있는 동안 MainActor 작업이 밀리기 때문이다.
/// 탭이 비어 있으면 "아무것도 안 나갔다" 를 보는 단언이 공허하게 통과하므로, 이 격리가 곧
/// 그 단언이 무언가를 지킨다는 근거다. 공유 상태는 잠금 하나로 지킨다.
final class TradeWireTap: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "trade-wire-tap")
    private var storedFrames: [TradeWireMessage] = []
    private var storedPeer: NWConnection?
    private let listener: NWListener

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            connection.start(queue: self.queue)
            self.lock.withLock { self.storedPeer = connection }
            self.readLength(connection)
        }
        listener.start(queue: queue)
    }

    var frames: [TradeWireMessage] { lock.withLock { storedFrames } }
    /// 상대가 붙었다. 이 값을 기다리지 않고 프레임을 밀면 아직 서지 않은 포트로 연결이 나가
    /// 조용히 사라진다.
    var peer: NWConnection? { lock.withLock { storedPeer } }
    /// `.ready` 이전의 `port` 는 아직 `.any`(0) 다 — 실제로 배정된 값만 돌려준다.
    var port: NWEndpoint.Port? { listener.port.flatMap { $0 == .any ? nil : $0 } }

    func cancel() { peer?.cancel(); listener.cancel() }

    func contains(_ predicate: (TradeWireMessage) -> Bool) -> Bool { frames.contains(where: predicate) }
    func firstIndex(_ predicate: (TradeWireMessage) -> Bool) -> Int? { frames.firstIndex(where: predicate) }

    static func isMemories(_ message: TradeWireMessage) -> Bool {
        if case .memories = message { return true }
        return false
    }
    static func isCommitted(_ message: TradeWireMessage) -> Bool {
        if case .committed = message { return true }
        return false
    }
    static func isCommit(_ message: TradeWireMessage) -> Bool {
        if case .commit = message { return true }
        return false
    }
    static func isDecline(_ message: TradeWireMessage) -> Bool {
        if case .decline = message { return true }
        return false
    }

    private func readLength(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, _ in
            guard let self, let data, data.count == 4 else { return }
            let length = Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian)
            self.readBody(length, on: connection)
        }
    }

    private func readBody(_ length: Int, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, _ in
            guard let self, let data, data.count == length else { return }
            if let message = try? JSONDecoder().decode(TradeWireMessage.self, from: data) {
                self.lock.withLock { self.storedFrames.append(message) }
            }
            self.readLength(connection)
        }
    }
}

/// 교환으로 넘어가는 추억. 검증하는 것은 다섯 가지다 — 보내는 쪽이 **무엇을 빼는가**(손글씨 메모·
/// 숨긴 기억·대화에서 파생된 기억), **언제 보내는가**(성사 전에 나가면 되돌릴 방법이 없다),
/// 받는 쪽이 **무엇을 안 믿는가**(개체 ID·날짜·길이·건수·출처), 적용이 **두 방향(신청자/수신자)
/// × 두 자리(동행/박스)** 에서 모두 도는가, 그리고 커밋 없이 끝난 세션엔 아무것도 남지 않는가.
final class TradeMemoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 앨범·대화 파일은 상태 파일 **옆에** 산다. 테스트마다 디렉토리를 갈라 두지 않으면 서로의
    /// 앨범을 읽는다(`/tmp` 를 공유하게 된다). 만든 디렉토리는 반드시 되돌린다 — 형제 파일
    /// (`MemoryHomeVisitProtocolTests`) 이 이미 같은 규약을 쓴다.
    @MainActor
    private func makeStore() -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trade-memory-\(UUID().uuidString)")
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                           names: [1: ["ko": "포1", "en": "P1", "ja": "ポ1"]])
        let store = CompanionStore(provider: StubProvider(value: line), clock: { self.now },
                                   fileURL: directory.appendingPathComponent("state.json"),
                                   rng: SeededRNG(seed: 1))
        // 기억 본문은 저장 시점 언어로 굳는다(부화 기록 등). 호스트 로케일을 그대로 두면 영어
        // 로케일 재실행에서만 깨진다 — 기대값을 언어로 못 박는다.
        store.setLanguage(.ko)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return store
    }

    private func incomingMon(baseID: Int = 20, firstMetAt: Date? = nil) -> MonState {
        MonState(baseID: baseID, pathIDs: [baseID], plannedPathIDs: [baseID], stageIndex: 0,
                 usedAtStage: 0, rarity: .common, totalForms: 1,
                 names: [baseID: ["ko": "포\(baseID)", "en": "P\(baseID)"]], firstMetAt: firstMetAt)
    }

    private func payload(for monID: UUID, bodies: [String],
                         source: PokemonMemorySource = .event) -> TradeMemoryPayload {
        TradeMemoryPayload(monID: monID,
                           entries: bodies.map { .init(body: $0, source: source, createdAt: now) })
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

    @MainActor
    private func makeTap() throws -> TradeWireTap {
        let tap = try TradeWireTap()
        addTeardownBlock { tap.cancel() }
        return tap
    }

    /// 소켓을 붙인다. 붙이지 않으면 `send()` 가 조용히 리턴해 전송 검증이 통째로 무의미해진다.
    /// 신청자 경로에서는 `request(_:)` 가 자기 연결을 먼저 붙이므로 **그 뒤에** 갈아 끼운다 —
    /// `attach` 가 앞 연결을 취소하고 새 것으로 바꾼다.
    @MainActor
    private func connect(_ center: PokemonTradeCenter, to tap: TradeWireTap) throws {
        let port = try XCTUnwrap(pump(until: { tap.port }), "루프백 리스너가 서지 않았다")
        center.attachForTesting(NWConnection(to: .hostPort(host: "127.0.0.1", port: port), using: .tcp))
        // 실제로 붙을 때까지 기다린다. 안 기다리면 아직 안 선 소켓에 프레임이 나가 조용히
        // 사라지고, 전송을 보는 단언이 통째로 무의미해진다(부재 단언은 그대로 통과한다).
        XCTAssertNotNil(pump(until: { tap.peer }), "루프백 연결이 서지 않았다")
    }

    /// 신청자 국면(`.negotiating`, `isInitiator == true`)을 세운다.
    @MainActor
    private func initiatorCenter(_ store: CompanionStore, tap: TradeWireTap? = nil) throws -> PokemonTradeCenter {
        let center = PokemonTradeCenter(companion: store)
        center.request(TradePeer(name: "Blue", serviceName: "Blue#000000",
                                 endpoint: .hostPort(host: "127.0.0.1", port: 9)))
        if let tap { try connect(center, to: tap) }
        center.receive(.accept(trainer: "Blue", chatSupported: true))
        return center
    }

    /// 수신자 국면(`.negotiating`, `isInitiator == false`)을 세운다.
    @MainActor
    private func responderCenter(_ store: CompanionStore, tap: TradeWireTap? = nil) throws -> PokemonTradeCenter {
        let center = PokemonTradeCenter(companion: store)
        center.receive(.request(version: TradeWireMessage.protocolVersion, trainer: "Blue",
                                chatSupported: true))
        if let tap { try connect(center, to: tap) }
        center.accept()
        return center
    }

    // MARK: - 와이어

    /// 새 프레임은 왕복해야 하고, **기존 프레임의 모양은 한 바이트도 바뀌면 안 된다** — 구버전은
    /// 모르는 프레임을 건너뛰지만(수신 루프가 다시 걸린다), 아는 프레임의 키가 바뀌면 커밋에서 멎는다.
    func testMemoriesFrameRoundTripsAndExistingFramesKeepTheirWireShape() throws {
        let monID = UUID()
        let sent = payload(for: monID, bodies: ["함께 첫 배틀을 이겼다"])
        let data = try JSONEncoder().encode(TradeWireMessage.memories(sent))
        guard case .memories(let decoded) = try JSONDecoder().decode(TradeWireMessage.self, from: data) else {
            return XCTFail("memories wire case")
        }
        XCTAssertEqual(decoded.monID, monID)
        XCTAssertEqual(decoded.entries.map(\.body), ["함께 첫 배틀을 이겼다"])
        XCTAssertEqual(decoded.entries.map(\.source), [.event])
        XCTAssertEqual(decoded.entries[0].createdAt.timeIntervalSinceReferenceDate,
                       now.timeIntervalSinceReferenceDate, accuracy: 0.001)

        // `.commit` 의 인자 키는 레이블 없는 `_0` 이다. 여기에 레이블을 붙이는 순간 키가 바뀌고
        // 구버전은 커밋 프레임을 디코드하지 못한다 — 추억을 실으려고 기존 케이스를 건드리면 이게 깨진다.
        let commit = String(decoding: try JSONEncoder().encode(TradeWireMessage.commit(UUID())), as: UTF8.self)
        XCTAssertTrue(commit.contains("\"_0\""), commit)
        XCTAssertEqual(TradeWireMessage.protocolVersion, 2, "추억은 버전이 아니라 프레임 추가로 간다")
    }

    // MARK: - 보내는 쪽이 빼는 것

    /// 나가는 페이로드는 **`.event` 뿐이다.** 그 개체가 겪은 일(부화·배틀·진화)만 나가고,
    /// `.conversation` 은 나가지 않는다 — 그 본문은 모델이 트레이너의 사생활에 **답한 문장**이라
    /// (`PokemonChat` 의 `safeReply` 가 그대로 저장된다) 인증되지 않은 LAN 피어에게 한 번 나가면
    /// 되돌릴 방법이 없다. 손글씨 메모와 숨긴 기억도 빠진다.
    @MainActor
    func testOutgoingPayloadCarriesOnlyEventMemoriesNeverConversationDerivedOnes() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mon = try XCTUnwrap(store.state.active)
        let album = store.memoryAlbum

        album.record(companionID: mon.id, body: "함께 첫 배틀을 이겼다", source: .event, createdAt: now)
        // 대화에서 남은 기억은 트레이너가 말한 것에 **모델이 답한 문장**이다. 사번·병명·주소가
        // 이 경로로 새 나간다 — 아래 부정 단언이 실제로 걸리는 문장이어야 의미가 있다.
        album.record(companionID: mon.id, body: "사번 K12345 얘기를 들어 줬다",
                     source: .conversation, createdAt: now)
        album.record(companionID: mon.id, body: "숨긴 기억", source: .event, createdAt: now)
        album.addManual(companionID: mon.id, body: "손글씨 메모")
        let hidden = try XCTUnwrap(album.entries(for: mon.id).first { $0.body == "숨긴 기억" })
        XCTAssertTrue(album.setHidden(hidden, isHidden: true))

        let payload = try XCTUnwrap(store.tradeMemoryPayload(for: mon.id))
        XCTAssertEqual(payload.monID, mon.id)
        XCTAssertTrue(payload.entries.allSatisfy { $0.source == .event },
                      "`.event` 밖의 출처가 실리면 대화에서 파생된 문장이 함께 나간다")
        XCTAssertTrue(payload.entries.contains { $0.body == "함께 첫 배틀을 이겼다" })
        XCTAssertTrue(payload.entries.contains { $0.body.contains("알에서 태어났다") })

        let wire = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        XCTAssertFalse(wire.contains("K12345"), "대화에서 파생된 문장이 페이로드에 새면 안 된다: \(wire)")
        XCTAssertFalse(wire.contains("손글씨"), "손글씨 메모는 트레이너의 글이라 나가지 않는다")
        XCTAssertFalse(wire.contains("숨긴"), "숨긴 기억은 나가지 않는다")
    }

    /// 대화에서 남은 기억**만** 있는 앨범은 보낼 게 없다 — 프레임 자체를 안 만든다.
    @MainActor
    func testAnAlbumOfOnlyConversationMemoriesProducesNoPayload() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mon = try XCTUnwrap(store.state.active)
        store.memoryAlbum.deleteAll(for: mon.id)
        store.memoryAlbum.record(companionID: mon.id, body: "오늘 있었던 일을 들어 줬다",
                                 source: .conversation, createdAt: now)
        XCTAssertFalse(store.memoryAlbum.entries(for: mon.id).isEmpty, "앨범엔 남아 있어야 한다")
        XCTAssertNil(store.tradeMemoryPayload(for: mon.id))
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

    // MARK: - 언제 보내는가 (진짜 소켓)

    /// **성사되지 않은 교환엔 추억이 나가지 않는다.** 이게 깨지면 상대는 아무것도 내주지 않고
    /// 남의 앨범만 수확할 수 있다: 내 명부(`.roster`)는 수락 직후 건너가므로 상대는 내 개체 ID 를
    /// 그대로 베껴 제안을 만들고 `.commit` 만 보내면 된다. `performTrade` 는 그 제안을 거절하지만,
    /// 추억을 먼저 보내는 판본에서는 앨범이 이미 상대 손에 가 있다.
    @MainActor
    func testAResponderSendsNoMemoriesWhenPerformTradeRejectsTheOffer() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        store.memoryAlbum.record(companionID: mine.id, body: "함께 산을 넘었다", source: .event, createdAt: now)
        XCTAssertNotNil(store.tradeMemoryPayload(for: mine.id),
                        "보낼 추억이 있는 상태여야 이 테스트가 무언가를 지킨다")

        let tap = try makeTap()
        let center = try responderCenter(store, tap: tap)
        center.selectOffer(mine)
        // 상대가 **내 명부에서 베낀** 개체를 제시한다 — `performTrade` 의 거절 조건이다.
        center.receive(.offer(TradePokemonSnapshot(mon: mine, displayName: "내 것을 되판다")))
        center.confirm()
        center.receive(.confirm(true))
        center.receive(.commit(UUID()))

        XCTAssertEqual(center.phase, .failed("교환 정보를 확인할 수 없습니다."))
        _ = pump(until: { tap.contains(TradeWireTap.isDecline) ? true : nil })
        XCTAssertFalse(tap.contains(TradeWireTap.isMemories),
                       "성사되지 않은 교환에 추억이 나가면 되돌릴 방법이 없다: \(tap.frames)")
    }

    /// 성사된 교환에서는 나가되, **`.committed` 보다 앞서** 나가야 한다 — 상대는 커밋 확인 뒤에
    /// 화면을 닫을 수 있고, TCP 순서만이 그 프레임이 도착할 것을 보장한다.
    @MainActor
    func testAResponderSendsItsMemoriesOnlyAfterTheTradeSucceededAndBeforeCommitted() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        store.memoryAlbum.record(companionID: mine.id, body: "함께 산을 넘었다", source: .event, createdAt: now)

        let tap = try makeTap()
        let center = try responderCenter(store, tap: tap)
        center.selectOffer(mine)
        center.receive(.offer(TradePokemonSnapshot(mon: incomingMon(), displayName: "P20")))
        center.confirm()
        center.receive(.confirm(true))
        center.receive(.commit(UUID()))
        XCTAssertEqual(center.phase, .animating)

        _ = pump(until: { tap.contains(TradeWireTap.isCommitted) ? true : nil })
        let memories = try XCTUnwrap(tap.firstIndex(TradeWireTap.isMemories),
                                     "성사된 교환은 추억을 보낸다: \(tap.frames)")
        let committed = try XCTUnwrap(tap.firstIndex(TradeWireTap.isCommitted))
        XCTAssertLessThan(memories, committed, "커밋 확인 뒤에 보내면 상대가 화면을 닫은 뒤일 수 있다")
    }

    /// 신청자도 같다 — `confirm()` 은 `.commit` 만 내보내고, 추억은 상대가 `.committed` 로
    /// **교환이 실제로 일어났음을 알려 준 뒤에** 나간다. `.decline` 로 끝나면 아무것도 안 나간다.
    @MainActor
    func testAnInitiatorHoldsItsMemoriesUntilTheCommitIsConfirmed() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        store.memoryAlbum.record(companionID: mine.id, body: "함께 산을 넘었다", source: .event, createdAt: now)

        let tap = try makeTap()
        let center = try initiatorCenter(store, tap: tap)
        center.selectOffer(mine)
        center.receive(.offer(TradePokemonSnapshot(mon: incomingMon(baseID: 21), displayName: "P21")))
        center.receive(.confirm(true))
        center.confirm()

        let transaction = try XCTUnwrap(center.activeTransaction)
        _ = pump(until: { tap.contains(TradeWireTap.isCommit) ? true : nil })
        XCTAssertTrue(tap.contains(TradeWireTap.isCommit), "커밋 프레임은 나가야 한다: \(tap.frames)")
        XCTAssertFalse(tap.contains(TradeWireTap.isMemories),
                       "커밋이 확인되기 전에는 추억이 나가지 않는다: \(tap.frames)")

        center.receive(.committed(transaction))
        XCTAssertEqual(center.phase, .animating)
        _ = pump(until: { tap.contains(TradeWireTap.isMemories) ? true : nil })
        XCTAssertTrue(tap.contains(TradeWireTap.isMemories),
                      "성사가 확인되면 그때 보낸다: \(tap.frames)")
    }

    /// 신청자가 성사 뒤에 보내므로, **수신자에게는 추억이 `performTrade` 뒤에 도착한다.**
    /// 그 프레임을 버퍼에만 넣고 끝내면 수신자는 영영 빈 앨범을 받는다.
    @MainActor
    func testMemoriesArrivingAfterTheTradeAreStillAdopted() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        let center = try responderCenter(store)
        let theirs = incomingMon()
        center.selectOffer(mine)
        center.receive(.offer(TradePokemonSnapshot(mon: theirs, displayName: "P20")))
        center.confirm()
        center.receive(.confirm(true))
        center.receive(.commit(UUID()))
        XCTAssertEqual(center.phase, .animating)

        center.receive(.memories(payload(for: theirs.id, bodies: ["성사 뒤에 도착한 기억"])))
        XCTAssertTrue(store.memoryAlbum.entries(for: theirs.id).contains { $0.body == "성사 뒤에 도착한 기억" },
                      "성사 뒤에 온 추억이 버려지면 수신자는 빈 앨범을 받는다")
    }

    /// 성사 뒤 경로도 바인딩 검사를 그대로 거친다 — 여기만 열어 두면 상대가 커밋 뒤에 내 다른
    /// 동행 앞으로 프레임을 보내 남의 앨범을 연다.
    @MainActor
    func testMemoriesArrivingAfterTheTradeStillHonourTheMonBinding() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        let bystander = incomingMon(baseID: 30)
        store.debugSetBoxedMons([bystander])
        let center = try responderCenter(store)
        let theirs = incomingMon()
        center.selectOffer(mine)
        center.receive(.offer(TradePokemonSnapshot(mon: theirs, displayName: "P20")))
        center.confirm()
        center.receive(.confirm(true))
        center.receive(.commit(UUID()))

        center.receive(.memories(payload(for: bystander.id, bodies: ["남의 앨범에 박히는 줄"])))
        XCTAssertFalse(store.memoryAlbum.entries(for: bystander.id).contains { $0.body == "남의 앨범에 박히는 줄" },
                       "성사 뒤 경로도 바인딩 검사를 그대로 거쳐야 한다")
    }

    /// 상대가 `.memories` 만 끝없이 밀어도 메인 스레드가 잡히면 안 된다. 형제 프레임은 전부
    /// 상한이 있다 — `.chat` 은 토큰 버킷, `.roster` 는 `prefix(100)`, 이름은 길이 클램프.
    @MainActor
    func testAFloodOfMemoriesFramesIsCapped() throws {
        let center = try responderCenter(makeStore())
        let monID = UUID()
        for index in 0..<(PokemonTradeCenter.maxMemoriesFramesPerSession + 5) {
            center.receive(.memories(payload(for: monID, bodies: ["\(index)번째 밀어 넣기"])))
        }
        let last = try XCTUnwrap(center.pendingIncomingMemories)
        XCTAssertEqual(last.entries.first?.body,
                       "\(PokemonTradeCenter.maxMemoriesFramesPerSession - 1)번째 밀어 넣기",
                       "상한을 넘은 프레임은 버퍼를 갱신하지 못한다")
    }

    // MARK: - 국면 가드 (프레임이 두 번 올 때)

    /// `.confirm(true)` 가 두 번 오면 커밋 트랜잭션이 **재발급되면 안 된다.** 재발급되면 상대가
    /// 앞선 ID 로 보낸 `.committed` 가 거부되고, 상대는 개체를 내줬는데 나는 그대로 들고 있게 된다.
    @MainActor
    func testARepeatedConfirmDoesNotRerollTheCommitTransaction() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        let center = try initiatorCenter(store)
        center.selectOffer(mine)
        center.receive(.offer(TradePokemonSnapshot(mon: incomingMon(baseID: 21), displayName: "P21")))
        center.receive(.confirm(true))
        center.confirm()

        let first = try XCTUnwrap(center.activeTransaction)
        center.receive(.confirm(true))
        XCTAssertEqual(center.activeTransaction, first,
                       "재발급되면 상대의 `.committed(first)` 가 거부돼 한쪽만 교환된다")

        center.receive(.committed(first))
        XCTAssertEqual(center.phase, .animating)
    }

    /// 성사 뒤에 `.commit` 이 한 번 더 오면(재전송·악의적 재생) **완료된 교환이 실패로 뒤집히면
    /// 안 된다.** 확인 플래그는 그대로 남아 있어서 가드가 국면을 안 보면 그대로 재진입한다.
    @MainActor
    func testADuplicateCommitDoesNotFlipACompletedTradeIntoFailure() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        let center = try responderCenter(store)
        let theirs = incomingMon()
        center.selectOffer(mine)
        center.receive(.offer(TradePokemonSnapshot(mon: theirs, displayName: "P20")))
        center.confirm()
        center.receive(.confirm(true))
        center.receive(.commit(UUID()))
        XCTAssertEqual(center.phase, .animating)

        center.receive(.commit(UUID()))
        XCTAssertEqual(center.phase, .animating, "성사된 교환에 실패 화면이 뜨면 안 된다")
        XCTAssertTrue(store.ownedMons.contains { $0.id == theirs.id }, "받은 개체는 그대로 있어야 한다")
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
            incomingMemories: payload(for: incoming.id, bodies: ["이전 트레이너와 산을 넘었다"])))

        let adopted = store.memoryAlbum.entries(for: incoming.id)
        XCTAssertTrue(adopted.contains { $0.body == "이전 트레이너와 산을 넘었다" })
        XCTAssertTrue(adopted.allSatisfy { $0.companionID == incoming.id })
        XCTAssertTrue(adopted.allSatisfy { $0.eventID == nil },
                      "상대가 정한 eventID 는 record() 의 중복 가드를 오염시킨다 — 버려야 한다")
        XCTAssertTrue(adopted.allSatisfy { !$0.isHidden })
        XCTAssertNil(store.chatStore.session(for: incoming.id),
                     "교환은 대화 세션을 만들지 않는다 — 메시지도 요약도 오지 않는다")
    }

    /// 통째로 걸러진 페이로드는 **도착 문구조차** 남기지 않는다. 이 가드가 없으면 상대가 쓰레기
    /// 30줄을 보내도 "이전 트레이너와의 기억을 안고 왔다" 가 앨범에 찍힌다 — 오지 않은 기억의 흔적이다.
    @MainActor
    func testAPayloadThatIsEntirelyRejectedLeavesNoTraceNotEvenTheArrivalNote() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        let incoming = incomingMon()
        let garbage = TradeMemoryPayload(
            monID: incoming.id,
            entries: [.init(body: "  ", source: .event, createdAt: now),
                      .init(body: "손글씨", source: .manual, createdAt: now)])

        XCTAssertTrue(store.performTrade(offeredID: mine.id, received: incoming,
                                         incomingMemories: garbage))
        XCTAssertTrue(store.memoryAlbum.entries(for: incoming.id).isEmpty)
    }

    /// 신뢰경계 클램프. 상대가 부르는 값은 **전부** 다시 잰다.
    ///
    /// 적대적인 줄이 **맨 앞**에 온다. 뒤에 두면 건수 캡(`prefix`)이 필드 검사보다 먼저 걸려
    /// 나머지 클램프를 한 번도 안 밟는다 — 그렇게 쓴 첫 판은 클램프를 전부 지워도 통과했다.
    func testHostilePayloadFieldsAreClampedAtTheBoundary() {
        let monID = UUID()
        let hostile = TradeMemoryPayload(
            monID: monID,
            entries:
                [.init(body: String(repeating: "가", count: TradeMemoryPayload.bodyLimit + 1),
                       source: .event, createdAt: now),
                 .init(body: "   ", source: .event, createdAt: now),
                 .init(body: "손글씨는 나가지도 들어오지도 않는다", source: .manual, createdAt: now),
                 .init(body: "줄바꿈이\n박힌\u{0007}줄", source: .event, createdAt: now),
                 .init(body: "미래에서 온 기억", source: .event,
                       createdAt: now.addingTimeInterval(60 * 60 * 24 * 365)),
                 .init(body: "1970년에서 온 기억", source: .event,
                       createdAt: Date(timeIntervalSince1970: 0))]
                + (0..<100).map { .init(body: "정상 \($0)", source: .event, createdAt: now) })

        let clean = TradeMemoryPayload.sanitized(hostile, now: now)

        // 적대적인 줄이 실제로 검사 구간에 들어왔다는 증거. 이 두 줄이 없으면 위 배열 순서가
        // 뒤집혀도 아무 단언이 안 깨진다.
        XCTAssertTrue(clean.entries.contains { $0.body.hasPrefix("줄바꿈이") }, "접힌 줄이 남아 있어야 한다")
        XCTAssertTrue(clean.entries.contains { $0.body == "미래에서 온 기억" })

        XCTAssertEqual(clean.monID, monID)
        XCTAssertLessThanOrEqual(clean.entries.count, TradeMemoryPayload.maxEntries,
                                 "건수가 열려 있으면 앨범 200칸이 한 번에 밀린다")
        XCTAssertFalse(clean.entries.contains { $0.body.count > TradeMemoryPayload.bodyLimit })
        XCTAssertFalse(clean.entries.contains { $0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertFalse(clean.entries.contains { $0.source == .manual })
        XCTAssertFalse(clean.entries.contains { $0.body.contains("\n") || $0.body.contains("\u{0007}") },
                       "줄바꿈·제어문자는 고정 높이 칸을 넘치게 한다")
        XCTAssertFalse(clean.entries.contains { $0.createdAt > now },
                       "미래 날짜는 일기 맨 위에 영원히 박힌다")
        XCTAssertFalse(clean.entries.contains { $0.createdAt < now.addingTimeInterval(-TradeMemoryPayload.maxAge) },
                       "아득한 과거는 일기의 맨 아래에 박힌다")
    }

    /// 정규화는 **문자(grapheme) 단위**로 돌아야 한다. 스칼라로 훑으면 ZWJ(U+200D)가 제어문자
    /// 범주(Cf)에 들어 있어 이모지 가족이 낱개로 쪼개진다 — 글자 수가 부풀어 정상 본문이 상한 밖으로
    /// 밀려나고, 그 줄은 조용히 버려진다. 보낸 쪽은 같은 교환에서 앨범을 지우므로 **영구 소실**이다.
    func testGraphemeClustersSurviveNormalizationAndWhitespaceRunsAreFolded() {
        let family = "👨‍👩‍👧 우리 가족"
        let clean = TradeMemoryPayload.sanitized(
            TradeMemoryPayload(monID: UUID(), entries: [
                .init(body: family, source: .event, createdAt: now),
                .init(body: "안녕" + String(repeating: " ", count: 170) + "끝", source: .event, createdAt: now),
            ]), now: now)

        XCTAssertEqual(clean.entries.first?.body, family,
                       "ZWJ 가 잘리면 이모지가 낱개로 쪼개지고 글자 수가 부푼다")
        XCTAssertEqual(clean.entries.last?.body, "안녕 끝",
                       "공백 런은 형제 경계(BattleChatPolicy)와 같은 규칙으로 접힌다")
    }

    /// 상대가 부르는 `firstMetAt` 은 **아예 쓰지 않는다.** 창으로 자르기만 하면 상한(3650일)까지
    /// 열려 있는데 친밀도 하트는 120일이면 이미 만점이라 클램프가 아무것도 막지 못한다 — 방금
    /// 받은 개체가 "함께한 3650일 · ♥♥♥♥♥" 로 뜬다. 나와 이 개체가 함께 보낸 날은 0일이다.
    @MainActor
    func testAReceivedCompanionStartsItsSharedHistoryAtZeroDays() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        let ancient = incomingMon(firstMetAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(store.performTrade(offeredID: mine.id, received: ancient))

        let log = store.memoryAlbum.pokeLog(for: ancient.id, now: now)
        XCTAssertEqual(log.daysTogether, 0, "방금 받은 개체와 함께 보낸 날은 0일이다")
        XCTAssertEqual(log.closenessHearts, 1, "상대가 부른 과거로 친밀도가 굳으면 안 된다")
        XCTAssertEqual(store.memoryAlbum.firstMetAt(for: ancient.id), now)

        // 미래 날짜도 같은 규칙 하나로 막힌다 — 함께한 날수가 음수가 될 자리가 없다.
        let store2 = makeStore()
        await store2.hatch(baseID: 1)
        let mine2 = try XCTUnwrap(store2.state.active)
        let future = incomingMon(baseID: 21, firstMetAt: now.addingTimeInterval(60 * 60 * 24 * 400))
        XCTAssertTrue(store2.performTrade(offeredID: mine2.id, received: future))
        XCTAssertEqual(store2.memoryAlbum.firstMetAt(for: future.id), now)
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
        // 수신자 — `.commit` 을 받고 교환을 수행하는 쪽. 신청자는 성사 뒤에 보내므로 추억은
        // `performTrade` 뒤에 도착한다.
        let responderStore = makeStore()
        await responderStore.hatch(baseID: 1)
        let responderMon = try XCTUnwrap(responderStore.state.active)
        let responder = try responderCenter(responderStore)
        let toResponder = incomingMon()
        responder.selectOffer(responderMon)
        responder.receive(.offer(TradePokemonSnapshot(mon: toResponder, displayName: "P20")))
        responder.confirm()
        responder.receive(.confirm(true))
        responder.receive(.commit(UUID()))
        XCTAssertEqual(responder.phase, .animating)
        responder.receive(.memories(payload(for: toResponder.id, bodies: ["수신자가 받은 기억"])))
        XCTAssertTrue(responderStore.memoryAlbum.entries(for: toResponder.id)
            .contains { $0.body == "수신자가 받은 기억" })

        // 신청자 — `.committed` 를 받고 교환을 수행하는 쪽. 상대는 성사 뒤에 보내지만 `.committed`
        // 보다 앞서 보내므로 여기서는 버퍼를 거쳐 들어온다.
        let initiatorStore = makeStore()
        await initiatorStore.hatch(baseID: 1)
        let initiatorMon = try XCTUnwrap(initiatorStore.state.active)
        let initiator = try initiatorCenter(initiatorStore)
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
    }

    /// 보낼 추억이 없어도 **교환은 성립한다.** 프레임을 못 만들면 그냥 안 보낼 뿐이다 —
    /// 여기서 멎으면 앨범을 비운 개체는 영영 교환할 수 없게 된다.
    @MainActor
    func testATradeStillCompletesWhenThereIsNothingToSend() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try XCTUnwrap(store.state.active)
        store.memoryAlbum.deleteAll(for: mine.id)
        XCTAssertNil(store.tradeMemoryPayload(for: mine.id))

        let center = try responderCenter(store)
        let incoming = incomingMon()
        center.selectOffer(mine)
        center.receive(.offer(TradePokemonSnapshot(mon: incoming, displayName: "P20")))
        center.confirm()
        center.receive(.confirm(true))
        center.receive(.commit(UUID()))
        XCTAssertEqual(center.phase, .animating)
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
        let center = try responderCenter(store)
        let incoming = incomingMon()
        center.receive(.memories(payload(for: incoming.id, bodies: ["커밋 없이 온 기억"])))
        XCTAssertNotNil(center.pendingIncomingMemories)
        center.cancel()
        XCTAssertNil(center.pendingIncomingMemories)
        XCTAssertTrue(store.memoryAlbum.entries(for: incoming.id).isEmpty)
    }
}
