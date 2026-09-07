import XCTest
@testable import PokeTokenBar

/// 읽는 글자는 10pt 아래로 내려가지 않는다.
///
/// 앱은 화면마다 `.font(.system(size: 7))` ~ `size: 9` 를 직접 박아 썼고, 그렇게 쓴 자리가
/// 104곳이었다 — 종 이름 · 스탯 값 · 도감 번호 · 전투 로그처럼 **읽어야 하는** 글자까지 macOS 의
/// 가장 작은 텍스트 스타일(`caption2` = 10pt) 아래였다.
///
/// 이 앱에서는 사용자가 그걸 키울 방법이 없다. macOS 에는 Dynamic Type 이 없어
/// `dynamicTypeSize` 를 `.accessibility5` 로 올려도 `.caption2` 조차 그대로이고(실측), 접근성
/// 텍스트 크기는 `com.apple.universalaccess` 의 `FontSizeCategory` 에 등록된 앱에만 걸린다.
/// 그래서 우리가 적은 pt 가 곧 사용자가 보는 크기다.
///
/// 왜 안 걸렸나: 폰트 크기는 어느 기능 요구사항에도 없고, 화면 테스트는 글자가 몇 pt 든 값만
/// 맞으면 통과한다. 게다가 처음 이 부류를 "Dynamic Type 미지원" 으로 적어 뒀는데, macOS 에서는
/// 일어날 수 없는 시나리오라 고칠 근거가 못 됐다 — 실측으로 전제를 확인한 뒤에야 진짜 결함
/// (절대 크기가 작다)이 남았다.
///
/// 규칙 밖: 배지 · 글리프. 캡슐 배지는 자리가 고정폭이고(체육관 타입 캡슐 42pt) 글리프는 pt 가
/// 글자 크기가 아니라 그림 크기다. 둘은 `PokedoroTheme.badgeFont` · `glyphFont` 로만 쓴다 —
/// 이름이 곧 "읽는 글자가 아니다" 라는 선언이라, 다음 사람이 읽는 글자를 그 이름으로 숨기려면
/// 일부러 거짓말을 해야 한다. **가드는 거짓말을 못 잡는다** — 잡는 것은 아무 생각 없이 박는 것이다.
final class MinimumTextSizeGuardTests: XCTestCase {

    func testNoScreenHardcodesTextBelowTheMinimumSize() throws {
        let files = SwiftSourceScan.files(under: "UI", from: #filePath)
        // 경로가 깨지면 빈 목록을 훑고 조용히 통과한다 — 그걸 막는 단언.
        XCTAssertGreaterThan(files.count, 10, "UI 소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated()
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for size in Self.rawSystemFontSizes(in: line)
                where size < Int(PokedoroTheme.minimumTextSize) {
                    offenders.append("\(file.lastPathComponent):\(index + 1) (\(size)pt)")
                }
            }
        }
        XCTAssertEqual(offenders, [], """
            10pt 미달 폰트를 직접 박은 자리 \(offenders.count)곳: \(offenders)
            읽는 글자면 \(Int(PokedoroTheme.minimumTextSize))pt 이상으로, 배지 · 글리프면
            PokedoroTheme.badgeFont / glyphFont 로 쓴다.
            """)
    }

    /// 자동 축소도 같은 하한을 받는다.
    ///
    /// `minimumScaleFactor` 는 글자가 칸을 넘칠 때만 작동하지만, 작동하는 순간 폰트에 적힌 pt 는
    /// 의미가 없어진다 — 10pt 이름에 0.7 을 걸어 두면 긴 이름(일본어 종 이름이 특히 길다)에서
    /// 7pt 로 줄어들어 위 가드를 통과한 채 하한이 무너진다. 부류 스윕에서 7곳이 그랬다.
    ///
    /// 0.9 까지 허용하는 이유: 축소를 아예 막으면 그 자리는 `…` 로 잘린다(도감 격자 칸은 44pt 라
    /// 이름 대부분이 사라진다). 잘림보다는 9pt 가 낫다고 보고 **한 단계만** 열어 둔다.
    func testAutomaticShrinkingDoesNotUndercutTheMinimum() throws {
        let files = SwiftSourceScan.files(under: "UI", from: #filePath)
        XCTAssertGreaterThan(files.count, 10, "UI 소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated()
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                guard let range = line.range(of: "minimumScaleFactor(") else { continue }
                let value = Double(line[range.upperBound...].prefix { $0.isNumber || $0 == "." }) ?? 0
                if value < Self.smallestAllowedShrink {
                    offenders.append("\(file.lastPathComponent):\(index + 1) (\(value))")
                }
            }
        }
        XCTAssertEqual(offenders, [], """
            10pt 글자를 \(Self.smallestAllowedShrink) 밑으로 줄이는 자리 \(offenders.count)곳: \(offenders)
            더 줄이는 대신 칸을 넓히거나 lineLimit 으로 자른다.
            """)
    }

    /// 10pt 하한에서 한 단계(9pt)까지만 허용한다.
    private static let smallestAllowedShrink = 0.9

    /// `.system(size: 8` 처럼 **숫자를 직접 적은** 자리의 pt 값. `badgeFont` · `glyphFont` 는
    /// 크기를 인자로 받아 `.system(size: size` 로 넘기므로 숫자가 없어 여기 걸리지 않는다.
    private static func rawSystemFontSizes(in line: String) -> [Int] {
        let marker = ".system(size: "
        var sizes: [Int] = []
        var rest = Substring(line)
        while let start = rest.range(of: marker) {
            rest = rest[start.upperBound...]
            let digits = rest.prefix { $0.isNumber }
            if !digits.isEmpty, let value = Int(digits) { sizes.append(value) }
        }
        return sizes
    }
}
