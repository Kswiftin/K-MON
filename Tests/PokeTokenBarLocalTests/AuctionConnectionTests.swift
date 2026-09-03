import Foundation
import Network
import Testing
@testable import PokeTokenBar

/// 센터가 소켓에 **실제로 밀어 넣은** 프레임을 읽고, 필요하면 상대 역할로 연결을 접는다.
///
/// 왜 진짜 소켓이어야 하나: 검증할 두 가지가 둘 다 소켓 안에서만 일어난다. ① 종료 프레임이
/// 정말 나갔는가 — `send` 직후 `cancel()` 은 그 프레임을 **버린다**(측정: 8바이트 중 0바이트
/// 도착). 소켓을 안 붙이면 무엇이 나가든 아무 단언도 깨지지 않는다. ② 상대가 앱을 정상 종료하면
/// TCP 는 FIN 만 남기므로 `data == nil` 을 받는 읽기 콜백만 그것을 안다.
///
/// 콜백은 **전용 큐**에서 돈다. 메인 큐에 걸면 센터의 `NWConnection` 콜백(`.main`)과 같은 줄에
/// 서서 테스트가 폴링하는 동안 밀린다. 탭이 비어 있으면 "무엇이 나갔다" 를 보는 단언이 공허하게
/// 통과하므로, 이 격리가 곧 그 단언이 무언가를 지킨다는 근거다.
/// (형제 `TradeWireTap` 과 같은 모양이다.)
final class AuctionWireTap: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "auction-wire-tap")
    private var storedFrames: [AuctionWireMessage] = []
    private var storedPeer: NWConnection?
    private var storedEOF = false
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

    var frames: [AuctionWireMessage] { lock.withLock { storedFrames } }
    /// 상대가 붙었다. 이 값을 기다리지 않고 단언하면 아직 서지 않은 소켓을 재게 된다.
    var peer: NWConnection? { lock.withLock { storedPeer } }
    /// 센터가 자기 쪽을 접었다 — 우리가 EOF 를 받았다.
    var sawEOF: Bool { lock.withLock { storedEOF } }
    /// `.ready` 이전의 `port` 는 아직 `.any`(0) 다 — 실제로 배정된 값만 돌려준다.
    var port: NWEndpoint.Port? { listener.port.flatMap { $0 == .any ? nil : $0 } }

    func cancel() { peer?.cancel(); listener.cancel() }
    /// 상대가 앱을 **정상 종료**한다. `.failed` 가 아니라 FIN 만 건너간다.
    func closePeer() { peer?.cancel() }

    func contains(_ predicate: (AuctionWireMessage) -> Bool) -> Bool {
        frames.contains(where: predicate)
    }

    static func isApply(_ message: AuctionWireMessage) -> Bool {
        if case .apply = message { return true }
        return false
    }
    static func isFailed(_ message: AuctionWireMessage) -> Bool {
        if case .failed = message { return true }
        return false
    }

    private func readLength(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            guard let data, data.count == 4 else {
                if isComplete { self.lock.withLock { self.storedEOF = true } }
                return
            }
            let length = Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian)
            self.readBody(length, on: connection)
        }
    }

    private func readBody(_ length: Int, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            guard let data, data.count == length else {
                if isComplete { self.lock.withLock { self.storedEOF = true } }
                return
            }
            if let message = try? JSONDecoder().decode(AuctionWireMessage.self, from: data) {
                self.lock.withLock { self.storedFrames.append(message) }
            }
            self.readLength(connection)
        }
    }
}

