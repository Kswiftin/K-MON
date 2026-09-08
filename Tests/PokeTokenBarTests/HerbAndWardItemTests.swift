import XCTest
@testable import PokeTokenBar

/// 허브·무효화 물건 5종 — 하양허브(내려간 랭크 원복), 멘탈허브(선택 잠금 해제),
/// 흉내허브(상대의 랭크 상승 따라하기), 클리어참(랭크 하락 차단), 은밀망토(부가효과 차단).
///
/// 앞 배치들과 갈리는 점은 **다른 기전이 이미 한 일**에 답한다는 것이다: 랭크가 내려간 뒤, 잠금이
/// 걸린 뒤, 상대가 올린 뒤에 움직인다. 그래서 묻는 자리를 기술 하나가 끝나는 **한 곳**으로 모은다 —
/// 랭크를 만지는 자리마다 물으면 새 자리가 늘 때 그 경로에서만 허브가 죽는다.
///
/// 파워허브(2턴 기술 즉발)와 특성가드(특성 변경 차단)는 뺐다 — 이 엔진에는 2턴 기술도 특성을
/// 바꾸는 기술도 없어서, 넣으면 아무 일도 하지 않는 물건이 된다.
final class HerbAndWardItemTests: XCTestCase {

    private static let items: [ItemKind] = [
        .whiteHerb, .mentalHerb, .mirrorHerb, .clearAmulet, .covertCloak
    ]

