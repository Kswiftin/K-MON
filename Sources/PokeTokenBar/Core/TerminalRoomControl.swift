import Foundation

/// 터미널이 LAN 방에 닿는 **좁은 창구.** 근거는 `TerminalBattleControl` 과 같다 — 센터를 그대로
/// 넘기면 실행기 테스트가 listener·browser 를 살려 실제 LAN 으로 나간다.
///
/// **방을 만들거나 찾는 일은 없다.** 그건 소켓과 목록 훑기라 터미널이 할 수 있는 모양이 아니고,
/// 할 수 없는 일은 창구에 아예 없어야 한다(수락·파티 편성을 대전 창구에 안 둔 것과 같다).
///
/// 손을 내는 함수가 셋인 이유는 **판의 형태가 셋**이기 때문이다: 전투원 목록(레이드·방 대전),
/// 결투(체육관·토너먼트), 트랙(포켓슬론·퀴즈). 활동 여섯이 아니라 형태 셋이다 —
/// 활동별 라우팅은 센터 안 한 곳에 있다(`startActivity`·`submitDuelMove`·`submitTrackInput`).
@MainActor
protocol TerminalRoomControl: AnyObject {
    var terminalState: RoomTerminalState { get }
    /// 대상은 **id 로** 받는다. 번호 → id 변환은 목록을 아는 실행기가 `RoomScreen.targetID` 로 한다.
    func submitAction(targetID: UUID, moveIndex: Int)
    /// 결투의 기술 — **엔진 순번**(0부터)이다. 화면 번호를 그대로 넘기면 옆 기술이 나간다.
    func submitDuelMove(index: Int)
    /// 결투의 교체 — 팀 순번(0부터).
    func submitDuelSwitch(slot: Int)
    func submitTrackInput(_ input: ArenaTrackInput)
    /// 관전자 베팅. 러너 번호 → id 변환은 실행기가 `ArenaScreen.runnerID` 로 한다.
    func placeArenaBet(runnerID: UUID, stardust: Int)
    /// 호스트가 판을 시작한다. **활동별 시작 함수는 센터가 고른다** — 예전엔 터미널이
    /// `startRaid()` 만 불러서 레이드 아닌 방은 눌러도 아무 일이 없었다.
    func startActivity()
    func leaveRoom()
}

extension MultiplayerRoomCenter: TerminalRoomControl {
    var terminalState: RoomTerminalState {
        var state = RoomTerminalState(phase: phase, activity: roomActivity, myID: myID)
        state.round = combatRound
        state.fighters = combatFighters
        state.hasSubmitted = hasSubmittedAction
        state.isHost = isHost
        state.canStart = lobby?.canStart ?? false
        state.raidTier = raidTier
        // 승패·정산은 **센터가 이미 판정한 값**을 싣는다. 터미널이 전투원 목록으로 다시 세면
        // 팀전·관전자·무승부에서 갈라진다(그 네 갈래를 `myOutcome` 하나가 든다).
        state.outcome = isBattleFinished ? myOutcome : nil
        state.payout = raidPayout ?? settlementPayout
        // **형태가 다른 판은 따로 싣는다.** 체육관·토너먼트·포켓슬론·퀴즈의 판은
        // `combatFighters` 에 없어서, 예전 화면은 그 넷에서 빈 목록을 그리며 "판을 준비하는
        // 중이다" 를 판이 끝날 때까지 남겼다.
        state.duel = duelTerminalState
        state.track = trackTerminalState
        return state
    }

    // MARK: 결투 — 체육관과 토너먼트가 같은 값으로 접힌다

    /// 어느 결투가 도는가. **체육관은 `phase` 로 못 가른다** — 판이 도는 동안 국면은 `.hosting`
    /// 그대로다(`fillTimedOutActions` 가 같은 이유로 `gymMatch != nil` 을 먼저 본다).
    private var duelTerminalState: DuelTerminalState? {
        if let match = gymMatch { return duel(gym: match) }
        if let match = tournamentState?.currentMatch { return duel(tournament: match) }
        return nil
    }

