import XCTest
@testable import PokeTokenBar

/// 기술 **선택**을 막는 부류 — 도발·앙코르·씨앙코르·트집·봉인·비밀의힘, 그리고 구애 아이템.
///
/// 다른 volatile 과 갈리는 점은 **막는 자리가 데미지 경로가 아니라 선택 경로**라는 것이다.
/// 선택은 네 모드(1대1·모의전·웨이브·방)와 터미널이 각자 하므로, 규칙을 한 자리
/// (`BattleSide.selectionLock(forMoveAt:)`)에 두고 그 한 자리를 모두가 지나게 잠근다.
/// 모드마다 갈래를 두면 방에서만 도발이 통하지 않는 식으로 조용히 어긋난다.
final class BattleSelectionLockTests: XCTestCase {

    // MARK: 픽스처

    private func attackMove(_ id: Int, damageClass: MoveDamageClass = .physical) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "공격\(id)"], type: .normal, power: 60,
                            damageClass: damageClass, accuracy: 100, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = false
        return move
    }

    private func statusMove(_ id: Int) -> MoveSpec {
        var move = attackMove(id, damageClass: .status)
        move.power = 0
        move.accuracy = nil
        return move
    }

    private func side(moves: [MoveSpec]) -> BattleSide {
        var snapshot = BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                      nature: nil, isShiny: false, types: [.normal],
                                      base: BattleStats(hp: 100, atk: 100, def: 100,
                                                        spa: 100, spd: 100, spe: 100),
                                      weightHectograms: 100)
        snapshot.moves = moves
        return BattleSide(snapshot)
    }

    // MARK: 데이터가 답한다

    /// 비밀의힘이 막는 것은 **회복기**고, 어느 기술이 회복기인지는 쇼다운의 `heal` 플래그가 답한다.
    /// 손 목록이면 회복기 하나가 조용히 빠지고, 화면에는 "그 기술만 비밀의힘을 무시한다" 로 나온다.
    func testTheHealingMoveTableComesFromTheData() {
        XCTAssertTrue(ShowdownMoveData.healing.contains(105), "자기회복(105)이 회복기 표에 없다")
        XCTAssertTrue(ShowdownMoveData.healing.contains(156), "잠자기(156)가 회복기 표에 없다")
        XCTAssertTrue(ShowdownMoveData.healing.contains(273), "희망사탕(273)이 회복기 표에 없다")
        // 흡수기도 표에 있다 — 쇼다운의 `healblock` 이 플래그가 붙은 기술을 전부 막는다.
        XCTAssertTrue(ShowdownMoveData.healing.contains(202), "기가드레인(202)도 회복 플래그를 든다")
        XCTAssertFalse(ShowdownMoveData.healing.contains(33), "몸통박치기(33)는 회복기가 아니다")
    }

    // MARK: 여섯 가지 잠금

    /// 도발은 **변화기만** 막는다. 공격기는 그대로 나간다.
    func testTauntLocksOnlyTheStatusMoves() {
        var mon = side(moves: [attackMove(33), statusMove(45)])
        XCTAssertTrue(mon.start(.taunt, turns: 3))
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .taunt)
        XCTAssertTrue(mon.canUse(moveAt: 0))
        XCTAssertFalse(mon.canUse(moveAt: 1))
    }

    /// 변화기만 든 개체가 도발당하면 **낼 기술이 하나도 없다** — 그때는 발버둥이다.
    /// PP 만 보는 옛 `mustStruggle` 은 이 개체를 "낼 기술이 있다" 로 읽어 아무 기술도 못 내는
    /// 턴을 만들었다(선택은 막히는데 발버둥도 안 나오는 자리).
    func testAMonWithNothingLeftToPickMustStruggle() {
        var mon = side(moves: [statusMove(45), statusMove(47)])
        XCTAssertFalse(mon.mustStruggle)
        XCTAssertTrue(mon.start(.taunt, turns: 3))
        XCTAssertTrue(mon.mustStruggle)
    }

    /// 씨앙코르는 **직전에 낸 그 기술 하나**를 막는다.
    func testDisableLocksTheOneMoveItNamed() {
        var mon = side(moves: [attackMove(33), attackMove(34)])
        XCTAssertTrue(mon.start(.disable, turns: 4))
        mon.disabledMoveID = 34
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .disable)
    }

    /// 앙코르는 반대다 — **한 기술만 남기고** 나머지를 막는다.
    func testEncoreLeavesOnlyTheMoveItRepeats() {
        var mon = side(moves: [attackMove(33), attackMove(34), statusMove(45)])
        XCTAssertTrue(mon.start(.encore, turns: 3))
        mon.encoredMoveID = 34
        XCTAssertEqual(mon.selectionLock(forMoveAt: 0), .encore)
        XCTAssertNil(mon.selectionLock(forMoveAt: 1))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 2), .encore)
    }

    /// 트집은 **같은 기술을 연달아** 내지 못하게 한다 — 직전에 낸 것만 막힌다.
    func testTormentLocksOnlyTheMoveJustUsed() {
        var mon = side(moves: [attackMove(33), attackMove(34)])
        XCTAssertTrue(mon.start(.torment))
        mon.lastMoveID = 33
        XCTAssertEqual(mon.selectionLock(forMoveAt: 0), .torment)
        XCTAssertNil(mon.selectionLock(forMoveAt: 1))
        // 다른 기술을 내면 막히는 자리가 옮겨 간다(고정된 목록이 아니다).
        mon.lastMoveID = 34
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .torment)
    }

    /// 봉인은 **상대와 겹치는 기술**을 막는다 — 겹치지 않는 기술은 그대로 낸다.
    func testImprisonLocksTheMovesTheCasterAlsoKnows() {
        var mon = side(moves: [attackMove(33), attackMove(34)])
        XCTAssertTrue(mon.start(.imprison))
        mon.imprisonedMoveIDs = [34]
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .imprison)
    }

    /// 비밀의힘은 회복기만 막는다 — 어느 기술이 회복기인지는 데이터가 답한다(위 표).
    func testHealBlockLocksTheHealingMoves() {
        var mon = side(moves: [attackMove(33), statusMove(105)])
        XCTAssertTrue(mon.start(.healBlock, turns: 5))
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertEqual(mon.selectionLock(forMoveAt: 1), .healBlock)
    }

    /// 잠금이 하나도 없으면 네 칸 모두 열려 있다 — 잠금 판정 자체가 기본값을 막지 않는지 본다
    /// (막는 조건이 뒤집혀 있어도 위 테스트들은 전부 초록이다).
    func testAnUntouchedMonHasEveryMoveOpen() {
        let mon = side(moves: [attackMove(33), statusMove(45), attackMove(34), statusMove(105)])
        for index in 0..<4 {
            XCTAssertNil(mon.selectionLock(forMoveAt: index), "칸 \(index) 가 이유 없이 막혔다")
            XCTAssertTrue(mon.canUse(moveAt: index))
        }
        XCTAssertFalse(mon.mustStruggle)
    }

    /// 교체하면 잠금도 함께 사라진다 — volatile 만 지우고 곁의 값(막힌 기술 id)을 남기면
    /// 다시 나온 개체가 이유 없이 한 기술을 못 낸다(층 HP 와 같은 부류의 결함이다).
    func testSwitchingOutClearsEveryLock() {
        var mon = side(moves: [attackMove(33), attackMove(34)])
        _ = mon.start(.disable, turns: 4)
        mon.disabledMoveID = 34
        _ = mon.start(.encore, turns: 3)
        mon.encoredMoveID = 33
        _ = mon.start(.imprison)
        mon.imprisonedMoveIDs = [33, 34]
        mon.choiceLockedMoveID = 33

        BattleEngine.prepareForSwitch(&mon)

        XCTAssertNil(mon.disabledMoveID)
        XCTAssertNil(mon.encoredMoveID)
        XCTAssertTrue(mon.imprisonedMoveIDs.isEmpty)
        XCTAssertNil(mon.choiceLockedMoveID)
        XCTAssertNil(mon.selectionLock(forMoveAt: 0))
        XCTAssertNil(mon.selectionLock(forMoveAt: 1))
    }
}
