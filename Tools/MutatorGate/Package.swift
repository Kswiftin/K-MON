// swift-tools-version: 5.9
import PackageDescription

// 인덱스 스토어를 읽는 게이트 도구. **앱 패키지와 분리한다** — `indexstore-db` 를 루트
// Package.swift 에 넣으면 릴리스 빌드(build-app.sh)와 서명 경로까지 새 의존성을 타고,
// 앱을 빌드하는 모든 사람이 게이트 도구를 함께 받는다. `scripts/rogue-sim.sh` 가 같은
// 이유로 시뮬레이터를 앱 타깃 밖에 세운다.
//
// 핀은 **CI 의 툴체인**(Swift 6.1.2, macos-15)에 맞춘다. 로컬은 6.3 이라 더 새 태그도
// 되지만, 6.3 태그의 소스가 6.1.2 에서 컴파일되지 않으면 CI 만 빨강이 된다.
//
// 리비전으로 핀하는 이유: indexstore-db 의 태그는 `swift-6.1.2-RELEASE` 꼴이라 SwiftPM 이
// 버전으로 읽지 못한다(semver 태그가 없다). 아래 SHA 가 그 태그다.
let package = Package(
    name: "MutatorGate",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(
            url: "https://github.com/apple/indexstore-db.git",
            revision: "54212fce1aecb199070808bdb265e7f17e396015" // swift-6.1.2-RELEASE
        ),
    ],
    targets: [
        .executableTarget(
            name: "MutatorGate",
            dependencies: [.product(name: "IndexStoreDB", package: "indexstore-db")],
            path: "Sources"
        ),
    ]
)
