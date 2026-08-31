import SwiftUI

/// 체육관 쟁탈전 — 이긴 사람이 관장이 된다.
///
/// **친구 탭에 산다.** 도전 탭이 아닌 이유는 둘이다. 하나는 그 탭의 원칙("친구 탭은 남과 하는 것,
/// 도전 탭은 혼자 하는 것", `ChallengeView` 머리 주석)이고, 다른 하나는 구조다 — 도전 탭은 방이
/// 돌아가는 중이면 목록을 통째로 감추므로(`ChallengeView.body`), 거기 두면 **관장이 되는 순간
/// 자기 체육관으로 들어가는 문이 사라진다.**
struct PlayerGymView: View {
    let store: CompanionStore
    let center: MultiplayerRoomCenter
    let onClose: () -> Void

    @Environment(PlayerGymCoordinator.self) private var coordinator
    /// 관장 화면의 카운트다운을 1초마다 다시 그리는 신호. 남은 시간이 화면에서 멈춰 있으면
    /// 마감이 지난 줄 모른 채 자격을 잃는다.
    @State private var tick = Date()

    private var l: L { store.l }
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let error = center.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
            notices
            if let match = center.gymMatch {
                matchView(match)
            } else if store.isGymLeader {
                leaderSetup
            } else {
                browser
            }
        }
        .padding(.vertical, 4)
        .onAppear { coordinator.refresh() }
        .onReceive(ticker) { now in
            tick = now
            // 마감은 화면이 떠 있는 동안에도 지날 수 있다 — 그때 자격이 풀려야 방어팀 잠금도 함께 풀린다.
            if store.isGymLeader, coordinator.setupSecondsRemaining == 0 { coordinator.refresh() }
        }
    }

    private var header: some View {
        HStack {
            Label(l.playerGymTitle, systemImage: "building.columns.fill")
                .font(.title3.bold()).foregroundStyle(.purple)
            Spacer()
            Button { onClose() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var notices: some View {
        if coordinator.blockedByExistingGym {
            noticeRow(l.playerGymAlreadyOpen, tint: .orange)
        }
        if coordinator.yieldedToExistingGym {
            noticeRow(l.playerGymAlreadyOpen, tint: .secondary)
        }
        if center.gymLeaderAbandonedMatch {
            VStack(alignment: .leading, spacing: 6) {
                Text(l.playerGymLeaderLeft).font(.caption.bold())
                HStack {
                    Button(l.playerGymTakeOver) { coordinator.takeOverAbandonedGym() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button(l.t("나중에", "Later", "あとで")) { center.dismissGymTakeoverOffer() }
                        .controlSize(.small)
                }
            }.padding(8).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        if let rejection = center.gymRejection {
            noticeRow(rejectionText(rejection), tint: .orange)
        }
    }

    private func noticeRow(_ text: String, tint: Color) -> some View {
        Text(text).font(.caption).foregroundStyle(tint)
    }

    private func rejectionText(_ rejection: GymChallengeRejection) -> String {
        switch rejection {
        case .busy: return l.playerGymRejectedBusy
        case .notReady: return l.playerGymRejectedNotReady
        case .cooldown(let seconds):
            return l.playerGymCooldownRemaining(MenuBarStatus.remainingClockText(seconds: seconds))
        }
    }

    // MARK: 관장이 아닐 때 — 체육관을 찾거나 연다

    private var browser: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let room = center.visibleGymRoom {
                VStack(alignment: .leading, spacing: 6) {
                    // 방 이름 원문(`GYM · 4k2p · 현우#abc123`)은 사람이 읽을 것이 아니다 —
                    // 실려 온 값을 풀어 "누가 몇 분째 지키는지"로 그린다.
                    if let parsed = PlayerGymRoomName.parse(room.serviceName) {
                        Text(l.playerGymTenure(
                            parsed.leaderName,
                            l.playerGymDuration(
                                minutes: PlayerGym.tenureMinutes(since: parsed.heldSince, now: tick))))
                            .font(.caption.bold()).lineLimit(1)
                    } else {
                        Text(room.name).font(.caption.bold()).lineLimit(1)
                    }
                    Text(l.t("도전 팀 4마리를 고르고 도전하세요.",
                             "Pick four Pokémon and challenge.",
                             "4体を選んで挑戦してください。"))
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button(l.playerGymChallenge) {
                            center.join(room, as: .runner)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(center.gymPickedTeam.count != PlayerGym.defenseTeamSize)
                        Button(l.playerGymSpectate) { center.join(room, as: .spectator) }
                            .controlSize(.small)
                    }
                }.padding(9).pokedoroCard(tint: .purple)

                TeamPicker(store: store,
                           selection: Binding(get: { center.gymPickedTeam },
                                              set: { center.gymPickedTeam = $0 }),
                           limit: PlayerGym.defenseTeamSize)
            } else if coordinator.isDiscoveryUnavailable {
                // 탐색이 꺼져 있으면 아무리 기다려도 방이 안 나타난다 — 그걸 "검색 중" 으로
                // 보여주면 고장으로 읽힌다. 무엇을 켜야 하는지 말해 준다.
                VStack(alignment: .leading, spacing: 6) {
                    Label(l.playerGymDiscoveryOff, systemImage: "wifi.slash")
                        .font(.caption).foregroundStyle(.orange)
                    Text(l.playerGymDiscoveryOffHint).font(.caption2).foregroundStyle(.secondary)
                }
            } else if !coordinator.hasScannedOnce {
                // 빈 목록을 "없음" 으로 읽으면 단일성 정책이 무의미해진다 — 스캔 전에는 열지 못한다.
                // 이 상태는 `PlayerGymCoordinator.scanWindow` 뒤에 반드시 끝난다(방 개수 변화가
                // 아니라 시간으로 넘긴다 — 방이 하나도 없으면 개수는 영영 안 바뀐다).
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(l.playerGymSearching).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(l.t("열린 체육관이 없습니다. 직접 열어 관장이 되어 보세요.",
                         "No gym is open. Open one and become the leader.",
                         "開いているジムがありません。自分で開いてリーダーになりましょう。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(l.playerGymOpen) { coordinator.openGym() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            if center.phase == .joined {
                Button(l.playerGymChallenge) { center.challengeGym() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            // 자리를 내준 뒤에도 누가 꺾었는지는 봐야 한다 — 기록은 자격과 무관하게 남는다.
            if !store.gymDefenseLog.isEmpty { defenseLog }
        }
    }

    // MARK: 관장일 때 — 방어팀을 세우고 도전을 기다린다

    private var leaderSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let deadline = store.gymLeadership?.defenseDeadline {
                // 넘기면 자격이 날아간다. 조용한 안내로 두면 안 되는 종류라 크게 센다.
                let remaining = max(0, deadline.timeIntervalSince(tick))
                let clockText = MenuBarStatus.remainingClockText(deadline, at: tick)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clockText)
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(remaining <= 60 ? .red : .orange)
                    Text(l.playerGymSetupCountdown(clockText))
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(9).pokedoroCard(tint: remaining <= 60 ? .red : .orange)
            } else {
                Label(l.t("도전을 기다리는 중입니다.", "Waiting for challengers.", "挑戦を待っています。"),
                      systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            if let held = store.gymLeadership?.heldSince {
                Text(l.playerGymTenure(
                    store.state.trainerName,
                    l.playerGymDuration(minutes: PlayerGym.tenureMinutes(since: held, now: tick))))
                    .font(.caption.bold()).foregroundStyle(.purple)
            }
            HStack(spacing: 6) {
                if let streak = store.gymLeadership?.consecutiveDefenses, streak > 0 {
                    Text(l.playerGymStreak(streak))
                        .font(.caption2.bold()).foregroundStyle(.green)
                }
                // 하루 상한이 있는 보상이라 남은 몫이 보여야 한다 — 안 보이면 왜 0 이 들어왔는지 모른다.
                Text(l.playerGymDefenseLedger(store.gymDefenseEarnedToday,
                                              PlayerGym.dailyDefenseRewardCap))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Text(l.playerGymDefenseTeam).font(.caption.bold())
            TeamPicker(store: store,
                       selection: Binding(get: { store.gymLeadership?.defenseMonIDs ?? [] },
                                          set: { store.setGymDefenseTeam($0) }),
                       limit: PlayerGym.defenseTeamSize)

            Toggle(l.playerGymUsesAI,
                   isOn: Binding(get: { store.gymLeadership?.usesAI ?? false },
                                 set: { store.setGymUsesAI($0) }))
                .controlSize(.small)
            Text(l.playerGymAIHint).font(.caption2).foregroundStyle(.secondary)

            Button(l.playerGymResign, role: .destructive) { coordinator.resign() }
                .controlSize(.small)

            defenseLog
        }
    }

    /// 누가 언제 도전했고 어떻게 됐나. **자리를 내준 판도 남는다** — 누가 나를 꺾었는지가
    /// 기록에서 가장 궁금한 줄이라, 관장이 아닌 동안에도 볼 수 있게 목록 화면에서도 그린다.
    @ViewBuilder private var defenseLog: some View {
        Divider().opacity(0.5)
        Text(l.playerGymDefenseLogTitle).font(.caption.bold())
        if store.gymDefenseLog.isEmpty {
            Text(l.playerGymDefenseLogEmpty).font(.caption2).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(store.gymDefenseLog.prefix(8)) { record in
                    HStack(spacing: 6) {
                        Image(systemName: record.defended ? "shield.fill" : "flag.slash.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(record.defended ? Color.green : Color.orange)
                        Text(record.challengerName).font(.caption2.bold()).lineLimit(1)
                        Text(record.defended ? l.playerGymDefended : l.playerGymYielded)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(record.defended ? Color.green : Color.orange)
                        if record.payout > 0 {
                            Text("⭐ \(GameNumberFormatter.compact(record.payout))")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 2)
                        Text(l.playerGymTimeAgo(l.playerGymDuration(
                            minutes: PlayerGym.tenureMinutes(since: record.at, now: tick))))
                            .font(.system(size: 8)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: 배틀 — 참가자는 조작하고 관전자는 보기만 한다

    @ViewBuilder private func matchView(_ match: GymMatchState) -> some View {
        let amLeader = match.leaderID == center.myID
        let amChallenger = match.challengerID == center.myID
        let amPlaying = amLeader || amChallenger
        let mine = amLeader ? match.leaderTeam : match.challengerTeam
        let theirs = amLeader ? match.challengerTeam : match.leaderTeam
        let myActive = amLeader ? match.leaderActive : match.challengerActive
        let theirActive = amLeader ? match.challengerActive : match.leaderActive

        VStack(alignment: .leading, spacing: 8) {
            Text("\(match.leaderName)  VS  \(match.challengerName)")
                .font(.caption.bold()).frame(maxWidth: .infinity)

            if let winner = match.winnerID {
                let name = winner == match.leaderID ? match.leaderName : match.challengerName
                Text(l.t("\(name) 승리!", "\(name) wins!", "\(name)の勝利！"))
                    .font(.headline).frame(maxWidth: .infinity)
                if winner == center.myID, amChallenger { Text(l.playerGymBecameLeader).font(.caption) }
                if winner != center.myID, amLeader { Text(l.playerGymLostLeadership).font(.caption) }
                // 방어 보상은 관장에게만, 그리고 **이긴 경우에만** 나간다. 0 이면 상한에 걸린 것이라
                // 그 사실을 말해 준다 — 안 그러면 보상이 사라진 줄 안다.
                if amLeader, winner == center.myID, let payout = center.lastGymDefensePayout {
                    Text(payout > 0 ? l.playerGymDefenseReward(payout) : l.playerGymDefenseCapped)
                        .font(.caption.bold())
                        .foregroundStyle(payout > 0 ? Color.orange : Color.secondary)
                }
            } else if amPlaying,
                      mine.indices.contains(myActive), theirs.indices.contains(theirActive) {
                playerArena(match, mine: mine, theirs: theirs,
                            myActive: myActive, theirActive: theirActive, amLeader: amLeader)
            } else if mine.indices.contains(myActive) || !theirs.isEmpty {
                spectatorArena(match)
            }
        }
    }

    private func playerArena(_ match: GymMatchState,
                             mine: [TournamentPokemonState], theirs: [TournamentPokemonState],
                             myActive: Int, theirActive: Int, amLeader: Bool) -> some View {
        let mySides = mine.map(\.side)
        let theirSides = theirs.map(\.side)
        // 관장은 배틀 엔진의 A 자리다 — 로그의 "내 편" 판정이 그 자리를 따라간다.
        let myActor: BattleActor = amLeader ? .a : .b
        let submitted = match.submitted.contains(center.myID)
        return BattleArenaView(
            mine: mySides[myActive], theirs: theirSides[theirActive],
            myTitle: l.battleMyPokemon,
            theirTitle: amLeader ? match.challengerName : l.playerGymLeaderLabel(match.leaderName),
            l: l, turn: match.turn,
            logLines: logLines(match),
            myActor: myActor,
            switchSlots: SwitchStripModel.slots(mySides, active: myActive),
            turnEndsAt: center.turnEndsAt,
            isWaitingForOpponent: submitted,
            onChoose: { index in center.submitGymAction(.move(index: index)) },
            onSwitch: { index in center.submitGymAction(.switchTo(index: index)) },
            onForfeit: { center.leaveRoom(); onClose() },
            chat: BattleChatConfiguration(
                messages: center.chatMessages, mySenderID: center.myID,
                isEnabled: true, unavailableMessage: nil, l: l, onSend: center.sendChat))
    }

    /// 관전은 콜백이 없는 조합으로 만든다 — `BattleArenaView` 를 쓰면 항복 버튼이 늘 그려지고
    /// `myActor` 가 필수라 제3자 자리를 표현할 수 없다.
    private func spectatorArena(_ match: GymMatchState) -> some View {
        let leader = match.leaderTeam.map(\.side)
        let challenger = match.challengerTeam.map(\.side)
        return VStack(alignment: .leading, spacing: 6) {
            Label(l.t("관전 중입니다.", "Spectating.", "観戦中です。"), systemImage: "eye.fill")
                .font(.caption).foregroundStyle(.secondary)
            if leader.indices.contains(match.leaderActive), challenger.indices.contains(match.challengerActive) {
                BattleFieldView(mine: leader[match.leaderActive],
                                theirs: challenger[match.challengerActive],
                                myTitle: l.playerGymLeaderLabel(match.leaderName),
                                theirTitle: match.challengerName,
                                l: l)
            }
            // 관전자는 어느 편도 아니다 — `myActor: nil` 이면 한쪽만 진하게 그리지 않는다.
            BattleLogBox(lines: logLines(match), myActor: nil)
            BattleChatPanel(configuration: BattleChatConfiguration(
                messages: center.chatMessages, mySenderID: center.myID,
                isEnabled: true, unavailableMessage: nil, l: l, onSend: center.sendChat))
        }
    }

    /// 그 턴의 이벤트를 로그 줄로 접는다. 기술은 **팀 전체**에서 찾는다 — 활성 자리만 보면 그 턴에
    /// 쓰러져 교체된 개체의 기술이 안 잡힌다.
    private func logLines(_ match: GymMatchState) -> [BattleLog.Line] {
        func moves(for actor: BattleActor) -> [MoveSpec] {
            (actor == .a ? match.leaderTeam : match.challengerTeam).flatMap { $0.side.moves }
        }
        return BattleLog.lines(match.events, l: l,
                               name: { $0 == .a ? match.leaderName : match.challengerName },
                               move: { actor, id in moves(for: actor).first { $0.id == id } ?? .struggle() })
    }
}
