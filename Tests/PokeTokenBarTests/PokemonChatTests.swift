import XCTest
@testable import PokeTokenBar

@MainActor
final class PokemonChatTests: XCTestCase {
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

    // 대표 특성 선택 규칙(숨은 특성 제외 · slot 최소)의 가드는
    // `BattleAbilityTests.testTheBattleProfileTakesTheFirstNonHiddenAbility` 한 곳에 둔다.
    // 페르소나와 배틀이 같은 `PokemonAbilitiesDTO.primaryAbilitySlug` 를 호출하므로 두 화면이
    // 다른 특성을 말할 수 없다 — 여기 사본을 두면 한쪽을 지워도 아무 테스트가 안 깨진다.

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

    /// 홈 화면이 능력치 여섯 칸을 항상 띄우는데(`currentStats`) 대화는 그 숫자를 몰랐다.
    ///
    /// **도구로 만들지 않는다.** 프로필은 이미 타입·기술·다음 진화를 싣는 자리이고, 도구로 하면
    /// 왕복 한 번과 프롬프트 광고 줄을 더 쓰면서 같은 값을 준다.
    func testProfileAndPromptCarryTheIndividualsStats() async throws {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        store.debugSetLoadedTypes([.electric], speciesID: 25,
                                  base: BattleStats(hp: 35, atk: 55, def: 40, spa: 50, spd: 50, spe: 90))
        let expected = try XCTUnwrap(store.currentStats)

        let profile = store.chatProfile(for: try XCTUnwrap(store.state.active))
        let prompt = PokemonChatRequest(profile: profile, summary: "", recentMessages: []).systemPrompt

        XCTAssertEqual(profile.stats, "HP \(expected.hp) / Atk \(expected.atk) / Def \(expected.def)"
                       + " / SpA \(expected.spa) / SpD \(expected.spd) / Spe \(expected.spe)")
        XCTAssertTrue(prompt.contains("Spe \(expected.spe)"), prompt)
    }

    /// 능력치는 **개체의** 값이다(레벨·성격이 먹은 값). 그래서 종이 같아도 다른 개체의 프로필에
    /// 실으면 안 된다 — `currentStats` 는 활성 개체의 레벨·성격으로 계산하므로, 박스에 있는
    /// 레벨 3 짜리 프로필에 활성 레벨 20 의 숫자가 그럴듯하게 실린다(타입과 달리 종만 맞춰선 못 막는다).
    func testStatsAreOmittedForACompanionWhoIsNotTheOneWhoseStatsAreLoaded() async throws {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        store.debugSetLoadedTypes([.electric], speciesID: 25,
                                  base: BattleStats(hp: 35, atk: 55, def: 40, spa: 50, spd: 50, spe: 90))
        store.debugSetBoxedMons([mon(speciesID: 25, name: "피카츄")])
        XCTAssertNotNil(store.currentStats, "전제: 활성 개체의 능력치는 로드돼 있다")

        let boxed = store.chatProfile(for: try XCTUnwrap(store.boxedMons.first))

        XCTAssertNil(boxed.stats, "같은 종이라는 이유로 남의 능력치가 실렸다")
    }

    /// 상한은 1_600 → 2_100 → 2_500 → 2_800 으로 올랐다. 마지막 300자는 도구 셋(`adventure.claim`·
    /// `dex.progress`·`challenge.status`)의 광고 줄과 능력치 절이다 — 실측 2_788.
    /// **늘어난 만큼만** 올린다 — 넉넉히 잡으면 다음에 무엇이 새어 들어와도 아무도 모른다.
    /// 도구를 더할 때 여기가 깨지는 건 정상이고, 깨진 만큼만 올리는 게 규칙이다.
    func testSystemPromptStaysWithinTheChatBudgetWithAFullIdentity() {
        var profile = PokemonChatProfile.fixture
        profile.apply(PokemonSpeciesIdentity(
            genera: ["ko": String(repeating: "분류", count: 20)], habitatSlug: "rough-terrain",
            flavorTexts: ["ko": String(repeating: "도감 설명 ", count: 25)],
            abilityNames: ["ko": String(repeating: "특성", count: 12)],
            abilityTexts: ["ko": String(repeating: "특성 설명 ", count: 20)],
            language: .ko
        ))

        // 능력치는 채워진 쪽이 최악이다("not loaded" 로 재면 실제 프롬프트보다 짧게 나온다).
        profile.stats = "HP 999 / Atk 999 / Def 999 / SpA 999 / SpD 999 / Spe 999"
        let prompt = PokemonChatRequest(profile: profile, summary: "", recentMessages: []).systemPrompt

        XCTAssertLessThanOrEqual(prompt.count, 2_800)
    }

