import XCTest
@testable import PokeTokenBar

/// §18 추억 카드 중 **날짜가 만드는** 두 장 — 함께한 첫 겨울, 크리스마스.
///
/// 기존 카드 6종은 전부 "적립"(N일·N회·진화) 계열이라 달력이 만드는 순간이 하나도 없었다.
/// 이 두 장은 저장 필드를 더하지 않고 이미 있는 `PokemonMemory.createdAt` 만 읽는다.
@MainActor
final class MemoryHomeDateCardTests: XCTestCase {
    private func temporaryURL() -> URL {
        storeStateURL("datecard")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// 달·해를 넘는 날짜를 손으로 세지 않는다 — `12/28 + 6일` 을 사람이 계산하면 그 자체가
    /// 이 테스트가 잡으려는 부류의 실수가 된다.
    private func day(_ year: Int, _ month: Int, _ start: Int, plus offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: date(year, month, start))!
    }

    /// 겨울 기억이 하나 있으면 첫 겨울 카드가 그 **가장 이른** 날짜로 뜬다.
    func testFirstWinterCardUsesTheEarliestWinterMemory() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        album.record(companionID: companion, body: "겨울 산책", source: .event, createdAt: date(2026, 12, 20))
        album.record(companionID: companion, body: "더 늦은 겨울", source: .event, createdAt: date(2027, 1, 8))

