import SwiftUI

/// LAN 협동 레이드(#80) — 오늘의 보스 하나를 같은 네트워크의 트레이너들이 함께 친다.
///
/// 화면이 세 국면을 갈아 끼운다: **모집 전**(오늘의 보스·티어 고르기·근처 방 목록),
/// **로비**(준비·시작), **교전**(보스 한 마리 + 파티 줄 + 정산).
///
/// 대상 고르기가 없다 — 때릴 것은 보스 하나뿐이다. 4인 방(`RoomBattleView.multiplayerArena`)이
/// 대상 격자를 그리는 자리에 여기서는 보스 카드가 들어간다.
struct RaidView: View {
    let store: CompanionStore
    @Environment(BattleCenter.self) private var battleCenter
    let onClose: () -> Void

    /// 턴 재생기 — 1v1·웨이브 런·토너먼트와 **같은 구동자**를 쓴다. 없으면 턴이 해상되는 순간
    /// HP 가 최종값으로 튀고 로그가 한꺼번에 나타나, 무엇이 일어났는지 볼 시간이 없다.
    @State private var animator = BattleAnimator()
    @Environment(AppSettings.self) private var settings

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
        // **오버레이는 자기 높이를 정한다.** 팝오버 본체의 `.frame(height:)` 밖에 놓이므로
        // 안 정하면 창이 콘텐츠 자연 높이로 줄고, 안쪽 `ScrollView` 가 남은 공간만 받아
        // 로그와 채팅이 잘린 채로 뜬다. 형제 오버레이(체육관·던전·꾸미기·대화)와 같은 값을 쓴다 —
        // 오버레이마다 창 높이가 뛰면 화면을 옮길 때마다 창이 요동친다.
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
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
            monPicker
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

