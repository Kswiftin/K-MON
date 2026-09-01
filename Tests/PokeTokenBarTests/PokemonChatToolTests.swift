import XCTest
@testable import PokeTokenBar

/// 대화가 바깥과 닿는 통로 전체의 계약. 여기서 지키는 건 "모델이 나쁜 짓을 하지 않는다" 가 아니라
/// **할 수 있는 일의 목록이 닫혀 있다** 는 것이다 — 목록 밖 이름은 거부되는 게 아니라 파싱되지 않는다.
@MainActor
final class PokemonChatToolTests: XCTestCase {

    // MARK: 화이트리스트

    /// 네 도구는 파싱되고, 그 밖의 무엇도 호출이 되지 않는다. 실패하면 대화가 앱 밖으로 나간다.
    func testOnlyTheDeclaredToolsParseAsCalls() {
        let allowed: [(String, PokemonChatToolCall)] = [
            ("[[tool:pokedex.lookup(4)]]", .pokedexLookup(speciesID: 4)),
            ("[[tool:pokedoro.status]]", .pokedoroStatus),
            ("[[tool:pokedoro.start(25)]]", .pokedoroStart(minutes: 25)),
            ("[[tool:pokedoro.stop]]", .pokedoroStop),
            ("[[tool:bag.list]]", .bagList),
            ("[[tool:roster.list]]", .rosterList),
            ("[[tool:item.use(rareCandy)]]", .itemUse(kind: .rareCandy)),
            ("[[tool:item.use(fireStone)]]", .itemUse(kind: .fireStone)),
            ("[[tool:evolution.accept]]", .evolutionAccept),
            ("[[tool:companion.switch(0)]]", .companionSwitch(index: 0)),
            ("[[tool:memory.record]]", .memoryRecord(body: "")),
            ("[[tool:adventure.claim]]", .adventureClaim),
            ("[[tool:dex.progress]]", .dexProgress),
            ("[[tool:challenge.status]]", .challengeStatus),
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
            // 새 도구가 목록을 넓힌 만큼, 그 이름 주변의 목록 밖도 다시 확인한다.
            "[[tool:item.use(bash)]]",              // ItemKind 밖 이름
            "[[tool:item.use(/bin/sh)]]",           // 경로 조각
            "[[tool:item.use()]]",                  // 빈 인자
            "[[tool:item.use]]",                    // 인자 없는 소모 요구
            "[[tool:companion.switch(-1)]]",        // 음수 인덱스
            "[[tool:companion.switch(abc)]]",       // 숫자가 아닌 인덱스
            "[[tool:companion.switch]]",            // 누구로 바꿀지 없는 교체
            "[[tool:evolution.accept(1)]]",         // 인자를 받지 않는 도구
            "[[tool:memory.record(내가 정한 기억)]]",   // 임의 문자열 인자
            "[[tool:bag.list(all)]]",
            "[[tool:roster.list(1)]]",
            "[[tool:memory.delete]]",               // 지우는 도구는 존재하지 않는다
            "[[tool:companion.release(0)]]",        // 놓아 주기는 도구가 아니다
            "[[tool:shop.buy(rareCandy)]]",         // 소비는 도구가 아니다
            "[[tool:adventure.claim(1)]]",          // 인자를 받지 않는 도구
            "[[tool:adventure.start(25)]]",         // 모험은 집중과 함께만 나간다 — 따로 보내는 도구는 없다
            "[[tool:adventure.cancel]]",            // 취소는 pokedoro.stop 뿐이다
            "[[tool:egg.hatch]]",                   // 알 품기는 동행을 밀어낸다 — 도구가 아니다
            "[[tool:companion.graduate]]",          // 졸업은 되돌릴 수 없다
            "[[tool:settings.doNotDisturb(true)]]", // 화면 설정은 대화가 바꾸지 않는다
            "[[tool:companion.nickname(피카)]]",      // 임의 문자열 인자
            "[[tool:dex.progress(species)]]",       // 인자를 받지 않는 도구
            "[[tool:challenge.status(gym)]]",       // 인자를 받지 않는 도구
            "[[tool:dungeon.enter]]",               // 던전 입장은 맵 이동이다 — 도구가 아니다
            "[[tool:gym.challenge(1)]]",            // 체육관 도전은 배틀 화면을 띄운다
            "[[tool:trade.offer(0)]]",              // 교환은 남이 개입한다
            "[[tool:battle.challenge(0)]]",         // 대전도 마찬가지다
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

    /// 태그는 가드가 본문을 보기 **전에** 없어진다. 남으면 마커의 백틱·`tool` 이 역할 이탈로
    /// 세어져 정상 답변이 캔 문구로 갈아치워진다.
    func testToolTagIsStrippedBeforeTheGuardSeesTheBody() {
        let parsed = PokemonChatToolParser.parse("첫 문장. 둘째 문장! 셋째 문장.\n[[tool:pokedoro.status]]")

        XCTAssertEqual(parsed.call, .pokedoroStatus)
        XCTAssertEqual(parsed.body, "첫 문장. 둘째 문장! 셋째 문장.")
        XCTAssertEqual(PokemonChatReplyGuard.sanitized(parsed.body, profile: .toolFixture).text, parsed.body)
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
    func testEveryToolThatSpendsOrChangesSomethingNeedsApproval() {
        for call: PokemonChatToolCall in [.pokedoroStart(minutes: 25), .pokedoroStop,
                                          .itemUse(kind: .rareCandy), .itemUse(kind: .fireStone),
                                          .evolutionAccept, .companionSwitch(index: 0),
                                          // 정산은 지갑·경험치를 움직이고, 경험치가 진화·기술 카드를 띄운다.
                                          .adventureClaim] {
            XCTAssertTrue(call.needsApproval, "\(call) 는 승인 없이 상태를 바꾼다")
        }
        for call: PokemonChatToolCall in [.pokedoroStatus, .pokedexLookup(speciesID: 25),
                                          .bagList, .rosterList, .dexProgress, .challengeStatus] {
            XCTAssertFalse(call.needsApproval, "\(call) 는 읽기인데 승인을 요구한다")
        }
        // 기억하기만 예외다. 저장되는 건 사용자가 화면에서 이미 읽은 문장뿐이고, 승인을 붙이면
        // 매 대화가 카드로 끊긴다. 근거는 docs/reference/chat-tool-sandbox.md.
        XCTAssertFalse(PokemonChatToolCall.memoryRecord(body: "오늘 같이 집중했어").needsApproval)
    }

    /// 승인 카드가 떠 있는 사이 동행이 바뀌어도, 실행은 제안이 지목한 개체에만 간다.
    func testApprovedTimerCallExecutesOnlyForItsOwnCompanion() async throws {
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let owner = UUID()
        chat.proposeForTesting(.pokedoroStart(minutes: 25), companionID: owner)

        var executedFor: [UUID] = []
        await chat.resolvePending(approved: true, profile: .toolFixture) { _, id in
            executedFor.append(id); return true
        }

        XCTAssertEqual(executedFor, [owner])
        XCTAssertNil(chat.pendingProposal)
    }

    /// 거절하면 아무것도 실행되지 않는다.
    func testRejectedTimerCallNeverReachesTheExecutor() async {
        let chat = PokemonChatStore(fileURL: temporaryURL())
        chat.proposeForTesting(.pokedoroStop, companionID: UUID())

        var executed = false
        await chat.resolvePending(approved: false, profile: .toolFixture) { _, _ in executed = true; return true }

        XCTAssertFalse(executed)
        XCTAssertNil(chat.pendingProposal)
    }

    /// 승인 카드와 결과 문구는 세 언어 모두에서 사람 문장이다. enum 슬러그가 새면 사용자는
    /// 자기가 무엇을 켜는지 모른 채 누르게 된다.
    func testApprovalTextIsHumanInEveryLanguageAndNeverLeaksASlug() {
        let slugs = Set(PokemonChatTool.allCases.map(\.rawValue))
        let calls: [PokemonChatToolCall] = [.pokedoroStart(minutes: 25), .pokedoroStop,
                                            .pokedoroStatus, .pokedexLookup(speciesID: 25),
                                            .bagList, .rosterList, .evolutionAccept,
                                            .itemUse(kind: .rareCandy), .companionSwitch(index: 2),
                                            .memoryRecord(body: "오늘 같이 집중했어")]
        for language in [AppLanguage.ko, .en, .ja] {
            var lines: [String] = []
            for call in calls {
                lines.append(call.approvalQuestion(language))
                lines.append(call.outcome(approved: true, success: true, language: language))
                lines.append(call.outcome(approved: true, success: false, language: language))
                lines.append(call.outcome(approved: false, success: false, language: language))
            }
            XCTAssertFalse(lines.contains { $0.isEmpty }, "\(language.rawValue) 에 빈 문구가 있다")
            XCTAssertFalse(lines.contains { line in slugs.contains(where: line.contains) },
                           "\(language.rawValue): \(lines)")
        }

        // 승인·거절·실패는 서로 다른 문장이어야 한다 — 같으면 눌러도 무슨 일이 났는지 알 수 없다.
        let start = PokemonChatToolCall.pokedoroStart(minutes: 25)
        XCTAssertEqual(Set([start.outcome(approved: true, success: true, language: .ko),
                            start.outcome(approved: true, success: false, language: .ko),
                            start.outcome(approved: false, success: false, language: .ko)]).count, 3)
        // 실제 인자가 문장에 실린다 — 25분 승인이 50분을 켜는 걸 사용자가 볼 수 있어야 한다.
        XCTAssertTrue(PokemonChatToolCall.pokedoroStart(minutes: 50).approvalQuestion(.ko).contains("50"))
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

    /// 마지막 왕복에서는 도구를 돌리지 않는다 — 결과를 전할 턴이 남지 않은 실행은 부작용만 남긴다.
    /// (상한 자체는 위 테스트가 지킨다. 이건 "상한에 걸린 턴에 무엇을 하는가" 라는 다른 성질이다.)
    func testTheLastRoundDoesNotRunAToolItCannotReportBack() async {
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let toolbox = CountingToolbox()

        await chat.send("계속 확인해 줘", for: UUID(), profile: .toolFixture,
                        provider: CountingToolProvider(reply: "확인할게. [[tool:pokedoro.status]]"),
                        toolbox: toolbox)

        XCTAssertEqual(toolbox.runCount, PokemonChatStore.maxToolRounds)
    }

    /// 마지막 왕복에서 모델이 **마커만** 적으면 본문이 빈다. 그 빈 문장이 앞선 턴에 한 말을 지워서
    /// 사용자는 자기 질문에 대한 답 대신 캔 문구를 받았다 — 모델은 말을 했는데 화면엔 안 남는다.
    ///
    /// 상한 테스트들이 이걸 못 걸렀다: 둘 다 **본문이 있는** 응답만 반복해서, 빈 본문 경로를
    /// 한 번도 밟지 않았다.
    func testTheModelsWordsSurviveALastRoundThatIsMarkerOnly() async {
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let id = UUID()
        let provider = ScriptedToolProvider(replies:
            ["잠깐 확인해 볼게! [[tool:pokedoro.status]]"]
            + Array(repeating: "[[tool:pokedoro.status]]", count: PokemonChatStore.maxToolRounds))

        await chat.send("지금 기분은 어때?", for: id, profile: .toolFixture,
                        provider: provider, toolbox: StubToolbox())

        let last = chat.messages(for: id).last { $0.role == .pokemon }
        XCTAssertEqual(last?.body, "잠깐 확인해 볼게!", "모델이 한 말이 빈 턴에 지워졌다")
    }

    /// 끝까지 아무 말도 안 왔을 때의 문구는 **질문을 모른다고 하지 않는다.** "그건 잘 모르겠어" 는
    /// 사용자의 질문을 못 알아들었다는 뜻이 되는데, 실제로 벌어진 일은 모델의 침묵이다.
    func testTotalSilenceGetsARetryInvitationNotAnIDontKnow() async {
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let id = UUID()
        let provider = ScriptedToolProvider(replies:
            Array(repeating: "[[tool:pokedoro.status]]", count: PokemonChatStore.maxToolRounds + 1))

        await chat.send("나랑 끝말잇기 하자", for: id, profile: .toolFixture,
                        provider: provider, toolbox: StubToolbox())

        let last = chat.messages(for: id).last { $0.role == .pokemon }
        XCTAssertNotNil(last)
        XCTAssertFalse(last?.body.isEmpty ?? true, "빈 답변이 그대로 남았다")
        XCTAssertFalse(last?.body.contains("잘 모르겠") ?? true,
                       "침묵을 '질문을 모르겠다' 로 바꿔 말한다: \(last?.body ?? "")")
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

    // MARK: 실물 실행기

    /// 상태 문자열은 타이머가 **실제로 움직인 결과**를 읽는다 — 요청한 값을 되읽으면 실행이
    /// 실패해도 성공처럼 보인다.
    func testTheToolboxReportsTheTimerStateItActuallyMoved() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let timer = FocusTimer()
        let toolbox = PokemonChatToolbox(timer: timer, companion: store, album: makeAlbum(), lookup: Self.emptyLookup)

        let idle = await toolbox.runAsActive(.pokedoroStatus)
        XCTAssertTrue(idle.line.contains("state=idle"), idle.line)

        let started = await toolbox.runAsActive(.pokedoroStart(minutes: 50))
        XCTAssertTrue(started.succeeded)
        XCTAssertTrue(started.line.contains("state=focus"), started.line)
        XCTAssertEqual(timer.focusMinutes, 50)
        XCTAssertNotNil(store.activeAdventure)

        let stopped = await toolbox.runAsActive(.pokedoroStop)
        XCTAssertTrue(stopped.succeeded)
        XCTAssertTrue(stopped.line.contains("state=idle"), stopped.line)
        XCTAssertNil(store.activeAdventure)
    }

    /// 시작 거절은 상태 문자열이 아니라 거절로 보여야 하고, **사유가 실려야** 한다. 뭉개면 모델이
    /// 왜 안 되는지 모른 채 같은 호출을 반복하고, 사용자에게는 아무 일도 안 난 것으로 보인다.
    /// 나와 있는 개체가 없는 경우가 그 첫 사유다.
    func testTheToolboxSaysWhyAFocusSessionCannotStart() async {
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: makeCompanionStore(),
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        // owner 를 직접 넘긴다 — `runAsActive` 의 `?? UUID()` 폴백에 기대면 "활성으로 실행" 이
        // 조용히 "남으로 실행" 이 되어, 무엇을 시험하는지가 헬퍼에 숨는다.
        let refused = await toolbox.run(.pokedoroStart(minutes: 25), owner: UUID())
        XCTAssertFalse(refused.succeeded, "거절이 성공으로 보고되면 승인 카드가 실패를 침묵으로 만든다")
        XCTAssertEqual(refused.line, "tool refused: no active companion")
    }

    /// 도감 조회는 받은 사실만 싣는다. 빈 조회를 빈 줄로 돌려주면 모델이 침묵을 사실로 읽는다.
    func testTheToolboxTurnsASpeciesLookupIntoFactsOrSaysItHasNone() async {
        let store = makeCompanionStore()
        let full = PokemonChatToolbox(timer: FocusTimer(), companion: store, album: makeAlbum()) { _, language in
            PokemonSpeciesIdentity(genera: ["ko": "쥐포켓몬"], habitatSlug: "forest",
                                   flavorTexts: ["ko": "전기를 볼에 저장한다."],
                                   abilityNames: ["ko": "정전기"], abilityTexts: [:], language: language)
        }

        let found = await full.runAsActive(.pokedexLookup(speciesID: 25))
        XCTAssertTrue(found.succeeded)
        XCTAssertTrue(found.line.contains("#25"), found.line)
        XCTAssertTrue(found.line.contains("genus=쥐포켓몬"), found.line)
        XCTAssertTrue(found.line.contains("habitat=숲"), found.line)
        XCTAssertTrue(found.line.contains("entry=전기를 볼에 저장한다."), found.line)

        let empty = PokemonChatToolbox(timer: FocusTimer(), companion: store, album: makeAlbum(), lookup: Self.emptyLookup)
        let blank = await empty.runAsActive(.pokedexLookup(speciesID: 999))
        XCTAssertFalse(blank.succeeded)
        XCTAssertEqual(blank.line, "pokedex #999 unavailable")
    }

    // MARK: 새 도구 — 실행

    /// 아이템은 종류마다 **다른 진짜 경로**로 간다. 여기서 인벤토리를 직접 깎으면 화면 버튼과
    /// 경로가 갈려 한쪽만 고쳐진다. 소모품·성격·진화·사용 불가를 각각 밟는다.
    func testItemUseRoutesEachKindToItsOwnStorePathAndReportsFailureHonestly() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        // 재고가 없으면 실패다 — 성공으로 뭉개면 모델이 "썼어" 라고 말한다.
        let broke = await toolbox.runAsActive(.itemUse(kind: .rareCandy))
        XCTAssertFalse(broke.succeeded, broke.line)

        store.debugAddItem(.rareCandy, 1)
        let candy = await toolbox.runAsActive(.itemUse(kind: .rareCandy))
        XCTAssertTrue(candy.succeeded, candy.line)
        XCTAssertEqual(store.itemCount(.rareCandy), 0, "진짜 사용 경로를 안 탔다")

        store.debugAddItem(.mint, 1)
        let mint = await toolbox.runAsActive(.itemUse(kind: .mint))
        XCTAssertTrue(mint.succeeded, mint.line)
        XCTAssertEqual(store.itemCount(.mint), 0)

        // 보유형(부적)은 대화에서 "지금 쓴다" 는 개념이 없다. 재고가 있어도 실패다.
        store.debugAddItem(.shinyCharm, 1)
        let charm = await toolbox.runAsActive(.itemUse(kind: .shinyCharm))
        XCTAssertFalse(charm.succeeded, charm.line)
        XCTAssertEqual(store.itemCount(.shinyCharm), 1, "쓸 수 없다고 해 놓고 소모했다")
    }

    /// 가방·로스터는 모델이 **되돌려 줄 수 있는 값**으로 찍힌다. 되돌려 줄 수 없는 값을 찍으면
    /// 모델이 그걸 인자로 써서 파싱에서 떨어지고, 사용자에겐 "아무 일도 안 일어남" 으로 보인다.
    ///
    /// 예전엔 여기서 현지화된 이름이 **떨어지는 것**을 단언했다. 그게 같은 증상의 다른 얼굴이었다 —
    /// 액션 칩은 사람 문장("이상한 사탕 하나 써 줘")을 보내는데 모델은 그 문장에서 rawValue 를
    /// 알 길이 없어, 인자를 든 유일한 칩이 아무 일도 못 했다. 이제 둘 다 통한다.
    func testReadToolsPrintNamesTheModelCanHandBackAsArguments() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        store.debugAddItem(.fireStone, 2)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let bag = await toolbox.runAsActive(.bagList)
        XCTAssertTrue(bag.line.contains("fireStone=2"), bag.line)
        XCTAssertEqual(PokemonChatToolParser.parse("[[tool:item.use(fireStone)]]").call,
                       .itemUse(kind: .fireStone), "가방이 찍은 이름이 그대로 인자가 돼야 한다")
        XCTAssertEqual(PokemonChatToolParser.parse("[[tool:item.use(불꽃의돌)]]").call,
                       .itemUse(kind: .fireStone), "사용자가 부른 이름으로도 같은 아이템에 닿아야 한다")
        XCTAssertNil(PokemonChatToolParser.parse("[[tool:item.use(전설의 돌)]]").call,
                     "목록 밖 이름은 여전히 호출이 되지 않는다 — 닫힌 목록 대조지 추측이 아니다")

        let roster = await toolbox.runAsActive(.rosterList)
        XCTAssertTrue(roster.line.contains("index=0"), roster.line)
        XCTAssertTrue(roster.line.contains("active=true"), roster.line)
        // 도감·로스터 카드에 이로치 표식이 붙었는데 대화만 몰랐다. 개체를 알아보는 값이라 싣는다.
        var shiny = Self.spareMon()
        shiny.isShiny = true
        store.debugSetBoxedMons([shiny])
        let withShiny = await toolbox.runAsActive(.rosterList)
        XCTAssertTrue(withShiny.line.contains("shiny=true"), withShiny.line)
        XCTAssertTrue(withShiny.line.contains("shiny=false"), withShiny.line)
    }

    /// 인덱스는 파서가 아니라 **로스터를 아는 실행기**가 자른다. 범위 밖은 실패이고,
    /// 이미 나와 있는 개체로의 교체도 실패다 — 성공으로 보고하면 모델이 바뀌었다고 말한다.
    func testCompanionSwitchOnlyMovesToARealTeammate() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        for index in [999, 1] {   // 범위 밖 · 비어 있는 자리
            let result = await toolbox.runAsActive(.companionSwitch(index: index))
            XCTAssertFalse(result.succeeded, "index=\(index): \(result.line)")
        }
        // 0번은 지금 나와 있는 개체다. 자기 자신으로의 교체는 아무 일도 아니다.
        let noop = await toolbox.runAsActive(.companionSwitch(index: 0))
        XCTAssertFalse(noop.succeeded, noop.line)
    }

    /// 대기 중인 진화가 없으면 실패다. 이 분기를 성공으로 두면 모델이 매번 "진화했어" 라고 말한다.
    func testEvolutionAcceptFailsWhenNothingIsWaitingToEvolve() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let result = await toolbox.runAsActive(.evolutionAccept)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.line, "evolution none pending")
    }

    /// 기억은 **가드를 통과한 답변**으로만 남는다. 모델이 문구를 직접 정하면 그게 임의 문자열
    /// 인자이고, 다음 요청의 컨텍스트로 되돌아온다.
    func testMemoryRecordStoresTheGuardedReplyAndNeverAModelWrittenString() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let album = makeAlbum()
        let chat = PokemonChatStore(fileURL: temporaryURL(), album: album)
        let id = store.activeMonID!
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: album, lookup: Self.emptyLookup)

        // 모델이 기억 문구를 인자로 넣는 마커는 애초에 호출이 되지 않는다.
        XCTAssertNil(PokemonChatToolParser.parse("[[tool:memory.record(내가 정한 기억)]]").call)

        await chat.send("오늘 고마웠어", for: id, profile: .toolFixture,
                        provider: CountingToolProvider(reply: "나도 즐거웠어! [[tool:memory.record]]"),
                        toolbox: toolbox)

        XCTAssertEqual(album.entries(for: id).map(\.body), ["나도 즐거웠어!"],
                       "앨범에 남은 건 화면에 보인 문장 그대로여야 한다")
        // 빈 본문은 앨범에 빈 줄을 남긴다 — 스토어가 채우기 전에 실행되면 안 된다.
        let blank = await toolbox.runAsActive(.memoryRecord(body: "   "))
        XCTAssertFalse(blank.succeeded)
        XCTAssertEqual(album.entries(for: id).count, 1)
    }

    /// 기억하기는 왕복을 **하나도 더 쓰지 않는다.** 본문을 스토어가 나중에 채우므로 루프 안의
    /// 실행은 빈 본문으로 실패하고, 실패 한 줄을 모델에 돌려주며 남은 왕복(3회)을 전부 태운다.
    /// 그리고 모델이 다음 턴에 마커를 다시 붙이지 않으면 `call` 이 비어 **기억이 아예 안 남는다.**
    ///
    /// 위 테스트가 이걸 못 걸렀다: 같은 답변을 무한 반복하는 프로바이더라 마지막 턴에도 마커가
    /// 남아 있었다. 트리거는 "마커를 한 번만 붙이는 모델" 이라 답변을 갈아 주는 프로바이더가 필요하다.
    func testMemoryRecordCostsNoExtraRoundAndSurvivesAModelThatSaysItOnce() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let album = makeAlbum()
        let chat = PokemonChatStore(fileURL: temporaryURL(), album: album)
        let id = store.activeMonID!
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: album, lookup: Self.emptyLookup)

        await chat.send("오늘 고마웠어", for: id, profile: .toolFixture,
                        provider: ScriptedToolProvider(replies: ["나도 즐거웠어! [[tool:memory.record]]",
                                                                 "또 얘기해 줘!"]),
                        toolbox: toolbox)

        XCTAssertEqual(album.entries(for: id).map(\.body), ["나도 즐거웠어!"],
                       "왕복을 더 쓰는 동안 기억이 사라졌다")
        XCTAssertEqual(chat.messages(for: id).last?.body, "나도 즐거웠어!",
                       "기억하기 하나에 CLI 를 한 번 더 띄웠다")
    }

    /// 카드가 떠 있는 사이 조건이 무너지면 `acceptEvolution` 은 **카드만 지우고 조용히 돌아간다**
    /// (레벨·시간대 경로·요구 파티원·요구 기술·로드 안 된 진화 라인). 대기 여부만 보고 성공으로
    /// 돌려주면 모델이 "나, 진화했어!" 라고 말하고 형태는 그대로다.
    ///
    /// 위 진화 테스트가 이걸 못 걸렀다: 조건이 **맞는** 경로만 밟아서, 실행기가 결과를 확인하는지
    /// 대기 여부만 보는지가 구분되지 않았다.
    func testEvolutionThatSilentlyFailsIsNotReportedAsAccepted() async {
        let store = makeCompanionStore(line: Self.knownMoveGatedLine)
        await store.hatch(baseID: 40)
        // 기술 조건 진화는 그 기술을 들고 있을 때만 카드가 뜬다.
        store.debugSetActiveLearnedMoves([MoveSpec(id: 246, names: ["ko": "원시의힘"], type: .rock,
                                                   power: 60, damageClass: .special, accuracy: 100, pp: 5)])
        store.debugAccrueLevelExperience(300_000_000)
        store.applyUsage(0)
        XCTAssertNotNil(store.evolutionPrompt, "전제: 카드가 떠야 이 경로를 밟는다")
        // 카드가 떠 있는 사이 조건이 무너진다(기술을 잊었다). `acceptEvolution` 은 여기서
        // 카드만 지우고 조용히 돌아간다 — 시간대·요구 파티원 진화도 같은 분기다.
        store.debugSetActiveLearnedMoves([])
        let stageBefore = store.activeStageIndex

        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)
        let result = await toolbox.runAsActive(.evolutionAccept)

        XCTAssertEqual(store.activeStageIndex, stageBefore, "전제: 형태는 그대로여야 한다")
        XCTAssertFalse(result.succeeded, "진화하지 않았는데 성공으로 보고했다: \(result.line)")
    }

    /// 앨범이 **안 받은** 기억을 성공으로 돌려주면 모델이 "기억해 둘게" 라고 말하고 앨범엔 아무것도
    /// 없다. `PokemonMemoryAlbum.record` 는 180자를 넘는 본문을 조용히 버리는데 답변 가드는
    /// 500자까지 통과시킨다 — 그 사이 길이가 실제로 밟히는 구간이다.
    ///
    /// 빈 본문 케이스만 재던 것이 이걸 못 걸렀다: 실행기가 자기 가드(공백)만 확인하고 앨범의
    /// 가드(길이)는 확인하지 않아, 짧은 문장으로만 재면 두 가드가 같아 보였다.
    func testAMemoryTheAlbumRefusesIsNotReportedAsRecorded() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let album = makeAlbum()
        let id = store.activeMonID!
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: album, lookup: Self.emptyLookup)
        // 가드는 통과하고(상한 이하) 앨범은 거절하는(180자 초과) 길이.
        let long = String(repeating: "오", count: 200)
        XCTAssertEqual(PokemonChatReplyGuard.sanitized(long, profile: .toolFixture).text, long,
                       "전제: 이 길이는 답변 가드를 그대로 통과한다")

        let result = await toolbox.runAsActive(.memoryRecord(body: long))

        XCTAssertFalse(result.succeeded, "앨범이 버린 기억을 성공으로 보고했다")
        XCTAssertEqual(result.line, "memory not recorded")
        XCTAssertTrue(album.entries(for: id).isEmpty)
    }

    /// 여섯 번째 메시지에는 주기 기록이 붙는다. 모델이 같은 턴에 마커까지 달면 **같은 문장**이
    /// 앨범에 두 번 남는다 — `record` 는 대화 기억을 중복 제거하지 않는다(이벤트만 `eventID` 로 막는다).
    func testTheSixthMessageDoesNotRecordTheSameMemoryTwice() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let album = makeAlbum()
        let chat = PokemonChatStore(fileURL: temporaryURL(), album: album)
        let id = store.activeMonID!
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: album, lookup: Self.emptyLookup)
        let provider = CountingToolProvider(reply: "나도 즐거웠어! [[tool:memory.record]]")

        // 주기 기록은 `lifetimeUserMessageCount % 6 == 0` 에서만 돈다 — 여섯 번째 턴을 밟아야 한다.
        for turn in 1...6 {
            await chat.send("메시지 \(turn)", for: id, profile: .toolFixture, provider: provider, toolbox: toolbox)
        }

        XCTAssertEqual(album.entries(for: id).count, 6, "같은 문장이 앨범에 두 번 남았다")
    }

    /// 가드가 답변을 갈아치웠다면 그 답변이 딸고 온 기억도 사용자의 대화가 아니다.
    func testARedirectedReplyIsNeverKeptAsAMemory() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let album = makeAlbum()
        let chat = PokemonChatStore(fileURL: temporaryURL(), album: album)
        let id = store.activeMonID!
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: album, lookup: Self.emptyLookup)

        await chat.send("코드 짜 줘", for: id, profile: .toolFixture,
                        provider: CountingToolProvider(reply: "```swift\nprint(1)\n``` [[tool:memory.record]]"),
                        toolbox: toolbox)

        XCTAssertTrue(album.entries(for: id).isEmpty, "가드가 지운 답변이 기억으로 남았다")
    }

    // MARK: 새 도구 — 성공 경로
    //
    // 아래 넷은 커버리지 게이트(87.8%)를 통과하고도 `llvm-cov show --show-regions` 에서 `^0` 이던
    // 자리다. 실패 분기만 시험하면 "정말 그 일이 일어나는가" 는 한 번도 안 밟힌다.

    /// 진화 수락이 실제로 한 단계 올린다. 실패 분기만 지키면 "수락했지만 아무 일도 안 일어남" 이
    /// 통과한다 — 모델은 진화했다고 말하고 화면은 그대로다.
    func testEvolutionAcceptActuallyAdvancesTheStage() async {
        let store = makeCompanionStore(line: Self.levelGatedLine)
        await store.hatch(baseID: 40)
        store.debugAccrueLevelExperience(300_000_000)
        store.applyUsage(0)
        XCTAssertNotNil(store.evolutionPrompt, "전제: 프롬프트가 떠야 이 경로를 밟는다")
        let before = store.activeStageIndex

        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)
        let result = await toolbox.runAsActive(.evolutionAccept)

        XCTAssertTrue(result.succeeded, result.line)
        XCTAssertEqual(store.activeStageIndex, (before ?? 0) + 1, "수락했는데 형태가 그대로다")
        XCTAssertNil(store.evolutionPrompt)
    }

    /// 교체가 실제로 활성 개체를 바꾼다. 그리고 바뀐 뒤의 인덱스는 다시 `roster.list` 와 맞아야
    /// 한다 — 어긋나면 다음 교체가 엉뚱한 개체를 지목한다.
    func testCompanionSwitchActuallyChangesWhoIsOutAndRenumbersTheRoster() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let first = store.activeMonID!
        store.debugSetBoxedMons([MonState(baseID: 25, pathIDs: [25], plannedPathIDs: [25],
                                          stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)])
        let benched = store.chatRosterEntries.first { !$0.isActive }!
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let result = await toolbox.runAsActive(.companionSwitch(index: benched.index))

        XCTAssertTrue(result.succeeded, result.line)
        XCTAssertEqual(store.activeMonID, benched.id, "교체했는데 나와 있는 개체가 그대로다")
        XCTAssertEqual(store.chatRosterEntries.first { $0.isActive }?.index, 0,
                       "활성은 언제나 0번이어야 roster.list 와 companion.switch 가 같은 번호를 센다")
        XCTAssertTrue(store.chatRosterEntries.contains { $0.id == first && !$0.isActive })
    }

    /// 돌은 진짜로 진화시킨다 — `useEvolutionItem` 경로를 밟지 않으면 소모만 되고 형태는 그대로다.
    func testAnEvolutionStoneGoesThroughTheRealEvolutionPath() async {
        let store = makeCompanionStore(line: Self.stoneLine)
        await store.hatch(baseID: 30)
        store.debugAddItem(.fireStone, 1)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let result = await toolbox.runAsActive(.itemUse(kind: .fireStone))

        XCTAssertTrue(result.succeeded, result.line)
        XCTAssertEqual(store.itemCount(.fireStone), 0)
        XCTAssertEqual(store.activeStageIndex, 1, "돌을 썼는데 형태가 그대로다")
    }

    /// 하트비늘은 후보 카드를 여는 것까지다. 아직 기술이 바뀌지 않았으므로 **소모하지 않는다** —
    /// 여기서 소모로 보고하면 모델이 "기술을 바꿨어" 라고 말한다.
    func testAHeartScaleOnlyOpensTheRelearnChoicesAndSpendsNothingYet() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        store.debugAddItem(.heartScale, 1)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let result = await toolbox.runAsActive(.itemUse(kind: .heartScale))

        XCTAssertTrue(result.succeeded, result.line)
        XCTAssertEqual(store.itemCount(.heartScale), 1, "고르기도 전에 소모됐다")
    }

    // MARK: 누구의 대화인가
    //
    // 대화 창은 **박스 개체로도 열린다**(`PokemonRosterView`). 실행기는 `companion` 을 통째로
    // 들고 있어서 아무 방어가 없으면 모든 도구가 "지금 나와 있는 개체" 에 작용한다 — 사용자는
    // 박스 피카츄 창에서 승인하는데 활성 파이리가 사탕을 먹는다.

    /// 기억은 대화의 주인 앨범에 남아야 한다. 활성 개체 앨범에 적으면 이 창에서는 영영 안 보이고,
    /// 남의 앨범이 이 대화의 문장으로 오염된다.
    func testMemoryFromABoxedCompanionsChatLandsInThatCompanionsAlbum() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let active = store.activeMonID!
        let boxed = Self.spareMon()
        store.debugSetBoxedMons([boxed])
        let album = makeAlbum()
        let chat = PokemonChatStore(fileURL: temporaryURL(), album: album)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: album, lookup: Self.emptyLookup)

        await chat.send("잘 있었어?", for: boxed.id, profile: .toolFixture,
                        provider: CountingToolProvider(reply: "응, 잘 있었어! [[tool:memory.record]]"),
                        toolbox: toolbox)

        XCTAssertEqual(album.entries(for: boxed.id).map(\.body), ["응, 잘 있었어!"],
                       "대화의 주인 앨범에 안 남았다")
        XCTAssertTrue(album.entries(for: active).isEmpty, "남의 앨범에 적혔다")
    }

    /// 대상을 인자로 받지 않는 상태 변경 도구는 암시적으로 "지금 나와 있는 나" 에 작용한다.
    /// 그래서 활성 동행의 대화에서만 돈다 — 승인 카드가 가리키는 개체와 실행 대상이 같아야 한다.
    func testToolsThatActOnMeRefuseFromABoxedCompanionsChat() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let active = store.activeMonID!
        let boxed = Self.spareMon()
        store.debugSetBoxedMons([boxed])
        store.debugAddItem(.rareCandy, 1)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        for call: PokemonChatToolCall in [.itemUse(kind: .rareCandy), .pokedoroStart(minutes: 25),
                                          .pokedoroStop, .evolutionAccept, .adventureClaim] {
            let refused = await toolbox.run(call, owner: boxed.id)
            XCTAssertFalse(refused.succeeded, "\(call) 가 남의 대화에서 실행됐다: \(refused.line)")
        }
        XCTAssertEqual(store.itemCount(.rareCandy), 1, "남의 대화에서 사탕이 소모됐다")
        XCTAssertNil(store.activeAdventure, "남의 대화에서 모험이 나갔다")

        // 가드가 기능 자체를 죽이면 안 된다 — 활성 동행의 대화에서는 그대로 돈다.
        let allowed = await toolbox.run(.itemUse(kind: .rareCandy), owner: active)
        XCTAssertTrue(allowed.succeeded, allowed.line)
        XCTAssertEqual(store.itemCount(.rareCandy), 0)
    }

    /// 예외 둘을 못 박는다. 교체는 **인자로 대상을 지목**하므로 남의 대화에서도 뜻이 분명하고,
    /// 읽기 도구는 트레이너의 것이다. 가드를 뭉뚱그려 걸면 박스 개체가 "나를 데리고 나가줘" 라고
    /// 말할 수 없고, 도감 조회조차 창에 따라 막힌다.
    func testTargetedAndReadOnlyToolsStillWorkFromABoxedCompanionsChat() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let boxed = Self.spareMon()
        store.debugSetBoxedMons([boxed])
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)
        let benched = store.chatRosterEntries.first { !$0.isActive }!

        for call: PokemonChatToolCall in [.bagList, .rosterList, .pokedoroStatus,
                                          .dexProgress, .challengeStatus] {
            let read = await toolbox.run(call, owner: boxed.id)
            XCTAssertTrue(read.succeeded, "읽기가 남의 대화에서 막혔다: \(call)")
        }

        let switched = await toolbox.run(.companionSwitch(index: benched.index), owner: boxed.id)
        XCTAssertTrue(switched.succeeded, switched.line)
        XCTAssertEqual(store.activeMonID, benched.id)
    }

    /// 박스 개체 대화에서 승인한 호출도 **제안이 지목한 개체**로 실행된다. 스토어가 개체 ID 를
    /// 넘겨주는 것만으로는 부족하다 — 받는 쪽이 그 값을 실행에 쓰는지까지가 계약이다.
    func testApprovalPathCarriesTheProposalsCompanionIntoTheExecutor() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let boxed = Self.spareMon()
        store.debugSetBoxedMons([boxed])
        store.debugAddItem(.rareCandy, 1)
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)
        chat.proposeForTesting(.itemUse(kind: .rareCandy), companionID: boxed.id)

        // 프로덕션 뷰가 쓰는 것과 같은 모양의 실행기 — 개체 ID 를 버리면 이 테스트가 깨진다.
        await chat.resolvePending(approved: true, profile: .toolFixture) { call, owner in
            await toolbox.run(call, owner: owner).succeeded
        }

        XCTAssertEqual(store.itemCount(.rareCandy), 1, "남의 대화의 승인이 활성 개체에 적용됐다")
        XCTAssertEqual(chat.messages(for: boxed.id).last?.body,
                       PokemonChatToolCall.itemUse(kind: .rareCandy)
                           .outcome(approved: true, success: false, language: .ko),
                       "실패가 성공 문구로 보고됐다")
    }

    // MARK: 포케도로 — 모험 루프
    //
    // Pokedoro 의 상호작용은 타이머가 아니라 **모험**에 있다: 집중과 함께 나가고, 끝나면 사용자가
    // 정산해야 하고, 정산 전에는 다음 집중이 안 켜진다. 상태 문자열이 타이머만 보던 동안 대화는
    // 이 루프를 통째로 몰랐다 — 왜 시작이 막혔는지도, 보상이 기다리는지도 말할 수 없었다.

    /// 상태 한 줄이 모험과 알 재고까지 싣는다. 타이머만 보면 모델은 "12분 남았어" 밖에 못 하고,
    /// 정작 사용자가 눌러야 하는 "보상 받기" 를 영영 알려주지 못한다.
    func testTheStatusLineCarriesTheAdventureAndTheEggStash() async {
        let clock = TestClock()
        let store = makeCompanionStore(clock: clock)
        await store.hatch(baseID: 25)
        let timer = FocusTimer()
        let toolbox = PokemonChatToolbox(timer: timer, companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let idle = await toolbox.runAsActive(.pokedoroStatus)
        XCTAssertTrue(idle.line.contains("adventure=none"), idle.line)
        XCTAssertTrue(idle.line.contains("eggs=0"), idle.line)

        XCTAssertTrue(timer.startFocusSession(minutes: 50, companion: store))
        clock.advance(25 * 60)
        let running = await toolbox.runAsActive(.pokedoroStatus)
        XCTAssertTrue(running.line.contains("adventure=running"), running.line)
        XCTAssertTrue(running.line.contains("zone=cave"), running.line)
        XCTAssertTrue(running.line.contains("progress=50%"), running.line)

        // 끝났지만 아직 정산 안 된 상태가 사용자가 버튼을 눌러야 하는 바로 그 구간이다.
        clock.advance(25 * 60)
        let ready = await toolbox.runAsActive(.pokedoroStatus)
        XCTAssertTrue(ready.line.contains("adventure=ready"), ready.line)
    }

    /// 정산은 끝난 모험만 한다. 없는데 성공으로 돌려주면 모델이 "보상 받았어" 라고 말한다.
    func testAdventureClaimSettlesTheFinishedRunAndSaysSoWhenNothingIsWaiting() async {
        let clock = TestClock()
        let store = makeCompanionStore(clock: clock)
        await store.hatch(baseID: 25)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let nothing = await toolbox.runAsActive(.adventureClaim)
        XCTAssertFalse(nothing.succeeded)
        XCTAssertEqual(nothing.line, "adventure none ready")

        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        // 아직 나가 있는 모험은 정산되지 않는다 — 여기서 성공하면 모험 시간이 의미를 잃는다.
        let early = await toolbox.runAsActive(.adventureClaim)
        XCTAssertFalse(early.succeeded, early.line)
        XCTAssertNotNil(store.activeAdventure)

        clock.advance(25 * 60)
        let walletBefore = store.state.starPieces
        let claimed = await toolbox.runAsActive(.adventureClaim)

        XCTAssertTrue(claimed.succeeded, claimed.line)
        XCTAssertNil(store.activeAdventure, "정산했는데 모험 슬롯이 그대로다")
        XCTAssertGreaterThan(store.state.starPieces, walletBefore)
        // 돌려주는 줄이 지갑 증가분을 설명해야 한다 — 숫자가 없으면 모델이 액수를 지어낸다.
        XCTAssertTrue(claimed.line.contains("stardust=\(store.state.starPieces - walletBefore)"), claimed.line)
    }

    /// 시작이 막히는 두 사유를 갈라 준다. "refused" 한 줄이면 모델은 이유를 모른 채 같은 호출을
    /// 반복하고, 사용자에겐 침묵으로 보인다. 정산 대기 중에는 화면도 시작 버튼을 내주지 않는다.
    func testFocusStartRefusalNamesTheAdventureThatIsInTheWay() async {
        let clock = TestClock()
        let store = makeCompanionStore(clock: clock)
        await store.hatch(baseID: 25)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        XCTAssertTrue(store.startFocusAdventure(minutes: 90))
        let running = await toolbox.runAsActive(.pokedoroStart(minutes: 25))
        XCTAssertFalse(running.succeeded)
        XCTAssertEqual(running.line, "pokedoro start refused: adventure in progress")

        clock.advance(90 * 60)
        let unclaimed = await toolbox.runAsActive(.pokedoroStart(minutes: 25))
        XCTAssertFalse(unclaimed.succeeded)
        XCTAssertEqual(unclaimed.line, "pokedoro start refused: adventure reward unclaimed")
        XCTAssertNotNil(store.activeAdventure, "시작이 거절됐는데 모험이 조용히 정산됐다")
    }

    /// 종료 승인 카드는 **잃는 것**을 말해야 한다. 집중을 끝내면 모험이 보상 없이 취소되는데
    /// (`cancelFocusAdventure`), 카드가 "끝낼까?" 만 물으면 사용자는 무엇을 승인하는지 모른다.
    func testStoppingFocusWarnsThatTheAdventureIsLost() {
        let stop = PokemonChatToolCall.pokedoroStop
        for (language, word) in [(AppLanguage.ko, "모험"), (.en, "adventure"), (.ja, "冒険")] {
            XCTAssertTrue(stop.approvalQuestion(language).contains(word),
                          "\(language.rawValue): \(stop.approvalQuestion(language))")
        }
    }

    /// ...그리고 카드 문장이 **참이어야** 한다. `cancelFocusAdventure` 는 완료 여부를 안 봐서
    /// 정산 대기 구간(`FocusTimer` 는 저장되지 않으므로 앱을 닫았다 열면 타이머는 idle 이고 모험만
    /// 남는다)의 종료가 받을 수 있던 보상을 지웠다 — 화면은 그 구간에 취소 버튼을 아예 그리지
    /// 않는데 대화는 "진행 중인 모험은 취소돼" 라고 물어보고 완료된 모험을 태웠다.
    ///
    /// 두 분기를 **둘 다** 밟는다. 완료 쪽만 재면 "종료가 언제나 정산한다" 는 반대 결함(집중을
    /// 끊어도 보상이 나온다)이 그대로 통과한다.
    func testStoppingFocusSettlesAFinishedAdventureButStillCancelsARunningOne() async {
        let clock = TestClock()
        let store = makeCompanionStore(clock: clock)
        await store.hatch(baseID: 25)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        let beforeFinished = store.state.starPieces
        let finished = await toolbox.runAsActive(.pokedoroStop)

        XCTAssertTrue(finished.succeeded, finished.line)
        XCTAssertNil(store.activeAdventure)
        XCTAssertGreaterThan(store.state.starPieces, beforeFinished,
                             "정산을 기다리던 보상이 종료로 사라졌다")

        // 진행 중인 모험은 그대로 보상 없이 취소된다 — 그게 카드가 경고하는 바로 그 손실이다.
        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(5 * 60)
        let beforeRunning = store.state.starPieces
        _ = await toolbox.runAsActive(.pokedoroStop)

        XCTAssertNil(store.activeAdventure)
        XCTAssertEqual(store.state.starPieces, beforeRunning, "진행 중인 모험이 보상을 주고 취소됐다")
    }

    // MARK: 도감·도전 진행도

    /// 도감은 원복 이후 가장 크게 자랐는데(전체 종·타입 필터·미포획 실루엣·이로치·정렬) 대화는
    /// 진행도를 하나도 몰랐다. 세는 자리를 새로 만들지 않는다 — **보상이 읽는 목표 표**를 그대로
    /// 찍는다(`dexGoalRows`). 따로 세면 대화가 말하는 숫자와 보상이 주는 목표가 갈라진다.
    func testDexProgressPrintsTheSameLadderTheRewardsRead() async {
        let store = makeCompanionStore()
        store.debugSetDex([Self.dexEntry(chain: [1, 2, 3], types: [.grass, .poison], shiny: true)])
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let progress = await toolbox.runAsActive(.dexProgress)

        XCTAssertTrue(progress.succeeded, progress.line)
        // 종은 라인 전체를 센다(격자와 같은 단위), 타입은 최종체 타입 커버리지, 이로치는 개체 수.
        XCTAssertTrue(progress.line.contains("species=3/10"), progress.line)
        XCTAssertTrue(progress.line.contains("types=2/9"), progress.line)
        // 다음 칸을 함께 찍는다 — shiny1 을 넘었으므로 목표는 shiny3 이다.
        XCTAssertTrue(progress.line.contains("shiny=1/3"), progress.line)
    }

    /// 도전 탭(체육관·웨이브 런)은 혼자 하는 콘텐츠인데 대화가 못 봤다. 입장·도전은 넣지 않는다 —
    /// 맵 이동과 배틀 화면이 필요해 승인 카드 한 번이 감당할 무게가 아니다.
    ///
    /// 런은 판마다 새로 뽑혀 "오늘 갔나" 라는 셀 값이 없다. 그래서 오늘의 열림 상태 대신
    /// **누적 실적**(최고 웨이브·클리어 수)을 싣는다.
    func testChallengeStatusReportsTodaysDungeonBadgesAndMissions() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        store.debugSetLoadedTypes([.electric], speciesID: 25)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let status = await toolbox.runAsActive(.challengeStatus)

        XCTAssertTrue(status.succeeded, status.line)
        // 총량은 카탈로그에서 온다 — 숫자를 여기 적으면 콘텐츠가 늘 때 문구만 옛말이 된다.
        // 배지 진행도가 아니라 체육관 타입 수를 싣는다: 체육관이 보상 없는 콘텐츠가 되면서
        // "몇 개 땄나" 가 셀 값이 아니게 됐다.
        XCTAssertTrue(status.line.contains("gym_types=\(GymLeague.catalog.count)"), status.line)
        XCTAssertTrue(status.line.contains("missions=0/\(MissionBoard.catalog.count)"), status.line)
        XCTAssertTrue(status.line.contains("dungeon_best=0/\(RogueRun.finalWave)"), status.line)
        XCTAssertTrue(status.line.contains("dungeon_clears=0"), status.line)

        // 실적이 쌓인 분기를 직접 밟는다. 0 만 시험하면 라인 커버리지는 100% 로 통과하면서
        // 값이 실제로 실리는지는 한 번도 안 재게 된다.
        store.recordRunResult(reachedWave: RogueRun.finalWave, cleared: true)
        let after = await toolbox.runAsActive(.challengeStatus)
        XCTAssertTrue(after.line.contains("dungeon_clears=1"), after.line)
        XCTAssertTrue(after.line.contains("dungeon_best=\(RogueRun.finalWave)/\(RogueRun.finalWave)"),
                      after.line)
    }

    /// 성공할 수 없는 질문은 **카드로 띄우지 않는다.** 박스 개체 대화에서 집중 시작을 제안하면
    /// 실행기가 거절할 것이 처음부터 정해져 있다(주인 게이트) — 카드를 띄우면 사용자는 탭 한 번을
    /// 버리고 "지금은 그렇게 할 수 없어" 를 받는다. 대신 사유를 모델에 돌려줘 사람 말로 설명하게 한다.
    func testAnUnrunnableApprovalCallBecomesAReasonForTheModelNotACardForTheUser() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let boxed = Self.spareMon()
        store.debugSetBoxedMons([boxed])
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)
        let provider = ScriptedToolProvider(replies: ["같이 집중하자! [[tool:pokedoro.start(25)]]",
                                                      "아, 난 지금 박스에 있어서 같이 못 가."])

        await chat.send("집중하고 싶어", for: boxed.id, profile: .toolFixture,
                        provider: provider, toolbox: toolbox)

        XCTAssertNil(chat.pendingProposal, "될 수 없는 일을 카드로 물어봤다")
        XCTAssertEqual(chat.messages(for: boxed.id).last?.body, "아, 난 지금 박스에 있어서 같이 못 가.")
        let seen = await provider.lastRequestMessages
        XCTAssertTrue(seen.contains { $0.role == .system && $0.body.contains("not the active companion") },
                      "거절 사유가 모델에게 안 갔다 — 모델은 왜 안 되는지 모른 채 같은 호출을 반복한다")
        XCTAssertEqual(store.activeAdventure, nil, "거절했는데 모험이 나갔다")
    }

    /// 대조군 — 실행할 수 있는 승인 도구는 그대로 카드가 된다. 위 가드가 넓게 걸리면 승인 게이트
    /// 자체가 죽는데, 그건 "아무것도 못 하는 대화" 로만 드러나 테스트 없이는 안 보인다.
    func testARunnableApprovalCallStillBecomesACard() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let active = store.activeMonID!
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        await chat.send("집중하고 싶어", for: active, profile: .toolFixture,
                        provider: CountingToolProvider(reply: "같이 집중하자! [[tool:pokedoro.start(25)]]"),
                        toolbox: toolbox)

        XCTAssertEqual(chat.pendingProposal?.call, .pokedoroStart(minutes: 25))
        XCTAssertEqual(chat.pendingProposal?.companionID, active)
    }

    /// **접힌 답변은 갈아치워진 답변이 아니다.** 스토어는 `safeReply == reply` 로 "가드가 손댔나" 를
    /// 되묻는데, 길이 상한에 걸려 접히기만 해도 그 등식이 깨진다 — 사용자는 집중하자는 말을 읽고
    /// 승인 카드는 뜨지 않는다. 이 PR 의 논지가 "접기는 갈아치우기가 아니다" 인데 호출부가
    /// 옛 등식을 그대로 쓰고 있었다.
    func testAClippedReplyStillRaisesTheApprovalCardItCameWith() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let active = store.activeMonID!
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)
        let long = String(repeating: "같이 집중하자.", count: 100)
        XCTAssertGreaterThan(long.count, PokemonChatReplyGuard.maxLength, "전제: 이 본문은 접힌다")

        await chat.send("집중하고 싶어", for: active, profile: .toolFixture,
                        provider: CountingToolProvider(reply: long + " [[tool:pokedoro.start(25)]]"),
                        toolbox: toolbox)

        XCTAssertEqual(chat.pendingProposal?.call, .pokedoroStart(minutes: 25),
                       "길다는 이유만으로 승인 카드가 사라졌다")
    }

    /// 본문은 앞선 턴 것을 남기는데(빈 문장이 말을 지우지 못하게) `call` 은 **마지막 턴 것**을 받는다.
    /// 그래서 화면엔 "가방 볼게!" 가 남고 카드는 집중 타이머를 켤지 묻는다 — 승인은 사용자가 실제로
    /// 읽은 문장에 대한 것이어야 하고, 여긴 상태를 바꾸는 승인 경계다.
    ///
    /// 빈 본문 회귀 테스트가 이걸 못 걸렀다: 마지막 턴의 마커가 승인이 **필요 없는** 도구뿐이라
    /// 카드가 뜨는 조합을 한 번도 만들지 않았다.
    func testAnApprovalCardNeverAttachesToAnEarlierRoundsSentence() async {
        let chat = PokemonChatStore(fileURL: temporaryURL())
        let id = UUID()
        let provider = ScriptedToolProvider(replies: ["가방 볼게! [[tool:bag.list]]",
                                                      "[[tool:pokedoro.start(25)]]"])

        await chat.send("가방 좀 봐 줘", for: id, profile: .toolFixture,
                        provider: provider, toolbox: StubToolbox())

        XCTAssertEqual(chat.messages(for: id).last?.body, "가방 볼게!")
        XCTAssertNil(chat.pendingProposal,
                     "읽은 적 없는 제안이 카드로 떴다: \(String(describing: chat.pendingProposal?.call))")
    }

    /// 가드가 갈아치운 캔 문구는 **관계 기억이 아니다.** 주기 기록이 그걸 앨범에 남기면 이후 모든
    /// 요청에 `Relationship memory (conversation): …` 로 되먹임돼, 모델은 자기 오류 문구를
    /// 우리 추억으로 읽는다.
    ///
    /// 도구 경로(`memory.record`)만 막은 것이 이걸 못 걸렀다 — 아홉 줄 아래 형제 경로가 같은 규칙을
    /// 안 지켰고, 갈아치우기와 여섯 번째 턴을 **함께** 밟는 테스트가 없었다.
    func testAGuardReplacementIsNeverKeptAsThePeriodicMemory() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let album = makeAlbum()
        let chat = PokemonChatStore(fileURL: temporaryURL(), album: album)
        let id = store.activeMonID!
        let provider = CountingToolProvider(reply: "```swift\nprint(1)\n```")

        // 주기 기록은 `lifetimeUserMessageCount % 6 == 0` 에서만 돈다 — 여섯 번째 턴을 밟아야 한다.
        for turn in 1...6 {
            await chat.send("메시지 \(turn)", for: id, profile: .toolFixture,
                            provider: provider, toolbox: StubToolbox())
        }

        XCTAssertTrue(album.entries(for: id).isEmpty,
                      "캔 문구가 관계 기억으로 남았다: \(album.entries(for: id).map(\.body))")
    }

    /// 화면은 타이머가 도는 동안 시작 피커를 아예 안 그린다. 휴식 단계도 `isRunning` 이라 그 구간이
    /// 포함되는데, 모험은 이미 정산돼 `activeAdventure` 가 nil 이다 — 모험만 보던 게이트는 그
    /// 구간을 통과시켜 **휴식을 조용히 덮어썼다.**
    func testFocusStartRefusesWhileTheTimerIsAlreadyRunning() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let timer = FocusTimer()
        let toolbox = PokemonChatToolbox(timer: timer, companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)
        XCTAssertTrue(timer.startFocusSession(minutes: 25, companion: store))

        let duringFocus = await toolbox.runAsActive(.pokedoroStart(minutes: 50))
        XCTAssertFalse(duringFocus.succeeded)
        XCTAssertEqual(duringFocus.line, "pokedoro start refused: already in focus")
        XCTAssertEqual(timer.focusMinutes, 25, "돌고 있는 세션을 덮어썼다")

        // 휴식 단계 — 모험은 없고 타이머만 돈다. 모험만 보는 게이트는 여기를 못 막는다.
        timer.stopFocusSession(companion: store)
        timer.startRest()
        XCTAssertNil(store.activeAdventure, "전제: 휴식 구간엔 나가 있는 모험이 없다")

        let duringRest = await toolbox.runAsActive(.pokedoroStart(minutes: 25))
        XCTAssertFalse(duringRest.succeeded)
        XCTAssertEqual(duringRest.line, "pokedoro start refused: already in rest")
        XCTAssertEqual(timer.phase, .rest, "휴식을 끊고 집중을 시작했다")
    }

    /// 아무것도 안 돌아가는데 "집중을 끝냈어. 수고했어!" 가 뜨면 그건 거짓이다. `FocusTimer` 는
    /// 저장되지 않으므로 앱을 다시 연 직후가 항상 이 상태다.
    func testStoppingRefusesWhenNothingIsRunning() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let refused = await toolbox.runAsActive(.pokedoroStop)

        XCTAssertFalse(refused.succeeded)
        XCTAssertEqual(refused.line, "pokedoro stop refused: nothing running")
    }

    /// 종료는 끝난 모험을 정산한다(`stopFocusSession`). 그러면 카드가 **정산도** 말해야 한다 —
    /// "취소돼" 만 적힌 카드를 승인했는데 지갑이 늘면, 사용자는 자기가 무엇을 승인했는지 모른다.
    /// 사후 문구가 아니라 카드에 적는 이유는, 승인 전에 알아야 승인의 뜻이 있기 때문이다.
    func testStopApprovalCardNamesBothTheSettlementAndTheCancellation() {
        let stop = PokemonChatToolCall.pokedoroStop
        // 낱말이 아니라 **뜻**을 단언한다. "보상 없이 취소돼" 에도 '보상'·'취소' 가 들어 있어,
        // 낱말만 보면 정산을 말하지 않는 옛 문구에서도 통과한다(실제로 그랬다).
        for (language, reward, loss) in [(AppLanguage.ko, "끝난 모험", "취소"),
                                         (.en, "finished", "cancel"), (.ja, "終わった", "取り消")] {
            let question = stop.approvalQuestion(language)
            XCTAssertTrue(question.contains(reward), "\(language.rawValue): \(question)")
            XCTAssertTrue(question.contains(loss), "\(language.rawValue): \(question)")
        }
    }

    // MARK: 제안 — 지금 성공할 수 있는 일
    //
    // 칩은 "무엇을 시킬 수 있는가" 를 화면에서 답한다. 그래서 제안 목록은 **실행 가능성의
    // 부분집합**이어야 한다 — 조건표가 두 벌이 됐으니, 갈라지는 순간 빨개지는 자리가 필요하다.

    /// **이 절의 핵심 가드.** 제안한 것은 그 상태에서 실행하면 거절당하지 않는다.
    ///
    /// 방향은 한쪽만 고정한다: 제안 ⊆ 실행 가능. 반대("실행 가능하면 반드시 제안한다")는 일부러
    /// 걸지 않는다 — 화면(`FocusTimerView`)이 버튼을 안 그리는 구간까지 대화만 넓게 제안하면
    /// "화면이 못 하는 일을 대화만 할 수 있다" 부류가 되돌아온다(`already in rest` 결함과 같다).
    /// 덜 제안하는 건 조용하고, 더 제안하는 건 거짓 약속이다.
    ///
    /// 상태마다 실행기를 **새로 만든다** — 실행이 상태를 바꾸므로 한 벌로 돌리면 두 번째 액션이
    /// 첫 번째가 바꿔 놓은 세계에서 판정된다.
    func testEverySuggestedActionSurvivesTheExecutorsGuards() async {
        for (name, build) in Self.suggestionStates {
            let probe = await build(self)
            let suggested = probe.toolbox.availableActions(owner: probe.owner)
            XCTAssertFalse(suggested.isEmpty, "\(name): 제안이 하나도 없어 이 상태는 아무것도 검증하지 않는다")

            for action in suggested {
                let fresh = await build(self)
                let result = await fresh.toolbox.run(action.call, owner: fresh.owner)
                XCTAssertTrue(result.succeeded,
                              "\(name): \(action) 를 제안해 놓고 실행이 거절했다 — \(result.line)")
            }
        }
    }

    /// 상태마다 무엇이 뜨는지. 위 가드는 "거짓 약속이 없다" 만 지키므로, 칩이 통째로 사라져도
    /// (`availableActions` 가 늘 빈 배열이어도) 통과한다 — 실제로 제안이 일어나는지는 여기서 본다.
    func testSuggestionsFollowTheFocusAndAdventureLoop() async {
        let clock = TestClock()
        let store = makeCompanionStore(clock: clock)
        await store.hatch(baseID: 25)
        let timer = FocusTimer()
        let toolbox = PokemonChatToolbox(timer: timer, companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)
        let owner = store.activeMonID!

        XCTAssertEqual(toolbox.availableActions(owner: owner), [.startFocus],
                       "멈춰 있을 때 제안할 것은 시작뿐이다")

        XCTAssertTrue(timer.startFocusSession(minutes: 25, companion: store))
        XCTAssertEqual(toolbox.availableActions(owner: owner), [.stopFocus],
                       "집중 중에 시작을 제안하면 실행기가 거절한다")

        clock.advance(25 * 60)
        timer.stop()
        XCTAssertEqual(toolbox.availableActions(owner: owner), [.claimAdventure],
                       "정산을 기다리는 구간에서 보상 받기를 못 가리키면 사용자는 눌러야 할 것을 모른다")

        store.debugAddItem(.rareCandy, 1)
        XCTAssertEqual(toolbox.availableActions(owner: owner), [.claimAdventure, .useRareCandy],
                       "가방에 사탕이 있으면 아이템도 제안한다")
    }

    /// 칩 줄의 1Hz 시계는 **깨울 것이 있을 때만** 돈다. `@Observable` 이 깨우는 건 상태가 바뀔
    /// 때뿐이고, 제안 술어 중 시계를 읽는 건 `isAdventureInProgress` 하나다(`clock()`) — 나머지는
    /// 전부 상태 변화로 깨어난다. 상시로 돌리면 팝오버를 열어 둔 내내 초당 한 번씩 칩 목록과
    /// 프로필이 다시 만들어지고, 프로필 한 번이 박스 전체 배열 한 벌이다.
    ///
    /// 반대 방향도 같이 건다 — 필요할 때 껐으면 모험이 끝나는 순간을 넘긴 채 "보상 받기" 칩이
    /// 영영 안 뜬다(`FocusTimerView` 가 같은 술어를 같은 이유로 깨운다).
    func testTheChipRowOnlyNeedsAClockWhileAnAdventureCanFinish() async {
        let clock = TestClock()
        let store = makeCompanionStore(clock: clock)
        await store.hatch(baseID: 25)
        let timer = FocusTimer()
        let toolbox = PokemonChatToolbox(timer: timer, companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        XCTAssertFalse(toolbox.needsWallClockTicker,
                       "모험이 없는데 초당 한 번씩 칩 줄을 다시 그린다")

        XCTAssertTrue(timer.startFocusSession(minutes: 25, companion: store))
        XCTAssertTrue(toolbox.needsWallClockTicker,
                      "모험 중에 시계를 끄면 끝나는 순간을 넘겨 '보상 받기' 가 영영 안 뜬다")

        clock.advance(25 * 60)
        timer.stop()
        XCTAssertTrue(toolbox.needsWallClockTicker, "정산을 기다리는 구간에서도 시계는 살아 있어야 한다")
    }

    /// 사탕이 없으면 제안하지 않는다 — "가방에 없다" 는 정직한 실패지만, 화면이 먼저 권해 놓고
    /// 실패시키는 건 다른 이야기다.
    func testAnEmptyBagSuggestsNoItem() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        XCTAssertFalse(toolbox.availableActions(owner: store.activeMonID!).contains(.useRareCandy))
        store.debugAddItem(.rareCandy, 1)
        XCTAssertTrue(toolbox.availableActions(owner: store.activeMonID!).contains(.useRareCandy))
    }

    /// 진화 대기는 제안이 된다. 카드가 뜨기를 기다리는 동안 대화가 그 길을 가리킬 수 있어야 한다.
    func testAPendingEvolutionIsSuggested() async {
        let store = makeCompanionStore(line: Self.levelGatedLine)
        await store.hatch(baseID: 40)
        store.debugAccrueLevelExperience(300_000_000)
        store.applyUsage(0)
        XCTAssertNotNil(store.evolutionPrompt, "전제: 프롬프트가 떠야 이 경로를 밟는다")
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        XCTAssertTrue(toolbox.availableActions(owner: store.activeMonID!).contains(.acceptEvolution))
    }

    /// 카드가 뜬 뒤 조건이 무너지면 제안도 함께 사라져야 한다. 실행기는 이미 이 상태를 거절하는데
    /// (`testEvolutionThatSilentlyFailsIsNotReportedAsAccepted`), 제안이 남으면 앱이 권한 대로
    /// 누른 사용자가 **진화 카드를 잃는다** — `acceptEvolution` 은 조건이 안 맞으면 카드만 지운다.
    func testAnEvolutionWhoseConditionsCollapsedIsNoLongerSuggested() async {
        let store = makeCompanionStore(line: Self.knownMoveGatedLine)
        await store.hatch(baseID: 40)
        let move = MoveSpec(id: 246, names: ["ko": "원시의힘"], type: .rock,
                            power: 60, damageClass: .special, accuracy: 100, pp: 5)
        store.debugSetActiveLearnedMoves([move])
        store.debugAccrueLevelExperience(300_000_000)
        store.applyUsage(0)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)
        XCTAssertTrue(toolbox.availableActions(owner: store.activeMonID!).contains(.acceptEvolution),
                      "대조군: 조건이 맞을 때는 제안돼야 아래 단언이 뜻을 가진다")

        store.debugSetActiveLearnedMoves([])

        XCTAssertNotNil(store.evolutionPrompt, "전제: 카드는 아직 떠 있다 — 무너진 건 조건뿐이다")
        XCTAssertFalse(toolbox.availableActions(owner: store.activeMonID!).contains(.acceptEvolution),
                       "실행하면 카드를 잃을 진화를 제안했다")
    }

    /// 휴식 단계는 **끝낼 집중이 아니다.** `isRunning` 은 `phase != .idle` 이라 휴식에서도 참인데,
    /// 그 값으로 제안하면 쉬는 중에 "집중을 끝내자" 칩이 뜨고 승인 카드는 "끝난 모험 보상은 챙기고,
    /// 아직 나가 있는 모험은 취소돼" 라고 말한다 — 그 구간엔 모험이 이미 정산돼 없다.
    ///
    /// 실행기가 이 상태를 거절하지는 않으므로(`isRunning` 이면 종료는 실행된다) 제안 ⊆ 실행 가능
    /// 가드로는 안 걸린다. 문구가 상태를 잘못 부르는 부류라 여기서 따로 잰다.
    func testTheRestPhaseIsNotOfferedAsAFocusToStop() async {
        let focusing = await probe { store, timer, _ in
            XCTAssertTrue(timer.startFocusSession(minutes: 25, companion: store))
        }
        XCTAssertTrue(focusing.toolbox.availableActions(owner: focusing.owner).contains(.stopFocus),
                      "대조군: 집중 중에는 종료를 제안해야 아래 단언이 뜻을 가진다")

        // 앱에서 휴식은 집중이 끝나며 켜지고, 그 완료가 모험을 함께 정산한다 — 그래서 휴식
        // 구간엔 나가 있는 모험이 없다. 상태를 그대로 세운다(`suggestionStates` 의 "휴식 중" 과
        // 같은 조립이다. `tick` 은 `onFocusCompleted` 가 앱 루트에서만 꽂히므로 여기선 정산을 안 한다).
        let resting = await probe { store, timer, _ in
            timer.startRest()
            XCTAssertNil(store.activeAdventure, "전제: 휴식 구간엔 나가 있는 모험이 없다")
        }

        XCTAssertTrue(resting.timer.isRunning, "전제: 휴식도 isRunning 이다 — 그래서 이 경로가 밟힌다")
        XCTAssertFalse(resting.toolbox.availableActions(owner: resting.owner).contains(.stopFocus),
                       "쉬는 중에 '집중을 끝내자' 를 권했다")
    }

    /// 칩 문구와 그 칩이 노리는 호출은 **같은 값**을 말해야 한다. 문구가 상수 표를 다시 읽으면
    /// 호출만 바뀌었을 때 칩은 25분이라 쓰고 승인 카드는 50분을 켠다.
    ///
    /// **인자를 든 칩은 전부 여기를 지난다.** `.pokedoroStart` 만 보고 나머지를 `continue` 로
    /// 흘리던 동안, 인자를 든 다른 칩(`.useRareCandy`)은 규칙 밖이었다 — 그래서 한국어 문구가
    /// 아이템 이름을 붙여 쓴 채(`이상한사탕`) 파서가 받는 이름(`이상한 사탕`)과 갈라져도
    /// 이 파일 전체가 초록이었다. 인자의 종류마다 갈래를 두고, 새 종류는 `default` 가 아니라
    /// 여기에 갈래를 더해야 한다.
    func testActionPhrasesQuoteTheirOwnCall() {
        for action in PokemonChatAction.allCases {
            for language in AppLanguage.allCases {
                let phrase = action.phrase(language)
                switch action.call {
                case .pokedoroStart(let minutes):
                    XCTAssertTrue(phrase.contains("\(minutes)"),
                                  "\(action)/\(language.rawValue): 문구가 호출의 \(minutes)분을 안 말한다")
                case .itemUse(let kind):
                    let name = L(language).itemName(kind)
                    XCTAssertTrue(phrase.contains(name),
                                  "\(action)/\(language.rawValue): 문구('\(phrase)')가 호출이 쓸 이름('\(name)')을 안 말한다")
                default:
                    continue
                }
            }
        }
    }

    /// 인자를 든 유일한 칩(`item.use`). 사용자가 보내는 문장에는 **현지화된 이름**밖에 없고,
    /// 모델이 `bag.list` 를 먼저 부르지 않으면 rawValue 를 알 길이 없다 — 왕복은 3회뿐이라
    /// 그 한 번이 비싸다. 닫힌 목록이므로 이름으로 되짚는다.
    ///
    /// 이 테스트는 **표의 이름이 파싱되는지**만 본다. 칩 문구가 그 이름을 그대로 말하는지는
    /// `testActionPhrasesQuoteTheirOwnCall` 이 건다 — 여기서 둘을 겸하면 입력을 표에서 뽑는
    /// 순간 항등식이 되어(표 → 표) 칩 문구가 어떻게 틀리든 초록이 된다.
    func testItemUseAcceptsTheLocalizedNameThatBagListPrints() {
        for language in AppLanguage.allCases {
            let name = L(language).itemName(.rareCandy)
            let (_, call) = PokemonChatToolParser.parse("좋아! [[tool:item.use(\(name))]]")
            XCTAssertEqual(call, .itemUse(kind: .rareCandy),
                           "\(language.rawValue): 표시 이름(\(name))으로는 호출이 안 만들어진다")
        }
        let (_, raw) = PokemonChatToolParser.parse("[[tool:item.use(rareCandy)]]")
        XCTAssertEqual(raw, .itemUse(kind: .rareCandy), "회귀: bag.list 가 찍는 rawValue 는 계속 통해야 한다")
    }

    /// rawValue 와 표시 이름이 **같은 관대함**을 받아야 한다. 정규화를 현지화 갈래에만 걸면
    /// `rare candy`(표시 이름)는 통하는데 `rarecandy`·` rareCandy `(정답 값)는 떨어진다 —
    /// 가방이 찍어 준 값이 사람 말보다 까다로운, 계약과 정반대의 상태다.
    func testItemNamesSurviveTheSpacingAndCaseTheModelAdds() {
        for raw in [" rareCandy ", "rarecandy", "RAREcandy", " 이상한 사탕 "] {
            XCTAssertEqual(PokemonChatToolParser.parse("[[tool:item.use(\(raw))]]").call,
                           .itemUse(kind: .rareCandy),
                           "'\(raw)' 가 거부됐다 — 같은 아이템의 다른 표기가 갈린다")
        }
    }

    /// 이름 되짚기는 **대화가 실제로 쓸 수 있는 종류**까지만 연다. 가구는 `useItem` 의 어느
    /// 갈래로도 성공하지 못하는데(진화 규칙이 없어 `default:` 에서 떨어진다) 이름은 갖고 있다 —
    /// 48종을 통째로 열어 두면 프롬프트가 "트레이너가 말한 대로" 를 허용하는 지금, 가구 이름
    /// 한 번에 승인 카드가 떴다가 그제서야 실패한다. 사용자에겐 승인한 일이 안 된 것으로 보인다.
    func testNamesOnlyReachItemsChatCanActuallyUse() {
        for language in AppLanguage.allCases {
            let bed = L(language).itemName(.roomBed)
            XCTAssertNil(PokemonChatToolParser.parse("[[tool:item.use(\(bed))]]").call,
                         "\(language.rawValue): 가구('\(bed)')가 호출이 됐다 — 승인 카드까지 간다")
        }
        XCTAssertNil(PokemonChatToolParser.parse("[[tool:item.use(roomBed)]]").call,
                     "회귀: rawValue 로도 가구는 쓸 수 없어야 한다")
        // 대조군. 위 단언만 두면 표를 통째로 비워도 통과한다.
        XCTAssertEqual(PokemonChatToolParser.parse("[[tool:item.use(moonStone)]]").call,
                       .itemUse(kind: .moonStone), "진화 아이템까지 같이 닫혔다")
    }

    /// 이름으로 되짚는 순간 **이름이 겹치면 엉뚱한 아이템을 쓴다** — 그리고 아이템 사용은
    /// 소모라 되돌릴 수 없다. 세 언어를 한 자루에 넣고 대조하므로 언어를 가로질러도 겹치면 안 된다.
    /// (rawValue 와 현지화 이름이 겹치는 경우도 같은 함정이라 함께 센다.)
    func testNoTwoItemsAnswerToTheSameName() {
        var owner: [String: ItemKind] = [:]
        for kind in ItemKind.allCases {
            var names = [kind.rawValue]
            // 언어를 손으로 세지 않는다 — 네 번째 언어가 붙는 날 새 충돌을 못 보고 지나친다.
            for language in AppLanguage.allCases { names.append(L(language).itemName(kind)) }
            for name in Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }) {
                if let existing = owner[name], existing != kind {
                    XCTFail("'\(name)' 를 \(existing) 와 \(kind) 가 함께 쓴다 — 이름으로는 못 가른다")
                }
                owner[name] = kind
            }
        }
    }

    /// 박스 개체 대화에는 제안이 없다. 다섯 액션이 전부 "지금 나와 있는 나" 에 작용하므로
    /// 주인 게이트가 먼저 자른다 — `canRun` 을 재사용하는 한 이 줄은 저절로 참이다.
    /// (`testToolsThatActOnMeRefuseFromABoxedCompanionsChat` 의 형제다.)
    func testABoxedCompanionsChatSuggestsNothing() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let boxed = Self.spareMon()
        store.debugSetBoxedMons([boxed])
        store.debugAddItem(.rareCandy, 1)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        XCTAssertEqual(toolbox.availableActions(owner: boxed.id), [],
                       "박스 개체 창이 활성 개체를 움직이는 일을 제안했다")
        XCTAssertFalse(toolbox.availableActions(owner: store.activeMonID!).isEmpty,
                       "대조군: 활성 개체 창에서는 제안이 있어야 위 단언이 뜻을 가진다")
    }

    /// 칩 문구는 사용자가 **읽고 보내는 문장**이다. 마커(`[[tool:...]]`)를 넣으면 사용자가 기계
    /// 문법을 보내게 되고, 그건 대화를 우회하는 두 번째 실행 경로다.
    func testActionPhrasesAreHumanSentencesInAllThreeLanguages() {
        for action in PokemonChatAction.allCases {
            var seen = Set<String>()
            for language in [AppLanguage.ko, .en, .ja] {
                let phrase = action.phrase(language)
                XCTAssertFalse(phrase.isEmpty, "\(action)/\(language.rawValue): 빈 문구")
                // `[[tool:` 만 막으면 규칙보다 좁다. 사용자 메시지는 그대로 대화 기록에 실려
                // 다음 왕복의 문맥으로 CLI 에 되돌아가므로, 대괄호 문법을 보여 주는 것만으로도
                // 모델에게 마커를 흉내 낼 본을 준다 — 그리고 그 마커는 실제로 파싱된다.
                XCTAssertFalse(phrase.contains("[["), "\(action)/\(language.rawValue): 마커 문법이 새어 나왔다")
                seen.insert(phrase)
            }
            XCTAssertEqual(seen.count, 3, "\(action): 세 언어 중 둘이 같은 문구다")
        }
    }

    /// 제안을 재는 한 판. 상태마다 **다시 만들어야** 하므로(실행이 상태를 바꾼다) 조립을 한 곳에 둔다.
    private struct ToolProbe {
        let store: CompanionStore
        let timer: FocusTimer
        let toolbox: PokemonChatToolbox
        let owner: UUID
    }

    private func probe(line: EvoLine? = nil, baseID: Int = 25,
                       setUp: @MainActor (CompanionStore, FocusTimer, TestClock) -> Void = { _, _, _ in }
    ) async -> ToolProbe {
        let clock = TestClock()
        let store = makeCompanionStore(line: line, clock: clock)
        await store.hatch(baseID: baseID)
        let timer = FocusTimer()
        setUp(store, timer, clock)
        return ToolProbe(store: store, timer: timer,
                         toolbox: PokemonChatToolbox(timer: timer, companion: store,
                                                     album: makeAlbum(), lookup: Self.emptyLookup),
                         owner: store.activeMonID!)
    }

    private static let suggestionStates: [(String, @MainActor (PokemonChatToolTests) async -> ToolProbe)] = [
        ("멈춰 있음", { await $0.probe() }),
        ("사탕 보유", { await $0.probe { store, _, _ in store.debugAddItem(.rareCandy, 1) } }),
        ("집중 중", { await $0.probe { store, timer, _ in
            XCTAssertTrue(timer.startFocusSession(minutes: 25, companion: store))
        } }),
        // 타이머만 돌고 **모험은 없는** 구간. 이 상태가 없으면 시작 판정의 두 조건 중 모험 쪽이
        // 타이머 쪽을 가려서, 타이머 검사를 통째로 지워도 아무 테스트가 안 깨진다(주입에서 확인).
        // 같은 가림을 실행기에서 이미 겪었다 — `pokedoro start refused: already in rest`.
        // 사탕을 쥐여 주는 이유는 이 상태가 **공허해지지 않게** 하려는 것뿐이다. 휴식 중엔 제안할
        // 타이머 동작이 없고(시작은 돌고 있어서, 종료는 끝낼 집중이 아니라서), 제안이 0개면 이
        // 상태는 아무 주입도 못 잡는다 — 위 가드가 "제안이 하나도 없다" 로 먼저 걸린다.
        ("휴식 중", { await $0.probe { store, timer, _ in
            timer.startRest()
            store.debugAddItem(.rareCandy, 1)
            XCTAssertNil(store.activeAdventure, "전제: 휴식 구간엔 나가 있는 모험이 없다")
        } }),
        ("모험 정산 대기", { await $0.probe { store, timer, clock in
            XCTAssertTrue(timer.startFocusSession(minutes: 25, companion: store))
            clock.advance(25 * 60)
            timer.stop()
        } }),
        ("진화 대기", { await $0.probe(line: levelGatedLine, baseID: 40) { store, _, _ in
            store.debugAccrueLevelExperience(300_000_000)
            store.applyUsage(0)
        } }),
        // 카드가 뜬 **뒤** 조건이 무너진 진화. 대기 여부만 보는 판정은 여기서도 칩을 띄우는데,
        // 승인은 카드만 지우고 조용히 돌아간다 — 앱이 권한 대로 누른 사용자가 진화를 잃는다.
        // `testEvolutionThatSilentlyFailsIsNotReportedAsAccepted` 가 실행기 쪽에서 이미 재던
        // 상태다. 제안 쪽에서 재지 않아 두 판정이 갈라진 걸 아무도 못 봤다.
        ("진화 조건 무너짐", { await $0.probe(line: knownMoveGatedLine, baseID: 40) { store, _, _ in
            store.debugSetActiveLearnedMoves([MoveSpec(id: 246, names: ["ko": "원시의힘"], type: .rock,
                                                       power: 60, damageClass: .special, accuracy: 100, pp: 5)])
            store.debugAccrueLevelExperience(300_000_000)
            store.applyUsage(0)
            store.debugSetActiveLearnedMoves([])
        } }),
    ]

    private static func dexEntry(chain: [Int], types: [PokemonType]? = nil, shiny: Bool = false) -> DexEntry {
        DexEntry(baseID: chain[0], finalID: chain[chain.count - 1], chainOrder: chain,
                 rarity: .common, caughtAt: nil, isShiny: shiny, types: types)
    }

    private static func spareMon() -> MonState {
        MonState(baseID: 25, pathIDs: [25], plannedPathIDs: [25], stageIndex: 0,
                 usedAtStage: 0, rarity: .common, totalForms: 1)
    }

    private static let levelGatedLine = EvoLine(
        baseID: 40, tree: EvoNode(speciesID: 40, children: [EvoNode(speciesID: 41, children: [], evolutionLevel: 5)]),
        rarity: .common, names: [40: ["ko": "푸린"], 41: ["ko": "푸크린"]])

    /// 기술을 배운 채로 자라야 하는 진화. 조건이 **개체 상태**에 매달려 있어, 카드가 뜬 뒤에도
    /// 무너질 수 있는 부류를 대표한다(시간대·요구 파티원도 같다).
    private static let knownMoveGatedLine = EvoLine(
        baseID: 40, tree: EvoNode(speciesID: 40, children: [
            EvoNode(speciesID: 41, children: [], evolutionTrigger: "level-up", evolutionKnownMoveID: 246)]),
        rarity: .common, names: [40: ["ko": "푸린"], 41: ["ko": "푸크린"]])

    private static let stoneLine = EvoLine(
        baseID: 30, tree: EvoNode(speciesID: 30, children: [
            EvoNode(speciesID: 31, children: [], evolutionTrigger: "use-item", evolutionItem: "fire-stone")]),
        rarity: .common, names: [30: ["ko": "니드리나"], 31: ["ko": "니드퀸"]])

    private static let emptyLookup: (Int, AppLanguage) async -> PokemonSpeciesIdentity = { _, language in
        PokemonSpeciesIdentity(genera: [:], habitatSlug: nil, flavorTexts: [:],
                               abilityNames: [:], abilityTexts: [:], language: language)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pokemon-chat-tool-\(UUID().uuidString).json")
    }

    private func makeAlbum() -> PokemonMemoryAlbum {
        PokemonMemoryAlbum(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("pokemon-chat-album-\(UUID().uuidString).json"))
    }

    private func makeCompanionStore(line: EvoLine? = nil, clock: TestClock? = nil) -> CompanionStore {
        let line = line ?? EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                                   names: [25: ["ko": "피카츄", "en": "Pikachu"]])
        let store = CompanionStore(provider: ToolLineProvider(line: line),
                                   clock: clock?.closure ?? { Date(timeIntervalSince1970: 1_000) },
                                   fileURL: temporaryURL(), rng: SeededRNG(seed: 1))
        store.setLanguage(.ko)
        return store
    }
}

