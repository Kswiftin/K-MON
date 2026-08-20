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

    /// 두 배치가 쌓인 LAN 팀전 — 1턴은 살아남고 2턴에 선봉이 기절한다.
    private func twoBatchBattle() -> NetBattleState {
        let attack = move(id: 101, name: "Lead Strike", power: 40)
        let leadMove = move(id: 201, name: "Lead Move", power: 10)
        let reserveMove = move(id: 301, name: "Reserve Move", power: 10)
        var battle = NetBattleState(iAmA: true,
                                    myTeam: [BattleSide(snapshot(id: 1, name: "Attacker",
                                                                 move: attack, speed: 200))],
                                    oppTeam: [BattleSide(snapshot(id: 2, name: "Fainted Lead",
                                                                  move: leadMove, speed: 10)),
                                              BattleSide(snapshot(id: 3, name: "Healthy Reserve",
                                                                  move: reserveMove, speed: 10))],
                                    rng: SplitMix64(seed: 9))
        battle.myAction = .move(index: 0)
        battle.oppAction = .move(index: 0)
        XCTAssertNil(battle.resolveChosenActions())
        battle.oppTeam[0].hp = 1
        battle.myAction = .move(index: 0)
        battle.oppAction = .move(index: 0)
        XCTAssertNil(battle.resolveChosenActions())
        return battle
    }

    /// 재생 진행도는 **평평한** `events` 개수로 세는데 로그는 배치별로 접힌다. 이 두 축이 어긋나면
    /// 아직 재생되지 않은 턴이 로그에 먼저 나와 재생할 이유 자체가 없어진다 — 잘림은 배치 경계를
    /// 넘어가며 세야 한다.
    func testLANLogStopsAtThePlayedEventCount() {
        let battle = twoBatchBattle()
        let l = L(.en)
        XCTAssertEqual(battle.eventBatches.count, 2, "픽스처가 배치 경계를 실제로 만들어야 한다")
        // 잘림이 기대는 불변식: 평평한 스트림은 배치들을 이어 붙인 것과 같은 순서·개수다.
        XCTAssertEqual(battle.events, battle.eventBatches.flatMap(\.events))

        let full = BattleLogSource.netBattle(battle, mine: .a, l: l).map(\.text)
        let firstBatch = battle.eventBatches[0].events.count
        XCTAssertGreaterThan(firstBatch, 1, "첫 배치가 두 이벤트 이상이어야 중간 잘림을 밟는다")
        let atEveryProgress = (0...battle.events.count).map {
            BattleLogSource.netBattle(battle, mine: .a, l: l, playedCount: $0).map(\.text)
        }

        XCTAssertTrue(atEveryProgress[0].isEmpty, "재생이 시작되지 않았으면 로그도 비어 있어야 한다")
        // 한 줄은 "기술 + 피해" 로 접히므로 재생 중 마지막 줄은 아직 자란다 — 그래서 정확히 같은
        // 앞부분이 아니라 **줄마다 앞부분**이다. 그 대신 없던 줄이 먼저 나오는 건 여기서 걸린다.
        for (progress, lines) in atEveryProgress.enumerated() {
            XCTAssertLessThanOrEqual(lines.count, full.count,
                                     "진행도 \(progress) 에서 전체보다 많은 줄이 나왔다")
            for (index, line) in lines.enumerated() where index < full.count {
                XCTAssertTrue(full[index].hasPrefix(line),
                              "진행도 \(progress) 의 \(index)번째 줄이 전체 로그와 갈라진다: \(line)")
            }
        }
        // 배치 경계(=firstBatch)에서만 맞으면 "배치 단위 잘림" 과 구별되지 않는다 — 경계 안쪽을 본다.
        XCTAssertLessThan(atEveryProgress[1].count, atEveryProgress[firstBatch].count,
                          "배치 중간에서 자르지 않고 배치 단위로만 자르면 이 두 지점이 같아진다")
        let played = atEveryProgress[firstBatch]
        XCTAssertLessThan(played.count, full.count, "1턴까지만 재생됐으면 로그도 그만큼이어야 한다")
        XCTAssertTrue(played.contains { $0.contains("Fainted Lead used Lead Move") },
                      "배치 안에서 자르더라도 그 배치의 이름·기술 문맥은 살아 있어야 한다")
        XCTAssertFalse(played.contains("Fainted Lead fainted!"),
                       "2턴 결과가 재생보다 먼저 로그에 새면 재생이 결과를 스포일한다")
        XCTAssertEqual(atEveryProgress[battle.events.count], full,
                       "전부 재생됐으면 자르지 않은 로그와 같아야 한다")
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
