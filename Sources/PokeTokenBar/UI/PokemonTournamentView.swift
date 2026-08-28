import SwiftUI

struct PokemonTournamentView: View {
    let store: CompanionStore
    let center: MultiplayerRoomCenter
    let onClose: () -> Void

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
            Text(store.l.t("출전 파티 · 전원 Lv.50", "Tournament team · all Lv.50", "出場パーティ・全員 Lv.50"))
                .font(.caption.bold())
            TeamPicker(store: store,
                       selection: Binding(get: { center.tournamentPickedTeam },
                                          set: { center.tournamentPickedTeam = $0 }), limit: 3)
            Button(store.l.t("8인 토너먼트 방 만들기", "Create tournament room", "トーナメント部屋を作る")) {
                center.createTournamentRoom()
            }.buttonStyle(.borderedProminent).disabled(center.tournamentPickedTeam.count != 3)
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
                            .controlSize(.small).disabled(center.tournamentPickedTeam.count != 3)
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
            } else if let match = state.currentMatch { matchView(match, state: state) }
        }
    }

    private func matchView(_ match: TournamentMatchState, state: PokemonTournamentState) -> some View {
        let mineIsA = match.playerA == center.myID
        let mineIsB = match.playerB == center.myID
        let amPlaying = mineIsA || mineIsB
        let myTeam = mineIsA ? match.teamA : match.teamB
        let myActive = mineIsA ? match.activeA : match.activeB
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.l.t("\(match.round)라운드", "Round \(match.round)", "第\(match.round)ラウンド"))
                    .font(.caption.bold()).foregroundStyle(.orange)
                Spacer()
                Text("\(match.nameA)  VS  \(match.nameB)").font(.caption.bold())
            }
            HStack(spacing: 12) {
                tournamentSide(match.teamA, active: match.activeA, name: match.nameA)
                Text("VS").font(.title3.weight(.black)).foregroundStyle(.red)
                tournamentSide(match.teamB, active: match.activeB, name: match.nameB)
            }
            if let winner = match.winnerID {
                let name = winner == match.playerA ? match.nameA : match.nameB
                Text(store.l.t("\(name) 승리! 다음 대진을 준비합니다.", "\(name) wins! Preparing the next match.",
                               "\(name)の勝利！次の対戦を準備します。"))
                    .font(.headline).frame(maxWidth: .infinity)
            } else if !amPlaying {
                Label(store.l.t("현재 경기를 관전 중입니다.", "You are spectating this match.", "この試合を観戦中です。"),
                      systemImage: "eye.fill").font(.caption).foregroundStyle(.secondary)
            } else if match.submitted.contains(center.myID) {
                HStack { ProgressView().controlSize(.small); Text(store.l.t("상대의 선택을 기다리는 중…", "Waiting for opponent…", "相手を待っています…")) }
                    .font(.caption).foregroundStyle(.secondary)
            } else if myTeam.indices.contains(myActive) {
                let active = myTeam[myActive].side
                if active.isAlive {
                    MoveGridView(moves: active.mustStruggle ? [.struggle()] : active.moves,
                                 pp: active.mustStruggle ? [] : active.pp, language: store.language,
                                 isEnabled: true) { index in
                        center.submitTournamentAction(.move(index: active.mustStruggle ? -1 : index))
                    }
                } else {
                    Label(store.l.t("다음에 내보낼 포켓몬을 선택하세요.",
                                    "Choose the next Pokémon to send out.",
                                    "次に出すポケモンを選んでください。"),
                          systemImage: "arrow.triangle.swap")
                        .font(.headline).foregroundStyle(.orange)
                }
                HStack {
                    ForEach(myTeam.indices.filter { $0 != myActive && myTeam[$0].hp > 0 }, id: \.self) { index in
                        Button(store.l.t("교체: \(myTeam[index].snapshot.name)", "Switch: \(myTeam[index].snapshot.name)",
                                         "交代：\(myTeam[index].snapshot.name)")) {
                            center.submitTournamentAction(.switchTo(index: index))
                        }.controlSize(.mini)
                    }
                }
            }
            if !match.events.isEmpty {
                BattleLogBox(lines: tournamentLogLines(match),
                            myActor: mineIsA ? .a : (mineIsB ? .b : nil))
            }
            BattleChatPanel(configuration: BattleChatConfiguration(
                messages: center.chatMessages, mySenderID: center.myID,
                isEnabled: true, unavailableMessage: nil, l: store.l,
                onSend: center.sendChat))
            bracket(state)
        }
    }

    /// 대진 하나(1v1)의 스트림을 로그 줄로 접는다 — `BattleLogSource.twoSided` 와 같은 결이지만,
    /// 토너먼트는 `TournamentMatchState`에 그 턴의 원본 이벤트만 오므로 여기서 직접 접는다.
    /// 기술은 팀 전체(교체로 빠진 자리 포함)에서 id 로 찾는다 — 활성 자리만 보면, 그 턴에 쓰러져
    /// 교체된 포켓몬의 기술이 안 잡힌다.
    private func tournamentLogLines(_ match: TournamentMatchState) -> [BattleLog.Line] {
        func moves(for actor: BattleActor) -> [MoveSpec] {
            (actor == .a ? match.teamA : match.teamB).flatMap { $0.side.moves }
        }
        return BattleLog.lines(match.events, l: store.l,
                               name: { $0 == .a ? match.nameA : match.nameB },
                               move: { actor, id in moves(for: actor).first { $0.id == id } ?? .struggle() })
    }

    private func tournamentSide(_ team: [TournamentPokemonState], active: Int, name: String) -> some View {
        VStack(spacing: 4) {
            Text(name).font(.caption.bold()).lineLimit(1)
            if team.indices.contains(active) {
                let mon = team[active]
                SpriteView(speciesID: mon.snapshot.speciesID, size: 62, shiny: mon.snapshot.isShiny)
                ProgressView(value: Double(mon.hp), total: Double(max(1, mon.side.stats.hp)))
                    .tint(HPTier.of(hp: mon.hp, max: mon.side.stats.hp).color)
            }
            HStack(spacing: 3) {
                ForEach(team.indices, id: \.self) { i in
                    Circle().fill(team[i].hp > 0 ? Color.green : Color.gray)
                        .frame(width: 7, height: 7).overlay(i == active ? Circle().stroke(.white) : nil)
                }
            }
        }.frame(maxWidth: .infinity).padding(7).pokedoroCard()
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
        Text(store.l.t("우승 보상: 2~3명 일반 알 · 4~5명 고급 알 · 6~8명 희귀 알 (전설 알 제외)",
                       "Champion reward: 2–3 standard · 4–5 uncommon · 6–8 rare Egg (no legendary Egg)",
                       "優勝報酬：2〜3人 通常・4〜5人 上級・6〜8人 レア（伝説タマゴなし）"))
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
