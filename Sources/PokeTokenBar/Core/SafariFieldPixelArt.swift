import Foundation

/// 사파리존 벌판 바닥 타일. `PixelSprite`/`PixelPalette`(트레이너 스프라이트가 쓰는 것과 같은
/// 파이프라인)를 그대로 재사용한다 — 새 렌더링 경로를 만들지 않는다.
///
/// 8×8 격자를 셀 크기(24pt)에 맞춰 3배 확대해서 그린다(`.interpolation(.none)`이라 정수배
/// 확대는 각지지 않고 깨끗하다). 존마다 타일 2종을 두고 칸 좌표로 결정론적으로 섞어
/// 단조로움을 줄인다(`SafariFieldView.tilePlan` 참고) — 매 프레임 다시 그리지 않고 방문 시작
/// 시 한 번만 만든 `CGImage` 를 재사용한다(트레이너 이미지 캐시와 같은 이유).
enum SafariFieldPixelArt {
    static let tileSize = 8
    private static let key: [Character: UInt8] = ["1": 1, "2": 2, "3": 3]

    private static func tile(_ rows: [String]) -> PixelSprite { PixelSprite(rows: rows, key: key) }

    static func palette(for zone: SafariZone.ZoneID) -> PixelPalette {
        switch zone {
        case .grassland:
            return PixelPalette(colors: [0, 0x3C7A3E, 0x59A15C, 0x2A5A2C])
        case .wetland:
            return PixelPalette(colors: [0, 0x2E6E8E, 0x4C97BE, 0x1E4A63])
        case .cave:
            return PixelPalette(colors: [0, 0x6E5A46, 0x8A7359, 0x4A3B2C])
        }
    }

    /// 존마다 타일 2종 — 풀잎/물결/돌 얼룩을 다른 자리에 흩어 같은 타일이 반복되는 티를 줄인다.
    static func tiles(for zone: SafariZone.ZoneID) -> [PixelSprite] {
        switch zone {
        case .grassland:
            return [
                tile(["11111111", "11211112", "11121121", "11111111",
                      "12111211", "11112111", "11111111", "11211121"]),
                tile(["12111121", "11111111", "11121211", "11111133",
                      "21112111", "11211111", "11111121", "11111111"]),
            ]
        case .wetland:
            return [
                tile(["11111111", "11111111", "22222222", "11111111",
                      "11111111", "11122211", "11111111", "22211111"]),
                tile(["22211111", "11111111", "11111111", "11222211",
                      "11111133", "22222222", "11111111", "11111111"]),
            ]
        case .cave:
            return [
                tile(["11111111", "11221111", "12221111", "11111111",
                      "11111221", "11111222", "11111133", "21111111"]),
                tile(["11111112", "11111122", "11111111", "22111111",
                      "22211111", "11111133", "11122111", "11111111"]),
            ]
        }
    }
}
