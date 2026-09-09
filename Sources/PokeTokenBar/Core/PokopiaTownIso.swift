import CoreGraphics
import Foundation

/// 아이소메트릭 마을의 기하와 색. **이 파일이 아트의 원본이다** — PNG 도, 문자 격자도 굽지 않는다.
///
/// 앞선 판은 16×16 문자 격자 도트였다(`PokopiaTownSprites`). 걷어낸 이유는 하나다: 같은 창에
/// 뜨는 플로팅 펫이 HOME 512 렌더(`SpriteStore.highResolutionBase`)를 쓰는데, 마을만 96px
/// 도트라 **한 앱에 화질이 두 벌**로 보였다. 도트를 키우는 쪽이 아니라 마을을 입체로 세우는
/// 쪽을 택했다 — 위에서 내려다보는 정사각 격자는 색을 어떻게 칠해도 종이처럼 납작하다.
///
/// 마름모 하나가 한 칸이다. 폭:높이 = **2:1 고정**(`tileWidth` / `tileHeight`) — 아이소메트릭의
/// 관례이고, 이 비율이 아니면 이웃 마름모의 꼭짓점이 안 맞아 격자에 틈이 생긴다.
///
/// 입체는 **세 면을 다른 밝기로 칠하는 것**이 전부다: 윗면은 원색, 좌측면·우측면은 `leftShade`·
/// `rightShade` 를 곱한 값이다. 지형마다 색을 **하나만** 두고 측면을 파생하므로, 새 지형을
/// 더할 때 조명 방향이 어긋날 수 없다(색 셋을 손으로 적어 두면 반드시 어긋난다).
///
/// 그리는 값은 전부 여기 있고 `Path` 는 UI 가 만든다 — 그래서 이 파일은 SwiftUI 없이
/// 단위 테스트가 닿고, `PokopiaTownIsoTests` 가 왕복 변환·여백·색을 직접 센다.
enum PokopiaTownIso {

    // MARK: - 기하

    /// 마름모 한 칸의 화면 폭·높이(pt). 2:1 을 깨지 않는다.
    static let tileWidth: CGFloat = 36
    static let tileHeight: CGFloat = 18

    /// 타일 두께. 격자 가장자리에서 이 값이 마을의 **벽**으로 보여, 떠 있는 땅덩이로 읽힌다.
    static let slab: CGFloat = 9

    /// 한 단(段) 높이. `elevation` 에 곱한다 — 물은 한 단 아래, 바위는 한 단 위다.
    static let step: CGFloat = 8

    /// 위쪽 여백. 맨 뒤 줄(row 0)의 나무 수관과 주민 스프라이트가 잘리지 않을 만큼이다.
    /// `PokopiaTownIsoTests` 가 모든 칸의 위 끝이 0 이상인지 센다 — 눈으로는 맨 뒷줄만
    /// 잘리므로 알아채기 어렵다.
    static let topPad: CGFloat = 44

    /// 아래쪽 여백. 맨 앞 줄의 슬래브와 **침하한 물**이 잘리지 않을 만큼이다 — 물을 더 깊게
    /// 하면 이 값도 같이 올려야 한다(테스트가 맨 앞 칸에서 0.4pt 초과를 잡아냈다).
    static let bottomPad: CGFloat = 28

    /// 격자의 대각 길이(칸 수). 폭·높이·원점이 모두 이 값에서 나온다.
    private static var span: CGFloat { CGFloat(PokopiaTown.columns + PokopiaTown.rows) }

    /// 캔버스 크기. **폭이 512 를 넘으면 안 된다** — 이 화면의 다른 칸이 전부 `maxWidth: 512`
    /// 로 묶여 있어, 캔버스만 넓으면 머리말·배너와 왼쪽 끝이 어긋난다. 테스트가 못 박는다.
    static var canvasSize: CGSize {
        .init(width: tileWidth / 2 * span,
              height: topPad + tileHeight / 2 * (span - 1) + bottomPad)
    }

