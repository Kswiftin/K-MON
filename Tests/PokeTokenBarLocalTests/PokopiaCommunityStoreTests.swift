import Foundation
import Testing
@testable import PokeTokenBar

@MainActor @Suite struct PokopiaCommunityStoreTests {
    private func admit(_ store: CompanionStore) {
        #expect(store.memoryAlbum.admitTownResident(.init(speciesID: 1, name: "이상해씨",
                   types: [.grass], arrivedAt: CommunityFixture.now)))
    }

    @Test func focusWithoutAdventureCountsOnceAfterIssue() throws {
        let directory = storeFixtureDirectory("community-focus")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CommunityFixture.store(at: directory.appendingPathComponent("state.json"), clock: { CommunityFixture.now })
        _ = store.completeFocusSession(minutes: 20)
        admit(store)
        store.refreshPokopiaCommunity()
        let request = try #require(store.state.pokopiaCommunity.daily?.requests.first)
        #expect(store.state.pokopiaCommunity.daily?.focusMinutes == 0)
        #expect(store.state.adventure == nil)
        _ = store.completeFocusSession(minutes: 19)
        #expect(store.claimPokopiaRequest(id: request.id) == nil)
        _ = store.completeFocusSession(minutes: 1)
        let stock = store.itemCount(request.reward)
        #expect(store.claimPokopiaRequest(id: request.id) != nil)
        #expect(store.itemCount(request.reward) == stock + 1)
        #expect(store.state.pokopiaCommunity.totalCompleted == 1)
        #expect(store.state.pokopiaCommunity.friendships["waste:1"] == 1)
        #expect(store.claimPokopiaRequest(id: request.id) == nil)
        #expect(store.itemCount(request.reward) == stock + 1)
    }

    @Test func reloadAndTransferKeepTheClaimClosed() throws {
        let directory = storeFixtureDirectory("community-reload")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let first = CommunityFixture.store(at: url, clock: { CommunityFixture.now })
        admit(first)
        first.refreshPokopiaCommunity()
        let request = try #require(first.state.pokopiaCommunity.daily?.requests.first)
        let old = try first.exportedSaveData(appVersion: "test", deviceName: "fixture")
        _ = first.completeFocusSession(minutes: 20)
        #expect(first.claimPokopiaRequest(id: request.id) != nil)
        let second = CommunityFixture.store(at: url, clock: { CommunityFixture.now })
        #expect(second.claimPokopiaRequest(id: request.id) == nil)
        try second.applySave(SaveTransfer.decode(old))
        #expect(second.claimPokopiaRequest(id: request.id) == nil)
        let current = try second.exportedSaveData(appVersion: "test", deviceName: "fixture")
        try second.applySave(SaveTransfer.decode(current))
        #expect(second.claimPokopiaRequest(id: request.id) == nil)
    }

    @Test func rejectedMealDoesNotAdvance() {
        let directory = storeFixtureDirectory("community-meal-fail")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CommunityFixture.store(at: directory.appendingPathComponent("state.json"), clock: { CommunityFixture.now })
        admit(store)
        store.refreshPokopiaCommunity()
        #expect(store.feedTown(.dishHerbSoup) == nil)
        #expect(store.state.pokopiaCommunity.daily?.mealsByRegion.isEmpty == true)
        #expect(store.memoryAlbum.feedTown(until: CommunityFixture.now.addingTimeInterval(PokopiaCrafting.maxSatiety)))
        store.debugSetItemCount(.dishPokopiaSet, 1)
        #expect(store.feedTown(.dishPokopiaSet) == nil)
        #expect(store.itemCount(.dishPokopiaSet) == 1)
        #expect(store.state.pokopiaCommunity.daily?.mealsByRegion.isEmpty == true)
    }

    @Test func successfulMealAdvancesOnlyTheFedRegion() {
        let directory = storeFixtureDirectory("community-meal")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CommunityFixture.store(at: directory.appendingPathComponent("state.json"), clock: { CommunityFixture.now })
        admit(store)
        store.refreshPokopiaCommunity()
        store.memoryAlbum.selectRegion(.coast)
        store.debugSetItemCount(.dishHerbSoup, 1)
        #expect(store.feedTown(.dishHerbSoup) != nil)
        #expect(store.state.pokopiaCommunity.daily?.mealsByRegion == ["coast": 1])
    }

    @Test func fullInventoryDoesNotConsumeARequest() throws {
        let directory = storeFixtureDirectory("community-full")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CommunityFixture.store(at: directory.appendingPathComponent("state.json"), clock: { CommunityFixture.now })
        admit(store)
        store.refreshPokopiaCommunity()
        let request = try #require(store.state.pokopiaCommunity.daily?.requests.first)
        _ = store.completeFocusSession(minutes: 20)
        store.debugSetItemCount(request.reward, SaveTransfer.maxTokenValue)
        #expect(store.claimPokopiaRequest(id: request.id) == nil)
        #expect(store.state.pokopiaCommunity.daily?.requests.first?.isClaimed == false)
        #expect(store.state.pokopiaCommunity.friendships.isEmpty)
        #expect(store.state.pokopiaCommunity.totalCompleted == 0)
        store.debugSetItemCount(request.reward, 999)
        #expect(store.claimPokopiaRequest(id: request.id) == nil)
        #expect(store.state.pokopiaCommunity.daily?.requests.first?.isClaimed == false)
    }

    @Test func failedWriteKeepsRewardAndLedgerTogetherInMemory() throws {
        let directory = storeFixtureDirectory("community-write-fail")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let store = CommunityFixture.store(at: url, clock: { CommunityFixture.now })
        admit(store)
        store.refreshPokopiaCommunity()
        let request = try #require(store.state.pokopiaCommunity.daily?.requests.first)
        _ = store.completeFocusSession(minutes: 20)
        let albumURL = directory.appendingPathComponent(CompanionStorageLocations.memoryFileName)
        let albumBefore = try Data(contentsOf: albumURL)
        let stock = store.itemCount(request.reward)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(store.claimPokopiaRequest(id: request.id) != nil)
        #expect(store.saveFailed)
        #expect(store.itemCount(request.reward) == stock + 1)
        #expect(store.state.pokopiaCommunity.daily?.requests.first?.isClaimed == true)
        #expect(store.claimPokopiaRequest(id: request.id) == nil)
        #expect(store.itemCount(request.reward) == stock + 1)
        #expect(try Data(contentsOf: albumURL) == albumBefore)
    }

    @Test func contextIsReadOnlyAndFoodRequiresAvailableResources() throws {
        let directory = storeFixtureDirectory("community-context")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let store = CommunityFixture.store(at: url, clock: { CommunityFixture.now })
        let before = try Data(contentsOf: url)
        #expect(!store.pokopiaCommunityContext().canShareFood)
        #expect(store.state.pokopiaCommunity.daily == nil)
        #expect(try Data(contentsOf: url) == before)
        store.debugSetItemCount(.dishHerbSoup, 1)
        #expect(store.pokopiaCommunityContext().canShareFood)
    }

    @Test(arguments: [false, true])
    func fractionalArrivalSurvivesTransferAndRemainsClaimable(intoFreshStore: Bool) throws {
        let sourceDirectory = storeFixtureDirectory("community-precision-source")
        let targetDirectory = storeFixtureDirectory("community-precision-target")
        defer {
            try? FileManager.default.removeItem(at: sourceDirectory)
            try? FileManager.default.removeItem(at: targetDirectory)
        }
        let arrivedAt = CommunityFixture.now.addingTimeInterval(0.125)
        let source = CommunityFixture.store(at: sourceDirectory.appendingPathComponent("state.json"), clock: { CommunityFixture.now })
        #expect(source.memoryAlbum.admitTownResident(.init(speciesID: 1, name: "이상해씨", types: [.grass], arrivedAt: arrivedAt)))
        source.refreshPokopiaCommunity()
        let request = try #require(source.state.pokopiaCommunity.daily?.requests.first)
        let exported = try source.exportedSaveData(appVersion: "test", deviceName: "fixture")
        let target = intoFreshStore
            ? CommunityFixture.store(at: targetDirectory.appendingPathComponent("state.json"), clock: { CommunityFixture.now }) : source
        try target.applySave(SaveTransfer.decode(exported))
        #expect(target.memoryAlbum.town.residents.first?.arrivedAt == arrivedAt)
        #expect(target.state.pokopiaCommunity.daily?.requests.first?.arrivedAt == arrivedAt)
        _ = target.completeFocusSession(minutes: 20)
        #expect(PokopiaCommunity.status(request, state: target.state.pokopiaCommunity, context: target.pokopiaCommunityContext()) == .ready)
        let stock = target.itemCount(request.reward)
        #expect(target.claimPokopiaRequest(id: request.id) != nil)
        #expect(target.itemCount(request.reward) == stock + 1)
        #expect(target.claimPokopiaRequest(id: request.id) == nil)
    }

    @Test func sameSecondReentryAfterTransferStillRejectsTheOldRequest() throws {
        let directory = storeFixtureDirectory("community-precision-reentry")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CommunityFixture.store(at: directory.appendingPathComponent("state.json"), clock: { CommunityFixture.now })
        #expect(store.memoryAlbum.admitTownResident(.init(speciesID: 1, name: "이상해씨", types: [.grass],
            arrivedAt: CommunityFixture.now.addingTimeInterval(0.125))))
        store.refreshPokopiaCommunity()
        let request = try #require(store.state.pokopiaCommunity.daily?.requests.first)
        try store.applySave(SaveTransfer.decode(store.exportedSaveData(appVersion: "test", deviceName: "fixture")))
        #expect(store.memoryAlbum.evictTownResident(speciesID: 1))
        #expect(store.memoryAlbum.admitTownResident(.init(speciesID: 1, name: "새 이웃", types: [.grass],
            arrivedAt: CommunityFixture.now.addingTimeInterval(0.375))))
        // 다시 내보내는 경계에서도 두 도착 시각이 같은 초로 합쳐지면 안 된다.
        try store.applySave(SaveTransfer.decode(store.exportedSaveData(appVersion: "test", deviceName: "fixture")))
        _ = store.completeFocusSession(minutes: 20)
        #expect(PokopiaCommunity.status(request, state: store.state.pokopiaCommunity, context: store.pokopiaCommunityContext()) == .residentLeft)
        #expect(store.claimPokopiaRequest(id: request.id) == nil)
    }
}
