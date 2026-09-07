import Foundation

/// 파트너 포켓몬을 터미널 칸으로 접는다. **부수효과 없음** — 픽셀을 읽어 오는 일은
/// `SpriteLoader.cachedPixels` 가 하고, 여기서는 받은 격자를 글자로 바꾼다.
///
/// 왜 반칸(`▀`)인가: 터미널 칸은 세로가 가로의 두 배쯤이라, 칸마다 위·아래 색을 따로 주면
/// 픽셀이 정사각으로 보이고 세로 해상도가 두 배가 된다. 한 칸에 한 색을 쓰면 스프라이트가
/// 절반으로 눌린다.
///
/// **이 파일이 만든 줄은 `TUIText.truncate`·`pad` 를 통과시키지 않는다.** 그 둘은 SGR escape
/// 바이트를 글자 한 칸으로 세므로(`TUIText.displayWidth`) escape 중간에서 잘리고, 그 줄부터
/// 커서 열이 어긋난다 — 터미널에 "반 칸 되돌리기" 가 없어 다시 그려도 복구되지 않는다. 대신
/// 폭·높이 판정을 `block` 이 스스로 하고, 만든 줄은 그대로 나간다.
enum TUISprite {

    /// RGBA 픽셀 격자. 알파는 **미리 곱하지 않은** 값이다(곱해진 채로 오면 반투명 테두리가
    /// 검게 죽는다 — 되돌리는 일은 픽셀을 읽는 쪽에서 한다).
    /// 순서는 위에서 아래, 왼쪽에서 오른쪽.
    struct Pixels: Equatable, Sendable {
        let width: Int
        let height: Int
        let rgba: [UInt8]

        init(width: Int, height: Int, rgba: [UInt8]) {
            self.width = width
            self.height = height
            self.rgba = rgba
        }
    }

    /// 이 값 미만의 알파는 없는 픽셀로 본다. 0 만 걸러 내면 안티에일리어싱 테두리의 알파 1~2 가
    /// 살아 남아 스프라이트 주위에 검은 테가 생긴다.
    static let alphaFloor: UInt8 = 8

    /// 그림의 가로 칸 수 상한. 넓은 터미널에서 무한정 키우면 홈의 나머지 줄이 화면 밖으로 밀린다.
    static let maximumColumns = 20

    /// 이 폭 미만에서는 그림을 뺀다. 파트너 이름·경험치 줄이 먼저 읽을 값이고, 좁은 창에서
    /// 그림까지 넣으면 줄이 접혀 화면이 흘러간다.
    static let minimumWidth = 40

    /// 흔들림 한 위상이 유지되는 프레임 수. `watch` 틱이 0.5초이므로 2 프레임 = 1초이고,
    /// 상시 표시 애니메이션의 fps 하한(GIF 0.4초, `defect-log.md` "에너지")보다 느리다.
    /// 새 타이머를 두지 않고 이미 도는 틱의 프레임 번호에 얹는 것도 같은 규율이다.
    static let bobFrames = 2

    /// 색을 쓸 수 있는 자리인가. **터미널일 때만** 참이다 — `pokedoro status > file` 이나
    /// 상태줄로 넘기는 파이프에 escape 가 섞이면 제어문자가 그대로 박힌다.
    /// `TERM` 이 없거나 `dumb` 이면 색을 모르는 터미널이다.
    static func colorAllowed(isTTY: Bool, noColor: Bool, term: String?) -> Bool {
        guard isTTY, !noColor, let term, !term.isEmpty, term != "dumb" else { return false }
        return true
    }

    /// 흔들림 위상. 저전력 모드에서는 **항상 정지**다 — 상시 표시되는 애니메이션 표면이
    /// 물려받는 규율이고, 플로팅 펫의 `FloatingPetController.shouldAnimate(lowPower:)` 와 같은 판정이다.
    static func isBobbed(frame: Int, lowPower: Bool) -> Bool {
        guard !lowPower else { return false }
        // 음수 프레임은 오지 않지만, 나눗셈 부호로 위상이 뒤집히는 것을 막는다.
        return (max(0, frame) / bobFrames) % 2 == 1
    }

