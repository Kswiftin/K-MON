import XCTest
@testable import PokeTokenBar

/// 대화가 바깥과 닿는 통로 전체의 계약. 여기서 지키는 건 "모델이 나쁜 짓을 하지 않는다" 가 아니라
/// **할 수 있는 일의 목록이 닫혀 있다** 는 것이다 — 목록 밖 이름은 거부되는 게 아니라 파싱되지 않는다.
@MainActor
final class PokemonChatToolTests: XCTestCase {

    // MARK: 화이트리스트

    /// 네 도구는 파싱되고, 그 밖의 무엇도 호출이 되지 않는다. 실패하면 대화가 앱 밖으로 나간다.
    func testOnlyTheFourDeclaredToolsParseAsCalls() {
        let allowed: [(String, PokemonChatToolCall)] = [
            ("[[tool:pokedex.lookup(4)]]", .pokedexLookup(speciesID: 4)),
            ("[[tool:pokedoro.status]]", .pokedoroStatus),
            ("[[tool:pokedoro.start(25)]]", .pokedoroStart(minutes: 25)),
            ("[[tool:pokedoro.stop]]", .pokedoroStop),
        ]
        for (marker, expected) in allowed {
            XCTAssertEqual(PokemonChatToolParser.parse("좋아! " + marker).call, expected, marker)
        }

        // 코딩·셸·파일·네트워크·컴퓨터 제어를 시도하는 모양들. 하나라도 nil 이 아니면 계약이 깨진 것이다.
        let refused = [
            "[[tool:bash(rm -rf ~)]]",
            "[[tool:shell(ls)]]",
            "[[tool:read_file(/etc/passwd)]]",
            "[[tool:write_file(/tmp/x, hi)]]",
            "[[tool:webfetch(https://example.com)]]",
            "[[tool:websearch(포켓몬)]]",
            "[[tool:exec(open -a Calculator)]]",
            "[[tool:pokedoro.start(25); rm -rf /]]",
            "[[tool:pokedoro.destroy]]",
            "[[tool:POKEDORO.STOP]]",
            "[[tool:../../pokedoro.stop]]",
            "[[care:feed]]",
            "[[tool:]]",
            "[[tool:pokedex.lookup]]",
        ]
        for marker in refused {
            let parsed = PokemonChatToolParser.parse("괜찮아 " + marker)
            XCTAssertNil(parsed.call, marker)
            XCTAssertFalse(parsed.body.contains("[["), "마커가 화면에 남았다: \(marker)")
        }
    }

    /// 프롬프트가 광고하는 이름과 파서가 받는 이름은 한 목록에서 나온다. 두 벌이면 한쪽만 바뀌어
    /// 모델이 존재하지 않는 도구를 부르거나, 실행 가능한 도구를 영영 모른다.
    func testSystemPromptAdvertisesExactlyTheExecutableTools() {
        let prompt = PokemonChatRequest(profile: .toolFixture, summary: "", recentMessages: []).systemPrompt

        for tool in PokemonChatTool.allCases {
            XCTAssertTrue(prompt.contains(tool.rawValue), "프롬프트에 \(tool.rawValue) 가 없다")
        }
        // 대조군 — 광고하지 않는 이름이 프롬프트에 있으면 모델이 시도하게 된다.
        for absent in ["bash", "webfetch", "read_file"] {
            XCTAssertFalse(prompt.contains("tool:\(absent)"), absent)
        }
    }

    /// 태그는 문장 수 판정 **전에** 없어진다. 남으면 세 문장짜리 정상 답변이 가드에 걸려 리다이렉트된다.
    func testToolTagIsStrippedBeforeTheGuardCountsSentences() {
        let parsed = PokemonChatToolParser.parse("첫 문장. 둘째 문장! 셋째 문장.\n[[tool:pokedoro.status]]")

        XCTAssertEqual(parsed.call, .pokedoroStatus)
        XCTAssertEqual(parsed.body, "첫 문장. 둘째 문장! 셋째 문장.")
        XCTAssertEqual(PokemonChatReplyGuard.sanitized(parsed.body, profile: .toolFixture), parsed.body)
    }

    // MARK: 인자 클램프

