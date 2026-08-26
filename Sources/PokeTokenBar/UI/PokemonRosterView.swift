import SwiftUI

/// 소유 포켓몬 — 도감과 같은 페이지식 고정 격자(3열×5행).
///
/// 스크롤을 쓰지 않는 이유는 도감(`DexGridView`)과 같다. 팝오버 본체가 이미 ScrollView 라
/// 여기에 또 하나를 두면 중첩이 되고, 안쪽은 스크롤되지 않아 한 화면에 들어가는 만큼만 보이고
/// 나머지는 **볼 방법이 없었다**(21마리째부터 도달 불가). 예전엔 격자에 260 을 걸어 9마리쯤에서,
/// 그 뒤 520 으로 늘려 20마리쯤에서 끊겼다 — 잘리는 지점만 옮겼을 뿐 같은 결함이었다.
struct PokemonRosterView: View {
    let store: CompanionStore
    @State private var page = 0
    /// 정렬은 **탭을 떠나도 남는다** — `@State` 로 두면 홈에 갔다 오는 것만으로 기본값으로
    /// 돌아가, 60마리 박스에서 매번 다시 고르게 된다. 화면이 사라져도 남아야 하는 값이라
    /// 뷰가 아니라 설정에 둔다.
    @Environment(AppSettings.self) private var settings
    @State private var typeFilter: PokemonType?
    /// 종별로 한 번만 해석해 두는 표시값. 카드마다 따로 받아오면 정렬 키(이름·타입)를 화면과
    /// 맞출 수 없다 — 정렬·필터는 박스 전체를 봐야 하는데 행은 자기 것만 알기 때문이다.
    @State private var names: [Int: String] = [:]
    @State private var types: [Int: [PokemonType]] = [:]
    /// 타입 해석이 한 바퀴 돌았는지. 돌기 전엔 필터 메뉴를 열지 않는다 — 절반만 해석된 표로
    /// 거르면 "왜 얘가 안 보이지"가 로딩 순서에 따라 달라진다.
    @State private var didResolveTypes = false
    /// 방생 확인 대상. 되돌릴 수 없으므로 카드에서 바로 놓아주지 않고 한 번 물어본다.
    @State private var releaseTarget: MonState?
    @Environment(PokemonChatPresenter.self) private var chatPresenter

    /// 도감·상점·가방과 같은 520. 탭을 넘나들어도 팝오버가 리사이즈되지 않는다.
    private static let contentHeight: CGFloat = 520
    private static let columns = 3
    private static let rows = 5
    /// 한 페이지 15칸. 격자에 주어지는 세로(520 − 헤더 − 페이저 − 간격 ≈ 468)를 5행이 나누면
    /// 행이 약 90pt 라 카드(스프라이트 28 + 이름·레벨·타입·상태)가 찌그러지지 않는다.
    static let pageSize = columns * rows
    private static let spacing: CGFloat = 5

    /// 마지막 페이지가 덜 차도 한 페이지다. 한 마리도 없으면 빈 격자 한 장.
    static func pageCount(ownedCount: Int) -> Int {
        max(1, (ownedCount + pageSize - 1) / pageSize)
    }

    var body: some View {
        let owned = store.ownedMons
        let arranged = RosterOrdering.arrange(owned, sort: settings.rosterSort,
                                              ascending: settings.rosterSortAscending,
                                              typeFilter: typeFilter, types: types,
                                              language: store.language, names: names)
        let pageCount = Self.pageCount(ownedCount: arranged.count)
        // 졸업·방출·필터로 마릿수가 줄면 보던 페이지가 사라진다 — 범위 밖이면 마지막 페이지로 당긴다.
        let current = min(page, pageCount - 1)
        let slice = Array(arranged.dropFirst(current * Self.pageSize).prefix(Self.pageSize))
        VStack(alignment: .leading, spacing: 6) {
            header(shownCount: arranged.count, ownedCount: owned.count, owned: owned)
            grid(slice)
            footer(current: current, pageCount: pageCount)
        }
        .frame(height: Self.contentHeight, alignment: .top)
        .task(id: owned.map(\.currentID).sorted()) { await resolveDisplayValues(for: owned) }
        .confirmationDialog(releaseQuestion(releaseTarget), isPresented: releaseDialogBinding,
                            titleVisibility: .visible) {
            Button(store.l.t("놓아주기", "Release", "にがす"), role: .destructive) {
                if let target = releaseTarget { store.releaseMon(target.id) }
                releaseTarget = nil
            }
            Button(store.l.t("취소", "Cancel", "キャンセル"), role: .cancel) { releaseTarget = nil }
        } message: {
            Text(store.l.t("놓아준 포켓몬은 돌아오지 않습니다. 졸업해 도감에 기록된 개체라면 도감 기록은 남습니다.",
                     "A released Pokémon does not come back. If it had graduated, its Pokédex record stays.",
                     "にがしたポケモンは戻りません。卒業して図鑑に記録された個体なら記録は残ります。"))
        }
    }

