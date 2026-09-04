import Foundation
import Testing
@testable import PokeTokenBar

/// 터미널이 부탁한 경매 동작을 **앱이** 실행하는 자리.
///
/// 가짜 창구를 끼우는 이유는 대전·방·교환과 같다 — `PokemonAuctionCenter` 를 그대로 쓰면
/// listener·browser 가 살아나 실제 LAN 으로 나간다.
///
/// 이 파일의 핵심은 **번호가 어느 목록의 것인지** 다. 경매는 번호 공간이 넷이라, 접는 자리가
/// 하나만 어긋나도 사용자가 고른 것과 다른 게시물·다른 제안에 손이 간다.
@MainActor
@Suite("AuctionExecutorTests")
struct AuctionExecutorTests {
    private final class FakeAuctionControl: TerminalAuctionControl {
        var terminalState: AuctionTerminalState
        /// 창구가 돌려줄 사유. `nil` 이면 성공이다.
        var postRefusal: String?
        var applyRefusal: String?
        /// 센터가 수락에 실패했을 때 남기는 한 줄. 실행기가 이 값을 되읽어 답한다.
        var acceptError: String?

        var posted: [Int] = []
        var unposted: [Int] = []
        var applied: [(listing: UUID, mon: Int)] = []
        var bids: [(listing: UUID, stardust: Int)] = []
        var accepted: [UUID] = []
        var rejected: [UUID] = []
        var cancelled: [UUID] = []
        var cleared: [UUID] = []

        init(_ state: AuctionTerminalState) { terminalState = state }

        func post(number: Int) -> String? {
            if let postRefusal { return postRefusal }
            posted.append(number)
            return nil
        }
        func unpost(number: Int) -> String? {
            if let postRefusal { return postRefusal }
            unposted.append(number)
            return nil
        }
        func apply(listingID: UUID, number: Int) -> String? {
            if let applyRefusal { return applyRefusal }
            applied.append((listingID, number))
            return nil
        }
        func bid(listingID: UUID, stardust: Int) -> String? {
            if let applyRefusal { return applyRefusal }
            bids.append((listingID, stardust))
            return nil
        }
        func accept(offerID: UUID) {
            accepted.append(offerID)
            terminalState.lastError = acceptError
        }
        func reject(offerID: UUID) { rejected.append(offerID) }
        func cancelOffer(offerID: UUID) { cancelled.append(offerID) }
        func clearResult(offerID: UUID) { cleared.append(offerID) }
    }

    private func makeDirectory() -> URL { storeFixtureDirectory("auction-exec") }

    /// 언어를 못 박는다 — 새 세이브의 언어는 호스트 로케일을 따르므로, 영어 기계에서만 문구
    /// 검사가 무너진다(#107 부류).
    private func makeStore(in directory: URL) -> CompanionStore {
        let store = CompanionStore(clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                   fileURL: directory.appendingPathComponent("state.json"))
        store.setLanguage(.ko)
        return store
    }

    private func execute(_ action: PokedoroRequest.Action, on store: CompanionStore,
                         auction: FakeAuctionControl?) async -> PokedoroReply {
        let request = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
        return await PokedoroRequestExecutor(timer: FocusTimer(), companion: store,
                                             auction: auction).execute(request)
    }

    // MARK: 게시

    /// 게시·내리기는 **`party` 번호를 그대로** 창구에 넘긴다 — 로스터를 아는 쪽이 창구다.
    @Test func testPostingAndUnpostingPassThePartyNumberThrough() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        let control = FakeAuctionControl(AuctionTerminalTests.busy())