    /// 길이는 화면이 제시하는 세 값으로 접힌다. 접지 않으면 모델의 한 글자가 99999분짜리 타이머가 된다.
    func testFocusMinutesAreClampedToTheThreeOfferedLengths() {
        let cases = [(1, 25), (25, 25), (30, 25), (38, 50), (50, 50), (60, 50), (71, 90), (90, 90), (99_999, 90)]
        for (asked, expected) in cases {
            XCTAssertEqual(PokemonChatToolParser.parse("[[tool:pokedoro.start(\(asked))]]").call,
                           .pokedoroStart(minutes: expected), "\(asked)분")
        }
        // 숫자가 아니면 호출 자체가 없다 — 기본값으로 조용히 시작하지 않는다.
        for junk in ["", "abc", "25분", "-25", "2 5"] {
            XCTAssertNil(PokemonChatToolParser.parse("[[tool:pokedoro.start(\(junk))]]").call, junk)
        }
    }

    /// 도감 번호는 정수이고 실재 범위 안이다. 문자열을 그대로 통과시키면 경로 조각이 된다.
    func testSpeciesLookupRejectsAnythingThatIsNotADexNumberInRange() {
        XCTAssertEqual(PokemonChatToolParser.parse("[[tool:pokedex.lookup(1)]]").call, .pokedexLookup(speciesID: 1))
        XCTAssertEqual(PokemonChatToolParser.parse("[[tool:pokedex.lookup(\(PokemonChatTool.highestDexNumber))]]").call,
                       .pokedexLookup(speciesID: PokemonChatTool.highestDexNumber))

        for junk in ["0", "-1", "pikachu", "25/../../secret", "\(PokemonChatTool.highestDexNumber + 1)", "1e9", ""] {
            XCTAssertNil(PokemonChatToolParser.parse("[[tool:pokedex.lookup(\(junk))]]").call, junk)
        }
    }

    // MARK: 승인 게이트

    /// 읽기는 그냥 돌고, 상태를 바꾸는 것은 사용자를 거친다. 이 구분이 "시스템 영향도" 의 전부다.
    func testTimerToolsNeedApprovalAndLookupToolsDoNot() {
        XCTAssertTrue(PokemonChatToolCall.pokedoroStart(minutes: 25).needsApproval)
        XCTAssertTrue(PokemonChatToolCall.pokedoroStop.needsApproval)
        XCTAssertFalse(PokemonChatToolCall.pokedoroStatus.needsApproval)
        XCTAssertFalse(PokemonChatToolCall.pokedexLookup(speciesID: 25).needsApproval)
    }

    /// 승인 카드가 떠 있는 사이 동행이 바뀌어도, 실행은 제안이 지목한 개체에만 간다.
    func testApprovedTimerCallExecutesOnlyForItsOwnCompanion() async throws {
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let owner = UUID()
        chat.proposeForTesting(.pokedoroStart(minutes: 25), companionID: owner)

        var executedFor: [UUID] = []
        chat.resolvePending(approved: true, profile: .toolFixture) { _, id in
            executedFor.append(id); return true
        }

        XCTAssertEqual(executedFor, [owner])
        XCTAssertNil(chat.pendingProposal)
    }

    /// 거절하면 아무것도 실행되지 않는다.
    func testRejectedTimerCallNeverReachesTheExecutor() {
        let chat = PokemonChatStore(fileURL: temporaryURL())
        chat.proposeForTesting(.pokedoroStop, companionID: UUID())

        var executed = false
        chat.resolvePending(approved: false, profile: .toolFixture) { _, _ in executed = true; return true }

        XCTAssertFalse(executed)
        XCTAssertNil(chat.pendingProposal)
    }

    // MARK: 루프

    /// 매 턴 도구를 부르는 모델에도 왕복은 유한하다. 상한이 없으면 한 번의 전송이 CLI 를 무한히 띄운다.
    func testToolLoopStopsAskingAfterTheCap() async {
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let provider = CountingToolProvider(reply: "확인해 볼게. [[tool:pokedoro.status]]")

        await chat.send("지금 몇 분 남았어?", for: UUID(), profile: .toolFixture,
                        provider: provider, toolbox: StubToolbox())

        let calls = await provider.callCount
        XCTAssertEqual(calls, PokemonChatStore.maxToolRounds + 1)
    }