    /// 들고 갈 개체를 고른다 — **방에 들어가기 전에만**. 로비에서 바꾸려면 참가자 `speciesID` 와
    /// 스냅샷을 다시 뿌려야 해서 와이어 메시지가 늘어난다(토너먼트가 후보를 방 밖에서 정하는 것과
    /// 같은 자리다).
    ///
    /// **여기서 고르는 것은 레이드 전용 값이 아니라 대표 포켓몬**(`battleRepresentativeID`)이다.
    /// 레이드만의 선택을 따로 두면 FriendView 의 "대표 포켓몬" 과 답이 갈려, 어느 쪽에서 고른 게
    /// 나가는지 알 수 없는 설정이 둘이 된다. 하나를 바꾸면 체육관·토너먼트·퀴즈·포켓슬론·1v1 도
    /// 같이 바뀐다 — 그 사실은 아래 문구가 말한다. 세이브에 이미 있는 필드라 저장도 공짜다.
    ///
    /// **티어·방 목록 아래에 둔다.** 위에 두면 피커 높이(칩 줄에 기술 미리보기까지)만큼 이웃의 방
    /// 목록이 화면 밖으로 밀려, 30초짜리 모집 창을 내 피커를 지나쳐 가며 찾게 된다 —
    /// `GymLeagueView` 가 팀 고르기를 맨 아래 고정한 이유와 같다.
    ///
    /// 고르는 것은 **선택 사항이라 티어·참가 버튼을 잠그지 않는다**(6마리를 요구하는 토너먼트와
    /// 다른 점이다). 안 고르면 예전처럼 `battleFacadeMon` 이 나가고, 그게 누구인지는 아래 문구가
    /// 이름으로 말한다.
    ///
    /// 후보가 하나뿐이면 **통째로 감춘다.** `TeamPicker` 가 그때 아무것도 안 그려서, 남는 것이
    /// 제목과 문구뿐인 빈 칸이 된다 — 고를 게 없는 화면이 아니라 불러오기에 실패한 화면으로 읽힌다.
    @ViewBuilder
    private var monPicker: some View {
        if store.deployableMons.count > 1 {
            VStack(alignment: .leading, spacing: 5) {
                Text(l.raidPickMon).font(.caption).bold()
                TeamPicker(store: store,
                           selection: Binding(get: { store.battleRepresentative.map { [$0.id] } ?? [] },
                                              set: { store.setBattleRepresentative($0.last) }),
                           limit: 1)
                    // 방을 여는·들어가는 동안에는 잠근다 — 티어·참가 버튼과 같은 조건이다.
                    // 그 사이에 바꾸면 컨트롤은 따라 바뀌는데 스냅샷은 이미 떠난 뒤라,
                    // "방에 들어간 뒤에는 못 바꾼다" 는 약속이 한 발 일찍 깨진다.
                    .disabled(center.phase != .idle)
                Text(l.raidPickMonHint(defaultRunnerName)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// 안 골랐을 때 **실제로** 나가는 개체의 이름 — `buildSnapshot` 이 쓰는 것과 같은 규칙
    /// (`battleFacadeMon`)이다. "동행" 이라고 못 박으면 동행이 알이거나 체육관을 지키는 동안엔
    /// 화면이 거짓말을 한다. 하필 그 두 경우가 이 피커를 만든 이유다.
    private var defaultRunnerName: String {
        guard let mon = store.battleFacadeMon else { return "" }
        return RosterOrdering.displayName(mon, language: store.language)
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
        // **표시용 개체는 재생기가 준다** — 엔진의 최종 상태를 그대로 그리면 재생할 것이 없다.
        // 모르는 주인은 엔진 값으로 접는다(첫 프레임·관전 입장 직후).
        func display(_ fighter: MultiplayerFighter) -> BattleSide {
            animator.side(for: .fighter(fighter.id))?.side ?? fighter.side
        }
        let bossFighter = fighters.first { $0.id == RaidBoss.bossID }
        let party = fighters.filter { $0.team == .red }.map {
            RaidArenaView.Cell(id: $0.id, title: $0.trainerName, side: display($0))
        }
        let visible = RaidArena.visibleEvents(center.combatEvents, playedCount: animator.playedCount)
        let showsResult = RaidArena.showsResult(isFinished: center.isBattleFinished,
                                                playedCount: animator.playedCount,
                                                streamCount: center.combatEvents.count,
                                                isReplaying: animator.overlay.isPlaying)
        return VStack(alignment: .leading, spacing: 8) {
            if let bossFighter {
                RaidArenaView(
                    boss: RaidArenaView.Cell(id: bossFighter.id, title: bossFighter.trainerName,
                                             side: display(bossFighter)),
                    bossMaxHP: center.raidTier?.bossHP ?? max(1, bossFighter.side.stats.hp),
                    party: party, myID: center.myID, l: l,
                    round: center.combatRound,
                    turnsLeft: max(0, RaidBoss.turnCap - center.combatRound + 1),
                    overlay: animator.overlay,
                    logLines: logLines(visible, fighters: fighters),
                    acceptsInput: RaidArena.acceptsInput(
                        hasSubmitted: center.hasSubmittedAction,
                        isAlive: fighters.first { $0.id == center.myID }?.isAlive ?? false,
                        isFinished: center.isBattleFinished,
                        isReplaying: animator.overlay.isPlaying),
                    isFinished: center.isBattleFinished
                ) { index in
                    center.submitAction(targetID: RaidBoss.bossID, moveIndex: index)
                }
            }
            if showsResult { finishedFooter }
            BattleChatPanel(configuration: BattleChatConfiguration(
                messages: center.chatMessages, mySenderID: center.myID,
                isEnabled: true, unavailableMessage: nil, l: l, onSend: center.sendChat))
        }
        // 재생이 따라잡을 때마다 화면을 다시 그린다. 스트림이 길어지는 자리와 개시가 모두
        // 여기를 지나야 한다 — `onAppear` 만 두면 방에 들어와 있는 동안 온 라운드를 못 받는다.
        .onAppear { syncReplay() }
        .onChange(of: center.combatEvents.count) { syncReplay() }
        .onChange(of: center.combatRound) { syncReplay() }
        // **이벤트 없이 끝나는 경로가 있다.** 이탈 몰수와 턴 상한은 `broadcastCombatState()` 로
        // 빈 이벤트를 보내므로 위 둘이 안 바뀐다 — 전투원만 바뀐다. 여기서 안 부르면 재생기의
        // 엔진 값이 낡은 채로 남아 `reconcile()` 도 `onCaughtUp` 도 지나지 않는다.
        .onChange(of: center.combatFighters.map(\.side.hp)) { syncReplay() }
    }

    /// 재생기에 스트림을 넘긴다. 속도 규칙은 기존 배틀과 같다(저전력이면 설정과 무관하게 끈다) —
    /// `RogueRunView.replay` 와 같은 자리다.
    private func syncReplay() {
        animator.sync(events: center.combatEvents,
                      sides: RaidArena.replaySides(center.combatFighters),
                      speed: BattleReplay.effectiveSpeed(
                        settings.battleReplaySpeed,
                        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
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
                    settlementRow(l.raidTurnsLeft, settlement.turnBonus)
                    settlementRow(l.raidRewardSurvivors, settlement.survivorBonus)
                    // 협동 항이 접힌 판은 **그 사실을 말한다** — 안 말하면 `+0 ✨` 세 줄이 규칙이
                    // 아니라 계산 오류로 읽힌다(아래 하루 한 번 게이트와 같은 이유). 지급이 0 이
                    // 아니라 그 문구는 안 뜨는 자리다.
                    if !RaidBoss.coopTermsApply(runnerCount: runnerCount) {
                        Text(l.raidSoloSettlement).font(.caption2).foregroundStyle(.orange)
                    }
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
            if let caught = catchLine {
                Text(caught).font(.caption2).foregroundStyle(.purple)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(l.t("나가기", "Leave", "退出")) { center.leaveRoom() }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }
    }

    /// 이 판의 러너 수 — 보스는 사람이 아니라 세지 않는다(정산이 같은 배열에서 세는 것과 같다).
    private var runnerCount: Int {
        center.combatFighters.filter { $0.team == .red }.count
    }

    /// 누가 보스를 데려갔나. **남이 뽑힌 판도 말해 준다** — 아무 말이 없으면 "나만 못 받았다" 가
    /// 아니라 "이 기능이 안 돌았다" 로 읽힌다. 추첨이 없는 판(1★·1인·패배)은 줄 자체가 없다.
    private var catchLine: String? {
        guard let winner = center.raidCatcherID,
              let boss = center.combatFighters.first(where: { $0.id == RaidBoss.bossID })
        else { return nil }
        let name = boss.trainerName
        guard winner != center.myID else {
            // 내 줄은 **실제 결과**를 기다린다. 뽑힌 것만으로 "박스에 있어요" 를 그리면, 라인 조회가
            // 실패한 판에서 오류 문구와 모순되는 두 문장이 한 화면에 남고 박스는 비어 있다.
            // 못 잡은 사유는 `lastError` 가 이미 말한다(같은 스크롤 안에 그려진다).
            switch center.raidCatchResult {
            case .box: return l.raidCaughtByMe(name, toBox: true)
            case .companion: return l.raidCaughtByMe(name, toBox: false)
            case .claimedToday, .unavailable, nil: return nil
            }
        }
        let trainer = center.combatFighters.first { $0.id == winner }?.trainerName ?? "?"
        return l.raidCaughtByOther(trainer: trainer, name: name)
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

    /// 패배 문구는 **두 가지**다. 턴 상한과 파티 전멸은 다음에 할 일이 다르다 —
    /// 전부 "턴이 다 됐습니다" 로 덮으면 17턴 남기고 전멸한 판도 화력 부족으로 읽힌다.
    private var resultText: String {
        switch center.myOutcome {
        case .win: l.t("보스를 쓰러뜨렸다!", "The boss is down!", "ボスを倒した！")
        case .loss: RaidBoss.endedByTurnCap(round: center.combatRound) ? l.raidTurnCapReached : l.raidPartyWiped
        default: l.t("레이드 종료", "Raid over", "レイド終了")
        }
    }

    /// 로그 줄 만들기 — 4인 방(`RoomBattleView.multiplayerLogLines`)과 **같은 규칙**을 쓴다.
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
