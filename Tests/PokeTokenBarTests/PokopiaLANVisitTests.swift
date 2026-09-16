import XCTest
@testable import PokeTokenBar

// MARK: 포코피아 8단계 — 친구 마을 방문 (LAN)
//
// 이 파일이 지키는 것은 셋이다.
// ① **동의** — `sharesTown` 은 기본 꺼짐이고, 이 키가 없던 세이브도 꺼짐으로 열린다
// ② **신뢰경계** — 원격 마을은 거절이 아니라 `PokopiaTown.normalized` 로 수리하고,
//    되돌리는 바탕은 **보낸 쪽의 지역**이다(전역 기본이면 해안 마을이 풀밭이 된다)
// ③ **수명** — 이웃 마을은 `stop()`(VISIT 탭 나가기)이 지우지 않는다. 화면이 다른 창에 있다

@MainActor
final class PokopiaLANVisitTests: XCTestCase {

    /// 마을에 **받아들여지는** 종 번호를 앞에서부터 모은다. 번호를 손으로 적으면 스프라이트
    /// 구멍(`PokemonAssets.spriteGaps`)에 걸린 테스트가 "상한이 잘랐다" 처럼 보인다.
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

    private func resident(_ speciesID: Int, name: String = "이웃") -> TownResident {
        TownResident(speciesID: speciesID, name: name, types: [.water],
                     arrivedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: 동의

    /// 마을은 8단계 전까지 LAN 에 안 나가던 데이터다. 기본값을 공개로 두면 업데이트 즉시
    /// 기존 공개 사용자 전원의 마을이 **사용자가 모르는 채** 나간다.
    func testSharesTownDefaultsToOff() {
        let album = PokemonMemoryAlbum(fileURL: memoryAlbumURL("pokopia-lan-default"))
        XCTAssertFalse(album.memoryHomeAccess.sharesTown, "마을 공유가 기본으로 켜져 있다")
        XCTAssertNil(album.townForSharing, "동의 없이 공유용 마을이 나왔다")
    }

    /// `sharesTown` 키가 없던 세이브가 **그대로 열린다.** 비옵셔널 `decode` 를 쓰면 기존 사용자
    /// 전원의 앨범이 `.corrupt` 로 밀려난다 — 그때 이 테스트는 "문구가 사라졌다" 로 빨개진다.
    func testOldSaveWithoutTheKeyDecodesToOff() throws {
        let url = memoryAlbumURL("pokopia-lan-oldsave")
        let album = PokemonMemoryAlbum(fileURL: url)
        XCTAssertTrue(album.setProfileMessage("피카츄랑 여행중"))
        album.setSharesTown(true)

        // 지금 코드로 구운 세이브에서 키만 지운다 — 손으로 JSON 을 적으면 형태가 실제 세이브와
        // 갈리고, 갈린 쪽을 검증하는 테스트가 된다.
        var text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"sharesTown\""), "구운 세이브에 키가 없다 — 테스트가 아무것도 안 지운다")
        text = text.replacingOccurrences(of: "\"sharesTown\":true,", with: "")
                   .replacingOccurrences(of: ",\"sharesTown\":true", with: "")
        try text.write(to: url, atomically: true, encoding: .utf8)

        let reopened = PokemonMemoryAlbum(fileURL: url)
        XCTAssertEqual(reopened.memoryHomeAccess.profileMessage, "피카츄랑 여행중",
                       "키 하나가 없어서 앨범 전체가 `.corrupt` 로 밀려났다")
        XCTAssertFalse(reopened.memoryHomeAccess.sharesTown, "키 없는 세이브가 공개로 열렸다")
    }

    /// 카드가 읽는 것은 `townForSharing` 파생 하나다. 토글을 끄면 즉시 나오지 않아야 한다.
    func testTownForSharingFollowsTheToggle() {
        let album = PokemonMemoryAlbum(fileURL: memoryAlbumURL("pokopia-lan-toggle"))
        album.selectRegion(.coast)

        album.setSharesTown(true)
        let shared = album.townForSharing
        XCTAssertEqual(shared?.region, .coast, "공유용 마을의 지역이 보고 있는 지역과 다르다")
        XCTAssertEqual(shared?.town, album.town, "공유용 마을이 보고 있는 마을과 다르다")

        album.setSharesTown(false)
        XCTAssertNil(album.townForSharing, "공유를 껐는데도 마을이 나온다")
    }

    // MARK: 신뢰경계 — 거절이 아니라 수리

