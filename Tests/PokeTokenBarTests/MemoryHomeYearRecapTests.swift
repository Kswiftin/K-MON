import XCTest
@testable import PokeTokenBar

/// 기획서 §25 연말 결산. 이 결산이 **거짓말을 하지 않는가**가 이 파일의 전부다 —
/// 창(올해)·숨김·타이브레이크 세 축을 각각 밟는다. 셋 다 실제로 어긋나 있던 축이라
/// (`seasonRecap` 회귀 테스트가 같은 파일 아래에 있다) 통과만 보는 테스트를 두지 않는다.
@MainActor
final class MemoryHomeYearRecapTests: XCTestCase {
    private func makeAlbum() -> PokemonMemoryAlbum {
        PokemonMemoryAlbum(fileURL: memoryAlbumURL("year-recap"))
    }

    /// `dayKey` 와 같은 달력을 쓴다 — 테스트가 다른 달력으로 날짜를 만들면 경계 하루가 어긋난다.
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        SeasonBoard.gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testCountsOnlyThisYearsMemories() {
        let album = makeAlbum(); let id = UUID()
        album.record(companionID: id, body: "last year", source: .event, createdAt: date(2025, 6, 1))
        album.record(companionID: id, body: "this year", source: .event, createdAt: date(2026, 1, 2))
        album.record(companionID: id, body: "this year too", source: .event, createdAt: date(2026, 8, 9))

        let recap = album.yearRecap(for: [id], now: date(2026, 12, 31))
        XCTAssertEqual(recap.year, 2026)
        XCTAssertEqual(recap.memoryCount, 2, "지난해 기억이 올해 결산에 섞였다")
    }

    /// 숨긴 기억은 사용자가 화면에서 내린 것이다. 결산이 되살리면 숨김이 숨김이 아니게 된다
    /// (`timeline`·`diary`·날짜 카드가 전부 같은 필터를 쓴다).
    func testExcludesHiddenMemories() {
        let album = makeAlbum(); let id = UUID()
        album.record(companionID: id, body: "visible", source: .event, createdAt: date(2026, 3, 3))
        album.record(companionID: id, body: "hidden", source: .event, createdAt: date(2026, 3, 4))
        let hidden = album.entries(for: id).first { $0.body == "hidden" }!
        XCTAssertTrue(album.setHidden(hidden, isHidden: true))

        let recap = album.yearRecap(for: [id], now: date(2026, 12, 31))
        XCTAssertEqual(recap.memoryCount, 1, "숨긴 기억이 결산에 셌다")
        XCTAssertEqual(recap.topCompanionDays, 1, "숨긴 기억의 날이 함께한 날로 셌다")
    }

    /// 기획서는 "가장 많은 시간을 함께한 친구" 라고 했다 — 기억 **개수**가 아니라 **날 수**다.
    /// B 가 하루에 기억 5개를 남겨도, 3일에 걸쳐 3개를 남긴 A 가 이긴다.
    func testTopCompanionIsMeasuredInDaysNotMemoryCount() {
        let album = makeAlbum(); let a = UUID(); let b = UUID()
        for day in 1...3 { album.record(companionID: a, body: "a\(day)", source: .event, createdAt: date(2026, 4, day)) }
        for index in 1...5 { album.record(companionID: b, body: "b\(index)", source: .event, createdAt: date(2026, 4, 10, hour: index)) }

        let recap = album.yearRecap(for: [a, b], now: date(2026, 12, 31))
        XCTAssertEqual(recap.topCompanionID, a, "기억 개수가 많은 쪽을 골랐다 — 기준은 함께한 날 수다")
        XCTAssertEqual(recap.topCompanionDays, 3)
    }

    /// 동률에서 사전 순으로 고정한다. `max(by:)` 를 딕셔너리에 그냥 걸면 순회 순서가 시드에 따라
    /// 달라져, 같은 세이브를 열 때마다 "올해의 친구" 가 바뀐다.
    func testTopCompanionTieBreakIsStableAcrossCalls() {
        let album = makeAlbum()
        let ids = (0..<8).map { _ in UUID() }
        for id in ids { album.record(companionID: id, body: "same", source: .event, createdAt: date(2026, 5, 5)) }

        let first = album.yearRecap(for: ids, now: date(2026, 12, 31)).topCompanionID
        XCTAssertEqual(first, ids.min { $0.uuidString < $1.uuidString }, "동률 타이브레이크가 사전 순이 아니다")
        for _ in 0..<20 {
            XCTAssertEqual(album.yearRecap(for: ids.shuffled(), now: date(2026, 12, 31)).topCompanionID, first,
                           "입력 순서가 바뀌자 올해의 친구가 바뀌었다")
        }
    }

