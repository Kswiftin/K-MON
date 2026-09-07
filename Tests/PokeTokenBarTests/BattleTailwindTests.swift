import XCTest
@testable import PokeTokenBar

/// 순풍 — 편에 4턴 깔리고 **그 편의 스피드를 2배**로 본다.
///
/// 다른 진영 상태와 달리 데미지가 아니라 **턴 순서**를 바꾼다. 순서 계산이 모드마다 따로 있어서
/// (1v1 `resolveTurn`·방·웨이브) 한 곳만 고치면 그 모드에서만 순풍이 없는 배틀이 된다.
/// 스피드를 위력으로 읽는 기술(일렉트릭볼·자이로볼)도 같은 값을 봐야 한다.
final class BattleTailwindTests: XCTestCase {

    private func side(speed: Int, hp: Int? = nil) -> BattleSide {
        var out = BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                            nature: nil, isShiny: false, types: [.normal],
                                            base: BattleStats(hp: 100, atk: 100, def: 100,
                                                              spa: 100, spd: 100, spe: speed),
                                            weightHectograms: 100))
        if let hp { out.hp = hp }
        return out
    }

    private func spec(_ id: Int, power: Int = 40, damageClass: MoveDamageClass = .physical,
                      accuracy: Int? = 100) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "기술"], type: .normal, power: power,
                            damageClass: damageClass, accuracy: accuracy, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0; move.targetsUser = false
        return move
    }

    private func tailwindMoveID() -> Int? {
        ShowdownMoveData.effects.keys.sorted().first {
            BattleSideCondition.called(byMoveID: $0) == .tailwind
        }
    }

    /// 데이터에 순풍이 있고 엔진이 그것을 안다 — 미구현 목록에서 빠졌다는 뜻이다.
    func testTailwindIsCalledByAMoveInTheData() throws {
        let id = try XCTUnwrap(tailwindMoveID(), "순풍을 부르는 기술을 데이터에서 못 찾는다")
        XCTAssertEqual(BattleSideCondition.called(byMoveID: id), .tailwind)
    }

    /// 순풍은 **4턴**이다 — 장막의 5턴을 그대로 쓰면 한 턴 더 분다.
    func testTailwindLastsFourTurnsWhileScreensLastFive() {
        XCTAssertEqual(BattleSideCondition.tailwind.duration, 4)
        XCTAssertEqual(BattleSideCondition.reflect.duration, 5)

        var field = BattleField()
        XCTAssertTrue(field.start(.tailwind, for: .a))
        XCTAssertFalse(field.start(.tailwind, for: .a), "다시 걸면 실패한다 — 영구 순풍 방지")
        var ended: [BattleEvent] = []
        for _ in 0..<3 {
            ended = BattleEngine.advanceField(&field)
            XCTAssertTrue(field.has(.tailwind, for: .a), "4턴 전에 걷히면 안 된다")
        }
        ended = BattleEngine.advanceField(&field)
        XCTAssertTrue(ended.contains(.sideConditionEnded(.a, .tailwind)))
        XCTAssertFalse(field.has(.tailwind, for: .a))
    }

    /// 편에 깔린 쪽만 2배로 본다. 순풍이 없는 판과 상대 편 순풍은 값이 그대로다.
    func testOrderingSpeedDoublesOnlyForTheTailwindSide() {
        let runner = side(speed: 100)
        var field = BattleField()
        XCTAssertEqual(BattleEngine.orderingSpeed(runner, team: .a, field: field),
                       runner.effectiveSpeed)
        XCTAssertTrue(field.start(.tailwind, for: .a))
        XCTAssertEqual(BattleEngine.orderingSpeed(runner, team: .a, field: field),
                       runner.effectiveSpeed * 2)
        XCTAssertEqual(BattleEngine.orderingSpeed(runner, team: .b, field: field),
                       runner.effectiveSpeed, "상대 편 순풍은 내 순서를 안 바꾼다")
    }

    /// 1v1 한 턴 — 느린 쪽이 순풍을 받으면 **먼저** 때린다. 순서가 안 바뀌면 이 단언이 뒤집힌다.
    func testTailwindFlipsTheTurnOrderInOneOnOne() {
        func firstMover(tailwindOnA: Bool) -> BattleActor? {
            var a = side(speed: 60, hp: 9_999), b = side(speed: 100, hp: 9_999)
            var field = BattleField()
            if tailwindOnA { XCTAssertTrue(field.start(.tailwind, for: .a)) }
            var rng = SplitMix64(seed: 7)
            let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: spec(33), moveB: spec(33),
                                                  turn: 1, field: &field, rng: &rng)
            return events.compactMap { if case .move(let actor, _) = $0 { return actor } else { return nil } }.first
        }
        XCTAssertEqual(firstMover(tailwindOnA: false), .b, "순풍이 없으면 빠른 쪽이 먼저다")
        XCTAssertEqual(firstMover(tailwindOnA: true), .a, "순풍(120)이 상대(100)를 앞선다")
    }

    /// 스피드를 위력으로 읽는 기술도 같은 값을 본다 — 순풍이 순서만 바꾸고 위력은 예전 값이면
    /// 화면에서 구별할 수 없는 오구현이다.
    func testTailwindRaisesElectroBallAndLowersGyroBall() {
        let attacker = side(speed: 100), defender = side(speed: 100)
        var windy = BattleField()
        XCTAssertTrue(windy.start(.tailwind, for: .a))

        XCTAssertEqual(VariableDamage.electroBallPower(attacker: attacker, defender: defender,
                                                       field: BattleField(),
                                                       attackerTeam: .a, defenderTeam: .b), 40)
        XCTAssertEqual(VariableDamage.electroBallPower(attacker: attacker, defender: defender,
                                                       field: windy,
                                                       attackerTeam: .a, defenderTeam: .b), 60,
                       "순풍으로 2배 빠르면 위력이 오른다")
        XCTAssertLessThan(VariableDamage.gyroBallPower(attacker: attacker, defender: defender,
                                                       field: windy,
                                                       attackerTeam: .a, defenderTeam: .b),
                          VariableDamage.gyroBallPower(attacker: attacker, defender: defender,
                                                       field: BattleField(),
                                                       attackerTeam: .a, defenderTeam: .b),
                          "자이로볼은 반대로 약해진다")
    }

    /// 기술로 깔린다 — 자기 편에, 이벤트 한 줄과 함께.
    func testTheTailwindMovePutsItOnTheUsersSide() throws {
        let move = spec(try XCTUnwrap(tailwindMoveID()), power: 0,
                        damageClass: .status, accuracy: nil)
        var caster = side(speed: 100), target = side(speed: 100, hp: 9_999)
        var field = BattleField()
        var rng = SplitMix64(seed: 4)
        let events = BattleEngine.applyAttack(attacker: &caster, defender: &target,
                                              attackerActor: .a, defenderActor: .b, move: move,
                                              field: &field, attackerTeam: .a, defenderTeam: .b,
                                              rng: &rng)
        XCTAssertTrue(events.contains(.sideConditionStarted(.a, .tailwind)))
        XCTAssertTrue(field.has(.tailwind, for: .a))
        XCTAssertFalse(field.has(.tailwind, for: .b))
        XCTAssertTrue(move.hasModeledStatusEffect, "무브셋 후보에서 빠지면 아무도 못 배운다")
    }

    /// **순서를 재는 모든 모드가 같은 함수를 써야 한다.** 한 곳이 `effectiveSpeed` 를 직접 읽으면
    /// 그 모드에서만 순풍이 없고, 화면에는 "이 배틀은 왜 안 빨라지지" 로만 보인다.
    ///
    /// 주석을 떼는 일은 `SourceScan` 이 한다 — 호출을 지워도 "`orderingSpeed` 가 보정을 들고
    /// 있다" 같은 설명 주석이 남아 스캔을 통과한다(결함을 주입해 실제로 새는 것을 확인했다).
    func testEveryTurnOrderSiteAsksTheEngineForSpeed() throws {
        var sitesWithoutTailwind: [String] = []
        for (name, code) in try SourceScan.sources() {
            guard code.contains(".turnPriority") else { continue }
            // 정의한 파일은 선언 한 번을 빼고 센다 — 안 빼면 엔진이 자기 함수를 안 부르는 채로
            // 통과한다(선언만으로 문자열이 있으므로).
            let declarations = code.components(separatedBy: "static func orderingSpeed(").count - 1
            let mentions = code.components(separatedBy: "orderingSpeed(").count - 1
            if mentions - declarations < 1 { sitesWithoutTailwind.append(name) }
        }
        XCTAssertEqual(sitesWithoutTailwind, [],
                       "순서를 재면서 순풍을 안 보는 모드가 있다")
    }
}
