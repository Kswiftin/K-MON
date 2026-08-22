import Foundation
import Observation

enum PokemonChatRole: String, Codable, Sendable { case user, pokemon, system }

struct PokemonChatMessage: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    let role: PokemonChatRole
    let body: String
    let createdAt: Date

    init(id: UUID = UUID(), role: PokemonChatRole, body: String, createdAt: Date = Date()) {
        self.id = id; self.role = role; self.body = body; self.createdAt = createdAt
    }
}

struct PokemonChatProfile: Codable, Sendable, Equatable {
    let speciesID: Int
    let displayName: String
    let nickname: String?
    let nature: String?
    let level: Int
    let stage: String
    var flavorText: String?
    let language: AppLanguage
}

struct PokemonChatSession: Codable, Sendable, Equatable {
    let companionID: UUID
    private(set) var speciesID: Int
    private(set) var displayName: String
    var summary: String = ""
    var messages: [PokemonChatMessage] = []
    var updatedAt = Date()

    init(companionID: UUID, speciesID: Int, displayName: String) {
        self.companionID = companionID; self.speciesID = speciesID; self.displayName = displayName
    }

    mutating func refreshIdentity(speciesID: Int, displayName: String) {
        self.speciesID = speciesID; self.displayName = displayName; updatedAt = Date()
    }
}

enum PokemonChatActionKind: String, Codable, Sendable, CaseIterable {
    case feed, play, rest, clean, medicate, train, pet, sleep, wake
    case evolve, useItem, buyItem, switchCompanion, release
}

enum PokemonChatActionState: String, Codable, Sendable { case pending, approved, rejected, executed, failed }

struct PokemonChatActionProposal: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    let kind: PokemonChatActionKind
    let companionID: UUID
    var detail: String = ""
    private(set) var state: PokemonChatActionState = .pending
    mutating func approve() { guard state == .pending else { return }; state = .approved }
    mutating func reject() { guard state == .pending else { return }; state = .rejected }
    mutating func finish(success: Bool) { guard state == .approved else { return }; state = success ? .executed : .failed }
}

struct PokemonChatRequest: Sendable {
    let profile: PokemonChatProfile
    let summary: String
    let recentMessages: [PokemonChatMessage]

    init(profile: PokemonChatProfile, summary: String, recentMessages: [PokemonChatMessage]) {
        self.profile = profile; self.summary = summary; self.recentMessages = recentMessages
    }

    var systemPrompt: String {
        let name = profile.nickname?.isEmpty == false ? "\(profile.nickname!) (\(profile.displayName))" : profile.displayName
        let flavor = profile.flavorText.map { "Pokédex note: \($0)" } ?? "Use broadly known, non-invented species traits."
        return """
        You are \(name), a Pokémon companion speaking to your trainer in \(profile.language.label).
        Role-play as a warm, concise animation-style companion. Never claim to be an AI or invent canon facts.
        Current identity: level \(profile.level), \(profile.stage), nature \(profile.nature ?? "unknown").
        \(flavor)
        ONLY discuss Pokédex information, this Pokémon's known species traits, and the companion information supplied above.
        Never offer coding, file, terminal, web research, project work, tool use, or general AI assistance. If asked, briefly say you can only help with Pokédex and companion information, then redirect to a relevant Pokémon topic.
        Do not invent abilities, lore, or game-state changes that were not supplied.
        """
    }
}

protocol PokemonChatProviding: Sendable {
    func reply(to request: PokemonChatRequest) async throws -> String
}

enum PokemonChatProviderKind: String, Codable, CaseIterable, Sendable { case codex, claude, opencode, custom }

