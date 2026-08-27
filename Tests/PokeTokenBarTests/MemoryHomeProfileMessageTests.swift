import XCTest
@testable import PokeTokenBar

/// 대문 문구의 유일한 위험은 "동의 없이 LAN 으로 나가는 것"이다. 그래서 검증보다 **공유 게이트**를
/// 더 많이 밟는다 — 기본 비공개, 문구 삭제 시 플래그 해제, 손댄 파일에서 온 켜진 플래그 정리.
@MainActor
final class MemoryHomeProfileMessageTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-home-message-\(UUID().uuidString).json")
    }

    func testValidatorAcceptsInnerSpacesAndRejectsLineBreaksAndOverlongText() {
        // 닉네임과 달리 내부 공백은 허용해야 한다 — 이건 서비스 이름이 아니라 화면 문구다.
        XCTAssertEqual(PokemonMemoryAlbum.validProfileMessage("행복은 가까이에 있는 법⚡"), "행복은 가까이에 있는 법⚡")
        XCTAssertEqual(PokemonMemoryAlbum.validProfileMessage("  피카츄랑 여행중 :)  "), "피카츄랑 여행중 :)")

        XCTAssertNil(PokemonMemoryAlbum.validProfileMessage(""))
        XCTAssertNil(PokemonMemoryAlbum.validProfileMessage("   "))
        XCTAssertNil(PokemonMemoryAlbum.validProfileMessage("두\n줄"), "줄바꿈이 통과했다")
        XCTAssertNil(PokemonMemoryAlbum.validProfileMessage("탭\t포함"), "제어문자가 통과했다")

        let limit = MemoryHomeAccessSettings.profileMessageLimit
        XCTAssertNotNil(PokemonMemoryAlbum.validProfileMessage(String(repeating: "가", count: limit)))
        XCTAssertNil(PokemonMemoryAlbum.validProfileMessage(String(repeating: "가", count: limit + 1)))
    }

    func testSavingAMessageDoesNotShareItAndPersists() {
        let url = temporaryURL()
        let album = PokemonMemoryAlbum(fileURL: url)

        XCTAssertTrue(album.setProfileMessage("피카츄랑 여행중 :)"))
        XCTAssertEqual(album.memoryHomeAccess.profileMessage, "피카츄랑 여행중 :)")
        XCTAssertFalse(album.memoryHomeAccess.sharesProfileMessage, "저장만으로 공유가 켜졌다")
        XCTAssertNil(album.profileMessageForSharing, "공유를 켜지 않았는데 공유 값이 나왔다")

        let reloaded = PokemonMemoryAlbum(fileURL: url)
        XCTAssertEqual(reloaded.memoryHomeAccess.profileMessage, "피카츄랑 여행중 :)")
        XCTAssertFalse(reloaded.memoryHomeAccess.sharesProfileMessage)
    }

    func testSharingIsExplicitAndReversible() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        album.setProfileMessage("행복은 가까이에")

        album.setSharesProfileMessage(true)
        XCTAssertEqual(album.profileMessageForSharing, "행복은 가까이에")

        album.setSharesProfileMessage(false)
        XCTAssertNil(album.profileMessageForSharing)
        XCTAssertEqual(album.memoryHomeAccess.profileMessage, "행복은 가까이에",
                       "공유만 끄려 했는데 문구까지 사라졌다")
    }

    func testSharingCannotBeEnabledWithoutAMessage() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        album.setSharesProfileMessage(true)
        XCTAssertFalse(album.memoryHomeAccess.sharesProfileMessage, "문구 없이 공유가 켜졌다")
        XCTAssertNil(album.profileMessageForSharing)
    }

    func testDeletingTheMessageAlsoClearsTheShareFlag() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        album.setProfileMessage("첫 문구")
        album.setSharesProfileMessage(true)

        album.clearProfileMessage()
        XCTAssertNil(album.memoryHomeAccess.profileMessage)
        // 켜진 플래그가 남으면 다음에 쓰는 문구가 동의 없이 즉시 LAN 으로 나간다.
        XCTAssertFalse(album.memoryHomeAccess.sharesProfileMessage, "삭제 후에도 공유 플래그가 남았다")
        album.setProfileMessage("다음 문구")
        XCTAssertNil(album.profileMessageForSharing, "새 문구가 동의 없이 공유됐다")
    }

    /// 변경 없는 재저장/재삭제는 디스크 쓰기를 건너뛰는 분기를 탄다. `--show-regions` 에서 `^0`
    /// 이던 두 줄이라 명시적으로 밟는다 — 안 밟으면 "같은 값 저장"이 false 를 리턴해도 못 잡는다.
    func testUnchangedWritesAreNoOpsAndStillReportSuccess() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        XCTAssertTrue(album.setProfileMessage("같은 문구"))
        XCTAssertTrue(album.setProfileMessage("같은 문구"), "같은 문구 재저장이 실패로 보고됐다")
        XCTAssertEqual(album.memoryHomeAccess.profileMessage, "같은 문구")
        // 앞뒤 공백만 다른 입력도 트림 후 같은 값이라 같은 분기를 탄다.
        XCTAssertTrue(album.setProfileMessage("  같은 문구  "))
        XCTAssertEqual(album.memoryHomeAccess.profileMessage, "같은 문구")

        album.clearProfileMessage()
        XCTAssertNil(album.memoryHomeAccess.profileMessage)
        album.clearProfileMessage()  // 이미 없는 상태에서 한 번 더
        XCTAssertNil(album.memoryHomeAccess.profileMessage)
    }

    func testRejectedMessageLeavesThePreviousValueUntouched() {
        let album = PokemonMemoryAlbum(fileURL: temporaryURL())
        album.setProfileMessage("원래 문구")
        XCTAssertFalse(album.setProfileMessage("나쁜\n문구"))
        XCTAssertEqual(album.memoryHomeAccess.profileMessage, "원래 문구")
    }

    /// 세이브 이전이나 손편집으로 "문구 없이 켜진 공유 플래그" 상태가 올 수 있다.
    func testTamperedShareFlagWithoutMessageIsClearedOnLoad() throws {
        let url = temporaryURL()
        var access = MemoryHomeAccessSettings()
        access.profileMessage = nil
        access.sharesProfileMessage = true
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:], memoryHomeAccess: access)
        try JSONEncoder().encode(snapshot).write(to: url)

        let album = PokemonMemoryAlbum(fileURL: url)
        XCTAssertFalse(album.memoryHomeAccess.sharesProfileMessage)
        XCTAssertNil(album.profileMessageForSharing)
    }

    func testTamperedInvalidMessageIsDroppedAndUnshared() throws {
        let url = temporaryURL()
        var access = MemoryHomeAccessSettings()
        access.profileMessage = "줄바꿈\n주입"
        access.sharesProfileMessage = true
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:], memoryHomeAccess: access)
        try JSONEncoder().encode(snapshot).write(to: url)

        let album = PokemonMemoryAlbum(fileURL: url)
        XCTAssertNil(album.memoryHomeAccess.profileMessage, "잘못된 문구가 살아남았다")
        XCTAssertFalse(album.memoryHomeAccess.sharesProfileMessage)
    }
}
