import XCTest
@testable import PokeTokenBar

/// 열매 29종 — 약점 반감 18(그 타입 기술의 데미지를 절반으로 깎고 사라진다)·위급 6(HP 가 최대의
/// 1/4 이하가 되면 한 번 일한다)·성격 회복 5(같은 조건에서 최대 HP 의 1/3 을 회복한다).
///
/// 앞선 지닌물건들과 갈리는 점은 **소모**다: 지금까지 소모되는 물건은 기합의띠 하나였고 그 조건도
/// 하나(만피에서 맞은 치명타)였는데, 열매는 두 갈래의 조건(맞은 타입 · 남은 HP)으로 터진다.
/// 그래서 여기서 잠그는 것은 배율 값이 아니라 **터지는 조건과 한 번만 터진다는 사실**이다.
@MainActor
final class BerryTests: XCTestCase {

    // MARK: 픽스처

    private static let resistBerries: [ItemKind] = [
        .occaBerry, .passhoBerry, .wacanBerry, .rindoBerry, .yacheBerry, .chopleBerry,
        .kebiaBerry, .shucaBerry, .cobaBerry, .payapaBerry, .tangaBerry, .chartiBerry,
        .kasibBerry, .habanBerry, .colburBerry, .babiriBerry, .chilanBerry, .roseliBerry
    ]
    private static let pinchBerries: [ItemKind] = [
        .liechiBerry, .ganlonBerry, .salacBerry, .petayaBerry, .apicotBerry, .lansatBerry
    ]
    private static let flavorBerries: [ItemKind] = [
        .figyBerry, .wikiBerry, .magoBerry, .aguavBerry, .iapapaBerry
    ]
    private static var all: [ItemKind] { resistBerries + pinchBerries + flavorBerries }

