import CoreGraphics

/// 던전 방 화면의 16×16 타일 도트. 트레이너와 같은 이유로 **에셋 파일 없이 코드 리터럴**이다
/// (`room-walk-dungeon-design.md` "조사 결론") — 다운로드도, 번들 리소스도 없다.
///
/// 굽기(`CGImage`)는 타일 종류마다 **한 번만** 한다. 캔버스는 초당 60번 그리므로 매 프레임
/// 픽셀을 RGBA 로 펼치면 그것만으로 CPU 가 눌린다(설계 "게임루프와 에너지").
enum RoomTileArt {
    static let size = 16

    private static let key: [Character: UInt8] = [
        "f": 1, "F": 2, "w": 3, "W": 4, "h": 5, "H": 6, "p": 7, "P": 8,
        "d": 9, "D": 10, "b": 11, "B": 12, "c": 13, "C": 14, "s": 15, "m": 16, "k": 17,
    ]

    /// 0 은 투명. 내 방(0번)은 벽지·마루 색을 따로 써서 "여긴 던전이 아니다" 가 한눈에 오게 한다.
    static let palette = PixelPalette(colors: [
        0, 0x3A3A46, 0x46465A, 0x6E6E7E, 0x4B4B5C, 0x8A5A2B, 0xA06B34, 0xA57FA0, 0x86648A,
        0x2A2A32, 0x12121A, 0x4FA6D8, 0xA8DCF2, 0xA87038, 0xE3C55A, 0x7F7F8D, 0x5E8A4A, 0x22222A,
    ])

    private static func sprite(_ rows: [String]) -> PixelSprite { PixelSprite(rows: rows, key: key) }

    private static let floor = sprite([
        "kfkfkfkfkfkfkfkf",
        "ffffffffffffffff",
        "kfffffffffffFfff",
        "ffffffffffffffff",
        "kfffffffffffffff",
        "fffFffffffffffff",
        "kfffffffffffffff",
        "ffffffffffffffff",
        "kffffffffffffFff",
        "ffffffffffffffff",
        "kfffffffffffffff",
        "fffffffffFffffff",
        "kfffffffffffffff",
        "ffffffFfffffffff",
        "kfffffffffffffff",
        "ffffffffffffffff",
    ])

    private static let floorHome = sprite([
        "kkkkkkkkkkkkkkkk",
        "hhhhhhhhhhhkhhhh",
        "hhhhhhhhhhhkhhhh",
        "hhhHhhhhhhhkhhhh",
        "hhhhhhhhhhhkhhhh",
        "hhhhhhhHhhhkhhhh",
        "hhhhhhhhhhhkhhhh",
        "hhhhhhhhhhhkhhhh",
        "kkkkkkkkkkkkkkkk",
        "hhhhkhhhhhhhhhhh",
        "hhhhkhhhhhhhhhhh",
        "hhhhkhhhhhhhhhhh",
        "hhhhkhhhhhhhhHhh",
        "hhhhkhhhhhhhhhhh",
        "hhhhkhhhhHhhhhhh",
        "hhhhkhhhhhhhhhhh",
    ])

    private static let wall = sprite([
        "WWWWWWWWWWWWWWWW",
        "Wwwwwwwwwwwwwwww",
        "Wwwwwwwwwwwwwwww",
        "Wwwwkwwwwwwwwwww",
        "Wwwwwwwwwwwkwwww",
        "Wwwwwwwwwwwwwwww",
        "Wwwwwwwwwwwwwwww",
        "WWWWWWWWWWWWWWWW",
        "wwwwwwwwWwwwwwww",
        "wwwwwwwwWwwwwwww",
        "wwwwwwwwWwwwwwww",
        "wwwkwwwwWwwwwwww",
        "wwwwwwwwWwwwkwww",
        "wwwwwwwwWwwwwwww",
        "wwwwwwwwWwwwwwww",
        "WWWWWWWWWWWWWWWW",
    ])

    private static let wallHome = sprite([
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PppppPppppPppppP",
        "PPPPPPPPPPPPPPPP",
        "kkkkkkkkkkkkkkkk",
    ])

    private static let doorOpen = sprite([
        "kkkkkkkkkkkkkkkk",
        "..dddddddddddd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
        "..dDDDDDDDDDDd..",
    ])

