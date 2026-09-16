import SwiftUI

/// 마을에서 무엇을 만들지 고르는 시트(9단계).
///
/// **판정은 스토어가 한다**(`CompanionStore.canStartTownCraft`) — 여기서 재고를 다시 세면 버튼은
/// 살아 있는데 눌러도 아무 일이 없는 상태가 생긴다(`PokopiaTransformSheet` 가 후보 집합을 스토어
/// 한 곳에서 받는 이유와 같다).
///
/// 레시피 묶음 순서는 `PokopiaCrafting.recipes` **선언 순서**에서 온다. 딕셔너리로 묶으면 그룹
/// 순서가 실행마다 바뀐다(`PokopiaTown.immigrant` 이 후보를 정렬하는 이유와 같은 부류다).
struct PokopiaCraftSheet: View {
    let store: CompanionStore
    @Environment(\.dismiss) private var dismiss

    /// 설비 묶음 하나 — `nil` 이면 맨손이다.
    private struct Group: Identifiable {
        let facility: ItemKind?
        let recipes: [PokopiaCrafting.Recipe]
        var id: String { facility?.rawValue ?? "" }
    }

    /// 선언 순서를 지키며 설비별로 묶는다. 처음 나온 설비가 그룹 순서를 정한다.
    private var groups: [Group] {
        var order: [ItemKind?] = []
        var buckets: [String: [PokopiaCrafting.Recipe]] = [:]
        for recipe in PokopiaCrafting.recipes {
            let key = recipe.facility?.rawValue ?? ""
            if buckets[key] == nil { order.append(recipe.facility) }
            buckets[key, default: []].append(recipe)
        }
        return order.map { Group(facility: $0, recipes: buckets[$0?.rawValue ?? ""] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            facilityShelf
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        groupSection(group)
                    }
                }
                .padding(.vertical, 2)
            }
            footer
        }
        .padding(16)
        .frame(width: 460, height: 520)
        .background(PokedoroTheme.pageBackground)
        .fontDesign(.rounded)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("무엇을 만들까요?").font(.headline)
            Text("재료는 상점에서 살 수 있어요. 요리를 마을에 먹이면 환경 레벨이 한 단 오를 수 있어요.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 가진 설비를 한 줄로 보여 준다 — **격자에 놓는 물건이 아니라는 것**이 이 줄의 뜻이다.
    private var facilityShelf: some View {
        HStack(spacing: 10) {
            ForEach(PokopiaCrafting.facilities, id: \.self) { facility in
                let owned = store.itemCount(facility) > 0
                HStack(spacing: 3) {
                    Image(systemName: owned ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(owned ? PokedoroTheme.blue : .secondary)
                    Text(store.l.itemName(facility))
                        .foregroundStyle(owned ? PokedoroTheme.ink : .secondary)
                }
                .font(.caption2)
            }
            Spacer()
        }
    }

    private func groupSection(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.facility.map { store.l.itemName($0) } ?? "맨손")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(group.recipes) { recipe in
                recipeRow(recipe)
            }
        }
    }

    private func recipeRow(_ recipe: PokopiaCrafting.Recipe) -> some View {
        let canStart = store.canStartTownCraft(recipe)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(recipe.output.fallbackEmoji)
                    Text(store.l.itemName(recipe.output)).font(.caption.weight(.medium))
                    if store.itemCount(recipe.output) > 0 {
                        Text("보유 \(store.itemCount(recipe.output))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Text(inputLine(recipe))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(durationText(recipe))
                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            Button("만들기") { store.startTownCraft(recipe) }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(!canStart)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// 재료 줄. **가진 수를 함께 적는다** — 모자란 것이 무엇인지 알아야 상점에서 무엇을 살지 정한다.
    private func inputLine(_ recipe: PokopiaCrafting.Recipe) -> String {
        recipe.inputs.map { input in
            "\(store.l.itemName(input.item)) \(store.itemCount(input.item))/\(input.count)"
        }.joined(separator: " · ")
    }

    private func durationText(_ recipe: PokopiaCrafting.Recipe) -> String {
        recipe.minutes >= 60 && recipe.minutes % 60 == 0
            ? "\(recipe.minutes / 60)시간"
            : "\(recipe.minutes)분"
    }

    private var footer: some View {
        HStack {
            // 지금 만드는 중인 것이 있으면 왜 버튼이 전부 죽어 있는지 여기서 말한다 —
            // 안 적으면 "만들기" 가 회색인 이유가 재료 부족인지 동시 제한인지 알 수 없다.
            if let order = store.state.townCraft {
                Text("\(store.l.itemName(order.output)) 만드는 중 — 한 번에 하나만 만들 수 있어요.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("닫기") { dismiss() }.controlSize(.small)
        }
    }
}
