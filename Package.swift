// swift-tools-version: 6.0
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
        .testTarget(
            name: "PokeTokenBarTests",
            dependencies: ["PokeTokenBar"],
            path: "Tests/PokeTokenBarTests"
        ),
    ]
)
