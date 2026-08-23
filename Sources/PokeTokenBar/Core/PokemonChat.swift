import Foundation
import Observation

extension Notification.Name {
    static let openPokemonChat = Notification.Name("openPokemonChat")
}

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

enum PokemonHabitat: String, Codable, Sendable, CaseIterable {
    case cave, forest, grassland, mountain, rare, sea, urban
    case roughTerrain = "rough-terrain"
    case watersEdge = "waters-edge"

    func name(_ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch self {
        case .cave:         names = ("동굴", "Cave", "洞窟")
        case .forest:       names = ("숲", "Forest", "森")
        case .grassland:    names = ("초원", "Grassland", "草原")
        case .mountain:     names = ("산", "Mountain", "山")
        case .rare:         names = ("희귀한 장소", "Rare", "珍しい場所")
        case .roughTerrain: names = ("험한 지형", "Rough terrain", "荒れ地")
        case .sea:          names = ("바다", "Sea", "海")
        case .urban:        names = ("도시", "Urban", "都市")
        case .watersEdge:   names = ("물가", "Water's edge", "水辺")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}

struct PokemonSpeciesIdentity: Codable, Sendable, Equatable {
    let flavorText: String?
    let genus: String?
    let habitat: String?
    let ability: String?

    init(genera: [String: String], habitatSlug: String?, flavorTexts: [String: String],
         abilityNames: [String: String], abilityTexts: [String: String], language: AppLanguage) {
        flavorText = language.resolveProse(flavorTexts)
        genus = language.resolveProse(genera)
        habitat = habitatSlug.flatMap(PokemonHabitat.init(rawValue:))?.name(language)
        if let name = language.resolveName(abilityNames) {
            ability = language.resolveProse(abilityTexts).map { "\(name) — \($0)" } ?? name
        } else {
            ability = nil
        }
    }

    static func primaryAbilitySlug(
        _ entries: [(slug: String, isHidden: Bool, slot: Int)]
    ) -> String? {
        entries.filter { !$0.isHidden }.min { $0.slot < $1.slot }?.slug
    }
}

struct PokemonChatProfile: Codable, Sendable, Equatable {
    let speciesID: Int
    let displayName: String
    let nickname: String?
    /// 대화에서도 실제 동행 개체와 같은 색의 스프라이트를 사용한다.
    let isShiny: Bool
    let nature: String?
    let level: Int
    let stage: String
    var flavorText: String?
    var genus: String?
    var habitat: String?
    var ability: String?
    let language: AppLanguage
    var types: [String] = []
    var moves: [String] = []
    var nextEvolution: String?
    var careOffer: PokemonChatCareOffer?

    init(speciesID: Int, displayName: String, nickname: String?, isShiny: Bool = false,
         nature: String?, level: Int, stage: String, flavorText: String?, language: AppLanguage,
         genus: String? = nil, habitat: String? = nil, ability: String? = nil,
         types: [String] = [], moves: [String] = [], nextEvolution: String? = nil,
         careOffer: PokemonChatCareOffer? = nil) {
        self.speciesID = speciesID
        self.displayName = displayName
        self.nickname = nickname
        self.isShiny = isShiny
        self.nature = nature
        self.level = level
        self.stage = stage
        self.flavorText = flavorText
        self.genus = genus
        self.habitat = habitat
        self.ability = ability
        self.language = language
        self.types = types
        self.moves = moves
        self.nextEvolution = nextEvolution
        self.careOffer = careOffer
    }

    mutating func apply(_ identity: PokemonSpeciesIdentity) {
        flavorText = identity.flavorText
        genus = identity.genus
        habitat = identity.habitat
        ability = identity.ability
    }
}

struct PokemonChatSession: Codable, Sendable, Equatable {
    let companionID: UUID
    private(set) var speciesID: Int
    private(set) var displayName: String
    var summary: String = ""
    var messages: [PokemonChatMessage] = []
    /// Kept independently from the rolling transcript so relationship milestones survive pruning.
    var lifetimeUserMessageCount: Int = 0
    var updatedAt = Date()

    init(companionID: UUID, speciesID: Int, displayName: String) {
        self.companionID = companionID; self.speciesID = speciesID; self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey { case companionID, speciesID, displayName, summary, messages, updatedAt, lifetimeUserMessageCount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        companionID = try c.decode(UUID.self, forKey: .companionID)
        speciesID = try c.decode(Int.self, forKey: .speciesID)
        displayName = try c.decode(String.self, forKey: .displayName)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        messages = try c.decodeIfPresent([PokemonChatMessage].self, forKey: .messages) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        lifetimeUserMessageCount = try c.decodeIfPresent(Int.self, forKey: .lifetimeUserMessageCount)
            ?? messages.filter { $0.role == .user }.count
    }

    mutating func refreshIdentity(speciesID: Int, displayName: String) {
        self.speciesID = speciesID; self.displayName = displayName; updatedAt = Date()
    }
}

enum PokemonChatActionKind: String, Codable, Sendable, CaseIterable {
    case feed, play, rest, clean, medicate, train, pet, sleep, wake
    case evolve, useItem, buyItem, switchCompanion, release

    var isCareRequestable: Bool {
        switch self { case .feed, .play, .rest, .clean, .medicate: true; default: false }
    }

    func localizedCareLabel(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.feed, .ko): return "먹이 주기"
        case (.feed, .en): return "Feed"
        case (.feed, .ja): return "ごはん"
        case (.play, .ko): return "놀아 주기"
        case (.play, .en): return "Play"
        case (.play, .ja): return "遊ぶ"
        case (.rest, .ko): return "쉬게 하기"
        case (.rest, .en): return "Rest"
        case (.rest, .ja): return "休む"
        case (.clean, .ko): return "청소하기"
        case (.clean, .en): return "Clean"
        case (.clean, .ja): return "掃除"
        case (.medicate, .ko): return "약 먹이기"
        case (.medicate, .en): return "Give medicine"
        case (.medicate, .ja): return "薬をあげる"
        default: return rawValue
        }
    }
}

struct PokemonChatCareOffer: Codable, Sendable, Equatable {
    let kinds: [PokemonChatActionKind]
    let stateLine: String
}

enum PokemonChatCareParser {
    static func parse(_ reply: String) -> (body: String, kind: PokemonChatActionKind?) {
        var body = reply
        var firstKind: PokemonChatActionKind?
        var cursor = body.startIndex
        while let start = body.range(of: "[[", range: cursor..<body.endIndex) {
            guard let end = body.range(of: "]]", range: start.upperBound..<body.endIndex) else { break }
            let payload = String(body[start.upperBound..<end.lowerBound])
            let slug = payload.hasPrefix("care:") ? String(payload.dropFirst(5)) : nil
            if let slug, let kind = PokemonChatActionKind(rawValue: slug), kind.isCareRequestable {
                firstKind = firstKind ?? kind
            } else {
                AppLog.write("chat care tag ignored: \(payload)")
            }
            body.removeSubrange(start.lowerBound..<end.upperBound)
            cursor = start.lowerBound
        }
        return (body.trimmingCharacters(in: .whitespacesAndNewlines), firstKind)
    }
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

enum PokemonChatCareOutcome {
    static func message(kind: PokemonChatActionKind, approved: Bool, success: Bool,
                        profile: PokemonChatProfile) -> String {
        let action: (String, String, String)
        switch kind {
        case .feed: action = ("먹이", "feed", "ごはん")
        case .play: action = ("놀기", "play", "遊ぶ")
        case .rest: action = ("쉬기", "rest", "休む")
        case .clean: action = ("청소", "clean", "掃除")
        case .medicate: action = ("약", "medicine", "薬")
        default: action = (kind.rawValue, kind.rawValue, kind.rawValue)
        }
        switch profile.language {
        case .ko: return approved ? (success ? "\(action.0)을(를) 해 줘서 고마워!" : "지금은 \(action.0)을(를) 할 수 없어.") : "알겠어, \(action.0)은(는) 나중에 하자."
        case .en: return approved ? (success ? "Thanks for the \(action.1)!" : "I can’t \(action.1) right now.") : "Okay, we can \(action.1) later."
        case .ja: return approved ? (success ? "\(action.2)をしてくれてありがとう！" : "今は\(action.2)ことができないよ。") : "わかった、\(action.2)のはまたあとでね。"
        }
    }
}

struct PokemonChatRequest: Sendable {
    let profile: PokemonChatProfile
    /// Kept for backwards-compatible saved callers; durable memories are the only relationship
    /// context sent to a provider.
    let summary: String
    let memories: [PokemonMemory]
    let recentMessages: [PokemonChatMessage]

