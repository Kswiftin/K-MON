import Foundation

/// The three durable companion stores deliberately live together.  In particular this makes
/// `PTB_STATE_DIR` a complete, isolated test/demo profile rather than only an isolated save file.
struct CompanionStorageLocations: Sendable {
    static let stateFileName = "companion-state.json"
    static let memoryFileName = "pokemon-memories.json"
    static let chatFileName = "pokemon-chat.json"

    let directory: URL
    var stateURL: URL { directory.appendingPathComponent(Self.stateFileName) }
    var memoryURL: URL { directory.appendingPathComponent(Self.memoryFileName) }
    var chatURL: URL { directory.appendingPathComponent(Self.chatFileName) }

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
