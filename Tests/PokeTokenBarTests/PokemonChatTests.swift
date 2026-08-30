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
        // 배운 기술도 함께 채운다. 프롬프트의 `learned moves` 는 **채워진 쪽 분기가 한 번도 안 돌던**
        // 자리다(`--show-regions` 에서 `^0`) — 아무 테스트도 "기술이 프롬프트에 실린다" 를 증명하지
        // 않은 채 "not loaded" 만 밟고 있었다.
        store.debugSetActiveLearnedMoves([move(id: 84, name: "전기쇼크", type: .electric)])
        let expected = try XCTUnwrap(store.currentStats)

        let profile = store.chatProfile(for: try XCTUnwrap(store.state.active))
        let prompt = PokemonChatRequest(profile: profile, summary: "", recentMessages: []).systemPrompt

        XCTAssertEqual(profile.stats, "HP \(expected.hp) / Atk \(expected.atk) / Def \(expected.def)"
                       + " / SpA \(expected.spa) / SpD \(expected.spd) / Spe \(expected.spe)")
        XCTAssertTrue(prompt.contains("Spe \(expected.spe)"), prompt)
        XCTAssertTrue(prompt.contains("learned moves 전기쇼크"), prompt)
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

    /// 상한은 1_600 → 2_100 → 2_500 → 2_800 → 2_860 으로 올랐다. 마지막 60자는 광고 줄이 아니라
    /// **재는 방식**이 늘어난 것이다 — 별명과 배운 기술이 빠진 프로필로 재고 있었다(실측 2_847).
    ///
    /// 예산은 각 절의 **긴 쪽**으로 잰다. 절마다 어느 쪽이 긴지는 다르다:
    /// - 별명·능력치·기술은 **채워진** 쪽이 길다(별명은 `(종 이름)` 을 덧붙이고, 나머지는
    ///   `not loaded` 열 글자를 대체한다).
    /// - 타입·다음 진화는 **비어 있는** 쪽이 길다(`not loaded`·`not known` 이 한국어 이름보다 길다).
    /// 한쪽만 재면 실제 프롬프트가 상한을 넘는데도 게이트는 초록으로 남는다.
    ///
    /// **늘어난 만큼만** 올린다 — 넉넉히 잡으면 다음에 무엇이 새어 들어와도 아무도 모른다.
    /// 도구를 더할 때 여기가 깨지는 건 정상이고, 깨진 만큼만 올리는 게 규칙이다.
    func testSystemPromptStaysWithinTheChatBudgetWithAFullIdentity() {
        // 별명은 세이브 경계(`SaveTransfer.maxNameLength`)까지 길 수 있고, 붙는 순간 종 이름이
        // 괄호로 **함께** 실린다 — 별명 없는 프로필로 재면 그 길이가 통째로 빠진다.
        var profile = PokemonChatProfile.fixture(nickname: String(repeating: "별", count: SaveTransfer.maxNameLength))
        profile.apply(PokemonSpeciesIdentity(
            genera: ["ko": String(repeating: "분류", count: 20)], habitatSlug: "rough-terrain",
            flavorTexts: ["ko": String(repeating: "도감 설명 ", count: 25)],
            abilityNames: ["ko": String(repeating: "특성", count: 12)],
            abilityTexts: ["ko": String(repeating: "특성 설명 ", count: 20)],
            language: .ko
        ))

        // 기술은 네 칸이 상한이다(`learnedMoves` 를 자르는 자리와 같은 수).
        profile.moves = Array(repeating: String(repeating: "기", count: 10), count: 4)
        profile.stats = "HP 999 / Atk 999 / Def 999 / SpA 999 / SpD 999 / Spe 999"
        let prompt = PokemonChatRequest(profile: profile, summary: "", recentMessages: []).systemPrompt

        XCTAssertLessThanOrEqual(prompt.count, 2_860)
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
        let url = temporaryChatURL()
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

    func testClaudeProviderDisablesBuiltInToolsMCPAndUserSettings() {
        let arguments = PokemonChatProviderSafety.arguments(for: .claude)

        XCTAssertEqual(arguments, ["claude", "--print", "--tools", "", "--safe-mode", "--setting-sources", "",
                                   "--strict-mcp-config",
                                   "--mcp-config", "{\"mcpServers\":{}}", "--no-session-persistence",
                                   "--disable-slash-commands", "--permission-mode", "dontAsk"])
    }

    /// 폴백 분기는 App Support 가 살아 있는 기계에서는 절대 돌지 않는다 — 상수 안에 두면
    /// 커버리지에 `^0` 으로 남아 아무도 검증하지 않는다. 권한 창을 없애려다 대화를 없애는 쪽이
    /// 더 나쁘므로, 못 쓰는 상태 디렉터리에서도 **쓸 수 있는 자리**가 나오는지 고정한다.
    func testAnUnusableStateDirectoryStillYieldsARunnableWorkingDirectory() {
        let unusable = URL(fileURLWithPath: "/dev/null").appendingPathComponent("nope", isDirectory: true)

        XCTAssertEqual(PokemonChatWorkspace.resolved(base: unusable),
                       FileManager.default.temporaryDirectory.resolvingSymlinksInPath())
    }

    /// 인자 배열만 비교하는 격리 테스트는 자식의 **실행 환경**을 보지 못한다 — 실제로 띄워서 확인한다.
    /// `XCTAssertNotEqual(stdout, "/")` 로 쓰면 `swift test` 의 cwd(저장소 루트)에서 언제나 통과해
    /// 아무것도 안 지킨다. 앱이 물려주는 cwd 가 무엇이든 **양성으로** 고정해야 결함이 걸린다.
    func testTheChatCLIRunsInTheAppOwnedDirectoryNotWhateverCWDTheAppInherited() async throws {
        let result = try await PokemonChatCommandRunner.run(executableURL: URL(fileURLWithPath: "/bin/pwd"),
                                                           arguments: [], input: "", timeout: 10)

        XCTAssertEqual(result.stdout, PokemonChatWorkspace.directoryURL.path)
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

    func testManualMemoriesNeverReachAProviderRequest() {
        let id = UUID()
        let request = PokemonChatRequest(profile: .fixture, memories: [
            PokemonMemory(companionID: id, createdAt: Date(), source: .event, body: "shared event"),
            PokemonMemory(companionID: id, createdAt: Date(), source: .manual, body: "private note")
        ], recentMessages: [])

        XCTAssertEqual(request.memories.map(\.body), ["shared event"])
        XCTAssertFalse(request.conversationInput.contains("private note"))
    }

    func testConcurrentRepliesAndReloadPreserveEveryMessage() async {
        let url = temporaryChatURL()
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
        let url = temporaryChatURL()
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
        let url = temporaryChatURL()
        let id = UUID()
        let store = PokemonChatStore(fileURL: url)
        store.appendLocalMessage("안녕", for: id, profile: .fixture)
        store.deleteSession(for: id)

        let restored = PokemonChatStore(fileURL: url)
        XCTAssertNil(restored.session(for: id))
    }

    // MARK: - draft 는 뷰가 아니라 스토어가 든다 (팝오버 이관)

    /// 팝오버는 바깥을 클릭하면 닫히고(`behavior = .transient`), 닫히면서 콘텐츠 뷰를 통째로
    /// 해제한다(`popoverDidClose` 가 `contentViewController = nil`). draft 가 뷰의 `@State` 면
    /// 입력 중이던 문장이 클릭 한 번에 사라진다 — 창에서는 안 겪던 손실이다.
    func testDraftSurvivesTheViewBecauseTheStoreHoldsIt() {
        let store = PokemonChatStore(fileURL: temporaryChatURL())
        let id = UUID()

        store.setDraft("배고프면 말해 줘", for: id)

        XCTAssertEqual(store.draft(for: id), "배고프면 말해 줘")
    }

    /// 대화 창은 활성 개체뿐 아니라 박스 개체로도 열린다. draft 를 한 칸에 두면 피카츄에게 쓰다
    /// 만 문장이 파이리 대화에 나타난다.
    func testDraftIsKeptPerCompanion() {
        let store = PokemonChatStore(fileURL: temporaryChatURL())
        let pikachu = UUID(), charmander = UUID()

        store.setDraft("같이 나갈래?", for: pikachu)

        XCTAssertEqual(store.draft(for: pikachu), "같이 나갈래?")
        XCTAssertEqual(store.draft(for: charmander), "")
    }

    /// 꺼내기와 비우기는 **한 동작**이다. 나눠 두면 꺼낸 뒤 비우기 전에 한 번 더 눌리는 창이
    /// 생긴다 — 전송은 `Task` 로 넘어가 비동기라 그 창이 실재한다.
    func testTakingTheDraftEmptiesItInOneStep() {
        let store = PokemonChatStore(fileURL: temporaryChatURL())
        let sender = UUID(), other = UUID()
        store.setDraft("안녕", for: sender)
        store.setDraft("나중에 얘기해", for: other)

        XCTAssertEqual(store.takeDraft(for: sender), "안녕")

        XCTAssertEqual(store.draft(for: sender), "")
        XCTAssertEqual(store.draft(for: other), "나중에 얘기해")
    }

    /// 트리거 브랜치: 공백만 친 뒤 Return. `TextField.onSubmit` 은 전송 버튼의 `disabled` 를
    /// 지나지 않으므로 전송 경로에 **들어간다**. 스토어의 `send` 는 빈 문장 가드에서 먼저
    /// 돌아가므로 거기서 비우면 공백이 입력칸에 영영 남는다.
    func testTakingAWhitespaceOnlyDraftStillEmptiesIt() {
        let store = PokemonChatStore(fileURL: temporaryChatURL())
        let id = UUID()
        store.setDraft("   ", for: id)

        _ = store.takeDraft(for: id)

        XCTAssertEqual(store.draft(for: id), "")
    }

    /// "기록 삭제" 는 대화를 지우는 일이다. 입력칸에 쓰다 만 문장이 남으면 지운 대화의 잔해가
    /// 새 대화에 얹힌다.
    func testDeletingASessionAlsoDropsItsDraft() {
        let store = PokemonChatStore(fileURL: temporaryChatURL())
        let id = UUID()
        store.setDraft("쓰다 만 문장", for: id)

        store.deleteSession(for: id)

        XCTAssertEqual(store.draft(for: id), "")
    }

    /// "새 대화" 도 같다 — 새로 시작했는데 이전 대화에 쓰던 문장이 입력칸에 차 있으면 안 된다.
    func testStartingANewSessionDropsTheDraft() {
        let store = PokemonChatStore(fileURL: temporaryChatURL())
        let id = UUID()
        store.setDraft("쓰다 만 문장", for: id)

        store.startNewSession(for: id, profile: .fixture)

        XCTAssertEqual(store.draft(for: id), "")
    }

    /// 놓아주기·교환·졸업으로 사라진 개체의 draft 가 남으면 죽은 UUID 로 키가 무한히 쌓인다.
    /// `prune` 이 `sessions` 만 거르면 그 자리는 아무도 안 치운다.
    func testPruneDropsDraftsOfCompanionsThatAreGone() {
        let store = PokemonChatStore(fileURL: temporaryChatURL())
        let kept = UUID(), gone = UUID()
        store.setDraft("남는다", for: kept)
        store.setDraft("사라진다", for: gone)

        store.prune(validCompanionIDs: [kept])

        XCTAssertEqual(store.draft(for: kept), "남는다")
        XCTAssertEqual(store.draft(for: gone), "")
    }

    /// "생각 중" 은 **그 대화**의 상태다. 전역 카운터를 그대로 읽으면 피카츄에게 보낸 답을
    /// 기다리는 동안 파이리 대화를 열었을 때, 파이리 기록에 절대 오지 않을 답의 점 세 개가 뜬다.
    /// 팝오버 이관으로 개체 사이 이동이 두 클릭이 되면서 상시로 밟게 됐다.
    func testSendingStateIsPerCompanionNotGlobal() async {
        let store = PokemonChatStore(fileURL: temporaryChatURL())
        let pikachu = UUID(), charmander = UUID()
        let provider = DeferredReplyProvider()
        let task = Task { await store.send("안녕", for: pikachu, profile: .fixture, provider: provider) }
        for _ in 0..<10 where !store.isSending { await Task.yield() }

        XCTAssertTrue(store.isSending(for: pikachu))
        XCTAssertFalse(store.isSending(for: charmander))

        await provider.resolve(with: "반가워!")
        _ = await task.value
        XCTAssertFalse(store.isSending(for: pikachu))
    }

    /// 실행 파일 해석은 디렉터리 13곳에 파일시스템 질의를 던진다(`searchDirectories`). 뷰 `body` 는
    /// 키 입력마다 다시 평가되므로 그때마다 해석하면 타이핑이 메인 스레드에서 경로 탐색을 끌고
    /// 다닌다. 입력(종류·지정 경로)이 그대로면 결과도 그대로다.
    func testProviderResolutionIsNotRepeatedWhileTheInputsStayTheSame() {
        var lookups = 0
        let cache = PokemonChatProviderCache { _, _ in lookups += 1; return nil }

        _ = cache.executableURL(for: .claude, override: nil)
        _ = cache.executableURL(for: .claude, override: nil)
        _ = cache.executableURL(for: .claude, override: nil)

        XCTAssertEqual(lookups, 1)
    }

    /// 캐시가 **안 갱신되면** 설정에서 경로를 고쳐도 대화는 옛 결과를 계속 쓴다 — 캐시의 반대편
    /// 결함이라 같이 고정한다.
    func testProviderResolutionRedoesTheLookupWhenTheInputsChange() {
        var lookups = 0
        let cache = PokemonChatProviderCache { _, _ in lookups += 1; return nil }

        _ = cache.executableURL(for: .claude, override: nil)
        _ = cache.executableURL(for: .claude, override: "/usr/local/bin/claude")
        _ = cache.executableURL(for: .codex, override: "/usr/local/bin/claude")

        XCTAssertEqual(lookups, 3)
    }

    /// 임시 파일을 만든 테스트가 치우지 않으면 실행마다 tmp 에 고아가 하나씩 쌓인다.
    /// 여섯 자리가 같은 식을 각자 베껴 쓰고 있어 치우는 자리도 각자였다 — 한 벌로 모은다.
    private func temporaryChatURL() -> URL { temporaryURL(prefix: "pokemon-chat") }

    private func temporaryURL(prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeCompanionStore() -> CompanionStore {
        let line = EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                           names: [25: ["ko": "피카츄", "en": "Pikachu"]])
        let url = temporaryURL(prefix: "pokemon-chat-companion")
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

private actor FixedReplyProvider: PokemonChatProviding {
    private let reply: String
    init(reply: String) { self.reply = reply }
    func reply(to request: PokemonChatRequest) async throws -> String { reply }
}

private actor QueuedReplyProvider: PokemonChatProviding {
    private var continuations: [CheckedContinuation<String, Error>] = []
    func reply(to request: PokemonChatRequest) async throws -> String {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func resolve(with reply: String) { guard !continuations.isEmpty else { return }; continuations.removeFirst().resume(returning: reply) }
}

private extension PokemonChatProfile {
    static var fixture: PokemonChatProfile { fixture(nickname: nil) }
    static func fixture(nickname: String?) -> PokemonChatProfile {
        PokemonChatProfile(speciesID: 1, displayName: "이상해씨", nickname: nickname,
                           nature: "온순", level: 5, stage: "첫 번째 형태",
                           flavorText: "태어날 때부터 등에 이상한 씨앗이 자란다.", language: .ko)
    }
}
