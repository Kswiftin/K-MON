import XCTest
@testable import PokeTokenBar

// MARK: 포코피아 마을 — 세이브 이전 · 저장 왕복 · 전송 신뢰경계

@MainActor
final class PokopiaTownMigrationTests: XCTestCase {

    private func resident(_ speciesID: Int, _ name: String, _ types: [PokemonType]) -> TownResident {
        TownResident(speciesID: speciesID, name: name, types: types,
                     arrivedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// 이 버전 **이전**의 세이브 파일을 만든다 — 지금 코드로 굽고 `town` 키만 도로 지운다.
    ///
    /// JSON 을 손으로 쓰지 않는 이유: 이 앨범의 딕셔너리 중 여럿이 `[UUID: …]` 라
    /// Swift Codable 이 그것을 **객체가 아니라 배열**로 굽는다(`String`·`Int` 키만 객체다).
    /// 손으로 쓴 `"memories":{}` 는 디코딩에 실패하고, 앨범은 조용히 빈 상태로 떨어져
    /// "이전이 됐다" 처럼 보이는 초록 테스트가 된다 — 실제로 한 번 그렇게 통과했다.
    private func writeLegacyAlbum(_ access: MemoryHomeAccessSettings, to file: URL) throws {
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:],
                                                  memoryHomeAccess: access)
        let data = try JSONEncoder().encode(snapshot)
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var home = try XCTUnwrap(root["memoryHomeAccess"] as? [String: Any])
        XCTAssertNotNil(home.removeValue(forKey: "town"),
                        "굽힌 JSON 에 town 키가 없다 — 이 테스트가 지울 것이 없다")
        root["memoryHomeAccess"] = home
        try JSONSerialization.data(withJSONObject: root).write(to: file)
    }

