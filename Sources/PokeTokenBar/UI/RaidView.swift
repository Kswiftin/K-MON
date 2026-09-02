import SwiftUI

/// LAN 협동 레이드(#80) — 오늘의 보스 하나를 같은 네트워크의 트레이너들이 함께 친다.
///
/// 화면이 세 국면을 갈아 끼운다: **모집 전**(오늘의 보스·티어 고르기·근처 방 목록),
/// **로비**(준비·시작), **교전**(보스 한 마리 + 파티 줄 + 정산).
///
/// 대상 고르기가 없다 — 때릴 것은 보스 하나뿐이다. 4인 방(`BattleView.multiplayerArena`)이
/// 대상 격자를 그리는 자리에 여기서는 보스 카드가 들어간다.
struct RaidView: View {
    let store: CompanionStore
    @Environment(BattleCenter.self) private var battleCenter
    let onClose: () -> Void

    @State private var pickedTier: RaidTier = .one

    private var center: MultiplayerRoomCenter { battleCenter.multiplayer }
    private var l: L { store.l }
    private var isRaidRoom: Bool { center.roomActivity == .raid }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if center.phase == .battling, center.combatMode == .coopBoss {
                        arena
                    } else if isRaidRoom, let lobby = center.lobby {
                        lobbyContent(lobby)
                    } else {
                        recruiting
                    }
                    if let error = center.lastError {
                        Text(error).font(.caption2).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(10)
    }

