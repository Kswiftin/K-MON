import Foundation
import Network
import Testing
@testable import PokeTokenBar

struct AuctionSeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct AuctionStubProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        id == value.baseID ? BaseSpecies(id: id, captureRate: 255) : nil
    }
}

/// 경매의 소유권 이전. 검증하는 것은 네 가지다 — 커밋이 **어느 순서로** 일어나는가(신청자가 먼저
/// 넘기면 게시자 쪽 실패가 곧 개체 유실이다), 같은 게시물이 **두 번 잠기지 않는가**, 목록에서 본
/// 개체와 **다른 개체**가 오면 멈추는가, 그리고 추억이 함께 건너가는가.
///
/// 전부 `#199` 가 `PokemonTrade` 의 커밋 프로토콜을 재사용하지 않고 새로 짜면서 잃은 안전장치다.
@MainActor
@Suite struct AuctionCommitTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("auction-commit-\(UUID().uuidString)")
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                           names: [1: ["ko": "포1", "en": "P1", "ja": "ポ1"]])
        let store = CompanionStore(provider: AuctionStubProvider(value: line), clock: { Self.now },
                                   fileURL: directory.appendingPathComponent("state.json"),
                                   rng: AuctionSeededRNG(seed: 1))
        store.setLanguage(AppLanguage.ko)
        return store
    }

    /// 소켓을 붙이지 않은 연결. 프레임은 아무 데도 가지 않지만 `receive` 가 요구하는 연결 등록은
    /// 실제와 같은 경로로 이뤄진다 — 국면 가드를 보는 테스트에는 그것으로 충분하다.
    private func attachedConnection(_ center: PokemonAuctionCenter) -> UUID {
        center.attachForTesting(NWConnection(to: .hostPort(host: "127.0.0.1", port: 9), using: .tcp))
    }

    private func remoteMon(baseID: Int = 20, level: Int = 5) -> MonState {
        var mon = MonState(baseID: baseID, pathIDs: [baseID], plannedPathIDs: [baseID], stageIndex: 0,
                           usedAtStage: 0, rarity: .common, totalForms: 1,
                           names: [baseID: ["ko": "포\(baseID)", "en": "P\(baseID)"]], firstMetAt: nil)
        // 레벨은 경험치에서 파생된다 — 광고값 대조 테스트가 종뿐 아니라 레벨도 봐야 해서 채운다.
        mon.levelExperience = (level - 1) * PokemonBalance.experiencePerLevel
        return mon
    }

    private func snapshot(_ mon: MonState) -> TradePokemonSnapshot {
        TradePokemonSnapshot(mon: mon, displayName: "P\(mon.currentID)")
    }

    private func listing(for mon: MonState, id: UUID = UUID()) -> AuctionListing {
        AuctionListing(id: id, trainerName: "Blue", serviceName: "Blue#000000",
                       endpoint: .hostPort(host: "127.0.0.1", port: 9), speciesID: mon.currentID,
                       displayName: "P\(mon.currentID)", level: mon.level, isShiny: mon.isShiny)
    }

    /// 게시자 국면을 세운다: 한 마리를 올리고 제안 하나를 받는다.
    private func listingCenter(_ store: CompanionStore, offering offered: MonState)
        async -> (center: PokemonAuctionCenter, listed: MonState, connection: UUID, offerID: UUID) {
        await store.hatch(baseID: 1)
        let listed = store.state.active!
        let center = PokemonAuctionCenter(companion: store)
        center.publish(listed)
        let listingID = center.localListings.keys.first!
        let connection = attachedConnection(center)
        let offerID = UUID()
        center.receive(.apply(version: AuctionWireMessage.protocolVersion, offerID: offerID,
                              listingID: listingID, trainer: "Red",
                              value: .pokemon(snapshot(offered))), connectionID: connection)
        return (center, listed, connection, offerID)
    }

    /// **신청자는 게시자의 이전이 끝났다는 프레임을 받고서야 자기 개체를 넘긴다.**
    ///
    /// 옛 순서(수락 프레임을 받자마자 넘김)에서는 게시자 쪽 커밋이 실패하면 신청자 개체가 그대로
    /// 사라졌다. 되돌리는 경로가 없어서 복구도 불가능했다.
    @Test func applicantKeepsItsPokemonUntilTheListerHasCommitted() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let theirs = remoteMon()
        let center = PokemonAuctionCenter(companion: store)
        let connection = try #require(center.apply(to: listing(for: theirs), offering: mine))
        let offerID = try #require(center.outgoingOffers.first?.id)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)
        #expect(center.outgoingOffers.first?.status == .accepted)
        #expect(store.ownedMons.contains { $0.id == mine.id },
                "수락 프레임만으로 개체를 넘기면 게시자 쪽 실패가 곧 유실이다")
        #expect(!store.ownedMons.contains { $0.id == theirs.id }, "아직 받은 것도 없어야 한다")

        // 게시자 쪽 커밋이 실패했다. 아무것도 움직이지 않았어야 한다.
        center.receive(.failed(offerID: offerID), connectionID: connection)
        #expect(center.outgoingOffers.first?.status == .failed)
        #expect(store.ownedMons.contains { $0.id == mine.id })
        #expect(!store.ownedMons.contains { $0.id == theirs.id })
    }

    /// 게시자가 커밋을 마쳤다는 프레임이 와야 교환이 끝난다.
    @Test func applicantCommitsOnceTheListerReportsCompletion() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let theirs = remoteMon()
        let center = PokemonAuctionCenter(companion: store)
        let connection = try #require(center.apply(to: listing(for: theirs), offering: mine))
        let offerID = try #require(center.outgoingOffers.first?.id)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)
        center.receive(.completed(offerID: offerID, memories: nil), connectionID: connection)

        #expect(center.outgoingOffers.first?.status == .completed)
        #expect(!store.ownedMons.contains { $0.id == mine.id })
        #expect(store.ownedMons.contains { $0.id == theirs.id })
    }

    /// 게시물은 하나뿐이라 **잠금도 하나뿐이다.** 두 번째 수락을 받아 주면 같은 개체가 두
    /// 트레이너에게 커밋된다.
    @Test func aSecondOfferCannotBeAcceptedWhileOneIsLocked() async throws {
        let store = makeStore()
        let first = remoteMon(baseID: 20), second = remoteMon(baseID: 21)
        let setup = await listingCenter(store, offering: first)
        let center = setup.center
        let secondConnection = attachedConnection(center)
        let secondOffer = UUID()
        center.receive(.apply(version: AuctionWireMessage.protocolVersion, offerID: secondOffer,
                              listingID: center.localListings.keys.first!, trainer: "Green",
                              value: .pokemon(snapshot(second))), connectionID: secondConnection)
        #expect(center.offers.count == 2)

        center.accept(setup.offerID)
        center.accept(secondOffer)

        #expect(center.offers.first { $0.id == setup.offerID }?.status == .accepted)
        #expect(center.offers.first { $0.id == secondOffer }?.status != .accepted,
                "두 제안이 동시에 잠기면 같은 개체가 두 번 커밋된다")
        #expect(center.lastError != nil)
    }

    /// 한 연결은 제안 하나만 나른다. 덮어쓰게 두면 앞 제안의 거절·수락 프레임이 상대에게 못 간다.
    @Test func oneConnectionCarriesOnlyOneOffer() async throws {
        let store = makeStore()
        let setup = await listingCenter(store, offering: remoteMon(baseID: 20))
        let center = setup.center

        center.receive(.apply(version: AuctionWireMessage.protocolVersion, offerID: UUID(),
                              listingID: center.localListings.keys.first!, trainer: "Green",
                              value: .pokemon(snapshot(remoteMon(baseID: 21)))), connectionID: setup.connection)

        #expect(center.offers.count == 1)
        #expect(center.offers.first?.id == setup.offerID)
    }

    /// 목록에 뜬 종·레벨과 다른 개체가 오면 멈춘다. 그대로 받으면 화면은 성사되고 상자에만 다른
    /// 포켓몬이 앉는다.
    @Test func aPokemonThatDoesNotMatchTheListingAbortsTheTrade() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let advertised = remoteMon(baseID: 20, level: 5)
        let swapped = remoteMon(baseID: 21, level: 60)
        let center = PokemonAuctionCenter(companion: store)
        let connection = try #require(center.apply(to: listing(for: advertised), offering: mine))
        let offerID = try #require(center.outgoingOffers.first?.id)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(swapped)), connectionID: connection)

        #expect(center.outgoingOffers.first?.status == .failed)
        #expect(center.outgoingOffers.first?.error != nil)
        #expect(store.ownedMons.contains { $0.id == mine.id })
        #expect(!store.ownedMons.contains { $0.id == swapped.id })
    }

    /// 게시를 내리는 것은 **내 게시물**을 내리는 것이다. 남에게 건 제안의 연결까지 끊으면
    /// 진행 중인 내 교환이 이유 없이 멎는다.
    ///
    /// 게시와 제안은 **서로 다른 개체**로 세운다 — 같은 개체를 둘 다에 걸면 양쪽이 수락됐을 때
    /// 두 번 커밋되므로 이제 센터가 막는다(`aListedPokemonCannotAlsoBackAnOffer`).
    @Test func cancellingMyListingLeavesMyOwnOfferAlone() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let listed = try #require(store.state.active)
        let offered = remoteMon(baseID: 30)
        #expect(store.receiveAuctionPokemon(offered))
        let theirs = remoteMon()
        let center = PokemonAuctionCenter(companion: store)
        center.publish(listed)
        let connection = try #require(center.apply(to: listing(for: theirs), offering: offered))
        let offerID = try #require(center.outgoingOffers.first?.id)

        center.cancelListing(center.localListings.keys.first!)
        #expect(center.localListings.isEmpty)
        #expect(center.outgoingOffers.first?.status == .pending)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)
        #expect(center.outgoingOffers.first?.status == .accepted, "게시 취소가 내 제안의 연결을 끊었다")
    }

    /// 대기 중인 제안은 신청자가 **직접** 거둬들인다 — 커밋이 시작된 뒤에는 거둬들이지 않는다.
    /// 자동 시간 제한은 없다(#227): 상대가 앱을 닫으면 연결 실패가 이미 정리하고(`drop`), 둘 다
    /// 켜져 있는데 게시자가 늦게 답하는 정상적인 경우까지 시간으로 끊으면 안 된다.
    @Test func aPendingOfferCanBeCancelledButACommittingOneCannot() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let theirs = remoteMon()
        let center = PokemonAuctionCenter(companion: store)
        let connection = try #require(center.apply(to: listing(for: theirs), offering: mine))
        let offerID = try #require(center.outgoingOffers.first?.id)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)
        center.cancelOutgoingOffer(offerID)
        #expect(center.outgoingOffers.first?.status == .accepted,
                "커밋 중인 제안을 취소로 끊으면 안 된다")

        let other = PokemonAuctionCenter(companion: store)
        _ = other.apply(to: listing(for: theirs), offering: mine)
        let pending = try #require(other.outgoingOffers.first)
        #expect(pending.status == .pending)
        other.cancelOutgoingOffer(pending.id)
        #expect(other.outgoingOffers.isEmpty, "거둬들인 제안은 실패가 아니라 목록에서 사라진다")
    }

    /// 추억은 교환과 함께 건너간다. 경매만 `incomingMemories` 없이 `performTrade` 를 불러
    /// 양쪽 앨범이 사라졌다.
    @Test func memoriesTravelWithTheAuctionTrade() async throws {
        let store = makeStore()
        let offered = remoteMon(baseID: 20)
        let setup = await listingCenter(store, offering: offered)
        let center = setup.center
        center.accept(setup.offerID)

        let payload = TradeMemoryPayload(monID: offered.id,
                                         entries: [.init(body: "함께 첫 배틀을 이겼다", source: .event,
                                                         createdAt: Self.now)])
        center.receive(.commit(offerID: setup.offerID, memories: payload), connectionID: setup.connection)

        #expect(center.offers.first?.status == .completed)
        #expect(store.ownedMons.contains { $0.id == offered.id })
        #expect(!store.ownedMons.contains { $0.id == setup.listed.id })
        #expect(store.memoryAlbum.entries(for: offered.id).contains { $0.body == "함께 첫 배틀을 이겼다" },
                "경매로 받은 개체의 앨범이 비면 추억이 교환 경로에서 사라진 것이다")
    }

    @Test func multiplePokemonCanBeListedAtTheSameTime() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let first = try #require(store.state.active)
        let second = remoteMon(baseID: 20)
        #expect(store.receiveAuctionPokemon(second))
        let center = PokemonAuctionCenter(companion: store)

        center.publish(first)
        center.publish(second)

        #expect(center.localListings.count == 2)
        #expect(Set(center.localListings.values.map { $0.mon.id }) == Set([first.id, second.id]))
    }

    @Test func acceptedStardustOfferPaysSellerAndTransfersListedPokemon() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let listed = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        center.publish(listed)
        let listingID = try #require(center.localListings.keys.first)
        let connection = attachedConnection(center)
        let offerID = UUID()
        center.receive(.apply(version: AuctionWireMessage.protocolVersion, offerID: offerID,
                              listingID: listingID, trainer: "Red", value: .stardust(12_345)),
                       connectionID: connection)

        center.accept(offerID)
        center.receive(.commit(offerID: offerID, memories: nil), connectionID: connection)

        #expect(store.availableTokens == 12_345)
        #expect(!store.ownedMons.contains { $0.id == listed.id })
        #expect(center.localListings[listingID] == nil)
        #expect(center.offers.first?.status == .completed)
    }

    // MARK: 제안 여러 건 동시 등록

    /// 제안 하나의 국면. 예전 스칼라 `outgoingStatus` 를 대신한다 — 국면이 제안별로 서므로
    /// 어느 게시물의 제안인지로 찾는다.
    private func offer(_ center: PokemonAuctionCenter, on listingID: UUID) -> OutgoingAuctionOffer? {
        center.outgoingOffers.first { $0.listing.id == listingID }
    }

    /// 제안은 **여러 건 동시에** 걸 수 있다. 국면이 스칼라 하나였을 때는 두 번째 제안이 아예
    /// 서지 않아, 답 없는 제안 하나가 제한 시간(90초) 동안 다른 기회를 전부 막았다.
    @Test func severalOffersCanBePendingAtTheSameTime() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let alsoMine = remoteMon(baseID: 30)
        #expect(store.receiveAuctionPokemon(alsoMine))
        let center = PokemonAuctionCenter(companion: store)
        let first = listing(for: remoteMon(baseID: 20))
        let second = listing(for: remoteMon(baseID: 21))

        let firstConnection = try #require(center.apply(to: first, offering: mine))
        let secondConnection = try #require(center.apply(to: second, offering: alsoMine))

        #expect(firstConnection != secondConnection, "제안마다 연결이 따로여야 프레임이 섞이지 않는다")
        #expect(center.outgoingOffers.count == 2)
        #expect(center.outgoingOffers.allSatisfy { $0.status == .pending })
    }

    /// 같은 개체가 두 제안을 받치면 **둘 다 수락됐을 때 같은 포켓몬이 두 번 커밋된다** —
    /// 하나는 실패로 끝나지만 그 실패가 어느 쪽인지는 순서 나름이다.
    @Test func theSamePokemonCannotBackTwoOffers() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)

        #expect(center.apply(to: listing(for: remoteMon(baseID: 20)), offering: mine) != nil)

        #expect(center.apply(to: listing(for: remoteMon(baseID: 21)), offering: mine) == nil,
                "같은 개체가 두 제안을 받치면 한쪽은 유실이다")
        #expect(center.outgoingOffers.count == 1)
    }

    /// 게시 중인 개체는 제안에도 걸 수 없다. 게시와 제안이 둘 다 수락되면 같은 개체가 두 번
    /// 커밋된다 — 제안이 하나뿐이던 때부터 있던 구멍인데, 제안이 여러 건 서면 훨씬 쉽게 밟힌다.
    @Test func aListedPokemonCannotAlsoBackAnOffer() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let center = PokemonAuctionCenter(companion: store)
        center.publish(mine)

        #expect(center.apply(to: listing(for: remoteMon(baseID: 20)), offering: mine) == nil)
        #expect(center.outgoingOffers.isEmpty)
    }

    /// 한 제안의 실패가 다른 제안을 건드리지 않는다. 국면이 스칼라였을 때는 나중 제안이 앞
    /// 제안의 상태·타임아웃·에스크로를 통째로 덮었다.
    @Test func oneOfferFailingLeavesTheOthersPending() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let alsoMine = remoteMon(baseID: 30)
        #expect(store.receiveAuctionPokemon(alsoMine))
        let center = PokemonAuctionCenter(companion: store)
        let first = listing(for: remoteMon(baseID: 20))
        let second = listing(for: remoteMon(baseID: 21))
        let firstConnection = try #require(center.apply(to: first, offering: mine))
        _ = try #require(center.apply(to: second, offering: alsoMine))
        let failing = try #require(offer(center, on: first.id))

        center.receive(.failed(offerID: failing.id), connectionID: firstConnection)

        #expect(offer(center, on: first.id)?.status == .failed)
        #expect(offer(center, on: second.id)?.status == .pending,
                "스칼라 국면일 때는 한 제안의 실패가 다른 제안을 통째로 덮었다")
    }

    /// 미결 제안의 **합**이 지갑을 넘으면 다음 제안이 서지 않는다. 에스크로는 수락 시점에
    /// 걷히므로 등록만 보면 지킬 수 없는 제안을 여러 건 걸 수 있다.
    @Test func pendingStardustOffersCannotExceedTheWallet() async throws {
        let store = makeStore()
        store.creditStarPieces(100)
        let center = PokemonAuctionCenter(companion: store)

        #expect(center.apply(to: listing(for: remoteMon(baseID: 20)), offeringStardust: 70) != nil)
        #expect(center.apply(to: listing(for: remoteMon(baseID: 21)), offeringStardust: 70) == nil,
                "미결 제안의 합이 지갑을 넘으면 지킬 수 없는 제안이다")
        #expect(center.apply(to: listing(for: remoteMon(baseID: 22)), offeringStardust: 30) != nil)
        #expect(center.outgoingOffers.count == 2)
    }

    /// **커밋이 시작된 제안은 치울 수 없다.** 에스크로는 수락 시점에 걷히고 게시자는 그 다음
    /// 프레임에서 자기 개체를 넘긴다 — 그 사이에 "확인" 이 눌리면 별의모래만 돌아오고 개체는
    /// 아무에게도 가지 않는다(화폐 복제).
    @Test func clearingAnOfferMidCommitCannotRefundTheEscrow() throws {
        let store = makeStore()
        store.creditStarPieces(100)
        let theirs = remoteMon()
        let center = PokemonAuctionCenter(companion: store)
        let connection = try #require(center.apply(to: listing(for: theirs), offeringStardust: 100))
        let offerID = try #require(center.outgoingOffers.first?.id)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)
        #expect(center.outgoingOffers.first?.status == .accepted)
        #expect(store.availableTokens == 0, "에스크로는 수락 시점에 걷힌다")

        center.clearOutgoingResult(offerID)

        #expect(store.availableTokens == 0, "커밋 중에 치우면 별의모래가 복제된다")
        #expect(center.outgoingOffers.first?.status == .accepted)
    }

    /// 같은 `.accepted` 가 두 번 오는 것은 **되돌릴 이유가 아니다.** 실패로 끌어내리면 게시자는
    /// 이미 넘긴 뒤라 에스크로만 돌아오고 개체는 사라진다.
    @Test func aRepeatedAcceptedFrameLeavesTheCommitAlone() throws {
        let store = makeStore()
        store.creditStarPieces(100)
        let theirs = remoteMon()
        let center = PokemonAuctionCenter(companion: store)
        let connection = try #require(center.apply(to: listing(for: theirs), offeringStardust: 100))
        let offerID = try #require(center.outgoingOffers.first?.id)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)
        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)

        #expect(center.outgoingOffers.first?.status == .accepted, "같은 프레임이 커밋을 되돌렸다")
        #expect(store.availableTokens == 0, "되돌리면 에스크로만 돌아온다")
    }

    /// 정원은 **살아 있는 제안만** 센다. 끝난 제안까지 세면 치우지 않은 결과 카드 여덟 장이
    /// 시장을 통째로 잠근다 — 버튼은 회색인데 이유는 어디에도 안 적힌다.
    @Test func theOfferCapCountsOnlyLiveOffers() throws {
        let store = makeStore()
        // 지갑은 정원보다 한 칸 넉넉하게 — 막히는 이유가 잔액이 아니라 정원이어야 한다.
        store.creditStarPieces(PokemonAuctionCenter.maxOutgoingOffers + 1)
        let center = PokemonAuctionCenter(companion: store)
        for index in 0..<PokemonAuctionCenter.maxOutgoingOffers {
            #expect(center.apply(to: listing(for: remoteMon(baseID: 20 + index)),
                                 offeringStardust: 1) != nil)
        }
        #expect(center.apply(to: listing(for: remoteMon(baseID: 19)), offeringStardust: 1) == nil,
                "정원이 찼다")

        let declined = try #require(center.outgoingOffers.first)
        center.receive(.declined(offerID: declined.id), connectionID: declined.connectionID)

        #expect(center.apply(to: listing(for: remoteMon(baseID: 19)), offeringStardust: 1) != nil,
                "거절당해 끝난 제안이 자리를 계속 먹었다")
    }

    /// 전역 실패 한 줄(`lastError`)은 지워지는 자리가 있어야 한다. 없으면 한 번의 수락 실패가
    /// 세션 내내 화면 아래 빨간 줄로 남는다.
    @Test func aNewOfferClearsTheStaleBanner() throws {
        let store = makeStore()
        store.creditStarPieces(10)
        let center = PokemonAuctionCenter(companion: store)
        center.accept(UUID())
        #expect(center.lastError != nil)

        #expect(center.apply(to: listing(for: remoteMon()), offeringStardust: 1) != nil)
        #expect(center.lastError == nil, "새 제안이 앞선 실패의 자국을 지우지 않았다")
    }

    /// 상한을 넘는 별의모래 제안은 게시자의 `isValid` 가 **무조건** 거절한다. 보내는 쪽에서 자르지
    /// 않으면 왕복 한 번이 통째로 거절로 버려진다 — `creditStarPieces` 는 상한을 걸지 않으므로
    /// 지갑이 상한을 넘은 세이브에서 실제로 밟힌다.
    @Test func anOverCapStardustOfferIsClampedBeforeItLeaves() throws {
        let store = makeStore()
        store.creditStarPieces(SaveTransfer.maxTokenValue + 5)
        let center = PokemonAuctionCenter(companion: store)

        #expect(center.apply(to: listing(for: remoteMon()),
                             offeringStardust: SaveTransfer.maxTokenValue + 5) != nil)
        #expect(center.outgoingOffers.first?.stardust == SaveTransfer.maxTokenValue,
                "상한을 넘겨 보내면 게시자가 받자마자 거절한다")
    }
}
