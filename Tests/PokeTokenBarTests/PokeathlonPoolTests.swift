import XCTest
@testable import PokeTokenBar

// MARK: 관전자 베팅 원장 — 파리뮤추얼 배당(순수 로직)

final class PokeathlonPoolTests: XCTestCase {

    /// uuidString 오름차순이 결정적이도록 앞자리를 고정한 UUID 를 만든다.
    /// 잔여 별조각 분배가 "금액 큰 순 → 동률이면 bettorID 오름차순" 인지 검증하는 데 필요.
    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "%08X-0000-0000-0000-000000000000", n))!
    }

    private func pool(_ entries: [(bettor: Int, runner: Int, amount: Int)]) -> PokeathlonPool {
        var pool = PokeathlonPool()
        for e in entries {
            let bet = PokeathlonBet(bettorID: id(e.bettor), runnerID: id(e.runner), amount: e.amount)
            pool.bets[bet.bettorID] = bet
        }
        return pool
    }

    // MARK: 정상 분배

    func testWinnersSplitWholePotByStake() {
        // 승자(러너 10)에 100·50, 패자에 150 → 판돈 300, 승자 지분 100:50 = 200:100.
        let p = pool([(1, 10, 100), (2, 10, 50), (3, 20, 150)])
        let payouts = p.payouts(winnerID: id(10))
        XCTAssertEqual(payouts[id(1)], 200)
        XCTAssertEqual(payouts[id(2)], 100)
        XCTAssertNil(payouts[id(3)])                 // 패자는 항목 없음(= 0 지급)
        XCTAssertEqual(payouts.values.reduce(0, +), p.total)
    }

    // MARK: 잔여 별조각 — 결정적 분배

    func testRemainderGoesToLargestStakeFirstThenAscendingBettorID() {
        // 판돈 10, 승자 지분 1:1:1 → 각 3, 잔여 1 → 금액 동률이므로 bettorID 오름차순 첫 번째.
        let p = pool([(2, 10, 1), (1, 10, 1), (3, 10, 1), (4, 20, 7)])
        let payouts = p.payouts(winnerID: id(10))
        XCTAssertEqual(payouts[id(1)], 4)
        XCTAssertEqual(payouts[id(2)], 3)
        XCTAssertEqual(payouts[id(3)], 3)
        XCTAssertEqual(payouts.values.reduce(0, +), 10)
    }

    func testRemainderPrefersLargerStakeOverSmallerBettorID() {
        // 판돈 10, 승자 지분 3:1 → 7:2, 잔여 1 → 금액 큰 쪽(id 2)이 먼저 받는다.
        let p = pool([(1, 10, 1), (2, 10, 3), (3, 20, 6)])
        let payouts = p.payouts(winnerID: id(10))
        XCTAssertEqual(payouts[id(2)], 8)
        XCTAssertEqual(payouts[id(1)], 2)
        XCTAssertEqual(payouts.values.reduce(0, +), 10)
    }

    // MARK: 환불 경로

    func testRefundsEveryoneWhenNobodyBackedTheWinner() {
        let p = pool([(1, 20, 40), (2, 30, 60)])
        let payouts = p.payouts(winnerID: id(10))
        XCTAssertEqual(payouts[id(1)], 40)
        XCTAssertEqual(payouts[id(2)], 60)
        XCTAssertEqual(payouts.values.reduce(0, +), p.total)
    }

    func testRefundsEveryoneWhenRaceNeverFinished() {
        let p = pool([(1, 10, 40), (2, 20, 60)])
        let payouts = p.payouts(winnerID: nil)
        XCTAssertEqual(payouts[id(1)], 40)
        XCTAssertEqual(payouts[id(2)], 60)
        XCTAssertEqual(payouts.values.reduce(0, +), p.total)
    }

    func testEmptyPoolPaysNothing() {
        XCTAssertTrue(PokeathlonPool().payouts(winnerID: id(10)).isEmpty)
        XCTAssertEqual(PokeathlonPool().total, 0)
    }

    // MARK: 불변식 — 별조각은 이동만, 생성 없음

    func testTotalIsPreservedAcrossManyShapes() {
        let shapes: [[(bettor: Int, runner: Int, amount: Int)]] = [
            [(1, 10, 7)],
            [(1, 10, 7), (2, 10, 11), (3, 10, 13)],
            [(1, 10, 1), (2, 20, 1), (3, 30, 1)],
            [(1, 10, 999), (2, 20, 1)],
        ]
        for shape in shapes {
            let p = pool(shape)
            for winner in [id(10), id(20), id(30), id(99)] {
                XCTAssertEqual(p.payouts(winnerID: winner).values.reduce(0, +), p.total,
                               "판돈 보존 실패: \(shape) / winner \(winner)")
            }
            XCTAssertEqual(p.payouts(winnerID: nil).values.reduce(0, +), p.total)
        }
    }
}
