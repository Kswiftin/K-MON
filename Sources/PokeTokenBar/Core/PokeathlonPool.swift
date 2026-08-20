import Foundation

/// 관전자 한 명의 베팅 한 건. 관전자당 1건만 유지되며, 새 베팅은 이전 것을 대체한다.
struct PokeathlonBet: Codable, Sendable, Equatable {
    let bettorID: UUID
    var runnerID: UUID
    var amount: Int
}

/// 원장은 **호스트가 보내오는 값이다** — 게스트는 `.pokeathlonPool`/`.pokeathlonSettlement` 를 그대로
/// 받아 `payouts` 를 다시 계산한다. 그래서 상한은 호스트측 `rejection` 이 아니라 **디코딩 경계**에
/// 있어야 한다. 여기 없으면 조작된 호스트가 `Int.max` 한 건으로 모든 게스트를 오버플로 트랩으로
/// 죽인다(`rejection` 은 호스트 자기 자신만 통과시킨다).
extension PokeathlonBet {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bettorID = try c.decode(UUID.self, forKey: .bettorID)
        runnerID = try c.decode(UUID.self, forKey: .runnerID)
        amount = min(PokeathlonPool.maximumBet, max(0, try c.decode(Int.self, forKey: .amount)))
    }
}

extension PokeathlonPool {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ledger = try c.decodeIfPresent([UUID: PokeathlonBet].self, forKey: .bets) ?? [:]
        // 건당 상한만으론 `pot` 이 안 묶인다 — 정원보다 많은 베팅이 오면 `pot × amount` 가 다시
        // 넘친다. 관전자 정원을 넘는 원장은 정상 경로로 만들 수 없으므로 통째로 버린다.
        bets = ledger.count <= MultiplayerLobby.spectatorCapacity ? ledger : [:]
        isClosed = try c.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false
    }
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

    /// 베팅 상한 — `payouts` 의 `pot * bet.amount` 가 오버플로 트랩나지 않는 값.
    /// pot ≤ 관전자 정원(8) × 상한이므로 `8 × 상한² < Int.max` 여야 한다. 10^9 은 8×10^18 로 여유가
    /// 없어 10^8 을 쓴다 — 랭크전 판돈 최대(45,000)의 2,000배가 넘어 정상 플레이는 닿지 않는다.
    ///
    /// 상한이 필요한 이유: 수용 검사가 `bet.amount <= member.reportedStarPieces` 만 봤고 그 잔액은
    /// 참가자가 **스스로 신고**하는 값이라 상한이 없었다. `Int.max` 한 건이 원장에 들어가면 배당
    /// 계산이 프로세스를 죽인다(defect-log "외부 수치는 경계 한 곳에서 클램프").
    static let maximumBet = 100_000_000

    var total: Int { bets.values.reduce(0) { $0 + $1.amount } }

    /// 우승자에 건 베팅들이 전체 판돈을 지분대로 분배. 아무도 우승자를 안 골랐거나
    /// `winnerID == nil`(경기 미완주)이면 전원 자기 판돈 그대로 환불.
    /// 정수 나눗셈 잔여분은 금액 큰 순 → 동률이면 bettorID(uuidString) 오름차순으로 1개씩.
    ///
    /// `amount > 0` 도 함께 걸러야 한다 — 디코딩 클램프가 음수·0 을 **0 으로 만들어** 원장에 남기므로
    /// 우승자에 걸린 게 0 원 베팅뿐이면 `backed == 0` 이 되어 `pot * amount / backed` 가 0 나눗셈
    /// 트랩으로 프로세스를 죽인다(호스트측 `rejection` 의 `amount > 0` 은 와이어 원장엔 안 걸린다).
    func payouts(winnerID: UUID?) -> [UUID: Int] {
        let winners = winnerID.map { winner in
            bets.values.filter { $0.runnerID == winner && $0.amount > 0 }
        } ?? []
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

/// 호스트가 베팅을 거절하는 이유. UI 문구와 테스트가 같은 값을 본다.
enum PokeathlonBetRejection: Error, Equatable {
    case identityMismatch, notSpectator, poolClosed, invalidAmount, unknownRunner, insufficientBalance
}

extension PokeathlonPool {
    /// 호스트측 베팅 수용 검사. `nil` 이면 수용. 순수 함수라 네트워크 없이 전 분기를 테스트할 수 있다.
    ///
    /// - `senderID` 는 연결에서 확인된 참가자 ID(위조 불가). `bet.bettorID` 가 이것과 다르면
    ///   남의 ID 로 베팅하려는 시도다.
    /// - 러너는 아예 베팅할 수 없다 — 승부를 조작해 이득 보는 경로를 만들기 전에 막는다.
    static func rejection(for bet: PokeathlonBet, senderID: UUID, lobby: MultiplayerLobby,
                          race: PokeathlonRace, pool: PokeathlonPool, now: Date) -> PokeathlonBetRejection? {
        guard bet.bettorID == senderID else { return .identityMismatch }
        guard let member = lobby.participants.first(where: { $0.id == senderID }),
              member.role == .spectator else { return .notSpectator }
        guard !pool.isClosed, now < race.startsAt else { return .poolClosed }
        guard bet.amount > 0, bet.amount <= maximumBet else { return .invalidAmount }
        guard race.racers.contains(where: { $0.id == bet.runnerID }) else { return .unknownRunner }
        guard bet.amount <= member.reportedStarPieces else { return .insufficientBalance }
        return nil
    }

    /// 호스트가 보낸 원장이 "내가 본 내 베팅"과 일치하는지. 남의 베팅이 늘어난 것은 정상이고,
    /// 내 항목이 바뀌거나 없던 내 베팅이 생긴 경우만 거부한다.
    func agreesWithSeenBet(_ seen: PokeathlonBet?, bettorID: UUID) -> Bool {
        bets[bettorID] == seen
    }
}
