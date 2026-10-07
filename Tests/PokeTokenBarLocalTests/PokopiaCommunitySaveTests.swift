import Foundation
import Testing
@testable import PokeTokenBar

@Suite struct PokopiaCommunitySaveTests {
    // 새 필드 추가 전 e1f6fdb에서 기존 signed로 생성한 고정 fixture.
    private let legacy = Data(#"{"achievements":{"counts":{}},"activeSecondsDate":"","activeSecondsToday":0,"activeSecondsTotal":0,"adventureHistory":[],"adventureWeekKey":"","auctionListingMonIDs":[],"battleHistory":[],"battleRank":{"points":0},"boxedMons":[],"collectedFinals":[],"dex":[],"economyVersion":2,"eggFragments":0,"eggUsage":0,"favoriteMonIDs":[],"focusEggReadyDates":[],"focusEggs":0,"forcedResetVersion":1,"frontierBP":0,"frontierBestStreak":0,"gymBadges":[],"gymDefenseLog":[],"gymDefenseRewardDate":"","gymDefenseRewardToday":0,"gymLeagueBadges":[],"homePartyIDs":[],"integrity":"1ed4f5635a13bd92","integrityVersion":14,"inventory":{"townWood":7},"lastAdventureBonusDate":"","lastCandyDate":"","missions":{"assignedDailyIDs":[],"assignedDayKey":"","daily":{},"dayKey":"","weekKey":"","weekly":{}},"outfit":{"worn":[]},"ownedOutfits":[],"professorTransferProgress":0,"raidCatchCountTierSix":0,"raidCatchDate":"","raidCatchDateTierFive":"","raidCatchDateTierSix":"","raidCatchDateTierThree":"","raidRewardCountTierSix":0,"raidRewardDate":"","raidRewardDateTierFive":"","raidRewardDateTierSix":"","raidRewardDateTierThree":"","safariZoneCatchDate":"","safariZoneCatchesToday":0,"safariZoneUpdateBonusClaimed":false,"safariZoneVisitDate":"","safariZoneVisitsToday":0,"seasons":{"counts":{},"seasonKey":""},"shinyEggCharges":0,"spentTokens":0,"starPieces":0,"starterCandidates":[],"starterChosen":false,"technicalMachines":{},"trainer":{"points":0},"trainerName":"","usedSinceInstall":0,"waveRun":{"bestWave":0,"clears":0,"finished":0},"waveRunEggRewardDate":"","weeklyAdventureCount":0}"#.utf8)
    private let seed = "pokopia-content-tests"

    private func issued() -> CompanionState {
        var state = CompanionState()
        _ = PokopiaCommunity.prepare(&state.pokopiaCommunity, context: CommunityFixture.context())
        return state
    }

    @Test func legacySignedSaveStillVerifies() throws {
        let state = try JSONDecoder().decode(CompanionState.self, from: legacy)
        #expect(state.inventory["townWood"] == 7)
        #expect(state.pokopiaCommunity == PokopiaCommunityState())
        #expect(!SaveTransfer.isTampered(state, deviceSeed: seed))
        #expect(PokopiaCommunity.canonicalPayload(state.pokopiaCommunity) == nil)
    }

    @Test func roundTripKeepsClaimAndFriendship() throws {
        var state = issued()
        let id = try #require(state.pokopiaCommunity.daily?.requests.first?.id)
        _ = PokopiaCommunity.recordFocusMinutes(20, dayKey: "2026-10-07", in: &state.pokopiaCommunity)
        _ = PokopiaCommunity.claim(requestID: id, context: CommunityFixture.context(), in: &state.pokopiaCommunity)
        let signed = SaveTransfer.signed(state, deviceSeed: seed)
        let decoded = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(signed))
        #expect(decoded.pokopiaCommunity == state.pokopiaCommunity)
        #expect(SaveTransfer.sanitized(decoded).pokopiaCommunity == state.pokopiaCommunity)
        #expect(!SaveTransfer.isTampered(decoded, deviceSeed: seed))
    }

