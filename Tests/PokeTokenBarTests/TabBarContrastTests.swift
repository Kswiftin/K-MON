import XCTest
import SwiftUI
@testable import PokeTokenBar

// MARK: 고른 탭의 글자가 보이는가

/// 다크 모드에서 **고른 탭의 글자만 사라졌다.** 알약은 보이는데 그 위 글자가 안 보였다.
///
/// 원인은 고정 색이다. `PokedoroTheme.ink` 는 다크 네이비 상수라 모드를 따라가지 않는데, 뒤에
/// 깔리는 알약(`controlBackgroundColor` + 파랑 18%)은 모드에 따라 밝기가 뒤집힌다. 라이트에서는
/// 9.79:1 로 멀쩡하고 다크에서는 **1.07:1** — 배경과 사실상 같은 색이 된다.
///
/// 왜 안 걸렸나: 테마 주석이 "밝은 필드" 라고 적혀 있듯 라이트 모드 기준으로 만들어졌고, 화면을
/// 라이트로만 보면 아무 문제가 없다. 색 대비는 **두 모드를 다 봐야** 드러나는 부류다.
final class TabBarContrastTests: XCTestCase {

    /// WCAG 상대 휘도.
    private func luminance(_ color: (Double, Double, Double)) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.0) + 0.7152 * channel(color.1) + 0.0722 * channel(color.2)
    }

    private func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    /// 고른 탭의 알약 = 컨트롤 배경 위에 테마 파랑 18%.
    private func selectedPill(over background: (Double, Double, Double)) -> (Double, Double, Double) {
        let blue = (0.30, 0.47, 0.62)
        return (0.82 * background.0 + 0.18 * blue.0,
                0.82 * background.1 + 0.18 * blue.1,
                0.82 * background.2 + 0.18 * blue.2)
    }

    private let inkConstant = (0.16, 0.20, 0.26)
    private let darkWindow = (0.12, 0.12, 0.13)
    private let lightWindow = (0.98, 0.98, 0.98)

    /// 결함 재현 — 예전 색이 다크 모드에서 왜 안 보였는지. 이 값이 바뀌면 위 설명이 낡은 것이다.
    func testTheOldFixedInkVanishesInDarkMode() {
        XCTAssertLessThan(contrast(inkConstant, selectedPill(over: darkWindow)), 1.5,
                          "이 색이 다크 모드에서 배경과 구별되지 않는 게 결함의 원인이었다")
        XCTAssertGreaterThan(contrast(inkConstant, selectedPill(over: lightWindow)), 4.5,
                            "라이트 모드에서는 멀쩡했다 — 그래서 눈으로 못 잡았다")
    }

    /// 처방 — 모드를 따라가는 색은 **양쪽 모두** 본문 기준(4.5:1)을 넘는다.
    func testTheAdaptiveForegroundClearsBothModes() {
        let white = (1.0, 1.0, 1.0), black = (0.0, 0.0, 0.0)
        XCTAssertGreaterThan(contrast(white, selectedPill(over: darkWindow)), 4.5)
        XCTAssertGreaterThan(contrast(black, selectedPill(over: lightWindow)), 4.5)
    }

    /// **고정 브랜드 색을 글자에 쓰지 않는다.** 배경은 모드를 따라가는데 그 색만 안 따라가면
    /// 한쪽 모드에서 반드시 대비가 무너진다.
    ///
    /// `ink` 자체를 모드에 맞춰 바꾸는 처방은 쓸 수 없다 — `PokeBallMark` 가 **자기가 그린 흰 원**
    /// 위에 ink 로 선을 긋기 때문에, 그 색이 다크 모드에서 밝아지면 몬스터볼이 흰색 위 흰색이 된다.
    /// 그래서 ink 는 고정으로 두고 글자 쪽이 쓰지 않는다.
    func testNoFixedThemeColorIsUsedAsAForeground() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI/PokedoroTheme.swift")
        // 주석은 뺀다 — 규칙을 설명하는 주석이 패턴을 담으면 가드가 자기 설명에 걸린다.
        let code = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
        XCTAssertTrue(code.contains("struct PokedoroTabBar"), "스캔 범위가 깨졌다")

        // **줄 단위로 본다.** `.foregroundStyle(PokedoroTheme.ink` 만 찾으면 삼항 연산자를 놓친다 —
        // 결함이 있던 형태가 정확히 `.foregroundStyle(선택 ? PokedoroTheme.ink : …)` 였다.
        let fixedColors = ["ink", "red", "blue", "yellow", "mint"]
        let offenders = code.split(separator: "\n")
            .filter { $0.contains(".foregroundStyle(") }
            .filter { line in fixedColors.contains { line.contains("PokedoroTheme.\($0)") } }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(offenders, [], """
            고정 테마색을 글자에 썼다. 배경은 모드를 따라가는데 이 색은 안 따라가서 한쪽 모드에서
            반드시 대비가 무너진다 — `Color.primary`/`.secondary` 처럼 모드를 따라가는 색을 쓴다.
            """)
    }
}
