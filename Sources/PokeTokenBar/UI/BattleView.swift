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
        switch center.phase {
        case .ready, .preparing:
            peerList
        case .challenging(let peer):
            waitingView(peer: peer)
        case .incoming(let peer):
            incomingView(peer: peer)
        case .battling:
            if let practice = center.teamPractice { teamPracticeView(practice) }
            else if let b = center.battle { arenaView(b) }       // 맞짱
        case .finished(let iWon, let byForfeit):
            finishedView(iWon: iWon, byForfeit: byForfeit)
        }
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
                        ProgressView(value: Double(fighter.side.hp), total: Double(max(1, fighter.side.stats.hp)))
                            .tint(fighter.isAlive ? .green : .gray).controlSize(.mini)
                        Text("HP \(fighter.side.hp)").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
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
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                        ForEach(Array(me.side.moves.enumerated()), id: \.offset) { index, move in
                            Button {
                                guard let target = multiplayerTargetID else { return }
                                center.multiplayer.submitAction(targetID: target, moveIndex: index)
                            } label: {
                                VStack(spacing: 1) {
                                    Text(move.name(store.language)).font(.caption2).bold().lineLimit(1)
                                    Text("PP \(me.side.pp[index])").font(.system(size: 8)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(multiplayerTargetID == nil || me.side.pp[index] <= 0)
                        }
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
                snapshotCard(opp, title: opp.trainer.map { l.battleTrainerLabel($0) } ?? "?", hpRatio: nil)
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

    // MARK: 대전 화면

    private func arenaView(_ b: NetBattleState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                snapshotCard(b.me.snapshot, title: l.battleMyPokemon,
                             hpRatio: Double(b.me.hp) / Double(max(1, b.me.stats.hp)))
                VStack(spacing: 2) {
                    Text(l.battleTurnLabel(b.turn))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("VS")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 34)
                snapshotCard(b.opp.snapshot,
                             title: b.opp.snapshot.trainer.map { l.battleTrainerLabel($0) } ?? "?",
                             hpRatio: Double(b.opp.hp) / Double(max(1, b.opp.stats.hp)))
            }
            if !b.events.isEmpty { eventLog(b) }
            if b.myChoice == nil {
                Text(l.battleYourTurn).font(.caption).bold()
                moveButtons(b)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.battleWaitingOpponent).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            HStack {
                Spacer()
                Button(l.battleForfeit) { center.forfeit() }
                    .controlSize(.mini)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func teamPracticeView(_ practice: TeamPracticeBattle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                teamSlotCard(practice.mySlot, title: store.language == .ko ? "내 포켓몬" : "My Pokémon")
                Text("VS").font(.headline).foregroundStyle(.secondary)
                teamSlotCard(practice.opponentSlot, title: "CPU")
            }
            HStack(spacing: 4) {
                ForEach(Array(practice.mine.enumerated()), id: \.offset) { index, slot in
                    Button { center.switchTeamPractice(to: index) } label: {
                        VStack(spacing: 1) {
                            SpriteView(speciesID: slot.snapshot.speciesID, size: 25, shiny: slot.snapshot.isShiny)
                            Text("\(slot.hp)").font(.system(size: 7).monospacedDigit())
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                    .disabled(index == practice.myActive || !slot.isAlive)
                }
            }
            Text(store.language == .ko ? "기술" : "Moves").font(.caption.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                ForEach(Array(practice.mySlot.moves.enumerated()), id: \.element.id) { index, move in
                    moveButton(move, pp: practice.mySlot.pp[index]) { center.chooseTeamPracticeMove(index) }
                        .disabled(practice.mySlot.pp[index] <= 0)
                }
            }
            HStack {
                Text("\(practice.mine.filter(\.isAlive).count)/\(practice.mine.count)")
                Spacer()
                Text("CPU \(practice.opponents.filter(\.isAlive).count)/\(practice.opponents.count)")
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func teamSlotCard(_ slot: BattleSide, title: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            SpriteView(speciesID: slot.snapshot.speciesID, size: 52, animated: true, shiny: slot.snapshot.isShiny)
            Text(slot.snapshot.name).font(.caption.bold()).lineLimit(1)
            ProgressView(value: Double(slot.hp), total: Double(max(1, slot.stats.hp)))
                .tint(slot.hp > 0 ? .green : .red)
        }.frame(maxWidth: .infinity).padding(6).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    private func moveButtons(_ b: NetBattleState) -> some View {
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            if b.mustStruggle {
                moveButton(MoveSpec.struggle(), pp: nil) { center.chooseMove(-1) }
            } else {
                ForEach(Array(b.me.moves.enumerated()), id: \.element.id) { idx, move in
                    moveButton(move, pp: b.me.pp[idx]) { center.chooseMove(idx) }
                        .disabled(b.me.pp[idx] <= 0)
                }
            }
        }
    }

    private func moveButton(_ move: MoveSpec, pp: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(move.name(store.language))
                    .font(.caption).bold()
                    .lineLimit(1)
                HStack(spacing: 4) {
                    typeChip(move.type)
                    Text("\(move.power)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let pp {
                        Text("PP \(pp)/\(move.pp)")
                            .font(.system(size: 9))
                            .foregroundStyle(pp == 0 ? .red : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .buttonStyle(.bordered)
    }

    private func finishedView(iWon: Bool?, byForfeit: Bool) -> some View {
        VStack(spacing: 10) {
            Text(finishText(iWon: iWon, byForfeit: byForfeit))
                .font(.title3).bold()
            if center.battle != nil {
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
            if let b = center.battle, !b.events.isEmpty { eventLog(b) }
            Button(l.battleClose) { center.dismissResult() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func finishText(iWon: Bool?, byForfeit: Bool) -> String {
        switch (iWon, byForfeit) {
        case (.some(true), true):   return l.battleOppForfeited
        case (.some(false), true):  return l.battleYouForfeited
        case (.some(true), false):  return l.battleWon
        case (.some(false), false): return l.battleLost
        default:                    return l.battleDraw
        }
    }

    // MARK: 로그/카드 공용

    private func eventLog(_ b: NetBattleState) -> some View {
        // 엔진 좌변(A)은 항상 challenger 다 — 내가 어느 쪽인지로 내 편/상대를 가른다.
        let mine: BattleActor = b.iAmA ? .a : .b
        let lines = BattleLog.lines(b.events, l: l,
                                    name: { $0 == mine ? b.me.snapshot.name : b.opp.snapshot.name },
                                    moveName: { actor, id in
                                        let moves = actor == mine ? b.me.moves : b.opp.moves
                                        return (moves.first { $0.id == id } ?? .struggle()).name(store.language)
                                    })
        return logBox(lines, mine: mine)
    }

    /// 멀티(2~4인)의 스트림은 참가자 UUID 로 쪽을 가른다 — 이름·기술명만 그 방의 파이터에서 찾아 준다.
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

    private func snapshotCard(_ snapshot: BattleSnapshot, title: String, hpRatio: Double?) -> some View {
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
            if let hpRatio {
                ProgressView(value: max(0, min(1, hpRatio)))
                    .tint(hpRatio > 0.5 ? .green : hpRatio > 0.2 ? .yellow : .red)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private func typeChip(_ type: PokemonType) -> some View {
        Text(type.name(store.language))
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
    }
}