    private func duel(gym match: GymMatchState) -> DuelTerminalState {
        // 관전자는 **관장을 왼쪽에** 둔다. 안 그러면 도전자 팀이 "내 팀" 자리에 실리고,
        // 내 것이 아닌 팀에 표시가 붙는다(`amFighting` 이 그 표시를 끈다).
        let amChallenger = match.challengerID == myID
        return duel(mySide: amChallenger ? match.challengerID : match.leaderID,
                    myName: amChallenger ? match.challengerName : match.leaderName,
                    theirName: amChallenger ? match.leaderName : match.challengerName,
                    myTeam: amChallenger ? match.challengerTeam : match.leaderTeam,
                    theirTeam: amChallenger ? match.leaderTeam : match.challengerTeam,
                    myActive: amChallenger ? match.challengerActive : match.leaderActive,
                    theirActive: amChallenger ? match.leaderActive : match.challengerActive,
                    turn: match.turn, caption: nil, submitted: match.submitted,
                    winnerID: match.winnerID,
                    winnerName: match.winnerID.map {
                        $0 == match.leaderID ? match.leaderName : match.challengerName
                    },
                    amFighting: match.leaderID == myID || amChallenger)
    }

    private func duel(tournament match: TournamentMatchState) -> DuelTerminalState {
        let amB = match.playerB == myID
        return duel(mySide: amB ? match.playerB : match.playerA,
                    myName: amB ? match.nameB : match.nameA,
                    theirName: amB ? match.nameA : match.nameB,
                    myTeam: amB ? match.teamB : match.teamA,
                    theirTeam: amB ? match.teamA : match.teamB,
                    myActive: amB ? match.activeB : match.activeA,
                    theirActive: amB ? match.activeA : match.activeB,
                    turn: match.turn, caption: "\(match.round) 라운드",
                    submitted: match.submitted, winnerID: match.winnerID,
                    winnerName: match.winnerID.map {
                        $0 == match.playerA ? match.nameA : match.nameB
                    },
                    amFighting: match.playerA == myID || amB)
    }

    /// 두 결투가 만나는 자리. **인자가 많은 대신 규칙이 한 벌이다** — 두 함수로 나누면 기술
    /// 목록·승패·표시가 두 곳이 되고, 한쪽만 고치는 부류가 그대로 생긴다.
    private func duel(mySide: UUID, myName: String, theirName: String,
                      myTeam: [TournamentPokemonState], theirTeam: [TournamentPokemonState],
                      myActive: Int, theirActive: Int, turn: Int, caption: String?,
                      submitted: Set<UUID>, winnerID: UUID?, winnerName: String?,
                      amFighting: Bool) -> DuelTerminalState {
        var duel = DuelTerminalState(myName: myName, theirName: theirName,
                                     mine: slots(myTeam, active: myActive),
                                     theirs: slots(theirTeam, active: theirActive))
        duel.turn = turn
        duel.caption = caption
        duel.amFighting = amFighting
        duel.hasSubmitted = submitted.contains(mySide)
        if amFighting, myTeam.indices.contains(myActive) {
            let side = myTeam[myActive].side
            duel.mustStruggle = side.mustStruggle
            duel.moves = moves(of: side)
        }
        duel.winnerName = winnerName
        // 관전자에게는 **줄 결과가 없다** — `nil` 이 그 뜻이고, 화면이 "이겼다/졌다" 대신
        // 승자만 찍는다(방 대전의 `myOutcome` 과 같은 규칙).
        duel.iWon = winnerID.flatMap { amFighting ? $0 == mySide : nil }
        return duel
    }

    private func slots(_ team: [TournamentPokemonState], active: Int) -> [ArenaScreen.Slot] {
        team.enumerated().map { index, state in
            let side = state.side
            return ArenaScreen.Slot(number: index + 1, id: UUID(),
                                    label: side.snapshot.name,
                                    hp: side.hp, maxHP: side.stats.hp,
                                    isActive: index == active,
                                    statusName: side.status.map(WaveRunScreen.statusName))
        }
    }