    /// 타일 (0,0) 윗면의 중심. row 가 커질수록 왼쪽으로 가므로 **왼쪽 여백은 `rows` 가 정한다**.
    ///
    /// `rows` 에서 1을 빼지 않는다 — 가장 왼쪽 칸(col 0, row `rows-1`)의 중심이 아니라 그
    /// **왼쪽 꼭짓점**이 x=0 에 닿아야 한다. 반 칸(`tileWidth/2`)을 빠뜨렸던 판은 맨 왼쪽
    /// 대각선 한 줄이 18pt 잘려 나갔고, 그 줄은 격자의 모서리라 눈으로는 "원래 그런 모양" 으로
    /// 읽혔다(`PokopiaTownIsoTests.testEveryTileStaysInsideTheCanvas` 가 잡았다).
    static var origin: CGPoint {
        .init(x: tileWidth / 2 * CGFloat(PokopiaTown.rows), y: topPad + tileHeight / 2)
    }

    /// 칸 → 윗면 중심(화면 좌표). **그리기와 탭이 전부 이 함수 하나를 지난다** — 그리는 쪽과
    /// 탭 처리 쪽이 각자 계산하면 한 칸 어긋난 채 남고, 눈으로만 보면 알아챌 수 없다.
    static func center(col: Int, row: Int, elevation: CGFloat = 0) -> CGPoint {
        let o = origin
        return .init(x: o.x + CGFloat(col - row) * tileWidth / 2,
                     y: o.y + CGFloat(col + row) * tileHeight / 2 - elevation * step)
    }

    /// 지형이 세워진 높이(단위: `step`). 색만으로는 물이 낮고 바위가 높다는 것이 안 보인다.
    ///
    /// 침하 깊이가 `slab` 보다 얕아야 한다 — 더 깊으면 뒤 칸의 측면이 못 덮어 그 사이로
    /// 창 배경이 비친다. 테스트가 그 부등식을 센다.
    static func elevation(_ terrain: TownTerrain) -> CGFloat {
        switch terrain {
        case .water:                  -0.8
        case .soil, .sand, .path:      0
        case .grass, .flower, .tree:   0.15
        case .rock:                    0.9
        }
    }

    /// 측면이 내려가는 길이. 솟은 타일은 솟은 만큼 **더 내려야** 앞 칸과의 사이가 뚫리지 않는다.
    static func skirt(_ terrain: TownTerrain) -> CGFloat {
        slab + max(0, elevation(terrain) * step)
    }

    // MARK: - 화면 좌표 → 칸

    /// 누른 자리의 칸. **앞에서 뒤로** 훑어 처음 맞는 칸을 준다.
    ///
    /// 평면 역변환(`(col-row, col+row)` 를 되돌리는 식)을 쓰지 않는 이유: 솟은 타일은 화면에서
    /// 위로 밀려 있어, 보이는 윗면을 눌렀을 때 평면식은 **그 뒤 칸**을 돌려준다. 바위 한 단이
    /// 8pt 고 마름모 반높이가 9pt 라 어긋남이 한 칸에 가깝다 — 사용자가 안 누른 칸이 바뀐다.
    /// (`PokopiaTown.index` 가 화면 밖 탭을 클램프하지 않는 것과 같은 판단이다.)
    ///
    /// 대각선 한 줄(`col + row` 가 같은 칸들)은 서로 가리지 않으므로 줄 안의 순서는 무관하다.
    /// 192칸 선형 훑기이고 탭 한 번에 한 번 돈다 — 프레임마다 도는 것이 아니다.
    static func cell(at point: CGPoint, terrain: [TownTerrain]) -> (col: Int, row: Int)? {
        for depth in stride(from: PokopiaTown.columns + PokopiaTown.rows - 2, through: 0, by: -1) {
            for col in 0..<PokopiaTown.columns {
                let row = depth - col
                guard let index = PokopiaTown.index(col: col, row: row),
                      terrain.indices.contains(index) else { continue }
                if covers(point, col: col, row: row, terrain: terrain[index]) { return (col, row) }
            }
        }
        return nil
    }

    /// 이 칸이 그 점을 덮는가 — 윗면 마름모 **또는** 그 아래 측면(슬래브)이다. 측면까지 넣는
    /// 이유는 솟은 바위의 벽면을 눌렀을 때 아무 일도 안 일어나면 죽은 영역이 되기 때문이다.
    static func covers(_ point: CGPoint, col: Int, row: Int, terrain: TownTerrain) -> Bool {
        let c = center(col: col, row: row, elevation: elevation(terrain))
        // 마름모를 정사각으로 펴서 본다 — 윗면은 |dx| + |dy| <= 1 한 줄로 끝난다.
        let dx = abs(point.x - c.x) / (tileWidth / 2)
        let dy = (point.y - c.y) / (tileHeight / 2)
        guard dx <= 1 else { return false }
        if dx + abs(dy) <= 1 { return true }
        // 측면 — 윗면의 아래쪽 두 변을 `skirt` 만큼 내린 띠.
        return dy > 0 && dx + dy - skirt(terrain) / (tileHeight / 2) <= 1
    }

