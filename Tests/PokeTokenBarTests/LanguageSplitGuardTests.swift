import XCTest
@testable import PokeTokenBar

/// 세 언어 중 **두 갈래만** 번역하는 부류를 기계로 막는다 — 일본어 사용자에게 영어가 나간다.
///
/// 처방은 `L.t(ko, en, ja)` 다(인자 세 개가 필수라 한 칸을 비우면 컴파일이 막는다). 이 가드는
/// 그 처방을 우회하는 길, 즉 코드가 언어를 직접 갈라 보는 길을 닫는다.
///
/// **검사 규칙: 한 파일의 `.ko` 와 `.ja` 등장 횟수가 같아야 한다.** `language == .ko ? ko : en`
/// 만 찾는 문자열 스캔은 같은 부류의 다른 표기를 놓쳤다 — 실제로 두 곳을 흘렸다:
/// `switch (language, phase)` 의 `case (.ko, …)`(FocusTimerView) 와
/// `languageProvider() == .ko ? … : …`(FloatingPetPanel). 세 언어 표는 반드시 `.ko` 와 `.ja` 를
/// 함께 쓰므로 개수 대칭이 곧 "세 갈래인가" 의 대리 지표가 된다.
///
/// 한계: `.ko` 만 필요한 헬퍼(한국어 조사 판정 같은 것)가 짝 없이 늘면 오탐이 난다. 그때는
/// 그 파일을 예외에 넣지 말고 `L` 로 올린다 — 오탐은 빌드를 막고 끝나지만 미탐은 배포된다.
///
/// **주석은 제외한다.** 규칙을 설명하는 주석 자체가 패턴을 담고 있어(이 파일이 그렇다) 제외하지
/// 않으면 가드가 자기 설명에 걸린다.
final class LanguageSplitGuardTests: XCTestCase {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)                 // Tests/PokeTokenBarTests/이 파일
            .deletingLastPathComponent()                // Tests/PokeTokenBarTests
            .deletingLastPathComponent()                // Tests
            .deletingLastPathComponent()                // 저장소 루트
            .appendingPathComponent("Sources")
    }

    /// `.ko` 처럼 **열거형 케이스로 쓰인** 토큰만 센다. 뒤에 글자가 붙으면(`koreanSubject`) 다른 뜻이다.
    private func caseTokenCount(_ token: String, in line: String) -> Int {
        var rest = Substring(line)
        var count = 0
        while let found = rest.range(of: token) {
            let next = rest[found.upperBound...].first
            if next.map({ !($0.isLetter || $0.isNumber || $0 == "_") }) ?? true { count += 1 }
            rest = rest[found.upperBound...]
        }
        return count
    }

    func testNoSourceFileBranchesOnLanguageWithoutJapanese() throws {
        let files = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        // 경로 계산이 깨지면 빈 목록을 훑고 조용히 통과한다 — 그걸 막는 단언.
        XCTAssertGreaterThan(files.count, 10, "소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var offenders: [String] = []
        for file in files {
            var ko = 0, ja = 0
            for line in try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                ko += caseTokenCount(".ko", in: line)
                ja += caseTokenCount(".ja", in: line)
            }
            if ko != ja { offenders.append("\(file.lastPathComponent) (.ko \(ko) · .ja \(ja))") }
        }

        XCTAssertEqual(offenders, [], """
            언어를 두 갈래로만 갈랐다 — 일본어 사용자에게 영어가 나간다. `l.t(ko, en, ja)` 로 바꿔라. \
            위반: \(offenders)
            """)
    }
}
