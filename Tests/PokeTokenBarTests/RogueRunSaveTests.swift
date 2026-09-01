import XCTest
@testable import PokeTokenBar

/// 진행 중인 판을 디스크로 옮기는 경로(`RogueRunSave`). 판이 30 웨이브라 앱을 끄면 사라지는 것이
/// 실제 손실이 됐다. 잠그는 것은 **되살린 판이 저장한 판과 같은가**와 **못 믿을 파일을 버리는가**다.
@MainActor
final class RogueRunSaveTests: XCTestCase {

    private let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                               rarity: .common, names: [1: ["en": "One", "ko": "하나"]])

    private func snapshot(_ id: Int, level: Int = 5, hp: Int = 100, speed: Int = 100)
    -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "M\(id)", trainer: "T", level: level, nature: nil,
                       isShiny: false, types: [.normal],
                       base: BattleStats(hp: hp, atk: 100, def: 50, spa: 100, spd: 50, spe: speed),
                       moves: [MoveSpec(id: 1, names: ["en": "Hit"], type: .normal, power: 200,
                                        damageClass: .physical, accuracy: nil, pp: 20)])
    }

    private func makeRun(seed: UInt64 = 5) -> RogueRun {
        RogueRun(party: [snapshot(1, hp: 900, speed: 200), snapshot(2, hp: 900, speed: 200)],
                 opponents: [snapshot(99, hp: 900, speed: 1)], seed: seed)
    }

    /// 한 방에 눕는 상대. `makeRun` 의 상대는 900 기준 HP 라 한 턴으로는 안 죽는다 — 보상 화면까지
    /// 가야 하는 테스트가 `useMove` 한 번으로 이겼다고 전제하면, 전제가 데미지 계산(난수 계수·급소)에
    /// 매인 채로 조용히 깨진다.
    private func makeWinnableRun(seed: UInt64 = 5) -> RogueRun {
        RogueRun(party: [snapshot(1, hp: 900, speed: 200), snapshot(2, hp: 900, speed: 200)],
                 opponents: [snapshot(99, hp: 1, speed: 1)], seed: seed)
    }

    private func roundTrip(_ run: RogueRun) throws -> RogueRun {
        let data = try JSONEncoder().encode(run.saveForm)
        let save = try JSONDecoder().decode(RogueRunSave.self, from: data)
        return try XCTUnwrap(RogueRun(save: save))
    }

    /// 판의 자원은 HP·PP 다 — 이월이 이 판의 난이도 전부라, 되살리면서 채워 주면 저장이 회복이 된다.
    func testCarriedResourcesSurviveTheRoundTrip() throws {
        var original = makeRun()
        original.useMove(0)                    // 한 턴을 실제로 두어 HP·PP·턴 수를 흔든다
        let restored = try roundTrip(original)
        XCTAssertEqual(restored.wave, original.wave)
        XCTAssertEqual(restored.stage, original.stage)
        XCTAssertEqual(restored.balls, original.balls)
        XCTAssertEqual(restored.party.map(\.hp), original.party.map(\.hp))
        XCTAssertEqual(restored.party.map(\.pp), original.party.map(\.pp))
        XCTAssertEqual(restored.battle.turn, original.battle.turn)
        XCTAssertEqual(restored.battle.opponents.map(\.hp), original.battle.opponents.map(\.hp))
    }

    /// 상태이상·랭크·혼란은 전투를 이어 두는 값이다. 지우고 되살리면 앱을 껐다 켜는 것이
    /// 만병통치제가 된다.
    func testStatusAndStagesSurvive() throws {
        var original = makeRun()
        original.debugAfflict(.poison)
        original.useMove(0)
        let restored = try roundTrip(original)
        XCTAssertEqual(restored.battle.mine.map(\.status), original.battle.mine.map(\.status))
        XCTAssertEqual(restored.battle.opponents[0].stages, original.battle.opponents[0].stages)
    }

    /// 지속 강화는 런이 들고 **개체에 도장으로** 들어간다. 되살릴 때 다시 찍지 않으면 화면에는
    /// 강화가 그대로인데 데미지에는 안 걸린다 — 눈으로는 절대 안 보이는 어긋남이다.
    func testBoostsAreStampedBackOntoTheParty() throws {
        var original = makeRun()
        var boosts = RunBoosts()
        boosts.typeDamage[.normal] = 2
        boosts.critStages = 1
        boosts.leftovers = 3
        original.debugSetBoosts(boosts)
        let restored = try roundTrip(original)
        XCTAssertEqual(restored.boosts, boosts)
        XCTAssertEqual(restored.party.map(\.runBoosts), Array(repeating: boosts,
                                                              count: restored.party.count))
        XCTAssertEqual(restored.battle.mine.map(\.runBoosts),
                       Array(repeating: boosts, count: restored.battle.mine.count))
    }

    /// rng 는 **소비한 뒤의 상태**를 싣는다. 씨앗을 실으면 앱을 껐다 켤 때마다 같은 보상 목록이
    /// 다시 나와, 마음에 드는 뽑기가 나올 때까지 재시작하는 것이 최적 전략이 된다.
    func testTheRandomStreamContinuesInsteadOfRestarting() throws {
        var original = makeWinnableRun()
        original.useMove(0)                    // 보상 화면 — 여기까지 rng 를 소비했다
        XCTAssertEqual(original.stage, .picking, "테스트 전제: 이겨서 보상 화면이어야 한다")
        var restored = try roundTrip(original)
        XCTAssertEqual(restored.offers, original.offers, "저장 시점의 제시 목록이 바뀌면 안 된다")
        restored.pick(restored.offers[0])
        var control = original
        control.pick(control.offers[0])
        XCTAssertEqual(restored.stage, control.stage)
        // 두 장을 받는 길이 아니면 다음 뽑기는 다음 웨이브다 — 어느 쪽이든 rng 상태가 같아야
        // 이어지는 판이 저장 전과 같은 값을 낸다.
        XCTAssertEqual(restored.saveForm.rngState, control.saveForm.rngState)
    }

    // MARK: 못 믿을 파일

    /// 필드 칸이 범위 밖이면 그 칸의 개체를 읽는 순간 크래시다. 판은 소모품이라 버린다.
    func testAnOutOfRangeFieldSlotIsRejected() {
        var save = makeRun().saveForm
        save.battle.myField = [9]
        XCTAssertNil(RogueRun(save: save))
    }

    /// 같은 개체가 두 칸에 선 파일도 버린다 — 되살리면 그 개체가 한 턴에 두 번 움직이고
    /// 데미지도 두 몫으로 들어간다.
    func testTheSameMemberOnTwoSlotsIsRejected() {
        var save = makeRun().saveForm
        save.battle.myField = [0, 0]
        XCTAssertNil(RogueRun(save: save))
    }

    /// 칸이 셋인 파일(손편집·미래 형식)도 버린다 — 필드 상한은 둘이다.
    func testMoreFieldSlotsThanTheFormatAllowsIsRejected() {
        var save = RogueRun(party: [snapshot(1), snapshot(2), snapshot(3)],
                            opponents: [snapshot(99)], seed: 5).saveForm
        save.battle.myField = [0, 1, 2]
        XCTAssertNil(RogueRun(save: save))
    }

    /// 판 길이는 밸런스 손잡이라 줄어들 수 있다. 그때 남아 있던 옛 판은 화면에 "40/30" 으로 뜬다.
    func testAWaveBeyondTheRunLengthIsRejected() {
        var save = makeRun().saveForm
        save.wave = RogueRun.finalWave + 1
        XCTAssertNil(RogueRun(save: save))
    }

    /// 모르는 형식 판은 반쯤 읽어 되살리지 않는다.
    func testAnUnknownFormatVersionIsRejected() {
        var save = makeRun().saveForm
        save.version = RogueRunSave.currentVersion + 1
        XCTAssertNil(RogueRun(save: save))
    }

    /// 고를 것이 없는 보상 화면은 버튼 없는 화면이다 — 그 판에 갇힌다.
    func testARewardScreenWithNothingToPickIsRejected() {
        var original = makeWinnableRun()
        original.useMove(0)
        var save = original.saveForm
        XCTAssertEqual(save.stage, .picking, "테스트 전제: 이겨서 보상 화면이어야 한다")
        save.offers = []
        XCTAssertNil(RogueRun(save: save))
    }

    /// 손편집된 HP 는 경계에서 자른다 — 최대치를 넘으면 HP 바가 칸을 넘어 그려지고, 음수면
    /// 살아 있는 개체가 기절로 읽힌다.
    func testHandEditedHitPointsAreClamped() throws {
        var save = makeRun().saveForm
        save.party[0].hp = 9_999
        save.battle.mine[0].hp = -5
        let restored = try XCTUnwrap(RogueRun(save: save))
        XCTAssertEqual(restored.party[0].hp, restored.party[0].stats.hp)
        XCTAssertEqual(restored.battle.mine[0].hp, 0)
    }

    // MARK: 저장소 왕복

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-run-\(UUID().uuidString)")
            .appendingPathComponent("companion-state.json")
    }

    private func store(at url: URL) -> CompanionStore {
        CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                       fileURL: url, rng: SeededRNG(seed: 7))
    }

    /// 앱을 껐다 켜도 판이 이어진다 — 이 기능의 전부다.
    func testTheRunSurvivesARestart() throws {
        let url = tempURL()
        let first = store(at: url)
        var run = makeRun()
        run.useMove(0)
        first.rogueRun = run

        let second = store(at: url)
        let restored = try XCTUnwrap(second.rogueRun)
        XCTAssertEqual(restored.wave, run.wave)
        XCTAssertEqual(restored.party.map(\.hp), run.party.map(\.hp))
    }

    /// 끝난 판을 비우면 파일도 사라진다. 남겨 두면 다음 기동이 끝난 판을 되살려 결과 화면이 다시 뜬다.
    func testClearingTheRunRemovesTheFile() {
        let url = tempURL()
        let first = store(at: url)
        first.rogueRun = makeRun()
        first.rogueRun = nil
        XCTAssertNil(store(at: url).rogueRun)
    }

    /// 못 읽는 파일은 **지운다** — 그대로 두면 켤 때마다 같은 실패를 반복한다.
    func testACorruptFileIsDiscardedInsteadOfRetriedForever() throws {
        let url = tempURL()
        _ = store(at: url)          // 디렉토리를 만든다
        let runURL = url.deletingLastPathComponent()
            .appendingPathComponent(CompanionStorageLocations.waveRunFileName)
        try Data("{\"nope\":1}".utf8).write(to: runURL)
        XCTAssertNil(store(at: url).rogueRun)
        XCTAssertFalse(FileManager.default.fileExists(atPath: runURL.path))
    }
}
