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
        case .volcano:
            return PixelPalette(colors: [0, 0x3A2A22, 0xB8441C, 0x1E1512])
        case .highland:
            return PixelPalette(colors: [0, 0x7C93A6, 0xB8CBD9, 0x53687A])
        case .ruins:
            return PixelPalette(colors: [0, 0x6B6259, 0x8B7FA8, 0x352F2A])
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
        case .volcano:
            return [
                tile(["11111111", "11211112", "11131121", "11111111",
                      "12111211", "11113111", "11111111", "12311121"]),
                tile(["13111121", "11111111", "11121311", "11111121",
                      "21112111", "11311111", "11111121", "11111111"]),
            ]
        case .highland:
            return [
                tile(["11111111", "11211112", "11121121", "11111111",
                      "12111211", "11112111", "11111111", "12211121"]),
                tile(["12111121", "11111111", "11121211", "11111122",
                      "21112111", "11211111", "11111121", "11111111"]),
            ]
        case .ruins:
            return [
                tile(["11111111", "11211112", "11121131", "11111111",
                      "13111211", "11112111", "11111111", "11211121"]),
                tile(["12111131", "11111111", "11121211", "11111122",
                      "31112111", "11211111", "11111121", "11111111"]),
            ]
        }
    }

    /// 벌판에 고정 배치되는 장애물(`SafariZone.obstacles(for:)`) 한 칸을 그리는 스프라이트 —
    /// 존마다 그림만 다르고(나무·물웅덩이·바위) 좌표는 공유한다. 바닥 타일과 달리 칸을 꽉
    /// 채우지 않는다(가장자리는 투명 `0`) — 밑에 깔린 바닥 타일이 비쳐 보여야 장애물처럼 도드라진다.
    static func obstaclePalette(for zone: SafariZone.ZoneID) -> PixelPalette {
        switch zone {
        case .grassland: return PixelPalette(colors: [0, 0x5A3A26, 0x2A6B2E])       // 줄기, 잎
        case .wetland: return PixelPalette(colors: [0, 0x3B7FA8])                    // 물웅덩이
        case .cave: return PixelPalette(colors: [0, 0x7A7A7A, 0x5A5A5A])             // 바위, 그림자
        case .volcano: return PixelPalette(colors: [0, 0x1E1512, 0xB8441C])          // 용암암석, 마그마
        case .highland: return PixelPalette(colors: [0, 0xB8CBD9])                   // 바람에 깎인 돌탑
        case .ruins: return PixelPalette(colors: [0, 0x5A554D, 0x8B7FA8])            // 부서진 기둥, 이끼
        }
    }

    static func obstacle(for zone: SafariZone.ZoneID) -> PixelSprite {
        switch zone {
        case .grassland:
            return tile(["........", "..2222..", ".222222.", "22222222",
                         ".222222.", "..1111..", "..1111..", "........"])
        case .wetland:
            return tile(["........", ".111111.", "11111111", "11111111",
                         "11111111", ".111111.", "........", "........"])
        case .cave:
            return tile(["........", "..1111..", ".112211.", "11222211",
                         "12222221", ".112211.", "........", "........"])
        case .volcano:
            return tile(["........", "...11...", "..1221..", ".122221.",
                         "12222221", ".112211.", "........", "........"])
        case .highland:
            return tile(["........", "...11...", "...11...", "..1111..",
                         "..1111..", ".111111.", ".111111.", "........"])
        case .ruins:
            return tile(["........", "..11....", "..21....", ".1111...",
                         ".1211...", "11111...", "11121...", "........"])
        }
    }
}
