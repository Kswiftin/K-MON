import XCTest
@testable import PokeTokenBar

final class PixelSpriteTests: XCTestCase {
    private let key: [Character: UInt8] = ["a": 1, "b": 2]

    func testRowsParseIntoIndices() {
        let s = PixelSprite(rows: ["a.", ".b"], key: key)
        XCTAssertEqual(s.width, 2); XCTAssertEqual(s.height, 2)
        XCTAssertEqual(s.pixel(x: 0, y: 0), 1)
        XCTAssertEqual(s.pixel(x: 1, y: 0), 0)
        XCTAssertEqual(s.pixel(x: 1, y: 1), 2)
        XCTAssertEqual(s.opaqueCount, 2)
    }

    func testOverlayReplacesOnlyOpaquePixels() {
        let base = PixelSprite(rows: ["aa", "aa"], key: key)
        let top = PixelSprite(rows: [".b", ".."], key: key)
        let out = base.overlaying(top)
        XCTAssertEqual(out.pixel(x: 1, y: 0), 2)
        XCTAssertEqual(out.pixel(x: 0, y: 0), 1, "투명 픽셀은 아래를 지우지 않는다")
    }

    func testFlipMirrorsColumns() {
        let s = PixelSprite(rows: ["ab"], key: key).flippedHorizontally()
        XCTAssertEqual(s.pixel(x: 0, y: 0), 2)
        XCTAssertEqual(s.pixel(x: 1, y: 0), 1)
    }

    func testBakesToImageOfSameSize() {
        let s = PixelSprite(rows: ["a.", ".b"], key: key)
        let img = s.cgImage(palette: PixelPalette(colors: [0, 0xFF0000, 0x00FF00]))
        XCTAssertEqual(img?.width, 2); XCTAssertEqual(img?.height, 2)
    }

    func testUnknownCharacterInRowsIsTransparent() {
        let s = PixelSprite(rows: ["x"], key: key)
        XCTAssertEqual(s.pixel(x: 0, y: 0), 0)
    }
}
