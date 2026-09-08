import XCTest
@testable import PokeTokenBar

/// 접촉·펀치·소리·다단·조이기에 답하는 물건 8종 — 울퉁불퉁멧·끈적끈적바늘·방호패드·펀치글러브·
/// 속임수주사위·조임밴드·끈기갈고리손톱·목스프레이.
///
/// 여덟이 묻는 것은 전부 **기술의 성질**이고 PokéAPI 에는 그 성질이 없다(접촉·펀치·소리 플래그가
/// 아예 없는 테이블이다). 그래서 쇼다운 데이터가 어느 기술인지 답하고(`ShowdownMoveData`) 엔진은
/// 규칙만 구현한다 — 접촉 기술 목록을 손으로 들면 277개가 조용히 낡는다.
final class ContactItemTests: XCTestCase {

    private static let items: [ItemKind] = [
        .rockyHelmet, .stickyBarb, .protectivePads, .punchingGlove,
        .loadedDice, .bindingBand, .gripClaw, .throatSpray
    ]

    private func side(types: [PokemonType] = [.normal], held: ItemKind? = nil,
                      hp: Int? = nil) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: types,
                                            base: BattleStats(hp: 200, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: 100),
                                            heldItem: held, weightHectograms: 100))
        if let hp { out.hp = hp }
        return out
    }

    /// 실제 기술 id 를 쓴다 — 접촉·펀치·소리는 id 로 답하므로 합성 id 는 아무 플래그도 못 든다.
    private func move(_ id: Int, type: PokemonType = .normal, power: Int = 60,
                      damageClass: MoveDamageClass = .physical) -> MoveSpec {
        var out = MoveSpec(id: id, names: ["ko": "기술\(id)"], type: type, power: power,
                           damageClass: damageClass, accuracy: nil, pp: 10)
        out.ailment = "none"; out.ailmentChance = 0
        out.statChanges = []; out.statChance = 0; out.targetsUser = false
        return out
    }

    @discardableResult
    private func hit(_ spec: MoveSpec, attacker: inout BattleSide, defender: inout BattleSide,
                     seed: UInt64 = 11) -> [BattleEvent] {
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyHit(attacker: &attacker, defender: &defender, attackerActor: .a,
                                     defenderActor: .b, move: spec, rng: &rng)
    }

    // MARK: - 기술 플래그

    /// 세 플래그는 쇼다운 데이터에서 온다 — 엔진이 목록을 따로 들지 않는다.
    func testTheMoveFlagsComeFromTheShowdownTable() {
        XCTAssertTrue(move(33).makesContact, "몸통박치기가 접촉이 아니다")
        XCTAssertFalse(move(52).makesContact, "불꽃세례가 접촉이다")
        XCTAssertTrue(move(7).isPunch, "불꽃펀치가 펀치가 아니다")
        XCTAssertTrue(move(7).makesContact, "불꽃펀치가 접촉이 아니다")
        XCTAssertFalse(move(33).isPunch, "몸통박치기가 펀치다")
        XCTAssertTrue(move(45).isSound, "울음소리가 소리 기술이 아니다")
        XCTAssertFalse(move(33).isSound, "몸통박치기가 소리 기술이다")
        // 접촉은 손으로 들 수 없는 규모라는 것이 이 데이터를 쓰는 이유다.
        XCTAssertGreaterThan(ShowdownMoveData.makingContact.count, 200)
    }

    // MARK: - 아이템 축

    func testTheContactItemsRideTheHeldItemAxis() {
        for kind in Self.items {
            XCTAssertEqual(kind.bagUse, .heldItem, kind.rawValue)
            XCTAssertNotNil(kind.heldBattleEffect, kind.rawValue)
            XCTAssertNil(kind.evolutionRule, kind.rawValue)
            XCTAssertNotNil(kind.shopPrice, kind.rawValue)
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "피어의 \(kind.rawValue) 가 반려된다")
            XCTAssertFalse(L().itemName(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().itemDescription(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().heldItemEffectHint(kind).isEmpty, kind.rawValue)
        }
        XCTAssertEqual(L().itemName(.rockyHelmet), "울퉁불퉁멧")
        XCTAssertEqual(L().itemName(.protectivePads), "방호패드")
        XCTAssertEqual(ItemKind.gripClaw.spriteName, "grip-claw")
        // 셋만 PokéAPI 에 스프라이트가 없다(8·9세대) — 이모지 폴백만 쓴다.
        for kind in [ItemKind.punchingGlove, .loadedDice, .throatSpray] {
            XCTAssertNil(kind.spriteName, kind.rawValue)
        }
    }

    // MARK: - 울퉁불퉁멧

    /// 접촉 기술로 때린 쪽이 최대 HP 의 1/6 을 잃는다. 접촉이 아닌 기술은 아무 일도 없다.
    func testTheRockyHelmetHurtsWhoeverTouchesIt() {
        var attacker = side()
        var holder = side(held: .rockyHelmet)
        let events = hit(move(33), attacker: &attacker, defender: &holder)
        XCTAssertEqual(attacker.hp, attacker.stats.hp - attacker.stats.hp / 6)
        XCTAssertTrue(events.contains(.damage(.a, amount: attacker.stats.hp / 6, cause: .heldItem)))
        XCTAssertFalse(holder.heldItemConsumed, "멧은 소모품이 아니다")

        var ranged = side()
        var second = side(held: .rockyHelmet)
        hit(move(52, type: .fire, damageClass: .special), attacker: &ranged, defender: &second)
        XCTAssertEqual(ranged.hp, ranged.stats.hp, "접촉이 아닌 기술에 멧이 답했다")
    }

    /// 층(대타출동)이 대신 맞으면 때린 쪽은 멧에 닿지 않는다 — 인형을 때린 것이다.
    func testTheRockyHelmetDoesNotAnswerAHitTheSubstituteTook() {
        var attacker = side()
        var holder = side(held: .rockyHelmet)
        XCTAssertTrue(holder.raiseSubstitute(costDivisor: 4))
        hit(move(33), attacker: &attacker, defender: &holder)
        XCTAssertEqual(attacker.hp, attacker.stats.hp)
    }

    // MARK: - 방호패드·펀치글러브

    /// 방호패드를 쥔 쪽은 접촉 효과를 받지 않는다 — 멧에 닿아도 깎이지 않는다.
    func testTheProtectivePadsKeepContactEffectsAway() {
        var attacker = side(held: .protectivePads)
        var holder = side(held: .rockyHelmet)
        hit(move(33), attacker: &attacker, defender: &holder)
        XCTAssertEqual(attacker.hp, attacker.stats.hp)
    }

    /// 펀치글러브는 **펀치 기술만** 접촉에서 빼고 그 위력을 1.1 배로 만든다.
    func testThePunchingGloveBoostsPunchesAndTakesTheirContactAway() {
        var gloved = side(held: .punchingGlove)
        var holder = side(held: .rockyHelmet)
        hit(move(7, type: .fire), attacker: &gloved, defender: &holder)
        XCTAssertEqual(gloved.hp, gloved.stats.hp, "펀치가 접촉으로 남아 멧에 깎였다")

        // 펀치가 아닌 접촉 기술은 그대로 접촉이다.
        var second = side(held: .punchingGlove)
        var secondHolder = side(held: .rockyHelmet)
        hit(move(33), attacker: &second, defender: &secondHolder)
        XCTAssertLessThan(second.hp, second.stats.hp, "펀치가 아닌 기술이 접촉에서 빠졌다")

        // 위력은 1.1 배다 — 같은 기술을 빈손으로 쓴 것과 비교한다.
        var bare = side()
        var target = side()
        var boostedTarget = side()
        var boosted = side(held: .punchingGlove)
        hit(move(7, type: .fire), attacker: &bare, defender: &target)
        hit(move(7, type: .fire), attacker: &boosted, defender: &boostedTarget)
        XCTAssertLessThan(boostedTarget.hp, target.hp, "펀치글러브가 위력을 안 올렸다")
    }

    // MARK: - 끈적끈적바늘

    /// 매 턴 최대 HP 의 1/8 을 잃고, 접촉 기술에 맞으면 **때린 쪽으로 옮겨 간다**.
    func testTheStickyBarbHurtsItsHolderAndMovesOnContact() {
        var holder = side(held: .stickyBarb)
        _ = BattleEngine.endOfTurnResidual(&holder, actor: .b)
        XCTAssertEqual(holder.hp, holder.stats.hp - holder.stats.hp / 8)

        var attacker = side()
        var barbed = side(held: .stickyBarb)
        hit(move(33), attacker: &attacker, defender: &barbed)
        XCTAssertEqual(attacker.activeHeldItem, .stickyBarb, "바늘이 옮겨 가지 않았다")
        XCTAssertEqual(attacker.heldEffect, .stickyBarb)
        XCTAssertTrue(barbed.heldItemConsumed, "옮겨 갔는데 원래 쥔 쪽에 남았다")

        // 이미 무엇을 쥔 쪽에는 옮겨 가지 않는다(본가와 같다).
        var holding = side(held: .rockyHelmet)
        var second = side(held: .stickyBarb)
        hit(move(33), attacker: &holding, defender: &second)
        XCTAssertEqual(holding.activeHeldItem, .rockyHelmet)
        XCTAssertFalse(second.heldItemConsumed)
    }

    // MARK: - 속임수주사위

    /// 다단 기술이 **최소 네 번** 맞는다 — 2~5회 기술이 4회 아래로 내려가지 않는다.
    func testTheLoadedDiceFloorsMultiHitMovesAtFour() {
        var doubleSlap = move(3, power: 15)
        doubleSlap.minHits = 2
        doubleSlap.maxHits = 5
        for seed in UInt64(1)...12 {
            var rng = SplitMix64(seed: seed)
            let bare = doubleSlap.hitCount(rng: &rng, minimumHits: nil)
            XCTAssertTrue((2...5).contains(bare))
            var loadedRNG = SplitMix64(seed: seed)
            let loaded = doubleSlap.hitCount(rng: &loadedRNG,
                                             minimumHits: HeldItemBalance.loadedDiceFloor)
            XCTAssertTrue((4...5).contains(loaded), "seed \(seed) 에서 \(loaded) 회 맞았다")
        }
        // 단발 기술은 주사위가 만지지 않는다 — 몸통박치기가 네 번 맞으면 안 된다.
        var rng = SplitMix64(seed: 3)
        XCTAssertEqual(move(33).hitCount(rng: &rng,
                                         minimumHits: HeldItemBalance.loadedDiceFloor), 1)
    }

    // MARK: - 조임밴드·끈기갈고리손톱

    /// 조임밴드는 조이기 잔뎀을 1/8 에서 1/6 으로 키운다 — **거는 쪽**의 물건이다.
    func testTheBindingBandDeepensTheTrapItsHolderSets() {
        var binder = side(held: .bindingBand)
        var trapped = side()
        hit(move(20), attacker: &binder, defender: &trapped)
        XCTAssertNotNil(trapped.volatiles[.partiallyTrapped], "조이기가 안 걸렸다")
        XCTAssertEqual(trapped.trapDamageDivisor, HeldItemBalance.bindingBandDivisor)

        let before = trapped.hp
        _ = BattleEngine.endOfTurnResidual(&trapped, actor: .b)
        XCTAssertEqual(before - trapped.hp, trapped.stats.hp / HeldItemBalance.bindingBandDivisor)
    }

    /// 끈기갈고리손톱은 조이기를 7턴으로 늘린다 — 4~5턴 난수를 대신한다.
    func testTheGripClawFixesTheTrapAtSevenTurns() {
        var binder = side(held: .gripClaw)
        var trapped = side()
        hit(move(20), attacker: &binder, defender: &trapped)
        XCTAssertEqual(trapped.volatiles[.partiallyTrapped], HeldItemBalance.gripClawTrapTurns)

        var bare = side()
        var second = side()
        hit(move(20), attacker: &bare, defender: &second)
        let plain = second.volatiles[.partiallyTrapped] ?? 0
        XCTAssertTrue((BattleVolatile.trapTurnFloor...BattleVolatile.trapTurnFloor + 1).contains(plain))
    }

    // MARK: - 목스프레이

    /// 소리 기술을 쓰면 특수공격이 한 단계 오르고 사라진다 — 소리가 아닌 기술은 아무 일도 없다.
    func testTheThroatSprayAnswersTheHoldersSoundMove() {
        var holder = side(held: .throatSpray)
        var target = side()
        var sound = move(45, power: 0, damageClass: .status)
        sound.statChanges = [StatChange(stat: .atk, change: -1)]
        let events = hit(sound, attacker: &holder, defender: &target)
        XCTAssertEqual(holder.stage(.spa), 1)
        XCTAssertTrue(holder.heldItemConsumed)
        XCTAssertTrue(events.contains(.heldItemTriggered(.a, .throatSpray)))

        var quiet = side(held: .throatSpray)
        var second = side()
        hit(move(33), attacker: &quiet, defender: &second)
        XCTAssertEqual(quiet.stage(.spa), 0, "소리가 아닌 기술에 스프레이가 터졌다")
        XCTAssertFalse(quiet.heldItemConsumed)
    }
}
