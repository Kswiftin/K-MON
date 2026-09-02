import Foundation

/// 터미널 칸(cell) 단위 문자열 계산. AppKit 의 `NSAttributedString.size()` 에 해당하는 자리다.
///
/// 왜 따로 있나: 터미널은 글자 수가 아니라 **칸 수**로 배치한다. 한글·CJK·이모지는 한 글자가 두
/// 칸을 차지하므로 `String.count` 로 자르거나 채우면 한국어 이름에서만 테두리가 어긋난다.
/// 반 칸이 잘려 나가면 그 줄부터 커서 열이 밀려 화면 전체가 깨지고, 전체 다시 그리기로는
/// 복구되지 않는다 — 터미널에 "반 칸 되돌리기" 가 없기 때문이다.
enum TUIText {
    /// East Asian Wide/Fullwidth 로 취급하는 스칼라 범위. Unicode EastAsianWidth 표의 부분집합이며
    /// 이 앱이 실제로 그리는 문자(한글·한자·가나·전각 기호·이모지)를 덮는다.
    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F,      // 한글 자모 초성
        0x2E80...0x303E,      // CJK 부수 · 한중일 기호
        0x3041...0x33FF,      // 가나 · 한글 호환 자모 · CJK 호환
        0x3400...0x4DBF,      // CJK 확장 A
        0x4E00...0x9FFF,      // CJK 통합 한자
        0xA000...0xA4CF,      // 이 (Yi)
        0xAC00...0xD7A3,      // 한글 음절
        0xF900...0xFAFF,      // CJK 호환 한자
        0xFE30...0xFE6F,      // CJK 호환 형식 · 소형 변형
        0xFF00...0xFF60,      // 전각 ASCII
        0xFFE0...0xFFE6,      // 전각 기호
        0x1F300...0x1F64F,    // 그림 기호 · 감정 표현
        0x1F900...0x1F9FF,    // 보충 그림 기호
        0x20000...0x3FFFD,    // CJK 확장 B 이상
    ]

    /// 이 스칼라가 두 칸을 먹는가.
    ///
    /// 범위 표만으로는 부족하다 — ✨(U+2728) 처럼 CJK 블록 밖에 있으면서 터미널이 두 칸으로 그리는
    /// 기호가 있다. 그 판정은 유니코드가 `Emoji_Presentation` 으로 이미 갖고 있으므로 범위를
    /// 손으로 늘리는 대신 그 속성을 쓴다. 손으로 늘리면 같은 블록의 한 칸짜리 기호(✓ 등)까지
    /// 두 칸으로 세어 반대 방향으로 어긋난다.
    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isEmojiPresentation { return true }
        let value = scalar.value
        return wideRanges.contains { $0.contains(value) }
    }

    /// 문자 하나의 칸 수. 이모지 시퀀스(ZWJ·변이 선택자로 이어 붙인 것)도 화면에서는 두 칸이므로,
    /// 구성 스칼라를 합산하지 않고 **하나라도 넓으면 2** 로 센다.
    static func width(of character: Character) -> Int {
        if character.unicodeScalars.contains(where: isWide) { return 2 }
        return 1
    }

    /// 문자열의 표시 폭.
    static func displayWidth(_ text: String) -> Int {
        text.reduce(0) { $0 + width(of: $1) }
    }

    /// 표시 폭 `limit` 칸을 넘지 않게 자른다. 경계에 두 칸짜리 글자가 걸리면 그 글자를 **버린다** —
    /// 반쪽을 내보내면 이후 줄의 커서 열이 어긋난다.
    static func truncate(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "" }
        var out = ""
        var used = 0
        for character in text {
            let next = width(of: character)
            if used + next > limit { break }
            out.append(character)
            used += next
        }
        return out
    }

    /// 표시 폭이 정확히 `width` 가 되도록 오른쪽을 공백으로 채운다. 이미 넘치면 잘라서 폭을 지킨다 —
    /// 넘친 채로 두면 터미널이 줄을 접어 화면이 흘러간다.
    static func pad(_ text: String, to width: Int) -> String {
        guard width > 0 else { return "" }
        let cut = truncate(text, to: width)
        return cut + String(repeating: " ", count: width - displayWidth(cut))
    }
}
