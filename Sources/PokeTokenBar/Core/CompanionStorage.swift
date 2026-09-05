import Foundation

/// The three durable companion stores deliberately live together.  In particular this makes
/// `PTB_STATE_DIR` a complete, isolated test/demo profile rather than only an isolated save file.
struct CompanionStorageLocations: Sendable {
    static let stateFileName = "companion-state.json"
    static let memoryFileName = "pokemon-memories.json"
    static let chatFileName = "pokemon-chat.json"
    /// 진행 중인 웨이브 런. **세이브 본체와 다른 파일이다** — 런은 재화도 도감도 주지 않으므로
    /// 무결성 서명·세이브 이전(migration) 경로에 닿지 않는다는 결정을 그대로 지킨다.
    static let waveRunFileName = "wave-run.json"
    /// 마친 집중 세션 기록. 웨이브 런과 같은 이유로 **세이브 본체와 다른 파일이다** — 세션 기록은
    /// 재화도 도감도 주지 않는 자기 계측 데이터라 무결성 서명·세이브 이전 경로에 닿지 않는다.
    /// 대신 이 디렉토리 안에 있으므로 `PTB_STATE_DIR` 프로필 격리는 그대로 받는다.
    static let focusSessionsFileName = "focus-sessions.json"

    let directory: URL
    var stateURL: URL { directory.appendingPathComponent(Self.stateFileName) }
    var memoryURL: URL { directory.appendingPathComponent(Self.memoryFileName) }
    var chatURL: URL { directory.appendingPathComponent(Self.chatFileName) }
    var waveRunURL: URL { directory.appendingPathComponent(Self.waveRunFileName) }
    var focusSessionsURL: URL { directory.appendingPathComponent(Self.focusSessionsFileName) }

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
