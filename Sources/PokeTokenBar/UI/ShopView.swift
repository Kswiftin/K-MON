import SwiftUI

/// 상점 — 별의모래(`CompanionStore.availableTokens`)로 아이템 구매(이상한 사탕·민트).
/// 인라인 확인(버튼 morph) — .sheet/.alert 금지(BagView 주석과 동일: transient 팝오버가 닫힐 때
/// 고아 시트가 이후 클릭을 먹통내는 결함 회피).
struct ShopView: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    @State private var category: ShopCategory = .general
    @State private var machineQuery = ""
    @State private var machineNames: [Int: String] = [:]

    private enum ShopCategory: String, CaseIterable, Identifiable {
        case general, evolution, eggs, machines, outfits
        var id: String { rawValue }
    }

    var body: some View {
        let l = store.l
        // 스크롤은 팝오버 본체가 한다 — 여기에 또 하나를 두면 중첩이라 안쪽이 잘린 자리부터
        // 볼 방법이 없다(`PokemonRosterView` 주석의 그 결함이다). 목록이 길어지는 탭이라
        // Lazy 는 유지한다: 판매 목록이 30줄 가까이 되고(진화 아이템 28종, #89) VStack 은
        // 열자마자 아이템 스프라이트를 전부 받아온다.
        LazyVStack(alignment: .leading, spacing: 10) {
            walletHeader(l)
            Picker("", selection: $category) {
                Text(l.t("도구", "Items", "どうぐ")).tag(ShopCategory.general)
                Text(l.t("진화", "Evolution", "進化")).tag(ShopCategory.evolution)
                Text(l.t("알", "Eggs", "タマゴ")).tag(ShopCategory.eggs)
                Text(l.t("기술머신", "TMs", "わざマシン")).tag(ShopCategory.machines)
                Text(l.t("의상", "Outfits", "ふく")).tag(ShopCategory.outfits)
            }
            .pickerStyle(.segmented)

            switch category {
            case .general:
                ForEach(store.purchasableItems.filter { !$0.isEvolutionItem }, id: \.self) { kind in
                    ShopItemCard(store: store, kind: kind)
                }
            case .evolution:
                ForEach(store.purchasableItems.filter(\.isEvolutionItem), id: \.self) { kind in
                    ShopItemCard(store: store, kind: kind)
                }
            case .eggs:
                ForEach(FreshEgg.shopTiers, id: \.self) { tier in
                    EggCard(store: store, nav: nav, tier: tier)
                }
            case .machines:
                TextField(l.t("기술명 또는 TM 번호 검색", "Search move or TM number", "わざ名・TM番号を検索"),
                          text: $machineQuery)
                    .textFieldStyle(.roundedBorder)
                if filteredMachines.isEmpty {
                    ContentUnavailableView.search(text: machineQuery)
                }
                ForEach(filteredMachines) { machine in
                    TechnicalMachineShopCard(store: store, machine: machine) { name in
                        machineNames[machine.moveID] = name
                    }
                }
            case .outfits:
                // 상점 판매분만(`shopPrice != nil`) — 업적 보상 의상은 옷장에서 잠금으로 보인다.
                ForEach(OutfitItem.allCases.filter { $0.shopPrice != nil }, id: \.self) { item in
                    ShopOutfitCard(store: store, item: item)
                }
            }
        }
    }

    private var filteredMachines: [TechnicalMachine] {
        let query = machineQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !query.isEmpty else { return TechnicalMachine.catalog }
        return TechnicalMachine.catalog.filter { machine in
            let fields = [machine.label, machine.slug.replacingOccurrences(of: "-", with: " "),
                          machineNames[machine.moveID] ?? "", String(machine.number)]
            return fields.contains { $0.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                                 locale: .current).contains(query) }
        }
    }

    private func walletHeader(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l.spendableTokens)
                .font(.caption).foregroundStyle(.secondary)
            Text("⭐" + GameNumberFormatter.compact(store.availableTokens))
                .font(.system(size: 24, weight: .bold)).monospacedDigit()
            Text(l.shopHint)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .pokedoroCard(tint: PokedoroTheme.yellow, emphasized: true)
    }
}

