import Foundation
import Testing
@testable import PokeTokenBar

/// 앱 → 터미널 **화면 채널**. 라이브 기능(대전·레이드·교환…)은 요청 한 번으로 끝나지 않고 상태가
/// 계속 바뀌므로, 앱이 지금 화면을 스냅샷으로 내놓고 터미널이 그걸 그린다.
///
/// 파일마다 쓰는 쪽은 여전히 **하나**다 — 붙었다는 신호는 터미널만(`pokedoro-attach.json`),
/// 화면은 앱만(`pokedoro-view.json`) 쓴다. 요청·답 두 파일과 같은 규칙이다.
@Suite("PokedoroViewChannelTests")
struct PokedoroViewChannelTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeDirectory() -> URL { storeFixtureDirectory("pokedoro-view") }

    private func attachment(at offset: TimeInterval = 0, width: Int = 80) -> PokedoroAttachment {
        PokedoroAttachment(id: UUID(), width: width, height: 24,
                           at: Self.now.addingTimeInterval(offset))
    }

    private func snapshot(_ lines: [String], at offset: TimeInterval = 0) -> PokedoroViewSnapshot {
        PokedoroViewSnapshot(screen: "battle", title: "대전", lines: lines, keys: ["1 기술"],
                             writtenAt: Self.now.addingTimeInterval(offset))
    }

    // MARK: 붙어 있는가

    /// 방금 남긴 신호는 붙어 있는 것이다.
    @Test func testAFreshHeartbeatMeansTheTerminalIsWatching() {
        #expect(PokedoroViewChannel.isAttached(attachment(), now: Self.now))
    }

    /// **터미널은 인사하고 죽는다.** 창을 닫거나 kill 당하면 신호 파일은 그대로 남으므로, 나이를
    /// 안 보면 앱이 영원히 스냅샷을 쓰고 창도 안 띄운다.
    @Test func testAStaleHeartbeatMeansNobodyIsWatching() {
        let limit = PokedoroViewChannel.attachmentTimeout
        #expect(PokedoroViewChannel.isAttached(attachment(at: -limit), now: Self.now))
        #expect(!PokedoroViewChannel.isAttached(attachment(at: -limit - 1), now: Self.now))
    }

    /// 어긋남은 **양쪽 대칭**이다 — 미래로 적은 신호 하나로 나이 제한을 우회하면, 그 파일이
    /// 남아 있는 한 앱이 계속 붙어 있다고 믿는다(요청 우편함과 같은 규칙).
    @Test func testAHeartbeatDatedInTheFutureIsNotTrusted() {
        #expect(!PokedoroViewChannel.isAttached(attachment(at: 3 * 3600), now: Self.now))
    }

    @Test func testNoHeartbeatAtAllMeansNobodyIsWatching() {
        #expect(!PokedoroViewChannel.isAttached(nil, now: Self.now))
    }

    // MARK: 바뀔 때만 쓴다

    /// **같은 화면은 다시 쓰지 않는다.** 연출 프레임마다 쓰면 디스크가 갈리고, 터미널은 바뀐 게
    /// 없는데도 매번 다시 그린다. 시각만 다른 것은 "바뀐 것" 이 아니다.
    ///
    /// 단 **갱신 주기까지**다. 그 뒤로는 내용이 같아도 한 번 다시 쓴다 — 안 쓰면 안 바뀌는
    /// 화면(상대를 기다리는 대전)이 낡음 판정에 걸려 터미널에서 사라진다
    /// (`NetBattleTerminalTests.testAnUnchangedScreenIsRefreshedBeforeItGoesStale`).
    @Test func testAnUnchangedScreenIsNotWrittenAgain() {
        let first = snapshot(["HP 30/30"])
        let sameButSoon = snapshot(["HP 30/30"], at: PokedoroViewChannel.refreshInterval / 2)
        #expect(!PokedoroViewChannel.shouldWrite(sameButSoon, lastWritten: first))
    }

    @Test func testAChangedScreenIsWritten() {
        #expect(PokedoroViewChannel.shouldWrite(snapshot(["HP 12/30"]), lastWritten: snapshot(["HP 30/30"])))
    }

    /// 키 안내만 바뀌어도 써야 한다 — 누를 수 있는 것이 달라졌는데 화면이 옛 키를 계속 보여 주면
    /// 사용자는 먹지 않는 키를 누른다.
    @Test func testAChangedKeyRowIsWritten() {
        var next = snapshot(["HP 30/30"])
        next.keys = ["c 정산"]
        #expect(PokedoroViewChannel.shouldWrite(next, lastWritten: snapshot(["HP 30/30"])))
    }

    @Test func testTheFirstScreenIsAlwaysWritten() {
        #expect(PokedoroViewChannel.shouldWrite(snapshot(["HP 30/30"]), lastWritten: nil))
    }

    // MARK: 낡은 화면

    /// 앱이 죽으면 스냅샷은 마지막 상태로 **얼어붙는다.** 그대로 그리면 사용자는 멈춘 대전을
    /// 진행 중으로 읽는다 — 나이를 보고 낡았다고 말해야 한다.
    @Test func testASnapshotStopsBeingTrustedOnceTheAppGoesQuiet() {
        let limit = PokedoroViewChannel.snapshotTimeout
        #expect(!PokedoroViewChannel.isStale(snapshot(["x"], at: -limit), now: Self.now))
        #expect(PokedoroViewChannel.isStale(snapshot(["x"], at: -limit - 1), now: Self.now))
    }

    // MARK: 첫 생산자 — 집중 타이머

    /// 타이머는 **세이브에 없다**(`FocusTimer` 는 저장되지 않는다). 그래서 터미널이 스스로 만들 수
    /// 없고, 이 채널이 있어야 비로소 보인다 — 채널의 첫 생산자인 이유다.
    @Test func testTheFocusSnapshotCarriesWhatTheSaveCannotTell() throws {
        let snapshot = try #require(PokedoroViewChannel.focusSnapshot(phase: .focus, clockText: "12:34",
                                                                      completed: 3, goal: 4,
                                                                      isLongRest: false, now: Self.now))
        #expect(snapshot.lines.contains { $0.contains("12:34") })
        #expect(snapshot.lines.contains { $0.contains("3") }, "오늘 몇 번 했는지도 세이브 밖 값이다")
        #expect(snapshot.writtenAt == Self.now)
    }

    /// 단계마다 다른 말을 해야 한다 — 휴식 중에 "집중 중" 이라고 쓰면 사용자는 타이머를 잘못 읽는다.
    @Test func testTheFocusSnapshotNamesThePhaseItIsIn() throws {
        let focusing = PokedoroViewChannel.focusSnapshot(phase: .focus, clockText: "01:00",
                                                          completed: 0, goal: 4,
                                                          isLongRest: false, label: nil,
                                                          width: 80, now: Self.now)
        let resting = PokedoroViewChannel.focusSnapshot(phase: .rest, clockText: "01:00",
                                                         completed: 0, goal: 4,
                                                         isLongRest: false, label: nil,
                                                         width: 80, now: Self.now)
        #expect(focusing?.lines != resting?.lines)
    }

    /// 긴 휴식은 짧은 휴식과 **다르게 보여야 한다.** 15분을 쉬는데 화면이 그냥 "휴식 중" 이면
    /// 사용자는 타이머가 고장 났다고 읽는다 — 왜 긴지가 체인이 주는 보상이다.
    @Test func testTheFocusSnapshotTellsALongBreakFromAShortOne() throws {
        let short = try #require(PokedoroViewChannel.focusSnapshot(phase: .rest, clockText: "04:00",
                                                                    completed: 3, goal: 4,
                                                                    isLongRest: false, label: nil,
                                                                    width: 80, now: Self.now))
        let long = try #require(PokedoroViewChannel.focusSnapshot(phase: .rest, clockText: "14:00",
                                                                   completed: 4, goal: 4,
                                                                   isLongRest: true, label: nil,
                                                                   width: 80, now: Self.now))
        #expect(short.title != long.title)
        #expect(long.lines.first != short.lines.first, "제목만 바뀌고 본문이 그대로면 화면에서 구분되지 않는다")
    }

    /// 하루 목표는 진행도와 **함께** 나와야 한다. 완료 수만 있으면 "3회" 가 많은지 적은지 알 수 없다.
    @Test func testTheFocusSnapshotShowsProgressTowardTheDailyGoal() throws {
        let snapshot = try #require(PokedoroViewChannel.focusSnapshot(phase: .focus, clockText: "10:00",
                                                                       completed: 2, goal: 6,
                                                                       isLongRest: false, label: nil,
                                                                       width: 80, now: Self.now))
        #expect(snapshot.lines.contains { $0.contains("2") && $0.contains("6") },
                "오늘 진행도와 목표가 같은 줄에 있어야 한다")
    }

    // MARK: 작업 라벨

    /// 라벨을 붙여 시작한 세션은 터미널에서도 그 라벨로 보여야 한다. 팝오버에만 뜨면 같은 앱이
    /// 두 가지를 말하게 된다 — 터미널을 보는 동안 "무엇을 하기로 했는지" 가 사라진다.
    @Test func testTheFocusSnapshotCarriesTheSessionLabel() throws {
        let snapshot = try #require(PokedoroViewChannel.focusSnapshot(phase: .focus, clockText: "10:00",
                                                                       completed: 1, goal: 4,
                                                                       isLongRest: false, label: "PR 리뷰",
                                                                       width: 80, now: Self.now))
        #expect(snapshot.lines.contains { $0.contains("PR 리뷰") })
    }

    /// 라벨은 **집중 단계의 것**이다. 휴식 줄에 남으면 쉬는 동안에도 "지금 PR 리뷰 중" 이라고 말한다.
    @Test func testABreakDoesNotShowTheLabelOfTheSessionThatEnded() throws {
        let resting = try #require(PokedoroViewChannel.focusSnapshot(phase: .rest, clockText: "04:00",
                                                                      completed: 1, goal: 4,
                                                                      isLongRest: false, label: "PR 리뷰",
                                                                      width: 80, now: Self.now))
        #expect(!resting.lines.contains { $0.contains("PR 리뷰") })
    }

    /// 라벨은 **사용자가 친 문자열**이라 길이를 앱이 통제하지 못하고, 한글은 한 글자가 두 칸이다.
    /// 폭을 넘기면 터미널이 줄을 접고, 접히는 순간 그 아래 화면이 통째로 밀린다(`TUIText` 헤더).
    @Test func testALongLabelIsCutToTheTerminalWidth() throws {
        let width = 30
        let snapshot = try #require(
            PokedoroViewChannel.focusSnapshot(phase: .focus, clockText: "10:00", completed: 1, goal: 4,
                                              isLongRest: false,
                                              label: String(repeating: "가", count: 40),
                                              width: width, now: Self.now))
        for line in snapshot.lines {
            #expect(TUIText.displayWidth(line) <= width, "라벨 줄이 터미널 폭을 넘겼다: \(line)")
        }
    }

    /// 아무것도 안 돌 때는 **화면을 내놓지 않는다** — 빈 스냅샷을 쓰면 터미널이 매번 빈 줄을
    /// 그리고, 파일도 이유 없이 갱신된다.
    @Test func testAnIdleTimerProducesNoSnapshot() {
        #expect(PokedoroViewChannel.focusSnapshot(phase: .idle, clockText: "00:00",
                                                   completed: 0, goal: 4,
                                                   isLongRest: false, label: nil,
                                                   width: 80, now: Self.now) == nil)
    }

    // MARK: 파일

    /// 네 파일은 **쓰는 쪽이 서로 다르므로 경로도 다르다.** 겹치면 한 파일에 두 주체가 쓴다.
    @Test func testEveryChannelFileHasItsOwnPath() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)

        let paths = [mailbox.requestURL, mailbox.replyURL, mailbox.attachURL, mailbox.viewURL]
        #expect(Set(paths.map(\.lastPathComponent)).count == paths.count)
        for path in paths {
            #expect(path.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
                    "\(path.lastPathComponent) 이 세이브 옆에 없다")
        }
    }

    @Test func testTheAppReadsBackTheAttachmentTheTerminalWrote() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)

        let sent = attachment(width: 100)
        try mailbox.attach(sent)
        #expect(mailbox.attachment() == sent)
    }

    @Test func testTheTerminalReadsBackTheViewTheAppWrote() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)

        let sent = snapshot(["HP 30/30", "무엇을 할까?"])
        try mailbox.postView(sent)
        #expect(mailbox.view() == sent)
    }

    /// 없는 파일과 깨진 파일은 둘 다 `nil` 이다 — 앱의 1초 틱이 이 경로를 매번 밟으므로 여기서
    /// 죽으면 메뉴바 앱이 통째로 내려간다(요청 우편함과 같은 이유).
    @Test func testAnAbsentOrCorruptChannelFileIsIgnoredInsteadOfCrashing() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)

        #expect(mailbox.attachment() == nil)
        #expect(mailbox.view() == nil)

        try Data("{ not json".utf8).write(to: mailbox.attachURL)
        try Data("{ not json".utf8).write(to: mailbox.viewURL)
        #expect(mailbox.attachment() == nil)
        #expect(mailbox.view() == nil)
    }

    /// 터미널이 자기 폭을 실어 보내는 이유는 **앱이 줄을 만들기 때문**이다. 폭을 모르면 앱은
    /// 80칸을 가정하고, 좁은 창에서는 매 줄이 접혀 화면이 흘러간다.
    @Test func testTheAttachmentCarriesTheTerminalSize() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = PokedoroMailbox(directory: directory)
        try mailbox.attach(attachment(width: 132))

        #expect(mailbox.attachment()?.width == 132)
    }

    /// 폭이 0·음수로 들어오면(파이프·손으로 고친 파일) 앱이 그 값으로 줄을 만들 수 없다.
    /// 화면이 죽는 대신 쓸 수 있는 폭으로 접는다.
    @Test func testAnImpossibleWidthFallsBackToSomethingDrawable() {
        #expect(PokedoroViewChannel.drawableWidth(0) > 0)
        #expect(PokedoroViewChannel.drawableWidth(-5) > 0)
        #expect(PokedoroViewChannel.drawableWidth(132) == 132)
    }
}
