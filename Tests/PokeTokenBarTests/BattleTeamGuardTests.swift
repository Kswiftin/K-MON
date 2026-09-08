import XCTest
@testable import PokeTokenBar

/// 편 방어기 넷 — 와이드가드·퀵가드·니가하지마·트릭가드.
///
/// 개인 방어(`BattleGuard`)와 갈리는 점이 둘이다: **편 전체**를 지키고(그래서 개체가 아니라
/// `BattleField` 의 진영 상태다), 넷이 서로 **막는 기술의 종류**로 갈린다. 확률·카운터는
/// 개인 방어와 하나를 공유한다 — 따로 두면 방어와 와이드가드를 번갈아 눌러 벌점 없는 무적이 된다.
final class BattleTeamGuardTests: XCTestCase {

    private func side(_ hp: Int = 9_999) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: [.normal],
                                            base: BattleStats(hp: 100, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: 100),
                                            weightHectograms: 100))
        out.hp = hp
        return out
    }

    private func spec(_ id: Int, power: Int = 60, damageClass: MoveDamageClass = .physical,
                      priority: Int? = nil, target: String? = nil) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "기술"], type: .normal, power: power,
                            damageClass: damageClass, accuracy: nil, pp: 10, target: target)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = false
        move.priority = priority
        return move
    }

    /// 편 방어기 스펙 — 위력 0 변화기이고 실제 id 로 데이터를 지난다.
    private func guardSpec(_ condition: BattleSideCondition) -> MoveSpec {
        let id = ShowdownMoveData.effects.keys.sorted()
            .first { BattleSideCondition.called(byMoveID: $0) == condition }
        return spec(id ?? -1, power: 0, damageClass: .status)
    }

    /// 편 `.b` 에 상태를 깔고 그 편을 때린다 — 막혔는지만 돌려준다.
    private func isBlocked(_ move: MoveSpec, by condition: BattleSideCondition?) -> Bool {
        var field = BattleField()
        if let condition { XCTAssertTrue(field.start(condition, for: .b)) }
        var attacker = side(), defender = side()
        var rng = SplitMix64(seed: 4)
        return BattleEngine.applyHit(attacker: &attacker, defender: &defender,
                                     attackerActor: .a, defenderActor: .b, move: move,
                                     field: field, defenderTeam: .b, rng: &rng)
            == [.guardBlocked(.b)]
    }

    // MARK: 데이터가 어느 기술인지 답한다

    /// 네 키가 전부 실제 기술로 이어진다 — 미구현 목록에서 뺐으니 이제 엔진이 알아야 한다.
    func testEveryTeamGuardKeyReachesTheEngine() {
        let expected: [String: BattleSideCondition] = [
            "wideguard": .wideGuard, "quickguard": .quickGuard,
            "matblock": .matBlock, "craftyshield": .craftyShield,
        ]
        var seen: Set<String> = []
        for (id, effect) in ShowdownMoveData.effects {
            guard let key = effect.sideCondition, let condition = expected[key] else { continue }
            XCTAssertEqual(BattleSideCondition.called(byMoveID: id), condition,
                           "기술 \(id) 의 '\(key)' 를 엔진이 모른다")
            seen.insert(key)
        }
        XCTAssertEqual(seen, Set(expected.keys), "데이터에서 사라진 키가 있다 — 추출을 먼저 본다")
        XCTAssertTrue(BattleSideCondition.allCases.filter(\.guardsTheTeam).count == 4)
    }

    // MARK: 무엇을 막는가

    /// 와이드가드는 **광역기만** 막는다. 종류를 안 보면 편에 깔린 방어 한 장이 배틀을 잠근다.
    func testWideGuardBlocksSpreadMovesOnly() {
        let quake = spec(89, target: "all-other-pokemon")
        XCTAssertTrue(quake.hitsSpread, "대조군이 광역기가 아니면 이 테스트는 아무것도 재지 않는다")
        XCTAssertTrue(isBlocked(quake, by: .wideGuard))
        XCTAssertFalse(isBlocked(spec(33), by: .wideGuard), "단일 타겟은 와이드가드를 지나간다")
    }

    /// 퀵가드는 **우선도 기술만** 막는다.
    func testQuickGuardBlocksPriorityMovesOnly() {
        XCTAssertTrue(isBlocked(spec(98, priority: 1), by: .quickGuard))
        XCTAssertFalse(isBlocked(spec(33), by: .quickGuard), "보통 기술은 퀵가드를 지나간다")
        XCTAssertFalse(isBlocked(spec(387, priority: -6), by: .quickGuard),
                       "후공 기술도 퀵가드에 안 막힌다")
    }

    /// 니가하지마는 데미지를, 트릭가드는 변화기를 막는다 — **서로 반대**다.
    /// 한쪽만 재면 "둘 다 전부 막는다" 오구현이 초록으로 지나간다.
    func testMatBlockAndCraftyShieldBlockOppositeHalves() {
        let hit = spec(33)
        let statusMove = spec(45, power: 0, damageClass: .status)
        XCTAssertTrue(isBlocked(hit, by: .matBlock))
        XCTAssertFalse(isBlocked(statusMove, by: .matBlock), "니가하지마는 변화기를 안 막는다")
        XCTAssertTrue(isBlocked(statusMove, by: .craftyShield))
        XCTAssertFalse(isBlocked(hit, by: .craftyShield), "트릭가드는 공격을 안 막는다")
    }

    /// 아무것도 안 깔렸으면 그대로 맞는다 — 대조군이 없으면 "늘 막힌다" 가 통과한다.
    func testNothingIsBlockedWithoutATeamGuard() {
        XCTAssertFalse(isBlocked(spec(33), by: nil))
        XCTAssertFalse(isBlocked(spec(89, target: "all-other-pokemon"), by: nil))
    }

    /// 편에 깔리므로 **그 편의 모두**가 지켜지고, 반대편은 지켜지지 않는다.
    /// 개체에 붙는 개인 방어와 갈리는 자리다.
    func testATeamGuardCoversEveryMonOnThatSideOnly() {
        var field = BattleField()
        XCTAssertTrue(field.start(.matBlock, for: .b))
        var attacker = side()
        var first = side(), second = side(), other = side()
        var rng = SplitMix64(seed: 3)
        XCTAssertEqual(BattleEngine.applyHit(attacker: &attacker, defender: &first,
                                             attackerActor: .a, defenderActor: .b, move: spec(33),
                                             field: field, defenderTeam: .b, rng: &rng),
                       [.guardBlocked(.b)])
        XCTAssertEqual(BattleEngine.applyHit(attacker: &attacker, defender: &second,
                                             attackerActor: .a, defenderActor: .b, move: spec(33),
                                             field: field, defenderTeam: .b, rng: &rng),
                       [.guardBlocked(.b)], "같은 편 두 번째 칸도 지켜진다")
        _ = BattleEngine.applyHit(attacker: &attacker, defender: &other,
                                  attackerActor: .b, defenderActor: .a, move: spec(33),
                                  field: field, defenderTeam: .a, rng: &rng)
        XCTAssertLessThan(other.hp, 9_999, "반대편은 이 방어로 지켜지지 않는다")
    }

    /// 페인트 부류는 편 방어기도 뚫는다 — 개인 방어와 같은 예외 목록을 본다.
    func testFeintGoesThroughATeamGuard() throws {
        let feintID = try XCTUnwrap(ShowdownMoveData.ignoringGuard.sorted().first)
        XCTAssertFalse(isBlocked(spec(feintID), by: .matBlock))
    }

    // MARK: 개인 방어와 공유하는 규칙

    /// 막힌 기술은 **실패**로 센다(본가와 같다) — 분함의발구르기가 그 값을 읽는다.
    func testABlockedMoveCountsAsAFailure() {
        var field = BattleField()
        XCTAssertTrue(field.start(.matBlock, for: .b))
        var attacker = side(), defender = side()
        var rng = SplitMix64(seed: 1)
        _ = BattleEngine.applyHit(attacker: &attacker, defender: &defender, attackerActor: .a,
                                  defenderActor: .b, move: spec(33), field: field,
                                  defenderTeam: .b, rng: &rng)
        XCTAssertTrue(attacker.lastMoveFailed)
    }

    /// 한 턴짜리다 — 턴이 끝나면 걷힌다. 안 걷히면 편 방어 한 장이 배틀 내내 남는다.
    func testATeamGuardLastsOnlyOneTurn() {
        var field = BattleField()
        XCTAssertTrue(field.start(.wideGuard, for: .a))
        let ended = BattleEngine.advanceField(&field)
        XCTAssertTrue(ended.contains(.sideConditionEnded(.a, .wideGuard)))
        XCTAssertFalse(field.has(.wideGuard, for: .a))
    }

    /// 첫 편 방어기는 rng 를 뽑지 않고 확정으로 깔린다 — 개인 방어와 같은 규칙이다.
    func testTheFirstTeamGuardRollsNothing() {
        var user = side(), other = side()
        var field = BattleField()
        var rng = SplitMix64(seed: 11)
        var untouched = SplitMix64(seed: 11)
        let events = BattleEngine.applyAttack(attacker: &user, defender: &other, attackerActor: .a,
                                              defenderActor: .b, move: guardSpec(.wideGuard),
                                              field: &field, attackerTeam: .a, defenderTeam: .b,
                                              rng: &rng)
        XCTAssertTrue(events.contains(.sideConditionStarted(.a, .wideGuard)))
        XCTAssertTrue(field.has(.wideGuard, for: .a))
        XCTAssertEqual(user.guardStreak, 1, "카운터를 안 올리면 매 턴 확정 성공이다")
        XCTAssertEqual(rng.next(), untouched.next(), "첫 방어는 난수를 소비하지 않는다")
    }

    /// **연속 확률을 개인 방어와 공유한다.** 방어를 한 번 성공한 뒤의 와이드가드는 1/3 이다 —
    /// 카운터가 갈려 있으면 여기서 늘 성공한다(둘을 번갈아 누르면 무적이 된다).
    func testTeamGuardsShareTheConsecutiveFailureOddsWithProtect() {
        var outcomes = Set<Bool>()
        for seed in UInt64(0)..<40 {
            var user = side(), other = side()
            user.guardStreak = 1                     // 직전 턴에 방어를 성공한 상태
            var field = BattleField()
            var rng = SplitMix64(seed: seed)
            _ = BattleEngine.applyAttack(attacker: &user, defender: &other, attackerActor: .a,
                                         defenderActor: .b, move: guardSpec(.quickGuard),
                                         field: &field, attackerTeam: .a, defenderTeam: .b,
                                         rng: &rng)
            let up = field.has(.quickGuard, for: .a)
            outcomes.insert(up)
            XCTAssertEqual(user.guardStreak, up ? 2 : 0, "실패하면 카운터가 처음으로 돌아간다")
            XCTAssertEqual(user.lastMoveFailed, !up)
        }
        XCTAssertEqual(outcomes, [true, false], "연속 편 방어가 늘 성공하면 확률이 없는 것이다")
    }

    /// 편 방어기를 성공한 다음 턴의 **개인 방어**도 벌점을 받는다 — 카운터가 한 벌이라는 증거의 반대 방향.
    func testAProtectAfterATeamGuardInheritsTheStreak() {
        var user = side(), other = side()
        var field = BattleField()
        var rng = SplitMix64(seed: 2)
        _ = BattleEngine.applyAttack(attacker: &user, defender: &other, attackerActor: .a,
                                     defenderActor: .b, move: guardSpec(.matBlock),
                                     field: &field, attackerTeam: .a, defenderTeam: .b, rng: &rng)
        XCTAssertEqual(user.guardStreak, 1)

        var outcomes = Set<Bool>()
        for seed in UInt64(0)..<40 {
            var repeated = user, target = side()
            var seedRng = SplitMix64(seed: seed)
            _ = BattleEngine.applyAttack(attacker: &repeated, defender: &target, attackerActor: .a,
                                         defenderActor: .b,
                                         move: spec(182, power: 0, damageClass: .status),
                                         field: &field, attackerTeam: .a, defenderTeam: .b,
                                         rng: &seedRng)
            outcomes.insert(repeated.isGuarding)
        }
        XCTAssertEqual(outcomes, [true, false], "편 방어 뒤의 개인 방어가 늘 성공하면 카운터가 두 벌이다")
    }

    /// 다른 기술을 끼우면 연속이 끊긴다 — 개인 방어와 같은 규칙이라 편 방어기도 그 뒤 확정 성공이다.
    func testAnotherMoveInBetweenClearsTheTeamGuardStreak() {
        var user = side(), other = side()
        var field = BattleField()
        var rng = SplitMix64(seed: 9)
        _ = BattleEngine.applyAttack(attacker: &user, defender: &other, attackerActor: .a,
                                     defenderActor: .b, move: spec(33), field: &field,
                                     attackerTeam: .a, defenderTeam: .b, rng: &rng)
        XCTAssertEqual(user.guardStreak, 0)
        _ = BattleEngine.applyAttack(attacker: &user, defender: &other, attackerActor: .a,
                                     defenderActor: .b, move: guardSpec(.craftyShield),
                                     field: &field, attackerTeam: .a, defenderTeam: .b, rng: &rng)
        XCTAssertTrue(field.has(.craftyShield, for: .a), "끊긴 뒤의 첫 편 방어는 확정 성공이다")
    }

    /// 같은 턴에 두 번은 실패한다 — 이미 깔려 있으면 진영 상태를 다시 깔지 못한다는 규칙 그대로다.
    func testATeamGuardCannotBeStackedTwiceInTheSameTurn() {
        var user = side(), other = side()
        var field = BattleField()
        var rng = SplitMix64(seed: 6)
        let move = guardSpec(.wideGuard)
        _ = BattleEngine.applyAttack(attacker: &user, defender: &other, attackerActor: .a,
                                     defenderActor: .b, move: move, field: &field,
                                     attackerTeam: .a, defenderTeam: .b, rng: &rng)
        user.guardStreak = 0                         // 확률을 빼고 "이미 깔렸다" 갈래만 본다
        let again = BattleEngine.applyAttack(attacker: &user, defender: &other, attackerActor: .a,
                                             defenderActor: .b, move: move, field: &field,
                                             attackerTeam: .a, defenderTeam: .b, rng: &rng)
        XCTAssertTrue(again.contains(.immune(.b)))
        XCTAssertTrue(user.lastMoveFailed)
    }
}
