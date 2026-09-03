import SwiftUI

struct PokemonAuctionView: View {
    private enum OfferKind: String, CaseIterable { case pokemon, stardust }
    let store: CompanionStore
    let center: PokemonAuctionCenter
    let onClose: () -> Void
    @State private var selectedListingMonID: UUID?
    @State private var offerSelections: [UUID: UUID] = [:]
    @State private var offerKinds: [UUID: OfferKind] = [:]
    @State private var stardustOffers: [UUID: String] = [:]
    @State private var showsListingPicker = false
    /// 제안 목록을 열어 둔 출품의 ID. 카드마다 상태를 두면 `ForEach` 안에서 팝오버가 여러 개
    /// 살아 있게 되므로, 열려 있는 하나만 기억한다.
    @State private var offerPickerListingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.l.t("포켓몬 경매 시장", "Pokémon Offer Market", "ポケモン交換市場"),
                      systemImage: "storefront.fill").font(.title3.bold()).foregroundStyle(.orange)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Text(store.l.t("여러 포켓몬을 올리고 포켓몬 또는 별의모래 제안을 비교해 수락하세요.",
                           "List multiple Pokémon and accept a Pokémon or Stardust offer.",
                           "複数のポケモンを出品し、ポケモンまたはほしのすなの提案を選べます。"))
                .font(.caption).foregroundStyle(.secondary)
            myListing
            Divider()
            market
            if let error = center.lastError { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private var myListing: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(store.l.t("내 경매 \(center.localListings.count)건", "My Listings (\(center.localListings.count))",
                           "自分の出品 \(center.localListings.count)件")).font(.headline)
            ForEach(center.localListings.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                if let listing = center.localListings[id] {
                    localListingCard(id: id, listing: listing)
                }
            }
            // 내 제안이 받치고 있는 개체도 후보에서 뺀다 — 게시와 제안이 둘 다 수락되면
            // 같은 개체가 두 번 커밋된다.
            let candidates = store.deployableMons.filter { !committedMonIDs.contains($0.id) }
            Button {
                showsListingPicker = true
            } label: {
                Label(selectedListingMon.map(nameWithLevel)
                      ?? store.l.t("게시할 포켓몬 선택", "Choose a Pokémon to list", "出品するポケモンを選ぶ"),
                      systemImage: "chevron.down")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showsListingPicker) {
                MonOfferPicker(store: store, mons: candidates) { mon in
                    selectedListingMonID = mon.id
                    showsListingPicker = false
                }
            }
            Button(store.l.t("경매 시장에 추가", "Add Listing", "市場に追加")) {
                center.publish(selectedListingMon)
                selectedListingMonID = nil
            }.buttonStyle(.bordered).disabled(selectedListingMon == nil)
        }.padding(9).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
    }

    private func localListingCard(id: UUID, listing: TradePokemonSnapshot) -> some View {
        let listingOffers = center.offers.filter { $0.listingID == id }
        return VStack(alignment: .leading, spacing: 6) {
            pokemonRow(listing.mon, name: listing.displayName)
                HStack {
                Text(store.l.t("제안 \(listingOffers.filter { $0.status == .pending }.count)건",
                               "\(listingOffers.filter { $0.status == .pending }.count) offer(s)",
                               "提案 \(listingOffers.filter { $0.status == .pending }.count)件"))
                        .font(.caption.bold()).foregroundStyle(.orange)
                    Spacer()
                    Button(store.l.t("게시 내리기", "Remove Listing", "出品を取り消す"), role: .destructive) {
                    center.cancelListing(id)
                    }.controlSize(.small)
                }
            ForEach(listingOffers) { offer in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(offer.trainerName).font(.caption.bold())
                    offerValue(offer.value)
                        HStack {
                            Text(statusText(offer.status)).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            if offer.status == .pending {
                                Button(store.l.t("거절", "Reject", "拒否")) { center.reject(offer.id) }
                                    .controlSize(.small)
                                Button(store.l.t("수락", "Accept", "承認")) { center.accept(offer.id) }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                            }
                        }
                    }.padding(7).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }
        }.padding(7).background(Color.orange.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    private var market: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(store.l.t("근처 경매 목록", "Nearby Listings", "近くの出品" )).font(.headline)
            ForEach(center.outgoingOffers) { outgoingCard($0) }
            if center.listings.isEmpty {
                ContentUnavailableView(store.l.t("올라온 포켓몬이 없어요", "No listings nearby", "近くに出品はありません"),
                                       systemImage: "shippingbox")
            } else {
                ForEach(center.listings) { listing in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SpriteView(speciesID: listing.speciesID, size: 40, shiny: listing.isShiny)
                            VStack(alignment: .leading) {
                                Text(listing.displayName).font(.callout.bold())
                                Text("\(listing.trainerName) · Lv.\(listing.level)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Picker(store.l.t("제안 종류", "Offer type", "提案の種類"),
                               selection: Binding(get: { offerKinds[listing.id] ?? .pokemon },
                                                  set: { offerKinds[listing.id] = $0 })) {
                            Text(store.l.t("포켓몬", "Pokémon", "ポケモン")).tag(OfferKind.pokemon)
                            Text(store.l.t("별의모래", "Stardust", "ほしのすな")).tag(OfferKind.stardust)
                        }
                        .pickerStyle(.segmented)
                        let kind = offerKinds[listing.id] ?? .pokemon
                        let offered = offerSelections[listing.id].flatMap(mon(withID:))
                        let amount = Int(stardustOffers[listing.id] ?? "") ?? 0
                        if kind == .pokemon {
                            Button {
                                offerPickerListingID = listing.id
                            } label: {
                                Label(offered.map(nameWithLevel)
                                      ?? store.l.t("제안할 내 포켓몬 선택", "Choose your offer", "提案するポケモンを選ぶ"),
                                      systemImage: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .popover(isPresented: offerPickerBinding(for: listing.id)) {
                                // 이미 게시·제안에 걸린 개체는 후보에서 뺀다 — 센터가 막지만
                                // 고를 수 있게 두면 버튼이 조용히 아무 일도 안 한 것처럼 보인다.
                                MonOfferPicker(store: store, mons: store.deployableMons.filter {
                                    !committedMonIDs.contains($0.id)
                                }) { mon in
                                    offerSelections[listing.id] = mon.id
                                    offerPickerListingID = nil
                                }
                            }
                        } else {
                            HStack {
                                TextField(store.l.t("제안 금액", "Offer amount", "提案額"),
                                          text: Binding(get: { stardustOffers[listing.id] ?? "" },
                                                        set: { stardustOffers[listing.id] = $0.filter(\.isNumber) }))
                                    .textFieldStyle(.roundedBorder)
                                Text("/ \(unpledgedTokens.formatted())")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        Button(store.l.t("교환 제안", "Send Offer", "交換を提案")) {
                            if kind == .pokemon, let offered {
                                center.apply(to: listing, offering: offered)
                                offerSelections[listing.id] = nil
                            } else if kind == .stardust {
                                center.apply(to: listing, offeringStardust: amount)
                                stardustOffers[listing.id] = nil
                            }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        // 제안은 여러 건 동시에 걸 수 있다. 막는 것은 정원과 **약속한 별의모래의
                        // 합**뿐이다 — 잔액만 보면 지킬 수 없는 제안을 여러 건 걸게 된다.
                        .disabled((kind == .pokemon ? offered == nil : amount <= 0 || amount > unpledgedTokens)
                                  || center.outgoingOffers.count >= PokemonAuctionCenter.maxOutgoingOffers)
                    }.padding(8).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func pokemonRow(_ mon: MonState, name: String) -> some View {
        HStack(spacing: 7) {
            SpriteView(speciesID: mon.presentationID, size: 36, shiny: mon.isShiny)
            Text(name).font(.callout.bold())
            Spacer(); Text("Lv.\(mon.level)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func offerValue(_ value: AuctionOfferValue) -> some View {
        switch value {
        case .pokemon(let pokemon): pokemonRow(pokemon.mon, name: pokemon.displayName)
        case .stardust(let amount):
            Label("\(amount.formatted()) \(store.l.t("별의모래", "Stardust", "ほしのすな"))",
                  systemImage: "sparkles").font(.callout.bold()).foregroundStyle(.orange)
        }
    }

    private var selectedListingMon: MonState? { selectedListingMonID.flatMap(mon(withID:)) }

    /// 고른 뒤 그 개체가 사라졌을 수도 있다(교환·체육관 배치) — ID 를 매번 현재 목록에서 되찾는다.
    private func mon(withID id: UUID) -> MonState? {
        store.deployableMons.first { $0.id == id }
    }

    /// 출품 카드마다 팝오버를 하나씩 두면 `ForEach` 안에서 여러 개가 동시에 살아 있게 된다 —
    /// 열려 있는 하나만 기억하고, 그 카드에서만 참으로 읽히는 바인딩을 만든다.
    private func offerPickerBinding(for listingID: UUID) -> Binding<Bool> {
        Binding(get: { offerPickerListingID == listingID },
                set: { if !$0 { offerPickerListingID = nil } })
    }

    /// 피커는 스프라이트도 부제도 없는 한 줄이라 이름만으로는 같은 종의 다른 개체를 못 고른다 —
    /// 목록 밖(카드·제안 줄)에서 쓰는 표기와 같은 형식으로 레벨을 뒤에 붙인다.
    private func nameWithLevel(_ mon: MonState) -> String {
        "\(displayName(mon)) · Lv.\(mon.level)"
    }

    private func displayName(_ mon: MonState) -> String {
        mon.nickname.flatMap { $0.isEmpty ? nil : $0 }
            ?? mon.names?[mon.currentID]?[store.language.rawValue] ?? "#\(mon.currentID)"
    }

    private func statusText(_ status: AuctionOffer.Status) -> String {
        switch status {
        case .pending: return store.l.t("응답 대기", "Pending", "返信待ち")
        case .accepted: return store.l.t("교환 처리 중", "Trading", "交換中")
        case .declined: return store.l.t("거절함", "Rejected", "拒否済み")
        case .completed: return store.l.t("교환 완료", "Completed", "交換完了")
        case .failed: return store.l.t("교환 실패", "Failed", "交換失敗")
        }
    }

    /// 내가 건 제안 하나. 제안이 여러 건 동시에 서므로 어느 게시물의 제안인지를 카드가 말한다 —
    /// 예전 배너 하나는 "제안이 수락되어 교환 중입니다" 만 적어도 뜻이 통했다.
    private func outgoingCard(_ offer: OutgoingAuctionOffer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ProgressView().controlSize(.small).opacity(offer.status == .pending ? 1 : 0)
                SpriteView(speciesID: offer.listing.speciesID, size: 26, shiny: offer.listing.isShiny)
                VStack(alignment: .leading) {
                    Text(offer.listing.displayName).font(.caption.bold())
                    Text(offeredText(offer)).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(statusText(offer.status)).font(.caption2.bold()).foregroundStyle(.secondary)
                // 대기 중인 제안은 거둬들일 수 있어야 한다 — 그러지 않으면 제한 시간까지 그
                // 개체가 다른 제안에 묶여 있다.
                if offer.status == .pending {
                    Button(store.l.t("취소", "Cancel", "取消")) { center.cancelOutgoingOffer(offer.id) }
                        .controlSize(.small)
                } else {
                    Button(store.l.t("확인", "Done", "確認")) { center.clearOutgoingResult(offer.id) }
                        .controlSize(.small)
                }
            }
            if let error = offer.error {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }.padding(8).background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    /// 이 제안에 내가 무엇을 걸었는지. 제안이 여럿이면 게시물 이름만으로는 구별되지 않는다.
    private func offeredText(_ offer: OutgoingAuctionOffer) -> String {
        if let monID = offer.monID {
            // 성사되면 그 개체는 이미 내 것이 아니다 — 목록에서 못 찾으면 이름만 비운다.
            return mon(withID: monID).map(nameWithLevel)
                ?? store.l.t("내 포켓몬", "My Pokémon", "自分のポケモン")
        }
        return "\(offer.stardust.formatted()) \(store.l.t("별의모래", "Stardust", "ほしのすな"))"
    }

    /// 이미 게시물이나 내 제안이 받치고 있는 개체 — 새 제안의 후보에서 뺀다.
    private var committedMonIDs: Set<UUID> {
        Set(center.localListings.values.map { $0.mon.id })
            .union(center.outgoingOffers.filter { $0.status.isLive }.compactMap(\.monID))
    }

    /// 아직 어느 제안에도 약속하지 않은 별의모래. 에스크로는 수락 시점에 걷히므로 잔액만 보면
    /// 지킬 수 없는 제안을 여러 건 걸게 된다.
    private var unpledgedTokens: Int {
        let pledged = center.outgoingOffers
            .filter { !$0.stardustEscrowed && $0.status.isLive }
            .reduce(0) { $0 + $1.stardust }
        return max(0, store.availableTokens - pledged)
    }
}
