import SwiftUI

struct CareCardView: View {
    let store: CompanionStore
    private var l: L { store.l }
    private var care: PetCareState { store.care }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l.t("돌봄", "Care", "お世話"), systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                Spacer()
                if care.isSick { Text(l.t("아픔", "Sick", "病気" )).font(.caption2).foregroundStyle(.red) }
            }
            HStack(spacing: 8) {
                gauge("🍎", care.hunger)
                gauge("😊", care.happiness)
                gauge("⚡", care.energy)
                gauge("🫧", care.hygiene)
            }
            HStack(spacing: 5) {
                action("🍎", l.t("먹이", "Feed", "食べる")) { store.feedCompanion() }
                action("🎾", l.t("놀기", "Play", "遊ぶ")) { store.playWithCompanion() }
                action("🛏️", l.t("쉬기", "Rest", "休む")) { store.restCompanion() }
                action("🫧", l.t("청소", "Clean", "掃除")) { store.cleanCompanion() }
                action("💊", l.t("약", "Medicine", "薬")) { _ = store.medicateCompanion() }
                    .disabled(!store.canPerformCare || !care.isSick)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .task { store.resumeCareClock() }
    }

    private func gauge(_ icon: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(icon).font(.caption)
            ProgressView(value: value, total: 100).tint(value <= 30 ? .red : .accentColor)
            Text("\(Int(value))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func action(_ icon: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { VStack(spacing: 2) { Text(icon); Text(title).font(.caption2) } }
            .buttonStyle(.bordered).controlSize(.mini)
            .disabled(!store.canPerformCare)
    }
}