        #expect(await execute(.auctionPost(number: 4), on: store, auction: control).succeeded)
        #expect(control.posted == [4])
        #expect(await execute(.auctionUnpost(number: 3), on: store, auction: control).succeeded)
        #expect(control.unposted == [3])
    }

    /// 창구가 만든 사유는 **그대로 전달된다** — 무엇을 풀어야 하는지 아는 곳이 로스터를 든
    /// 창구이고, 실행기가 뭉개면 "게시할 수 없다" 한 줄만 남는다.
    @Test func testTheSeamsRefusalReachesTheUser() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeAuctionControl(AuctionTerminalTests.busy())
        control.postRefusal = "고디탱은 함께 다니는 중이라 올릴 수 없다."

        let reply = await execute(.auctionPost(number: 3), on: makeStore(in: directory),
                                  auction: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("함께 다니는 중"))
        #expect(control.posted.isEmpty, "거절인데 창구가 게시했다")
    }

    // MARK: 제안 걸기

    /// 시장 번호는 **그 목록에서만** id 로 접힌다.
    @Test func testApplyingFoldsTheMarketNumberToItsListing() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AuctionTerminalTests.busy()
        let second = try #require(state.market.last)
        let control = FakeAuctionControl(state)

        let reply = await execute(.auctionApply(listing: 2, mon: 5),
                                  on: makeStore(in: directory), auction: control)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(control.applied.count == 1)
        #expect(control.applied.first?.listing == second.id, "시장 번호가 엉뚱한 게시물로 접혔다")
        #expect(control.applied.first?.mon == 5, "개체 번호는 창구가 접는다")
    }

    /// 목록 밖 시장 번호는 **거절이고 첫 게시물로 접지 않는다.**
    @Test func testAMarketNumberOutsideTheListIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeAuctionControl(AuctionTerminalTests.busy())

        let reply = await execute(.auctionApply(listing: 9, mon: 1),
                                  on: makeStore(in: directory), auction: control)

        #expect(!reply.succeeded)
        #expect(control.applied.isEmpty, "거절이 창구를 불렀다")
        #expect(reply.message.contains("2"), "몇 건이 올라 있는지 말해야 다음 번호를 고른다")
    }

    /// 정원이 찼으면 **걸기 전에** 거절한다 — 센터도 막지만, 조용히 아무 일도 안 하면
    /// 사용자는 제안이 나간 줄 안다.
    @Test func testApplyingNeedsRoomInTheOfferSlots() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        var full = AuctionTerminalTests.busy()
        full.canOffer = false
        let control = FakeAuctionControl(full)

        for action: PokedoroRequest.Action in [.auctionApply(listing: 1, mon: 1),
                                               .auctionBid(listing: 1, stardust: 10)] {
            let reply = await execute(action, on: store, auction: control)
            #expect(!reply.succeeded, "\(action.name) 이 정원을 넘겼다")
            #expect(reply.message.contains("\(PokemonAuctionCenter.maxOutgoingOffers)"),
                    "정원이 몇인지 말해야 무엇을 치울지 안다")
        }
        #expect(control.applied.isEmpty && control.bids.isEmpty)
    }

    /// 별의모래 제안은 **약속하지 않은 잔액**을 넘지 못한다. 잔액만 보면 지킬 수 없는 제안을
    /// 여러 건 걸게 되므로, 화면과 실행기가 센터와 **같은 값**(`unpledgedTokens`)을 본다.
    @Test func testABidBeyondTheUnpledgedBalanceIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeAuctionControl(AuctionTerminalTests.busy())

        let reply = await execute(.auctionBid(listing: 1, stardust: 5_000),
                                  on: makeStore(in: directory), auction: control)

        #expect(!reply.succeeded)
        #expect(control.bids.isEmpty)
        // 자릿수 구분 기호는 로케일이 정한다 — 표를 지나 비교한다(#107 부류).
        #expect(reply.message.contains(TUIRender.number(1_200)),
                "얼마를 걸 수 있는지 말해야 값을 고칠 수 있다")
    }

    @Test func testABidWithinTheBalanceReachesTheSeam() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AuctionTerminalTests.busy()
        let first = try #require(state.market.first)
        let control = FakeAuctionControl(state)

        #expect(await execute(.auctionBid(listing: 1, stardust: 1_200),
                              on: makeStore(in: directory), auction: control).succeeded)
        #expect(control.bids.first?.listing == first.id)
        #expect(control.bids.first?.stardust == 1_200)
    }

    // MARK: 받은 제안에 답하기

    @Test func testAcceptingFoldsTheOfferNumberToItsOffer() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AuctionTerminalTests.busy()
        let offer = try #require(state.incoming.first)
        let control = FakeAuctionControl(state)

        #expect(await execute(.auctionAccept(number: 1), on: makeStore(in: directory),
                              auction: control).succeeded)
        #expect(control.accepted == [offer.id])
    }

    /// 센터가 수락을 거절하면 **그 한 줄을 되읽어 답한다** — 성공으로 답하면 사용자는 개체가
    /// 넘어간 줄 알고 다음 일을 한다.
    @Test func testTheCentresAcceptFailureIsReportedAsARefusal() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FakeAuctionControl(AuctionTerminalTests.busy())
        control.acceptError = "게시한 포켓몬을 확인할 수 없습니다."

        let reply = await execute(.auctionAccept(number: 1), on: makeStore(in: directory),
                                  auction: control)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("확인할 수 없"))
    }

    /// 이미 답한 제안은 거절이다 — 국면을 안 보면 커밋 중인 제안을 두 번 수락하게 된다.
    @Test func testOnlyPendingOffersCanBeAnswered() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        var settled = AuctionTerminalTests.busy()
        settled.incoming = [AuctionScreen.Card(number: 1, id: UUID(), label: "옆자리",
                                               status: .accepted)]
        let control = FakeAuctionControl(settled)

        for action: PokedoroRequest.Action in [.auctionAccept(number: 1),
                                               .auctionReject(number: 1)] {
            let reply = await execute(action, on: store, auction: control)
            #expect(!reply.succeeded, "\(action.name) 이 이미 답한 제안을 다시 건드렸다")
        }
        #expect(control.accepted.isEmpty && control.rejected.isEmpty)
    }

    @Test func testRejectingAPendingOfferReachesTheCentre() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AuctionTerminalTests.busy()
        let offer = try #require(state.incoming.first)
        let control = FakeAuctionControl(state)

        #expect(await execute(.auctionReject(number: 1), on: makeStore(in: directory),
                              auction: control).succeeded)
        #expect(control.rejected == [offer.id])
    }

    // MARK: 내가 건 제안 치우기

    /// **거둬들이기는 대기 중인 것만, 치우기는 끝난 것만.** 커밋이 시작된 제안을 치우면
    /// 에스크로만 돌아오고 개체는 아무에게도 가지 않는다(센터 주석의 근거 그대로다).
    @Test func testCancelTakesPendingOffersAndClearTakesFinishedOnes() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let pending = AuctionTerminalTests.busy()
        let live = try #require(pending.outgoing.first)
        let onPending = FakeAuctionControl(pending)
        #expect(await execute(.auctionCancel(number: 1), on: store, auction: onPending).succeeded)
        #expect(onPending.cancelled == [live.id])
        // 대기 중인 제안은 치울 것이 아니다 — 아직 결과가 없다.
        let clearPending = await execute(.auctionClear(number: 1), on: store, auction: onPending)
        #expect(!clearPending.succeeded)
        #expect(onPending.cleared.isEmpty)

        var finished = AuctionTerminalTests.busy()
        finished.outgoing = [AuctionScreen.Card(number: 1, id: UUID(), label: "피카츄",
                                                status: .declined)]
        let done = try #require(finished.outgoing.first)
        let onFinished = FakeAuctionControl(finished)
        #expect(await execute(.auctionClear(number: 1), on: store, auction: onFinished).succeeded)
        #expect(onFinished.cleared == [done.id])
        let cancelFinished = await execute(.auctionCancel(number: 1), on: store,
                                           auction: onFinished)
        #expect(!cancelFinished.succeeded)
        #expect(onFinished.cancelled.isEmpty)

        // 커밋 중(`.accepted`)은 **둘 다** 안 된다.
        var committing = AuctionTerminalTests.busy()
        committing.outgoing = [AuctionScreen.Card(number: 1, id: UUID(), label: "피카츄",
                                                  status: .accepted)]
        let onCommitting = FakeAuctionControl(committing)
        for action: PokedoroRequest.Action in [.auctionCancel(number: 1),
                                               .auctionClear(number: 1)] {
            let reply = await execute(action, on: store, auction: onCommitting)
            #expect(!reply.succeeded, "\(action.name) 이 커밋 중인 제안을 건드렸다")
        }
        #expect(onCommitting.cancelled.isEmpty && onCommitting.cleared.isEmpty)
    }

    /// 창구가 없으면 **경매가 없는 것과 같다.**
    @Test func testWithoutAControlEverythingReadsAsNoAuction() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        for action: PokedoroRequest.Action in [.auctionPost(number: 1), .auctionUnpost(number: 1),
                                               .auctionApply(listing: 1, mon: 1),
                                               .auctionBid(listing: 1, stardust: 10),
                                               .auctionAccept(number: 1),
                                               .auctionReject(number: 1),
                                               .auctionCancel(number: 1),
                                               .auctionClear(number: 1)] {
            let reply = await execute(action, on: store, auction: nil)
            #expect(!reply.succeeded)
            #expect(reply.message.contains("경매"), "\(action.name) 의 사유가 다르다")
        }
    }
}
