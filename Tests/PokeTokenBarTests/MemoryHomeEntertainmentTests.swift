import XCTest
@testable import PokeTokenBar

@MainActor
final class MemoryHomeEntertainmentTests: XCTestCase {
    private func temporaryURL() -> URL {
        storeStateURL("memory-home-entertainment")
    }

    /// BGM(주크박스)을 지운 뒤의 트리거 브랜치는 **키 삭제가 아니라 남은 키를 만나는 쪽**이다 —
    /// 이미 배포된 세이브에는 `jukeboxTrack` 이 들어 있고, 그 파일을 여는 것은 이제 그 키를
    /// 모르는 빌드다. 디코딩이 던지면 `init(fileURL:)` 이 파일을 `.corrupt` 로 밀어내므로
    /// 홈 전체(닉네임·방 스타일·기분·방문 수)가 조용히 초기화된다. 그래서 필드가 살아남았는지와
    /// `.corrupt` 백업이 생기지 않았는지를 함께 본다 — 값만 보면 기본값과 구별되지 않는다.
    func testSaveWrittenByABuildWithBGMOpensWithoutLoss() throws {
        let url = temporaryURL()
        // `memories` 는 `[UUID: [PokemonMemory]]` 다. UUID 키 딕셔너리를 `JSONDecoder` 는
        // 객체가 아니라 **배열**(키·값 교대)로 읽는다 — `{}` 로 적으면 세이브 전체가 던져서
        // 이 테스트가 BGM 과 무관한 이유로 빨개진다.
        try Data("""
        {"memories":[],"pinnedMemoryIDs":[],"memoryHomeAccess":{"publicNickname":"민지",\
        "jukeboxTrack":"summerRiver","roomStyle":"retro","unlockedRoomStyles":["campus","retro"],\
        "moodByDayKey":{"2026-08-30":"calm"},"visitTotal":7}}
        """.utf8).write(to: url)

        let album = PokemonMemoryAlbum(fileURL: url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
                       "지운 키 하나가 세이브 전체를 corrupt 로 밀어냈다")
        XCTAssertEqual(album.memoryHomeAccess.publicNickname, "민지")
        XCTAssertEqual(album.memoryHomeAccess.roomStyle, .retro)
        XCTAssertEqual(album.memoryHomeAccess.moodByDayKey["2026-08-30"], .calm)
        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 7)
    }

    /// 다시 저장하면 지운 키가 파일에서도 사라진다. 남겨 두면 "지웠는데 세이브에는 계속 있는"
    /// 상태가 되어, 다음 이전 작업이 그 값을 살아 있는 설정으로 오해한다(`defect-log.md` 의
    /// "일회성 이전은 일회성이 아니다" 와 같은 부류다).
    func testResavingDropsTheRetiredBGMKey() throws {
        let url = temporaryURL()
        try Data(#"{"memories":[],"pinnedMemoryIDs":[],"memoryHomeAccess":{"jukeboxTrack":"summerRiver"}}"#.utf8)
            .write(to: url)

        let album = PokemonMemoryAlbum(fileURL: url)
        XCTAssertTrue(album.addGuestbookEntry(author: "나", body: "저장을 한 번 일으킨다", authorKind: .trainer))

        let rewritten = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(rewritten.contains("jukeboxTrack"), "은퇴한 키가 세이브에 다시 쓰였다")
    }

    func testGuestbookValidatesBoundsAndPersistsNewestFirst() {
        let url = temporaryURL()
        let album = PokemonMemoryAlbum(fileURL: url)
        let earlier = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)

        XCTAssertTrue(album.addGuestbookEntry(author: "민지", body: "방문 찍고 감~~", authorKind: .trainer, createdAt: earlier))
        XCTAssertTrue(album.addGuestbookEntry(author: "피카츄", body: "pika pika ⚡", authorKind: .companion, createdAt: later))
        XCTAssertFalse(album.addGuestbookEntry(author: "민지", body: "두\n줄", authorKind: .trainer))
        XCTAssertFalse(album.addGuestbookEntry(author: "민지", body: String(repeating: "가", count: MemoryHomeAccessSettings.guestbookBodyLimit + 1), authorKind: .trainer))

        XCTAssertEqual(album.memoryHomeAccess.guestbookEntries.map(\.body), ["pika pika ⚡", "방문 찍고 감~~"])
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: url).memoryHomeAccess.guestbookEntries.map(\.author), ["피카츄", "민지"])
    }

    func testGuestbookIsBoundedAndLegacySnapshotsGetEntertainmentDefaults() throws {
        let url = temporaryURL()
        let album = PokemonMemoryAlbum(fileURL: url)
        for index in 0..<(MemoryHomeAccessSettings.guestbookLimit + 3) {
            XCTAssertTrue(album.addGuestbookEntry(author: "나", body: "메모 \(index)", authorKind: .trainer,
                                                   createdAt: Date(timeIntervalSince1970: TimeInterval(index))))
        }
        XCTAssertEqual(album.memoryHomeAccess.guestbookEntries.count, MemoryHomeAccessSettings.guestbookLimit)
        XCTAssertEqual(album.memoryHomeAccess.guestbookEntries.first?.body, "메모 \(MemoryHomeAccessSettings.guestbookLimit + 2)")

        let legacyURL = temporaryURL()
        try Data(#"{"memories":{},"pinnedMemoryIDs":{}}"#.utf8).write(to: legacyURL)
        let legacy = PokemonMemoryAlbum(fileURL: legacyURL)
        XCTAssertTrue(legacy.memoryHomeAccess.guestbookEntries.isEmpty)
    }
}