/// 대화용 CLI는 모델의 응답 품질보다 도구 격리가 우선이다. 검증되지 않은 제공자는 실행하지 않는다.
enum PokemonChatProviderSafety {
    static func arguments(for provider: PokemonChatProviderKind) -> [String]? {
        switch provider {
        case .claude:
            // `--tools ""`는 Claude Code 내장 도구 전체를 제거한다. strict MCP 설정과 빈 설정을 함께
            // 주어 사용자·프로젝트 MCP 구성이 섞이지 않게 한다.
            return ["claude", "--print", "--tools", "", "--safe-mode", "--strict-mcp-config",
                    "--mcp-config", "{\"mcpServers\":{}}", "--no-session-persistence",
                    "--disable-slash-commands", "--permission-mode", "dontAsk"]
        case .codex:
            // Codex CLI에는 이 버전에서 tool-free 플래그가 없다. MCP·사용자 설정·규칙을 배제하고,
            // 남는 내장 실행 기능은 읽기 전용 샌드박스로 제한한다. 따라서 파일 수정은 불가능하다.
            return ["codex", "exec", "--skip-git-repo-check", "--sandbox", "read-only",
                    "--ephemeral", "--ignore-user-config", "--ignore-rules", "--config", "mcp_servers={}"]
        case .opencode, .custom:
            // OpenCode/임의 CLI는 앱이 보장 가능한 무도구 실행 계약이 확인되기 전까지 실행 금지.
            return nil
        }
    }
}

struct PokemonChatCLIProvider: PokemonChatProviding, Sendable {
    let executableURL: URL
    let arguments: [String]

    func reply(to request: PokemonChatRequest) async throws -> String {
        let prompt = ([request.systemPrompt, request.summary.isEmpty ? nil : "Conversation summary: \(request.summary)"]
            .compactMap { $0 } + request.recentMessages.map { "\($0.role.rawValue): \($0.body)" })
            .joined(separator: "\n")
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let input = Pipe(), output = Pipe(), error = Pipe()
            process.executableURL = executableURL; process.arguments = arguments
            process.standardInput = input; process.standardOutput = output; process.standardError = error
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let stderr = error.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0, !text.isEmpty { continuation.resume(returning: text) }
                else { continuation.resume(throwing: NSError(domain: "PokemonChat", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(decoding: stderr, as: UTF8.self).isEmpty ? "AI tool returned no response." : String(decoding: stderr, as: UTF8.self)])) }
            }
            do {
                try process.run()
                input.fileHandleForWriting.write(Data(prompt.utf8))
                try? input.fileHandleForWriting.close()
            } catch { continuation.resume(throwing: error) }
        }
    }
}

@MainActor
@Observable
final class PokemonChatStore {
    private struct Snapshot: Codable { var sessions: [UUID: PokemonChatSession] }
    private(set) var sessions: [UUID: PokemonChatSession] = [:]
    private(set) var isSending = false
    private(set) var errorMessage: String?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
        if let data = try? Data(contentsOf: self.fileURL), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) { sessions = snapshot.sessions }
    }

    func session(for companionID: UUID) -> PokemonChatSession? { sessions[companionID] }
    func messages(for companionID: UUID) -> [PokemonChatMessage] { sessions[companionID]?.messages ?? [] }

    func appendLocalMessage(_ body: String, for companionID: UUID, profile: PokemonChatProfile) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var session = sessions[companionID] ?? PokemonChatSession(companionID: companionID, speciesID: profile.speciesID, displayName: profile.displayName)
        session.refreshIdentity(speciesID: profile.speciesID, displayName: profile.displayName)
        session.messages.append(PokemonChatMessage(role: .user, body: trimmed))
        session.updatedAt = Date(); sessions[companionID] = session; save()
    }

    func send(_ body: String, for companionID: UUID, profile: PokemonChatProfile, provider: any PokemonChatProviding) async {
        appendLocalMessage(body, for: companionID, profile: profile)
        guard var session = sessions[companionID] else { return }
        isSending = true; errorMessage = nil
        defer { isSending = false }
        do {
            let reply = try await provider.reply(to: PokemonChatRequest(profile: profile, summary: session.summary, recentMessages: Array(session.messages.suffix(12))))
            session.messages.append(PokemonChatMessage(role: .pokemon, body: reply))
            session.updatedAt = Date(); sessions[companionID] = session; save()
        } catch { errorMessage = error.localizedDescription }
    }

    func startNewSession(for companionID: UUID, profile: PokemonChatProfile) {
        sessions[companionID] = PokemonChatSession(companionID: companionID, speciesID: profile.speciesID, displayName: profile.displayName); save()
    }
    func deleteSession(for companionID: UUID) { sessions.removeValue(forKey: companionID); save() }

    private func save() {
        let dir = fileURL.deletingLastPathComponent(); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Snapshot(sessions: sessions)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    private static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar", isDirectory: true).appendingPathComponent("pokemon-chat.json")
    }
}