    /// 페르소나 전용 DTO 는 `SpeciesDTO` 와 따로 산다 — `flavor_text_entries` 는 종 응답에서 가장 큰
    /// 배열이라 부화·진화라인 로드마다 디코딩하고 버리면 안 된다. 두 필드 모두 선택적이다.
    func testChatSpeciesDTODecodesWithAndWithoutGeneraAndHabitat() throws {
        let full = Data("""
        {
          "flavor_text_entries": [],
          "genera": [{"genus": "쥐포켓몬", "language": {"name": "ko", "url": null}}],
          "habitat": {"name": "forest", "url": null}
        }
        """.utf8)
        let sparse = Data("""
        { "flavor_text_entries": [] }
        """.utf8)

        let decodedFull = try JSONDecoder().decode(ChatSpeciesDTO.self, from: full)
        let decodedSparse = try JSONDecoder().decode(ChatSpeciesDTO.self, from: sparse)

        XCTAssertEqual(decodedFull.genera?.first?.genus, "쥐포켓몬")
        XCTAssertEqual(decodedFull.habitat?.name, "forest")
        XCTAssertNil(decodedSparse.genera)
        XCTAssertNil(decodedSparse.habitat)
    }

    /// 부화·진화라인이 쓰는 `SpeciesDTO` 에는 페르소나 필드가 **없어야** 한다. 얹는 순간 종 응답의
    /// 가장 큰 배열을 매 로드마다 디코딩하게 되고, 그 회귀는 눈으로만 보면 안 보인다.
    func testSpeciesDTOCarriesNoPersonaOnlyFields() throws {
        let json = Data("""
        {
          "capture_rate": 190,
          "is_legendary": false,
          "is_mythical": false,
          "names": [],
          "evolution_chain": {"url": "https://pokeapi.co/api/v2/evolution-chain/10/"},
          "evolves_from_species": null
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(SpeciesDTO.self, from: json)

        XCTAssertEqual(decoded.capture_rate, 190)
        XCTAssertEqual(Mirror(reflecting: decoded).children.compactMap(\.label).sorted(),
                       ["capture_rate", "evolution_chain", "evolves_from_species",
                        "gender_rate", "is_legendary", "is_mythical", "names"])
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

    /// 라인 커버리지 84% 를 통과하는 동안 `label`·`verifiedKinds`·`blockReason` 는 **한 번도
    /// 실행되지 않았다**(`llvm-cov --show-functions` 로 0.00% 확인). 피커·설정 두 화면이 이 셋에
    /// 의존하므로 실행되는지를 여기서 못 박는다.
    func testProviderLabelsAndVerifiedKindsFeedBothScreensFromOneList() {
        XCTAssertEqual(PokemonChatProviderSafety.verifiedKinds, [.codex, .claude])
        for kind in PokemonChatProviderKind.allCases {
            for language in [AppLanguage.ko, .en, .ja] {
                XCTAssertFalse(kind.label(language).isEmpty, "\(kind.rawValue)/\(language): 빈 이름")
            }
        }
        XCTAssertEqual(Set(PokemonChatProviderKind.allCases.map { $0.label(.en) }).count,
                       PokemonChatProviderKind.allCases.count, "제공자 이름이 겹친다")
        XCTAssertEqual(PokemonChatProviderSafety.availability(for: .opencode).blockReason,
                       .unverifiedToolContract)
        XCTAssertNil(PokemonChatProviderSafety.availability(for: .codex).blockReason)
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

    private func makeCompanionStore() -> CompanionStore {
        let line = EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                           names: [25: ["ko": "피카츄", "en": "Pikachu"]])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pokemon-chat-companion-\(UUID().uuidString).json")
        let store = CompanionStore(provider: ChatLineProvider(line: line),
                                   clock: { Date(timeIntervalSince1970: 1_000) },
                                   fileURL: url, rng: SeededRNG(seed: 1))
        // 신규 세이브의 언어는 `.systemDefault` 라 호스트 로케일을 따라간다(한국어 Mac=ko, CI=en).
        // 페르소나 단언이 한국어 이름을 기대하므로 여기서 못 박는다 — 안 박으면 로컬에서만 통과한다.
        store.setLanguage(.ko)
        return store
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
