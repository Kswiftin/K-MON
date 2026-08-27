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
    private func makeRun(partySize: Int = 2, seed: UInt64 = 1) -> RogueRun {
        RogueRun(party: (0..<partySize).map { snapshot(1 + $0, speed: 200) },
                 opponents: [snapshot(99, level: 5, hp: 1, speed: 1)],
                 seed: seed)
    }

    // MARK: 난이도 곡선

    func testBossWavesAreEveryFourth() {
        XCTAssertEqual((1...12).filter { RogueRun.isBoss(wave: $0) }, [4, 8, 12])
    }

    func testOpponentLevelRisesAndBossesAddMore() {
        XCTAssertEqual(RogueRun.opponentLevel(wave: 1), 5)
        XCTAssertEqual(RogueRun.opponentLevel(wave: 3), 9)
        XCTAssertEqual(RogueRun.opponentLevel(wave: 4), 14)    // 보스 +3
        XCTAssertEqual(RogueRun.opponentLevel(wave: 8), 22)
        XCTAssertEqual(RogueRun.opponentLevel(wave: 12), 32)   // 최종 +5
    }

    /// 야생은 파티 기준선(스타터 5 + 승리마다 2)과 같은 레벨이어야 한다 — 야생조차 늘 위에 있으면
    /// 한 마리짜리 파티가 매 웨이브 손해를 쌓고 되돌릴 수단이 없다.
    func testWildWavesMatchThePartyLevelBaseline() {
        for wave in 1...RogueRun.finalWave where !RogueRun.isBoss(wave: wave) {
            XCTAssertEqual(RogueRun.opponentLevel(wave: wave), 3 + 2 * wave, "wave \(wave)")
        }
    }

    // MARK: 상대 종 티어

    private func stats(total: Int) -> BattleStats {
        let each = total / 6
        return BattleStats(hp: each, atk: each, def: each, spa: each, spd: each,
                           spe: total - each * 5)
    }

    /// 웨이브 1 에 슬라킹(670)·전설이 나오던 결함의 회귀 — 상한이 티어 순으로 오르고, 최종 보스
    /// 상한(640)도 전설 대부분(660~720)을 막는다.
    func testBaseStatCapRisesWithTheWaveAndKeepsLegendariesOut() {
        XCTAssertFalse(RogueRun.isFairOpponent(baseStats: stats(total: 670), wave: 1))
        XCTAssertTrue(RogueRun.isFairOpponent(baseStats: stats(total: 318), wave: 1))
        XCTAssertLessThan(RogueRun.baseStatTotalCap(wave: 3), RogueRun.baseStatTotalCap(wave: 5))
        XCTAssertLessThan(RogueRun.baseStatTotalCap(wave: 5), RogueRun.baseStatTotalCap(wave: 9))
        XCTAssertEqual(RogueRun.baseStatTotalCap(wave: 12), 640)
        XCTAssertFalse(RogueRun.isFairOpponent(baseStats: stats(total: 680), wave: 12))
    }

    /// 보스는 같은 웨이브의 야생보다 센 종까지 받는다.
    func testBossWavesAllowStrongerSpeciesThanTheirTier() {
        XCTAssertGreaterThan(RogueRun.baseStatTotalCap(wave: 4), RogueRun.baseStatTotalCap(wave: 3))
    }

    /// 하한이 없으면 최종 보스로 잉어킹(200)이 나온다.
    func testTooWeakSpeciesAreRejectedForLateWaves() {
        XCTAssertFalse(RogueRun.isFairOpponent(baseStats: stats(total: 200), wave: 12))
    }

    // MARK: 진행

    func testWinningOffersThreeDistinctModifiers() {
        var run = makeRun()
        run.useMove(0)
        XCTAssertEqual(run.stage, .picking)
        XCTAssertEqual(run.offers.count, RogueRun.offerCount)
        XCTAssertEqual(Set(run.offers).count, RogueRun.offerCount)
    }

    func testPickingAdvancesTheWaveAndWaitsForOpponents() {
        var run = makeRun()
        run.useMove(0)
        run.pick(run.offers[0])
        XCTAssertEqual(run.wave, 2)
        XCTAssertEqual(run.stage, .loadingWave)
        run.beginWave(opponents: [snapshot(98, hp: 1, speed: 1)])
        XCTAssertEqual(run.stage, .battling)
    }

    /// 제시되지 않은 보상은 고를 수 없다 — 화면이 목록 밖의 값을 넣어도 웨이브가 넘어가지 않는다.
    func testPickIgnoresModifiersThatWereNotOffered() {
        var run = makeRun()
        run.useMove(0)
        let notOffered = RunModifier.allCases.first { !run.offers.contains($0) }!
        run.pick(notOffered)
        XCTAssertEqual(run.wave, 1)
        XCTAssertEqual(run.stage, .picking)
    }

    /// 파티 HP 는 웨이브를 넘어 이월된다 — 이게 이 판의 유일한 자원이다.
    func testPartyDamageCarriesIntoTheNextWave() {
        // 상대 첫 타를 **버티고** 반격으로 끝내야 이월을 볼 수 있다. 종족 HP 100 이면 레벨 5 유효
        // HP 가 26 인데 상대 일격이 급소까지 겹치면 그걸 넘어 쓰러진다 — 그래서 HP 를 크게 둔다.
        var run = RogueRun(party: [snapshot(1, hp: 900, speed: 1)],
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
        var run = makeRun(partySize: 2)
        run.useMove(0)
        run.pick(run.offers[0])
        var fainted = run
        fainted.debugFaint(0)
        fainted.beginWave(opponents: [snapshot(98, hp: 1, speed: 1)])
        XCTAssertEqual(fainted.battle.myActive, 1)
    }

    func testFinalWaveVictoryClearsTheRun() {
        var run = makeRun()
        run.debugJump(toWave: RogueRun.finalWave)
        run.useMove(0)
        XCTAssertEqual(run.stage, .cleared)
        XCTAssertTrue(run.offers.isEmpty)
    }

    /// 보스를 넘으면 살아 있는 파티가 완전 회복한다 — 이월 자원이 HP·PP 뿐이라 회복 지점이 없으면
    /// 후반 웨이브가 되돌릴 수 없는 소화가 된다. 야생 웨이브에서는 회복하지 않는다(이월이 자원이다).
    func testBossVictoryRestoresTheParty() {
        func damagedWin(atWave wave: Int) -> RogueRun {
            var run = RogueRun(party: [snapshot(1, hp: 900, speed: 1)],
                               opponents: [snapshot(99, level: 5, hp: 1, speed: 200)],
                               seed: 7)
            run.debugJump(toWave: wave)
            run.useMove(0)   // 상대가 먼저 때린 뒤 내가 쓰러뜨린다
            return run
        }
        let boss = damagedWin(atWave: 4)
        XCTAssertTrue(RogueRun.isBoss(wave: 4))
        XCTAssertEqual(boss.party[0].hp, boss.party[0].stats.hp)

        let wild = damagedWin(atWave: 3)
        XCTAssertLessThan(wild.party[0].hp, wild.party[0].stats.hp,
                          "야생 웨이브에서 회복하면 HP 이월이 자원이 아니게 된다")
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

    // MARK: 화면 계약 (소스 가드)

    /// 런은 `CompanionStore` 가 들어야 한다. 뷰의 `@State` 로 들면 팝오버를 닫는 순간 판이 사라진다
    /// (실제로 그렇게 유실됐다). 로직 테스트로는 잡을 수 없어 소스에서 기계적으로 확인한다.
    func testRunStateLivesInTheStore() throws {
        let source = try Self.viewSource()
        XCTAssertTrue(source.contains("store.rogueRun"),
                      "런을 store 에서 읽고 써야 팝오버를 닫아도 이어진다")
        XCTAssertFalse(source.contains("case running("),
                       "진행 중인 런을 뷰 상태(enum)로 되들이면 창을 닫을 때 사라진다")
    }

    /// 기술 버튼·PP 배지·로그는 기존 배틀과 **같은 렌더러**로 그려야 한다. 직접 그리면 같은 기술이
    /// 화면마다 다른 색으로 보인다.
    func testRunBattleUsesTheSharedArenaRenderer() throws {
        let source = try Self.viewSource()
        XCTAssertTrue(source.contains("BattleArenaView("),
                      "던전 런도 공용 배틀 렌더러를 쓴다")
        XCTAssertFalse(source.contains("Text(\"PP "),
                       "PP 표시를 직접 그리면 공용 렌더러의 색·배지 규칙에서 벗어난다")
    }

    /// 종을 전 범위에서 균등 추첨하면 웨이브 1 에 슬라킹·전설이 나온다. 뽑기가 코어 밖(뷰)에 있어
    /// 로직 테스트로 못 잡으므로 소스에서 기계적으로 확인한다.
    func testWildDrawFiltersBySpeciesTier() throws {
        let source = try Self.viewSource()
        XCTAssertTrue(source.contains("RogueRun.isFairOpponent("),
                      "야생 뽑기는 웨이브 티어(종족값 상한)를 지나야 한다")
    }

    /// 재생기를 빼면 기절·피격이 화면에 뜨기 전에 필드가 다음 포켓몬으로 갈아탄다 — 사용자에게는
    /// "맞아서 쓰러진" 순간이 없고 그냥 교체된 것처럼 보인다(실제 리포트).
    func testRunBattleDrivesTheReplayAnimator() throws {
        let source = try Self.viewSource()
        XCTAssertTrue(source.contains("BattleAnimator()"), "런 전투도 기존 배틀과 같은 재생기를 쓴다")
        XCTAssertTrue(source.contains("animator.playedCount"),
                      "로그는 재생이 닿은 지점까지만 보여야 한다")
        XCTAssertTrue(source.contains("overlay: animator.overlay"),
                      "피격·기절 연출을 렌더러에 넘겨야 한다")
    }

    /// 화면 문구는 전부 `L.t` 를 지나야 한다 — 프로토타입이라 영어 리터럴로 두었더니 한국어 사용자에게
    /// 그대로 영어가 나갔다.
    func testRunScreenHasNoUntranslatedSentences() throws {
        let source = try Self.viewSource()
        var offenders: [String] = []
        for marker in ["Text(\"", "Button(\""] {
            for segment in source.components(separatedBy: marker).dropFirst() {
                guard let first = segment.first, first.isLetter, first.isASCII else { continue }
                offenders.append(marker + segment.prefix(40))
            }
        }
        XCTAssertTrue(offenders.isEmpty, "번역을 지나지 않은 문구: \(offenders)")
    }

    private static func viewSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/PokeTokenBarTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // <repo>
        return try String(contentsOf: root.appendingPathComponent("Sources/PokeTokenBar/UI/RogueRunView.swift"),
                          encoding: .utf8)
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
