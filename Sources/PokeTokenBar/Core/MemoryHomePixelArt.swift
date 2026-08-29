import AppKit

/// 미니룸 아트 엔진. 원본은 `MemoryHomePixelArtSprites` 의 문자 격자이고, 이 타입은 그것을
/// 스타일 램프로 칠해 `NSImage` 로 만든다.
///
/// **저장소에 스프라이트 이미지 파일을 두지 않는다.** 이유 세 가지:
///  1. 모든 픽셀이 diff 에 보인다 — PNG 는 리뷰할 수 없다.
///  2. 좌표표(rect)가 없다 — 12 종이 3 개 rect 를 돌려쓰던 부류가 구조적으로 불가능해진다.
///  3. 제3자 에셋이 없다 — 라이선스 공지·해시 게이트가 필요 없고, 오프라인에서 항상 그려진다.
/// `@MainActor` 인 이유는 아래 세 캐시다. 방을 그리는 곳은 전부 SwiftUI 뷰(이미 메인 액터)이고,
/// 이 표시가 없으면 Swift 6.1 이 "non-Sendable 한 `static let`" 으로 컴파일을 거부한다.
/// `nonisolated(unsafe)` 로 막으면 반대로 Swift 6.3(macOS 26 SDK, `NSImage` 가 이미 `Sendable`)
/// 이 "불필요한 표시" warning 을 내 `test-gate.sh` 가 죽는다 — 두 툴체인 다 조용한 쪽은 이것뿐이다.
@MainActor
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
        /// g h j k — 창유리. **스타일이 아니라 시각에서 온다.** 이 램프를 나머지 셋과 갈라 둔
        /// 것이 "방 테마는 시간에 안 변하고, 하늘은 테마에 안 변한다" 의 근거다.
        ///
        /// 기본값이 낮인 이유: 창 말고는 이 램프를 쓰는 격자가 없다(가구·벽지·바닥에 `g h j k`
        /// 가 한 글자도 없음을 테스트가 못 박는다). 그래서 기존 호출부는 이 값을 몰라도 된다.
        var sky: [PixelColor] = MemoryHomePixelArt.skyRamp(for: .day)
    }

    /// 창밖 하늘. 저장 필드가 0개다 — 시계에서 파생하는 `MemoryHomeTimeOfDay` 만 읽는다.
    ///
    /// 밤 램프가 눈에 띄게 어두운 것이 이 기능의 전부다. 세 램프의 밝기 차가 작으면 방을 열어도
    /// "시간이 흐른다" 가 안 읽히고, 코드에만 있는 기능이 된다.
    /// `nonisolated` 인 이유: `Palette.sky` 의 기본값이 이 함수를 부르는데, 구조체의 암묵적
    /// memberwise `init` 은 메인 액터가 아니다. 순수 함수라 액터에 묶일 이유도 없다.
    nonisolated static func skyRamp(for timeOfDay: MemoryHomeTimeOfDay) -> [PixelColor] {
        switch timeOfDay {
        case .morning: return [0x3A4A6E, 0x7C6E8E, 0xE8A878, 0xFFE7C8].map(PixelColor.init)
        case .day:     return [0x2E5C86, 0x4E8CBE, 0x8ABEE2, 0xD8EEFA].map(PixelColor.init)
        case .night:   return [0x10162E, 0x232C50, 0x3E4A7C, 0x9AA6D2].map(PixelColor.init)
        }
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
        case "g": return palette.sky[0];    case "h": return palette.sky[1]
        case "j": return palette.sky[2];    case "k": return palette.sky[3]
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

    /// 벽에 걸리는 창. 스타일이 틀을, 시각이 유리를 정한다.
    static func windowImage(for style: MemoryHomeRoomStyle,
                            timeOfDay: MemoryHomeTimeOfDay) -> NSImage? {
        styledWindows[style]?[timeOfDay]
    }

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

    /// 12 조합(4 스타일 × 3 시각). 창은 방을 다시 그릴 때마다 필요하고 시각은 한 세션 안에서도
    /// 넘어갈 수 있으므로, 셋을 미리 다 그려 두는 편이 시각이 바뀔 때 래스터화가 튀는 것보다 낫다.
    private static let styledWindows: [MemoryHomeRoomStyle: [MemoryHomeTimeOfDay: NSImage]] = {
        var table: [MemoryHomeRoomStyle: [MemoryHomeTimeOfDay: NSImage]] = [:]
        for style in MemoryHomeRoomStyle.allCases {
            let base = palette(for: style)
            var row: [MemoryHomeTimeOfDay: NSImage] = [:]
            for timeOfDay in MemoryHomeTimeOfDay.allCases {
                let palette = Palette(frame: base.frame, fabric: base.fabric, accent: base.accent,
                                      sky: skyRamp(for: timeOfDay))
                guard let image = render(MemoryHomePixelArtSprites.window, palette: palette,
                                         scale: roomScale) else { continue }
                row[timeOfDay] = image
            }
            table[style] = row
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
