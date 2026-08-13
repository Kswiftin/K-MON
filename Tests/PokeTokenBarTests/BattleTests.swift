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
        var s = BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 100)
        _ = s   // canonical 확인용이 아니라 keypath 대상 타입 고정용
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

    // MARK: 배틀 코드 직렬화

    private func sampleSnapshot() -> BattleSnapshot {
        BattleSnapshot(speciesID: 6, name: "리자몽", trainer: "지우", level: 77,
                       nature: .jolly, isShiny: true, types: [.fire, .flying],
                       base: BattleStats(hp: 78, atk: 84, def: 78, spa: 109, spd: 85, spe: 100))
    }

    func testBattleCodeRoundTrip() throws {
        let original = sampleSnapshot()
        let code = try BattleCode.encode(original)
        XCTAssertTrue(code.hasPrefix(BattleCode.prefix))
        let decoded = try BattleCode.decode(code)
        XCTAssertEqual(decoded.speciesID, original.speciesID)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.level, original.level)
        XCTAssertEqual(decoded.nature, original.nature)
        XCTAssertEqual(decoded.types, original.types)
        XCTAssertEqual(decoded.base, original.base)
        XCTAssertTrue(decoded.isShiny)
    }

    func testBattleCodeRoundTripWithWhitespace() throws {
        let code = try BattleCode.encode(sampleSnapshot())
        _ = try BattleCode.decode("  \(code)\n")   // Slack 복붙 잔여 공백 허용
    }

    func testBattleCodeTamperDetected() throws {
        let code = try BattleCode.encode(sampleSnapshot())
        // 레벨을 77 → 99 로 고쳐 재인코딩(checksum 은 그대로) — badChecksum 이어야 한다.
        let b64 = String(code.dropFirst(BattleCode.prefix.count))
        var padded = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        let json = String(data: Data(base64Encoded: padded)!, encoding: .utf8)!
        let tampered = json.replacingOccurrences(of: "\"level\":77", with: "\"level\":99")
        XCTAssertNotEqual(json, tampered, "fixture 가 level 필드를 못 찾으면 테스트가 무의미")
        let tamperedCode = BattleCode.prefix + Data(tampered.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try BattleCode.decode(tamperedCode)) { error in
            XCTAssertEqual(error as? BattleCode.DecodeError, .badChecksum)
        }
    }

    func testBattleCodeGarbageRejected() {
        XCTAssertThrowsError(try BattleCode.decode("PTB1.notbase64!!!"))
        XCTAssertThrowsError(try BattleCode.decode("hello"))
        XCTAssertThrowsError(try BattleCode.decode(""))
    }

    // MARK: 배틀 엔진

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

    func testSimulationDeterministicForSameSeed() {
        let r1 = BattleEngine.simulate(a: water(), b: fire(), seed: 42)
        let r2 = BattleEngine.simulate(a: water(), b: fire(), seed: 42)
        XCTAssertEqual(r1, r2)
    }

    func testSimulationEndsWithWinnerOrDraw() {
        let r = BattleEngine.simulate(a: water(), b: fire(), seed: 7)
        XCTAssertFalse(r.turns.isEmpty)
        XCTAssertLessThanOrEqual(r.turns.count, BattleEngine.maxTurns)
        if let last = r.turns.last, r.winnerIsA != nil, r.turns.count < BattleEngine.maxTurns {
            XCTAssertEqual(last.defenderHPAfter, 0, "상한 전 종료면 마지막 피격자는 기절이어야 한다")
        }
    }

    func testTypeAdvantageWinsLopsidedMatch() {
        // 물 vs 불(비행 복합, 물 2배) — 동레벨·유사 종족값이면 seed 무관하게 물이 대부분 이겨야 한다.
        var waterWins = 0
        for seed in UInt64(0)..<20 {
            let r = BattleEngine.simulate(a: water(), b: fire(), seed: seed)
            if r.winnerIsA == true { waterWins += 1 }
        }
        XCTAssertGreaterThanOrEqual(waterWins, 15, "타입 상성이 결과에 반영돼야 한다 (20판 중 \(waterWins)승)")
    }

    func testStruggleFallbackWhenAllTypesImmune() {
        // 노말 단일 vs 고스트 단일 — 노말 공격이 0배라 발버둥(moveType nil)으로 폴백해야 한다.
        let normal = BattleSnapshot(speciesID: 143, name: "잠만보", trainer: nil, level: 50,
                                    nature: nil, isShiny: false, types: [.normal],
                                    base: BattleStats(hp: 160, atk: 110, def: 65, spa: 65, spd: 110, spe: 30))
        let ghost = BattleSnapshot(speciesID: 92, name: "고오스", trainer: nil, level: 50,
                                   nature: nil, isShiny: false, types: [.ghost],
                                   base: BattleStats(hp: 30, atk: 35, def: 30, spa: 100, spd: 35, spe: 80))
        let r = BattleEngine.simulate(a: normal, b: ghost, seed: 1)
        let normalAttacks = r.turns.filter { $0.attackerIsA }
        XCTAssertFalse(normalAttacks.isEmpty)
        XCTAssertTrue(normalAttacks.allSatisfy { $0.moveType == nil }, "노말→고스트는 발버둥이어야 한다")
        XCTAssertTrue(normalAttacks.allSatisfy { $0.damage >= 1 }, "발버둥도 최소 1 데미지")
    }

    func testSymmetricSeedIsOrderIndependent() {
        XCTAssertEqual(BattleEngine.symmetricSeed("codeA", "codeB"),
                       BattleEngine.symmetricSeed("codeB", "codeA"))
    }

    func testFasterPokemonActsFirst() {
        let r = BattleEngine.simulate(a: water(), b: fire(), seed: 3)
        // fire(spe 100) > water(spe 78) — 첫 턴 공격자는 b.
        XCTAssertEqual(r.turns.first?.attackerIsA, false)
    }

    // MARK: 네트워크 대전 턴 해상

    private func hydroPump() -> MoveSpec {
        MoveSpec(id: 56, names: ["en": "Hydro Pump"], type: .water, power: 110,
                 damageClass: .special, accuracy: 80, pp: 5)
    }
    private func flamethrower() -> MoveSpec {
        MoveSpec(id: 53, names: ["en": "Flamethrower"], type: .fire, power: 90,
                 damageClass: .special, accuracy: 100, pp: 15)
    }

    func testResolveTurnDeterministic() {
        let (a, b) = (water(), fire())
        let (sa, sb) = (a.effectiveStats(), b.effectiveStats())
        var rng1 = SplitMix64(seed: 99), rng2 = SplitMix64(seed: 99)
        var a1 = sa.hp, b1 = sb.hp, a2 = sa.hp, b2 = sb.hp
        let e1 = BattleEngine.resolveTurn(a: a, b: b, statsA: sa, statsB: sb, hpA: &a1, hpB: &b1,
                                          moveA: hydroPump(), moveB: flamethrower(), rng: &rng1)
        let e2 = BattleEngine.resolveTurn(a: a, b: b, statsA: sa, statsB: sb, hpA: &a2, hpB: &b2,
                                          moveA: hydroPump(), moveB: flamethrower(), rng: &rng2)
        XCTAssertEqual(e1, e2, "두 피어가 같은 seed 로 같은 결과를 얻어야 대전이 성립한다")
        XCTAssertEqual(a1, a2)
        XCTAssertEqual(b1, b2)
    }

    func testResolveTurnAccuracyRoll() {
        // 명중 80 기술 — 여러 seed 에서 빗나감과 명중이 모두 관측돼야 한다.
        let (a, b) = (water(), fire())
        let (sa, sb) = (a.effectiveStats(), b.effectiveStats())
        var missSeen = false, hitSeen = false
        for seed in UInt64(0)..<40 {
            var rng = SplitMix64(seed: seed)
            var ha = sa.hp, hb = sb.hp
            let events = BattleEngine.resolveTurn(a: a, b: b, statsA: sa, statsB: sb, hpA: &ha, hpB: &hb,
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
        let (sp, sg) = (pika.effectiveStats(), dugtrio.effectiveStats())
        let thunderbolt = MoveSpec(id: 85, names: ["en": "Thunderbolt"], type: .electric, power: 90,
                                   damageClass: .special, accuracy: nil, pp: 15)
        let dig = MoveSpec(id: 91, names: ["en": "Dig"], type: .ground, power: 80,
                           damageClass: .physical, accuracy: nil, pp: 10)
        var rng = SplitMix64(seed: 1)
        var hp = sp.hp, hg = sg.hp
        let events = BattleEngine.resolveTurn(a: pika, b: dugtrio, statsA: sp, statsB: sg, hpA: &hp, hpB: &hg,
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
        let (ss, sf) = (strong.effectiveStats(), frail.effectiveStats())
        var rng = SplitMix64(seed: 3)
        var hs = ss.hp, hf = sf.hp
        // 발버둥(무속성)이라 고스트에도 박힌다 — 선공 기절 시 이벤트는 1개여야 한다.
        let events = BattleEngine.resolveTurn(a: strong, b: frail, statsA: ss, statsB: sf, hpA: &hs, hpB: &hf,
                                              moveA: .struggle(), moveB: .struggle(), rng: &rng)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(hf, 0)
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
}
