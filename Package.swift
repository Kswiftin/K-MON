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
