import XCTest
@testable import PokeTokenBar

/// 아이콘만 있는 버튼에는 **읽어 줄 이름**이 있어야 한다.
///
/// 앱은 아이콘 버튼을 화면마다 따로 만들었고, 이름을 안 단 자리가 18곳이었다 — 화면 판독기로
/// 보면 이름 없는 버튼이 늘어선 화면이다. `help` 는 이 자리를 대신하지 못한다. 그건 마우스
/// 포인터가 머물 때 뜨는 툴팁이라 VoiceOver 에는 전달되지 않는다.
///
/// 왜 안 걸렸나: 접근성은 어느 화면의 기능 요구사항으로도 적히지 않는다. 화면별 테스트는 버튼이
/// 눌리면 통과하고, 눌리는 것과 이름이 있는 것은 서로 무관하다. 그래서 화면 밖 전수로 둔다.
///
/// 글자가 붙은 버튼은 그 글자가 곧 이름이라 규칙 밖이다. 스캐너의 한계는 `SwiftSourceScan` 참고.
final class IconButtonLabelGuardTests: XCTestCase {

    func testEveryIconOnlyButtonHasAnAccessibilityLabel() throws {
        let files = SwiftSourceScan.files(under: "UI", from: #filePath)
        // 경로가 깨지면 빈 목록을 훑고 조용히 통과한다 — 그걸 막는 단언.
        XCTAssertGreaterThan(files.count, 10, "UI 소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for block in SwiftSourceScan.buttonBlocks(in: lines)
            where SwiftSourceScan.isIconOnly(block.text) && !block.text.contains(".accessibilityLabel") {
                offenders.append("\(file.lastPathComponent):\(block.start + 1)")
            }
        }
        XCTAssertEqual(offenders, [], "이름 없는 아이콘 버튼 \(offenders.count)개: \(offenders)")
    }
}
