import Foundation

/// The durable companion state lives under one directory.  In particular this makes
/// `PTB_STATE_DIR` a complete, isolated test/demo profile rather than only an isolated save file.
struct CompanionStorageLocations: Sendable {
    static let stateFileName = "companion-state.json"

    let directory: URL
    var stateURL: URL { directory.appendingPathComponent(Self.stateFileName) }

    init(stateURL: URL? = nil) {
        if let stateURL { directory = stateURL.deletingLastPathComponent() }
        else {
            let override = (ProcessInfo.processInfo.environment["PTB_STATE_DIR"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            directory = override.isEmpty
                ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("PokeTokenBar", isDirectory: true)
                : URL(fileURLWithPath: override, isDirectory: true)
        }
    }
}