    private var releaseDialogBinding: Binding<Bool> {
        Binding(get: { releaseTarget != nil }, set: { if !$0 { releaseTarget = nil } })
    }

    private func releaseQuestion(_ mon: MonState?) -> String {
        guard let mon else { return "" }
        return store.l.t("Lv.\(mon.level) 포켓몬을 놓아줄까요?",
                          "Release this Lv.\(mon.level) Pokémon?",
                          "Lv.\(mon.level) のポケモンをにがしますか？")
    }

    /// 박스 전체의 이름·타입을 한 번 해석한다. 이름은 개체에 저장된 다국어 이름으로 대부분 끝나고
    /// (`MonState.names`), 없는 것만 조회한다. 타입은 `battleProfile` 이 캐시하므로 두 번째부터 공짜다.
    private func resolveDisplayValues(for owned: [MonState]) async {
        for mon in owned {
            let id = mon.currentID
            if names[id] == nil {
                let local = RosterOrdering.displayName(mon, language: store.language)
                names[id] = local.hasPrefix("#") ? await store.resolveSpeciesName(id) : local
            }
            if types[id] == nil,
               let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: id) {
                types[id] = profile.types
            }
        }
        didResolveTypes = true
    }

    private func header(shownCount: Int, ownedCount: Int, owned: [MonState]) -> some View {
        HStack(spacing: 6) {
            Label(store.l.t("소유 포켓몬", "Owned Pokémon", "手持ちポケモン"), systemImage: "square.grid.2x2.fill")
                .font(.headline)
            Spacer(minLength: 2)
            sortMenu
            typeMenu(owned: owned)
            // 필터가 걸렸을 땐 "보이는 수 / 전체 수" — 숫자 하나만 두면 필터가 켜진 걸 놓친다.
            Text(shownCount == ownedCount ? "\(ownedCount)" : "\(shownCount)/\(ownedCount)")
                .font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
    }

    /// 정렬 메뉴 — **버튼 자체가 방향을 말한다.**
    ///
    /// 예전 버튼 아이콘은 `arrow.up.arrow.down` / `arrow.down.arrow.up` 이었다. 둘은 화살표 두 개가
    /// 자리만 바뀐 그림이라 나란히 놓고 봐야 겨우 구별되고, 하나만 보면 지금이 오름인지 내림인지
    /// 알 수 없다. 메뉴를 열어야만 알 수 있는 상태는 없는 것과 같다 — 한쪽 화살표로 바꾼다.
    private var sortMenu: some View {
        @Bindable var settings = settings
        return Menu {
            ForEach(RosterSort.allCases, id: \.self) { option in
                Button {
                    if settings.rosterSort == option { settings.rosterSortAscending.toggle() }
                    else { settings.rosterSort = option; settings.rosterSortAscending = true }
                    page = 0
                } label: {
                    Label(sortLabel(option), systemImage: settings.rosterSort == option
                          ? (settings.rosterSortAscending ? "arrow.up" : "arrow.down") : "")
                }
            }
        } label: {
            Label(sortLabel(settings.rosterSort),
                  systemImage: settings.rosterSortAscending ? "arrow.up" : "arrow.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel(settings.rosterSortAscending
                            ? store.l.t("정렬 — 오름차순", "Sort — ascending", "並べ替え — 昇順")
                            : store.l.t("정렬 — 내림차순", "Sort — descending", "並べ替え — 降順"))
    }

    private func typeMenu(owned: [MonState]) -> some View {
        let available = RosterOrdering.availableTypes(owned, types: types)
        return Menu {
            Button(store.l.t("전체 타입", "All types", "すべてのタイプ")) { typeFilter = nil; page = 0 }
            ForEach(available, id: \.self) { type in
                Button(type.name(store.language)) { typeFilter = type; page = 0 }
            }
        } label: {
            Label(typeFilter?.name(store.language) ?? store.l.t("타입", "Type", "タイプ"),
                  systemImage: "line.3.horizontal.decrease.circle")
                .font(.system(size: 10, weight: .semibold))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(!didResolveTypes || available.isEmpty)
        .accessibilityLabel(store.l.t("타입 필터", "Type filter", "タイプで絞り込み"))
    }

    private func sortLabel(_ option: RosterSort) -> String {
        switch option {
        case .caught:    return store.l.t("부화순", "Caught", "ふ化順")
        case .dexNumber: return store.l.t("도감번호순", "Dex No.", "図鑑番号順")
        case .name:      return store.l.t("이름순", "Name", "名前順")
        case .level:     return store.l.t("레벨순", "Level", "レベル順")
        }
    }

    /// 도감과 같은 이유로 행마다 maxHeight 를 건다 — 빈 칸의 Color 는 유연 크기라, 행에 안 걸면
    /// 빈 행이 늘어나 채워진 행을 짓누른다(마지막 페이지가 한 줄뿐일 때 그 줄이 찌그러짐).
    private func grid(_ slice: [MonState]) -> some View {
        VStack(spacing: Self.spacing) {
            ForEach(0..<Self.rows, id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(0..<Self.columns, id: \.self) { column in
                        let index = row * Self.columns + column
                        if index < slice.count {
                            let mon = slice[index]
                            RosterMonCard(store: store, mon: mon, isActive: mon.id == store.activeMonID,
                                          name: names[mon.currentID] ?? "",
                                          types: types[mon.currentID] ?? [],
                                          onRelease: { releaseTarget = mon },
                                          onChat: { chatPresenter.open(companionID: mon.id) })
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// 하단 한 줄 — 왼쪽은 모아둔 알, 오른쪽은 페이저. 페이저가 1페이지라 안 보일 때도 이 줄을
    /// 항상 예약한다(도감과 같은 규칙) — 페이지 수에 따라 격자 높이가 흔들리지 않게.
    private func footer(current: Int, pageCount: Int) -> some View {
        HStack(spacing: 8) {
            if store.focusEggCount > 0 {
                Text("🥚 × \(store.focusEggCount)").font(.caption.bold())
            }
            Spacer(minLength: 4)
            if pageCount > 1 {
                Button { page = max(0, current - 1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).disabled(current == 0)
                    .accessibilityLabel(store.l.dexPagePrev)
                Text("\(current + 1) / \(pageCount)")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(store.l.dexPageLabel(current + 1, pageCount))
                Button { page = min(pageCount - 1, current + 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).disabled(current == pageCount - 1)
                    .accessibilityLabel(store.l.dexPageNext)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .frame(height: 18)
    }
}

private struct RosterMonCard: View {
    let store: CompanionStore
    let mon: MonState
    let isActive: Bool
    /// 이름·타입은 부모가 박스 단위로 해석해 넘긴다 — 정렬·필터가 쓰는 값과 카드가 그리는 값이
    /// 갈라지지 않게 한다(행마다 따로 받아오면 정렬 키를 화면과 맞출 수 없다).
    let name: String
    let types: [PokemonType]
    /// 방생 요청 — 확인 대화상자는 부모가 띄운다(카드는 격자 칸이라 대화상자를 붙일 자리가 아니다).
    let onRelease: () -> Void
    let onChat: () -> Void

    var body: some View {
        card.contextMenu {
            Button(action: onChat) { Label(store.l.t("대화", "Chat", "話す"), systemImage: "bubble.left.and.bubble.right") }
            // 동행 중인 개체는 놓아줄 수 없다 — 성장 tick 이 붙을 곳이 없어진다. 먼저 교체한다.
            if !isActive {
                Button(role: .destructive, action: onRelease) {
                    Label(store.l.t("놓아주기", "Release", "にがす"), systemImage: "hand.wave")
                }
            }
        }
    }

    private var card: some View {
        Button { if !isActive { store.switchCompanion(to: mon.id) } } label: {
            VStack(spacing: 2) {
                // ✨ 는 도감 칸과 **같은 표식**이다(`DexCell`). 이로치 스프라이트는 색만 다를 뿐이라
                // 원래 색을 모르면 알아볼 수 없다 — 특히 색 차이가 작은 종(잉어킹 등)에서 그렇다.
                // 좌상단인 이유는 우상단을 대화 버튼이 쓰기 때문이다.
                SpriteView(speciesID: mon.currentID, size: 28, shiny: mon.isShiny)
                    .overlay(alignment: .topLeading) {
                        if mon.isShiny {
                            Text("✨")
                                .font(.system(size: 8))
                                .padding(.horizontal, 2)
                                .background(.regularMaterial, in: Capsule())
                                .accessibilityLabel(store.l.dexShinyLabel)
                        }
                    }
                Text(name.isEmpty ? "#\(mon.currentID)" : name).font(.system(size: 10, weight: .bold)).lineLimit(1)
                Text("Lv.\(mon.level)").font(.system(size: 8)).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(types, id: \.self) { type in
                        Text(type.name(store.language).uppercased())
                            .font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(type.rosterColor, in: Capsule())
                    }
                }
                Text(isActive
                     ? store.l.t("동행 중", "Active", "同行中")
                     : store.l.t("교체", "Switch", "交代"))
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(isActive ? .green : .secondary)
            }.frame(maxWidth: .infinity).padding(4)
        }.buttonStyle(.bordered).disabled(isActive)
        .overlay(alignment: .topTrailing) {
            Button(action: onChat) { Image(systemName: "bubble.left") }
                .buttonStyle(.borderless).controlSize(.mini).padding(3)
                .accessibilityLabel(store.l.t("대화", "Chat", "話す"))
        }
    }
}

private extension PokemonType {
    var rosterColor: Color {
        switch self {
        case .normal: .gray; case .fire: .red; case .water: .blue; case .electric: .yellow
        case .grass: .green; case .ice: .cyan; case .fighting: .brown; case .poison: .purple
        case .ground: .orange; case .flying: .indigo; case .psychic: .pink; case .bug: .green
        case .rock: .brown; case .ghost: .purple; case .dragon: .indigo; case .dark: .black
        case .steel: .gray; case .fairy: .pink
        }
    }
}
