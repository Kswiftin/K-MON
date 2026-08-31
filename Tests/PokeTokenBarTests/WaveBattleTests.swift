import XCTest
@testable import PokeTokenBar

/// 웨이브 런 전용 다중 슬롯 전투(`WaveBattle`). 잠그는 것은 **2대2 규칙**이다 —
/// 타겟팅·네 명 턴 순서·기절 슬롯 교체·전멸 판정. 데미지·상태이상 계산은 `BattleEngine` 이
/// 자기 테스트로 이미 잠겨 있으므로 여기서 다시 재지 않는다.
final class WaveBattleTests: XCTestCase {

    /// 한 방에 죽지 않는 개체 — 순서·타겟을 재려면 여러 턴을 밟아야 한다.
    private func snapshot(_ id: Int, level: Int = 50, hp: Int = 200, power: Int = 40,
                          speed: Int = 100) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "M\(id)", trainer: "T", level: level, nature: nil,
                       isShiny: false, types: [.normal],
                       base: BattleStats(hp: hp, atk: 80, def: 80, spa: 80, spd: 80, spe: speed),
                       moves: [MoveSpec(id: 1, names: ["en": "Hit"], type: .normal, power: power,
                                        damageClass: .physical, accuracy: nil, pp: 20)])
    }

    /// 광역기 하나만 든 개체. `target` 슬러그가 범위의 유일한 신호다(`MoveSpec.reach`).
    private func spreadSnapshot(_ id: Int, target: String, power: Int = 60,
                                speed: Int = 100, hp: Int = 400) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "S\(id)", trainer: "T", level: 50, nature: nil,
                       isShiny: false, types: [.normal],
                       base: BattleStats(hp: hp, atk: 80, def: 80, spa: 80, spd: 80, spe: speed),
                       moves: [MoveSpec(id: 89, names: ["en": "Quake"], type: .normal, power: power,
                                        damageClass: .physical, accuracy: nil, pp: 20,
                                        target: target)])
    }

    private func battle(mine: [BattleSnapshot], opponents: [BattleSnapshot],
                        seed: UInt64 = 7) -> WaveBattle {
        WaveBattle(mine: mine.map(BattleSide.init), opponents: opponents.map(BattleSide.init),
                   rng: SplitMix64(seed: seed))
    }

    // MARK: 필드 구성

    /// 상대가 둘이면 양쪽 다 두 칸이다 — 앞 상대를 눕히면 다음이 나오는 **연전이 아니다**.
    func testTwoOpponentsPutTwoOnEachSide() {
        let subject = battle(mine: [snapshot(1), snapshot(2), snapshot(3)],
                             opponents: [snapshot(90), snapshot(91)])
        XCTAssertEqual(subject.myField.map(\.teamIndex), [0, 1])
        XCTAssertEqual(subject.opponentField.map(\.teamIndex), [0, 1])
    }

    /// 파티가 한 마리면 2대1 이다. 포켓로그도 플레이어 필드를 파티 수로 자른다
    /// (`battle-scene.ts:733`) — 자르지 않으면 빈 칸이 상대 공격을 받는 유령 슬롯이 된다.
    func testPartyOfOneFacesTwoWithOneSlot() {
        let subject = battle(mine: [snapshot(1)], opponents: [snapshot(90), snapshot(91)])
        XCTAssertEqual(subject.myField.count, 1)
        XCTAssertEqual(subject.opponentField.count, 2)
    }

    /// 상대가 하나면 내 칸도 하나다 — 파티가 여섯이어도 단일전이다.
    func testSingleOpponentKeepsSingleSlots() {
        let subject = battle(mine: [snapshot(1), snapshot(2)], opponents: [snapshot(90)])
        XCTAssertEqual(subject.myField.count, 1)
        XCTAssertEqual(subject.opponentField.count, 1)
    }

    // MARK: 행동 수집

    /// 두 칸이면 **두 칸이 다 정해질 때까지** 턴이 해상되지 않는다. 첫 칸 입력에 턴을 돌리면
    /// 두 번째 칸은 매 턴 아무것도 하지 않는 관객이 된다.
    func testTurnWaitsUntilEverySlotHasChosen() {
        var subject = battle(mine: [snapshot(1), snapshot(2)],
                             opponents: [snapshot(90), snapshot(91)])
        XCTAssertEqual(subject.slotsAwaitingAction, [0, 1])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertEqual(subject.turn, 1, "한 칸만 정해졌으면 아직 턴이 아니다")
        XCTAssertEqual(subject.slotsAwaitingAction, [1])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertEqual(subject.turn, 2)
        XCTAssertTrue(subject.pendingActions.isEmpty, "해상된 턴의 입력은 남지 않는다")
    }

    /// 같은 칸에 두 번 입력하면 뒤 입력이 앞 입력을 덮는다(취소·수정 경로).
    func testChoosingAgainForTheSameSlotReplacesTheAction() {
        var subject = battle(mine: [snapshot(1), snapshot(2)],
                             opponents: [snapshot(90), snapshot(91)])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(subject.choose(.move(index: 0, target: 1), forSlot: 0))
        XCTAssertEqual(subject.pendingActions[0], .move(index: 0, target: 1))
        XCTAssertEqual(subject.turn, 1)
    }

    // MARK: 타겟팅

    /// 고른 타겟만 맞는다. 타겟을 못 고르던 시절엔 늘 앞 상대만 때려서, 뒤에 선 상대가
    /// 전투가 끝날 때까지 만피로 서 있었다.
    func testMoveHitsTheChosenTarget() {
        var subject = battle(mine: [snapshot(1, speed: 300)],
                             opponents: [snapshot(90, speed: 1), snapshot(91, speed: 1)])
        let untouched = subject.opponents[0].hp
        XCTAssertTrue(subject.choose(.move(index: 0, target: 1), forSlot: 0))
        XCTAssertEqual(subject.opponents[0].hp, untouched, "고르지 않은 상대는 맞지 않는다")
        XCTAssertLessThan(subject.opponents[1].hp, subject.opponents[1].stats.hp)
    }

    /// 내가 고른 타겟이 **그 턴 앞순서에** 쓰러지면 남은 상대로 돌려 때린다. 본가 3세대 이후와
    /// 같은 규칙이다 — 돌리지 않으면 두 칸이 같은 상대를 고른 턴의 뒤 칸이 통째로 헛돈다.
    func testAttackIsRedirectedWhenTheChosenTargetAlreadyFainted() {
        var subject = battle(mine: [snapshot(1, power: 200, speed: 300),
                                    snapshot(2, power: 200, speed: 200)],
                             opponents: [snapshot(90, hp: 1, speed: 1),
                                         snapshot(91, hp: 200, speed: 1)])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertFalse(subject.opponents[0].isAlive)
        XCTAssertLessThan(subject.opponents[1].hp, subject.opponents[1].stats.hp,
                          "쓰러진 타겟을 고른 뒤 칸은 남은 상대를 때린다")
    }

    /// 범위 밖 타겟은 입력 자체가 거부된다 — 화면이 어긋난 인덱스를 보내도 크래시하지 않는다.
    func testOutOfRangeTargetIsRejected() {
        var subject = battle(mine: [snapshot(1)], opponents: [snapshot(90), snapshot(91)])
        XCTAssertFalse(subject.choose(.move(index: 0, target: 2), forSlot: 0))
        XCTAssertFalse(subject.choose(.move(index: 0, target: -1), forSlot: 0))
        XCTAssertEqual(subject.turn, 1)
    }

    // MARK: 광역기

    /// `all-opponents`(암석봉인 부류)는 상대 두 칸을 **한 방에** 때린다. 범위 데이터가 없던 동안은
    /// 모든 기술이 단일 타겟이라 2대2 에서 상대 하나가 늘 온전했다.
    func testAllOpponentsHitsBothFoes() {
        var subject = battle(mine: [spreadSnapshot(1, target: "all-opponents", speed: 300)],
                             opponents: [snapshot(90, speed: 1), snapshot(91, speed: 1)])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertLessThan(subject.opponents[0].hp, subject.opponents[0].stats.hp)
        XCTAssertLessThan(subject.opponents[1].hp, subject.opponents[1].stats.hp)
    }

    /// 기술명 줄(`.move`)은 대상 수와 무관하게 **한 번**이다. 대상마다 `applyAttack` 을 부르면
    /// 로그에 같은 기술이 두 줄 남고, 행동 가능 판정(마비·잠듦)도 두 번 굴러 rng 가 흔들린다.
    func testASpreadMoveLogsOneMoveLine() {
        var subject = battle(mine: [spreadSnapshot(1, target: "all-opponents", speed: 300)],
                             opponents: [snapshot(90, speed: 1), snapshot(91, speed: 1)])
        let myActor = BattleActor.fighter(subject.myField[0].id)
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        let myMoveLines = subject.events.filter {
            if case .move(myActor, _) = $0 { return true } else { return false }
        }
        XCTAssertEqual(myMoveLines.count, 1)
    }

    /// 둘을 때리면 데미지가 **0.75 배**다(본가 4세대 이후). 감쇠가 없으면 광역기가 같은 위력으로
    /// 두 배로 닿아 단일기를 고를 이유가 사라진다.
    func testSpreadDamageIsReducedWhenItHitsMoreThanOne() {
        var double = battle(mine: [spreadSnapshot(1, target: "all-opponents", speed: 300)],
                            opponents: [snapshot(90, speed: 1), snapshot(91, speed: 1)])
        XCTAssertTrue(double.choose(.move(index: 0, target: 0), forSlot: 0))
        let spreadDamage = double.opponents[0].stats.hp - double.opponents[0].hp

        // 같은 seed·같은 개체로 단일 타겟만 남긴 판. 상대가 하나면 감쇠가 걸리지 않는다.
        var single = battle(mine: [spreadSnapshot(1, target: "all-opponents", speed: 300)],
                            opponents: [snapshot(90, speed: 1)])
        XCTAssertTrue(single.choose(.move(index: 0, target: 0), forSlot: 0))
        let fullDamage = single.opponents[0].stats.hp - single.opponents[0].hp

        XCTAssertGreaterThan(fullDamage, 0)
        XCTAssertLessThan(spreadDamage, fullDamage, "둘을 때린 쪽이 약해야 한다")
    }

    /// `all-other-pokemon`(지진 부류)은 **아군도 맞는다.** 아군을 빼면 2대2 에서 지진이 대가 없는
    /// 최강 기술이 된다.
    func testAllOtherPokemonAlsoHitsMyPartner() {
        // 상대 위력을 0 으로 둔다 — 상대가 때리면 시전자가 **자기** 지진에 맞았는지 구별할 수 없다.
        var subject = battle(mine: [spreadSnapshot(1, target: "all-other-pokemon", speed: 300),
                                    snapshot(2, hp: 400, speed: 1)],
                             opponents: [snapshot(90, power: 0, speed: 1),
                                         snapshot(91, power: 0, speed: 1)])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertLessThan(subject.mine[1].hp, subject.mine[1].stats.hp, "아군이 맞는다")
        XCTAssertEqual(subject.mine[0].hp, subject.mine[0].stats.hp, "시전자는 안 맞는다")
    }

    /// 상대가 하나뿐이면 광역기도 감쇠 없이 그 하나만 때린다 — 대상이 없는 턴에 "둘을 때리는 대가"
    /// 를 물리면 안 된다.
    func testASpreadMoveHitsOneFoeAtFullPower() {
        var subject = battle(mine: [spreadSnapshot(1, target: "all-opponents", speed: 300)],
                             opponents: [snapshot(90, speed: 1)])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertLessThan(subject.opponents[0].hp, subject.opponents[0].stats.hp)
    }

    /// 범위 데이터가 없는 기술(옛 세이브·구버전 피어·합성 무브셋)은 **단일 타겟**이다 —
    /// 모르는 기술을 광역으로 승격하면 위력 있는 기술 하나가 조용히 두 배로 닿는다.
    func testAMoveWithoutTargetDataStaysSingleTarget() {
        var subject = battle(mine: [snapshot(1, power: 60, speed: 300)],
                             opponents: [snapshot(90, speed: 1), snapshot(91, speed: 1)])
        XCTAssertNil(subject.mine[0].moves[0].target, "테스트 전제: 대상 데이터가 없어야 한다")
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertEqual(subject.opponents[1].hp, subject.opponents[1].stats.hp)
    }

    // MARK: 턴 순서

    /// 네 명이 스피드 순으로 움직인다. 편(내 편/상대 편)으로 묶어 돌리면 느린 내 개체가
    /// 빠른 상대보다 먼저 때려 스피드가 값을 잃는다.
    func testTurnOrderSortsAllFourBySpeed() {
        var subject = battle(mine: [snapshot(1, speed: 400), snapshot(2, speed: 100)],
                             opponents: [snapshot(90, speed: 300), snapshot(91, speed: 200)])
        let expected: [BattleActor] = [.fighter(subject.myField[0].id),
                                       .fighter(subject.opponentField[0].id),
                                       .fighter(subject.opponentField[1].id),
                                       .fighter(subject.myField[1].id)]
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))
        let movers = subject.events.compactMap { event -> BattleActor? in
            guard case .move(let actor, _) = event else { return nil }
            return actor
        }
        XCTAssertEqual(movers, expected)
    }

    // MARK: 기절 슬롯

    /// 쓰러진 칸은 **공짜로** 벤치에서 채운다(본가와 같다). 교체에 턴을 물리던 1대1 규칙을 그대로
    /// 쓰면 2대2 에서 한 마리를 잃을 때마다 남은 한 마리가 둘을 상대로 한 턴을 더 헌납한다.
    func testFaintedSlotIsRefilledForFreeFromTheBench() {
        var subject = battle(mine: [snapshot(1), snapshot(2, hp: 600), snapshot(3, hp: 600)],
                             opponents: [snapshot(90, power: 1, speed: 1),
                                         snapshot(91, power: 1, speed: 1)])
        // 턴 끝 독뎀으로 눕는다 — 상대 타겟 추첨(무작위)에 기대지 않고 1번 칸만 확실히 쓰러뜨린다.
        subject.mine[0].status = .poison
        subject.mine[0].hp = 1
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertFalse(subject.mine[0].isAlive)
        XCTAssertEqual(subject.slotsNeedingSendOut, [0])
        XCTAssertTrue(subject.slotsAwaitingAction.isEmpty,
                      "채워야 할 칸이 있으면 그 칸을 채우기 전에는 행동을 받지 않는다")

        let turnBefore = subject.turn
        XCTAssertTrue(subject.sendOut(teamIndex: 2, toSlot: 0))
        XCTAssertEqual(subject.turn, turnBefore, "기절 교체는 턴을 쓰지 않는다")
        XCTAssertEqual(subject.myField[0].teamIndex, 2)
        XCTAssertTrue(subject.events.contains(.sendOut(.fighter(subject.myField[0].id), teamIndex: 2)))
    }

    /// 이미 다른 칸에 서 있는 개체로는 채울 수 없다 — 한 개체가 두 칸을 먹으면 그 개체가
    /// 한 턴에 두 번 움직이고 데미지도 두 몫으로 들어간다.
    func testSendOutRejectsAMemberAlreadyOnTheField() {
        var subject = battle(mine: [snapshot(1), snapshot(2, hp: 600), snapshot(3, hp: 600)],
                             opponents: [snapshot(90, power: 1, speed: 1),
                                         snapshot(91, power: 1, speed: 1)])
        subject.mine[0].status = .poison
        subject.mine[0].hp = 1
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertFalse(subject.sendOut(teamIndex: 1, toSlot: 0))
    }

    /// 벤치가 비었으면 그 칸은 빈 칸으로 남고 남은 칸만 싸운다 — 채울 데가 없다고 판이
    /// 멈추지는 않는다.
    func testSlotStaysEmptyWhenTheBenchIsGone() {
        var subject = battle(mine: [snapshot(1), snapshot(2, hp: 600)],
                             opponents: [snapshot(90, power: 1, speed: 1),
                                         snapshot(91, power: 1, speed: 1)])
        subject.mine[0].status = .poison
        subject.mine[0].hp = 1
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertFalse(subject.mine[0].isAlive)
        XCTAssertTrue(subject.slotsNeedingSendOut.isEmpty)
        XCTAssertEqual(subject.slotsAwaitingAction, [1], "살아 있는 칸만 행동을 정한다")
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertEqual(subject.turn, 3)
    }

    /// 상대는 벤치를 자동으로 내보낸다 — 고를 사람이 없다.
    func testOpponentBenchSendsItselfOut() {
        var subject = battle(mine: [snapshot(1, power: 200, speed: 300)],
                             opponents: [snapshot(90, hp: 1, speed: 1), snapshot(91, hp: 1, speed: 1),
                                         snapshot(92, speed: 1)])
        XCTAssertEqual(subject.opponentField.map(\.teamIndex), [0, 1])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertFalse(subject.opponents[0].isAlive)
        XCTAssertEqual(subject.opponentField[0].teamIndex, 2, "벤치가 그 자리에 들어온다")
        XCTAssertNil(subject.result)
    }

    // MARK: 승부

    /// 상대 둘을 다 눕혀야 승리다. 하나만 눕히고 이기던 시절이 곧 연전 구조였다.
    func testWinNeedsBothOpponentsDown() {
        var subject = battle(mine: [snapshot(1, power: 300, speed: 300)],
                             opponents: [snapshot(90, hp: 1, speed: 1), snapshot(91, hp: 1, speed: 1)])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertNil(subject.result, "한 마리가 남아 있으면 아직 승리가 아니다")
        XCTAssertTrue(subject.choose(.move(index: 0, target: 1), forSlot: 0))
        XCTAssertEqual(subject.result, .win)
    }

    /// 파티 전멸은 패배다. 양쪽이 같은 턴에 전멸하면 무승부다 — 1대1(`resolveIfReady`)·
    /// 팀 연습과 같은 규칙을 본다.
    func testWipeIsALossAndSimultaneousWipeIsADraw() {
        var loss = battle(mine: [snapshot(1, hp: 1)],
                          opponents: [snapshot(90, power: 300, speed: 300)])
        XCTAssertTrue(loss.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertEqual(loss.result, .loss)

        var draw = battle(mine: [snapshot(1, hp: 1, power: 300, speed: 300)],
                          opponents: [snapshot(90, hp: 1, power: 300, speed: 1)])
        draw.mine[0].status = .poison       // 내 공격이 상대를 눕히고, 턴 끝 독뎀이 나를 눕힌다
        draw.mine[0].hp = 1
        XCTAssertTrue(draw.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertEqual(draw.result, .draw)
    }

    /// 포획으로 상대를 뺀다 — 쓰러뜨린 것과 **같은 자리**를 지난다. 둘 중 하나만 잡았으면
    /// 전투는 이어지고, 마지막 하나를 잡으면 승리다.
    func testRetiringOpponentsMirrorsFainting() {
        var subject = battle(mine: [snapshot(1)], opponents: [snapshot(90), snapshot(91)])
        subject.retireOpponent(atSlot: 1)
        XCTAssertNil(subject.result)
        XCTAssertFalse(subject.opponents[1].isAlive)
        subject.retireOpponent(atSlot: 0)
        XCTAssertEqual(subject.result, .win)
    }

    /// 볼을 던지면 **내 편 전원이** 그 턴을 쓴다. 한 칸만 헌납하는 값으로 두면 2대2 에서
    /// 볼 던지기가 사실상 공짜가 된다(남은 칸이 그 턴에도 때린다).
    func testSpendingTheTurnLetsEveryOpponentAttack() {
        var subject = battle(mine: [snapshot(1, hp: 400), snapshot(2, hp: 400)],
                             opponents: [snapshot(90, power: 100, speed: 1),
                                         snapshot(91, power: 100, speed: 1)])
        let before = subject.mine[0].hp + subject.mine[1].hp
        XCTAssertTrue(subject.spendTurnWithoutAttacking())
        XCTAssertEqual(subject.turn, 2)
        XCTAssertLessThan(subject.mine[0].hp + subject.mine[1].hp, before)
        let movers = subject.events.filter { if case .move = $0 { return true } else { return false } }
        XCTAssertEqual(movers.count, 2, "내 칸은 한 번도 움직이지 않는다")
    }

    /// 교체는 **그 칸의 행동이다** — 교체한 칸은 그 턴에 때리지 못한다(1대1 규칙과 같다).
    func testDeliberateSwitchCostsThatSlotsAction() {
        var subject = battle(mine: [snapshot(1), snapshot(2), snapshot(3)],
                             opponents: [snapshot(90, speed: 1), snapshot(91, speed: 1)])
        XCTAssertTrue(subject.choose(.switchTo(teamIndex: 2), forSlot: 0))
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 1))
        XCTAssertEqual(subject.myField[0].teamIndex, 2)
        let myMoves = subject.events.filter {
            if case .move(.fighter(subject.myField[0].id), _) = $0 { return true } else { return false }
        }
        XCTAssertTrue(myMoves.isEmpty, "교체한 칸은 공격하지 않는다")
    }

    /// 끝난 전투는 어떤 입력도 받지 않는다 — 결과가 적힌 뒤 한 턴이 더 돌면 승패가 뒤집힌다.
    func testFinishedBattleIgnoresInput() {
        var subject = battle(mine: [snapshot(1, hp: 1)],
                             opponents: [snapshot(90, power: 300, speed: 300)])
        XCTAssertTrue(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertEqual(subject.result, .loss)
        XCTAssertFalse(subject.choose(.move(index: 0, target: 0), forSlot: 0))
        XCTAssertFalse(subject.spendTurnWithoutAttacking())
        XCTAssertFalse(subject.sendOut(teamIndex: 0, toSlot: 0))
    }
}
