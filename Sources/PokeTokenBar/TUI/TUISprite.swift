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

    /// **자를 경계**를 잡을 때 이 값 미만의 알파는 없는 픽셀로 본다. 0 만 걸러 내면
    /// 안티에일리어싱 테두리의 알파 1~2 가 살아 남아 스프라이트 주위에 검은 테가 생긴다.
    /// 그리는 판정은 이 값이 아니라 `coverageFloor` 다 — 둘의 방향이 반대라 값이 다르다.
    static let alphaFloor: UInt8 = 8

    /// **그릴지 말지**의 문턱. 반칸 하나는 색이 하나뿐이라 반투명을 표현할 방법이 없으므로
    /// 절반 이상 덮인 칸만 그린다. 조금 걸친 칸까지 그리면 스프라이트 주위에 한 칸짜리 후광이
    /// 생겨 실루엣이 부푼다(줄일 때 테두리 칸의 알파는 대개 중간값이다).
    static let coverageFloor: UInt8 = 128

    /// 그림의 가로 칸 수 상한. **화면에서 차지하는 자리로 정한 값이다** — 해상도가 아니다.
    /// 소스(96~106px)는 40칸까지 채울 수 있지만, 그러면 100칸 창에서 홈의 절반이 그림이 된다.
    /// 24칸이면 넓은 종이 8줄(그림 7줄 + 흔들림 1줄)로, 23줄짜리 홈의 3분의 1쯤이다.
    /// 이 값만 바꾸면 크기가 바뀐다 — 세로는 비율에서 따라오므로 따로 만질 것이 없다.
    static let maximumColumns = 24

    /// 이보다 작으면 그리지 않는다 — 몇 칸짜리 그림은 파트너로 보이지 않고 자리만 먹는다.
    static let minimumColumns = 8

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

    /// 이 창에 쓸 수 있는 가로 칸 수.
    static func columns(width: Int) -> Int {
        guard width >= minimumWidth else { return 0 }
        return min(maximumColumns, width)
    }

    /// 이 창에 쓸 수 있는 **픽셀** 줄 수 — 남은 글자 줄의 두 배다(반칸 하나가 픽셀 두 줄).
    /// 흔들림에 쓰는 한 줄은 먼저 뗀다. 홀수가 되지 않는 이유는 두 배 한 값이라서다.
    ///
    /// 예산을 **먼저 접는다**: 한 번 찍는 명령은 예산이 없다는 뜻으로 `.max` 를 넘기므로,
    /// 두 배로 부풀리는 계산을 먼저 하면 정수 넘침으로 죽는다.
    static func pixelRows(maxRows: Int) -> Int {
        let rowBudget = min(maxRows, maximumColumns / 2 + 1)
        return max(0, (rowBudget - 1) * 2)
    }

    /// 불투명 경계로 자른 뒤 `columns` × `pixelRows` **안에 비율을 지켜** 넣는다.
    ///
    /// 자르기가 없으면 파트너가 가운데 점으로 보인다 — 스프라이트 원본은 96×96 캔버스에 실물이
    /// 그 일부만 차지한다(`SpriteLoader.cropToContent` 가 알 스프라이트에서 같은 일을 한다).
    ///
    /// **정사각으로 맞추지 않는다.** 두 축을 같은 배율로 줄이면 비율이 지켜지고, 정사각 창에
    /// 끼워 넣으면 넓은 종(고래왕자 106×68)의 위아래에 빈 띠가 생겨 `watch` 의 줄 예산을
    /// 그만큼 버린다 — 그 예산이 곧 해상도다.
    ///
    /// 불투명 픽셀이 하나도 없으면 `nil` — 0 폭 격자를 만들면 그 뒤 계산이 전부 0 으로 나눈다.
    static func fit(_ pixels: Pixels, columns: Int, pixelRows: Int) -> Pixels? {
        guard columns > 0, pixelRows > 0, pixels.width > 0, pixels.height > 0,
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
        // 배율은 **더 빡빡한 쪽**이 정한다. 정수만으로 계산한다 — 부동소수 배율은 경계에서
        // 한 픽셀씩 흔들려 같은 창에서도 크기가 오락가락한다.
        var targetWidth = columns
        var targetHeight = max(2, boxHeight * columns / boxWidth)
        if targetHeight > pixelRows {
            targetHeight = pixelRows
            targetWidth = min(columns, max(1, boxWidth * pixelRows / boxHeight))
        }
        // 세로는 **짝수**여야 한다 — 반칸 하나가 픽셀 두 줄이라, 홀수면 마지막 줄이 반쪽으로 남는다.
        targetHeight = max(2, targetHeight - targetHeight % 2)

        var out = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        for ty in 0..<targetHeight {
            let y0 = minY + ty * boxHeight / targetHeight
            let y1 = max(y0 + 1, minY + (ty + 1) * boxHeight / targetHeight)
            for tx in 0..<targetWidth {
                let x0 = minX + tx * boxWidth / targetWidth
                let x1 = max(x0 + 1, minX + (tx + 1) * boxWidth / targetWidth)
                // 한 칸이 덮는 **원본 면적을 평균**한다. 가장 가까운 픽셀만 집으면 96px 원본에서
                // 절반 이상을 버려 곡선이 계단으로 깨진다.
                var red = 0, green = 0, blue = 0, alpha = 0, samples = 0
                for sy in y0..<y1 {
                    for sx in x0..<x1 {
                        samples += 1
                        let from = (sy * pixels.width + sx) * 4
                        let weight = Int(pixels.rgba[from + 3])
                        // 색은 **알파로 가중**한다. 투명 픽셀의 색(대개 검정)을 같은 무게로 섞으면
                        // 테두리가 한 칸 안쪽까지 검게 죽는다.
                        red += Int(pixels.rgba[from]) * weight
                        green += Int(pixels.rgba[from + 1]) * weight
                        blue += Int(pixels.rgba[from + 2]) * weight
                        alpha += weight
                    }
                }
                // 알파 합이 0 이면 원본이 전부 투명한 칸이다 — 색을 구하면 0 으로 나눈다.
                // `samples` 는 조건에 넣지 않는다: 범위를 `max(x0 + 1, …)` 로 잡아 **항상 1 이상**이고,
                // 죽은 조건을 끼워 두면 이 가드가 무엇을 지키는지 읽을 수 없다.
                guard alpha > 0 else { continue }
                let to = (ty * targetWidth + tx) * 4
                out[to] = UInt8(min(255, red / alpha))
                out[to + 1] = UInt8(min(255, green / alpha))
                out[to + 2] = UInt8(min(255, blue / alpha))
                out[to + 3] = UInt8(min(255, alpha / samples))
            }
        }
        return Pixels(width: targetWidth, height: targetHeight, rgba: out)
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
        guard colorAllowed, let pixels,
              let fitted = fit(pixels, columns: columns(width: width),
                               pixelRows: pixelRows(maxRows: maxRows)),
              // 몇 칸짜리로 줄어들면 파트너로 보이지 않는다 — 자리만 먹는다.
              fitted.width >= minimumColumns else { return [] }
        // 줄 예산은 여기서 다시 보지 않는다 — `pixelRows` 가 흔들림 한 줄을 먼저 떼고 남은 줄의
        // 두 배를 상한으로 주므로, `fit` 을 지난 그림은 이미 예산 안이다. 여기서 한 번 더 세면
        // **어느 쪽도 실제로 걸리지 않는 가드**가 되어 무엇을 지키는지 알 수 없게 된다
        // (`testBlockShrinksToTheRowBudgetInsteadOfVanishing` 가 그 불변을 끝에서 확인한다).
        let artwork = rows(fitted)
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
        guard pixels.rgba[i + 3] >= coverageFloor else { return nil }
        return "\(pixels.rgba[i]);\(pixels.rgba[i + 1]);\(pixels.rgba[i + 2])"
    }
}
