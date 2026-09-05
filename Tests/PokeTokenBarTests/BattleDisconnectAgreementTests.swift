import XCTest
@testable import PokeTokenBar

/// 끊김 판정이 **양쪽에서 같은 결론**을 내는지 — 판돈 이중 지급의 마지막 창을 닫는다.
///
/// 회귀 원본(defect-log: "상태가 같으니 결론도 반대는 턴 경계에서만 참이다"). 1v1 끊김 판정은 두
/// 피어가 같은 배틀 상태를 본다는 전제로 남은 HP 비율을 비교한다. 그런데 `resolveIfReady` 는 두
/// 선택이 모이는 **즉시** 각자 해상하므로, 한쪽 행동만 도착한 채 링크가 죽으면 상태가 한 턴
/// 어긋난다. 그 창에서는 양쪽이 모두 "내가 앞선다"를 보고, 정산은 각자 자기 지갑에만 하므로
/// (`settleRankedBrawl` 은 공유 원장이 없다) 판돈이 두 지갑에 동시에 들어간다.
///
/// **양쪽 관점을 모두 밟는다.** 한쪽만 보면 이 결함은 안 보인다 — 각 피어는 자기 화면에서 늘
/// 일관돼 보이고, 어긋남은 두 관점을 나란히 놓아야만 드러난다. 이게 원래 못 걸린 이유다.
final class BattleDisconnectAgreementTests: XCTestCase {

    // MARK: 픽스처

    private func snapshot(baseHP: Int = 200) -> BattleSnapshot {
        BattleSnapshot(speciesID: 143, name: "Mon", trainer: nil, level: 50, nature: nil, isShiny: false,
                       types: [.normal],
                       base: BattleStats(hp: baseHP, atk: 60, def: 60, spa: 5, spd: 60, spe: 50),
                       moves: [MoveSpec(id: 1, names: [:], type: .normal, power: 10,
                                        damageClass: .physical, accuracy: 100, pp: 30)])
    }

    private func side(hp: Int) -> BattleSide {
        var side = BattleSide(snapshot())
        side.hp = hp
        return side
    }

    /// 턴 4 를 해상하기 **전** — A 가 앞선다(150 대 100).
    private var stateAfterTurn3: (a: [BattleSide], b: [BattleSide]) {
        (a: [side(hp: 150)], b: [side(hp: 100)])
    }

    /// 턴 4 를 해상한 **뒤** — B 의 한 방이 판을 뒤집는다(40 대 100).
    private var stateAfterTurn4: (a: [BattleSide], b: [BattleSide]) {
        (a: [side(hp: 40)], b: [side(hp: 100)])
    }

    // MARK: 결함 재현 — 지금 상태로 판정하면 양쪽이 이긴다

    /// A 의 행동은 B 에 닿았고 B 는 턴 4 를 해상했다. B 의 행동은 링크와 함께 사라져 A 는 턴 3 에
    /// 멈춰 있다. 각자 **자기 눈앞의 상태**로 판정하면 둘 다 이긴다 — 별의조각 총량이 늘어난다.
    func testJudgingOnTheLiveStateLetsBothPeersWin() {
        let three = stateAfterTurn3, four = stateAfterTurn4

        // A 의 눈: 턴 3 상태. 150 대 100 이라 내가 앞선다.
        XCTAssertEqual(BattleEngine.disconnectOutcome(me: three.a, opp: three.b), true)
        // B 의 눈: 턴 4 상태. 100 대 40 이라 내가 앞선다.
        XCTAssertEqual(BattleEngine.disconnectOutcome(me: four.b, opp: four.a), true)
    }

    // MARK: 처방 — 합의된 턴의 상태로 판정한다

    /// 두 피어가 `min(내 해상 턴, 상대가 알린 해상 턴)` 을 **같게** 계산하는 것이 처방의 근거다.
    /// A 는 3 을 해상했고 B 가 알린 값도 3(턴 4 해상 보고는 유실됐다) → 3.
    /// B 는 4 를 해상했지만 A 가 알린 값이 3 → 3. 어느 쪽에서 계산해도 같은 쌍의 min 이다.
    func testBothPeersAgreeOnTheSameTurnEvenWhenOneIsAhead() {
        var a = BattleEngine.AgreedTurnLedger()
        a.recordResolved(turn: 3, me: stateAfterTurn3.a, opp: stateAfterTurn3.b)
        a.recordPeerResolved(3)

        var b = BattleEngine.AgreedTurnLedger()
        b.recordResolved(turn: 3, me: stateAfterTurn3.b, opp: stateAfterTurn3.a)
        b.recordResolved(turn: 4, me: stateAfterTurn4.b, opp: stateAfterTurn4.a)
        b.recordPeerResolved(3)     // A 는 턴 3 까지만 해상했다고 알려 왔다

        XCTAssertEqual(a.agreedTurn, 3)
        XCTAssertEqual(b.agreedTurn, 3, "앞서 있어도 상대가 확인한 턴까지만 합의된 것이다")
    }