    func testCountsFirstMeetingsAndPhotosInsideTheYearOnly() {
        let album = makeAlbum(); let a = UUID(); let b = UUID()
        album.recordFirstMeeting(companionID: a, at: date(2025, 11, 1))
        album.recordFirstMeeting(companionID: b, at: date(2026, 2, 2))
        album.addPhoto(.init(createdAt: date(2025, 12, 1), speciesID: 25, isShiny: false, caption: "old",
                             frame: "heart", background: "sunset", composition: "together", trainerStyle: "trainer"))
        album.addPhoto(.init(createdAt: date(2026, 7, 7), speciesID: 25, isShiny: false, caption: "new",
                             frame: "heart", background: "sunset", composition: "together", trainerStyle: "trainer"))

        let recap = album.yearRecap(for: [a, b], now: date(2026, 12, 31))
        XCTAssertEqual(recap.companionsMet, 1, "지난해 만난 동행이 올해 만남으로 셌다")
        XCTAssertEqual(recap.photoCount, 1, "지난해 사진이 올해 사진으로 셌다")
    }

    /// 설치 첫날에도 화면이 깨지지 않아야 한다 — 0건이 정상 상태다.
    func testEmptyAlbumYieldsZeroedRecapWithNoTopCompanion() {
        let recap = makeAlbum().yearRecap(for: [], now: date(2026, 12, 31))
        XCTAssertEqual(recap.memoryCount, 0)
        XCTAssertEqual(recap.companionsMet, 0)
        XCTAssertEqual(recap.photoCount, 0)
        XCTAssertEqual(recap.topCompanionDays, 0)
        XCTAssertNil(recap.topCompanionID)
    }

    // MARK: - `seasonRecap` 회귀 — 연말 결산과 같은 부류의 결함이 계절 결산에 있었다

    func testSeasonRecapExcludesHiddenMemories() {
        let album = makeAlbum(); let id = UUID(); let now = date(2026, 7, 15)
        album.record(companionID: id, body: "visible", source: .event, createdAt: now)
        album.record(companionID: id, body: "hidden", source: .event, createdAt: now)
        let hidden = album.entries(for: id).first { $0.body == "hidden" }!
        XCTAssertTrue(album.setHidden(hidden, isHidden: true))

        XCTAssertEqual(album.seasonRecap(for: [id], now: now).memoryCount, 1, "숨긴 기억이 계절 결산에 셌다")
    }

    func testSeasonRecapMoodTieBreakIsStableAcrossCalls() {
        let album = makeAlbum(); let now = date(2026, 7, 20)
        // 같은 횟수(각 1회)로 다섯 기분을 전부 채워 동률을 강제한다.
        for (offset, mood) in MemoryHomeMood.allCases.enumerated() {
            album.setMood(mood, now: date(2026, 7, 1 + offset))
        }
        let first = album.seasonRecap(for: [], now: now).mostChosenMood
        XCTAssertEqual(first, MemoryHomeMood.allCases.min { $0.rawValue < $1.rawValue },
                       "동률 타이브레이크가 rawValue 사전 순이 아니다")
        for _ in 0..<20 {
            XCTAssertEqual(album.seasonRecap(for: [], now: now).mostChosenMood, first,
                           "같은 입력에서 가장 많이 고른 기분이 호출마다 바뀌었다")
        }
    }

    /// 동률이 아닐 때는 최다 기분이 그대로 이긴다 — 타이브레이크가 승자를 덮어쓰면 안 된다.
    func testSeasonRecapMoodPicksTheActualWinnerWhenNotTied() {
        let album = makeAlbum(); let now = date(2026, 7, 20)
        // `down` 3일, `excited` 1일. `down` 이 rawValue 사전 순으로는 지지만 횟수로는 이긴다.
        for day in 1...3 { album.setMood(.down, now: date(2026, 7, day)) }
        album.setMood(.excited, now: date(2026, 7, 10))
        XCTAssertEqual(album.seasonRecap(for: [], now: now).mostChosenMood, .down,
                       "타이브레이크가 실제 최다 기분을 덮어썼다")
    }
}
