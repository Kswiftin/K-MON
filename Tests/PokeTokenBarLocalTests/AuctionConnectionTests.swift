import Foundation
import Network
import Testing
@testable import PokeTokenBar

/// 센터가 소켓에 **실제로 밀어 넣은** 프레임을 읽고, 필요하면 상대 역할로 연결을 접는다.
///
/// 왜 진짜 소켓이어야 하나: 검증할 두 가지가 둘 다 소켓 안에서만 일어난다. ① 종료 프레임이
/// 정말 나갔는가 — `send` 는 연결이 없으면 조용히 리턴하므로, 소켓을 안 붙이면 무엇이 나가든
/// 아무 단언도 깨지지 않는다. ② 상대가 앱을 정상 종료하면 TCP 는 FIN 만 남기므로
/// `data == nil` 을 받는 읽기 콜백만 그것을 안다.
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

    /// 온전한 프레임 하나를 보낸다 — 센터의 읽기 루프가 실제로 디코드해 `receive` 로 넘기는지
    /// 보는 유일한 경로다. 기존 테스트는 `receive` 를 직접 불러 이 루프를 건너뛴다.
    func sendFrame(_ message: AuctionWireMessage) {
        guard let peer, let payload = try? JSONEncoder().encode(message) else { return }
        var frame = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        frame.append(payload)
        peer.send(content: frame, completion: .contentProcessed { _ in })
    }

    /// 길이는 온전하지만 **본문이 우리 프로토콜이 아닌** 프레임. 구버전 앱의 `.apply` 가 이 모양이다 —
    /// 디코드가 안 되면 `receive` 를 안 거치므로 회수 판정도 그 갈래에서만 따로 돌아야 한다.
    func sendUndecodableFrame() {
        guard let peer else { return }
        let payload = Data("{\"nope\":1}".utf8)
        var frame = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        frame.append(payload)
        peer.send(content: frame, completion: .contentProcessed { _ in })
    }

    /// 길이 헤더만 보내고 본문 없이 죽는다 — 프레임 **중간에** 끊긴 상대. `length` 를 0 이나
    /// 상한 밖으로 주면 길이 값 자체가 반려되는 갈래를 밟는다.
    func sendLengthThenClose(_ length: UInt32) {
        guard let peer else { return }
        let header = withUnsafeBytes(of: length.bigEndian) { Data($0) }
        peer.send(content: header, contentContext: .finalMessage, isComplete: true,
                  completion: .contentProcessed { _ in peer.cancel() })
    }

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
    private func makeStore() -> CompanionStore { AuctionFixtures.makeStore("auction-connection") }
    private func remoteMon(baseID: Int = 20, level: Int = 5) -> MonState {
        AuctionFixtures.remoteMon(baseID: baseID, level: level)
    }
    private func snapshot(_ mon: MonState) -> TradePokemonSnapshot { AuctionFixtures.snapshot(mon) }

    /// 게시물 하나. `port` 를 주면 그 포트로 **실제 연결이 나간다**(`apply` 가 소켓을 연다).
    private func listing(for mon: MonState, port: NWEndpoint.Port = 9) -> AuctionListing {
        AuctionListing(id: UUID(), trainerName: "Blue", serviceName: "Blue#000000",
                       endpoint: .hostPort(host: "127.0.0.1", port: port), speciesID: mon.currentID,
                       displayName: "P\(mon.currentID)", level: mon.level, isShiny: mon.isShiny)
    }

    /// `probe` 가 참이 될 때까지 기다린다. 센터의 `NWConnection` 콜백은 `.main` 에서 도는데
    /// `Task.sleep` 은 메인을 놓아 주므로 그 사이에 실행된다.
    private func poll(timeout: Duration = .seconds(5), _ probe: () -> Bool) async -> Bool {
        (await pollValue(timeout: timeout) { probe() ? true : nil }) ?? false
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
        let connection = AuctionFixtures.attachedConnection(center)
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
        let connection = AuctionFixtures.attachedConnection(center)

        // 버전이 갈린 상대. 센터는 `.declined` 로 답하고 제안을 세우지 않는다.
        center.receive(.apply(version: AuctionWireMessage.protocolVersion - 1, offerID: UUID(),
                              listingID: listingID, trainer: "Red",
                              value: .pokemon(snapshot(remoteMon()))), connectionID: connection)

        #expect(center.offers.isEmpty)
        #expect(await poll { center.trackedConnectionCount == 0 },
                "제안이 안 선 연결은 아무 정원에도 안 세어져 무제한으로 쌓인다")
    }

    // MARK: - 소켓 (기전 자체)

    /// 거둬들인 제안은 **종료 프레임을 상대에게 남기고** 연결을 놓는다. 그 프레임이 안 가면
    /// 게시자 카드는 `.pending` 에 남고, `#227` 이 자동 시간 제한을 없앴으므로 영구히 남는다.
    ///
    /// **이 테스트가 지키지 못하는 것**: 접기가 큐를 흘리는지 여부는 여기서 갈리지 않는다.
    /// `closeWhenFlushed` 를 즉시 `cancel()` 로 되돌려도 두 프레임이 다 도착해 초록으로 남았다
    /// (재주입 3회 확인). 루프백은 어느 쪽으로도 전달하므로, 순서 보장은 리뷰와
    /// `NWConnection` 계약이 근거이고 이 단언의 근거는 아니다. 단언하는 것은 그 위의 동작
    /// 하나뿐이다 — 종료 프레임이 상대에게 닿고, 연결이 회수된다.
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
        // 동기점은 `.apply` **도착**이다. `tap.peer`(TCP 수락)로 당기면 우리 쪽 `.ready` 보다
        // 앞설 수 있고, 그러면 `.apply` 는 아직 보내지지도 않은 채 연결이 접혀 테스트가
        // 간헐적으로 빨간불이 된다(실제로 그랬다). 소켓이 실제로 섰다는 근거이기도 하다 —
        // 안 기다리면 아래 단언이 "아직 안 붙어서" 통과한다.
        #expect(await poll { tap.contains(AuctionWireTap.isApply) }, "제안 프레임이 나가지 않았다")

        center.cancelOutgoingOffer(offerID)

        #expect(await poll { tap.contains(AuctionWireTap.isFailed) },
                "접기가 종료 프레임을 버렸다 — 게시자 카드가 영구히 pending 에 남는다")
        #expect(await poll { center.trackedConnectionCount == 0 })
        // 장부가 비는 것만 재면 **소켓이 안 닫혀도 초록이다** — 회수가 아니라 누수 은폐다.
        // 상대가 EOF 를 받았다는 것이 `cancel()` 이 실제로 걸렸다는 유일한 증거다.
        #expect(await poll { tap.sawEOF }, "장부에서만 빠지고 소켓은 살아 있다")
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

    /// **읽기 루프 전체를 소켓으로 밟는 유일한 테스트.** 다른 스무 개는 `receive` 를 직접 불러
    /// 길이 프리픽스 읽기·디코드·전달을 통째로 건너뛰므로, 그 루프의 가드를 고쳐도(이 변경이
    /// 그랬다) 아무도 해피 패스가 깨진 것을 모른다 — `--show-regions` 에 실행 `0` 으로 남는다.
    @Test func aFrameArrivingOverTheSocketReachesTheOffer() async throws {
        let tap = try AuctionWireTap()
        defer { tap.cancel() }
        let port = try #require(await pollValue { tap.port })
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        _ = try #require(center.apply(to: listing(for: remoteMon(), port: port), offering: mine))
        let offerID = try #require(center.outgoingOffers.first?.id)
        #expect(await poll { tap.contains(AuctionWireTap.isApply) }, "제안 프레임이 나가지 않았다")

        tap.sendFrame(.declined(offerID: offerID))

        #expect(await poll { center.outgoingOffers.first?.status == .declined },
                "소켓으로 온 프레임이 제안에 닿지 않았다")
        #expect(await poll { center.trackedConnectionCount == 0 })
    }

    /// 프레임 **중간에** 끊긴 상대. `receiveLength` 는 성공하고 `receiveBody` 가 짧은 읽기를
    /// 받는다 — 여기서 조용히 리턴하면 죽은 소켓 위에서 제안이 영영 `.pending` 이다.
    ///
    /// 이 테스트가 있는 이유는 커버리지다. 앞의 EOF 테스트는 `receiveLength` 만 밟고
    /// `receiveBody` 의 실패 분기는 `--show-regions` 에서 실행 `0` 으로 남았다 — 총계
    /// 89%는 그것을 가린다.
    @Test func aFrameCutInHalfReleasesMyConnection() async throws {
        let tap = try AuctionWireTap()
        defer { tap.cancel() }
        let port = try #require(await pollValue { tap.port })
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        _ = try #require(center.apply(to: listing(for: remoteMon(), port: port), offering: mine))
        #expect(await poll { tap.contains(AuctionWireTap.isApply) }, "제안 프레임이 나가지 않았다")

        // 본문 8바이트가 온다고 알리고 아무것도 안 보낸 채 끊는다.
        tap.sendLengthThenClose(8)

        #expect(await poll { center.trackedConnectionCount == 0 },
                "본문을 기다리다 끊긴 소켓이 죽은 채로 남는다")
        #expect(center.outgoingOffers.first?.status == .failed)
    }

    /// 길이 값 자체가 규격 밖인 상대(0 바이트 프레임). 신뢰경계라 값을 믿지 않고 끊는다.
    @Test func aFrameWithAnImpossibleLengthReleasesMyConnection() async throws {
        let tap = try AuctionWireTap()
        defer { tap.cancel() }
        let port = try #require(await pollValue { tap.port })
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        _ = try #require(center.apply(to: listing(for: remoteMon(), port: port), offering: mine))
        #expect(await poll { tap.contains(AuctionWireTap.isApply) }, "제안 프레임이 나가지 않았다")

        tap.sendLengthThenClose(0)

        #expect(await poll { center.trackedConnectionCount == 0 })
        #expect(center.outgoingOffers.first?.status == .failed)
    }

    /// 못 읽는 프레임은 **건너뛰되 살아 있는 제안의 연결은 놓지 않는다.** 뒤 버전이 더한 선택적
    /// 프레임이 이 모양이라(형제 `PokemonTrade` 가 같은 이유로 루프를 다시 건다), 여기서 접으면
    /// 진행 중인 교환이 모르는 프레임 하나에 끊긴다. 뒤이은 `.declined` 가 닿는 것이 곧 연결이
    /// 살아 있고 루프가 다시 걸렸다는 증거다.
    @Test func anUndecodableFrameKeepsALiveOffersConnection() async throws {
        let tap = try AuctionWireTap()
        defer { tap.cancel() }
        let port = try #require(await pollValue { tap.port })
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        _ = try #require(center.apply(to: listing(for: remoteMon(), port: port), offering: mine))
        let offerID = try #require(center.outgoingOffers.first?.id)
        #expect(await poll { tap.contains(AuctionWireTap.isApply) }, "제안 프레임이 나가지 않았다")

        tap.sendUndecodableFrame()
        tap.sendFrame(.declined(offerID: offerID))

        #expect(await poll { center.outgoingOffers.first?.status == .declined },
                "못 읽는 프레임이 살아 있는 제안의 연결을 끊었다")
    }

    /// 게시를 내리면 **잠긴(`.accepted`) 제안의 연결까지** 놓는다. `cancelListing` 은 그 제안을
    /// `offers` 에서 지우기만 하므로, 회수를 여기서 한 번 더 보지 않으면 그 연결은 어느 판정에도
    /// 걸리지 않는다 — 신청자는 자동 시간 제한이 없어(#227) 영구히 "교환 처리 중" 이고 에스크로한
    /// 별의모래도 안 돌아온다. 접으면 상대 읽기 루프가 EOF 로 그것을 안다.
    @Test func removingAListingReleasesTheConnectionOfALockedOffer() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let listed = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        center.publish(listed)
        let listingID = try #require(center.localListings.keys.first)
        let connection = AuctionFixtures.attachedConnection(center)
        let offerID = UUID()
        center.receive(.apply(version: AuctionWireMessage.protocolVersion, offerID: offerID,
                              listingID: listingID, trainer: "Red",
                              value: .pokemon(snapshot(remoteMon()))), connectionID: connection)
        center.accept(offerID)
        #expect(center.offers.first?.status == .accepted)
        #expect(center.trackedConnectionCount == 1, "커밋 중인 연결은 살아 있어야 한다")

        center.cancelListing(listingID)

        #expect(center.offers.isEmpty)
        #expect(await poll { center.trackedConnectionCount == 0 },
                "제안이 사라진 연결을 아무도 회수하지 않는다")
    }

    /// 프레임을 한 번도 안 보내는 수신 연결은 **회수 판정이 아예 안 돈다** — `reclaimIfIdle` 은
    /// 프레임을 읽은 뒤에만 걸리고, `#227` 이 자동 시간 제한을 걷어내 시간이 끊어 줄 것도 없다.
    /// 남은 방어는 정원 하나뿐이라, 그 문이 없으면 같은 LAN 의 피어 하나가(포트 스캐너로도 된다)
    /// 무제한으로 소켓을 쌓는다.
    ///
    /// **폴링 없이 세는 것이 근거다.** `acceptConnection` 의 등록은 `@MainActor` 동기 구간이고
    /// `drop` 은 `Task { @MainActor }` 로 들어오므로 이 루프 중간에 끼어들 수 없다 — 붙는 포트가
    /// 닫혀 있어도(9) 세는 값이 흔들리지 않는다.
    @Test func acceptingStopsPastTheConnectionBudget() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let center = PokemonAuctionCenter(companion: store)
        let budget = PokemonAuctionCenter.maxConnections
        var opened: [NWConnection] = []
        defer { opened.forEach { $0.cancel() } }

        for _ in 0..<(budget + 4) {
            let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 9), using: .tcp)
            opened.append(connection)
            center.acceptConnection(connection)
        }

        #expect(center.trackedConnectionCount == budget,
                "정원을 넘겨 붙은 연결이 장부에 올라간다 — 아무것도 안 보내면 회수 판정도 안 돈다")
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
