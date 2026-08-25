import Foundation

/// The durable companion state lives under one directory.  In particular this makes
/// `PTB_STATE_DIR` a complete, isolated test/demo profile rather than only an isolated save file.
///
/// Retired features can leave files behind here (`pokemon-memories.json`, `pokemon-chat.json`,
/// `pokemon-*.pre-import-*`): nothing reads or removes them any more.  They are inert, so we keep
/// them rather than deleting user data on their behalf -- but the directory is not guaranteed to
/// hold only files this build knows about.
struct CompanionStorageLocations: Sendable {
    static let stateFileName = "companion-state.json"

    let directory: URL
    var stateURL: URL { directory.appendingPathComponent(Self.stateFileName) }

    /// 기본은 Application Support/PokeTokenBar. `PTB_STATE_DIR` 가 있으면 그 디렉토리를 쓴다 —
    /// 개발/QA 격리용(실제 companion 상태를 건드리지 않고 데모 상태로 실행). 프로덕션은 무영향.
    /// 공백만 있는 값은 무시한다(`URL(fileURLWithPath:)` 가 CWD 상대경로로 해석되는 것 방지).
    init() {
        let override = (ProcessInfo.processInfo.environment["PTB_STATE_DIR"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        directory = override.isEmpty
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PokeTokenBar", isDirectory: true)
            : URL(fileURLWithPath: override, isDirectory: true)
    }
}
