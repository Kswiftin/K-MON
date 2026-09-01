import XCTest
@testable import PokeTokenBar

/// 자기 회복기 — 회복·아침햇살·광합성·달빛·둥지틀기(최대 HP 절반)와 잠자기(전회복 + 상태 해제 + 수면).
///
/// 이전에는 `meta.healing` 을 안 읽어서 **위력 0 짜리 무동작**이었다. 턴만 태우고 아무 일도
/// 일어나지 않아, 자동 무브셋에 뽑히면 그대로 함정이었다(이슈 #24 코멘트).
final class SelfHealingTests: XCTestCase {

    private func side(_ hpFraction: Double = 1.0, status: Status? = nil) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 1, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: [.normal],
                                            base: BattleStats(hp: 100, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: 100)))
        out.hp = max(1, Int(Double(out.stats.hp) * hpFraction))
        if let status { out.status = status; out.statusCounter = 3 }
        return out
    }

    private func healingMove(_ id: Int, healing: Int) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "회복기"], type: .normal, power: 0,
                            damageClass: .status, accuracy: nil, pp: 5)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = true; move.drain = 0; move.healing = healing
        move.target = "user"        // 대상 슬러그도 수렴 판정이 보는 축이다
        return move
    }

    private var recover: MoveSpec { healingMove(105, healing: 50) }
    private var rest: MoveSpec { healingMove(MoveSpec.restMoveID, healing: 0) }

    @discardableResult
    private func use(_ move: MoveSpec, _ user: inout BattleSide, seed: UInt64 = 9) -> [BattleEvent] {
        var target = side()
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyAttack(attacker: &user, defender: &target, attackerActor: .a,
                                        defenderActor: .b, move: move, rng: &rng)
    }

    private func hasImmune(_ events: [BattleEvent]) -> Bool {
        events.contains { if case .immune = $0 { return true }; return false }
    }

    // MARK: 절반 회복

    func testRecoverRestoresHalfOfMaxHealth() {
        var user = side(0.4)
        let before = user.hp
        let events = use(recover, &user)
        XCTAssertEqual(user.hp - before, user.stats.hp / 2, "최대 HP 절반이다 — 남은 HP 기준이 아니다")
        XCTAssertTrue(events.contains { if case .heal = $0 { return true }; return false })
    }

    /// 넘치게 회복하지 않는다. `heal` 헬퍼가 이미 클램프하지만, 회복기가 그 헬퍼를 지나는지를 본다.
    func testRecoverNeverOverfills() {
        var user = side(0.9)
        use(recover, &user)
        XCTAssertEqual(user.hp, user.stats.hp)
    }

    /// **꽉 찼으면 실패한다.** 없으면 멀쩡한 상태에서 눌러 턴만 날리는 사고가 난다.
    /// 실패도 줄을 남겨야 한다 — 데미지 0 은 무반응과 구별되지 않는다.
    func testRecoverFailsAtFullHealthAndSaysSo() {
        var user = side()
        let events = use(recover, &user)
        XCTAssertEqual(user.hp, user.stats.hp)
        XCTAssertTrue(hasImmune(events), "조용히 지나가면 고장으로 읽힌다")
    }

    // MARK: 잠자기

    /// 잠자기는 `meta.healing` 이 0 이라 절반 회복 경로에 안 걸린다 — id 로 가른다.
    /// 전회복 + 상태 해제 + 수면 셋이 한 번에 일어나야 한다.
    func testRestFullyHealsCuresStatusAndSleeps() {
        var user = side(0.3, status: .poison)
        let events = use(rest, &user)
        XCTAssertEqual(user.hp, user.stats.hp, "전회복")
        XCTAssertEqual(user.status, .sleep, "해제 뒤에 수면이 걸린다 — 순서가 뒤집히면 수면이 지워진다")
        XCTAssertTrue(events.contains { if case .cureStatus(_, .poison) = $0 { return true }; return false })
    }

    /// 수면은 **2턴 고정**이다. 일반 수면(1~7턴)을 물려받으면 운에 따라 7턴을 날려 쓸 이유가 없어진다.
    func testRestSleepsForExactlyTwoTurns() {
        var user = side(0.3)
        use(rest, &user)
        XCTAssertEqual(user.statusCounter, MoveSpec.restSleepCounter)

        var attack = MoveSpec(id: -33, names: ["ko": "몸통박치기"], type: .normal, power: 40,
                              damageClass: .physical, accuracy: 100, pp: 35)
        attack.statChanges = []; attack.targetsUser = false; attack.drain = 0; attack.healing = 0
        var rng = SplitMix64(seed: 9)
        var blocked = 0
        for _ in 0..<4 {
            var target = side()
            let events = BattleEngine.applyAttack(attacker: &user, defender: &target,
                                                  attackerActor: .a, defenderActor: .b,
                                                  move: attack, rng: &rng)
            if events.contains(where: { if case .cant = $0 { return true }; return false }) { blocked += 1 }
        }
        XCTAssertEqual(blocked, 2, "두 턴만 쉰다")
    }

    /// **만피여도 상태가 있으면 성공한다.** 잠자기는 해독 수단이기도 하다 — 이 예외가 없으면
    /// 독에 걸린 만피 개체가 독을 풀 방법을 잃는다.
    func testRestStillWorksAtFullHealthWhenThereIsStatusToCure() {
        var user = side(1.0, status: .poison)
        use(rest, &user)
        XCTAssertEqual(user.status, .sleep)
    }

    /// 만피 + 상태 없음이면 실패한다 — 회복기와 같은 규칙이다.
    func testRestFailsWhenThereIsNothingToFix() {
        var user = side()
        let events = use(rest, &user)
        XCTAssertNil(user.status, "스스로 재우기만 하는 기술이 되면 안 된다")
        XCTAssertTrue(hasImmune(events))
    }

    // MARK: 경계

    /// 회복기는 상대를 보지 않는다 — 고스트 상대에게도, 특성이 있는 상대에게도 그대로 회복한다.
    /// `resolveAttack` 에 태우면 위력 0 이라 rng 만 태우고 아무것도 안 하는 기술이 된다.
    func testSelfHealingIgnoresTheOpponentEntirely() {
        var user = side(0.5)
        var ghost = BattleSide(BattleSnapshot(speciesID: 92, name: "고스트", trainer: nil, level: 50,
                                              nature: nil, isShiny: false, types: [.ghost],
                                              base: BattleStats(hp: 100, atk: 100, def: 100,
                                                                spa: 100, spd: 100, spe: 100)))
        var rng = SplitMix64(seed: 3)
        let before = user.hp
        _ = BattleEngine.applyAttack(attacker: &user, defender: &ghost, attackerActor: .a,
                                     defenderActor: .b, move: recover, rng: &rng)
        XCTAssertEqual(user.hp - before, user.stats.hp / 2)
        XCTAssertEqual(ghost.hp, ghost.stats.hp, "상대는 건드리지 않는다")
    }

    /// 보통 기술은 이 경로를 타면 안 된다 — 대조군이 없으면 "전부 회복기로 취급" 하는 오구현도 초록이다.
    func testOrdinaryMovesDoNotHeal() {
        var attack = MoveSpec(id: 33, names: ["ko": "몸통박치기"], type: .normal, power: 40,
                              damageClass: .physical, accuracy: 100, pp: 35)
        attack.statChanges = []; attack.targetsUser = false; attack.drain = 0; attack.healing = 0
        var user = side(0.5)
        let before = user.hp
        use(attack, &user)
        XCTAssertEqual(user.hp, before)
    }

    /// **세이브 보강 축.** `healing` 은 `drain` 보다 늦게 생긴 필드라, 그 사이에 받은 세이브는
    /// `drain` 만 차 있고 `healing` 은 비어 있다. 판정을 안 늘리면 회복기가 조용히 0 회복이 된다.
    ///
    /// `CompanionStore` 가 `@MainActor` 라 이 한 테스트만 메인 액터에서 돈다.
    @MainActor
    func testASaveWithDrainButNoHealingIsRefreshed() {
        var move = healingMove(105, healing: 50)
        move.descriptions = ["en": "Restores HP."]
        XCTAssertFalse(CompanionStore.needsDetailRefresh(move), "축이 다 찬 스펙을 또 받으면 안 된다")

        move.healing = nil
        XCTAssertTrue(CompanionStore.needsDetailRefresh(move),
                      "`drain` 이 `healing` 을 대표하지 못한다 — 늦게 생긴 축이다")
    }
}
