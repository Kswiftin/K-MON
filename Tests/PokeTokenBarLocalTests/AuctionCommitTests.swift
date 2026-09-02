import Foundation
import Network
import Testing
@testable import PokeTokenBar

private struct AuctionSeededRNG: RandomNumberGenerator {
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

private struct AuctionStubProvider: PokeProviding {
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
        let connection = attachedConnection(center)
        let offerID = UUID()
        center.receive(.apply(version: AuctionWireMessage.protocolVersion, offerID: offerID,
                              listingID: center.localListingID!, trainer: "Red",
                              pokemon: snapshot(offered)), connectionID: connection)
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
        let offerID = try #require(center.outgoingOfferID)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)
        #expect(center.outgoingStatus == .accepted)
        #expect(store.ownedMons.contains { $0.id == mine.id },
                "수락 프레임만으로 개체를 넘기면 게시자 쪽 실패가 곧 유실이다")
        #expect(!store.ownedMons.contains { $0.id == theirs.id }, "아직 받은 것도 없어야 한다")

        // 게시자 쪽 커밋이 실패했다. 아무것도 움직이지 않았어야 한다.
        center.receive(.failed(offerID: offerID), connectionID: connection)
        #expect(center.outgoingStatus == .failed)
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
        let offerID = try #require(center.outgoingOfferID)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)
        center.receive(.completed(offerID: offerID, memories: nil), connectionID: connection)

        #expect(center.outgoingStatus == .completed)
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
                              listingID: center.localListingID!, trainer: "Green",
                              pokemon: snapshot(second)), connectionID: secondConnection)
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
                              listingID: center.localListingID!, trainer: "Green",
                              pokemon: snapshot(remoteMon(baseID: 21))), connectionID: setup.connection)

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
        let offerID = try #require(center.outgoingOfferID)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(swapped)), connectionID: connection)

        #expect(center.outgoingStatus == .failed)
        #expect(center.lastError != nil)
        #expect(store.ownedMons.contains { $0.id == mine.id })
        #expect(!store.ownedMons.contains { $0.id == swapped.id })
    }

    /// 게시를 내리는 것은 **내 게시물**을 내리는 것이다. 남에게 건 제안의 연결까지 끊으면
    /// 진행 중인 내 교환이 이유 없이 멎는다.
    @Test func cancellingMyListingLeavesMyOwnOfferAlone() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let theirs = remoteMon()
        let center = PokemonAuctionCenter(companion: store)
        center.publish(mine)
        let connection = try #require(center.apply(to: listing(for: theirs), offering: mine))
        let offerID = try #require(center.outgoingOfferID)

        center.cancelListing()
        #expect(center.localListing == nil)
        #expect(center.outgoingStatus == .pending)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)
        #expect(center.outgoingStatus == .accepted, "게시 취소가 내 제안의 연결을 끊었다")
    }

    /// 답 없는 제안은 시간이 지나면 실패로 끝난다 — 커밋이 시작된 뒤에는 끊지 않는다.
    @Test func aPendingOfferExpiresButACommittingOneDoesNot() async throws {
        let store = makeStore()
        await store.hatch(baseID: 1)
        let mine = try #require(store.state.active)
        let theirs = remoteMon()
        let center = PokemonAuctionCenter(companion: store)
        let connection = try #require(center.apply(to: listing(for: theirs), offering: mine))
        let offerID = try #require(center.outgoingOfferID)

        center.receive(.accepted(offerID: offerID, pokemon: snapshot(theirs)), connectionID: connection)
        center.expireOutgoingOffer(offerID)
        #expect(center.outgoingStatus == .accepted, "커밋 중인 제안을 시간으로 끊으면 안 된다")

        let other = PokemonAuctionCenter(companion: store)
        _ = other.apply(to: listing(for: theirs), offering: mine)
        let pending = try #require(other.outgoingOfferID)
        other.expireOutgoingOffer(pending)
        #expect(other.outgoingStatus == .failed)
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
}