    private func snapshot(types: [PokemonType] = [.normal], held: ItemKind? = nil) -> BattleSnapshot {
        BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 100),
                       moves: nil, heldItem: held, weightHectograms: 100)
    }

    private func side(types: [PokemonType] = [.normal], held: ItemKind? = nil,
                      hp: Int? = nil) -> BattleSide {
        var out = BattleSide(snapshot(types: types, held: held))
        if let hp { out.hp = hp }
        return out
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

    /// 같은 seed 로 한 방을 재서 **배율만** 비교한다.
    private func damage(of move: MoveSpec, defenderTypes: [PokemonType],
                        holding item: ItemKind?) -> Int {
        var attacker = side()
        var defender = side(types: defenderTypes, held: item)
        return dealt(hit(move, by: &attacker, on: &defender, seed: 11))
    }

    // MARK: - 아이템 축

    /// 29종이 전부 지닌물건 갈래를 탄다 — 가방·상점·와이어 검증이 이 한 축을 보므로 하나라도
    /// 빠지면 "가방에서는 지니게 되는데 배틀에서는 아무 일도 안 하는" 물건이 된다.
    func testTheBerriesRideTheHeldItemAxis() throws {
        XCTAssertEqual(Self.all.count, 29)
        for kind in Self.all {
            XCTAssertEqual(kind.bagUse, .heldItem, kind.rawValue)
            XCTAssertNotNil(kind.heldBattleEffect, "\(kind.rawValue) 가 배틀에서 하는 일이 없다")
            XCTAssertNil(kind.evolutionRule, kind.rawValue)
            XCTAssertNil(kind.roomReaction, kind.rawValue)
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "피어의 \(kind.rawValue) 가 반려된다")
            XCTAssertTrue(ItemKind.nameable.contains(kind), "\(kind.rawValue) 를 이름으로 못 부른다")
            XCTAssertNotNil(kind.shopPrice, "\(kind.rawValue) 를 상점에서 못 산다")
        }
    }

    /// 스프라이트 이름은 **케이스명에서 파생한다**(`occaBerry` → `occa-berry`) — 29줄을 손으로
    /// 적으면 하나가 어긋나도 화면에는 이모지만 남고 오류가 나지 않는다.
    func testTheBerrySpriteNamesComeFromTheCaseNames() {
        XCTAssertEqual(ItemKind.occaBerry.spriteName, "occa-berry")
        XCTAssertEqual(ItemKind.iapapaBerry.spriteName, "iapapa-berry")
        for kind in Self.all {
            XCTAssertEqual(kind.spriteName?.hasSuffix("-berry"), true, kind.rawValue)
        }
    }

    /// 이름·설명·효과 힌트가 다 채워져 있다 — 하나라도 비면 가방·상점에 빈 줄이 뜬다.
    func testTheBerriesAreNamedAndDescribed() {
        let l = L()
        for kind in Self.all {
            XCTAssertFalse(l.itemName(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(l.itemDescription(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(l.heldItemEffectHint(kind).isEmpty, kind.rawValue)
        }
        XCTAssertEqual(l.itemName(.occaBerry), "오카열매")
    }

    /// 각 열매가 **자기 축에만** 답한다 — 축을 섞으면 위급 열매가 데미지를 반감하거나 약점 반감
    /// 열매가 랭크를 올리는 식으로 조용히 새어 나간다.
    func testEachBerryAnswersOnlyItsOwnAxis() {
        XCTAssertEqual(ItemKind.occaBerry.heldBattleEffect, .resistBerry(.fire))
        XCTAssertEqual(ItemKind.liechiBerry.heldBattleEffect, .pinchStatBoost(.atk))
        XCTAssertEqual(ItemKind.lansatBerry.heldBattleEffect, .pinchCrit)
        XCTAssertEqual(ItemKind.figyBerry.heldBattleEffect, .pinchHeal)
        // 열매는 데미지를 올리지도, 상태를 걸지도, 기술을 묶지도 않는다.
        for kind in Self.all {
            let effect = kind.heldBattleEffect
            XCTAssertNil(effect?.boostedDamageClass, kind.rawValue)
            XCTAssertNil(effect?.guardedDamageClass, kind.rawValue)
            XCTAssertNil(effect?.selfInflictedStatus, kind.rawValue)
            XCTAssertEqual(effect?.boostedMoveTypes, [], kind.rawValue)
            XCTAssertEqual(effect?.boostsSpeed, false, kind.rawValue)
            XCTAssertEqual(effect?.blocksStatusMoves, false, kind.rawValue)
            XCTAssertEqual(effect?.locksIntoOneMove, false, kind.rawValue)
        }
        // 위급 열매만 위급 행동에 답한다.
        for kind in Self.resistBerries {
            XCTAssertNil(kind.heldBattleEffect?.pinchAction, kind.rawValue)
        }
        for kind in Self.pinchBerries + Self.flavorBerries {
            XCTAssertNotNil(kind.heldBattleEffect?.pinchAction, kind.rawValue)
        }
    }

    // MARK: - 약점 반감 열매

    /// 효과가 굉장한 히트를 절반으로 깎는다.
    func testAWeaknessBerryHalvesASuperEffectiveHit() {
        let fire = attackMove(type: .fire)
        let bare = damage(of: fire, defenderTypes: [.grass], holding: nil)
        let berried = damage(of: fire, defenderTypes: [.grass], holding: .occaBerry)
        XCTAssertGreaterThan(bare, 1, "약점 히트가 0 이면 이 테스트는 아무것도 안 잠근다")
        XCTAssertEqual(berried, bare * HeldItemBalance.resistBerryNumerator
                       / HeldItemBalance.resistBerryDenominator)
    }

    /// 효과가 굉장하지 않으면 터지지 않는다 — 열매가 그대로 남아 다음 약점 히트를 막는다.
    func testAWeaknessBerryIgnoresANeutralHit() {
        let fire = attackMove(type: .fire)
        let bare = damage(of: fire, defenderTypes: [.normal], holding: nil)
        XCTAssertEqual(damage(of: fire, defenderTypes: [.normal], holding: .occaBerry), bare)

        var attacker = side()
        var defender = side(types: [.normal], held: .occaBerry)
        hit(fire, by: &attacker, on: &defender)
        XCTAssertFalse(defender.heldItemConsumed, "안 터진 열매가 사라졌다")
    }

    /// 카리열매(노말)만 배율과 무관하게 반감한다 — 노말은 어느 타입에게도 효과가 굉장하지
    /// 않아서, 다른 열매와 같은 규칙을 주면 아무 일도 못 하는 죽은 물건이 된다.
    func testTheChilanBerryHalvesEvenANeutralHit() {
        let tackle = attackMove(type: .normal)
        let bare = damage(of: tackle, defenderTypes: [.water], holding: nil)
        XCTAssertEqual(damage(of: tackle, defenderTypes: [.water], holding: .chilanBerry),
                       bare * HeldItemBalance.resistBerryNumerator
                       / HeldItemBalance.resistBerryDenominator)
    }

    /// 한 번 막으면 사라지고 그 사실이 로그에 남는다 — 두 번째 약점 히트는 온전히 들어간다.
    func testAWeaknessBerryIsSpentAfterItWorks() {
        let fire = attackMove(type: .fire)
        var attacker = side()
        var defender = side(types: [.grass], held: .occaBerry)
        let first = hit(fire, by: &attacker, on: &defender, seed: 11)
        XCTAssertTrue(defender.heldItemConsumed, "막은 열매가 남아 있다")
        XCTAssertTrue(first.contains(.heldItemTriggered(.b, .occaBerry)),
                      "무엇이 데미지를 깎았는지가 로그에 없다")

        var freshAttacker = side()
        var bareDefender = side(types: [.grass])
        let bare = dealt(hit(fire, by: &freshAttacker, on: &bareDefender, seed: 11))
        var secondAttacker = side()
        let second = dealt(hit(fire, by: &secondAttacker, on: &defender, seed: 11))
        XCTAssertEqual(second, bare, "소모된 열매가 두 번째 히트도 깎았다")
    }

    /// 공식을 안 타는 데미지(나이트헤드 부류)는 깎지 않고 열매도 쓰지 않는다 — 상성이 곱해지지
    /// 않은 값이라 "약점을 막았다" 가 성립하지 않는다(생명의구슬과 같은 게이트다).
    func testAWeaknessBerryDoesNotHalveFixedDamage() {
        var nightShade = attackMove(101, type: .ghost, power: 0, damageClass: .special)
        nightShade.accuracy = 100
        var attacker = side()
        var defender = side(types: [.psychic], held: .kasibBerry)
        var bareAttacker = side()
        var bareDefender = side(types: [.psychic])
        let bare = dealt(hit(nightShade, by: &bareAttacker, on: &bareDefender, seed: 11))
        XCTAssertGreaterThan(bare, 0, "고정 데미지가 0 이면 이 테스트는 아무것도 안 잠근다")
        XCTAssertEqual(dealt(hit(nightShade, by: &attacker, on: &defender, seed: 11)), bare)
        XCTAssertFalse(defender.heldItemConsumed)
    }

    // MARK: - 위급 열매

    /// HP 가 최대의 1/4 이하면 턴 끝에 랭크가 오르고 열매가 사라진다.
    func testAPinchBerryRaisesItsStatAtQuarterHP() {
        var holder = side(held: .liechiBerry)
        holder.hp = holder.stats.hp / HeldItemBalance.pinchThresholdDivisor
        let events = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.stage(.atk), 1)
        XCTAssertTrue(holder.heldItemConsumed)
        XCTAssertTrue(events.contains(.heldItemTriggered(.a, .liechiBerry)), "\(events)")
        XCTAssertTrue(events.contains(.boost(.a, .atk, 1)), "\(events)")
    }

    /// 1/4 위에서는 아무 일도 없다 — 열매도 그대로다.
    func testAPinchBerryStaysQuietAboveQuarterHP() {
        var holder = side(held: .liechiBerry)
        holder.hp = holder.stats.hp / HeldItemBalance.pinchThresholdDivisor + 1
        XCTAssertEqual(BattleEngine.endOfTurnResidual(&holder, actor: .a), [])
        XCTAssertEqual(holder.stage(.atk), 0)
        XCTAssertFalse(holder.heldItemConsumed)
    }

    /// 다섯 위급 열매가 **서로 다른 스탯**을 올린다 — 하나로 접히면 다섯 물건이 같은 물건이 된다.
    func testTheFivePinchBerriesRaiseFiveDifferentStats() {
        let raised: [ItemKind: BattleStat] = [
            .liechiBerry: .atk, .ganlonBerry: .def, .salacBerry: .spe,
            .petayaBerry: .spa, .apicotBerry: .spd
        ]
        for (kind, stat) in raised {
            var holder = side(held: kind)
            holder.hp = 1
            _ = BattleEngine.endOfTurnResidual(&holder, actor: .a)
            XCTAssertEqual(holder.stage(stat), 1, kind.rawValue)
        }
    }

    /// 랑사열매는 랭크가 아니라 **급소 단계**를 올린다 — 기합충전과 같은 자리에 붙는다.
    func testTheLansatBerryStartsFocusEnergy() {
        var holder = side(held: .lansatBerry)
        holder.hp = 1
        let events = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertTrue(holder.has(.focusEnergy))
        XCTAssertTrue(events.contains(.volatileStarted(.a, .focusEnergy)), "\(events)")
    }

    /// 성격 회복 열매는 최대 HP 의 1/3 을 회복한다.
    func testAFlavorBerryHealsAThirdAtQuarterHP() {
        var holder = side(held: .figyBerry)
        let full = holder.stats.hp
        holder.hp = full / HeldItemBalance.pinchThresholdDivisor
        let before = holder.hp
        _ = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.hp, before + full / HeldItemBalance.pinchHealDivisor)
        XCTAssertTrue(holder.heldItemConsumed)
    }

    /// 열매를 1/4 아래로 **떨어뜨린 그 히트**에서 터진다 — 턴 끝까지 기다리면 그 사이의 한 방에
    /// 쓰러진다(위급 열매가 존재하는 이유가 그 한 방이다).
    func testAPinchBerryTriggersOnTheHitThatCrossesTheThreshold() {
        var attacker = side()
        var defender = side(held: .salacBerry)
        defender.hp = defender.stats.hp / HeldItemBalance.pinchThresholdDivisor + 5
        let events = hit(attackMove(), by: &attacker, on: &defender)
        XCTAssertLessThanOrEqual(defender.hp * HeldItemBalance.pinchThresholdDivisor,
                                 defender.stats.hp, "이 히트가 임계를 안 넘겼다")
        XCTAssertEqual(defender.stage(.spe), 1, "\(events)")
        XCTAssertTrue(defender.heldItemConsumed)
    }

    /// **쓰러뜨린 히트에서는 터지지 않는다.** 히트 자리의 열매는 기절 판정 앞에서 도는데,
    /// 거기서 살아 있는지 안 물으면 쓰러진 개체가 기절 줄 앞에 랭크를 올린다(로그가 죽은 개체를
    /// 강화한다). 턴 끝 자리는 `endOfTurnResidual` 이 이미 `isAlive` 로 막으므로 이 경로가
    /// 함수 자신의 가드를 검증하는 유일한 자리다.
    func testAPinchBerryDoesNotTriggerOnTheHitThatFaintsTheHolder() {
        var attacker = side()
        var defender = side(held: .liechiBerry)
        defender.hp = 1
        let events = hit(attackMove(), by: &attacker, on: &defender)
        XCTAssertEqual(defender.hp, 0, "이 히트가 안 쓰러뜨렸다 — 테스트가 아무것도 안 잠근다")
        XCTAssertFalse(defender.heldItemConsumed)
        XCTAssertEqual(defender.stage(.atk), 0)
        XCTAssertFalse(events.contains(.heldItemTriggered(.b, .liechiBerry)), "\(events)")
    }

    /// 한 번 터진 열매는 다시 터지지 않는다 — 매 턴 터지면 랭크가 무한히 오른다.
    func testASpentPinchBerryDoesNotTriggerAgain() {
        var holder = side(held: .liechiBerry)
        holder.hp = 1
        _ = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        let second = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.stage(.atk), 1)
        XCTAssertEqual(second, [])
    }
}