/// 수량 선택 — 재고로 쌓이는 상품(도구·진화 아이템·기술머신)에만 붙는다. 알·의상·보유형은 대상이 아니다.
/// 상한은 "지금 잔액으로 살 수 있는 최대"라, 사는 즉시 상한이 줄고 선택 수량도 따라 줄어든다.
/// 네이티브 Stepper 를 쓰는 이유: 길게 누르면 자동 반복이라 수십 개도 클릭 한 번으로 올릴 수 있다.
private struct PurchaseQuantityPicker: View {
    @Binding var quantity: Int
    let upperBound: Int
    let l: L

    var body: some View {
        HStack(spacing: 6) {
            Stepper(value: $quantity, in: 1...max(1, upperBound)) {
                Text("×\(quantity)").font(.caption.weight(.bold)).monospacedDigit()
            }
            .controlSize(.small)
            .fixedSize()
            Button(l.buyMax) { quantity = upperBound }
                .buttonStyle(.borderless).controlSize(.small)
                .disabled(quantity >= upperBound)
        }
    }
}

/// 단가와 (수량이 2 이상일 때) 합계를 한 줄로 — "가격 ⭐100 → ⭐300".
private func priceLabel(_ l: L, unitPrice: Int, quantity: Int) -> String {
    let unit = "\(l.shopPriceLabel) ⭐\(GameNumberFormatter.compact(unitPrice))"
    guard quantity > 1 else { return unit }
    return unit + " → ⭐" + GameNumberFormatter.compact(unitPrice * quantity)
}

