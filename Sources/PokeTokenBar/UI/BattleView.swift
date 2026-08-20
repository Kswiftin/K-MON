import AppKit
import SwiftUI

/// 배틀 탭 — 같은 네트워크(LAN) 실시간 대전. 상대 목록에서 신청하고, 신청이 오면
/// 알림+수락 화면, 대전 중엔 기술 4개 중 선택.
struct BattleView: View {
    @Bindable var store: CompanionStore
    @Environment(BattleCenter.self) private var center
    @Environment(PopoverNavigation.self) private var nav

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
        return BattleArenaView(
            mine: battle.me, theirs: battle.opp,
            myTitle: l.battleMyPokemon,
            theirTitle: battle.opp.snapshot.trainer.map { l.battleTrainerLabel($0) } ?? "?",
            l: l, turn: battle.turn,
            logLines: BattleLogSource.netBattle(battle, mine: mine, l: l),
            myActor: mine,
            switchSlots: SwitchStripModel.battleSlots(battle.myTeam, active: battle.myActive),
            turnEndsAt: center.turnEndsAt,
            isWaitingForOpponent: battle.myAction != nil,
            onChoose: { center.chooseMove($0) },
            onSwitch: { center.switchLAN(to: $0) },
            onForfeit: { center.forfeit() })
    }

    private func practiceArena(_ practice: TeamPracticeBattle) -> some View {
        BattleArenaView(
            mine: practice.mySlot, theirs: practice.opponentSlot,
            myTitle: l.battleMyPokemon, theirTitle: "CPU",
            l: l, turn: practice.turn,
            logLines: BattleLogSource.twoSided(practice.events, mine: .a, l: l,
                                               myName: practice.mySlot.snapshot.name,
                                               theirName: practice.opponentSlot.snapshot.name,
                                               myMoves: practice.mySlot.moves,
                                               theirMoves: practice.opponentSlot.moves),
            myActor: .a,
            switchSlots: SwitchStripModel.slots(practice.mine, active: practice.myActive),
            turnEndsAt: nil,                       // CPU 는 즉시 답한다 — 기다림이 없으니 마감도 없다
            isWaitingForOpponent: false,
            onChoose: { center.chooseTeamPracticeMove($0) },
            onSwitch: { center.switchTeamPractice(to: $0) },
            onForfeit: { center.forfeit() })
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
                     ? (store.language == .ko ? "모의전 결과" : "Practice result")
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
            Label(store.language == .ko ? "랭크배틀" : "Ranked Battle",
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
                    Label(store.language == .ko ? "CPU 모의전" : "Practice vs CPU", systemImage: "gamecontroller.fill")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(!isChallengeEnabled)
                Button {
                    nav.showGymLeague = true
                } label: {
                    Label(l.gymLeagueTitle, systemImage: "building.columns.fill")
                }
                .controlSize(.small)
                .disabled(!isChallengeEnabled)
                Text(l.gymBadgeCount(store.earnedGymBadges.count, GymLeague.catalog.count))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(store.language == .ko
                 ? "키운 레벨 그대로 · 랭크와 별의조각은 변하지 않음"
                 : "At the levels you raised · rank and Star Pieces are unchanged")
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
                Text(store.language == .ko ? "· 전원 Lv.50" : "· all Lv.50")
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
                        HStack {
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(peer.name).font(.callout).lineLimit(1)
                                Text(peer.rank?.displayName
                                     ?? (store.language == .ko ? "랭크 정보 없음" : "Rank unavailable"))
                                    .font(.caption2)
                                    .foregroundStyle(peer.rank == nil ? .tertiary : .secondary)
                            }
                            Spacer()
                            Button(l.battleChallengeButton) { center.challenge(peer) }
                                .controlSize(.small)
                                .disabled(!isChallengeEnabled)
                        }
                        .padding(.vertical, 2)
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
                Label(store.language == .ko ? "최대 4인 배틀" : "Up to 4 players",
                      systemImage: "person.3.fill").font(.caption).bold()
                Spacer()
            }
            Picker("", selection: $roomMode) {
                Text(store.language == .ko ? "개인전" : "Free-for-all").tag(MultiplayerBattleMode.freeForAll)
                Text("2 vs 2").tag(MultiplayerBattleMode.teams)
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Button(store.language == .ko ? "방 만들기" : "Create room") {
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
                        Button(store.language == .ko ? "참가" : "Join") { center.multiplayer.join(room) }
                            .controlSize(.small)
                    }
                }
            }
            if let error = center.multiplayer.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
            if !store.recentBattles.isEmpty {
                Divider().padding(.vertical, 1)
                Text(store.language == .ko ? "최근 배틀" : "Recent battles").font(.caption2).bold()
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
                Label(store.language == .ko ? "4인 배틀 로비" : "Multiplayer lobby",
                      systemImage: "person.3.fill").font(.callout).bold()
                Spacer()
                Text(center.multiplayer.isHost ? (store.language == .ko ? "방장" : "HOST") : "")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
            }
            if case .creating = center.multiplayer.phase {
                ProgressView(store.language == .ko ? "방을 만드는 중…" : "Creating room…")
            } else if case .joining(let name) = center.multiplayer.phase {
                ProgressView("\(name)…")
            }
            if let lobby = center.multiplayer.lobby {
                Text(lobby.mode == .teams ? "2 vs 2" : (store.language == .ko ? "개인전" : "Free-for-all"))
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
                    HStack { Image(systemName: "person.crop.circle.dashed"); Text(store.language == .ko ? "참가자 대기 중" : "Waiting for player") }
                        .font(.caption2).foregroundStyle(.tertiary).padding(5)
                }
                if lobby.mode == .teams, let me = center.multiplayer.myParticipant {
                    Picker("Team", selection: Binding(get: { me.team }, set: { center.multiplayer.selectTeam($0) })) {
                        Text("🔴 RED").tag(BattleTeam.red); Text("🔵 BLUE").tag(BattleTeam.blue)
                    }.pickerStyle(.segmented)
                }
                HStack {
                    Button(center.multiplayer.myParticipant?.isReady == true
                           ? (store.language == .ko ? "준비 취소" : "Cancel ready")
                           : (store.language == .ko ? "준비" : "Ready")) {
                        center.multiplayer.toggleReady()
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                    Spacer()
                    if center.multiplayer.isHost, lobby.canStart {
                        Button(store.language == .ko ? "배틀 시작" : "Start battle") {
                            center.multiplayer.startBattle()
                        }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    Button(store.language == .ko ? "나가기" : "Leave") { center.multiplayer.leaveRoom() }
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
                Text("⚔️ \(store.language == .ko ? "4인 배틀" : "Multiplayer Battle")")
                    .font(.callout).bold()
                Spacer()
                Text("R\(center.multiplayer.combatRound)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if let end = center.multiplayer.turnEndsAt, !center.multiplayer.isBattleFinished {
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
                Button(store.language == .ko ? "로비 나가기" : "Leave") { center.multiplayer.leaveRoom() }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            } else if me?.isAlive == false {
                Text(store.language == .ko ? "탈락 — 배틀을 관전하고 있습니다." : "Knocked out — spectating.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else if center.multiplayer.hasSubmittedAction {
                HStack { ProgressView().controlSize(.small); Text(store.language == .ko ? "다른 참가자의 행동을 기다리는 중…" : "Waiting for other players…") }
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else {
                Text(multiplayerTargetID == nil
                     ? (store.language == .ko ? "공격할 상대를 선택하세요." : "Choose a target.")
                     : (store.language == .ko ? "기술을 선택하세요." : "Choose a move."))
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
