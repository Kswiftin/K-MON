import SwiftUI

/// 배틀프런티어 — 선택한 세 마리를 Lv.50으로 맞춰 연속 CPU 3대3에 도전한다.
struct BattleFrontierView: View {
    let store: CompanionStore
    @Environment(BattleCenter.self) private var center
    let onClose: () -> Void

    var body: some View {
        if center.isFrontierBattle, center.phase != .ready {
            BattleView(store: store)
                .padding(PopoverMetrics.padding)
                .frame(height: PopoverMetrics.currentHeight(for: .battle))
        } else {
            lobby
        }
    }

    private var lobby: some View {
        VStack(alignment: .leading, spacing: 10) {
            PokedoroOverlayHeader(title: "배틀프런티어", systemImage: "tower.fill",
                                  tint: .indigo, closeLabel: store.l.close, onClose: close)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label("최고 연승 \(store.state.frontierBestStreak)", systemImage: "trophy.fill")
                    Spacer()
                    Text("전원 Lv.50 · 3 vs 3")
                }
                .font(.caption.bold())
                Text("승리할수록 강한 트레이너가 등장합니다. 7연승마다 프런티어 브레인이 기다립니다.")
                    .font(.caption2).foregroundStyle(.secondary)
                if center.frontierStreak > 0 {
                    Text("이번 도전 \(center.frontierStreak)연승 · 획득 ⭐ \(center.frontierTotalReward.formatted())")
                        .font(.caption.bold()).foregroundStyle(.indigo)
                }
            }
            .padding(9).pokedoroCard()

            if let error = center.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }

            TeamPicker(store: store,
                       selection: Binding(get: { center.pickedTeam }, set: { center.pickedTeam = $0 }),
                       limit: BattleFrontier.teamSize,
                       title: "출전 순서")
            Spacer(minLength: 0)
            HStack {
                Text("\(center.pickedTeam.count) / \(BattleFrontier.teamSize)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button(center.frontierStreak > 0 ? "다음 배틀" : "도전 시작") {
                    center.startFrontierBattle(newRun: center.frontierStreak == 0)
                }
                .buttonStyle(.borderedProminent).tint(.indigo)
                .disabled(center.pickedTeam.count != BattleFrontier.teamSize || center.phase != .ready)
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
    }

    private func close() {
        center.endFrontierRun()
        onClose()
    }
}
