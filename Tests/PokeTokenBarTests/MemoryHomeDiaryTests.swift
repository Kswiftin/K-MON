import XCTest
@testable import PokeTokenBar

/// R5 DIARY — 이미 쌓여 있는 기억을 **날짜로 묶어** 보여 주는 파생 뷰의 계약.
///
/// 저장 필드를 하나도 더하지 않는다. 그래서 이 테스트가 지키는 건 "무엇이 저장됐나" 가 아니라
/// "무엇이 어떻게 묶여 나오나" 다 — 하루 경계, 정렬, 숨김, 기분 결합, 동행 격리.
@MainActor
final class MemoryHomeDiaryTests: XCTestCase {
    private func temporaryURL() -> URL {
        storeStateURL("memory-home-diary")
    }

    /// 고정 타임스탬프가 아니라 **로컬 달력의 자정**에서 출발한다. `dayKey` 가 로컬 달력 기준이라
    /// `Date(timeIntervalSince1970:)` 을 하드코딩하면 게이트의 영어 로케일 재실행이나 다른
    /// 타임존의 CI 러너에서 날짜가 하루 밀린다(#107 과 같은 부류).
    private var midnight: Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
    }

    /// 이벤트 기억만 `createdAt` 을 주입할 수 있다 — `addManual` 은 내부에서 `Date()` 를 쓴다.
    private func record(_ album: PokemonMemoryAlbum, _ companion: UUID,
                        _ body: String, at date: Date) {
        album.record(companionID: companion, body: body, source: .event,
                     eventID: "e-\(body)", createdAt: date)
    }

    // MARK: - 하루 단위 묶음

    func testMemoriesOnTheSameLocalDayCollapseIntoOneEntry() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        record(album, companion, "morning", at: midnight.addingTimeInterval(9 * 3600))
        record(album, companion, "evening", at: midnight.addingTimeInterval(21 * 3600))

        let diary = album.diary(for: companion)

        XCTAssertEqual(diary.count, 1, "같은 로컬 날짜의 기억 둘은 한 묶음이어야 한다")
        XCTAssertEqual(diary.first?.memories.count, 2)
        XCTAssertEqual(diary.first?.dayKey, CompanionStore.dayKey(midnight))
    }

    /// 자정을 60초 사이에 두고 갈린다. `Date` 산술로 하루를 계산하면 타임존 변경·DST 경계에서
    /// 어긋나므로 `dayKey` 문자열 비교만 써야 한다 — R4 방문 카운터와 같은 이유.
    func testMidnightSplitsTwoMemoriesIntoSeparateDays() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        record(album, companion, "late", at: midnight.addingTimeInterval(-60))
        record(album, companion, "early", at: midnight.addingTimeInterval(60))

        let diary = album.diary(for: companion)

        XCTAssertEqual(diary.count, 2, "자정을 사이에 둔 기억 둘은 다른 날이어야 한다")
        XCTAssertEqual(diary.map(\.memories.count), [1, 1])
    }

    func testDaysAreNewestFirstAndSoAreMemoriesWithinADay() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        record(album, companion, "older-day", at: midnight.addingTimeInterval(-24 * 3600))
        record(album, companion, "first", at: midnight.addingTimeInterval(3600))
        record(album, companion, "second", at: midnight.addingTimeInterval(7200))

        let diary = album.diary(for: companion)

        XCTAssertEqual(diary.count, 2)
        XCTAssertEqual(diary.first?.memories.map(\.body), ["second", "first"],
                       "하루 안에서도 최신이 먼저여야 한다")
        XCTAssertEqual(diary.last?.memories.map(\.body), ["older-day"])
        XCTAssertGreaterThan(diary[0].dayKey, diary[1].dayKey, "날짜는 최신이 먼저여야 한다")
    }

    /// 묶음의 `date` 는 화면 날짜 헤더의 로케일 포맷에 쓰인다 — 그날 **가장 최신** 기억 시각이다.
    func testDayDateIsTheNewestMemoryOfThatDay() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        let newest = midnight.addingTimeInterval(20 * 3600)
        record(album, companion, "early", at: midnight.addingTimeInterval(3600))
        record(album, companion, "newest", at: newest)

        XCTAssertEqual(album.diary(for: companion).first?.date, newest)
    }

    // MARK: - 숨김·격리

    func testHiddenMemoriesNeverAppearInTheDiary() throws {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        record(album, companion, "visible", at: midnight.addingTimeInterval(3600))
        record(album, companion, "hidden", at: midnight.addingTimeInterval(7200))
        let hidden = try XCTUnwrap(album.entries(for: companion).first { $0.body == "hidden" })
        XCTAssertTrue(album.setHidden(hidden, isHidden: true))

        let diary = album.diary(for: companion)

        XCTAssertEqual(diary.first?.memories.map(\.body), ["visible"])
    }

    /// 숨긴 기억뿐인 날은 **행 자체가 없어야** 한다 — 빈 일기 껍데기가 남으면 안 된다.
    func testADayOfOnlyHiddenMemoriesProducesNoEntry() throws {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        record(album, companion, "hidden", at: midnight.addingTimeInterval(3600))
        let hidden = try XCTUnwrap(album.entries(for: companion).first)
        XCTAssertTrue(album.setHidden(hidden, isHidden: true))

        XCTAssertTrue(album.diary(for: companion).isEmpty)
    }

    func testAnotherCompanionsMemoriesNeverLeakIntoTheDiary() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let mine = UUID(), theirs = UUID()
        record(album, mine, "mine", at: midnight.addingTimeInterval(3600))
        record(album, theirs, "theirs", at: midnight.addingTimeInterval(3600))

        XCTAssertEqual(album.diary(for: mine).flatMap(\.memories).map(\.body), ["mine"])
        XCTAssertEqual(album.diary(for: theirs).flatMap(\.memories).map(\.body), ["theirs"])
    }

    // MARK: - 기분 결합

    func testTheDaysMoodIsAttachedToThatDayAlone() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        record(album, companion, "yesterday", at: midnight.addingTimeInterval(-12 * 3600))
        record(album, companion, "today", at: midnight.addingTimeInterval(3600))
        album.setMood(.fluttering, now: midnight.addingTimeInterval(3600))

        let diary = album.diary(for: companion)

        XCTAssertEqual(diary.count, 2)
        XCTAssertEqual(diary.first?.mood, .fluttering, "기분을 고른 날에 붙어야 한다")
        XCTAssertNil(diary.last?.mood, "기분은 고른 그 날에만 붙어야 한다")
    }

    /// 기분은 60일치, 기억은 200개 캡이다. 기분 단독 행을 만들면 기억이 잘려 나간 옛날이
    /// "기분만 있는 빈 일기" 로 남는다 — 그래서 기억 없는 날은 행을 만들지 않는다.
    func testADayWithOnlyAMoodProducesNoEntry() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        album.setMood(.down, now: midnight.addingTimeInterval(3600))

        XCTAssertTrue(album.diary(for: companion).isEmpty)
    }

    func testDiaryIsEmptyForACompanionWithNoMemories() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())

        XCTAssertTrue(album.diary(for: UUID()).isEmpty)
    }

    // MARK: - 지속성

    func testDiarySurvivesAReloadFromDisk() {
        let url = temporaryURL()
        let companion = UUID()
        do {
            let album = PokemonMemoryAlbum(fileURL: url)
            record(album, companion, "kept", at: midnight.addingTimeInterval(3600))
            album.setMood(.calm, now: midnight.addingTimeInterval(3600))
        }

        let reloaded = PokemonMemoryAlbum(fileURL: url).diary(for: companion)

        XCTAssertEqual(reloaded.first?.memories.map(\.body), ["kept"])
        XCTAssertEqual(reloaded.first?.mood, .calm)
    }
}
