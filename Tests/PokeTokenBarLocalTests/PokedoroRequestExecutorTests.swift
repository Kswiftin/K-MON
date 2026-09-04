import Foundation
import Testing
@testable import PokeTokenBar

/// 터미널 요청을 **앱이** 실행하는 자리. 판정은 `PokedoroSessionGate`, 실제 변경은 세 단일
/// 진입점(`startFocusSession`·`claimAdventure`·`stopFocusSession`), 문구만 여기서 만든다.
///
/// 이 타입이 따로 있는 이유는 `PokeTokenBarApp` 에 테스트가 닿지 않기 때문이다 — 터미널 쪽
/// (`TUITerminal`·`TUIWatch`)에 판단을 두지 않는 것과 같은 규칙이다.
@MainActor
@Suite("PokedoroRequestExecutorTests")
struct PokedoroRequestExecutorTests {
    /// 시계를 움직일 수 있어야 한다 — 고정 시계로는 모험이 영영 안 끝나 정산 경로를 못 밟는다.
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    /// 스토어를 만드는 픽스처라 **디렉토리 단위로** 격리한다 — `CompanionStore` 는 이름이 고정된
    /// 곁방 세이브(기억 앨범·대화·웨이브 런)를 상태 파일 옆에 만들고, temp 는 실행 사이에도
    /// 지워지지 않는다(#232).
    private func makeDirectory() -> URL { storeFixtureDirectory("pokedoro-exec") }

