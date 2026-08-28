import XCTest
@testable import PokeTokenBar

final class MemoryHomeBundledArtTests: XCTestCase {
    func testInteriorTilesetIsBundledAndDecodable() {
        let image = MemoryHomeBundledArt.interiorTileset()
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }
}
