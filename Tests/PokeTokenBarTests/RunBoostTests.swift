import XCTest
@testable import PokeTokenBar

/// 런 동안 **쌓이는** 강화(`RunBoosts`). 소모형 보상(회복·부활)과 달리 웨이브를 넘어 남으므로,
/// 잠글 것은 두 가지다 — ① 엔진이 실제로 그 값을 읽는가 ② 파티가 바뀌는 모든 경로에서 강화가
/// 개체에 도장 찍히는가(잡아서 합류한 개체, 다음 웨이브, 진행 중인 전투).
final class RunBoostTests: XCTestCase {

    private func snapshot(_ id: Int, level: Int = 5, hp: Int = 100, speed: Int = 100,
                          types: [PokemonType] = [.normal]) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "M\(id)", trainer: "T", level: level, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: hp, atk: 100, def: 50, spa: 100, spd: 50, spe: speed),
                       moves: [MoveSpec(id: 1, names: ["en": "Hit"], type: .normal, power: 60,
                                        damageClass: .physical, accuracy: nil, pp: 20)])
    }

    // MARK: 엔진이 값을 읽는가

    /// 타입 강화는 **그 타입 기술만** 올린다. 같은 seed 로 두 번 굴려 비교하므로 난수 폭·급소가
    /// 같은 값이고, 차이는 강화 하나뿐이다.
    func testTypeBoostRaisesDamageOfThatTypeOnly() {
        let attacker = BattleSide(snapshot(1))
        let defender = BattleSide(snapshot(2, hp: 900))
        let move = attacker.moves[0]

        var plain = SplitMix64(seed: 5)
        let base = BattleEngine.resolveAttack(attacker: attacker, defender: defender,
                                             move: move, rng: &plain)

        var boosted = attacker
        boosted.runBoosts.typeDamage[.normal] = 1
        var rng = SplitMix64(seed: 5)
        let withBoost = BattleEngine.resolveAttack(attacker: boosted, defender: defender,
                                                  move: move, rng: &rng)
        XCTAssertGreaterThan(withBoost.damage, base.damage)

        var other = attacker
        other.runBoosts.typeDamage[.water] = 1
        var otherRNG = SplitMix64(seed: 5)
        let unrelated = BattleEngine.resolveAttack(attacker: other, defender: defender,
                                                  move: move, rng: &otherRNG)
        XCTAssertEqual(unrelated.damage, base.damage, "다른 타입 강화가 노말 기술을 올렸다")
    }

    /// 스택이 쌓일수록 더 오른다 — 중첩되지 않으면 두 번째 장이 꽝이 된다.
    func testTypeBoostStacks() {
        let defender = BattleSide(snapshot(2, hp: 900))
        func damage(stacks: Int) -> Int {
            var attacker = BattleSide(snapshot(1))
            if stacks > 0 { attacker.runBoosts.typeDamage[.normal] = stacks }
            var rng = SplitMix64(seed: 11)
            return BattleEngine.resolveAttack(attacker: attacker, defender: defender,
                                              move: attacker.moves[0], rng: &rng).damage
        }
        XCTAssertLessThan(damage(stacks: 1), damage(stacks: 2))
        XCTAssertLessThan(damage(stacks: 2), damage(stacks: 3))
    }

    /// 급소 강화는 기술의 급소 단계에 더해진다. 3 스택이면 표상 100% 라 seed 와 무관하게 급소다 —
    /// 확률 분기를 재지 않고 훅이 걸렸는지만 잠근다.
    func testFocusLensStacksIntoCritStage() {
        var attacker = BattleSide(snapshot(1))
        attacker.runBoosts.critStages = 3
        let defender = BattleSide(snapshot(2, hp: 900))
        for seed in UInt64(1)...20 {
            var rng = SplitMix64(seed: seed)
            let outcome = BattleEngine.resolveAttack(attacker: attacker, defender: defender,
                                                     move: attacker.moves[0], rng: &rng)
            XCTAssertTrue(outcome.isCritical, "seed \(seed)")
        }
    }

    /// 먹다남은음식은 턴 끝에 최대 HP 의 1/16 을 회복한다. 강화가 없으면 한 값도 달라지지 않는다.
    func testLeftoversHealsAtEndOfTurn() {
        var side = BattleSide(snapshot(1, hp: 900))
        let full = side.stats.hp
        side.hp = full / 2
        var plain = side
        XCTAssertTrue(BattleEngine.endOfTurnResidual(&plain, actor: .a).isEmpty)
        XCTAssertEqual(plain.hp, full / 2)

        side.runBoosts.leftovers = 1
        let events = BattleEngine.endOfTurnResidual(&side, actor: .a)
        XCTAssertEqual(side.hp, full / 2 + max(1, full / 16))
        XCTAssertEqual(events, [.heal(.a, amount: max(1, full / 16))])
    }

    /// 만피에서는 회복 이벤트를 내지 않는다 — 매 턴 "회복했다" 줄이 로그를 덮으면 실제로 무엇이
    /// 일어났는지 읽을 수 없다.
    func testLeftoversIsSilentAtFullHP() {
        var side = BattleSide(snapshot(1, hp: 900))
        side.runBoosts.leftovers = 2
        XCTAssertTrue(BattleEngine.endOfTurnResidual(&side, actor: .a).isEmpty)
        XCTAssertEqual(side.hp, side.stats.hp)
    }

    /// 회복이 잔뎀보다 **먼저**다(본가와 같다). 순서가 뒤집히면 화상 데미지로 쓰러진 뒤 회복이
    /// 들어가 죽은 개체가 살아난다.
    func testLeftoversHealsBeforeStatusDamage() {
        var side = BattleSide(snapshot(1, hp: 900))
        let full = side.stats.hp
        side.hp = max(1, full / 16)     // 화상 1턴이면 쓰러지는 HP
        side.status = .burn
        side.runBoosts.leftovers = 1
        let events = BattleEngine.endOfTurnResidual(&side, actor: .a)
        XCTAssertTrue(side.isAlive, "회복이 잔뎀 뒤로 밀려 쓰러졌다")
        XCTAssertEqual(events.first, .heal(.a, amount: max(1, full / 16)))
        XCTAssertTrue(events.contains(.damage(.a, amount: max(1, full / 16), cause: .burn)))
    }

    // MARK: 런이 강화를 개체에 도장 찍는가

    /// 뽑기 3장에는 **적어도 한 장의 지속형**이 든다. 소모형만 뜨면 그 웨이브의 선택이 다시
    /// "회복 타이밍" 하나로 접혀, 12 웨이브를 지나도 판이 첫 웨이브와 같은 모양으로 남는다.
    func testOffersAlwaysIncludeAPersistentModifier() {
        for seed in UInt64(1)...200 {
            var rng = SplitMix64(seed: seed)
            let offers = RogueRun.drawOffers(&rng)
            XCTAssertEqual(offers.count, RogueRun.offerCount, "seed \(seed)")
            XCTAssertEqual(Set(offers).count, RogueRun.offerCount, "seed \(seed)")
            XCTAssertTrue(offers.contains(where: \.isPersistent), "seed \(seed): 소모형만 나왔다")
        }
    }

    /// 고른 강화는 **진행 중인 전투에도** 걸린다. 파티에만 찍으면 다음 웨이브에서야 듣기 시작해
    /// 방금 고른 보상이 안 듣는 것처럼 보인다.
    func testPickedBoostAppliesToPartyAndOngoingBattle() {
        var run = winnableRun()
        winWave(&run)
        guard run.stage == .picking else { return XCTFail("승리하지 못했다: \(run.stage)") }
        run.debugOffer(.leftovers)
        run.pick(.leftovers)
        XCTAssertEqual(run.boosts.leftovers, 1)
        run.take(.safe)
        run.beginWave(opponents: [snapshot(98, hp: 1, speed: 1)])
        XCTAssertEqual(run.party[0].runBoosts.leftovers, 1)
        XCTAssertEqual(run.battle.mine[0].runBoosts.leftovers, 1)
    }

    /// 타입 강화는 **선두의 첫 타입**을 올린다 — 무엇이 올라가는지 고르기 전에 알아야 빌드가 된다.
    func testTypeBoostFollowsTheLeadType() {
        var run = RogueRun(party: [snapshot(1, hp: 900, speed: 200, types: [.water, .flying])],
                           opponents: [snapshot(99, level: 5, hp: 1, speed: 1)],
                           seed: 3)
        XCTAssertEqual(run.boostableType, .water)
        winWave(&run)
        guard run.stage == .picking else { return XCTFail("승리하지 못했다: \(run.stage)") }
        run.debugOffer(.typeBoost)
        run.pick(.typeBoost)
        XCTAssertEqual(run.boosts.typeDamage[.water], 1)
        XCTAssertNil(run.boosts.typeDamage[.flying])
    }

    /// 잡아서 합류한 개체도 강화를 받는다. 파티가 늘어나는 경로가 도장 자리를 안 지나면 잡은
    /// 포켓몬만 강화 없이 싸운다(화면에는 강화가 걸린 것으로 보인다).
    func testCaughtMemberInheritsRunBoosts() {
        for seed in UInt64(1)...200 {
            var run = RogueRun(party: [snapshot(1, hp: 4000, speed: 200)],
                               opponents: [snapshot(99, hp: 100, speed: 1)],
                               seed: seed)
            run.debugSetBoosts(RunBoosts(typeDamage: [.normal: 2], critStages: 1, leftovers: 1))
            run.debugSetOpponentHP(1)
            guard run.throwBall() else { continue }
            XCTAssertEqual(run.party.count, 2)
            XCTAssertEqual(run.party[1].runBoosts.typeDamage[.normal], 2)
            XCTAssertEqual(run.party[1].runBoosts.critStages, 1)
            return
        }
        XCTFail("no seed produced a catch")
    }

    /// 레벨업은 스냅샷으로 개체를 **다시 만든다** — 강화를 옮기지 않으면 이상한사탕 한 장이
    /// 그때까지 쌓은 지속 강화를 통째로 지운다(화면에는 그대로 남아 있는 것으로 보인다).
    /// 웨이브 승리마다 레벨이 오르므로 이 경로는 판마다 11번 밟힌다.
    func testLevelUpKeepsBoosts() {
        var side = BattleSide(snapshot(1))
        side.runBoosts = RunBoosts(typeDamage: [.normal: 2], critStages: 1, leftovers: 1)
        let leveled = RogueRun.leveledUp(side, by: 2)
        XCTAssertEqual(leveled.snapshot.level, 7)
        XCTAssertEqual(leveled.runBoosts, side.runBoosts, "레벨업이 런 강화를 지웠다")
    }

    /// 승리 정산(레벨업 포함)을 지난 뒤에도 강화가 파티에 남는다 — 위 단위 테스트가 잠그는 규칙이
    /// 실제 웨이브 경로에서도 유지되는지 본다.
    func testBoostsSurviveWaveVictory() {
        var run = winnableRun()
        run.debugSetBoosts(RunBoosts(typeDamage: [.normal: 1], critStages: 0, leftovers: 2))
        winWave(&run)
        guard run.stage == .picking else { return XCTFail("승리하지 못했다: \(run.stage)") }
        XCTAssertEqual(run.party[0].runBoosts.leftovers, 2)
        XCTAssertEqual(run.party[0].runBoosts.typeDamage[.normal], 1)
    }

    /// 네트워크 대전·체육관은 강화를 채우지 않는다 — 기본값이 비어 있어야 그 판들의 데미지가
    /// 한 값도 달라지지 않는다(`rulesVersion` 을 건드리지 않는 근거다).
    func testBoostsAreEmptyByDefault() {
        XCTAssertTrue(BattleSide(snapshot(1)).runBoosts.isEmpty)
    }

    /// 상대를 눕힐 때까지 때린다 — 한 방에 죽지 않는 상대라 승리 경로를 도달점으로 잡는다.
    private func winWave(_ run: inout RogueRun, limit: Int = 10) {
        for _ in 0..<limit where run.stage == .battling { run.useMove(0) }
    }

    private func winnableRun() -> RogueRun {
        RogueRun(party: [snapshot(1, hp: 900, speed: 200)],
                 opponents: [snapshot(99, level: 5, hp: 1, speed: 1)],
                 seed: 4)
    }
}

