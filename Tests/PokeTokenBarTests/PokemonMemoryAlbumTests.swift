import XCTest
@testable import PokeTokenBar

private struct LegacyMemorySnapshot: Codable {
    let memories: [UUID: [LegacyMemory]]
}

private struct LegacyMemory: Codable {
    let id: UUID
    let companionID: UUID
    let createdAt: Date
    let source: PokemonMemorySource
    let body: String
    let eventID: String?
}

@MainActor
final class PokemonMemoryAlbumTests: XCTestCase {
    private func temporaryURL() -> URL {
        storeStateURL("mon-memory-home")
    }

    func testManualMemoryValidatesGraphemesAndPersists() {
        let url = temporaryURL(), companionID = UUID()
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)

        XCTAssertFalse(album.addManual(companionID: companionID, body: ""))
        XCTAssertFalse(album.addManual(companionID: companionID, body: String(repeating: "👨‍👩‍👧‍👦", count: 281)))
        XCTAssertTrue(album.addManual(companionID: companionID, body: "오늘 함께 집중했다."))

        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).entries(for: companionID).first?.source, .manual)
    }

    func testManualMemoryAtGraphemeLimitAndItsPinSurviveRelaunch() {
        let url = temporaryURL(), companionID = UUID()
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)
        let body = String(repeating: "👨‍👩‍👧‍👦", count: 280)

        XCTAssertTrue(album.addManual(companionID: companionID, body: body))
        guard let memory = album.entries(for: companionID).first else {
            return XCTFail("A successful submission must create one memory")
        }
        album.pin(memory)

        let reloaded = PokemonMemoryAlbum(fileURL: url)
        XCTAssertEqual(reloaded.entries(for: companionID), [memory])
        XCTAssertEqual(reloaded.pinned(for: companionID)?.id, memory.id)
    }

    func testPinnedMemoryIsScopedToCompanionAndClearsWhenDeleted() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let firstID = UUID(), secondID = UUID()
        album.record(companionID: firstID, body: "First", source: .event)
        album.record(companionID: secondID, body: "Second", source: .event)
        let first = album.entries(for: firstID)[0]
        let second = album.entries(for: secondID)[0]

        album.pin(first)
        album.pin(second)

        XCTAssertEqual(album.pinned(for: firstID)?.id, first.id)
        XCTAssertEqual(album.pinned(for: secondID)?.id, second.id)
        XCTAssertFalse(album.delete(first), "Automatic evidence cannot be deleted")

        XCTAssertTrue(album.addManual(companionID: firstID, body: "Private note"))
        let manual = album.entries(for: firstID).last!
        album.pin(manual)
        XCTAssertTrue(album.delete(manual))
        XCTAssertNil(album.pinned(for: firstID))
    }

    func testAutomaticMemoryCanBeHiddenRestoredAndPersists() {
        let url = temporaryURL(), companionID = UUID()
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)
        album.record(companionID: companionID, body: "Event", source: .event)
        let automatic = album.entries(for: companionID)[0]

        XCTAssertTrue(album.setHidden(automatic, isHidden: true))
        XCTAssertTrue(PokemonMemoryAlbum(fileURL: url).entries(for: companionID)[0].isHidden)

        let reloaded = PokemonMemoryAlbum(fileURL: url)
        let hidden = reloaded.entries(for: companionID)[0]
        XCTAssertTrue(reloaded.setHidden(hidden, isHidden: false))
        XCTAssertFalse(PokemonMemoryAlbum(fileURL: url).entries(for: companionID)[0].isHidden)
        XCTAssertFalse(reloaded.delete(hidden), "Automatic evidence cannot be deleted")
    }

    func testDistinctStableEventIDsKeepRepeatedEventsWhileReplayIsIdempotent() {
        let url = temporaryURL(), companionID = UUID()
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)

        album.record(companionID: companionID, body: "First adventure", source: .event,
                     eventID: "adventure:run-1")
        album.record(companionID: companionID, body: "Second adventure", source: .event,
                     eventID: "adventure:run-2")
        album.record(companionID: companionID, body: "Replay", source: .event,
                     eventID: "adventure:run-1")

        XCTAssertEqual(album.entries(for: companionID).map(\.eventID),
                       ["adventure:run-1", "adventure:run-2"])
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).entries(for: companionID).count, 2,
                       "Persisted event IDs must also suppress a replay after relaunch")
    }

    func testTimelineHidesEntriesAndLimitsToTwentyNewest() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL()), companionID = UUID()
        for number in 0..<20 { album.record(companionID: companionID, body: "Event \(number)", source: .event) }
        XCTAssertTrue(album.addManual(companionID: companionID, body: "Private note"))
        let hidden = album.entries(for: companionID)[20]

        album.setHidden(hidden, isHidden: true)

        XCTAssertEqual(album.timeline(for: companionID).count, 20)
        XCTAssertFalse(album.timeline(for: companionID).contains(where: { $0.id == hidden.id }))
    }

    func testAlbumKeepsTwoHundredEntriesAndClearsAnEvictedPin() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL()), companionID = UUID()
        for number in 0..<200 { album.record(companionID: companionID, body: "Event \(number)", source: .event) }
        album.pin(album.entries(for: companionID)[0])

        album.record(companionID: companionID, body: "Event 200", source: .event)

        XCTAssertEqual(album.entries(for: companionID).count, 200)
        XCTAssertNil(album.pinned(for: companionID))
    }

    func testPruningRemovesDanglingEntriesAndPins() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let retainedID = UUID(), releasedID = UUID()
        album.record(companionID: retainedID, body: "Keep", source: .event)
        album.record(companionID: releasedID, body: "Remove", source: .event)
        album.pin(album.entries(for: releasedID)[0])

        album.prune(validCompanionIDs: [retainedID])

        XCTAssertTrue(album.entries(for: releasedID).isEmpty)
        XCTAssertNil(album.pinned(for: releasedID))
    }

    func testLegacySnapshotDecodesAndCorruptFileIsBackedUp() throws {
        let url = temporaryURL(), companionID = UUID()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
        }
        let legacy = LegacyMemorySnapshot(memories: [companionID: [
            LegacyMemory(id: UUID(), companionID: companionID, createdAt: Date(), source: .event,
                         body: "Legacy", eventID: nil)
        ]])
        try JSONEncoder().encode(legacy).write(to: url)
        let migrated = PokemonMemoryAlbum(fileURL: url)
        XCTAssertEqual(migrated.entries(for: companionID).count, 1)
        XCTAssertEqual(migrated.firstRecordedAt(for: companionID), legacy.memories[companionID]?.first?.createdAt,
                       "Old albums derive their first-record date from their earliest retained memory")
        XCTAssertEqual(migrated.firstMetAt(for: companionID), legacy.memories[companionID]?.first?.createdAt,
                       "Old albums use their earliest retained memory as the stable first-meeting fallback")

        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(PokemonMemoryAlbum(fileURL: url).entries(for: companionID).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }

    func testMilestonesCountOnlyNewSettlementsAndPersistAcrossRelaunch() {
        let url = temporaryURL(), companionID = UUID()
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)
        let first = Date(timeIntervalSinceReferenceDate: 1_000)
        album.record(companionID: companionID, body: "First", source: .event, createdAt: first)
        for number in 0..<10 {
            album.recordCompletedFocusSession(companionID: companionID, sessionID: "run-\(number)",
                                              completedAt: first.addingTimeInterval(Double(number + 1)))
        }
        album.recordCompletedFocusSession(companionID: companionID, sessionID: "run-9",
                                          completedAt: first.addingTimeInterval(99))

        // 이 테스트의 주제는 **집중 정산**이다. 전체 카드 목록을 잠그면 날짜에서 파생하는
        // 카드(첫 겨울·크리스마스)를 더할 때마다 여기가 깨진다 — `first` 가 1월이라 첫 겨울
        // 카드도 정당하게 뜬다. 그래서 집중 카드만 본다.
        let focusIDs = { (album: PokemonMemoryAlbum) in
            album.milestones(for: companionID, now: first).map(\.id).filter { $0.hasPrefix("focus-") }
        }
        XCTAssertEqual(album.firstRecordedAt(for: companionID), first)
        XCTAssertEqual(focusIDs(album), ["focus-10"], "같은 세션 ID를 두 번 세었다")
        XCTAssertEqual(focusIDs(PokemonMemoryAlbum(fileURL: url)), ["focus-10"])
    }

    func testFocusMilestoneBoundariesAndEvolutionSurviveMemoryEviction() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL()), companionID = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        for number in 0..<100 {
            album.recordCompletedFocusSession(companionID: companionID, sessionID: "run-\(number)",
                                              completedAt: start.addingTimeInterval(Double(number)))
        }
        album.recordEvolution(companionID: companionID, eventID: "evolution-stable-id", evolvedSpeciesID: 26,
                              occurredAt: start)
        for number in 0...200 {
            album.record(companionID: companionID, body: "Event \(number)", source: .event,
                         eventID: "event-\(number)", createdAt: start.addingTimeInterval(Double(number + 200)))
        }

        let ids = album.milestones(for: companionID, now: start).map(\.id)
        XCTAssertTrue(ids.contains("focus-10"))
        XCTAssertTrue(ids.contains("focus-30"))
        XCTAssertTrue(ids.contains("focus-100"))
        XCTAssertTrue(ids.contains("evolution:evolution-stable-id"))
        XCTAssertEqual(album.entries(for: companionID).count, 200)
    }

    func testFirstMeetingIsImmediateAndItsAnniversaryUsesThePersistedMeetingDate() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL()), companionID = UUID()
        let first = Date(timeIntervalSinceReferenceDate: 10_000)
        album.recordFirstMeeting(companionID: companionID, at: first)
        let almostYear = Calendar.current.date(byAdding: .day, value: 364, to: first)!
        let anniversary = Calendar.current.date(byAdding: .year, value: 1, to: first)!

        XCTAssertEqual(album.milestones(for: companionID, now: first).map(\.id), ["first-meeting"])
        XCTAssertFalse(album.milestones(for: companionID, now: almostYear).contains { $0.id == "anniversary-1" })
        XCTAssertTrue(album.milestones(for: companionID, now: anniversary).contains { $0.id == "anniversary-1" })
    }

    func testThemesAreCompanionScopedPersistAndPrune() {
        let url = temporaryURL(), first = UUID(), second = UUID()
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)
        album.setTheme(.red, for: first)
        album.setTheme(.mint, for: second)
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).theme(for: first), .red)
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).theme(for: second), .mint)
        album.prune(validCompanionIDs: [first])
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).theme(for: second), .blue)
    }

    func testMemoryHomeAccessDefaultsForLegacySnapshotAndSharedPinClears() throws {
        let url = temporaryURL(), companionID = UUID()
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = LegacyMemorySnapshot(memories: [companionID: []])
        try JSONEncoder().encode(legacy).write(to: url)
        let album = PokemonMemoryAlbum(fileURL: url)
        XCTAssertEqual(album.memoryHomeAccess.visibility, .open)
        XCTAssertTrue(album.addManual(companionID: companionID, body: "Only this note may be shared"))
        let note = album.entries(for: companionID)[0]
        album.pin(note); album.setSharedPinnedMemory(note, activeCompanionID: companionID)
        XCTAssertEqual(album.sharedPinnedMemory(for: companionID)?.id, note.id)
        XCTAssertTrue(album.delete(note))
        XCTAssertNil(album.memoryHomeAccess.sharedPinnedMemoryID)
    }

    func testMemoryHomeRecentRequestersDeduplicateCapAndPersist() {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)
        let first = UUID()
        for number in 0..<21 { album.recordMemoryHomeRequester(displayName: "Visitor \(number)", peerID: number == 0 ? first : UUID()) }
        album.recordMemoryHomeRequester(displayName: "Newest", peerID: first)
        XCTAssertEqual(album.memoryHomeAccess.recentRequesters.count, 20)
        XCTAssertEqual(album.memoryHomeAccess.recentRequesters.first?.displayName, "Newest")
        album.setMemoryHomeBlocked(first, blocked: true)
        XCTAssertTrue(PokemonMemoryAlbum(fileURL: url).memoryHomeAccess.blockedPeerIDs.contains(first))
    }

    /// 100개 상한을 넘길 때 버리는 항목이 **방금 쓴 것**이면, `setPeerAlias` 는 `true` 를 돌려주고도
    /// 값을 잃는다. `remove(at: startIndex)` 는 해시 순서라 방금 넣은 키가 걸릴 수 있었다.
    func testPeerAliasEvictionNeverDropsTheAliasJustWritten() {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)
        let existing = (0..<100).map { _ in UUID() }
        for peerID in existing { XCTAssertTrue(album.setPeerAlias("이웃", for: peerID)) }
        let newest = UUID()

        XCTAssertTrue(album.setPeerAlias("막내", for: newest))

        let stored = PokemonMemoryAlbum(fileURL: url).memoryHomeAccess.peerAliases
        XCTAssertEqual(stored.count, 100)
        XCTAssertEqual(stored[newest], "막내",
                       "상한을 넘겼다고 방금 저장한 일촌명을 버리면 저장에 성공한 척하고 값이 사라진다")
        // 버리는 항목도 결정적이어야 한다 — 해시 순서로 고르면 실행마다 다른 사람이 지워진다.
        let evicted = existing.min(by: { $0.uuidString < $1.uuidString })!
        XCTAssertNil(stored[evicted])
        XCTAssertEqual(existing.filter { stored[$0] != nil }.count, 99)
    }

    func testMemoryHomePublicNicknameMigratesOnceValidatesAndPersists() {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)

        album.initializeMemoryHomePublicNickname(from: " Ash Ketchum ")
        XCTAssertEqual(album.memoryHomePublicNickname, "AshKetchum")
        XCTAssertFalse(album.setMemoryHomePublicNickname("has space"))
        XCTAssertFalse(album.setMemoryHomePublicNickname("bad\nname"))
        XCTAssertTrue(album.setMemoryHomePublicNickname("PalletHome"))
        album.initializeMemoryHomePublicNickname(from: "OtherTrainer")

        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).memoryHomePublicNickname, "PalletHome")
    }

    func testSharedPinClearsWhenItsCompanionIsNoLongerActive() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let first = UUID(), second = UUID()
        album.record(companionID: first, body: "Pinned", source: .event)
        let memory = album.entries(for: first)[0]
        album.pin(memory)
        album.setSharedPinnedMemory(memory, activeCompanionID: first)

        album.clearSharedPinnedMemory(unlessPinnedFor: second)

        XCTAssertNil(album.memoryHomeAccess.sharedPinnedMemoryID)
        XCTAssertNil(album.sharedPinnedMemory(for: second))
    }

    /// 고정이 편도면 대표 기억을 **내릴** 수 없다 — 핀을 다시 눌러도 같은 기억을 재고정할 뿐이라
    /// "아래 기억의 핀을 눌러…" 빈 상태는 첫 고정 이후 영원히 도달 불가가 된다.
    /// 내릴 때는 LAN 공유도 함께 꺼져야 한다 — 고정이 풀린 기억이 계속 나가면 동의를 넘어선다.
    func testPinningTheSameMemoryAgainUnpinsItAndStopsSharing() {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)
        let companionID = UUID()
        album.record(companionID: companionID, body: "첫 집중", source: .event)
        let memory = album.entries(for: companionID)[0]
        album.pin(memory)
        album.setSharedPinnedMemory(memory, activeCompanionID: companionID)

        album.pin(memory)

        XCTAssertNil(album.pinned(for: companionID), "같은 핀을 다시 눌렀는데 고정이 풀리지 않으면 내릴 길이 없다")
        XCTAssertNil(album.memoryHomeAccess.sharedPinnedMemoryID, "고정이 풀린 기억이 계속 공유되면 동의를 넘어선다")
        XCTAssertNil(PokemonMemoryAlbum(fileURL: url).pinned(for: companionID))
    }

    /// 대표 기억을 **바꾸면** LAN 공유가 꺼진다(의도된 동작 — 새 기억은 아직 동의받지 않았다).
    /// 화면은 이 사실을 미리 알려야 하므로, 규칙이 조용히 뒤집히지 않게 여기에 고정해 둔다.
    ///
    /// 검증은 **되돌아가 재고정하는** 분기로 한다. 바꾼 직후만 보면 `sharedPinnedMemory(for:)`
    /// 자신의 "고정된 것과 같은 ID 인가" 가드가 결함을 가려, 정규화를 통째로 지워도 통과한다.
    /// 위험한 것은 남은 ID 다 — A 로 돌아오면 동의를 다시 받지 않고 공유가 되살아난다.
    func testPinningADifferentMemoryTurnsOffLANSharingForGood() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companionID = UUID()
        album.record(companionID: companionID, body: "첫 집중", source: .event)
        album.record(companionID: companionID, body: "비 오는 날", source: .event)
        let first = album.entries(for: companionID)[0], second = album.entries(for: companionID)[1]
        album.pin(first)
        album.setSharedPinnedMemory(first, activeCompanionID: companionID)

        album.pin(second)

        XCTAssertEqual(album.pinned(for: companionID)?.id, second.id)
        XCTAssertNil(album.memoryHomeAccess.sharedPinnedMemoryID, "대표를 바꿨는데 공유 동의가 남아 있다")

        album.pin(first)

        XCTAssertEqual(album.pinned(for: companionID)?.id, first.id)
        XCTAssertNil(album.sharedPinnedMemory(for: companionID),
                     "대표를 되돌렸다고 공유가 동의 없이 되살아나면 안 된다")
    }

    /// 일촌명을 **내리는** 길. `setPeerAlias` 는 빈 값을 거부하므로, 지우는 경로가 따로 없으면
    /// 잘못 붙인 별명은 덮어쓸 수만 있고 없앨 수 없다(대문 문구의 `clearProfileMessage` 와 같은 짝).
    func testClearPeerAliasRemovesTheAliasAndPersists() {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url)
        let peerID = UUID()
        XCTAssertTrue(album.setPeerAlias("옆집", for: peerID))
        XCTAssertFalse(album.setPeerAlias("", for: peerID), "빈 값으로는 지울 수 없다 — 그래서 전용 경로가 필요하다")

        XCTAssertTrue(album.clearPeerAlias(for: peerID))

        XCTAssertNil(album.memoryHomeAccess.peerAliases[peerID])
        XCTAssertNil(PokemonMemoryAlbum(fileURL: url).memoryHomeAccess.peerAliases[peerID], "지운 별명이 다시 살아났다")
        XCTAssertFalse(album.clearPeerAlias(for: peerID), "지울 것이 없으면 세이브도 나가지 않아야 한다")
    }
}
