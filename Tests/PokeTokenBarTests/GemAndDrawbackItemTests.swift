import XCTest
@testable import PokeTokenBar

/// 주얼 18종(그 타입 기술 하나를 1.3 배로 만들고 사라진다)과 대가만 있는 물건 셋
/// (검은철구 — 스피드 절반 + 땅에 닿는다, 느림보꼬리·만복향로 — 같은 우선도에서 뒤로 밀린다).
///
/// 열매(`BerryTests`)와 갈리는 점은 **누구의 물건이 언제 답하나**다: 열매는 맞는 쪽이 맞는 순간
/// 답하고, 주얼은 때리는 쪽이 기술을 내는 순간 답한다. 대가만 있는 셋은 데미지 경로가 아니라
/// 스피드·순서·접지에 붙어서, 아이템이 데미지 밖의 축에도 붙는다는 사실을 여기서 잠근다.
@MainActor
final class GemAndDrawbackItemTests: XCTestCase {

    // MARK: 픽스처

    private static let gems: [ItemKind] = [
        .normalGem, .fireGem, .waterGem, .electricGem, .grassGem, .iceGem,
        .fightingGem, .poisonGem, .groundGem, .flyingGem, .psychicGem, .bugGem,
        .rockGem, .ghostGem, .dragonGem, .darkGem, .steelGem, .fairyGem
    ]
    private static let drawbacks: [ItemKind] = [.ironBall, .laggingTail, .fullIncense]