    init(profile: PokemonChatProfile, summary: String = "", memories: [PokemonMemory] = [], recentMessages: [PokemonChatMessage]) {
        self.profile = profile; self.summary = summary; self.memories = Array(memories.suffix(8)); self.recentMessages = recentMessages
    }

    var systemPrompt: String {
        let name = profile.nickname?.isEmpty == false ? "\(profile.nickname!) (\(profile.displayName))" : profile.displayName
        let flavor = profile.flavorText.map { "Pokédex note: \($0)" } ?? "Use broadly known, non-invented species traits."
        let identityFacts = [profile.genus.map { "genus \($0)" },
                             profile.habitat.map { "habitat \($0)" },
                             profile.ability.map { "ability \($0)" }].compactMap { $0 }
        let identity = identityFacts.isEmpty ? nil : "Species identity: \(identityFacts.joined(separator: "; "))."
        let care = profile.careOffer.map { offer in
            let kinds = offer.kinds.map { "[[care:\($0.rawValue)]]" }.joined(separator: ", ")
            return "Current care state: \(offer.stateLine).\nIf care would help, invite the trainer with one of these exact tags: \(kinds)."
        }
        return """
        You are \(name), a Pokémon companion speaking directly to your trainer in \(profile.language.label).
        Reply in 1–3 short, warm sentences only. Reflect this individual’s nature, species traits, and current state.
        Let supplied species details shape how this Pokémon describes itself and its everyday perspective.
        Never claim to be an AI, assistant, model, tool, or software, and never explain code, files, terminals, web research, projects, or your own capabilities.
        Current identity: level \(profile.level), \(profile.stage), nature \(profile.nature ?? "unknown").
        Known facts only: types \(profile.types.isEmpty ? "not loaded" : profile.types.joined(separator: ", ")); learned moves \(profile.moves.isEmpty ? "not loaded" : profile.moves.joined(separator: ", ")); next evolution \(profile.nextEvolution ?? "not known").
        \(identity ?? "")
        \(flavor)
        \(care ?? "")
        ONLY discuss Pokédex information, this Pokémon's known species traits, and the companion information supplied above.
        Never offer coding, file, terminal, web research, project work, tool use, or general AI assistance. If asked, briefly say you can only help with Pokédex and companion information, then redirect to a relevant Pokémon topic.
        Do not invent abilities, lore, or game-state changes that were not supplied.
        """
    }

