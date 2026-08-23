import XCTest
@testable import PokeTokenBar

@MainActor
final class PokemonChatTests: XCTestCase {
    func testCareTagIsStrippedBeforeTheGuardCountsSentences() {
        let parsed = PokemonChatCareParser.parse("첫 문장. 둘째 문장! 셋째 문장.\n[[care:feed]]")

        XCTAssertEqual(parsed.kind, .feed)
        XCTAssertEqual(parsed.body, "첫 문장. 둘째 문장! 셋째 문장.")
    }

    func testUnknownCareTagIsDroppedAndTreatedAsPlainConversation() {
        for reply in ["괜찮아 [[care:dance]]", "괜찮아 [[care:]]", "괜찮아 [[ care : feed ]]" ] {
            let parsed = PokemonChatCareParser.parse(reply)
            XCTAssertNil(parsed.kind)
            XCTAssertFalse(parsed.body.contains("[["))
        }
    }

    func testOnlyStateVerifiedCareKindsAreRequestable() {
        XCTAssertTrue(PokemonChatActionKind.feed.isCareRequestable)
        XCTAssertTrue(PokemonChatActionKind.medicate.isCareRequestable)
        XCTAssertFalse(PokemonChatActionKind.train.isCareRequestable)
        XCTAssertFalse(PokemonChatActionKind.release.isCareRequestable)
    }

    func testCareOfferIsIncludedInPromptWithinTheUpdatedBudget() {
        var profile = PokemonChatProfile.fixture
        profile.careOffer = PokemonChatCareOffer(kinds: [.feed, .rest], stateLine: "배고픔 40, 에너지 50")

        let prompt = PokemonChatRequest(profile: profile, summary: "", recentMessages: []).systemPrompt

        XCTAssertTrue(prompt.contains("배고픔 40"))
        XCTAssertTrue(prompt.contains("[[care:feed]]"))
        XCTAssertLessThanOrEqual(prompt.count, 1_750)
    }

    func testBoxedPokemonGetsNoCareOfferOrInvitation() async throws {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let boxed = mon(speciesID: 4, name: "파이리")
        store.debugSetBoxedMons([boxed])

        let profile = store.chatProfile(for: try XCTUnwrap(store.boxedMons.first))

        XCTAssertNil(profile.careOffer)
        XCTAssertFalse(PokemonChatRequest(profile: profile, summary: "", recentMessages: []).systemPrompt.contains("[[care:"))
    }

    func testNonCareKindsAreRejectedByTheChatExecutor() async throws {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)

