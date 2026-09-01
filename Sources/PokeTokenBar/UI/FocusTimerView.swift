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
            // 정산 배너는 세 분기 **밖**에 둔다. 예전엔 idle 분기 안에 있어서, 집중이 끝나는 순간
            // 타이머가 곧바로 휴식으로 넘어가(`FocusTimer.tick` → `startRest`) `isRunning` 이 참이
            // 되면 방금 정산한 결과가 화면에 뜨지도 못했다.
            if let claim = claimBanner {
                VStack(alignment: .leading, spacing: 2) {
                    if claim.bonusEggs > 0 {
                        Text(companion.l.t("🎉 신비한 알 발견!", "🎉 Mystery Egg found!", "🎉 ふしぎなタマゴ発見！"))
                            .font(.caption.weight(.semibold)).foregroundStyle(.purple)
                    }
                    Text(companion.l.claimSettled(claim.totalStardust))
                        .font(claim.bonusEggs > 0 ? .caption2 : .caption.weight(.semibold))
                        .foregroundStyle(claim.bonusEggs > 0 ? Color.secondary : Color.green)
                    // 만렙에 걸린 경험치가 되돌아온 몫(#82). 알림을 끈 사용자에게는 이 줄이 지갑
                    // 증가분을 설명하는 유일한 자리다(#192).
                    if claim.overflowBonus > 0 {
                        Text(companion.l.claimOverflowConverted(claim.overflowBonus))
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
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
    }

    /// 스토어가 들고 있는 마지막 정산을 한 번만 건네받는다. 사탕 피드백과 같은 seq + consume 형태다.
    private func adoptClaimIfNeeded() {
        guard let claim = companion.lastClaim, companion.claimFeedbackSeq != seenClaimSeq else { return }
        seenClaimSeq = companion.claimFeedbackSeq
        claimBanner = claim
        companion.consumeClaimFeedback()
    }

    private var title: String {
        switch timer.phase {
        case .focus: companion.l.t("집중 중", "Focus session", "集中中")
        case .rest: companion.l.t("휴식 중", "Break", "休憩中")
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
