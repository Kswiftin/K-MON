import XCTest
@testable import PokeTokenBar

@MainActor
final class PokemonChatTests: XCTestCase {
    func testSessionStaysAttachedToIndividualAcrossSpeciesChange() throws {
        let id = UUID()
        var session = PokemonChatSession(companionID: id, speciesID: 1, displayName: "이상해씨")
        session.refreshIdentity(speciesID: 2, displayName: "이상해풀")

        XCTAssertEqual(session.companionID, id)
        XCTAssertEqual(session.speciesID, 2)
        XCTAssertEqual(session.displayName, "이상해풀")
    }

    func testPromptUsesPersonaAndRecentMessagesButNotFullHistory() {
        let profile = PokemonChatProfile(speciesID: 25, displayName: "피카츄", nickname: "번개",
                                         nature: "명랑", level: 18, stage: "첫 번째 형태",
                                         flavorText: "전기를 볼에 저장한다.", language: .ko)
        let history = (0..<16).map { PokemonChatMessage(role: .user, body: "메시지 \($0)") }
        let request = PokemonChatRequest(profile: profile, summary: "트레이너와 산책을 약속했다.",
                                         recentMessages: Array(history.suffix(12)))

        XCTAssertTrue(request.systemPrompt.contains("피카츄"))
        XCTAssertTrue(request.systemPrompt.contains("명랑"))
        XCTAssertTrue(request.systemPrompt.contains("전기를 볼에 저장한다."))
        XCTAssertEqual(request.recentMessages.count, 12)
        XCTAssertEqual(request.summary, "트레이너와 산책을 약속했다.")
    }

    func testShinyProfileIsRetainedForChatSpriteRendering() {
        let profile = PokemonChatProfile(speciesID: 25, displayName: "피카츄", nickname: nil,
                                         isShiny: true, nature: nil, level: 5, stage: "첫 번째 형태",
                                         flavorText: nil, language: .ko)
        XCTAssertTrue(profile.isShiny)
    }

    func testOnlyMostRecentPokemonMessageUsesEmphasizedPresentation() {
        let first = PokemonChatMessage(role: .pokemon, body: "처음")
        let user = PokemonChatMessage(role: .user, body: "안녕")
        let last = PokemonChatMessage(role: .pokemon, body: "마지막")
        XCTAssertEqual(PokemonChatMessagePresentation.emphasizedPokemonMessageID(in: [first, user, last]), last.id)
        XCTAssertEqual(PokemonChatMessagePresentation.avatarSize(isEmphasized: true), 72)
        XCTAssertEqual(PokemonChatMessagePresentation.avatarSize(isEmphasized: false), 28)
    }

    func testSendingStateChangesFromThinkingToPokemonReply() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pokemon-chat-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PokemonChatStore(fileURL: url)
        let companionID = UUID()
        let provider = DeferredReplyProvider()
        let task = Task { await store.send("안녕", for: companionID, profile: .fixture, provider: provider) }

        for _ in 0..<10 where !store.isSending { await Task.yield() }
        XCTAssertTrue(store.isSending)
        await provider.resolve(with: "반가워!")
        await task.value

        XCTAssertFalse(store.isSending)
        XCTAssertEqual(store.messages(for: companionID).last?.role, .pokemon)
    }

    func testPromptRestrictsThePokemonToPokedexAndCompanionTopics() {
        let request = PokemonChatRequest(profile: .fixture, summary: "", recentMessages: [])

        XCTAssertTrue(request.systemPrompt.contains("ONLY discuss Pokédex information"))
        XCTAssertTrue(request.systemPrompt.contains("Never offer coding, file, terminal, web research"))
    }

    func testClaudeProviderDisablesBuiltInToolsAndMCPConfiguration() {
        let arguments = PokemonChatProviderSafety.arguments(for: .claude)

        XCTAssertEqual(arguments, ["claude", "--print", "--tools", "", "--safe-mode", "--strict-mcp-config",
                                   "--mcp-config", "{\"mcpServers\":{}}", "--no-session-persistence",
                                   "--disable-slash-commands", "--permission-mode", "dontAsk"])
    }

    func testClaudePassesPersonaAsSystemPromptAndKeepsItOutOfConversationInput() {
        let request = PokemonChatRequest(profile: .fixture, summary: "산책 약속", recentMessages: [PokemonChatMessage(role: .user, body: "안녕")])
        let provider = PokemonChatCLIProvider(executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                                              arguments: PokemonChatProviderSafety.arguments(for: .claude)!, kind: .claude)
        let invocation = provider.invocationArguments(for: request)
        XCTAssertEqual(invocation.suffix(2), ["--system-prompt", request.systemPrompt])
        XCTAssertFalse(request.conversationInput.contains("You are"))
        XCTAssertTrue(request.conversationInput.contains("user: 안녕"))
    }

    func testRoleBreakingReplyIsReplacedBeforeDisplayOrPersistence() {
        let safe = PokemonChatReplyGuard.sanitized("```swift\nread_file(\"secret\")\n```", profile: .fixture)
        XCTAssertFalse(safe.contains("```"))
        XCTAssertFalse(safe.lowercased().contains("read_file"))
        XCTAssertTrue(safe.contains("도감"))
    }

    func testAlbumDeduplicatesCapsAndDeletes() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pokemon-memory-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url), id = UUID()
        album.record(companionID: id, body: "함께 산책했다.", source: .event)
        album.record(companionID: id, body: "함께 산책했다.", source: .event)
        XCTAssertEqual(album.entries(for: id).count, 1)
        album.deleteAll(for: id)
        XCTAssertTrue(album.entries(for: id).isEmpty)
    }

    func testCodexProviderIgnoresConfigurationAndUsesReadOnlySandbox() {
        let arguments = PokemonChatProviderSafety.arguments(for: .codex)

        XCTAssertEqual(arguments, ["codex", "exec", "--skip-git-repo-check", "--sandbox", "read-only",
                                   "--ephemeral", "--ignore-user-config", "--ignore-rules", "--config", "mcp_servers={}"])
    }

    func testProvidersWithoutAVerifiedToolFreeContractAreBlocked() {
        XCTAssertNil(PokemonChatProviderSafety.arguments(for: .opencode))
        XCTAssertNil(PokemonChatProviderSafety.arguments(for: .custom))
    }

    func testDeletingSessionRemovesPersistedConversation() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pokemon-chat-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        let store = PokemonChatStore(fileURL: url)
        store.appendLocalMessage("안녕", for: id, profile: .fixture)
        store.deleteSession(for: id)

        let restored = PokemonChatStore(fileURL: url)
        XCTAssertNil(restored.session(for: id))
    }

    func testActionProposalRequiresExplicitApproval() {
        var proposal = PokemonChatActionProposal(kind: .feed, companionID: UUID())
        XCTAssertEqual(proposal.state, .pending)
        proposal.approve()
        XCTAssertEqual(proposal.state, .approved)
    }
}

private actor DeferredReplyProvider: PokemonChatProviding {
    private var continuation: CheckedContinuation<String, Error>?

    func reply(to request: PokemonChatRequest) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(with reply: String) {
        continuation?.resume(returning: reply)
        continuation = nil
    }
}

private extension PokemonChatProfile {
    static let fixture = PokemonChatProfile(speciesID: 1, displayName: "이상해씨", nickname: nil,
                                            nature: "온순", level: 5, stage: "첫 번째 형태",
                                            flavorText: "태어날 때부터 등에 이상한 씨앗이 자란다.", language: .ko)
}