    private var header: some View {
        HStack {
            Label(l.raidTitle, systemImage: "person.3.sequence.fill").font(.callout).bold()
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    // MARK: 모집 전

    private var recruiting: some View {
        VStack(alignment: .leading, spacing: 10) {
            todaysBossCard
            tierPicker
            nearbyRooms
            if store.raidRewardClaimedToday {
                Text(l.raidAlreadyPaidToday).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var todaysBossCard: some View {
        HStack(spacing: 10) {
            SpriteView(speciesID: center.todaysRaidSpeciesID, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(l.raidTodaysBoss).font(.caption2).foregroundStyle(.secondary)
                // 이름은 비동기 조회라 여기서 쓰지 않는다 — 스프라이트가 이미 누구인지 말하고,
                // 정확한 이름은 교전이 시작되면 스냅샷이 싣고 온다.
                Text(l.raidTitle).font(.callout).bold()
                // 다음 5★ 시각은 **아침에 공개된다** — 무작위인데 안 알려 주면 마침 접속해 있던
                // 사람만 참여하게 되고, 그러면 무작위로 둔 이유가 사라진다.
                if let next = RaidSchedule.nextHatch(after: Date()) {
                    Text("\(l.raidNextHatch) · \(next.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(9)
        .pokedoroCard(tint: .purple)
    }

    /// 티어는 고를 수 있고 **보스는 못 고른다** — 고르게 두면 모두가 가장 이득인 하나만 판다.
    /// 5★ 는 부화 창 안에서만 열린다: 예약이 존재하는 이유가 혼자서는 못 여는 티어를 위해
    /// 사람을 모으는 것이라, 아무 때나 열 수 있으면 예약이 뜻을 잃는다.
    private var tierPicker: some View {
        let hatchIsLive = RaidSchedule.activeHatch(at: Date()) != nil
        let tiers = RaidBoss.adHocTiers + (hatchIsLive ? [RaidBoss.hatchTier] : [])
        return VStack(alignment: .leading, spacing: 5) {
            Text(l.raidTitle).font(.caption).bold()
            HStack(spacing: 6) {
                ForEach(tiers, id: \.rawValue) { tier in
                    Button {
                        pickedTier = tier
                        center.createRaidRoom(tier: tier)
                    } label: {
                        VStack(spacing: 1) {
                            Text("\(tier.rawValue)★").font(.callout.bold())
                            Text(l.raidTierLabel(tier.rawValue, runners: tier.recommendedRunners))
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(center.phase != .idle)
                }
            }
        }
    }

    private var nearbyRooms: some View {
        let rooms = center.rooms.compactMap { peer -> (MultiplayerRoomPeer, RaidRoomName)? in
            guard let parsed = RaidRoomName.parse(peer.serviceName),
                  parsed.idTag != center.myRoomTag else { return nil }
            return (peer, parsed)
        }
        return VStack(alignment: .leading, spacing: 5) {
            if rooms.isEmpty {
                Text(center.isBrowsing ? l.battleNoPeers : l.battleManualHint)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(rooms, id: \.0.id) { peer, parsed in
                HStack(spacing: 6) {
                    Text("\(parsed.tier.rawValue)★").font(.caption.bold()).foregroundStyle(.purple)
                    Text(parsed.trainerName).font(.caption).lineLimit(1)
                    Spacer()
                    Button(l.t("참가", "Join", "参加")) { center.join(peer) }
                        .controlSize(.small).disabled(center.phase != .idle)
                }
            }
        }
    }

    // MARK: 로비

    private func lobbyContent(_ lobby: MultiplayerLobby) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let tier = center.raidTier {
                Text(l.raidTierLabel(tier.rawValue, runners: tier.recommendedRunners))
                    .font(.caption).bold()
            }
            ForEach(lobby.runners) { participant in
                HStack(spacing: 7) {
                    SpriteView(speciesID: participant.speciesID, size: 28)
                    Text(participant.trainerName).font(.caption).bold().lineLimit(1)
                    Spacer()
                    Image(systemName: participant.isReady ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(participant.isReady ? .green : .secondary)
                }
                .padding(5)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }
            HStack {
                Button(center.myParticipant?.isReady == true
                       ? l.t("준비 취소", "Cancel ready", "準備をやめる")
                       : l.t("준비", "Ready", "準備完了")) { center.toggleReady() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Spacer()
                // 러너 한 명이면 혼자 시작한다 — LAN 은 이웃이 없을 수 있고, 1★ 를 혼자 못 돌면
                // 이웃 없는 사용자에게 이 기능은 콘텐츠가 0 이다.
                if center.isHost, lobby.canStart {
                    Button(l.t("레이드 시작", "Start raid", "レイド開始")) { center.startRaid() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                Button(l.t("나가기", "Leave", "退出")) { center.leaveRoom() }.controlSize(.small)
            }
        }
    }

    // MARK: 교전

    private var arena: some View {
        let fighters = center.combatFighters
        let boss = fighters.first { $0.id == RaidBoss.bossID }
        let party = fighters.filter { $0.team == .red }
        let me = fighters.first { $0.id == center.myID }
        return VStack(alignment: .leading, spacing: 8) {
            if let boss { bossCard(boss) }
            partyRow(party)
            if center.isBattleFinished { finishedFooter }
            else if me?.isAlive == false {
                Text(l.t("탈락 — 파티를 응원하고 있습니다.", "Knocked out - cheering the party on.",
                         "戦闘不能 — パーティを応援中です。"))
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else if center.hasSubmittedAction {
                HStack { ProgressView().controlSize(.small)
                    Text(l.t("다른 참가자의 행동을 기다리는 중…", "Waiting for other players…",
                             "ほかの参加者の行動を待っています…")) }
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else if let me {
                // 대상 고르기가 없다 — 때릴 것은 보스 하나다.
                let struggling = me.side.mustStruggle
                MoveGridView(moves: struggling ? [.struggle()] : me.side.moves,
                             pp: struggling ? [] : me.side.pp, language: store.language,
                             isEnabled: true) { index in
                    center.submitAction(targetID: RaidBoss.bossID, moveIndex: struggling ? -1 : index)
                }
            }
            if !center.combatEvents.isEmpty {
                BattleLogBox(lines: logLines(center.combatEvents, fighters: fighters),
                             myActor: .fighter(center.myID))
            }
            BattleChatPanel(configuration: BattleChatConfiguration(
                messages: center.chatMessages, mySenderID: center.myID,
                isEnabled: true, unavailableMessage: nil, l: l, onSend: center.sendChat))
        }
    }

    private func bossCard(_ boss: MultiplayerFighter) -> some View {
        // 보스 HP 는 종족값이 아니라 **티어가 정하는 절대값**이라 막대의 분모도 거기서 온다.
        // `side.stats.hp` 로 나누면 막대가 100% 를 넘어 화면 밖으로 나간다.
        let maxHP = center.raidTier?.bossHP ?? max(1, boss.side.stats.hp)
        return VStack(spacing: 3) {
            HStack {
                Text(boss.trainerName).font(.caption.bold())
                Spacer()
                Text("R\(center.combatRound) · \(l.raidTurnsLeft) \(max(0, RaidBoss.turnCap - center.combatRound + 1))")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            SpriteView(speciesID: boss.side.snapshot.speciesID, size: 64)
                .opacity(boss.isAlive ? 1 : 0.25)
            ProgressView(value: Double(max(0, boss.side.hp)), total: Double(maxHP))
                .tint(HPTier.of(hp: boss.side.hp, max: maxHP).color)
            Text("\(max(0, boss.side.hp)) / \(maxHP)")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            StatusBadgeRow(side: boss.side)
        }
        .padding(8)
        .pokedoroCard(tint: .purple)
    }

    private func partyRow(_ party: [MultiplayerFighter]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(party) { fighter in
                VStack(spacing: 2) {
                    Text(fighter.trainerName).font(.caption2).bold().lineLimit(1)
                    SpriteView(speciesID: fighter.side.snapshot.speciesID, size: 34,
                               shiny: fighter.side.snapshot.isShiny)
                        .opacity(fighter.isAlive ? 1 : 0.25)
                    ProgressView(value: Double(max(0, fighter.side.hp)),
                                 total: Double(max(1, fighter.side.stats.hp)))
                        .tint(HPTier.of(hp: fighter.side.hp, max: fighter.side.stats.hp).color)
                        .controlSize(.mini)
                    Text(fighter.id == center.myID
                         ? HPReadout.mine(hp: fighter.side.hp, max: fighter.side.stats.hp)
                         : HPReadout.theirs(hp: fighter.side.hp, max: fighter.side.stats.hp))
                        .font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                    StatusBadgeRow(side: fighter.side)
                }
                .padding(5)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    /// 정산은 **항목별로** 그린다. 지갑을 바꾼 값은 그 자리에서 설명돼야 한다 —
    /// 알림은 그 표면의 대체가 아니다(defect-log: 한 지갑에 지급하는 경로가 여럿일 때).
    private var finishedFooter: some View {
        VStack(spacing: 6) {
            Text(resultText).font(.title3).bold().frame(maxWidth: .infinity)
            if let settlement = center.raidSettlement {
                VStack(alignment: .leading, spacing: 2) {
                    settlementRow(l.raidRewardBase, settlement.base)
                    settlementRow(l.raidContribution, settlement.contribution)
                    settlementRow(l.raidRewardTurns, settlement.turnBonus)
                    settlementRow(l.raidRewardSurvivors, settlement.survivorBonus)
                    Divider().opacity(0.5)
                    if let payout = center.raidPayout, payout > 0 {
                        settlementRow(l.t("지급", "Paid", "支給"), payout, emphasized: true)
                    } else {
                        // 하루 한 번 게이트에 걸렸다는 사실을 **말해 준다** — 안 말하면 정산표만
                        // 보이고 잔액이 안 늘어 계산이 틀린 것처럼 보인다.
                        Text(l.raidAlreadyPaidToday).font(.caption2).foregroundStyle(.orange)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            Button(l.t("나가기", "Leave", "退出")) { center.leaveRoom() }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }
    }

    private func settlementRow(_ label: String, _ value: Int, emphasized: Bool = false) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text("+\(GameNumberFormatter.compact(value)) ✨")
                .font(emphasized ? .caption.bold() : .caption2)
                .foregroundStyle(emphasized ? Color.orange : .primary)
        }
    }

    private var resultText: String {
        switch center.myOutcome {
        case .win: l.t("보스를 쓰러뜨렸다!", "The boss is down!", "ボスを倒した！")
        case .loss: l.raidTurnCapReached
        default: l.t("레이드 종료", "Raid over", "レイド終了")
        }
    }

    /// 로그 줄 만들기 — 4인 방(`BattleView.multiplayerLogLines`)과 **같은 규칙**을 쓴다.
    /// 갈라 두면 같은 사건이 두 화면에서 다른 문장으로 나온다.
    private func logLines(_ events: [BattleEvent], fighters: [MultiplayerFighter]) -> [BattleLog.Line] {
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
