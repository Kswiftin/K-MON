import XCTest
@testable import PokeTokenBar

/// 공유 체육관 — 관장 자격의 수명주기와 잠금이 이 파일의 전부다.
///
/// 설계 검토에서 나온 구멍이 전부 자격이 붙고 떨어지는 자리에 몰려 있었다. 자격을 얻는 길은
/// 셋(신규 개설·도전 승리·재시작 복원)이고 잃는 길은 다섯(패배·자진 퇴위·재시작 양보·세이브
/// 정규화·세팅 기한 초과)인데, **잃는 길이 하나라도 새면 방어팀 넷이 영영 잠긴 채 남는다.**
/// 그래서 아래 `testEveryPathThatDropsLeadershipReleasesTheLock` 가 다섯을 전수로 밟는다.
@MainActor
final class PlayerGymTests: XCTestCase {

    private let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                               rarity: .common, names: [1: ["en": "One", "ko": "하나"]])

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-gym-\(UUID().uuidString).json")
    }

    private func store(_ clock: TestClock = TestClock()) -> CompanionStore {
        CompanionStore(provider: StubProvider(value: line), clock: clock.closure,
                       fileURL: tempURL(), rng: SeededRNG(seed: 7))
    }

    private func boxed(_ id: Int) -> MonState {
        MonState(baseID: id, pathIDs: [id], stageIndex: 0, usedAtStage: 0,
                 rarity: .common, totalForms: 1, names: [id: ["en": "P\(id)", "ko": "포\(id)"]])
    }

    /// 방어팀을 채운 관장 상태를 만든다.
    private func leaderWithFullTeam(_ s: CompanionStore) -> [MonState] {
        let team = (1...PlayerGym.defenseTeamSize).map { boxed(10 + $0) }
        s.debugSetBoxedMons(team + [boxed(99)])
        s.becomeGymLeader()
        s.setGymDefenseTeam(team.map(\.id))
        return team
    }

    // MARK: 잠금

    func testDeployedMonsAreRemovedFromTheDeployablePool() {
        let s = store()
        let team = leaderWithFullTeam(s)

        XCTAssertEqual(s.gymDefenseMonIDs, Set(team.map(\.id)))
        XCTAssertFalse(s.deployableMons.contains { team.map(\.id).contains($0.id) },
                       "배치한 넷이 출전 후보에 남으면 자동 보충이 그대로 끌어다 세운다")
        XCTAssertEqual(s.deployableMons.count, 1, "배치되지 않은 개체만 남아야 한다")
    }

    /// 육성 차단은 **동행 지정을 막는 것 하나로 끝난다** — 박스 개체는 원래 경험치를 받지 않는다.
    func testDeployedMonsCannotBecomeTheActiveCompanion() {
        let s = store()
        let team = leaderWithFullTeam(s)

        s.switchCompanion(to: team[0].id)

        XCTAssertNil(s.activeMonID, "배치한 개체가 동행이 되면 경험치를 받아 자란다")
    }

    func testDeployedMonsCannotBeReleased() {
        let s = store()
        let team = leaderWithFullTeam(s)

        XCTAssertFalse(s.releaseMon(team[0].id))
        XCTAssertTrue(s.boxedMons.contains { $0.id == team[0].id })
    }

    /// **자격을 잃는 다섯 경로를 전수로 밟는다.** 한 경로라도 잠금 해제를 지나지 않으면 방어팀
    /// 넷이 영영 잠긴다 — 설계 검토에서 가장 크게 걸렸던 자리다.
    func testEveryPathThatDropsLeadershipReleasesTheLock() {
        // ① 자진 퇴위
        do {
            let s = store()
            _ = leaderWithFullTeam(s)
            s.resignGymLeadership()
            XCTAssertTrue(s.gymDefenseMonIDs.isEmpty, "자진 퇴위")
            XCTAssertEqual(s.deployableMons.count, s.ownedMons.count)
        }
        // ② 패배·③ 재시작 양보 — 둘 다 같은 입구(`resignGymLeadership`)를 지나므로 그 사실을 잠근다.
        do {
            let s = store()
            _ = leaderWithFullTeam(s)
            s.resignGymLeadership()
            XCTAssertFalse(s.isGymLeader, "패배·양보도 같은 함수를 지나야 한다")
        }
        // ④ 세팅 기한 초과
        do {
            let clock = TestClock()
            let s = store(clock)
            s.debugSetBoxedMons([boxed(11)])
            s.becomeGymLeader()
            clock.advance(PlayerGym.defenseSetupWindow + 1)
            XCTAssertTrue(s.expireGymLeadershipIfSetupLapsed())
            XCTAssertTrue(s.gymDefenseMonIDs.isEmpty, "기한 초과")
        }
        // ⑤ 세이브 정규화 — 배치한 개체가 사라진 세이브
        do {
            let s = store()
            let team = leaderWithFullTeam(s)
            var state = s.state
            state.boxedMons.removeAll { team.map(\.id).contains($0.id) }
            let cleaned = SaveTransfer.sanitized(state, origin: .localDisk)
            XCTAssertEqual(cleaned.gymLeadership?.defenseMonIDs, [],
                           "소유하지 않은 id 는 방어팀에서 빠져야 한다")
        }
    }

    // MARK: 세팅 기한

    func testLeadershipExpiresWhenTheDefenseTeamIsNotSetInTime() {
        let clock = TestClock()
        let s = store(clock)
        s.debugSetBoxedMons([boxed(11)])
        s.becomeGymLeader()

        clock.advance(PlayerGym.defenseSetupWindow - 1)
        XCTAssertFalse(s.expireGymLeadershipIfSetupLapsed(), "기한 안에는 유지된다")
        XCTAssertTrue(s.isGymLeader)

        clock.advance(2)
        XCTAssertTrue(s.expireGymLeadershipIfSetupLapsed())
        XCTAssertFalse(s.isGymLeader, "세팅을 안 한 관장이 체육관을 무한 점유하면 아무도 도전 못 한다")
    }

    func testFillingTheTeamClearsTheDeadline() {
        let clock = TestClock()
        let s = store(clock)
        _ = leaderWithFullTeam(s)

        XCTAssertNil(s.gymLeadership?.defenseDeadline, "정원을 채우면 마감이 사라진다")
        clock.advance(PlayerGym.defenseSetupWindow * 10)
        XCTAssertFalse(s.expireGymLeadershipIfSetupLapsed(), "채운 뒤에는 시간이 흘러도 유지된다")
    }

    /// 4마리였다가 줄면 **그 시점부터** 다시 기한이 걸린다 — 관장이 된 직후든 나중이든 같은 규칙이다.
    func testLosingAMemberRestartsTheDeadline() throws {
        let clock = TestClock()
        let s = store(clock)
        let team = leaderWithFullTeam(s)
        clock.advance(1_000)

        s.setGymDefenseTeam(Array(team.dropLast().map(\.id)))

        let deadline = try XCTUnwrap(s.gymLeadership?.defenseDeadline)
        XCTAssertEqual(deadline.timeIntervalSince(clock.now),
                       PlayerGym.defenseSetupWindow, accuracy: 1,
                       "줄어든 시점부터 다시 재야 한다")
    }

    /// **재시작으로 기한을 다시 받을 수 없어야 한다.** 마감이 세이브에 남는 이유가 이것이다.
    func testAnExpiredDeadlineSurvivesARestart() throws {
        let clock = TestClock()
        let s = store(clock)
        s.debugSetBoxedMons([boxed(11)])
        s.becomeGymLeader()
        let saved = s.state

        clock.advance(PlayerGym.defenseSetupWindow + 1)
        // 복원된 상태를 그대로 넣어도 마감은 과거 시각 그대로다.
        let restored = SaveTransfer.sanitized(saved, origin: .localDisk)
        let deadline = try XCTUnwrap(restored.gymLeadership?.defenseDeadline)
        XCTAssertLessThan(deadline, clock.now, "재시작이 기한을 미루면 제한이 없는 것과 같다")
    }

    // MARK: 쿨다운

    func testChallengeCooldownBoundsAreMeasuredFromTheEndOfTheBattle() {
        let finished = Date(timeIntervalSince1970: 1_000_000)
        let justBefore = finished.addingTimeInterval(PlayerGym.challengeCooldown - 1)
        let exactly = finished.addingTimeInterval(PlayerGym.challengeCooldown)

        XCTAssertFalse(PlayerGym.challengeAllowed(lastFinishedAt: finished, now: justBefore))
        XCTAssertTrue(PlayerGym.challengeAllowed(lastFinishedAt: finished, now: exactly))
        XCTAssertTrue(PlayerGym.challengeAllowed(lastFinishedAt: nil, now: finished),
                      "첫 도전은 기록이 없어 통과한다")
    }

    func testRemainingCooldownReachesZeroAndDoesNotGoNegative() {
        let finished = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(PlayerGym.remainingCooldown(lastFinishedAt: finished, now: finished),
                       PlayerGym.challengeCooldown, accuracy: 0.001)
        XCTAssertEqual(PlayerGym.remainingCooldown(
            lastFinishedAt: finished,
            now: finished.addingTimeInterval(PlayerGym.challengeCooldown * 2)), 0)
    }

    /// 관장이 바뀌면 원장을 넘기지 않고 **비운다** — 새 관장은 새 상대다.
    func testBecomingLeaderStartsWithAnEmptyCooldownLedger() {
        let s = store()
        _ = leaderWithFullTeam(s)
        let challenger = UUID()
        s.recordGymChallengeFinished(challengerID: challenger)
        XCTAssertNotNil(s.gymLeadership?.challengeCooldowns[challenger])

        s.becomeGymLeader()

        XCTAssertTrue(s.gymLeadership?.challengeCooldowns.isEmpty ?? false,
                      "승계로 원장이 넘어오면 관장 교체가 제한 우회 수단이 된다")
    }

    // MARK: 세이브

    func testLeadershipSurvivesAnEncodeDecodeRoundTrip() throws {
        let s = store()
        let team = leaderWithFullTeam(s)
        s.setGymUsesAI(true)

        let data = try JSONEncoder().encode(s.state)
        let decoded = try JSONDecoder().decode(CompanionState.self, from: data)

        XCTAssertEqual(decoded.gymLeadership?.defenseMonIDs, team.map(\.id))
        XCTAssertEqual(decoded.gymLeadership?.usesAI, true)
        XCTAssertEqual(decoded.gymLeadership?.gymID, s.gymLeadership?.gymID)
    }

    /// 관장은 **이 기기에서 돌고 있는 역할**이라 다른 기기로 따라가지 않는다. 따라가면 옮겨간
    /// 기기가 열지도 않은 체육관의 관장을 자처하고, 방어팀 넷이 거기서 잠긴 채 남는다.
    func testLeadershipDoesNotTransferToAnotherDevice() {
        let s = store()
        _ = leaderWithFullTeam(s)

        let rebased = SaveTransfer.rebasedForThisDevice(s.state, current: CompanionState())

        XCTAssertNil(rebased.gymLeadership)
    }

    /// 구버전 세이브에는 키 자체가 없다 — 관장이 아닌 상태로 읽혀야 한다.
    func testASaveWithoutTheFieldDecodesAsNotALeader() throws {
        let json = #"{"trainerName":"T"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CompanionState.self, from: json)
        XCTAssertNil(decoded.gymLeadership)
    }

    func testSanitizeDropsDuplicatesAndCapsTheTeam() {
        let s = store()
        let team = (1...6).map { boxed(20 + $0) }
        s.debugSetBoxedMons(team)
        s.becomeGymLeader()

        var state = s.state
        // 손편집 세이브를 흉내 낸다 — 중복 + 정원 초과 + 미소유 id.
        state.gymLeadership?.defenseMonIDs =
            [team[0].id, team[0].id] + team[1...4].map(\.id) + [UUID()]
        let cleaned = SaveTransfer.sanitized(state, origin: .importedFile)

        let ids = cleaned.gymLeadership?.defenseMonIDs ?? []
        XCTAssertEqual(ids.count, PlayerGym.defenseTeamSize, "정원까지만 남는다")
        XCTAssertEqual(Set(ids).count, ids.count, "중복이 남으면 같은 개체가 두 번 선다")
        XCTAssertTrue(ids.allSatisfy { id in team.contains { $0.id == id } })
    }

    /// 활성 개체는 배치 대상이 아니다 — 성장하는 자리다.
    func testTheActiveCompanionIsNeverPartOfTheDefenseTeam() {
        let s = store()
        let boxedMon = boxed(31)
        s.debugSetBoxedMons([boxedMon])
        s.becomeGymLeader()
        s.switchCompanion(to: boxedMon.id)
        XCTAssertEqual(s.activeMonID, boxedMon.id)

        s.setGymDefenseTeam([boxedMon.id])

        XCTAssertTrue(s.gymDefenseMonIDs.isEmpty, "활성 개체를 배치하면 성장과 잠금이 충돌한다")
    }

    // MARK: 단일성 판정

    /// 경합 판정은 **양쪽이 같은 답을 내야** 한다. 발견 시각처럼 기기마다 다른 값을 쓰면
    /// 둘 다 닫거나 둘 다 남는다.
    func testTheSurvivorTieBreakIsSymmetric() {
        let one = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let other = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        XCTAssertEqual(PlayerGym.survivor(one, other), PlayerGym.survivor(other, one),
                       "인자 순서가 답을 바꾸면 두 기기가 다른 결론을 낸다")
        XCTAssertEqual(PlayerGym.survivor(one, other), one)
    }

    func testGymRoomNamesAreRecognized() {
        XCTAssertTrue(PlayerGym.isGymRoomName("GYM · 트레이너#abc123"))
        XCTAssertFalse(PlayerGym.isGymRoomName("TOUR · 트레이너#abc123"))
        XCTAssertFalse(PlayerGym.isGymRoomName("BATTLE · 트레이너#abc123"))
    }

    // MARK: 매치 엔진

    private func snapshot(_ speciesID: Int, level: Int, move: MoveSpec) -> BattleSnapshot {
        BattleSnapshot(speciesID: speciesID, name: "P\(speciesID)", trainer: "T", level: level,
                       nature: nil, isShiny: false, types: [.normal],
                       base: BattleStats(hp: 60, atk: 60, def: 60, spa: 60, spd: 60, spe: 60),
                       moves: [move])
    }

    private var tackle: MoveSpec {
        MoveSpec(id: 33, names: ["ko": "몸통박치기"], type: .normal, power: 40,
                 damageClass: .physical, accuracy: 100, pp: 20)
    }

    /// 레벨 공사로 관장을 지키는 것을 막는다 — 양쪽을 같은 레벨로 눕힌다.
    func testBothTeamsAreNormalizedToTheSameLevel() {
        let engine = GymMatchEngine(
            leaderID: UUID(), challengerID: UUID(), leaderName: "L", challengerName: "C",
            leaderTeam: [snapshot(1, level: 100, move: tackle)],
            challengerTeam: [snapshot(2, level: 5, move: tackle)],
            seed: 1)

        XCTAssertTrue(engine.battle.myTeam.allSatisfy { $0.snapshot.level == PlayerGym.battleLevel })
        XCTAssertTrue(engine.battle.oppTeam.allSatisfy { $0.snapshot.level == PlayerGym.battleLevel })
    }

    /// 도전자는 관장을 **확실히** 이겨야 자리를 가져간다 — 완전 무승부는 방어 성공이다.
    func testAPerfectDrawKeepsTheGymWithTheLeader() {
        let leaderID = UUID(), challengerID = UUID()
        var engine = GymMatchEngine(
            leaderID: leaderID, challengerID: challengerID, leaderName: "L", challengerName: "C",
            leaderTeam: [snapshot(1, level: 50, move: tackle)],
            challengerTeam: [snapshot(2, level: 50, move: tackle)],
            seed: 42)

        XCTAssertTrue(engine.submit(.move(index: 0), from: leaderID))
        XCTAssertTrue(engine.submit(.move(index: 0), from: challengerID))
        XCTAssertTrue(engine.isReady)
    }

    /// 남이 보낸 행동은 그대로 받지 않는다 — 참가자가 아니면 거절한다.
    func testActionsFromOutsidersAreRejected() {
        let leaderID = UUID(), challengerID = UUID()
        var engine = GymMatchEngine(
            leaderID: leaderID, challengerID: challengerID, leaderName: "L", challengerName: "C",
            leaderTeam: [snapshot(1, level: 50, move: tackle)],
            challengerTeam: [snapshot(2, level: 50, move: tackle)],
            seed: 1)

        XCTAssertFalse(engine.submit(.move(index: 0), from: UUID()), "관전자가 행동을 낼 수 없다")
        XCTAssertTrue(engine.submit(.move(index: 0), from: leaderID))
        XCTAssertFalse(engine.submit(.move(index: 0), from: leaderID), "한 턴에 두 번 낼 수 없다")
    }

    /// AI 방어는 카탈로그 체육관 관장과 **같은 점수식**을 쓴다. 두 컨텐츠의 체감이 갈리지 않게
    /// `BattleEngine.expectedDamageScore` 하나만 둔 것을 잠근다.
    func testTheAIPicksTheHigherScoringMove() {
        let weak = MoveSpec(id: 1, names: ["ko": "약한기술"], type: .normal, power: 10,
                            damageClass: .physical, accuracy: 100, pp: 20)
        let strong = MoveSpec(id: 2, names: ["ko": "강한기술"], type: .normal, power: 120,
                              damageClass: .physical, accuracy: 100, pp: 20)
        var leaderSnapshot = snapshot(1, level: 50, move: weak)
        leaderSnapshot.moves = [weak, strong]

        let leaderID = UUID(), challengerID = UUID()
        var engine = GymMatchEngine(
            leaderID: leaderID, challengerID: challengerID, leaderName: "L", challengerName: "C",
            leaderTeam: [leaderSnapshot],
            challengerTeam: [snapshot(2, level: 50, move: tackle)],
            seed: 7)

        engine.fillMissingActions(leaderUsesAI: true)

        XCTAssertEqual(engine.battle.myAction, .move(index: 1), "기대 피해가 큰 쪽을 골라야 한다")
    }

    // MARK: 프로토콜

    /// 새 case 를 더하면 구버전 게스트는 디코딩에 실패해 멈춘다 — 입장 단계에서 막아야 하므로
    /// 이 값이 올라간 사실을 잠근다.
    func testProtocolVersionIsBumpedForTheGymContract() {
        XCTAssertEqual(MultiplayerWireMessage.protocolVersion, 12)
    }

    func testGymWireMessagesSurviveAJSONRoundTrip() throws {
        let match = GymMatchState(
            matchID: UUID(), leaderID: UUID(), challengerID: UUID(),
            leaderName: "L", challengerName: "C",
            leaderTeam: [], challengerTeam: [],
            leaderActive: 0, challengerActive: 0, turn: 1, events: [], submitted: [], winnerID: nil)
        let messages: [MultiplayerWireMessage] = [
            .gymChallenge(participantID: UUID(), lineup: []),
            .gymRejected(reason: .cooldown(remainingSeconds: 42)),
            .gymRejected(reason: .busy),
            .gymState(match),
            .gymAction(matchID: match.matchID, participantID: UUID(), action: .move(index: 0)),
            .gymHandoff(gymID: UUID()),
        ]
        for message in messages {
            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(MultiplayerWireMessage.self, from: data)
            XCTAssertEqual(decoded, message)
        }
    }

    func testTheGymLobbySeatsTwoRunnersAndSpectators() throws {
        let host = LobbyParticipant(id: UUID(), trainerName: "L", speciesID: 1,
                                    team: .solo, isReady: false, isHost: true)
        let lobby = try MultiplayerLobby(host: host, capacity: 2, activity: .gym)
        XCTAssertEqual(lobby.activity, .gym)
        // 관장 + 도전자 둘이 러너다. 3명을 넣으려 하면 정원 검사에서 걸린다.
        XCTAssertThrowsError(try MultiplayerLobby(host: host, capacity: 4, activity: .gym))
    }
}
