import XCTest
@testable import PokeTokenBar

final class BattlePhase5Tests: XCTestCase {
    private func snapshot(types: [PokemonType] = [.normal], speed: Int = 100) -> BattleSnapshot {
        BattleSnapshot(speciesID: 1, name: "Test", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: speed))
    }

    private func attack(id: Int = 1, power: Int = 80) -> MoveSpec {
        MoveSpec(id: id, names: ["en": "Test"], type: .normal, power: power,
                 damageClass: .physical, accuracy: nil, pp: 20)
    }

    func testDrainHealsFromDamageAndClampsAtMaximumHP() {
        var attacker = BattleSide(snapshot())
        attacker.hp = attacker.stats.hp - 1
        var defender = BattleSide(snapshot())
        var move = attack(); move.drain = 50
        var rng = SplitMix64(seed: 1)

        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: move, rng: &rng)

        XCTAssertEqual(attacker.hp, attacker.stats.hp, "drain must not exceed maximum HP")
        XCTAssertTrue(events.contains { if case .heal(.a, amount: 1, cause: .drain) = $0 { return true }; return false })
    }

    func testRecoilCanFaintTheAttacker() {
        var attacker = BattleSide(snapshot()); attacker.hp = 1
        var defender = BattleSide(snapshot())
        var move = attack(); move.drain = -100
        var rng = SplitMix64(seed: 1)

        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: move, rng: &rng)

        XCTAssertEqual(attacker.hp, 0)
        XCTAssertTrue(events.contains { if case .damage(.a, _, cause: .recoil) = $0 { return true }; return false })
        XCTAssertTrue(events.contains(.faint(.a)))
    }

    func testFixedMultiHitReportsEachHitInItsOutcomeAndOneAggregateDamageEvent() {
        var attacker = BattleSide(snapshot()), defender = BattleSide(snapshot())
        var move = attack(); move.minHits = 2; move.maxHits = 2
        var rng = SplitMix64(seed: 5)
        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: move, rng: &rng)

        XCTAssertTrue(events.contains(.multiHit(.a, hits: 2)))
        XCTAssertEqual(events.filter { if case .damage(.b, _, .move) = $0 { return true }; return false }.count, 1)
    }

    func testFlinchStopsOnlyTheLaterActorAndClearsAtNextTurn() {
        var a = BattleSide(snapshot(speed: 10)), b = BattleSide(snapshot(speed: 200))
        var flinching = attack(); flinching.flinchChance = 100; flinching.priority = 1
        let ordinary = attack(id: 2)
        var rng = SplitMix64(seed: 2)

        let first = BattleEngine.resolveTurn(a: &a, b: &b, moveA: flinching, moveB: ordinary,
                                             turn: 1, rng: &rng)
        XCTAssertTrue(first.contains(.cant(.b, .flinch)))
        XCTAssertTrue(b.flinched, "flinch remains volatile until the next turn begins")

        let second = BattleEngine.resolveTurn(a: &a, b: &b, moveA: ordinary, moveB: ordinary,
                                              turn: 2, rng: &rng)
        XCTAssertTrue(second.contains(.move(.b, moveID: 2)))
        XCTAssertFalse(b.flinched)
    }

    func testNewMoveFieldsAreValidatedAtTheMultiplayerBoundary() {
        var valid = attack(); valid.drain = -100; valid.flinchChance = 100; valid.minHits = 2; valid.maxHits = 5
        XCTAssertTrue(MultiplayerValidation.validMoves([valid]))
        valid.minHits = 6; valid.maxHits = 2
        XCTAssertFalse(MultiplayerValidation.validMoves([valid]))
    }

    // MARK: - 대조군 — 새 필드가 없는 기술은 아무 일도 하지 않아야 한다

    /// `drain` 이 없는 기술은 회복도 반동도 없다. 이 대조군이 없으면 "모든 공격이 절반 회복" 같은
    /// 오구현이 위 테스트만으로 초록이 된다(화상 물리/특수 대조군과 같은 이유).
    func testAMoveWithoutDrainNeitherHealsNorRecoils() {
        var attacker = BattleSide(snapshot()); attacker.hp = attacker.stats.hp / 2
        var defender = BattleSide(snapshot())
        let before = attacker.hp
        var rng = SplitMix64(seed: 7)

        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: attack(), rng: &rng)

        XCTAssertEqual(attacker.hp, before, "drain 없는 기술이 HP 를 움직이면 안 된다")
        XCTAssertFalse(events.contains { if case .heal = $0 { return true }; return false })
        XCTAssertFalse(events.contains { if case .damage(_, _, .recoil) = $0 { return true }; return false })
    }

    /// 히트 수가 늘면 총 데미지도 같이 늘어야 한다. `hits` 만 세고 데미지는 1회분인 오구현은
    /// `.multiHit` 이벤트 단언만으로는 통과한다 — 그게 이 기전의 가장 흔한 반쪽 구현이다.
    func testMultiHitTotalScalesWithTheHitCount() {
        func totalDamage(hits: Int, seed: UInt64) -> Int {
            var defender = BattleSide(snapshot())
            let attacker = BattleSide(snapshot())
            defender.hp = 100_000                    // 히트가 KO 로 끊기지 않게
            var move = attack(power: 25); move.minHits = hits; move.maxHits = hits
            var rng = SplitMix64(seed: seed)
            return BattleEngine.resolveAttack(attacker: attacker, defender: defender,
                                              move: move, rng: &rng).damage
        }
        for seed in UInt64(1)...20 {
            let single = totalDamage(hits: 1, seed: seed)
            let double = totalDamage(hits: 2, seed: seed)
            XCTAssertGreaterThan(double, Int(Double(single) * 1.5),
                                 "seed \(seed): 2회 히트가 1회분 데미지에 머물렀다")
        }
    }

    /// 상대가 중간에 쓰러지면 남은 히트는 없다 — 본가와 같다. 안 끊으면 죽은 상대를 계속 때린다.
    func testMultiHitStopsWhenTheDefenderFaints() {
        var attacker = BattleSide(snapshot()), defender = BattleSide(snapshot())
        defender.hp = 1
        var move = attack(power: 25); move.minHits = 5; move.maxHits = 5
        var rng = SplitMix64(seed: 3)

        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: move, rng: &rng)

        XCTAssertEqual(defender.hp, 0)
        XCTAssertFalse(events.contains { if case .multiHit(_, let hits) = $0 { return hits > 1 }; return false },
                       "1히트에 쓰러졌으면 다단 문구도 나오지 않는다")
    }

    // MARK: - 되돌려주기 · 와이어 · 문구

    /// 카운터는 **마지막 히트**를 되돌려준다(본가). 다단기의 합계를 기록하면 되돌아오는 데미지가
    /// 히트 수만큼 뻥튀기된다 — 다단이 들어오면서 기존 기전이 조용히 세지는 자리다.
    func testCounterReturnsTheLastHitNotTheMultiHitTotal() {
        var attacker = BattleSide(snapshot()), defender = BattleSide(snapshot())
        var move = attack(power: 25); move.minHits = 2; move.maxHits = 2
        var rng = SplitMix64(seed: 11)
        BattleEngine.beginTurn(&attacker); BattleEngine.beginTurn(&defender)

        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                              attackerActor: .a, defenderActor: .b,
                                              move: move, rng: &rng)
        let total = events.reduce(0) { sum, event in
            if case .damage(.b, let amount, .move) = event { return sum + amount }
            return sum
        }
        XCTAssertTrue(events.contains(.multiHit(.a, hits: 2)))
        let recorded = defender.lastHitThisTurn?.amount
        XCTAssertNotNil(recorded)
        XCTAssertLessThan(recorded ?? total, total, "합계가 아니라 마지막 히트를 기록해야 한다")
        XCTAssertGreaterThan((recorded ?? 0) * 3, total, "마지막 히트가 합계의 1/3 미만이면 값이 깨진 것이다")
    }

    /// 풀죽음은 **volatile** 이다 — 주 상태 슬롯에 실려 오면 안 된다. 호스트가 라운드마다 보내는
    /// `status` 는 검사 없이 들어오고, `.flinch` 를 주 상태로 받아들이면 `canBeAfflicted` 가
    /// "이미 주 상태가 있다"로 읽어 그 개체가 **모든 상태이상에 영구 면역**이 된다.
    func testFlinchIsNeverAcceptedAsAMainStatusFromThePeer() throws {
        let participant = LobbyParticipant(id: UUID(), trainerName: "호스트", speciesID: 1,
                                           team: .solo, isReady: true, isHost: false)
        let honest = MultiplayerFighter(participant: participant, snapshot: snapshot())
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(honest)) as? [String: Any])
        json["status"] = Status.flinch.rawValue

        let forged = try JSONDecoder().decode(
            MultiplayerFighter.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(forged.side.status, "풀죽음은 주 상태가 아니다 — 경계에서 버린다")
        XCTAssertTrue(forged.side.canBeAfflicted(by: .paralysis),
                      "주 상태가 없으므로 상태이상은 그대로 걸려야 한다")

        // 실제로 쓰는 주 상태는 그대로 건너온다(대조군) — 전부 버리는 오구현을 막는다.
        json["status"] = Status.paralysis.rawValue
        let paralyzed = try JSONDecoder().decode(
            MultiplayerFighter.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(paralyzed.side.status, .paralysis)
    }

    /// 드레인 회복 줄은 3언어다. `"+12 HP"` 처럼 굽어 있으면 세 언어가 같은 문구를 받는다 —
    /// `.ko`/`.ja` 대칭만 보는 `LanguageSplitGuardTests` 는 이 부류를 못 잡는다.
    func testDrainHealLineIsLocalized() {
        func line(_ language: AppLanguage) -> String {
            BattleLog.lines([.heal(.a, amount: 12, cause: .drain)], l: L(language),
                            name: { _ in "거북왕" }, moveName: { _, _ in "메가드레인" })
                .map(\.text).joined()
        }
        XCTAssertTrue(line(.ko).contains("12"), "회복량이 안 보이면 줄이 무의미하다")
        XCTAssertNotEqual(line(.ko), line(.en))
        XCTAssertNotEqual(line(.en), line(.ja))
    }

    /// 다단 히트는 **화면에 몇 번 맞았는지 나와야** 기전이 존재한다. 이벤트만 흘리고 문구가 없으면
    /// 플레이어에게는 "위력이 이상하게 센 기술" 로만 보인다.
    func testMultiHitLineTellsThePlayerHowManyTimesItLanded() {
        func line(_ language: AppLanguage) -> String {
            BattleLog.lines([.move(.a, moveID: 24), .multiHit(.a, hits: 4),
                             .damage(.b, amount: 60, cause: .move)], l: L(language),
                            name: { _ in "시드라" }, moveName: { _, _ in "더블어택" })
                .map(\.text).joined(separator: " | ")
        }
        XCTAssertTrue(line(.ko).contains("4"), "히트 수가 로그에 없으면 다단은 보이지 않는 기전이다")
        XCTAssertNotEqual(line(.ko), line(.ja))
    }

    /// 엔진이 적용하지 못하는 변화기는 **사용자에게 권하지도 않는다.** 습득창·하트비늘이 보는
    /// `isUsable` 이 이 판정을 공유하지 않으면 회복기를 배우고 턴만 버린다.
    func testStatusMovesWithNoModeledEffectAreNotOfferedToTheUser() {
        func status(id: Int, ailment: String? = nil, changes: [StatChange]? = nil) -> MoveSpec {
            MoveSpec(id: id, names: ["en": "S"], type: .normal, power: 0,
                     damageClass: .status, accuracy: nil, pp: 10,
                     ailment: ailment, statChanges: changes, targetsUser: ailment == nil ? nil : false)
        }
        // 회복(105)·아침햇살(234): 회복이 구현되지 않아 엔진이 아무것도 안 한다.
        XCTAssertFalse(VariableDamage.isUsable(status(id: 105)))
        XCTAssertFalse(VariableDamage.isUsable(status(id: 234)))
        // 칼춤·전기자석파는 그대로 남는다(대조군) — 전 변화기를 막는 오구현을 걸러낸다.
        XCTAssertTrue(VariableDamage.isUsable(status(id: 14, changes: [StatChange(stat: .atk, change: 2)])))
        XCTAssertTrue(VariableDamage.isUsable(status(id: MoveSpec.thunderWaveID, ailment: "paralysis")))
        // 공격기는 이 게이트를 타지 않는다.
        XCTAssertTrue(VariableDamage.isUsable(attack()))
    }

    /// 새 기전이 rng 소비를 조건부로 늘리면 두 피어가 갈라진다. 같은 seed·같은 입력이면
    /// 이벤트 스트림이 **완전히 같아야** 한다(소비 횟수가 어긋나면 뒤 판정이 전부 밀린다).
    func testNewMechanicsStayDeterministicForTheSameSeed() {
        func run() -> [BattleEvent] {
            var a = BattleSide(snapshot(speed: 120)), b = BattleSide(snapshot(speed: 90))
            var multi = attack(power: 25); multi.minHits = 2; multi.maxHits = 5
            multi.flinchChance = 30
            var leech = attack(id: 3, power: 40); leech.drain = 50
            var rng = SplitMix64(seed: 4242)
            var events: [BattleEvent] = []
            for turn in 1...4 {
                events += BattleEngine.resolveTurn(a: &a, b: &b, moveA: multi, moveB: leech,
                                                   turn: turn, rng: &rng)
            }
            return events
        }
        XCTAssertEqual(run(), run())
    }
}
