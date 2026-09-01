import XCTest
@testable import PokeTokenBar

/// `NSWindow(contentRect:)` 로 잡은 크기는 `contentViewController` 를 붙이는 순간 무효가 된다.
/// AppKit 이 SwiftUI 호스팅 뷰의 fitting size 로 창을 다시 재고, 그 값은 대개 `minSize` 까지
/// 쪼그라든다. 창은 뜨고 내용도 있어서 "동작한다" 로 보이지만 본문이 서너 줄로 접힌다.
///
/// 실제로 두 창이 같은 방식으로 작아진 채 배포됐다 — 릴리스 노트 창(480×400)과 Memory Home
/// (`NSWindow Frame MemoryHomeWindow` 저장값이 선언한 1040×720 이 아닌 minSize 900×640).
/// 사람 눈으로만 잡히는 부류라 소스 스캔으로 막는다: 호스팅 컨트롤러를 창에 붙이는 파일은
/// **붙인 뒤에** 크기를 다시 잡아야 한다.
final class WindowContentSizeGuardTests: XCTestCase {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // Tests/PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // 저장소 루트
            .appendingPathComponent("Sources")
    }

    func testWindowsWithHostingControllerSetContentSize() throws {
        let files = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        // 경로가 깨지면 빈 목록을 훑고 조용히 통과한다 — 그걸 막는 단언.
        XCTAssertGreaterThan(files.count, 10, "소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var offenders: [String] = []
        for file in files {
            // 규칙을 설명하는 주석이 패턴을 담고 있어(이 파일이 그렇다) 주석은 뺀다.
            let code = try String(contentsOf: file, encoding: .utf8)
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            guard code.contains("NSWindow(contentRect:"),
                  code.contains("contentViewController = NSHostingController") else { continue }
            if !code.contains("setContentSize(") { offenders.append(file.lastPathComponent) }
        }

        XCTAssertEqual(offenders, [], """
            창에 SwiftUI 호스팅 컨트롤러를 붙이고 크기를 다시 잡지 않았다 — AppKit 이 fitting size 로 \
            다시 재서 minSize 로 쪼그라든다. contentViewController 를 지정한 **뒤에** \
            setContentSize(...) 를 호출해라.
            """)
    }
}
