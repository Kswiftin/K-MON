import XCTest
@testable import PokeTokenBar

/// 기술 **선택**을 막는 부류 — 도발·앙코르·씨앙코르·트집·봉인·비밀의힘, 그리고 구애 아이템.
///
/// 다른 volatile 과 갈리는 점은 **막는 자리가 데미지 경로가 아니라 선택 경로**라는 것이다.
/// 선택은 네 모드(1대1·모의전·웨이브·방)와 터미널이 각자 하므로, 규칙을 한 자리
/// (`BattleSide.selectionLock(forMoveAt:)`)에 두고 그 한 자리를 모두가 지나게 잠근다.
/// 모드마다 갈래를 두면 방에서만 도발이 통하지 않는 식으로 조용히 어긋난다.
final class BattleSelectionLockTests: XCTestCase {

    // MARK: 픽스처

    private func attackMove(_ id: Int, damageClass: MoveDamageClass = .physical) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "공격\(id)"], type: .normal, power: 60,
                            damageClass: damageClass, accuracy: 100, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = false
        return move
    }

    private func statusMove(_ id: Int) -> MoveSpec {
        var move = attackMove(id, damageClass: .status)
        move.power = 0
        move.accuracy = nil
        return move
    }

    /// 선택을 막는 기술 — id 가 규칙이다(엔진이 데이터에 물어 무엇을 거는지 알아본다).
    private func lockMove(_ id: Int) -> MoveSpec {
        var move = statusMove(id)
        move.pp = 20
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

    private func side(moves: [MoveSpec], holding item: ItemKind? = nil) -> BattleSide {
        var snapshot = BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                      nature: nil, isShiny: false, types: [.normal],
                                      base: BattleStats(hp: 100, atk: 100, def: 100,
                                                        spa: 100, spd: 100, spe: 100),
                                      weightHectograms: 100)
        snapshot.moves = moves
        snapshot.heldItem = item
        return BattleSide(snapshot)
    }

    /// 한 방의 데미지 — 같은 seed 로 두 번 재서 **배율만** 비교한다(난수가 끼면 비교가 흐려진다).
    private func damage(of move: MoveSpec, holding item: ItemKind?) -> Int {
        var attacker = side(moves: [move], holding: item)
        var defender = side(moves: [move])
        let events = use(move, by: &attacker, on: &defender, seed: 11)
        return events.compactMap { event -> Int? in
            guard case .damage(_, let amount, let cause) = event, cause == .move else { return nil }
            return amount
        }.reduce(0, +)
    }

    // MARK: 데이터가 답한다

    /// 비밀의힘이 막는 것은 **회복기**고, 어느 기술이 회복기인지는 쇼다운의 `heal` 플래그가 답한다.
    /// 손 목록이면 회복기 하나가 조용히 빠지고, 화면에는 "그 기술만 비밀의힘을 무시한다" 로 나온다.
    func testTheHealingMoveTableComesFromTheData() {
        XCTAssertTrue(ShowdownMoveData.healing.contains(105), "자기회복(105)이 회복기 표에 없다")
        XCTAssertTrue(ShowdownMoveData.healing.contains(156), "잠자기(156)가 회복기 표에 없다")
        XCTAssertTrue(ShowdownMoveData.healing.contains(273), "희망사탕(273)이 회복기 표에 없다")
        // 흡수기도 표에 있다 — 쇼다운의 `healblock` 이 플래그가 붙은 기술을 전부 막는다.
        XCTAssertTrue(ShowdownMoveData.healing.contains(202), "기가드레인(202)도 회복 플래그를 든다")
        XCTAssertFalse(ShowdownMoveData.healing.contains(33), "몸통박치기(33)는 회복기가 아니다")
    }

    // MARK: 여섯 가지 잠금

    /// 도발은 **변화기만** 막는다. 공격기는 그대로 나간다.
    func testTauntLocksOnlyTheStatusMoves() {
        var mon = side(moves: [attackMove(33), statusMove(45)])
        XCTAssertTrue(mon.start(.taunt, turns: 3))
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .taunt)
        XCTAssertTrue(mon.canUse(moveAt: 0))
        XCTAssertFalse(mon.canUse(moveAt: 1))
    }

    /// 변화기만 든 개체가 도발당하면 **낼 기술이 하나도 없다** — 그때는 발버둥이다.
    /// PP 만 보는 옛 `mustStruggle` 은 이 개체를 "낼 기술이 있다" 로 읽어 아무 기술도 못 내는
    /// 턴을 만들었다(선택은 막히는데 발버둥도 안 나오는 자리).
    func testAMonWithNothingLeftToPickMustStruggle() {
        var mon = side(moves: [statusMove(45), statusMove(47)])
        XCTAssertFalse(mon.mustStruggle)
        XCTAssertTrue(mon.start(.taunt, turns: 3))
        XCTAssertTrue(mon.mustStruggle)
    }

    /// 씨앙코르는 **직전에 낸 그 기술 하나**를 막는다.
    func testDisableLocksTheOneMoveItNamed() {
        var mon = side(moves: [attackMove(33), attackMove(34)])
        XCTAssertTrue(mon.start(.disable, turns: 4))
        mon.disabledMoveID = 34
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .disable)
    }

    /// 앙코르는 반대다 — **한 기술만 남기고** 나머지를 막는다.
    func testEncoreLeavesOnlyTheMoveItRepeats() {
        var mon = side(moves: [attackMove(33), attackMove(34), statusMove(45)])
        XCTAssertTrue(mon.start(.encore, turns: 3))
        mon.encoredMoveID = 34
        XCTAssertEqual(mon.selectionLock(forMoveAt: 0), .encore)
        XCTAssertNil(mon.selectionLock(forMoveAt: 1))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 2), .encore)
    }

    /// 트집은 **같은 기술을 연달아** 내지 못하게 한다 — 직전에 낸 것만 막힌다.
    func testTormentLocksOnlyTheMoveJustUsed() {
        var mon = side(moves: [attackMove(33), attackMove(34)])
        XCTAssertTrue(mon.start(.torment))
        mon.lastMoveID = 33
        XCTAssertEqual(mon.selectionLock(forMoveAt: 0), .torment)
        XCTAssertNil(mon.selectionLock(forMoveAt: 1))
        // 다른 기술을 내면 막히는 자리가 옮겨 간다(고정된 목록이 아니다).
        mon.lastMoveID = 34
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .torment)
    }

    /// 봉인은 **상대와 겹치는 기술**을 막는다 — 겹치지 않는 기술은 그대로 낸다.
    func testImprisonLocksTheMovesTheCasterAlsoKnows() {
        var mon = side(moves: [attackMove(33), attackMove(34)])
        XCTAssertTrue(mon.start(.imprison))
        mon.imprisonedMoveIDs = [34]
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .imprison)
    }

    /// 비밀의힘은 회복기만 막는다 — 어느 기술이 회복기인지는 데이터가 답한다(위 표).
    func testHealBlockLocksTheHealingMoves() {
        var mon = side(moves: [attackMove(33), statusMove(105)])
        XCTAssertTrue(mon.start(.healBlock, turns: 5))
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .healBlock)
    }

    /// 잠금이 하나도 없으면 네 칸 모두 열려 있다 — 잠금 판정 자체가 기본값을 막지 않는지 본다
    /// (막는 조건이 뒤집혀 있어도 위 테스트들은 전부 초록이다).
    func testAnUntouchedMonHasEveryMoveOpen() {
        let mon = side(moves: [attackMove(33), statusMove(45), attackMove(34), statusMove(105)])
        for index in 0..<4 {
            XCTAssertNil(mon.selectionLock(forMoveAt: index), "칸 \(index) 가 이유 없이 막혔다")
            XCTAssertTrue(mon.canUse(moveAt: index))
        }
        XCTAssertFalse(mon.mustStruggle)
    }

    /// 교체하면 잠금도 함께 사라진다 — volatile 만 지우고 곁의 값(막힌 기술 id)을 남기면
    /// 다시 나온 개체가 이유 없이 한 기술을 못 낸다(층 HP 와 같은 부류의 결함이다).
    func testSwitchingOutClearsEveryLock() {
        var mon = side(moves: [attackMove(33), attackMove(34)])
        _ = mon.start(.disable, turns: 4)
        mon.disabledMoveID = 34
        _ = mon.start(.encore, turns: 3)
        mon.encoredMoveID = 33
        _ = mon.start(.imprison)
        mon.imprisonedMoveIDs = [33, 34]
        mon.choiceLockedMoveID = 33

        BattleEngine.prepareForSwitch(&mon)

        XCTAssertNil(mon.disabledMoveID)
        XCTAssertNil(mon.encoredMoveID)
        XCTAssertTrue(mon.imprisonedMoveIDs.isEmpty)
        XCTAssertNil(mon.choiceLockedMoveID)
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertNil(mon.selectionLock(forMoveAt: 1))
    }

    // MARK: 엔진이 거는 자리

    /// 여섯 기술의 id 는 손 목록이 아니라 데이터가 답한다 — 새 기술이 같은 키를 부르면
    /// (사이코노이즈처럼 비밀의힘을 부르는 공격기) 저절로 따라온다.
    func testTheDataNamesTheMovesThatLockASelection() {
        XCTAssertEqual(BattleVolatile.called(byMoveID: 50), .disable)
        XCTAssertEqual(BattleVolatile.called(byMoveID: 227), .encore)
        XCTAssertEqual(BattleVolatile.called(byMoveID: 269), .taunt)
        XCTAssertEqual(BattleVolatile.called(byMoveID: 259), .torment)
        XCTAssertEqual(BattleVolatile.called(byMoveID: 286), .imprison)
        XCTAssertEqual(BattleVolatile.called(byMoveID: 377), .healBlock)
        XCTAssertEqual(BattleVolatile.called(byMoveID: 917), .healBlock, "사이코노이즈도 같은 키를 부른다")
    }

    /// 도발을 실제로 걸면 상대의 변화기 칸이 막히고, **걸린 쪽에서** 턴을 센다.
    func testTauntLandsWithItsOwnClock() {
        var caster = side(moves: [lockMove(269)])
        var target = side(moves: [attackMove(33), statusMove(45)])
        let events = use(lockMove(269), by: &caster, on: &target)

        XCTAssertTrue(events.contains(.volatileStarted(.b, .taunt)), "도발이 붙은 줄이 없다")
        XCTAssertEqual(target.volatiles[.taunt], BattleVolatile.taunt.foeDuration)
        XCTAssertEqual(target.selectionLock(forMoveAt: 1), .taunt)
    }

    /// 씨앙코르는 **상대가 직전에 낸 기술**을 막는다 — 아직 아무것도 내지 않았으면 실패다
    /// (막을 대상이 없는데 붙이면 아무 칸도 막지 않는 4턴이 로그에만 남는다).
    func testDisableTakesTheMoveTheTargetJustUsed() {
        var caster = side(moves: [lockMove(50)])
        var target = side(moves: [attackMove(33), attackMove(34)])
        target.lastMoveID = 34

        use(lockMove(50), by: &caster, on: &target)

        XCTAssertEqual(target.disabledMoveID, 34)
        XCTAssertEqual(target.selectionLock(forMoveAt: 1), .disable)
        XCTAssertNil(target.selectionLock(forMoveAt: 0))
    }

    func testDisableFailsAgainstAMonThatHasNotMoved() {
        var caster = side(moves: [lockMove(50)])
        var target = side(moves: [attackMove(33)])
        let events = use(lockMove(50), by: &caster, on: &target)

        XCTAssertFalse(target.has(.disable), "낸 기술이 없는데 씨앙코르가 붙었다")
        XCTAssertNil(target.disabledMoveID)
        XCTAssertTrue(caster.lastMoveFailed)
        XCTAssertTrue(events.contains(.immune(.b)), "실패한 줄이 없으면 무반응 턴으로 읽힌다")
    }

    /// 앙코르도 직전 기술을 본다 — 다만 **그 하나만 남긴다**.
    func testEncoreRepeatsTheMoveTheTargetJustUsed() {
        var caster = side(moves: [lockMove(227)])
        var target = side(moves: [attackMove(33), attackMove(34)])
        target.lastMoveID = 33

        use(lockMove(227), by: &caster, on: &target)

        XCTAssertEqual(target.encoredMoveID, 33)
        XCTAssertNil(target.selectionLock(forMoveAt: 0))
        XCTAssertEqual(target.selectionLock(forMoveAt: 1), .encore)
    }

    func testEncoreFailsAgainstAMonThatHasNotMoved() {
        var caster = side(moves: [lockMove(227)])
        var target = side(moves: [attackMove(33)])
        use(lockMove(227), by: &caster, on: &target)

        XCTAssertFalse(target.has(.encore))
        XCTAssertNil(target.encoredMoveID)
        XCTAssertTrue(caster.lastMoveFailed)
    }

    /// 봉인은 **겹치는 기술만** 적어 둔다. 겹치는 것이 없으면 실패다(본가와 같다).
    func testImprisonSealsTheMovesBothSidesKnow() {
        var caster = side(moves: [lockMove(286), attackMove(34)])
        var target = side(moves: [attackMove(33), attackMove(34)])
        use(lockMove(286), by: &caster, on: &target)

        XCTAssertEqual(target.imprisonedMoveIDs, [34])
        XCTAssertEqual(target.selectionLock(forMoveAt: 1), .imprison)
        XCTAssertNil(target.selectionLock(forMoveAt: 0))
    }

    func testImprisonFailsWhenTheTwoShareNothing() {
        var caster = side(moves: [lockMove(286)])
        var target = side(moves: [attackMove(33), attackMove(34)])
        use(lockMove(286), by: &caster, on: &target)

        XCTAssertFalse(target.has(.imprison), "겹치는 기술이 없는데 봉인이 붙었다")
        XCTAssertTrue(target.imprisonedMoveIDs.isEmpty)
        XCTAssertTrue(caster.lastMoveFailed)
    }

    /// 트집·봉인은 턴을 세지 않는다(0 = 교체할 때까지). 도발·비밀의힘은 센다 — 둘을 한 값으로
    /// 접으면 트집이 세 턴 만에 풀리거나 도발이 배틀 내내 산다.
    func testOnlyTheTimedLocksCarryAClock() {
        var caster = side(moves: [lockMove(259), lockMove(377)])
        var target = side(moves: [attackMove(33), statusMove(105)])

        use(lockMove(259), by: &caster, on: &target)
        XCTAssertEqual(target.volatiles[.torment], 0, "트집은 턴을 세지 않는다")

        use(lockMove(377), by: &caster, on: &target)
        XCTAssertEqual(target.volatiles[.healBlock], 5)
        XCTAssertEqual(target.selectionLock(forMoveAt: 1), .healBlock)
    }

    /// 턴이 다 지나면 잠금이 **풀린다** — 안 풀리면 3턴짜리 도발이 배틀 내내 산다.
    /// (턴을 세는 자리는 `endOfTurnResidual` 이라 여기서 그 함수를 직접 돌린다.)
    func testATimedLockLiftsWhenItsClockRunsOut() {
        var caster = side(moves: [lockMove(269)])
        var target = side(moves: [attackMove(33), statusMove(45)])
        use(lockMove(269), by: &caster, on: &target)

        var ended: [BattleEvent] = []
        for _ in 0..<BattleVolatile.taunt.foeDuration {
            ended += BattleEngine.endOfTurnResidual(&target, actor: .b)
        }

        XCTAssertFalse(target.has(.taunt), "도발이 제 시간에 풀리지 않았다")
        XCTAssertTrue(ended.contains(.volatileEnded(.b, .taunt)))
        XCTAssertNil(target.selectionLock(forMoveAt: 1))
    }

    // MARK: 구애 2종 — 잠그는 것이 상대가 아니라 자기 물건이다

    /// 구애 2종은 지닌물건 축을 그대로 탄다 — 가방·와이어 검증·상점이 이 한 축을 보므로
    /// 하나라도 빠지면 "가방에서는 지니게 되는데 배틀에서는 아무 일도 안 하는" 물건이 된다.
    func testTheChoiceItemsRideTheHeldItemAxis() {
        for kind in [ItemKind.choiceBand, .choiceSpecs] {
            XCTAssertEqual(kind.bagUse, .heldItem, "\(kind) 가 지닌물건 갈래가 아니다")
            XCTAssertNotNil(kind.heldBattleEffect, "\(kind) 가 배틀에서 하는 일이 없다")
            XCTAssertNotNil(kind.shopPrice, "\(kind) 를 상점에서 못 산다")
            XCTAssertNil(kind.evolutionRule)
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "피어의 \(kind) 가 반려된다")
        }
        XCTAssertEqual(ItemKind.choiceBand.heldBattleEffect?.boostedDamageClass, .physical)
        XCTAssertEqual(ItemKind.choiceSpecs.heldBattleEffect?.boostedDamageClass, .special)
    }

    /// 구애머리띠는 **물리만** 1.5 배로 만든다 — 특수까지 올리면 안경과 같은 물건이 된다.
    func testTheChoiceBandRaisesOnlyPhysicalDamage() {
        let physical = damage(of: attackMove(33), holding: .choiceBand)
        let bare = damage(of: attackMove(33), holding: nil)
        XCTAssertEqual(physical, bare * HeldItemBalance.choiceNumerator / HeldItemBalance.choiceDenominator)

        let special = damage(of: attackMove(34, damageClass: .special), holding: .choiceBand)
        XCTAssertEqual(special, damage(of: attackMove(34, damageClass: .special), holding: nil),
                       "머리띠가 특수 기술까지 올렸다")
    }

    func testTheChoiceSpecsRaiseOnlySpecialDamage() {
        let special = damage(of: attackMove(34, damageClass: .special), holding: .choiceSpecs)
        let bare = damage(of: attackMove(34, damageClass: .special), holding: nil)
        XCTAssertEqual(special, bare * HeldItemBalance.choiceNumerator / HeldItemBalance.choiceDenominator)
        XCTAssertEqual(damage(of: attackMove(33), holding: .choiceSpecs),
                       damage(of: attackMove(33), holding: nil), "안경이 물리 기술까지 올렸다")
    }

    /// 대가는 선택이다 — 처음 낸 기술 하나로 묶이고 나머지 칸이 막힌다.
    func testAChoiceItemLocksTheFirstMoveItUsed() {
        var mon = side(moves: [attackMove(33), attackMove(34)], holding: .choiceBand)
        var target = side(moves: [attackMove(33)])
        use(attackMove(33), by: &mon, on: &target)

        XCTAssertEqual(mon.choiceLockedMoveID, 33)
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .choiceItem)
    }

    /// 구애를 안 지녔으면 아무것도 묶이지 않는다 — 잠금 조건이 뒤집혀 있으면 이 테스트가 빨개진다.
    func testAMonWithoutAChoiceItemStaysFree() {
        var mon = side(moves: [attackMove(33), attackMove(34)], holding: .leftovers)
        var target = side(moves: [attackMove(33)])
        use(attackMove(33), by: &mon, on: &target)

        XCTAssertNil(mon.choiceLockedMoveID)
        XCTAssertNil(mon.selectionLock(forMoveAt: 1))
    }

    /// 발버둥으로는 묶이지 않는다 — 무브셋에 없는 기술이라 묶으면 그 뒤 아무 칸도 못 고른다.
    func testStruggleNeverBecomesTheChoiceLock() {
        var mon = side(moves: [attackMove(33), attackMove(34)], holding: .choiceBand)
        var target = side(moves: [attackMove(33)])
        use(.struggle(), by: &mon, on: &target)

        XCTAssertNil(mon.choiceLockedMoveID)
    }

    // MARK: 고르는 자리가 넷 + 터미널이다

    /// **CPU 도 잠금을 지킨다.** 웨이브의 CPU 는 자기 배열에서 직접 행동을 만들어 모드의
    /// 사전 검증을 지나지 않으므로, 남은 PP 만 보고 고르면 도발당한 상대가 변화기를 그대로 낸다
    /// (화면에는 도발이 걸린 것으로 보이고 효과만 새어 나간다).
    func testTheWaveCPUPicksStruggleWhenEveryMoveIsLocked() {
        let paralyzer = statusMove(86)
        var status = paralyzer
        status.ailment = "paralysis"; status.ailmentChance = 100
        let foe = BattleSnapshot(speciesID: 90, name: "상대", trainer: "T", level: 50, nature: nil,
                                 isShiny: false, types: [.normal],
                                 base: BattleStats(hp: 200, atk: 80, def: 80, spa: 80, spd: 80, spe: 60),
                                 moves: [status])
        let mine = BattleSnapshot(speciesID: 1, name: "내편", trainer: "T", level: 50, nature: nil,
                                  isShiny: false, types: [.normal],
                                  base: BattleStats(hp: 200, atk: 80, def: 80, spa: 80, spd: 80, spe: 200),
                                  moves: [attackMove(33)])
        var subject = WaveBattle(mine: [BattleSide(mine)], opponents: [BattleSide(foe)],
                                 rng: SplitMix64(seed: 5))
        XCTAssertTrue(subject.opponents[0].start(.taunt, turns: 3))
        let foeHP = subject.opponents[0].hp

        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))

        XCTAssertNil(subject.mine[0].status, "도발당한 상대가 변화기를 그대로 냈다")
        XCTAssertLessThan(subject.opponents[0].hp, foeHP,
                          "낼 기술이 없으면 발버둥이라 반동으로 HP 가 줄어야 한다")
    }

    /// 기술을 **고르는 자리**는 남은 PP 가 아니라 `canUse(moveAt:)` 로 고른다 — 잠금을 모르는
    /// 자리가 하나 남으면 그 모드에서만 도발·구애가 새어 나가고, 화면에는 정상으로 보인다.
    /// 부류로 막아야 하는 이유는 자리가 다섯이라서다(CPU 넷 + 보스 폴백).
    func testNoChooserPicksAMoveByRawPPAlone() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "소스를 못 찾으면 이 가드는 아무것도 지키지 않는다")

        var offenders: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.split(separator: "//", maxSplits: 1).first.map(String.init) ?? ""
                guard code.contains("pp") else { continue }
                // 고르는 자리의 두 모양: `pp` 를 걸러 후보를 만드는 것과 첫 칸을 찾는 것.
                if code.contains("pp[$0] > 0") || code.contains("pp.firstIndex(where: { $0 > 0 })") {
                    offenders.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }
        XCTAssertEqual(offenders, [], "이 자리는 canUse(moveAt:) 로 골라야 한다: \(offenders)")
    }

    // MARK: 화면과 터미널이 읽는 자리

    /// 버튼 네 칸의 잠금 상태는 **한 배열**로 답한다 — 화면마다 `selectionLock` 을 따로 훑으면
    /// 한 화면에서만 잠금이 안 보인다(UI 규약: 못 쓰는 조작은 숨기지 않고 비활성으로 남긴다).
    func testTheGridReadsEveryLockInOneArray() {
        var mon = side(moves: [attackMove(33), statusMove(45), statusMove(105)])
        XCTAssertTrue(mon.start(.taunt, turns: 3))
        XCTAssertEqual(mon.selectionLocks, [nil, .taunt, .taunt])
        XCTAssertEqual(side(moves: [attackMove(33)]).selectionLocks, [nil])
    }

    /// 잠금 사유는 세 언어 다 있고 **서로 다르다** — 같은 문구를 돌려주면 화면이 왜 못 누르는지
    /// 말하지 못한다(비활성 버튼만 남고 이유가 사라진다).
    func testEveryLockReasonReadsInThreeLanguages() {
        for language in AppLanguage.allCases {
            let l = L(language)
            var seen: Set<String> = []
            for lock in MoveSelectionLock.allCases {
                let text = l.moveSelectionLockReason(lock)
                XCTAssertFalse(text.isEmpty, "\(lock) 의 \(language) 문구가 비어 있다")
                XCTAssertTrue(seen.insert(text).inserted, "\(lock) 이 다른 잠금과 같은 문구다: \(text)")
            }
        }
    }

    /// 터미널의 기술 목록도 같은 판정을 지난다 — 목록에 남으면 골랐다가 거절당하고,
    /// 거절 사유가 없으면 사용자는 그 기술이 왜 안 나가는지 알 수 없다.
    func testTheTerminalOffersOnlyTheMovesItCanUse() {
        var mon = side(moves: [attackMove(33), statusMove(45)])
        XCTAssertTrue(mon.start(.taunt, turns: 3))
        let offered = mon.moves.indices.filter { mon.canUse(moveAt: $0) }
        XCTAssertEqual(offered, [0], "도발당한 개체의 변화기가 터미널 목록에 남았다")
    }
}