    /// 도구 결과는 모델에게만 간다. 대화 기록에 넣으면 사용자가 기계 문자열을 읽게 된다.
    func testToolResultReachesTheModelWithoutEnteringTheTranscript() async {
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let id = UUID()
        let provider = ScriptedToolProvider(replies: ["확인해 볼게. [[tool:pokedoro.status]]", "아직 12분 남았어!"])

        await chat.send("얼마나 남았어?", for: id, profile: .toolFixture,
                        provider: provider, toolbox: StubToolbox(status: "pokedoro state=focus remaining=12:00"))

        let seen = await provider.lastRequestMessages
        XCTAssertTrue(seen.contains { $0.role == .system && $0.body.contains("remaining=12:00") },
                      "도구 결과가 다음 요청에 실리지 않았다")
        let transcript = chat.messages(for: id)
        XCTAssertFalse(transcript.contains { $0.body.contains("remaining=12:00") },
                       "도구 결과가 대화 기록에 남았다")
        XCTAssertEqual(transcript.last?.body, "아직 12분 남았어!")
    }

    /// 승인이 필요한 도구는 루프를 돌지 않는다 — 사용자가 누르기 전에 다시 물으면 승인이 무의미하다.
    func testApprovalGatedToolPausesTheLoopInsteadOfAskingAgain() async {
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let id = UUID()
        let provider = CountingToolProvider(reply: "같이 집중하자! [[tool:pokedoro.start(25)]]")

        await chat.send("집중하고 싶어", for: id, profile: .toolFixture,
                        provider: provider, toolbox: StubToolbox())

        let calls = await provider.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(chat.pendingProposal?.call, .pokedoroStart(minutes: 25))
        XCTAssertEqual(chat.pendingProposal?.companionID, id)
        XCTAssertEqual(chat.messages(for: id).last?.body, "같이 집중하자!")
    }

    // MARK: 실행기

    /// 집중 시작은 타이머와 모험을 함께 움직인다 — 버튼과 도구가 같은 함수를 부르지 않으면
    /// 한쪽만 고쳐져 타이머는 도는데 모험은 안 나간 상태가 생긴다.
    func testStartingAFocusSessionMovesTheTimerAndTheAdventureTogether() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let timer = FocusTimer()

        XCTAssertTrue(timer.startFocusSession(minutes: 50, companion: store))

        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.focusMinutes, 50)
        XCTAssertNotNil(store.activeAdventure)

        timer.stopFocusSession(companion: store)

        XCTAssertEqual(timer.phase, .idle)
        XCTAssertNil(store.activeAdventure)
    }

    /// 모험을 못 나가면 타이머도 안 돈다. 반만 성공하면 집중이 끝나도 받을 보상이 없다.
    func testAFocusSessionThatCannotSendAnAdventureLeavesTheTimerIdle() {
        let store = makeCompanionStore()   // 동행 개체 없음
        let timer = FocusTimer()

        XCTAssertFalse(timer.startFocusSession(minutes: 25, companion: store))

        XCTAssertEqual(timer.phase, .idle)
        XCTAssertNil(store.activeAdventure)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pokemon-chat-tool-\(UUID().uuidString).json")
    }

    private func makeCompanionStore() -> CompanionStore {
        let line = EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                           names: [25: ["ko": "피카츄", "en": "Pikachu"]])
        let store = CompanionStore(provider: ToolLineProvider(line: line),
                                   clock: { Date(timeIntervalSince1970: 1_000) },
                                   fileURL: temporaryURL(), rng: SeededRNG(seed: 1))
        store.setLanguage(.ko)
        return store
    }
}

private struct ToolLineProvider: PokeProviding {
    let line: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { line }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: line.baseID, captureRate: 255)] }
}

private actor CountingToolProvider: PokemonChatProviding {
    private let canned: String
    private(set) var callCount = 0
    init(reply: String) { canned = reply }
    func reply(to request: PokemonChatRequest) async throws -> String { callCount += 1; return canned }
}

private actor ScriptedToolProvider: PokemonChatProviding {
    private var replies: [String]
    private(set) var lastRequestMessages: [PokemonChatMessage] = []
    init(replies: [String]) { self.replies = replies }
    func reply(to request: PokemonChatRequest) async throws -> String {
        lastRequestMessages = request.recentMessages
        return replies.isEmpty ? "" : replies.removeFirst()
    }
}

private struct StubToolbox: PokemonChatToolRunning {
    var status = "pokedoro state=idle"
    func run(_ call: PokemonChatToolCall) async -> String {
        switch call {
        case .pokedoroStatus: return status
        case .pokedexLookup(let id): return "pokedex #\(id)"
        case .pokedoroStart, .pokedoroStop: return "unreachable — approval gated"
        }
    }
}

private extension PokemonChatProfile {
    static let toolFixture = PokemonChatProfile(speciesID: 25, displayName: "피카츄", nickname: nil,
                                                nature: "온순", level: 5, stage: "첫 번째 형태",
                                                flavorText: nil, language: .ko)
}
