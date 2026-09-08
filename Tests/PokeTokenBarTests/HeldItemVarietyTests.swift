import XCTest
@testable import PokeTokenBar

/// 지닌물건 확장 4종 — 화염구슬·독구슬(턴 끝에 **자기에게** 상태를 건다), 돌격조끼(특수를 막는
/// 대신 변화기를 못 쓴다), 구애스카프(스피드 1.5배 + 기술 고정).
///
/// 기존 5종(`HeldItemTests`·`BattleSelectionLockTests`)과 갈리는 점은 **대가의 축**이다: 앞의 셋은
/// HP 로 값을 치르고 구애 2종은 선택으로 치렀는데, 여기 넷은 상태이상·기술 분류·스피드라는 서로
/// 다른 축에 값을 매긴다. 축이 늘면 "물건 이름을 직접 보는" 구현이 조용히 빠지므로, 각 효과가
/// **자기 축의 질문**(`selfInflictedStatus`·`guardedDamageClass`·`boostsSpeed`·`locksIntoOneMove`)에
/// 답하는지를 여기서 잠근다.
@MainActor
final class HeldItemVarietyTests: XCTestCase {

    // MARK: 픽스처

    private static let four: [ItemKind] = [.flameOrb, .toxicOrb, .assaultVest, .choiceScarf]

