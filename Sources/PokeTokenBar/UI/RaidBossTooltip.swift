import SwiftUI

/// 보스에서 툴팁으로 이동할 시간을 주고, 이전 보스의 늦은 이탈은 무시한다.
@MainActor @Observable
final class RaidBossHoverState {
    private(set) var targetID: String?
    private var hideTask: Task<Void, Never>?

    func setHovered(_ id: String, isInside: Bool) {
        if isInside {
            hideTask?.cancel()
            targetID = id
        } else if targetID == id {
            hideTask?.cancel()
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, targetID == id else { return }
                targetID = nil
            }
        }
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        targetID = nil
    }
}

enum RaidBossTooltipLayout {
    static func frame(anchor: CGRect, container: CGSize, tooltip: CGSize) -> CGRect {
        let width = min(tooltip.width, max(0, container.width - 16))
        let height = min(tooltip.height, max(0, container.height - 16))
        let x = max(8, min(anchor.midX - width / 2, container.width - width - 8))
        let below = anchor.maxY + 6
        let y = below + height <= container.height - 8 ? below : anchor.minY - height - 6
        return CGRect(x: x, y: max(8, min(y, container.height - height - 8)),
                      width: width, height: height)
    }
}

struct RaidBossTooltipTarget {
    let speciesID: Int
    let tier: RaidTier
    var side: BattleSide? = nil
    var maxHP: Int? = nil
    var id: String { "\(side == nil ? "preview" : "battle")-\(tier.rawValue)-\(speciesID)" }
}

private struct RaidBossHoverKey: EnvironmentKey {
    static let defaultValue: RaidBossHoverState? = nil
}

extension EnvironmentValues {
    var raidBossHover: RaidBossHoverState? {
        get { self[RaidBossHoverKey.self] }
        set { self[RaidBossHoverKey.self] = newValue }
    }
}

private struct RaidBossTooltipAnchor {
    let target: RaidBossTooltipTarget
    let bounds: Anchor<CGRect>
}

private struct RaidBossTooltipPreference: PreferenceKey {
    static let defaultValue: [RaidBossTooltipAnchor] = []
    static func reduce(value: inout [RaidBossTooltipAnchor],
                       nextValue: () -> [RaidBossTooltipAnchor]) {
        value += nextValue()
    }
}

private struct RaidBossTooltipTrigger: ViewModifier {
    let target: RaidBossTooltipTarget
    @Environment(\.raidBossHover) private var hover

    func body(content: Content) -> some View {
        let isHovered = hover?.targetID == target.id
        return content
            .contentShape(Rectangle())
            .onHover { hover?.setHovered(target.id, isInside: $0) }
            .anchorPreference(key: RaidBossTooltipPreference.self, value: .bounds) {
                isHovered ? [.init(target: target, bounds: $0)] : []
            }
            .accessibilityHint("커서를 올리면 보스 정보와 타입 상성을 볼 수 있어요.")
    }
}

extension View {
    func raidBossTooltip(_ target: RaidBossTooltipTarget) -> some View {
        modifier(RaidBossTooltipTrigger(target: target))
    }
}

/// ScrollView 밖의 한 겹에 그려 네 모서리와 스크롤 클리핑을 피한다.
struct RaidBossTooltipHost: ViewModifier {
    let store: CompanionStore
    let contextID: String
    @State private var hover = RaidBossHoverState()

    func body(content: Content) -> some View {
        let targetID = hover.targetID
        return content
            .environment(\.raidBossHover, hover)
            .overlayPreferenceValue(RaidBossTooltipPreference.self) { anchors in
                GeometryReader { geometry in
                    if let item = anchors.first(where: { $0.target.id == targetID }) {
                        let anchor = geometry[item.bounds]
                        let rect = RaidBossTooltipLayout.frame(anchor: anchor,
                            container: geometry.size, tooltip: CGSize(width: 300, height: 320))
                        if anchor.intersects(CGRect(origin: .zero, size: geometry.size)) {
                            RaidBossTooltipPanel(target: item.target, store: store)
                                .id(item.target.id)
                                .frame(width: rect.width, height: rect.height)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.primary.opacity(0.15)))
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                                .contentShape(Rectangle())
                                .onHover { hover.setHovered(item.target.id, isInside: $0) }
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
            }
            .onChange(of: contextID) { hover.dismiss() }
            .onDisappear { hover.dismiss() }
    }
}

private struct RaidBossTooltipPanel: View {
    let target: RaidBossTooltipTarget
    let store: CompanionStore
    @State private var previewInfo: RaidBossInfo?
    @State private var failed = false
    @State private var retry = 0
    @State private var abilityName: String?

    private var info: RaidBossInfo? {
        if let side = target.side {
            return RaidBossInfo(side: side, maxHP: target.maxHP ?? target.tier.bossHP)
        }
        return previewInfo
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(info?.name ?? "#\(target.speciesID)").font(.headline)
                    Spacer(minLength: 4)
                    Text("\(target.tier.rawValue)★ 보스").font(.caption.bold())
                }
                Text("레벨 \(info?.level ?? target.tier.bossLevel) · 최대 HP \(info?.maxHP ?? target.tier.bossHP)")
                    .font(.caption)
                Text("승리 후 포획 확률 \(RaidBoss.catchPercent(tier: target.tier, speciesID: target.speciesID))%")
                    .font(.caption).foregroundStyle(.purple)
                if let info {
                    HStack(spacing: 4) {
                        ForEach(info.types, id: \.self) { TypeBadge(type: $0) }
                    }
                    if info.abilitySlug != nil {
                        Text("특성 · \(abilityName ?? "불러오는 중…")").font(.caption)
                    } else {
                        Text("특성 정보 없음").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("보스에게 사용하는 공격 타입별 상성").font(.caption.bold())
                    ForEach(info.groups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.label).font(.caption.bold())
                                .foregroundStyle(group.multiplier > 1 ? .orange : .secondary)
                            Text(group.types.map(\.name).joined(separator: " · "))
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("타입 기준입니다. 특성·기술에 따라 실제 효과가 달라질 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if failed {
                    Text("보스 정보를 불러오지 못했어요.").font(.caption)
                    Button("다시 시도") { retry += 1 }.controlSize(.small)
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("보스 정보를 불러오는 중…").font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .task(id: retry) { await loadPreview() }
        .task(id: info?.abilitySlug) {
            abilityName = nil
            guard let slug = info?.abilitySlug else { return }
            let name = await PokeAPIClient.shared.localizedAbilityName(slug: slug)
            guard !Task.isCancelled else { return }
            abilityName = name
        }
    }

    private func loadPreview() async {
        guard target.side == nil else { return }
        failed = false
        do {
            let profile = try await PokeAPIClient.shared.battleProfile(speciesID: target.speciesID)
            let name = await store.resolveSpeciesName(target.speciesID)
            guard !Task.isCancelled else { return }
            previewInfo = RaidBossInfo(speciesID: target.speciesID, name: name,
                                      profile: profile, tier: target.tier)
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
    }
}
