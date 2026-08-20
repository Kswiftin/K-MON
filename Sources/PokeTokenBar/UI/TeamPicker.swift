import SwiftUI

/// 출전 팀 고르기 — 누르면 넣고 빼고, 배지 숫자가 출전 순서다.
///
/// 배틀 탭과 체육관 오버레이가 같은 것을 쓴다. 두 곳에서 고르는 팀이 다르면 "내 출전 팀" 이
/// 둘이 되어, 어느 쪽에서 고른 게 나가는지 알 수 없다.
///
/// 스크롤을 쓰지 않는다. 배틀 탭은 팝오버 본체 ScrollView 안이라 안쪽에 또 두면 그 칸이
/// 잘린다(`BattleFieldTests.testTheBattleFieldSourceHasNoScrollView` 가 소스에서 막는다).
/// 대신 도감·소유 포켓몬과 같은 페이지식이다.
struct TeamPicker: View {
    let store: CompanionStore
    @Binding var selection: [UUID]
    /// 이 화면에서 고를 수 있는 최대 인원. 체육관은 관장 팀에 맞춰 3, 모의전은 화면에서 고른 크기다.
    let limit: Int
    @State private var page = 0
    /// 고를 타입. nil = 거르지 않음.
    @State private var typeFilter: PokemonType?
    /// 종 id → 타입. `MonState` 는 종 id 만 들고 있어 타입은 따로 받아야 한다.
    /// `battleProfile` 이 메모리 캐시를 두므로 같은 종을 여러 마리 가져도 조회는 한 번이다.
    @State private var monTypes: [Int: [PokemonType]] = [:]
    /// 종 id → 표시 이름. 스프라이트만으로는 무엇인지 알아보기 어렵다.
    @State private var speciesNames: [Int: String] = [:]

    /// 한 줄에 넷. 스프라이트 44 에 이름 한 줄이 들어가려면 칩이 이만큼은 돼야 한다 —
    /// 여섯을 넣던 시절엔 칸이 44pt 라 스프라이트가 30 으로 줄어 무엇인지 알아보기 어려웠다.
    private static let pageSize = 4
    /// 칩 넷 + 간격 셋 + 자체 여백이 팝오버 콘텐츠 폭(332) 안에 들어가야 한다:
    /// 70×4 + 6×3 + 16 = 314. 74 로 잡았을 땐 여유가 2pt 뿐이라 폰트가 조금만 커져도 넘쳤다.
    private static let chipWidth: CGFloat = 70

    private var l: L { store.l }

    /// 소유 포켓몬에 실제로 있는 타입만 — 안 가진 타입까지 늘어놓으면 고를 게 없는 항목이 대부분이다.
    private var availableTypes: [PokemonType] {
        let owned = Set(store.ownedMons.map(\.currentID))
        return Array(Set(monTypes.filter { owned.contains($0.key) }.values.flatMap { $0 }))
            .sorted { $0.rawValue < $1.rawValue }
    }

    private func displayName(_ mon: MonState) -> String {
        mon.nickname ?? speciesNames[mon.currentID] ?? "#\(mon.currentID)"
    }

    private func toggle(_ monID: UUID) {
        if let index = selection.firstIndex(of: monID) {
            selection.remove(at: index)
        } else if selection.count < limit {
            selection.append(monID)
        }
    }

    var body: some View {
        let all = store.ownedMons
        let shown = typeFilter.map { type in
            all.filter { (monTypes[$0.currentID] ?? []).contains(type) }
        } ?? all
        if all.count > 1 {
            let pageCount = max(1, (shown.count + Self.pageSize - 1) / Self.pageSize)
            // 개체가 줄면(졸업·방출·필터) 보던 페이지가 사라진다 — 범위 밖이면 마지막 페이지로 당긴다.
            let current = min(page, pageCount - 1)
            let slice = Array(shown.dropFirst(current * Self.pageSize).prefix(Self.pageSize))
            VStack(alignment: .leading, spacing: 6) {
                header
                pickedRow
                Divider().opacity(0.5)
                grid(slice)
                footer(current: current, pageCount: pageCount)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
            // 타입·이름은 화면에 뜬 뒤 채워진다 — 받는 동안에도 목록은 그대로 보인다.
            .task(id: all.map(\.currentID)) {
                for speciesID in Set(all.map(\.currentID)) {
                    if monTypes[speciesID] == nil,
                       let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID) {
                        monTypes[speciesID] = profile.types
                    }
                    if speciesNames[speciesID] == nil {
                        speciesNames[speciesID] = await store.resolveSpeciesName(speciesID)
                    }
                }
            }
        }
    }

