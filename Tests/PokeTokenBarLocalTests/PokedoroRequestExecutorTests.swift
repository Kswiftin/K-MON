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

    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pokedoro-exec-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

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

    private func request(_ verb: PokedoroRequest.Verb, minutes: Int? = nil,
                         at date: Date) -> PokedoroRequest {
        PokedoroRequest(id: UUID(), verb: verb, minutes: minutes, requestedAt: date)
    }

    // MARK: 시작

    @Test func testStartPutsTheCompanionOnAnAdventureAndReportsIt() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = await makeStore(in: directory, clock: clock)
        let timer = FocusTimer()

        let sent = request(.start, minutes: 25, at: clock.now)
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
        _ = executor.execute(request(.start, minutes: 25, at: clock.now))
        let started = store.activeAdventure

        let second = executor.execute(request(.start, minutes: 90, at: clock.now))

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
            .execute(request(.start, minutes: 25, at: clock.now))

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
            .execute(request(.start, minutes: 600, at: clock.now))

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
            .execute(request(.start, minutes: nil, at: clock.now))

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
        _ = executor.execute(request(.start, minutes: 25, at: clock.now))
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
        _ = executor.execute(request(.start, minutes: 90, at: clock.now))
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
            .execute(request(.start, minutes: 25, at: clock.now))

        // 앱이 다시 뜬 상황: 타이머는 새로 만들어져 idle 이고 모험만 남아 있다.
        let restarted = FocusTimer()
        let reply = PokedoroRequestExecutor(timer: restarted, companion: store)
            .execute(request(.stop, at: clock.now))

        #expect(reply.succeeded)
        #expect(store.activeAdventure == nil)
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
