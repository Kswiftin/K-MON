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
                    .font(.callout.weight(.semibold))
                Spacer()
                Toggle(companion.language == .ko ? "방해금지" : "Do Not Disturb", isOn: $settings.doNotDisturb)
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
                        Button(companion.language == .ko ? "종료" : "Stop") { timer.stop() }
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
            } else {
                Picker("", selection: $selectedMinutes) {
                    Text("25m").tag(25)
                    Text("50m").tag(50)
                    Text("90m").tag(90)
                }
                .pickerStyle(.segmented).labelsHidden()
                HStack {
                    Button(companion.language == .ko ? "모험 보내고 집중 시작" : "Send on adventure & focus") {
                        if companion.startFocusAdventure(minutes: selectedMinutes) {
                            timer.startFocus(minutes: selectedMinutes)
                        }
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
                         ? (companion.language == .ko ? "🎉 신비한 알 발견!" : "🎉 Mystery Egg found!")
                         : (companion.language == .ko ? "집중 세션 완료" : "Focus session complete"))
                        .font(.caption.weight(.semibold)).foregroundStyle(reward.foundEgg ? .purple : .green)
                }
                if companion.focusEggCount > 0, companion.hasActive {
                    Button(companion.language == .ko ? "🥚 알 부화 시작" : "🥚 Incubate Egg") {
                        _ = companion.beginIncubatingFocusEgg()
                    }
                    .controlSize(.small)
                    .help(companion.language == .ko
                          ? "현재 동행은 박스에 안전하게 보관됩니다."
                          : "Your current companion will be stored safely in the Box.")
                }
            }
        }
        .padding(9)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var title: String {
        switch (companion.language, timer.phase) {
        case (.ko, .focus): "집중 중"
        case (.ko, .rest): "휴식 중"
        case (.ko, .idle): "집중 타이머"
        case (_, .focus): "Focus session"
        case (_, .rest): "Break"
        default: "Focus timer"
        }
    }
    private var focusHint: String { companion.language == .ko ? "완료 시 파트너 보상" : "Partner reward on completion" }
    private var restHint: String { companion.language == .ko ? "잠깐 쉬어가세요" : "Take a short break" }
    private func adventureText(_ minutes: Int) -> String {
        if companion.language == .ko { return "파트너가 \(minutes)분 모험 중 · 완료해야 보상" }
        return "Partner exploring for \(minutes)m · finish to claim"
    }
    private func eggChanceText(_ minutes: Int) -> String {
        let chance = Double(FocusRewardRules.eggChanceBasisPoints(minutes: minutes)) / 100
        return companion.language == .ko ? "신비한 알 확률 \(chance.formatted())%" : "Mystery Egg chance \(chance.formatted())%"
    }
    private func rewardText(_ minutes: Int) -> String {
        let reward = AdventureRules.amounts(minutes: minutes)
        let fragments = minutes >= 90 ? 6 : (minutes >= 50 ? 3 : 1)
        return "+\(GameNumberFormatter.compact(reward.experience)) EXP · +\(GameNumberFormatter.compact(reward.starPieces)) ⭐ · +\(fragments) 🧩"
    }
}
