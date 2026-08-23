import AppKit
import SwiftUI

/// 배틀 탭 — 같은 네트워크(LAN) 실시간 대전. 상대 목록에서 신청하고, 신청이 오면
/// 알림+수락 화면, 대전 중엔 기술 4개 중 선택.
struct BattleView: View {
    @Bindable var store: CompanionStore
    @Environment(BattleCenter.self) private var center
    @Environment(PopoverNavigation.self) private var nav
    @Environment(AppSettings.self) private var settings
    /// 턴 해상 결과를 시간축에 푸는 재생기 — 배틀이 바뀌어도 같은 객체를 쓴다(스스로 되감는다).
    @State private var animator = BattleAnimator()

    // 수동(IP) 연결 상태
    @State private var manualAddress = ""
    @State private var addressCopied = false
    @State private var roomMode: MultiplayerBattleMode = .freeForAll
    @State private var multiplayerTargetID: UUID?
    @State private var peerPage = 0

    private var l: L { store.l }

    /// 한 페이지에 그리는 상대 수. 팝오버 안에서는 스크롤로 미룰 수 없어(defect-log) 이 목록도
    /// 세로 예산을 지켜야 한다. 다만 예산은 **한 번에 몇 명을 그리나**만 정하고, 넘치는 상대는
    /// 페이저로 넘겨서 본다. 예전엔 상한까지만 그리고 나머지를 "그 밖에 n명 더"로 알렸는데,
    /// 그건 도달성 처방이 아니라 잘리는 지점만 옮기던 도감·로스터 시절 실수를 되풀이한 것이었다.
    static let peerPageSize = 5

    /// 마지막 페이지가 덜 차도 한 페이지다. 아무도 없으면 빈 목록 한 장(페이저는 그리지 않는다).
    static func peerPageCount(_ peerCount: Int) -> Int {
        max(1, (peerCount + peerPageSize - 1) / peerPageSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.isEgg {
                Text(l.battleNeedHatch)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                networkSection
            }
        }
        .onAppear { center.pendingAttention = false }
    }

    // MARK: 네트워크 대전

    @ViewBuilder
    private var networkSection: some View {
        switch center.phase {
        case .ready, .preparing:
            peerList
        case .challenging(let peer):
            waitingView(peer: peer)
        case .incoming(let peer):
            incomingView(peer: peer)
        case .battling:
            // 세 모드가 같은 `BattleArenaView` 를 쓴다(계획 §6.3 안 B — 팝오버 탭 안에서 그린다).
            // 2~4인 방만 예외다: 참가자 넷은 좌우 두 자리 배치에 담기지 않아 격자를 유지하되,
            // 그 격자도 같은 HP 단계·상태 배지·타입색 버튼을 읽는다.
            if let practice = center.teamPractice { practiceArena(practice) }
            else if let battle = center.battle { lanArena(battle) }
        case .finished(let iWon, let byForfeit):
            finishedView(iWon: iWon, byForfeit: byForfeit)
        }
    }

    // MARK: 대전 화면 (팝오버 탭 안 — 계획 §6.3 안 B)

    private func lanArena(_ battle: NetBattleState) -> some View {
        // 엔진 좌변(A)은 항상 challenger 다 — 내가 어느 쪽인지로 내 편/상대를 가른다.
        let mine: BattleActor = battle.iAmA ? .a : .b
        let theirs: BattleActor = battle.iAmA ? .b : .a
        // 재생 중엔 엔진의 최종 상태가 아니라 **재생이 도달한 상태**를 그리고, 로그도 같은 진행도로
        // 자른다. 한쪽만 미루면 로그가 결과를 먼저 알려 줘 재생할 이유가 사라진다.
        //
        // HP 만이 아니라 **활성 칸과 팀 전체**를 재생기에서 읽는다 — 엔진의 활성 칸을 쓰면 기절
        // 자동 출전 턴에 새로 나온 만피 개체를 이전 개체의 HP 로 깎아 그리고(그리고 흐린 '쓰러진'
        // 스프라이트로 보여 준다), 교체 스트립의 미니 바도 큰 바보다 먼저 최종값으로 넘어간다.
        let engineMine = ReplaySide(team: battle.myTeam, active: battle.myActive)
        let engineTheirs = ReplaySide(team: battle.oppTeam, active: battle.oppActive)
        let shownMine = animator.side(for: mine) ?? engineMine
        let shownTheirs = animator.side(for: theirs) ?? engineTheirs
        let me = shownMine.side ?? battle.me
        let opp = shownTheirs.side ?? battle.opp
        return BattleArenaView(
            mine: me, theirs: opp,
            myTitle: l.battleMyPokemon,
            theirTitle: battle.opp.snapshot.trainer.map { l.battleTrainerLabel($0) } ?? "?",
            l: l, turn: battle.turn,
            logLines: BattleLogSource.netBattle(battle, mine: mine, l: l,
                                                playedCount: animator.playedCount),
            myActor: mine,
            switchSlots: SwitchStripModel.battleSlots(shownMine.team, active: shownMine.active),
            turnEndsAt: center.turnEndsAt,
            isWaitingForOpponent: battle.myAction != nil,
            overlay: animator.overlay,
            onChoose: { center.chooseMove($0) },
            onSwitch: { center.switchLAN(to: $0) },
            onForfeit: { center.forfeit() },
            chat: BattleChatConfiguration(messages: center.chatMessages, mySenderID: center.chatSenderID,
                                          isEnabled: center.chatIsAvailable,
                                          unavailableMessage: center.chatIsAvailable ? nil : l.battleChatUnavailable,
                                          l: l, onSend: center.sendChat))
        .onAppear { replay(battle.events, sides: [mine: engineMine, theirs: engineTheirs]) }
        .onChange(of: battle.events.count) {
            replay(battle.events, sides: [mine: engineMine, theirs: engineTheirs])
        }
    }