private struct TechnicalMachineShopCard: View {
    let store: CompanionStore
    let machine: TechnicalMachine
    let onResolveName: (String) -> Void
    @State private var move: MoveSpec?
    @State private var canActiveLearn: Bool?
    @State private var confirming = false
    @State private var quantity = 1

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
                        Text(move?.name(store.language) ?? machine.slug.replacingOccurrences(of: "-", with: " ").capitalized)
                            .font(.callout.weight(.semibold))
                        if let move {
                            TypeBadge(type: move.type, language: store.language)
                            MoveCategoryIcon(damageClass: move.damageClass, l: store.l)
                        }
                        let owned = store.technicalMachineCount(machine.moveID)
                        if owned > 0 {
                            Text("×\(owned)").font(.caption2.bold()).foregroundStyle(.secondary)
                        }
                    }
                    Text(move?.description(store.language)
                         ?? store.l.t("포켓몬에게 기술을 가르치는 일회용 기술머신입니다.",
                                      "A single-use machine that teaches a move.",
                                      "ポケモンにわざを教える使い切りのマシンです。"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if let move {
                        HStack(spacing: 10) {
                            Label(store.l.t("위력 \(move.power > 0 ? String(move.power) : "—")",
                                            "Power \(move.power > 0 ? String(move.power) : "—")",
                                            "威力 \(move.power > 0 ? String(move.power) : "—")"),
                                  systemImage: "burst.fill")
                            Label(store.l.t("명중률 \(move.accuracy.map { "\($0)%" } ?? "—")",
                                            "Accuracy \(move.accuracy.map { "\($0)%" } ?? "—")",
                                            "命中 \(move.accuracy.map { "\($0)%" } ?? "—")"),
                                  systemImage: "scope")
                        }
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    compatibilityLabel
                }
                Spacer()
            }
            if confirming {
                HStack {
                    Text(store.l.buyConfirm(move?.name(store.language) ?? machine.slug,
                                            quantity: quantity,
                                            total: GameNumberFormatter.compact(machine.price * quantity)))
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button(store.l.buy) { buyNow() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button(store.l.cancel) { confirming = false }.buttonStyle(.borderless).controlSize(.small)
                }
            } else {
                HStack {
                    Text(priceLabel(store.l, unitPrice: machine.price, quantity: quantity))
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    Spacer()
                    if store.canBuyTechnicalMachine(machine) {
                        if affordableCount > 1 {
                            PurchaseQuantityPicker(quantity: $quantity, upperBound: affordableCount, l: store.l)
                        }
                        Button(store.l.buy) { confirming = true }.buttonStyle(.bordered).controlSize(.small)
                    } else {
                        Text(store.l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(10)
        .pokedoroCard(tint: .purple)
        // 잔액이 줄면(여기서 샀든 다른 카드에서 샀든) 선택 수량을 상한까지 끌어내린다 — 안 그러면
        // 살 수 없는 수량이 남아 확인 문구는 "5장"인데 구매는 조용히 실패한다.
        .onChange(of: affordableCount) { _, newCount in
            quantity = min(quantity, max(1, newCount))
        }
        .task(id: "\(store.currentSpeciesID ?? 0)-\(machine.moveID)") {
            move = await PokeAPIClient.shared.moveDetail(id: machine.moveID)
            if let move { onResolveName(move.name(store.language)) }
            if let speciesID = store.currentSpeciesID {
                canActiveLearn = await PokeAPIClient.shared.canLearnMachine(speciesID: speciesID,
                                                                            moveID: machine.moveID)
            } else {
                canActiveLearn = nil
            }
        }
    }

    private var affordableCount: Int { store.maxPurchasableTechnicalMachines(machine) }

    private func buyNow() {
        confirming = false
        store.buyTechnicalMachine(machine, quantity: quantity)
        quantity = 1
    }

    @ViewBuilder private var compatibilityLabel: some View {
        if store.currentSpeciesID == nil {
            Label(store.l.t("홈 포켓몬이 없습니다.", "No home Pokémon.", "ホームポケモンがいません。"),
                  systemImage: "minus.circle")
                .font(.caption2).foregroundStyle(.secondary)
        } else if let canActiveLearn {
            Label(canActiveLearn
                  ? store.l.t("현재 홈 포켓몬이 배울 수 있음", "Home Pokémon can learn it", "ホームのポケモンが覚えられます")
                  : store.l.t("현재 홈 포켓몬은 배울 수 없음", "Home Pokémon cannot learn it", "ホームのポケモンは覚えられません"),
                  systemImage: canActiveLearn ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(canActiveLearn ? .green : .secondary)
        } else {
            Label(store.l.t("습득 가능 여부 확인 중", "Checking compatibility", "覚えられるか確認中"),
                  systemImage: "ellipsis.circle")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// 상점 아이템 1장 — 아이콘·이름·설명(사탕 XP / 민트 "성격 랜덤 변경")·보유수 + 가격/구매(인라인 확인).
/// kind 별 store.canBuy(kind)/buy(kind) 로 일반화 — 판매 목록은 store.purchasableItems.
private struct ShopItemCard: View {
    let store: CompanionStore
    let kind: ItemKind
    @State private var confirming = false
    @State private var quantity = 1

    private var price: Int { kind.shopPrice ?? 0 }
    private var affordableCount: Int { store.maxPurchasable(kind) }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.itemName(kind)).font(.callout.weight(.semibold))
                        let owned = store.itemCount(kind)
                        if owned > 0 && !kind.isPassive {
                            Text(l.ownedCount(owned)).font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Text(l.itemDescription(kind))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            buyControls(l)
        }
        .padding(10)
        .pokedoroCard(tint: PokedoroTheme.blue)
        // 잔액이 줄면(여기서 샀든 다른 카드에서 샀든) 선택 수량을 상한까지 끌어내린다 — 안 그러면
        // 살 수 없는 수량이 남아 확인 문구는 "5개"인데 구매는 조용히 실패한다.
        .onChange(of: affordableCount) { _, newCount in
            quantity = min(quantity, max(1, newCount))
        }
    }

    @ViewBuilder
    private func buyControls(_ l: L) -> some View {
        if kind.isPassive && store.itemCount(kind) > 0 {
            // 보유형(이로치 부적 등) — 1회 구매라 소유 후엔 "보유 중" 표시(재구매 버튼 없음).
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green)
                Text(l.ownedAlready).font(.caption2.weight(.semibold)).foregroundStyle(.green)
                Spacer()
            }
        } else if confirming {
            HStack(spacing: 8) {
                // 수량·합계가 붙으면 한 줄에 안 들어간다 — 2줄까지 허용.
                Text(l.buyConfirm(l.itemName(kind), quantity: quantity,
                                  total: GameNumberFormatter.compact(price * quantity)))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(l.buy) { buyNow() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { confirming = false }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        } else {
            HStack {
                Text(priceLabel(l, unitPrice: price, quantity: quantity))
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                if store.canBuy(kind) {
                    // 한 개밖에 못 사면 스텝퍼를 띄우지 않는다(기존 화면 그대로).
                    if affordableCount > 1 {
                        PurchaseQuantityPicker(quantity: $quantity, upperBound: affordableCount, l: l)
                    }
                    Button(l.buy) { confirming = true }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Text(l.notEnoughTokens)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func buyNow() {
        confirming = false
        store.buy(kind, quantity: quantity)
        quantity = 1
    }
}

/// 의상 상점 카드 — `ShopItemCard` 와 같은 골격이지만 아이콘이 아이템 스프라이트가 아니라
/// 그 슬롯 하나만 입힌 트레이너 미리보기다. 재구매 불가(보유형)라 `owned` 분기만 있고 개수 표시는 없다.
private struct ShopOutfitCard: View {
    let store: CompanionStore
    let item: OutfitItem
    @State private var confirming = false

    private var price: Int { item.shopPrice ?? 0 }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                TrainerAvatarView(outfit: TrainerOutfit(worn: [item.slot: item]), scale: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.outfitItemName(item)).font(.callout.weight(.semibold))
                    Text(l.outfitSlotName(item.slot))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            buyControls(l)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func buyControls(_ l: L) -> some View {
        if store.ownsOutfit(item) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green)
                Text(l.ownedAlready).font(.caption2.weight(.semibold)).foregroundStyle(.green)
                Spacer()
            }
        } else if confirming {
            HStack(spacing: 8) {
                Text(l.buyConfirm(l.outfitItemName(item)))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(l.buy) { buyNow() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { confirming = false }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        } else {
            HStack {
                Text("\(l.shopPriceLabel) ⭐\(GameNumberFormatter.compact(price))")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                if store.canBuyOutfit(item) {
                    Button(l.buy) { confirming = true }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Text(l.notEnoughTokens)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func buyNow() {
        confirming = false
        _ = store.buyOutfit(item)
    }
}

/// 알 카드 — 구매 = 보관 알 하나 추가. 키우던 개체는 건드리지 않는다(5분 뒤 박스로 부화한다).
/// `tier` 는 보증 등급 하한(nil = 보증 없는 기본 알). 구매 전 인라인으로 한 번 확인한다.
///
/// 등급 알의 시각 구분은 **카드의 등급 배지**로만 한다 — 알 스프라이트는 한 장뿐이고, 메뉴바·플로팅 펫은
/// 기존 알 그대로 둔다(새 에셋 없이 구분이 서는 최소 범위).
private struct EggCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let tier: Rarity?
    @State private var stage: Stage = .idle
    private enum Stage { case idle, confirm }

    private var price: Int { FreshEgg.price(guaranteeing: tier) }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // 크롭+정사각 보정한 알. 레이아웃은 30(다른 아이템 아이콘과 정렬 일치)으로 두되 알 자체는 26으로
                // 살짝 작게 — 프레임에 여백이 생겨 꽉 찬 "뚱뚱" 느낌이 줄고 크기도 약간 작아진다.
                SpriteView(speciesID: nil, size: 26)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.eggName(tier)).font(.callout.weight(.semibold))
                        if let tier {
                            // 도감 칩과 같은 라벨·색 — 상점의 등급 표기가 도감과 한 말로 맞물리게.
                            Text(l.rarityLabel(tier).uppercased()).font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(rarityColor(tier)).foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text(l.eggDescription(tier))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            controls(l)
        }
        .padding(10)
        .pokedoroCard(tint: .orange)
    }

    @ViewBuilder
    private func controls(_ l: L) -> some View {
        switch stage {
        case .idle:
            HStack {
                Text("\(l.shopPriceLabel) \(l.stardust(GameNumberFormatter.compact(price)))")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                if store.canBuyEgg(tier) {
                    Button(l.buy) { stage = .confirm }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Text(l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        case .confirm:
            HStack(spacing: 8) {
                Text(l.buyConfirm(l.eggName(tier)))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button(l.buy) { commit() }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { stage = .idle }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    /// 구매 실행 — 보관 알이 하나 늘고 가방의 알 줄에 반영된다. 화면 전환은 하지 않는다.
    private func commit() {
        stage = .idle
        _ = store.buyEgg(tier)
    }
}
