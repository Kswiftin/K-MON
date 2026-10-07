import SwiftUI

/// 기존 꾸미기 진입점은 저장·취소가 있는 초안 편집기를 연다.
struct OutfitView: View {
    let store: CompanionStore
    let onClose: () -> Void
    var body: some View {
        TrainerEditorView(store: store, mode: .editing, onCancel: onClose, onSaved: onClose)
            .padding(PopoverMetrics.padding)
            .frame(height: PopoverMetrics.currentHeight(for: .battle))
    }
}