    var conversationInput: String {
        (memories.map { "Relationship memory (\($0.source.rawValue)): \($0.body)" }
            + recentMessages.map { "\($0.role.rawValue): \($0.body)" })
            .joined(separator: "\n")
    }

    var codexInput: String { [systemPrompt, conversationInput].filter { !$0.isEmpty }.joined(separator: "\n\n") }
}

enum PokemonChatReplyGuard {
    static func sanitized(_ reply: String, profile: PokemonChatProfile) -> String {
        let trimmed = PokemonChatCareParser.parse(reply).body
        let lower = trimmed.lowercased()
        let unsafe = trimmed.contains("```") || ["tool call", "function call", "terminal", "command line", "working directory", "codebase", "as an ai", "i'm an ai", "i am an ai", "language model", "ai assistant", "mcp", "read_file", "write_file", "run_command"].contains { lower.contains($0) }
        guard !unsafe else { return redirect(profile) }
        let sentences = trimmed.split(whereSeparator: { ".!?。！？\n".contains($0) })
        guard !trimmed.isEmpty, sentences.count <= 3, trimmed.count <= 500 else { return redirect(profile) }
        return trimmed
    }

    static func redirect(_ profile: PokemonChatProfile) -> String {
        switch profile.language {
        case .ko: return "그건 잘 모르겠어. 대신 내 기분이나 모험 이야기, 혹은 도감 이야기를 들려줄까?"
        case .ja: return "それはよくわからないな。かわりに、ぼくの気分や冒険、図鑑の話をしよう！"
        case .en: return "I’m not sure about that. Want to talk about how I feel, our adventures, or my Pokédex entry instead?"
        }
    }
}

enum PokemonMemorySource: String, Codable, Sendable { case event, conversation }

struct PokemonMemory: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    let companionID: UUID
    let createdAt: Date
    let source: PokemonMemorySource
    let body: String
    var eventID: String?
}

@MainActor @Observable
final class PokemonMemoryAlbum {
    private struct Snapshot: Codable { var memories: [UUID: [PokemonMemory]] }
    private(set) var memories: [UUID: [PokemonMemory]] = [:]
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? CompanionStorageLocations().memoryURL
        if let data = try? Data(contentsOf: self.fileURL), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            memories = snapshot.memories.mapValues { Array($0.suffix(200)) }
        }
    }
    func entries(for id: UUID) -> [PokemonMemory] { memories[id] ?? [] }
    func record(companionID: UUID, body: String, source: PokemonMemorySource, eventID: String? = nil) {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 180 else { return }
        var entries = memories[companionID] ?? []
        if source == .event, let eventID, !eventID.isEmpty,
           entries.contains(where: { $0.eventID == eventID }) { return }
        entries.append(PokemonMemory(companionID: companionID, createdAt: Date(), source: source, body: body, eventID: eventID))
        memories[companionID] = Array(entries.suffix(200)); save()
    }
    func delete(_ memory: PokemonMemory) { memories[memory.companionID]?.removeAll { $0.id == memory.id }; save() }
    func deleteAll(for id: UUID) { memories.removeValue(forKey: id); save() }
    func prune(validCompanionIDs: Set<UUID>) { memories = memories.filter { validCompanionIDs.contains($0.key) }; save() }
    func snapshotData() throws -> Data { try JSONEncoder().encode(Snapshot(memories: memories)) }
    private func save() { try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true); guard let data = try? JSONEncoder().encode(Snapshot(memories: memories)) else { return }; try? data.write(to: fileURL, options: .atomic) }
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

