import XCTest
@testable import PokeTokenBar

/// 타일 도트는 리터럴이라 손으로 고치다 줄 길이가 어긋나면 `PixelSprite` 의 precondition 이
/// **앱 실행 중에** 죽는다. 타입체크로는 안 잡히므로 전 타일을 여기서 한 번 만들어 본다.
final class RoomTileArtTests: XCTestCase {

    func testEveryTileIsSixteenSquareAndBakes() {
        for tile in RoomTile.allCases {
            let sprite = RoomTileArt.sprite(for: tile)
            XCTAssertEqual(sprite.width, RoomTileArt.size, "\(tile) 폭")
            XCTAssertEqual(sprite.height, RoomTileArt.size, "\(tile) 높이")
            XCTAssertGreaterThan(sprite.opaqueCount, 0, "\(tile) 이 통째로 투명하다")
            XCTAssertNotNil(RoomTileArt.image(tile), "\(tile) 굽기 실패")
        }
    }

    /// 팔레트 밖 인덱스는 예외가 아니라 **조용히 투명**으로 빠진다 — 색이 하나 사라진 타일이
    /// 그럴듯하게 그려져 눈치채기 어렵다.
    func testNoPixelPointsPastThePalette() {
        for tile in RoomTile.allCases {
            let sprite = RoomTileArt.sprite(for: tile)
            let highest = sprite.pixels.max() ?? 0
            XCTAssertLessThan(Int(highest), RoomTileArt.palette.colors.count, "\(tile) 팔레트 밖 인덱스")
        }
    }

    /// 내 방(0번)은 벽지·마루라 던전 타일과 색이 달라야 한다 — 같으면 "여긴 내 방" 이 안 읽힌다.
    func testHomeTilesDifferFromDungeonTiles() {
        XCTAssertNotEqual(RoomTileArt.sprite(for: .floor), RoomTileArt.sprite(for: .floorHome))
        XCTAssertNotEqual(RoomTileArt.sprite(for: .wall), RoomTileArt.sprite(for: .wallHome))
    }

    /// 장식은 바닥 위에 얹으므로 사방이 다 채워져 있으면 바닥이 사라진다.
    func testDecorTilesStayMostlyTransparent() {
        for decor in [FloorDecor.crack, .moss, .pebble] {
            let tile = RoomTile(decor: decor)
            XCTAssertNotNil(tile)
            guard let tile else { continue }
            let sprite = RoomTileArt.sprite(for: tile)
            XCTAssertLessThan(sprite.opaqueCount, sprite.width * sprite.height / 4, "\(decor) 가 바닥을 덮는다")
        }
        XCTAssertNil(RoomTile(decor: .none), "그릴 것이 없는 장식은 타일이 없다")
    }
}
