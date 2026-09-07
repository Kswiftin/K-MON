import Foundation
import Testing
@testable import PokeTokenBar

/// 터미널이 부탁한 웨이브 런 동작을 **앱이** 실행하는 자리.
///
/// 규칙은 `RogueRun`, 무엇을 고를 수 있는지는 `WaveRunScreen`, 네트워크는 `WaveRunLoader` 가
/// 든다. 여기서 재는 것은 **거절을 갈라 말하는가**와 **판이 실제로 움직였는가** 둘이다 —
/// 뭉뚱그린 거절은 사용자가 같은 명령을 반복하게 만들고, 성공으로 뭉갠 무동작은 사용자가
/// 일어나지 않은 일을 믿게 만든다.
///
/// 조회는 전부 스텁 `provider` 를 지난다(`CompanionStore.wildSnapshot`·`evolutionLine`).
/// 그래서 판을 여는 경로까지 **네트워크 없이** 돈다 — 예전처럼 화면이 `PokeAPIClient.shared` 를
/// 직접 부르면 이 파일 전체가 존재할 수 없다.
@MainActor
@Suite("WaveRunExecutorTests")
struct WaveRunExecutorTests {
    private func makeDirectory() -> URL { storeFixtureDirectory("wave-exec") }

    private func makeStore(in directory: URL) -> CompanionStore {
        CompanionStore(provider: WaveStubProvider(),
                       clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                       fileURL: directory.appendingPathComponent("state.json"))
    }

    private func execute(_ action: PokedoroRequest.Action,
                         on store: CompanionStore) async -> PokedoroReply {
        let request = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
        return await PokedoroRequestExecutor(timer: FocusTimer(), companion: store).execute(request)
    }

    // MARK: 판 열기

    /// 터미널에서 판을 **끝까지 열 수 있어야 한다.** 예전엔 상대를 받는 코드가 팝오버 화면의
    /// private 이라, 앱 창을 열지 않으면 판이 시작조차 안 됐다.
    @Test func testStartingARunFromTheTerminalOpensWaveOne() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let reply = await execute(.waveStart(starter: 1), on: store)