    private func practiceArena(_ practice: TeamPracticeBattle) -> some View {
        // LAN 과 같은 규칙이다 — 표시 상태(팀·활성 칸·HP)는 전부 재생기에서 읽는다.
        let engineMine = ReplaySide(team: practice.mine, active: practice.myActive)
        let engineTheirs = ReplaySide(team: practice.opponents, active: practice.opponentActive)
        let shownMine = animator.side(for: .a) ?? engineMine
        let shownTheirs = animator.side(for: .b) ?? engineTheirs
        let me = shownMine.side ?? practice.mySlot
        let opp = shownTheirs.side ?? practice.opponentSlot
        return BattleArenaView(
            mine: me, theirs: opp,
            myTitle: l.battleMyPokemon, theirTitle: "CPU",
            l: l, turn: practice.turn,
            // 이름·기술도 **화면에 서 있는 개체** 기준이다 — 엔진의 활성 개체로 풀면 기절 턴의
            // 로그가 아직 나오지도 않은 개체 이름으로 쓰러진다(LAN 은 배치 문맥이 같은 일을 한다).
            logLines: BattleLogSource.twoSided(played(practice.events), mine: .a, l: l,
                                               myName: me.snapshot.name,
                                               theirName: opp.snapshot.name,
                                               myMoves: me.moves,
                                               theirMoves: opp.moves),
            myActor: .a,
            switchSlots: SwitchStripModel.slots(shownMine.team, active: shownMine.active),
            turnEndsAt: nil,                       // CPU 는 즉시 답한다 — 기다림이 없으니 마감도 없다
            isWaitingForOpponent: false,
            overlay: animator.overlay,
            onChoose: { center.chooseTeamPracticeMove($0) },
            onSwitch: { center.switchTeamPractice(to: $0) },
            onForfeit: { center.forfeit() })
        .onAppear { replay(practice.events, sides: [.a: engineMine, .b: engineTheirs]) }
        .onChange(of: practice.events.count) {
            replay(practice.events, sides: [.a: engineMine, .b: engineTheirs])
        }
    }

    /// 재생이 아직 닿지 않은 이벤트는 화면에 없다 — 로그도 스트림도 같은 진행도로 자른다.
    private func played(_ events: [BattleEvent]) -> [BattleEvent] {
        Array(events.prefix(animator.playedCount))
    }

