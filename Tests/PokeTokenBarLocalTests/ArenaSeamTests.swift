import Foundation
import Testing
@testable import PokeTokenBar

/// 창구가 센터의 판을 **터미널 값으로 접는 자리**를 검증한다 (Phase 5-7).
///
/// 실행기 테스트는 가짜 창구를 쓴다(소켓을 살리지 않으려고) — 그래서 조립 자체는
/// 커버리지에서 통째로 `^0` 이었다. 여기서 도는 것은 실제 `MultiplayerRoomCenter` 이고,
/// `init(companion:)` 은 listener·browser 를 켜지 않으므로 LAN 으로 나가지 않는다
/// (`startBrowsing()` 을 부르지 않는다).
///
/// 이 조립에서 조용히 깨질 수 있는 것: **어느 쪽이 내 팀인가.** 관장과 도전자를 뒤바꾸면
/// 화면은 그대로 그려지고 HP 도 맞아 보이는데, 사용자가 상대 팀의 기술을 고르게 된다.
@Suite("ArenaSeamTests")
@MainActor
struct ArenaSeamTests {

    private func makeCenter(_ name: String) -> (MultiplayerRoomCenter, URL) {
        let directory = storeFixtureDirectory(name)
        let store = CompanionStore(clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                   fileURL: directory.appendingPathComponent("state.json"))
        store.setLanguage(.ko)
        return (MultiplayerRoomCenter(companion: store), directory)
    }

    private func snapshot(_ name: String) -> BattleSnapshot {
        BattleSnapshot(
            speciesID: 1, name: name, trainer: name, level: 50, nature: nil, isShiny: false,
            types: [.normal],
            base: BattleStats(hp: 100, atk: 100, def: 50, spa: 100, spd: 50, spe: 100),
            moves: [MoveSpec(id: 1, names: ["ko": "타격"], type: .normal, power: 40,
                             damageClass: .physical, accuracy: nil, pp: 20),
                    MoveSpec(id: 2, names: ["ko": "울음"], type: .normal, power: 0,
                             damageClass: .status, accuracy: nil, pp: 40)])
    }

    private func team(_ names: [String]) -> [TournamentPokemonState] {
        names.map { TournamentPokemonState(BattleSide(snapshot($0))) }
    }

    private func gymMatch(in center: MultiplayerRoomCenter, iAmLeader: Bool,
                          winnerIsLeader: Bool? = nil,
                          submitted: Set<UUID> = []) -> GymMatchState {
        let other = UUID()
        let leaderID = iAmLeader ? center.myID : other
        let challengerID = iAmLeader ? other : center.myID
        return GymMatchState(matchID: UUID(), leaderID: leaderID, challengerID: challengerID,
                             leaderName: "관장 민", challengerName: "도전자 나",
                             leaderTeam: team(["관장 앞", "관장 뒤"]),
                             challengerTeam: team(["내 앞", "내 뒤"]),
                             leaderActive: 0, challengerActive: 0, turn: 4, events: [],
                             submitted: submitted,
                             winnerID: winnerIsLeader.map { $0 ? leaderID : challengerID })
    }

    // MARK: 시작 표 — 화면이 권하는 키와 센터가 부르는 함수가 한 짝이다