        #expect(reply.succeeded, "\(reply.message)")
        let run = try #require(store.rogueRun)
        #expect(run.wave == 1)
        #expect(run.party.count == 1)
        #expect(run.party[0].snapshot.speciesID == RogueRun.starterPool[0],
                "번호는 고정 목록의 순번이다 — 다른 종이 나오면 사용자가 고른 것과 다른 판이다")
        #expect(!run.battle.opponents.isEmpty, "상대 없는 판은 첫 정산에서 패배로 닫힌다")
    }

    /// **진행 중인 판을 덮어쓰지 않는다.** 판은 세이브에 남는 유일한 진행이고 되돌릴 수 없다 —
    /// 버리는 길은 확인을 받는 `wave forfeit` 하나뿐이어야 한다.
    @Test func testStartingAgainDoesNotThrowAwayTheRunInProgress() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        store.rogueRun = Self.run()
        let before = try #require(store.rogueRun).battle.mine[0].snapshot.name

        let reply = await execute(.waveStart(starter: 2), on: store)

        #expect(!reply.succeeded)
        #expect(store.rogueRun?.battle.mine[0].snapshot.name == before, "거절이 판을 갈아치웠다")
        #expect(reply.message.contains("forfeit"), "버리는 방법을 같이 말해야 다시 묻지 않는다")
    }

    /// 목록 밖 번호는 **무작위로 접지 않는다** — 사용자는 자기가 고른 것과 다른 스타터로 판을
    /// 시작한 줄 모른다.
    @Test func testAStarterNumberOutsideThePoolIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let reply = await execute(.waveStart(starter: RogueRun.starterPool.count + 1), on: store)

        #expect(!reply.succeeded)
        #expect(store.rogueRun == nil)
    }

    // MARK: 전투

    /// 판이 없는데 온 동작은 **여는 법을 알려 준다.** 침묵하면 사용자는 앱이 꺼진 것과 구분 못 한다.
    @Test func testActingWithoutARunSaysHowToOpenOne() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let reply = await execute(.waveMove(move: 1, target: nil), on: store)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("wave start"))
    }

    /// 기술 하나가 실제로 턴을 굴린다 — 1대1 이면 그 자리에서 해상된다(`WaveBattle.choose`).
    @Test func testAMoveResolvesTheTurnAndTheReplySaysWhatHappened() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        store.rogueRun = Self.run()

        let reply = await execute(.waveMove(move: 1, target: nil), on: store)

        #expect(reply.succeeded, "\(reply.message)")
        let run = try #require(store.rogueRun)
        #expect(!run.battle.events.isEmpty, "턴이 돌지 않았다")
        #expect(reply.message.contains("타격"), "무엇을 골랐는지 답에 없다")
    }

    /// PP 가 없는 번호는 **거절이다.** 조용히 다른 기술로 접으면 사용자는 자기가 쓰지 않은
    /// 기술이 나간 것을 로그에서야 본다.
    @Test func testAMoveWithoutPPIsRefusedInsteadOfSubstituted() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        var run = Self.run()
        run.debugDrainPP(moveIndex: 1)
        store.rogueRun = run
        let played = try #require(store.rogueRun).battle.events.count

        let reply = await execute(.waveMove(move: 2, target: nil), on: store)

        #expect(!reply.succeeded)
        #expect(store.rogueRun?.battle.events.count == played, "거절이 턴을 굴렸다")
    }

    /// 상대 칸 밖의 타겟은 거절이고, **몇 칸이 서 있는지** 같이 말한다.
    @Test func testATargetOutsideTheFieldIsRefusedWithTheSlotCount() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        store.rogueRun = Self.run()

        let reply = await execute(.waveMove(move: 1, target: 3), on: store)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("1"), "지금 서 있는 칸 수를 말해야 다음 값을 고를 수 있다")
    }

    /// 쓰러진 칸이 있으면 **그것부터**다. `WaveBattle` 은 그 상태에서 행동을 아예 안 받으므로,
    /// 성공으로 답하면 사용자는 턴이 지나간 줄 알고 다음 명령을 친다.
    @Test func testAMoveIsRefusedWhileASlotStillNeedsFilling() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        var run = Self.run(partySize: 2)
        run.debugFaintInBattle(0)
        store.rogueRun = run

        let reply = await execute(.waveMove(move: 1, target: nil), on: store)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("wave switch"), "무엇을 해야 하는지 말해야 한다")
    }

    // MARK: 교체

    /// 빈 칸 채우기는 **턴을 쓰지 않는다**(`WaveBattle.sendOut`). 턴을 쓰면 2대2 에서 한 마리를
    /// 잃을 때마다 남은 칸이 둘을 상대로 한 턴을 더 내주는 연쇄가 된다.
    @Test func testFillingAFaintedSlotDoesNotSpendTheTurn() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        var run = Self.run(partySize: 2)
        run.debugFaintInBattle(0)
        store.rogueRun = run
        let turn = try #require(store.rogueRun).battle.turn

        let reply = await execute(.waveSwitch(number: 2), on: store)

        #expect(reply.succeeded, "\(reply.message)")
        let after = try #require(store.rogueRun)
        #expect(after.battle.turn == turn, "기절 보충이 턴을 먹었다")
        #expect(after.battle.slotsNeedingSendOut.isEmpty)
    }

    /// 이미 필드에 선 개체로 바꾸는 것은 아무 일도 아니다 — 성공으로 답하면 사용자는 교체가
    /// 일어났다고 믿는다(파트너 교체와 같은 부류).
    @Test func testSwitchingToSomeoneAlreadyOnTheFieldIsRefused() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        store.rogueRun = Self.run(partySize: 2)

        let reply = await execute(.waveSwitch(number: 1), on: store)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("필드"))
    }

    /// 쓰러진 개체로는 못 바꾼다 — **사유를 갈라 말한다.** "이미 나와 있다" 와 "쓰러졌다" 는
    /// 다음에 할 일이 다르다.
    @Test func testSwitchingToAFaintedMemberSaysSoInsteadOfBeingVague() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        var run = Self.run(partySize: 3)
        run.debugFaint(2)
        store.rogueRun = run

        let reply = await execute(.waveSwitch(number: 3), on: store)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("쓰러져"))
    }

    // MARK: 볼

    /// 볼이 없을 때와 보스일 때를 **갈라 말한다.** `canThrowBall` 은 불리언 하나라 이유를
    /// 못 말하는데, 뭉뚱그리면 사용자는 볼을 보충하면 되는지 아닌지 모른다.
    @Test func testBallRefusalsAreToldApart() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        var empty = Self.run()
        empty.debugSetBalls(0)
        store.rogueRun = empty
        let noBalls = await execute(.waveBall(target: nil), on: store)
        #expect(!noBalls.succeeded)
        #expect(noBalls.message.contains("몬스터볼이 없다"))

        var boss = Self.run()
        boss.debugJump(toWave: RogueTuning.standard.bossEvery)
        store.rogueRun = boss
        let atBoss = await execute(.waveBall(target: nil), on: store)
        #expect(!atBoss.succeeded)
        #expect(atBoss.message.contains("보스"))
    }

    /// 성공하면 파티가 는다. 포획은 **이벤트를 만들지 않으므로**(상대가 조용히 빠진다) 이 답이
    /// 없으면 잡았다는 사실이 터미널 어디에도 뜨지 않는다.
    @Test func testCatchingAddsToThePartyAndSaysSo() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        var caught = false
        // 빈사 직전이면 성공률이 상한(95%)에 붙는다. 그래도 확률이라, 실패하면 판을 같은 조건으로
        // 되세워 다시 던진다 — rng 를 흔들지 않고 성공 경로를 반드시 지나기 위해서다.
        for _ in 0..<20 where !caught {
            var run = Self.run()
            run.debugSetOpponentHP(1)
            store.rogueRun = run
            let reply = await execute(.waveBall(target: nil), on: store)
            caught = reply.message.contains("잡았다")
        }
        #expect(caught, "20번 던져도 한 번도 안 잡혔다면 확률식이 아니라 경로가 막힌 것이다")
        #expect(try #require(store.rogueRun).party.count == 2)
    }

    // MARK: 보상·길

    @Test func testPickingARewardAppliesItAndMovesOn() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        var run = Self.run()
        run.debugSetStagePicking(offering: [.xSpeed])
        store.rogueRun = run

        let reply = await execute(.wavePick(number: 1), on: store)

        #expect(reply.succeeded, "\(reply.message)")
        let after = try #require(store.rogueRun)
        #expect(after.boosts.speed == 1, "고른 보상이 판에 안 걸렸다")
        #expect(after.stage == .routing)
    }

    /// 길을 고르면 **그 자리에서 다음 웨이브가 열린다.** 안 열면 판이 `.loadingWave` 에 서는데,
    /// 그 국면에는 사용자가 보낼 동작이 없다.
    @Test func testChoosingARouteOpensTheNextWave() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        var run = Self.run()
        run.debugSetStageRouting()
        store.rogueRun = run

        let reply = await execute(.waveRoute(.risky), on: store)

        #expect(reply.succeeded, "\(reply.message)")
        let after = try #require(store.rogueRun)
        #expect(after.wave == 2)
        #expect(after.stage == .battling, "길만 고르고 상대를 안 받으면 판이 멈춘다")
        #expect(after.route == .risky)
    }

    /// **상대를 받다 만 판은 다음 동작이 이어 받는다.** 네트워크가 한 번 흔들려 `.loadingWave` 에
    /// 멈춘 판은 그 국면에서 받는 동작이 없어, 이 되살림이 없으면 영영 멈춘다.
    @Test func testARunStalledWhileLoadingIsResumedByTheNextAction() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        var run = Self.run()
        run.debugSetStageRouting()
        run.take(.safe)          // → .loadingWave (상대는 아직 없다)
        store.rogueRun = run
        #expect(store.rogueRun?.stage == .loadingWave)

        let reply = await execute(.waveMove(move: 1, target: nil), on: store)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(store.rogueRun?.stage == .battling, "멈춘 판이 되살아나지 않았다")
    }

    // MARK: 포기

    @Test func testForfeitingDropsTheRun() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        store.rogueRun = Self.run()

        let reply = await execute(.waveForfeit, on: store)

        #expect(reply.succeeded)
        #expect(store.rogueRun == nil)
    }

    // MARK: 대기 시간

    /// **네트워크를 타는 동작만** 오래 기다린다. 전부 늘리면 앱이 꺼져 있을 때 모든 명령이
    /// 20초씩 셸을 붙잡고, 안 늘리면 판을 여는 명령이 3초에 포기해 늘 "응답 없음" 이 된다.
    @Test func testOnlyTheNetworkBoundWaveActionsWaitLonger() {
        for action: PokedoroRequest.Action in [.waveStart(starter: nil), .waveRoute(.safe),
                                               .waveMove(move: 1, target: nil), .waveBall(target: nil)] {
            #expect(PokedoroCLI.timeout(for: action) == PokedoroCLI.hatchReplyTimeout,
                    "\(action.name) 이 3초에 포기하면 판을 여는 명령이 늘 실패로 보인다")
        }
        for action: PokedoroRequest.Action in [.wavePick(number: 1), .waveSwitch(number: 1),
                                               .waveForfeit] {
            #expect(PokedoroCLI.timeout(for: action) == PokedoroCLI.replyTimeout)
        }
    }

    // MARK: 픽스처

    /// 전투 중인 판. 상대는 한 마리다.
    static func run(partySize: Int = 1) -> RogueRun {
        RogueRun(party: (0..<partySize).map { snapshot(speciesID: 1, name: "내\($0 + 1)") },
                 opponents: [snapshot(speciesID: 4, name: "야생")], seed: 11)
    }

    static func snapshot(speciesID: Int, name: String) -> BattleSnapshot {
        BattleSnapshot(
            speciesID: speciesID, name: name, trainer: nil, level: 5, nature: nil, isShiny: false,
            types: [.normal],
            base: BattleStats(hp: 100, atk: 100, def: 50, spa: 100, spd: 50, spe: 100),
            moves: [MoveSpec(id: 1, names: ["ko": "타격", "en": "Hit"], type: .normal, power: 40,
                             damageClass: .physical, accuracy: nil, pp: 20),
                    MoveSpec(id: 2, names: ["ko": "울음", "en": "Growl"], type: .normal, power: 0,
                             damageClass: .status, accuracy: nil, pp: 40)])
    }
}

/// 네트워크 없이 판을 여는 스텁. `moveSet` 까지 덮는 이유는 그것이 `PokeProviding` 에 있어야
/// 하는 이유 그대로다 — 없으면 이 스텁이 야생 하나를 만들 때마다 실제 PokéAPI 로 나간다.
private struct WaveStubProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [baseSpeciesID: ["ko": "종\(baseSpeciesID)",
                                                         "en": "S\(baseSpeciesID)"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 1, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: id, captureRate: 255) }
    func battleProfile(speciesID: Int) async throws -> PokemonBattleProfile {
        PokemonBattleProfile(speciesID: speciesID,
                             stats: BattleStats(hp: 60, atk: 60, def: 60, spa: 60, spd: 60, spe: 60),
                             types: [.normal])
    }
    func moveSet(speciesID: Int, level: Int, types: [PokemonType]) async -> [MoveSpec] {
        [MoveSpec(id: 1, names: ["ko": "타격", "en": "Hit"], type: .normal, power: 40,
                  damageClass: .physical, accuracy: nil, pp: 20)]
    }
}
