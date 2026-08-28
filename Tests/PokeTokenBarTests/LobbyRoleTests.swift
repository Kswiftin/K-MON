import XCTest
@testable import PokeTokenBar

// MARK: 로비 역할 — 러너/관전자 정원과 러너 전용 게임플레이 판정

final class LobbyRoleTests: XCTestCase {

    private func participant(_ n: Int, role: LobbyRole = .runner, ready: Bool = true,
                             team: BattleTeam = .solo, wallet: Int = 0) -> LobbyParticipant {
        LobbyParticipant(id: UUID(uuidString: String(format: "%08X-0000-0000-0000-000000000000", n))!,
                         trainerName: "T\(n)", speciesID: 25, team: team,
                         isReady: ready, isHost: false, role: role, reportedStarPieces: wallet)
    }

    private func lobby(runnerCapacity: Int = 4) throws -> MultiplayerLobby {
        try MultiplayerLobby(host: participant(1, ready: false), capacity: runnerCapacity,
                             activity: .pokeathlon)
    }

    // MARK: 정원 — 역할별로 따로 센다

    func testRunnerCapacityRejectsFifthRunner() throws {
        var l = try lobby()
        try l.join(participant(2)); try l.join(participant(3)); try l.join(participant(4))
        XCTAssertThrowsError(try l.join(participant(5))) { error in
            XCTAssertEqual(error as? LobbyError, .runnersFull)
        }
        XCTAssertEqual(l.runners.count, 4)
    }

    func testSpectatorsJoinBeyondRunnerCapacity() throws {
        var l = try lobby()
        try l.join(participant(2)); try l.join(participant(3)); try l.join(participant(4))
        for n in 10..<18 { try l.join(participant(n, role: .spectator)) }   // 관전 8명
        XCTAssertEqual(l.runners.count, 4)
        XCTAssertEqual(l.spectators.count, 8)
        XCTAssertThrowsError(try l.join(participant(18, role: .spectator))) { error in
            XCTAssertEqual(error as? LobbyError, .spectatorsFull)
        }
    }

    func testSpectatorSlotsAreNotConsumedByRunners() throws {
        // 러너가 꽉 찬 방에도 관전은 들어갈 수 있고, 관전이 꽉 찬 방에도 러너 자리는 남는다.
        var l = try lobby(runnerCapacity: 2)
        for n in 10..<18 { try l.join(participant(n, role: .spectator)) }
        try l.join(participant(2))                                   // 러너 2번째 — 성공
        XCTAssertEqual(l.runners.count, 2)
        XCTAssertThrowsError(try l.join(participant(3))) { error in
            XCTAssertEqual(error as? LobbyError, .runnersFull)
        }
    }

    // MARK: canStart — 관전자는 시작을 막지 않는다

    func testSpectatorsNeverBlockStart() throws {
        var l = try lobby()
        l.setReady(true, participantID: participant(1).id)
        try l.join(participant(2))
        XCTAssertTrue(l.canStart)
        try l.join(participant(3, role: .spectator, ready: false))    // 미준비 관전자
        XCTAssertTrue(l.canStart, "관전자의 준비 상태가 시작을 막으면 안 된다")
    }

    func testTwoRunnersRequiredEvenWithManySpectators() throws {
        var l = try lobby()
        l.setReady(true, participantID: participant(1).id)
        for n in 10..<14 { try l.join(participant(n, role: .spectator)) }
        XCTAssertFalse(l.canStart, "러너 1명 + 관전 4명으로는 시작할 수 없다")
    }

    // MARK: 팀전 구성 — 러너만 센다

    func testTeamModeIgnoresSpectatorTeams() throws {
        var l = try MultiplayerLobby(host: participant(1, team: .red), capacity: 4, activity: .battle)
        try l.join(participant(2, team: .red)); try l.join(participant(3, team: .blue))
        try l.join(participant(4, team: .blue))
        try l.join(participant(10, role: .spectator, team: .solo))
        XCTAssertEqual(l.mode, .teams, "관전자의 solo 팀이 모드 판정을 흔들면 안 된다")
        XCTAssertTrue(l.canStart)
    }

    // MARK: 하위 호환 — role 없는 옛 payload 는 러너로 디코딩

    func testParticipantWithoutRoleDecodesAsRunner() throws {
        let json = """
        {"id":"00000001-0000-0000-0000-000000000000","trainerName":"T1","speciesID":25,
         "team":"solo","isReady":true,"isHost":false}
        """
        let decoded = try JSONDecoder().decode(LobbyParticipant.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.role, .runner)
        XCTAssertEqual(decoded.reportedStarPieces, 0)
    }

    func testParticipantRoleSurvivesRoundTrip() throws {
        let original = participant(7, role: .spectator, wallet: 120)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(LobbyParticipant.self, from: data), original)
    }

    // MARK: 와이어 계약 — 버전 상승과 새 메시지 왕복

    func testProtocolVersionIsBumpedWhenTheWireContractChanges() {
        // 옛 빌드가 레이스·배틀 중간에 깨지는 대신 핸드셰이크에서 거절되게 버전을 올린다.
        // 2 = LobbyParticipant.role + 관전자 베팅 메시지, 3 = 라운드 결과가 이벤트 스트림,
        // 4 = 상태이상(파이터에 status 필드, 스트림에 `.status`/`.cant` case),
        // 5 = 랭크(파이터에 stages 필드, 스트림에 `.boost` case), 6 = 방 채팅, 7 = 포켓몬 OX 퀴즈,
        // 8 = 드레인·반동·다단·풀린치(스트림에 `.heal`/`.multiHit` case, `Status.flinch`),
        // 9 = 특성(스냅샷에 ability 필드), 11 = 토너먼트 팀·대진·관전 상태 동기화.
        // 방은 `rulesVersion` 을 안 보므로 규칙 차이를 막을 곳이 이 값뿐이다.
        XCTAssertEqual(MultiplayerWireMessage.protocolVersion, 11)
    }

    func testBettingMessagesRoundTrip() throws {
        let bettor = UUID(); let runner = UUID()
        var pool = PokeathlonPool()
        pool.bets[bettor] = PokeathlonBet(bettorID: bettor, runnerID: runner, amount: 30)
        let messages: [MultiplayerWireMessage] = [
            .pokeathlonBet(participantID: bettor, runnerID: runner, amount: 30),
            .pokeathlonPool(pool),
            .pokeathlonSettlement(pool: pool, winnerID: runner),
            .pokeathlonSettlement(pool: pool, winnerID: nil),
        ]
        for message in messages {
            let data = try JSONEncoder().encode(message)
            XCTAssertEqual(try JSONDecoder().decode(MultiplayerWireMessage.self, from: data), message)
        }
    }
}