    private static let spring = sprite([
        "................",
        ".....kkkkkk.....",
        "....kkkkkkkk....",
        "...kkbbbbbbkk...",
        "..kkbbbbbbbbkk..",
        ".kkbbBBbbbbbbkk.",
        ".kkbbBbbbbbbbkk.",
        ".kkbbbbbbbbbbkk.",
        ".kkbbbbbbbbbbkk.",
        ".kkbbbbbbBbbbkk.",
        ".kkbbbbbbbbbbkk.",
        "..kkbbbbbbbbkk..",
        "...kkbbbbbbkk...",
        "....kkkkkkkk....",
        ".....kkkkkk.....",
        "................",
    ])

    private static let chest = sprite([
        "................",
        "................",
        "................",
        "..kkkkkkkkkkkk..",
        "..kcccccccccck..",
        "..kcccccccccck..",
        "..kcccccccccck..",
        "..kccccCCcccck..",
        "..kCCCCCCCCCCk..",
        "..kccccCCcccck..",
        "..kccccCCcccck..",
        "..kcccccccccck..",
        "..kcccccccccck..",
        "..kcccccccccck..",
        "..kkkkkkkkkkkk..",
        "................",
    ])

    private static let chestOpen = sprite([
        "..kkkkkkkkkkkk..",
        "..cccccccccccc..",
        "..cccccccccccc..",
        "..cccccccccccc..",
        "..cccccccccccc..",
        "..kkkkkkkkkkkk..",
        "..kkkkkkkkkkkk..",
        "..kkkCkkkCkkkk..",
        "..kkkkkCkkkCkk..",
        "..kcccccccccck..",
        "..kcccccccccck..",
        "..kcccccccccck..",
        "..kcccccccccck..",
        "..kcccccccccck..",
        "..kcccccccccck..",
        "................",
    ])

    private static let stairsBoss = sprite([
        "................",
        "................",
        ".kkkkkkkkkkkkkk.",
        ".ksssssssssssss.",
        ".ksssssssssssss.",
        "....kkkkkkkkkkk.",
        "....kssssssssss.",
        "....kssssssssss.",
        ".......kkkkkkkk.",
        ".......ksssssss.",
        ".......ksssssss.",
        "..........kkkkk.",
        "..........kssss.",
        "..........kssss.",
        "................",
        "................",
    ])

    private static let decorCrack = sprite([
        "................",
        "................",
        "................",
        "....k...........",
        ".....k..........",
        ".....kk.........",
        "......k.........",
        ".......k........",
        ".......kk.......",
        "........k.......",
        ".........k......",
        ".........k......",
        "..........k.....",
        "................",
        "................",
        "................",
    ])

    private static let decorMoss = sprite([
        "................",
        "................",
        "................",
        "................",
        "...mm.......m...",
        "....mm.....m....",
        "................",
        "................",
        "................",
        ".........mm.....",
        "..........mm....",
        "......mm........",
        "................",
        "................",
        "................",
        "................",
    ])

    private static let decorPebble = sprite([
        "................",
        "................",
        "................",
        "................",
        "................",
        "....ss..........",
        "....kk..........",
        "..........ss....",
        "..........kk....",
        "................",
        "................",
        "......ss........",
        "......kk........",
        "................",
        "................",
        "................",
    ])

    static func sprite(for tile: RoomTile) -> PixelSprite {
        switch tile {
        case .floor: return floor
        case .floorHome: return floorHome
        case .wall: return wall
        case .wallHome: return wallHome
        case .doorOpen: return doorOpen
        case .spring: return spring
        case .chest: return chest
        case .chestOpen: return chestOpen
        case .stairsBoss: return stairsBoss
        case .crack: return decorCrack
        case .moss: return decorMoss
        case .pebble: return decorPebble
        }
    }

    /// 구워 둔 타일. 첫 접근에 한 번 만들어지고 그 뒤로는 사전 조회다.
    private static let baked: [RoomTile: CGImage] = {
        var out: [RoomTile: CGImage] = [:]
        for tile in RoomTile.allCases {
            if let image = sprite(for: tile).cgImage(palette: palette) { out[tile] = image }
        }
        return out
    }()

    static func image(_ tile: RoomTile) -> CGImage? { baked[tile] }
}

/// 방 화면이 쓰는 타일 종류. `FloorDecor.none` 은 그릴 것이 없으므로 여기 없다.
enum RoomTile: CaseIterable, Hashable, Sendable {
    case floor, floorHome, wall, wallHome, doorOpen, spring, chest, chestOpen, stairsBoss
    case crack, moss, pebble

    init?(decor: FloorDecor) {
        switch decor {
        case .none: return nil
        case .crack: self = .crack
        case .moss: self = .moss
        case .pebble: self = .pebble
        }
    }
}
