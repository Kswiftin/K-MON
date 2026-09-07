import XCTest
@testable import PokeTokenBar

/// 화면에 나가는 재화 이름은 **한 벌**이어야 한다.
///
/// 같은 재화를 앱이 세 이름으로 불렀다. 한국어는 `별의조각` 12곳 · `별의모래` 3곳, 일본어는
/// `ほしのかけら` 11곳 · `ほしのすな` 1곳 · `累計トークン`(누적 토큰) 1곳, 영어는 `Star Pieces`
/// 11곳 · `Stardust` 4곳. 세이브 내보내기 설명 한 줄 안에서 세 언어가 서로 다른 재화를 말하는
/// 상태였다 — 그걸 읽은 사용자는 자기 지갑에 있는 것과 다른 무엇이 저장된다고 읽는다.
///
/// 왜 안 걸렸나: `L.t(ko, en, ja)` 는 세 칸이 **채워졌는지**만 강제한다. 세 칸이 서로 같은 것을
/// 가리키는지는 문법이 볼 수 없고, 화면별 테스트도 자기 문구 한 줄만 본다. 그래서 전수로 본다.
///
/// 코드 식별자는 규칙 밖이다 — `StardustPayout` · `totalStardust` · `OfferKind.stardust` 는
/// 타입 이름이라 그대로 둔다. 검사는 **낱말로 선 `Stardust`** 만 본다.
final class TerminologyGuardTests: XCTestCase {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)                 // Tests/PokeTokenBarTests/이 파일
            .deletingLastPathComponent()                // Tests/PokeTokenBarTests
            .deletingLastPathComponent()                // Tests
            .deletingLastPathComponent()                // 저장소 루트
            .appendingPathComponent("Sources")
    }

    /// 앞뒤가 글자·숫자가 아닌, 낱말로 선 토큰만 센다(`totalStardust` 는 앞이 글자라 아니다).
    private func standsAlone(_ token: String, in line: String) -> Bool {
        var rest = Substring(line)
        while let found = rest.range(of: token) {
            let before = rest[..<found.lowerBound].last
            let after = rest[found.upperBound...].first
            let boundedBefore = before.map { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") } ?? true
            let boundedAfter = after.map { !($0.isLetter || $0.isNumber || $0 == "_") } ?? true
            if boundedBefore && boundedAfter { return true }
            rest = rest[found.upperBound...]
        }
        return false
    }

    func testTheCurrencyHasOneNamePerLanguage() throws {
        /// 버려진 이름과 그것을 대신할 정본.
        let retired = [("별의모래", "별의조각"), ("ほしのすな", "ほしのかけら"),
                       ("累計トークン", "ほしのかけら"), ("Stardust", "Star Pieces")]
        let files = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        // 경로가 깨지면 빈 목록을 훑고 조용히 통과한다 — 그걸 막는 단언.
        XCTAssertGreaterThan(files.count, 10, "소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var offenders: [String] = []
        for file in files {
            for (index, line) in try String(contentsOf: file, encoding: .utf8)
                .components(separatedBy: .newlines).enumerated() {
                for (old, canonical) in retired where standsAlone(old, in: line) {
                    offenders.append("\(file.lastPathComponent):\(index + 1) \(old) → \(canonical)")
                }
            }
        }
        XCTAssertEqual(offenders, [], "재화 이름이 갈렸다: \(offenders)")
    }
}
