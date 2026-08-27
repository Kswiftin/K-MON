import XCTest
@testable import PokeTokenBar

/// 포켓로그식 런 코어(프로토타입). 잠그는 것은 **웨이브 진행 규칙과 파티 이월**이다 —
/// 전투 자체는 `TeamPracticeBattle`·`BattleEngine` 이 이미 자기 테스트로 잠겨 있다.
final class RogueRunTests: XCTestCase {

    private func snapshot(_ id: Int, level: Int = 5, hp: Int = 100, speed: Int = 100,
                          types: [PokemonType] = [.normal]) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "M\(id)", trainer: "T", level: level, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: hp, atk: 100, def: 50, spa: 100, spd: 50, spe: speed),
                       moves: [MoveSpec(id: 1, names: ["en": "Hit"], type: .normal, power: 200,
                                        damageClass: .physical, accuracy: nil, pp: 20)])
    }

    /// 내가 반드시 선공하고 한 방에 끝나는 상황 — 승리 경로를 rng 흔들림 없이 밟는다.
    private func run(partySize: Int = 2, seed: UInt64 = 1) -> RogueRun {
        RogueRun(party: (0..<partySize).map { snapshot(1 + $0, speed: 200) },
                 opponents: [snapshot(99, level: 5, hp: 1, speed: 1)],
                 seed: seed)
    }

    // MARK: 난이도 곡선

    func testBossWavesAreEveryFourth() {
        XCTAssertEqual((1...12).filter { RogueRun.isBoss(wave: $0) }, [4, 8, 12])
    }

    func testOpponentLevelRisesAndBossesAddMore() {
        XCTAssertEqual(RogueRun.opponentLevel(wave: 1), 6)
        XCTAssertEqual(RogueRun.opponentLevel(wave: 3), 10)
        XCTAssertEqual(RogueRun.opponentLevel(wave: 4), 16)    // 보스 +4
        XCTAssertEqual(RogueRun.opponentLevel(wave: 8), 24)
        XCTAssertEqual(RogueRun.opponentLevel(wave: 12), 34)   // 최종 +6
    }

    // MARK: 진행

    func testWinningOffersThreeDistinctModifiers() {
        var run = self.run()
        run.useMove(0)
        XCTAssertEqual(run.stage, .picking)
        XCTAssertEqual(run.offers.count, RogueRun.offerCount)
        XCTAssertEqual(Set(run.offers).count, RogueRun.offerCount)
    }

    func testPickingAdvancesTheWaveAndWaitsForOpponents() {
        var run = self.run()
        run.useMove(0)
        run.pick(run.offers[0])
        XCTAssertEqual(run.wave, 2)
        XCTAssertEqual(run.stage, .loadingWave)
        run.beginWave(opponents: [snapshot(98, hp: 1, speed: 1)])
        XCTAssertEqual(run.stage, .battling)
    }

    /// 제시되지 않은 보상은 고를 수 없다 — 화면이 목록 밖의 값을 넣어도 웨이브가 넘어가지 않는다.
    func testPickIgnoresModifiersThatWereNotOffered() {
        var run = self.run()
        run.useMove(0)
        let notOffered = RunModifier.allCases.first { !run.offers.contains($0) }!
        run.pick(notOffered)
        XCTAssertEqual(run.wave, 1)
        XCTAssertEqual(run.stage, .picking)
    }

    /// 파티 HP 는 웨이브를 넘어 이월된다 — 이게 이 판의 유일한 자원이다.
    func testPartyDamageCarriesIntoTheNextWave() {
        var run = RogueRun(party: [snapshot(1, speed: 1)],
                           opponents: [snapshot(99, level: 5, hp: 1, speed: 200)],
                           seed: 7)
        run.useMove(0)   // 상대가 먼저 때린 뒤 내가 쓰러뜨린다
        guard run.stage == .picking else { return XCTFail("승리하지 못했다: \(run.stage)") }
        let carried = run.party[0].hp
        XCTAssertLessThan(carried, run.party[0].stats.hp)
        run.pick(run.offers.first { $0 != .potion && $0 != .candy } ?? run.offers[0])
        run.beginWave(opponents: [snapshot(98, hp: 1, speed: 1)])
        XCTAssertEqual(run.battle.mine[0].hp, carried)
    }

    /// 앞 웨이브에서 1번이 쓰러졌으면 다음 웨이브는 **살아 있는 칸**으로 시작한다.
    func testNextWaveLeadsWithALivingMember() {
        var run = self.run(partySize: 2)
        run.useMove(0)
        run.pick(run.offers[0])
        var fainted = run
        fainted.debugFaint(0)
        fainted.beginWave(opponents: [snapshot(98, hp: 1, speed: 1)])
        XCTAssertEqual(fainted.battle.myActive, 1)
    }

    func testFinalWaveVictoryClearsTheRun() {
        var run = self.run()
        run.debugJump(toWave: RogueRun.finalWave)
        run.useMove(0)
        XCTAssertEqual(run.stage, .cleared)
        XCTAssertTrue(run.offers.isEmpty)
    }

    func testPartyWipeFailsTheRun() {
        var run = RogueRun(party: [snapshot(1, hp: 1, speed: 1)],
                           opponents: [snapshot(99, level: 50, speed: 200)],
                           seed: 3)
        run.useMove(0)
        XCTAssertEqual(run.stage, .failed)
    }

    // MARK: 보상 효과

    func testPotionHealsTheLivingOnly() {
        var side = BattleSide(snapshot(1))
        side.hp = 1
        var dead = BattleSide(snapshot(2))
        dead.hp = 0
        var run = RogueRun(party: [snapshot(1), snapshot(2)], opponents: [snapshot(99)], seed: 1)
        run.debugSetParty([side, dead])
        run.debugApply(.potion)
        XCTAssertGreaterThan(run.party[0].hp, 1)
        XCTAssertEqual(run.party[1].hp, 0)
    }

    func testReviveBringsBackOneFaintedMember() {
        var dead = BattleSide(snapshot(2))
        dead.hp = 0
        var run = RogueRun(party: [snapshot(1), snapshot(2)], opponents: [snapshot(99)], seed: 1)
        run.debugSetParty([BattleSide(snapshot(1)), dead])
        run.debugApply(.revive)
        XCTAssertEqual(run.party[1].hp, run.party[1].stats.hp / 2)
    }

    /// 레벨업은 최대 HP 를 올린다 — **비율**로 옮기지 않으면 다친 개체가 조용히 손해를 본다.
    func testLevelUpKeepsTheDamageRatio() {
        var side = BattleSide(snapshot(1, level: 10))
        side.hp = side.stats.hp / 2
        let next = RogueRun.leveledUp(side, by: 2)
        XCTAssertGreaterThan(next.stats.hp, side.stats.hp)
        XCTAssertEqual(Double(next.hp) / Double(next.stats.hp), 0.5, accuracy: 0.02)
    }

    /// 쓰러진 개체는 레벨이 올라도 살아나지 않는다.
    func testLevelUpDoesNotReviveTheFainted() {
        var side = BattleSide(snapshot(1, level: 10))
        side.hp = 0
        XCTAssertEqual(RogueRun.leveledUp(side, by: 2).hp, 0)
    }

    func testElixirRestoresPowerPoints() {
        var side = BattleSide(snapshot(1))
        side.pp[0] = 0
        var run = RogueRun(party: [snapshot(1)], opponents: [snapshot(99)], seed: 1)
        run.debugSetParty([side])
        run.debugApply(.elixir)
        XCTAssertEqual(run.party[0].pp[0], run.party[0].moves[0].pp)
    }

    func testCleanseClearsStatusAndConfusion() {
        var side = BattleSide(snapshot(1))
        side.status = .burn
        side.statusCounter = 2
        side.confusionTurns = 3
        var run = RogueRun(party: [snapshot(1)], opponents: [snapshot(99)], seed: 1)
        run.debugSetParty([side])
        run.debugApply(.cleanse)
        XCTAssertNil(run.party[0].status)
        XCTAssertEqual(run.party[0].statusCounter, 0)
        XCTAssertEqual(run.party[0].confusionTurns, 0)
    }
}
