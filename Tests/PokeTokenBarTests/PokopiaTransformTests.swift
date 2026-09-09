import XCTest
@testable import PokeTokenBar

// MARK: 포코피아 마을 — 메타몽 변신

@MainActor
final class PokopiaTransformTests: XCTestCase {
    private func album(_ tag: String = "pokopia-transform") -> PokemonMemoryAlbum {
        PokemonMemoryAlbum(fileURL: memoryAlbumURL(tag))
    }

    /// 쓰기 자리의 신뢰경계. 도감 밖 종은 거절하고 **해제(`nil`)는 항상 허용**한다 —
    /// 해제를 막으면 도감에서 사라진 종으로 변신한 사용자가 트레이너로 못 돌아온다.
    func testTransformRequiresARegisteredSpeciesAndUnsetIsAlwaysAllowed() {
        let album = album()
        XCTAssertFalse(album.setDittoForm(9_999, registeredSpecies: [25]), "도감 밖 종")
        XCTAssertNil(album.town.dittoForm)

        XCTAssertTrue(album.setDittoForm(25, registeredSpecies: [25]))
        XCTAssertEqual(album.town.dittoForm, 25)

        XCTAssertTrue(album.setDittoForm(nil, registeredSpecies: []), "해제는 도감과 무관하다")
        XCTAssertNil(album.town.dittoForm)
    }

    /// 빈 도감에서는 어떤 종으로도 변신할 수 없다 — 신규 사용자의 상태다.
    func testEmptyDexAllowsNoTransform() {
        let album = album()
        XCTAssertFalse(album.setDittoForm(25, registeredSpecies: []))
        XCTAssertNil(album.town.dittoForm)
    }

    /// 같은 값을 다시 넣으면 `false` 다 — undo 스택에 빈 항목을 쌓지 않는다.
    func testSettingTheSameFormIsANoOp() {
        let album = album()
        XCTAssertTrue(album.setDittoForm(25, registeredSpecies: [25]))
        XCTAssertFalse(album.setDittoForm(25, registeredSpecies: [25]))
    }

    /// 이미 해제 상태에서 해제를 또 부르면 `false` — 위와 같은 이유.
    func testUnsettingWhenAlreadyUnsetIsANoOp() {
        let album = album()
        XCTAssertFalse(album.setDittoForm(nil, registeredSpecies: [25]))
        XCTAssertFalse(album.canUndoTownEdit)
    }

    func testTransformPersistsAcrossRestart() {
        let file = memoryAlbumURL("pokopia-transform-restart")
        let album = PokemonMemoryAlbum(fileURL: file)
        XCTAssertTrue(album.setDittoForm(25, registeredSpecies: [25]))
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: file).town.dittoForm, 25)
    }

    /// 변신은 편집이라 되돌릴 수 있다.
    func testTransformIsUndoable() {
        let album = album()
        XCTAssertTrue(album.setDittoForm(25, registeredSpecies: [25]))
        album.undoTownEdit()
        XCTAssertNil(album.town.dittoForm)
    }

    // MARK: 변신 ↔ 브러시

    /// **변신이 규칙에 닿는 지점.** 변신한 종의 타입이 밀 수 있는 지형을 정하고,
    /// 변신하지 않으면 아무것도 못 민다. 이 연결이 끊기면 변신은 아바타 그림만 바꾸는 장식이 된다.
    func testTransformDecidesWhatCanBeShaped() {
        XCTAssertNil(PokopiaTown.brush(dittoFormTypes: nil), "변신 전에 밀 수 있으면 안 된다")
        XCTAssertEqual(PokopiaTown.brush(dittoFormTypes: [.water]), .water)
        XCTAssertEqual(PokopiaTown.brush(dittoFormTypes: [.fire]), .sand)
        XCTAssertNotEqual(PokopiaTown.brush(dittoFormTypes: [.water]),
                          PokopiaTown.brush(dittoFormTypes: [.fire]),
                          "무엇으로 변신하든 같은 지형이 나온다")
    }

    /// 18 타입 전부가 브러시를 가진다 — 어떤 종으로 변신해도 뭔가는 밀 수 있다.
    func testEveryTypeYieldsABrushWhenTransformed() {
        for type in PokemonType.allCases {
            XCTAssertNotNil(PokopiaTown.brush(dittoFormTypes: [type]),
                            "\(type) 으로 변신하면 아무것도 못 민다")
        }
    }

    /// 변신 해제가 브러시를 되돌린다 — 앨범과 표를 함께 지나는 왕복이다.
    func testUnsettingTheFormTakesTheBrushAway() {
        let album = album()
        XCTAssertTrue(album.setDittoForm(25, registeredSpecies: [25]))
        XCTAssertEqual(album.town.dittoForm, 25)
        XCTAssertTrue(album.setDittoForm(nil, registeredSpecies: []))
        XCTAssertNil(album.town.dittoForm)
        XCTAssertNil(PokopiaTown.brush(dittoFormTypes: nil))
    }
}