    /// **표 둘이 어긋나면 권한 키가 아무 일도 안 한다.** 화면은 `RoomActivity.isHostStarted` 로
    /// 시작 키를 낼지 정하고, 센터는 `starter(for:)` 로 무엇을 부를지 정한다 — 그 둘이 같은
    /// 사실을 봐야 한다.
    ///
    /// 이 검사가 **주입으로 확인된 유일한 방법**이다. 라우팅을 함수 본문의 `switch` 로 두었을 때
    /// `.battle` 갈래를 `break` 로 바꿔도 전 스위트가 초록이었다(실행기 테스트는 가짜 창구를 쓰고,
    /// 진짜 시작 함수는 소켓과 스냅샷이 필요해 효과를 볼 수 없다). 그래서 효과가 아니라 **표**를 본다.
    @Test func testEveryHostStartedActivityHasAStarter() throws {
        let (center, directory) = makeCenter("arena-seam-starters")
        defer { try? FileManager.default.removeItem(at: directory) }

        for activity in RoomActivity.allCases {
            #expect((center.starter(for: activity) != nil) == activity.isHostStarted,
                    "\(activity.rawValue) — 화면과 센터가 다른 답을 낸다")
        }
    }

    // MARK: 어느 쪽이 내 팀인가

    /// 도전자로 붙었으면 **도전자 팀이 내 팀**이다. 뒤바뀌면 사용자가 상대의 기술을 고른다.
    @Test func testTheChallengerSeesItsOwnTeamAsMine() throws {
        let (center, directory) = makeCenter("arena-seam-challenger")
        defer { try? FileManager.default.removeItem(at: directory) }
        center.debugApplyGymState(gymMatch(in: center, iAmLeader: false))

        let duel = try #require(center.terminalState.duel)

        #expect(duel.myName == "도전자 나")
        #expect(duel.theirName == "관장 민")
        #expect(duel.mine.map(\.label) == ["내 앞", "내 뒤"])
        #expect(duel.theirs.map(\.label) == ["관장 앞", "관장 뒤"])
        #expect(duel.amFighting)
        #expect(duel.turn == 4)
    }

    /// 관장으로 있으면 관장 팀이 내 팀이다 — 같은 판, 반대 자리.
    @Test func testTheLeaderSeesItsOwnTeamAsMine() throws {
        let (center, directory) = makeCenter("arena-seam-leader")
        defer { try? FileManager.default.removeItem(at: directory) }
        center.debugApplyGymState(gymMatch(in: center, iAmLeader: true))

        let duel = try #require(center.terminalState.duel)

        #expect(duel.myName == "관장 민")
        #expect(duel.mine.map(\.label) == ["관장 앞", "관장 뒤"])
        #expect(duel.amFighting)
    }

    /// 관전자는 **관장을 왼쪽에** 둔다. 도전자 팀을 "내 팀" 자리에 실으면 내 것이 아닌 팀에
    /// 표시가 붙는다.
    @Test func testASpectatorGetsTheLeaderOnTheLeftAndNoMarkAtAll() throws {
        let (center, directory) = makeCenter("arena-seam-watcher")
        defer { try? FileManager.default.removeItem(at: directory) }
        // 나는 어느 쪽도 아니다 — 두 id 를 모두 남에게 준다.
        let watched = gymMatch(in: center, iAmLeader: false)
        center.debugApplyGymState(
            GymMatchState(matchID: watched.matchID, leaderID: UUID(), challengerID: UUID(),
                          leaderName: watched.leaderName, challengerName: watched.challengerName,
                          leaderTeam: watched.leaderTeam, challengerTeam: watched.challengerTeam,
                          leaderActive: 0, challengerActive: 0, turn: watched.turn,
                          events: [], submitted: [], winnerID: nil))

        let duel = try #require(center.terminalState.duel)

        #expect(duel.myName == "관장 민")
        #expect(!duel.amFighting)
        #expect(duel.moves.isEmpty, "관전자에게 낼 기술을 실었다")
        #expect(duel.iWon == nil)
    }

    // MARK: 자리·기술·승패

    /// 자리 번호는 **팀 순서**이고 나온 자리에만 표시가 붙는다.
    @Test func testSlotNumbersFollowTheTeamOrderAndMarkTheActiveOne() throws {
        let (center, directory) = makeCenter("arena-seam-slots")
        defer { try? FileManager.default.removeItem(at: directory) }
        var match = gymMatch(in: center, iAmLeader: false)
        match.challengerActive = 1
        center.debugApplyGymState(match)

        let duel = try #require(center.terminalState.duel)

        #expect(duel.mine.map(\.number) == [1, 2])
        #expect(duel.mine.map(\.isActive) == [false, true])
        #expect(duel.mine.allSatisfy { $0.hp == $0.maxHP })
    }

    /// 기술 번호는 **엔진 순번 + 1** 이고, PP 가 떨어진 자리는 목록에서 빠진 채 번호에 구멍이
    /// 남는다 — 다시 매기면 사용자가 고른 것과 다른 기술이 나간다.
    @Test func testSpentMovesLeaveTheirNumberBehind() throws {
        let (center, directory) = makeCenter("arena-seam-moves")
        defer { try? FileManager.default.removeItem(at: directory) }
        var match = gymMatch(in: center, iAmLeader: false)
        var side = BattleSide(snapshot("내 앞"))
        side.pp[0] = 0                                   // 1번 기술을 다 썼다
        match.challengerTeam[0] = TournamentPokemonState(side)
        center.debugApplyGymState(match)

        let state = center.terminalState
        let duel = try #require(state.duel)

        #expect(duel.moves.map(\.number) == [2], "번호를 다시 매겼다: \(duel.moves)")
        #expect(duel.moves.first?.label == "울음")
        #expect(ArenaScreen.moveNumbers(state) == [2])
        #expect(RoomScreen.action(number: 1, in: state) == nil)
    }

    /// 이미 냈으면 그 사실이 실린다 — 안 실으면 사용자가 같은 턴을 두 번 낸다.
    @Test func testASubmittedTurnIsCarriedThrough() throws {
        let (center, directory) = makeCenter("arena-seam-submitted")
        defer { try? FileManager.default.removeItem(at: directory) }
        center.debugApplyGymState(gymMatch(in: center, iAmLeader: false,
                                           submitted: [center.myID]))

        let state = center.terminalState

        #expect(state.duel?.hasSubmitted == true)
        #expect(RoomScreen.kind(state) == .waiting)
    }

    /// 승패는 **누가 이겼는지로** 정해진다. 도전자가 이긴 판을 관장의 승리로 실으면 화면이
    /// 반대로 뒤집힌다.
    @Test func testTheWinnerIsResolvedFromTheMatchNotFromMySide() throws {
        let (center, directory) = makeCenter("arena-seam-winner")
        defer { try? FileManager.default.removeItem(at: directory) }
        center.debugApplyGymState(gymMatch(in: center, iAmLeader: false, winnerIsLeader: true))

        let lost = try #require(center.terminalState.duel)
        #expect(lost.winnerName == "관장 민")
        #expect(lost.iWon == false)

        center.debugApplyGymState(gymMatch(in: center, iAmLeader: false, winnerIsLeader: false))
        let won = try #require(center.terminalState.duel)
        #expect(won.winnerName == "도전자 나")
        #expect(won.iWon == true)
    }

    // MARK: 토너먼트 — 같은 규칙, 다른 상태

    /// 토너먼트도 **같은 조립을 지난다.** 두 함수로 나누면 기술 목록·승패·표시가 두 곳이 되고,
    /// 한쪽만 고치는 부류가 그대로 생긴다. 라운드는 머리글의 덧말로 실린다.
    @Test func testATournamentMatchFoldsThroughTheSameDuelRules() throws {
        let (center, directory) = makeCenter("arena-seam-tournament")
        defer { try? FileManager.default.removeItem(at: directory) }
        let rival = UUID()
        let match = TournamentMatchState(
            id: UUID(), round: 2, playerA: rival, playerB: center.myID,
            nameA: "상대", nameB: "나",
            teamA: team(["상대 앞"]), teamB: team(["내 앞", "내 뒤"]),
            activeA: 0, activeB: 0, turn: 3, events: [], submitted: [], winnerID: nil)
        center.debugApplyTournamentMatch(match, entrants: [
            TournamentEntrant(id: rival, trainerName: "상대", speciesID: 1),
            TournamentEntrant(id: center.myID, trainerName: "나", speciesID: 1)
        ])

        let state = center.terminalState
        let duel = try #require(state.duel)

        // B 자리로 들어갔으면 B 팀이 내 팀이다 — A 를 늘 왼쪽에 두면 상대 기술을 고르게 된다.
        #expect(duel.myName == "나")
        #expect(duel.mine.map(\.label) == ["내 앞", "내 뒤"])
        #expect(duel.caption == "2 라운드")
        #expect(duel.moves.map(\.number) == [1, 2])
        #expect(RoomScreen.kind(state) == .duelMove)
        #expect(RoomScreen.lines(state, language: .ko, width: 70)
            .contains { $0.contains("2 라운드") })

        // 승자 이름도 **경기에서** 나온다. A 를 늘 승자로 두면 이긴 판이 진 판으로 보인다.
        var decided = match
        decided.winnerID = rival
        center.debugApplyTournamentMatch(decided, entrants: [])
        let over = try #require(center.terminalState.duel)
        #expect(over.winnerName == "상대")
        #expect(over.iWon == false)
        #expect(RoomScreen.kind(center.terminalState) == .finished)
    }

    // MARK: 트랙 — 순위·판돈·마감

    /// 순위는 **거리 내림차순**이고 번호는 그 자리다. 러너 배열 순서를 그대로 찍으면 1등이
    /// 목록 가운데 있고, `bet 1` 이 꼴찌에게 간다.
    @Test func testPokeathlonStandingsAreSortedAndNumbered() throws {
        let (center, directory) = makeCenter("arena-seam-race")
        defer { try? FileManager.default.removeItem(at: directory) }
        var slow = PokeathlonRacer(id: center.myID, trainerName: "나", speciesID: 1)
        slow.distance = 40
        slow.lane = 2
        slow.crashes = 3
        var fast = PokeathlonRacer(id: UUID(), trainerName: "이웃", speciesID: 4)
        fast.distance = 210
        center.debugApplyPokeathlon(race: PokeathlonRace(racers: [slow, fast],
                                                         startsAt: Date(timeIntervalSince1970: 0)))

        let state = center.terminalState
        let track = try #require(state.track)

        #expect(track.standings.map(\.label) == ["이웃", "나"])
        #expect(track.standings.map(\.number) == [1, 2])
        #expect(ArenaScreen.runnerID(number: 2, in: state) == center.myID)
        #expect(track.amRacing)
        #expect(track.canMove, "출발 시각이 지났는데 못 달린다고 실었다")
        #expect(!track.canBet, "러너에게 베팅을 열었다")
        #expect(track.myChoice == "레인 3")
        #expect(track.standings.last?.right.contains("넘어짐 3") == true,
                "\(track.standings.last?.right ?? "")")
    }

    /// 걸 수 있는 조건은 **호스트 검사기와 같은 셋**이다(관전자·열린 원장·출발 전). 하나라도
    /// 어긋나면 터미널이 권한 베팅이 호스트에게 거절된다.
    @Test func testABetIsOnlyOfferedUnderTheSameThreeConditionsTheHostChecks() throws {
        let (center, directory) = makeCenter("arena-seam-pool")
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = PokeathlonRacer(id: UUID(), trainerName: "이웃", speciesID: 4)
        let watcher = UUID()
        var pool = PokeathlonPool()
        pool.bets[center.myID] = PokeathlonBet(bettorID: center.myID, runnerID: runner.id,
                                               amount: 400)
        pool.bets[watcher] = PokeathlonBet(bettorID: watcher, runnerID: runner.id, amount: 100)
        let upcoming = Date().addingTimeInterval(60)
        center.debugApplyPokeathlon(race: PokeathlonRace(racers: [runner], startsAt: upcoming),
                                    pool: pool)

        let open = try #require(center.terminalState.track)
        #expect(open.canBet)
        #expect(!open.canMove, "출발 전인데 달릴 수 있다고 실었다")
        #expect(open.pot == 500)
        #expect(open.myBet == ArenaScreen.Bet(runnerName: "이웃", amount: 400))
        #expect((open.secondsLeft ?? 0) > 0)

        var closed = pool
        closed.isClosed = true
        center.debugApplyPokeathlon(race: PokeathlonRace(racers: [runner], startsAt: upcoming),
                                    pool: closed)
        #expect(center.terminalState.track?.canBet == false, "닫힌 원장에 베팅을 열었다")
    }

    /// 우승자가 나오면 그 이름이 실린다 — 없으면 사용자는 경기가 끝난 줄 모른다.
    @Test func testAFinishedRaceCarriesItsWinner() throws {
        let (center, directory) = makeCenter("arena-seam-race-end")
        defer { try? FileManager.default.removeItem(at: directory) }
        var winner = PokeathlonRacer(id: UUID(), trainerName: "이웃", speciesID: 4)
        winner.distance = PokeathlonRace.finishLine
        winner.finished = true
        var race = PokeathlonRace(racers: [winner], startsAt: Date(timeIntervalSince1970: 0))
        race.winnerID = winner.id
        center.debugApplyPokeathlon(race: race)

        let state = center.terminalState
        #expect(state.track?.winnerName == "이웃")
        #expect(RoomScreen.kind(state) == .finished)
    }

    /// 퀴즈는 **문항과 내 위치**가 전부다. 정답 공개 중에는 못 움직인다 —
    /// 그때 방향을 권하면 눌러도 아무 일이 없다(`PokemonOXGame.move` 가 먼저 본다).
    @Test func testAQuizCarriesTheQuestionMyChoiceAndTheRevealLock() throws {
        let (center, directory) = makeCenter("arena-seam-quiz")
        defer { try? FileManager.default.removeItem(at: directory) }
        var me = PokemonOXPlayer(id: center.myID, trainerName: "나", speciesID: 1)
        me.position = 0.5                                  // O 쪽에 서 있다
        me.score = 20
        let rival = PokemonOXPlayer(id: UUID(), trainerName: "이웃", speciesID: 4)
        let question = PokemonOXQuestion(id: 1, speciesID: 1, ko: "불꽃타입은 물에 강하다.",
                                         en: "Fire beats Water.", ja: "ほのおはみずに強い。",
                                         answer: false)
        center.debugApplyPokemonQuiz(PokemonOXGame(players: [me, rival], questions: [question]))

        let running = try #require(center.terminalState.track)
        #expect(running.question == "불꽃타입은 물에 강하다.")
        #expect(running.myChoice == "O (참)")
        #expect(running.canMove)
        // 점수 내림차순이라 내가 먼저다.
        #expect(running.standings.map(\.label) == ["나", "이웃"])
        #expect(running.standings.first?.right.contains("20") == true)

        var revealing = PokemonOXGame(players: [me, rival], questions: [question])
        revealing.reveal()
        center.debugApplyPokemonQuiz(revealing)
        #expect(center.terminalState.track?.canMove == false, "공개 중에 방향을 열었다")
        // **판정과 화면이 같은 함수를 본다** — 0.5 는 O 이고 정답은 거짓이라 틀렸다.
        #expect(center.terminalState.track?.standings.first { $0.isMine }?
            .right.contains("✗") == true)
    }

    /// 판이 없으면 결투도 트랙도 없다 — `nil` 이라야 화면이 전투원 목록 경로로 돌아간다.
    @Test func testNoMatchMeansNoDuelAndNoTrack() throws {
        let (center, directory) = makeCenter("arena-seam-empty")
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = center.terminalState

        #expect(state.duel == nil)
        #expect(state.track == nil)
        #expect(RoomScreen.kind(state) == .none)
    }
}