    /// 남이 보낸 마을은 **고쳐서 그린다.** 지형 길이·주민 중복·인구 상한·스프라이트를 전부
    /// `normalized` 하나가 맡는다 — 거절하면 상대가 살짝 어긋난 마을을 보냈을 때 아무것도
    /// 안 보이고, 이유도 화면에 없다.
    func testCorruptRemoteTownIsRepairedNotRejected() throws {
        let ids = drawableSpeciesIDs(PokopiaTown.populationLimit + 4)
        let gap = try XCTUnwrap(PokemonAssets.spriteGaps.min(), "스프라이트 구멍이 하나도 없다")

        var town = PokopiaTownState(region: .coast)
        town.terrain = [.water, .sand, .rock]                       // 길이가 틀렸다
        town.residents = ids.map { resident($0) }                   // 20명 — 상한을 넘는다
            + [resident(ids[0])]                                    // 중복 — 종이 곧 정체다
            + [resident(gap, name: "못 그리는 종")]                   // 이 기기에 스프라이트가 없다
            + [resident(-1, name: "음수 종")]

        let repaired = PokopiaTown.normalized(town, region: .coast)

        XCTAssertEqual(repaired.terrain.count, PokopiaTown.tileCount, "지형 길이가 복원되지 않았다")
        XCTAssertLessThanOrEqual(repaired.residents.count, PokopiaTown.populationLimit,
                                 "인구 상한을 넘는 마을이 그대로 통과했다")
        XCTAssertEqual(Set(repaired.residents.map(\.speciesID)).count, repaired.residents.count,
                       "같은 종이 두 번 사는 마을이 통과했다")
        XCTAssertFalse(repaired.residents.contains { $0.speciesID == gap },
                       "이 기기에 그릴 수 없는 종이 주민으로 남았다")
        XCTAssertFalse(repaired.residents.contains { $0.speciesID <= 0 }, "종 번호가 양수가 아닌 주민이 남았다")
    }

    /// 되돌리는 바탕은 **보낸 쪽의 지역**이다. 전역 기본으로 되돌리면 해안 마을이 풀밭이 되어,
    /// 사용자가 만들지도 않은 바탕이 남의 마을로 그려진다.
    func testRepairedTownUsesTheSendersRegionBase() {
        var town = PokopiaTownState(region: .coast)
        town.terrain = [.grass]

        let repaired = PokopiaTown.normalized(town, region: .coast)
        XCTAssertEqual(repaired.terrain, PokopiaTown.defaultTerrain(for: .coast),
                       "해안 마을이 해안 바탕으로 복원되지 않았다")
        XCTAssertEqual(repaired.terrain.first, TownRegion.coast.base, "복원된 바탕이 해안의 것이 아니다")
    }

    // MARK: 수명 — VISIT 탭을 떠나도 남는다

    private func center(_ tag: String) -> MemoryHomeVisitCenter {
        MemoryHomeVisitCenter(companion: CompanionStore(fileURL: storeStateURL(tag)), peerID: UUID())
    }

    private func card(withTown town: PokopiaTownState?, region: TownRegion? = .coast) -> MemoryHomeProfileCard {
        MemoryHomeProfileCard(displayName: "이웃", speciesID: 25, isShiny: false,
                              sharedMemoryBody: nil, profileMessage: nil,
                              town: town, townRegion: town == nil ? nil : region)
    }

    /// 받는 순간 정규화를 통과한다 — `receiveResponse` 가 이 메서드 하나를 부른다.
    func testAcceptingACardNormalizesTheRemoteTown() throws {
        let visits = center("pokopia-lan-accept")
        var town = PokopiaTownState(region: .coast)
        town.terrain = [.grass]
        visits.acceptProfileCard(card(withTown: town))

        let visited = try XCTUnwrap(visits.visitedTown, "마을을 실은 카드를 받았는데 이웃 마을이 없다")
        XCTAssertEqual(visited.region, .coast)
        XCTAssertEqual(visited.ownerName, "이웃")
        XCTAssertEqual(visited.town.terrain.count, PokopiaTown.tileCount,
                       "원격 마을이 정규화를 안 거치고 그대로 담겼다")
    }

    /// **이 한 줄이 이 단계 UX 의 전부다.** `stop()` 이 이웃 마을을 지우면, VISIT 탭을 나가는
    /// 순간 포코피아 창의 이웃 마을이 사라져 사용자가 하려던 동작(방문 → 포코피아 창에서 보기)이
    /// 통째로 불가능해진다.
    func testLeavingTheVisitTabKeepsTheNeighborTown() {
        let visits = center("pokopia-lan-stop")
        visits.acceptProfileCard(card(withTown: PokopiaTownState(region: .coast)))
        XCTAssertNotNil(visits.visitedTown)

        visits.stop()
        XCTAssertNil(visits.selectedProfile, "VISIT 탭을 떠났는데 원격 카드가 남았다")
        XCTAssertNotNil(visits.visitedTown,
                        "VISIT 탭을 떠나는 것만으로 이웃 마을이 사라졌다 — 포코피아 창에서 볼 길이 없다")
    }

    /// 지우는 길은 다음 방문과 `shutdown()` 둘뿐이다.
    func testShutdownClearsTheNeighborTown() {
        let visits = center("pokopia-lan-shutdown")
        visits.acceptProfileCard(card(withTown: PokopiaTownState(region: .coast)))
        visits.shutdown()
        XCTAssertNil(visits.visitedTown, "앱을 접었는데 이웃 마을이 남았다")
    }

    /// 마을을 안 공개한 집을 이어서 방문하면 **비워진다.** 안 덮으면 직전 집의 마을이 남아,
    /// 화면이 방금 방문한 집의 마을을 보여 주는 것처럼 읽힌다.
    func testVisitingAHomeWithoutATownClearsTheNeighbor() {
        let visits = center("pokopia-lan-overwrite")
        visits.acceptProfileCard(card(withTown: PokopiaTownState(region: .coast)))
        XCTAssertNotNil(visits.visitedTown)

        visits.acceptProfileCard(card(withTown: nil))
        XCTAssertNil(visits.visitedTown, "마을을 안 보낸 집을 방문했는데 직전 집의 마을이 남았다")
    }
}
