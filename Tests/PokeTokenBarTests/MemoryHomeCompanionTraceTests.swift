import XCTest
@testable import PokeTokenBar

/// §13 "그리고 피카츄가 아주 드물게 pika pika ⚡ 라고 방명록에 흔적을 남기기도 합니다."
///
/// 이 기능의 위험은 문구가 아니라 **빈도**다. 방명록 캡이 50개고 사용자가 직접 쓴 글과 같은
/// 목록을 쓰므로, 열 때마다 한 줄씩 남으면 동행이 사용자의 기록을 밀어낸다.
@MainActor
final class MemoryHomeCompanionTraceTests: XCTestCase {
    private func makeAlbum() -> (PokemonMemoryAlbum, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trace-\(UUID()).json")
        return (PokemonMemoryAlbum(fileURL: url), url)
    }

    /// dayKey 를 준 날에 흔적이 남는 날이 **존재해야** 한다. 확률이 0 이 되면 이 기능은
    /// 코드만 있고 아무도 못 보는 상태가 된다 — 이 저장소에서 이미 한 번 일어난 부류다.
    func testSomeDaysLeaveATraceButNotMost() {
        let hits = (1...28).filter { day in
            MemoryHomeCompanionTrace.leavesTrace(dayKey: String(format: "2026-03-%02d", day))
        }
        XCTAssertFalse(hits.isEmpty, "한 달 내내 흔적이 안 남으면 아무도 이 기능을 못 본다")
        XCTAssertLessThan(hits.count, 14, "달의 절반 넘게 남으면 '아주 드물게' 가 아니다")
    }

    /// 같은 날 두 번 열어도 결과가 같아야 한다. 난수면 창을 여닫을 때마다 새 글이 생긴다.
    func testTraceDecisionIsDeterministicPerDay() {
        let key = "2026-07-16"
        let first = MemoryHomeCompanionTrace.leavesTrace(dayKey: key)
        for _ in 0..<20 {
            XCTAssertEqual(MemoryHomeCompanionTrace.leavesTrace(dayKey: key), first)
        }
    }

    /// 하루 1개. 같은 날 이미 동행 글이 있으면 아무 일도 없어야 한다(멱등).
    func testSecondCallOnTheSameDayAddsNothing() throws {
        let (album, _) = makeAlbum()
        let date = try XCTUnwrap(dayKeyDate(try noisyDay()))

        XCTAssertTrue(album.recordCompanionTraceIfNeeded(companionName: "피카츄", l: L(.ko), now: date))
        XCTAssertEqual(album.memoryHomeAccess.guestbookEntries.count, 1)
        XCTAssertFalse(album.recordCompanionTraceIfNeeded(companionName: "피카츄", l: L(.ko), now: date),
                       "같은 날 두 번째 호출은 아무것도 남기지 않아야 한다")
        XCTAssertEqual(album.memoryHomeAccess.guestbookEntries.count, 1)
    }

    /// 흔적이 남지 않는 날은 글이 0개다. 이 가지를 안 밟으면 "항상 남기는" 구현도 통과한다.
    func testQuietDayLeavesNothing() throws {
        let (album, _) = makeAlbum()
        let quiet = try XCTUnwrap((1...31).map { String(format: "2026-03-%02d", $0) }
            .first(where: { !MemoryHomeCompanionTrace.leavesTrace(dayKey: $0) }))
        let date = try XCTUnwrap(dayKeyDate(quiet))

        XCTAssertFalse(album.recordCompanionTraceIfNeeded(companionName: "피카츄", l: L(.ko), now: date))
        XCTAssertTrue(album.memoryHomeAccess.guestbookEntries.isEmpty)
    }

    /// 남은 글은 **동행 작성자**로 표시돼야 한다. 트레이너로 남으면 사용자가 자기가 쓴 줄 안다.
    func testTraceIsAttributedToTheCompanionAndPersists() throws {
        let (album, url) = makeAlbum()
        let date = try XCTUnwrap(dayKeyDate(try noisyDay()))

        XCTAssertTrue(album.recordCompanionTraceIfNeeded(companionName: "피카츄", l: L(.ko), now: date))
        let entry = try XCTUnwrap(album.memoryHomeAccess.guestbookEntries.first)
        XCTAssertEqual(entry.authorKind, .companion)
        XCTAssertEqual(entry.author, "피카츄")
        XCTAssertFalse(entry.body.isEmpty)
        // 방명록은 기기 안에만 남는 기록이므로 재시작 후에도 그대로여야 한다.
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).memoryHomeAccess.guestbookEntries.count, 1)
    }

    /// 사용자가 같은 날 남긴 글은 동행 흔적을 막지 않는다 — 하루 1개 제한은 **동행 글**에만
    /// 걸린다. `authorKind` 를 안 보고 날짜만 보면 이 케이스가 조용히 막힌다.
    func testTrainerNoteOnTheSameDayDoesNotBlockTheTrace() throws {
        let (album, _) = makeAlbum()
        let date = try XCTUnwrap(dayKeyDate(try noisyDay()))

        XCTAssertTrue(album.addGuestbookEntry(author: "트레이너", body: "오늘의 한마디",
                                              authorKind: .trainer, createdAt: date))
        XCTAssertTrue(album.recordCompanionTraceIfNeeded(companionName: "피카츄", l: L(.ko), now: date))
        XCTAssertEqual(album.memoryHomeAccess.guestbookEntries.filter { $0.authorKind == .companion }.count, 1)
    }

    /// 그날 기분과 어긋나는 문구가 나오면 §17 을 배신한다 — 우울한 날 "진짜 신났어!" 는 안 된다.
    func testTraceBodyFollowsTheDayMood() {
        for language in [AppLanguage.ko, .en, .ja] {
            let l = L(language)
            let bodies = MemoryHomeMood.allCases.map { MemoryHomeCompanionTrace.body(mood: $0, l) }
            XCTAssertEqual(Set(bodies).count, MemoryHomeMood.allCases.count,
                           "\(language): 기분 5개가 서로 다른 문구여야 한다")
            XCTAssertFalse(bodies.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            // 방명록 본문 캡을 넘으면 `addGuestbookEntry` 가 조용히 거부한다.
            XCTAssertFalse(bodies.contains { $0.count > MemoryHomeAccessSettings.guestbookBodyLimit })
            XCTAssertFalse(MemoryHomeCompanionTrace.body(mood: nil, l).isEmpty,
                           "\(language): 기분을 고르지 않은 날에도 문구가 있어야 한다")
        }
    }

    /// 흔적이 남는 날 하나. 전 달을 훑어 하나도 없으면 `leavesTrace` 가 상수 false 인 것이므로
    /// 테스트를 통과시키는 대신 실패시킨다.
    private func noisyDay() throws -> String {
        try XCTUnwrap((1...31).map { String(format: "2026-03-%02d", $0) }
            .first(where: MemoryHomeCompanionTrace.leavesTrace(dayKey:)))
    }

    private func dayKeyDate(_ dayKey: String) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1],
                                                         day: parts[2], hour: 12))
    }
}