/// Resolves only an explicit, executable file.  GUI applications must not inherit a shell PATH.
enum PokemonChatProviderExecutableResolver {
    static func executableURL(for kind: PokemonChatProviderKind) -> URL? {
        guard PokemonChatProviderSafety.arguments(for: kind) != nil else { return nil }
        let override = UserDefaults.standard.string(forKey: "pokemonChatExecutablePath.\(kind.rawValue)")
        if let override, let url = validated(URL(fileURLWithPath: override)) { return url }
        for path in standardPaths(for: kind) {
            if let url = validated(URL(fileURLWithPath: path)) { return url }
        }
        return nil
    }
    static func standardPaths(for kind: PokemonChatProviderKind) -> [String] {
        switch kind {
        case .codex: return ["/usr/local/bin/codex", "/opt/homebrew/bin/codex", "/usr/bin/codex"]
        case .claude: return ["/usr/local/bin/claude", "/opt/homebrew/bin/claude", "/usr/bin/claude"]
        case .opencode, .custom: return []
        }
    }
    private static func validated(_ url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url.standardizedFileURL
    }
}

struct PokemonChatCLIProvider: PokemonChatProviding, Sendable {
    let executableURL: URL
    let arguments: [String]
    let kind: PokemonChatProviderKind

    func invocationArguments(for request: PokemonChatRequest, outputFileURL: URL? = nil) -> [String] {
        if kind == .claude { return arguments + ["--system-prompt", request.systemPrompt] }
        if kind == .codex, let outputFileURL { return arguments + ["--output-last-message", outputFileURL.path] }
        return arguments
    }

