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
    /// 즐겨찾기만 보기. 타입 필터와 같이 화면을 떠나면 풀린다 — 정렬과 달리 "지금 이 박스를 좁혀
    /// 보는 중"이라는 일시적 상태고, 남겨 두면 다음에 열었을 때 박스가 비어 보인다.
    @State private var favoritesOnly = false
    /// 같은 진화 계보를 가진 개체가 둘 이상인 가족만 보기.
    @State private var duplicatesOnly = false
    /// 졸업·교환 등으로 영구 도감에 아직 기록되지 않은 현재 모습만 보기.
    @State private var unregisteredOnly = false
    /// 최종 진화형에 닿아 졸업 버튼을 누를 수 있는 개체만 보기.
    @State private var graduateReadyOnly = false
    /// 종별로 한 번만 해석해 두는 표시값. 카드마다 따로 받아오면 정렬 키(이름·타입)를 화면과
    /// 맞출 수 없다 — 정렬·필터는 박스 전체를 봐야 하는데 행은 자기 것만 알기 때문이다.
    /// `store.rosterDisplayNameCache` 등으로 초기값을 미리 채운다(아래 `init`) — 탭을 나갔다
    /// 들어와도 이름·타입이 한 틱 비어 보이지 않게 하기 위해서다(`CompanionStore` 의 캐시 주석 참고).
    @State private var names: [Int: String]
    @State private var types: [Int: [PokemonType]]
    /// baseID → 진화 트리. 카드가 "졸업 가능" 배지를 달려면 그 개체가 최종형인지 알아야 하는데,
    /// 최종형 여부는 트리를 봐야만 안다(`CompanionStore.canGraduate(_:in:)` 와 같은 판정).
    /// 박스 개체는 활성화 전까지 `stageIndex`/`totalForms` 가 정규화되지 않을 수 있어
    /// (defect-log) 저장된 필드 대신 이 트리로 직접 판정한다. base 단위라 같은 계보를 여럿
    /// 가져도 조회는 한 번이다(`PokeAPIClient` 가 메모리 캐시를 둔다).
    @State private var evoLines: [Int: EvoLine]
    /// 타입 해석이 한 바퀴 돌았는지. 돌기 전엔 필터 메뉴를 열지 않는다 — 절반만 해석된 표로
    /// 거르면 "왜 얘가 안 보이지"가 로딩 순서에 따라 달라진다.
    @State private var didResolveTypes = false
    /// 방생 확인 대상. 되돌릴 수 없으므로 카드에서 바로 놓아주지 않고 한 번 물어본다.
    @State private var releaseTarget: MonState?
    @State private var infoTarget: MonState?
    @State private var searchText = ""
    @Environment(PokemonChatPresenter.self) private var chatPresenter

    /// 이름·타입·진화 트리를 `store` 의 캐시로 미리 채운다 — 탭을 나갔다 들어와 이 뷰가 통째로
    /// 다시 만들어져도(`PopoverView` 의 `switch nav.tab`), 지난번에 이미 풀어 둔 값이라면 빈
    /// 상태로 한 틱 그려지지 않는다.
    init(store: CompanionStore) {
        self.store = store
        _names = State(initialValue: store.rosterDisplayNameCache)
        _types = State(initialValue: store.rosterTypeCache)
        _evoLines = State(initialValue: store.rosterEvoLineCache)
    }

    /// 도감·상점·가방과 같은 520. 탭을 넘나들어도 팝오버가 리사이즈되지 않는다.
    ///
    /// `PopoverLayoutTests` 가 읽는다(`CollectionView.contentHeight` 와 같은 이유로 internal) —
    /// 이 값이 팝오버 뷰포트보다 크다는 사실이 페이저를 격자 위에 두는 근거다.
    static let contentHeight: CGFloat = 520
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
        let duplicateFamilies = RosterOrdering.duplicateEvolutionFamilyIDs(in: owned)
        // `store.dexSpecies` 는 소유 중인 개체까지 합성하므로 쓰지 않는다. 영구 도감만 보아야
        // 아직 졸업·교환으로 기록하지 않은 소유 포켓몬을 찾을 수 있다.
        let registeredSpecies = Set(store.state.dex.flatMap(\.chainOrder))
        let unregisteredIDs = Set(RosterOrdering.unregistered(
            owned, registeredSpeciesIDs: registeredSpecies).map(\.id))
        // 진화 트리를 아직 못 푼 개체는 졸업 가능 여부를 모른다 — `evoLines[mon.baseID]` 가 없으면
        // false 로 접는다(카드의 `graduateReady` 배지와 같은 기준, `grid(_:)` 참고).
        let graduateReadyIDs = Set(owned.filter { mon in
            evoLines[mon.baseID].map { store.canGraduate(mon, in: $0) } ?? false
        }.map(\.id))
        let searched = owned.filter {
            PokemonNameSearch.matches(searchText, names: PokemonNameSearch.names(
                for: $0, resolvedSpeciesName: names[$0.presentationID]))
            && (!favoritesOnly || store.isFavorite($0.id))
            && (!duplicatesOnly || duplicateFamilies.contains($0.baseID))
            && (!unregisteredOnly || unregisteredIDs.contains($0.id))
            && (!graduateReadyOnly || graduateReadyIDs.contains($0.id))
        }
        let arranged = RosterOrdering.arrange(searched, sort: settings.rosterSort,
                                              ascending: settings.rosterSortAscending,
                                              typeFilter: typeFilter, types: types, names: names)
        let pageCount = Self.pageCount(ownedCount: arranged.count)
        // 졸업·방출·필터로 마릿수가 줄면 보던 페이지가 사라진다 — 범위 밖이면 마지막 페이지로 당긴다.
        let current = min(page, pageCount - 1)
        let slice = Array(arranged.dropFirst(current * Self.pageSize).prefix(Self.pageSize))
        VStack(alignment: .leading, spacing: 6) {
            // zIndex — 필터 버튼 설명이 마우스를 올리면 아래 검색창·페이저 줄 위로 그려져야 한다.
            // 기본 순서(먼저 쓴 자식이 아래)로는 바로 다음 줄이 설명 말풍선을 덮어버린다.
            RosterHeader(shownCount: arranged.count, ownedCount: owned.count, owned: owned,
                         types: types, didResolveTypes: didResolveTypes,
                         typeFilter: $typeFilter, favoritesOnly: $favoritesOnly,
                         duplicatesOnly: $duplicatesOnly, unregisteredOnly: $unregisteredOnly,
                         graduateReadyOnly: $graduateReadyOnly, page: $page)
                .zIndex(1)
            // 검색칸과 페이저가 한 줄이다 — 페이저는 격자 **위**에 있어야 한다. 아래에 두었을 때는
            // 탭 콘텐츠(520)가 팝오버 뷰포트보다 높아 스크롤 밖으로 밀려, 11페이지를 가진 사용자가
            // 다음 페이지 버튼을 못 봤다(2026-09-07 리포트).
            HStack(spacing: 6) {
                PokemonSearchField(text: $searchText, l: store.l)
                pager(current: current, pageCount: pageCount)
            }
            grid(slice)
            footer()
        }
        .frame(height: Self.contentHeight, alignment: .top)
        // 상세정보 팝오버를 탭 오른쪽에 고정한다. 카드마다 다른 위치(그 카드의 정보 아이콘)에
        // 붙이는 대신, 오른쪽 가장자리에 박아 둔 이 1pt 짜리 고정 앵커 하나를 모든 카드가 공유한다.
        // 앵커가 **작고 위치가 바뀌지 않으므로** 첫 프레임 점프 결함(`RosterMonCard`, 2026-08-28
        // defect-log)이 재발하지 않는다 — 그 결함은 앵커가 탭 전체(520pt)처럼 컸을 때만 생겼다.
        .overlay(alignment: .trailing) {
            Color.clear.frame(width: 1, height: 1)
                .popover(isPresented: infoTargetIsPresented) {
                    if let infoTarget { PokemonDetailCard(store: store, mon: infoTarget) }
                }
        }
        .onChange(of: searchText) { page = 0 }
        .task(id: ownedNameTaskID(owned)) {
            await store.backfillMissingOwnedNames()
            await resolveDisplayValues(for: store.ownedMons)
        }
        .confirmationDialog(releaseQuestion(releaseTarget), isPresented: releaseDialogBinding,
                            titleVisibility: .visible) {
            Button("놓아주기", role: .destructive) {
                if let target = releaseTarget { store.releaseMon(target.id) }
                releaseTarget = nil
            }
            Button("취소", role: .cancel) { releaseTarget = nil }
        } message: {
            Text("놓아준 포켓몬은 돌아오지 않습니다. 졸업해 도감에 기록된 개체라면 도감 기록은 남습니다.")
        }
    }

    private var infoTargetIsPresented: Binding<Bool> {
        Binding(get: { infoTarget != nil }, set: { if !$0 { infoTarget = nil } })
    }

    private var releaseDialogBinding: Binding<Bool> {
        Binding(get: { releaseTarget != nil }, set: { if !$0 { releaseTarget = nil } })
    }

    private func releaseQuestion(_ mon: MonState?) -> String {
        guard let mon else { return "" }
        return "Lv.\(mon.level) 포켓몬을 놓아줄까요?"
    }

    /// 박스 전체의 이름·타입을 한 번 해석한다. 이름은 개체에 저장된 다국어 이름으로 대부분 끝나고
    /// (`MonState.names`), 없는 것만 조회한다. 타입은 `battleProfile` 이 캐시하므로 두 번째부터 공짜다.
    /// 세 값 모두 푼 뒤 `store` 의 캐시에도 써 둔다 — 다음에 이 탭을 열 때(뷰가 다시 만들어져도)
    /// `init` 이 그 캐시로 시작해 이 루프가 거의 다 건너뛴다.
    private func resolveDisplayValues(for owned: [MonState]) async {
        for mon in owned {
            let id = mon.presentationID
            if names[id] == nil {
                let local = RosterOrdering.displayName(mon)
                let resolved = local.hasPrefix("#") ? await store.resolveSpeciesName(id) : local
                names[id] = resolved
                store.rosterDisplayNameCache[id] = resolved
            }
            if types[id] == nil,
               let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: id) {
                types[id] = profile.types
                store.rosterTypeCache[id] = profile.types
            }
            if evoLines[mon.baseID] == nil,
               let line = try? await PokeAPIClient.shared.line(baseSpeciesID: mon.baseID) {
                evoLines[mon.baseID] = line
                store.rosterEvoLineCache[mon.baseID] = line
            }
        }
        didResolveTypes = true
    }

    private func ownedNameTaskID(_ owned: [MonState]) -> String {
        let identities = owned.map { "\($0.id):\($0.presentationID):\($0.names?[$0.currentID]?.count ?? 0)" }
            .sorted().joined(separator: "|")
        return "ko|\(identities)"
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
                            let graduateReady = evoLines[mon.baseID].map { store.canGraduate(mon, in: $0) } ?? false
                            RosterMonCard(store: store, mon: mon, isActive: mon.id == store.activeMonID,
                                          isGymDeployed: store.gymDefenseMonIDs.contains(mon.id),
                                          isFavorite: store.isFavorite(mon.id),
                                          graduateReady: graduateReady,
                                          name: names[mon.presentationID] ?? "",
                                          types: types[mon.presentationID] ?? [],
                                          infoTarget: $infoTarget,
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

    /// 페이지 이동 — 검색칸 오른쪽. 1페이지뿐이면 자리만 비워 둔다(칸 폭이 페이지 수에 따라
    /// 흔들리지 않게).
    @ViewBuilder private func pager(current: Int, pageCount: Int) -> some View {
        if pageCount > 1 {
            HStack(spacing: 6) {
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
            .font(.system(size: 11, weight: .semibold))
            .fixedSize()
        }
    }

    /// 하단 한 줄 — 모아둔 알. 알이 없을 때도 이 줄을 항상 예약한다(도감과 같은 규칙) —
    /// 알을 얻는 순간 격자 높이가 흔들리지 않게.
    private func footer() -> some View {
        HStack(spacing: 8) {
            if store.focusEggCount > 0 {
                Text("🥚 × \(store.focusEggCount)").font(.caption.bold())
            }
            Spacer(minLength: 4)
        }
        .font(.system(size: 11, weight: .semibold))
        .frame(height: 18)
    }
}

private struct RosterMonCard: View {
    let store: CompanionStore
    let mon: MonState
    let isActive: Bool
    /// 공유 체육관에 배치돼 지금 쓸 수 없는 개체. 동행 지정·방생·교환이 전부 막히므로 그 사실이
    /// 카드에도 보여야 한다 — 눌러 보고서야 아는 잠금은 고장으로 읽힌다.
    let isGymDeployed: Bool
    /// 즐겨찾기는 표시가 아니라 자물쇠다 — 켜져 있으면 놓아주기·경매 출품이 막힌다. 카드가 잠금
    /// 사유를 직접 그려야 "놓아주기가 왜 없지" 가 고장으로 읽히지 않는다.
    let isFavorite: Bool
    /// 최종 진화형에 닿았고 아직 졸업 버튼을 안 눌렀다(`CompanionStore.canGraduate(_:in:)`).
    /// 활성 개체는 홈 탭에 "다음 포켓몬으로 넘어가기" 카드가 따로 뜨지만, 박스에 놔둔 채 잊은
    /// 개체는 그 카드를 다시 볼 방법이 없다 — 활성으로 되돌리기 전까진 여기서만 알 수 있다.
    let graduateReady: Bool
    /// 이름·타입은 부모가 박스 단위로 해석해 넘긴다 — 정렬·필터가 쓰는 값과 카드가 그리는 값이
    /// 갈라지지 않게 한다(행마다 따로 받아오면 정렬 키를 화면과 맞출 수 없다).
    let name: String
    let types: [PokemonType]
    /// 상세정보 팝오버가 지금 누구를 보여주는지 — 팝오버 자체는 탭 오른쪽 고정 앵커에 하나만
    /// 붙어 있다(`PokemonRosterView.body`). 이 카드는 눌렸을 때 자기 개체로 바꿔 쓰기만 한다.
    @Binding var infoTarget: MonState?
    /// 방생 요청 — 확인 대화상자는 부모가 띄운다(카드는 격자 칸이라 대화상자를 붙일 자리가 아니다).
    let onRelease: () -> Void
    let onChat: () -> Void

    var body: some View {
        card.contextMenu {
            Button {
                store.markPokemonSeen(mon.id)
                infoTarget = mon
            } label: {
                Label("정보", systemImage: "info.circle")
            }
            Button(action: onChat) { Label("대화", systemImage: "bubble.left.and.bubble.right") }
            Button { store.toggleFavorite(mon.id) } label: {
                Label(isFavorite ? store.l.unfavorite : store.l.favorite,
                      systemImage: isFavorite ? "star.slash" : "star")
            }
            // 동행 중인 개체는 놓아줄 수 없다 — 성장 tick 이 붙을 곳이 없어진다. 먼저 교체한다.
            // 체육관 방어팀도 같다 — 자리에서 내리기 전엔 놓아줄 수 없다.
            // 즐겨찾기도 같은 부류의 잠금이고, 여기선 별을 끄는 것이 곧 해제다.
            if !isActive, !isGymDeployed, !isFavorite {
                Button(role: .destructive, action: onRelease) {
                    Label("놓아주기", systemImage: "hand.wave")
                }
            }
        }
    }

    private var card: some View {
        Button {
            store.markPokemonSeen(mon.id)
            if !isActive, !isGymDeployed { store.switchCompanion(to: mon.id) }
        } label: {
            VStack(spacing: 2) {
                // ✨ 는 도감 칸과 **같은 표식**이다(`DexCell`). 이로치 스프라이트는 색만 다를 뿐이라
                // 원래 색을 모르면 알아볼 수 없다 — 특히 색 차이가 작은 종(잉어킹 등)에서 그렇다.
                // 좌상단인 이유는 우상단을 대화 버튼이 쓰기 때문이다.
                SpriteView(speciesID: mon.presentationID, size: 28, shiny: mon.isShiny)
                    .overlay(alignment: .topLeading) {
                        if mon.isShiny {
                            Text("✨")
                                .font(PokedoroTheme.glyphFont(size: 8))
                                .padding(.horizontal, 2)
                                .background(.regularMaterial, in: Capsule())
                                .accessibilityLabel(store.l.dexShinyLabel)
                        }
                    }
                HStack(spacing: 2) {
                    Text(name.isEmpty ? "#\(mon.currentID)" : name)
                    if let gender = mon.gender {
                        Text(gender.symbol)
                            .foregroundStyle(gender == .male ? .blue : gender == .female ? .pink : .secondary)
                    }
                }
                .font(.system(size: 10, weight: .bold)).lineLimit(1)
                Text("Lv.\(mon.level)").font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(types, id: \.self) { type in
                        Text(type.name)
                            .font(PokedoroTheme.badgeFont(size: 7, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(type.rosterColor, in: Capsule())
                    }
                }
                // "동행 중"/"교체" 는 지웠다 — 활성 여부는 테두리 색(`mint`)과 탭 가능 여부로
                // 이미 보인다. 이 자리는 대신 놓치기 쉬운 신호를 준다: 최종형인데 졸업 버튼을
                // 안 눌러 둔 개체. 활성 개체는 홈 탭에 "다음 포켓몬으로 넘어가기" 카드가 따로
                // 뜨지만, 박스에 둔 채 잊은 개체는 여기서만 알 수 있다.
                Text(isGymDeployed ? store.l.gymDeployedBadge
                     : graduateReady ? "졸업 가능" : "")
                    .font(PokedoroTheme.badgeFont(size: 7, weight: .bold))
                    .foregroundStyle(isGymDeployed ? .orange : graduateReady ? .green : .clear)
            }.frame(maxWidth: .infinity).padding(4)
        }
        .buttonStyle(.plain).disabled(isActive || isGymDeployed)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(isGymDeployed ? Color.orange.opacity(0.55)
                          : isActive ? PokedoroTheme.mint.opacity(0.45) : Color.primary.opacity(0.075),
                          lineWidth: 1)
            .allowsHitTesting(false))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 0) {
                Button {
                    store.markPokemonSeen(mon.id)
                    infoTarget = mon
                } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless).controlSize(.mini)
                    .accessibilityLabel("포켓몬 정보")
                Button(action: onChat) { Image(systemName: "bubble.left") }
                    .buttonStyle(.borderless).controlSize(.mini)
                    .accessibilityLabel("대화")
                // 채워진 노란 별이 잠금 표시를 겸한다 — 별도 배지 없이 상태와 토글이 한 자리다.
                Button { store.toggleFavorite(mon.id) } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Color.yellow : .secondary)
                }
                .buttonStyle(.borderless).controlSize(.mini)
                .accessibilityLabel(isFavorite ? store.l.unfavorite : store.l.favorite)
                .help(isFavorite ? store.l.favoriteLockedHint : store.l.favorite)
            }.padding(3)
        }
        .overlay(alignment: .bottomLeading) {
            if let held = mon.heldItem {
                Image(systemName: "bag.fill")
                    .font(PokedoroTheme.badgeFont(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .background(.regularMaterial, in: Capsule())
                    .padding(3)
                    .help("\(store.l.heldItemSectionTitle): \(store.l.itemName(held))")
                    .accessibilityLabel("\(store.l.heldItemSectionTitle) \(store.l.itemName(held))")
            }
        }
        .overlay(alignment: .topLeading) {
            if mon.isNewlyHatched {
                Text("NEW")
                    .font(PokedoroTheme.badgeFont(size: 7, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .padding(3)
                    .accessibilityLabel("새 포켓몬")
            }
        }
    }
}

private struct PokemonDetailCard: View {
    let store: CompanionStore
    let mon: MonState
    @State private var profile: PokemonBattleProfile?
    @State private var line: EvoLine?
    @State private var abilityText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SpriteView(speciesID: mon.presentationID, size: 54, shiny: mon.isShiny)
                VStack(alignment: .leading, spacing: 3) {
                    Text(RosterOrdering.displayName(mon)).font(.headline)
                    Text("#\(String(format: "%03d", mon.currentID)) · Lv.\(mon.level) \(mon.gender?.symbol ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(evolutionText).font(.caption2).foregroundStyle(.orange)
                }
            }
            if let abilityText, !abilityText.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Label("특성", systemImage: "sparkles")
                        .font(.caption.bold())
                    Text(abilityText)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            heldItemRow()
            teraTypeRow()
            // 종족값을 그대로 띄우지 않는다 — `CompanionStore.currentStats` 와 같은 이유로
            // 이 개체의 레벨·성격을 먹인 실제 능력치라야 민트를 써도 숫자가 움직인다.
            if let base = profile?.stats { statGrid(base.effective(level: mon.level, nature: mon.nature)) }
            Divider()
            Text(store.l.movesTitle).font(.caption.bold())
            if mon.learnedMoves.isEmpty {
                Text(store.l.movesEmpty).font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(mon.learnedMoves) { move in
                    HStack(spacing: 5) {
                        Text(move.name).font(.caption.bold())
                        MoveCategoryIcon(damageClass: move.damageClass, l: store.l)
                        Text(store.l.moveCategory(move.damageClass)).font(.caption2)
                            .foregroundStyle(move.damageClass == .physical ? .orange : move.damageClass == .special ? .blue : .secondary)
                        Spacer()
                        Text(move.damageClass == .status ? "—" : store.l.movePowerShort(move.power))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14).frame(width: 330)
        .task(id: "\(mon.presentationID)-\(mon.abilitySlug ?? "default")-ko") {
            profile = try? await PokeAPIClient.shared.battleProfile(speciesID: mon.presentationID)
            line = try? await PokeAPIClient.shared.line(baseSpeciesID: mon.baseID)
            if let slug = mon.abilitySlug ?? profile?.abilitySlug {
                abilityText = await PokeAPIClient.shared.localizedAbilityName(slug: slug)
                    + (mon.abilityIsHidden ? " (숨은 특성)" : "")
            } else {
                abilityText = nil
            }
        }
    }

    /// 테라 타입 줄. 값이 없으면 그리지 않는다 — `nil` 은 "첫 번째 타입에서 파생" 이라
    /// (`BattleSnapshot.teraType`) 표시할 사실이 아직 없다는 뜻이고, 테라피스를 써야 생긴다.
    @ViewBuilder private func teraTypeRow() -> some View {
        if let tera = mon.teraType {
            HStack(spacing: 4) {
                Label(store.l.teraTypeSectionTitle, systemImage: "diamond")
                    .font(.caption.bold())
                Text(tera.name)
                    .font(PokedoroTheme.badgeFont(size: 7, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(tera.rosterColor, in: Capsule())
                Spacer(minLength: 4)
            }
        }
    }

    /// 지닌물건 줄. 물건이 없으면 아무것도 그리지 않는다 — 빈 줄을 예약하면 특성과 종족값
    /// 사이가 벌어지고, "없음" 은 161종 중 어느 것도 안 쥔 대다수 개체에서 잡음만 된다.
    ///
    /// 효과 힌트를 이름과 함께 낸다(가방과 같은 문구 — `heldItemEffectHint`). 이름만으로는
    /// 무엇이 붙었는지 알 수 없는 물건이 대부분이다.
    ///
    /// 벗기기는 **활성 개체에서만** 낸다 — `CompanionStore.takeHeldItem` 이 활성 개체를 대상으로
    /// 하므로, 박스 개체에 버튼을 두면 눌러도 다른 개체의 물건이 벗겨진다.
    @ViewBuilder private func heldItemRow() -> some View {
        if let held = store.heldItem(of: mon) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Label(store.l.heldItemSectionTitle, systemImage: "bag")
                        .font(.caption.bold())
                    Spacer(minLength: 4)
                    if mon.id == store.activeMonID, store.canTakeHeldItem {
                        Button(store.l.heldItemTakeOff) { store.takeHeldItem() }
                            .buttonStyle(.bordered).controlSize(.mini)
                    }
                }
                Text(store.l.itemName(held)).font(.caption2.bold())
                Text(store.l.heldItemEffectHint(held))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statGrid(_ s: BattleStats) -> some View {
        let values = [("HP", s.hp), ("공격", s.atk),
                      ("방어", s.def),
                      ("특공", s.spa),
                      ("특방", s.spd),
                      ("스피드", s.spe)]
        return LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 5) {
            ForEach(values, id: \.0) { label, value in
                HStack { Text(label); Spacer(); Text("\(value)").bold() }
                    .font(.caption2).padding(5).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private var evolutionText: String {
        guard let node = line?.tree.node(withID: mon.currentID), !node.children.isEmpty else { return store.l.finalForm }
        let nextIndex = mon.stageIndex + 1
        let next = mon.plannedPathIDs.indices.contains(nextIndex)
            ? node.children.first(where: { $0.speciesID == mon.plannedPathIDs[nextIndex] }) ?? node.children[0]
            : node.children[0]
        var parts: [String] = []
        if let g = next.evolutionGender { parts.append(g.name) }
        if let time = next.evolutionTimeOfDay { parts.append(time == "day" ? "낮" : "밤") }
        if let move = next.evolutionKnownMoveID {
            let name = line?.evolutionMoveNames[move].flatMap { PokemonNaming.name($0) } ?? "#\(move)"
            parts.append("\(name) 습득 후 레벨업")
        }
        else if let level = next.evolutionLevel { parts.append("Lv.\(level)에 진화") }
        else if let item = ItemKind.allCases.first(where: { $0.evolutionRule?.opens(next) == true }) { parts.append(store.l.evolutionNeedsItem(store.l.itemName(item))) }
        else if next.evolutionPartySpeciesID == 223 { parts.append("총어 보유 후 레벨업") }
        // 레벨 조건 없는 레벨업 진화(친밀도·장소 등)는 키우면 진화한다 — 홈의
        // `evolutionRequirementText` 와 같은 말을 해야 두 화면이 어긋나지 않는다.
        else if next.evolutionTrigger == "level-up" { parts.append("레벨업으로 진화") }
        else { parts.append("특수 조건으로 진화") }
        return parts.joined(separator: " · ")
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
