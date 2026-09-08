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
        // 9 = 특성(스냅샷에 ability 필드), 11 = 토너먼트 팀·대진·관전 상태 동기화,
        // 12 = 공유 체육관(도전·거절·상태·행동·승계),
        // 15 = LAN 협동 레이드(`.raidStart`·`.raidSettlement`, `MultiplayerBattleMode.coopBoss`),
        // 16 = 레이드 포획을 참가자별 확률·순차 공개로, 보상 원장을 오전·오후로 분리,
        // 17 = 레이드 포획 추첨에서 몰수당한(`hasLeft`) 참가자만 제외,
        // 18 = 협동 레이드 러너 정원을 4명에서 8명으로 확대,
        // 19 = `BattleEvent` 에 case 다섯 추가(볼라틸 셋·지닌물건·기술 잠금),
        // 20 = 지닌물건 4종 추가(구애스카프·화염구슬·독구슬·돌격조끼 — 구버전은 그 이름을 모르는
        //      아이템으로 접어 같은 판의 HP·순서가 갈리고, `MoveSelectionLock` 에 늘어난 case 를
        //      만나면 라운드 스트림 디코딩이 throw 한다).
        // 21 = 타입 강화 도구 22종(목탄·신비의물방울 부류 — 해당 타입 기술 ×1.2. 구버전 피어는
        //      그 이름을 모르는 아이템으로 접어 같은 판의 데미지가 갈린다).
        // 22 = 열매 29종(약점 반감·위급·성격 회복 — 구버전 게스트는 그 이름을 모르는 아이템으로
        //      접어 같은 판의 데미지·랭크·HP 가 갈린다).
        // 23 = 주얼 18종과 대가만 있는 셋(검은철구·느림보꼬리·만복향로 — 후공 물건은 행동 순서와
        //      무작위 tie-break 소비까지 바꾼다).
        // 24 = 플레이트 17종(타입 강화 도구와 같은 ×1.2).
        // 25 = 특정 종 전용 10종(전기구슬 부류 — 능력치 배율·급소 단계·두 타입 강화).
        // 26 = 일반 배틀 도구 12종(힘의머리띠 부류의 데미지 배율·초점렌즈의 급소·렌즈와 가루의
        //      명중·조개껍질방울과 큰뿌리의 회복·검은오물의 턴 끝 회복 또는 데미지 — 명중이 갈리면
        //      난수 소비 횟수까지 갈리고, `DamageCause` 에 원인 하나가 늘어 와이어 모양도 바뀐다).
        // 27 = 면역·무시 물건 6종(풍선의 땅 기술 면역과 맞으면 터짐·통굽부츠의 입장 데미지 무시·
        //      방진고글의 날씨 잔뎀 무시·만능우산의 볕과 비 위력 보정 무시·겨냥표적의 타입 면역
        //      해제·가벼운돌의 체중 절반 — 데미지가 아니라 맞고 안 맞고가 갈린다).
        // 방은 `rulesVersion` 을 안 보므로 규칙 차이를 막을 곳이 이 값뿐이다.
        //
        // **이 값을 리터럴로 박는 테스트는 여기 하나뿐이다.** 다섯 군데에 박혀 있던 동안은 누가
        // 정당하게 올릴 때마다 무관한 테스트 넷이 같이 빨개져 진짜 회귀와 구별이 안 됐다
        // (defect-log: 버전 리터럴을 박은 테스트는 남의 정당한 상향에 깨진다). 나머지 자리는
        // 자기 기능이 들어간 버전 **이상**인지만 본다 — 그게 각자가 주장하려던 사실이다.
        XCTAssertEqual(MultiplayerWireMessage.protocolVersion, 27)
    }

    /// `BattleEvent` 의 case 수를 동결한다 — **늘리면 `protocolVersion` 도 올려야 한다.**
    ///
    /// 이 enum 은 associated value 를 들고 자동합성 `Codable` 이라, 모르는 case 를 만난 디코더는
    /// `nil` 로 접는 게 아니라 throw 한다. 스트림은 `roundResolved` 에 통째로 실려 나가고
    /// 수신부는 디코딩 실패를 연결 종료로 처리하므로(`MultiplayerRoomCenter` 의 길이 프레임 수신),
    /// case 하나가 조용히 늘면 구버전 게스트가 그 이벤트가 처음 뜨는 라운드에서 방 밖으로 튕긴다.
    ///
    /// 왜 안 걸렸나: 배틀 엔진 쪽 테스트는 case 를 늘려도 전부 초록이고(엔진은 자기 안에서만 쓴다),
    /// 버전 테스트는 값을 그대로 두면 초록이다. 두 사실을 잇는 자리가 없어 #291 이 case 다섯을
    /// 더하면서 `rulesVersion` 만 올리고 지나갔다 — 방은 `rulesVersion` 을 읽지 않는다.
    ///
    /// 소스를 읽는 이유는 Swift 가 associated value 를 든 enum 을 열거하지 못해서다.
    func testBattleEventCaseCountIsFrozenAgainstTheProtocolVersion() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/Core/BattleModel.swift")
        let lines = try String(contentsOf: source, encoding: .utf8).components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("enum BattleEvent: Codable") }),
              let end = lines[start...].firstIndex(where: { $0 == "}" }) else {
            return XCTFail("`BattleEvent` 선언을 못 찾았다 — 옮겼으면 이 경로도 같이 고친다")
        }
        let cases = lines[start...end].filter {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("case ")
        }
        XCTAssertEqual(cases.count, 30,
                       """
                       `BattleEvent` 의 case 가 늘거나 줄었다. 고칠 것은 이 숫자만이 아니다 —
                       `MultiplayerWireMessage.protocolVersion` 도 함께 올려야 구버전 게스트가
                       라운드 스트림을 디코딩하다 튕기는 대신 입장에서 거절된다.
                       """)
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
