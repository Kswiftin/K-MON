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

/// 끝없이 반복하는 애니메이션은 시스템의 "동작 줄이기" 를 따라야 한다.
///
/// `defect-log.md` 에 이미 같은 부류가 있다 — "끄기 설정은 값만 끄고 보간을 남기면 끈 게
/// 아니다"(`CombatantBar`, 2026-08-21). 그때는 앱 자체의 재생 토글이었고, 이번엔 **시스템**
/// 설정이다. 세 곳 중 지키던 곳은 한 곳뿐이었다: 파트너 둥실거림과 알 흔들림은 사용자가
/// 동작을 줄여 놓아도 계속 흔들렸고, 둘 다 화면에 늘 떠 있는 표면이라 피할 방법이 없었다.
///
/// 왜 안 걸렸나: 애니메이션이 도는지는 어느 테스트도 보지 않는다(볼 수도 없다). 그래서 검사는
/// "이 자리에 판정이 있는가" 로 한다 — 값이 맞는지가 아니라 물어보긴 했는가.
final class ReduceMotionGuardTests: XCTestCase {

    /// `repeatForever` 가 있는 줄 위 8줄 안에 `reduceMotion` 판정이 있어야 한다. 거리로 재는
    /// 이유는 판정이 보통 `guard` 나 `if` 로 바로 위에 오기 때문이고, 파일 전체에 하나만 있으면
    /// 되는 규칙으로 두면 한 곳만 지키고 나머지가 새는 원래 상태로 돌아간다.
    func testEveryEndlessAnimationAsksAboutReducedMotion() throws {
        let files = SwiftSourceScan.files(under: "UI", from: #filePath)
        XCTAssertGreaterThan(files.count, 10, "UI 소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated()
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                && line.contains("repeatForever") {
                let window = lines[max(0, index - 8)...index].joined(separator: "\n")
                if !window.contains("reduceMotion") { offenders.append("\(file.lastPathComponent):\(index + 1)") }
            }
        }
        XCTAssertEqual(offenders, [],
                       "동작 줄이기를 안 보는 상시 애니메이션: \(offenders)")
    }
}
