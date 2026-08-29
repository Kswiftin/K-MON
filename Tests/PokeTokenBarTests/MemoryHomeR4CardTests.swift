import XCTest
@testable import PokeTokenBar

/// R4 가 추가한 카드 두 종(`togetherDays`, `homeVisits`)과 LAN 카드의 대문 문구 계약.
@MainActor
final class MemoryHomeR4CardTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-home-r4-cards-\(UUID().uuidString).json")
    }
    private let met = Date(timeIntervalSince1970: 1_780_000_000)
    private func days(_ count: Int, after date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: count, to: date)!
    }

    // MARK: - 함께한 N일

    func testTogetherDayCardsAppearOnlyOnceTheirDayHasArrived() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        album.recordFirstMeeting(companionID: companion, at: met)

        // 29일차 — 아직 아무 카드도 없다.
        let atDay29 = album.milestones(for: companion, now: days(29, after: met))
        XCTAssertFalse(atDay29.contains { $0.id == "together-30" }, "30일 카드가 하루 일찍 나왔다")

        // 30일차 정확히 — 경계 그 자체를 밟는다.
        let atDay30 = album.milestones(for: companion, now: days(30, after: met))
        let card = atDay30.first { $0.id == "together-30" }
        XCTAssertEqual(card?.kind, .togetherDays(30))
        XCTAssertEqual(card?.occurredAt, days(30, after: met), "카드 날짜가 조회 시각으로 찍혔다")
        XCTAssertFalse(atDay30.contains { $0.id == "together-100" })

        let atDay100 = album.milestones(for: companion, now: days(100, after: met))
        XCTAssertTrue(atDay100.contains { $0.kind == .togetherDays(100) })
    }

    /// 365 는 의도적으로 빼 뒀다 — `anniversary-1` 카드가 사실상 같은 날짜를 덮는다.
    func testNo365DayCardDuplicatesTheAnniversaryCard() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        album.recordFirstMeeting(companionID: companion, at: met)

        let afterAYear = album.milestones(for: companion, now: days(400, after: met))
        XCTAssertTrue(afterAYear.contains { $0.id == "anniversary-1" })
        XCTAssertFalse(afterAYear.contains { $0.id == "together-365" },
                       "기념일 카드와 겹치는 365일 카드가 생겼다")
    }

    func testNoTogetherCardsWithoutAFirstMeetingDate() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        // 첫 만남 기록이 전혀 없는 신규 UUID — 백필 경로도 타지 않는다.
        XCTAssertTrue(album.milestones(for: companion, now: days(400, after: met)).isEmpty)
    }

    // MARK: - 방문 카드

    func testHomeVisitCardIsHomeLevelAndSurvivesAnEmptyMilestoneState() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let now = Date(timeIntervalSince1970: 1_787_000_400)
        for _ in 0..<10 { album.recordMemoryHomeRequester(displayName: "guest", peerID: UUID(), now: now) }

        // 마일스톤 기록이 전혀 없는 동행의 방에서도 홈 기록은 보여야 한다.
        // 이 브랜치가 `guard let state` 안에 있으면 카드가 통째로 사라진다.
        let fresh = UUID()
        let cards = album.milestones(for: fresh, now: now)
        XCTAssertEqual(cards.map(\.kind), [.homeVisits(10)])
        XCTAssertEqual(cards.first?.occurredAt, now)
    }

    func testHomeVisitCardAppearsAlongsideCompanionCardsInDateOrder() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        album.recordFirstMeeting(companionID: companion, at: met)
        let visitDay = days(45, after: met)
        for _ in 0..<10 { album.recordMemoryHomeRequester(displayName: "guest", peerID: UUID(), now: visitDay) }

        let ids = album.milestones(for: companion, now: days(120, after: met)).map(\.id)
        XCTAssertEqual(ids, ["first-meeting", "together-30", "home-visits-10", "together-100"],
                       "카드가 날짜순으로 정렬되지 않았다")
    }

    // MARK: - LAN 카드 계약

    func testPreR4ProfileCardPayloadStillDecodes() throws {
        // `profileMessage` 키가 없는 R4 이전 피어의 페이로드. `Optional` 이라 합성 Codable 이
        // `decodeIfPresent` 를 쓰므로 통과해야 한다 — 여기가 깨지면 프로토콜 호환이 끊긴다.
        let legacy = #"{"displayName":"MemoryHome","speciesID":25,"isShiny":true}"#
        let card = try JSONDecoder().decode(MemoryHomeProfileCard.self, from: Data(legacy.utf8))
        XCTAssertEqual(card.speciesID, 25)
        XCTAssertNil(card.profileMessage)
        XCTAssertTrue(MemoryHomeVisitCenter.valid(card))
    }

    func testRemoteProfileMessageIsValidatedLikeALocalOne() {
        var card = MemoryHomeProfileCard(displayName: "MemoryHome", speciesID: 25, isShiny: false,
                                         sharedMemoryBody: nil, profileMessage: "피카츄랑 여행중 :)")
        XCTAssertTrue(MemoryHomeVisitCenter.valid(card), "로컬에서 저장 가능한 문구를 상대가 거부했다")

        card.profileMessage = "줄바꿈\n주입"
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card), "줄바꿈이 든 원격 문구가 통과했다")

        card.profileMessage = String(repeating: "가", count: MemoryHomeAccessSettings.profileMessageLimit + 1)
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card), "길이 상한을 넘는 원격 문구가 통과했다")

        card.profileMessage = "   "
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card))
    }

    func testSpeciesLabelRendersTheNumberNotItsSource() {
        // 백슬래시가 빠진 보간이 리터럴로 나갔던 결함(fb7e67e)의 회귀 테스트.
        let shiny = MemoryHomeProfileCard(displayName: "MemoryHome", speciesID: 25, isShiny: true,
                                          sharedMemoryBody: nil, profileMessage: nil)
        XCTAssertEqual(shiny.speciesLabel, "#25 ✨")
        let plain = MemoryHomeProfileCard(displayName: "MemoryHome", speciesID: 1, isShiny: false,
                                          sharedMemoryBody: nil, profileMessage: nil)
        XCTAssertEqual(plain.speciesLabel, "#1")
        XCTAssertFalse(plain.speciesLabel.contains("speciesID"), "표현식 소스가 그대로 렌더됐다")
    }

    func testV2CardRetainsPlacedShowroomAndFeaturedPhoto() throws {
        let decor = MemoryHomePlacedDecor(item: .retroArcade, position: .init(x: 0.75, y: 0.5))
        let photo = MemoryHomePhoto(speciesID: 25, isShiny: true, caption: "Arcade night", frame: "star",
                                    background: "studio", composition: "left", trainerStyle: "explorer")
        let card = MemoryHomeProfileCard(displayName: "MemoryHome", speciesID: 25, isShiny: false,
                                         sharedMemoryBody: nil, profileMessage: nil, roomStyle: .retro,
                                         placedDecor: [decor], featuredPhoto: photo)
        let decoded = try JSONDecoder().decode(MemoryHomeProfileCard.self,
                                               from: JSONEncoder().encode(card))
        XCTAssertEqual(decoded.roomStyle, .retro)
        XCTAssertEqual(decoded.placedDecor, [decor])
        XCTAssertEqual(decoded.featuredPhoto, photo)
    }

    func testVisitBrowsingDoesNotOwnPublicHostingLifetime() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("visit-lifetime-\(UUID().uuidString)")
        let stateURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(fileURL: stateURL)
        let visits = MemoryHomeVisitCenter(companion: store, peerID: UUID())
        visits.startHostingIfEligible()
        XCTAssertTrue(visits.isHosting)

        visits.start()
        visits.stop()
        XCTAssertFalse(visits.isActive)
        XCTAssertTrue(visits.isHosting, "leaving Visit must not unpublish the home")

        store.memoryAlbum.setMemoryHomeVisibility(.blocked)
        visits.refreshAccess()
        XCTAssertFalse(visits.isHosting)
        visits.start()
        XCTAssertTrue(visits.isActive, "private users may still browse other public homes")
        visits.shutdown()
    }

    func testNewCardKindsHaveIconAndTitleInAllThreeLanguages() {
        let kinds: [PokemonMemoryMilestone.Kind] = [.togetherDays(30), .togetherDays(100), .homeVisits(10)]
        for language in [AppLanguage.ko, .en, .ja] {
            let l = L(language)
            for kind in kinds {
                let milestone = PokemonMemoryMilestone(id: "probe", kind: kind, occurredAt: met)
                XCTAssertFalse(MemoryHomeCardStyle.icon(milestone).isEmpty, "\(kind) 아이콘 없음")
                XCTAssertFalse(MemoryHomeCardStyle.title(milestone, l).isEmpty, "\(language)/\(kind) 제목 없음")
            }
        }
    }
}
