import XCTest
@testable import PokeTokenBar

/// 운에 걸린 물건 5종 — 선제공격손톱·기합의머리띠, 그리고 위급 열매 셋(스타열매·미클열매·애슈열매).
///
/// 다섯이 갈리는 것은 **묻는 자리**다: 손톱·애슈·미클은 턴이 시작될 때(순서를 재기 전),
/// 머리띠는 치명적인 히트에서, 스타는 턴 끝 위급 판정에서 답한다.
final class LuckItemTests: XCTestCase {

    private static let items: [ItemKind] = [
        .quickClaw, .focusBand, .starfBerry, .micleBerry, .custapBerry
    ]

    private func side(held: ItemKind? = nil, hp: Int? = nil,
                      base: BattleStats = BattleStats(hp: 200, atk: 100, def: 100,
                                                      spa: 100, spd: 100, spe: 100)) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: [.normal],
                                            base: base, heldItem: held, weightHectograms: 100))
        if let hp { out.hp = hp }
        return out
    }

    private func attackMove(_ id: Int = 33, power: Int = 60, accuracy: Int? = 100) -> MoveSpec {
        var out = MoveSpec(id: id, names: ["ko": "기술\(id)"], type: .normal, power: power,
                           damageClass: .physical, accuracy: accuracy, pp: 10)
        out.ailment = "none"; out.ailmentChance = 0
        out.statChanges = []; out.statChance = 0; out.targetsUser = false
        return out
    }

    /// 위급(최대 HP 의 1/4 이하)으로 만든다 — 세 열매가 답하는 조건이다.
    private func pinched(held: ItemKind) -> BattleSide {
        var out = side(held: held)
        out.hp = out.stats.hp / 4
        return out
    }

    // MARK: - 아이템 축

    func testTheLuckItemsRideTheHeldItemAxis() {
        for kind in Self.items {
            XCTAssertEqual(kind.bagUse, .heldItem, kind.rawValue)
            XCTAssertNotNil(kind.heldBattleEffect, kind.rawValue)
            XCTAssertNil(kind.evolutionRule, kind.rawValue)
            XCTAssertNotNil(kind.shopPrice, kind.rawValue)
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "피어의 \(kind.rawValue) 가 반려된다")
            XCTAssertFalse(L().itemName(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().itemDescription(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().heldItemEffectHint(kind).isEmpty, kind.rawValue)
            XCTAssertNotNil(kind.spriteName, kind.rawValue)
        }
        XCTAssertEqual(L().itemName(.quickClaw), "선제공격손톱")
        XCTAssertEqual(L().itemName(.custapBerry), "애슈열매")
    }

    // MARK: - 선제공격손톱

    /// 확률로 선공을 가져간다 — 200턴을 굴려 **터진 턴과 안 터진 턴이 모두** 나오는지 본다.
    /// 확률을 재는 대신 두 갈래가 다 밟히는지를 보는 이유는 seed 하나로는 아무것도 못 말해서다.
    func testTheQuickClawSometimesTakesTheTurn() {
        var rng = SplitMix64(seed: 9)
        var firsts = 0
        for _ in 0..<200 {
            var holder = side(held: .quickClaw)
            _ = BattleEngine.rollTurnStartItems(&holder, actor: .a, rng: &rng)
            if BattleEngine.movesFirst(holder) { firsts += 1 }
            XCTAssertFalse(holder.heldItemConsumed, "손톱은 소모품이 아니다")
        }
        XCTAssertGreaterThan(firsts, 0, "200턴 동안 한 번도 안 터졌다")
        XCTAssertLessThan(firsts, 200, "200턴 내내 터졌다 — 확률이 아니다")

        // 물건이 없으면 굴리지도 않는다.
        var bare = side()
        var idle = SplitMix64(seed: 9)
        _ = BattleEngine.rollTurnStartItems(&bare, actor: .a, rng: &idle)
        XCTAssertFalse(BattleEngine.movesFirst(bare))
        XCTAssertEqual(idle.state, SplitMix64(seed: 9).state, "빈손인데 난수를 소비했다")
    }

    /// 선공은 **스피드를 이기고 우선도에는 진다** — 후공 물건과 같은 자리의 규칙이다.
    func testTakingTheTurnBeatsSpeedButNotPriority() {
        var rng = SplitMix64(seed: 1)
        XCTAssertTrue(BattleEngine.firstMoverIsA(priorityA: 0, priorityB: 0, speedA: 1, speedB: 999,
                                                 movesFirstA: true, rng: &rng))
        XCTAssertFalse(BattleEngine.firstMoverIsA(priorityA: 0, priorityB: 1, speedA: 999, speedB: 1,
                                                  movesFirstA: true, rng: &rng))
        // 둘 다 가져가면 서로 지워지고 스피드로 돌아간다.
        XCTAssertTrue(BattleEngine.firstMoverIsA(priorityA: 0, priorityB: 0, speedA: 999, speedB: 1,
                                                 movesFirstA: true, movesFirstB: true, rng: &rng))
    }

    /// **순서를 재는 모든 모드가 선공 물건을 봐야 한다.** 한 곳이 빠지면 그 모드에서만 손톱·애슈가
    /// 아무 일도 하지 않고 화면에는 아무 오류도 안 보인다(후공 물건 스캔과 같은 이유).
    func testEveryTurnOrderSiteAsksAboutTheHurryingItem() throws {
        var sitesWithoutHurry: [String] = []
        for (name, code) in try SourceScan.sources() {
            guard code.contains(".turnPriority") else { continue }
            let declarations = code.components(separatedBy: "static func movesFirst(").count - 1
            let mentions = code.components(separatedBy: "movesFirst(").count - 1
            if mentions - declarations < 1 { sitesWithoutHurry.append(name) }
        }
        XCTAssertEqual(sitesWithoutHurry, [], "순서를 재면서 선공 물건을 안 보는 모드가 있다")
    }

    // MARK: - 애슈열매·미클열매

    /// 애슈열매는 위급일 때 그 턴의 선공을 가져가고 사라진다 — 위급이 아니면 아무 일도 없다.
    func testTheCustapBerryHurriesOnceWhenPinched() {
        var rng = SplitMix64(seed: 4)
        var holder = pinched(held: .custapBerry)
        let events = BattleEngine.rollTurnStartItems(&holder, actor: .a, rng: &rng)
        XCTAssertTrue(BattleEngine.movesFirst(holder))
        XCTAssertTrue(holder.heldItemConsumed)
        XCTAssertTrue(events.contains(.heldItemTriggered(.a, .custapBerry)))

        var healthy = side(held: .custapBerry)
        _ = BattleEngine.rollTurnStartItems(&healthy, actor: .a, rng: &rng)
        XCTAssertFalse(BattleEngine.movesFirst(healthy), "만피인데 애슈열매가 터졌다")
        XCTAssertFalse(healthy.heldItemConsumed)
    }

    /// 미클열매는 위급일 때 **다음 기술 하나**를 반드시 맞히고 사라진다.
    func testTheMicleBerryMakesTheNextMoveHit() {
        var rng = SplitMix64(seed: 4)
        var holder = pinched(held: .micleBerry)
        _ = BattleEngine.rollTurnStartItems(&holder, actor: .a, rng: &rng)
        XCTAssertTrue(holder.nextMoveNeverMisses)
        XCTAssertTrue(holder.heldItemConsumed)

        // 명중 1% 기술도 빗나가지 않고, 그 한 번으로 효과가 끝난다.
        var target = side()
        let shaky = attackMove(87, accuracy: 1)
        var hitRNG = SplitMix64(seed: 2)
        let events = BattleEngine.applyHit(attacker: &holder, defender: &target, attackerActor: .a,
                                           defenderActor: .b, move: shaky, rng: &hitRNG)
        XCTAssertFalse(events.contains(.miss(.a)), "미클열매를 쓴 기술이 빗나갔다")
        XCTAssertFalse(holder.nextMoveNeverMisses, "한 번 쓰고도 효과가 남았다")
    }

    // MARK: - 기합의머리띠

    /// 치명적인 히트를 확률로 HP 1 에서 버틴다 — 200회를 때려 두 갈래가 다 나오는지 본다.
    func testTheFocusBandSometimesLeavesTheHolderAtOne() {
        var survived = 0
        for seed in UInt64(0)..<200 {
            var attacker = side()
            var holder = side(held: .focusBand, hp: 1)
            var rng = SplitMix64(seed: seed)
            _ = BattleEngine.applyHit(attacker: &attacker, defender: &holder, attackerActor: .a,
                                      defenderActor: .b, move: attackMove(), rng: &rng)
            if holder.hp == 1 { survived += 1 }
            XCTAssertFalse(holder.heldItemConsumed, "머리띠는 소모품이 아니다")
        }
        XCTAssertGreaterThan(survived, 0, "200회 동안 한 번도 안 버텼다")
        XCTAssertLessThan(survived, 200, "200회 내내 버텼다 — 확률이 아니다")
    }

    // MARK: - 스타열매

    /// 위급일 때 능력 하나가 두 단계 오른다. **오르는 자리는 종족값이 가장 높은 능력**이다 —
    /// 본가는 무작위지만 턴 끝 자리에는 두 피어가 공유하는 난수원이 없다.
    func testTheStarfBerryRaisesTheHoldersBestStat() {
        var holder = side(held: .starfBerry,
                          base: BattleStats(hp: 200, atk: 60, def: 60, spa: 150, spd: 60, spe: 60))
        holder.hp = holder.stats.hp / 4
        let events = BattleEngine.triggerPinchBerry(&holder, actor: .a)
        XCTAssertEqual(holder.stage(.spa), HeldItemBalance.pinchStatStages)
        XCTAssertEqual(holder.stage(.atk), 0)
        XCTAssertTrue(holder.heldItemConsumed)
        XCTAssertTrue(events.contains(.heldItemTriggered(.a, .starfBerry)))

        // 위급이 아니면 터지지 않는다.
        var healthy = side(held: .starfBerry)
        _ = BattleEngine.triggerPinchBerry(&healthy, actor: .a)
        XCTAssertFalse(healthy.heldItemConsumed)
    }
}