        let card = album.milestones(for: companion, now: date(2027, 3, 1)).first { $0.id == "first-winter" }
        XCTAssertEqual(card?.kind, .firstWinter)
        XCTAssertEqual(card?.occurredAt, date(2026, 12, 20), "더 늦은 겨울 기억이 카드 날짜를 덮었다")
    }

    /// 겨울은 12·1·2 로 **연말을 가로지른다**. 1월·2월만 검증하면 12월 가지가, 12월만 검증하면
    /// 1·2월 가지가 무테스트로 남는다 — `MemoryHomeSeason` 의 `default` 가 이 셋을 함께 받는다.
    func testEveryWinterMonthTriggersTheCard() {
        for (year, month) in [(2026, 12), (2027, 1), (2027, 2)] {
            let album = PokemonMemoryAlbum(fileURL: temporaryURL())
            let companion = UUID()
            album.record(companionID: companion, body: "겨울", source: .event,
                         createdAt: date(year, month, 10))
            XCTAssertTrue(album.milestones(for: companion, now: date(2027, 6, 1))
                .contains { $0.id == "first-winter" }, "\(month)월이 겨울로 안 세어졌다")
        }
    }

    /// 봄·여름·가을 기억만 있으면 겨울 카드는 없다. 이 가지를 안 밟으면 "항상 뜨는" 구현도 통과한다.
    func testNonWinterMemoriesProduceNoWinterCard() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        for month in [3, 6, 9, 11] {
            album.record(companionID: companion, body: "그 계절", source: .event,
                         createdAt: date(2026, month, 15))
        }
        let ids = album.milestones(for: companion, now: date(2026, 12, 1)).map(\.id)
        XCTAssertFalse(ids.contains("first-winter"))
        XCTAssertFalse(ids.contains("christmas"))
    }

    /// 12/25 하루만 크리스마스다. 12/24·12/26 에서 뜨면 카드가 의미를 잃는다.
    func testChristmasCardIsExactlyDecember25() {
        for day in [24, 25, 26] {
            let album = PokemonMemoryAlbum(fileURL: temporaryURL())
            let companion = UUID()
            album.record(companionID: companion, body: "12월 \(day)일", source: .event,
                         createdAt: date(2026, 12, day))
            let hasCard = album.milestones(for: companion, now: date(2027, 1, 1))
                .contains { $0.id == "christmas" }
            XCTAssertEqual(hasCard, day == 25, "12/\(day) 에서 크리스마스 카드 판정이 틀렸다")
        }
    }

    /// 숨긴 기억은 카드를 만들지 않는다 — 사용자가 화면에서 지운 날이 카드로 되살아나면
    /// 숨김이 숨김이 아니게 된다.
    func testHiddenMemoryDoesNotUnlockADateCard() throws {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        album.record(companionID: companion, body: "크리스마스", source: .event, createdAt: date(2026, 12, 25))
        let memory = try XCTUnwrap(album.entries(for: companion).first)
        XCTAssertTrue(album.setHidden(memory, isHidden: true))

        let ids = album.milestones(for: companion, now: date(2027, 1, 1)).map(\.id)
        XCTAssertFalse(ids.contains("christmas"))
        XCTAssertFalse(ids.contains("first-winter"))
    }

    /// 카드는 여전히 날짜순으로 정렬돼야 한다 — 새 카드를 배열 끝에 붙이고 정렬을 잊으면
    /// 화면의 카드 줄이 뒤엉킨다.
    func testDateCardsStaySortedAmongTheExistingCards() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        album.recordFirstMeeting(companionID: companion, at: date(2026, 11, 1))
        album.record(companionID: companion, body: "첫 겨울", source: .event, createdAt: date(2026, 12, 3))
        album.record(companionID: companion, body: "크리스마스", source: .event, createdAt: date(2026, 12, 25))

        // 첫 만남 11/01 → together-30 은 12/01 이고, 첫 겨울 **기억**은 12/03 이다.
        // 즉 새 카드가 기존 카드 사이에 끼어야 맞다 — 끝에 붙는 구현이면 이 순서가 깨진다.
        let ids = album.milestones(for: companion, now: date(2027, 2, 1)).map(\.id)
        XCTAssertEqual(ids, ["first-meeting", "together-30", "first-winter", "christmas"])
    }

    // MARK: - 새해

    /// 1/1 하루만 새해다. 12/31·1/2 에서 뜨면 카드가 의미를 잃는다 — 크리스마스와 같은 계약이고,
    /// **연말·연초를 가로지르는** 날짜라 판정이 틀리면 하루씩 밀린다.
    func testNewYearCardIsExactlyJanuary1() {
        for (year, month, day) in [(2026, 12, 31), (2027, 1, 1), (2027, 1, 2)] {
            let album = PokemonMemoryAlbum(fileURL: temporaryURL())
            let companion = UUID()
            album.record(companionID: companion, body: "\(month)/\(day)", source: .event,
                         createdAt: date(year, month, day))
            let hasCard = album.milestones(for: companion, now: date(2027, 6, 1))
                .contains { $0.id == "new-year" }
            XCTAssertEqual(hasCard, month == 1 && day == 1, "\(year)/\(month)/\(day) 판정이 틀렸다")
        }
    }

    // MARK: - 사계절

    /// 카드 날짜는 **네 번째 계절을 채운 그 기억**의 날짜다. 오늘 날짜를 쓰면 옛 기억 사이에
    /// 미래 카드가 끼어 정렬이 뒤엉킨다.
    func testAllSeasonsCardUsesTheMemoryThatCompletedTheSet() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        album.record(companionID: companion, body: "봄", source: .event, createdAt: date(2026, 4, 1))
        album.record(companionID: companion, body: "여름", source: .event, createdAt: date(2026, 7, 1))
        album.record(companionID: companion, body: "가을", source: .event, createdAt: date(2026, 10, 1))
        album.record(companionID: companion, body: "겨울", source: .event, createdAt: date(2026, 12, 5))
        album.record(companionID: companion, body: "또 겨울", source: .event, createdAt: date(2027, 1, 9))

        let card = album.milestones(for: companion, now: date(2027, 6, 1)).first { $0.id == "all-seasons" }
        XCTAssertEqual(card?.kind, .allFourSeasons)
        XCTAssertEqual(card?.occurredAt, date(2026, 12, 5), "네 번째 계절을 채운 날이 아니다")
    }

    /// 세 계절만으로는 뜨지 않는다. 이 가지를 안 밟으면 "항상 뜨는" 구현도 통과한다.
    func testThreeSeasonsAreNotEnough() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        for month in [4, 7, 10] {
            album.record(companionID: companion, body: "\(month)월", source: .event, createdAt: date(2026, month, 1))
        }
        XCTAssertFalse(album.milestones(for: companion, now: date(2027, 6, 1))
            .contains { $0.id == "all-seasons" })
    }

    // MARK: - 연속 기록

    /// 연속은 **총량이 아니다.** 같은 7개라도 흩어져 있으면 카드가 없어야 한다 — 이 두 케이스를
    /// 나란히 보지 않으면 `count >= 7` 로 세는 구현이 그대로 통과한다.
    func testStreakCountsConsecutiveDaysNotTotalMemories() {
        let consecutive = PokemonMemoryAlbum(fileURL: temporaryURL())
        let a = UUID()
        for offset in 0..<7 {
            consecutive.record(companionID: a, body: "연속 \(offset)", source: .event,
                               createdAt: day(2026, 5, 4, plus: offset))
        }
        XCTAssertTrue(consecutive.milestones(for: a, now: date(2026, 6, 1)).contains { $0.id == "streak-7" })

        let scattered = PokemonMemoryAlbum(fileURL: temporaryURL())
        let b = UUID()
        for offset in 0..<7 {
            scattered.record(companionID: b, body: "띄엄 \(offset)", source: .event,
                             createdAt: day(2026, 5, 4, plus: offset * 2))
        }
        XCTAssertFalse(scattered.milestones(for: b, now: date(2026, 6, 1)).contains { $0.id == "streak-7" },
                       "하루 걸러 남긴 7개가 연속 7일로 세어졌다")
    }

    /// 하루에 여러 개를 남겨도 하루다. 접지 않으면 한 시간 동안 7개를 적는 것으로 카드가 열린다.
    func testManyMemoriesInOneDayAreStillOneDay() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        for index in 0..<10 {
            album.record(companionID: companion, body: "같은 날 \(index)", source: .event,
                         createdAt: Calendar.current.date(byAdding: .minute, value: index * 5, to: date(2026, 5, 4))!)
        }
        XCTAssertFalse(album.milestones(for: companion, now: date(2026, 6, 1)).contains { $0.id == "streak-7" })
    }

    /// 연속이 **연말을 가로지른다**. 12/28~1/3 은 7일이다 — 연·월이 바뀌면 끊긴다고 보는 구현
    /// (예: 일(day) 숫자만 비교)이 정확히 여기서 걸린다.
    func testStreakSpansTheYearBoundary() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        for offset in 0..<7 {
            album.record(companionID: companion, body: "연말 \(offset)", source: .event,
                         createdAt: day(2026, 12, 28, plus: offset))
        }
        let card = album.milestones(for: companion, now: date(2027, 3, 1)).first { $0.id == "streak-7" }
        XCTAssertEqual(card?.kind, .memoryStreak(7))
        XCTAssertEqual(card?.occurredAt, day(2026, 12, 28, plus: 6), "7일째는 1/3 이다")
    }

    /// **숨긴 기억은 연속을 잇지 않는다.** 가운데 하루를 숨기면 7일이 3일+3일로 갈라져야 한다.
    /// 이것이 `seasonRecap.memoryCount` 가 숨긴 기억을 세던 결함과 같은 부류다 — 파생 통계가
    /// 라벨과 어긋나는 쪽.
    func testHiddenMemoryBreaksTheStreak() throws {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let companion = UUID()
        for offset in 0..<7 {
            album.record(companionID: companion, body: "연속 \(offset)", source: .event,
                         createdAt: day(2026, 5, 4, plus: offset))
        }
        XCTAssertTrue(album.milestones(for: companion, now: date(2026, 6, 1)).contains { $0.id == "streak-7" })

        let middle = try XCTUnwrap(album.entries(for: companion)
            .first { CompanionStore.dayKey($0.createdAt) == CompanionStore.dayKey(day(2026, 5, 4, plus: 3)) })
        XCTAssertTrue(album.setHidden(middle, isHidden: true))

        XCTAssertFalse(album.milestones(for: companion, now: date(2026, 6, 1)).contains { $0.id == "streak-7" },
                       "숨긴 하루가 연속을 계속 이어 주고 있다")
    }

    /// 새 `Kind` 케이스에 아이콘·세 언어 제목이 붙어 있어야 한다. `switch` 는 컴파일러가
    /// 강제하지만 **빈 문자열**은 강제하지 못한다.
    func testDateCardKindsHaveIconAndTitleInAllThreeLanguages() {
        for kind in [PokemonMemoryMilestone.Kind.firstWinter, .christmas,
                     .newYear, .allFourSeasons, .memoryStreak(7)] {
            let milestone = PokemonMemoryMilestone(id: "x", kind: kind, occurredAt: Date())
            XCTAssertFalse(MemoryHomeCardStyle.icon(milestone).isEmpty)
            let titles = [AppLanguage.ko, .en, .ja].map { MemoryHomeCardStyle.title(milestone, L($0)) }
            XCTAssertEqual(Set(titles).count, 3, "\(kind): 세 언어 제목이 서로 달라야 한다")
            XCTAssertFalse(titles.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }
}