    private func side(held: ItemKind? = nil, moves: [MoveSpec]? = nil) -> BattleSide {
        BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                  nature: nil, isShiny: false, types: [.normal],
                                  base: BattleStats(hp: 100, atk: 100, def: 100,
                                                    spa: 100, spd: 100, spe: 100),
                                  moves: moves, heldItem: held, weightHectograms: 100))
    }

    private func move(_ id: Int, power: Int = 0, damageClass: MoveDamageClass = .status,
                      statChanges: [StatChange] = [], ailment: String = "none",
                      ailmentChance: Int = 0) -> MoveSpec {
        var out = MoveSpec(id: id, names: ["ko": "기술\(id)"], type: .normal, power: power,
                           damageClass: damageClass, accuracy: nil, pp: 10)
        out.ailment = ailment; out.ailmentChance = ailmentChance
        out.statChanges = statChanges
        out.statChance = statChanges.isEmpty ? 0 : 100
        out.targetsUser = false
        return out
    }

    private func attack(_ spec: MoveSpec, attacker: inout BattleSide, defender: inout BattleSide,
                        seed: UInt64 = 7) -> [BattleEvent] {
        var field = BattleField()
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                        attackerActor: .a, defenderActor: .b, move: spec,
                                        field: &field, rng: &rng)
    }

    /// 상대의 공격 랭크를 하나 깎는 변화기(울부짖기 자리).
    private func lowersFoeAttack() -> MoveSpec {
        move(46, statChanges: [StatChange(stat: .atk, change: -1)])
    }

    /// 자기 공격 랭크를 둘 올리는 변화기(칼춤 자리).
    private func raisesOwnAttack() -> MoveSpec {
        move(14, statChanges: [StatChange(stat: .atk, change: 2)])
    }

    // MARK: - 아이템 축

    func testTheHerbsAndWardsRideTheHeldItemAxis() {
        for kind in Self.items {
            XCTAssertEqual(kind.bagUse, .heldItem, kind.rawValue)
            XCTAssertNotNil(kind.heldBattleEffect, kind.rawValue)
            XCTAssertNil(kind.evolutionRule, kind.rawValue)
            XCTAssertNotNil(kind.shopPrice, kind.rawValue)
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "피어의 \(kind.rawValue) 가 반려된다")
            XCTAssertFalse(L().itemName(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().itemDescription(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().heldItemEffectHint(kind).isEmpty, kind.rawValue)
            XCTAssertNil(kind.heldBattleEffect?.restrictedSpecies, "\(kind.rawValue) 에 종 제한이 생겼다")
        }
        XCTAssertEqual(L().itemName(.mirrorHerb), "흉내허브")
        XCTAssertEqual(ItemKind.whiteHerb.spriteName, "white-herb")
        // 9세대 물건 셋은 PokéAPI 에 스프라이트가 없다 — 이모지 폴백만 쓴다.
        for kind in [ItemKind.mirrorHerb, .clearAmulet, .covertCloak] {
            XCTAssertNil(kind.spriteName, kind.rawValue)
        }
    }

    // MARK: - 하양허브

    /// 내려간 랭크가 원래대로 돌아오고 허브는 사라진다.
    func testTheWhiteHerbUndoesTheDropAndIsSpent() {
        var attacker = side(), holder = side(held: .whiteHerb)
        let events = attack(lowersFoeAttack(), attacker: &attacker, defender: &holder)
        XCTAssertEqual(holder.stage(.atk), 0, "허브가 랭크를 안 돌려놨다")
        XCTAssertTrue(holder.heldItemConsumed)
        XCTAssertTrue(events.contains(.heldItemTriggered(.b, .whiteHerb)))

        // 한 번 쓰면 그만이다 — 두 번째 하락은 그대로 남는다.
        _ = attack(lowersFoeAttack(), attacker: &attacker, defender: &holder)
        XCTAssertEqual(holder.stage(.atk), -1)
    }

    /// 올라간 랭크는 건드리지 않는다 — 내려간 것만 되돌린다.
    func testTheWhiteHerbLeavesTheRaisedStagesAlone() {
        var holder = side(held: .whiteHerb), foe = side()
        _ = attack(raisesOwnAttack(), attacker: &holder, defender: &foe)
        XCTAssertEqual(holder.stage(.atk), 2)
        XCTAssertFalse(holder.heldItemConsumed, "올라간 랭크에 허브가 반응했다")
    }

    // MARK: - 클리어참

    /// 클리어참은 상대가 내리는 랭크를 아예 막는다 — 되돌리는 하양허브와 달리 소모되지 않는다.
    func testTheClearAmuletBlocksTheDropWithoutBeingSpent() {
        var attacker = side(), holder = side(held: .clearAmulet)
        _ = attack(lowersFoeAttack(), attacker: &attacker, defender: &holder)
        XCTAssertEqual(holder.stage(.atk), 0)
        XCTAssertFalse(holder.heldItemConsumed)
        // 자기 랭크 상승은 막지 않는다 — 막으면 쥔 쪽이 손해를 본다.
        var foe = side()
        _ = attack(raisesOwnAttack(), attacker: &holder, defender: &foe)
        XCTAssertEqual(holder.stage(.atk), 2)
    }

    /// 끈적끈적네트도 남이 내리는 랭크다 — 참을 쥐면 밟아도 안 느려진다.
    func testTheClearAmuletBlocksTheStickyWeb() {
        var field = BattleField()
        XCTAssertTrue(field.start(.stickyWeb, for: .a))
        var holder = side(held: .clearAmulet)
        var rng = SplitMix64(seed: 3)
        _ = BattleEngine.applyEntryHazards(&holder, actor: .a, team: .a, field: field, rng: &rng)
        XCTAssertEqual(holder.stage(.spe), 0)
        var bare = side()
        _ = BattleEngine.applyEntryHazards(&bare, actor: .a, team: .a, field: field, rng: &rng)
        XCTAssertEqual(bare.stage(.spe), -1)
    }

    // MARK: - 흉내허브

    /// 상대가 올린 만큼 따라 올리고 사라진다.
    func testTheMirrorHerbCopiesTheFoeBoost() {
        var booster = side(), holder = side(held: .mirrorHerb)
        let events = attack(raisesOwnAttack(), attacker: &booster, defender: &holder)
        XCTAssertEqual(booster.stage(.atk), 2)
        XCTAssertEqual(holder.stage(.atk), 2, "흉내허브가 안 따라 올렸다")
        XCTAssertTrue(holder.heldItemConsumed)
        XCTAssertTrue(events.contains(.heldItemTriggered(.b, .mirrorHerb)))
    }

    /// 상대가 내려간 것은 따라하지 않는다 — 올린 것만 본다.
    func testTheMirrorHerbIgnoresTheFoeDrop() {
        var attacker = side(), holder = side(held: .mirrorHerb)
        _ = attack(lowersFoeAttack(), attacker: &attacker, defender: &holder)
        XCTAssertEqual(holder.stage(.atk), -1)
        XCTAssertFalse(holder.heldItemConsumed)
    }

    // MARK: - 은밀망토

    /// 공격기에 딸린 부가효과(상태·풀죽음·랭크 하락)가 안 붙는다.
    func testTheCovertCloakBlocksTheAddedEffects() {
        var attacker = side()
        var holder = side(held: .covertCloak)
        _ = attack(move(52, power: 60, damageClass: .physical, ailment: "burn",
                        ailmentChance: 100), attacker: &attacker, defender: &holder)
        XCTAssertNil(holder.status, "부가 상태가 붙었다")

        var dropped = side(held: .covertCloak)
        _ = attack(move(479, power: 60, damageClass: .physical,
                        statChanges: [StatChange(stat: .def, change: -1)]),
                   attacker: &attacker, defender: &dropped)
        XCTAssertEqual(dropped.stage(.def), 0, "부가 랭크 하락이 붙었다")
        XCTAssertFalse(dropped.heldItemConsumed, "망토는 소모되지 않는다")
    }

    /// 변화기가 본래 하는 일은 못 막는다 — 울부짖기의 하락은 부가효과가 아니다.
    func testTheCovertCloakDoesNotBlockAStatusMoveItself() {
        var attacker = side(), holder = side(held: .covertCloak)
        _ = attack(lowersFoeAttack(), attacker: &attacker, defender: &holder)
        XCTAssertEqual(holder.stage(.atk), -1)
    }

    // MARK: - 멘탈허브

    /// 도발이 걸리는 즉시 풀리고 허브는 사라진다.
    func testTheMentalHerbClearsTheSelectionLock() {
        let tackle = move(33, power: 40, damageClass: .physical)
        var attacker = side(moves: [tackle])
        var holder = side(held: .mentalHerb, moves: [tackle])
        let events = attack(move(269), attacker: &attacker, defender: &holder)   // 도발
        XCTAssertFalse(holder.has(.taunt), "도발이 남았다")
        XCTAssertTrue(holder.heldItemConsumed)
        XCTAssertTrue(events.contains(.heldItemTriggered(.b, .mentalHerb)))

        var bare = side(moves: [tackle])
        _ = attack(move(269), attacker: &attacker, defender: &bare)
        XCTAssertTrue(bare.has(.taunt), "허브 없이도 도발이 안 걸렸다 — 이 테스트가 아무것도 안 본다")
    }
}
