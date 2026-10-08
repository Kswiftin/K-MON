import SwiftUI

struct TrainerCreationProgress {
    private(set) var isComplete: Bool
    init(hasTrainerName: Bool) { isComplete = hasTrainerName }
    mutating func complete(ifSaved saved: Bool) { if saved { isComplete = true } }
}

struct TrainerCreationView: View {
    let store: CompanionStore
    let onSaved: () -> Void
    @State private var draft = TrainerEditDraft(name: "", outfit: TrainerOutfit(appearance: .creationDefault))
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrainerEditorFields(store: store, mode: .creation, draft: $draft)
            if failed {
                Text("저장하지 못했어요. 다시 시도해 주세요.").font(.caption).foregroundStyle(.red)
            }
            Button("트레이너 만들기") {
                if store.saveTrainer(draft) { failed = false; onSaved() } else { failed = true }
            }.buttonStyle(.borderedProminent)
                .disabled(store.trainerEditIssue(draft) != nil)
        }
    }
}
