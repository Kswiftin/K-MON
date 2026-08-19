import AppKit
import SwiftUI

/// 배틀 탭 — 같은 네트워크(LAN) 실시간 대전. 상대 목록에서 신청하고, 신청이 오면
/// 알림+수락 화면, 대전 중엔 기술 4개 중 선택.
struct BattleView: View {
    @Bindable var store: CompanionStore
    @Environment(BattleCenter.self) private var center

    // 수동(IP) 연결 상태
    @State private var manualAddress = ""
    @State private var addressCopied = false
    @State private var roomMode: MultiplayerBattleMode = .freeForAll
    @State private var multiplayerTargetID: UUID?

    private var l: L { store.l }

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
        // 1v1 LAN·연습 배틀은 전용 창이 그린다(계획 §6.3 안 A) — 팝오버에 같은 화면을 한 벌 더
        // 두면 스프라이트 GIF 트리가 둘이 되고, 어느 쪽을 봐야 하는지도 애매해진다.
        if center.wantsBattleWindow {
            battleWindowPointer
        } else {
            switch center.phase {
            case .ready, .preparing:
                peerList
            case .challenging(let peer):
                waitingView(peer: peer)
            case .incoming(let peer):
                incomingView(peer: peer)
            case .battling, .finished:
                // 창이 맡는 구간이라 여기 올 일이 없다(`wantsBattleWindow` 가 먼저 걸린다).
                battleWindowPointer
            }
        }
    }

    /// 배틀이 창으로 옮겨 갔다는 안내. 창이 다른 창에 가려졌을 때 다시 끌어올 길이 필요하다.
    private var battleWindowPointer: some View {
        VStack(spacing: 10) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.title2).foregroundStyle(.secondary)
            Text(l.battleRunsInItsOwnWindow)
                .font(.callout).multilineTextAlignment(.center)
            Button(l.battleShowWindow) {
                (NSApp.delegate as? AppDelegate)?.showBattleWindow()
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var peerList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(store.language == .ko ? "랭크배틀 · 전원 Lv.50" : "Ranked Battle · All Pokémon Lv.50",
                  systemImage: "shield.lefthalf.filled")
                .font(.caption.bold())
            Picker("", selection: Binding(get: { center.rankedTeamSize }, set: { center.rankedTeamSize = $0 })) {
                Text("1 vs 1").tag(1)
                Text("3 vs 3").tag(3)
                Text("6 vs 6").tag(6)
            }.pickerStyle(.segmented).labelsHidden()

            Button {
                center.startRankedPractice()
            } label: {
                Label(store.language == .ko ? "CPU 모의전" : "Practice vs CPU", systemImage: "gamecontroller.fill")
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .disabled(!isChallengeEnabled)
            Text(store.language == .ko
                 ? "실전과 동일한 Lv.50 규칙 · 랭크와 별의조각은 변하지 않음"
                 : "Same Lv.50 rules · rank and Star Pieces are unchanged")
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
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(center.peers) { peer in
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
                    }
                }
                .frame(maxHeight: 180)
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
        let targets = fighters.filter { fighter in
            guard fighter.id != center.multiplayer.myID, fighter.isAlive else { return false }
            if center.multiplayer.lobby?.mode == .teams, let myTeam = me?.team { return fighter.team != myTeam }
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
                            if center.multiplayer.lobby?.mode == .teams {
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
                Text(center.multiplayer.didIWin
                     ? (store.language == .ko ? "승리!" : "Victory!")
                     : (store.language == .ko ? "패배" : "Defeated"))
                    .font(.title3).bold().frame(maxWidth: .infinity)
                if let reward = center.multiplayer.battleReward {
                    Text("+\(reward) ✨")
                        .font(.callout.weight(.semibold)).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                }
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
                    // 1v1 과 같은 버튼을 쓴다 — 타입색·분류 아이콘·PP 경고 단계가 모드마다 다를 이유가 없다.
                    MoveGridView(moves: me.side.moves, pp: me.side.pp, language: store.language,
                                 isEnabled: multiplayerTargetID != nil) { index in
                        guard let target = multiplayerTargetID else { return }
                        center.multiplayer.submitAction(targetID: target, moveIndex: index)
                    }
                }
            }
            if !center.multiplayer.combatEvents.isEmpty {
                // 1v1 과 스트림도 접기도 같다. 예전엔 여기만 "이름 → 이름: -12" 라는
                // 별도 문구였고, 기술 이름도 급소도 상성도 나오지 않았다.
                logBox(multiplayerLogLines(center.multiplayer.combatEvents, fighters: fighters),
                       mine: .fighter(center.multiplayer.myID))
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
        VStack(spacing: 8) {
            Text("⚔️ \(l.battleIncomingFrom(peer))")
                .font(.callout).bold()
                .multilineTextAlignment(.center)
            Text(l.battleKindBrawl)
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
            HStack(spacing: 12) {
                Button(l.battleAccept) { center.acceptIncoming() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(l.battleDecline) { center.declineIncoming() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: 로그/카드 공용

    /// 멀티(2~4인)의 스트림은 참가자 UUID 로 쪽을 가른다 — 이름·기술명만 그 방의 파이터에서 찾아 준다.
    /// 좌우 두 자리인 1v1·연습 배틀은 `BattleLogSource.twoSided` 가 맡는다(창이 그 화면을 그린다).
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

    /// 스트림을 접은 줄만 그린다 — 문구 결정은 `BattleLog` 에 있다(뷰는 순수 렌더러).
    /// 최근 몇 줄만 보이는 구조라 `ScrollView` 는 쓰지 않는다 — 팝오버 본체가 이미 스크롤이고,
    /// 그 안에 세로 스크롤을 겹치면 안쪽이 스크롤되지 않고 잘린다(defect-log 규칙).
    private func logBox(_ lines: [BattleLog.Line], mine: BattleActor?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.suffix(4).enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(.caption2)
                    .foregroundStyle(line.actor == mine ? .primary : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
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