    @Test func everyRewardLedgerFieldChangesTheSignature() {
        let signed = SaveTransfer.signed(issued(), deviceSeed: seed)
        let changes: [(inout PokopiaCommunityState) -> Void] = [
            { $0.daily?.dayKey = "2026-10-08" }, { $0.daily?.isIssued = false },
            { $0.daily?.isBlocked = true }, { $0.daily?.issuedCount = 2 },
            { $0.daily?.focusMinutes = 1 }, { $0.daily?.mealsByRegion["waste"] = 1 },
            { $0.daily?.claimedCount = 1 }, { $0.daily?.requests[0].isClaimed = true },
            { $0.daily?.requests[0].reward = .townStone }, { $0.daily?.requests[0].target = 1 },
            { $0.daily?.requests[0].arrivedAt = CommunityFixture.now.addingTimeInterval(1) },
            { $0.daily?.requests[0].id = "changed" }, { $0.daily?.requests[0].region = .coast },
            { $0.daily?.requests[0].speciesID = 4 }, { $0.daily?.requests[0].kind = .meal },
            { $0.daily?.requests[0].terrain = .grass }, { $0.daily?.requests = [] },
            { $0.friendships["waste:1"] = 1 }, { $0.totalCompleted = 1 },
            { $0.milestones.insert(.firstThanks) }, { $0.needsRecovery = true }
        ]
        for change in changes {
            var changed = signed
            change(&changed.pokopiaCommunity)
            #expect(SaveTransfer.isTampered(changed, deviceSeed: seed))
        }
    }

    @Test func malformedCommunityCannotReissueToday() throws {
        var json = try #require(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        json["pokopiaCommunity"] = ["daily": "broken"]
        let state = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json))
        var community = state.pokopiaCommunity
        #expect(community.needsRecovery)
        #expect(PokopiaCommunity.prepare(&community, context: CommunityFixture.context()))
        #expect(community.daily?.isBlocked == true)
        #expect(!PokopiaCommunity.prepare(&community, context: CommunityFixture.context()))
        #expect(PokopiaCommunity.claim(requestID: "anything", context: CommunityFixture.context(), in: &community) == nil)
        #expect(PokopiaCommunity.prepare(&community, context: CommunityFixture.context(dayKey: "2026-10-08")))
        #expect(community.daily?.isBlocked == false)
        #expect(community.daily?.requests.count == 1)
    }

    @Test func unknownRequestDoesNotFreeAnIssuedSlot() throws {
        var state = issued()
        state.pokopiaCommunity.daily?.issuedCount = 3
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var community = try #require(json["pokopiaCommunity"] as? [String: Any])
        var board = try #require(community["daily"] as? [String: Any])
        var requests = try #require(board["requests"] as? [[String: Any]])
        requests.append(["kind": "future-request"])
        board["requests"] = requests
        community["daily"] = board
        json["pokopiaCommunity"] = community
        var decoded = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json)).pokopiaCommunity
        #expect(decoded.daily?.issuedCount == 3)
        #expect(decoded.daily?.requests.count == 1)
        #expect(!PokopiaCommunity.prepare(&decoded, context: CommunityFixture.context(residents: 5)))
        #expect(decoded.daily?.requests.count == 1)
    }

    @Test func canonicalIgnoresDictionaryAndMilestoneInsertionOrder() {
        var first = issued().pokopiaCommunity, second = first
        first.friendships = ["waste:1": 2, "coast:4": 7]
        second.friendships = ["coast:4": 7, "waste:1": 2]
        first.milestones = [.firstThanks, .settledHome]
        second.milestones = [.settledHome, .firstThanks]
        #expect(PokopiaCommunity.canonicalPayload(first) == PokopiaCommunity.canonicalPayload(second))
    }

    @Test func normalizationRejectsInvalidRequestAndClampsCounters() {
        var state = issued().pokopiaCommunity
        state.daily?.requests[0].reward = .rareCandy
        state.daily?.focusMinutes = Int.max
        state.daily?.claimedCount = Int.max
        state.friendships = ["waste:1": Int.max, "unknown:1": 5, "waste:-1": 5]
        let normalized = PokopiaCommunity.normalized(state)
        #expect(normalized.daily?.requests.isEmpty == true)
        #expect(normalized.daily?.issuedCount == 1)
        #expect(normalized.daily?.focusMinutes == 20)
        #expect(normalized.daily?.claimedCount == 1)
        #expect(normalized.friendships == ["waste:1": 10])
    }

    @Test func importingAnOlderBackupCannotReopenAClaim() throws {
        let old = issued()
        var current = old
        let id = try #require(current.pokopiaCommunity.daily?.requests.first?.id)
        _ = PokopiaCommunity.recordFocusMinutes(20, dayKey: "2026-10-07", in: &current.pokopiaCommunity)
        _ = PokopiaCommunity.claim(requestID: id, context: CommunityFixture.context(), in: &current.pokopiaCommunity)
        var merged = SaveTransfer.rebasedForThisDevice(old, current: current).pokopiaCommunity
        #expect(merged.daily?.requests.first?.isClaimed == true)
        #expect(merged.totalCompleted == 1)
        #expect(merged.friendships["waste:1"] == 1)
        #expect(PokopiaCommunity.claim(requestID: id, context: CommunityFixture.context(), in: &merged) == nil)
    }
}