        let activeID = try XCTUnwrap(store.state.active?.id)
        XCTAssertFalse(store.applyChatCare(.release, for: activeID))
        XCTAssertFalse(store.applyChatCare(.evolve, for: activeID))
    }

    func testChatCareProposalCannotRetargetAnotherCompanion() async throws {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let activeID = try XCTUnwrap(store.state.active?.id)
        store.debugSetCare(PetCareState(hunger: 30, lastUpdatedAt: Date(timeIntervalSince1970: 1_000)))
        let before = store.state.care.hunger

        XCTAssertFalse(store.applyChatCare(.feed, for: UUID()))
        XCTAssertEqual(store.state.care.hunger, before)
        XCTAssertTrue(store.applyChatCare(.feed, for: activeID))
        XCTAssertGreaterThan(store.state.care.hunger, before)
    }

    func testCareProposalLabelsAreLocalizedAndNeverUseEnumSlugs() {
        let slugs = Set(PokemonChatActionKind.allCases.map(\.rawValue))
        for language in [AppLanguage.ko, .en, .ja] {
            let labels = [PokemonChatActionKind.feed, .play, .rest, .clean, .medicate]
                .map { $0.localizedCareLabel(language) }
            XCTAssertEqual(Set(labels).count, 5)
            XCTAssertTrue(labels.allSatisfy { !slugs.contains($0) }, "\(language.rawValue): \(labels)")
        }
    }

    func testBoxedPokemonPersonaUsesItsOwnTypesAndMovesNotTheActivePartners() async throws {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let activeMove = move(id: 84, name: "전기쇼크", type: .electric)
        store.debugSetActiveLearnedMoves([activeMove])
        store.debugSetDisplayedMoves([activeMove])
        store.debugSetLoadedTypes([.electric], speciesID: 25)

        var boxed = mon(speciesID: 4, name: "파이리")
        let boxedMove = move(id: 10, name: "할퀴기", type: .normal)
        boxed.learnedMoves = [boxedMove]
        store.debugSetBoxedMons([boxed])

        let profile = store.chatProfile(for: try XCTUnwrap(store.boxedMons.first))

        XCTAssertTrue(profile.types.isEmpty)
        XCTAssertEqual(profile.moves, [boxedMove.name(.ko)])
        XCTAssertNotEqual(profile.moves, [activeMove.name(.ko)])
    }

    func testActivePartnerPersonaStillCarriesItsLoadedTypes() async throws {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        store.debugSetLoadedTypes([.electric], speciesID: 25)

        let profile = store.chatProfile(for: try XCTUnwrap(store.state.active))

        XCTAssertEqual(profile.types, [PokemonType.electric.name(.ko)])
    }

    func testBoxedPokemonOfTheSameSpeciesKeepsCorrectTypes() async throws {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        store.debugSetLoadedTypes([.electric], speciesID: 25)
        let boxed = mon(speciesID: 25, name: "피카츄")
        store.debugSetBoxedMons([boxed])

        let profile = store.chatProfile(for: try XCTUnwrap(store.boxedMons.first))

        XCTAssertEqual(profile.types, [PokemonType.electric.name(.ko)])
    }

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

    func testSpeciesIdentityLineCarriesGenusHabitatAndAbility() {
        var profile = PokemonChatProfile.fixture
        profile.apply(PokemonSpeciesIdentity(
            genera: ["ko": "쥐포켓몬"], habitatSlug: "forest",
            flavorTexts: ["ko": "볼의 양쪽에는 전기를 모으는 주머니가 있다."],
            abilityNames: ["ko": "정전기"], abilityTexts: ["ko": "접촉한 상대를 마비시킬 때가 있다."],
            language: .ko
        ))

        let prompt = PokemonChatRequest(profile: profile, summary: "", recentMessages: []).systemPrompt

        XCTAssertTrue(prompt.contains("쥐포켓몬"))
        XCTAssertTrue(prompt.contains("숲"))
        XCTAssertTrue(prompt.contains("정전기"))
        XCTAssertTrue(prompt.contains("접촉한 상대를 마비시킬 때가 있다."))
    }

    func testMissingSpeciesFactsAreOmittedInsteadOfLabelledUnknown() {
        var profile = PokemonChatProfile.fixture
        profile.apply(PokemonSpeciesIdentity(
            genera: [:], habitatSlug: nil, flavorTexts: [:], abilityNames: [:], abilityTexts: [:],
            language: .ko
        ))

        let prompt = PokemonChatRequest(profile: profile, summary: "", recentMessages: []).systemPrompt

        XCTAssertFalse(prompt.contains("Species identity:"))
        XCTAssertFalse(prompt.contains("genus "))
        XCTAssertFalse(prompt.contains("habitat "))
        XCTAssertFalse(prompt.contains("ability "))
        XCTAssertFalse(prompt.contains("unknown"))
        XCTAssertFalse(prompt.contains("()"))
    }

    func testAbilityNameSurvivesWhenItsDescriptionIsMissing() {
        let identity = PokemonSpeciesIdentity(
            genera: [:], habitatSlug: nil, flavorTexts: [:],
            abilityNames: ["ko": "정전기"], abilityTexts: ["en": "May paralyze on contact."],
            language: .ko
        )

        XCTAssertEqual(identity.ability, "정전기")
        XCTAssertFalse(identity.ability?.contains("—") ?? true)
    }

    func testProseFieldsDoNotFallBackToEnglishWhileNamesDo() {
        let englishOnly = ["en": "Static"]

        XCTAssertEqual(AppLanguage.ko.resolveName(englishOnly), "Static")
        XCTAssertNil(AppLanguage.ko.resolveProse(englishOnly))
    }

    func testUnknownHabitatSlugIsDroppedRatherThanShownRaw() {
        let identity = PokemonSpeciesIdentity(
            genera: [:], habitatSlug: "temple", flavorTexts: [:], abilityNames: [:], abilityTexts: [:],
            language: .ko
        )

        XCTAssertNil(PokemonHabitat(rawValue: "temple"))
        XCTAssertNil(identity.habitat)
    }

    func testEveryHabitatHasThreeDistinctLanguageNames() {
        XCTAssertEqual(PokemonHabitat.allCases.count, 9)
        for habitat in PokemonHabitat.allCases {
            let names = AppLanguage.allCases.map(habitat.name)
            XCTAssertTrue(names.allSatisfy { !$0.isEmpty }, "Missing habitat translation for \(habitat.rawValue)")
            XCTAssertEqual(Set(names).count, 3, "Habitat translations must be distinct for \(habitat.rawValue)")
        }
    }

    func testHiddenAbilityIsNeverChosenAsTheRepresentativeOne() {
        let entries = [
            (slug: "lightning-rod", isHidden: true, slot: 1),
            (slug: "static", isHidden: false, slot: 2),
            (slug: "run-away", isHidden: false, slot: 3),
        ]

        XCTAssertEqual(PokemonSpeciesIdentity.primaryAbilitySlug(entries), "static")
    }

    func testProfileApplyFillsEveryIdentitySlot() {
        var profile = PokemonChatProfile.fixture
        let identity = PokemonSpeciesIdentity(
            genera: ["ko": "쥐포켓몬"], habitatSlug: "forest",
            flavorTexts: ["ko": "전기를 볼에 저장한다."],
            abilityNames: ["ko": "정전기"], abilityTexts: ["ko": "접촉한 상대를 마비시킨다."],
            language: .ko
        )

        profile.apply(identity)

        XCTAssertEqual(profile.flavorText, identity.flavorText)
        XCTAssertEqual(profile.genus, identity.genus)
        XCTAssertEqual(profile.habitat, identity.habitat)
        XCTAssertEqual(profile.ability, identity.ability)
    }

    func testSystemPromptStaysWithinTheChatBudgetWithAFullIdentity() {
        var profile = PokemonChatProfile.fixture
        profile.apply(PokemonSpeciesIdentity(
            genera: ["ko": String(repeating: "분류", count: 20)], habitatSlug: "rough-terrain",
            flavorTexts: ["ko": String(repeating: "도감 설명 ", count: 25)],
            abilityNames: ["ko": String(repeating: "특성", count: 12)],
            abilityTexts: ["ko": String(repeating: "특성 설명 ", count: 20)],
            language: .ko
        ))

        let prompt = PokemonChatRequest(profile: profile, summary: "", recentMessages: []).systemPrompt

        XCTAssertLessThanOrEqual(prompt.count, 1_600)
    }

    func testSpeciesDTODecodesWithAndWithoutGeneraAndHabitat() throws {
        let full = Data("""
        {
          "capture_rate": 190,
          "is_legendary": false,
          "is_mythical": false,
          "names": [],
          "evolution_chain": {"url": "https://pokeapi.co/api/v2/evolution-chain/10/"},
          "evolves_from_species": null,
          "flavor_text_entries": [],
          "genera": [{"genus": "쥐포켓몬", "language": {"name": "ko", "url": null}}],
          "habitat": {"name": "forest", "url": null}
        }
        """.utf8)
        let sparse = Data("""
        {
          "capture_rate": 45,
          "is_legendary": false,
          "is_mythical": false,
          "names": [],
          "evolution_chain": {"url": "https://pokeapi.co/api/v2/evolution-chain/1/"},
          "evolves_from_species": null,
          "flavor_text_entries": []
        }
        """.utf8)

        let decodedFull = try JSONDecoder().decode(SpeciesDTO.self, from: full)
        let decodedSparse = try JSONDecoder().decode(SpeciesDTO.self, from: sparse)

        XCTAssertEqual(decodedFull.genera?.first?.genus, "쥐포켓몬")
        XCTAssertEqual(decodedFull.habitat?.name, "forest")
        XCTAssertNil(decodedSparse.genera)
        XCTAssertNil(decodedSparse.habitat)
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

    func testAlbumRetainsRepeatedEventsCapsAndDeletes() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pokemon-memory-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let album = PokemonMemoryAlbum(fileURL: url), id = UUID()
        album.record(companionID: id, body: "함께 산책했다.", source: .event)
        album.record(companionID: id, body: "함께 산책했다.", source: .event)
        XCTAssertEqual(album.entries(for: id).count, 2)
        album.deleteAll(for: id)
        XCTAssertTrue(album.entries(for: id).isEmpty)
    }

    func testCodexProviderIgnoresConfigurationAndUsesReadOnlySandbox() {
        let arguments = PokemonChatProviderSafety.arguments(for: .codex)

        XCTAssertEqual(arguments, ["codex", "exec", "--skip-git-repo-check", "--sandbox", "read-only",
                                   "--ephemeral", "--ignore-user-config", "--ignore-rules", "--config", "mcp_servers={}"])
    }

    func testCodexWritesOnlyTheFinalMessageToItsTemporaryOutputFile() {
        let provider = PokemonChatCLIProvider(executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                                              arguments: PokemonChatProviderSafety.arguments(for: .codex)!, kind: .codex)
        let output = URL(fileURLWithPath: "/tmp/final-message.txt")
        let arguments = provider.invocationArguments(for: PokemonChatRequest(profile: .fixture, recentMessages: []), outputFileURL: output)
        XCTAssertEqual(arguments.suffix(2), ["--output-last-message", output.path])
    }

    func testOnlyTheNewestEightDurableMemoriesReachARequest() {
        let id = UUID()
        let memories = (0..<10).map { PokemonMemory(companionID: id, createdAt: Date(), source: .event, body: "event \($0)") }
        let request = PokemonChatRequest(profile: .fixture, memories: memories, recentMessages: [])
        XCTAssertEqual(request.memories.map(\.body), (2..<10).map { "event \($0)" })
        XCTAssertFalse(request.conversationInput.contains("event 1"))
        XCTAssertTrue(request.conversationInput.contains("event 9"))
    }

    func testConcurrentRepliesAndReloadPreserveEveryMessage() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pokemon-chat-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PokemonChatStore(fileURL: url), id = UUID(), provider = QueuedReplyProvider()
        let first = Task { await store.send("first", for: id, profile: .fixture, provider: provider) }
        let second = Task { await store.send("second", for: id, profile: .fixture, provider: provider) }
        for _ in 0..<20 where store.outstandingSendCount < 2 { await Task.yield() }
        XCTAssertEqual(store.outstandingSendCount, 2)
        await provider.resolve(with: "reply one"); await provider.resolve(with: "reply two")
        await first.value; await second.value
        XCTAssertFalse(store.isSending)
        XCTAssertEqual(store.messages(for: id).count, 4)
        XCTAssertEqual(PokemonChatStore(fileURL: url).messages(for: id).count, 4)
    }

    func testTranscriptIsCappedAtTwoHundredMessages() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pokemon-chat-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PokemonChatStore(fileURL: url), id = UUID()
        for index in 0..<205 { store.appendLocalMessage("message \(index)", for: id, profile: .fixture) }
        XCTAssertEqual(store.messages(for: id).count, 200)
        XCTAssertEqual(store.messages(for: id).first?.body, "message 5")
    }

    /// 가용성과 실행 인자가 각자 판단하면 한쪽만 고쳐져 차단이 새어 나간다. `allCases` 전수로
    /// 두 값이 같은 진실을 말하는지 묶는다 — 새 제공자가 늘어도 이 단언이 따라간다.
    func testEveryProviderKindAgreesBetweenAvailabilityAndArguments() {
        for kind in PokemonChatProviderKind.allCases {
            XCTAssertEqual(PokemonChatProviderSafety.arguments(for: kind) != nil,
                           PokemonChatProviderSafety.availability(for: kind).isVerified,
                           "\(kind.rawValue): 가용성과 실행 인자가 어긋난다")
        }
        XCTAssertEqual(PokemonChatProviderSafety.availability(for: .opencode),
                       .blocked(.unverifiedToolContract))
        XCTAssertEqual(PokemonChatProviderSafety.availability(for: .custom),
                       .blocked(.arbitraryExecutable))
    }

    /// 트리거 분기: 사용자 설정(경로 override)이 안전 관문을 우회하는 경로. 실존 실행 파일을
    /// 넣어도 차단 제공자는 해석되지 않아야 한다.
    func testBlockedProviderStaysBlockedEvenWithAnExplicitExecutableOverride() {
        let key = "pokemonChatExecutablePath.opencode"
        UserDefaults.standard.set("/usr/bin/env", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: "/usr/bin/env"),
                      "테스트 전제가 깨졌다 — 실존 실행 파일이어야 우회 시도가 성립한다")
        XCTAssertNil(PokemonChatProviderExecutableResolver.executableURL(for: .opencode))
    }

    func testBlockReasonIsLocalizedInAllThreeLanguages() {
        for reason in [PokemonChatBlockReason.unverifiedToolContract, .arbitraryExecutable] {
            let messages = [AppLanguage.ko, .en, .ja].map { reason.message($0) }
            XCTAssertFalse(messages.contains(where: \.isEmpty), "\(reason): 빈 문구")
            XCTAssertEqual(Set(messages).count, 3, "\(reason): 세 언어가 같은 문구다")
        }
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

    private func makeCompanionStore() -> CompanionStore {
        let line = EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                           names: [25: ["ko": "피카츄", "en": "Pikachu"]])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pokemon-chat-companion-\(UUID().uuidString).json")
        return CompanionStore(provider: ChatLineProvider(line: line),
                              clock: { Date(timeIntervalSince1970: 1_000) },
                              fileURL: url, rng: SeededRNG(seed: 1))
    }

    private func mon(speciesID: Int, name: String) -> MonState {
        MonState(baseID: speciesID, pathIDs: [speciesID], stageIndex: 0, usedAtStage: 0,
                 rarity: .common, totalForms: 1,
                 names: [speciesID: ["ko": name, "en": name]])
    }

    private func move(id: Int, name: String, type: PokemonType) -> MoveSpec {
        MoveSpec(id: id, names: ["ko": name, "en": name], type: type,
                 power: 40, damageClass: .physical, accuracy: 100, pp: 35)
    }
}

private struct ChatLineProvider: PokeProviding {
    let line: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { line }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        [BaseSpecies(id: line.baseID, captureRate: 255)]
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

private actor QueuedReplyProvider: PokemonChatProviding {
    private var continuations: [CheckedContinuation<String, Error>] = []
    func reply(to request: PokemonChatRequest) async throws -> String {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func resolve(with reply: String) { guard !continuations.isEmpty else { return }; continuations.removeFirst().resume(returning: reply) }
}

private extension PokemonChatProfile {
    static let fixture = PokemonChatProfile(speciesID: 1, displayName: "이상해씨", nickname: nil,
                                            nature: "온순", level: 5, stage: "첫 번째 형태",
                                            flavorText: "태어날 때부터 등에 이상한 씨앗이 자란다.", language: .ko)
}
