import XCTest
@testable import PokeTokenBar

/// 대타출동 — HP 대신 맞는 인형 한 층.
///
/// 다른 volatile 과 갈리는 점은 **층이 데미지·상태·랭크 경로 앞에 선다**는 것이다. 그래서 검증이
/// 한 자리에 모이지 않는다: 세우는 자리(대가와 실패 조건)·맞는 자리(인형이 먼저 깎인다)·
/// 지나가는 자리(소리 기술과 자기 기술은 층을 무시한다)·사라지는 자리(교체)를 각각 잠근다.
///
/// 어느 기술이 층을 세우는지는 손 목록이 아니라 쇼다운 데이터가 답하고, 어느 기술이 층을
/// 지나가는지도 데이터의 `bypasssub` 플래그가 답한다 — 소리 기술 목록을 손으로 들면 새 기술
/// 하나가 조용히 막힌다.
final class BattleSubstituteTests: XCTestCase {

    // MARK: 픽스처

    private func side(hp: Int? = nil, types: [PokemonType] = [.normal],
                      base: Int = 100) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: types,
                                            base: BattleStats(hp: base, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: 100),
                                            weightHectograms: 100))
        if let hp { out.hp = hp }
        return out
    }

    /// 대타출동 자체 — id 가 규칙이다(엔진이 데이터에 물어 이 기술을 알아본다).
    private func substituteMove() -> MoveSpec {
        var move = MoveSpec(id: 164, names: ["ko": "대타출동"], type: .normal, power: 0,
                            damageClass: .status, accuracy: nil, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = true
        return move
    }

    private func attackMove(_ id: Int = 33, power: Int = 60,
                            damageClass: MoveDamageClass = .physical,
                            type: PokemonType = .normal) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "공격"], type: type, power: power,
                            damageClass: damageClass, accuracy: 100, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = false
        return move
    }

    /// 상태기 — 마비를 확정으로 건다(층이 막는지 보는 데 rng 가 끼면 판정이 흐려진다).
    private func paralyzingMove() -> MoveSpec {
        var move = MoveSpec(id: 86, names: ["ko": "전기자석파"], type: .electric, power: 0,
                            damageClass: .status, accuracy: nil, pp: 20)
        move.ailment = "paralysis"; move.ailmentChance = 100
        move.statChanges = []; move.statChance = 0
        move.targetsUser = false
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

    @discardableResult
    private func hit(_ move: MoveSpec, by attacker: inout BattleSide, on defender: inout BattleSide,
                     seed: UInt64 = 7) -> [BattleEvent] {
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyHit(attacker: &attacker, defender: &defender,
                                     attackerActor: .a, defenderActor: .b, move: move, rng: &rng)
    }

    // MARK: 데이터가 어느 기술인지 답한다

    /// 대타출동과 쉐도우테일이 같은 키를 부른다 — 손 목록이면 둘째가 조용히 빠진다.
    func testTheDataNamesTheMovesThatRaiseASubstitute() {
        let raising = ShowdownMoveData.effects.filter { $0.value.volatileStatus == "substitute" }
        XCTAssertEqual(Set(raising.keys), [164, 880], "층을 세우는 기술이 바뀌었으면 추출을 먼저 본다")
        for id in raising.keys {
            XCTAssertEqual(BattleVolatile.called(byMoveID: id), .substitute,
                           "기술 \(id) 가 층을 세우는 것을 엔진이 모른다")
        }
    }

    /// 층을 **지나가는** 기술도 데이터가 답한다(쇼다운 `bypasssub` 플래그). 소리 기술이 전부 든다.
    func testTheDataNamesTheMovesThatPassThroughASubstitute() {
        XCTAssertTrue(ShowdownMoveData.bypassingSubstitute.contains(304), "하이퍼보이스는 소리 기술이다")
        XCTAssertFalse(ShowdownMoveData.bypassingSubstitute.contains(33), "몸통박치기는 층에 막힌다")
        XCTAssertGreaterThan(ShowdownMoveData.bypassingSubstitute.count, 50,
                             "플래그를 든 기술이 이만큼 적으면 추출이 플래그를 못 읽은 것이다")
    }

    // MARK: 세우는 자리

    /// 대가는 **최대 HP 의 1/4** 이고 인형도 같은 값으로 선다. 종족값이 아니라 파생 스탯 기준이다.
    func testRaisingASubstituteCostsAQuarterOfMaxHP() {
        var user = side(); var foe = side()
        let quarter = user.stats.hp / 4
        let events = use(substituteMove(), by: &user, on: &foe)
        XCTAssertEqual(user.hp, user.stats.hp - quarter)
        XCTAssertEqual(user.substituteHP, quarter)
        XCTAssertTrue(user.has(.substitute))
        XCTAssertTrue(events.contains(.volatileStarted(.a, .substitute)), "세운 줄이 로그에 없다")
    }

    /// HP 가 1/4 **이하**면 실패한다 — 대가를 치르면 그 자리에서 쓰러지기 때문이다(본가와 같다).
    func testRaisingFailsWhenHPIsNotAboveAQuarter() {
        var user = side(); var foe = side()
        user.hp = user.stats.hp / 4
        let events = use(substituteMove(), by: &user, on: &foe)
        XCTAssertEqual(user.hp, user.stats.hp / 4, "실패했는데 대가를 치렀다")
        XCTAssertEqual(user.substituteHP, 0)
        XCTAssertFalse(user.has(.substitute))
        XCTAssertTrue(events.contains(.immune(.b)), "실패를 말하는 줄이 없다")
        XCTAssertTrue(user.lastMoveFailed)
    }

    /// 이미 서 있으면 실패한다 — 안 막으면 매 턴 새 인형으로 무한 방벽이 된다.
    func testRaisingFailsWhileOneStillStands() {
        var user = side(); var foe = side()
        use(substituteMove(), by: &user, on: &foe)
        let hpAfterFirst = user.hp
        let events = use(substituteMove(), by: &user, on: &foe)
        XCTAssertEqual(user.hp, hpAfterFirst, "두 번째 대타출동이 대가를 또 치렀다")
        XCTAssertEqual(user.substituteHP, user.stats.hp / 4)
        XCTAssertTrue(events.contains(.immune(.b)))
    }

    // MARK: 맞는 자리

    /// 데미지는 인형이 먼저 받는다 — 주인의 HP 는 한 칸도 줄지 않는다.
    func testDamageLandsOnTheSubstituteInsteadOfTheOwner() {
        var user = side(); var foe = side()
        use(substituteMove(), by: &user, on: &foe)
        let hpBefore = user.hp
        let subBefore = user.substituteHP
        var attacker = side()
        let events = hit(attackMove(power: 20), by: &attacker, on: &user)
        XCTAssertEqual(user.hp, hpBefore, "인형이 서 있는데 주인이 깎였다")
        XCTAssertLessThan(user.substituteHP, subBefore, "인형이 깎이지 않았다")
        XCTAssertTrue(user.has(.substitute), "한 방에 부서질 데미지가 아니다")
        XCTAssertTrue(events.contains(.volatileTriggered(.b, .substitute)), "대신 맞은 줄이 없다")
        XCTAssertEqual(user.timesHit, 0, "주인은 맞지 않았다 — 원한의응보가 세면 안 된다")
        XCTAssertNil(user.lastHitThisTurn, "주인이 안 맞았으므로 되돌려줄 데미지도 없다")
    }

    /// 인형 HP 를 넘긴 데미지는 **넘긴 만큼이 주인에게 넘어가지 않는다**(본가와 같다).
    func testBreakingTheSubstituteDoesNotCarryTheExcessToTheOwner() {
        var user = side(); var foe = side()
        use(substituteMove(), by: &user, on: &foe)
        let hpBefore = user.hp
        var attacker = side()
        let events = hit(attackMove(power: 250), by: &attacker, on: &user)
        XCTAssertEqual(user.substituteHP, 0)
        XCTAssertFalse(user.has(.substitute))
        XCTAssertEqual(user.hp, hpBefore, "인형을 넘긴 데미지가 주인에게 넘어갔다")
        XCTAssertTrue(events.contains(.volatileEnded(.b, .substitute)), "부서진 줄이 없다")
    }

    /// 인형이 서 있으면 **쓰러지지 않는다** — HP 1 짜리 주인도 치명타를 그대로 흘린다.
    func testTheOwnerCannotFaintWhileTheSubstituteStands() {
        var user = side(); var foe = side()
        use(substituteMove(), by: &user, on: &foe)
        user.hp = 1
        var attacker = side()
        let events = hit(attackMove(power: 250), by: &attacker, on: &user)
        XCTAssertEqual(user.hp, 1)
        XCTAssertTrue(user.isAlive)
        XCTAssertFalse(events.contains(.faint(.b)), "인형이 막았는데 주인이 쓰러졌다")
    }

    /// 상태는 인형에 막힌다 — 인형은 마비되지 않고 주인도 걸리지 않는다.
    func testStatusMovesCannotReachTheOwnerBehindASubstitute() {
        var user = side(); var foe = side()
        use(substituteMove(), by: &user, on: &foe)
        var attacker = side()
        let events = hit(paralyzingMove(), by: &attacker, on: &user)
        XCTAssertNil(user.status, "층을 지나 마비가 걸렸다")
        XCTAssertTrue(events.contains(.immune(.b)), "아무 일도 없었다는 줄이 없다")
    }

    /// 상대 랭크 깎기는 막히지만 **쓴 쪽 자기 랭크 상승은 그대로다**(본가와 같다).
    func testASubstituteBlocksTheTargetsDropButNotTheUsersOwnBoost() {
        var user = side(); var foe = side()
        use(substituteMove(), by: &user, on: &foe)
        var attacker = side()
        var move = attackMove(power: 20)
        move.statChanges = [StatChange(stat: .def, change: -1)]
        move.statChance = 100
        hit(move, by: &attacker, on: &user)
        XCTAssertEqual(user.stage(.def), 0, "층을 지나 랭크가 깎였다")

        var booster = side()
        var boosting = attackMove(power: 20)
        boosting.statChanges = [StatChange(stat: .atk, change: 1)]
        boosting.statChance = 100
        hit(boosting, by: &booster, on: &user)
        XCTAssertEqual(booster.stage(.atk), 1, "자기 랭크 상승까지 층이 막았다")
    }

    /// 소리 기술은 층을 지난다 — 인형은 그대로고 주인이 깎인다.
    func testASoundMovePassesThroughTheSubstitute() {
        var user = side(); var foe = side()
        use(substituteMove(), by: &user, on: &foe)
        let hpBefore = user.hp
        let subBefore = user.substituteHP
        var attacker = side()
        hit(attackMove(304, power: 90, damageClass: .special), by: &attacker, on: &user)
        XCTAssertLessThan(user.hp, hpBefore, "소리 기술이 층에 막혔다")
        XCTAssertEqual(user.substituteHP, subBefore, "소리 기술이 인형을 깎았다")
    }

    /// 자기에게 거는 기술은 층과 상관없이 자기에게 닿는다 — 방어와 나 사이에 아무것도 없는 것과 같다.
    func testAMoveAimedAtTheUserIsNotDivertedByTheTargetsSubstitute() {
        var user = side(); var foe = side()
        use(substituteMove(), by: &user, on: &foe)
        var attacker = side()
        var selfMove = attackMove(power: 20)
        selfMove.targetsUser = true
        selfMove.statChanges = [StatChange(stat: .atk, change: 1)]
        selfMove.statChance = 100
        hit(selfMove, by: &attacker, on: &user)
        XCTAssertEqual(attacker.stage(.atk), 1, "자기 대상 기술이 상대의 층에 막혔다")
    }

    /// 반동·드레인은 **인형에 넣은 데미지** 기준이다(쇼다운과 같다).
    func testDrainAndRecoilCountTheDamageDealtToTheSubstitute() {
        var user = side(); var foe = side()
        use(substituteMove(), by: &user, on: &foe)
        var drainer = side(hp: 10)
        var draining = attackMove(power: 20)
        draining.drain = 50
        let drained = hit(draining, by: &drainer, on: &user)
        XCTAssertTrue(drained.contains { if case .heal(.a, _) = $0 { return true }; return false },
                      "인형을 때린 드레인이 회복하지 않았다")

        var recoiler = side()
        var recoiling = attackMove(power: 20)
        recoiling.drain = -33
        let recoiled = hit(recoiling, by: &recoiler, on: &user)
        XCTAssertTrue(recoiled.contains { if case .damage(.a, _, .recoil) = $0 { return true }; return false },
                      "인형을 때린 반동이 돌아오지 않았다")
    }

    // MARK: 사라지는 자리

    /// 교체하면 인형도 사라진다 — 남겨 두면 물러났다 다시 나온 개체가 인형을 그대로 쓴다.
    func testTheSubstituteIsGoneAfterSwitchingOut() {
        var user = side(); var foe = side()
        use(substituteMove(), by: &user, on: &foe)
        BattleEngine.prepareForSwitch(&user)
        XCTAssertEqual(user.substituteHP, 0, "교체했는데 인형 HP 가 남았다")
        XCTAssertFalse(user.has(.substitute))
    }

    // MARK: 로그

    /// 세운 줄·대신 맞은 줄·부서진 줄이 **셋 다 다르다** — 같으면 로그가 무슨 일이 났는지 못 말한다.
    func testTheThreeSubstituteLinesReadDifferentlyInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            let started = l.battleVolatileStarted("리자몽", .substitute)
            let triggered = l.battleVolatileTriggered("리자몽", .substitute)
            let ended = l.battleVolatileEnded("리자몽", .substitute)
            XCTAssertEqual(Set([started, triggered, ended]).count, 3, "\(lang) 에서 세 줄이 겹친다")
            for line in [started, triggered, ended] {
                XCTAssertTrue(line.contains("리자몽"), "\(lang) 문구에 이름이 없다")
            }
        }
    }
}
