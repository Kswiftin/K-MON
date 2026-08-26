import CoreGraphics
import Foundation

/// 팔레트 인덱스 격자. 에셋 파일·다운로드 없이 **코드 리터럴**로 도트를 정의한다
/// (`room-walk-dungeon-design.md` "조사 결론"). 0 은 투명.
struct PixelSprite: Equatable, Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height)
        self.width = width; self.height = height; self.pixels = pixels
    }

    /// `.` 과 `key` 에 없는 글자는 투명. 모든 줄은 첫 줄과 같은 길이여야 한다.
    init(rows: [String], key: [Character: UInt8]) {
        let width = rows.first?.count ?? 0
        precondition(rows.allSatisfy { $0.count == width }, "줄 길이가 다르다")
        self.width = width
        self.height = rows.count
        self.pixels = rows.flatMap { row in row.map { key[$0] ?? 0 } }
    }

    func pixel(x: Int, y: Int) -> UInt8 { pixels[y * width + x] }

    var opaqueCount: Int { pixels.filter { $0 != 0 }.count }

    func overlaying(_ top: PixelSprite) -> PixelSprite {
        precondition(top.width == width && top.height == height)
        var out = pixels
        for i in out.indices where top.pixels[i] != 0 { out[i] = top.pixels[i] }
        return PixelSprite(width: width, height: height, pixels: out)
    }

    func flippedHorizontally() -> PixelSprite {
        var out = pixels
        for y in 0..<height {
            let row = Array(pixels[(y * width)..<((y + 1) * width)]).reversed()
            out.replaceSubrange((y * width)..<((y + 1) * width), with: row)
        }
        return PixelSprite(width: width, height: height, pixels: out)
    }
}

struct PixelPalette: Sendable {
    /// `0xRRGGBB`. 인덱스 0 은 투명이라 값이 무시된다.
    let colors: [UInt32]
}

extension PixelSprite {
    /// 정수 배로 확대해 그리는 쪽(`Image.interpolation(.none)`)을 위해 1:1 로 굽는다.
    func cgImage(palette: PixelPalette) -> CGImage? {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for (i, index) in pixels.enumerated() where index != 0 && Int(index) < palette.colors.count {
            let c = palette.colors[Int(index)]
            rgba[i * 4] = UInt8((c >> 16) & 0xFF)
            rgba[i * 4 + 1] = UInt8((c >> 8) & 0xFF)
            rgba[i * 4 + 2] = UInt8(c & 0xFF)
            rgba[i * 4 + 3] = 0xFF
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
