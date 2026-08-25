import SwiftUI

struct FocusTimerView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(AppSettings.self) private var settings
    @Environment(CompanionStore.self) private var companion
    @State private var selectedPreset = FocusPreset.classic

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: timer.phase == .rest ? "cup.and.saucer.fill" : "timer")
                    .font(.callout.weight(.semibold))
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
                // 세그먼트 라벨은 분 숫자만 쓴다 — 팝오버 콘텐츠 폭이 332pt 라(`PopoverMetrics`)
                // 다섯 칸에 이름까지 넣으면 en·ja 에서 압축된다. 이름과 휴식은 아래 캡션에 둔다.
                // 대화의 `pokedoro.start` 도 `FocusPreset` 같은 목록으로 인자를 접는다 — 두 벌이면
                // 화면이 제시하지 않는 길이를 도구만 켤 수 있게 된다.
                Picker("", selection: $selectedPreset) {
                    ForEach(FocusPreset.allCases) { Text("\($0.minutes)m").tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Text(presetCaption(selectedPreset)).font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button(companion.l.t("모험 보내고 집중 시작", "Send on adventure & focus", "冒険に送って集中開始")) {
                        timer.startFocusSession(minutes: selectedPreset.minutes, companion: companion)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    // 진행 중일 때만 막는다. 끝난 모험은 시작 시 자동 정산되므로 여기서 잠그면
                    // 정산 전 상태에서 버튼이 영영 비활성이 된다(#8).
                    .disabled(!companion.hasActive || companion.isAdventureInProgress)
                    Spacer()
                    Text(rewardText(selectedPreset.minutes))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Text(eggChanceText(selectedPreset.minutes)).font(.caption2).foregroundStyle(.secondary)
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
        .padding(9)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var title: String {
        switch timer.phase {
        case .focus: companion.l.t("집중 중", "Focus session", "集中中")
        case .rest: companion.l.t("휴식 중", "Break", "休憩中")
        case .idle: companion.l.t("집중 타이머", "Focus timer", "集中タイマー")
        }
    }
    /// 프리셋 이름 + 집중/휴식 분. 이름은 이 화면에서만 쓰므로 `L` 프로퍼티로 올리지 않는다.
    private func presetCaption(_ preset: FocusPreset) -> String {
        let l = companion.l
        let name = switch preset {
        case .warmup: l.t("워밍업", "Warm-up", "ウォームアップ")
        case .sprint: l.t("스프린트", "Sprint", "スプリント")
        case .classic: l.t("클래식", "Classic", "クラシック")
        case .deep: l.t("딥워크", "Deep work", "ディープワーク")
        case .longDeep: l.t("롱 딥워크", "Long deep work", "ロングディープ")
        }
        return l.t("\(name) · 집중 \(preset.minutes)분 · 휴식 \(preset.restMinutes)분",
                   "\(name) · \(preset.minutes)m focus · \(preset.restMinutes)m break",
                   "\(name) · 集中\(preset.minutes)分 · 休憩\(preset.restMinutes)分")
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
        let fragments = FocusRewardRules.eggFragments(minutes: minutes)
        return "+\(GameNumberFormatter.compact(reward.experience)) EXP · +\(GameNumberFormatter.compact(reward.starPieces)) ⭐ · +\(fragments) 🧩"
    }
}
