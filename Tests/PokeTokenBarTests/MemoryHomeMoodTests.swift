import XCTest
@testable import PokeTokenBar

@MainActor
final class MemoryHomeMoodTests: XCTestCase {
    private func temporaryURL() -> URL {
        storeStateURL("memory-home-mood")
    }
    private let noon = Date(timeIntervalSince1970: 1_787_000_400)

    func testMoodIsOnePerDayAndOverwritesTheSameDay() {
        let url = temporaryURL()
        let album = PokemonMemoryAlbum(fileURL: url)
        XCTAssertNil(album.mood(on: noon))

        album.setMood(.down, now: noon)
        XCTAssertEqual(album.mood(on: noon), .down)

        // 같은 날 다시 고르면 덮어쓴다 — 하루에 두 개가 쌓이면 "오늘 기분"이 아니다.
        album.setMood(.fluttering, now: noon.addingTimeInterval(3_600))
        XCTAssertEqual(album.mood(on: noon), .fluttering)
        XCTAssertEqual(album.memoryHomeAccess.moodByDayKey.count, 1)

        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).mood(on: noon), .fluttering)
    }

    /// 같은 기분을 다시 고르면 쓰기를 건너뛴다 — `--show-regions` 에서 `^0` 이던 분기.
    func testRepickingTheSameMoodIsANoOp() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        album.setMood(.annoyed, now: noon)
        album.setMood(.annoyed, now: noon.addingTimeInterval(120))
        XCTAssertEqual(album.mood(on: noon), .annoyed)
        XCTAssertEqual(album.memoryHomeAccess.moodByDayKey.count, 1)
    }

    func testMoodIsScopedToItsOwnDay() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        album.setMood(.excited, now: noon)
        let nextDay = noon.addingTimeInterval(86_400)
        XCTAssertNil(album.mood(on: nextDay), "어제 기분이 오늘로 새어 나왔다")
        album.setMood(.calm, now: nextDay)
        XCTAssertEqual(album.mood(on: noon), .excited)
        XCTAssertEqual(album.mood(on: nextDay), .calm)
    }

    func testHistoryIsCappedKeepingTheNewestDays() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let limit = MemoryHomeAccessSettings.moodHistoryLimit
        // 상한 + 5일치를 하루 간격으로 채운다.
        for day in 0..<(limit + 5) {
            album.setMood(MemoryHomeMood.allCases[day % MemoryHomeMood.allCases.count],
                          now: noon.addingTimeInterval(Double(day) * 86_400))
        }
        XCTAssertEqual(album.memoryHomeAccess.moodByDayKey.count, limit)
        // 최신 쪽이 남아야 한다: dayKey 문자열 정렬이 곧 시간순이라는 전제를 여기서 검증한다.
        XCTAssertNotNil(album.mood(on: noon.addingTimeInterval(Double(limit + 4) * 86_400)),
                        "가장 최근 날짜가 잘려 나갔다")
        XCTAssertNil(album.mood(on: noon), "가장 오래된 날짜가 남았다")
    }

    func testTamperedDayKeysAreDroppedOnLoad() throws {
        let url = temporaryURL()
        var access = MemoryHomeAccessSettings()
        access.moodByDayKey = ["2026-08-28": .excited, "garbage": .down, "2026-8-1": .calm]
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:], memoryHomeAccess: access)
        try JSONEncoder().encode(snapshot).write(to: url)

        let album = PokemonMemoryAlbum(fileURL: url)
        XCTAssertEqual(album.memoryHomeAccess.moodByDayKey, ["2026-08-28": .excited],
                       "형식이 깨진 dayKey 가 살아남았다")
    }

    func testEveryMoodHasEmojiNameAndReactionInAllThreeLanguages() {
        for language in [AppLanguage.ko, .en, .ja] {
            let l = L(language)
            for mood in MemoryHomeMood.allCases {
                XCTAssertFalse(MemoryHomeMoodStyle.emoji(mood).isEmpty, "\(mood) 이모지 없음")
                XCTAssertFalse(MemoryHomeMoodStyle.name(mood, l).isEmpty, "\(language)/\(mood) 이름 없음")
                let reaction = MemoryHomeMoodStyle.reaction(mood, companion: "피카츄", l)
                XCTAssertFalse(reaction.isEmpty, "\(language)/\(mood) 반응 없음")
                XCTAssertTrue(reaction.contains("피카츄"), "\(language)/\(mood) 반응에 동행 이름이 안 들어갔다")
            }
        }
    }

    func testMoodNamesAreDistinctWithinEachLanguage() {
        for language in [AppLanguage.ko, .en, .ja] {
            let l = L(language)
            let names = Set(MemoryHomeMood.allCases.map { MemoryHomeMoodStyle.name($0, l) })
            XCTAssertEqual(names.count, MemoryHomeMood.allCases.count,
                           "\(language) 기분 이름이 중복돼 접근성 라벨이 구별되지 않는다")
            let emoji = Set(MemoryHomeMood.allCases.map { MemoryHomeMoodStyle.emoji($0) })
            XCTAssertEqual(emoji.count, MemoryHomeMood.allCases.count, "기분 이모지가 중복됐다")
        }
    }
}
