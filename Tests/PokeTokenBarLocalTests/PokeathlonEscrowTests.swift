import Foundation
import Testing
@testable import PokeTokenBar

/// 베팅 원장에 남은 항목은 전부 **누군가 실제로 낸 별조각**이어야 한다. 호스트가 보는 상한은
/// 참가할 때 신고한 잔액이라, 로비에서 별조각을 쓴 뒤 베팅하면 호스트는 통과시키는데 판돈이
/// 실제로는 빠져나가지 않는다. 그 항목이 원장에 남으면 배당이 없는 돈을 나눠 별조각이 생성된다.
@Suite struct PokeathlonEscrowTests {
    private func bet(_ bettor: UUID, runner: UUID, amount: Int) -> PokeathlonBet {
        PokeathlonBet(bettorID: bettor, runnerID: runner, amount: amount)
    }

    @Test func anUnfundedBetLeavesTheOpenLedger() {
        let runner = UUID(), payer = UUID(), deadbeat = UUID()
        var pool = PokeathlonPool()
        pool.bets[payer] = bet(payer, runner: runner, amount: 100)
        pool.bets[deadbeat] = bet(deadbeat, runner: runner, amount: 500)

        let cleaned = pool.withoutUnfundedBet(of: deadbeat)

        #expect(cleaned.bets[deadbeat] == nil)
        #expect(cleaned.bets[payer] != nil, "남의 베팅은 건드리지 않는다")
        #expect(cleaned.total == 100)
        // 판돈 총액과 배당 총액이 같아야 별조각이 생성되지 않는다.
        #expect(cleaned.payouts(winnerID: runner).values.reduce(0, +) == cleaned.total)
    }

    /// 잠긴 원장에서는 빼지 않는다 — 배당 계산이 이미 그 판돈을 세고 있어, 빼면 남은 사람들의
    /// 배당이 소리 없이 늘어난다.
    @Test func aClosedLedgerIsNeverEdited() {
        let runner = UUID(), bettor = UUID()
        var pool = PokeathlonPool()
        pool.bets[bettor] = bet(bettor, runner: runner, amount: 100)
        pool.isClosed = true

        #expect(pool.withoutUnfundedBet(of: bettor) == pool)
    }
}
