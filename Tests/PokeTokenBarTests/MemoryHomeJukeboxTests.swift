import XCTest
@testable import PokeTokenBar

/// §11 주크박스. 해금이 이 기능의 전부이므로 테스트도 해금 경계를 본다.
@MainActor
final class MemoryHomeJukeboxTests: XCTestCase {
    private func memory(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> PokemonMemory {
        let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day,
                                                             hour: hour))!
        return PokemonMemory(companionID: UUID(), createdAt: date, source: .event, body: "기억")
    }

    /// 새 세이브에서 고를 수 있는 곡이 정확히 하나여야 한다 — 0개면 고장으로 보이고,
    /// 전부 열려 있으면 해금이라는 개념이 없다.
    func testFreshSaveUnlocksOnlyTheDefaultTrack() {
        let unlocked = MemoryHomeJukeboxTrack.allCases.filter {
            MemoryHomeJukebox.isUnlocked($0, memories: [], focusSessions: 0)
        }
        XCTAssertEqual(unlocked, [MemoryHomeJukebox.defaultTrack])
    }

    /// 집중 10회 **경계 그 자체**를 밟는다. 9와 10을 함께 보지 않으면 `>=` 를 `>` 로 적은
    /// 실수가 통과한다.
    func testRainyWalkNeedsExactlyTenFocusSessions() {
        XCTAssertFalse(MemoryHomeJukebox.isUnlocked(.rainyWalk, memories: [], focusSessions: 9))
        XCTAssertTrue(MemoryHomeJukebox.isUnlocked(.rainyWalk, memories: [], focusSessions: 10))
    }

    /// 여름(6·7·8)만 여름이다. 5월·9월이 통과하면 계절 판정을 안 쓰고 있는 것이다.
    func testSummerRiverNeedsASummerMemory() {
        for month in [6, 7, 8] {
            XCTAssertTrue(MemoryHomeJukebox.isUnlocked(.summerRiver, memories: [memory(2026, month, 15)],
                                                       focusSessions: 0), "\(month)월이 여름이 아니다")
        }
        for month in [5, 9, 12] {
            XCTAssertFalse(MemoryHomeJukebox.isUnlocked(.summerRiver, memories: [memory(2026, month, 15)],
                                                        focusSessions: 0), "\(month)월이 여름으로 셌다")
        }
    }

    /// 밤은 자정을 가로지른다. 22시와 3시가 **둘 다** 밤이어야 하고, 21시·4시는 아니어야 한다.
    /// 한쪽만 검증하면 `hour >= 22 && hour < 4`(항상 false) 같은 실수를 못 잡는다.
    func testNightWindowCrossesMidnight() {
        for hour in [22, 23, 0, 3] {
            XCTAssertTrue(MemoryHomeJukebox.isUnlocked(.lavenderNight, memories: [memory(2026, 5, 4, hour: hour)],
                                                       focusSessions: 0), "\(hour)시가 밤이 아니다")
        }
        for hour in [4, 12, 21] {
            XCTAssertFalse(MemoryHomeJukebox.isUnlocked(.lavenderNight, memories: [memory(2026, 5, 4, hour: hour)],
                                                        focusSessions: 0), "\(hour)시가 밤으로 셌다")
        }
    }

    /// 이름·조건·심볼이 네 곡 모두 세 언어로 채워져 있어야 한다. 화면에 조건을 안 적으면
    /// 잠긴 곡이 왜 잠겼는지 알 수 없다.
    func testEveryTrackHasNameRequirementAndSymbolInThreeLanguages() {
        XCTAssertEqual(Set(MemoryHomeJukeboxTrack.allCases.map(MemoryHomeJukebox.symbol)).count,
                       MemoryHomeJukeboxTrack.allCases.count, "심볼이 겹쳤다")
        for language in [AppLanguage.ko, .en, .ja] {
            let l = L(language)
            let names = MemoryHomeJukeboxTrack.allCases.map { MemoryHomeJukebox.name($0, l) }
            let requirements = MemoryHomeJukeboxTrack.allCases.map { MemoryHomeJukebox.requirement($0, l) }
            XCTAssertEqual(Set(names).count, MemoryHomeJukeboxTrack.allCases.count,
                           "\(language): 곡 이름이 겹쳤다")
            XCTAssertEqual(Set(requirements).count, MemoryHomeJukeboxTrack.allCases.count,
                           "\(language): 해금 조건 문구가 겹쳤다")
            XCTAssertFalse((names + requirements).contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }

    /// 선택은 그대로 저장돼야 한다 — 해금 판정이 파생이라 저장 계약은 예전과 같다.
    func testSelectedTrackStillPersists() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jukebox-\(UUID()).json")
        let album = PokemonMemoryAlbum(fileURL: url)
        album.setJukeboxTrack(.summerRiver)
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).memoryHomeAccess.jukeboxTrack, .summerRiver)
    }
}
