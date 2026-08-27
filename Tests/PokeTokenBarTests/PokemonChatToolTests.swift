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

        let refused = await toolbox.runAsActive(.pokedoroStart(minutes: 25))
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

        // 보유형·던전 소모품은 대화에서 "지금 쓴다" 는 개념이 없다. 재고가 있어도 실패다.
        store.debugAddItem(.shinyCharm, 1)
        store.debugAddItem(.freshWater, 1)
        for kind in [ItemKind.shinyCharm, .freshWater] {
            let result = await toolbox.runAsActive(.itemUse(kind: kind))
            XCTAssertFalse(result.succeeded, result.line)
            XCTAssertEqual(store.itemCount(kind), 1, "쓸 수 없다고 해 놓고 소모했다")
        }
    }

    /// 가방·로스터는 모델이 **되돌려 줄 수 있는 값**으로 찍힌다. 현지화된 이름을 주면 모델이
    /// 그걸 인자로 써서 파싱에서 떨어지고, 사용자에겐 "아무 일도 안 일어남" 으로 보인다.
    func testReadToolsPrintNamesTheModelCanHandBackAsArguments() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        store.debugAddItem(.fireStone, 2)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let bag = await toolbox.runAsActive(.bagList)
        XCTAssertTrue(bag.line.contains("fireStone=2"), bag.line)
        XCTAssertNil(PokemonChatToolParser.parse("[[tool:item.use(불꽃의돌)]]").call,
                     "현지화된 이름이 인자로 통과하면 안 된다")
        XCTAssertEqual(PokemonChatToolParser.parse("[[tool:item.use(fireStone)]]").call,
                       .itemUse(kind: .fireStone), "가방이 찍은 이름이 그대로 인자가 돼야 한다")

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

    /// 도전 탭(체육관·던전)은 혼자 하는 콘텐츠인데 대화가 못 봤다. 메뉴바 집중 앱에서 가장
    /// 쓸모 있는 대사가 "오늘 던전 아직 안 갔어" 다. 입장·도전은 넣지 않는다 — 맵 이동과
    /// 배틀 화면이 필요하고, 하루 한 판이라 승인 카드 한 번이 감당할 무게가 아니다.
    func testChallengeStatusReportsTodaysDungeonBadgesAndMissions() async {
        let store = makeCompanionStore()
        await store.hatch(baseID: 25)
        let toolbox = PokemonChatToolbox(timer: FocusTimer(), companion: store,
                                         album: makeAlbum(), lookup: Self.emptyLookup)

        let status = await toolbox.runAsActive(.challengeStatus)

        XCTAssertTrue(status.succeeded, status.line)
        XCTAssertTrue(status.line.contains("dungeon=open"), status.line)
        // 총량은 카탈로그에서 온다 — 숫자를 여기 적으면 콘텐츠가 늘 때 문구만 옛말이 된다.
        XCTAssertTrue(status.line.contains("badges=0/\(GymLeague.catalog.count)"), status.line)
        XCTAssertTrue(status.line.contains("missions=0/\(MissionBoard.catalog.count)"), status.line)
        XCTAssertTrue(status.line.contains("budget=\(store.dungeonBudgetPreview)"), status.line)
    }

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
    func run(_ call: PokemonChatToolCall, owner: UUID) async -> (line: String, succeeded: Bool) {
        runCount += 1; return ("pokedoro state=idle", true)
    }
}

private struct StubToolbox: PokemonChatToolRunning {
    var status = "pokedoro state=idle"
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