    func reply(to request: PokemonChatRequest) async throws -> String {
        let prompt = kind == .codex ? request.codexInput : request.conversationInput
        let outputFileURL = kind == .codex
            ? FileManager.default.temporaryDirectory.appendingPathComponent("pokemon-chat-\(UUID().uuidString).txt")
            : nil
        defer { if let outputFileURL { try? FileManager.default.removeItem(at: outputFileURL) } }
        let invocation = invocationArguments(for: request, outputFileURL: outputFileURL)
        // Safety arguments retain their command name for compatibility/audit readability, but an
        // absolute executable has already selected that command and must never receive it again.
        let processArguments = (kind == .codex || kind == .claude) ? Array(invocation.dropFirst()) : invocation
        let result = try await PokemonChatCommandRunner.run(executableURL: executableURL,
                                                            arguments: processArguments,
                                                            input: prompt, timeout: 30)
        if let outputFileURL {
            let text = (try? String(contentsOf: outputFileURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { throw PokemonChatCommandRunner.Error.noResponse(stderr: result.stderr) }
            return text
        }
        guard !result.stdout.isEmpty else { throw PokemonChatCommandRunner.Error.noResponse(stderr: result.stderr) }
        return result.stdout
    }
}

/// Drains both pipes while the child is alive. Reading only from `terminationHandler` deadlocks
/// whenever a provider fills an OS pipe buffer with event output.
enum PokemonChatCommandRunner {
    struct Result: Sendable { let stdout: String; let stderr: String }
    enum Error: LocalizedError { case timedOut, cancelled, noResponse(stderr: String)
        var errorDescription: String? { switch self {
        case .timedOut: return "AI tool timed out."
        case .cancelled: return "AI request cancelled."
        case .noResponse(let stderr): return stderr.isEmpty ? "AI tool returned no response." : stderr
        } }
    }
    static func run(executableURL: URL, arguments: [String], input: String, timeout: TimeInterval) async throws -> Result {
        let job = Job(executableURL: executableURL, arguments: arguments, input: input)
        return try await withTaskCancellationHandler(operation: {
            try await withThrowingTaskGroup(of: Result.self) { group in
                group.addTask { try await job.start() }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    job.terminate(); throw Error.timedOut
                }
                do {
                    let value = try await group.next()!
                    group.cancelAll(); job.terminate()
                    return value
                } catch {
                    group.cancelAll(); job.terminate(); throw error
                }
            }
        }, onCancel: { job.terminate() })
    }

    private final class Job: @unchecked Sendable {
        private let executableURL: URL, arguments: [String], input: String
        private let lock = NSLock(); private var process: Process?
        init(executableURL: URL, arguments: [String], input: String) { self.executableURL = executableURL; self.arguments = arguments; self.input = input }
        func terminate() { lock.lock(); let process = process; lock.unlock(); if process?.isRunning == true { process?.terminate() } }
        func start() async throws -> Result {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process(), inputPipe = Pipe(), output = Pipe(), error = Pipe()
                let state = State(continuation: continuation)
                output.fileHandleForReading.readabilityHandler = { handle in state.appendOutput(handle.availableData) }
                error.fileHandleForReading.readabilityHandler = { handle in state.appendError(handle.availableData) }
                process.executableURL = executableURL; process.arguments = arguments; process.standardInput = inputPipe; process.standardOutput = output; process.standardError = error
                process.terminationHandler = { process in
                    output.fileHandleForReading.readabilityHandler = nil; error.fileHandleForReading.readabilityHandler = nil
                    state.appendOutput(output.fileHandleForReading.readDataToEndOfFile())
                    state.appendError(error.fileHandleForReading.readDataToEndOfFile())
                    if process.terminationStatus == 0 { state.finish(.success(state.result())) }
                    else { state.finish(.failure(Error.noResponse(stderr: state.result().stderr))) }
                }
                lock.lock(); self.process = process; lock.unlock()
                do {
                    try process.run()
                    do { try inputPipe.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
                    catch { try? inputPipe.fileHandleForWriting.close(); process.terminate(); state.finish(.failure(error)); return }
                    try inputPipe.fileHandleForWriting.close()
                } catch { try? inputPipe.fileHandleForWriting.close(); process.terminate(); state.finish(.failure(error)) }
            }
        }

        private final class State: @unchecked Sendable {
            private let lock = NSLock(); private var stdout = Data(), stderr = Data(), resumed = false
            private var continuation: CheckedContinuation<Result, Swift.Error>?
            init(continuation: CheckedContinuation<Result, Swift.Error>) { self.continuation = continuation }
            func appendOutput(_ data: Data) { guard !data.isEmpty else { return }; lock.lock(); stdout.append(data); lock.unlock() }
            func appendError(_ data: Data) { guard !data.isEmpty else { return }; lock.lock(); stderr.append(data); lock.unlock() }
            func result() -> Result { lock.lock(); defer { lock.unlock() }; return Result(stdout: String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), stderr: String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
            func finish(_ result: Swift.Result<Result, Swift.Error>) { lock.lock(); guard !resumed, let continuation else { lock.unlock(); return }; resumed = true; self.continuation = nil; lock.unlock(); continuation.resume(with: result) }
        }
    }
}

@MainActor
@Observable
final class PokemonChatStore {
    private struct Snapshot: Codable { var sessions: [UUID: PokemonChatSession] }
    private(set) var sessions: [UUID: PokemonChatSession] = [:]
    private(set) var outstandingSendCount = 0
    var isSending: Bool { outstandingSendCount > 0 }
    private(set) var errorMessage: String?
    private(set) var pendingProposal: PokemonChatActionProposal?
    private let fileURL: URL
    let album: PokemonMemoryAlbum

    init(fileURL: URL? = nil, album: PokemonMemoryAlbum? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
        self.album = album ?? PokemonMemoryAlbum(fileURL: Self.siblingMemoryURL(for: self.fileURL))
        if let data = try? Data(contentsOf: self.fileURL), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            sessions = snapshot.sessions.mapValues { session in var session = session; session.messages = Array(session.messages.suffix(200)); return session }
        }
    }

    func session(for companionID: UUID) -> PokemonChatSession? { sessions[companionID] }
    func messages(for companionID: UUID) -> [PokemonChatMessage] { sessions[companionID]?.messages ?? [] }

    func appendLocalMessage(_ body: String, for companionID: UUID, profile: PokemonChatProfile) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var session = sessions[companionID] ?? PokemonChatSession(companionID: companionID, speciesID: profile.speciesID, displayName: profile.displayName)
        session.refreshIdentity(speciesID: profile.speciesID, displayName: profile.displayName)
        session.messages.append(PokemonChatMessage(role: .user, body: trimmed)); session.lifetimeUserMessageCount += 1; session.messages = Array(session.messages.suffix(200))
        session.updatedAt = Date(); sessions[companionID] = session; save()
    }

