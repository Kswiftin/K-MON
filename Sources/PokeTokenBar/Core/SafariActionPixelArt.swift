import Foundation

/// 사파리존 조우 화면의 볼·미끼·진흙 아이템 스프라이트. `PixelSprite`/`PixelPalette`
/// (트레이너·사파리 필드 타일과 같은 파이프라인)을 그대로 재사용한다.
///
/// 각 아이템은 **정지 이미지 한 장**뿐이다 — "날아가며 회전한다"는 느낌은 프레임을 갈아 끼우지
/// 않고 SwiftUI `.rotationEffect` 하나로 낸다(다리 움직임을 표현해야 하는 트레이너와 다르다).
enum SafariActionPixelArt {
    private static let ballKey: [Character: UInt8] = ["1": 1, "2": 2, "3": 3]
    private static let baitKey: [Character: UInt8] = ["1": 1, "2": 2]
    private static let mudKey: [Character: UInt8] = ["1": 1]

    /// 위 절반 빨강(1)·아래 절반 흰색(2)·가운데 띠와 버튼 테두리는 검정(3) — 몬스터볼 실루엣.
    static let ball = PixelSprite(rows: [
        ".111111.",
        "11111111",
        "11122111",
        "33222333",
        "22222222",
        "22222222",
        "12222221",
        ".222222.",
    ], key: ballKey)
    static let ballPalette = PixelPalette(colors: [0, 0xE0393C, 0xF3F3F3, 0x1B1B2F])

    /// 초록 꼭지(2) + 둥근 빨강 열매(1).
    static let bait = PixelSprite(rows: [
        "........",
        "..2.2...",
        "...11...",
        ".111111.",
        "11111111",
        "11111111",
        ".111111.",
        "..1111..",
    ], key: baitKey)
    static let baitPalette = PixelPalette(colors: [0, 0xD83A3A, 0x3B8A3F])

    /// 갈색 덩어리(1).
    static let mud = PixelSprite(rows: [
        "........",
        "..1111..",
        ".111111.",
        "11111111",
        "11111111",
        ".111111.",
        "..1111..",
        "........",
    ], key: mudKey)
    static let mudPalette = PixelPalette(colors: [0, 0x6E5A3E])
}
