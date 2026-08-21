import XCTest
@testable import PokeTokenBar

/// 화면이 언어를 **직접 두 갈래로** 가르는 부류를 기계로 막는다.
///
/// `store.language == .ko ? "한국어" : "English"` 는 세 언어 중 두 갈래만 번역한다 — 일본어
/// 사용자에게 영어가 나간다. `BattleView.roomResultText` 의 주석이 이 부류를 이미 적어 뒀지만
/// 주석은 새 코드를 막지 못했고, 스윕 시점에 UI 전체에 115곳이 쌓여 있었다.
///
/// 처방은 `L.t(ko, en, ja)` 다 — 세 인자가 필수라 한 칸을 비우면 컴파일이 막는다. 이 테스트는
/// 그 처방을 우회하는 길(뷰에서 언어를 직접 보는 것)을 닫는다.
///
/// **주석은 검사에서 제외한다.** 규칙을 설명하는 주석 자체가 패턴을 담고 있어(이 파일도 그렇다),
/// 주석까지 걸면 가드가 자기 설명에 걸려 영구 실패한다 — defect-log 가 적어 둔 함정이다.
final class LanguageSplitGuardTests: XCTestCase {

    private var uiDirectory: URL {
        URL(fileURLWithPath: #filePath)            // Tests/PokeTokenBarTests/이 파일
            .deletingLastPathComponent()           // Tests/PokeTokenBarTests
            .deletingLastPathComponent()           // Tests
            .deletingLastPathComponent()           // 저장소 루트
            .appendingPathComponent("Sources/PokeTokenBar/UI")
    }

    func testNoViewSplitsLanguagesByHand() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: uiDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "UI 소스를 못 찾았다 — 경로 계산이 깨졌으면 가드가 조용히 통과한다")

        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }   // 규칙을 설명하는 주석은 제외
                guard line.contains("language == .ko") else { continue }
                offenders.append("\(file.lastPathComponent):\(index + 1)")
            }
        }

        XCTAssertEqual(offenders, [], """
            뷰가 언어를 직접 갈랐다 — 일본어 사용자에게 영어가 나간다. \
            `l.t(ko, en, ja)` 로 바꿔라. 위반 \(offenders.count)곳: \(offenders.prefix(10))
            """)
    }
}
