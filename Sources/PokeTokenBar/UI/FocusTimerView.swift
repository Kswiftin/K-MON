import SwiftUI

struct FocusTimerView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(AppSettings.self) private var settings
    @Environment(CompanionStore.self) private var companion
    @State private var selectedMinutes = 25

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
                                Button(companion.l.t("보상 받기", "Claim", "受け取る")) {
                                    _ = companion.claimAdventure()
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
                if let reward = timer.lastReward {
                    Text(reward.foundEgg
                         ? companion.l.t("🎉 신비한 알 발견!", "🎉 Mystery Egg found!", "🎉 ふしぎなタマゴ発見！")
                         : companion.l.t("집중 세션 완료", "Focus session complete", "集中セッション完了"))
                        .font(.caption.weight(.semibold)).foregroundStyle(reward.foundEgg ? .purple : .green)
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
