import AppKit

/// 미니룸 아트 엔진. 원본은 `MemoryHomePixelArtSprites` 의 문자 격자이고, 이 타입은 그것을
/// 스타일 램프로 칠해 `NSImage` 로 만든다.
///
/// **저장소에 스프라이트 이미지 파일을 두지 않는다.** 이유 세 가지:
///  1. 모든 픽셀이 diff 에 보인다 — PNG 는 리뷰할 수 없다.
///  2. 좌표표(rect)가 없다 — 12 종이 3 개 rect 를 돌려쓰던 부류가 구조적으로 불가능해진다.
///  3. 제3자 에셋이 없다 — 라이선스 공지·해시 게이트가 필요 없고, 오프라인에서 항상 그려진다.
enum MemoryHomePixelArt {

    // MARK: - 팔레트

    struct PixelColor: Equatable, Sendable {
        let r: UInt8, g: UInt8, b: UInt8
        init(_ hex: UInt32) {
            r = UInt8((hex >> 16) & 0xFF); g = UInt8((hex >> 8) & 0xFF); b = UInt8(hex & 0xFF)
        }
    }

    /// 재질 램프 3 개 × 명암 4 단계. 그림은 색이 아니라 인덱스로 그리므로 스타일 4 종이
    /// **같은 격자**에서 나온다. 4 색 시트로는 표현할 수 없던 구분(램프의 빛 vs 나무 기둥)이
    /// `accent` 램프 덕에 생긴다.
    struct Palette: Equatable, Sendable {
        let frame: [PixelColor]   // 1 2 3 4 — 목재·프레임
        let fabric: [PixelColor]  // q w e r — 천·쿠션·잎
        let accent: [PixelColor]  // a s d f — 발광·화면·강조
    }

    /// 세 번째 단계를 `MemoryHomeRoomStyle.tint` 와 같은 색조로 맞춘다 — 스타일 카드 색과
    /// 방 안의 색이 어긋나면 사용자가 고른 스타일이 화면에서 두 가지로 보인다.
    static func palette(for style: MemoryHomeRoomStyle) -> Palette {
        switch style {
        case .campus:
            return Palette(frame: [0x2A1E16, 0x4A3524, 0x6E5138, 0x8E6B4A].map(PixelColor.init),
                           fabric: [0x1B2E3E, 0x2F4C63, 0x4C789E, 0x7FA6C4].map(PixelColor.init),
                           accent: [0x4A3A12, 0x8A6A1C, 0xD8B23C, 0xF5E39B].map(PixelColor.init))
        case .lovely:
            return Palette(frame: [0x2E1A22, 0x52303C, 0x7A4A58, 0x9C6A76].map(PixelColor.init),
                           fabric: [0x3A1826, 0x6A2F47, 0xB86A8A, 0xE7B9CB].map(PixelColor.init),
                           accent: [0x5A2438, 0xA34A6A, 0xE88BA8, 0xFFD6E4].map(PixelColor.init))
        case .retro:
            return Palette(frame: [0x2B1D0E, 0x4A3418, 0x6B4820, 0x8E6430].map(PixelColor.init),
                           fabric: [0x33210E, 0x7A5426, 0xB8863F, 0xE4C889].map(PixelColor.init),
                           accent: [0x14301E, 0x2C6B3E, 0x56B96A, 0xA8F0B0].map(PixelColor.init))
        case .nature:
            return Palette(frame: [0x22190F, 0x3E2E1C, 0x5C462A, 0x7A6038].map(PixelColor.init),
                           fabric: [0x11221E, 0x2B5348, 0x598F7D, 0xA6CFBF].map(PixelColor.init),
                           accent: [0x3A2A0E, 0x7A5A1E, 0xD8B24A, 0xF2E0A0].map(PixelColor.init))
        }
    }

    /// 격자 문자 → 색. 알 수 없는 문자는 투명으로 둔다. 오타 하나가 스프라이트를 통째로 날리는
    /// 대신 그 픽셀만 비므로, 렌더를 보면 어디가 틀렸는지 눈에 띈다.
    static func color(for character: Character, in palette: Palette) -> PixelColor? {
        switch character {
        case "1": return palette.frame[0];  case "2": return palette.frame[1]
        case "3": return palette.frame[2];  case "4": return palette.frame[3]
        case "q": return palette.fabric[0]; case "w": return palette.fabric[1]
        case "e": return palette.fabric[2]; case "r": return palette.fabric[3]
        case "a": return palette.accent[0]; case "s": return palette.accent[1]
        case "d": return palette.accent[2]; case "f": return palette.accent[3]
        default: return nil
        }
    }