    // MARK: - 색

    /// 윗면 색 `0xRRGGBB`. 측면은 파생이다(`shaded`) — 지형마다 색을 셋 적으면 어긋난다.
    ///
    /// 도트 팔레트보다 밝고 맑다. 도트는 한 색으로 채운 면이 납작해 보여 어둡게 깔았는데,
    /// 여기서는 **측면이 어두움을 담당**하므로 윗면이 빛을 받은 색이어야 입체로 읽힌다.
    static func topColor(_ terrain: TownTerrain) -> UInt32 {
        switch terrain {
        case .grass:  0x6FBE52
        case .soil:   0x9C6F45
        case .water:  0x4FA6DE
        case .sand:   0xE4CE8B
        case .path:   0xC3B59B
        case .flower: 0x7FC65C
        case .tree:   0x5FAE49
        case .rock:   0x9EA2AE
        }
    }

    /// 측면 밝기. 광원은 **왼쪽 위 하나**다 — 두 측면의 값을 지형마다 정하지 않는 것이
    /// 조명 방향이 하나로 남는 근거다.
    static let leftShade: CGFloat = 0.74
    static let rightShade: CGFloat = 0.55

    /// 곱 셰이딩. `0xRRGGBB` 를 채널마다 곱한다. UI 가 `Color` 를 만들 때 쓰는데, 계산을 UI 에
    /// 두면 캔버스와 배너 견본이 각자 어두워져 같은 지형이 두 색으로 보인다.
    static func shaded(_ rgb: UInt32, _ factor: CGFloat) -> UInt32 {
        let f = max(0, min(1, factor))
        let channel: (UInt32) -> UInt32 = { shift in
            UInt32((CGFloat((rgb >> shift) & 0xFF) * f).rounded())
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    /// 윗면에 긋는 칸선 밝기. **일부러 긋는다** — 안 그으면 이웃 마름모 사이에 안티에일리어싱
    /// 실틈이 남아 뒤 타일의 어두운 측면이 비치고, 그 선은 자리마다 굵기가 달라 얼룩으로 읽힌다.
    /// 그을 선이라면 고르게 긋는 쪽이 낫고, 칸을 눌러 지형을 미는 화면이라 칸 경계가 조작에 쓰인다.
    static let gridShade: CGFloat = 0.88

    /// 타일 위에 얹는 소품의 색. 지형 색과 갈라 두는 이유: 나무 수관과 풀밭이 같은 램프에서
    /// 오면 나무가 풀밭에 녹아 실루엣이 사라진다.
    enum Prop {
        static let trunk: UInt32 = 0x6B4A2A
        static let canopy: UInt32 = 0x2F7A43
        static let canopyLit: UInt32 = 0x53A85C
        /// 바위는 타일과 같은 블록으로 그리므로 측면 색은 `shaded` 가 파생한다 — 어두운 짝을
        /// 따로 두면 바위만 광원이 다른 색이 된다.
        static let boulder: UInt32 = 0xC4C8D4
        static let waterCrest: UInt32 = 0xA6DCFF
        /// 꽃잎 세 색을 돌려 쓴다. 한 색이면 6칸 넘게 민 꽃밭이 도장을 찍은 것처럼 보인다.
        static let petals: [UInt32] = [0xF06C9B, 0xFFF3A8, 0xFFFFFF]
    }

    /// 소품을 칸마다 조금씩 흔드는 값(0...4). 무작위가 아니라 **좌표 파생**이다 — 무작위면
    /// 재렌더마다 꽃이 자리를 옮기고, 그것은 상시 애니메이션과 같은 산만함이 된다.
    static func jitter(col: Int, row: Int) -> Int { (col * 7 + row * 13) % 5 }

    /// 하늘. 마름모 격자는 사각 캔버스의 네 귀퉁이를 비우므로, 그 자리에 창 배경이 그대로
    /// 보이면 격자가 잘려 나간 것처럼 읽힌다. 위·아래 두 색으로 그 자리를 하늘로 만든다.
    static let skyTop: UInt32 = 0xDCEBF5
    static let skyBottom: UInt32 = 0xAFCFE4
}
