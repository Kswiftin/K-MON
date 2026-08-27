import XCTest
@testable import PokeTokenBar

/// R5 계절 미니룸 — 달력 월에서 **파생**되는 계절. 저장 필드가 없다.
///
/// 이름에 "시즌" 을 쓰지 않는 것도 계약이다: `SeasonBoard`·`SeasonChallenge`·`seasonKey` 가
/// 월간 순환 챌린지로 그 어휘를 이미 점유했다. 여기 이름이 흐려지면 두 시스템이 같은 말로 불린다.
@MainActor
final class MemoryHomeSeasonTests: XCTestCase {
    /// 월을 직접 만들어 넣는다 — `Date()` 를 쓰면 테스트가 실행한 달에만 통과한다.
    private func date(month: Int) throws -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = 15
        components.hour = 12
        return try XCTUnwrap(Calendar.current.date(from: components))
    }

    func testEveryMonthMapsToItsNorthernHemisphereSeason() throws {
        let expected: [Int: MemoryHomeSeason] = [
            1: .winter, 2: .winter, 3: .spring, 4: .spring, 5: .spring, 6: .summer,
            7: .summer, 8: .summer, 9: .autumn, 10: .autumn, 11: .autumn, 12: .winter,
        ]
        for month in 1...12 {
            XCTAssertEqual(MemoryHomeSeason.current(try date(month: month)), expected[month],
                           "\(month)월의 계절이 어긋났다")
        }
    }

    /// 12월과 1월이 같은 겨울이어야 한다 — 연말연시 경계에서 방이 색을 바꾸면 안 된다.
    func testDecemberAndJanuaryShareTheSameWinter() throws {
        XCTAssertEqual(MemoryHomeSeason.current(try date(month: 12)),
                       MemoryHomeSeason.current(try date(month: 1)))
    }

    func testEveryMonthResolvesToSomeSeason() throws {
        var seen: Set<MemoryHomeSeason> = []
        for month in 1...12 { seen.insert(MemoryHomeSeason.current(try date(month: month))) }
        XCTAssertEqual(seen, Set(MemoryHomeSeason.allCases),
                       "네 계절이 모두 어떤 달에는 나와야 한다")
    }

    // MARK: - 3개 언어

    /// 뷰 안 `private` 함수였다면 이 검증이 아예 불가능하다 — `MemoryHomeMoodStyle` 과 같은 이유로
    /// 파일 스코프에 둔다. 호스트 로케일과 무관하게 `L` 을 직접 만들어 세 언어를 모두 밟는다.
    func testEachSeasonHasAllThreeLanguageNames() {
        for season in MemoryHomeSeason.allCases {
            let ko = MemoryHomeSeasonStyle.name(season, L(.ko))
            let en = MemoryHomeSeasonStyle.name(season, L(.en))
            let ja = MemoryHomeSeasonStyle.name(season, L(.ja))
            XCTAssertFalse(ko.isEmpty, "\(season) 한국어 이름이 비었다")
            XCTAssertFalse(en.isEmpty, "\(season) 영어 이름이 비었다")
            XCTAssertFalse(ja.isEmpty, "\(season) 일본어 이름이 비었다")
            XCTAssertNotEqual(ko, en, "\(season) 한국어가 영어로 새어 나갔다")
        }
    }

    func testSeasonNamesAreDistinctWithinALanguage() {
        for language in [AppLanguage.ko, .en, .ja] {
            let names = MemoryHomeSeason.allCases.map { MemoryHomeSeasonStyle.name($0, L(language)) }
            XCTAssertEqual(Set(names).count, MemoryHomeSeason.allCases.count,
                           "\(language) 에서 두 계절이 같은 이름이다")
        }
    }

    func testEachSeasonHasItsOwnSymbol() {
        let symbols = MemoryHomeSeason.allCases.map(MemoryHomeSeasonStyle.symbol)
        XCTAssertEqual(Set(symbols).count, MemoryHomeSeason.allCases.count,
                       "두 계절이 같은 심볼을 쓴다")
        XCTAssertFalse(symbols.contains(where: \.isEmpty))
    }
}
