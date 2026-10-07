import SwiftUI

struct PokopiaCommunityCards: View {
    let store: CompanionStore
    let onConversation: (PokopiaConversationSelection) -> Void
    @State private var feedback: String?
    @State private var showsMilestones = false

    var body: some View {
        let state = store.state.pokopiaCommunity
        let context = store.pokopiaCommunityContext()
        let region = store.memoryAlbum.region
        let cards = PokopiaCommunityPresentation.cards(state: state, context: context, region: region)
        VStack(alignment: .leading, spacing: 10) {
            Label("오늘의 부탁", systemImage: "bubble.left.and.bubble.right")
                .font(.callout.weight(.semibold))
            Text("다섯 마을 합계 하루 최대 3개 · 수령 \(state.daily?.claimedCount ?? 0)/3")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if state.needsRecovery || state.daily?.isBlocked == true {
                Text("부탁 기록을 복구하는 중이에요. 오늘은 쉬고 다음 날 다시 만나요.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let daily = state.daily, daily.dayKey > context.dayKey {
                Text("저장된 날짜가 현재보다 앞서 있어요. 날짜가 맞을 때 부탁을 이어갈 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if cards.isEmpty {
                Text(state.daily?.requests.isEmpty != false
                     ? "오늘은 부탁이 없어요. 주민과 이야기하고 내일 다시 확인해 보세요."
                     : "이 마을에는 오늘 부탁이 없어요. 다른 마을의 이웃을 만나 보세요.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(cards) { card in requestCard(card, state: state) }
            let otherRegions = TownRegion.allCases.filter { candidate in
                candidate != region && state.daily?.requests.contains(where: { $0.region == candidate }) == true
            }
            if !otherRegions.isEmpty {
                Text("다른 마을의 부탁").font(.caption2).foregroundStyle(.secondary)
                ForEach(otherRegions, id: \.rawValue) { other in
                    Button("\(other.name) 마을로 이동") {
                        store.memoryAlbum.selectRegion(other)
                        store.refreshPokopiaCommunity()
                    }
                    .font(.caption).buttonStyle(.bordered).controlSize(.small)
                }
            }
            if let feedback {
                Text(feedback).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            DisclosureGroup(isExpanded: $showsMilestones) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("함께 마친 부탁 \(state.totalCompleted)회")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(PokopiaMilestone.allCases, id: \.rawValue) { milestone in
                        Label(PokopiaCommunityPresentation.milestoneName(milestone),
                              systemImage: state.milestones.contains(milestone) ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(state.milestones.contains(milestone) ? PokedoroTheme.blue : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.top, 6)
            } label: {
                Text("마을 성장 기록 \(state.milestones.count)/6").font(.caption.weight(.medium))
            }
        }
        .padding(12)
        .background(PokedoroTheme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: region) { _, _ in feedback = nil }
    }

    private func requestCard(_ card: PokopiaRequestCard, state: PokopiaCommunityState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.residentName).font(.caption.weight(.semibold))
                .lineLimit(2).help(card.residentName)
            Text(card.title).font(.caption)
            Text(PokopiaCommunityPresentation.statusText(card.status))
                .font(.caption2).foregroundStyle(.secondary)
            Text("선물 · \(store.l.itemName(card.reward)) 1개")
                .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let request = state.daily?.requests.first(where: { $0.id == card.id }), card.status != .residentLeft {
                    Button("대화하기") {
                        onConversation(.init(region: request.region, speciesID: request.speciesID, arrivedAt: request.arrivedAt))
                    }
                    .disabled(card.status == .expired || card.status == .blocked)
                    .accessibilityLabel("\(card.residentName) 주민과 대화하기")
                }
                if card.status == .ready {
                    Button("선물 받기") {
                        if let reward = store.claimPokopiaRequest(id: card.id) {
                            feedback = "\(store.l.itemName(reward.item)) 1개를 받았어요."
                                + (store.saveFailed ? " 저장을 다시 시도해 주세요." : "")
                        } else {
                            feedback = "부탁의 현재 상태와 재료 보관 수량을 다시 확인해 주세요."
                        }
                    }
                    .accessibilityLabel("\(card.residentName) 부탁 선물 받기")
                }
            }
            .font(.caption).buttonStyle(.bordered).controlSize(.small)
        }
        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }
}