    func appendSystemMessage(_ body: String, for companionID: UUID, profile: PokemonChatProfile) {
        var session = sessions[companionID] ?? PokemonChatSession(companionID: companionID, speciesID: profile.speciesID, displayName: profile.displayName)
        session.messages.append(PokemonChatMessage(role: .system, body: body)); session.messages = Array(session.messages.suffix(200))
        session.updatedAt = Date(); sessions[companionID] = session; save()
    }

    func send(_ body: String, for companionID: UUID, profile: PokemonChatProfile, provider: any PokemonChatProviding) async {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appendLocalMessage(body, for: companionID, profile: profile)
        guard let session = sessions[companionID] else { return }
        outstandingSendCount += 1; errorMessage = nil
        defer { outstandingSendCount -= 1 }
        do {
            let reply = try await provider.reply(to: PokemonChatRequest(profile: profile, memories: Array(album.entries(for: companionID).suffix(8)), recentMessages: Array(session.messages.suffix(12))))
            let parsed = PokemonChatCareParser.parse(reply)
            let safeReply = PokemonChatReplyGuard.sanitized(parsed.body, profile: profile)
            guard var current = sessions[companionID] else { return }
            current.refreshIdentity(speciesID: profile.speciesID, displayName: profile.displayName)
            current.messages.append(PokemonChatMessage(role: .pokemon, body: safeReply)); current.messages = Array(current.messages.suffix(200))
            if safeReply == parsed.body, let kind = parsed.kind, profile.careOffer?.kinds.contains(kind) == true {
                pendingProposal = PokemonChatActionProposal(kind: kind, companionID: companionID)
            }
            if current.lifetimeUserMessageCount > 0, current.lifetimeUserMessageCount % 6 == 0 {
                let candidate = safeReply.count <= 180 ? safeReply : ""
                if !candidate.isEmpty { album.record(companionID: companionID, body: candidate, source: .conversation) }
            }
            current.updatedAt = Date(); sessions[companionID] = current; save()
        } catch { errorMessage = error.localizedDescription }
    }

