import Foundation
@testable import PokeTokenBar

// MARK: 스토어 픽스처 격리 (디렉토리 단위) — swift-testing 타깃

/// `CompanionStore` 는 기억 앨범·대화 세이브·진행 중인 웨이브 런을 상태 파일 *옆에* **이름이 고정된**
/// 채로 만든다(`CompanionStorageLocations`). 그러니 상태 파일 이름만 유일하게 하고 공용 temp
/// 디렉토리에 두면 곁방 셋은 모든 픽스처가 하나를 공유한다 — temp 는 실행 사이에도 지워지지 않아
/// `swift test` 를 다시 돌려도 남는다(#232).
///
/// **XCTest 쪽 `storeDirectory` 와 같은 규칙이고, 다른 것은 치우는 방식뿐이다** — swift-testing 에는
/// `addTeardownBlock` 이 없으므로 호출부가 `defer` 로 지운다. 그래서 파일을 나눠 두 타깃이 각자
/// 자기 프레임워크의 자리에서 같은 규칙을 지킨다(SwiftPM 은 소스 하나를 두 타깃에 함께 넣지 못한다).
///
/// 디렉토리를 **미리 만든다**: 픽스처가 스토어보다 먼저 파일을 쓰는 경우(`SaveFailureTests` 는
/// 상태 파일 자리에 디렉토리를 만들어 쓰기를 실패시킨다) 스토어의 `createDirectory` 를 못 기다린다.
func storeFixtureDirectory(_ tag: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("poke-\(tag)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// 갓 판 디렉토리 안의 상태 파일. 디렉토리 자체가 필요한 픽스처만 `storeFixtureDirectory` 를 쓴다.
func storeFixtureStateURL(_ tag: String) -> URL {
    storeFixtureDirectory(tag).appendingPathComponent(CompanionStorageLocations.stateFileName)
}