@MainActor
private extension PokemonChatToolbox {
    /// 테스트 편의 — "활성 동행의 대화에서 불렀다" 는 뜻. 프로토콜에 기본값을 두지 않았으므로
    /// 이 지름길은 테스트 파일 밖으로 새지 않는다(프로덕션은 owner 를 반드시 명시한다).
    func runAsActive(_ call: PokemonChatToolCall) async -> (line: String, succeeded: Bool) {
        await run(call, owner: companion.activeMonID ?? UUID())
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

@MainActor
private final class CountingToolbox: PokemonChatToolRunning {
    private(set) var runCount = 0
    func canRun(_ call: PokemonChatToolCall, owner: UUID) -> Bool { true }
    /// 이 스텁은 루프의 왕복 횟수만 센다 — 제안은 실물 실행기(`PokemonChatToolbox`)에서 검증한다.
    func availableActions(owner: UUID) -> [PokemonChatAction] { [] }
    var needsWallClockTicker: Bool { false }
    func run(_ call: PokemonChatToolCall, owner: UUID) async -> (line: String, succeeded: Bool) {
        runCount += 1; return ("pokedoro state=idle", true)
    }
}

private struct StubToolbox: PokemonChatToolRunning {
    var status = "pokedoro state=idle"
    func canRun(_ call: PokemonChatToolCall, owner: UUID) -> Bool { true }
    func availableActions(owner: UUID) -> [PokemonChatAction] { [] }
    var needsWallClockTicker: Bool { false }
    func run(_ call: PokemonChatToolCall, owner: UUID) async -> (line: String, succeeded: Bool) {
        switch call {
        case .pokedoroStatus: return (status, true)
        case .pokedexLookup(let id): return ("pokedex #\(id)", true)
        case .pokedoroStart, .pokedoroStop, .adventureClaim: return ("unreachable — approval gated", false)
        case .bagList: return ("bag empty", true)
        case .rosterList: return ("roster index=0 name=피카츄 shiny=false active=true", true)
        case .dexProgress: return ("dex species=0/10 types=0/9 shiny=0/1", true)
        case .challengeStatus: return ("challenge dungeon=open budget=100 badges=0/4 missions=0/6", true)
        case .itemUse, .evolutionAccept, .companionSwitch: return ("unreachable — approval gated", false)
        case .memoryRecord(let body): return ("memory recorded len=\(body.count)", true)
        }
    }
}

private extension PokemonChatProfile {
    static let toolFixture = PokemonChatProfile(speciesID: 25, displayName: "피카츄", nickname: nil,
                                                nature: "온순", level: 5, stage: "첫 번째 형태",
                                                flavorText: nil, language: .ko)
}
