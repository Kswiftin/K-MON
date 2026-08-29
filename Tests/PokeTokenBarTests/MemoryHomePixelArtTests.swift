import XCTest
@testable import PokeTokenBar

/// 미니룸 아트 계약. 원본이 문자 격자라 **격자 자체를 검사**할 수 있다 — PNG 였다면
/// "파일이 있다" 말고는 물어볼 것이 없었다.
final class MemoryHomePixelArtTests: XCTestCase {

    private var allGrids: [(String, [String])] {
        MemoryHomePixelArtSprites.furniture
            .map { ($0.key.rawValue, $0.value) }
            .sorted { $0.0 < $1.0 }
        + [("wallpaper", MemoryHomePixelArtSprites.wallpaper),
           ("floor", MemoryHomePixelArtSprites.floor),
           ("window", MemoryHomePixelArtSprites.window)]
    }

    /// 판매되는 12 종 전부에 격자가 있어야 한다. 손으로 나열하지 않고 카탈로그를 돈다 —
    /// 하드코딩한 목록은 카탈로그가 늘어날 때 따라 늘지 않는다.
    func testEverySellableFurniturePieceHasAGrid() throws {
        for item in ItemKind.memoryHomeFurniture {
            XCTAssertNotNil(MemoryHomePixelArtSprites.furniture[item], "격자 없음: \(item)")
        }
        XCTAssertEqual(MemoryHomePixelArtSprites.furniture.count, ItemKind.memoryHomeFurniture.count)
    }

    /// 규격: 모든 행의 폭이 같고, 변은 16 또는 32 만 쓴다. 2 배로 그리므로 이 값이 아니면
    /// 방 안에서 픽셀 크기가 어긋난다.
    func testGridsAreRectangularAndUseSupportedSides() throws {
        for (name, grid) in allGrids {
            let widths = Set(grid.map(\.count))
            XCTAssertEqual(widths.count, 1, "\(name): 행마다 폭이 다릅니다 \(widths.sorted())")
            let width = try XCTUnwrap(widths.first)
            XCTAssertTrue([16, 32].contains(width), "\(name): 폭 \(width) 는 16/32 가 아닙니다.")
            XCTAssertTrue([16, 32].contains(grid.count), "\(name): 높이 \(grid.count) 는 16/32 가 아닙니다.")
        }
    }

    /// **이 검사가 실제로 벌어들인 가드다.** 격자를 만들 때 본문 길이를 잘못 세면 남는 칸이
    /// 조용히 투명으로 채워진다 — 폭은 맞으니 위 테스트는 통과하고, 스프라이트만 한쪽으로
    /// 밀린다. 작화 중 이 부류로 8 곳이 틀렸고 전부 눈에 안 띄었다.
    /// 미니룸 가구는 전부 좌우 대칭이므로 여백이 같아야 한다.
    func testSpriteRowsHaveSymmetricTransparentMargins() throws {
        for (name, grid) in allGrids {
            for (index, line) in grid.enumerated() {
                let characters = Array(line)
                guard characters.contains(where: { $0 != "." }) else { continue }
                let leading = characters.prefix { $0 == "." }.count
                let trailing = characters.reversed().prefix { $0 == "." }.count
                XCTAssertEqual(leading, trailing,
                               "\(name) 행 \(index): 좌여백 \(leading) ≠ 우여백 \(trailing) — 본문 길이가 틀렸습니다.")
            }
        }
    }

    /// 격자에 정의되지 않은 문자가 있으면 그 픽셀은 투명이 된다. 오타가 스프라이트에 구멍을
    /// 내고도 조용하므로, 허용 문자만 쓰였는지 못 박는다.
    func testGridsUseOnlyDefinedPaletteCharacters() throws {
        let allowed = Set(".1234qweradsfghjk")
        for (name, grid) in allGrids {
            for (index, line) in grid.enumerated() {
                let unknown = Set(line).subtracting(allowed)
                XCTAssertTrue(unknown.isEmpty, "\(name) 행 \(index): 알 수 없는 문자 \(unknown.sorted())")
            }
        }
    }

    /// 12 종이 서로 다른 그림이어야 한다. 예전 아틀라스 시절엔 소파·침대·TV·벤치가 **같은 픽셀**
    /// 이었고, 가구를 사도 방에 같은 그림이 하나 더 생겼다.
    func testEveryFurniturePieceIsADistinctDrawing() throws {
        var seen: [[String]: ItemKind] = [:]
        for item in ItemKind.memoryHomeFurniture.sorted(by: { $0.rawValue < $1.rawValue }) {
            let grid = try XCTUnwrap(MemoryHomePixelArtSprites.furniture[item], "\(item)")
            if let clash = seen[grid] {
                XCTFail("\(item) 와 \(clash) 가 같은 격자입니다 — 방에 같은 그림이 두 번 놓입니다.")
            }
            seen[grid] = item
        }
        XCTAssertEqual(seen.count, ItemKind.memoryHomeFurniture.count)
    }

