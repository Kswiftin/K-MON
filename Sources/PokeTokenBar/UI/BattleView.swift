import AppKit
import SwiftUI

/// 배틀 탭 — 같은 네트워크(LAN) 실시간 대전. 상대 목록에서 신청하고, 신청이 오면
/// 알림+수락 화면, 대전 중엔 기술 4개 중 선택.
struct BattleView: View {
    @Bindable var store: CompanionStore
    @Environment(BattleCenter.self) private var center
    @Environment(AppSettings.self) private var settings
    /// 턴 해상 결과를 시간축에 푸는 재생기 — 배틀이 바뀌어도 같은 객체를 쓴다(스스로 되감는다).
    @State private var animator = BattleAnimator()

    // 수동(IP) 연결 상태
    @State private var manualAddress = ""
    @State private var addressCopied = false
    @State private var peerPage = 0
    @State private var pendingChallengePeer: BattlePeer?
    /// 수동 IP 로 신청하려는 주소. 탐색으로 찾은 상대와 **같은 후보 선택 화면**을 지나야 한다 —
    /// 신청은 후보 6마리를 요구하는데 이 화면에는 고를 자리가 없었다(mDNS 가 막힌 환경의 폴백이
    /// 항상 "먼저 후보를 선택하세요" 로 끝났다).
    @State private var pendingManualAddress: String?

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
            // 알을 품는 중인 것 자체는 막을 이유가 아니다 — 박스에 키워 둔 개체가 있으면 그걸로
            // 싸운다. 정말 못 싸우는 건 내보낼 개체가 하나도 없을 때다.
            if !store.hasBattleReadyMon {
                Text(l.battleNeedHatch)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                networkSection
            }
        }
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
        case .poolSelecting(let peer):
            poolSelectingView(peer: peer)
        case .teamBuilding(let peer):
            teamBuildingView(peer: peer, waiting: false)
        case .poolBuilding(let peer):
            VStack(spacing: 8) {
                ProgressView()
                Text(l.t("\(peer)님과 후보 6마리를 공개하는 중…",
                         "Revealing six candidates with \(peer)…",
                         "\(peer)と候補6匹を公開中…"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .waitingTeam(let peer):
            teamBuildingView(peer: peer, waiting: true)
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
            calledMoves: battle.eventBatches.flatMap { $0.a.moves + $0.b.moves },
            myBeginnerMode: settings.beginnerModeEnabled,
            theirBeginnerMode: center.opponentRankProfile?.beginnerMode == true,
            onChoose: { center.chooseMove($0) },
            onSwitch: { center.switchLAN(to: $0) },
            onForfeit: { center.forfeit() },
            chat: BattleChatConfiguration(messages: center.chatMessages, mySenderID: center.chatSenderID,
                                          isEnabled: center.chatIsAvailable,
                                          unavailableMessage: center.chatLockMessage,
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
    @ViewBuilder private var peerList: some View {
        if let peer = pendingChallengePeer {
            candidateSelection(named: peer.name) { center.challenge(peer) }
        } else if let address = pendingManualAddress {
            candidateSelection(named: address) { center.challengeManual(address) }
        } else {
            peerBrowser
        }
    }

    private func candidateSelection(named opponent: String, challenge: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { pendingChallengePeer = nil; pendingManualAddress = nil } label: {
                Label(l.t("다른 트레이너 선택", "Choose another trainer", "別のトレーナーを選ぶ"),
                      systemImage: "chevron.left")
            }.buttonStyle(.borderless)
            Label(l.t("배틀 후보 6마리", "Six Battle Candidates", "バトル候補6匹"),
                  systemImage: "square.grid.3x2.fill")
                .font(.caption.bold())
            Text(l.t("\(opponent)님과 배틀할 후보를 고르세요. 이후에 상대를 다시 고르지 않습니다.",
                     "Choose the pool for your battle with \(opponent). You won't choose the trainer again.",
                     "\(opponent)と戦う候補を選んでください。相手の再選択はありません。"))
                .font(.caption).foregroundStyle(.secondary)
            TeamPicker(store: store,
                       selection: Binding(get: { center.pickedTeam }, set: { center.pickedTeam = $0 }),
                       limit: 6)
            HStack {
                Text("\(center.pickedTeam.count) / 6")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button(l.battleChallengeButton) {
                    pendingChallengePeer = nil
                    pendingManualAddress = nil
                    challenge()
                }
                .buttonStyle(.borderedProminent)
                .disabled(center.pickedTeam.count != 6)
            }
        }
    }

    private var peerBrowser: some View {
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

            Text(l.t("먼저 후보 6마리를 공개한 뒤 실제 출전 포켓몬을 고릅니다.",
                     "Reveal six candidates first, then choose the battle team.",
                     "先に候補6匹を公開してから実際の出場ポケモンを選びます。"))
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Label(store.battleRank.displayName, systemImage: "shield.lefthalf.filled")
                    .foregroundStyle(store.battleRank.tier.tint)
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
                        PeerRow(store: store, peer: peer, isEnabled: center.phase == .ready) {
                            pendingChallengePeer = peer
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
        let address = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BattleCenter.manualEndpoint(address) != nil else {
            center.reportBadManualAddress()
            return
        }
        pendingManualAddress = address
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
                    if profile.beginnerMode { BeginnerBadgeView(l: l) }
                    if center.incomingRankedStake > 0 {
                        Text(l.battleFixedStake(GameNumberFormatter.compact(center.incomingRankedStake)))
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
            }
            if store.deployableMons.count < 6 {
                Text(l.t("배틀을 수락하려면 포켓몬이 6마리 필요합니다.",
                         "You need six Pokémon to accept this battle.",
                         "バトルを承認するにはポケモンが6匹必要です。"))
                    .font(.caption2).foregroundStyle(.orange)
            } else if let error = center.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button(l.battleAccept) { center.acceptIncoming() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.deployableMons.count < 6)
                Button(l.battleDecline) { center.declineIncoming() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func poolSelectingView(peer: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(l.t("공개할 후보 6마리", "Choose Six Candidates", "公開する候補6匹"),
                  systemImage: "square.grid.3x2.fill")
                .font(.headline)
            Text(l.t("\(peer)님에게 공개할 포켓몬 6마리를 선택하세요. 서로의 후보가 준비되면 실제 출전 파티를 고릅니다.",
                     "Choose six Pokémon to reveal to \(peer). After both pools are ready, choose the actual battle team.",
                     "\(peer)に公開する6匹を選んでください。両方の候補が揃ったら実際の出場パーティを選びます。"))
                .font(.caption).foregroundStyle(.secondary)
            TeamPicker(store: store,
                       selection: Binding(get: { center.incomingPickedTeam },
                                          set: { center.incomingPickedTeam = $0 }),
                       limit: 6)
            if let error = center.lastError { Text(error).font(.caption2).foregroundStyle(.orange) }
            HStack {
                Button(l.battleCancel) { center.cancelChallenge() }
                Spacer()
                Text("\(center.incomingPickedTeam.count) / 6")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button(l.t("후보 공개", "Reveal Candidates", "候補を公開")) { center.confirmBattlePool() }
                    .buttonStyle(.borderedProminent)
                    .disabled(center.incomingPickedTeam.count != 6)
            }
        }.padding(.vertical, 4)
    }

    private func teamBuildingView(peer: String, waiting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(l.t("파티 편성", "Choose Your Party", "パーティ編成"), systemImage: "person.3.fill")
                .font(.headline)
            Text(l.t("\(peer)님이 수락했습니다. 두 트레이너가 모두 확인하면 배틀이 시작됩니다.",
                     "\(peer) accepted. The battle starts after both trainers confirm.",
                     "\(peer)が承認しました。両方が確認するとバトル開始です。"))
                .font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Binding(get: { center.incomingTeamSize }, set: { _ in })) {
                Text("\(center.incomingTeamSize) vs \(center.incomingTeamSize)").tag(center.incomingTeamSize)
            }.pickerStyle(.segmented).labelsHidden().disabled(true)
            if !center.incomingBattlePool.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.t("상대 후보 6마리", "Opponent's six candidates", "相手の候補6匹"))
                        .font(.caption.bold())
                    HStack(spacing: 5) {
                        ForEach(Array(center.incomingBattlePool.enumerated()), id: \.offset) { _, snapshot in
                            VStack(spacing: 1) {
                                SpriteView(speciesID: snapshot.speciesID, size: 30, shiny: snapshot.isShiny)
                                Text(snapshot.name).font(.system(size: 7)).lineLimit(1)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            TeamPicker(store: store,
                       selection: Binding(get: { center.incomingPickedTeam },
                                          set: { center.incomingPickedTeam = $0 }),
                       limit: center.incomingTeamSize,
                       allowedIDs: Set(center.battlePoolIDs))
                .disabled(waiting)
            HStack {
                Button(l.battleCancel) { center.cancelChallenge() }.disabled(waiting)
                Spacer()
                if waiting {
                    ProgressView().controlSize(.small)
                    Text(l.t("상대 확인 대기 중…", "Waiting for opponent…", "相手の確認待ち…"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(l.t("파티 확인", "Confirm Party", "パーティ確認")) { center.confirmBattleTeam() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.ownedMons.count < center.incomingTeamSize)
                }
            }
        }.padding(.vertical, 4)
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
                .foregroundStyle(peer.rank?.tier.tint ?? Color.secondary)
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
