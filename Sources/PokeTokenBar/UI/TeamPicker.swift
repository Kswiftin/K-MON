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
    /// 이 화면에서 고를 수 있는 최대 인원. 체육관은 관장 팀에 맞춰 4(`GymLeague.teamSize`),
    /// 모의전은 화면에서 고른 크기다.
    let limit: Int
    @State private var page = 0
    /// 고를 타입. nil = 거르지 않음.
    @State private var typeFilter: PokemonType?
    /// 종 id → 타입. `MonState` 는 종 id 만 들고 있어 타입은 따로 받아야 한다.
    /// `battleProfile` 이 메모리 캐시를 두므로 같은 종을 여러 마리 가져도 조회는 한 번이다.
    @State private var monTypes: [Int: [PokemonType]] = [:]
    /// 종 id → 표시 이름. 스프라이트만으로는 무엇인지 알아보기 어렵다.
    @State private var speciesNames: [Int: String] = [:]
    /// 칩 줄의 레벨 정렬. 전투에는 키운 개체를 먼저 고르는 편이 자연스러워 높은 레벨이 기본이다.
    @State private var levelOrder: TeamPickerLevelOrder = .defaultOrder
    /// 기술을 펼쳐 볼 개체 — 칩이나 고른 칸을 누르면 그 개체로 바뀐다.
    /// 처음엔 비어 있다. 아무것도 안 눌렀는데 자리를 잡아먹으면 배틀 탭 세로 예산만 축낸다.
    @State private var previewedMonID: UUID?
    /// 개체 id → 대전에 나갈 기술. 한 번 받은 개체는 다시 받지 않는다.
    @State private var previewMoves: [UUID: [MoveSpec]] = [:]
    @State private var searchText = ""

    /// 한 줄에 넷. 스프라이트 44 에 이름 한 줄이 들어가려면 칩이 이만큼은 돼야 한다 —
    /// 여섯을 넣던 시절엔 칸이 44pt 라 스프라이트가 30 으로 줄어 무엇인지 알아보기 어려웠다.
    private static let pageSize = 4
    /// 칩 넷 + 간격 셋 + 자체 여백이 팝오버 콘텐츠 폭(332) 안에 들어가야 한다:
    /// 70×4 + 6×3 + 16 = 314. 74 로 잡았을 땐 여유가 2pt 뿐이라 폰트가 조금만 커져도 넘쳤다.
    private static let chipWidth: CGFloat = 70
    /// 기술 미리보기 격자 — 2×2 = 4칸. 넷은 본가 기술 상한이자 `SaveTransfer` 가 자르는 수라,
    /// 이보다 많은 기술이 들어올 자리가 없다.
    private static let previewRows = 2
    private static let previewColumns = 2

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

    /// 레벨 정렬 — 순서 규칙은 박스와 **같은** `RosterOrdering` 을 쓴다. 여기서 다시 구현하면
    /// 같은 "레벨순" 이 화면마다 다른 순서가 된다(동레벨 tie-break 이 특히 갈린다).
    private func arranged(_ mons: [MonState]) -> [MonState] {
        switch levelOrder {
        case .caught:     return mons
        case .ascending:  return RosterOrdering.arrange(mons, sort: .level, ascending: true)
        case .descending: return RosterOrdering.arrange(mons, sort: .level, ascending: false)
        }
    }

    private var levelOrderLabel: String {
        levelOrder == .caught ? l.t("부화순", "Caught", "ふ化順") : l.t("레벨순", "Level", "レベル順")
    }

    /// 누른 개체는 팀에 넣고 빼는 것과 **별개로** 기술을 펼친다. 뺄 때도 펼친 채로 두는 이유는,
    /// 정원이 찬 상태에서 누른 경우(넣지도 빼지도 못한다) 아무 반응이 없으면 고장으로 읽히기 때문이다.
    private func toggle(_ monID: UUID) {
        previewedMonID = monID
        if let index = selection.firstIndex(of: monID) {
            selection.remove(at: index)
        } else if selection.count < limit {
            selection.append(monID)
        }
    }

    /// 팀 전체 해제 — 한 칸씩 누르며 순서를 되돌릴 필요 없이 새 조합을 바로 고르게 한다.
    private func clearSelection() {
        selection.removeAll()
    }

    /// 대전에 실제로 나가는 목록을 그대로 받는다 — `CompanionStore.battleSnapshot` 과 같은 규칙이다.
    /// 저장된 기술이 있으면 그것(축이 빠졌으면 채워서), 없으면 같은 자동 무브셋이다.
    /// 화면과 실전이 다른 목록이면 이 미리보기가 오히려 팀을 잘못 짜게 만든다.
    ///
    /// 레벨은 개체 레벨이다. Lv.50 으로 맞추는 대전은 그 레벨의 자동 무브셋을 쓰므로 저장된 기술이
    /// 없는 개체에서는 실전과 갈릴 수 있다 — 그 경우까지 맞추려면 화면이 대전 종류를 알아야 한다.
    private func loadPreviewMoves(_ mon: MonState) async {
        guard previewMoves[mon.id] == nil else { return }
        if mon.learnedMoves.isEmpty {
            previewMoves[mon.id] = await PokeAPIClient.shared.moveSet(
                speciesID: mon.currentID, level: mon.level, types: monTypes[mon.currentID] ?? [])
        } else {
            previewMoves[mon.id] = await store.detailedMoves(of: mon)
        }
    }

    private func move(_ moves: [MoveSpec]?, at index: Int) -> MoveSpec? {
        guard let moves, index < moves.count else { return nil }
        return moves[index]
    }

    var body: some View {
        let all = store.ownedMons
        let searched = all.filter {
            PokemonNameSearch.matches(searchText, names: PokemonNameSearch.names(
                for: $0, resolvedSpeciesName: speciesNames[$0.currentID]))
        }
        let filtered = typeFilter.map { type in
            searched.filter { (monTypes[$0.currentID] ?? []).contains(type) }
        } ?? searched
        let shown = arranged(filtered)
        if all.count > 1 {
            let pageCount = max(1, (shown.count + Self.pageSize - 1) / Self.pageSize)
            // 개체가 줄면(졸업·방출·필터) 보던 페이지가 사라진다 — 범위 밖이면 마지막 페이지로 당긴다.
            let current = min(page, pageCount - 1)
            let slice = Array(shown.dropFirst(current * Self.pageSize).prefix(Self.pageSize))
            VStack(alignment: .leading, spacing: 6) {
                header
                PokemonSearchField(text: $searchText, l: l)
                pickedRow
                Divider().opacity(0.5)
                grid(slice)
                if let previewed = previewedMonID,
                   let mon = all.first(where: { $0.id == previewed }) {
                    movePreview(mon)
                }
                footer(current: current, pageCount: pageCount)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
            .onChange(of: searchText) { page = 0 }
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
            .task(id: previewedMonID) {
                guard let previewed = previewedMonID,
                      let mon = store.ownedMons.first(where: { $0.id == previewed }) else { return }
                await loadPreviewMoves(mon)
            }
        }
    }

    /// 제목 줄 — 이 자리가 무엇인지 먼저 말하고, 고른 수를 오른쪽에 둔다.
    private var header: some View {
        HStack(spacing: 6) {
            Label(l.teamPickerTitle, systemImage: "person.2.badge.gearshape")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 4)
            Button(l.t("전체 해제", "Clear all", "すべて解除"), action: clearSelection)
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
                .disabled(selection.isEmpty)
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

    /// 누른 개체가 들고 나갈 기술.
    ///
    /// **2열로 접는다.** 배틀 탭은 자기 `ScrollView` 를 둘 수 없고 세로 예산이 정해져 있어(#9),
    /// 네 줄로 펴면 넘친 만큼이 그대로 잘린다 — 스크롤로 볼 방법이 없다.
    ///
    /// 받는 동안에도 **같은 칸 수**를 그린다. 도착한 뒤에 줄이 생기면 그만큼 아래 페이저가 튄다
    /// (`MoveListView` 의 자리표시자와 같은 이유). 기술이 넷보다 적은 개체도 같은 높이로 남는다.
    private func movePreview(_ mon: MonState) -> some View {
        let moves = previewMoves[mon.id]
        return VStack(alignment: .leading, spacing: 3) {
            let name = displayName(mon)
            Text(l.t("\(name)의 기술", "\(name)'s moves", "\(name)のわざ"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary).lineLimit(1)
            ForEach(0..<Self.previewRows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<Self.previewColumns, id: \.self) { column in
                        moveCell(move(moves, at: row * Self.previewColumns + column))
                    }
                }
            }
        }
    }

    /// 기술 한 칸 — 이름과 위력만. 명중·PP 까지 넣으면 두 열에 안 들어가고, 팀을 고르는 자리에서
    /// 먼저 보는 건 무엇을 들고 나가는지와 얼마나 세게 때리는지다.
    private func moveCell(_ move: MoveSpec?) -> some View {
        HStack(spacing: 3) {
            Text(move.map { $0.name(store.language) } ?? "—")
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 2)
            if let move {
                MoveCategoryIcon(damageClass: move.damageClass, l: l)
                Text(move.damageClass == .status ? l.moveCategoryStatus
                     : "\(l.moveCategory(move.damageClass)) · \(l.movePowerShort(move.power))")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(move == nil ? 0.35 : 1)
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
            levelSortButton
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

    /// 레벨 정렬 버튼 — 누를 때마다 부화순 → 레벨 오름 → 레벨 내림으로 돈다.
    ///
    /// 오름·내림 **두 상태만** 두면 원래 순서(부화순)로 돌아갈 길이 없어진다. 지금까지 이 줄의
    /// 유일한 순서였으므로 그 자리를 없애지 않는다. 방향은 아이콘이 말하므로 글자에는 화살표를
    /// 넣지 않는다 — 좁은 줄에서 같은 정보를 두 번 그리게 된다.
    private var levelSortButton: some View {
        Button {
            levelOrder = levelOrder.next
            page = 0
        } label: {
            HStack(spacing: 2) {
                Image(systemName: levelOrder.iconName).font(.system(size: 9))
                Text(levelOrderLabel)
            }
            .font(.caption2)
            .foregroundStyle(levelOrder == .caught ? AnyShapeStyle(.secondary)
                                                   : AnyShapeStyle(Color.accentColor))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l.t("레벨 정렬", "Sort by level", "レベルで並べ替え"))
    }
}

/// 팀 고르기 줄의 레벨 정렬 상태.
///
/// `caught` 는 저장 순서다. 기본은 높은 레벨순이지만, 레벨 오름·내림과 부화순을 모두 순환해
/// 원하는 기준으로 되돌릴 수 있게 한다.
enum TeamPickerLevelOrder: CaseIterable, Sendable {
    case caught, ascending, descending

    static let defaultOrder: TeamPickerLevelOrder = .descending

    var next: TeamPickerLevelOrder {
        switch self {
        case .caught:     return .descending
        case .descending: return .ascending
        case .ascending:  return .caught
        }
    }

    /// 박스 정렬 메뉴와 같은 아이콘 — 두 화면이 다른 그림을 쓰면 같은 기능으로 안 읽힌다.
    var iconName: String {
        switch self {
        case .caught:     return "arrow.up.arrow.down"
        case .ascending:  return "arrow.up"
        case .descending: return "arrow.down"
        }
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
