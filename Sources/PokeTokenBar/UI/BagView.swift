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
            // 고정 높이 — 컬렉션과 동일(팝오버 재오픈 시 fitting size 축소 방지).
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if store.eggFragmentCount > 0 {
                        HStack {
                            Text("🧩").font(.title2)
                            Text(store.l.t("알 조각 \(store.eggFragmentCount)/10 · 주간 모험 \(store.weeklyAdventureProgress)/10",
                                     "Egg Fragments \(store.eggFragmentCount)/10 · Weekly \(store.weeklyAdventureProgress)/10",
                                     "タマゴのかけら \(store.eggFragmentCount)/10 · 週間 \(store.weeklyAdventureProgress)/10"))
                                .font(.caption.bold())
                        }
                    }
                    if store.focusEggCount > 0 {
                        HStack(spacing: 10) {
                            Text("🥚").font(.system(size: 30))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.l.t("신비한 알 ×\(store.focusEggCount)", "Mystery Egg ×\(store.focusEggCount)", "ふしぎなタマゴ ×\(store.focusEggCount)"))
                                    .font(.callout.weight(.semibold))
                                Text(store.l.t("집중 모험에서 발견한 알입니다. 안전하게 보관 중이에요.",
                                         "Found during focus adventures and stored safely.",
                                         "集中の冒険で見つけたタマゴです。安全に保管中です。"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .pokedoroCard(tint: .purple)
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
            .frame(height: 520)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 27)).foregroundStyle(.purple)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(machine.label).font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.purple, in: Capsule())
                        Text(move?.name(store.language) ?? machine.slug).font(.callout.weight(.semibold))
                        Text("×\(count)").font(.caption.bold()).foregroundStyle(.secondary)
                        if let move {
                            TypeBadge(type: move.type, language: store.language)
                            MoveCategoryIcon(damageClass: move.damageClass, l: store.l)
                        }
                    }
                    Text(move?.description(store.language)
                         ?? store.l.t("포켓몬에게 기술을 가르칩니다.", "Teaches a move to a Pokémon.", "ポケモンにわざを教えます。"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
            }
            HStack {
                Text(statusText).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button(store.l.useItem) { teach() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(checking || applying || !canLearn || move == nil)
            }
        }
        .padding(10)
        .pokedoroCard(tint: .purple)
        .task(id: "\(store.currentSpeciesID ?? 0)-\(machine.moveID)") { await refresh() }
    }

    private var statusText: String {
        if store.state.active?.learnedMoves.contains(where: { $0.id == machine.moveID }) == true {
            return store.l.t("이미 배운 기술", "Already learned", "すでに覚えています")
        }
        if checking { return store.l.t("배울 수 있는지 확인 중…", "Checking compatibility…", "覚えられるか確認中…") }
        return canLearn
            ? store.l.t("현재 포켓몬이 배울 수 있어요", "The current Pokémon can learn it", "今のポケモンが覚えられます")
            : store.l.t("현재 포켓몬은 배울 수 없어요", "The current Pokémon cannot learn it", "今のポケモンは覚えられません")
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
        .pokedoroCard(tint: PokedoroTheme.blue)
    }

    /// 이 아이템을 지금 쓸 수 있나 (kind 별 — 사탕은 라인 로딩 필요, 민트는 활성 포켓몬만).
    private var canUse: Bool {
        switch kind {
        case .rareCandy: return store.canUseRareCandy
        case .mint:      return store.canUseMint
        case .shinyCharm: return false   // 보유형 — 사용 개념 없음(상시 효과)
        case .heartScale: return store.canUseHeartScale
        case .roomBed, .roomTable, .roomLamp, .lovelyVanity, .lovelySofa, .lovelyHeartLamp,
             .retroArcade, .retroRadio, .retroTV, .naturePlant, .natureBench, .natureLantern: return false
        default:   // 진화 아이템 전체(돌·연결의끈·지닌물건) — kind.isEvolutionItem
            return store.canUseEvolutionItem(kind)
        }
    }
    /// 사용 컨트롤 효과 힌트 ("+XP" / "성격 랜덤 변경").
    private func effectHint(_ l: L) -> String {
        switch kind {
        case .rareCandy: return "+\(GameNumberFormatter.compact(RareCandy.xp)) XP"
        case .mint:      return l.mintEffectHint
        case .shinyCharm: return l.shinyCharmEffectHint
        case .heartScale: return l.heartScaleEffectHint
        case .roomBed, .roomTable, .roomLamp, .lovelyVanity, .lovelySofa, .lovelyHeartLamp,
             .retroArcade, .retroRadio, .retroTV, .naturePlant, .natureBench, .natureLantern: return l.t("미니룸에서 배치", "Place in Mini Room", "ミニルームで配置")
        default:   // 진화 아이템 전체(돌·연결의끈·지닌물건) — kind.isEvolutionItem
            return l.t("진화 가능할 때 사용", "Use when evolution is available", "進化できるときに使う")
        }
    }
    private func performUse() {
        switch kind {
        case .rareCandy: _ = store.useRareCandy()
        case .mint:      _ = store.useMint()
        case .shinyCharm: break   // 보유형 — 사용 동작 없음
        case .heartScale: store.useHeartScale()
        case .roomBed, .roomTable, .roomLamp, .lovelyVanity, .lovelySofa, .lovelyHeartLamp,
             .retroArcade, .retroRadio, .retroTV, .naturePlant, .natureBench, .natureLantern: break
        default:   // 진화 아이템 전체(돌·연결의끈·지닌물건) — kind.isEvolutionItem
            _ = store.useEvolutionItem(kind)
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
                    Button(l.useItem) { confirming = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        } else {
            // 알(부화 전)/활성 없음/(사탕만)라인 미로딩 — 비활성 + 사유
            Text(store.isEgg ? l.useAfterHatch : l.useNeedsPokemon)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// 사용 → 항상 Home 탭으로 전환(진화/졸업 연출·"+XP"·성격 변경 토스트는 Home 의 CompanionHeader 에서 재생).
    private func useNow() {
        confirming = false
        performUse()
        nav.tab = .home
    }
}
