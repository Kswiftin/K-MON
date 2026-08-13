import Foundation

/// 관전자 한 명의 베팅 한 건. 관전자당 1건만 유지되며, 새 베팅은 이전 것을 대체한다.
struct PokeathlonBet: Codable, Sendable, Equatable {
    let bettorID: UUID
    var runnerID: UUID
    var amount: Int
}

/// 포켓슬론 관전자 베팅 원장. 파리뮤추얼 — 우승 러너에 건 관전자들이 전체 판돈을
/// 자기 지분대로 나눠 갖는다. 별조각은 관전자 사이에서만 이동하고 새로 생성되지 않는다.
///
/// `payouts` 는 순수 함수다: 같은 입력이면 어느 Mac 에서도 같은 결과가 나온다.
/// 그래서 호스트 계산을 각 클라이언트가 재계산해 검증할 수 있다(정산 위조 차단).
struct PokeathlonPool: Codable, Sendable, Equatable {
    /// key = bettorID — 관전자당 한 건만 담기게 하는 자료구조 차원의 보장.
    var bets: [UUID: PokeathlonBet] = [:]
    var isClosed = false

    var total: Int { bets.values.reduce(0) { $0 + $1.amount } }

    /// 우승자에 건 베팅들이 전체 판돈을 지분대로 분배. 아무도 우승자를 안 골랐거나
    /// `winnerID == nil`(경기 미완주)이면 전원 자기 판돈 그대로 환불.
    /// 정수 나눗셈 잔여분은 금액 큰 순 → 동률이면 bettorID(uuidString) 오름차순으로 1개씩.
    func payouts(winnerID: UUID?) -> [UUID: Int] {
        let winners = winnerID.map { winner in bets.values.filter { $0.runnerID == winner } } ?? []
        guard !winners.isEmpty else { return bets.mapValues(\.amount) }   // 환불(= 원금 지급)

        let pot = total
        let backed = winners.reduce(0) { $0 + $1.amount }
        var payouts: [UUID: Int] = [:]
        for bet in winners { payouts[bet.bettorID] = pot * bet.amount / backed }

        // 잔여 별조각 — 무작위 없이 고정 순서로 1개씩. UUID 는 Comparable 이 아니라 uuidString 비교.
        let order = winners.sorted {
            $0.amount == $1.amount ? $0.bettorID.uuidString < $1.bettorID.uuidString : $0.amount > $1.amount
        }
        var remainder = pot - payouts.values.reduce(0, +)
        var cursor = 0
        while remainder > 0 {
            payouts[order[cursor % order.count].bettorID, default: 0] += 1
            remainder -= 1
            cursor += 1
        }
        return payouts
    }
}