    /// **트리거 브랜치.** `town` 키가 아예 없는 옛 세이브를 연다. 비옵셔널 `decode` 를 쓰면
    /// 여기서 앨범이 `.corrupt` 로 밀려나고 **기존 사용자 전원의 기억이 사라진다**.
    func testAlbumWithoutTheTownKeyOpensWithDefaults() throws {
        let file = memoryAlbumURL("pokopia-legacy")
        var access = MemoryHomeAccessSettings()
        access.visitTotal = 7
        try writeLegacyAlbum(access, to: file)

        let album = PokemonMemoryAlbum(fileURL: file)

        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 7,
                       "앨범이 손상 처리됐다 — 기존 사용자의 기억이 날아가는 경로다")
        XCTAssertEqual(album.town.terrain, PokopiaTown.defaultTerrain)
        XCTAssertNil(album.town.dittoForm)
        XCTAssertTrue(album.town.residents.isEmpty)
    }

    /// 옛 세이브의 **방 데이터가 그대로 살아 있어야** 한다 — 마을이 방을 건드리면 안 된다.
    func testAddingTheTownKeyDoesNotDisturbExistingRoomData() throws {
        let file = memoryAlbumURL("pokopia-legacy-room")
        var access = MemoryHomeAccessSettings()
        access.unlockedRoomStyles = [.campus, .retro]
        access.roomStyle = .retro
        access.visitTotal = 3
        access.profileMessage = "안녕"
        try writeLegacyAlbum(access, to: file)

        let album = PokemonMemoryAlbum(fileURL: file)

        XCTAssertEqual(album.roomStyle, .retro)
        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 3)
        XCTAssertEqual(album.memoryHomeAccess.profileMessage, "안녕")
    }

    /// **저장 왕복.** 세 자리(필드 선언 · `CodingKeys` · `init(from:)`) 중 하나를 빠뜨리면
    /// 여기서 잡힌다 — 저장은 되는데 다음 실행에서 사라지는 부류다.
    func testTownSurvivesSaveAndReload() throws {
        let file = memoryAlbumURL("pokopia-roundtrip")
        let album = PokemonMemoryAlbum(fileURL: file)
        XCTAssertTrue(album.shapeTownTile(col: 5, row: 5, to: .water))
        XCTAssertTrue(album.setDittoForm(25, registeredSpecies: [25]))
        XCTAssertTrue(album.admitTownResident(resident(7, "꼬부기", [.water])))

        let reloaded = PokemonMemoryAlbum(fileURL: file)

        let index = try XCTUnwrap(PokopiaTown.index(col: 5, row: 5))
        XCTAssertEqual(reloaded.town.terrain[index], .water, "`CodingKeys` 에 town 이 빠졌다")
        XCTAssertEqual(reloaded.town.dittoForm, 25)
        XCTAssertEqual(reloaded.town.residents, album.town.residents)
    }

    /// **주민의 이름과 타입이 왕복한다.** 도감 밖 종이라 나중에 조회할 근거가 없으므로,
    /// 이 값이 사라지면 오프라인에서 마을이 `#7` 로 뜬다.
    func testResidentNameAndTypesSurviveReload() throws {
        let file = memoryAlbumURL("pokopia-resident-roundtrip")
        let album = PokemonMemoryAlbum(fileURL: file)
        XCTAssertTrue(album.admitTownResident(resident(7, "꼬부기", [.water])))

        let reloaded = PokemonMemoryAlbum(fileURL: file)
        let stored = try XCTUnwrap(reloaded.town.residents.first)

        XCTAssertEqual(stored.speciesID, 7)
        XCTAssertEqual(stored.name, "꼬부기", "이름이 사라지면 마을이 종 번호로 뜬다")
        XCTAssertEqual(stored.types, [.water], "타입이 사라지면 주민이 자기 지형을 못 찾는다")
    }

    /// 지형 192칸 전부가 왕복한다 — 한 칸만 확인하면 배열이 잘려도 통과한다.
    func testEveryShapedTileSurvivesReload() {
        let file = memoryAlbumURL("pokopia-roundtrip-all")
        let album = PokemonMemoryAlbum(fileURL: file)
        for col in 0..<PokopiaTown.columns {
            XCTAssertTrue(album.shapeTownTile(col: col, row: 0, to: .soil), "col \(col)")
        }

        let reloaded = PokemonMemoryAlbum(fileURL: file)

        XCTAssertEqual(reloaded.town.terrain.count, PokopiaTown.tileCount)
        XCTAssertEqual(reloaded.town.terrain, album.town.terrain)
        XCTAssertTrue(reloaded.town.terrain.prefix(PokopiaTown.columns).allSatisfy { $0 == .soil })
    }

    // MARK: 파일에서 온 못 믿을 값

    /// 파일에서 온 못 믿을 마을은 **여는 순간** 정규화된다 — 전송(`replace`)이 아니라 직접
    /// 열기 경로다. `normalizeMemoryHomeAccess` 에 마을이 배선되지 않았으면 여기서 잡힌다.
    func testUntrustedTownFromFileIsNormalizedOnOpen() throws {
        let file = memoryAlbumURL("pokopia-legacy-untrusted")
        var access = MemoryHomeAccessSettings()
        access.town.terrain = []
        access.town.dittoForm = -25
        let spriteless = PokemonAssets.spriteGaps.min() ?? 990
        access.town.residents = (1...(PokopiaTown.populationLimit + 3)).map {
            resident($0, "주민\($0)", [.water])
        } + [
            resident(7, "중복", [.water]),
            resident(spriteless, "그릴 수 없는 종", [.dragon]),
            resident(9_000, "이름만 있는 종", []),
        ]
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:],
                                                  memoryHomeAccess: access)
        try JSONEncoder().encode(snapshot).write(to: file)

        let album = PokemonMemoryAlbum(fileURL: file)

        XCTAssertEqual(album.town.terrain.count, PokopiaTown.tileCount, "빈 지형 배열이 남았다")
        XCTAssertNil(album.town.dittoForm, "음수 종으로 변신한 채 남았다")
        XCTAssertEqual(album.town.residents.count, PokopiaTown.populationLimit, "상한 초과 주민")
        XCTAssertEqual(Set(album.town.residents.map(\.speciesID)).count,
                       album.town.residents.count, "중복 종이 남았다")
        XCTAssertFalse(album.town.residents.contains { $0.speciesID == spriteless },
                       "그릴 수 없는 종이 주민으로 남았다")
        XCTAssertFalse(album.town.residents.contains { $0.types.isEmpty },
                       "타입 없는 주민이 남았다 — 자기 지형을 못 찾는다")
    }

    // MARK: prune · replace

    /// **`prune` 이 마을을 건드리지 않는다.** 주민은 소유 개체가 아니므로 개체를 방생해도
    /// 마을 인구는 그대로다 — 이전 판은 주민이 UUID 라 여기서 사라졌다.
    func testPruneLeavesTheTownAloneBecauseResidentsAreNotOwned() throws {
        let album = PokemonMemoryAlbum(fileURL: memoryAlbumURL("pokopia-prune"))
        XCTAssertTrue(album.shapeTownTile(col: 6, row: 6, to: .water))
        XCTAssertTrue(album.setDittoForm(25, registeredSpecies: [25]))
        XCTAssertTrue(album.admitTownResident(resident(7, "꼬부기", [.water])))

        album.prune(validCompanionIDs: [])

        let index = try XCTUnwrap(PokopiaTown.index(col: 6, row: 6))
        XCTAssertEqual(album.town.terrain[index], .water)
        XCTAssertEqual(album.town.dittoForm, 25, "개체 정리가 변신을 풀었다")
        XCTAssertEqual(album.town.residents.map(\.speciesID), [7],
                       "개체를 다 비웠는데 마을 인구가 사라졌다")
    }

    /// 전송된 앨범의 마을은 **그대로 살아난다** — 종 번호·이름·타입이라 남의 기기에서도
    /// 뜻이 통한다(남의 마을 인구를 물려받는 셈이다). 못 믿을 값만 정규화가 잘라낸다.
    func testReplaceCarriesTheTownAcrossDevices() throws {
        var access = MemoryHomeAccessSettings()
        access.town.residents = [resident(7, "꼬부기", [.water]), resident(4, "파이리", [.fire])]
        access.town.dittoForm = 25
        let album = PokemonMemoryAlbum(fileURL: memoryAlbumURL("pokopia-replace"))

        album.replace(with: PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:],
                                                        memoryHomeAccess: access),
                      validCompanionIDs: [])

        XCTAssertEqual(album.town.residents.map(\.speciesID), [7, 4],
                       "전송된 마을 인구가 사라졌다")
        XCTAssertEqual(album.town.dittoForm, 25)
    }

    /// 전송분의 못 믿을 지형 길이는 잘린다.
    func testCorruptTerrainLengthFromAnImportIsNormalized() {
        var access = MemoryHomeAccessSettings()
        access.town.terrain = [.water, .water]
        let album = PokemonMemoryAlbum(fileURL: memoryAlbumURL("pokopia-replace-length"))

        album.replace(with: PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:],
                                                        memoryHomeAccess: access),
                      validCompanionIDs: [])

        XCTAssertEqual(album.town.terrain, PokopiaTown.defaultTerrain)
    }
}
