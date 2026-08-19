import XCTest
@testable import PokeTokenBar

final class BattleTests: XCTestCase {

    // MARK: 타입 상성표

    func testTypeChartKnownMatchups() {
        XCTAssertEqual(TypeChart.effectiveness(.water, against: [.fire]), 2)
        XCTAssertEqual(TypeChart.effectiveness(.electric, against: [.ground]), 0)
        XCTAssertEqual(TypeChart.effectiveness(.normal, against: [.ghost]), 0)
        XCTAssertEqual(TypeChart.effectiveness(.fire, against: [.water]), 0.5)
        XCTAssertEqual(TypeChart.effectiveness(.dragon, against: [.fairy]), 0)
        // 복합타입은 곱 — 풀 → 물/땅(누오) = 2×2 = 4.
        XCTAssertEqual(TypeChart.effectiveness(.grass, against: [.water, .ground]), 4)
        // 무기재 칸은 1.0.
        XCTAssertEqual(TypeChart.effectiveness(.normal, against: [.fire]), 1)
    }

    // MARK: 성격 보정

    func testNatureModifiers() {
        XCTAssertEqual(NatureEffect.multiplier(.adamant, for: \.atk), 1.1)
        XCTAssertEqual(NatureEffect.multiplier(.adamant, for: \.spa), 0.9)
        XCTAssertEqual(NatureEffect.multiplier(.adamant, for: \.spe), 1.0)
        // 중립 5종은 무보정.
        XCTAssertEqual(NatureEffect.multiplier(.hardy, for: \.atk), 1.0)
        XCTAssertEqual(NatureEffect.multiplier(nil, for: \.atk), 1.0)
    }

    // MARK: 유효 스탯 (본가 공식, IV 31 / EV 0)