    // MARK: - 크기

    /// 방 안에서는 1 픽셀 = 2pt 다. **장면 전체가 같은 배율이어야** 픽셀 크기가 균일해 보인다 —
    /// 가구만 4 배, 벽지만 3 배로 그리면 한 방에 해상도가 두 개 있는 것처럼 보인다.
    static let roomScale = 2
    /// 카탈로그·쇼케이스 썸네일. 좁은 칸에 들어가야 하므로 1 배.
    static let thumbnailScale = 1

    static func displaySize(for item: ItemKind, scale: Int = roomScale) -> CGSize? {
        guard let grid = MemoryHomePixelArtSprites.furniture[item],
              let width = grid.first?.count, width > 0, scale > 0 else { return nil }
        return CGSize(width: width * scale, height: grid.count * scale)
    }

    // MARK: - 공개 API

    static func furnitureImage(for item: ItemKind, style: MemoryHomeRoomStyle,
                               scale: Int = roomScale) -> NSImage? {
        if scale == roomScale { return styledFurniture[style]?[item] }
        guard let grid = MemoryHomePixelArtSprites.furniture[item] else { return nil }
        return render(grid, palette: palette(for: style), scale: scale)
    }

    static func wallpaperTile(for style: MemoryHomeRoomStyle) -> NSImage? { styledTiles[style]?.wallpaper }
    static func floorTile(for style: MemoryHomeRoomStyle) -> NSImage? { styledTiles[style]?.floor }

    // MARK: - 캐시

    /// 48 조합(12 종 × 4 스타일)을 한 번만 그려 들고 있는다. 방을 다시 그릴 때마다 래스터화하면
    /// 드래그 중 매 프레임 비트맵을 만들게 된다. 전부 32×32 이하라 총량은 수십 KB 다.
    private static let styledFurniture: [MemoryHomeRoomStyle: [ItemKind: NSImage]] = {
        var table: [MemoryHomeRoomStyle: [ItemKind: NSImage]] = [:]
        for style in MemoryHomeRoomStyle.allCases {
            let palette = palette(for: style)
            var row: [ItemKind: NSImage] = [:]
            for (item, grid) in MemoryHomePixelArtSprites.furniture {
                guard let image = render(grid, palette: palette, scale: roomScale) else { continue }
                row[item] = image
            }
            table[style] = row
        }
        return table
    }()

    private static let styledTiles: [MemoryHomeRoomStyle: (wallpaper: NSImage, floor: NSImage)] = {
        var table: [MemoryHomeRoomStyle: (NSImage, NSImage)] = [:]
        for style in MemoryHomeRoomStyle.allCases {
            let palette = palette(for: style)
            guard let wallpaper = render(MemoryHomePixelArtSprites.wallpaper, palette: palette, scale: roomScale),
                  let floor = render(MemoryHomePixelArtSprites.floor, palette: palette, scale: roomScale) else { continue }
            table[style] = (wallpaper, floor)
        }
        return table
    }()

    // MARK: - 래스터화

    /// 격자를 그대로 픽셀에 찍는다. 확대는 **정수배로 픽셀을 복제**해서 하므로 보간이 개입할 여지가
    /// 없다 — `.interpolation(.none)` 에 기대는 대신 애초에 원하는 크기로 만든다.
    static func render(_ grid: [String], palette: Palette, scale: Int) -> NSImage? {
        guard scale > 0, let firstRow = grid.first, !firstRow.isEmpty,
              grid.allSatisfy({ $0.count == firstRow.count }) else { return nil }
        let cols = firstRow.count, rows = grid.count
        let width = cols * scale, height = rows * scale
        let rowCharacters = grid.map(Array.init)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<rows {
                for x in 0..<cols {
                    guard let color = color(for: rowCharacters[y][x], in: palette) else { continue }
                    // 픽셀 하나를 scale × scale 블록으로 복제한다.
                    for dy in 0..<scale {
                        let rowOffset = (y * scale + dy) * width
                        for dx in 0..<scale {
                            let offset = (rowOffset + x * scale + dx) * 4
                            base[offset] = color.r; base[offset + 1] = color.g
                            base[offset + 2] = color.b; base[offset + 3] = 255
                        }
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cg, size: CGSize(width: width, height: height))
    }
}