    /// 불투명 경계로 자른 뒤 `columns` 픽셀 폭으로 줄인다.
    ///
    /// 자르기가 없으면 파트너가 가운데 점으로 보인다 — 스프라이트 원본은 96×96 캔버스에 실물이
    /// 그 일부만 차지한다(`SpriteLoader.cropToContent` 가 알 스프라이트에서 같은 일을 한다).
    /// 경계는 **정사각으로 넓혀** 비율을 지킨다. 그대로 자르면 세로로 긴 종이 가로로 늘어난다.
    ///
    /// 불투명 픽셀이 하나도 없으면 `nil` — 0 폭 격자를 만들면 그 뒤 계산이 전부 0 으로 나눈다.
    static func fit(_ pixels: Pixels, columns: Int) -> Pixels? {
        guard columns > 0, pixels.width > 0, pixels.height > 0,
              pixels.rgba.count == pixels.width * pixels.height * 4 else { return nil }

        var minX = pixels.width, minY = pixels.height, maxX = -1, maxY = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where pixels.rgba[(y * pixels.width + x) * 4 + 3] >= alphaFloor {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let boxWidth = maxX - minX + 1, boxHeight = maxY - minY + 1
        let side = min(max(boxWidth, boxHeight), min(pixels.width, pixels.height))
        let originX = max(0, min(minX - (side - boxWidth) / 2, pixels.width - side))
        let originY = max(0, min(minY - (side - boxHeight) / 2, pixels.height - side))

        // 세로는 **짝수**여야 한다 — 반칸 하나가 픽셀 두 줄이라, 홀수면 마지막 줄이 반쪽으로 남는다.
        let targetHeight = max(2, columns % 2 == 0 ? columns : columns + 1)
        var out = [UInt8](repeating: 0, count: columns * targetHeight * 4)
        for ty in 0..<targetHeight {
            let sy = originY + ty * side / targetHeight
            for tx in 0..<columns {
                let sx = originX + tx * side / columns
                let from = (sy * pixels.width + sx) * 4
                let to = (ty * columns + tx) * 4
                out[to] = pixels.rgba[from]
                out[to + 1] = pixels.rgba[from + 1]
                out[to + 2] = pixels.rgba[from + 2]
                out[to + 3] = pixels.rgba[from + 3]
            }
        }
        return Pixels(width: columns, height: targetHeight, rgba: out)
    }

    /// 픽셀 두 줄을 글자 한 줄로. 위 픽셀은 전경, 아래 픽셀은 배경이고 글자는 `▀` 다.
    ///
    /// 칸마다 `ESC[0m` 을 먼저 낸다 — 앞 칸이 남긴 배경색이 다음 칸으로 새면 투명한 자리가
    /// 앞 칸 색으로 칠해진다. 아래만 있는 칸은 `▄` 에 전경색을 쓴다(`▀` 에 배경색만 주면
    /// 그 칸의 전경색이 앞 칸에서 흘러온 값이다).
    static func rows(_ pixels: Pixels) -> [String] {
        guard pixels.width > 0, pixels.height > 0,
              pixels.rgba.count == pixels.width * pixels.height * 4 else { return [] }

        var lines: [String] = []
        for top in stride(from: 0, to: pixels.height, by: 2) {
            var line = ""
            for x in 0..<pixels.width {
                let upper = color(pixels, x: x, y: top)
                // 홀수 높이의 마지막 줄은 아래 절반이 **없다**. 없는 픽셀을 읽으면 배열 범위를 넘는다.
                let lower = top + 1 < pixels.height ? color(pixels, x: x, y: top + 1) : nil
                line += "\u{1B}[0m"
                switch (upper, lower) {
                case let (upper?, lower?):
                    line += "\u{1B}[38;2;\(upper);48;2;\(lower)m▀"
                case let (upper?, nil):
                    line += "\u{1B}[38;2;\(upper)m▀"
                case let (nil, lower?):
                    line += "\u{1B}[38;2;\(lower)m▄"
                case (nil, nil):
                    line += " "
                }
            }
            lines.append(line + "\u{1B}[0m")
        }
        return lines
    }

    /// 홈 화면에 얹을 블록. 그림을 못 그리는 조건이면 **빈 배열**이고, 그때 홈은 지금까지의
    /// 텍스트 그대로다 — 그림 없음은 고장이 아니라 정상 상태다(캐시 미스·파이프·좁은 창).
    ///
    /// 높이는 흔들림 위상과 **무관하게 같다**. 위상마다 높이가 달라지면 아래 줄(경험치·모험)이
    /// 매초 한 줄씩 오르내린다 — 파트너가 흔들리는 것이 아니라 화면이 흔들린다.
    ///
    /// `maxRows` 는 이 블록에 내줄 수 있는 줄 수다. `TUITerminal.draw` 는 화면 높이를 넘는 줄을
    /// **버리므로**(`prefix(height)`), 예산을 넘겨 그리면 아래쪽 키 안내가 화면에서 사라진다.
    static func block(_ pixels: Pixels?, width: Int, maxRows: Int,
                      colorAllowed: Bool, bobbed: Bool) -> [String] {
        guard colorAllowed, width >= minimumWidth, let pixels,
              let fitted = fit(pixels, columns: min(maximumColumns, width)) else { return [] }
        let artwork = rows(fitted)
        // 흔들림에 쓰는 빈 줄 한 칸을 더한 것이 이 블록의 높이다.
        guard !artwork.isEmpty, maxRows >= artwork.count + 1 else { return [] }
        return bobbed ? artwork + [""] : [""] + artwork
    }

    /// 화면에서 실제로 차지하는 칸 수. SGR escape 는 0 칸이다.
    /// `TUIText.displayWidth` 를 쓸 수 없어서 따로 센다 — 그쪽은 escape 바이트를 글자로 센다.
    static func visibleWidth(_ line: String) -> Int {
        // ESC 다음 한 글자는 시퀀스의 종류를 정하는 자리다. `[` 면 CSI 라 매개변수가 더 붙고,
        // 그 외(`ESC c` 등)는 거기서 끝난다. **`[` 를 종료 바이트로 세면 안 된다** — 0x5B 는
        // 종료 바이트 범위(0x40–0x7E) 안에 있어서, 범위만 보면 escape 가 바로 끝난 것으로
        // 판정되고 뒤따르는 `38;2;…m` 이 전부 글자로 세어진다.
        enum Scan { case text, introducer, csi }
        var count = 0
        var scan = Scan.text
        for character in line {
            switch scan {
            case .text:
                if character == "\u{1B}" { scan = .introducer; continue }
                count += TUIText.width(of: character)
            case .introducer:
                scan = character == "[" ? .csi : .text
            case .csi:
                // CSI 는 종료 바이트(0x40–0x7E)에서 끝난다. `m` 만 찾으면 다른 시퀀스에서 안 끝난다.
                if let scalar = character.unicodeScalars.first, (0x40...0x7E).contains(scalar.value) {
                    scan = .text
                }
            }
        }
        return count
    }

    /// `R;G;B` — 불투명하지 않으면 `nil`.
    private static func color(_ pixels: Pixels, x: Int, y: Int) -> String? {
        let i = (y * pixels.width + x) * 4
        guard pixels.rgba[i + 3] >= alphaFloor else { return nil }
        return "\(pixels.rgba[i]);\(pixels.rgba[i + 1]);\(pixels.rgba[i + 2])"
    }
}
