import XCTest
@testable import PokeTokenBar

/// 아이소메트릭 마을의 기하. 도트 판의 `PokopiaTownSpriteTests`(격자 규격을 세던 테스트)를
/// 대체한다 — 규격이 문자 격자에서 좌표 변환으로 옮겨 갔으니 세는 대상도 옮긴다.
///
/// 여기서 세는 것은 **눈으로 못 보는 것들**이다: 한 칸 어긋난 탭, 맨 뒷줄만 잘리는 여백,
/// 이어 붙는 자리에 생기는 틈. 화면을 열어 보면 다 그럴싸해 보이는 부류다.
final class PokopiaTownIsoTests: XCTestCase {

    // MARK: 여백과 크기

    func testCanvasFitsThePanelWidth() {
        // 이 화면의 다른 칸이 전부 `maxWidth: 512` 다. 캔버스만 넓으면 왼쪽 끝이 어긋난다.
        XCTAssertLessThanOrEqual(PokopiaTownIso.canvasSize.width, 512)
        XCTAssertEqual(PokopiaTownIso.canvasSize.width,
                       PokopiaTownIso.tileWidth / 2
                       * CGFloat(PokopiaTown.columns + PokopiaTown.rows), accuracy: 0.001)
    }

    /// 모든 칸이 캔버스 안에 들어온다 — 나무 수관(중심에서 위로 `1.78 × 반폭`)과 앞줄 슬래브까지.
    /// 잘리면 맨 뒷줄·맨 앞줄만 잘리므로, 화면을 봐도 "원래 그런 그림" 으로 읽힌다.
    func testEveryTileStaysInsideTheCanvas() {
        let size = PokopiaTownIso.canvasSize
        let halfWidth = PokopiaTownIso.tileWidth / 2
        let halfHeight = PokopiaTownIso.tileHeight / 2
        for terrain in TownTerrain.allCases {
            for row in 0..<PokopiaTown.rows {
                for col in 0..<PokopiaTown.columns {
                    let center = PokopiaTownIso.center(col: col, row: row,
                                                       elevation: PokopiaTownIso.elevation(terrain))
                    // 나무가 가장 높이 올라가는 소품이다(수관 위 끝).
                    XCTAssertGreaterThanOrEqual(center.y - 1.78 * halfWidth, 0,
                                                "(\(col),\(row)) \(terrain) 위가 잘린다")
                    XCTAssertLessThanOrEqual(center.y + halfHeight + PokopiaTownIso.skirt(terrain),
                                             size.height,
                                             "(\(col),\(row)) \(terrain) 아래가 잘린다")
                    XCTAssertGreaterThanOrEqual(center.x - halfWidth, 0)
                    XCTAssertLessThanOrEqual(center.x + halfWidth, size.width)
                }
            }
        }
    }

    /// 이웃 칸의 꼭짓점이 맞물린다. 2:1 이 깨지거나 원점 식이 바뀌면 격자에 틈이 생긴다.
    func testNeighboursInterlock() {
        let origin = PokopiaTownIso.center(col: 3, row: 4)
        let right = PokopiaTownIso.center(col: 4, row: 4)
        let down = PokopiaTownIso.center(col: 3, row: 5)
        XCTAssertEqual(right.x - origin.x, PokopiaTownIso.tileWidth / 2, accuracy: 0.001)
        XCTAssertEqual(right.y - origin.y, PokopiaTownIso.tileHeight / 2, accuracy: 0.001)
        XCTAssertEqual(down.x - origin.x, -PokopiaTownIso.tileWidth / 2, accuracy: 0.001)
        XCTAssertEqual(down.y - origin.y, PokopiaTownIso.tileHeight / 2, accuracy: 0.001)
    }

    // MARK: 탭 → 칸

    /// 192칸 전부의 윗면 중심이 자기 칸으로 돌아온다. 평지·물·바위 세 지형으로 각각 돈다 —
    /// 높이가 다르면 화면 좌표가 다르므로, 한 지형만 보면 높이를 무시한 판정도 통과한다.
    func testCenterRoundTripsForEveryTile() {
        for terrain in [TownTerrain.path, .water, .rock] {
            let field = [TownTerrain](repeating: terrain, count: PokopiaTown.tileCount)
            for row in 0..<PokopiaTown.rows {
                for col in 0..<PokopiaTown.columns {
                    let center = PokopiaTownIso.center(col: col, row: row,
                                                       elevation: PokopiaTownIso.elevation(terrain))
                    let hit = PokopiaTownIso.cell(at: center, terrain: field)
                    XCTAssertEqual(hit?.col, col, "\(terrain) (\(col),\(row)) 열이 어긋났다")
                    XCTAssertEqual(hit?.row, row, "\(terrain) (\(col),\(row)) 행이 어긋났다")
                }
            }
        }
    }