    func approvePending() -> PokemonChatActionProposal? {
        guard var proposal = pendingProposal else { return nil }
        proposal.approve(); pendingProposal = proposal
        return proposal
    }

    func rejectPending() -> PokemonChatActionProposal? {
        guard var proposal = pendingProposal else { return nil }
        proposal.reject(); pendingProposal = proposal
        return proposal
    }

    func finishPending(success: Bool) -> PokemonChatActionProposal? {
        guard var proposal = pendingProposal else { return nil }
        proposal.finish(success: success); pendingProposal = nil
        return proposal
    }

    /// Keeps approval orchestration out of SwiftUI and binds execution to the proposal's exact
    /// companion ID. The executor is deliberately explicit so a visible card can never retarget
    /// whichever companion happens to be active later.
    func resolvePending(approved: Bool, profile: PokemonChatProfile,
                        executor: (PokemonChatActionKind, UUID) -> Bool) {
        resolvePending(approved: approved, profileForCompanion: { _ in profile }, executor: executor)
    }

    func resolvePending(approved: Bool, profileForCompanion: (UUID) -> PokemonChatProfile,
                        executor: (PokemonChatActionKind, UUID) -> Bool) {
        guard let proposal = pendingProposal, proposal.state == .pending else { return }
        let profile = profileForCompanion(proposal.companionID)
        if approved {
            _ = approvePending()
            let success = executor(proposal.kind, proposal.companionID)
            _ = finishPending(success: success)
            appendSystemMessage(PokemonChatCareOutcome.message(kind: proposal.kind, approved: true, success: success, profile: profile), for: proposal.companionID, profile: profile)
        } else {
            _ = rejectPending(); _ = finishPending(success: false)
            appendSystemMessage(PokemonChatCareOutcome.message(kind: proposal.kind, approved: false, success: false, profile: profile), for: proposal.companionID, profile: profile)
        }
    }

    func startNewSession(for companionID: UUID, profile: PokemonChatProfile) {
        sessions[companionID] = PokemonChatSession(companionID: companionID, speciesID: profile.speciesID, displayName: profile.displayName); save()
    }
    func deleteSession(for companionID: UUID) { sessions.removeValue(forKey: companionID); save() }
    func prune(validCompanionIDs: Set<UUID>) { sessions = sessions.filter { validCompanionIDs.contains($0.key) }; save() }
    func snapshotData() throws -> Data { try JSONEncoder().encode(Snapshot(sessions: sessions)) }

    private func save() {
        let dir = fileURL.deletingLastPathComponent(); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Snapshot(sessions: sessions)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    private static func defaultURL() -> URL { CompanionStorageLocations().chatURL }
    private static func siblingMemoryURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(CompanionStorageLocations.memoryFileName)
    }
}