    func testEffectiveStatsFormula() {
        let snap = BattleSnapshot(speciesID: 25, name: "Pikachu", trainer: nil, level: 50,
                                  nature: nil, isShiny: false, types: [.electric],
                                  base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 100))
        let stats = snap.effectiveStats()
        // hp = (2*100+31)*50/100 + 50 + 10 = 115 + 60 = 175
        XCTAssertEqual(stats.hp, 175)
        // other = (2*100+31)*50/100 + 5 = 120
        XCTAssertEqual(stats.atk, 120)
        XCTAssertEqual(stats.spe, 120)
    }

    func testEffectiveStatsNatureApplied() {
        let snap = BattleSnapshot(speciesID: 25, name: "Pikachu", trainer: nil, level: 50,
                                  nature: .adamant, isShiny: false, types: [.electric],
                                  base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 100))
        let stats = snap.effectiveStats()
        XCTAssertEqual(stats.atk, 132)   // 120 × 1.1
        XCTAssertEqual(stats.spa, 108)   // 120 × 0.9
        XCTAssertEqual(stats.def, 120)
    }

    // MARK: 레벨 유도

    func testLevelDerivationBounds() {
        // 갓 부화(1형태 라인, 진행 0) → 최소 5.
        XCTAssertEqual(BattleSnapshot.level(stageIndex: 0, totalForms: 1, stageProgress: 0), 5)
        // 완주 → 100.
        XCTAssertEqual(BattleSnapshot.level(stageIndex: 2, totalForms: 3, stageProgress: 1), 100)
        // 진행도 클램프 — 음수/1 초과 입력에도 5~100 범위.
        XCTAssertEqual(BattleSnapshot.level(stageIndex: 0, totalForms: 3, stageProgress: -1), 5)
        XCTAssertEqual(BattleSnapshot.level(stageIndex: 5, totalForms: 3, stageProgress: 2), 100)
        // totalForms 0(손상 상태)에도 크래시 없이 범위 내.
        let l = BattleSnapshot.level(stageIndex: 0, totalForms: 0, stageProgress: 0.5)
        XCTAssertTrue((5...100).contains(l))
    }

    func testLevelMonotonicInProgress() {
        let early = BattleSnapshot.level(stageIndex: 0, totalForms: 3, stageProgress: 0.2)
        let mid = BattleSnapshot.level(stageIndex: 1, totalForms: 3, stageProgress: 0.2)
        let late = BattleSnapshot.level(stageIndex: 2, totalForms: 3, stageProgress: 0.9)
        XCTAssertLessThan(early, mid)
        XCTAssertLessThan(mid, late)
    }

    // MARK: 네트워크 대전 턴 해상

    private func water() -> BattleSnapshot {
        BattleSnapshot(speciesID: 9, name: "거북왕", trainer: nil, level: 50,
                       nature: nil, isShiny: false, types: [.water],
                       base: BattleStats(hp: 79, atk: 83, def: 100, spa: 85, spd: 105, spe: 78))
    }
    private func fire() -> BattleSnapshot {
        BattleSnapshot(speciesID: 6, name: "리자몽", trainer: nil, level: 50,
                       nature: nil, isShiny: false, types: [.fire, .flying],
                       base: BattleStats(hp: 78, atk: 84, def: 78, spa: 109, spd: 85, spe: 100))
    }

    private func hydroPump() -> MoveSpec {
        MoveSpec(id: 56, names: ["en": "Hydro Pump"], type: .water, power: 110,
                 damageClass: .special, accuracy: 80, pp: 5)
    }
    private func flamethrower() -> MoveSpec {
        MoveSpec(id: 53, names: ["en": "Flamethrower"], type: .fire, power: 90,
                 damageClass: .special, accuracy: 100, pp: 15)
    }

    /// 전광석화(우선도 +1). 위력은 낮게 둬서 "먼저 때렸다" 가 위력 때문이 아님을 분명히 한다.
    private func quickAttack() -> MoveSpec {
        MoveSpec(id: 98, names: ["en": "Quick Attack"], type: .normal, power: 40,
                 damageClass: .physical, accuracy: 100, pp: 30, priority: 1)
    }

    // MARK: 턴 순서 — 우선도 → 스피드 → 무작위

    /// 본가 규칙: 우선도가 스피드를 이긴다. 거북왕(스피드 78)이 전광석화를 쓰면 리자몽(100)보다 먼저다.
    /// 예전엔 우선도라는 개념 자체가 없어 스피드만 봤다 — 전광석화가 보통 기술과 똑같이 굴렀다.
    func testPriorityBeatsSpeed() {
        let (slow, fast) = (BattleSide(water()), BattleSide(fire()))
        XCTAssertLessThan(slow.stats.spe, fast.stats.spe, "스피드로는 거북왕이 후공인 상황이어야 한다")

        for seed in UInt64(0)..<20 {
            var rng = SplitMix64(seed: seed)
            var a = slow, b = fast
            let events = BattleEngine.resolveTurn(a: &a, b: &b,
                                                  moveA: quickAttack(), moveB: flamethrower(), rng: &rng)
            XCTAssertEqual(events.first?.attackerIsA, true, "seed \(seed): 우선도 +1 이 먼저 나가야 한다")
        }
    }

    /// 우선도가 같으면 예전 그대로 스피드 순이다 — 우선도 도입이 기존 순서를 흔들면 안 된다.
    func testSpeedStillDecidesWhenPriorityIsEqual() {
        let (slow, fast) = (BattleSide(water()), BattleSide(fire()))
        for seed in UInt64(0)..<20 {
            var rng = SplitMix64(seed: seed)
            var a = slow, b = fast
            let events = BattleEngine.resolveTurn(a: &a, b: &b,
                                                  moveA: hydroPump(), moveB: flamethrower(), rng: &rng)
            XCTAssertEqual(events.first?.attackerIsA, false, "seed \(seed): 빠른 쪽이 먼저다")
        }
    }

    /// 우선도·스피드가 모두 같으면 무작위 — 어느 한쪽이 늘 선공하면 그게 곧 보이지 않는 이점이다.
    /// (멀티는 이 자리에서 UUID 문자열 순으로 갈라, 앱을 켠 동안 한쪽이 계속 선공했다.)
    func testEqualPriorityAndSpeedBreaksRandomly() {
        let mirror = BattleSide(water())
        var firstMoverWasA = Set<Bool>()
        for seed in UInt64(0)..<40 {
            var rng = SplitMix64(seed: seed)
            var a = mirror, b = mirror
            let events = BattleEngine.resolveTurn(a: &a, b: &b,
                                                  moveA: hydroPump(), moveB: hydroPump(), rng: &rng)
            if let first = events.first?.attackerIsA { firstMoverWasA.insert(first) }
        }
        XCTAssertEqual(firstMoverWasA, [true, false], "양쪽 모두 선공을 잡는 seed 가 있어야 한다")
    }

    /// 우선도가 스냅샷에 없던 시절(구버전 세이브·구버전 피어)의 기술은 보통 기술로 읽는다.
    func testMissingPriorityReadsAsZero() {
        XCTAssertEqual(hydroPump().turnPriority, 0)
        XCTAssertNil(hydroPump().priority)
        XCTAssertEqual(quickAttack().turnPriority, 1)
    }

    func testResolveTurnDeterministic() {
        var rng1 = SplitMix64(seed: 99), rng2 = SplitMix64(seed: 99)
        var a1 = BattleSide(water()), b1 = BattleSide(fire())
        var a2 = BattleSide(water()), b2 = BattleSide(fire())
        let e1 = BattleEngine.resolveTurn(a: &a1, b: &b1,
                                          moveA: hydroPump(), moveB: flamethrower(), rng: &rng1)
        let e2 = BattleEngine.resolveTurn(a: &a2, b: &b2,
                                          moveA: hydroPump(), moveB: flamethrower(), rng: &rng2)
        XCTAssertEqual(e1, e2, "두 피어가 같은 seed 로 같은 결과를 얻어야 대전이 성립한다")
        XCTAssertEqual(a1.hp, a2.hp)
        XCTAssertEqual(b1.hp, b2.hp)
    }

    func testResolveTurnAccuracyRoll() {
        // 명중 80 기술 — 여러 seed 에서 빗나감과 명중이 모두 관측돼야 한다.
        var missSeen = false, hitSeen = false
        for seed in UInt64(0)..<40 {
            var rng = SplitMix64(seed: seed)
            var a = BattleSide(water()), b = BattleSide(fire())
            let events = BattleEngine.resolveTurn(a: &a, b: &b,
                                                  moveA: hydroPump(), moveB: flamethrower(), rng: &rng)
            for e in events where e.attackerIsA { e.missed ? (missSeen = true) : (hitSeen = true) }
        }
        XCTAssertTrue(missSeen && hitSeen)
    }

    func testResolveTurnImmunityDealsZero() {
        // 전기 → 땅 = 무효(0 데미지, effectiveness 0). 땅 쪽 스피드를 낮춰 전기가 먼저 치게 한다.
        let pika = BattleSnapshot(speciesID: 25, name: "피카츄", trainer: nil, level: 50, nature: nil,
                                  isShiny: false, types: [.electric],
                                  base: BattleStats(hp: 35, atk: 55, def: 40, spa: 50, spd: 50, spe: 90))
        let dugtrio = BattleSnapshot(speciesID: 51, name: "닥트리오", trainer: nil, level: 50, nature: nil,
                                     isShiny: false, types: [.ground],
                                     base: BattleStats(hp: 35, atk: 100, def: 50, spa: 50, spd: 70, spe: 10))
        let thunderbolt = MoveSpec(id: 85, names: ["en": "Thunderbolt"], type: .electric, power: 90,
                                   damageClass: .special, accuracy: nil, pp: 15)
        let dig = MoveSpec(id: 91, names: ["en": "Dig"], type: .ground, power: 80,
                           damageClass: .physical, accuracy: nil, pp: 10)
        var rng = SplitMix64(seed: 1)
        var a = BattleSide(pika), b = BattleSide(dugtrio)
        let events = BattleEngine.resolveTurn(a: &a, b: &b,
                                              moveA: thunderbolt, moveB: dig, rng: &rng)
        let pikaAttack = events.first { $0.attackerIsA }
        XCTAssertEqual(pikaAttack?.damage, 0)
        XCTAssertEqual(pikaAttack?.effectiveness, 0)
    }

    func testResolveTurnFaintSkipsSecondAction() {
        let strong = BattleSnapshot(speciesID: 143, name: "잠만보", trainer: nil, level: 50, nature: nil,
                                    isShiny: false, types: [.normal],
                                    base: BattleStats(hp: 160, atk: 110, def: 65, spa: 65, spd: 110, spe: 30))
        let frail = BattleSnapshot(speciesID: 92, name: "유령", trainer: nil, level: 5, nature: nil,
                                   isShiny: false, types: [.ghost],
                                   base: BattleStats(hp: 1, atk: 1, def: 1, spa: 1, spd: 1, spe: 1))
        var rng = SplitMix64(seed: 3)
        var a = BattleSide(strong), b = BattleSide(frail)
        // 발버둥(무속성)이라 고스트에도 박힌다 — 선공 기절 시 이벤트는 1개여야 한다.
        let events = BattleEngine.resolveTurn(a: &a, b: &b,
                                              moveA: .struggle(), moveB: .struggle(), rng: &rng)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(b.hp, 0)
    }

    func testFallbackMoveSet() {
        let set = MoveSpec.fallbackSet(types: [.fire, .flying])
        XCTAssertEqual(set.count, 4)
        XCTAssertTrue(set.allSatisfy { $0.power > 0 })
        XCTAssertTrue(set.contains { $0.type == .fire })
        XCTAssertTrue(set.contains { $0.type == .flying })
    }

    // MARK: 무브셋 선택 로직

    func testMoveCandidatesFiltersLevelUpAndSorts() throws {
        let json = """
        {"moves": [
          {"move": {"name": "tackle", "url": null},
           "version_group_details": [{"level_learned_at": 1, "move_learn_method": {"name": "level-up", "url": null}}]},
          {"move": {"name": "hyper-beam", "url": null},
           "version_group_details": [{"level_learned_at": 0, "move_learn_method": {"name": "machine", "url": null}}]},
          {"move": {"name": "flamethrower", "url": null},
           "version_group_details": [{"level_learned_at": 47, "move_learn_method": {"name": "level-up", "url": null}}]},
          {"move": {"name": "fire-blast", "url": null},
           "version_group_details": [{"level_learned_at": 83, "move_learn_method": {"name": "level-up", "url": null}}]},
          {"move": {"name": "ember", "url": null},
           "version_group_details": [{"level_learned_at": 7, "move_learn_method": {"name": "level-up", "url": null}}]},
          {"move": {"name": "scratch", "url": null},
           "version_group_details": [{"level_learned_at": 1, "move_learn_method": {"name": "level-up", "url": null}}]}
        ]}
        """
        let dto = try JSONDecoder().decode(PokemonMovesDTO.self, from: Data(json.utf8))
        let names = PokeAPIClient.moveCandidates(dto, level: 50)
        // 기계기(hyper-beam) 제외, 레벨 50 초과(fire-blast) 제외, 습득레벨 내림차순.
        XCTAssertFalse(names.contains("hyper-beam"))
        XCTAssertFalse(names.contains("fire-blast"))
        XCTAssertEqual(names.first, "flamethrower")
    }

    func testPickFourPrefersStabAndTypeDiversity() {
        func spec(_ id: Int, _ type: PokemonType, _ power: Int) -> MoveSpec {
            MoveSpec(id: id, names: [:], type: type, power: power, damageClass: .physical, accuracy: 100, pp: 10)
        }
        let picked = PokeAPIClient.pickFour(
            from: [spec(1, .fire, 90), spec(2, .fire, 120), spec(3, .normal, 100),
                   spec(4, .flying, 75), spec(5, .dragon, 80)],
            types: [.fire, .flying])
        XCTAssertEqual(picked.count, 4)
        // STAB 최고위력이 먼저, 같은 타입 중복은 1차 선발에서 뒤로.
        XCTAssertEqual(picked.first?.id, 2)
        XCTAssertTrue(picked.contains { $0.type == .flying })
        XCTAssertEqual(Set(picked.prefix(3).map(\.type)).count, 3, "1차 선발은 타입 중복 없음")
    }

    // MARK: 팀 연습 배틀 — 교체는 그 턴을 쓴다

    /// CPU 기술 선택은 이제 시드 rng 에서 뽑는다. 무브셋이 여러 개여도 seed 를 고정하면 같은
    /// 선택이 나오므로, 아래 교체 테스트는 데미지 값에 의존하지 않는다.
    private func practiceBattle(myTeam: [BattleSnapshot], opponent: BattleSnapshot) -> TeamPracticeBattle {
        TeamPracticeBattle(mine: myTeam.map(BattleSide.init),
                           opponents: [BattleSide(opponent)],
                           rng: SplitMix64(seed: 5))
    }

    /// 회귀: 교체가 활성 슬롯만 바꾸고 끝나서 공짜였다. 상성이 나쁘면 계속 갈아타며 유리한 상대만
    /// 때릴 수 있었고, 상대는 그동안 한 번도 움직이지 못했다. 이제 교체한 턴은 상대만 공격한다.
    func testSwitchingCostsTheTurnAndLetsTheOpponentAttack() {
        var battle = practiceBattle(myTeam: [water(), fire()], opponent: fire())
        let before = battle.mine[1].hp

        XCTAssertTrue(battle.switchMine(to: 1))

        XCTAssertEqual(battle.myActive, 1, "교체는 이뤄진다")
        XCTAssertEqual(battle.events.count, 1, "그 턴에 오간 공격은 상대 것 하나뿐이다")
        XCTAssertEqual(battle.events.first?.attackerIsA, false, "내 공격은 없다")
        XCTAssertLessThan(battle.mine[1].hp, before, "새로 나온 포켓몬이 그 공격을 맞는다")
        XCTAssertEqual(battle.turn, 2, "턴이 넘어간다")
    }

    /// 교체 자체는 내 PP 를 쓰지 않는다 — 쓴 건 턴이지 기술이 아니다.
    func testSwitchingDoesNotSpendMyPP() {
        var battle = practiceBattle(myTeam: [water(), fire()], opponent: fire())
        let ppBefore = battle.mine[1].pp

        XCTAssertTrue(battle.switchMine(to: 1))

        XCTAssertEqual(battle.mine[1].pp, ppBefore)
    }

    /// 교체하며 내보낸 포켓몬이 그 공격에 쓰러지면 다음 포켓몬으로 넘어간다 —
    /// 남은 게 없으면 그 자리에서 패배가 확정된다(호출부가 이 값으로 화면을 닫는다).
    func testSwitchingIntoAFatalHitEndsTheBattle() {
        var frail = fire()
        frail.base = BattleStats(hp: 1, atk: 1, def: 1, spa: 1, spd: 1, spe: 1)
        var battle = practiceBattle(myTeam: [water(), frail], opponent: fire())

        XCTAssertTrue(battle.switchMine(to: 1))

        XCTAssertFalse(battle.mine[1].isAlive, "맞고 쓰러진다")
        XCTAssertEqual(battle.myActive, 0, "살아 있는 포켓몬으로 넘어간다")
        XCTAssertNil(battle.result, "아직 한 마리 남았으므로 배틀은 계속된다")
    }

    /// 6턴을 버티는 내 포켓몬 — 어느 쪽도 그 안에 쓰러지지 않아야 CPU 선택 분기를 6번 밟는다.
    private func tank() -> BattleSnapshot {
        BattleSnapshot(speciesID: 143, name: "탱커", trainer: nil, level: 50, nature: nil, isShiny: false,
                       types: [.normal],
                       base: BattleStats(hp: 200, atk: 5, def: 200, spa: 5, spd: 200, spe: 50),
                       moves: [MoveSpec(id: 1, names: [:], type: .normal, power: 10,
                                        damageClass: .physical, accuracy: 100, pp: 30)])
    }

    /// CPU 무브셋 4개 — id 가 다르므로 이벤트에 "무엇을 골랐는지" 가 그대로 드러난다.
    private func cpuWithFourMoves() -> BattleSnapshot {
        BattleSnapshot(speciesID: 25, name: "CPU", trainer: "CPU", level: 50, nature: nil, isShiny: false,
                       types: [.normal],
                       base: BattleStats(hp: 200, atk: 5, def: 200, spa: 5, spd: 200, spe: 40),
                       moves: (0..<4).map { i in
                           MoveSpec(id: 100 + i, names: [:], type: .normal, power: 40 + i * 20,
                                    damageClass: .physical, accuracy: 100, pp: 20)
                       })
    }

    /// `BattleSide` 의 두 접근자는 신뢰 경계다 — 인덱스는 상대가 보내온 값이고, `pp` 는 와이어로
    /// 들어와 `moves` 와 길이가 어긋날 수 있다. 거절 조건을 **하나씩** 밟는다(한 조건만 보면 나머지
    /// 조건이 죽어 있어도 초록으로 통과한다).
    func testBattleSideRejectsOutOfRangeAndSpentMoves() {
        var side = BattleSide(tank())            // 기술 1개, PP 30
        XCTAssertEqual(side.moves.count, 1)
        XCTAssertTrue(side.canUse(moveAt: 0))
        XCTAssertFalse(side.canUse(moveAt: 1), "무브셋 범위 밖")
        XCTAssertFalse(side.canUse(moveAt: -1), "발버둥 표식(−1)은 기술 인덱스가 아니다")
        side.pp = []                             // 와이어에서 길이가 어긋난 pp
        XCTAssertFalse(side.canUse(moveAt: 0), "pp 가 짧으면 인덱싱 전에 막힌다")
        side.pp = [0]
        XCTAssertFalse(side.canUse(moveAt: 0), "PP 0")
        XCTAssertTrue(side.mustStruggle)
        // 범위 밖·음수 인덱스는 발버둥으로 읽는다.
        XCTAssertEqual(side.move(at: -1).id, MoveSpec.struggleID)
        XCTAssertEqual(side.move(at: 9).id, MoveSpec.struggleID)
        XCTAssertEqual(side.move(at: 0).id, 1)
    }

    /// PP 가 전부 떨어지면 발버둥으로 계속 싸운다. 연습 배틀이 그 자리에서 멈추면 안 된다.
    /// (`move(at:)` 의 발버둥 폴백을 실제로 밟는 경로다.)
    func testPracticeBattleStrugglesWhenPPRunsOut() {
        var battle = TeamPracticeBattle(mine: [BattleSide(tank())],
                                        opponents: [BattleSide(cpuWithFourMoves())],
                                        rng: SplitMix64(seed: 11))
        battle.mine[0].pp = [0]
        battle.opponents[0].pp = [0, 0, 0, 0]

        XCTAssertTrue(battle.useMove(0))

        XCTAssertEqual(battle.events.map(\.moveID), [MoveSpec.struggleID, MoveSpec.struggleID],
                       "양쪽 모두 발버둥을 쓴다")
        XCTAssertEqual(battle.mine[0].pp, [0], "발버둥은 PP 를 쓰지 않는다")
    }

    /// 회귀: CPU 기술 선택이 `randomElement()`(시스템 RNG)라 같은 seed 로도 연습 배틀이 재현되지
    /// 않았다. 그게 왜 발목을 잡는지는 `TeamPracticeBattle.cpuMoveChoice` 주석에 적어 뒀다.
    ///
    /// 한 판이 우연히 같아질 확률은 (1/4)^6 이므로 같은 seed 로 10판을 돌려 전부 같은지 본다.
    func testPracticeBattleIsDeterministicForASeed() {
        func run() -> [Int] {
            var battle = TeamPracticeBattle(mine: [BattleSide(tank())],
                                            opponents: [BattleSide(cpuWithFourMoves())],
                                            rng: SplitMix64(seed: 2_024))
            for turn in 0..<6 { XCTAssertTrue(battle.useMove(0), "\(turn + 1)번째 턴이 진행돼야 한다") }
            return battle.events.map { $0.moveID }
        }
        let runs = Set((0..<10).map { _ in run() })
        XCTAssertEqual(runs.count, 1, "같은 seed 는 같은 배틀이어야 하는데 \(runs.count) 가지가 나왔다")
    }

    /// 같은 자리로는 교체할 수 없다 — 턴만 버리는 조작이 된다.
    func testSwitchingToTheActiveSlotIsRejected() {
        var battle = practiceBattle(myTeam: [water(), fire()], opponent: fire())

        XCTAssertFalse(battle.switchMine(to: 0))

        XCTAssertTrue(battle.events.isEmpty, "거절된 교체는 상대에게 공격 기회를 주지 않는다")
        XCTAssertEqual(battle.turn, 1)
    }
}

