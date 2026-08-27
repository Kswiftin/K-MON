import XCTest
@testable import PokeTokenBar

// MARK: 스프라이트 비율 — 정사각 틀에 억지로 맞추지 않는다

/// 플로팅 펫이 뭉개져 보인다는 제보에서 나왔다. 해상도만 문제가 아니라 **가로세로가 찌그러져**
/// 있었다.
///
/// `Image.resizable()` 뒤에 `.frame(width:height:)` 만 걸면 원본을 그 틀에 **늘려 채운다**.
/// 정적 스프라이트(96×96)와 아이템(30×30)은 정사각이라 아무 일도 없었지만, 애니메이션 GIF 는
/// 스프라이트 경계로 잘려 있어 대부분 정사각이 아니다 — 표본 20종 중 18종.
/// 라플라스(102×65)는 정사각 틀에서 세로로 57% 부풀었다.
///
/// 그래서 눈으로도 테스트로도 안 잡혔다. 왜곡을 만드는 경로(GIF)만 비정사각이고, 그 경로는
/// 화면에서만 보이며 원본 크기를 아는 사람이 없으면 "원래 저렇게 생겼나" 로 넘어간다.
final class SpriteAspectTests: XCTestCase {

    private func spriteViewBody() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI/CompanionView.swift")
        // 주석은 뺀다 — 규칙을 설명하는 주석이 패턴을 담으면 가드가 자기 설명에 걸린다.
        let code = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
        let start = try XCTUnwrap(code.range(of: "struct SpriteView: View"),
                                  "SpriteView 를 못 찾았다 — 이름이 바뀌면 가드가 조용히 무력해진다")
        let rest = code[start.upperBound...]
        // 다음 최상위 선언까지가 이 뷰의 몸통이다.
        let end = rest.range(of: "\nprivate struct ") ?? rest.range(of: "\nstruct ")
        return String(end.map { rest[..<$0.lowerBound] } ?? rest)
    }

    /// **늘려 채우는 경로가 하나도 없어야 한다.** `.resizable()` 은 반드시 비율 고정과 짝이다.
    func testEveryResizableSpriteKeepsItsAspectRatio() throws {
        let body = try spriteViewBody()
        let resizable = body.components(separatedBy: ".resizable()").count - 1
        let fitted = body.components(separatedBy: ".aspectRatio(contentMode: .fit)").count - 1
        XCTAssertGreaterThan(resizable, 0, "스캔 범위가 깨졌다 — 그냥 통과하는 가드가 된다")
        XCTAssertEqual(fitted, resizable,
                       "resizable \(resizable)개 중 \(fitted)개만 비율을 지킨다 — 나머지는 늘어난다")
    }

    /// 비정사각 원본이 실제로 존재한다는 근거. 전부 정사각이라면 위 가드는 무의미한 규칙이고,
    /// 언젠가 "필요 없으니 지우자" 가 된다. 왜 필요한지를 숫자로 남긴다.
    ///
    /// 값은 PokéAPI showdown GIF 실측이다(2026-08). 원본이 바뀌면 이 테스트가 먼저 알려준다 —
    /// 그때는 이 표를 고치는 게 맞고, 가드를 지우는 건 아니다.
    func testTheAnimatedSourceIsMostlyNonSquare() {
        let measured: [Int: (width: Int, height: Int)] = [
            1: (45, 49), 3: (106, 77), 4: (48, 57), 25: (60, 60), 39: (46, 46),
            113: (74, 58), 130: (115, 99), 134: (102, 65), 149: (85, 98), 248: (75, 101),
        ]
        let nonSquare = measured.values.filter { $0.width != $0.height }.count
        XCTAssertGreaterThan(nonSquare, measured.count / 2, "다수가 비정사각이라 비율 고정이 필요하다")

        // 가장 심한 칸 — 정사각으로 늘리면 얼마나 부푸는가.
        let worst = measured.values
            .map { abs(Double($0.width) / Double($0.height) - 1) }
            .max() ?? 0
        XCTAssertGreaterThan(worst, 0.5, "라플라스(102×65)급 왜곡이 실제로 있었다")
    }
}
