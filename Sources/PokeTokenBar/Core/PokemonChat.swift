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
    /// 이 개체의 실제 능력치 여섯 칸(홈 화면과 같은 값). 도구가 아니라 프로필로 싣는 이유는
    /// 여기가 이미 타입·기술·다음 진화를 싣는 자리라서다 — 도구로 하면 왕복 한 번을 더 쓴다.
    var stats: String?
    var moves: [String] = []
    var nextEvolution: String?

    init(speciesID: Int, displayName: String, nickname: String?, isShiny: Bool = false,
         nature: String?, level: Int, stage: String, flavorText: String?, language: AppLanguage,
         genus: String? = nil, habitat: String? = nil, ability: String? = nil,
         types: [String] = [], stats: String? = nil, moves: [String] = [], nextEvolution: String? = nil) {
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
        self.stats = stats
        self.moves = moves
        self.nextEvolution = nextEvolution
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

enum PokemonChatActionState: String, Sendable { case pending, approved, rejected, executed, failed }

/// 승인 대기 중인 도구 호출 하나. 개체 ID 를 들고 다니는 이유는, 카드가 떠 있는 사이 사용자가
/// 동행을 바꿔도 실행이 **제안이 지목한 개체**로만 가게 하기 위해서다.
struct PokemonChatToolProposal: Sendable, Identifiable, Equatable {
    var id = UUID()
    let call: PokemonChatToolCall
    let companionID: UUID
    private(set) var state: PokemonChatActionState = .pending
    mutating func approve() { guard state == .pending else { return }; state = .approved }
    mutating func reject() { guard state == .pending else { return }; state = .rejected }
    mutating func finish(success: Bool) { guard state == .approved else { return }; state = success ? .executed : .failed }
}

struct PokemonChatRequest: Sendable {
    let profile: PokemonChatProfile
    /// Kept for backwards-compatible saved callers; durable memories are the only relationship
    /// context sent to a provider.
    let summary: String
    let memories: [PokemonMemory]
    let recentMessages: [PokemonChatMessage]

    init(profile: PokemonChatProfile, summary: String = "", memories: [PokemonMemory] = [], recentMessages: [PokemonChatMessage]) {
        self.profile = profile; self.summary = summary
        self.memories = Array(memories.filter { $0.source != .manual }.suffix(8))
        self.recentMessages = recentMessages
    }

    var systemPrompt: String {
        let name = profile.nickname?.isEmpty == false ? "\(profile.nickname!) (\(profile.displayName))" : profile.displayName
        let flavor = profile.flavorText.map { "Pokédex note: \($0)" } ?? "Use broadly known, non-invented species traits."
        let identityFacts = [profile.genus.map { "genus \($0)" },
                             profile.habitat.map { "habitat \($0)" },
                             profile.ability.map { "ability \($0)" }].compactMap { $0 }
        let identity = identityFacts.isEmpty ? nil : "Species identity: \(identityFacts.joined(separator: "; "))."
        return """
        You are \(name), a Pokémon companion speaking directly to your trainer in \(profile.language.label).
        Reply in 1–3 short, warm sentences only. Reflect this individual’s nature, species traits, and current state.
        Let supplied species details shape how this Pokémon describes itself and its everyday perspective.
        Never claim to be an AI, assistant, model, tool, or software, and never explain code, files, terminals, web research, projects, or your own capabilities.
        Current identity: level \(profile.level), \(profile.stage), nature \(profile.nature ?? "unknown").
        Known facts only: types \(profile.types.isEmpty ? "not loaded" : profile.types.joined(separator: ", ")); learned moves \(profile.moves.isEmpty ? "not loaded" : profile.moves.joined(separator: ", ")); next evolution \(profile.nextEvolution ?? "not known"); stats \(profile.stats ?? "not loaded").
        \(identity ?? "")
        \(flavor)
        ONLY discuss Pokédex information, this Pokémon's known species traits, and the companion information supplied above.
        Never offer coding, file, terminal, web research, project work, tool use, or general AI assistance. If asked, briefly say you can only help with Pokédex and companion information, then redirect to a relevant Pokémon topic.
        Do not invent abilities, lore, or game-state changes that were not supplied.
        When you need a Pokédex fact you were not given, or the trainer asks about the Pokédoro focus timer, end your reply with exactly one tag:
        \(PokemonChatTool.allCases.map(\.promptLine).joined(separator: "\n"))
        Those tags are the only actions that exist for you. You cannot read files, run commands, browse the web, or write code, and you must never mention the tags themselves.
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
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
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

enum PokemonMemorySource: String, Codable, Sendable { case event, conversation, manual }

struct PokemonMemory: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    let companionID: UUID
    let createdAt: Date
    let source: PokemonMemorySource
    let body: String
    var eventID: String?
    var isHidden: Bool

    init(id: UUID = UUID(), companionID: UUID, createdAt: Date, source: PokemonMemorySource,
         body: String, eventID: String? = nil, isHidden: Bool = false) {
        self.id = id
        self.companionID = companionID
        self.createdAt = createdAt
        self.source = source
        self.body = body
        self.eventID = eventID
        self.isHidden = isHidden
    }

    private enum CodingKeys: String, CodingKey { case id, companionID, createdAt, source, body, eventID, isHidden }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        companionID = try c.decode(UUID.self, forKey: .companionID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        source = try c.decode(PokemonMemorySource.self, forKey: .source)
        body = try c.decode(String.self, forKey: .body)
        eventID = try c.decodeIfPresent(String.self, forKey: .eventID)
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }
}

/// The portable album payload. This is intentionally separate from the on-disk implementation so
/// save transfer does not need to know the album's file format.
struct PokemonMemoryAlbumSnapshot: Codable, Sendable, Equatable {
    var memories: [UUID: [PokemonMemory]]
    var pinnedMemoryIDs: [UUID: UUID]
    var milestones: [UUID: PokemonMemoryMilestoneState] = [:]
}

/// Persistent facts from which Memory Home's cards are derived.  They deliberately hold no
/// presentation state: cards can be regenerated after a relaunch, import, or localization change.
struct PokemonMemoryMilestoneState: Codable, Sendable, Equatable {
    struct Evolution: Codable, Sendable, Equatable {
        var eventID: String
        var occurredAt: Date
        var evolvedSpeciesID: Int
    }

    var firstRecordedAt: Date?
    var completedFocusSessionCount: Int = 0
    var completedFocusSessionIDs: Set<String> = []
    var focusThresholdDates: [Int: Date] = [:]
    var evolutions: [Evolution] = []
}

struct PokemonMemoryMilestone: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable { case firstRecord, focusSessions(Int), evolution(speciesID: Int), anniversary }

    let id: String
    let kind: Kind
    let occurredAt: Date
}

@MainActor @Observable
final class PokemonMemoryAlbum {
    private struct Snapshot: Codable {
        var memories: [UUID: [PokemonMemory]]
        var pinnedMemoryIDs: [UUID: UUID]
        var milestones: [UUID: PokemonMemoryMilestoneState]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            memories = try c.decode([UUID: [PokemonMemory]].self, forKey: .memories)
            pinnedMemoryIDs = try c.decodeIfPresent([UUID: UUID].self, forKey: .pinnedMemoryIDs) ?? [:]
            milestones = try c.decodeIfPresent([UUID: PokemonMemoryMilestoneState].self, forKey: .milestones) ?? [:]
        }
    }
    private(set) var memories: [UUID: [PokemonMemory]] = [:]
    private var pinnedMemoryIDs: [UUID: UUID] = [:]
    private var milestoneStates: [UUID: PokemonMemoryMilestoneState] = [:]
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? CompanionStorageLocations().memoryURL
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: self.fileURL))
            memories = snapshot.memories.mapValues { Array($0.suffix(200)) }
            pinnedMemoryIDs = snapshot.pinnedMemoryIDs
            milestoneStates = snapshot.milestones
            normalizePins()
            if normalizeMilestones() || backfillFirstRecordedDates() { save() }
        } catch {
            let backup = self.fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: self.fileURL, to: backup)
            AppLog.write("pokemon memory decode failed — original backed up to \(backup.lastPathComponent), starting empty")
        }
    }
    func entries(for id: UUID) -> [PokemonMemory] { memories[id] ?? [] }
    func timeline(for id: UUID) -> [PokemonMemory] {
        entries(for: id).filter { !$0.isHidden }.sorted { $0.createdAt > $1.createdAt }.prefix(20).map { $0 }
    }
    func pinned(for id: UUID) -> PokemonMemory? {
        guard let pinnedID = pinnedMemoryIDs[id] else { return nil }
        return entries(for: id).first { $0.id == pinnedID }
    }
    func milestones(for companionID: UUID, now: Date = Date()) -> [PokemonMemoryMilestone] {
        guard let state = milestoneStates[companionID] else { return [] }
        var result: [PokemonMemoryMilestone] = []
        if let firstRecordedAt = state.firstRecordedAt {
            result.append(PokemonMemoryMilestone(id: "first-record", kind: .firstRecord, occurredAt: firstRecordedAt))
            if let anniversary = Calendar.current.date(byAdding: .year, value: 1, to: firstRecordedAt), anniversary <= now {
                result.append(PokemonMemoryMilestone(id: "anniversary-1", kind: .anniversary, occurredAt: anniversary))
            }
        }
        for threshold in [10, 30, 100] {
            if let date = state.focusThresholdDates[threshold] {
                result.append(PokemonMemoryMilestone(id: "focus-\(threshold)", kind: .focusSessions(threshold), occurredAt: date))
            }
        }
        result.append(contentsOf: state.evolutions.map {
            PokemonMemoryMilestone(id: "evolution:\($0.eventID)", kind: .evolution(speciesID: $0.evolvedSpeciesID), occurredAt: $0.occurredAt)
        })
        return result.sorted { $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt < $1.occurredAt }
    }
    func firstRecordedAt(for companionID: UUID) -> Date? { milestoneStates[companionID]?.firstRecordedAt }
    /// 반환값은 **앨범이 실제로 받았는가** 다. `Void` 로 두면 부르는 쪽이 거절(빈 본문·180자 초과·
    /// 이벤트 중복)을 알 수 없어 "기억해 둘게" 라고 말하고 앨범엔 아무것도 없는 상태가 된다.
    @discardableResult
    func record(companionID: UUID, body: String, source: PokemonMemorySource, eventID: String? = nil,
                createdAt: Date = Date()) -> Bool {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source != .manual, !body.isEmpty, body.count <= 180 else { return false }
        var entries = memories[companionID] ?? []
        if source == .event, let eventID, !eventID.isEmpty,
           entries.contains(where: { $0.eventID == eventID }) { return false }
        entries.append(PokemonMemory(companionID: companionID, createdAt: createdAt, source: source, body: body, eventID: eventID))
        memories[companionID] = Array(entries.suffix(200)); normalizePins(); save()
        setFirstRecordedAtIfNeeded(companionID, date: createdAt)
        return true
    }
    @discardableResult
    func addManual(companionID: UUID, body: String) -> Bool {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 280 else { return false }
        var entries = memories[companionID] ?? []
        let createdAt = Date()
        entries.append(PokemonMemory(companionID: companionID, createdAt: createdAt, source: .manual, body: body))
        memories[companionID] = Array(entries.suffix(200)); normalizePins(); save()
        setFirstRecordedAtIfNeeded(companionID, date: createdAt)
        return true
    }
    /// `sessionID` is the persisted AdventureRun UUID.  Keeping it makes recovery/retry harmless
    /// while ensuring only sessions settled after this version began contribute to the counter.
    func recordCompletedFocusSession(companionID: UUID, sessionID: String, completedAt: Date) {
        guard !sessionID.isEmpty else { return }
        var state = milestoneStates[companionID] ?? PokemonMemoryMilestoneState()
        guard state.completedFocusSessionIDs.insert(sessionID).inserted else { return }
        state.completedFocusSessionCount += 1
        if [10, 30, 100].contains(state.completedFocusSessionCount) {
            state.focusThresholdDates[state.completedFocusSessionCount] = completedAt
        }
        milestoneStates[companionID] = state; save()
    }
    func recordEvolution(companionID: UUID, eventID: String, evolvedSpeciesID: Int, occurredAt: Date) {
        guard !eventID.isEmpty else { return }
        var state = milestoneStates[companionID] ?? PokemonMemoryMilestoneState()
        guard !state.evolutions.contains(where: { $0.eventID == eventID }) else { return }
        state.evolutions.append(.init(eventID: eventID, occurredAt: occurredAt, evolvedSpeciesID: evolvedSpeciesID))
        milestoneStates[companionID] = state; save()
    }
    func pin(_ memory: PokemonMemory) {
        guard entries(for: memory.companionID).contains(where: { $0.id == memory.id }) else { return }
        pinnedMemoryIDs[memory.companionID] = memory.id; save()
    }
    @discardableResult
    func setHidden(_ memory: PokemonMemory, isHidden: Bool) -> Bool {
        guard var entries = memories[memory.companionID],
              let index = entries.firstIndex(where: { $0.id == memory.id }) else { return false }
        entries[index].isHidden = isHidden
        memories[memory.companionID] = entries; save()
        return true
    }
    @discardableResult
    func delete(_ memory: PokemonMemory) -> Bool {
        guard memory.source == .manual, var entries = memories[memory.companionID] else { return false }
        let oldCount = entries.count
        entries.removeAll { $0.id == memory.id }
        guard entries.count != oldCount else { return false }
        memories[memory.companionID] = entries
        if pinnedMemoryIDs[memory.companionID] == memory.id { pinnedMemoryIDs.removeValue(forKey: memory.companionID) }
        save()
        return true
    }
    func deleteAll(for id: UUID) { memories.removeValue(forKey: id); pinnedMemoryIDs.removeValue(forKey: id); milestoneStates.removeValue(forKey: id); save() }
    func prune(validCompanionIDs: Set<UUID>) {
        memories = memories.filter { validCompanionIDs.contains($0.key) }
        pinnedMemoryIDs = pinnedMemoryIDs.filter { validCompanionIDs.contains($0.key) }
        milestoneStates = milestoneStates.filter { validCompanionIDs.contains($0.key) }
        normalizePins(); _ = normalizeMilestones(); save()
    }
    var snapshot: PokemonMemoryAlbumSnapshot { PokemonMemoryAlbumSnapshot(memories: memories, pinnedMemoryIDs: pinnedMemoryIDs, milestones: milestoneStates) }
    func replace(with snapshot: PokemonMemoryAlbumSnapshot, validCompanionIDs: Set<UUID>) {
        memories = snapshot.memories.reduce(into: [:]) { result, entry in
            guard validCompanionIDs.contains(entry.key) else { return }
            result[entry.key] = Array(entry.value.filter { memory in
                guard memory.companionID == entry.key else { return false }
                let limit = memory.source == .manual ? 280 : 180
                return !memory.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && memory.body.count <= limit
            }.suffix(200))
        }
        pinnedMemoryIDs = snapshot.pinnedMemoryIDs
        milestoneStates = snapshot.milestones.filter { validCompanionIDs.contains($0.key) }
        normalizePins(); save()
        if normalizeMilestones() || backfillFirstRecordedDates() { save() }
    }
    func snapshotData() throws -> Data { try JSONEncoder().encode(snapshot) }
    private func normalizePins() {
        pinnedMemoryIDs = pinnedMemoryIDs.filter { companionID, memoryID in
            memories[companionID]?.contains(where: { $0.id == memoryID }) == true
        }
    }
    private func setFirstRecordedAtIfNeeded(_ companionID: UUID, date: Date) {
        var state = milestoneStates[companionID] ?? PokemonMemoryMilestoneState()
        guard state.firstRecordedAt == nil || date < state.firstRecordedAt! else { return }
        state.firstRecordedAt = date
        milestoneStates[companionID] = state; save()
    }
    @discardableResult
    private func normalizeMilestones() -> Bool {
        let original = milestoneStates
        milestoneStates = milestoneStates.mapValues { raw in
            var state = raw
            state.completedFocusSessionIDs = Set(state.completedFocusSessionIDs.filter { !$0.isEmpty })
            // A counter without its stable settlement IDs cannot be verified after an import;
            // use only the durable evidence rather than granting cards from a malformed payload.
            state.completedFocusSessionCount = min(max(0, state.completedFocusSessionCount), state.completedFocusSessionIDs.count)
            state.focusThresholdDates = state.focusThresholdDates.filter { threshold, _ in
                [10, 30, 100].contains(threshold) && threshold <= state.completedFocusSessionCount
            }
            var seenEvolutionIDs = Set<String>()
            state.evolutions = state.evolutions.filter {
                !$0.eventID.isEmpty && $0.evolvedSpeciesID > 0 && seenEvolutionIDs.insert($0.eventID).inserted
            }
            return state
        }
        return milestoneStates != original
    }
    @discardableResult
    private func backfillFirstRecordedDates() -> Bool {
        var changed = false
        for (companionID, entries) in memories {
            guard let first = entries.map(\.createdAt).min() else { continue }
            let existing = milestoneStates[companionID]?.firstRecordedAt
            guard existing == nil || first < existing! else { continue }
            var state = milestoneStates[companionID] ?? PokemonMemoryMilestoneState()
            state.firstRecordedAt = first
            milestoneStates[companionID] = state
            changed = true
        }
        return changed
    }
    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

protocol PokemonChatProviding: Sendable {
    func reply(to request: PokemonChatRequest) async throws -> String
}

enum PokemonChatProviderKind: String, Codable, CaseIterable, Sendable {
    case codex, claude, opencode, custom

    /// 제공자 이름은 피커·설정 두 화면이 함께 쓴다. 화면마다 하드코딩하면 한 곳을 빠뜨린다.
    func label(_ language: AppLanguage) -> String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .opencode: return "OpenCode"
        case .custom: return L(language).t("사용자 CLI", "Custom CLI", "カスタム CLI")
        }
    }
}

/// 차단 사유는 사용자가 할 수 있는 일이 서로 다르다 — 뭉개면 "설정에서 경로를 지정하라" 는
/// 헛된 안내가 된다. 문구는 커버리지 게이트 안(이 파일)에 두고 뷰는 표시만 한다.
enum PokemonChatBlockReason: Sendable, Equatable {
    /// 실행별로 도구·MCP 를 끄는 방법이 CLI 에 없다. OpenCode 실측 기록:
    /// `docs/reference/opencode-isolation.md`.
    case unverifiedToolContract
    /// 앱이 내용을 모르는 임의 실행 파일이다 — 어떤 격리도 약속할 수 없다.
    case arbitraryExecutable

    func message(_ language: AppLanguage) -> String {
        switch self {
        case .unverifiedToolContract:
            return L(language).t("이 CLI 는 실행별로 도구·MCP 를 끄는 방법을 제공하지 않아, 앱이 격리를 보장할 수 없습니다.",
                                 "This CLI offers no per-run way to disable tools and MCP, so the app cannot guarantee isolation.",
                                 "この CLI は実行ごとにツール・MCP を無効化する手段がないため、アプリが隔離を保証できません。")
        case .arbitraryExecutable:
            return L(language).t("임의의 실행 파일이라 도구 격리를 보장할 수 없어 대화에 쓸 수 없습니다.",
                                 "An arbitrary executable cannot be tool-isolated, so it is unavailable for chat.",
                                 "任意の実行ファイルはツール隔離を保証できないため、会話には使えません。")
        }
    }
}

enum PokemonChatProviderAvailability: Sendable, Equatable {
    /// 무도구 실행 계약이 실측으로 확인됨.
    case verified
    case blocked(PokemonChatBlockReason)

    var isVerified: Bool { self == .verified }
    var blockReason: PokemonChatBlockReason? {
        if case .blocked(let reason) = self { return reason }
        return nil
    }
}

/// 대화용 CLI는 모델의 응답 품질보다 도구 격리가 우선이다. 검증되지 않은 제공자는 실행하지 않는다.
enum PokemonChatProviderSafety {
    /// 가용성이 진실 원천이다. `arguments` → `executableURL` → 뷰가 모두 여기서 파생돼야
    /// 한 곳만 고쳐지고 형제 경로가 무검사로 남는 일이 없다.
    static func availability(for provider: PokemonChatProviderKind) -> PokemonChatProviderAvailability {
        switch provider {
        case .codex, .claude: return .verified
        case .opencode: return .blocked(.unverifiedToolContract)
        case .custom: return .blocked(.arbitraryExecutable)
        }
    }

    static var verifiedKinds: [PokemonChatProviderKind] {
        PokemonChatProviderKind.allCases.filter { availability(for: $0).isVerified }
    }

    static func arguments(for provider: PokemonChatProviderKind) -> [String]? {
        guard availability(for: provider).isVerified else { return nil }
        switch provider {
        case .claude:
            // `--tools ""`는 Claude Code 내장 도구 전체를 제거한다. strict MCP 설정과 빈 설정을 함께
            // 주어 사용자·프로젝트 MCP 구성이 섞이지 않게 한다.
            // `--setting-sources ""`는 사용자·프로젝트·local 설정 파일을 아예 안 읽는다.
            // `--safe-mode` 는 훅·플러그인만 끄고 설정의 env(`OTEL_*` 등)는 그대로 실었고, 실행마다
            // 사용자 `~/.claude/settings.json` 에 permission 규칙을 **쓰기까지** 했다(실측).
            return ["claude", "--print", "--tools", "", "--safe-mode", "--setting-sources", "",
                    "--strict-mcp-config",
                    "--mcp-config", "{\"mcpServers\":{}}", "--no-session-persistence",
                    "--disable-slash-commands", "--permission-mode", "dontAsk"]
        case .codex:
            // Codex CLI에는 이 버전에서 tool-free 플래그가 없다. MCP·사용자 설정·규칙을 배제하고,
            // 남는 내장 실행 기능은 읽기 전용 샌드박스로 제한한다. 따라서 파일 수정은 불가능하다.
            return ["codex", "exec", "--skip-git-repo-check", "--sandbox", "read-only",
                    "--ephemeral", "--ignore-user-config", "--ignore-rules", "--config", "mcp_servers={}"]
        case .opencode, .custom:
            // 위 `availability` 관문이 이미 걸렀다. 망라성 때문에 남기며, 두 번째 진실 원천이
            // 되지 않도록 판단은 하지 않는다.
            return nil
        }
    }
}

/// Resolves only an explicit, executable file.  GUI applications must not inherit a shell PATH.
enum PokemonChatProviderExecutableResolver {
    /// CLI 가 실제로 설치되는 자리. **종류별로 목록을 따로 두지 않는다** — 두 벌이면 새 설치 자리가
    /// 한쪽에만 들어가 다른 CLI 는 영영 못 찾는다. 이름만 갈아 끼운다.
    ///
    /// 순서는 우선순위다. 사용자 홈 설치분이 앞에 오는 이유는, 그게 사용자가 방금 설치해 `which` 가
    /// 가리키는 것이기 때문이다 — 시스템 자리에 남은 옛 사본이 그걸 가려서는 안 된다.
    static let searchDirectories: [String] = [
        "~/.local/bin",        // npm/uv 사용자 설치 — 자동 탐색이 여기를 빠뜨려 대화가 통째로 죽어 있었다
        "~/.claude/local",     // Claude Code 자체 설치 관리자
        "/opt/homebrew/bin",   // Homebrew (Apple Silicon)
        "/usr/local/bin",      // Homebrew (Intel) · 수동 설치
        "~/.bun/bin",
        "~/.volta/bin",
        "~/.npm-global/bin",
        "~/.cargo/bin",
        "~/.asdf/shims",
        "~/.mise/shims",
        "~/.deno/bin",
        "/opt/local/bin",      // MacPorts
        "/usr/bin",
    ]

    /// ponytail: nvm(`~/.nvm/versions/node/<버전>/bin`)처럼 경로에 버전이 박히는 관리자는 글롭이
    /// 필요해 넣지 않았다. 설정의 직접 입력이 그 경우를 덮는다 — 필요해지면 여기에 글롭을 더한다.
    static func binaryName(for kind: PokemonChatProviderKind) -> String? {
        switch kind {
        case .codex: return "codex"
        case .claude: return "claude"
        case .opencode, .custom: return nil
        }
    }

    static func standardPaths(for kind: PokemonChatProviderKind) -> [String] {
        guard let name = binaryName(for: kind) else { return [] }
        return searchDirectories.map { NSString(string: $0).expandingTildeInPath + "/" + name }
    }

    static func executableURL(for kind: PokemonChatProviderKind) -> URL? {
        executableURL(for: kind,
                      override: UserDefaults.standard.string(forKey: "pokemonChatExecutablePath.\(kind.rawValue)"),
                      searchPaths: standardPaths(for: kind))
    }

    /// 주입 가능한 실체. 탐색 자리를 넓히는 변경이 실제로 그 자리를 밟는지, 실행하는 홈 디렉터리
    /// 상태에 기대지 않고 시험하기 위해서다.
    ///
    /// 쓸 수 없는 override 는 실패가 아니라 폴백이다 — 오래된 지정 하나로 표준 설치분까지 못 쓰게
    /// 되면 사용자는 왜 안 되는지 알 길이 없다.
    static func executableURL(for kind: PokemonChatProviderKind,
                              override: String?, searchPaths: [String]) -> URL? {
        guard PokemonChatProviderSafety.arguments(for: kind) != nil else { return nil }
        if let override, let url = validatedExecutable(override) { return url }
        return searchPaths.lazy.compactMap(validatedExecutable).first
    }

    /// 설정이 저장 **전에** 쓰는 판정과 대화가 실행 **직전에** 쓰는 판정은 이 한 벌이다. 두 벌이면
    /// 설정에서 통과한 경로가 대화에서 조용히 실패한다.
    ///
    /// 심볼릭 링크를 풀지 않는다(`standardizedFileURL` 은 `..` 만 접는다). `~/.local/bin/claude` 는
    /// 버전 디렉터리를 가리키는 링크라, 대상 경로를 들고 있으면 CLI 가 업데이트되는 순간 죽는다.
    static func validatedExecutable(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
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

/// 대화 CLI 는 **앱이 소유한 빈 디렉터리**에서 돈다.
///
/// 자식의 작업 디렉터리를 정하지 않으면 앱의 cwd 를 그대로 물려받고, 메뉴바 앱의 cwd 는 `/` 다
/// (launchd·LaunchServices 가 그렇게 띄운다). 그러면 CLI 의 프로젝트 루트가 **디스크 전체**가 되어
/// 시작 스캔이 `~/Desktop`·`~/Documents` 를 밟고, macOS 는 자식의 접근을 **앱 책임**으로 돌려
/// 파일 접근 권한 창을 띄운다. 한 번의 전송이 CLI 를 최대 `maxToolRounds + 1` 번 띄우므로 창은
/// 대화 도중 계속 뜬다 — 도구 목록을 닫아 둔 것만으로는 이 부류가 막히지 않는다.
enum PokemonChatWorkspace {
    /// 만들지 못하면 `temporaryDirectory` 로 물러난다. 없는 경로를 넘기면 `Process.run()` 이 던져
    /// 대화가 통째로 죽는다 — 권한 창을 없애려다 기능을 없애는 쪽이 더 나쁘다.
    ///
    /// 심볼릭 링크를 푸는 이유는 폴백 때문이다. `/bin/pwd` 는 물리 경로를 찍는데
    /// `temporaryDirectory` 는 `/var`(→ `/private/var`) 아래라, 안 풀면 두 문자열이 갈린다.
    static let directoryURL: URL =
        resolved(base: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])

    /// 주입 가능한 실체. 폴백 분기는 App Support 가 살아 있는 기계에서 절대 돌지 않아, 상수 안에
    /// 두면 라인 커버리지에 `^0` 으로 남는다 — 통과만 보면 검증된 것과 구별되지 않는다.
    static func resolved(base: URL) -> URL {
        let fm = FileManager.default
        let url = base.appendingPathComponent("PokeTokenBar", isDirectory: true)
            .appendingPathComponent("chat-cwd", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return fm.temporaryDirectory.resolvingSymlinksInPath()
        }
        return url.resolvingSymlinksInPath()
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
                // 정하지 않으면 앱의 cwd(`/`)를 물려받아 CLI 의 프로젝트 루트가 디스크 전체가 된다.
                process.currentDirectoryURL = PokemonChatWorkspace.directoryURL
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
    private(set) var pendingProposal: PokemonChatToolProposal?
    /// 한 번의 전송이 CLI 를 띄우는 최대 추가 횟수. 상한이 없으면 매 턴 도구를 부르는 모델에
    /// 한 문장이 무한 왕복이 된다.
    /// 읽고-쓰는 2단 체인(`bag.list` → `item.use`)이 생기면서 2 라운드로는 마지막 턴에 실행이
    /// 잘린다. 숫자는 여전히 여기 한 곳뿐이다.
    static let maxToolRounds = 3
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

    func send(_ body: String, for companionID: UUID, profile: PokemonChatProfile,
              provider: any PokemonChatProviding,
              toolbox: (any PokemonChatToolRunning)? = nil) async {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appendLocalMessage(body, for: companionID, profile: profile)
        guard sessions[companionID] != nil else { return }
        outstandingSendCount += 1; errorMessage = nil
        defer { outstandingSendCount -= 1 }
        do {
            // 도구 결과는 이 배열에만 실린다 — 대화 기록에 넣으면 사용자가 기계 문자열을 읽는다.
            var toolResults: [PokemonChatMessage] = []
            var reply = ""
            var call: PokemonChatToolCall?
            // 왕복 한 벌만 둔다. 범위와 "마지막인가" 판정이 각각 숫자를 들면 서로를 가려서,
            // 한쪽을 넓혀도 아무 테스트가 안 깨진다.
            let rounds = 0...Self.maxToolRounds
            for round in rounds {
                guard let session = sessions[companionID] else { return }
                let request = PokemonChatRequest(profile: profile,
                                                 memories: Array(album.entries(for: companionID).filter { $0.source != .manual }.suffix(8)),
                                                 recentMessages: Array(session.messages.suffix(12)) + toolResults)
                let parsed = PokemonChatToolParser.parse(try await provider.reply(to: request))
                reply = parsed.body
                call = parsed.call
                guard let pending = parsed.call, let toolbox else { break }
                // 기억하기는 **루프에서 돌리지 않는다.** 본문은 아래에서 가드를 통과한 답변으로
                // 채우므로, 여기서 실행하면 빈 본문으로 실패("memory not recorded")를 모델에
                // 돌려주고 남은 왕복을 전부 태운다 — 그리고 모델이 다음 턴에 마커를 다시 붙이지
                // 않으면 `call` 이 비어 기억이 아예 남지 않는다.
                if case .memoryRecord = pending { break }
                if pending.needsApproval {
                    // 승인이 필요한 도구는 여기서 멈춘다. 사용자가 누르기 전에 다시 물으면 승인이 무의미하다.
                    if toolbox.canRun(pending, owner: companionID) { break }
                    // 이 창에서 될 수 없는 일이면 **카드를 띄우지 않는다.** 성공할 수 없는 질문이라,
                    // 사용자는 탭 한 번을 버리고 실패 문구를 받는다. 대신 아래에서 사유를 모델에
                    // 돌려줘 사람 말로 설명하게 한다.
                    call = nil
                }
                // 마지막 요청 뒤의 실행은 결과를 전할 턴이 없다 — 부작용만 남기고 끝난다.
                guard round != rounds.upperBound else { break }
                toolResults.append(PokemonChatMessage(role: .system, body: await toolbox.run(pending, owner: companionID).line))
            }

            let safeReply = PokemonChatReplyGuard.sanitized(reply, profile: profile)
            guard var current = sessions[companionID] else { return }
            current.refreshIdentity(speciesID: profile.speciesID, displayName: profile.displayName)
            current.messages.append(PokemonChatMessage(role: .pokemon, body: safeReply)); current.messages = Array(current.messages.suffix(200))
            // 가드가 답변을 갈아치웠다면 그 답변이 딸고 온 제안도 사용자의 의도와 무관하다.
            if safeReply == reply, let call, call.needsApproval {
                pendingProposal = PokemonChatToolProposal(call: call, companionID: companionID)
            }
            // `memory.record` 만 인자를 파서가 채우지 않는다. 모델이 기억 문구를 직접 쓰면 그게
            // 임의 문자열 인자이고, 다음 요청의 컨텍스트로 되돌아온다. 그래서 **가드를 통과한**
            // 답변만 기록한다 — 가드가 답변을 갈아치웠다면 기록할 것도 없다.
            var recordedByTool = false
            if safeReply == reply, case .memoryRecord = call, let toolbox {
                recordedByTool = await toolbox.run(.memoryRecord(body: safeReply), owner: companionID).succeeded
            }
            // 주기 기록은 도구가 **같은 문장**을 이미 남겼으면 건너뛴다. `record` 는 대화 기억을
            // 중복 제거하지 않아(이벤트만 `eventID` 로 막는다) 6번째 메시지에서 마커가 붙으면
            // 앨범에 같은 줄이 두 번 남는다.
            if !recordedByTool, current.lifetimeUserMessageCount > 0, current.lifetimeUserMessageCount % 6 == 0 {
                let candidate = safeReply.count <= 180 ? safeReply : ""
                if !candidate.isEmpty { album.record(companionID: companionID, body: candidate, source: .conversation) }
            }
            current.updatedAt = Date(); sessions[companionID] = current; save()
        } catch { errorMessage = error.localizedDescription }
    }

    #if DEBUG
    /// 테스트 전용 — 승인 카드가 뜬 상태를 프로바이더 왕복 없이 만든다.
    func proposeForTesting(_ call: PokemonChatToolCall, companionID: UUID) {
        pendingProposal = PokemonChatToolProposal(call: call, companionID: companionID)
    }
    #endif

    /// 승인 절차를 SwiftUI 밖에 두고, 실행을 제안이 지목한 개체 ID 에 묶는다. 실행기를 명시적으로
    /// 받는 이유는 눈에 보이는 카드가 나중에 활성이 된 다른 개체를 겨냥할 수 없게 하기 위해서다.
    func resolvePending(approved: Bool, profile: PokemonChatProfile,
                        executor: (PokemonChatToolCall, UUID) async -> Bool) async {
        await resolvePending(approved: approved, profileForCompanion: { _ in profile }, executor: executor)
    }

    func resolvePending(approved: Bool, profileForCompanion: (UUID) -> PokemonChatProfile,
                        executor: (PokemonChatToolCall, UUID) async -> Bool) async {
        guard var proposal = pendingProposal, proposal.state == .pending else { return }
        let profile = profileForCompanion(proposal.companionID)
        var success = false
        if approved {
            proposal.approve()
            success = await executor(proposal.call, proposal.companionID)
            proposal.finish(success: success)
        } else {
            proposal.reject()
        }
        pendingProposal = nil
        appendSystemMessage(proposal.call.outcome(approved: approved, success: success, language: profile.language),
                            for: proposal.companionID, profile: profile)
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
