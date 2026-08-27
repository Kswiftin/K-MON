import XCTest
@testable import PokeTokenBar

/// TODAY/TOTAL 은 수락된 LAN 방문에서만 오른다. 이 스위트는 결함 트리거 브랜치를 직접 밟는다:
/// 같은 피어 재접속, 자정 넘김, 상한 초과, 그리고 손댄 파일에서 온 불가능한 값.
@MainActor
final class MemoryHomeVisitCounterTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-home-visits-\(UUID().uuidString).json")
    }
    /// 고정 시각. `dayKey` 는 호스트 캘린더를 쓰므로 테스트는 "같은 날/다른 날"만 주장하고
    /// 특정 날짜 문자열을 못 박지 않는다 — CI 로케일 패리티 재실행에서도 그대로 통과해야 한다.
    private let noon = Date(timeIntervalSince1970: 1_787_000_400)

    func testSamePeerCountsOncePerDayAndTotalTracksToday() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let peer = UUID()

        album.recordMemoryHomeRequester(displayName: "minji", peerID: peer, now: noon)
        XCTAssertEqual(album.memoryHomeAccess.visitToday, 1)
        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 1)

        // 재접속(같은 날, 같은 피어) — 숫자를 부풀리지 못해야 한다.
        album.recordMemoryHomeRequester(displayName: "minji", peerID: peer, now: noon.addingTimeInterval(60))
        XCTAssertEqual(album.memoryHomeAccess.visitToday, 1, "같은 피어가 같은 날 두 번 세어졌다")
        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 1)

        // 다른 피어(같은 날) — 둘 다 오른다.
        album.recordMemoryHomeRequester(displayName: "junho", peerID: UUID(), now: noon)
        XCTAssertEqual(album.memoryHomeAccess.visitToday, 2)
        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 2)
    }

    func testTodayResetsOnDayRolloverWhileTotalAccumulates() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let peer = UUID()
        album.recordMemoryHomeRequester(displayName: "minji", peerID: peer, now: noon)
        let firstDayKey = album.memoryHomeAccess.visitDayKey

        // 같은 피어, 다음 날 — TODAY 는 리셋되고 그 피어가 다시 세어지며 TOTAL 은 누적된다.
        album.recordMemoryHomeRequester(displayName: "minji", peerID: peer, now: noon.addingTimeInterval(86_400))
        XCTAssertEqual(album.memoryHomeAccess.visitToday, 1, "자정을 넘겨도 TODAY 가 리셋되지 않았다")
        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 2)
        XCTAssertNotEqual(album.memoryHomeAccess.visitDayKey, firstDayKey)
    }

    func testCountersAndThresholdDatePersistAcrossRelaunch() {
        let url = temporaryURL()
        let album = PokemonMemoryAlbum(fileURL: url)
        // 첫 임계값(10)을 정확히 밟는다 — 그 경계가 카드 발급 조건이다.
        for _ in 0..<10 { album.recordMemoryHomeRequester(displayName: "guest", peerID: UUID(), now: noon) }
        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 10)
        XCTAssertEqual(album.memoryHomeAccess.visitThresholdDates[10], noon)
        XCTAssertNil(album.memoryHomeAccess.visitThresholdDates[100], "밟지 않은 임계값에 날짜가 찍혔다")

        let reloaded = PokemonMemoryAlbum(fileURL: url)
        XCTAssertEqual(reloaded.memoryHomeAccess.visitTotal, 10)
        XCTAssertEqual(reloaded.memoryHomeAccess.visitToday, 10)
        XCTAssertEqual(reloaded.memoryHomeAccess.visitThresholdDates[10], noon)
    }

    func testDailyPeerCapStopsBothTodayAndTotal() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        let limit = MemoryHomeAccessSettings.visitTodayPeerLimit
        for _ in 0..<(limit + 5) {
            album.recordMemoryHomeRequester(displayName: "guest", peerID: UUID(), now: noon)
        }
        // 집합만 멈추고 TOTAL 이 계속 오르면 상한 이후 중복 제거가 무의미해진다.
        XCTAssertEqual(album.memoryHomeAccess.visitToday, limit)
        XCTAssertEqual(album.memoryHomeAccess.visitTotal, limit, "상한을 넘어서도 TOTAL 이 올랐다")
    }

    func testEmptyDisplayNameRecordsNeitherRequesterNorVisit() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        album.recordMemoryHomeRequester(displayName: "   ", peerID: UUID(), now: noon)
        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 0)
        XCTAssertTrue(album.memoryHomeAccess.recentRequesters.isEmpty)
    }

    /// 손댄/이전된 파일 방어. 이 브랜치는 정상 플레이로는 절대 안 밟히므로 직접 주입한다.
    func testTamperedSnapshotIsNormalizedOnLoad() throws {
        let url = temporaryURL()
        var access = MemoryHomeAccessSettings()
        access.visitDayKey = "garbage"
        access.visitTodayPeerIDs = [UUID(), UUID(), UUID()]
        access.visitTotal = -50
        access.visitThresholdDates = [10: Date(timeIntervalSince1970: 1), 7: Date(timeIntervalSince1970: 2)]
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:], memoryHomeAccess: access)
        try JSONEncoder().encode(snapshot).write(to: url)

        let album = PokemonMemoryAlbum(fileURL: url)
        XCTAssertNil(album.memoryHomeAccess.visitDayKey, "못 믿을 dayKey 가 살아남았다")
        XCTAssertTrue(album.memoryHomeAccess.visitTodayPeerIDs.isEmpty,
                      "어느 날의 집합인지 모르는 채로 TODAY 피어가 남았다")
        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 0, "음수 TOTAL 이 클램프되지 않았다")
        XCTAssertNil(album.memoryHomeAccess.visitThresholdDates[7], "임계값이 아닌 키가 남았다")
        XCTAssertNil(album.memoryHomeAccess.visitThresholdDates[10], "TOTAL 을 넘는 임계값이 남았다")
    }

    /// R4 키가 하나도 없는 페이로드 — 기존 사용자 전원의 앨범이 이 형태다.
    ///
    /// 손으로 쓴 JSON 을 쓰지 않는다: `[UUID: T]` 는 Swift 가 키드 오브젝트가 아니라 **배열**로
    /// 인코딩하므로 `"memories":{}` 는 디코드에 실패하고, 그러면 앨범이 빈 상태로 복구된다.
    /// 그 빈 앨범은 아래 "0/nil" 주장을 **전부 통과시킨다** — 그래서 진짜 신호는 R4 이전에
    /// 저장돼 있던 값(닉네임)이 살아남았는지와 `.corrupt` 백업이 안 생겼는지 두 가지뿐이다.
    func testPreR4SnapshotLoadsWithZeroedCounters() throws {
        struct PreR4Access: Encodable {
            var publicNickname = "OldHome"
            var visibility = "open"
            var blockedPeerIDs: [UUID] = []
        }
        struct PreR4Snapshot: Encodable {
            var memories: [UUID: [PokemonMemory]] = [:]
            var pinnedMemoryIDs: [UUID: UUID] = [:]
            var memoryHomeAccess = PreR4Access()
        }
        let url = temporaryURL()
        try JSONEncoder().encode(PreR4Snapshot()).write(to: url)

        let album = PokemonMemoryAlbum(fileURL: url)
        // 빈 앨범으로는 통과할 수 없는 주장 — 실제로 디코드됐다는 증거.
        XCTAssertEqual(album.memoryHomePublicNickname, "OldHome", "R4 이전 앨범이 디코드되지 않았다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
                       "R4 이전 앨범이 .corrupt 로 밀려났다")

        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 0)
        XCTAssertEqual(album.memoryHomeAccess.visitToday, 0)
        XCTAssertNil(album.memoryHomeAccess.visitDayKey)
        XCTAssertTrue(album.memoryHomeAccess.visitThresholdDates.isEmpty)
        XCTAssertNil(album.memoryHomeAccess.profileMessage)
        XCTAssertFalse(album.memoryHomeAccess.sharesProfileMessage)
        XCTAssertNil(album.mood(on: noon))
    }

    func testDayKeyValidatorRejectsMalformedKeys() {
        XCTAssertNotNil(PokemonMemoryAlbum.validDayKey("2026-08-28"))
        for bad in ["2026-8-28", "2026-08-28T00", "26-08-28", "2026/08/28", "", "２０２６-０８-２８"] {
            XCTAssertNil(PokemonMemoryAlbum.validDayKey(bad), "\(bad) 를 통과시켰다")
        }
    }
}
