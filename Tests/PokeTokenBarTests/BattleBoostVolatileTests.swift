import XCTest
@testable import PokeTokenBar

/// 배율만 얹는 volatile 다섯 — 기합충전·레이저포커스(급소), 작아지기(맞는 쪽), 방어태세·충전(위력).
///
/// 앞 배치의 다섯(조이기·저주·나이트메어·아쿠아링·뿌리박기)과 갈리는 점은 **HP 를 만지지 않는다**는
/// 것이다. 그래서 검증도 잔뎀이 아니라 "같은 seed 로 데미지·급소·명중이 달라지는가" 로 한다.
/// 어느 기술이 무엇을 부르는지는 여기서도 손 목록이 아니라 쇼다운 데이터가 답한다.
final class BattleBoostVolatileTests: XCTestCase {

    private func side(_ types: [PokemonType] = [.water], hp: Int? = nil) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: types,
                                            base: BattleStats(hp: 100, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: 100),
                                            weightHectograms: 100))
        if let hp { out.hp = hp }
        return out
    }

    /// 변화기 스펙 — 위력 0·필중이라 명중 rng 를 타지 않는다.
    private func statusMove(_ id: Int, type: PokemonType,
                            statChanges: [StatChange] = []) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "기술"], type: type, power: 0,
                            damageClass: .status, accuracy: nil, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = statChanges; move.statChance = 0
        move.targetsUser = false
        return move
    }

    /// 공격기 스펙 — 2차효과·랭크가 없어서 데미지 말고는 아무 일도 하지 않는다.
    private func attackMove(_ id: Int, type: PokemonType, power: Int = 60,
                            accuracy: Int? = nil,
                            damageClass: MoveDamageClass = .physical) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "공격"], type: type, power: power,
                            damageClass: damageClass, accuracy: accuracy, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChance = 0
        move.targetsUser = false
        return move
    }

    @discardableResult
    private func use(_ move: MoveSpec, by attacker: inout BattleSide,
                     on defender: inout BattleSide, seed: UInt64 = 7,
                     field: BattleField = BattleField()) -> [BattleEvent] {
        var board = field
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                        attackerActor: .a, defenderActor: .b, move: move,
                                        field: &board, rng: &rng)
    }

    private func dealtDamage(_ events: [BattleEvent]) -> Int {
        events.reduce(0) {
            if case .damage(.b, let amount, .move) = $1 { return $0 + amount }
            return $0
        }
    }

    /// 같은 seed 로 한 번 때린 데미지. 배율을 재는 테스트는 전부 이 함수로 두 판을 비교한다.
    private func damage(of move: MoveSpec, attacker: BattleSide, defender: BattleSide,
                        seed: UInt64 = 7, field: BattleField = BattleField()) -> Int {
        var mine = attacker, theirs = defender
        return dealtDamage(use(move, by: &mine, on: &theirs, seed: seed, field: field))
    }

    private func critCount(of move: MoveSpec, attacker: BattleSide, defender: BattleSide,
                           seeds: Range<UInt64>, field: BattleField = BattleField()) -> Int {
        seeds.reduce(0) { count, seed in
            var mine = attacker, theirs = defender
            let events = use(move, by: &mine, on: &theirs, seed: seed, field: field)
            return count + (events.contains(.crit(.b)) ? 1 : 0)
        }
    }

    private func missCount(of move: MoveSpec, attacker: BattleSide, defender: BattleSide,
                           seeds: Range<UInt64>) -> Int {
        seeds.reduce(0) { count, seed in
            var mine = attacker, theirs = defender
            let events = use(move, by: &mine, on: &theirs, seed: seed)
            return count + (events.contains(.miss(.a)) ? 1 : 0)
        }
    }

    // MARK: 데이터가 어느 기술인지 답한다

    /// 다섯 키가 전부 엔진에 닿는다. 하나라도 못 닿으면 그 기술은 턴만 태운다.
    func testEveryBoostVolatileKeyInTheDataReachesTheEngine() {
        let expected: [String: BattleVolatile] = [
            "focusenergy": .focusEnergy, "laserfocus": .laserFocus, "minimize": .minimize,
            "defensecurl": .defenseCurl, "charge": .charge,
        ]
        for (key, volatileStatus) in expected {
            let callers = ShowdownMoveData.effects.filter { $0.value.volatileStatus == key }
            XCTAssertFalse(callers.isEmpty, "'\(key)' 를 부르는 기술이 데이터에 없다")
            for id in callers.keys {
                XCTAssertEqual(BattleVolatile.called(byMoveID: id), volatileStatus,
                               "기술 \(id) 의 '\(key)' 를 엔진이 모른다")
            }
        }
    }

    /// 작아진 상대에게 세게 들어가는 기술 목록은 **쇼다운의 `minimize` 플래그**에서 나온다.
    /// 손 목록이면 세대마다 붙는 기술(슈퍼셀블로)이 조용히 빠진다.
    func testTheMinimizeFlagListComesFromTheData() {
        XCTAssertTrue(ShowdownMoveData.hittingMinimizedHarder.contains(23), "발구르기가 빠졌다")
        XCTAssertTrue(ShowdownMoveData.hittingMinimizedHarder.contains(34), "누르기가 빠졌다")
        XCTAssertFalse(ShowdownMoveData.hittingMinimizedHarder.contains(33), "몸통박치기는 플래그가 없다")
        XCTAssertGreaterThanOrEqual(ShowdownMoveData.hittingMinimizedHarder.count, 9,
                                    "플래그 달린 기술이 줄었으면 추출을 먼저 본다")
    }

    /// 방어태세로 두 배가 되는 기술도 데이터가 답한다 — 구르기와 아이스볼 둘뿐이다.
    func testTheDefenseCurlDoubledListComesFromTheData() {
        XCTAssertEqual(ShowdownMoveData.doubledByDefenseCurl, [205, 301])
    }

    // MARK: 급소 — 기합충전·레이저포커스

    /// 기합충전은 급소 단계를 2 올린다(1/24 → 1/2). 같은 seed 묶음으로 두 판을 비교한다 —
    /// 확률이라 한 판만 보면 아무것도 못 잠근다.
    func testFocusEnergyLiftsTheCritRate() {
        let tackle = attackMove(33, type: .normal)
        var focused = side([.normal])
        XCTAssertTrue(focused.start(.focusEnergy), "기합충전이 안 붙었다")

        let plain = critCount(of: tackle, attacker: side([.normal]), defender: side(),
                              seeds: 0..<100)
        let boosted = critCount(of: tackle, attacker: focused, defender: side(), seeds: 0..<100)
        XCTAssertLessThan(plain, 15, "기본 급소율(1/24)이 이렇게 높을 수 없다")
        XCTAssertGreaterThan(boosted, 35, "기합충전이 급소 단계를 안 올렸다")
    }

    /// 레이저포커스는 **확정 급소**다 — 단계 3 이 표의 상한(100%)에 닿는다.
    func testLaserFocusMakesEveryHitCritical() {
        let tackle = attackMove(33, type: .normal)
        var focused = side([.normal])
        XCTAssertTrue(focused.start(.laserFocus, turns: BattleVolatile.laserFocus.selfDuration))
        XCTAssertEqual(critCount(of: tackle, attacker: focused, defender: side(), seeds: 0..<20),
                       20, "레이저포커스가 확정 급소가 아니다")
    }

    /// 행운의부적은 **확정 급소도** 막는다. 막는 자리가 급소 단계가 아니라 결과라서 성립한다 —
    /// 단계에서 막으면 rng 소비 횟수가 갈려 두 피어가 어긋난다.
    func testLuckyChantStillBlocksALaserFocusedCrit() {
        let tackle = attackMove(33, type: .normal)
        var focused = side([.normal])
        XCTAssertTrue(focused.start(.laserFocus, turns: BattleVolatile.laserFocus.selfDuration))
        var field = BattleField()
        XCTAssertTrue(field.start(.luckyChant, for: .b))
        XCTAssertEqual(critCount(of: tackle, attacker: focused, defender: side(),
                                 seeds: 0..<20, field: field), 0,
                       "행운의부적이 확정 급소를 못 막았다")
    }

    // MARK: 작아지기 — 맞는 쪽 배율

    /// 작아진 상대에게 플래그 달린 기술은 데미지가 두 배이고 **명중을 굴리지 않는다**.
    func testMinimizeDoublesAFlaggedMoveAndSkipsTheAccuracyRoll() {
        var small = side()
        XCTAssertTrue(small.start(.minimize))

        // 데미지 배율은 **필중 스펙으로** 잰다 — 명중 50 으로 재면 빗나간 판이 0 데미지를 주고,
        // 0 과 0 을 비교하는 테스트는 아무것도 잠그지 않는다.
        let stomp = attackMove(23, type: .normal)
        let plain = damage(of: stomp, attacker: side([.normal]), defender: side())
        let doubled = damage(of: stomp, attacker: side([.normal]), defender: small)
        XCTAssertGreaterThan(plain, 0, "때리지 못했으면 배율을 잴 수 없다")
        XCTAssertGreaterThan(doubled, plain * 19 / 10, "작아진 상대에게 두 배가 안 들어갔다")

        let shaky = attackMove(23, type: .normal, accuracy: 50)
        XCTAssertGreaterThan(missCount(of: shaky, attacker: side([.normal]), defender: side(),
                                       seeds: 0..<20), 0,
                             "명중 50 인데 스무 판을 다 맞았다 — 비교 기준이 성립하지 않는다")
        XCTAssertEqual(missCount(of: shaky, attacker: side([.normal]), defender: small,
                                 seeds: 0..<20), 0,
                       "작아진 상대에게 플래그 기술은 안 빗나간다")
    }

    /// 플래그가 없는 기술은 그대로다 — 배율이 기술을 안 가리면 작아지기가 순수한 손해가 된다.
    func testMinimizeLeavesAnUnflaggedMoveAlone() {
        var small = side()
        XCTAssertTrue(small.start(.minimize))

        let tackle = attackMove(33, type: .normal)
        let plain = damage(of: tackle, attacker: side([.normal]), defender: side())
        XCTAssertGreaterThan(plain, 0, "때리지 못했으면 배율을 잴 수 없다")
        XCTAssertEqual(damage(of: tackle, attacker: side([.normal]), defender: small), plain,
                       "플래그 없는 기술의 데미지가 달라졌다")
        XCTAssertGreaterThan(missCount(of: attackMove(33, type: .normal, accuracy: 50),
                                       attacker: side([.normal]), defender: small,
                                       seeds: 0..<20), 0,
                             "명중 50 인데 스무 판을 다 맞았다 — 명중 판정을 건너뛴 것이다")
    }

    // MARK: 위력 — 방어태세·충전

    /// 방어태세는 구르기·아이스볼의 위력을 두 배로 만든다. 구르기는 가변위력 경로,
    /// 아이스볼은 도감 위력 경로라 **두 경로를 같이 본다** — 한 자리에만 얹으면 하나가 빠진다.
    func testDefenseCurlDoublesRolloutAndIceBall() {
        for id in [205, 301] {
            let move = attackMove(id, type: .rock, power: 30)
            var curled = side([.rock])
            XCTAssertTrue(curled.start(.defenseCurl))
            let plain = damage(of: move, attacker: side([.rock]), defender: side())
            let doubled = damage(of: move, attacker: curled, defender: side())
            XCTAssertGreaterThan(plain, 0, "기술 \(id) 가 데미지를 안 넣었다")
            XCTAssertGreaterThan(doubled, plain * 19 / 10, "기술 \(id) 의 위력이 두 배가 안 됐다")
        }
    }

    func testDefenseCurlLeavesOtherMovesAlone() {
        let tackle = attackMove(33, type: .normal, power: 30)
        var curled = side([.normal])
        XCTAssertTrue(curled.start(.defenseCurl))
        XCTAssertEqual(damage(of: tackle, attacker: curled, defender: side()),
                       damage(of: tackle, attacker: side([.normal]), defender: side()),
                       "방어태세가 상관없는 기술을 세게 만들었다")
    }

    /// 충전은 **전기 기술만** 두 배로 만든다. 타입을 안 보면 충전 한 번이 모든 기술을 세게 한다.
    func testChargeDoublesOnlyElectricMoves() {
        var charged = side([.electric])
        XCTAssertTrue(charged.start(.charge, turns: BattleVolatile.charge.selfDuration))

        let bolt = attackMove(84, type: .electric, damageClass: .special)
        let plainBolt = damage(of: bolt, attacker: side([.electric]), defender: side())
        XCTAssertGreaterThan(damage(of: bolt, attacker: charged, defender: side()),
                             plainBolt * 19 / 10, "충전이 전기 기술을 두 배로 안 만들었다")

        let ember = attackMove(52, type: .fire, damageClass: .special)
        XCTAssertEqual(damage(of: ember, attacker: charged, defender: side()),
                       damage(of: ember, attacker: side([.electric]), defender: side()),
                       "충전이 전기가 아닌 기술까지 세게 만들었다")
    }

    // MARK: 사는 기간

    /// 충전과 레이저포커스는 **다음 턴까지만** 산다 — 건 턴 끝에 한 번, 다음 턴 끝에 풀린다.
    /// 안 풀리면 충전 한 번이 배틀 내내 전기 기술을 두 배로 만든다.
    func testChargeAndLaserFocusWearOffAfterTheNextTurn() {
        for volatileStatus in [BattleVolatile.charge, .laserFocus] {
            var mon = side()
            XCTAssertTrue(mon.start(volatileStatus, turns: volatileStatus.selfDuration))
            let first = BattleEngine.endOfTurnResidual(&mon, actor: .a)
            XCTAssertTrue(mon.has(volatileStatus), "\(volatileStatus) 가 건 턴 끝에 풀렸다")
            XCTAssertFalse(first.contains(.volatileEnded(.a, volatileStatus)))
            let second = BattleEngine.endOfTurnResidual(&mon, actor: .a)
            XCTAssertFalse(mon.has(volatileStatus), "\(volatileStatus) 가 안 풀렸다")
            XCTAssertTrue(second.contains(.volatileEnded(.a, volatileStatus)),
                          "풀린 줄이 로그에 없다")
        }
    }

    /// 나머지 셋은 턴을 세지 않는다 — 교체할 때까지 산다(교체가 비우는 것은 앞 배치가 잠갔다).
    func testTheIndefiniteBoostVolatilesSurviveEveryTurnEnd() {
        for volatileStatus in [BattleVolatile.focusEnergy, .minimize, .defenseCurl] {
            var mon = side(hp: 40)
            XCTAssertTrue(mon.start(volatileStatus, turns: volatileStatus.selfDuration))
            for _ in 0..<5 { _ = BattleEngine.endOfTurnResidual(&mon, actor: .a) }
            XCTAssertTrue(mon.has(volatileStatus), "\(volatileStatus) 가 턴 끝에 사라졌다")
        }
    }

    /// 배율만 얹는 다섯은 턴 끝에 **HP 를 만지지 않는다.** 회복·잔뎀 분모를 "자기에게 거는가" 로
    /// 물으면(아쿠아링·뿌리박기와 같은 축) 기합충전이 매 턴 1/16 을 회복하는 기술이 된다 —
    /// 실제로 한 번 그렇게 짰던 자리라 다섯을 전부 여기서 잠근다.
    func testNoBoostVolatileMovesHPAtTheEndOfATurn() {
        for volatileStatus in [BattleVolatile.focusEnergy, .laserFocus, .minimize,
                               .defenseCurl, .charge] {
            var mon = side(hp: 40)
            XCTAssertTrue(mon.start(volatileStatus, turns: volatileStatus.selfDuration))
            let events = BattleEngine.endOfTurnResidual(&mon, actor: .a)
            XCTAssertEqual(mon.hp, 40, "\(volatileStatus) 가 턴 끝에 HP 를 움직였다")
            XCTAssertFalse(events.contains { if case .heal = $0 { return true }
                                             if case .damage = $0 { return true }
                                             return false },
                           "\(volatileStatus) 가 회복·잔뎀 줄을 냈다")
        }
    }

    // MARK: 기술을 실제로 써서 붙인다

    /// 작아지기는 volatile 과 **회피 랭크를 같이** 올린다. volatile 로 옮기면서 조기반환이 생겨
    /// 랭크가 빠질 수 있는 자리다(그 갈래가 이 테스트의 이유다).
    func testUsingMinimizeStartsTheVolatileAndRaisesEvasion() {
        var attacker = side([.normal]), defender = side()
        let minimize = statusMove(107, type: .normal,
                                  statChanges: [StatChange(stat: .evasion, change: 2)])
        let events = use(minimize, by: &attacker, on: &defender)
        XCTAssertTrue(attacker.has(.minimize), "작아지기가 안 붙었다")
        XCTAssertEqual(attacker.stage(.evasion), 2, "회피 랭크가 안 올랐다")
        XCTAssertTrue(events.contains(.volatileStarted(.a, .minimize)))
        XCTAssertTrue(events.contains(.boost(.a, .evasion, 2)))

        // 두 번째 사용은 volatile 은 이미 붙었지만 랭크는 더 오른다(본가와 같다).
        let again = use(minimize, by: &attacker, on: &defender)
        XCTAssertEqual(attacker.stage(.evasion), 4, "두 번째 작아지기가 회피를 안 올렸다")
        XCTAssertFalse(again.contains(.immune(.b)), "랭크가 올랐는데 실패로 적혔다")
        XCTAssertFalse(attacker.lastMoveFailed, "랭크가 올랐는데 실패로 기록됐다")
    }

    /// 충전은 특방을 함께 올린다. 랭크가 ±6 에 닿아 더 못 오를 때만 실패로 적힌다.
    func testUsingChargeStartsTheVolatileAndRaisesSpecialDefence() {
        var attacker = side([.electric]), defender = side()
        let charge = statusMove(268, type: .electric,
                                statChanges: [StatChange(stat: .spd, change: 1)])
        let events = use(charge, by: &attacker, on: &defender)
        XCTAssertTrue(attacker.has(.charge), "충전이 안 붙었다")
        XCTAssertEqual(attacker.volatiles[.charge], 2, "충전이 턴을 안 세고 있다")
        XCTAssertEqual(attacker.stage(.spd), 1, "특방이 안 올랐다")
        XCTAssertTrue(events.contains(.volatileStarted(.a, .charge)))
    }

    /// 랭크가 없는 부류(기합충전·레이저포커스)를 두 번 쓰면 두 번째는 실패다 —
    /// 아무 일도 없었으면 로그에 그 사실이 남아야 한다(기술명 한 줄만 남으면 무반응이다).
    func testUsingFocusEnergyTwiceReportsTheSecondAsNothingHappening() {
        var attacker = side([.normal]), defender = side()
        let focus = statusMove(116, type: .normal)
        XCTAssertTrue(use(focus, by: &attacker, on: &defender).contains(.volatileStarted(.a, .focusEnergy)))
        XCTAssertEqual(use(focus, by: &attacker, on: &defender), [.move(.a, moveID: 116),
                                                                 .immune(.b)])
        XCTAssertTrue(attacker.lastMoveFailed, "두 번째 기합충전이 실패로 안 적혔다")
    }
}