    /// 제목 줄 — 이 자리가 무엇인지 먼저 말하고, 고른 수를 오른쪽에 둔다.
    private var header: some View {
        HStack(spacing: 6) {
            Label(l.teamPickerTitle, systemImage: "person.2.badge.gearshape")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 4)
            Text("\(min(selection.count, limit)) / \(limit)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(selection.count >= limit ? AnyShapeStyle(Color.accentColor)
                                                           : AnyShapeStyle(.secondary))
        }
    }

    /// 고른 팀 — **필터와 무관하게 항상 여기 보인다.**
    ///
    /// 아래 칩 줄은 필터에 걸린 것만 보여주므로, 다른 타입으로 옮기면 이미 고른 개체가 사라진다.
    /// 그 상태로는 빼려고 원래 타입으로 되돌아가야 했다. 이 줄에서 바로 뺀다.
    ///
    /// 정원만큼 칸을 그린다 — 빈 칸이 남은 자리를 보여주고, 줄 높이도 고정된다.
    private var pickedRow: some View {
        HStack(spacing: 5) {
            ForEach(0..<limit, id: \.self) { slot in
                if slot < selection.count,
                   let mon = store.ownedMons.first(where: { $0.id == selection[slot] }) {
                    PickedSlot(mon: mon, order: slot + 1,
                               onRemove: { toggle(mon.id) })
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .foregroundStyle(.tertiary)
                        .frame(width: PickedSlot.width, height: PickedSlot.height)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 칩 줄 — **항상 `pageSize` 칸이다.** 필터로 한 마리만 남아도 빈 칸으로 자리를 채워
    /// 높이가 그대로여야 한다. 예전엔 남는 수만큼만 그려 필터를 바꿀 때마다 아래가 출렁였다.
    private func grid(_ slice: [MonState]) -> some View {
        HStack(spacing: 6) {
            ForEach(slice, id: \.id) { mon in
                TeamPickChip(mon: mon, name: displayName(mon),
                             width: Self.chipWidth,
                             pickedIndex: selection.firstIndex(of: mon.id),
                             onTap: { toggle(mon.id) })
            }
            if slice.count < Self.pageSize {
                ForEach(slice.count..<Self.pageSize, id: \.self) { _ in
                    Color.clear.frame(width: Self.chipWidth, height: TeamPickChip.height)
                }
            }
        }
    }

    /// 아래 줄 — 왼쪽은 안내, 오른쪽은 페이저. 페이저를 고른 수(헤더 오른쪽)에서 떼어 놓는다.
    /// 둘이 붙어 있으면 `2 / 3` 과 `1 / 5` 가 나란히 놓여 어느 쪽이 팀 인원인지 헷갈린다.
    private func footer(current: Int, pageCount: Int) -> some View {
        HStack(spacing: 4) {
            Menu {
                Button(l.teamFilterAllTypes) { typeFilter = nil; page = 0 }
                ForEach(availableTypes, id: \.self) { type in
                    Button(type.name(store.language)) { typeFilter = type; page = 0 }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 9))
                    Text(typeFilter?.name(store.language) ?? l.teamFilterAllTypes)
                }
                .font(.caption2)
                .foregroundStyle(typeFilter == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .disabled(availableTypes.isEmpty)
            Spacer(minLength: 8)
            if pageCount > 1 {
                Button { page = max(0, current - 1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).disabled(current == 0)
                    .accessibilityLabel(l.dexPagePrev)
                Text("\(current + 1) / \(pageCount)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    .accessibilityLabel(l.dexPageLabel(current + 1, pageCount))
                Button { page = min(pageCount - 1, current + 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).disabled(current == pageCount - 1)
                    .accessibilityLabel(l.dexPageNext)
            }
        }
        .frame(height: 16)   // 페이저가 없는 페이지에서도 아래 여백이 같도록 자리를 예약한다.
    }
}

/// 고른 팀의 한 칸 — 스프라이트에 출전 순서, 누르면 뺀다.
/// 이름은 넣지 않는다. 방금 고른 것이라 스프라이트로 알아보고, 좁은 줄에 정원만큼 들어가야 한다.
private struct PickedSlot: View {
    let mon: MonState
    let order: Int
    let onRemove: () -> Void

    static let width: CGFloat = 38
    static let height: CGFloat = 40

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                SpriteView(speciesID: mon.currentID, size: 28, shiny: mon.isShiny)
                Text("\(order)").font(.system(size: 7, weight: .heavy)).foregroundStyle(.secondary)
            }
            .frame(width: Self.width, height: Self.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
            }
            .buttonStyle(.plain)
            .offset(x: 3, y: -3)
        }
        .frame(width: Self.width, height: Self.height)
    }
}

/// 출전 팀 칩 하나 — 스프라이트·이름·레벨. 고른 것에는 출전 순서를 배지로 얹는다.
struct TeamPickChip: View {
    let mon: MonState
    let name: String
    let width: CGFloat
    let pickedIndex: Int?
    let onTap: () -> Void

    /// 칩 높이 — 빈 자리도 같은 높이로 채워야 줄 높이가 흔들리지 않는다.
    static let height: CGFloat = 74

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                ZStack(alignment: .topTrailing) {
                    SpriteView(speciesID: mon.currentID, size: 44, shiny: mon.isShiny)
                    if let pickedIndex {
                        Text("\(pickedIndex + 1)")
                            .font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(Color.accentColor))
                    }
                }
                Text(name).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                Text("Lv.\(mon.level)").font(.system(size: 8)).foregroundStyle(.secondary)
            }
            .frame(width: width, height: Self.height)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(pickedIndex == nil ? Color.clear : Color.accentColor.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(pickedIndex == nil ? Color.secondary.opacity(0.3) : Color.accentColor,
                    lineWidth: pickedIndex == nil ? 1 : 1.5))
    }
}