    /// 스트림이 길어질 때마다 재생기에 넘긴다. **저전력이면 설정과 무관하게 끈다** —
    /// `FloatingPetController.shouldAnimate(lowPower:)` 와 같은 가드다.
    private func replay(_ events: [BattleEvent], sides: [BattleActor: ReplaySide]) {
        // 승부가 난 턴의 결과 화면을 재생 뒤로 미루는 연결. 재생기는 뷰가 들고 있어 센터가 직접
        // 알 수 없으므로, 따라잡았다는 사실을 이 콜백으로 전한다(팝오버가 닫혀 있으면 센터의
        // `finishDeadline` 이 대신 부른다).
        animator.onCaughtUp = { center.commitPendingFinish() }
        animator.sync(events: events, sides: sides,
                      speed: BattleReplay.effectiveSpeed(
                        settings.battleReplaySpeed,
                        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
    }

    /// 결과 — 마지막 장면(필드)을 남겨 두고 아래 칸만 결과로 갈아 끼운다.
    @ViewBuilder
    private func finishedView(iWon: Bool?, byForfeit: Bool) -> some View {
        VStack(spacing: 8) {
            if let sides = finishedSides {
                BattleFieldView(mine: sides.mine, theirs: sides.theirs,
                                myTitle: l.battleMyPokemon, theirTitle: sides.theirTitle, l: l)
                    .frame(height: BattleFieldMetrics.fieldHeight)
            }
            Text(finishText(iWon: iWon, byForfeit: byForfeit)).font(.title3).bold()
            if center.battle != nil || center.teamPractice != nil {
                Text(center.isPracticeBattle
                     ? l.t("모의전 결과", "Practice result", "練習バトルの結果")
                     : store.battleRank.displayName)
                    .font(.caption).bold()
                if center.lastRankDelta != 0 {
                    Text("\(center.lastRankDelta > 0 ? "+" : "")\(center.lastRankDelta) LP")
                        .font(.caption2)
                        .foregroundStyle(center.lastRankDelta > 0 ? .green : .red)
                }
                if center.rankedStake > 0, let iWon {
                    Text("\(iWon ? "+" : "−")⭐ \(GameNumberFormatter.compact(center.rankedStake))")
                        .font(.caption2).foregroundStyle(iWon ? .green : .orange)
                }
            }
            Button(l.battleClose) { center.dismissResult() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// 결과 화면이 남겨 둘 마지막 장면. 연습은 활성 슬롯, 1v1 은 그대로다.
    private var finishedSides: (mine: BattleSide, theirs: BattleSide, theirTitle: String)? {
        if let practice = center.teamPractice {
            return (practice.mySlot, practice.opponentSlot, "CPU")
        }
        if let battle = center.battle {
            return (battle.me, battle.opp,
                    battle.opp.snapshot.trainer.map { l.battleTrainerLabel($0) } ?? "?")
        }
        return nil
    }

    /// 방 결과 문구 — 승/패/무/관전 네 갈래. `nil` 은 전투원이 아니었다는 뜻이다(관전자).
    /// 1v1 의 `finishText` 와 같은 규칙 — 판정이 낸 값을 그대로 문구로 옮기고 화면에서 다시 갈라
    /// 판단하지 않는다. 문구도 1v1 과 같은 `l.battleWon`/`l.battleLost` 를 쓴다. 여기서
    /// `language == .ko ? … : …` 로 직접 갈랐을 때는 일본어 사용자에게 영어가 나갔고(세 갈래 중 두
    /// 갈래만 번역됨), 같은 결과를 두 화면이 다른 문구로 말했다.
    private func roomResultText(_ outcome: BattleOutcome?) -> String {
        switch outcome {
        case .win:  return l.battleWon
        case .loss: return l.battleLost
        case .draw: return l.battleDraw
        case nil:   return l.battleSpectatorFinished
        }
    }

    private func finishText(iWon: Bool?, byForfeit: Bool) -> String {
        switch (iWon, byForfeit) {
        case (.some(true), true):   return l.battleOppForfeited
        case (.some(false), true):  return l.battleYouForfeited
        case (.some(true), false):  return l.battleWon
        case (.some(false), false): return l.battleLost
        // 승패가 없는 끝(동시 전멸·끊김 동률)은 전부 무승부다. 끊김은 `byForfeit: false` 로 오고
        // "왜 끝났는지"는 `lastError`(`battleConnectionLost`)가 따로 말한다 — 기권과 섞지 않는다.
        default:                    return l.battleDraw
        }
    }

    /// 한 페이지에 그리는 칩 수. 팝오버 콘텐츠 폭(332) 안에 칩 6개(44)와 간격이 들어간다.
    /// 최대 팀 크기와 같은 수라, 한 페이지가 곧 한 팀 분량이다.
    private var peerList: some View {
        // 상대는 Bonjour 탐색을 따라 수시로 들어오고 나간다 — 보던 페이지가 사라지면 마지막 페이지로 당긴다.
        let pageCount = Self.peerPageCount(center.peers.count)
        let page = min(peerPage, pageCount - 1)
        let slice = Array(center.peers.dropFirst(page * Self.peerPageSize).prefix(Self.peerPageSize))
        return VStack(alignment: .leading, spacing: 6) {
            // 제목이 Lv.50 을 말하지 않는다 — 그 규칙은 아래 상대 목록(맞짱)에만 해당하고,
            // 같은 섹션의 모의전은 키운 레벨 그대로 나간다.
            Label(l.t("랭크배틀", "Ranked Battle", "ランクバトル"),
                  systemImage: "shield.lefthalf.filled")
                .font(.caption.bold())
            Picker("", selection: Binding(get: { center.rankedTeamSize }, set: { center.rankedTeamSize = $0 })) {
                Text("1 vs 1").tag(1)
                Text("3 vs 3").tag(3)
                Text("6 vs 6").tag(6)
            }.pickerStyle(.segmented).labelsHidden()

            TeamPicker(store: store,
                       selection: Binding(get: { center.pickedTeam }, set: { center.pickedTeam = $0 }),
                       limit: center.rankedTeamSize)

            HStack(spacing: 6) {
                Button {
                    center.startRankedPractice()
                } label: {
                    Label(l.t("CPU 모의전", "Practice vs CPU", "CPU と練習"), systemImage: "gamecontroller.fill")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(!isChallengeEnabled)
                Button {
                    nav.showGymLeague = true
                } label: {
                    Label(l.gymLeagueTitle, systemImage: "building.columns.fill")
                }
                .controlSize(.small)
                // 던전은 배틀 준비 상태와 무관하다 — 팀도 상대도 필요 없고 혼자 푸는 퍼즐이라
                // 체육관과 달리 `isChallengeEnabled` 로 막지 않는다.
                Button {
                    nav.showDungeon = true
                } label: {
                    Label(l.dungeonTitle, systemImage: "map.fill")
                }
                .controlSize(.small)
                .disabled(!isChallengeEnabled)
                Text(l.gymBadgeCount(store.earnedGymBadges.count, GymLeague.catalog.count))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(l.t("키운 레벨 그대로 · 랭크와 별의조각은 변하지 않음",
                     "At the levels you raised · rank and Star Pieces are unchanged",
                     "育てたレベルそのまま · ランクとほしのかけらは変わりません"))
                .font(.caption2).foregroundStyle(.secondary)

            HStack {
                Label(store.battleRank.displayName, systemImage: "shield.lefthalf.filled")
                Spacer()
                Text("⭐ \(GameNumberFormatter.compact(store.availableTokens))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text(l.battleNearby).font(.caption).bold()
                Text(l.t("· 전원 Lv.50", "· all Lv.50", "· 全員 Lv.50"))
                    .font(.caption2).foregroundStyle(.secondary)
                if case .preparing = center.phase { ProgressView().controlSize(.mini) }
                Spacer()
                if !center.peers.isEmpty {
                    Text("\(center.peers.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if let err = center.lastError {
                Text(err).font(.caption2).foregroundStyle(.orange)
            }
            if center.peers.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.battleNoPeers).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                // 예전엔 이 목록이 `ScrollView` + `maxHeight: 180` 이었다. 팝오버 본체가 이미
                // `ScrollView` 라 안쪽은 **스크롤되지 않고 잘린다**(defect-log) — 상대가 다섯 명을
                // 넘어가면 뒤쪽은 신청할 방법이 없었다. 스크롤을 지우고 도감·로스터와 같은 페이지식으로
                // 간다 — 한 페이지에 다섯 명씩, 나머지는 페이저로 넘겨서 신청한다.
                VStack(spacing: 4) {
                    ForEach(slice) { peer in
                        PeerRow(store: store, peer: peer, isEnabled: isChallengeEnabled) {
                            center.challenge(peer)
                        }
                    }
                    if pageCount > 1 {
                        HStack(spacing: 8) {
                            Spacer(minLength: 4)
                            Button { peerPage = max(0, page - 1) } label: { Image(systemName: "chevron.left") }
                                .buttonStyle(.plain).disabled(page == 0)
                                .accessibilityLabel(l.dexPagePrev)
                            Text("\(page + 1) / \(pageCount)")
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                .accessibilityLabel(l.dexPageLabel(page + 1, pageCount))
                            Button { peerPage = min(pageCount - 1, page + 1) } label: { Image(systemName: "chevron.right") }
                                .buttonStyle(.plain).disabled(page == pageCount - 1)
                                .accessibilityLabel(l.dexPageNext)
                        }
                    }
                }
            }
            manualConnect
        }
    }

    private var multiplayerRooms: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(l.t("최대 4인 배틀", "Up to 4 players", "最大4人バトル"),
                      systemImage: "person.3.fill").font(.caption).bold()
                Spacer()
            }
            Picker("", selection: $roomMode) {
                Text(l.t("개인전", "Free-for-all", "個人戦")).tag(MultiplayerBattleMode.freeForAll)
                Text("2 vs 2").tag(MultiplayerBattleMode.teams)
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Button(l.t("방 만들기", "Create room", "部屋を作る")) {
                    center.multiplayer.createRoom(mode: roomMode)
                }.buttonStyle(.borderedProminent).controlSize(.small)
                Spacer()
            }
            if !center.multiplayer.rooms.isEmpty {
                ForEach(center.multiplayer.rooms) { room in
                    HStack {
                        Image(systemName: "door.left.hand.open").foregroundStyle(.secondary)
                        Text(room.name).font(.caption).lineLimit(1)
                        Spacer()
                        Button(l.t("참가", "Join", "参加")) { center.multiplayer.join(room) }
                            .controlSize(.small)
                    }
                }
            }
            if let error = center.multiplayer.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
            if !store.recentBattles.isEmpty {
                Divider().padding(.vertical, 1)
                Text(l.t("최근 배틀", "Recent battles", "最近のバトル")).font(.caption2).bold()
                ForEach(store.recentBattles.prefix(3)) { record in
                    HStack(spacing: 5) {
                        Image(systemName: record.won ? "trophy.fill" : "shield.fill")
                            .foregroundStyle(record.won ? .orange : .secondary)
                        Text(record.mode == .teams ? "2 vs 2" : "\(record.participantCount)P")
                            .font(.caption2).bold()
                        Text(record.opponentNames.joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text("+\(record.reward) ✨").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(7)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private var multiplayerLobby: some View {
        Group {
            if center.multiplayer.phase == .battling { multiplayerArena }
            else { multiplayerLobbyContent }
        }
    }

    private var multiplayerLobbyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l.t("4인 배틀 로비", "Multiplayer lobby", "マルチバトルのロビー"),
                      systemImage: "person.3.fill").font(.callout).bold()
                Spacer()
                Text(center.multiplayer.isHost ? l.t("방장", "HOST", "ホスト") : "")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
            }
            if case .creating = center.multiplayer.phase {
                ProgressView(l.t("방을 만드는 중…", "Creating room…", "部屋を作成中…"))
            } else if case .joining(let name) = center.multiplayer.phase {
                ProgressView("\(name)…")
            }
            if let lobby = center.multiplayer.lobby {
                Text(lobby.mode == .teams ? "2 vs 2" : l.t("개인전", "Free-for-all", "個人戦"))
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(lobby.participants) { participant in
                    HStack(spacing: 7) {
                        SpriteView(speciesID: participant.speciesID, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(participant.trainerName).font(.caption).bold().lineLimit(1)
                            Text(participant.isHost ? "HOST" : "PLAYER").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if lobby.mode == .teams {
                            Text(participant.team == .red ? "🔴" : "🔵")
                        }
                        Image(systemName: participant.isReady ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(participant.isReady ? .green : .secondary)
                    }
                    .padding(5)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }
                ForEach(lobby.runners.count..<max(lobby.runners.count, lobby.capacity), id: \.self) { _ in
                    HStack { Image(systemName: "person.crop.circle.dashed"); Text(l.t("참가자 대기 중", "Waiting for player", "参加者を待っています")) }
                        .font(.caption2).foregroundStyle(.tertiary).padding(5)
                }
                if lobby.mode == .teams, let me = center.multiplayer.myParticipant {
                    Picker("Team", selection: Binding(get: { me.team }, set: { center.multiplayer.selectTeam($0) })) {
                        Text("🔴 RED").tag(BattleTeam.red); Text("🔵 BLUE").tag(BattleTeam.blue)
                    }.pickerStyle(.segmented)
                }
                HStack {
                    Button(center.multiplayer.myParticipant?.isReady == true
                           ? l.t("준비 취소", "Cancel ready", "準備をやめる")
                           : l.t("준비", "Ready", "準備完了")) {
                        center.multiplayer.toggleReady()
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                    Spacer()
                    if center.multiplayer.isHost, lobby.canStart {
                        Button(l.t("배틀 시작", "Start battle", "バトル開始")) {
                            center.multiplayer.startBattle()
                        }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    Button(l.t("나가기", "Leave", "退出")) { center.multiplayer.leaveRoom() }
                        .controlSize(.small)
                }
            }
            if let error = center.multiplayer.lastError { Text(error).font(.caption2).foregroundStyle(.orange) }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var multiplayerArena: some View {
        let fighters = center.multiplayer.combatFighters
        let me = fighters.first { $0.id == center.multiplayer.myID }
        // 팀 판정은 `combatMode`(= 배틀 시작 시점에 고정된 모드) 하나만 본다. `lobby?.mode` 는 편성에서
        // 파생되는 가변값이라 여기서 따로 읽으면 승패 판정은 팀전인데 화면은 개인전인 상태가 생긴다 —
        // 그러면 같은 팀을 대상으로 고를 수 있고, 그 라운드는 `resolveRound` 가 통째로 거절한다.
        let isTeamBattle = center.multiplayer.combatMode == .teams
        let targets = fighters.filter { fighter in
            guard fighter.id != center.multiplayer.myID, fighter.isAlive else { return false }
            if isTeamBattle, let myTeam = me?.team { return fighter.team != myTeam }
            return true
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("⚔️ \(l.t("4인 배틀", "Multiplayer Battle", "マルチバトル"))")
                    .font(.callout).bold()
                Spacer()
                Text("R\(center.multiplayer.combatRound)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                // 내 행동을 보낸 뒤에는 상대 입력을 기다리는 상태다. 이때 남은 시간은 내게
                // 행동을 요구하는 것처럼 보이므로, 1:1 화면과 동일하게 카운트다운을 숨긴다.
                if let end = center.multiplayer.turnEndsAt,
                   !center.multiplayer.isBattleFinished,
                   !center.multiplayer.hasSubmittedAction {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(max(0, Int(end.timeIntervalSince(context.date))))s")
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(end.timeIntervalSince(context.date) <= 5 ? .red : .orange)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(fighters) { fighter in
                    VStack(spacing: 2) {
                        HStack {
                            if isTeamBattle {
                                Text(fighter.team == .red ? "🔴" : "🔵").font(.caption2)
                            }
                            Text(fighter.trainerName).font(.caption2).bold().lineLimit(1)
                        }
                        SpriteView(speciesID: fighter.side.snapshot.speciesID, size: 38,
                                   shiny: fighter.side.snapshot.isShiny)
                            .opacity(fighter.isAlive ? 1 : 0.25)
                        // 필드와 같은 3단계 색·같은 표기 규칙을 읽는다. 예전엔 여기만
                        // `isAlive ? .green : .gray` 라 HP 5% 와 100% 가 같은 색이었고, 남의 실수치가
                        // 그대로 보였다 — 4인 방에서도 상대 HP 는 원래 모르는 정보다.
                        ProgressView(value: Double(fighter.side.hp), total: Double(max(1, fighter.side.stats.hp)))
                            .tint(HPTier.of(hp: fighter.side.hp, max: fighter.side.stats.hp).color)
                            .controlSize(.mini)
                        Text(fighter.id == center.multiplayer.myID
                             ? HPReadout.mine(hp: fighter.side.hp, max: fighter.side.stats.hp)
                             : HPReadout.theirs(hp: fighter.side.hp, max: fighter.side.stats.hp))
                            .font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                        StatusBadgeRow(side: fighter.side)
                        // 방 화면도 랭크를 그린다 — 없으면 4인 방에선 로그 문장으로만 남는다.
                        StageArrows(side: fighter.side)
                    }
                    .padding(5)
                    .background((multiplayerTargetID == fighter.id ? Color.red.opacity(0.12) : Color.primary.opacity(0.04)),
                                in: RoundedRectangle(cornerRadius: 7))
                    .onTapGesture {
                        if targets.contains(where: { $0.id == fighter.id }), !center.multiplayer.hasSubmittedAction {
                            multiplayerTargetID = fighter.id
                        }
                    }
                }
            }
            if center.multiplayer.isBattleFinished {
                Text(roomResultText(center.multiplayer.myOutcome))
                    .font(.title3).bold().frame(maxWidth: .infinity)
                Button(l.t("로비 나가기", "Leave", "ロビーを出る")) { center.multiplayer.leaveRoom() }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            } else if me?.isAlive == false {
                Text(l.t("탈락 — 배틀을 관전하고 있습니다.", "Knocked out — spectating.", "戦闘不能 — 観戦中です。"))
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else if center.multiplayer.hasSubmittedAction {
                HStack { ProgressView().controlSize(.small); Text(l.t("다른 참가자의 행동을 기다리는 중…", "Waiting for other players…", "ほかの参加者の行動を待っています…")) }
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else {
                Text(multiplayerTargetID == nil
                     ? l.t("공격할 상대를 선택하세요.", "Choose a target.", "攻撃する相手を選んでください。")
                     : l.t("기술을 선택하세요.", "Choose a move.", "わざを選んでください。"))
                    .font(.caption).bold()
                if let me {
                    // 1v1 과 같은 버튼·같은 발버둥 처리를 쓴다. 발버둥이 없던 동안은 PP 가 전부
                    // 마르면 네 칸이 모두 비활성이라 마감(30초)까지 아무것도 할 수 없었다.
                    let struggling = me.side.mustStruggle
                    MoveGridView(moves: struggling ? [.struggle()] : me.side.moves,
                                 pp: struggling ? [] : me.side.pp, language: store.language,
                                 isEnabled: multiplayerTargetID != nil) { index in
                        guard let target = multiplayerTargetID else { return }
                        center.multiplayer.submitAction(targetID: target, moveIndex: struggling ? -1 : index)
                    }
                }
            }
            if !center.multiplayer.combatEvents.isEmpty {
                // 1v1 과 스트림도 접기도 같다. 예전엔 여기만 "이름 → 이름: -12" 라는
                // 별도 문구였고, 기술 이름도 급소도 상성도 나오지 않았다.
                BattleLogBox(lines: multiplayerLogLines(center.multiplayer.combatEvents, fighters: fighters),
                             myActor: .fighter(center.multiplayer.myID))
            }
            BattleChatPanel(configuration: BattleChatConfiguration(
                messages: center.multiplayer.chatMessages, mySenderID: center.multiplayer.myID,
                isEnabled: true, unavailableMessage: nil, l: l,
                onSend: center.multiplayer.sendChat))
        }
        .onAppear {
            if multiplayerTargetID == nil { multiplayerTargetID = targets.first?.id }
        }
        .onChange(of: center.multiplayer.combatRound) {
            if !targets.contains(where: { fighter in multiplayerTargetID.map { fighter.id == $0 } ?? false }) {
                multiplayerTargetID = targets.first?.id
            }
        }
    }

    /// 사내망 등 mDNS 차단 환경 폴백 — 내 주소 공유 + 상대 주소 직접 입력.
    private var manualConnect: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.battleManualHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let addr = center.myManualAddress {
                HStack(spacing: 6) {
                    Text("\(l.battleMyAddress): \(addr)")
                        .font(.system(size: 11, design: .monospaced))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(addr, forType: .string)
                        addressCopied = true
                        Task { try? await Task.sleep(for: .seconds(2)); addressCopied = false }
                    } label: {
                        Image(systemName: addressCopied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    Spacer()
                }
            }
            HStack(spacing: 6) {
                TextField(l.battleManualPlaceholder, text: $manualAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit { challengeManual() }
                Button(l.battleChallengeButton) { challengeManual() }
                    .controlSize(.small)
                    .disabled(!isChallengeEnabled || manualAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 4)
    }

    private func challengeManual() {
        guard isChallengeEnabled else { return }
        center.challengeManual(manualAddress)
    }

    private var isChallengeEnabled: Bool {
        if case .ready = center.phase { return true }
        return false
    }

    private func waitingView(peer: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("\(peer) — \(l.battleWaitingAccept)")
                .font(.callout)
                .foregroundStyle(.secondary)
            challengeCountdown
            Button(l.battleCancel) { center.cancelChallenge() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func incomingView(peer: String) -> some View {
        VStack(spacing: 7) {
            Text("⚔️ \(l.battleIncomingFrom(peer))")
                .font(.callout).bold()
                .multilineTextAlignment(.center)
            challengeCountdown
            Text("\(center.incomingTeamSize) vs \(center.incomingTeamSize)")
                .font(.caption2).foregroundStyle(.secondary)
            if let profile = center.opponentRankProfile {
                VStack(spacing: 2) {
                    Text("\(profile.rank.displayName)  VS  \(store.battleRank.displayName)")
                    if center.incomingRankedStake > 0 {
                        Text(l.battleFixedStake(GameNumberFormatter.compact(center.incomingRankedStake)))
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
            }
            if let opp = center.incomingSnapshot {
                snapshotCard(opp, title: opp.trainer.map { l.battleTrainerLabel($0) } ?? "?")
                    .frame(maxWidth: 180)
            }
            TeamPicker(store: store,
                       selection: Binding(get: { center.incomingPickedTeam },
                                          set: { center.incomingPickedTeam = $0 }),
                       limit: center.incomingTeamSize)
            if store.ownedMons.count < center.incomingTeamSize {
                Text(l.battleNeedsPokemon(center.incomingTeamSize))
                    .font(.caption2).foregroundStyle(.orange)
            } else if let error = center.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button(l.battleAccept) { center.acceptIncoming() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.ownedMons.count < center.incomingTeamSize)
                Button(l.battleDecline) { center.declineIncoming() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var challengeCountdown: some View {
        if let endsAt = center.challengeEndsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(endsAt.timeIntervalSince(context.date).rounded(.up)))
                Text(l.battleChallengeTimeRemaining(seconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(seconds <= 10 ? .orange : .secondary)
                    .accessibilityLabel(l.battleChallengeTimeRemaining(seconds))
            }
        }
    }

    // MARK: 로그/카드 공용

    /// 멀티(2~4인)의 스트림은 참가자 UUID 로 쪽을 가른다 — 이름·기술명만 그 방의 파이터에서 찾아 준다.
    /// 좌우 두 자리인 1v1·연습 배틀은 `BattleLogSource.twoSided` 가 맡는다(배틀 탭이 그 화면을 그린다).
    private func multiplayerLogLines(_ events: [BattleEvent],
                                     fighters: [MultiplayerFighter]) -> [BattleLog.Line] {
        func fighter(_ actor: BattleActor) -> MultiplayerFighter? {
            guard case .fighter(let id) = actor else { return nil }
            return fighters.first { $0.id == id }
        }
        return BattleLog.lines(events, l: l,
                               name: { fighter($0)?.side.snapshot.name ?? "?" },
                               moveName: { actor, id in
                                   let moves = fighter(actor)?.side.moves ?? []
                                   return (moves.first { $0.id == id } ?? .struggle()).name(store.language)
                               })
    }

    /// 신청 수락 화면의 상대 미리보기. HP 도 상태도 아직 없다 — 스냅샷만 왔고 배틀은 안 시작했다.
    /// 대전 중 화면은 `CombatantBar` 가 맡는다(세 모드가 같은 칸을 쓴다).
    private func snapshotCard(_ snapshot: BattleSnapshot, title: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            SpriteView(speciesID: snapshot.speciesID, size: 56, animated: true, shiny: snapshot.isShiny)
            HStack(spacing: 3) {
                if snapshot.isShiny { Text("✨").font(.caption2) }
                Text(snapshot.name).font(.caption).bold().lineLimit(1)
                Text(l.battleLv(snapshot.level)).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                ForEach(snapshot.types, id: \.rawValue) { typeChip($0) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    /// 타입 배지 — 실제 타입색이다. 예전엔 18타입 전부를 accent 한 색으로 그려서 배지가 타입을
    /// 전혀 전달하지 못했다(기술 버튼과 같은 색·같은 글자색 규칙을 읽는다).
    private func typeChip(_ type: PokemonType) -> some View {
        Text(type.name(store.language))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(type.battleLabelColor)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(type.battleColor))
    }
}

/// 근처 트레이너 한 명. 이름 줄과 진행도 줄, 두 줄 고정이다.
///
/// 세 번째 줄이 생기면 한 페이지 5명(`BattleView.peerPageSize`) 예산이 깨진다. 진행도를 이름
/// 옆에 두지 않는 이유도 같다. 이름은 Bonjour 에서 와 길이를 우리가 정하지 못하지만, 아래 줄은
/// 전부 길이가 정해진 값이라 최악의 폭을 미리 잴 수 있다. 가드는 `PopoverLayoutTests` 카드 절.
struct PeerRow: View {
    let store: CompanionStore
    let peer: BattlePeer
    let isEnabled: Bool
    let onChallenge: () -> Void

    private var l: L { store.l }

    var body: some View {
        HStack {
            Image(systemName: "person.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(peer.name).font(.callout).lineLimit(1)
                progressLine
            }
            Spacer()
            Button(l.battleChallengeButton, action: onChallenge)
                .controlSize(.small)
                .disabled(!isEnabled)
        }
        .padding(.vertical, 2)
    }

    /// 랭크·트레이너 레벨·업적 단계. 광고에 없는 칸은 그리지 않는다. 구버전 상대는 랭크만
    /// 보이고, 정보 없음을 세 번 반복하지 않는다.
    private var progressLine: some View {
        HStack(spacing: 4) {
            Text(rankText)
                .foregroundStyle(peer.rank == nil ? .tertiary : .secondary)
            if let level = peer.advertisement.trainerLevel {
                Text("· Lv.\(level)").monospacedDigit().foregroundStyle(.secondary)
            }
            // 분모는 상대가 광고한 것을 쓴다. 내 카탈로그로 그리면 새 버전 상대가 완료로 보인다.
            if let badge = peer.advertisement.achievementProgress {
                Text("· 🏅\(badge.tiers)/\(badge.ceiling)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// 화면과 스크린리더가 같은 값을 써야 한다. 따로 만들면 한쪽만 번역된다.
    private var rankText: String { peer.rank?.displayName ?? l.battleRankUnknown }

    /// 스크린리더용. 화면의 짧은 표기(`Lv.12 · 🏅8/16`)를 그대로 읽히면 뜻이 안 통한다.
    private var accessibilityText: String {
        let badge = peer.advertisement.achievementProgress
        let progress = l.peerProgressLabel(peer.advertisement.trainerLevel,
                                          badge?.tiers,
                                          badge?.ceiling ?? AchievementLadder.tierCeiling)
        return progress.isEmpty ? rankText : "\(rankText), \(progress)"
    }
}