    /// 스프라이트가 비어 있으면 방에 아무것도 안 보인다. 실루엣이 너무 성기지 않도록
    /// 최소 채움 비율을 요구한다.
    func testEveryFurniturePieceDrawsEnoughPixels() throws {
        for item in ItemKind.memoryHomeFurniture {
            let grid = try XCTUnwrap(MemoryHomePixelArtSprites.furniture[item], "\(item)")
            let total = grid.reduce(0) { $0 + $1.count }
            let opaque = grid.reduce(0) { $0 + $1.filter { $0 != "." }.count }
            XCTAssertGreaterThan(Double(opaque) / Double(total), 0.12,
                                 "\(item): 불투명 픽셀이 \(opaque)/\(total) 뿐입니다.")
        }
    }

    // MARK: - 렌더링

    /// 스타일 4 종이 실제로 다른 색으로 나와야 한다. 예전 스타일은 바닥 색띠뿐이라 러블리를
    /// 골라도 가구는 그대로 초록이었다.
    func testEachRoomStyleRendersDistinctColors() throws {
        for item in ItemKind.memoryHomeFurniture {
            var seen: [Data: MemoryHomeRoomStyle] = [:]
            for style in MemoryHomeRoomStyle.allCases {
                let image = try XCTUnwrap(MemoryHomePixelArt.furnitureImage(for: item, style: style), "\(item)/\(style)")
                let pixels = try XCTUnwrap(image.tiffRepresentation, "\(item)/\(style)")
                if let clash = seen[pixels] { XCTFail("\(item) 이 \(style) 와 \(clash) 에서 같은 색입니다.") }
                seen[pixels] = style
            }
            XCTAssertEqual(seen.count, MemoryHomeRoomStyle.allCases.count, "\(item)")
        }
    }

    /// 스타일 램프 12 색은 서로 달라야 한다 — 두 단계가 같은 색이면 명암이 사라져 스프라이트가
    /// 납작해진다.
    func testEveryStylePaletteUsesTwelveDistinctColors() throws {
        for style in MemoryHomeRoomStyle.allCases {
            let palette = MemoryHomePixelArt.palette(for: style)
            XCTAssertEqual(palette.frame.count, 4, "\(style)")
            XCTAssertEqual(palette.fabric.count, 4, "\(style)")
            XCTAssertEqual(palette.accent.count, 4, "\(style)")
            let all = palette.frame + palette.fabric + palette.accent
            XCTAssertEqual(Set(all.map { [$0.r, $0.g, $0.b] }).count, 12, "\(style): 램프에 중복 색이 있습니다.")
        }
    }

    /// 각 램프는 어두움 → 밝음 순서여야 한다. 순서가 뒤집히면 하이라이트가 그림자 자리에 온다.
    func testEveryRampAscendsInBrightness() throws {
        for style in MemoryHomeRoomStyle.allCases {
            let palette = MemoryHomePixelArt.palette(for: style)
            for (name, ramp) in [("frame", palette.frame), ("fabric", palette.fabric), ("accent", palette.accent)] {
                let luminance = ramp.map { 0.2126 * Double($0.r) + 0.7152 * Double($0.g) + 0.0722 * Double($0.b) }
                for index in 1..<luminance.count {
                    XCTAssertGreaterThan(luminance[index], luminance[index - 1],
                                         "\(style)/\(name): \(index) 단계가 앞 단계보다 어둡습니다.")
                }
            }
        }
    }

    /// 크기 계약: 격자 크기 × 배율. 방은 2 배, 썸네일은 1 배이며 **장면 전체가 같은 배율**이어야
    /// 픽셀 크기가 균일해 보인다.
    func testRenderedSizeIsGridTimesScale() throws {
        for item in ItemKind.memoryHomeFurniture {
            let grid = try XCTUnwrap(MemoryHomePixelArtSprites.furniture[item])
            for scale in [MemoryHomePixelArt.thumbnailScale, MemoryHomePixelArt.roomScale] {
                let size = try XCTUnwrap(MemoryHomePixelArt.displaySize(for: item, scale: scale), "\(item)")
                XCTAssertEqual(size.width, CGFloat(grid[0].count * scale), "\(item) 폭 @\(scale)x")
                XCTAssertEqual(size.height, CGFloat(grid.count * scale), "\(item) 높이 @\(scale)x")
                let image = try XCTUnwrap(MemoryHomePixelArt.furnitureImage(for: item, style: .campus, scale: scale))
                XCTAssertEqual(image.size, size, "\(item): 그린 크기와 알린 크기가 다릅니다 @\(scale)x")
            }
        }
    }

