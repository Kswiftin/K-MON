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

    // MARK: 호스트측 베팅 수용 검사 (순수 — 네트워크 없이 전 분기 검증)

    private func racer(_ n: Int) -> PokeathlonRacer {
        PokeathlonRacer(id: id(n), trainerName: "R\(n)", speciesID: 25)
    }

    private func member(_ n: Int, role: LobbyRole, wallet: Int) -> LobbyParticipant {
        LobbyParticipant(id: id(n), trainerName: "T\(n)", speciesID: 25, team: .solo,
                         isReady: true, isHost: false, role: role, reportedStarPieces: wallet)
    }

    /// 러너 10·11, 관전자 1(잔액 100). 레이스는 t+10초 시작.
    private func fixture() throws -> (lobby: MultiplayerLobby, race: PokeathlonRace, start: Date) {
        var lobby = try MultiplayerLobby(host: member(10, role: .runner, wallet: 0),
                                         capacity: 4, activity: .pokeathlon)
        try lobby.join(member(11, role: .runner, wallet: 0))
        try lobby.join(member(1, role: .spectator, wallet: 100))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var race = PokeathlonRace(racers: [racer(10), racer(11)])
        race.startsAt = start
        return (lobby, race, start)
    }

    func testValidSpectatorBetIsAccepted() throws {
        let f = try fixture()
        let bet = PokeathlonBet(bettorID: id(1), runnerID: id(10), amount: 100)
        XCTAssertNil(PokeathlonPool.rejection(for: bet, senderID: id(1), lobby: f.lobby, race: f.race,
                                              pool: PokeathlonPool(), now: f.start.addingTimeInterval(-1)))
    }

    func testBetUnderAnotherParticipantsIDIsRejected() throws {
        let f = try fixture()
        // 관전자 1이 관전자 2의 ID 로 베팅을 보낸 상황 — 연결의 참가자 ID 와 불일치.
        let bet = PokeathlonBet(bettorID: id(2), runnerID: id(10), amount: 10)
        XCTAssertEqual(PokeathlonPool.rejection(for: bet, senderID: id(1), lobby: f.lobby, race: f.race,
                                                pool: PokeathlonPool(), now: f.start.addingTimeInterval(-1)),
                       .identityMismatch)
    }

    func testBetFromARunnerIsRejected() throws {
        let f = try fixture()
        let bet = PokeathlonBet(bettorID: id(11), runnerID: id(10), amount: 10)
        XCTAssertEqual(PokeathlonPool.rejection(for: bet, senderID: id(11), lobby: f.lobby, race: f.race,
                                                pool: PokeathlonPool(), now: f.start.addingTimeInterval(-1)),
                       .notSpectator)
    }

    func testBetFromANonMemberIsRejected() throws {
        let f = try fixture()
        let bet = PokeathlonBet(bettorID: id(99), runnerID: id(10), amount: 10)
        XCTAssertEqual(PokeathlonPool.rejection(for: bet, senderID: id(99), lobby: f.lobby, race: f.race,
                                                pool: PokeathlonPool(), now: f.start.addingTimeInterval(-1)),
                       .notSpectator)
    }

    func testBetAfterStartIsRejected() throws {
        let f = try fixture()
        let bet = PokeathlonBet(bettorID: id(1), runnerID: id(10), amount: 10)
        XCTAssertEqual(PokeathlonPool.rejection(for: bet, senderID: id(1), lobby: f.lobby, race: f.race,
                                                pool: PokeathlonPool(), now: f.start),
                       .poolClosed)
    }

    func testBetIntoAClosedPoolIsRejectedEvenBeforeStart() throws {
        let f = try fixture()
        var closed = PokeathlonPool(); closed.isClosed = true
        let bet = PokeathlonBet(bettorID: id(1), runnerID: id(10), amount: 10)
        XCTAssertEqual(PokeathlonPool.rejection(for: bet, senderID: id(1), lobby: f.lobby, race: f.race,
                                                pool: closed, now: f.start.addingTimeInterval(-5)),
                       .poolClosed)
    }

    func testNonPositiveAmountIsRejected() throws {
        let f = try fixture()
        for amount in [0, -50] {
            let bet = PokeathlonBet(bettorID: id(1), runnerID: id(10), amount: amount)
            XCTAssertEqual(PokeathlonPool.rejection(for: bet, senderID: id(1), lobby: f.lobby, race: f.race,
                                                    pool: PokeathlonPool(), now: f.start.addingTimeInterval(-1)),
                           .invalidAmount)
        }
    }

    func testBetOnSomeoneWhoIsNotRacingIsRejected() throws {
        let f = try fixture()
        let bet = PokeathlonBet(bettorID: id(1), runnerID: id(1), amount: 10)   // 자기 자신(관전자)에 베팅
        XCTAssertEqual(PokeathlonPool.rejection(for: bet, senderID: id(1), lobby: f.lobby, race: f.race,
                                                pool: PokeathlonPool(), now: f.start.addingTimeInterval(-1)),
                       .unknownRunner)
    }

    func testBetAboveTheBalanceReportedAtJoinIsRejected() throws {
        let f = try fixture()
        let bet = PokeathlonBet(bettorID: id(1), runnerID: id(10), amount: 101)   // 신고 잔액 100
        XCTAssertEqual(PokeathlonPool.rejection(for: bet, senderID: id(1), lobby: f.lobby, race: f.race,
                                                pool: PokeathlonPool(), now: f.start.addingTimeInterval(-1)),
                       .insufficientBalance)
    }

    // MARK: 정산 검증 — 호스트 원장이 내가 본 내 베팅과 다르면 거부

    func testAgreementRequiresMyOwnBetToMatchWhatISaw() {
        let mine = PokeathlonBet(bettorID: id(1), runnerID: id(10), amount: 40)
        var pool = PokeathlonPool(); pool.bets[id(1)] = mine
        XCTAssertTrue(pool.agreesWithSeenBet(mine, bettorID: id(1)))

        // 호스트가 내 금액을 바꿔치기
        var tampered = pool
        tampered.bets[id(1)] = PokeathlonBet(bettorID: id(1), runnerID: id(10), amount: 400)
        XCTAssertFalse(tampered.agreesWithSeenBet(mine, bettorID: id(1)))

        // 호스트가 내 러너를 바꿔치기
        var switched = pool
        switched.bets[id(1)] = PokeathlonBet(bettorID: id(1), runnerID: id(11), amount: 40)
        XCTAssertFalse(switched.agreesWithSeenBet(mine, bettorID: id(1)))

        // 내가 걸지 않은 베팅이 호스트 원장에 등장
        XCTAssertFalse(pool.agreesWithSeenBet(nil, bettorID: id(1)))

        // 내가 걸었는데 호스트 원장에서 사라짐
        XCTAssertFalse(PokeathlonPool().agreesWithSeenBet(mine, bettorID: id(1)))

        // 남의 베팅이 늘어난 것은 파리뮤추얼상 정상 — 내 배당은 재계산으로 검증된다.
        var others = pool
        others.bets[id(2)] = PokeathlonBet(bettorID: id(2), runnerID: id(11), amount: 5)
        XCTAssertTrue(others.agreesWithSeenBet(mine, bettorID: id(1)))
    }
}
