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

    // MARK: 보상 — 방어에만, 하루 상한 안에서

    func testDefendingPaysAndBuildsAStreakBonus() {
        let s = store()
        _ = leaderWithFullTeam(s)
        let before = s.state.starPieces

        // 1·2회는 기본만, 3회째에 연승 보너스가 붙는다.
        XCTAssertEqual(s.recordGymDefenseSuccess(), PlayerGym.defenseReward)
        XCTAssertEqual(s.recordGymDefenseSuccess(), PlayerGym.defenseReward)
        XCTAssertEqual(s.recordGymDefenseSuccess(),
                       PlayerGym.defenseReward + PlayerGym.defenseStreakBonus)
        XCTAssertEqual(s.state.starPieces - before,
                       PlayerGym.defenseReward * 3 + PlayerGym.defenseStreakBonus)
        XCTAssertEqual(s.gymLeadership?.consecutiveDefenses, 3)
    }

    /// 여섯 번 지키면 하루 상한이다 — 그 뒤로는 이겨도 0 이 나온다(연승은 계속 오른다).
    func testTheDailyCapStopsPayingAfterSixDefenses() {
        let s = store()
        _ = leaderWithFullTeam(s)
        let before = s.state.starPieces

        for _ in 0..<6 { s.recordGymDefenseSuccess() }
        XCTAssertEqual(s.state.starPieces - before, PlayerGym.dailyDefenseRewardCap)

        XCTAssertEqual(s.recordGymDefenseSuccess(), 0, "상한을 넘겨 지급하면 안 된다")
        XCTAssertEqual(s.state.starPieces - before, PlayerGym.dailyDefenseRewardCap)
        XCTAssertEqual(s.gymLeadership?.consecutiveDefenses, 7,
                       "상한에 걸린 것이지 못 지킨 것이 아니다 — 연승은 이어진다")
    }

    /// **핵심 구멍**: 일일 원장을 관장 자격 안에 두면 퇴위했다 다시 잡는 것만으로 상한이 리셋된다.
    /// 그래서 원장은 `CompanionState` 에 직접 있다.
    func testResigningAndRetakingDoesNotResetTheDailyCap() {
        let s = store()
        _ = leaderWithFullTeam(s)
        for _ in 0..<6 { s.recordGymDefenseSuccess() }
        let afterCap = s.state.starPieces

        s.resignGymLeadership()
        _ = leaderWithFullTeam(s)

        XCTAssertEqual(s.recordGymDefenseSuccess(), 0, "퇴위·재점령으로 상한이 되살아나면 무한 지급이다")
        XCTAssertEqual(s.state.starPieces, afterCap)
        XCTAssertEqual(s.gymLeadership?.consecutiveDefenses, 1, "연승은 자리를 잃으면 0 부터다")
    }

    func testTheCapResetsOnTheNextDay() {
        let clock = TestClock()
        let s = store(clock)
        _ = leaderWithFullTeam(s)
        for _ in 0..<6 { s.recordGymDefenseSuccess() }
        XCTAssertEqual(s.gymDefenseRewardRemainingToday, 0)

        clock.advance(24 * 60 * 60)

        XCTAssertEqual(s.gymDefenseEarnedToday, 0, "날짜가 바뀌면 원장이 새로 시작한다")
        XCTAssertGreaterThan(s.recordGymDefenseSuccess(), 0)
    }

    /// 점령에는 보상이 없다 — 관장이 바뀌면 쿨다운이 초기화되므로, 점령에 값을 붙이면 둘이
    /// 번갈아 뺏는 왕복이 그대로 파밍이 된다.
    func testTakingTheGymPaysNothing() {
        let s = store()
        let before = s.state.starPieces
        _ = leaderWithFullTeam(s)
        XCTAssertEqual(s.state.starPieces, before, "점령 자체로는 한 푼도 나가지 않는다")
    }

    /// 세이브를 주고받아 하루 상한을 되살리는 길을 막는다 — 같은 날이면 **많이 받은 쪽**이 남는다.
    func testMergingLedgersKeepsTheLargerAmountOnTheSameDay() {
        let merged = SaveTransfer.mergedGymDefenseLedger(
            imported: (date: "2026-08-31", amount: 1_000),
            current: (date: "2026-08-31", amount: 6_000))
        XCTAssertEqual(merged.0, "2026-08-31")
        XCTAssertEqual(merged.1, 6_000, "적은 쪽을 쓰면 기기를 옮기는 것만으로 상한이 되살아난다")

        let newer = SaveTransfer.mergedGymDefenseLedger(
            imported: (date: "2026-09-01", amount: 500),
            current: (date: "2026-08-31", amount: 8_000))
        XCTAssertEqual(newer.0, "2026-09-01", "다른 날이면 더 최근 쪽을 쓴다")
        XCTAssertEqual(newer.1, 500)
    }

    /// 손편집으로 오늘 지급액을 음수로 만들면 상한이 그만큼 늘어난다.
    func testSanitizeClampsTheDailyLedger() {
        var state = CompanionState()
        state.gymDefenseRewardDate = "2026-08-31"
        state.gymDefenseRewardToday = -50_000
        XCTAssertEqual(SaveTransfer.sanitized(state, origin: .importedFile).gymDefenseRewardToday, 0)

        state.gymDefenseRewardToday = 999_999
        XCTAssertEqual(SaveTransfer.sanitized(state, origin: .importedFile).gymDefenseRewardToday,
                       PlayerGym.dailyDefenseRewardCap)
    }

    /// 원장은 재화 멱등 가드라 서명 대상이다. 다만 **값이 없던 세이브의 canonical 은 그대로**여야
    /// 정상 세이브가 조작으로 잡히지 않는다(조건부 append 규칙).
    func testTheLedgerIsSignedButAbsentValuesDoNotChangeOldSignatures() {
        let empty = CompanionState()
        var earned = CompanionState()
        earned.gymDefenseRewardDate = "2026-08-31"
        earned.gymDefenseRewardToday = 3_000

        XCTAssertFalse(SaveTransfer.isTampered(SaveTransfer.signed(empty)))
        XCTAssertFalse(SaveTransfer.isTampered(SaveTransfer.signed(earned)))

        // 서명 후 원장만 손대면 조작으로 잡혀야 한다.
        var forged = SaveTransfer.signed(earned)
        forged.gymDefenseRewardToday = 0
        XCTAssertTrue(SaveTransfer.isTampered(forged), "상한을 되돌리는 손편집이 통과하면 안 된다")
    }

    // MARK: 도전 기록

    func testDefendingRecordsWhoChallengedAndWhatItPaid() {
        let s = store()
        _ = leaderWithFullTeam(s)

        let payout = s.recordGymDefenseSuccess(challengerName: "지수")

        let record = s.gymDefenseLog.first
        XCTAssertEqual(record?.challengerName, "지수")
        XCTAssertEqual(record?.defended, true)
        XCTAssertEqual(record?.payout, payout)
    }

    /// **자리를 내준 판이 기록에서 가장 궁금한 줄**이다. 자격이 풀린 뒤에도 남아야 한다.
    func testLosingTheGymIsRecordedAndSurvivesLosingLeadership() {
        let s = store()
        _ = leaderWithFullTeam(s)

        s.recordGymDefenseLoss(challengerName: "민준")
        s.resignGymLeadership()

        XCTAssertEqual(s.gymDefenseLog.first?.challengerName, "민준")
        XCTAssertEqual(s.gymDefenseLog.first?.defended, false)
        XCTAssertFalse(s.isGymLeader, "자격은 풀렸는데")
        XCTAssertEqual(s.gymDefenseLog.count, 1, "기록은 남는다")
    }

    /// 최신이 위로 온다 — 화면이 그대로 그린다.
    func testTheLogIsNewestFirstAndCapped() {
        let clock = TestClock()
        let s = store(clock)
        _ = leaderWithFullTeam(s)

        for index in 0..<(PlayerGym.defenseLogLimit + 5) {
            clock.advance(60)
            s.recordGymDefenseLoss(challengerName: "도전자\(index)")
        }

        XCTAssertEqual(s.gymDefenseLog.count, PlayerGym.defenseLogLimit, "세이브가 무한히 늘면 안 된다")
        XCTAssertEqual(s.gymDefenseLog.first?.challengerName,
                       "도전자\(PlayerGym.defenseLogLimit + 4)", "최신이 맨 위")
    }

    /// 도전자 이름은 남이 보낸 값이라 그대로 싣지 않는다.
    func testSanitizeClampsTheChallengeLog() {
        var state = CompanionState()
        state.gymDefenseLog = (0..<(PlayerGym.defenseLogLimit + 10)).map { index in
            GymDefenseRecord(challengerName: String(repeating: "가", count: 200),
                             at: Date(timeIntervalSince1970: TimeInterval(1_000 + index)),
                             defended: true, payout: -5)
        }

        let cleaned = SaveTransfer.sanitized(state, origin: .importedFile)

        XCTAssertEqual(cleaned.gymDefenseLog.count, PlayerGym.defenseLogLimit)
        XCTAssertTrue(cleaned.gymDefenseLog.allSatisfy { $0.challengerName.count <= SaveTransfer.maxNameLength })
        XCTAssertTrue(cleaned.gymDefenseLog.allSatisfy { $0.payout >= 0 }, "음수 지급액은 없다")
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

    // MARK: 방 이름 — 관장 이름과 재임 시각을 나르는 유일한 통로

    func testRoomNameCarriesLeaderAndTenureRoundTrip() throws {
        let held = Date(timeIntervalSince1970: 1_756_000_000)
        let name = PlayerGymRoomName.make(leaderName: "현우", idTag: "abc123", heldSince: held)

        let parsed = try XCTUnwrap(PlayerGymRoomName.parse(name))
        XCTAssertEqual(parsed.leaderName, "현우")
        XCTAssertEqual(parsed.idTag, "abc123")
        XCTAssertEqual(parsed.heldSince.timeIntervalSince1970, held.timeIntervalSince1970, accuracy: 1)
    }

    /// Bonjour 서비스 이름은 63바이트가 상한이라 넘으면 **광고가 아예 안 뜬다.** 한국어 이름은
    /// 글자당 3바이트라 20자면 60바이트다 — 넘칠 땐 이름을 자르고, 재임 시각과 식별자는 지킨다.
    func testRoomNameStaysWithinTheBonjourLimitByTrimmingTheName() throws {
        let held = Date(timeIntervalSince1970: 1_756_000_000)
        let longName = String(repeating: "가", count: SaveTransfer.maxNameLength)

        let name = PlayerGymRoomName.make(leaderName: longName, idTag: "abc123", heldSince: held)

        XCTAssertLessThanOrEqual(name.utf8.count, PlayerGym.maxServiceNameBytes,
                                 "상한을 넘으면 방이 광고되지 않아 아무도 체육관을 못 찾는다")
        let parsed = try XCTUnwrap(PlayerGymRoomName.parse(name))
        XCTAssertEqual(parsed.idTag, "abc123", "식별자는 잘리면 안 된다")
        XCTAssertEqual(parsed.heldSince.timeIntervalSince1970, held.timeIntervalSince1970, accuracy: 1,
                       "재임 시각도 잘리면 안 된다")
        XCTAssertFalse(parsed.leaderName.isEmpty)
    }

    /// 내 방을 남의 목록에서 가려내는 꼬리표(`#앞6자리`)가 새 형식에서도 그대로 잡혀야 한다 —
    /// 안 잡히면 자기 체육관을 남의 것으로 보고 스스로 자격을 반납한다.
    func testMyOwnRoomIsStillIdentifiableByTheIdTag() {
        let name = PlayerGymRoomName.make(leaderName: "현우", idTag: "abc123",
                                          heldSince: Date(timeIntervalSince1970: 1_756_000_000))
        XCTAssertTrue(name.contains("#abc123"))
        XCTAssertTrue(PlayerGym.isGymRoomName(name))
        XCTAssertNotNil(PlayerGymCoordinator.gymID(fromRoomName: name),
                        "경합 tie-break 이 식별자를 못 읽으면 둘 다 닫히거나 둘 다 남는다")
    }

    /// **회귀**: 방 목록의 `name` 은 `#` 앞에서 잘린 표시용 이름이다(`displayName`). 거기서
    /// 식별자를 읽으려 했더니 비교가 늘 실패해 **내 방이 남의 방으로 보였다** — 자기 체육관을
    /// 열어 두고 "이미 열린 체육관이 있습니다" 를 보게 된다. 판정은 원문(`serviceName`)으로 한다.
    func testTheDisplayNameLosesTheIdentifierSoJudgementsMustUseTheServiceName() throws {
        let service = PlayerGymRoomName.make(leaderName: "현우", idTag: "tklxl3",
                                             heldSince: Date(timeIntervalSince1970: 1_756_000_000))
        // 화면용 이름은 `#` 앞에서 잘린다 — 실제 목록이 그렇게 담는다.
        let displayed = String(service.split(separator: "#", maxSplits: 1).first ?? "")

        XCTAssertFalse(displayed.contains("#tklxl3"), "표시용 이름에는 식별자가 없다")
        XCTAssertNil(PlayerGymRoomName.parse(displayed),
                     "잘린 이름으로는 재임 시각도 못 읽는다 — 그래서 원문이 그대로 화면에 떴다")

        let parsed = try XCTUnwrap(PlayerGymRoomName.parse(service))
        XCTAssertEqual(parsed.leaderName, "현우")
        XCTAssertEqual(parsed.idTag, "tklxl3")
        XCTAssertTrue(service.contains("#tklxl3"), "내 방 판별은 원문에서만 된다")
    }

    /// 재임 시각이 없던 옛 형식도 이름만은 읽혀야 한다 — 못 읽으면 목록에서 체육관이 사라진다.
    func testALegacyRoomNameWithoutATimestampIsNotParsedAsTenure() {
        XCTAssertNil(PlayerGymRoomName.parse("GYM · 현우#abc123"),
                     "재임 시각이 없으면 시간을 지어내지 말고 nil 이어야 한다")
        XCTAssertTrue(PlayerGym.isGymRoomName("GYM · 현우#abc123"), "그래도 체육관 방인 건 맞다")
    }

    func testTenureMinutesFloorsAndNeverGoesNegative() {
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        XCTAssertEqual(PlayerGym.tenureMinutes(since: start, now: start.addingTimeInterval(59)), 0)
        XCTAssertEqual(PlayerGym.tenureMinutes(since: start, now: start.addingTimeInterval(60)), 1)
        XCTAssertEqual(PlayerGym.tenureMinutes(since: start, now: start.addingTimeInterval(1_500)), 25)
        XCTAssertEqual(PlayerGym.tenureMinutes(since: start, now: start.addingTimeInterval(-60)), 0,
                       "기기 시계가 어긋나도 음수 분이 화면에 뜨면 안 된다")
    }

    /// 자리가 넘어가면 재임 시간은 **0 부터 다시** 센다 — 체육관이 아니라 관장 개인의 기록이다.
    func testTenureRestartsWhenLeadershipChanges() {
        let clock = TestClock()
        let s = store(clock)
        _ = leaderWithFullTeam(s)
        let first = s.gymLeadership?.heldSince

        clock.advance(3_600)
        s.becomeGymLeader()

        XCTAssertNotEqual(s.gymLeadership?.heldSince, first)
        XCTAssertEqual(PlayerGym.tenureMinutes(since: s.gymLeadership?.heldSince ?? clock.now,
                                               now: clock.now), 0)
    }

    // MARK: 끝난 판 정리 — 한 번 방어하고 체육관이 잠기던 자리

    /// **회귀**: 방어에 성공해도 `gymMatch` 를 안 치우면 끝난 판이 그대로 남는다. 그러면 다음
    /// 도전이 `acceptGymChallenge` 의 "이미 배틀 중" 가드에 걸려 **체육관이 영구히 잠긴다.**
    /// 결과를 잠깐 보여 준 뒤 반드시 치워야 한다.
    func testAFinishedMatchIsClearedSoTheGymCanTakeTheNextChallenge() async {
        let s = store()
        let rooms = MultiplayerRoomCenter(companion: s)
        _ = leaderWithFullTeam(s)

        // 승패가 난 판을 흉내 낸다 — 게스트 경로(`.gymState` 수신)와 같은 자리를 지난다.
        let finished = GymMatchState(
            matchID: UUID(), leaderID: rooms.myID, challengerID: UUID(),
            leaderName: "현우", challengerName: "둘기덕",
            leaderTeam: [], challengerTeam: [],
            leaderActive: 0, challengerActive: 0, turn: 3, events: [],
            submitted: [], winnerID: rooms.myID)
        rooms.debugApplyGymState(finished)
        XCTAssertNotNil(rooms.gymMatch, "결과는 잠깐 보인다")

        try? await Task.sleep(for: .seconds(PlayerGym.resultDisplaySeconds + 1))

        XCTAssertNil(rooms.gymMatch,
                     "끝난 판이 남으면 다음 도전이 '이미 배틀 중' 으로 거절되어 체육관이 잠긴다")
    }

    // MARK: 스캔 창 — "체육관 검색 중…" 이 안 끝나던 자리

    /// **회귀**: 스캔 완료를 "방 개수가 바뀌었나" 로 판정했더니, 방이 하나도 없는 것이 정상인
    /// 상황(첫 사용자·혼자 켠 경우)에서 개수가 0 에서 움직이지 않아 화면이 영영 "체육관
    /// 검색 중…" 에 갇혔다. 시간으로 넘겨야 한다.
    func testTheScanWindowEndsWithoutAnyRoomAppearing() async {
        let s = store()
        let rooms = MultiplayerRoomCenter(companion: s)
        let coordinator = PlayerGymCoordinator(companion: s, rooms: rooms)
        XCTAssertFalse(coordinator.hasScannedOnce)

        coordinator.beginScanIfNeeded()
        // 방을 하나도 만들지 않는다 — 개수는 0 그대로다.
        try? await Task.sleep(for: .seconds(PlayerGymCoordinator.scanWindow + 0.5))

        XCTAssertTrue(coordinator.hasScannedOnce,
                      "방이 없다고 스캔이 안 끝나면 개설 버튼이 영영 안 나온다")
    }

    /// 창은 앱 수명 동안 한 번만 연다 — 탭을 드나들 때마다 다시 기다리면 성가시다.
    func testTheScanWindowIsNotReopenedOnceFinished() async {
        let s = store()
        let rooms = MultiplayerRoomCenter(companion: s)
        let coordinator = PlayerGymCoordinator(companion: s, rooms: rooms)

        coordinator.beginScanIfNeeded()
        try? await Task.sleep(for: .seconds(PlayerGymCoordinator.scanWindow + 0.5))
        XCTAssertTrue(coordinator.hasScannedOnce)

        coordinator.beginScanIfNeeded()
        XCTAssertTrue(coordinator.hasScannedOnce, "이미 끝난 창을 다시 열면 안 된다")
    }

    /// **회귀**: 세팅 기한이 지나 자격이 풀릴 때 **방을 안 닫으면** 방은 계속 광고되는데 화면은
    /// 관장이 아닌 것으로 떨어진다. 그러면 자기 방이 목록에 남고, `join` 은 `phase == .hosting`
    /// 이라 조용히 거절되어 **도전·관전 버튼이 눌러도 아무 반응이 없다.**
    func testExpiringLeadershipAlsoClosesTheRoom() {
        let clock = TestClock()
        let s = store(clock)
        let rooms = MultiplayerRoomCenter(companion: s)
        let coordinator = PlayerGymCoordinator(companion: s, rooms: rooms, clock: clock.closure)
        s.debugSetBoxedMons([boxed(11)])
        s.becomeGymLeader()

        clock.advance(PlayerGym.defenseSetupWindow + 1)
        coordinator.refresh()

        XCTAssertFalse(s.isGymLeader, "기한이 지나면 자격이 풀린다")
        XCTAssertEqual(rooms.phase, .idle,
                       "자격만 풀고 방을 열어 두면 도전·관전이 조용히 막힌다")
    }

    /// 자격이 없는데 체육관 방만 떠 있는 어긋남도 정리한다.
    func testAGymRoomWithoutLeadershipIsClosed() {
        let s = store()
        let rooms = MultiplayerRoomCenter(companion: s)
        let coordinator = PlayerGymCoordinator(companion: s, rooms: rooms)
        XCTAssertFalse(s.isGymLeader)

        coordinator.refresh()

        XCTAssertEqual(rooms.phase, .idle)
    }

    /// 탐색이 꺼져 있으면 기다림이 아니라 **꺼져 있다는 사실**을 알려야 한다 — 아무리 기다려도
    /// 방이 안 나타나므로 "검색 중" 은 거짓말이 된다.
    func testDiscoveryOffIsDistinguishedFromStillScanning() {
        let s = store()
        let rooms = MultiplayerRoomCenter(companion: s)
        let coordinator = PlayerGymCoordinator(companion: s, rooms: rooms)

        XCTAssertFalse(rooms.isBrowsing, "startBrowsing 전에는 탐색이 돌지 않는다")
        XCTAssertTrue(coordinator.isDiscoveryUnavailable)
    }

    // MARK: 친구 탭 라우팅 — 관장이라는 이유로 화면을 붙잡지 않는다

    /// 주석을 뺀 `FriendView` 소스. 가드가 자기 설명 문구에 걸리지 않게 한다.
    private func friendViewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI/FriendView.swift")
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// **회귀**: 갈림길에 `store.isGymLeader` 를 걸었더니 관장인 내내 체육관 화면이 강제됐다.
    /// 닫기를 눌러 `destination` 을 비워도 조건이 계속 참이라 안 나가지고, 그동안 교환도
    /// 1:1 배틀도 못 했다. 붙잡는 것은 **판이 돌 때**뿐이어야 한다.
    func testLeadershipAloneDoesNotPinTheFriendTab() throws {
        let code = try friendViewSource()
        XCTAssertFalse(code.contains("store.isGymLeader"),
                       "관장이라는 상태만으로 화면을 붙잡으면 친구 탭에서 다른 걸 못 한다")
        XCTAssertTrue(code.contains("battleCenter.multiplayer.gymMatch != nil"),
                      "붙잡는 기준은 진행 중인 판이다")
    }

    /// **회귀**: 끝난 판까지 붙잡으면 결과 화면에서 닫기가 먹히지 않는다 — 조건이 계속 참이라
    /// `destination = nil` 이 소용없다. 붙잡는 기준은 **승패가 나기 전**이어야 한다.
    func testAFinishedMatchDoesNotPinTheScreen() throws {
        let code = try friendViewSource()
        XCTAssertTrue(code.contains("isGymMatchLive"),
                      "끝난 판까지 붙잡으면 결과 화면에서 못 나온다")
        XCTAssertTrue(code.contains("match.winnerID == nil"),
                      "진행 중 판정은 승자 유무로 한다")
    }

    /// 체육관 방도 `phase != .idle` 이라, 토너먼트 갈림길에서 빼지 않으면 관장이 토너먼트
    /// 화면에 갇힌다.
    func testTheTournamentBranchExcludesGymRooms() throws {
        let code = try friendViewSource()
        XCTAssertTrue(code.contains("!battleCenter.multiplayer.isGymRoom"),
                      "체육관 방을 빼지 않으면 관장이 토너먼트 화면으로 끌려간다")
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
        XCTAssertEqual(MultiplayerWireMessage.protocolVersion, 13)
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
