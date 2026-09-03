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

    private func request(verb: PokedoroRequest.Verb = .start, minutes: Int? = 25,
                         at offset: TimeInterval = 0,
                         id: UUID = UUID()) -> PokedoroRequest {
        PokedoroRequest(id: id, verb: verb, minutes: minutes,
                        requestedAt: Self.now.addingTimeInterval(offset))
    }

    // MARK: 실행 판정

    @Test func testAFreshRequestRuns() {
        #expect(PokedoroRequestBus.shouldExecute(request(), now: Self.now, lastExecutedID: nil))
    }

    /// **이 테스트가 이 가드의 존재 이유다.** 앱이 꺼진 사이 터미널이 남긴 요청을 나이 제한 없이
    /// 실행하면, 사용자가 세 시간 전에 포기한 90분 집중이 앱을 켜는 순간 시작된다 — 그 시각엔
    /// 사용자가 무엇 때문에 타이머가 켜졌는지 알 방법이 없다.
    @Test func testAStaleRequestLeftBehindWhileTheAppWasClosedNeverRuns() {
        let threeHoursAgo = request(minutes: 90, at: -3 * 3600)
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
        let previous = request(verb: .claim, minutes: nil)
        let next = request()
        #expect(PokedoroRequestBus.shouldExecute(next, now: Self.now, lastExecutedID: previous.id))
    }

    // MARK: 파일 왕복

    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pokedoro-bus-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 터미널이 쓴 것을 앱이 그대로 읽는다. 두 프로세스가 같은 인코딩 규약을 쓰는지 보는 유일한 자리다.
    @Test func testTheAppReadsBackExactlyWhatTheTerminalWrote() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)

        let sent = request(verb: .start, minutes: 90)
        try mailbox.send(sent)

        #expect(mailbox.pendingRequest() == sent)
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