    /// **회귀 가드 — 이 테스트가 `cell(at:terrain:)` 이 앞에서 뒤로 훑는 이유다.**
    ///
    /// 솟은 바위의 보이는 윗면을 누르면 그 바위가 잡혀야 한다. 평면 역변환(높이를 무시하고
    /// `(col-row, col+row)` 를 되돌리는 식)은 **다른 칸**을 준다 — 아래에서 그 식을 직접 계산해
    /// 답이 갈리는 것을 확인한다. 갈리지 않으면 이 가드는 아무것도 지키지 않는다.
    func testRaisedTileIsPickedByItsVisibleTop() {
        var field = [TownTerrain](repeating: .path, count: PokopiaTown.tileCount)
        let target = (col: 8, row: 5)
        let index = try! XCTUnwrap(PokopiaTown.index(col: target.col, row: target.row))
        field[index] = .rock

        // 윗면의 **위쪽 절반**을 노린다. 중심은 마름모 한가운데라 0.5칸 여유가 있어, 한 단
        // (8pt ≈ 0.4칸)을 밀어도 평면식이 우연히 맞는다 — 그러면 이
        // 가드가 통과만 하고 아무것도 지키지 않는다.
        let visibleTop = PokopiaTownIso.center(col: target.col, row: target.row,
                                               elevation: PokopiaTownIso.elevation(.rock))
            .applying(.init(translationX: 0, y: -PokopiaTownIso.tileHeight * 0.3))
        let hit = PokopiaTownIso.cell(at: visibleTop, terrain: field)
        XCTAssertEqual(hit?.col, target.col)
        XCTAssertEqual(hit?.row, target.row)

        // 결함 주입 — 높이를 안 보는 판정은 같은 점에서 다른 칸을 답한다.
        let origin = PokopiaTownIso.origin
        let fx = (visibleTop.x - origin.x) / PokopiaTownIso.tileWidth
        let fy = (visibleTop.y - origin.y) / PokopiaTownIso.tileHeight
        let flatCol = Int((fx + fy + 0.5).rounded(.down))
        let flatRow = Int((fy - fx + 0.5).rounded(.down))
        XCTAssertNotEqual([flatCol, flatRow], [target.col, target.row],
                          "평면식이 같은 답을 낸다 — 높이가 너무 낮아 이 가드가 무력하다")
    }

    /// 솟은 타일의 **측면**도 그 타일이다. 벽면이 죽은 영역이면 바위를 눌러도 아무 일이 없다.
    func testRaisedSideFaceBelongsToItsTile() {
        var field = [TownTerrain](repeating: .path, count: PokopiaTown.tileCount)
        let index = try! XCTUnwrap(PokopiaTown.index(col: 2, row: 2))
        field[index] = .rock
        let center = PokopiaTownIso.center(col: 2, row: 2, elevation: PokopiaTownIso.elevation(.rock))
        // 아래 꼭짓점에서 조금 내려간 점. **솟은 만큼만** 내려간다 — 슬래브 두께만큼 내려가면
        // 그 자리는 앞 칸의 윗면이 덮는 자리이고(앞 칸이 나중에 그려져 이긴다), 보이지도 않는
        // 벽을 누른 셈이 된다. 실제로 보이는 벽은 솟은 높이만큼의 띠뿐이다.
        let onWall = CGPoint(x: center.x, y: center.y + PokopiaTownIso.tileHeight / 2
                             + PokopiaTownIso.elevation(.rock) * PokopiaTownIso.step / 2)
        let hit = PokopiaTownIso.cell(at: onWall, terrain: field)
        XCTAssertEqual(hit?.col, 2)
        XCTAssertEqual(hit?.row, 2)
    }