/// 런 중 진화. 종 데이터는 네트워크를 지나므로 코어가 잠그는 것은 두 가지다 —
/// ① 판 안에서 만족시킬 수 있는 조건만 진화로 인정하는가 ② 진화가 이월 자원을 손해로 바꾸지 않는가.
final class RunEvolutionTests: XCTestCase {

    private func snapshot(_ id: Int, level: Int = 16, hp: Int = 100) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "M\(id)", trainer: "T", level: level, nature: nil,
                       isShiny: false, types: [.normal],
                       base: BattleStats(hp: hp, atk: 100, def: 50, spa: 100, spd: 50, spe: 100),
                       moves: [MoveSpec(id: 1, names: ["en": "Hit"], type: .normal, power: 60,
                                        damageClass: .physical, accuracy: nil, pp: 20)])
    }

    private func child(_ id: Int, level: Int? = nil, trigger: String? = "level-up",
                       item: String? = nil, heldItem: String? = nil,
                       knownMove: Int? = nil, timeOfDay: String? = nil,
                       children: [EvoNode] = []) -> EvoNode {
        EvoNode(speciesID: id, children: children, evolutionLevel: level, evolutionTrigger: trigger,
                evolutionItem: item, evolutionHeldItem: heldItem, evolutionGender: nil,
                evolutionKnownMoveID: knownMove, evolutionTimeOfDay: timeOfDay)
    }

    func testLevelUpEvolutionNeedsTheLevel() {
        let node = EvoNode(speciesID: 1, children: [child(2, level: 16)])
        XCTAssertNil(RogueRun.levelUpEvolution(from: node, level: 15))
        XCTAssertEqual(RogueRun.levelUpEvolution(from: node, level: 16)?.speciesID, 2)
    }

    /// 런에는 아이템·교환·기술·시간대 축이 없다. 무시하고 진화시키면 돌 없이 피카츄가 라이츄가 된다.
    func testConditionsTheRunCannotSatisfyAreNotEvolutions() {
        let node = EvoNode(speciesID: 1, children: [
            child(2, trigger: "use-item", item: "thunder-stone"),
            child(3, level: 5, heldItem: "kings-rock"),
            child(4, level: 5, knownMove: 33),
            child(5, level: 5, timeOfDay: "night"),
            child(6, trigger: "trade"),
        ])
        XCTAssertNil(RogueRun.levelUpEvolution(from: node, level: 99))
    }

    /// 보스 승리는 레벨을 3 올린다 — 두 단계 조건을 한 번에 넘겼으면 **높은 쪽**으로 간다.
    /// 낮은 쪽을 고르면 한 웨이브에 한 단계씩만 올라 최종 형태에 영영 닿지 않는다.
    func testTheHighestSatisfiedStageWins() {
        let node = EvoNode(speciesID: 1, children: [child(2, level: 16), child(3, level: 18)])
        XCTAssertEqual(RogueRun.levelUpEvolution(from: node, level: 20)?.speciesID, 3)
        XCTAssertEqual(RogueRun.levelUpEvolution(from: node, level: 17)?.speciesID, 2)
    }

    /// 진화는 이 판의 보상이다 — HP 를 **비율로** 옮기지 않으면 최대치가 뛴 만큼 조용히 손해가 되고,
    /// 강화가 지워지면 그때까지 고른 지속 보상이 사라진다. 레벨은 파티 값을 유지한다.
    func testEvolvingKeepsTheHPRatioLevelAndBoosts() {
        var run = RogueRun(party: [snapshot(1, level: 16, hp: 100)],
                           opponents: [snapshot(99, level: 5, hp: 1)], seed: 4)
        run.debugSetBoosts(RunBoosts(typeDamage: [.normal: 2], critStages: 1, leftovers: 0))
        for _ in 0..<10 where run.stage == .battling { run.useMove(0) }
        guard run.stage == .picking else { return XCTFail("승리하지 못했다: \(run.stage)") }
        let beforeRatio = Double(run.party[0].hp) / Double(run.party[0].stats.hp)
        let level = run.party[0].snapshot.level

        // 종족 HP 가 3배인 진화체. 레벨을 어긋나게 넣어도 코어가 파티 레벨로 덮는다.
        run.evolve(memberAt: 0, into: snapshot(2, level: 99, hp: 300))
        XCTAssertEqual(run.party[0].snapshot.speciesID, 2)
        XCTAssertEqual(run.party[0].snapshot.level, level, "진화가 레벨을 갈아버렸다")
        XCTAssertGreaterThan(run.party[0].stats.hp, 0)
        let afterRatio = Double(run.party[0].hp) / Double(run.party[0].stats.hp)
        XCTAssertEqual(afterRatio, beforeRatio, accuracy: 0.02)
        XCTAssertEqual(run.party[0].runBoosts.typeDamage[.normal], 2)
        XCTAssertEqual(run.party[0].runBoosts.critStages, 1)
        XCTAssertEqual(run.party[0].pp, run.party[0].moves.map(\.pp), "진화하면 새 무브셋의 PP 는 만피다")
    }

    /// 전투 중에는 진화하지 않는다 — 진행 중인 턴의 활성 슬롯이 다른 종으로 바뀐다.
    func testEvolvingIsIgnoredMidBattle() {
        var run = RogueRun(party: [snapshot(1)], opponents: [snapshot(99, hp: 1)], seed: 1)
        XCTAssertEqual(run.stage, .battling)
        run.evolve(memberAt: 0, into: snapshot(2, hp: 300))
        XCTAssertEqual(run.party[0].snapshot.speciesID, 1)
    }
}

