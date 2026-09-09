import Foundation
import Testing

/// 포코피아 화면 문구에서 **보간된 이름 바로 뒤에 조사를 붙이지 않는다.**
///
/// 지형 이름은 받침이 갈린다 — 풀밭·흙·물·길·꽃밭은 있고 모래·나무·바위는 없다. `"\(name)이에요"` 로
/// 적으면 여덟 중 셋이 "모래이에요"·"모래을" 이 된다. 포켓몬 이름도 같다(피카츄 vs 파이리).
/// 설계 문서의 처방은 이름과 조사 사이에 받침이 정해진 명사를 끼우는 것이다 — "…타입을",
/// "…지형이에요". 그 규칙이 타입 이름에만 적용되고 지형 이름엔 빠져 있던 것을 리뷰가 잡았다.
///
/// 렌더링으로는 볼 수 없어 소스를 읽는다(`NestedScrollGuardTests` 와 같은 방식).
///
/// **범위가 포코피아 파일뿐인 이유**: 같은 패턴이 `Localization`·`MemoryHomeRoomLife`·
/// `PokemonAuction`·`PokemonTrade` 에 이미 있다(2026-09-09 리뷰 M4). 저장소 전체로 넓히면
/// 오늘 main 이 빨개진다 — 그쪽을 고친 뒤 접두어를 지워 넓힌다.
@Suite struct PokopiaParticleGuardTests {

    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // Tests/PokeTokenBarLocalTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // 저장소 루트
            .appendingPathComponent("Sources/PokeTokenBar")
    }

    /// `\(…)` 바로 뒤에 오는 한 글자 조사와 `이에요`. `을 수`(…할 수) 같은 우연한 일치를 막기 위해
    /// 조사 뒤에 공백·마침표·따옴표 중 하나가 와야 한다.
    private static let offending = try! NSRegularExpression(
        pattern: #"\\\([^)]{1,60}\)(이에요|예요|을|를|이|가|은|는|와|과)(?=[ .,!?"])"#)

    private static func offendingLines() throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: sourcesDirectory,
                                                              includingPropertiesForKeys: nil)
        else { return [] }
        var found: [String] = []
        for case let url as URL in enumerator
        where url.pathExtension == "swift" && url.lastPathComponent.hasPrefix("Pokopia") {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
                // 주석은 규칙을 설명하느라 위반 예시를 적는다 — 그 줄은 세지 않는다.
                let code = line.components(separatedBy: "//").first ?? line
                let range = NSRange(code.startIndex..., in: code)
                if offending.firstMatch(in: code, range: range) != nil {
                    found.append("\(url.lastPathComponent):\(offset + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        return found
    }

    @Test func noParticleIsGluedToAnInterpolatedName() throws {
        let offenders = try Self.offendingLines()
        #expect(offenders.isEmpty,
                "보간된 이름 뒤에 조사가 붙었다 — 받침 없는 이름에서 틀린다:\n\(offenders.joined(separator: "\n"))")
    }

    /// 정규식이 실제로 잡는지 한 번 확인한다. 위 테스트만 있으면 정규식이 아무것도 못 잡아도
    /// 초록이라, 가드가 일하는지와 일하지 않는지를 구별할 수 없다.
    @Test func theGuardCatchesTheShapeItIsMeantToCatch() {
        let bad = [#"feedback = "이미 \(brush.name)이에요.""#,
                   #"map { "\($0.name)을 밀 수 있어요" }"#]
        let good = [#"feedback = "이미 \(brush.name) 지형이에요.""#,
                    #""\(habitat.types.map(\.name).joined(separator: "·")) 타입을 부르는 중""#,
                    #""\(name) 물가에서 몸을 말리고 있어요.""#]
        for line in bad {
            #expect(Self.offending.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil,
                    "잡아야 하는 줄을 놓쳤다: \(line)")
        }
        for line in good {
            #expect(Self.offending.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil,
                    "맞는 줄을 잡았다: \(line)")
        }
    }
}