    private func snapshot(types: [PokemonType] = [.normal], held: ItemKind? = nil,
                          moves: [MoveSpec]? = nil) -> BattleSnapshot {
        BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 100),
                       moves: moves, heldItem: held, weightHectograms: 100)
    }

    private func side(types: [PokemonType] = [.normal], held: ItemKind? = nil,
                      moves: [MoveSpec]? = nil) -> BattleSide {
        BattleSide(snapshot(types: types, held: held, moves: moves))
    }

    private func attackMove(_ id: Int = 33, power: Int = 60,
                            damageClass: MoveDamageClass = .physical) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "공격\(id)"], type: .normal, power: power,
                            damageClass: damageClass, accuracy: 100, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = false
        return move
    }

    private func statusMove(_ id: Int = 45) -> MoveSpec {
        var move = attackMove(id, power: 0, damageClass: .status)
        move.accuracy = nil
        return move
    }

    @discardableResult
    private func use(_ move: MoveSpec, by attacker: inout BattleSide,
                     on defender: inout BattleSide, seed: UInt64 = 7) -> [BattleEvent] {
        var field = BattleField()
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                        attackerActor: .a, defenderActor: .b, move: move,
                                        field: &field, rng: &rng)
    }

    /// 한 방의 데미지 — 같은 seed 로 재서 **배율만** 비교한다.
    private func damage(of move: MoveSpec, defenderHolding item: ItemKind?) -> Int {
        var attacker = side(moves: [move])
        var defender = side(held: item, moves: [move])
        return use(move, by: &attacker, on: &defender, seed: 11).reduce(0) {
            if case .damage(.b, let amount, .move) = $1 { return $0 + amount }
            return $0
        }
    }

    // MARK: - 아이템 축

    /// 넷 다 지닌물건 갈래를 그대로 탄다 — 가방·상점·와이어 검증이 이 한 축을 보므로 하나라도
    /// 빠지면 "가방에서는 지니게 되는데 배틀에서는 아무 일도 안 하는" 물건이 된다.
    func testTheFourRideTheHeldItemAxis() throws {
        for kind in Self.four {
            XCTAssertEqual(kind.bagUse, .heldItem, "\(kind.rawValue)")
            XCTAssertNotNil(kind.heldBattleEffect, "\(kind.rawValue) 가 배틀에서 하는 일이 없다")
            XCTAssertNil(kind.evolutionRule, "\(kind.rawValue)")
            XCTAssertFalse(kind.isPassive, "\(kind.rawValue)")
            XCTAssertNil(kind.roomReaction, "\(kind.rawValue)")
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "피어의 \(kind.rawValue) 가 반려된다")
            XCTAssertTrue(ItemKind.nameable.contains(kind), "\(kind.rawValue) 를 이름으로 못 부른다")
            let price = try XCTUnwrap(kind.shopPrice, "\(kind.rawValue) 를 상점에서 못 산다")
            XCTAssertGreaterThan(price, TeraShard.price, "\(kind.rawValue)")
            XCTAssertLessThanOrEqual(price, RareCandy.price, "\(kind.rawValue)")
        }
    }

    /// 이름·설명·효과 힌트가 **아이템마다 갈린다**. 한 줄로 뭉개면 무엇을 사는지 화면에서 알 수 없다.
    func testTheFourAreNamedAndDescribedApart() {
        let l = L()
        for kind in Self.four {
            XCTAssertFalse(l.itemName(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(l.itemDescription(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(l.heldItemEffectHint(kind).isEmpty, kind.rawValue)
        }
        let hints = Set(ItemKind.allCases.filter { $0.bagUse == .heldItem }
            .map { l.heldItemEffectHint($0) })
        XCTAssertEqual(hints.count, ItemKind.allCases.filter { $0.bagUse == .heldItem }.count,
                       "지닌물건 효과 힌트가 겹친다")
    }

    /// 스프라이트 이름이 있다 — 지닌물건은 진화 규칙에서 파일명을 파생할 수 없어(규칙이 nil 이다)
    /// 손으로 적어야 하고, 빠뜨리면 가방·상점에 이모지만 남는다.
    func testTheFourCarryASpriteName() {
        for kind in Self.four {
            XCTAssertNotNil(kind.spriteName, "\(kind.rawValue) 의 스프라이트 이름이 없다")
        }
    }

    /// 각 효과가 **자기 축에만** 답한다 — 축을 섞으면 돌격조끼가 데미지를 올리거나 구애스카프가
    /// 특수방어를 올리는 식으로 조용히 새어 나간다.
    func testEachEffectAnswersOnlyItsOwnAxis() {
        XCTAssertEqual(HeldItemEffect.flameOrb.selfInflictedStatus, .burn)
        XCTAssertEqual(HeldItemEffect.toxicOrb.selfInflictedStatus, .toxic)
        XCTAssertNil(HeldItemEffect.leftovers.selfInflictedStatus)

        XCTAssertEqual(HeldItemEffect.assaultVest.guardedDamageClass, .special)
        XCTAssertNil(HeldItemEffect.assaultVest.boostedDamageClass)
        XCTAssertNil(HeldItemEffect.choiceBand.guardedDamageClass)

        XCTAssertTrue(HeldItemEffect.choiceScarf.boostsSpeed)
        XCTAssertFalse(HeldItemEffect.choiceBand.boostsSpeed)
        XCTAssertNil(HeldItemEffect.choiceScarf.boostedDamageClass, "스카프는 데미지를 안 올린다")

        // 구애 셋은 다 묶고, 나머지는 안 묶는다.
        for effect in HeldItemEffect.allCases {
            let isChoice = [.choiceBand, .choiceSpecs, .choiceScarf].contains(effect)
            XCTAssertEqual(effect.locksIntoOneMove, isChoice, "\(effect)")
        }
    }

    /// **구슬이 거는 상태는 난수를 안 쓰는 것만이다.** 턴 끝 잔뎀 자리(`endOfTurnResidual`)에는
    /// rng 가 없으므로, 잠듦·혼란처럼 카운터를 뽑는 상태를 구슬에 붙이면 두 피어가 갈린다.
    func testTheOrbStatusesNeverNeedRandomness() {
        for effect in HeldItemEffect.allCases {
            guard let status = effect.selfInflictedStatus else { continue }
            XCTAssertFalse([Status.sleep, .confusion].contains(status),
                           "\(effect) 가 난수를 쓰는 상태를 건다 — 턴 끝 자리에 rng 가 없다")
        }
    }

    // MARK: - 화염구슬 · 독구슬

    func testTheFlameOrbBurnsItsHolderAtTheEndOfTheTurn() {
        var holder = side(held: .flameOrb)
        let events = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.status, .burn)
        XCTAssertTrue(events.contains(.status(.a, .burn)), "붙은 줄이 없으면 로그가 무반응으로 남는다")
    }

    /// 독구슬은 **맹독**이다(보통 독이 아니다) — 카운터가 1 에서 시작해 매턴 커진다.
    func testTheToxicOrbBadlyPoisonsItsHolder() {
        var holder = side(held: .toxicOrb)
        let events = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.status, .toxic)
        XCTAssertEqual(holder.statusCounter, 1)
        XCTAssertTrue(events.contains(.status(.a, .toxic)))
    }

    /// **붙는 턴에는 잔뎀이 없다** — 상태를 잔뎀보다 먼저 걸면 구슬을 쥔 턴부터 깎여 본가와 갈린다.
    func testTheOrbDoesNotHurtOnTheTurnItTriggers() {
        var holder = side(held: .flameOrb)
        let full = holder.stats.hp
        _ = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.hp, full)
        // 다음 턴부터 화상 잔뎀이 돈다.
        _ = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertLessThan(holder.hp, full)
    }

    /// 타입 면역을 그대로 지킨다 — 불꽃은 안 타고 독·강철은 안 중독된다.
    func testTheOrbsRespectTypeImmunity() {
        var fireType = side(types: [.fire], held: .flameOrb)
        _ = BattleEngine.endOfTurnResidual(&fireType, actor: .a)
        XCTAssertNil(fireType.status, "불꽃 타입이 화염구슬에 탔다")

        var steelType = side(types: [.steel], held: .toxicOrb)
        _ = BattleEngine.endOfTurnResidual(&steelType, actor: .a)
        XCTAssertNil(steelType.status, "강철 타입이 독구슬에 중독됐다")
    }

    /// 이미 다른 주 상태가 붙어 있으면 덮어쓰지 않는다(주 상태는 하나다).
    func testTheOrbDoesNotOverwriteAnExistingStatus() {
        var holder = side(held: .flameOrb)
        holder.status = .paralysis
        _ = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.status, .paralysis)
    }

    /// **그 턴에 쓰러진 개체에는 안 붙는다** — 기절 줄 뒤에 상태 줄이 붙으면 로그가 쓰러진 개체에게
    /// 화상을 건다.
    func testTheOrbSkipsAHolderThatFaintedThisTurn() {
        var holder = side(held: .flameOrb)
        holder.status = .poison            // 잔뎀으로 쓰러질 자리를 만든다
        holder.hp = 1
        let events = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.hp, 0)
        XCTAssertEqual(holder.status, .poison, "쓰러진 개체에 새 상태가 붙었다")
        XCTAssertFalse(events.contains(.status(.a, .burn)))
        XCTAssertEqual(events.last, .faint(.a), "기절 줄이 마지막이 아니다")
    }

    // MARK: - 돌격조끼

    /// 특수 기술을 **덜 맞는다** — 특수방어가 1.5배가 된다.
    func testTheAssaultVestSoftensSpecialHits() {
        let move = attackMove(34, damageClass: .special)
        let bare = damage(of: move, defenderHolding: nil)
        let vested = damage(of: move, defenderHolding: .assaultVest)
        XCTAssertGreaterThan(bare, 0)
        XCTAssertLessThan(vested, bare, "돌격조끼가 특수 데미지를 안 줄였다")
    }

    /// 물리는 그대로 맞는다 — 방어까지 오르면 이 물건이 다른 게임의 물건이 된다.
    func testTheAssaultVestDoesNotSoftenPhysicalHits() {
        let move = attackMove(33)
        XCTAssertEqual(damage(of: move, defenderHolding: .assaultVest),
                       damage(of: move, defenderHolding: nil))
    }

    /// 대가는 **변화기를 못 쓰는 것**이다. 잠금은 도발과 같은 자리(`selectionLock`)를 지난다 —
    /// 그 한 자리를 네 모드와 터미널이 모두 보므로 여기서 막으면 모두가 막힌다.
    func testTheAssaultVestLocksStatusMoves() {
        let mon = side(held: .assaultVest, moves: [attackMove(33), statusMove(45)])
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .assaultVest)
        XCTAssertFalse(mon.canUse(moveAt: 1))
    }

    /// 안 지녔으면 변화기가 그대로 나간다 — 잠금 조건이 뒤집혀 있으면 여기가 빨개진다.
    func testAMonWithoutTheVestKeepsItsStatusMoves() {
        let mon = side(held: .leftovers, moves: [attackMove(33), statusMove(45)])
        XCTAssertNil(mon.selectionLock(forMoveAt: 1))
    }

    /// 잠금 사유 문구가 있다 — 버튼 툴팁과 로그 줄 양쪽이다(하나로 뭉개면 왜 못 누르는지가 사라진다).
    func testTheVestLockExplainsItself() {
        let l = L()
        XCTAssertFalse(l.moveSelectionLockReason(.assaultVest).isEmpty)
        XCTAssertFalse(l.battleCantUseMove("리자몽", lock: .assaultVest).isEmpty)
        let reasons = Set(MoveSelectionLock.allCases.map { l.moveSelectionLockReason($0) })
        XCTAssertEqual(reasons.count, MoveSelectionLock.allCases.count, "잠금 사유 문구가 겹친다")
    }

    // MARK: - 구애스카프

    /// 스피드가 1.5배가 된다 — 순서를 재는 자리가 이 값을 쓴다.
    func testTheChoiceScarfRaisesSpeed() {
        let bare = side()
        let scarfed = side(held: .choiceScarf)
        XCTAssertEqual(scarfed.effectiveSpeed,
                       bare.effectiveSpeed * HeldItemBalance.choiceNumerator
                           / HeldItemBalance.choiceDenominator)
    }

    /// 마비 반감은 **스카프 뒤에** 온다(본가와 같은 순서) — 앞에 두면 정수 나눗셈이 한 점씩 갈린다.
    func testTheScarfMultipliesBeforeParalysisHalves() {
        var scarfed = side(held: .choiceScarf)
        scarfed.status = .paralysis
        let bare = side()
        let expected = max(1, bare.effectiveSpeed * HeldItemBalance.choiceNumerator
                              / HeldItemBalance.choiceDenominator / 2)
        XCTAssertEqual(scarfed.effectiveSpeed, expected)
    }

    /// 데미지는 안 올린다 — 올리면 머리띠·안경과 같은 물건이 된다.
    func testTheScarfDoesNotRaiseDamage() {
        let move = attackMove(33)
        var scarfed = side(held: .choiceScarf, moves: [move])
        var bare = side(moves: [move])
        var victimA = side(), victimB = side()
        let with = use(move, by: &scarfed, on: &victimA, seed: 11)
        let without = use(move, by: &bare, on: &victimB, seed: 11)
        func dealt(_ events: [BattleEvent]) -> Int {
            events.reduce(0) {
                if case .damage(.b, let amount, .move) = $1 { return $0 + amount }
                return $0
            }
        }
        XCTAssertGreaterThan(dealt(without), 0)
        XCTAssertEqual(dealt(with), dealt(without))
    }

    /// 대가는 구애 2종과 같다 — 처음 낸 기술 하나로 묶인다.
    func testTheScarfLocksTheFirstMoveItUsed() {
        var mon = side(held: .choiceScarf, moves: [attackMove(33), attackMove(34)])
        var target = side(moves: [attackMove(33)])
        use(attackMove(33), by: &mon, on: &target)
        XCTAssertEqual(mon.choiceLockedMoveID, 33)
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .choiceItem)
    }
}