    /// 동행이 있는 저장소. `hatch` 없이는 `currentSpeciesID` 가 비어 시작이 항상 거절된다.
    private func makeStore(in directory: URL, clock: Clock, withCompanion: Bool = true) async -> CompanionStore {
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                           names: [1: ["ko": "포1", "en": "P1", "ja": "ポ1"]])
        let store = CompanionStore(provider: ExecutorStubProvider(value: line),
                                   clock: { clock.now },
                                   fileURL: directory.appendingPathComponent("state.json"),
                                   rng: ExecutorRNG(seed: 7))
        if withCompanion { await store.hatch(baseID: 1) }
        return store
    }

    private func request(_ action: PokedoroRequest.Action, at date: Date) -> PokedoroRequest {
        PokedoroRequest(id: UUID(), action: action, requestedAt: date)
    }

    // MARK: 시작

    @Test func testStartPutsTheCompanionOnAnAdventureAndReportsIt() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)
        let timer = FocusTimer()

        let sent = request(.start(minutes: 25), at: clock.now)
        let reply = PokedoroRequestExecutor(timer: timer, companion: store).execute(sent)

        #expect(reply.succeeded)
        #expect(reply.id == sent.id, "답의 id 가 다르면 터미널이 영영 자기 답을 못 받는다")
        #expect(reply.message.contains("25"))
        #expect(store.activeAdventure != nil)
        #expect(timer.isRunning, "타이머와 모험은 함께 움직인다")
    }

    /// 이미 도는 세션이 있으면 거절이고, **모험은 손대지 않는다**. 거절이 상태를 바꾸면
    /// 사용자는 실패했다고 들은 채로 진행을 잃는다.
    @Test func testStartIsRefusedWhileASessionIsRunningAndChangesNothing() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)
        let timer = FocusTimer()
        let executor = PokedoroRequestExecutor(timer: timer, companion: store)
        _ = executor.execute(request(.start(minutes: 25), at: clock.now))
        let started = store.activeAdventure

        let second = executor.execute(request(.start(minutes: 90), at: clock.now))

        #expect(!second.succeeded)
        #expect(store.activeAdventure == started, "거절이 진행 중인 모험을 갈아치웠다")
    }

    /// **대화 경로에서는 도달할 수 없던 분기다** — 거기선 주인 게이트가 먼저 막는다. 터미널엔
    /// 주인 개념이 없으므로 여기가 `.noCompanion` 의 첫 실사용처다.
    @Test func testStartIsRefusedWithoutACompanion() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock, withCompanion: false)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.start(minutes: 25), at: clock.now))

        #expect(!reply.succeeded)
        #expect(store.activeAdventure == nil)
    }

    /// 요청 파일은 손으로 고칠 수 있는 **신뢰경계**다. 목록 밖의 분을 그대로 믿으면 화면이
    /// 제시하지 않는 길이(600분)를 터미널만 켤 수 있게 된다 — 대화가 이미 같은 이유로 접는다.
    @Test func testAnOutOfRangeLengthIsFoldedToAnOfferedOne() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.start(minutes: 600), at: clock.now))

        #expect(reply.succeeded)
        let run = try #require(store.activeAdventure)
        let minutes = Int((run.endsAt.timeIntervalSince(run.startedAt) / 60).rounded())
        #expect(PokemonChatTool.focusMinutes.contains(minutes), "화면이 안 주는 길이가 켜졌다: \(minutes)")
    }

    /// 분이 아예 없는 `start` 요청(손으로 쓴 파일)도 크래시하지 않고 기본 길이로 간다.
    @Test func testAStartRequestWithoutMinutesFallsBackToAnOfferedLength() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.start(minutes: nil), at: clock.now))

        #expect(reply.succeeded)
        #expect(store.activeAdventure != nil)
    }

    // MARK: 정산

    /// 정산 답은 **지갑 증가분을 설명해야** 한다. 숫자를 빼면 사용자는 얼마를 받았는지 앱을
    /// 열어야만 알 수 있어, 터미널에서 정산할 이유가 없어진다.
    @Test func testClaimSettlesTheFinishedAdventureAndReportsThePayout() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)
        let executor = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
        _ = executor.execute(request(.start(minutes: 25), at: clock.now))
        let before = store.availableTokens
        clock.now = clock.now.addingTimeInterval(26 * 60)   // 모험을 끝낸다

        let reply = executor.execute(request(.claim, at: clock.now))

        #expect(reply.succeeded)
        #expect(store.activeAdventure == nil)
        #expect(store.availableTokens > before)
        #expect(reply.message.contains(TUIRender.number(store.availableTokens - before)),
                "지급액이 답에 없다: \(reply.message)")
    }

    /// 아직 나가 있는 모험은 정산되지 않는다 — 시간을 안 채우고 보상을 받는 길이 된다.
    @Test func testClaimIsRefusedWhileTheAdventureIsStillRunning() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)
        let executor = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
        _ = executor.execute(request(.start(minutes: 90), at: clock.now))
        let before = store.availableTokens

        let reply = executor.execute(request(.claim, at: clock.now))

        #expect(!reply.succeeded)
        #expect(store.activeAdventure != nil)
        #expect(store.availableTokens == before)
    }

    @Test func testClaimIsRefusedWithNoAdventureAtAll() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.claim, at: clock.now))

        #expect(!reply.succeeded)
    }

    // MARK: 종료

    /// **모험 단독(B)을 따로 본다.** 앱을 다시 연 직후가 그 상태다 — `FocusTimer` 는 저장되지
    /// 않아 타이머가 `.idle` 인데 모험은 디스크에 남는다. 타이머만 보면 그 모험을 영영 못 치운다.
    @Test func testStopWorksWhenOnlyTheAdventureSurvivedAnAppRestart() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)
        _ = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.start(minutes: 25), at: clock.now))

        // 앱이 다시 뜬 상황: 타이머는 새로 만들어져 idle 이고 모험만 남아 있다.
        let restarted = FocusTimer()
        let reply = PokedoroRequestExecutor(timer: restarted, companion: store)
            .execute(request(.stop, at: clock.now))

        #expect(reply.succeeded)
        #expect(store.activeAdventure == nil)
    }

    // MARK: 아이템

    /// 재고가 없으면 **정직하게 실패한다.** 성공으로 뭉개면 사용자는 쓴 줄 알고 가방을 다시 본다.
    @Test func testUsingAnItemTheBagDoesNotHaveIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.use(item: .rareCandy), at: clock.now))

        #expect(!reply.succeeded)
        #expect(reply.message.contains("없다"), "왜 안 됐는지 말해야 한다: \(reply.message)")
    }

    /// 재고가 있으면 **실제 사용 경로**로 간다 — 여기서 인벤토리를 직접 깎으면 화면 버튼과 다른
    /// 경로가 되어 소모·연출·진화가 어긋난다.
    @Test func testUsingARareCandyGoesThroughTheRealPathAndSpendsIt() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)
        store.debugAddCandy(1)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.use(item: .rareCandy), at: clock.now))

        #expect(reply.succeeded)
        #expect(store.rareCandyCount == 0, "재고가 줄지 않았으면 실제 경로를 안 밟았다")
    }

    /// 보유형(부적)은 "지금 쓴다" 는 개념이 없다. 재고 부족과 **다른 문구**로 답해야 한다 —
    /// 사용자가 사러 가야 하는지, 애초에 쓰는 물건이 아닌지 갈린다.
    @Test func testAHeldItemSaysItIsNotUsedThatWay() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.use(item: .shinyCharm), at: clock.now))

        #expect(!reply.succeeded)
        #expect(!reply.message.contains("없다"), "재고 문구를 재사용하면 안 된다: \(reply.message)")
    }

    // MARK: 진화

    /// 대기 중인 진화가 없으면 실패다. 성공으로 돌려주면 화면엔 아무 일도 없는데 터미널만
    /// "진화했다" 고 말한다.
    @Test func testEvolveWithNothingPendingIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.evolve, at: clock.now))

        #expect(!reply.succeeded)
    }

    // MARK: 파트너 교체

    /// 로스터에 없는 번호는 거절이다 — 그대로 인덱스로 쓰면 배열 밖을 읽는다.
    @Test func testSwitchingToANumberThatIsNotInTheRosterIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.switchCompanion(number: 99), at: clock.now))

        #expect(!reply.succeeded)
        #expect(reply.message.contains("99"), "어느 번호가 없는지 말해야 한다: \(reply.message)")
    }

    /// 이미 나와 있는 개체로 바꾸는 것은 **아무 일도 아니다.** 성공으로 답하면 사용자는 교체가
    /// 일어났다고 믿는다.
    @Test func testSwitchingToTheCompanionAlreadyOutIsRefused() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)
        let active = try #require(store.chatRosterEntries.first { $0.isActive })

        let number = TUIRender.printedRosterNumber(index: active.index)
        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.switchCompanion(number: number), at: clock.now))

        #expect(!reply.succeeded)
    }

    // MARK: 별명

    /// 별명은 붙고, **답이 실제로 붙은 이름을 말한다** — 클램프가 걸렸으면 사용자가 그것을 봐야 한다.
    @Test func testRenamingTheCompanionAppliesAndReportsTheName() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.rename(nickname: "리자몽"), at: clock.now))

        #expect(reply.succeeded)
        #expect(reply.message.contains("리자몽"))
        #expect(store.chatRosterEntries.first { $0.isActive }?.name == "리자몽")
    }

    /// 세이브 경계보다 긴 이름은 **경계와 같은 값으로 접는다.** 여기서 더 길게 통과시키면 방금
    /// 넣은 이름이 로드 때 잘려, 사용자는 자기가 지은 이름이 왜 달라졌는지 모른다.
    @Test func testAnOverlongNicknameIsClampedToTheSaveBoundary() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let long = String(repeating: "가", count: SaveTransfer.maxNameLength + 12)
        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.rename(nickname: long), at: clock.now))

        #expect(reply.succeeded)
        let applied = store.chatRosterEntries.first { $0.isActive }?.name
        #expect(applied?.count == SaveTransfer.maxNameLength)
        #expect(reply.message.contains(applied ?? "?"), "접힌 이름을 그대로 보여 줘야 한다")
    }

    /// 줄바꿈·제어문자는 **한 줄 화면을 깨뜨린다.** 요청 파일은 손으로 고칠 수 있으므로 파서가
    /// 아니라 실행기가 막아야 한다.
    @Test func testANicknameWithNewlinesIsFlattened() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.rename(nickname: "피카\n츄\t!"), at: clock.now))

        #expect(reply.succeeded)
        let applied = store.chatRosterEntries.first { $0.isActive }?.name ?? ""
        #expect(!applied.contains("\n"))
        #expect(!applied.contains("\t"))
    }

    /// 동행이 없으면 이름을 붙일 대상이 없다 — 조용히 성공하면 사용자는 이름이 붙은 줄 안다.
    @Test func testRenamingWithoutACompanionIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock, withCompanion: false)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.rename(nickname: "피카"), at: clock.now))

        #expect(!reply.succeeded)
    }

    // MARK: 상점

    /// 잔액이 모자라면 **정직하게 실패한다.** 성공으로 뭉개면 사용자는 산 줄 알고 가방을 뒤진다.
    @Test func testBuyingWithoutEnoughStardustIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = await PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.buy(good: .item(.rareCandy), quantity: 1), at: clock.now))

        #expect(!reply.succeeded)
        #expect(reply.message.contains("별의조각"), "왜 안 됐는지 말해야 한다: \(reply.message)")
    }

    /// 살 수 있으면 **실제 구매 경로**로 간다 — 지갑이 줄고 가방이 는다.
    @Test func testBuyingSpendsStardustAndFillsTheBag() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)
        store.debugAddStardust(500_000)
        let before = store.availableTokens

        let reply = await PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.buy(good: .item(.rareCandy), quantity: 2), at: clock.now))

        #expect(reply.succeeded)
        #expect(store.rareCandyCount == 2)
        #expect(store.availableTokens < before, "지갑이 줄지 않았으면 실제 경로를 안 밟았다")
    }

    // MARK: 부화

    /// 부화할 알이 없으면 실패다. 성공으로 답하면 사용자는 파트너가 생긴 줄 안다.
    @Test func testHatchingWithNothingReadyIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = await PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.hatch, at: clock.now))

        #expect(!reply.succeeded)
    }

    // MARK: 방생

    /// 함께 다니는 개체는 놓아줄 수 없다 — `releaseMon` 은 박스만 본다. 성공으로 답하면
    /// 사용자는 파트너가 사라진 줄 안다.
    @Test func testReleasingTheActiveCompanionIsRefused() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)
        let active = try #require(store.chatRosterEntries.first { $0.isActive })

        let reply = await PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.release(number: TUIRender.printedRosterNumber(index: active.index)),
                             at: clock.now))

        #expect(!reply.succeeded)
        #expect(store.chatRosterEntries.contains { $0.id == active.id }, "개체가 사라졌다")
    }

    /// 목록에 없는 번호도 거절이다 — 그대로 인덱스로 쓰면 배열 밖을 읽는다.
    @Test func testReleasingANumberThatIsNotInTheRosterIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = await PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.release(number: 99), at: clock.now))

        #expect(!reply.succeeded)
        #expect(reply.message.contains("99"))
    }

    // MARK: 왕복

    /// 세 조각(우편함·실행 판정·실행기)을 **앱이 배선하는 그 순서 그대로** 밟는다. 조각별
    /// 테스트는 각자 통과하면서도 배선이 어긋날 수 있다 — 앱 루트에는 테스트가 안 닿으므로
    /// 그 순서를 지키는 자리는 여기뿐이다.
    @Test func testTheAppSideRoundTripFromRequestFileToReplyFile() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)
        let mailbox = PokedoroMailbox(directory: directory)
        let timer = FocusTimer()

        // 터미널이 하는 일.
        let sent = request(.start(minutes: 50), at: clock.now)
        try mailbox.send(sent)

        // 앱이 1초 틱에서 하는 일.
        let pending = try #require(mailbox.pendingRequest())
        #expect(PokedoroRequestBus.shouldExecute(pending, now: clock.now, lastExecutedID: nil))
        try mailbox.post(PokedoroRequestExecutor(timer: timer, companion: store).execute(pending))

        // 터미널이 받는 것.
        let reply = try #require(mailbox.reply(to: sent.id))
        #expect(reply.succeeded)
        #expect(store.activeAdventure != nil)

        // 같은 요청이 다음 틱에서 다시 실행되면 안 된다 — 파일은 그대로 남아 있다.
        #expect(!PokedoroRequestBus.shouldExecute(pending, now: clock.now, lastExecutedID: pending.id))
    }

    @Test func testStopIsRefusedWhenNothingIsRunning() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)

        let reply = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
            .execute(request(.stop, at: clock.now))

        #expect(!reply.succeeded)
    }
}

private struct ExecutorStubProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        id == value.baseID ? BaseSpecies(id: id, captureRate: 255) : nil
    }
}

private struct ExecutorRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