/// 웨이브 사이의 갈림길(`RunRoute`). 잠그는 것은 **위험과 보상이 같은 선택에 묶여 있는가**다 —
/// 한쪽만 걸리면 험한 길이 순수한 손해(또는 공짜 보상)가 된다.
final class RunRouteTests: XCTestCase {

    private func snapshot(_ id: Int, level: Int = 5, hp: Int = 100, speed: Int = 100) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "M\(id)", trainer: "T", level: level, nature: nil,
                       isShiny: false, types: [.normal],
                       base: BattleStats(hp: hp, atk: 100, def: 50, spa: 100, spd: 50, spe: speed),
                       moves: [MoveSpec(id: 1, names: ["en": "Hit"], type: .normal, power: 200,
                                        damageClass: .physical, accuracy: nil, pp: 20)])
    }

    private func winnableRun() -> RogueRun {
        RogueRun(party: [snapshot(1, hp: 900, speed: 200)],
                 opponents: [snapshot(99, hp: 1, speed: 1)], seed: 4)
    }

    private func winWave(_ run: inout RogueRun, limit: Int = 10) {
        for _ in 0..<limit where run.stage == .battling { run.useMove(0) }
    }

    /// 첫 웨이브는 고를 기회가 없었으므로 평탄한 길이다 — 기본값이 험한 길이면 판이 시작부터
    /// 고르지 않은 난이도로 열린다.
    func testTheRunStartsOnTheSafePath() {
        XCTAssertEqual(winnableRun().route, .safe)
    }

    /// 험한 길은 상대 레벨과 종족값 상한을 함께 올린다. 한쪽만 오르면 "험하다"가 이름뿐이 된다.
    func testTheRoughPathRaisesBothLevelAndStatCap() {
        for wave in [1, 5, 9] {
            XCTAssertEqual(RogueRun.opponentLevel(wave: wave, route: .risky),
                           RogueRun.opponentLevel(wave: wave, route: .safe) + RunRoute.risky.levelBonus,
                           "wave \(wave)")
            XCTAssertEqual(RogueRun.baseStatTotalCap(wave: wave, route: .risky),
                           RogueRun.baseStatTotalCap(wave: wave, route: .safe) + RunRoute.risky.statBonus,
                           "wave \(wave)")
        }
        // 보스 보너스는 길과 별개로 남는다 — 겹쳐야 험한 길의 보스가 실제로 더 세다.
        XCTAssertGreaterThan(RogueRun.baseStatTotalCap(wave: 4, route: .risky),
                             RogueRun.baseStatTotalCap(wave: 4, route: .safe))
    }

    /// 상한이 오르면 그 상한에 맞춰 채택 범위도 넓어진다 — `isFairOpponent` 가 길을 안 보면
    /// 레벨만 오르고 종은 그대로여서 늘린 난이도가 절반만 걸린다.
    func testFairnessCheckFollowsTheRoute() {
        let cap = RogueRun.baseStatTotalCap(wave: 1, route: .safe)
        let stats = BattleStats(hp: cap / 6 + 20, atk: cap / 6, def: cap / 6,
                               spa: cap / 6, spd: cap / 6, spe: cap / 6)
        let total = RogueRun.baseStatTotal(stats)
        XCTAssertGreaterThan(total, cap, "상한을 넘는 후보로 재야 하는 테스트다")
        XCTAssertFalse(RogueRun.isFairOpponent(baseStats: stats, wave: 1, route: .safe))
        XCTAssertTrue(RogueRun.isFairOpponent(baseStats: stats, wave: 1, route: .risky))
    }

    /// 험한 길을 넘기면 보상이 두 장이다. **목록은 장마다 새로 뽑는다** — 같은 3장에서 두 장을
    /// 고르게 하면 두 번째 선택이 남은 것 중 최선 하나로 정해진다.
    func testTheRoughPathPaysTwoRewards() {
        var run = winnableRun()
        winWave(&run)
        run.pick(run.offers[0])
        run.take(.risky)
        run.beginWave(opponents: [snapshot(98, hp: 1, speed: 1)])
        winWave(&run)
        guard run.stage == .picking else { return XCTFail("승리하지 못했다: \(run.stage)") }
        XCTAssertEqual(run.remainingPicks, 2)
        let first = run.offers
        run.pick(first[0])
        XCTAssertEqual(run.stage, .picking, "두 장을 주는 웨이브인데 한 장에서 넘어갔다")
        XCTAssertEqual(run.remainingPicks, 1)
        XCTAssertEqual(run.offers.count, RogueRun.offerCount)
        run.pick(run.offers[0])
        XCTAssertEqual(run.stage, .routing)
    }

    /// 평탄한 길은 한 장이다.
    func testTheEvenPathPaysOneReward() {
        var run = winnableRun()
        winWave(&run)
        XCTAssertEqual(run.remainingPicks, 1)
        run.pick(run.offers[0])
        XCTAssertEqual(run.stage, .routing)
    }

    /// 길은 **보상을 다 고른 뒤에만** 고를 수 있고, 고른 길은 다음 웨이브에 그대로 걸린다.
    func testRouteIsChosenOnlyAfterTheRewardsAndCarriesToTheNextWave() {
        var run = winnableRun()
        winWave(&run)
        run.take(.risky)
        XCTAssertEqual(run.route, .safe, "보상을 고르기 전에 길이 바뀌었다")
        XCTAssertEqual(run.stage, .picking)
        run.pick(run.offers[0])
        run.take(.risky)
        XCTAssertEqual(run.route, .risky)
        XCTAssertEqual(run.wave, 2)
        XCTAssertEqual(run.stage, .loadingWave)
    }

    /// 최종 웨이브를 넘기면 길을 고르지 않는다 — 판이 끝났는데 다음 길을 묻는 화면이 뜬다.
    func testClearingTheFinalWaveSkipsRouting() {
        var run = winnableRun()
        run.debugJump(toWave: RogueRun.finalWave)
        winWave(&run)
        XCTAssertEqual(run.stage, .cleared)
        XCTAssertEqual(run.remainingPicks, 0)
    }
}