    /// 방 배율은 썸네일보다 커야 한다. 둘이 같아지면 방 안 가구가 카탈로그 아이콘만 해진다.
    func testRoomScaleIsLargerThanThumbnailScale() {
        XCTAssertGreaterThan(MemoryHomePixelArt.roomScale, MemoryHomePixelArt.thumbnailScale)
    }

    // MARK: - 벽지와 바닥

    /// 패턴 타일에 투명 픽셀이 있으면 방이 뚫려 보인다.
    func testPatternTilesAreFullyOpaque() throws {
        for grid in [MemoryHomePixelArtSprites.wallpaper, MemoryHomePixelArtSprites.floor] {
            for line in grid {
                XCTAssertFalse(line.contains("."), "패턴 타일에 투명 칸이 있습니다: \(line)")
            }
        }
    }

    /// 벽지와 바닥은 서로 달라야 한다 — 같으면 바닥선이 사라져 방이 평평해 보인다.
    func testWallpaperAndFloorDifferForEveryStyle() throws {
        XCTAssertNotEqual(MemoryHomePixelArtSprites.wallpaper, MemoryHomePixelArtSprites.floor)
        for style in MemoryHomeRoomStyle.allCases {
            let wallpaper = try XCTUnwrap(MemoryHomePixelArt.wallpaperTile(for: style)?.tiffRepresentation, "\(style)")
            let floor = try XCTUnwrap(MemoryHomePixelArt.floorTile(for: style)?.tiffRepresentation, "\(style)")
            XCTAssertNotEqual(wallpaper, floor, "\(style): 벽지와 바닥이 같은 그림입니다.")
        }
    }

    /// 방의 깊이 계약. "벽지가 **모든** 가구보다 연하다" 는 틀린 계약이다 — 빛나는 램프나
    /// 하트 조명은 벽보다 밝은 게 정상이고, 그렇게 요구하면 발광 램프를 못 쓰게 된다.
    /// 실제로 지켜야 하는 것은 둘이다:
    ///  1. 벽지가 가구 **중앙값**보다 연하다 → 대부분의 가구가 벽 위에서 실루엣으로 뜬다.
    ///  2. 어떤 가구도 벽지와 밝기가 비슷하지 않다 → 벽무늬에 묻히는 가구가 없다.
    func testFurnitureStandsOutAgainstTheWallpaper() throws {
        let minimumContrast = 12.0
        for style in MemoryHomeRoomStyle.allCases {
            let wallpaper = try meanLuminance(of: XCTUnwrap(MemoryHomePixelArt.wallpaperTile(for: style)))
            var luminances: [(ItemKind, Double)] = []
            for item in ItemKind.memoryHomeFurniture {
                let image = try XCTUnwrap(MemoryHomePixelArt.furnitureImage(for: item, style: style))
                luminances.append((item, try meanLuminance(of: image)))
            }
            let sorted = luminances.map(\.1).sorted()
            let median = sorted[sorted.count / 2]
            XCTAssertGreaterThan(wallpaper, median, "\(style): 벽지가 가구 중앙값보다 어둡습니다.")
            for (item, luminance) in luminances {
                XCTAssertGreaterThan(abs(luminance - wallpaper), minimumContrast,
                                     "\(style)/\(item): 벽지와 밝기가 \(abs(luminance - wallpaper)) 밖에 안 나 벽에 묻힙니다.")
            }
        }
    }

    // MARK: - 창밖 시각

    /// 이 기능의 존재 이유. 세 시각이 같은 그림이면 창은 그냥 벽에 붙은 정물이다.
    func testWindowGlassChangesWithTimeOfDay() throws {
        for style in MemoryHomeRoomStyle.allCases {
            var seen: [Data: MemoryHomeTimeOfDay] = [:]
            for timeOfDay in MemoryHomeTimeOfDay.allCases {
                let image = try XCTUnwrap(MemoryHomePixelArt.windowImage(for: style, timeOfDay: timeOfDay),
                                          "\(style)/\(timeOfDay)")
                let pixels = try XCTUnwrap(image.tiffRepresentation)
                if let clash = seen[pixels] { XCTFail("\(style): \(timeOfDay) 와 \(clash) 가 같은 창입니다.") }
                seen[pixels] = timeOfDay
            }
            XCTAssertEqual(seen.count, MemoryHomeTimeOfDay.allCases.count, "\(style)")
        }
    }

    /// 창틀은 여전히 방 스타일을 따른다 — 시각만 보고 스타일을 무시하면 러블리 방에 캠퍼스
    /// 창틀이 걸린다.
    func testWindowFrameStillFollowsTheRoomStyle() throws {
        var seen: [Data: MemoryHomeRoomStyle] = [:]
        for style in MemoryHomeRoomStyle.allCases {
            let image = try XCTUnwrap(MemoryHomePixelArt.windowImage(for: style, timeOfDay: .day), "\(style)")
            let pixels = try XCTUnwrap(image.tiffRepresentation)
            if let clash = seen[pixels] { XCTFail("\(style) 과 \(clash) 의 창틀이 같습니다.") }
            seen[pixels] = style
        }
        XCTAssertEqual(seen.count, MemoryHomeRoomStyle.allCases.count)
    }

