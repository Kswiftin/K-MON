import XCTest
@testable import PokeTokenBar

@MainActor
final class MemoryHomeRoomRenovationTests: XCTestCase {
    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("room-r8-\(UUID().uuidString).json") }

    func testPlacementSnapsAvoidsCollisionsAndRespectsInventory() {
        let file = url(); defer { try? FileManager.default.removeItem(at: file) }
        let album = PokemonMemoryAlbum(fileURL: file)
        let owned = [ItemKind.roomBed.rawValue: 2]
        let first = album.placeDecor(.roomBed, at: .init(x: 0.51, y: 0.61), ownedItems: owned)
        let second = album.placeDecor(.roomBed, at: .init(x: 0.51, y: 0.61), ownedItems: owned)
        XCTAssertNotNil(first); XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.position, second?.position)
        XCTAssertFalse(album.moveDecor(id: UUID(), to: .init(x: 0, y: 0)))
        XCTAssertNil(album.placeDecor(.roomBed, at: .init(x: 0.5, y: 0.6), ownedItems: owned))
    }

    func testLegacySlotsMigrateToCampusGridAndPersist() {
        let file = url(); defer { try? FileManager.default.removeItem(at: file) }
        var access = MemoryHomeAccessSettings()
        access.roomLayout = ["left": .roomBed, "center": .roomTable, "right": .roomLamp]
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:], memoryHomeAccess: access)
        let album = PokemonMemoryAlbum(fileURL: file)
        album.replace(with: snapshot, validCompanionIDs: [])
        XCTAssertEqual(album.roomStyle, .campus)
        XCTAssertEqual(album.memoryHomeAccess.placedDecor.count, 3)
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: file).memoryHomeAccess.placedDecor.count, 3)
    }

    /// 이전이 **한 번만** 일어나야 한다. 이전 조건이 `placedDecor.isEmpty` 하나였고 legacy
    /// `roomLayout` 을 아무도 비우지 않아서, 방을 초기화하고 재시작하면 옛 가구가 되살아났다.
    /// 기존 이전 테스트는 "3개가 남았다" 만 봐서 이 경로를 한 번도 밟지 않았다.
    func testResetAfterMigrationDoesNotResurrectLegacyFurniture() {
        let file = url(); defer { try? FileManager.default.removeItem(at: file) }
        var access = MemoryHomeAccessSettings()
        access.roomLayout = ["left": .roomBed, "center": .roomTable, "right": .roomLamp]
        let album = PokemonMemoryAlbum(fileURL: file)
        album.replace(with: PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:],
                                                      memoryHomeAccess: access),
                      validCompanionIDs: [])
        XCTAssertEqual(album.memoryHomeAccess.placedDecor.count, 3)

        album.resetDecor()
        XCTAssertTrue(album.memoryHomeAccess.placedDecor.isEmpty)
        XCTAssertTrue(album.memoryHomeAccess.roomLayout.isEmpty,
                      "이전을 마쳤으면 legacy 슬롯이 비어 있어야 한다")
        XCTAssertTrue(PokemonMemoryAlbum(fileURL: file).memoryHomeAccess.placedDecor.isEmpty,
                      "재시작하니 초기화한 가구가 되살아났다")
    }

    /// 이전은 저장된 legacy 좌표를 **존중**해야 한다. 기존 이전 테스트는 `furniturePositions`
    /// 를 비운 채 개수만 봐서, 저장 좌표를 읽는 가지가 커버리지에 `^0` 으로 남아 있었다
    /// (측정으로 확인함) — 즉 슬롯 기본 위치로 덮어써도 통과하던 상태다.
    func testMigrationHonoursSavedLegacyPositionsInsteadOfSlotDefaults() throws {
        let file = url(); defer { try? FileManager.default.removeItem(at: file) }
        var access = MemoryHomeAccessSettings()
        access.roomLayout = ["left": .roomBed]
        // 왼쪽 슬롯의 기본 위치는 (0.20, 0.70) 이다. 그와 멀리 떨어진 좌표를 저장해 둔다.
        access.furniturePositions = ["left": .clamped(x: 0.90, y: 0.20)]
        let album = PokemonMemoryAlbum(fileURL: file)
        album.replace(with: PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:],
                                                      memoryHomeAccess: access),
                      validCompanionIDs: [], ownedItems: [ItemKind.roomBed.rawValue: 1])

        // 8×6 격자는 셀 중심을 저장한다. 기존 좌표 (0.90, 0.20)는 (7, 1)로 옮겨진다.
        let moved = try XCTUnwrap(album.memoryHomeAccess.placedDecor.first)
        XCTAssertEqual(moved.position.x, 7.5 / 8.0, accuracy: 0.001)
        XCTAssertEqual(moved.position.y, 1.5 / 6.0, accuracy: 0.001)
    }

    func testFeaturedPhotoAndStyleTicketsAreExplicit() {
        let album = PokemonMemoryAlbum(fileURL: url())
        XCTAssertTrue(album.isRoomStyleUnlocked(.campus))
        XCTAssertFalse(album.isRoomStyleUnlocked(.lovely))
        album.unlockRoomStyle(.lovely); album.selectRoomStyle(.lovely)
        XCTAssertEqual(album.roomStyle, .lovely)
        let photo = MemoryHomePhoto(speciesID: 25, isShiny: false, caption: "", frame: "a", background: "b", composition: "c", trainerStyle: "d")
        album.addPhoto(photo); album.setFeaturedPhoto(id: photo.id)
        XCTAssertEqual(album.memoryHomeAccess.featuredPhotoID, photo.id)
    }

    func testResetCanBeUndoneAndCompanionMovesJoinRoomHistory() throws {
        let file = url(); defer { try? FileManager.default.removeItem(at: file) }
        let album = PokemonMemoryAlbum(fileURL: file)
        let companionID = UUID()
        let decor = try XCTUnwrap(album.placeDecor(.roomLamp, at: .init(x: 0.2, y: 0.4),
                                                   ownedItems: [ItemKind.roomLamp.rawValue: 1]))

        album.setCompanionPosition(.init(x: 0.8, y: 0.3), for: companionID,
                                   validCompanionIDs: [companionID])
        XCTAssertEqual(album.companionPosition(for: companionID), .clamped(x: 0.8, y: 0.3))
        album.undoRoomEdit()
        XCTAssertNotEqual(album.companionPosition(for: companionID), .clamped(x: 0.8, y: 0.3))

        album.resetDecor()
        XCTAssertTrue(album.memoryHomeAccess.placedDecor.isEmpty)
        album.undoRoomEdit()
        XCTAssertEqual(album.memoryHomeAccess.placedDecor.map(\.id), [decor.id])
    }
}
