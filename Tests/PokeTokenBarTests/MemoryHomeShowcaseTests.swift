import XCTest
@testable import PokeTokenBar

/// 방문자가 실제로 받는 카드에 **대표 기억**과 **대표 사진**이 실리는지. 앨범 메서드만 호출해
/// 검증하면 `sharedPinnedMemoryID`·`featuredPhotoID` 가 세이브에 들어간 것까지만 보이고, 그 값이
/// 전선으로 나가는지는 못 본다 — 카드를 굽는 v2 분기가 필드를 빠뜨려도 통과한다.
/// (이 셋의 설정 경로가 화면에 **도달 가능한가** 는 테스트가 답할 수 없다. `test-gate.sh` 의
/// 호출부 없는 mutator 스윕이 그쪽을 맡는다.)
@MainActor
final class MemoryHomeShowcaseTests: XCTestCase {
    /// 스토어마다 **디렉토리**를 새로 판다. 기억 앨범은 상태 파일 *옆에* 살기 때문에
    /// (`CompanionStore.init`), 상태 파일만 유일하게 하고 공용 temp 디렉토리에 두면 모든
    /// 테스트가 앨범 파일 하나를 공유한다 — 앞 테스트의 대표 사진이 다음 테스트에 남고,
    /// 심지어 `swift test` 실행 사이에도 남는다(이 테스트를 쓰다가 실제로 밟았다).
    private func hatchedStore() async -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("poke-showcase-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(fileURL: directory.appendingPathComponent("state.json"))
        await store.hatch(baseID: 1)
        return store
    }

    private func photo() -> MemoryHomePhoto {
        MemoryHomePhoto(speciesID: 25, isShiny: false, caption: "첫 사진", frame: "star",
                        background: "studio", composition: "left", trainerStyle: "explorer")
    }

    /// 고정하지 않은 기억은 공유될 수 없고, 고정만 해도 아직 나가지 않는다 — 공유는 **명시적**
    /// 동작이다(대문 문구가 `profileMessageForSharing` 를 지나는 것과 같은 규칙).
    func testCardOmitsTheSharedMemoryUntilItIsPinnedAndShared() async throws {
        let store = await hatchedStore()
        let center = MemoryHomeVisitCenter(companion: store, peerID: UUID())
        let mon = try XCTUnwrap(store.state.active)
        let album = store.memoryAlbum
        XCTAssertTrue(album.record(companionID: mon.id, body: "같이 첫 집중을 마쳤다", source: .event, eventID: "e1"))
        // 부화가 이미 기억 하나를 남긴다 — 내가 방금 적은 것은 마지막이다.
        let memory = try XCTUnwrap(album.entries(for: mon.id).last)

        XCTAssertNil(center.profileCard().sharedMemoryBody, "고정도 공유도 하지 않았는데 기억이 나갔다")

        album.pin(memory)
        XCTAssertEqual(album.pinned(for: mon.id)?.id, memory.id, "고정하는 길이 없으면 대표 기억을 고를 수 없다")
        XCTAssertNil(center.profileCard().sharedMemoryBody, "고정만으로 공유되면 동의 없이 새어 나간다")

        album.setSharedPinnedMemory(memory, activeCompanionID: mon.id)
        XCTAssertEqual(center.profileCard().sharedMemoryBody, "같이 첫 집중을 마쳤다")
    }

    func testClearingStopsSharingThePinnedMemory() async throws {
        let store = await hatchedStore()
        let center = MemoryHomeVisitCenter(companion: store, peerID: UUID())
        let mon = try XCTUnwrap(store.state.active)
        let album = store.memoryAlbum
        XCTAssertTrue(album.record(companionID: mon.id, body: "비 오는 날의 집중", source: .event, eventID: "e2"))
        let memory = try XCTUnwrap(album.entries(for: mon.id).last)
        album.pin(memory)
        album.setSharedPinnedMemory(memory, activeCompanionID: mon.id)
        XCTAssertNotNil(center.profileCard().sharedMemoryBody)

        album.clearSharedPinnedMemory()

        XCTAssertNil(center.profileCard().sharedMemoryBody, "공유를 끈 뒤에도 카드가 기억을 실어 보냈다")
    }

    /// 고정된 기억이 아닌 것을 공유하려 하면 앨범이 거절한다. 화면이 목록 아무 줄이나 공유
    /// 버튼으로 넘기면 조용히 아무 일도 일어나지 않으므로, 이 계약을 여기에 못 박는다.
    func testSharingRefusesAMemoryThatIsNotPinned() async throws {
        let store = await hatchedStore()
        let center = MemoryHomeVisitCenter(companion: store, peerID: UUID())
        let mon = try XCTUnwrap(store.state.active)
        let album = store.memoryAlbum
        XCTAssertTrue(album.record(companionID: mon.id, body: "고정된 기억", source: .event, eventID: "e3"))
        XCTAssertTrue(album.record(companionID: mon.id, body: "고정 안 된 기억", source: .event, eventID: "e4"))
        // 부화 기억이 맨 앞이라 내가 적은 둘은 뒤 두 개다.
        let entries = album.entries(for: mon.id).suffix(2)
        album.pin(try XCTUnwrap(entries.first))

        album.setSharedPinnedMemory(try XCTUnwrap(entries.last), activeCompanionID: mon.id)

        XCTAssertNil(center.profileCard().sharedMemoryBody, "고정되지 않은 기억이 공유됐다")
    }

    func testCardOmitsTheFeaturedPhotoUntilOneIsChosen() async throws {
        let store = await hatchedStore()
        let center = MemoryHomeVisitCenter(companion: store, peerID: UUID())
        let album = store.memoryAlbum
        let shot = photo()
        album.addPhoto(shot)

        XCTAssertNil(center.profileCard().featuredPhoto, "전시만 했는데 대표 사진으로 나갔다")

        album.setFeaturedPhoto(id: shot.id)

        XCTAssertEqual(center.profileCard().featuredPhoto?.id, shot.id, "대표 사진을 고르는 길이 없으면 쇼룸이 늘 빈다")
    }

    /// 앨범에 없는 id 는 거절한다 — 지운 사진이 대표로 남아 있으면 카드에 nil 이 실려 사용자가
    /// 고른 사진이 조용히 사라진 것처럼 보인다.
    func testFeaturedPhotoRefusesAnIDThatIsNotInTheAlbum() async throws {
        let store = await hatchedStore()
        let center = MemoryHomeVisitCenter(companion: store, peerID: UUID())
        let album = store.memoryAlbum
        let shot = photo()
        album.addPhoto(shot)
        album.setFeaturedPhoto(id: shot.id)

        album.setFeaturedPhoto(id: UUID())

        XCTAssertEqual(center.profileCard().featuredPhoto?.id, shot.id, "없는 사진을 대표로 받아 쇼룸이 비었다")
    }
}
