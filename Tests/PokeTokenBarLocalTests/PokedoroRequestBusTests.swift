import Foundation
import Testing
@testable import PokeTokenBar

/// 터미널 → 앱 요청 우편함. **세이브의 쓰기 주체는 여전히 앱 하나다** — 터미널은 이 파일만 쓰고,
/// 실행은 앱이 한다. 그래서 `ReadOnlyStoreTests` 가 지키는 성질이 그대로 남는다.
///
/// 파일마다 쓰는 쪽이 하나다: 요청은 터미널만, 답은 앱만 쓴다. 앱이 요청 파일을 지우지 않는
/// 이유도 그것이다 — 지우려면 앱이 터미널의 파일에 손을 대야 하고, 그 순간 두 쓰기 주체가 된다.
/// 대신 **나이 제한과 id** 두 가드가 "이미 처리한 요청" 을 걸러 낸다.
@Suite("PokedoroRequestBusTests")
struct PokedoroRequestBusTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func request(_ action: PokedoroRequest.Action = .start(minutes: 25),
                         at offset: TimeInterval = 0,
                         id: UUID = UUID()) -> PokedoroRequest {
        PokedoroRequest(id: id, action: action, requestedAt: Self.now.addingTimeInterval(offset))
    }

    // MARK: 실행 판정

    @Test func testAFreshRequestRuns() {
        #expect(PokedoroRequestBus.shouldExecute(request(), now: Self.now, lastExecutedID: nil))
    }

    /// **이 테스트가 이 가드의 존재 이유다.** 앱이 꺼진 사이 터미널이 남긴 요청을 나이 제한 없이
    /// 실행하면, 사용자가 세 시간 전에 포기한 90분 집중이 앱을 켜는 순간 시작된다 — 그 시각엔
    /// 사용자가 무엇 때문에 타이머가 켜졌는지 알 방법이 없다.
    @Test func testAStaleRequestLeftBehindWhileTheAppWasClosedNeverRuns() {
        let threeHoursAgo = request(.start(minutes: 90), at: -3 * 3600)
        #expect(!PokedoroRequestBus.shouldExecute(threeHoursAgo, now: Self.now, lastExecutedID: nil))
    }

    /// 경계를 양쪽에서 본다 — 제한값 자체는 통과하고 그 너머는 막힌다.
    @Test func testTheAgeLimitIsInclusiveAtItsBoundary() {
        let limit = PokedoroRequestBus.maximumAge
        #expect(PokedoroRequestBus.shouldExecute(request(at: -limit), now: Self.now, lastExecutedID: nil))
        #expect(!PokedoroRequestBus.shouldExecute(request(at: -limit - 0.5), now: Self.now, lastExecutedID: nil))
    }

    /// 시계가 크게 어긋난 요청도 막는다. 대칭으로 두는 이유는, 앞으로 어긋난 값만 통과시키면
    /// 시각을 조작한 요청 하나로 나이 제한을 통째로 우회할 수 있기 때문이다.
    @Test func testARequestDatedFarInTheFutureNeverRuns() {
        #expect(!PokedoroRequestBus.shouldExecute(request(at: 3 * 3600), now: Self.now, lastExecutedID: nil))
    }

    /// 앱은 1초마다 이 파일을 본다. 파일을 지우지 않으므로, id 가드가 없으면 **같은 요청이 매
    /// 틱마다 다시 실행된다** — 10초 동안 열 번.
    @Test func testTheSameRequestIsNotExecutedTwice() {
        let sent = request()
        #expect(PokedoroRequestBus.shouldExecute(sent, now: Self.now, lastExecutedID: nil))
        #expect(!PokedoroRequestBus.shouldExecute(sent, now: Self.now, lastExecutedID: sent.id))
    }

    /// 앞 요청을 처리한 뒤 들어온 **다른** 요청은 막히지 않는다. id 가드가 마지막 하나만 기억하는
    /// 것으로 충분하다는 근거다 — 아니면 정산 직후의 시작이 조용히 삼켜진다.
    @Test func testANewRequestRunsEvenAfterAnotherOneWasJustExecuted() {
        let previous = request(.claim)
        let next = request()
        #expect(PokedoroRequestBus.shouldExecute(next, now: Self.now, lastExecutedID: previous.id))
    }

    // MARK: 파일 왕복

    /// 우편함 두 파일만 쓰는 픽스처지만 같은 헬퍼를 쓴다 — 유일한 디렉토리를 여기서 다시 만들
    /// 이유가 없고, 이름이 고정된 파일을 공용 temp 에 두지 않는다는 규칙은 요청 파일에도 그대로다.
    private func makeDirectory() -> URL { storeFixtureDirectory("pokedoro-bus") }

    /// 터미널이 쓴 것을 앱이 그대로 읽는다. 두 프로세스가 같은 인코딩 규약을 쓰는지 보는 유일한 자리다.
    @Test func testTheAppReadsBackExactlyWhatTheTerminalWrote() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)

        let sent = request(.start(minutes: 90))
        try mailbox.send(sent)

        #expect(mailbox.pendingRequest() == sent)
    }

    /// 세 동작 **모두** 왕복해야 한다. 하나만 보면 인코딩이 그 동작에만 맞는 구현도 초록이다
    /// (인자를 든 동작은 시작 하나뿐이라 특히 그렇다).
    @Test func testEveryActionSurvivesTheFileRoundTrip() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)

        for action in [PokedoroRequest.Action.start(minutes: 50), .start(minutes: nil), .claim, .stop] {
            let sent = request(action)
            try mailbox.send(sent)
            #expect(mailbox.pendingRequest() == sent, "\(action) 이 왕복에서 달라졌다")
        }
    }

    /// 파일은 **손으로 고칠 수 있는 평평한 JSON** 이어야 한다. 인자를 든 enum 을 Swift 에 그냥
    /// 맡기면 `{"start":{"minutes":25}}` 같은 중첩이 나오는데, 문서가 약속한 모양이 아니라서
    /// 사용자가 고친 파일이 조용히 무시된다.
    @Test func testTheRequestFileStaysFlatAndHandEditable() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)
        try mailbox.send(request(.start(minutes: 50)))

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: mailbox.requestURL))
        let fields = try #require(json as? [String: Any])
        #expect(fields["action"] as? String == "start")
        #expect(fields["argument"] as? String == "50")
        #expect(fields["id"] is String)
        #expect(fields["requestedAt"] != nil)
    }

    /// 인자를 안 받는 동작에는 인자 칸이 **아예 없다**. 남겨 두면 `{"action":"stop","argument":null}`
    /// 같은 파일이 정상으로 보이고, 손으로 고치는 사용자가 그 칸이 뭔가 한다고 믿는다.
    @Test func testAnArgumentlessActionWritesNoArgumentField() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)
        try mailbox.send(request(.stop))

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: mailbox.requestURL))
        let fields = try #require(json as? [String: Any])
        #expect(fields["action"] as? String == "stop")
        #expect(fields["argument"] == nil)
    }

    /// 이름과 인자가 어긋난 파일은 요청이 **되지 않는다** — 깨진 파일과 같은 취급이다.
    /// 손으로 고칠 수 있는 파일이라 이 조합은 실제로 들어온다. 인자를 버리고 실행하면 사용자는
    /// 자기가 적은 값이 무시된 것을 모른 채 다른 일이 벌어진 걸 본다.
    @Test func testAFileWhoseActionAndArgumentDisagreeIsNotARequest() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)
        try Data("""
        {"id":"\(UUID().uuidString)","action":"stop","argument":"90","requestedAt":0}
        """.utf8).write(to: mailbox.requestURL)

        #expect(mailbox.pendingRequest() == nil)
    }

    /// 모르는 이름도 요청이 되지 않는다. 앱 화면에만 있는 기능 이름을 적어도 마찬가지다 —
    /// 목록 밖 이름은 거절되는 게 아니라 **요청으로 읽히지 않는다**(대화 도구와 같은 성질).
    @Test func testAFileNamingAnUnknownActionIsNotARequest() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)
        try Data("""
        {"id":"\(UUID().uuidString)","action":"battle","requestedAt":0}
        """.utf8).write(to: mailbox.requestURL)

        #expect(mailbox.pendingRequest() == nil)
    }

    // MARK: 동작 어휘 — 인자 칸 하나

    /// 인자는 **칸 하나**(`argument`)로 실린다. 동작마다 칸 이름을 따로 두면 새 동작이 늘 때마다
    /// "그 동작에 없어야 하는 칸" 검사가 같이 늘고, 한 칸을 빠뜨려도 컴파일이 통과한다.
    @Test func testEveryArgumentRidesInOneField() {
        #expect(PokedoroRequest.Action.start(minutes: 50).argument == "50")
        #expect(PokedoroRequest.Action.use(item: .rareCandy).argument == ItemKind.rareCandy.rawValue)
        #expect(PokedoroRequest.Action.switchCompanion(number: 3).argument == "3")
        #expect(PokedoroRequest.Action.rename(nickname: "피카").argument == "피카")
        for action in [PokedoroRequest.Action.claim, .stop, .evolve] {
            #expect(action.argument == nil, "\(action) 이 인자 칸을 쓴다")
        }
    }

    /// 새 동작도 이름 → 동작 → 이름이 제자리로 돌아온다.
    @Test func testTheNewActionsRoundTripThroughTheirOwnTable() {
        let actions: [PokedoroRequest.Action] = [
            .use(item: .rareCandy), .use(item: .fireStone), .evolve,
            .switchCompanion(number: 2), .rename(nickname: "라이츄")
        ]
        for action in actions {
            #expect(PokedoroRequest.Action(name: action.name, argument: action.argument) == action)
        }
    }

    /// 아이템은 **닫힌 목록 대조**다 — 목록 밖 이름은 거절되는 게 아니라 요청으로 읽히지 않는다.
    @Test func testAnItemOutsideTheNameTableIsNotAnAction() {
        #expect(PokedoroRequest.Action(name: "use", argument: "masterball") == nil)
        #expect(PokedoroRequest.Action(name: "use", argument: "") == nil)
        #expect(PokedoroRequest.Action(name: "use", argument: nil) == nil)
    }

    /// 사용자가 부르는 이름(현지화된 표시 이름)도 받는다 — 터미널에 `use rare candy` 를 치는
    /// 사람과 `use 이상한 사탕` 을 치는 사람이 같은 일을 해야 한다.
    @Test func testAnItemCanBeNamedTheWayTheScreenPrintsIt() {
        #expect(PokedoroRequest.Action(name: "use", argument: "이상한 사탕") == .use(item: .rareCandy))
        #expect(PokedoroRequest.Action(name: "use", argument: "Rare Candy") == .use(item: .rareCandy))
    }

    /// 개체 번호는 `party` 가 찍는 값(1부터)이다. 0 이나 음수는 그 목록에 없으므로 요청이 아니다 —
    /// 그대로 인덱스로 쓰면 배열 밖을 읽거나 엉뚱한 개체를 건드린다.
    @Test func testARosterNumberBelowOneIsNotAnAction() {
        #expect(PokedoroRequest.Action(name: "switch", argument: "1") == .switchCompanion(number: 1))
        #expect(PokedoroRequest.Action(name: "switch", argument: "0") == nil)
        #expect(PokedoroRequest.Action(name: "switch", argument: "-2") == nil)
        #expect(PokedoroRequest.Action(name: "switch", argument: "두번째") == nil)
    }

    /// 별명은 **인자가 자유 문자열인 유일한 동작**이다. 빈 이름·공백만은 요청이 아니다 — 실수로
    /// 지운 이름이 조용히 통과하면 사용자는 자기가 무엇을 지웠는지 모른다. 길이 클램프는 실행기가
    /// 한다(파일을 직접 고친 경로까지 막아야 하므로).
    @Test func testABlankNicknameIsNotAnAction() {
        #expect(PokedoroRequest.Action(name: "name", argument: "리자몽") == .rename(nickname: "리자몽"))
        #expect(PokedoroRequest.Action(name: "name", argument: "   ") == nil)
        #expect(PokedoroRequest.Action(name: "name", argument: "") == nil)
        #expect(PokedoroRequest.Action(name: "name", argument: nil) == nil)
    }

    /// 인자를 안 받는 새 동작에 인자가 붙어도 추측하지 않는다.
    @Test func testAnArgumentOnEvolveIsNotAnAction() {
        #expect(PokedoroRequest.Action(name: "evolve", argument: "2") == nil)
        #expect(PokedoroRequest.Action(name: "evolve", argument: nil) == .evolve)
    }

    /// 파일에서도 인자 칸은 하나다. 아이템은 **rawValue 로 적힌다** — 표시 이름으로 적으면 언어
    /// 설정을 바꾼 사용자가 자기 요청 파일을 못 읽는다.
    @Test func testTheNewActionsWriteOneArgumentField() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)
        try mailbox.send(request(.use(item: .rareCandy)))

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: mailbox.requestURL))
        let fields = try #require(json as? [String: Any])
        #expect(fields["action"] as? String == "use")
        #expect(fields["argument"] as? String == ItemKind.rareCandy.rawValue)
        #expect(fields["minutes"] == nil, "인자 칸이 두 벌이면 어느 쪽이 진짜인지 알 수 없다")
    }

    /// 새 동작도 파일 왕복에서 자기 자신이다.
    @Test func testTheNewActionsSurviveTheFileRoundTrip() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)

        for action in [PokedoroRequest.Action.use(item: .waterStone), .evolve,
                       .switchCompanion(number: 4), .rename(nickname: "꼬북")] {
            let sent = request(action)
            try mailbox.send(sent)
            #expect(mailbox.pendingRequest() == sent, "\(action) 이 왕복에서 달라졌다")
        }
    }

    // MARK: 동작 어휘

    /// 이름은 세 동작이 서로 다르다 — 같은 이름을 두 동작이 쓰면 왕복에서 하나가 다른 것이 된다.
    @Test func testEveryActionHasItsOwnName() {
        let names = [PokedoroRequest.Action.start(minutes: 25), .claim, .stop].map(\.name)
        #expect(Set(names).count == names.count)
    }

    /// 인자를 받지 않는 동작에 인자가 붙었으면 **추측하지 않는다** — 대화 도구 파서와 같은 규칙이다.
    @Test func testAnArgumentOnAnArgumentlessActionIsNotAnAction() {
        #expect(PokedoroRequest.Action(name: "stop", argument: "25") == nil)
        #expect(PokedoroRequest.Action(name: "claim", argument: "0") == nil)
    }

    @Test func testAnUnknownActionNameIsNotAnAction() {
        #expect(PokedoroRequest.Action(name: "battle", argument: nil) == nil)
        #expect(PokedoroRequest.Action(name: "", argument: nil) == nil)
    }

    /// 분이 없는 시작은 그대로 통과한다 — 기본 길이는 실행기가 고른다. 여기서 25 를 채우면
    /// 기본값이 두 곳이 되고, 한쪽만 바뀌면 화면과 터미널이 다른 길이를 켠다.
    @Test func testStartWithoutALengthIsStillAnAction() {
        #expect(PokedoroRequest.Action(name: "start", argument: nil) == .start(minutes: nil))
    }

    /// 이름 → 동작 → 이름이 제자리로 돌아온다. 이 왕복이 곧 파일 규약이다.
    @Test func testActionNamesRoundTripThroughTheirOwnTable() {
        for action in [PokedoroRequest.Action.start(minutes: 90), .claim, .stop] {
            #expect(PokedoroRequest.Action(name: action.name, argument: action.argument) == action)
        }
    }

    /// 답도 같은 규약으로 돌아온다. 터미널은 **자기 요청의 답만** 받아야 한다 — id 가 다르면
    /// 앞 세션의 답을 자기 것으로 착각해 하지도 않은 일을 성공으로 보고한다.
    @Test func testTheTerminalOnlyAcceptsTheReplyToItsOwnRequest() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)

        let mine = UUID()
        try mailbox.post(PokedoroReply(id: UUID(), succeeded: true, message: "남의 답"))
        #expect(mailbox.reply(to: mine) == nil)

        try mailbox.post(PokedoroReply(id: mine, succeeded: true, message: "내 답"))
        #expect(mailbox.reply(to: mine)?.message == "내 답")
    }

    /// 파일이 없는 것이 **정상 상태**다 — 앱은 요청이 없는 매 초에도 이 경로를 밟는다.
    @Test func testAnAbsentMailboxIsEmptyNotAnError() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)

        #expect(mailbox.pendingRequest() == nil)
        #expect(mailbox.reply(to: UUID()) == nil)
    }

    /// 반쯤 쓰인 파일을 읽어도 앱이 죽으면 안 된다. 이 파일은 메뉴바 앱의 1초 틱이 읽으므로
    /// 크래시가 곧 앱 종료다.
    @Test func testACorruptMailboxIsIgnoredInsteadOfCrashing() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)
        try Data("{ not json".utf8).write(to: mailbox.requestURL)

        #expect(mailbox.pendingRequest() == nil)
    }

    /// 요청 파일은 세이브 **옆에** 산다 — `PTB_STATE_DIR` 하나로 프로필 전체가 격리된다는
    /// `CompanionStorageLocations` 의 계약을 요청도 지켜야 한다. 아니면 격리된 QA 세션의
    /// 터미널이 실제 사용자 앱을 조종한다.
    @Test func testTheMailboxLivesNextToTheSave() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)

        #expect(mailbox.requestURL.deletingLastPathComponent().standardizedFileURL
                == directory.standardizedFileURL)
        #expect(mailbox.replyURL.deletingLastPathComponent().standardizedFileURL
                == directory.standardizedFileURL)
        #expect(mailbox.requestURL != mailbox.replyURL, "요청과 답은 쓰는 쪽이 달라 파일도 다르다")
    }
}
