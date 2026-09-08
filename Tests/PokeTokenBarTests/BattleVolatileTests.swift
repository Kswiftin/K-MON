import XCTest
@testable import PokeTokenBar

/// 개체에 붙어 턴을 넘어 사는 상태(조이기·저주·나이트메어·아쿠아링·뿌리박기).
///
/// 주 상태이상(`Status`)과 갈리는 점이 셋이다: 여러 개가 **동시에** 붙고, 잔뎀·회복이
/// `endOfTurnResidual` 한 자리에 얹히고, 교체하면 전부 사라진다. 어느 기술이 무엇을 붙이는지는
/// 손 목록이 아니라 쇼다운 데이터(`ShowdownMoveData.effects`)가 답한다 — 날씨·필드·진영 상태와
/// 같은 규칙이다.
final class BattleVolatileTests: XCTestCase {

    private func side(_ types: [PokemonType] = [.water], hp: Int? = nil,
                      status: Status? = nil) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: types,
                                            base: BattleStats(hp: 100, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: 100),
                                            weightHectograms: 100))
        if let hp { out.hp = hp }
        out.status = status
        return out
    }

    /// 변화기 스펙 — 위력 0·필중이라 명중 rng 를 타지 않는다(같은 seed 로 반복해도 같은 판이다).
    private func statusMove(_ id: Int, type: PokemonType,
                            statChanges: [StatChange] = []) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "기술"], type: type, power: 0,
                            damageClass: .status, accuracy: nil, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = statChanges; move.statChance = 0
        move.targetsUser = false
        return move
    }

    /// 상대에게 거는 기술 한 번 — `applyAttack` 을 지난다(자기 대상 갈래도 여기서 갈린다).
    @discardableResult
    private func use(_ move: MoveSpec, by attacker: inout BattleSide,
                     on defender: inout BattleSide, seed: UInt64 = 7) -> [BattleEvent] {
        var field = BattleField()
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                        attackerActor: .a, defenderActor: .b, move: move,
                                        field: &field, rng: &rng)
    }

    private func damageAmounts(_ events: [BattleEvent], cause: DamageCause) -> [Int] {
        events.compactMap {
            if case .damage(_, let amount, let found) = $0, found == cause { return amount }
            return nil
        }
    }

    // MARK: 데이터가 어느 기술인지 답한다

    /// 조이기는 열 기술이 같은 키를 부른다 — 하나라도 놓치면 그 기술만 잔뎀을 안 남긴다.
    func testEveryTrapMoveInTheDataReachesTheEngine() {
        let trapMoves = ShowdownMoveData.effects.filter { $0.value.volatileStatus == "partiallytrapped" }
        XCTAssertEqual(trapMoves.count, 10, "조이기 부류는 열 기술이다 — 데이터가 줄었으면 추출을 먼저 본다")
        for id in trapMoves.keys {
            XCTAssertEqual(BattleVolatile.called(byMoveID: id), .partiallyTrapped,
                           "기술 \(id) 의 조이기를 엔진이 모른다")
        }
    }

    /// 엔진이 아는 상태는 하나씩 실제 기술이 있다 — 부르는 기술이 없으면 아무도 못 쓰는 코드다.
    func testEveryVolatileTheEngineKnowsHasAMoveThatCallsIt() {
        for volatileStatus in BattleVolatile.allCases {
            XCTAssertTrue(ShowdownMoveData.effects.keys.contains {
                BattleVolatile.called(byMoveID: $0) == volatileStatus
            }, "\(volatileStatus) 를 부르는 기술이 데이터에 없다")
        }
    }

    // MARK: 조이기

    /// 조이기는 매 턴 최대 HP 의 1/8 을 깎고 4~5턴 뒤 풀린다. **풀리는 갈래를 같이 본다** —
    /// 안 풀면 한 번 걸린 조이기가 배틀 끝까지 남아 잔뎀 두 벌이 된다.
    func testATrapHurtsOneEighthEveryTurnAndThenWearsOff() {
        var attacker = side([.normal]), defender = side([.water], hp: 100)
        // 조이기(id 20 Bind) — 데미지가 있는 기술이라 2차효과 자리에서 붙는다.
        var bind = statusMove(20, type: .normal)
        bind.power = 15
        bind.damageClass = .physical
        use(bind, by: &attacker, on: &defender)
        XCTAssertTrue(defender.has(.partiallyTrapped), "조이기가 안 붙었다")

        var ticks = 0
        var ended = false
        defender.hp = 999                                  // 잔뎀으로 쓰러지지 않게 넉넉히 둔다
        for _ in 0..<8 {
            let events = BattleEngine.endOfTurnResidual(&defender, actor: .b)
            let hurt = damageAmounts(events, cause: .trap)
            if !hurt.isEmpty {
                XCTAssertEqual(hurt, [defender.stats.hp / 8], "조이기 잔뎀은 최대 HP 의 1/8 이다")
                ticks += 1
            }
            if events.contains(.volatileEnded(.b, .partiallyTrapped)) { ended = true; break }
        }
        XCTAssertTrue(ended, "조이기가 풀리지 않는다 — 영구 잔뎀이 된다")
        XCTAssertFalse(defender.has(.partiallyTrapped))
        XCTAssertTrue((4...5).contains(ticks), "조이기는 4~5턴 깎는다 (실제 \(ticks)턴)")
    }

    // MARK: 아쿠아링 · 뿌리박기

    /// 아쿠아링·뿌리박기는 **자기에게** 걸고 매 턴 1/16 을 회복한다. 상대에게 걸면 상대를 치료한다.
    func testSelfTargetedRingsHealTheUserAndNotTheTarget() {
        for (id, volatileStatus) in [(392, BattleVolatile.aquaRing), (275, BattleVolatile.ingrain)] {
            var attacker = side([.water], hp: 50), defender = side([.water], hp: 50)
            var move = statusMove(id, type: .water)
            move.targetsUser = true
            use(move, by: &attacker, on: &defender)
            XCTAssertTrue(attacker.has(volatileStatus), "\(volatileStatus) 가 쓴 쪽에 안 붙었다")
            XCTAssertFalse(defender.has(volatileStatus), "\(volatileStatus) 가 상대에게 붙었다")

            let events = BattleEngine.endOfTurnResidual(&attacker, actor: .a)
            XCTAssertEqual(events, [.heal(.a, amount: attacker.stats.hp / 16)],
                           "\(volatileStatus) 는 매 턴 최대 HP 의 1/16 을 회복한다")
            XCTAssertTrue(BattleEngine.endOfTurnResidual(&defender, actor: .b).isEmpty,
                          "안 걸린 쪽은 회복하지 않는다")
        }
    }

    /// 이미 걸려 있으면 다시 걸지 못한다 — 안 막으면 매 턴 다시 눌러 실패 없는 무한 회복이 된다.
    func testARingCannotBeStackedOnItself() {
        var attacker = side([.water], hp: 50), defender = side([.water])
        var move = statusMove(392, type: .water)
        move.targetsUser = true
        use(move, by: &attacker, on: &defender)
        let again = use(move, by: &attacker, on: &defender)
        XCTAssertTrue(again.contains(.immune(.b)), "두 번째 아쿠아링은 실패한다")
        XCTAssertTrue(attacker.lastMoveFailed, "실패를 기록하지 않으면 분함의발구르기가 두 배가 안 된다")
    }

    /// 만피면 회복 줄이 없다 — 0 회복 줄은 로그가 거짓말을 한다(이 파일의 다른 회복과 같은 규칙).
    func testARingHealsNothingAtFullHP() {
        var full = side([.water])
        XCTAssertTrue(full.start(.aquaRing))
        XCTAssertTrue(BattleEngine.endOfTurnResidual(&full, actor: .a).isEmpty,
                      "만피에서 아쿠아링이 0 회복 줄을 낸다")
    }

    // MARK: 저주

    /// 고스트가 쓰는 저주는 **자기 최대 HP 의 절반**을 내고 상대에게 매 턴 1/4 을 물린다.
    func testAGhostPaysHalfItsHPToCurseTheTarget() {
        var attacker = side([.ghost], hp: 100), defender = side([.water], hp: 100)
        let events = use(statusMove(174, type: .ghost), by: &attacker, on: &defender)
        XCTAssertTrue(defender.has(.curse), "저주가 안 걸렸다")
        XCTAssertEqual(damageAmounts(events, cause: .curse), [attacker.stats.hp / 2],
                       "저주는 쓴 쪽의 최대 HP 절반을 대가로 낸다")
        XCTAssertEqual(attacker.hp, 100 - attacker.stats.hp / 2)

        let residual = BattleEngine.endOfTurnResidual(&defender, actor: .b)
        XCTAssertEqual(damageAmounts(residual, cause: .curse), [defender.stats.hp / 4],
                       "저주 잔뎀은 최대 HP 의 1/4 이다")
    }

    /// **상대에게** 붙는 volatile 도 두 번 걸리지 않는다. 자기 대상(아쿠아링)만 막고 이쪽을 안
    /// 막으면 저주를 매 턴 다시 걸어 잔뎀이 겹치는 것으로 읽힌다.
    func testAVolatileCannotBeAppliedTwiceToTheSameTarget() {
        var attacker = side([.ghost], hp: 999), defender = side([.water], hp: 100)
        let curse = statusMove(174, type: .ghost)
        use(curse, by: &attacker, on: &defender)
        let again = use(curse, by: &attacker, on: &defender)
        XCTAssertTrue(again.contains(.immune(.b)), "두 번째 저주는 실패한다")
        XCTAssertTrue(attacker.lastMoveFailed)
        XCTAssertEqual(damageAmounts(again, cause: .curse), [], "실패한 저주는 대가도 받지 않는다")
    }

    /// 고스트가 아니면 저주는 **자기 랭크**를 움직인다(공격·방어 +1, 스피드 −1). 부호가 섞여
    /// `statChangePercent` 가 0 을 주므로, 이 갈래가 없으면 고스트 아닌 개체의 저주는 무반응이다.
    func testANonGhostCurseMovesItsOwnStatsInstead() {
        var attacker = side([.normal], hp: 100), defender = side([.water], hp: 100)
        let curse = statusMove(174, type: .ghost, statChanges: [
            StatChange(stat: .atk, change: 1), StatChange(stat: .def, change: 1),
            StatChange(stat: .spe, change: -1),
        ])
        use(curse, by: &attacker, on: &defender)
        XCTAssertFalse(defender.has(.curse), "고스트가 아니면 저주를 걸지 않는다")
        XCTAssertEqual(attacker.hp, 100, "랭크 갈래는 HP 를 내지 않는다")
        XCTAssertEqual(attacker.stage(.atk), 1)
        XCTAssertEqual(attacker.stage(.def), 1)
        XCTAssertEqual(attacker.stage(.spe), -1)
        XCTAssertEqual(defender.stage(.spe), 0, "스피드 감소는 자기 몫이다 — 상대에게 걸면 뒤집힌다")

        // 이미 +6 인 축은 움직이지 않는다 — 0 변화에 줄을 내면 로그가 거짓말을 한다.
        var capped = side([.normal], hp: 100)
        capped.stages[.atk] = 6
        let events = use(curse, by: &capped, on: &defender)
        XCTAssertFalse(events.contains(.boost(.a, .atk, 0)), "±6 에 닿은 축은 줄을 내지 않는다")
        XCTAssertEqual(capped.stage(.atk), 6)
    }

    // MARK: 씨뿌리기

    /// 씨뿌리기는 깎은 만큼 **뿌린 쪽이** 회복한다 — 두 개체를 동시에 만지는 유일한 턴 끝 효과다.
    func testLeechSeedMovesHPFromTheSeededToTheSeeder() {
        var seeder = side([.grass], hp: 50), seeded = side([.water], hp: 100)
        use(statusMove(73, type: .grass), by: &seeder, on: &seeded)
        XCTAssertTrue(seeded.has(.leechSeed), "씨가 안 박혔다")
        XCTAssertEqual(seeded.leechSeedSource, .a, "뿌린 자리를 안 적으면 아무도 회복하지 않는다")

        let sap = seeded.stats.hp / 8
        let events = BattleEngine.endOfTurnLeechSeed(seeded: &seeded, seededActor: .b,
                                                     seeder: &seeder, seederActor: .a)
        XCTAssertEqual(damageAmounts(events, cause: .leechSeed), [sap])
        XCTAssertEqual(seeded.hp, 100 - sap)
        XCTAssertEqual(seeder.hp, 50 + sap, "빨아낸 만큼 뿌린 쪽이 찬다")
        XCTAssertTrue(events.contains(.heal(.a, amount: sap)))
    }

    /// 풀 타입에는 씨가 박히지 않는다(본가와 같다). 상성표는 풀에게 0.5배를 주므로 이 규칙이
    /// 없으면 풀 타입이 씨뿌리기에 걸린다.
    func testLeechSeedDoesNotStickToGrassTypes() {
        var seeder = side([.grass]), grass = side([.grass], hp: 100)
        let events = use(statusMove(73, type: .grass), by: &seeder, on: &grass)
        XCTAssertFalse(grass.has(.leechSeed))
        XCTAssertTrue(events.contains(.immune(.b)))
        XCTAssertTrue(seeder.lastMoveFailed)
    }

    /// 뿌린 쪽이 쓰러져 있으면 깎기만 한다 — 회복을 그대로 넣으면 쓰러진 개체의 HP 가 되살아난다.
    func testLeechSeedSapsNothingIntoAFaintedSeeder() {
        var downed = side([.grass], hp: 0), seeded = side([.water], hp: 100)
        XCTAssertTrue(seeded.start(.leechSeed))
        let events = BattleEngine.endOfTurnLeechSeed(seeded: &seeded, seededActor: .b,
                                                     seeder: &downed, seederActor: .a)
        XCTAssertEqual(downed.hp, 0, "쓰러진 쪽은 회복하지 않는다")
        XCTAssertFalse(events.contains { if case .heal = $0 { return true } else { return false } })
        XCTAssertEqual(damageAmounts(events, cause: .leechSeed).count, 1, "깎기는 그대로 들어간다")
    }

    /// 씨뿌리기는 **개체 하나만 보는 잔뎀 자리에서 처리하지 않는다.** 양쪽에서 처리하면 한 턴에
    /// 두 번 빨린다 — 그 갈래를 여기서 잠근다.
    func testLeechSeedIsNotHandledByTheGenericResidual() {
        var seeded = side([.water], hp: 100)
        XCTAssertTrue(seeded.start(.leechSeed))
        XCTAssertTrue(BattleEngine.endOfTurnResidual(&seeded, actor: .b).isEmpty,
                      "잔뎀 자리가 씨까지 빨면 한 턴에 두 번 빨린다")
        XCTAssertEqual(seeded.hp, 100)
    }

    /// **트리거 브랜치**: 잔뎀을 도는 턴 루프가 씨뿌리기도 도는지 소스에서 센다. 한 모드만
    /// 빠뜨리면 그 모드에서 씨뿌리기가 아무 일도 하지 않고 화면에는 정상으로 보인다 — 짝이 필요해
    /// 함수가 갈린 효과라 컴파일러가 못 잡는다. 주석은 `SourceScan` 이 떼고 온다.
    func testEveryTurnLoopThatRunsResidualsAlsoRunsLeechSeed() throws {
        var loopsWithoutLeechSeed: [String] = []
        for (name, code) in try SourceScan.sources() {
            // 정의(`static func endOfTurnResidual`)가 아니라 **호출**만 센다.
            let callsResidual = code.contains("endOfTurnResidual(&")
            guard callsResidual else { continue }
            if !code.contains("endOfTurnLeechSeed(seeded:") && !code.contains("resolveLeechSeed()") {
                loopsWithoutLeechSeed.append(name)
            }
        }
        XCTAssertEqual(loopsWithoutLeechSeed, [],
                       "잔뎀은 도는데 씨뿌리기를 안 도는 턴 루프가 있다 — 그 모드에서만 씨가 죽는다")
    }

    // MARK: 나이트메어

    /// 나이트메어는 **잠든 상대에게만** 걸리고, 깨면 그 자리에서 풀린다.
    /// 깨는 갈래를 안 보면 잠에서 깬 뒤에도 1/4 이 계속 빠진다.
    func testNightmareNeedsASleepingTargetAndEndsWhenItWakes() {
        var attacker = side([.ghost]), awake = side([.water], hp: 100)
        let nightmare = statusMove(171, type: .ghost)
        let refused = use(nightmare, by: &attacker, on: &awake)
        XCTAssertFalse(awake.has(.nightmare), "깨어 있는 상대에게는 걸리지 않는다")
        XCTAssertTrue(refused.contains(.immune(.b)), "실패한 변화기는 그 사실을 로그에 남긴다")

        var asleep = side([.water], hp: 100, status: .sleep)
        use(nightmare, by: &attacker, on: &asleep)
        XCTAssertTrue(asleep.has(.nightmare))
        asleep.statusCounter = 9                            // 잔뎀만 보려고 깨는 판정을 미룬다
        let hurting = BattleEngine.endOfTurnResidual(&asleep, actor: .b)
        XCTAssertEqual(damageAmounts(hurting, cause: .nightmare), [asleep.stats.hp / 4])

        asleep.status = nil
        let waking = BattleEngine.endOfTurnResidual(&asleep, actor: .b)
        XCTAssertTrue(waking.contains(.volatileEnded(.b, .nightmare)), "깨면 나이트메어가 풀린다")
        XCTAssertTrue(damageAmounts(waking, cause: .nightmare).isEmpty, "깬 턴에는 깎지 않는다")
        XCTAssertFalse(asleep.has(.nightmare))
    }

    // MARK: 잔뎀 한 자리에 모인 규칙

    /// 회복은 잔뎀보다 **먼저**다(런 강화의 나머지회복과 같은 규칙). 뒤로 밀면 조이기로 쓰러진
    /// 개체가 그 턴에 되살아난다.
    func testResidualHealingComesBeforeResidualDamage() {
        var side = self.side([.water], hp: 40)
        XCTAssertTrue(side.start(.aquaRing))
        XCTAssertTrue(side.start(.partiallyTrapped, turns: 4))
        let events = BattleEngine.endOfTurnResidual(&side, actor: .a)
        let healIndex = events.firstIndex { if case .heal = $0 { return true } else { return false } }
        let hurtIndex = events.firstIndex { if case .damage = $0 { return true } else { return false } }
        XCTAssertNotNil(healIndex); XCTAssertNotNil(hurtIndex)
        XCTAssertLessThan(healIndex ?? 0, hurtIndex ?? 0, "회복이 잔뎀보다 앞이어야 한다")
    }

    /// 상태이상과 volatile 이 같은 턴에 겹쳐 쓰러져도 **기절 줄은 한 번**이다.
    /// 두 번 나가면 재생이 같은 개체를 두 번 쓰러뜨리고 로그도 두 줄이 된다.
    func testAMonKilledByTwoResidualsFaintsOnce() {
        var side = self.side([.water], hp: 3, status: .burn)
        XCTAssertTrue(side.start(.curse))
        let events = BattleEngine.endOfTurnResidual(&side, actor: .a)
        XCTAssertEqual(events.filter { $0 == .faint(.a) }.count, 1)
        XCTAssertFalse(side.isAlive)
    }

    /// 쓰러진 뒤에는 남은 volatile 이 더 깎지 않는다 — 죽은 개체의 HP 를 계속 만지면 재생과
    /// 엔진의 최종 HP 가 갈린다.
    func testResidualStopsAtZeroHP() {
        var side = self.side([.water], hp: 1)
        XCTAssertTrue(side.start(.curse))
        XCTAssertTrue(side.start(.partiallyTrapped, turns: 4))
        let events = BattleEngine.endOfTurnResidual(&side, actor: .a)
        XCTAssertEqual(side.hp, 0)
        XCTAssertEqual(events.filter { if case .damage = $0 { return true } else { return false } }.count, 1,
                       "첫 잔뎀에 쓰러지면 그 뒤 잔뎀은 없다")
        XCTAssertEqual(events.filter { $0 == .faint(.a) }.count, 1,
                       "volatile 잔뎀으로 쓰러져도 기절 줄은 맨 끝 한 번이다")
    }

    /// 교체하면 전부 사라진다 — 남겨 두면 조이기를 교체로 피했다가 그 상태로 다시 나온다.
    func testVolatilesClearWhenTheMonLeavesTheField() {
        var side = self.side([.water])
        XCTAssertTrue(side.start(.curse))
        XCTAssertTrue(side.start(.aquaRing))
        BattleEngine.prepareForSwitch(&side)
        XCTAssertTrue(side.volatiles.isEmpty, "물러나면 volatile 은 남지 않는다")
    }

    /// volatile 을 거는 기술은 **배울 수 있어야** 한다 — 상태이상도 랭크도 안 거는 변화기라
    /// `hasModeledStatusEffect` 가 열어 주지 않으면 아무도 못 배운다(날씨기와 같은 이유).
    func testMovesThatOnlySetAVolatileAreLearnable() {
        for id in [20, 174, 171, 392, 275] {
            XCTAssertTrue(statusMove(id, type: .ghost).hasModeledStatusEffect,
                          "기술 \(id) 는 volatile 을 거는데 배울 수 없다")
        }
    }
}
