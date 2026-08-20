import XCTest
@testable import PokeTokenBar

final class ReviewRegressionTests: XCTestCase {
    private func move(id: Int, name: String, power: Int) -> MoveSpec {
        MoveSpec(id: id, names: ["en": name], type: .normal, power: power,
                 damageClass: .physical, accuracy: nil, pp: 20)
    }

    private func snapshot(id: Int, name: String, move: MoveSpec, speed: Int = 80) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: name, trainer: "Trainer", level: 50,
                       nature: nil, isShiny: false, types: [.normal],
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: speed),
                       moves: [move])
    }

    /// 자동 출전으로 현재 슬롯이 바뀐 뒤에도 누적 로그는 이벤트 당시 포켓몬 이름과 기술을 써야 한다.
    func testLANLogPreservesTheCombatantThatProducedEachEventBatch() {
        let attack = move(id: 101, name: "Lead Strike", power: 40)
        let leadMove = move(id: 201, name: "Lead Move", power: 10)
        let reserveMove = move(id: 301, name: "Reserve Move", power: 10)
        let attacker = BattleSide(snapshot(id: 1, name: "Attacker", move: attack, speed: 200))
        let faintedLead = BattleSide(snapshot(id: 2, name: "Fainted Lead", move: leadMove, speed: 10))
        let healthyReserve = BattleSide(snapshot(id: 3, name: "Healthy Reserve", move: reserveMove, speed: 10))
        var battle = NetBattleState(iAmA: true, myTeam: [attacker],
                                    oppTeam: [faintedLead, healthyReserve],
                                    rng: SplitMix64(seed: 9))

        battle.myAction = .move(index: 0)
        battle.oppAction = .move(index: 0)
        XCTAssertNil(battle.resolveChosenActions())
        battle.oppTeam[0].hp = 1
        battle.myAction = .move(index: 0)
        battle.oppAction = .move(index: 0)
        XCTAssertNil(battle.resolveChosenActions())
        XCTAssertEqual(battle.oppActive, 1, "픽스처가 자동 출전을 실제로 밟아야 한다")

        let lines = BattleLogSource.netBattle(battle, mine: .a, l: L(.en)).map(\.text)
        let defenderLines = BattleLogSource.netBattle(battle, mine: .b, l: L(.en)).map(\.text)

        XCTAssertTrue(lines.contains { $0.contains("Fainted Lead used Lead Move") },
                      "교체 전 기술을 새 포켓몬의 무브셋으로 재해석하면 Struggle로 보인다")
        XCTAssertTrue(lines.contains("Fainted Lead fainted!"))
        XCTAssertFalse(lines.contains("Healthy Reserve fainted!"),
                       "자동 출전한 생존 포켓몬이 기절한 것으로 표시되어서는 안 된다")
        XCTAssertEqual(defenderLines, lines, "challenger/defender 어느 화면에서도 전투원 문맥은 같아야 한다")
    }

    /// 한 마리 팀에는 선택 가능한 교체 대상이 없으므로 LAN 화면에 교체 줄을 만들지 않는다.
    func testLANSingleTeamProducesNoSwitchStripSlots() {
        let only = BattleSide(snapshot(id: 1, name: "Only", move: move(id: 1, name: "Move", power: 10)))
        XCTAssertTrue(SwitchStripModel.battleSlots([only], active: 0).isEmpty)
    }

    /// 팀전에서는 기존처럼 활성·대기·기절 슬롯 전체를 보존해야 인덱스가 교체 대상과 일치한다.
    func testLANTeamStillProducesTheCompleteSwitchStrip() {
        let first = BattleSide(snapshot(id: 1, name: "First", move: move(id: 1, name: "One", power: 10)))
        let second = BattleSide(snapshot(id: 2, name: "Second", move: move(id: 2, name: "Two", power: 10)))
        XCTAssertEqual(SwitchStripModel.battleSlots([first, second], active: 0).map(\.index), [0, 1])
    }
}
