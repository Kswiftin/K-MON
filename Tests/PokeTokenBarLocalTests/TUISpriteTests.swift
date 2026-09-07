import CoreGraphics
import Foundation
import Testing
@testable import PokeTokenBar

// 터미널에 그리는 파트너 그림. 픽셀 → 칸 변환은 전부 순수 함수라 터미널을 띄우지 않고 검증한다.
//
// 이 화면이 특별히 위험한 이유: 그림 줄에는 **SGR escape** 가 들어간다. `TUIText.displayWidth` 는
// escape 바이트를 글자로 세므로(TUIText.swift:49) 그림 줄이 `truncate`·`pad` 를 통과하면 escape
// 중간에서 잘리고, 그 줄부터 커서 열이 어긋난다. 그래서 폭·높이 판정을 그림 만드는 쪽에 두고
// 여기서 잠근다.
@Suite("TUISpriteTests")
struct TUISpriteTests {

    // MARK: 픽셀 → 반칸

    /// 픽셀 두 줄이 글자 한 줄이 된다 — 위는 전경, 아래는 배경, 글자는 `▀`.
    /// 칸마다 `[0m` 을 먼저 내는 이유는 앞 칸의 배경색이 다음 칸으로 새지 않게 하기 위해서다.
    @Test func testTwoPixelRowsBecomeOneHalfBlockLine() {
        let pixels = TUISprite.Pixels(width: 2, height: 2, rgba: [
            255, 0, 0, 255,   0, 255, 0, 255,     // 위: 빨강 · 초록
            0, 0, 255, 255,   0, 0, 0, 0,         // 아래: 파랑 · 투명
        ])
        let lines = TUISprite.rows(pixels)
        #expect(lines.count == 1)
        #expect(lines[0] == "\u{1B}[0m\u{1B}[38;2;255;0;0;48;2;0;0;255m▀"
                + "\u{1B}[0m\u{1B}[38;2;0;255;0m▀"
                + "\u{1B}[0m")
    }

    /// 위가 비고 아래만 있으면 아래쪽 반칸(`▄`)이다. `▀` 에 배경색만 넣어 표현하면 앞 칸이 남긴
    /// 전경색이 그 칸에 그려진다.
    @Test func testBottomOnlyPixelUsesLowerHalfBlock() {
        let pixels = TUISprite.Pixels(width: 1, height: 2, rgba: [
            0, 0, 0, 0,
            9, 8, 7, 255,
        ])
        #expect(TUISprite.rows(pixels) == ["\u{1B}[0m\u{1B}[38;2;9;8;7m▄\u{1B}[0m"])
    }

    /// 양쪽이 투명하면 공백이다 — 색을 지운 뒤 공백을 내야 한다. 그냥 공백만 내면 앞 칸의
    /// 배경색이 그 칸을 칠한다.
    @Test func testTransparentCellClearsColorBeforeSpace() {
        let pixels = TUISprite.Pixels(width: 1, height: 2, rgba: Array(repeating: 0, count: 8))
        #expect(TUISprite.rows(pixels) == ["\u{1B}[0m \u{1B}[0m"])
    }

    /// 픽셀 높이가 홀수면 마지막 글자 줄의 아래 절반이 **없다**. 없는 픽셀을 읽으면 배열 범위를
    /// 넘어 크래시한다(`TUIRender.bar` 의 클램프와 같은 부류).
    @Test func testOddPixelHeightTreatsMissingBottomRowAsTransparent() {
        let pixels = TUISprite.Pixels(width: 1, height: 1, rgba: [1, 2, 3, 255])
        #expect(TUISprite.rows(pixels) == ["\u{1B}[0m\u{1B}[38;2;1;2;3m▀\u{1B}[0m"])
    }

    /// 빈 격자는 빈 배열이다. 빈 문자열 한 줄을 내면 홈 화면에 이유 없는 빈 줄이 생긴다.
    @Test func testEmptyPixelsYieldNoLines() {
        #expect(TUISprite.rows(TUISprite.Pixels(width: 0, height: 0, rgba: [])).isEmpty)
    }

    // MARK: 자르기와 줄이기

    /// 스프라이트 원본은 여백이 절반을 넘는다(96×96 캔버스에 실물은 그 일부). 불투명 경계로
    /// 자르지 않으면 파트너가 가운데 점으로 보인다.
    @Test func testFitCropsToOpaqueBounds() {
        // 4×4 중 오른쪽 아래 2×2 만 불투명.
        var rgba = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for (x, y) in [(2, 2), (3, 2), (2, 3), (3, 3)] {
            let i = (y * 4 + x) * 4
            rgba[i] = 200; rgba[i + 1] = 100; rgba[i + 2] = 50; rgba[i + 3] = 255
        }
        let fitted = TUISprite.fit(TUISprite.Pixels(width: 4, height: 4, rgba: rgba), columns: 2, pixelRows: 2)
        #expect(fitted?.width == 2)
        #expect(fitted?.height == 2)
        // 잘라 낸 뒤에는 네 픽셀 모두 불투명이어야 한다 — 여백이 남았으면 alpha 0 이 섞인다.
        #expect(fitted?.rgba.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 255 } == true)
    }

    /// 전부 투명한 이미지는 자를 경계가 없다. `nil` 로 돌려 그림을 아예 빼야 한다 —
    /// 0 폭 격자를 만들면 그 뒤 계산이 전부 0 으로 나눈다.
    @Test func testFitReturnsNilWhenNothingIsOpaque() {
        let blank = TUISprite.Pixels(width: 4, height: 4, rgba: [UInt8](repeating: 0, count: 64))
        #expect(TUISprite.fit(blank, columns: 2, pixelRows: 2) == nil)
    }

    /// 아주 좁은·짧은 터미널에서 예산이 0 이하로 계산될 수 있다. 크래시하지 않고 `nil` 이어야 한다.
    @Test func testFitRejectsNonPositiveBudgets() {
        let pixels = TUISprite.Pixels(width: 2, height: 2, rgba: [UInt8](repeating: 255, count: 16))
        #expect(TUISprite.fit(pixels, columns: 0, pixelRows: 4) == nil)
        #expect(TUISprite.fit(pixels, columns: -3, pixelRows: 4) == nil)
        #expect(TUISprite.fit(pixels, columns: 4, pixelRows: 0) == nil)
        #expect(TUISprite.fit(pixels, columns: 4, pixelRows: -2) == nil)
    }

    /// 세로는 항상 짝수여야 한다 — 반칸 하나가 픽셀 두 줄이라, 홀수면 마지막 줄이 반쪽으로 남는다.
    @Test func testFitKeepsPixelHeightEven() {
        let pixels = TUISprite.Pixels(width: 8, height: 8, rgba: [UInt8](repeating: 255, count: 8 * 8 * 4))
        for columns in 1...12 {
            for pixelRows in [2, 4, 10, 24] {
                let fitted = TUISprite.fit(pixels, columns: columns, pixelRows: pixelRows)!
                #expect(fitted.height % 2 == 0)
                #expect(fitted.rgba.count == fitted.width * fitted.height * 4)
            }
        }
    }

    /// **두 예산 안에 비율을 지켜 넣는다.** 가로세로를 같은 배율로 줄여야 파트너가 늘거나 눌리지
    /// 않고, 정사각으로 맞추면 넓은 종의 위아래에 빈 띠가 생겨 `watch` 의 줄 예산을 그만큼 버린다.
    @Test func testFitScalesBothAxesByTheSameFactor() {
        // 가로가 두 배인 내용(16×8, 전부 불투명).
        let pixels = TUISprite.Pixels(width: 16, height: 8,
                                      rgba: [UInt8](repeating: 255, count: 16 * 8 * 4))
        let fitted = TUISprite.fit(pixels, columns: 16, pixelRows: 40)!
        #expect(fitted.width == 16)
        #expect(fitted.height == 8, "비율이 어긋났다")
        // 세로 예산이 더 좁으면 그쪽이 배율을 정한다.
        let short = TUISprite.fit(pixels, columns: 16, pixelRows: 4)!
        #expect(short.height == 4)
        #expect(short.width == 8, "세로 예산이 배율을 정하지 못했다")
    }

    /// **가장 가까운 픽셀만 집지 않고 면적을 평균한다.** 96px 원본을 40칸으로 줄이면 최근접은
    /// 원본의 절반 이상을 버려 곡선이 계단으로 깨진다. 한 칸 간격으로 검정·흰색이 번갈아 있는
    /// 원본을 절반으로 줄이면 평균은 중간값이고, 최근접은 검정 아니면 흰색이다.
    @Test func testFitAveragesTheSourceAreaInsteadOfPickingOnePixel() {
        var rgba: [UInt8] = []
        for _ in 0..<4 {
            for x in 0..<4 {
                let level: UInt8 = x % 2 == 0 ? 0 : 255
                rgba += [level, level, level, 255]
            }
        }
        let fitted = TUISprite.fit(TUISprite.Pixels(width: 4, height: 4, rgba: rgba), columns: 2, pixelRows: 2)!
        for i in stride(from: 0, to: fitted.rgba.count, by: 4) {
            let level = Int(fitted.rgba[i])
            #expect(level >= 100, "중간값이 아니다 — 최근접으로 집었다")
            #expect(level <= 155, "중간값이 아니다 — 최근접으로 집었다")
        }
    }

    /// 색은 **알파로 가중**해 평균한다. 투명 픽셀의 색(대개 검정)을 같은 무게로 섞으면
    /// 스프라이트 테두리가 한 칸 안쪽까지 검게 죽는다.
    @Test func testFitWeightsColorByAlpha() {
        // 양끝은 불투명 빨강, 가운데 둘은 완전 투명한 검정. 경계가 전 폭을 덮으므로 두 칸으로
        // 줄이면 한 칸 안에서 빨강과 투명이 섞인다.
        var rgba: [UInt8] = []
        for _ in 0..<4 {
            for x in 0..<4 { rgba += (x == 0 || x == 3) ? [255, 0, 0, 255] : [0, 0, 0, 0] }
        }
        let fitted = TUISprite.fit(TUISprite.Pixels(width: 4, height: 4, rgba: rgba), columns: 2, pixelRows: 2)!
        // 색은 **순수 빨강**이어야 한다. 알파를 무시하고 평균하면 투명한 검정이 절반 섞여 127 이 된다.
        let red = Int(fitted.rgba[0])
        let green = Int(fitted.rgba[1])
        let alpha = Int(fitted.rgba[3])
        #expect(red == 255, "투명한 검정이 색을 끌어내렸다")
        #expect(green == 0)
        // 알파는 덮인 비율이다 — 절반만 덮였다.
        #expect(alpha >= 120)
        #expect(alpha <= 135)
    }

    /// 반칸 하나는 색이 하나뿐이라 반투명을 표현할 수 없다. **절반 이상 덮인 칸만** 그린다 —
    /// 조금 걸친 칸까지 그리면 스프라이트 주위에 한 칸짜리 후광이 생겨 실루엣이 부푼다.
    @Test func testCellsCoveredLessThanHalfAreNotDrawn() {
        let faint = TUISprite.Pixels(width: 1, height: 2, rgba: [9, 9, 9, 100,  0, 0, 0, 0])
        let solid = TUISprite.Pixels(width: 1, height: 2, rgba: [9, 9, 9, 200,  0, 0, 0, 0])
        #expect(TUISprite.rows(faint) == ["\u{1B}[0m \u{1B}[0m"])
        #expect(TUISprite.rows(solid) == ["\u{1B}[0m\u{1B}[38;2;9;9;9m▀\u{1B}[0m"])
    }

    /// 자를 경계는 반대로 **희미한 테두리까지** 포함한다. 그리는 판정으로 경계를 잡으면
    /// 안티에일리어싱된 윤곽이 잘려 스프라이트가 한 칸씩 깎인다.
    @Test func testCropBoundsIncludeFaintEdges() {
        // 가운데만 진하고 둘레는 희미한 3×3.
        let faint: [UInt8] = [9, 9, 9, 20]
        let solid: [UInt8] = [9, 9, 9, 255]
        var rgba: [UInt8] = []
        for y in 0..<3 {
            for x in 0..<3 { rgba += (x == 1 && y == 1) ? solid : faint }
        }
        let fitted = TUISprite.fit(TUISprite.Pixels(width: 3, height: 3, rgba: rgba), columns: 3, pixelRows: 4)!
        // 둘레까지 경계에 들었으면 3×3 이 그대로 3칸으로 온다(가운데 한 점만 잡으면 1칸이 된다).
        #expect(fitted.width == 3)
        #expect(fitted.rgba[3] > 0, "희미한 왼쪽 위가 경계에서 빠졌다")
    }

    /// 가로로 넓은 스프라이트의 **양끝을 잘라 내지 않는다.** 짧은 변을 기준으로 정사각으로
    /// 자르면(고래왕자는 106×68 이다) 지느러미가 통째로 사라지고, 잘린 것이 무엇인지 사용자는
    /// 알 수 없다.
    @Test func testFitKeepsBothEdgesOfWideContent() {
        // 8×2 전부 불투명 — 왼끝 빨강, 오른끝 파랑, 가운데 초록.
        var rgba: [UInt8] = []
        for _ in 0..<2 {
            for x in 0..<8 {
                if x == 0 { rgba += [255, 0, 0, 255] }
                else if x == 7 { rgba += [0, 0, 255, 255] }
                else { rgba += [0, 255, 0, 255] }
            }
        }
        let fitted = TUISprite.fit(TUISprite.Pixels(width: 8, height: 2, rgba: rgba), columns: 4,
                                   pixelRows: 8)!
        #expect(fitted.width == 4)
        // 내용이 있는 줄에서 왼끝에 빨강이, 오른끝에 파랑이 남아 있어야 한다.
        let rows = (0..<fitted.height).map { y in (0..<fitted.width).map { x -> [UInt8] in
            let i = (y * fitted.width + x) * 4
            return Array(fitted.rgba[i..<(i + 4)])
        } }
        let withContent = rows.filter { $0.contains { $0[3] > 0 } }
        #expect(!withContent.isEmpty, "내용이 있는 줄이 하나도 없다")
        #expect(withContent.contains { $0.first![0] > 0 }, "왼끝 빨강이 잘렸다")
        #expect(withContent.contains { $0.last![2] > 0 }, "오른끝 파랑이 잘렸다")
    }

    // MARK: 블록 — 폭·높이·색 판정

    private static func solid(_ side: Int) -> TUISprite.Pixels {
        TUISprite.Pixels(width: side, height: side,
                         rgba: (0..<(side * side)).flatMap { _ -> [UInt8] in [40, 80, 160, 255] })
    }

    /// 그림이 붙는 정상 경로. 블록 높이는 흔들림과 **무관하게 같다** — 위상마다 높이가 달라지면
    /// 아래 줄(경험치·모험)이 매초 흔들린다.
    @Test func testBlockHeightIsStableAcrossBobPhases() {
        let pixels = Self.solid(32)
        let down = TUISprite.block(pixels, width: 80, maxRows: 40, colorAllowed: true, bobbed: false)
        let up = TUISprite.block(pixels, width: 80, maxRows: 40, colorAllowed: true, bobbed: true)
        #expect(!down.isEmpty)
        #expect(down.count == up.count)
        #expect(down != up)   // 위상이 같으면 흔들리지 않는다
    }

    /// 흔들림은 빈 줄의 위치만 바꾼다 — 그림 줄 자체는 두 위상에서 같아야 한다.
    /// 프레임마다 픽셀을 다시 뽑으면 흔들림이 아니라 깜빡임이 된다.
    @Test func testBobMovesTheBlankRowNotTheArtwork() {
        let pixels = Self.solid(32)
        let down = TUISprite.block(pixels, width: 80, maxRows: 40, colorAllowed: true, bobbed: false)
        let up = TUISprite.block(pixels, width: 80, maxRows: 40, colorAllowed: true, bobbed: true)
        #expect(down.first == "")
        #expect(up.last == "")
        #expect(down.dropFirst() == up.dropLast())
    }

    /// 색을 못 쓰는 자리(파이프·`NO_COLOR`)에서는 그림이 통째로 빠진다. escape 가 섞여 나가면
    /// 상태줄·로그 파일에 제어문자가 박힌다.
    @Test func testBlockIsEmptyWhenColorIsNotAllowed() {
        #expect(TUISprite.block(Self.solid(32), width: 80, maxRows: 40,
                                colorAllowed: false, bobbed: false).isEmpty)
    }

    /// 캐시에 스프라이트가 없으면 그림이 없다 — 그것이 정상 상태다(알 부화 중과 같은 부류).
    @Test func testBlockIsEmptyWithoutPixels() {
        #expect(TUISprite.block(nil, width: 80, maxRows: 40, colorAllowed: true, bobbed: false).isEmpty)
    }

    /// 좁은 창에서는 그림을 뺀다. 남겨 두면 그림이 폭을 넘겨 줄이 접히고 화면이 흘러간다.
    @Test func testBlockIsEmptyOnNarrowTerminals() {
        #expect(TUISprite.block(Self.solid(32), width: TUISprite.minimumWidth - 1, maxRows: 40,
                                colorAllowed: true, bobbed: false).isEmpty)
        #expect(!TUISprite.block(Self.solid(32), width: TUISprite.minimumWidth, maxRows: 40,
                                 colorAllowed: true, bobbed: false).isEmpty)
    }

    /// 짧은 창에서는 **작게 그린다.** `TUITerminal.draw` 는 높이를 넘는 줄을 버리므로(prefix)
    /// 예산을 넘길 수는 없지만, 넘길 것 같으면 통째로 빼는 것이 아니라 칸 수를 줄인다 —
    /// 24줄 터미널에서 그림이 영영 안 나오는 것을 막는다.
    @Test func testBlockShrinksToTheRowBudgetInsteadOfVanishing() {
        let pixels = Self.solid(64)
        let roomy = TUISprite.block(pixels, width: 120, maxRows: 60, colorAllowed: true, bobbed: false)
        let tight = TUISprite.block(pixels, width: 120, maxRows: 8, colorAllowed: true, bobbed: false)
        #expect(!tight.isEmpty, "예산이 8줄이면 작게라도 그려야 한다")
        #expect(tight.count <= 8)
        #expect(tight.count < roomy.count)
    }

    /// 예산이 가장 작은 그림도 못 담으면 그때는 뺀다 — 몇 칸짜리 그림은 파트너로 보이지 않는다.
    @Test func testBlockIsEmptyBelowTheSmallestUsefulBlock() {
        let smallest = TUISprite.minimumColumns / 2 + 1
        for budget in 0..<smallest {
            #expect(TUISprite.block(Self.solid(64), width: 120, maxRows: budget,
                                    colorAllowed: true, bobbed: false).isEmpty)
        }
        #expect(!TUISprite.block(Self.solid(64), width: 120, maxRows: smallest,
                                 colorAllowed: true, bobbed: false).isEmpty)
    }

    /// 스프라이트 **안쪽**의 빈 자리(모서리·다리 사이)는 알파 0 인 칸이 된다. 색을 계산하지 않고
    /// 공백으로 남겨야 한다 — 알파 합이 0 이라 색을 구하면 0 으로 나눈다.
    @Test func testFullyTransparentCellsStayEmpty() {
        // 왼쪽 위와 오른쪽 아래 모서리만 불투명 → 경계는 전체 4×4, 가운데는 비어 있다.
        var rgba = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for (x, y) in [(0, 0), (3, 3)] {
            let i = (y * 4 + x) * 4
            rgba[i] = 200; rgba[i + 1] = 100; rgba[i + 2] = 50; rgba[i + 3] = 255
        }
        let fitted = TUISprite.fit(TUISprite.Pixels(width: 4, height: 4, rgba: rgba),
                                   columns: 2, pixelRows: 2)!
        // 오른쪽 위 칸은 원본이 전부 투명하다.
        #expect(fitted.rgba[(0 * 2 + 1) * 4 + 3] == 0)
        // 그 칸은 공백으로 그려진다.
        #expect(TUISprite.rows(fitted)[0].hasSuffix("\u{1B}[0m \u{1B}[0m"))
    }

    // MARK: 두 예산

    /// 넓은 창에서는 상한까지 쓴다. 20칸으로 묶어 두면 소스(96~106px)가 가진 해상도를 절반도
    /// 못 쓴다.
    @Test func testColumnsUseTheCapWhenThereIsRoom() {
        #expect(TUISprite.columns(width: 200) == TUISprite.maximumColumns)
        #expect(TUISprite.columns(width: TUISprite.minimumWidth - 1) == 0)
    }

    /// 픽셀 줄 예산은 **남은 글자 줄의 두 배**다 — 반칸 하나가 픽셀 두 줄이다. 흔들림에 쓰는
    /// 한 줄은 먼저 뗀다.
    @Test func testPixelRowsAreTwiceTheRemainingTextRows() {
        #expect(TUISprite.pixelRows(maxRows: 11) == 20)
        #expect(TUISprite.pixelRows(maxRows: 6) == 10)
        #expect(TUISprite.pixelRows(maxRows: 1) == 0)
        #expect(TUISprite.pixelRows(maxRows: 0) == 0)
    }

    /// 한 번 찍는 명령은 예산이 없다는 뜻으로 `.max` 를 넘긴다. 두 배로 부풀리는 계산이
    /// **정수 넘침으로 죽지 않아야** 한다.
    @Test func testPixelRowsSurviveAnUnboundedBudget() {
        #expect(TUISprite.pixelRows(maxRows: .max) == TUISprite.maximumColumns)
    }

    /// 픽셀 줄 수는 항상 짝수다 — 홀수면 마지막 글자 줄이 반쪽으로 남는다.
    @Test func testPixelRowsAreAlwaysEven() {
        for maxRows in 0...200 {
            #expect(TUISprite.pixelRows(maxRows: maxRows) % 2 == 0)
        }
    }

    /// 그림 줄은 폭 계산을 통과하지 않는다는 전제로 만든다. 그래서 **칸 수를 스스로 지켜야** 한다 —
    /// 넘치면 줄이 접힌다. 폭에서 세는 것은 글리프 수(칸 수)이고 escape 는 0 칸이다.
    @Test func testBlockNeverExceedsTerminalWidth() {
        for width in TUISprite.minimumWidth...120 {
            let block = TUISprite.block(Self.solid(48), width: width, maxRows: 60,
                                        colorAllowed: true, bobbed: false)
            for line in block {
                #expect(TUISprite.visibleWidth(line) <= width)
            }
        }
    }

    // MARK: 흔들림 위상 · 색 허용 판정

    /// 저전력 모드에서는 흔들리지 않는다. 상시 표시 애니메이션이 지켜야 하는 규율이다
    /// (`defect-log.md` "에너지" — 플로팅 펫의 `shouldAnimate(lowPower:)` 와 같은 판정).
    @Test func testLowPowerModeStopsTheBob() {
        for frame in 0..<20 {
            #expect(TUISprite.isBobbed(frame: frame, lowPower: true) == false)
        }
    }

    /// 위상은 한 번 바뀌면 최소 `bobFrames` 프레임을 유지한다. `watch` 틱이 0.5초이므로 이 값이
    /// 곧 애니메이션 주기이고, GIF 하한(0.4초)보다 느려야 한다.
    @Test func testBobHoldsEachPhaseForTheConfiguredFrames() {
        #expect(TUISprite.bobFrames >= 2)   // 0.5초 틱 × 2 = 1초 ≥ 0.4초 하한
        let phases = (0..<(TUISprite.bobFrames * 4)).map { TUISprite.isBobbed(frame: $0, lowPower: false) }
        // 같은 위상이 연속 bobFrames 개씩 나온다.
        for chunk in stride(from: 0, to: phases.count, by: TUISprite.bobFrames) {
            let slice = phases[chunk..<(chunk + TUISprite.bobFrames)]
            #expect(slice.allSatisfy { $0 == slice.first })
        }
        #expect(Set(phases).count == 2)   // 두 위상이 실제로 다 나온다
    }

    /// CSI 가 아닌 escape(`ESC c` 처럼 두 글자로 끝나는 시퀀스)도 0 칸이다. 그림은 CSI 만 쓰지만
    /// 이 함수는 홈의 **모든 줄**을 세는 데 쓰이므로, 다른 시퀀스에서 글자가 새면 총폭 단정이
    /// 헛돈다. 한글은 두 칸, 영문은 한 칸이다.
    @Test func testVisibleWidthSkipsNonCSIEscapes() {
        #expect(TUISprite.visibleWidth("\u{1B}c가A") == 3)
        #expect(TUISprite.visibleWidth("가A") == 3)
    }

    // MARK: 캐시 이미지 → 픽셀

    /// 알파가 **미리 곱해진** 값을 그대로 쓰면 반투명 테두리가 검게 죽는다. 되돌려야 원래 색이다.
    /// (스프라이트 테두리는 안티에일리어싱이라 알파가 중간값인 픽셀이 실제로 있다.)
    @MainActor
    @Test func testPixelsUndoPremultipliedAlpha() {
        // 알파 128 에 곱해진 빨강 128 → 되돌리면 255 다.
        let image = Self.image(width: 1, height: 1, bytes: [128, 0, 0, 128])
        let pixels = SpriteLoader.pixels(from: image)
        #expect(pixels?.rgba[3] == 128)
        #expect((pixels?.rgba[0] ?? 0) >= 250, "곱해진 알파를 되돌리지 않았다: \(pixels?.rgba[0] ?? 0)")
    }

    /// 위아래가 뒤집히면 안 된다. CoreGraphics 의 사용자 좌표는 왼쪽 **아래**가 원점이라,
    /// 그리는 방향을 확인하지 않으면 파트너가 거꾸로 선다 — 색만 보는 검증으로는 안 걸린다.
    @MainActor
    @Test func testPixelsKeepImageOrientation() {
        // 위 줄 빨강, 아래 줄 파랑.
        let image = Self.image(width: 1, height: 2, bytes: [255, 0, 0, 255,
                                                            0, 0, 255, 255])
        let pixels = SpriteLoader.pixels(from: image)
        #expect(pixels?.width == 1)
        #expect(pixels?.height == 2)
        #expect(pixels?.rgba.prefix(4).elementsEqual([255, 0, 0, 255]) == true, "위 줄이 빨강이 아니다")
        #expect(pixels?.rgba.suffix(4).elementsEqual([0, 0, 255, 255]) == true, "아래 줄이 파랑이 아니다")
    }

    /// 테스트용 RGBA 이미지. 바이트는 위에서 아래로, 알파는 미리 곱해진 값이다.
    private static func image(width: Int, height: Int, bytes: [UInt8]) -> CGImage {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    /// 색은 **터미널일 때만** 쓴다. 파이프·리다이렉트(`pokedoro status > file`)와 `NO_COLOR`,
    /// 색을 모르는 터미널(`TERM=dumb`)에서는 끈다.
    @Test func testColorIsAllowedOnlyOnACapableTTY() {
        #expect(TUISprite.colorAllowed(isTTY: true, noColor: false, term: "xterm-256color"))
        #expect(!TUISprite.colorAllowed(isTTY: false, noColor: false, term: "xterm-256color"))
        #expect(!TUISprite.colorAllowed(isTTY: true, noColor: true, term: "xterm-256color"))
        #expect(!TUISprite.colorAllowed(isTTY: true, noColor: false, term: "dumb"))
        #expect(!TUISprite.colorAllowed(isTTY: true, noColor: false, term: nil))
    }
}
