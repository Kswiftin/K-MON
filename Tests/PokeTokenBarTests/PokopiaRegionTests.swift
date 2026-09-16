import XCTest
@testable import PokeTokenBar

// MARK: 포코피아 7단계 — 지역 다섯 · 전역 상한 · 되돌리기 격리
//
// 이 파일이 지키는 것은 셋이다.
// ① 지역 표(`TownRegion.base`)가 다섯 지역에 서로 다른, **부르는** 바탕을 준다
// ② 전역 상한이 마을당 상한 × 5 보다 **낮다** — 같거나 크면 "어느 마을을 키울지 고른다" 가 사라진다
// ③ 저장 형태가 JSON **객체**다 — String rawValue enum 을 딕셔너리 키로 쓰면 배열로 굽힌다

@MainActor
final class PokopiaRegionTests: XCTestCase {

    private func resident(_ speciesID: Int, _ name: String, _ types: [PokemonType]) -> TownResident {
        TownResident(speciesID: speciesID, name: name, types: types,
                     arrivedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// 주민으로 **받아들여지는** 종 번호를 앞에서부터 모은다. `PokopiaTown.isAdmissible` 이
    /// 스프라이트 없는 종을 거절하므로(`PokemonAssets.spriteGaps`), 번호를 손으로 적으면
    /// 구멍에 걸린 테스트가 "상한 때문에 거절됐다" 처럼 보인다.
    private func drawableSpeciesIDs(_ count: Int) -> [Int] {
        var ids: [Int] = []
        var candidate = 1
        while ids.count < count && candidate < 2_000 {
            if PokemonAssets.hasAnimatedSprite(speciesID: candidate) { ids.append(candidate) }
            candidate += 1
        }
        XCTAssertEqual(ids.count, count, "그릴 수 있는 종이 \(count)개가 안 된다")
        return ids
    }

    // MARK: 지역 표

    /// 다섯 지역의 바탕이 **서로 다르다.** 둘이 같으면 그 둘은 1일차에 같은 타입을 부르고,
    /// 지역을 나눈 것이 이름표가 된다.
    func testEveryRegionHasItsOwnBaseTerrain() {
        let bases = TownRegion.allCases.map(\.base)
        XCTAssertEqual(Set(bases).count, TownRegion.allCases.count,
                       "바탕이 겹치는 지역이 있다 — 그 둘은 같은 마을이다")
    }

    /// 화면 이름이 **다섯 다 다르고 비지 않는다.** 겹치면 Picker 칸 둘이 같은 글자가 되어
    /// 사용자가 어느 쪽을 누르는지 모른다(`TownWeather` 의 `everyWeatherHasItsOwnPrefix` 와 같은 축).
    func testEveryRegionHasItsOwnScreenName() {
        let names = TownRegion.allCases.map(\.name)
        XCTAssertEqual(Set(names).count, TownRegion.allCases.count, "이름이 겹치는 지역이 있다")
        XCTAssertTrue(names.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                      "이름이 빈 지역이 있다")
    }

    /// **다섯 지역을 다 돈다.** 하나만 돌리면 `base` 를 잘못 써도 통과한다. 1일차 마을이 아무도
    /// 안 부르면 첫 세션의 이사 판정이 영영 빈손이고, 사용자는 기능이 도는지도 모른다.
    func testEveryRegionsDefaultTownAlreadyCallsSomething() {
        for region in TownRegion.allCases {
            let terrain = PokopiaTown.defaultTerrain(for: region)
            let development = PokopiaTown.development(terrain, residents: [])
            XCTAssertGreaterThanOrEqual(development.habitats, 1,
                                        "\(region.name) 의 1일차 마을이 아무 타입도 안 부른다")
            XCTAssertFalse(PokopiaTown.welcomingTypes(terrain).isEmpty,
                           "\(region.name) 의 바탕에 대응하는 타입이 없다")
        }
    }

    /// 맨 아래 줄은 **언제나 길**이다 — 아바타가 서는 자리라 지역마다 다르면 물 위에 선다.
    func testTheBottomRowIsAlwaysPathInEveryRegion() {
        for region in TownRegion.allCases {
            let terrain = PokopiaTown.defaultTerrain(for: region)
            XCTAssertEqual(terrain.count, PokopiaTown.tileCount, "\(region.name) 격자 길이")
            XCTAssertTrue(terrain.suffix(PokopiaTown.columns).allSatisfy { $0 == .path },
                          "\(region.name) 의 맨 아래 줄이 길이 아니다 — 아바타 자리다")
        }
    }

    // MARK: 상수 등식

    /// **`globalPopulationLimit < 5 × populationLimit`.** 같거나 크면 다섯 마을을 전부 꽉 채울 수
    /// 있고, 그러면 전역 상한을 둔 목적이 사라진다.
    func testTheGlobalLimitIsLowerThanFiveTownsWorth() {
        XCTAssertLessThan(PokopiaTown.globalPopulationLimit,
                          TownRegion.allCases.count * PokopiaTown.populationLimit,
                          "전역 상한이 마을당 상한 × 지역 수 이상이다 — 고를 이유가 없어졌다")
        XCTAssertGreaterThan(PokopiaTown.globalPopulationLimit, PokopiaTown.populationLimit,
                             "전역 상한이 마을 하나도 못 채운다")
    }

    // MARK: 저장 형태

    /// **`towns` 는 JSON 객체로 굽힌다.** `[TownRegion: …]`(String rawValue enum 키)로 쓰면 Swift
    /// Codable 이 `{"towns":["waste",{…}]}` 처럼 **배열**로 굽는다 — 그 형태로 나간 세이브는
    /// 지역 이름을 잃는다. 이 테스트가 그 되돌림을 기계로 막는다.
    func testTheTownsDictionaryBakesAsAJSONObject() throws {
        var state = PokopiaState()
        state.towns[TownRegion.coast.rawValue] = PokopiaTownState(region: .coast)

        let data = try JSONEncoder().encode(state)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let towns = root["towns"]
        XCTAssertNil(towns as? [Any], "towns 가 배열로 굽혔다 — 지역 이름이 값 사이에 끼었다")
        let object = try XCTUnwrap(towns as? [String: Any], "towns 가 객체가 아니다")
        XCTAssertNotNil(object[TownRegion.coast.rawValue], "해안 키가 없다")
    }

    /// 안 만든 지역은 **저장에 안 들어간다** — 포코피아를 한 번도 안 연 사용자의 세이브가
    /// 다섯 마을만큼 커지지 않는다.
    func testUntouchedRegionsAreNotStored() {
        let album = PokemonMemoryAlbum(fileURL: memoryAlbumURL("pokopia-region-lazy"))
        XCTAssertTrue(album.shapeTownTile(col: 2, row: 2, to: .water))

        XCTAssertEqual(album.pokopia.towns.count, 1, "안 건드린 지역이 저장에 들어갔다")
        XCTAssertNotNil(album.pokopia.towns[TownRegion.waste.rawValue])
        XCTAssertEqual(album.pokopia.town(.coast).terrain, PokopiaTown.defaultTerrain(for: .coast),
                       "안 만든 지역이 자기 바탕으로 안 열린다")
    }

    // MARK: 신뢰경계

    /// **모르는 지역 키는 버린다.** 던지면 그 예외 하나가 앨범을 `.corrupt` 로 밀어내
    /// 기존 사용자 전원의 기억이 백업 파일로 간다.
    func testAnUnknownRegionKeyIsDroppedInsteadOfCorruptingTheAlbum() throws {
        let file = memoryAlbumURL("pokopia-region-unknown-key")
        var access = MemoryHomeAccessSettings()
        access.visitTotal = 5
        var state = PokopiaState()
        state.towns["atlantis"] = PokopiaTownState()
        state.towns[TownRegion.waste.rawValue] = PokopiaTownState(region: .waste)
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:],
                                                  memoryHomeAccess: access, pokopia: state)
        try JSONEncoder().encode(snapshot).write(to: file)

        let album = PokemonMemoryAlbum(fileURL: file)

        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 5, "앨범이 손상 처리됐다")
        XCTAssertNil(album.pokopia.towns["atlantis"], "모르는 지역 키가 남았다")
        XCTAssertNotNil(album.pokopia.towns[TownRegion.waste.rawValue], "멀쩡한 지역까지 지웠다")
    }

    /// **모르는 `home` 값도 던지지 않는다.** 합성 디코드에 맡기면 여기서 `dataCorrupted` 가 나고
    /// 앨범 전체가 밀려난다 — `PokopiaState.init(from:)` 이 `try?` 를 쓰는 이유다.
    func testAnUnknownHomeRegionFallsBackInsteadOfThrowing() throws {
        let file = memoryAlbumURL("pokopia-region-unknown-home")
        var access = MemoryHomeAccessSettings()
        access.visitTotal = 9
        let snapshot = PokemonMemoryAlbumSnapshot(memories: [:], pinnedMemoryIDs: [:],
                                                  memoryHomeAccess: access)
        var root = try XCTUnwrap(try JSONSerialization
            .jsonObject(with: try JSONEncoder().encode(snapshot)) as? [String: Any])
        var pokopia = try XCTUnwrap(root["pokopia"] as? [String: Any])
        pokopia["home"] = "atlantis"
        root["pokopia"] = pokopia
        try JSONSerialization.data(withJSONObject: root).write(to: file)

        let album = PokemonMemoryAlbum(fileURL: file)

        XCTAssertEqual(album.memoryHomeAccess.visitTotal, 9, "앨범이 손상 처리됐다")
        XCTAssertEqual(album.region, .waste, "모르는 지역이 그대로 남았다")
    }

    // MARK: 지역 전환 · 되돌리기 격리

    /// 지역을 바꾸면 **그 지역의 마을**이 보인다. 편집도 그리로 간다.
    func testSelectingARegionSwitchesWhichTownIsEdited() throws {
        let album = PokemonMemoryAlbum(fileURL: memoryAlbumURL("pokopia-region-switch"))
        let index = try XCTUnwrap(PokopiaTown.index(col: 3, row: 3))
        XCTAssertTrue(album.shapeTownTile(col: 3, row: 3, to: .water))

        XCTAssertTrue(album.selectRegion(.ridge))
        XCTAssertFalse(album.selectRegion(.ridge), "같은 지역을 다시 고르는 것은 no-op 이다")

        XCTAssertEqual(album.town.terrain[index], PokopiaTown.defaultTerrain(for: .ridge)[index],
                       "지역을 바꿨는데 앞 지역의 지형이 보인다")
        XCTAssertTrue(album.shapeTownTile(col: 3, row: 3, to: .flower))
        XCTAssertEqual(album.pokopia.town(.waste).terrain[index], .water,
                       "산지에 민 것이 황야를 덮었다")
    }

    /// 지역과 선택이 **저장에서 살아난다.**
    func testTheSelectedRegionSurvivesReload() {
        let file = memoryAlbumURL("pokopia-region-reload")
        let album = PokemonMemoryAlbum(fileURL: file)
        XCTAssertTrue(album.selectRegion(.isle))
        XCTAssertTrue(album.shapeTownTile(col: 1, row: 1, to: .water))

        let reloaded = PokemonMemoryAlbum(fileURL: file)

        XCTAssertEqual(reloaded.region, .isle, "`CodingKeys` 에 home 이 빠졌다")
        XCTAssertEqual(reloaded.pokopia.towns.count, 1)
    }

    /// **트리거 브랜치.** 해안에서 되돌리기를 눌러도 황야의 편집이 안 돌아간다. 스택이 한 벌이면
    /// 여기서 황야의 칸이 풀로 되돌아간다.
    func testUndoInOneRegionDoesNotTouchAnother() throws {
        let album = PokemonMemoryAlbum(fileURL: memoryAlbumURL("pokopia-region-undo"))
        let index = try XCTUnwrap(PokopiaTown.index(col: 4, row: 4))
        XCTAssertTrue(album.shapeTownTile(col: 4, row: 4, to: .flower))

        XCTAssertTrue(album.selectRegion(.coast))
        XCTAssertFalse(album.canUndoTownEdit, "새 지역인데 앞 지역의 스택이 보인다")
        XCTAssertTrue(album.shapeTownTile(col: 4, row: 4, to: .tree))
        album.undoTownEdit()

        XCTAssertEqual(album.town.terrain[index], PokopiaTown.defaultTerrain(for: .coast)[index],
                       "해안이 안 되돌아갔다")
        XCTAssertTrue(album.selectRegion(.waste))
        XCTAssertEqual(album.town.terrain[index], .flower,
                       "해안에서 누른 되돌리기가 황야를 되돌렸다")
        XCTAssertTrue(album.canUndoTownEdit, "황야의 스택이 사라졌다")
    }

    // MARK: 전역 상한

    /// 전역 상한에 닿으면 이사가 **멈춘다.** 그리고 **아무도 사라지지 않는다** — 자동 퇴거는 없다.
    func testTheGlobalLimitStopsImmigrationWithoutEvicting() {
        let album = PokemonMemoryAlbum(fileURL: memoryAlbumURL("pokopia-region-global-limit"))
        let perRegion = PokopiaTown.populationLimit
        let ids = drawableSpeciesIDs(TownRegion.allCases.count * perRegion + 1)
        // 마을당 상한(16)이 아니라 전역 상한(60)에 닿게 지역을 옮겨 가며 채운다.
        for (offset, region) in TownRegion.allCases.enumerated() {
            _ = album.selectRegion(region)
            for id in ids[(offset * perRegion)..<((offset + 1) * perRegion)] {
                _ = album.admitTownResident(resident(id, "주민\(id)", [.water]))
            }
        }

        XCTAssertEqual(album.pokopia.totalResidents, PokopiaTown.globalPopulationLimit,
                       "전역 상한을 넘거나 못 미쳤다")
        XCTAssertFalse(album.admitTownResident(resident(ids[ids.count - 1], "한 명 더", [.water])),
                       "전역 상한을 넘겨 받았다")
        XCTAssertEqual(album.pokopia.totalResidents, PokopiaTown.globalPopulationLimit,
                       "거절하면서 누군가를 내보냈다 — 자동 퇴거는 없다")
    }

    /// 상한에 닿아도 **정규화가 자르지 않는다.** 잘라 버리면 지역을 옮길 때마다 주민이 사라진다.
    func testNormalizationDoesNotEnforceTheGlobalLimit() {
        let perRegion = PokopiaTown.populationLimit
        let ids = drawableSpeciesIDs(TownRegion.allCases.count * perRegion)
        var state = PokopiaState()
        for (offset, region) in TownRegion.allCases.enumerated() {
            var town = PokopiaTownState(region: region)
            town.residents = ids[(offset * perRegion)..<((offset + 1) * perRegion)]
                .map { resident($0, "주민\($0)", [.water]) }
            state.towns[region.rawValue] = town
        }
        let before = state.totalResidents
        XCTAssertGreaterThan(before, PokopiaTown.globalPopulationLimit, "이 테스트의 전제가 깨졌다")

        let after = PokopiaTown.normalized(state)

        XCTAssertEqual(after.totalResidents, before,
                       "신뢰경계가 전역 상한을 적용했다 — 자동 퇴거다")
    }
}
