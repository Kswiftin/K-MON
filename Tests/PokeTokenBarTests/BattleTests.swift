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

    /// 필중 물 기술 — 명중 판정을 건너뛰므로 rng 소비가 **급소 → 난수** 두 번뿐이다.
    /// 그래서 아래 골든값을 손으로 계산할 수 있다.
    private func surf() -> MoveSpec {
        MoveSpec(id: 57, names: ["en": "Surf"], type: .water, power: 90,
                 damageClass: .special, accuracy: nil, pp: 15)
    }

    // MARK: 데미지 파이프라인 — Gen 2 순서

    /// Gen 2 데미지 식의 **순서**를 골든값으로 잠근다. 거북왕(특공 105)의 파도타기(위력 90)가
    /// 리자몽(특방 105, 불꽃/비행)을 때린다. 양쪽 레벨 50.
    ///
    ///     base   = (2·50/5 + 2)·90·105/105/50 = 39
    ///     비급소 = (39 + 2)·3/2·2 = 122      급소 = (39 + 2)·3/2·3/2·2 = 182
    ///     최종   = 위 값 · rand / 255          rand ∈ 217…255 (균등 정수)
    ///
    /// 현행 급소 배율 ×1.5와 정수 난수 파이프라인을 고정한다.
    func testCurrentDamageOrderAndCritMultiplier() {
        let attacker = BattleSide(water()), defender = BattleSide(fire())
        // (seed, 급소인가, 기대 데미지). seed 33은 현행 기본 확률 1/24에서 급소다.
        // seed 0 은 rand 하한 217, seed 20 은 상한 255 를 밟는다.
        let golden: [(seed: UInt64, crit: Bool, damage: Int)] = [(0, false, 103), (33, true, 160), (20, false, 122)]
        for (seed, expectedCrit, expectedDamage) in golden {
            var rng = SplitMix64(seed: seed)
            let outcome = BattleEngine.resolveAttack(attacker: attacker, defender: defender,
                                                     move: surf(), rng: &rng)
            XCTAssertEqual(outcome.isCritical, expectedCrit, "seed \(seed): 급소 판정")
            XCTAssertEqual(outcome.damage, expectedDamage, "seed \(seed): 현행 식의 값이어야 한다")
            XCTAssertEqual(outcome.effectiveness, 2, "seed \(seed): 표시용 상성 배율은 그대로 2 다")
        }
    }

    /// 데미지 값이 바뀌면 두 피어의 HP 가 갈린다 — 규칙 버전을 올리지 않으면 구버전 앱과 붙어
    /// **같은 배틀을 서로 다르게 본다**(challenge/accept 가 거절하지 못한다). 위 골든값과 이 상수는
    /// 같이 움직여야 한다.
    func testRulesVersionMovesWithTheDamagePipeline() {
        XCTAssertGreaterThanOrEqual(BattleEngine.rulesVersion, 2, "Gen 2 데미지 파이프라인부터 규칙 2 이상")
    }

    // MARK: 급소 단계

    /// 현행 급소 단계표(분모 24). 고급소기는 이 표에서 **+1 단계**다.
    func testCriticalHitThresholdsFollowTheCurrentStageTable() {
        XCTAssertEqual(BattleEngine.critThreshold(stage: 0), 1)    // 1/24 ≈ 4.17%
        XCTAssertEqual(BattleEngine.critThreshold(stage: 1), 3)    // 1/8
        XCTAssertEqual(BattleEngine.critThreshold(stage: 2), 12)   // 1/2
        XCTAssertEqual(BattleEngine.critThreshold(stage: 3), 24)   // 100%
        XCTAssertEqual(BattleEngine.critThreshold(stage: 9), 24)
        XCTAssertEqual(BattleEngine.critThreshold(stage: -1), 1)
    }

    /// 단계표가 `resolveAttack` 까지 **실제로 연결됐는지** 본다. 표만 맞고 배선이 없어도 위 테스트는
    /// 초록으로 통과하니, 판정을 실제로 밟는 경로를 따로 확인한다.
    func testHighCritMoveCritsFarMoreOftenThanANormalMove() {
        let attacker = BattleSide(water()), defender = BattleSide(fire())
        func critCount(_ move: MoveSpec) -> Int {
            (UInt64(0)..<512).reduce(0) { count, seed in
                var rng = SplitMix64(seed: seed)
                let outcome = BattleEngine.resolveAttack(attacker: attacker, defender: defender,
                                                         move: move, rng: &rng)
                return count + (outcome.isCritical ? 1 : 0)
            }
        }
        var highCrit = surf()
        highCrit.critRate = 1                       // PokéAPI `meta.crit_rate` — 베어가르기 부류
        let plain = critCount(surf()), boosted = critCount(highCrit)

        // 512회 중 기대값은 약 21(1/24) 과 64(1/8)다. seed 를 고정한 순회라 값이 실행마다 같다.
        XCTAssertGreaterThan(plain, 0, "기본 확률도 관측돼야 한다 — 0 이면 판정 자체가 죽었다")
        XCTAssertGreaterThan(boosted, plain * 2, "고급소기가 두 배도 안 되면 단계가 연결되지 않았다")
        XCTAssertEqual(Double(boosted) / 512, 0.125, accuracy: 0.04,
                       "고급소기의 +1 단계는 1/8 이어야 한다")
    }

    /// PokéAPI `/move` 응답 → `MoveSpec` 매핑. `meta.crit_rate` 는 이 경로로만 들어오므로
    /// 필드가 스펙까지 실려오는지를 JSON 모양 그대로 확인한다.
    private func slashJSON(includeMeta: Bool) -> Data {
        let meta = includeMeta ? #", "meta": {"crit_rate": 1}"# : ""
        return Data("""
        {"id": 163, "power": 70, "accuracy": 100, "pp": 20, "priority": 0,
         "type": {"name": "normal", "url": null},
         "damage_class": {"name": "physical", "url": null},
         "names": [{"name": "Slash", "language": {"name": "en", "url": null}},
                   {"name": "베어가르기", "language": {"name": "ko", "url": null}}],
         "flavor_text_entries": [{"flavor_text": "Cuts with claws.",
                                  "language": {"name": "en", "url": null}}]\(meta)}
        """.utf8)
    }

    func testMoveSpecFromPokeAPIJSONCarriesCritRate() throws {
        let dto = try JSONDecoder().decode(MoveDTO.self, from: slashJSON(includeMeta: true))
        let spec = try XCTUnwrap(MoveSpec.from(dto, fallbackName: "slash", languages: ["ko", "en"]))

        XCTAssertEqual(spec.critRate, 1)
        XCTAssertEqual(spec.critStage, 1, "현행 고급소기는 +1 단계다")
        XCTAssertEqual(spec.id, 163)
        XCTAssertEqual(spec.power, 70)
        XCTAssertEqual(spec.pp, 20)
        XCTAssertEqual(spec.accuracy, 100)
        XCTAssertEqual(spec.type, .normal)
        XCTAssertEqual(spec.damageClass, .physical)
        XCTAssertEqual(spec.turnPriority, 0)
        XCTAssertEqual(spec.name(.ko), "베어가르기")
        XCTAssertEqual(spec.name(.en), "Slash")
    }

    /// `meta` 가 없는 응답(옛 캐시)은 보통 급소율로 읽는다 — `nil` 이 곧 0단계다.
    func testMoveSpecWithoutMetaReadsAsTheBaseCritRate() throws {
        let dto = try JSONDecoder().decode(MoveDTO.self, from: slashJSON(includeMeta: false))
        let spec = try XCTUnwrap(MoveSpec.from(dto, fallbackName: "slash", languages: ["ko", "en"]))

        XCTAssertNil(spec.critRate)
        XCTAssertEqual(spec.critStage, 0)
    }

    /// 앱이 모르는 타입·분류가 오면 스펙을 만들지 않는다(호출부가 그 기술을 건너뛴다).
    /// 이름이 하나도 없으면 영어 자리에 요청 이름을 넣어 화면에 "?" 가 남지 않게 한다.
    func testMoveSpecRejectsUnknownTypeAndFallsBackToTheRequestedName() throws {
        let unknownType = Data("""
        {"id": 1, "power": 40, "accuracy": 100, "pp": 35, "priority": 0,
         "type": {"name": "cosmic", "url": null},
         "damage_class": {"name": "physical", "url": null},
         "names": [], "flavor_text_entries": []}
        """.utf8)
        let dto = try JSONDecoder().decode(MoveDTO.self, from: unknownType)
        XCTAssertNil(MoveSpec.from(dto, fallbackName: "cosmic-blast", languages: ["ko", "en"]))

        let noNames = Data("""
        {"id": 33, "power": 40, "accuracy": 100, "pp": 35, "priority": 0,
         "type": {"name": "normal", "url": null},
         "damage_class": {"name": "physical", "url": null},
         "names": [], "flavor_text_entries": []}
        """.utf8)
        let plain = try XCTUnwrap(MoveSpec.from(try JSONDecoder().decode(MoveDTO.self, from: noNames),
                                               fallbackName: "tackle", languages: ["ko", "en"]))
        XCTAssertEqual(plain.name(.en), "tackle")
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
            let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: quickAttack(),
                                                  moveB: flamethrower(), turn: 1, rng: &rng)
            XCTAssertEqual(events.moveActors.first, .a, "seed \(seed): 우선도 +1 이 먼저 나가야 한다")
        }
    }

    /// 우선도가 같으면 예전 그대로 스피드 순이다 — 우선도 도입이 기존 순서를 흔들면 안 된다.
    func testSpeedStillDecidesWhenPriorityIsEqual() {
        let (slow, fast) = (BattleSide(water()), BattleSide(fire()))
        for seed in UInt64(0)..<20 {
            var rng = SplitMix64(seed: seed)
            var a = slow, b = fast
            let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: hydroPump(),
                                                  moveB: flamethrower(), turn: 1, rng: &rng)
            XCTAssertEqual(events.moveActors.first, .b, "seed \(seed): 빠른 쪽이 먼저다")
        }
    }

    /// 우선도·스피드가 모두 같으면 무작위 — 어느 한쪽이 늘 선공하면 그게 곧 보이지 않는 이점이다.
    /// (멀티는 이 자리에서 UUID 문자열 순으로 갈라, 앱을 켠 동안 한쪽이 계속 선공했다.)
    func testEqualPriorityAndSpeedBreaksRandomly() {
        let mirror = BattleSide(water())
        var firstMovers = Set<BattleActor>()
        for seed in UInt64(0)..<40 {
            var rng = SplitMix64(seed: seed)
            var a = mirror, b = mirror
            let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: hydroPump(),
                                                  moveB: hydroPump(), turn: 1, rng: &rng)
            if let first = events.moveActors.first { firstMovers.insert(first) }
        }
        XCTAssertEqual(firstMovers, [.a, .b], "양쪽 모두 선공을 잡는 seed 가 있어야 한다")
    }

    /// 우선도가 스냅샷에 없던 시절(구버전 세이브·구버전 피어)의 기술은 보통 기술로 읽는다.
    func testMissingPriorityReadsAsZero() {
        XCTAssertEqual(hydroPump().turnPriority, 0)
        XCTAssertNil(hydroPump().priority)
        XCTAssertEqual(quickAttack().turnPriority, 1)
    }

    // MARK: 이벤트 스트림 (Showdown 어휘)

    /// 스트림의 첫 줄은 턴 번호다 — 로그가 턴 구분선을 끼울 수 있어야 한다.
    func testResolveTurnEmitsTheTurnNumberFirst() {
        var rng = SplitMix64(seed: 1)
        var a = BattleSide(water()), b = BattleSide(fire())
        let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: surf(), moveB: flamethrower(),
                                              turn: 7, rng: &rng)
        XCTAssertEqual(events.first, .turn(7))
    }

    /// 쓰러졌다는 사실을 스트림이 **말한다**. 예전엔 이벤트에 그런 case 가 없어서 뷰가 HP 0 을
    /// 보고 추론했다 — 기절 연출(Phase 7)도 그 추론 위에 얹을 수밖에 없었다.
    func testResolveTurnAnnouncesTheFaint() {
        let strong = BattleSnapshot(speciesID: 143, name: "잠만보", trainer: nil, level: 50, nature: nil,
                                    isShiny: false, types: [.normal],
                                    base: BattleStats(hp: 160, atk: 110, def: 65, spa: 65, spd: 110, spe: 30))
        let frail = BattleSnapshot(speciesID: 92, name: "유령", trainer: nil, level: 5, nature: nil,
                                   isShiny: false, types: [.ghost],
                                   base: BattleStats(hp: 1, atk: 1, def: 1, spa: 1, spd: 1, spe: 1))
        var rng = SplitMix64(seed: 3)
        var a = BattleSide(strong), b = BattleSide(frail)
        let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: .struggle(), moveB: .struggle(),
                                              turn: 1, rng: &rng)
        XCTAssertTrue(events.contains(.faint(.b)), "기절이 스트림에 있어야 한다")
        XCTAssertFalse(events.contains(.faint(.a)), "쓰러지지 않은 쪽에는 없어야 한다")
    }

    /// 급소·상성은 데미지와 **따로** 실린다. 한 구조체에 플래그로 묶여 있던 값들이라,
    /// 분리되지 않으면 상태이상(Phase 2)이 들어올 자리가 없다.
    func testCritAndEffectivenessAreSeparateEvents() {
        // 급소가 어느 seed 에서 나는지는 미리 알 수 없다(선공이 rng 를 먼저 쓴다). 순회해서 찾는다.
        var sawCrit = false
        for seed in UInt64(0)..<64 {
            var rng = SplitMix64(seed: seed)
            var a = BattleSide(water()), b = BattleSide(fire())
            let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: surf(), moveB: flamethrower(),
                                                  turn: 1, rng: &rng)
            XCTAssertTrue(events.contains(.superEffective(.b)), "seed \(seed): 물 → 불꽃/비행 = ×2")
            XCTAssertTrue(events.contains(.resisted(.a)), "seed \(seed): 불꽃 → 물 = ×0.5")
            XCTAssertTrue(events.contains { if case .damage(.b, _, _) = $0 { return true } else { return false } })
            if events.contains(.crit(.b)) { sawCrit = true }
        }
        XCTAssertTrue(sawCrit, "급소가 데미지와 별개의 이벤트로 실려야 한다")
    }

    func testResolveTurnDeterministic() {
        var rng1 = SplitMix64(seed: 99), rng2 = SplitMix64(seed: 99)
        var a1 = BattleSide(water()), b1 = BattleSide(fire())
        var a2 = BattleSide(water()), b2 = BattleSide(fire())
        let e1 = BattleEngine.resolveTurn(a: &a1, b: &b1, moveA: hydroPump(),
                                          moveB: flamethrower(), turn: 1, rng: &rng1)
        let e2 = BattleEngine.resolveTurn(a: &a2, b: &b2, moveA: hydroPump(),
                                          moveB: flamethrower(), turn: 1, rng: &rng2)
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
            let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: hydroPump(),
                                                  moveB: flamethrower(), turn: 1, rng: &rng)
            // A 가 빗나갔으면 `.miss(.a)`, 맞았으면 B 쪽에 `.damage` 가 실린다.
            if events.contains(.miss(.a)) { missSeen = true }
            if events.contains(where: { if case .damage(.b, _, _) = $0 { return true } else { return false } }) {
                hitSeen = true
            }
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
        let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: thunderbolt, moveB: dig,
                                              turn: 1, rng: &rng)
        // 무효는 `.immune` 로 실리고 데미지 이벤트 자체가 없다 — "0 데미지" 로 새면 맞은 것처럼 읽힌다.
        XCTAssertTrue(events.contains(.immune(.b)))
        XCTAssertFalse(events.contains { if case .damage(.b, _, _) = $0 { return true } else { return false } })
        XCTAssertEqual(b.hp, b.stats.hp, "닥트리오는 한 점도 깎이지 않는다")
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
        // 발버둥(무속성)이라 고스트에도 박힌다 — 선공에 기절하면 공격은 하나뿐이어야 한다.
        let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: .struggle(), moveB: .struggle(),
                                              turn: 1, rng: &rng)
        XCTAssertEqual(events.moveActors, [.a], "기절한 쪽은 반격하지 못한다")
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

    /// 레벨이 낮아 후보가 4개가 안 될 때 **최종기를 앞당겨 주지 않는다.** 예전엔 완화된 풀도
    /// 습득레벨 내림차순이라 레벨 2 야생이 그 종의 마지막 기술을 들고 나왔다.
    func testMoveCandidatesFillShortPoolsWithTheEarliestMoves() throws {
        let json = """
        {"moves": [
          {"move": {"name": "tackle", "url": null},
           "version_group_details": [{"level_learned_at": 1, "move_learn_method": {"name": "level-up", "url": null}}]},
          {"move": {"name": "ember", "url": null},
           "version_group_details": [{"level_learned_at": 7, "move_learn_method": {"name": "level-up", "url": null}}]},
          {"move": {"name": "flamethrower", "url": null},
           "version_group_details": [{"level_learned_at": 47, "move_learn_method": {"name": "level-up", "url": null}}]},
          {"move": {"name": "fire-blast", "url": null},
           "version_group_details": [{"level_learned_at": 83, "move_learn_method": {"name": "level-up", "url": null}}]}
        ]}
        """
        let dto = try JSONDecoder().decode(PokemonMovesDTO.self, from: Data(json.utf8))
        let names = PokeAPIClient.moveCandidates(dto, level: 2)
        XCTAssertEqual(names, ["tackle", "ember", "flamethrower", "fire-blast"])
        XCTAssertEqual(names.first, "tackle")
        XCTAssertNotEqual(names[1], "fire-blast", "최종기가 두 번째 칸에 오면 완화가 내림차순이다")
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

    /// CPU 기술 선택은 이제 배틀의 `rng` 에서 뽑는다. 무브셋이 여러 개여도 seed 를 고정하면 같은
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
        XCTAssertEqual(battle.events.moveActors, [.b], "그 턴에 오간 공격은 상대(CPU) 것 하나뿐이다")
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

    /// 교체하며 내보낸 포켓몬이 그 공격에 쓰러져도 자동으로 다음 슬롯을 고르지 않는다.
    /// 사용자가 살아 있는 포켓몬을 직접 골라야 배틀이 이어진다.
    func testSwitchingIntoAFatalHitWaitsForManualReplacement() {
        var frail = fire()
        frail.base = BattleStats(hp: 1, atk: 1, def: 1, spa: 1, spd: 1, spe: 1)
        var battle = practiceBattle(myTeam: [water(), frail], opponent: fire())

        XCTAssertTrue(battle.switchMine(to: 1))

        XCTAssertFalse(battle.mine[1].isAlive, "맞고 쓰러진다")
        XCTAssertEqual(battle.myActive, 1, "쓰러진 슬롯에서 사용자의 교체 선택을 기다린다")
        XCTAssertNil(battle.result, "아직 한 마리 남았으므로 배틀은 계속된다")
        let turnBeforeReplacement = battle.turn
        let ppBeforeMove = battle.mine[0].pp[0]
        XCTAssertTrue(battle.switchMine(to: 0), "살아 있는 포켓몬을 직접 선택할 수 있다")
        XCTAssertEqual(battle.myActive, 0)
        XCTAssertEqual(battle.turn, turnBeforeReplacement, "기절 뒤 강제 교체는 턴을 소비하지 않는다")
        XCTAssertTrue(battle.useMove(0), "새로 나온 포켓몬은 즉시 기술을 쓸 수 있다")
        XCTAssertEqual(battle.mine[0].pp[0], ppBeforeMove - 1)
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

        XCTAssertEqual(battle.events.moveIDs, [MoveSpec.struggleID, MoveSpec.struggleID],
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
            return battle.events.moveIDs
        }
        let runs = Set((0..<10).map { _ in run() })
        XCTAssertEqual(runs.count, 1, "같은 seed 는 같은 배틀이어야 하는데 \(runs.count) 가지가 나왔다")
    }

    /// 관장은 무작위 CPU와 다르다. STAB·상성·명중률을 반영한 기대 피해가 더 큰 기술을 써서,
    /// 마지막 전설을 포함한 관장전이 낮은 위력 기술을 뽑아 스스로 난이도를 낮추지 않는다.
    func testGymStrategyChoosesTheHighestExpectedDamageMove() {
        var cpu = water()
        cpu.moves = [
            MoveSpec(id: 901, names: [:], type: .water, power: 90,
                     damageClass: .special, accuracy: 100, pp: 15),
            MoveSpec(id: 902, names: [:], type: .normal, power: 100,
                     damageClass: .special, accuracy: 100, pp: 15),
        ]
        var battle = TeamPracticeBattle(mine: [BattleSide(fire())], opponents: [BattleSide(cpu)],
                                        opponentMoveStrategy: .damageFocused, rng: SplitMix64(seed: 7))

        XCTAssertTrue(battle.useMove(0))

        XCTAssertTrue(battle.events.contains(.move(.b, moveID: 901)),
                      "물 STAB의 불꽃 약점 공략이 더 높은 무속성 위력보다 우선한다")
    }

    /// 같은 자리로는 교체할 수 없다 — 턴만 버리는 조작이 된다.
    func testSwitchingToTheActiveSlotIsRejected() {
        var battle = practiceBattle(myTeam: [water(), fire()], opponent: fire())

        XCTAssertFalse(battle.switchMine(to: 0))

        XCTAssertTrue(battle.events.isEmpty, "거절된 교체는 상대에게 공격 기회를 주지 않는다")
        XCTAssertEqual(battle.turn, 1)
    }
}

/// 스트림에서 "누가 무엇을 썼다" 만 골라낸다 — 선공 판정 테스트가 보는 건 그 순서다.
/// 예전엔 이벤트가 공격 1건과 1:1 이라 `events.first` 로 됐지만, 이제 한 공격이 이벤트 여럿을
/// 남기고 턴 구분선도 들어간다. (`AdventureTests` 의 멀티 라운드 테스트도 같이 쓴다.)
extension Array where Element == BattleEvent {
    var moveActors: [BattleActor] {
        compactMap { if case .move(let actor, _) = $0 { return actor } else { return nil } }
    }
    var moveIDs: [Int] {
        compactMap { if case .move(_, let id) = $0 { return id } else { return nil } }
    }
}
