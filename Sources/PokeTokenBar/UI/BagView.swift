import SwiftUI

/// 가방(인벤토리) — 소유 아이템 카드 + 사용. 빈 상태는 움직이는 잠만보(컬렉션의 피카츄 패턴).
struct BagView: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    var body: some View {
        if store.ownedItems.isEmpty && store.ownedTechnicalMachines.isEmpty
            && store.focusEggCount == 0 && store.eggFragmentCount == 0 {
            emptyState
        } else {
            // 스크롤은 팝오버 본체가 한다 — 여기에 또 하나를 두면 중첩이라 안쪽이 잘린 자리부터
            // 볼 방법이 없다(`PokemonRosterView` 주석의 그 결함이다).
            VStack(alignment: .leading, spacing: 8) {
                if store.eggFragmentCount > 0 {
                    HStack {
                        Text("🧩").font(.title2)
                        Text("알 조각 \(store.eggFragmentCount)/10 · 주간 모험 \(store.weeklyAdventureProgress)/10")
                            .font(.caption.bold())
                    }
                }
                if store.focusEggCount > 0 {
                    HStack(spacing: 10) {
                        Text("🥚").font(.system(size: 30))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("신비한 알 ×\(store.focusEggCount)")
                                .font(.callout.weight(.semibold))
                            Text("집중 모험에서 발견한 알입니다. 안전하게 보관 중이에요.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .pokedoroCard()
                }
                ForEach(store.ownedItems, id: \.kind) { item in
                    ItemCard(store: store, nav: nav, kind: item.kind, count: item.count)
                }
                ForEach(store.ownedTechnicalMachines, id: \.machine.id) { entry in
                    TechnicalMachineBagCard(store: store, nav: nav,
                                            machine: entry.machine, count: entry.count)
                }
            }
        }
    }

    /// 빈 가방 — 움직이는 잠만보(143) + 안내(특정 아이템명 미언급, 확장 대비).
    private var emptyState: some View {
        VStack(spacing: 10) {
            SpriteView(speciesID: 143, size: 96, animated: true)   // 잠만보(움직임)
            Text(store.l.bagEmptyTitle)
                .font(.callout.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private struct TechnicalMachineBagCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let machine: TechnicalMachine
    let count: Int
    @State private var move: MoveSpec?
    @State private var canLearn = false
    @State private var checking = true
    @State private var applying = false
    @State private var discarding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 27)).foregroundStyle(.purple)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(machine.label).font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.purple, in: Capsule())
                        Text(move?.name ?? machine.slug).font(.callout.weight(.semibold))
                        Text("×\(count)").font(.caption.bold()).foregroundStyle(.secondary)
                        if let move {
                            TypeBadge(type: move.type)
                            MoveCategoryIcon(damageClass: move.damageClass, l: store.l)
                        }
                    }
                    Text(move?.flavorText
                         ?? "포켓몬에게 기술을 가르칩니다.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
            }
            if discarding {
                discardControls(store.l)
            } else {
                HStack {
                    Text(statusText).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button(store.l.discard, role: .destructive) { discarding = true }
                        .buttonStyle(.borderless).controlSize(.small)
                        .disabled(applying)
                    Button(store.l.useItem) { teach() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(checking || applying || !canLearn || move == nil)
                }
            }
        }
        .padding(10)
        .pokedoroCard()
        .task(id: "\(store.currentSpeciesID ?? 0)-\(machine.moveID)") { await refresh() }
    }

    /// 아이템 카드와 같은 규약 — 되돌릴 수 없다는 문구를 버튼 위 한 줄에 둔다.
    private func discardControls(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.discardConfirm(move?.name ?? machine.label))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                if count > 1 {
                    Button(l.discardOne) { discardNow(1) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                Button(count > 1 ? l.discardAll(count) : l.discard, role: .destructive) { discardNow(count) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { discarding = false }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    private func discardNow(_ quantity: Int) {
        discarding = false
        store.discardTechnicalMachine(machine, quantity: quantity)
    }

    private var statusText: String {
        if store.state.active?.learnedMoves.contains(where: { $0.id == machine.moveID }) == true {
            return "이미 배운 기술"
        }
        if checking { return "배울 수 있는지 확인 중…" }
        return canLearn
            ? "현재 포켓몬이 배울 수 있어요"
            : "현재 포켓몬은 배울 수 없어요"
    }

    @MainActor private func refresh() async {
        checking = true
        move = await PokeAPIClient.shared.moveDetail(id: machine.moveID)
        if let speciesID = store.currentSpeciesID {
            canLearn = await PokeAPIClient.shared.canLearnMachine(speciesID: speciesID, moveID: machine.moveID)
                && store.state.active?.learnedMoves.contains(where: { $0.id == machine.moveID }) == false
        } else {
            canLearn = false
        }
        checking = false
    }

    private func teach() {
        applying = true
        Task { @MainActor in
            let opened = await store.useTechnicalMachine(machine)
            applying = false
            if opened { nav.tab = .home }
            else { await refresh() }
        }
    }
}

/// 아이템 1장 — 아이콘·이름·개수·설명 + 인라인 확인 사용.
/// 확인은 인라인(버튼 morph) — .sheet/.alert 금지: transient 팝오버가 닫힐 때 고아 시트가
/// 이후 클릭을 먹통내는 기존 결함(PopoverView 주석) 회피.
private struct ItemCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let kind: ItemKind
    let count: Int
    @State private var confirming = false
    @State private var discarding = false

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.itemName(kind)).font(.callout.weight(.semibold))
                        if !kind.isPassive {   // 보유형은 개수 개념이 없음(1회 구매·영구)
                            Text("×\(count)").font(.caption.weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Text(l.itemDescription(kind))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            useControls(l)
        }
        .padding(10)
        .pokedoroCard()
    }

    /// 이 아이템을 지금 쓸 수 있나 (갈래별 — 사탕은 라인 로딩 필요, 민트·테라피스는 활성 포켓몬만).
    ///
    /// 아래 세 switch 는 **`default:` 를 두지 않는다.** 갈래를 하나 늘렸는데 한 자리만 빠뜨리면
    /// 컴파일은 통과한 채 그 아이템이 진화 아이템처럼 다뤄진다 — `ItemKind.bagUse` 가 있는 이유다.
    private var canUse: Bool {
        switch kind.bagUse {
        case .candy:          return store.canUseRareCandy
        case .mint:           return store.canUseMint
        case .teraShard:      return store.canUseTeraShard
        case .heartScale:     return store.canUseHeartScale
        case .passive:        return false   // 보유형 — 사용 개념 없음(상시 효과)
        case .furniture:      return false
        case .evolutionItem:  return store.canUseEvolutionItem(kind)
        }
    }
    /// 사용 컨트롤 효과 힌트 ("+XP" / "성격 랜덤 변경").
    private func effectHint(_ l: L) -> String {
        switch kind.bagUse {
        case .candy:      return "+\(GameNumberFormatter.compact(RareCandy.xp)) XP"
        case .mint:       return l.mintEffectHint
        case .teraShard:  return l.teraShardEffectHint
        case .heartScale: return l.heartScaleEffectHint
        case .passive:    return l.shinyCharmEffectHint
        case .furniture:  return l.t("미니룸에서 배치", "Place in Mini Room", "ミニルームで配置")
        case .evolutionItem:
            return l.t("진화 가능할 때 사용", "Use when evolution is available", "進化できるときに使う")
        }
    }
    private func performUse() {
        switch kind.bagUse {
        case .candy:      _ = store.useRareCandy()
        case .mint:       _ = store.useMint()
        case .teraShard:  _ = store.useTeraShard()
        case .heartScale: store.useHeartScale()
        case .passive:    break   // 보유형 — 사용 동작 없음
        case .furniture:  break
        case .evolutionItem: _ = store.useEvolutionItem(kind)
        }
    }

    @ViewBuilder
    private func useControls(_ l: L) -> some View {
        if kind.isPassive {
            // 보유형(이로치 부적) — 사용 버튼 대신 상시 효과 표시.
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green)
                Text(l.shinyCharmEffectHint).font(.caption2.weight(.semibold)).foregroundStyle(.green)
                Spacer()
            }
        } else if discarding {
            discardControls(l)
        } else if canUse {
            if confirming {
                HStack(spacing: 8) {
                    Text(l.useOnCurrent(store.displayName))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button(l.use) { useNow() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button(l.cancel) { confirming = false }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            } else {
                HStack {
                    Text(effectHint(l))
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    Spacer()
                    discardButton(l)
                    Button(l.useItem) { confirming = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        } else {
            // 알(부화 전)/활성 없음/(사탕만)라인 미로딩 — 비활성 + 사유. 쓸 수 없어도 버릴 수는 있다.
            HStack {
                Text(store.isEgg ? l.useAfterHatch : l.useNeedsPokemon)
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                discardButton(l)
            }
        }
    }

    /// 버리기는 되돌릴 수 없어 문구를 한 줄 위에 따로 둔다 — 버튼과 같은 줄에 넣으면 잘린다.
    private func discardControls(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.discardConfirm(l.itemName(kind)))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                if count > 1 {
                    Button(l.discardOne) { discardNow(1) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                Button(count > 1 ? l.discardAll(count) : l.discard, role: .destructive) { discardNow(count) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { discarding = false }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    private func discardButton(_ l: L) -> some View {
        Button(l.discard, role: .destructive) { discarding = true }
            .buttonStyle(.borderless).controlSize(.small)
    }

    /// 전부 버리면 카드가 목록에서 사라진다(ownedItems 는 개수>0 만 싣는다).
    private func discardNow(_ quantity: Int) {
        discarding = false
        store.discardItem(kind, quantity: quantity)
    }

    /// 사용 → 항상 Home 탭으로 전환(진화/졸업 연출·"+XP"·성격 변경 토스트는 Home 의 CompanionHeader 에서 재생).
    private func useNow() {
        confirming = false
        performUse()
        nav.tab = .home
    }
}
