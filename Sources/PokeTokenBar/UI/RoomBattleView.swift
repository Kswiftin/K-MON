import SwiftUI

/// 2~4인 LAN 방 배틀 — 같은 네트워크에서 방을 열고 최대 넷이 한 판을 돈다(개인전 / 2 vs 2).
///
/// 화면이 두 국면을 갈아 끼운다: **모집 전**(방 만들기·근처 배틀 방 목록·최근 전적)과
/// **로비/교전**. 레이드(`RaidView`)와 같은 골격이고, 다른 것은 때릴 대상이 보스 하나가
/// 아니라 **다른 참가자**라 대상 격자를 그린다는 점뿐이다.
///
/// 왜 `BattleView` 에서 떼어냈나: 이 조각들은 세 주 동안 **아무 데도 안 붙어 있었다**(#209).
/// `BattleView` 는 1:1 랭크배틀을 그리는 화면이라, 방 배틀을 같은 파일에 두면 친구 탭이
/// 한 뷰 안에서 두 기능을 다시 갈라야 한다 — 그 갈림이 없어진 자리가 결함의 출발점이었다.
struct RoomBattleView: View {
    let store: CompanionStore
    @Environment(BattleCenter.self) private var center
    let onClose: () -> Void

    @State private var roomMode: MultiplayerBattleMode = .freeForAll
    @State private var multiplayerTargetID: UUID?

    private var l: L { store.l }

    /// 로비를 그릴 것인가. **활동이 배틀인 방만** 그린다 — 다른 활동의 방을 여기서 그리면
    /// 화면은 방 배틀인데 뒤에서는 레이드가 도는 상태가 된다.
    ///
    /// 개설·참가 중에는 아직 활동을 모른다(로비는 `await` 뒤에 온다). 그 사이 모집 화면으로
    /// 되돌리면 방금 누른 "방 만들기" 가 아무 일도 안 한 것처럼 보이므로 국면으로 판단한다.
    static func showsLobby(phase: MultiplayerRoomCenter.Phase, activity: RoomActivity?) -> Bool {
        switch phase {
        case .idle: false
        case .creating, .joining: true
        default: activity == .battle
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBar
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if Self.showsLobby(phase: center.multiplayer.phase,
                                       activity: center.multiplayer.roomActivity) {
                        multiplayerLobby
                    } else {
                        multiplayerRooms
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Label(l.t("2~4인 방 배틀", "Room Battle", "2〜4人ルームバトル"),
                  systemImage: "person.3.fill").font(.callout).bold()
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    /// 전적 한 줄의 모드 표기. 뷰 밖에 두는 이유는 순수 판정이라 테스트가 닿아야 해서다 —
    /// 협동전이 `3P` 로 나오면 4인 개인전과 구별되지 않는다.
    enum RecentBattleLabel {
        static func text(mode: MultiplayerBattleMode, participantCount: Int) -> String {
            switch mode {
            case .teams: "2 vs 2"
            case .coopBoss: "RAID \(participantCount)P"
            case .freeForAll: "\(participantCount)P"
            }
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
                    .disabled(center.multiplayer.phase != .idle)
                Spacer()
            }
            // **배틀 방만** 그린다. 거르지 않으면 체육관·토너먼트·레이드 방까지 여기 뜨고,
            // 누른 사람은 자기가 고른 적 없는 판에 붙는다. 내 방도 뺀다 — 자기 방은 참가가
            // 조용히 거절돼(`guard phase == .idle`) 눌러도 아무 일이 없는 버튼으로 보인다.
            let visibleRooms = center.multiplayer.rooms.filter {
                LANRoomList.isVisible($0.serviceName, activity: .battle,
                                      myTag: center.multiplayer.myRoomTag)
            }
            if visibleRooms.isEmpty {
                Text(center.multiplayer.isBrowsing ? l.battleNoPeers : l.battleManualHint)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(visibleRooms) { room in
                HStack {
                    Image(systemName: "door.left.hand.open").foregroundStyle(.secondary)
                    Text(room.name).font(.caption).lineLimit(1)
                    Spacer()
                    Button(l.t("참가", "Join", "参加")) { center.multiplayer.join(room) }
                        .controlSize(.small).disabled(center.multiplayer.phase != .idle)
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
                        Text(RecentBattleLabel.text(mode: record.mode,
                                                    participantCount: record.participantCount))
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
                    // 마르면 네 칸이 모두 비활성이라 턴 마감까지 아무것도 할 수 없었다.
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
                               move: { actor, id in
                                   let moves = fighter(actor)?.side.moves ?? []
                                   return moves.first { $0.id == id } ?? .struggle()
                               })
    }
}