    /// 낼 수 있는 기술만. **번호는 엔진 순번 + 1** 이라 PP 가 떨어진 자리는 빠지고 번호에
    /// 구멍이 남는다 — 다시 매기면 사용자가 고른 것과 다른 기술이 나간다.
    private func moves(of side: BattleSide) -> [ArenaScreen.Move] {
        side.moves.indices.filter { side.canUse(moveAt: $0) }.map { index in
            ArenaScreen.Move(number: index + 1,
                             label: side.moves[index].name(displayLanguage),
                             pp: side.pp.indices.contains(index) ? side.pp[index] : 0,
                             maxPP: side.moves[index].pp)
        }
    }

    // MARK: 트랙 — 포켓슬론과 퀴즈가 같은 값으로 접힌다

    private var trackTerminalState: TrackTerminalState? {
        if let game = pokemonQuizGame { return track(quiz: game) }
        if let race = pokeathlonRace { return track(race: race) }
        return nil
    }

    private func track(quiz game: PokemonOXGame) -> TrackTerminalState {
        let ordered = game.standings
        var track = TrackTerminalState(standings: ordered.enumerated().map { index, player in
            ArenaScreen.Runner(number: index + 1, id: player.id, label: player.trainerName,
                               right: "\(TUIRender.number(player.score))점"
                                   + (player.lastCorrect.map { $0 ? " ✓" : " ✗" } ?? ""),
                               isMine: player.id == myID)
        })
        track.amRacing = game.players.contains { $0.id == myID }
        // 정답 공개 중에는 못 움직인다(`PokemonOXGame.move` 가 먼저 본다) — 그때 방향을
        // 권하면 눌러도 아무 일이 없다.
        track.canMove = !game.isRevealing && !game.isFinished
        track.question = game.currentQuestion.map(text(of:))
        track.myChoice = game.players.first { $0.id == myID }
            .map { PokemonOXGame.choice(at: $0.position) }
            .map { $0.map { $0 ? "O (참)" : "X (거짓)" } ?? "가운데" }
        track.secondsLeft = seconds(until: game.deadline)
        if game.isFinished { track.winnerName = ordered.first?.trainerName }
        return track
    }

    private func text(of question: PokemonOXQuestion) -> String {
        switch displayLanguage {
        case .ko: question.ko
        case .en: question.en
        case .ja: question.ja
        }
    }

    private func track(race: PokeathlonRace) -> TrackTerminalState {
        let ordered = race.racers.sorted {
            $0.distance == $1.distance ? $0.trainerName < $1.trainerName : $0.distance > $1.distance
        }
        var track = TrackTerminalState(standings: ordered.enumerated().map { index, racer in
            ArenaScreen.Runner(number: index + 1, id: racer.id, label: racer.trainerName,
                               right: "\(TUIRender.number(racer.distance))/"
                                   + "\(TUIRender.number(PokeathlonRace.finishLine))m"
                                   + (racer.crashes > 0 ? "  넘어짐 \(racer.crashes)" : ""),
                               isMine: racer.id == myID)
        })
        let now = Date()
        let mine = race.racers.first { $0.id == myID }
        track.amRacing = mine != nil
        // 출발 전에는 못 달린다(`PokeathlonRace.apply` 가 `now >= startsAt` 을 먼저 본다).
        track.canMove = race.winnerID == nil && now >= race.startsAt
        track.myChoice = mine.map { "레인 \($0.lane + 1)" }
        track.secondsLeft = seconds(until: race.startsAt)
        // 걸 수 있는 조건은 **호스트 검사기와 같은 셋**이다(`PokeathlonPool.rejection`):
        // 관전자이고, 원장이 열려 있고, 아직 출발 전이다.
        track.canBet = mine == nil && !pokeathlonPool.isClosed && now < race.startsAt
        track.pot = pokeathlonPool.total
        if let bet = pokeathlonPool.bets[myID],
           let runner = race.racers.first(where: { $0.id == bet.runnerID }) {
            track.myBet = ArenaScreen.Bet(runnerName: runner.trainerName, amount: bet.amount)
        }
        track.winnerName = race.racers.first { $0.id == race.winnerID }?.trainerName
        return track
    }

    /// 마감까지 남은 초. **이미 지났으면 `nil`** — 0 을 계속 찍으면 멈춘 화면으로 읽힌다.
    private func seconds(until deadline: Date) -> Int? {
        let remaining = deadline.timeIntervalSince(Date())
        return remaining > 0 ? Int(remaining.rounded(.up)) : nil
    }
}
