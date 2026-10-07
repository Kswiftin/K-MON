import SwiftUI

struct PokopiaResidentConversationSheet: View {
    let store: CompanionStore
    let selection: PokopiaConversationSelection
    @Environment(\.dismiss) private var dismiss
    @State private var crafting = false
    @State private var feedback: String?

    private var content: PokopiaConversationContent {
        PokopiaCommunityPresentation.conversation(selection: selection, state: store.state.pokopiaCommunity,
            context: store.pokopiaCommunityContext(), season: .current(), timeOfDay: .current())
    }

    var body: some View {
        let content = content
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("주민과 이야기").font(.title3.weight(.semibold))
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let resident = content.resident, let dialogue = content.dialogue {
                        HStack(spacing: 12) {
                            PokopiaResidentView(speciesID: resident.speciesID, isShiny: false, side: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(resident.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                                Text("\(selection.region.name) · \(content.friendship.name)")
                                    .font(.caption).foregroundStyle(.secondary)
                                let points = store.state.pokopiaCommunity.friendships[
                                    PokopiaCommunity.friendshipKey(region: selection.region, speciesID: selection.speciesID), default: 0]
                                Text("친밀도 \(points)/10").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Text(dialogue.greeting).font(.callout)
                        Text(dialogue.story).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Divider()
                        if let line = dialogue.requestLine { Text(line).font(.callout) }
                        if let request = content.request, let status = content.status {
                            requestSection(request, status: status)
                        }
                    } else {
                        Label("이 주민은 마을을 떠났어요.", systemImage: "person.crop.circle.badge.questionmark")
                        Text("닫고 현재 마을의 이웃을 다시 만나 보세요.").font(.callout).foregroundStyle(.secondary)
                    }
                    if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20).frame(width: 500, height: 440)
        .background(PokedoroTheme.pageBackground).fontDesign(.rounded)
        .sheet(isPresented: $crafting) { PokopiaCraftSheet(store: store) }
        .onAppear { store.refreshPokopiaCommunity() }
    }

    private func requestSection(_ request: PokopiaResidentRequest, status: PokopiaRequestStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PokopiaCommunityPresentation.title(request)).font(.callout.weight(.semibold))
            Text(PokopiaCommunityPresentation.statusText(status)).font(.caption).foregroundStyle(.secondary)
            Text("선물 · \(store.l.itemName(request.reward)) 1개").font(.caption)
            if status == .ready {
                Button("선물 받기") {
                    if let reward = store.claimPokopiaRequest(id: request.id) {
                        feedback = "\(store.l.itemName(reward.item)) 1개를 받았어요."
                            + (store.saveFailed ? " 저장을 다시 시도해 주세요." : "")
                    } else { feedback = "부탁의 현재 상태와 재료 보관 수량을 다시 확인해 주세요." }
                }.buttonStyle(.borderedProminent)
            } else if case .inProgress = status {
                switch request.kind {
                case .focus:
                    Text("부탁을 받은 뒤 완료한 집중 세션을 합쳐 20분을 채워 주세요.")
                        .font(.caption).foregroundStyle(.secondary)
                case .habitat:
                    Button("지도로 돌아가 정비하기") {
                        store.memoryAlbum.selectRegion(selection.region)
                        store.refreshPokopiaCommunity()
                        dismiss()
                    }.buttonStyle(.bordered)
                case .meal:
                    Button("요리 만들기와 나누기") {
                        store.memoryAlbum.selectRegion(selection.region)
                        store.refreshPokopiaCommunity()
                        crafting = true
                    }.buttonStyle(.bordered)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(PokedoroTheme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