    /// **테마는 시간에 안 변한다.** 이걸 이미지로 검사하면 "가구 API 가 시각 인자를 안 받으니까
    /// 당연히 통과" 하는 공허한 테스트가 된다. 그래서 진짜 근거인 격자를 본다 — 시각 램프
    /// 문자(`g h j k`)를 쓰는 격자가 창 하나뿐이면, 다른 그림이 하늘색을 집어갈 방법이 없다.
    func testOnlyTheWindowUsesTheSkyRamp() throws {
        let skyCharacters = Set("ghjk")
        for (name, grid) in allGrids where name != "window" {
            for (index, line) in grid.enumerated() {
                let used = Set(line).intersection(skyCharacters)
                XCTAssertTrue(used.isEmpty,
                              "\(name) 행 \(index): 창이 아닌 그림이 시각 램프 \(used.sorted()) 를 씁니다 — 방 테마가 시간에 따라 변하게 됩니다.")
            }
        }
        XCTAssertFalse(Set(MemoryHomePixelArtSprites.window.joined()).intersection(skyCharacters).isEmpty,
                       "창이 시각 램프를 하나도 안 씁니다 — 시간이 흘러도 그림이 같습니다.")
    }

    /// 하늘 램프 3 종도 스타일 램프와 같은 계약을 받는다: 4 색, 어두움 → 밝음. 더해서 밤이
    /// 아침·낮보다 **눈에 띄게** 어두워야 한다 — 세 램프가 비슷하면 위 이미지 테스트는 통과해도
    /// 사람 눈에는 창이 안 변한다.
    func testSkyRampsAscendAndNightIsClearlyDarkest() {
        func meanLuminance(_ ramp: [MemoryHomePixelArt.PixelColor]) -> Double {
            ramp.reduce(0.0) { $0 + 0.2126 * Double($1.r) + 0.7152 * Double($1.g) + 0.0722 * Double($1.b) }
                / Double(ramp.count)
        }
        var means: [MemoryHomeTimeOfDay: Double] = [:]
        for timeOfDay in MemoryHomeTimeOfDay.allCases {
            let ramp = MemoryHomePixelArt.skyRamp(for: timeOfDay)
            XCTAssertEqual(ramp.count, 4, "\(timeOfDay)")
            let luminance = ramp.map { 0.2126 * Double($0.r) + 0.7152 * Double($0.g) + 0.0722 * Double($0.b) }
            for index in 1..<luminance.count {
                XCTAssertGreaterThan(luminance[index], luminance[index - 1],
                                     "\(timeOfDay): \(index) 단계가 앞 단계보다 어둡습니다.")
            }
            means[timeOfDay] = meanLuminance(ramp)
        }
        let night = means[.night] ?? 0
        for timeOfDay in [MemoryHomeTimeOfDay.morning, .day] {
            XCTAssertGreaterThan((means[timeOfDay] ?? 0) - night, 40,
                                 "밤이 \(timeOfDay) 보다 충분히 어둡지 않습니다 — 창이 변한 걸 눈으로 못 봅니다.")
        }
    }

    /// 기본 팔레트의 하늘은 낮이다. 이 기본값이 흔들리면 시각을 안 넘긴 렌더가 조용히 다른
    /// 하늘로 그려진다.
    func testDefaultPaletteSkyIsDaytime() {
        for style in MemoryHomeRoomStyle.allCases {
            XCTAssertEqual(MemoryHomePixelArt.palette(for: style).sky,
                           MemoryHomePixelArt.skyRamp(for: .day), "\(style)")
        }
    }

    /// 렌더러가 잘못된 입력을 조용히 통과시키면 안 된다 — 행 폭이 다른 격자는 nil 이어야 한다.
    func testRenderRejectsRaggedGrids() {
        let palette = MemoryHomePixelArt.palette(for: .campus)
        XCTAssertNil(MemoryHomePixelArt.render(["....", "..."], palette: palette, scale: 2))
        XCTAssertNil(MemoryHomePixelArt.render([], palette: palette, scale: 2))
        XCTAssertNil(MemoryHomePixelArt.render(["...."], palette: palette, scale: 0))
        XCTAssertNotNil(MemoryHomePixelArt.render(["1234", "qwer"], palette: palette, scale: 2))
    }

    private func meanLuminance(of image: NSImage) throws -> Double {
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var total = 0.0, count = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] > 0 {
            total += 0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2])
            count += 1
        }
        return count == 0 ? 0 : total / Double(count)
    }
}
