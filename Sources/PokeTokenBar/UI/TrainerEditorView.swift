import SwiftUI

struct TrainerEditorView: View {
    let store: CompanionStore
    let mode: TrainerEditorMode
    let onCancel: () -> Void
    let onSaved: () -> Void
    @State private var draft: TrainerEditDraft
    @State private var failed = false

    init(store: CompanionStore, mode: TrainerEditorMode, onCancel: @escaping () -> Void, onSaved: @escaping () -> Void) {
        self.store = store; self.mode = mode; self.onCancel = onCancel; self.onSaved = onSaved
        _draft = State(initialValue: store.trainerEditDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PokedoroOverlayHeader(title: store.l.outfitTitle, systemImage: "tshirt.fill",
                                  closeLabel: store.l.close, onClose: onCancel)
            ScrollView {
                TrainerEditorFields(store: store, mode: mode, draft: $draft).padding(.vertical, 4)
            }
            Divider()
            if let issue = store.trainerEditIssue(draft) {
                Text(issue.message).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if failed {
                Text("저장하지 못했어요. 다시 시도해 주세요.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("취소", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button("저장") {
                    if store.saveTrainer(draft) { failed = false; onSaved() } else { failed = true }
                }.buttonStyle(.borderedProminent).disabled(store.trainerEditIssue(draft) != nil)
            }
        }
        .onAppear { draft = store.trainerEditDraft; failed = false }
    }
}