    private func snapshot(types: [PokemonType] = [.normal], held: ItemKind? = nil,
                          speed: Int = 100, ability: String? = nil) -> BattleSnapshot {
        BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: speed),
                       moves: nil, ability: ability, heldItem: held, weightHectograms: 100)
    }

    private func side(types: [PokemonType] = [.normal], held: ItemKind? = nil,
                      speed: Int = 100, ability: String? = nil) -> BattleSide {
        BattleSide(snapshot(types: types, held: held, speed: speed, ability: ability))
    }

    private func attackMove(_ id: Int = 33, type: PokemonType = .normal, power: Int = 60,
                            damageClass: MoveDamageClass = .physical) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "공격\(id)"], type: type, power: power,
                            damageClass: damageClass, accuracy: 100, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = false
        return move
    }

    @discardableResult
    private func hit(_ move: MoveSpec, by attacker: inout BattleSide, on defender: inout BattleSide,
                     seed: UInt64 = 7) -> [BattleEvent] {
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyHit(attacker: &attacker, defender: &defender,
                                     attackerActor: .a, defenderActor: .b,
                                     move: move, rng: &rng)
    }

    private func dealt(_ events: [BattleEvent]) -> Int {
        events.reduce(0) {
            if case .damage(.b, let amount, .move) = $1 { return $0 + amount }
            return $0
        }
    }

    // MARK: - 아이템 축

    /// 21종이 전부 지닌물건 갈래를 탄다 — 하나라도 빠지면 "가방에서는 지니게 되는데 배틀에서는
    /// 아무 일도 안 하는" 물건이 된다.
    func testTheGemsAndDrawbacksRideTheHeldItemAxis() {
        for kind in Self.gems + Self.drawbacks {
            XCTAssertEqual(kind.bagUse, .heldItem, kind.rawValue)
            XCTAssertNotNil(kind.heldBattleEffect, "\(kind.rawValue) 가 배틀에서 하는 일이 없다")
            XCTAssertNil(kind.evolutionRule, kind.rawValue)
            XCTAssertNotNil(kind.shopPrice, "\(kind.rawValue) 를 상점에서 못 산다")
            XCTAssertNotNil(kind.spriteName, kind.rawValue)
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "피어의 \(kind.rawValue) 가 반려된다")
            XCTAssertFalse(L().itemName(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().itemDescription(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().heldItemEffectHint(kind).isEmpty, kind.rawValue)
        }
        XCTAssertEqual(ItemKind.fireGem.spriteName, "fire-gem")
        XCTAssertEqual(L().itemName(.fireGem), "불꽃주얼")
        XCTAssertEqual(L().itemName(.ironBall), "검은철구")
    }

    /// 주얼 18종이 **18타입에 하나씩** 있다 — 하나가 빠지면 그 타입만 이유 없이 강화 수단이 없다.
    func testEveryTypeHasExactlyOneGem() {
        let types = Self.gems.compactMap { $0.heldBattleEffect?.oneShotBoostedMoveType }
        XCTAssertEqual(Set(types).count, PokemonType.allCases.count)
        XCTAssertEqual(types.count, Self.gems.count)
    }

    /// 대가만 있는 셋이 **자기 축에만** 답한다 — 검은철구는 스피드·접지, 나머지 둘은 순서다.
    func testTheDrawbackItemsAnswerOnlyTheirOwnAxis() {
        XCTAssertEqual(ItemKind.ironBall.heldBattleEffect, .ironBall)
        XCTAssertEqual(ItemKind.laggingTail.heldBattleEffect, .movesLast)
        XCTAssertEqual(ItemKind.fullIncense.heldBattleEffect, .movesLast)
        XCTAssertTrue(HeldItemEffect.ironBall.halvesSpeed)
        XCTAssertTrue(HeldItemEffect.ironBall.groundsHolder)
        XCTAssertFalse(HeldItemEffect.ironBall.movesLast)
        XCTAssertTrue(HeldItemEffect.movesLast.movesLast)
        XCTAssertFalse(HeldItemEffect.movesLast.halvesSpeed)
        for kind in Self.gems + Self.drawbacks {
            XCTAssertNil(kind.heldBattleEffect?.pinchAction, kind.rawValue)
            XCTAssertNil(kind.heldBattleEffect?.boostedMoveType, kind.rawValue)
        }
    }

    // MARK: - 주얼

    /// 같은 타입 기술 하나를 1.3 배로 만든다.
    func testAGemBoostsItsOwnType() {
        let fire = attackMove(type: .fire)
        var bareAttacker = side(), bareDefender = side()
        let bare = dealt(hit(fire, by: &bareAttacker, on: &bareDefender, seed: 11))
        var attacker = side(held: .fireGem), defender = side()
        let boosted = dealt(hit(fire, by: &attacker, on: &defender, seed: 11))
        XCTAssertEqual(boosted, bare * HeldItemBalance.gemNumerator / HeldItemBalance.gemDenominator)
    }

    /// 쓰면 사라진다 — 두 번째 기술은 그대로다. 로그가 무엇이 일했는지 말한다.
    func testAGemIsSpentOnTheMoveItBoosts() {
        let fire = attackMove(type: .fire)
        var attacker = side(held: .fireGem), defender = side()
        let events = hit(fire, by: &attacker, on: &defender, seed: 11)
        XCTAssertTrue(attacker.heldItemConsumed)
        XCTAssertTrue(events.contains(.heldItemTriggered(.a, .fireGem)), "\(events)")

        var bareAttacker = side(), bareDefender = side()
        let bare = dealt(hit(fire, by: &bareAttacker, on: &bareDefender, seed: 11))
        var second = side()
        XCTAssertEqual(dealt(hit(fire, by: &attacker, on: &second, seed: 11)), bare,
                       "소모된 주얼이 두 번째 기술도 올렸다")
    }

    /// 다른 타입 기술에는 아무 일도 없다 — 주얼도 남는다.
    func testAGemIgnoresOtherTypes() {
        let tackle = attackMove(type: .normal)
        var bareAttacker = side(), bareDefender = side()
        let bare = dealt(hit(tackle, by: &bareAttacker, on: &bareDefender, seed: 11))
        var attacker = side(held: .fireGem), defender = side()
        XCTAssertEqual(dealt(hit(tackle, by: &attacker, on: &defender, seed: 11)), bare)
        XCTAssertFalse(attacker.heldItemConsumed)
    }

    /// 상성표를 안 보는 기술(발버둥)은 올리지 않고 주얼도 쓰지 않는다 — 타입 강화 도구와 같은
    /// 게이트다(도구가 발버둥을 올리면 PP 가 마른 뒤가 오히려 강해진다).
    func testAGemDoesNotBoostStruggle() {
        var struggle = attackMove(MoveSpec.struggleID, type: .normal, power: 50)
        struggle.accuracy = nil
        var bareAttacker = side(), bareDefender = side()
        let bare = dealt(hit(struggle, by: &bareAttacker, on: &bareDefender, seed: 11))
        var attacker = side(held: .normalGem), defender = side()
        XCTAssertEqual(dealt(hit(struggle, by: &attacker, on: &defender, seed: 11)), bare)
        XCTAssertFalse(attacker.heldItemConsumed)
    }

    // MARK: - 검은철구

    /// 스피드가 절반이 된다 — 자이로볼처럼 느릴수록 강한 기술과 짝지어 쓰는 물건이다.
    func testTheIronBallHalvesSpeed() {
        let bare = side().effectiveSpeed
        XCTAssertEqual(side(held: .ironBall).effectiveSpeed, bare / 2)
    }

    /// 지닌 개체는 **땅에 닿는다** — 부유·비행이 땅 기술을 흘리지 못하고 필드 효과도 받는다.
    func testTheIronBallGroundsAFloatingHolder() {
        let quake = attackMove(89, type: .ground, power: 100)
        var floater = side(types: [.flying], ability: "levitate")
        XCTAssertEqual(BattleEngine.typeMultiplier(of: quake, against: floater), 0)
        XCTAssertFalse(BattleField.isGrounded(floater))

        floater = side(types: [.flying], held: .ironBall, ability: "levitate")
        XCTAssertEqual(BattleEngine.typeMultiplier(of: quake, against: floater), 1)
        XCTAssertTrue(BattleField.isGrounded(floater))
    }

    // MARK: - 후공 물건

    /// 같은 우선도라면 **스피드가 빨라도 뒤로 밀린다**.
    func testALaggingHolderMovesLastDespiteBeingFaster() {
        var fast = side(held: .laggingTail, speed: 200)
        var slow = side(speed: 50)
        var field = BattleField()
        var rng = SplitMix64(seed: 5)
        let events = BattleEngine.resolveTurn(a: &fast, b: &slow, moveA: attackMove(1),
                                              moveB: attackMove(2), turn: 1,
                                              field: &field, rng: &rng)
        let movers = events.compactMap { event -> BattleActor? in
            if case .move(let actor, _) = event { return actor }
            return nil
        }
        XCTAssertEqual(movers, [.b, .a], "느림보꼬리를 쥔 쪽이 먼저 움직였다")
    }

    /// 물건이 없으면 빠른 쪽이 먼저다 — 위 테스트가 스피드 때문에 통과한 게 아님을 잠근다.
    func testTheSameTurnWithoutTheItemKeepsSpeedOrder() {
        var fast = side(speed: 200)
        var slow = side(speed: 50)
        var field = BattleField()
        var rng = SplitMix64(seed: 5)
        let events = BattleEngine.resolveTurn(a: &fast, b: &slow, moveA: attackMove(1),
                                              moveB: attackMove(2), turn: 1,
                                              field: &field, rng: &rng)
        let movers = events.compactMap { event -> BattleActor? in
            if case .move(let actor, _) = event { return actor }
            return nil
        }
        XCTAssertEqual(movers, [.a, .b])
    }

    /// 우선도는 후공보다 세다 — 후공 물건을 쥐어도 전광석화는 먼저 나간다(본가와 같다).
    func testPriorityStillBeatsTheLaggingItem() {
        var holder = side(held: .laggingTail, speed: 50)
        var other = side(speed: 200)
        var quick = attackMove(98, power: 40)
        quick.priority = 1
        var field = BattleField()
        var rng = SplitMix64(seed: 5)
        let events = BattleEngine.resolveTurn(a: &holder, b: &other, moveA: quick,
                                              moveB: attackMove(2), turn: 1,
                                              field: &field, rng: &rng)
        let movers = events.compactMap { event -> BattleActor? in
            if case .move(let actor, _) = event { return actor }
            return nil
        }
        XCTAssertEqual(movers, [.a, .b])
    }

    /// **순서를 재는 모든 모드가 후공 물건을 봐야 한다.** 한 곳이 빠지면 그 모드에서만 물건이
    /// 아무 일도 안 하고, 화면에는 아무 오류도 안 보인다(순풍 스캔과 같은 이유).
    func testEveryTurnOrderSiteAsksAboutTheLaggingItem() throws {
        var sitesWithoutLagging: [String] = []
        for (name, code) in try SourceScan.sources() {
            guard code.contains(".turnPriority") else { continue }
            let declarations = code.components(separatedBy: "static func movesLast(").count - 1
            let mentions = code.components(separatedBy: "movesLast(").count - 1
            if mentions - declarations < 1 { sitesWithoutLagging.append(name) }
        }
        XCTAssertEqual(sitesWithoutLagging, [], "순서를 재면서 후공 물건을 안 보는 모드가 있다")
    }
}
