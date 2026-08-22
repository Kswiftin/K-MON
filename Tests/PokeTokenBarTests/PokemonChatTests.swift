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

private extension PokemonChatProfile {
    static let fixture = PokemonChatProfile(speciesID: 1, displayName: "이상해씨", nickname: nil,
                                            nature: "온순", level: 5, stage: "첫 번째 형태",
                                            flavorText: "태어날 때부터 등에 이상한 씨앗이 자란다.", language: .ko)
}
