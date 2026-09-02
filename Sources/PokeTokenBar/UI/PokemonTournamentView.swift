import SwiftUI

struct PokemonTournamentView: View {
    let store: CompanionStore
    let center: MultiplayerRoomCenter
    let onClose: () -> Void
    @Environment(AppSettings.self) private var settings
    @State private var animator = BattleAnimator()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.l.t("포켓몬 토너먼트", "Pokémon Tournament", "ポケモントーナメント"),
                      systemImage: "trophy.fill").font(.title3.bold()).foregroundStyle(.orange)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            switch center.phase {
            case .idle: browser
            case .creating, .joining: ProgressView(store.l.t("토너먼트 방에 연결 중…", "Connecting…", "接続中…"))
            case .hosting, .joined: lobby
            case .tournament: tournament
            default: browser
            }
            if let error = center.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(.vertical, 4)
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.l.t("후보 6마리 · 전원 Lv.50", "Six candidates · all Lv.50", "候補6匹・全員 Lv.50"))
                .font(.caption.bold())
            TeamPicker(store: store,
                       selection: Binding(get: { center.tournamentPickedTeam },
                                          set: { center.tournamentPickedTeam = $0 }), limit: 6)
            Button(store.l.t("8인 토너먼트 방 만들기", "Create tournament room", "トーナメント部屋を作る")) {
                center.createTournamentRoom()
            }.buttonStyle(.borderedProminent).disabled(center.tournamentPickedTeam.count != 6)
            Divider()
            Text(store.l.t("참가 가능한 방", "Available rooms", "参加できる部屋")).font(.caption.bold())
            let rooms = center.rooms.filter { $0.name.hasPrefix("TOUR ·") }
            if rooms.isEmpty {
                Text(store.l.t("토너먼트 방을 찾는 중…", "Looking for tournaments…", "大会を検索中…"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(rooms) { room in
                    HStack {
                        Text(room.name).font(.caption).lineLimit(1)
                        Spacer()
                        Button(store.l.t("참가", "Join", "参加")) { center.join(room) }
                            .controlSize(.small).disabled(center.tournamentPickedTeam.count != 6)
                    }
                }
            }
            rewardGuide
        }
    }

    private var lobby: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(store.l.t("참가자 로비 (2~8명)", "Tournament lobby (2–8)", "参加者ロビー（2〜8人）"))
                .font(.headline)
            if let lobby = center.lobby {
                ForEach(lobby.runners) { player in
                    HStack {
                        SpriteView(speciesID: player.speciesID, size: 28)
                        Text(player.trainerName).font(.caption.bold())
                        if player.isHost { Text("HOST").font(.system(size: 8)).foregroundStyle(.orange) }
                        Spacer()
                        Image(systemName: player.isReady ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(player.isReady ? .green : .secondary)
                    }.padding(5).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                    if let pool = center.tournamentPools[player.id] {
                        HStack(spacing: 4) {
                            ForEach(Array(pool.enumerated()), id: \.offset) { _, snapshot in
                                SpriteView(speciesID: snapshot.speciesID, size: 25, shiny: snapshot.isShiny)
                            }
                        }
                    }
                }
                if center.tournamentPools[center.myID]?.count == 6 {
                    Text(store.l.t("공개된 후보 중 실제 출전할 3마리", "Choose three from your revealed pool",
                                   "公開した候補から出場する3匹"))
                        .font(.caption.bold())
                    TeamPicker(store: store,
                               selection: Binding(get: { center.tournamentFinalTeam },
                                                  set: { center.tournamentFinalTeam = $0 }),
                               limit: 3, allowedIDs: Set(center.tournamentPickedTeam))
                    Button(store.l.t("출전 3마리 확정", "Confirm three", "出場3匹を確定")) {
                        center.confirmTournamentTeam()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(center.tournamentFinalTeam.count != 3)
                }
                Text(store.l.t("참가자가 많을수록 우승 알의 등급이 올라갑니다.",
                               "More entrants improve the champion Egg.",
                               "参加者が多いほど優勝タマゴの等級が上がります。"))
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button(center.myParticipant?.isReady == true
                           ? store.l.t("준비 취소", "Cancel ready", "準備取消")
                           : store.l.t("준비", "Ready", "準備")) { center.toggleReady() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Spacer()
                    if center.isHost, lobby.canStart {
                        Button(store.l.t("대진 시작", "Start bracket", "対戦開始")) { center.startTournament() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    Button(store.l.t("나가기", "Leave", "退出")) { close() }.controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder private var tournament: some View {
        if let state = center.tournamentState {
            if let champion = state.champion {
                VStack(spacing: 12) {
                    Image(systemName: "trophy.fill").font(.system(size: 52)).foregroundStyle(.yellow)
                    Text(store.l.t("우승: \(champion.trainerName)", "Champion: \(champion.trainerName)",
                                   "優勝：\(champion.trainerName)"))
                        .font(.title2.bold())
                    Text(rewardName(state.reward)).font(.headline).foregroundStyle(.orange)
                    Button(store.l.t("나가기", "Leave", "退出")) { close() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if let match = state.currentMatch {
                matchView(match, state: state)
            } else if let revealUntil = state.bracketRevealUntil {
                openingBracket(state, until: revealUntil)
            }
        }
    }

    private func openingBracket(_ state: PokemonTournamentState, until: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(store.l.t("대진 추첨 완료!", "Bracket Draw Complete!", "対戦カード決定！"),
                      systemImage: "trophy.fill").font(.title3.bold()).foregroundStyle(.orange)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(max(0, Int(until.timeIntervalSince(context.date).rounded(.up))))s")
                        .font(.headline.monospacedDigit()).foregroundStyle(.orange)
                }
            }
            Text(store.l.t("첫 라운드 대진입니다. 10초 후 첫 경기가 시작됩니다.",
                           "First-round pairings. The opening match begins in 10 seconds.",
                           "1回戦の組み合わせです。10秒後に開始します。"))
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 10) {
                ForEach(state.openingMatches ?? []) { match in
                    HStack(spacing: 8) {
                        entrantCard(state, id: match.playerA)
                        Text("VS").font(.headline.weight(.black)).foregroundStyle(.orange)
                        entrantCard(state, id: match.playerB)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.09)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.28)))
                }
                // 홀수 인원의 부전승자. 짝이 없어 경기 줄에는 못 들어가지만 표에서 사라지면
                // 본인은 올라간 줄 모르고 다른 참가자는 왜 안 뛰는지 모른다.
                ForEach(state.byeEntrants) { entrant in
                    HStack(spacing: 8) {
                        entrantCard(state, id: entrant.id)
                        Text(store.l.t("부전승", "Bye", "不戦勝"))
                            .font(.caption.bold()).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.18)))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
    }

    private func entrantCard(_ state: PokemonTournamentState, id: UUID) -> some View {
        let entrant = state.entrants.first { $0.id == id }
        return VStack(spacing: 3) {
            SpriteView(speciesID: entrant?.speciesID ?? 0, size: 38)
            Text(entrant?.trainerName ?? "?").font(.caption.bold()).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }

    private func matchView(_ match: TournamentMatchState, state: PokemonTournamentState) -> some View {
        let mineIsA = match.playerA == center.myID
        let mineIsB = match.playerB == center.myID
        let amPlaying = mineIsA || mineIsB
        // 관전자는 대진표의 A를 왼쪽(내 편 자리)에 둔다. 참가자는 언제나 자기 팀이 내 편 자리에 온다.
        let viewingB = mineIsB
        let engineMyTeam = viewingB ? match.teamB : match.teamA
        let engineTheirTeam = viewingB ? match.teamA : match.teamB
        let myActive = viewingB ? match.activeB : match.activeA
        let theirActive = viewingB ? match.activeA : match.activeB
        let myActor: BattleActor = viewingB ? .b : .a
        let theirActor: BattleActor = viewingB ? .a : .b
        let engineMine = ReplaySide(team: engineMyTeam.map(\.side), active: myActive)
        let engineTheirs = ReplaySide(team: engineTheirTeam.map(\.side), active: theirActive)
        let shownMine = animator.side(for: myActor) ?? engineMine
        let shownTheirs = animator.side(for: theirActor) ?? engineTheirs
        let myName = viewingB ? match.nameB : match.nameA
        let theirName = viewingB ? match.nameA : match.nameB
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.l.t("\(match.round)라운드", "Round \(match.round)", "第\(match.round)ラウンド"))
                    .font(.caption.bold()).foregroundStyle(.orange)
                Spacer()
                Text("\(match.nameA)  VS  \(match.nameB)").font(.caption.bold())
            }
            if let winner = match.winnerID {
                let name = winner == match.playerA ? match.nameA : match.nameB
                Text(store.l.t("\(name) 승리! 다음 대진을 준비합니다.", "\(name) wins! Preparing the next match.",
                               "\(name)の勝利！次の対戦を準備します。"))
                    .font(.headline).frame(maxWidth: .infinity)
            }
            if let shownMySide = shownMine.side, let shownTheirSide = shownTheirs.side {
                BattleArenaView(
                    mine: shownMySide,
                    theirs: shownTheirSide,
                    myTitle: myName, theirTitle: theirName,
                    l: store.l, turn: match.turn,
                    logLines: tournamentLogLines(match, playedCount: animator.playedCount), myActor: myActor,
                    switchSlots: SwitchStripModel.battleSlots(shownMine.team, active: shownMine.active),
                    turnEndsAt: center.turnEndsAt,
                    isWaitingForOpponent: amPlaying && match.submitted.contains(center.myID),
                    overlay: animator.overlay,
                    calledMoves: (match.teamA + match.teamB).flatMap { $0.side.moves },
                    allowsActions: amPlaying && match.winnerID == nil,
                    showsForfeit: false,
                    onChoose: { center.submitTournamentAction(.move(index: $0)) },
                    onSwitch: { center.submitTournamentAction(.switchTo(index: $0)) },
                    onForfeit: {},
                    chat: BattleChatConfiguration(messages: center.chatMessages, mySenderID: center.myID,
                                                  isEnabled: true, unavailableMessage: nil, l: store.l,
                                                  onSend: center.sendChat))
                .onAppear { replayTournament(match, mine: engineMine, theirs: engineTheirs,
                                             myActor: myActor, theirActor: theirActor) }
                .onChange(of: match.events.count) {
                    replayTournament(match, mine: engineMine, theirs: engineTheirs,
                                     myActor: myActor, theirActor: theirActor)
                }
                .onChange(of: match.id) {
                    replayTournament(match, mine: engineMine, theirs: engineTheirs,
                                     myActor: myActor, theirActor: theirActor)
                }
            }
            bracket(state)
        }
    }

    /// 대진 하나(1v1)의 스트림을 로그 줄로 접는다 — `BattleLogSource.twoSided` 와 같은 결이지만,
    /// 토너먼트는 `TournamentMatchState`에 누적된 원본 이벤트가 오므로 재생기가 소비한 데까지만 접는다.
    /// 기술은 팀 전체(교체로 빠진 자리 포함)에서 id 로 찾는다 — 활성 자리만 보면, 그 턴에 쓰러져
    /// 교체된 포켓몬의 기술이 안 잡힌다.
    private func tournamentLogLines(_ match: TournamentMatchState, playedCount: Int) -> [BattleLog.Line] {
        func moves(for actor: BattleActor) -> [MoveSpec] {
            (actor == .a ? match.teamA : match.teamB).flatMap { $0.side.moves }
        }
        return BattleLog.lines(Array(match.events.prefix(playedCount)), l: store.l,
                               name: { $0 == .a ? match.nameA : match.nameB },
                               move: { actor, id in moves(for: actor).first { $0.id == id } ?? .struggle() })
    }

    private func replayTournament(_ match: TournamentMatchState, mine: ReplaySide, theirs: ReplaySide,
                                  myActor: BattleActor, theirActor: BattleActor) {
        animator.sync(events: match.events, sides: [myActor: mine, theirActor: theirs],
                      speed: BattleReplay.effectiveSpeed(settings.battleReplaySpeed,
                        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
    }

    private func bracket(_ state: PokemonTournamentState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.l.t("대진표", "Bracket", "トーナメント表")).font(.caption.bold())
            ForEach(state.matches) { match in
                let a = state.entrants.first { $0.id == match.playerA }?.trainerName ?? "?"
                let b = state.entrants.first { $0.id == match.playerB }?.trainerName ?? "?"
                let winner = state.entrants.first { $0.id == match.winnerID }?.trainerName
                Text("R\(match.round) · \(a) vs \(b)\(winner.map { " → \($0)" } ?? "")")
                    .font(.caption2).foregroundStyle(match.winnerID == nil ? .primary : .secondary)
            }
        }.padding(7).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var rewardGuide: some View {
        Text(store.l.t("최소 3명 · 우승 보상: 3~4명 일반 알 · 5~6명 고급 알 · 7~8명 희귀 알 (전설 알 제외)",
                       "Minimum 3 · Champion reward: 3–4 standard · 5–6 uncommon · 7–8 rare Egg (no legendary Egg)",
                       "最低3人・優勝報酬：3〜4人 通常・5〜6人 上級・7〜8人 レア（伝説タマゴなし）"))
            .font(.caption2).foregroundStyle(.secondary)
    }

    private func rewardName(_ reward: TournamentEggReward) -> String {
        switch reward {
        case .standard: return store.l.t("일반 알 획득", "Standard Egg earned", "通常タマゴ獲得")
        case .uncommon: return store.l.t("고급 알 획득", "Uncommon Egg earned", "上級タマゴ獲得")
        case .rare: return store.l.t("희귀 알 획득", "Rare Egg earned", "レアタマゴ獲得")
        }
    }

    private func close() { center.leaveRoom(); onClose() }
}
