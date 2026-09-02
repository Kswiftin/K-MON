import XCTest
@testable import PokeTokenBar

/// macOS 는 `NSBonjourServices` 에 적힌 서비스 타입만 브라우징/광고하게 한다. 목록에 없는 타입은
/// 에러 없이 **결과가 영영 0건**이라, 앱은 정상으로 보이고 화면만 텅 빈다.
///
/// 실제로 경매장(`_kmonauct._tcp`)이 이 목록 없이 배포돼 다른 트레이너의 출품이 아무에게도 보이지
/// 않았다. LAN 센터를 새로 만들 때마다 사람이 빌드 스크립트를 같이 고쳐야 하는 부류라 소스 스캔으로
/// 막는다 — 코드에 선언된 서비스 타입은 전부 plist 에 있어야 한다.
final class BonjourServiceDeclarationTests: XCTestCase {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // Tests/PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // 저장소 루트
    }

    func testEveryServiceTypeInSourcesIsDeclaredInTheAppPlist() throws {
        let sources = FileManager.default
            .enumerator(at: repositoryRoot.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        // 경로가 깨지면 빈 목록을 훑고 조용히 통과한다 — 그걸 막는 단언.
        XCTAssertGreaterThan(sources.count, 10, "소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var declaredTypes: Set<String> = []
        for file in sources {
            let code = try String(contentsOf: file, encoding: .utf8)
            for line in code.components(separatedBy: .newlines) where line.contains("serviceType") {
                guard let start = line.range(of: "\"_"), let end = line.range(of: "._tcp\"") else { continue }
                declaredTypes.insert(String(line[start.lowerBound..<end.upperBound]).replacingOccurrences(of: "\"", with: ""))
            }
        }
        // 다섯 LAN 센터(배틀·방·교환·메모리홈·경매)가 있다 — 스캔이 헛돌면 여기서 걸린다.
        XCTAssertGreaterThanOrEqual(declaredTypes.count, 5, "서비스 타입 스캔이 아무것도 못 찾았다")

        let script = try String(contentsOf: repositoryRoot.appendingPathComponent("scripts/build-app.sh"),
                                encoding: .utf8)
        let missing = declaredTypes.filter { !script.contains("<string>\($0)</string>") }.sorted()
        XCTAssertEqual(missing, [], """
            코드가 쓰는 Bonjour 서비스 타입이 build-app.sh 의 NSBonjourServices 에 없다 — \
            목록에 없는 타입은 브라우징 결과가 영영 0건이라 화면만 비고 에러는 안 난다.
            """)
    }
}
