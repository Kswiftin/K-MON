import SwiftUI

struct FocusTimerView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(AppSettings.self) private var settings
    @Environment(CompanionStore.self) private var companion
    @State private var selectedMinutes = 25
    /// 마지막 정산 — 스토어에서 한 번 건네받아 들고 있는다(사탕 "+XP" 와 같은 1회성 계약).
    /// 소비하지 않고 스토어를 직접 그리면, 팝오버를 닫았다 열 때마다 같은 정산이 다시 떠오른다.
    @State private var claimBanner: AdventureReward?
    @State private var seenClaimSeq = 0
    /// 정산이 비어 있던 세션 완료를 한 줄로 알린다. 배너와 **배타**다 — 정산이 들어오면 그쪽이 이긴다.
    @State private var sessionDone = false
    /// 위 두 안내가 **어느 세션의 것인지**. `timer.sessionStartSeq` 와 어긋나면 다음 집중이 이미
    /// 시작된 것이라 내린다 — 새 세션 시작이 유일한 소멸 계기다(자동 소멸도 닫기 버튼도 없다).
    ///
    /// `onChange` 로 지우지 않고 **값을 비교**하는 이유: 모험 시작 정산은 시작과 *같은 갱신*에서
    /// 들어온다(`startFocusSession` → `startFocusAdventure` 가 이전 모험을 정산한 뒤 `startFocus`).
    /// 지우는 쪽을 onChange 에 두면 두 핸들러의 순서에 따라 그 정산이 뜨지도 못하고 지워진다.
    @State private var noticeSessionSeq = 0

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: timer.phase == .rest ? "cup.and.saucer.fill" : "timer")
                    .font(.callout.weight(.bold))
                Spacer()
                Toggle(companion.l.t("방해금지", "Do Not Disturb", "おやすみ"), isOn: $settings.doNotDisturb)
                    .toggleStyle(.checkbox).font(.caption2)
            }
            if timer.isRunning, timer.endsAt != nil {
                TimelineView(PeriodicTimelineSchedule(from: Date.now, by: 1)) { context in
                    HStack {
                        Text(timer.clockText(at: context.date))
                            .font(.system(.title2, design: .monospaced).weight(.semibold))
                        Spacer()
                        Text(timer.phase == .focus ? focusHint : restHint)
                            .font(.caption2).foregroundStyle(.secondary)
                        Button(companion.l.t("종료", "Stop", "終了")) {
                            timer.stopFocusSession(companion: companion)
                        }
                            .controlSize(.small)
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "map.fill").foregroundStyle(.green)
                    Text(adventureText(timer.focusMinutes)).font(.caption2)
                    Spacer()
                    Text(rewardText(timer.focusMinutes))
                        .font(.caption2).foregroundStyle(.orange)
                }
            } else if let adventure = companion.activeAdventure {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(companion.l.t("진행 중인 모험", "Active adventure", "進行中の冒険"),
                                  systemImage: "map.fill")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            if adventure.isComplete(at: context.date) {
                                // 결과는 버리지만 사라지지 않는다 — `claimAdventure()` 가 스토어에
                                // 배너를 남기고, 위 `adoptClaimIfNeeded` 가 그걸 건네받는다. 예전엔
                                // 여기서 `_ =` 로 버린 게 곧 "지급을 아무도 설명하지 않음" 이었다.
                                Button(companion.l.t("보상 받기", "Claim", "受け取る")) {
                                    companion.claimAdventure()
                                }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                            } else {
                                Text(adventure.endsAt, style: .timer)
                                    .font(.caption.monospacedDigit())
                            }
                        }
                        ProgressView(value: adventure.progress(at: context.date)).tint(.green)
                        Text(adventure.isComplete(at: context.date)
                             ? companion.l.t("완료된 모험의 보상을 받아야 다음 집중을 시작할 수 있어요.",
                                     "Claim this reward before starting another focus session.",
                                     "この報酬を受け取ってから次の集中を始められます。")
                             : companion.l.t("앱을 다시 열어도 모험은 계속 진행됩니다.",
                                     "The adventure continues after reopening the app.",
                                     "アプリを開き直しても冒険は続きます。"))
                            .font(.caption2).foregroundStyle(.secondary)
                        if !adventure.isComplete(at: context.date) {
                            Button(companion.l.t("모험 취소", "Cancel adventure", "冒険をやめる")) {
                                companion.cancelFocusAdventure()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            } else {
                Picker("", selection: $selectedMinutes) {
                    // 대화의 `pokedoro.start` 도 같은 목록으로 인자를 접는다 — 두 벌이면 화면이
                    // 제시하지 않는 길이를 도구만 켤 수 있게 된다.
                    ForEach(PokemonChatTool.focusMinutes, id: \.self) { Text("\($0)m").tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                HStack {
                    Button(companion.l.t("모험 보내고 집중 시작", "Send on adventure & focus", "冒険に送って集中開始")) {
                        timer.startFocusSession(minutes: selectedMinutes, companion: companion)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    // 진행 중일 때만 막는다. 끝난 모험은 시작 시 자동 정산되므로 여기서 잠그면
                    // 정산 전 상태에서 버튼이 영영 비활성이 된다(#8).
                    .disabled(!companion.hasActive || companion.isAdventureInProgress)
                    Spacer()
                    Text(rewardText(selectedMinutes))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Text(eggChanceText(selectedMinutes)).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(companion.l.focusStash(eggs: companion.focusEggCount,
                                                fragments: companion.eggFragmentCount,
                                                weekly: companion.weeklyAdventureProgress))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            // 오늘의 집계도 세 분기 **밖**이다 — 집중 중이든 쉬는 중이든 "오늘 얼마나 했나"는
            // 같은 자리에 있어야 한다. 값은 원장에서 온다(재기동·자정을 넘긴다).
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                // 목표를 함께 적는다 — 완료 수만 있으면 "3세션" 이 많은지 적은지 알 수 없다.
                // 체인은 이 목표에서 멈춘다(`FocusChainRules.afterRest`).
                Text(companion.l.t("오늘 \(companion.focusSessionsToday)/\(settings.dailyFocusGoal)세션 · \(companion.focusMinutesToday)분",
                                   "Today \(companion.focusSessionsToday)/\(settings.dailyFocusGoal) sessions · \(companion.focusMinutesToday) min",
                                   "今日 \(companion.focusSessionsToday)/\(settings.dailyFocusGoal)セッション・\(companion.focusMinutesToday)分"))
                Spacer()
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            // 정산 배너는 세 분기 **밖**에 둔다. 예전엔 idle 분기 안에 있어서, 집중이 끝나는 순간
            // 타이머가 곧바로 휴식으로 넘어가(`FocusTimer.tick` → `startRest`) `isRunning` 이 참이
            // 되면 방금 정산한 결과가 화면에 뜨지도 못했다.
            if let claim = claimBanner, noticeIsCurrent {
                // 줄 조립은 `AdventureReward.bannerLines` 가 한다 — 여기서 `if` 로 다시 세면
                // 지급 경로가 늘 때 이 화면만 빠지고, 그걸 걸러 줄 테스트가 생길 자리가 없다.
                let lines = claim.bannerLines
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        claimLine(line, isFirst: index == 0)
                    }
                }
            } else if sessionDone, noticeIsCurrent {
                // 정산할 게 없는 세션 완료(대화 칩으로 먼저 받은 뒤 tick 이 오는 경우)도 끝났다는
                // 말은 남긴다 — 예전 `timer.lastReward` 가 하던 최소한의 일이다.
                Text(companion.l.t("집중 세션 완료!", "Focus session complete!", "集中セッション完了！"))
                    .font(.caption.weight(.semibold)).foregroundStyle(.green)
            }
            if companion.focusEggCount > 0, let readyAt = companion.nextStoredEggHatchAt {
                // `Text(readyAt, style: .timer)` 를 쓰면 예정 시각을 지난 뒤 SwiftUI 가 경과
                // 시간을 세어 올려 카운트다운이 0 에서 다시 증가한다(#86). 부화 트리거는 60초
                // 방치 틱이고 종 추첨엔 네트워크가 필요해 그 구간은 항상 생긴다 — 남은 시간을
                // 직접 계산해 0 에서 멈추고, 그 뒤엔 "곧 부화" 로 바꾼다.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Text(companion.l.eggAutoHatchLabel)
                        Spacer()
                        switch StoredEggCountdown.resolve(readyAt: readyAt, now: context.date) {
                        case .counting(let clock):
                            Text(clock).monospacedDigit()
                        case .due:
                            Text(companion.l.eggHatchingSoon)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                }
            }
        }
        .padding(11)
        .pokedoroCard(tint: timer.phase == .focus ? PokedoroTheme.red : PokedoroTheme.blue,
                      emphasized: timer.isRunning)
        // 기동 직후 자동 정산된 모험(`CompanionStore.init` 의 복구 경로)도 여기서 잡힌다 —
        // 그 정산은 버튼도 세션 완료도 거치지 않아 onChange 만으로는 못 본다.
        .onAppear { adoptClaimIfNeeded() }
        .onChange(of: companion.claimFeedbackSeq) { adoptClaimIfNeeded() }
        .onChange(of: timer.completedSessions) { noteSessionCompleted() }
    }

    /// 스토어가 들고 있는 마지막 정산을 한 번만 건네받는다. 사탕 피드백과 같은 seq + consume 형태다.
    ///
    /// **비어 있는 정산도 건네받는다.** 세이브를 불러오면 스토어가 `lastClaim` 을 비우고 seq 를
    /// 올리는데, 그때 nil 을 안 받으면 이미 화면에 떠 있는 **남의 세이브 정산액**이 그대로 남는다 —
    /// 스토어만 비우는 것으로는 뷰가 건네받아 들고 있는 사본에 닿지 못한다.
    private func adoptClaimIfNeeded() {
        guard companion.claimFeedbackSeq != seenClaimSeq else { return }
        seenClaimSeq = companion.claimFeedbackSeq
        claimBanner = companion.lastClaim
        guard claimBanner != nil else { return }
        companion.consumeClaimFeedback()
        noticeSessionSeq = timer.sessionStartSeq
        sessionDone = false   // 정산이 이긴다 — 두 줄을 함께 띄우면 같은 사건을 두 번 말한다.
    }

    /// 정산할 게 없는 세션 완료(대화 칩으로 먼저 받은 뒤 tick 이 오는 경우)도 끝났다는 말은 남긴다.
    /// **순서에 기대지 않는다** — 정산이 먼저 들어왔으면 여기서 빠지고, 이쪽이 먼저면 뒤이은
    /// `adoptClaimIfNeeded` 가 `sessionDone` 을 내린다.
    private func noteSessionCompleted() {
        guard claimBanner == nil else { return }
        sessionDone = true
        noticeSessionSeq = timer.sessionStartSeq
    }

    /// 지금 떠 있는 안내가 **이번 세션의 것**인가. 다음 집중이 시작되면 어긋나 안내가 내려간다.
    private var noticeIsCurrent: Bool { noticeSessionSeq == timer.sessionStartSeq }

    @ViewBuilder
    private func claimLine(_ line: ClaimBannerLine, isFirst: Bool) -> some View {
        switch line {
        case .eggs(let count):
            Text(count > 1
                 ? companion.l.t("🎉 신비한 알 \(count)개 발견!",
                                 "🎉 \(count) Mystery Eggs found!",
                                 "🎉 ふしぎなタマゴ\(count)個発見！")
                 : companion.l.t("🎉 신비한 알 발견!", "🎉 Mystery Egg found!", "🎉 ふしぎなタマゴ発見！"))
                .font(.caption.weight(.semibold)).foregroundStyle(.purple)
        case .settled(let stardust):
            // 첫 줄일 때만 강조한다 — 알 줄이 위에 오면 그쪽이 머리글이라 둘 다 굵으면 서로 밀린다.
            Text(companion.l.claimSettled(stardust))
                .font(isFirst ? .caption.weight(.semibold) : .caption2)
                .foregroundStyle(isFirst ? Color.green : Color.secondary)
        case .overflowConverted(let stardust):
            Text(companion.l.claimOverflowConverted(stardust))
                .font(.caption2).foregroundStyle(.orange)
        case .rareCandy:
            Text(companion.l.t("🍬 \(companion.l.itemName(.rareCandy)) 1개 발견!",
                               "🍬 Found a \(companion.l.itemName(.rareCandy))!",
                               "🍬 \(companion.l.itemName(.rareCandy))を1個発見！"))
                .font(.caption2).foregroundStyle(.pink)
        }
    }

    private var title: String {
        switch timer.phase {
        case .focus: companion.l.t("집중 중", "Focus session", "集中中")
        // 긴 휴식은 다르게 말한다 — 15분을 쉬는데 "휴식 중" 이면 타이머가 고장 난 것처럼 보인다.
        // 판정은 휴식 길이를 정한 것과 **같은 파생**이다(`FocusChainRules.isLongRest`).
        case .rest: FocusChainRules.isLongRest(completedToday: companion.focusSessionsToday)
            ? companion.l.t("긴 휴식 중", "Long break", "長い休憩中")
            : companion.l.t("휴식 중", "Break", "休憩中")
        case .idle: companion.l.t("집중 타이머", "Focus timer", "集中タイマー")
        }
    }
    private var focusHint: String { companion.l.t("완료 시 파트너 보상", "Partner reward on completion", "完了でパートナーに報酬") }
    private var restHint: String { companion.l.t("잠깐 쉬어가세요", "Take a short break", "少し休みましょう") }
    private func adventureText(_ minutes: Int) -> String {
        companion.l.t("파트너가 \(minutes)분 모험 중 · 완료해야 보상",
                      "Partner exploring for \(minutes)m · finish to claim",
                      "パートナーが\(minutes)分の冒険中 · 完了で報酬")
    }
    private func eggChanceText(_ minutes: Int) -> String {
        let chance = Double(FocusRewardRules.eggChanceBasisPoints(minutes: minutes)) / 100
        return companion.l.t("신비한 알 확률 \(chance.formatted())%", "Mystery Egg chance \(chance.formatted())%", "ふしぎなタマゴ確率 \(chance.formatted())%")
    }
    private func rewardText(_ minutes: Int) -> String {
        let reward = AdventureRules.amounts(minutes: minutes)
        let fragments = minutes >= 90 ? 6 : (minutes >= 50 ? 3 : 1)
        return "+\(GameNumberFormatter.compact(reward.experience)) EXP · +\(GameNumberFormatter.compact(reward.starPieces)) ⭐ · +\(fragments) 🧩"
    }
}