/// 끝난 제안의 **연결 회수**(#228). 검증하는 것은 네 가지다 — 신청자 쪽 종료 국면 세 갈래가
/// 연결을 놓는가, 게시자 쪽 두 갈래(거절·`.apply` 반려)가 놓는가, 접기 전에 종료 프레임이
/// **정말 나가는가**(안 나가면 상대 카드가 `#227` 이후 영구히 `.pending` 이다), 그리고 상대가
/// 앱을 정상 종료했을 때 내 쪽이 그것을 아는가(FIN 은 `.failed` 로 오지 않는다).
@MainActor
@Suite struct AuctionConnectionTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("auction-connection-\(UUID().uuidString)")
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                           names: [1: ["ko": "포1", "en": "P1", "ja": "ポ1"]])
        let store = CompanionStore(provider: AuctionStubProvider(value: line), clock: { Self.now },
                                   fileURL: directory.appendingPathComponent("state.json"),
                                   rng: AuctionSeededRNG(seed: 1))
        store.setLanguage(AppLanguage.ko)
        return store
    }

    private func remoteMon(baseID: Int = 20, level: Int = 5) -> MonState {
        var mon = MonState(baseID: baseID, pathIDs: [baseID], plannedPathIDs: [baseID], stageIndex: 0,
                           usedAtStage: 0, rarity: .common, totalForms: 1,
                           names: [baseID: ["ko": "포\(baseID)", "en": "P\(baseID)"]], firstMetAt: nil)
        mon.levelExperience = (level - 1) * PokemonBalance.experiencePerLevel
        return mon
    }

    private func snapshot(_ mon: MonState) -> TradePokemonSnapshot {
        TradePokemonSnapshot(mon: mon, displayName: "P\(mon.currentID)")
    }

    /// 게시물 하나. `port` 를 주면 그 포트로 **실제 연결이 나간다**(`apply` 가 소켓을 연다).
    private func listing(for mon: MonState, port: NWEndpoint.Port = 9) -> AuctionListing {
        AuctionListing(id: UUID(), trainerName: "Blue", serviceName: "Blue#000000",
                       endpoint: .hostPort(host: "127.0.0.1", port: port), speciesID: mon.currentID,
                       displayName: "P\(mon.currentID)", level: mon.level, isShiny: mon.isShiny)
    }

    /// `probe` 가 참이 될 때까지 기다린다. 센터의 `NWConnection` 콜백은 `.main` 에서 도는데
    /// `Task.sleep` 은 메인을 놓아 주므로 그 사이에 실행된다.
    private func poll(timeout: Duration = .seconds(5), _ probe: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if probe() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return probe()
    }

    // MARK: - 신청자 쪽 (내가 건 제안)

    /// 거절당한 제안은 연결을 놓는다. 놓지 않으면 결과 카드를 안 치운 사용자당 소켓이 그대로
    /// 쌓인다 — `maxOutgoingOffers` 가 8로 묶어 주지만 그건 상한이지 회수가 아니다.
    @Test func aDeclinedOfferReleasesItsConnection() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        let connection = try #require(center.apply(to: listing(for: remoteMon()), offering: mine))
        let offerID = try #require(center.outgoingOffers.first?.id)
        #expect(center.trackedConnectionCount == 1)

        center.receive(.declined(offerID: offerID), connectionID: connection)

        #expect(center.outgoingOffers.first?.status == .declined)
        #expect(await poll { center.trackedConnectionCount == 0 },
                "끝난 제안의 연결이 앱이 끝날 때까지 남는다")
        #expect(center.outgoingOffers.count == 1, "연결을 놓아도 결과 카드는 남아야 한다")
    }

    /// 상대가 실패를 알려온 제안도 같다. `#228` 이 이 갈래를 빠뜨렸다 — 종료 국면이 넷인데
    /// 셋만 적어 두면 나머지 하나가 그대로 샌다.
    @Test func aFailedOfferReleasesItsConnection() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        let connection = try #require(center.apply(to: listing(for: remoteMon()), offering: mine))
        let offerID = try #require(center.outgoingOffers.first?.id)

        center.receive(.failed(offerID: offerID), connectionID: connection)

        #expect(center.outgoingOffers.first?.status == .failed)
        #expect(await poll { center.trackedConnectionCount == 0 })
    }

    /// 성사된 제안도 연결을 놓는다. 교환이 끝난 소켓은 더 나를 것이 없다.
    @Test func aCompletedOfferReleasesItsConnection() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let theirs = remoteMon()
        let center = PokemonAuctionCenter(companion: store)
        let connection = try #require(center.apply(to: listing(for: theirs), offering: mine))
        let offerID = try #require(center.outgoingOffers.first?.id)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)
        #expect(center.trackedConnectionCount == 1, "커밋 중인 연결은 살아 있어야 한다")
        center.receive(.completed(offerID: offerID, memories: nil), connectionID: connection)

        #expect(center.outgoingOffers.first?.status == .completed)
        #expect(await poll { center.trackedConnectionCount == 0 })
    }

    // MARK: - 게시자 쪽 (#228 이 통째로 안 본 절반)

    /// 거절한 제안의 연결도 놓는다. 게시자 쪽은 **정원이 없어** 신청자 쪽 8개 상한이 여기엔
    /// 아무 도움이 안 된다.
    @Test func aRejectedOfferReleasesTheListersConnection() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let listed = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        center.publish(listed)
        let listingID = try #require(center.localListings.keys.first)
        let connection = center.attachForTesting(NWConnection(to: .hostPort(host: "127.0.0.1", port: 9),
                                                              using: .tcp))
        let offerID = UUID()
        center.receive(.apply(version: AuctionWireMessage.protocolVersion, offerID: offerID,
                              listingID: listingID, trainer: "Red",
                              value: .pokemon(snapshot(remoteMon()))), connectionID: connection)
        #expect(center.trackedConnectionCount == 1)

        center.reject(offerID)

        #expect(center.offers.first?.status == .declined)
        #expect(await poll { center.trackedConnectionCount == 0 })
    }

    /// 반려된 `.apply` 는 제안조차 서지 않는다 — 그래서 어느 정원에도 안 세어지고, 회수하지
    /// 않으면 **무제한으로** 쌓인다. 구버전 앱 하나가 재시도하면 그대로 소켓이 늘어난다.
    @Test func aRejectedApplyReleasesTheListersConnection() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let listed = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        center.publish(listed)
        let listingID = try #require(center.localListings.keys.first)
        let connection = center.attachForTesting(NWConnection(to: .hostPort(host: "127.0.0.1", port: 9),
                                                              using: .tcp))

        // 버전이 갈린 상대. 센터는 `.declined` 로 답하고 제안을 세우지 않는다.
        center.receive(.apply(version: AuctionWireMessage.protocolVersion - 1, offerID: UUID(),
                              listingID: listingID, trainer: "Red",
                              value: .pokemon(snapshot(remoteMon()))), connectionID: connection)

        #expect(center.offers.isEmpty)
        #expect(await poll { center.trackedConnectionCount == 0 },
                "제안이 안 선 연결은 아무 정원에도 안 세어져 무제한으로 쌓인다")
    }

    // MARK: - 소켓 (기전 자체)

    /// **접기 전에 종료 프레임이 정말 나가야 한다.**
    ///
    /// `send` 직후 `cancel()` 하면 그 프레임은 버려진다(측정: 8바이트 중 0바이트 도착).
    /// `cancelOutgoingOffer` 가 정확히 그 모양이었다 — `#227` 이 90초 자동 타임아웃을 없앴으므로
    /// 게시자 화면의 카드는 90초가 아니라 **영구히** `.pending` 에 남는다. 회수가 누수 수정이
    /// 아니라 오늘 보이는 결함 수정인 지점이다.
    @Test func cancellingAnOfferDeliversTheFailedFrameBeforeClosing() async throws {
        let tap = try AuctionWireTap()
        defer { tap.cancel() }
        let port = try #require(await pollValue { tap.port })
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        _ = try #require(center.apply(to: listing(for: remoteMon(), port: port), offering: mine))
        let offerID = try #require(center.outgoingOffers.first?.id)
        // 소켓이 실제로 섰다는 근거. 안 기다리면 아래 단언이 "아직 안 붙어서" 통과한다.
        #expect(await poll { tap.contains(AuctionWireTap.isApply) }, "제안 프레임이 나가지 않았다")

        center.cancelOutgoingOffer(offerID)

        #expect(await poll { tap.contains(AuctionWireTap.isFailed) },
                "접기가 종료 프레임을 버렸다 — 게시자 카드가 영구히 pending 에 남는다")
        #expect(await poll { center.trackedConnectionCount == 0 })
        #expect(center.outgoingOffers.isEmpty, "거둬들인 제안은 결과 카드를 남기지 않는다")
    }

    /// 상대가 앱을 **정상 종료**하면 TCP 는 FIN 만 남기고 상태는 `.ready` 에 머문다 —
    /// `stateUpdateHandler` 의 `.failed`/`.cancelled` 는 영영 뜨지 않는다. `data == nil` 을 받는
    /// 읽기 콜백만 그것을 안다. 형제 넷(`PokemonTrade`·`BattleNet`·`MultiplayerRoomCenter`·
    /// `MemoryHomeVisitCenter`)은 전부 그렇게 끝내는데 경매만 조용히 리턴했다.
    ///
    /// **이 테스트는 우리 쪽에서 아무것도 보내면 안 된다.** 닫힌 소켓에 쓰면 RST 가 돌아오고
    /// 그건 `.failed` 라, 결함을 되주입해도 상태 핸들러가 회수해 초록이 된다(defect-log 가 그
    /// 함정을 명시한다).
    @Test func aPeerClosingItsAppReleasesMyConnection() async throws {
        let tap = try AuctionWireTap()
        defer { tap.cancel() }
        let port = try #require(await pollValue { tap.port })
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        _ = try #require(center.apply(to: listing(for: remoteMon(), port: port), offering: mine))
        #expect(await poll { tap.contains(AuctionWireTap.isApply) }, "제안 프레임이 나가지 않았다")
        #expect(center.trackedConnectionCount == 1)

        tap.closePeer()

        #expect(await poll { center.trackedConnectionCount == 0 },
                "정상 종료한 상대의 소켓이 죽은 채로 남는다")
        #expect(center.outgoingOffers.first?.status == .failed,
                "연결이 끊겼으면 그 제안은 실패다 — 안 그러면 개체가 계속 묶인다")
    }

    private func pollValue<T>(timeout: Duration = .seconds(5), _ probe: () -> T?) async -> T? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if let value = probe() { return value }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return probe()
    }
}
