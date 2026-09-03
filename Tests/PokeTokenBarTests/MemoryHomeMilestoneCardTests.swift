import XCTest
@testable import PokeTokenBar

/// 적립형 추억 카드 — 함께한 N일(`togetherDays`)과 홈 방문 N회(`homeVisits`).
/// 달력이 만드는 카드는 `MemoryHomeDateCardTests` 가 따로 맡는다.
@MainActor
final class MemoryHomeMilestoneCardTests: XCTestCase {
    private func temporaryURL() -> URL {
        storeStateURL("memory-home-milestone-cards")
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
