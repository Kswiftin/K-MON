import XCTest
@testable import PokeTokenBar

final class MemoryHomeBundledArtTests: XCTestCase {
    func testInteriorTilesetIsBundledAndDecodable() {
        let image = MemoryHomeBundledArt.interiorTileset()
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }

    func testEachSellableFurniturePieceHasBundledPixelArt() throws {
        for item in [ItemKind.roomBed, .roomTable, .roomLamp] {
            let image = try XCTUnwrap(MemoryHomeBundledArt.furnitureImage(for: item), "Missing art for \(item)")
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }
}