    /// **핵심 단언** — 같은 턴의 상태로 판정하면 결론이 정확히 반대가 된다. 한쪽만 지급받는다.
    func testJudgingOnTheAgreedTurnMakesExactlyOnePeerWin() throws {
        var a = BattleEngine.AgreedTurnLedger()
        a.recordResolved(turn: 3, me: stateAfterTurn3.a, opp: stateAfterTurn3.b)
        a.recordPeerResolved(3)

        var b = BattleEngine.AgreedTurnLedger()
        b.recordResolved(turn: 3, me: stateAfterTurn3.b, opp: stateAfterTurn3.a)
        b.recordResolved(turn: 4, me: stateAfterTurn4.b, opp: stateAfterTurn4.a)
        b.recordPeerResolved(3)

        let aState = try XCTUnwrap(a.agreedState)
        let bState = try XCTUnwrap(b.agreedState)
        let aWon = BattleEngine.disconnectOutcome(me: aState.me, opp: aState.opp)
        let bWon = BattleEngine.disconnectOutcome(me: bState.me, opp: bState.opp)

        XCTAssertEqual(aWon, true, "합의된 턴 3 에서는 A 가 앞섰다")
        XCTAssertEqual(bWon, false, "같은 턴을 보면 B 는 진 것이다 — 양쪽이 이기면 판돈이 두 번 나간다")
        XCTAssertNotEqual(aWon, bWon, "두 피어의 결론은 반드시 반대여야 한다")
    }

    /// 깨끗한 턴 경계 — 양쪽이 같은 턴을 해상하고 서로 확인까지 했다. 판정이 그대로 살아야 한다.
    /// 여기까지 환급으로 접으면 "지고 있을 때 뽑으면 무손실" 이 되살아난다(defect-log 참조).
    func testACleanBoundaryStillProducesAVerdict() throws {
        var a = BattleEngine.AgreedTurnLedger()
        a.recordResolved(turn: 4, me: stateAfterTurn4.a, opp: stateAfterTurn4.b)
        a.recordPeerResolved(4)

        let state = try XCTUnwrap(a.agreedState)
        XCTAssertEqual(state.me.first?.hp, 40, "합의된 턴은 4 다")
        XCTAssertEqual(BattleEngine.disconnectOutcome(me: state.me, opp: state.opp), false,
                       "턴 4 에서 A 는 뒤진다 — 합의됐으므로 판정을 낸다")
    }

    /// 합의된 턴이 하나도 없으면(첫 턴이 해상되기 전에 끊김) 판정하지 않는다 — 환급이다.
    func testNothingAgreedYetYieldsNoVerdict() {
        var ledger = BattleEngine.AgreedTurnLedger()
        ledger.recordResolved(turn: 1, me: stateAfterTurn3.a, opp: stateAfterTurn3.b)
        // 상대가 아무것도 확인해 주지 않았다.
        XCTAssertEqual(ledger.agreedTurn, 0)
        XCTAssertNil(ledger.agreedState, "확인되지 않은 턴으로 판정하면 다시 갈라진다")
    }

    /// 보관함이 배틀 내내 자라면 긴 배틀에서 메모리를 먹는다. 합의된 턴보다 오래된 것은 버린다.
    func testOlderTurnsAreDroppedOnceTheyAreAgreed() {
        var ledger = BattleEngine.AgreedTurnLedger()
        for turn in 1...20 {
            ledger.recordResolved(turn: turn, me: stateAfterTurn3.a, opp: stateAfterTurn3.b)
            ledger.recordPeerResolved(turn - 1)
        }
        XCTAssertLessThanOrEqual(ledger.retainedTurnCount, 2,
                                 "합의 지연은 최대 한 턴이라 두 개보다 많이 들고 있을 이유가 없다")
    }
}