    /// 격자 밖은 nil 이다 — 클램프하면 사용자가 안 누른 가장자리 칸이 바뀐다
    /// (`PokopiaTown.index` 가 클램프를 거절하는 것과 같은 이유).
    func testOutsideTheGridIsRejected() {
        let field = PokopiaTown.defaultTerrain
        for point in [CGPoint(x: -20, y: -20),
                      CGPoint(x: 2, y: 2),                                  // 왼쪽 위 빈 귀퉁이
                      CGPoint(x: PokopiaTownIso.canvasSize.width - 2, y: 2),
                      CGPoint(x: 2, y: PokopiaTownIso.canvasSize.height - 2),
                      CGPoint(x: 9999, y: 9999)] {
            XCTAssertNil(PokopiaTownIso.cell(at: point, terrain: field), "\(point) 가 칸으로 잡혔다")
        }
    }

    // MARK: 높이

    /// 침하는 슬래브보다 얕아야 한다 — 더 깊으면 뒤 칸의 측면이 못 덮어 그 틈으로 창 배경이 비친다.
    func testSinkNeverOutrunsTheSlab() {
        for terrain in TownTerrain.allCases {
            let sink = -PokopiaTownIso.elevation(terrain) * PokopiaTownIso.step
            XCTAssertLessThan(sink, PokopiaTownIso.slab, "\(terrain) 가 너무 깊다")
            // 측면 길이는 항상 두께 이상이다(솟은 만큼 더 내려간다).
            XCTAssertGreaterThanOrEqual(PokopiaTownIso.skirt(terrain), PokopiaTownIso.slab)
        }
    }

    // MARK: 색

    /// 여덟 지형의 윗면 색이 서로 다르다. 같은 색이면 브러시를 바꿨는데 화면이 안 바뀐다.
    func testEveryTerrainHasItsOwnTopColor() {
        let colors = TownTerrain.allCases.map(PokopiaTownIso.topColor)
        XCTAssertEqual(Set(colors).count, TownTerrain.allCases.count)
        XCTAssertEqual(colors.count, 8, "지형이 늘었다 — 색과 높이를 같이 더한다")
    }

    /// 측면은 윗면보다 어둡고, 오른쪽이 왼쪽보다 어둡다. 광원이 하나라는 계약이다.
    func testShadingKeepsOneLightSource() {
        XCTAssertLessThan(PokopiaTownIso.rightShade, PokopiaTownIso.leftShade)
        XCTAssertLessThan(PokopiaTownIso.leftShade, 1)
        for terrain in TownTerrain.allCases {
            let base = PokopiaTownIso.topColor(terrain)
            let left = PokopiaTownIso.shaded(base, PokopiaTownIso.leftShade)
            let right = PokopiaTownIso.shaded(base, PokopiaTownIso.rightShade)
            for shift in [16, 8, 0] {
                let channel: (UInt32) -> UInt32 = { ($0 >> UInt32(shift)) & 0xFF }
                XCTAssertLessThanOrEqual(channel(right), channel(left), "\(terrain) 채널 \(shift)")
                XCTAssertLessThanOrEqual(channel(left), channel(base), "\(terrain) 채널 \(shift)")
            }
        }
    }

    func testShadingClampsOutOfRangeFactors() {
        let white: UInt32 = 0xFFFFFF
        XCTAssertEqual(PokopiaTownIso.shaded(white, 2), white)
        XCTAssertEqual(PokopiaTownIso.shaded(white, -1), 0)
    }

    /// 소품 흔들기는 좌표 파생이라 **같은 칸이면 늘 같은 값**이다. 무작위면 재렌더마다 꽃이
    /// 자리를 옮겨, 정지 화면이라는 계약이 깨진다.
    func testJitterIsDeterministicAndBounded() {
        for row in 0..<PokopiaTown.rows {
            for col in 0..<PokopiaTown.columns {
                let value = PokopiaTownIso.jitter(col: col, row: row)
                XCTAssertEqual(value, PokopiaTownIso.jitter(col: col, row: row))
                XCTAssertTrue((0..<5).contains(value))
            }
        }
        // 이웃끼리 값이 갈려야 흔들기가 뜻을 가진다.
        XCTAssertNotEqual(PokopiaTownIso.jitter(col: 0, row: 0), PokopiaTownIso.jitter(col: 1, row: 0))
    }
}
