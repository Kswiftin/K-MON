// swift-tools-version: 6.0
import Foundation
import PackageDescription

let package = Package(
    name: "PokeTokenBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.5"),
    ],
    targets: [
        .executableTarget(
            name: "PokeTokenBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/PokeTokenBar",
            // 번들 리소스가 없다. Memory Home 아트는 `MemoryHomePixelArtSprites` 의 문자 격자로
            // 실행 파일 안에 들어간다. 빈 `Resources` 를 선언해 두면 새로 클론했을 때 그 디렉터리가
            // 없어 SwiftPM 이 "Invalid Resource" 로 실패한다 — 리소스를 다시 넣을 때 되살릴 것.
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                // build-app.sh embeds Sparkle in Contents/Frameworks. SwiftPM's binary
                // target only adds @loader_path, so add the normal app-bundle lookup path.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        // swift-testing 으로 쓴 테스트. **Xcode 없이도 로컬에서 실행된다** —
        // `Testing.framework` 은 Command Line Tools 에 들어 있고 `XCTest.framework` 만 없기
        // 때문이다. 새 테스트는 되도록 이쪽에 쓴다. 실행은 `scripts/test-local.sh`.
        .testTarget(
            name: "PokeTokenBarLocalTests",
            dependencies: ["PokeTokenBar"],
            path: "Tests/PokeTokenBarLocalTests"
        ),
    ] + xctestTargets
)

/// XCTest 로 쓴 기존 테스트 타깃.
///
/// `PTB_NO_XCTEST=1` 이면 목록에서 뺀다. Xcode 없는 머신에서는 이 타깃이 **컴파일조차 되지 않아**
/// (`no such module 'XCTest'`) 같은 패키지의 swift-testing 타깃까지 못 돌리기 때문이다. CI 는 이
/// 변수를 두지 않으므로 두 타깃이 모두 돈다 — 로컬에서 뺀 것이 검증에서 빠지지 않는다.
var xctestTargets: [Target] {
    if ProcessInfo.processInfo.environment["PTB_NO_XCTEST"] == "1" { return [] }
    return [
        .testTarget(
            name: "PokeTokenBarTests",
            dependencies: ["PokeTokenBar"],
            path: "Tests/PokeTokenBarTests"
        ),
    ]
}
