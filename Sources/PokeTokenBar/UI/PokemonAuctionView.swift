import SwiftUI

struct PokemonAuctionView: View {
    let store: CompanionStore
    let center: PokemonAuctionCenter
    let onClose: () -> Void
    @State private var selectedListingMonID: UUID?
    @State private var offerSelections: [UUID: UUID] = [:]
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.l.t("포켓몬 경매 시장", "Pokémon Offer Market", "ポケモン交換市場"),
                      systemImage: "storefront.fill").font(.title3.bold()).foregroundStyle(.orange)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Text(store.l.t("포켓몬을 하나 올리면 여러 트레이너가 교환 제안을 보낼 수 있습니다. 원하는 제안 하나만 수락하세요.",
                           "List one Pokémon, receive multiple offers, and accept the one you want.",
                           "1匹を出品し、複数の提案から好きなものを1つ選べます。"))
                .font(.caption).foregroundStyle(.secondary)
            myListing
            Divider()
            market
            if let error = center.lastError { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private var myListing: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(store.l.t("내 경매", "My Listing", "自分の出品")).font(.headline)
            if let listing = center.localListing {
                pokemonRow(listing.mon, name: listing.displayName)
                HStack {
                    Text(store.l.t("제안 \(center.offers.filter { $0.status == .pending }.count)건",
                                   "\(center.offers.filter { $0.status == .pending }.count) offer(s)",
                                   "提案 \(center.offers.filter { $0.status == .pending }.count)件"))
                        .font(.caption.bold()).foregroundStyle(.orange)
                    Spacer()
                    Button(store.l.t("게시 내리기", "Remove Listing", "出品を取り消す"), role: .destructive) {
                        center.cancelListing()
                    }.controlSize(.small)
                }
                ForEach(center.offers) { offer in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(offer.trainerName).font(.caption.bold())
                        pokemonRow(offer.pokemon.mon, name: offer.pokemon.displayName)
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
            } else {
                PokemonSearchField(text: $searchText, l: store.l)
                let mons = store.deployableMons.filter {
                    PokemonNameSearch.matches(searchText, names: PokemonNameSearch.names(for: $0))
                }
                Picker(store.l.t("게시할 포켓몬", "Pokémon to list", "出品するポケモン"), selection: $selectedListingMonID) {
                    Text(store.l.t("선택하세요", "Choose", "選択")).tag(UUID?.none)
                    ForEach(mons) { mon in
                        Text(displayName(mon)).tag(Optional(mon.id))
                    }
                }
                Button(store.l.t("경매 시장에 올리기", "List on Market", "市場に出品")) {
                    center.publish(store.deployableMons.first { $0.id == selectedListingMonID })
                    selectedListingMonID = nil
                }.buttonStyle(.bordered).disabled(selectedListingMonID == nil)
            }
        }.padding(9).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
    }

    private var market: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(store.l.t("근처 경매 목록", "Nearby Listings", "近くの出品" )).font(.headline)
            if let status = center.outgoingStatus {
                HStack {
                    ProgressView().controlSize(.small).opacity(status == .pending ? 1 : 0)
                    Text(outgoingText(status)).font(.caption.bold())
                    Spacer()
                    if status != .pending { Button(store.l.t("확인", "Done", "確認")) { center.clearOutgoingResult() } }
                }.padding(8).background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }
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
                        Picker(store.l.t("제안할 내 포켓몬", "Your offer", "自分の提案"),
                               selection: Binding(get: { offerSelections[listing.id] },
                                                  set: { offerSelections[listing.id] = $0 })) {
                            Text(store.l.t("선택하세요", "Choose", "選択")).tag(UUID?.none)
                            ForEach(store.deployableMons) { mon in
                                Text(displayName(mon)).tag(Optional(mon.id))
                            }
                        }
                        Button(store.l.t("교환 제안", "Send Offer", "交換を提案")) {
                            guard let id = offerSelections[listing.id],
                                  let mon = store.deployableMons.first(where: { $0.id == id }) else { return }
                            center.apply(to: listing, offering: mon)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(offerSelections[listing.id] == nil || center.outgoingStatus == .pending)
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

    private func outgoingText(_ status: AuctionOffer.Status) -> String {
        let name = center.outgoingListingName ?? store.l.t("포켓몬", "Pokémon", "ポケモン")
        switch status {
        case .pending: return store.l.t("\(name) 교환 제안 대기 중", "Offer for \(name) pending", "\(name)への提案を送信中")
        case .accepted: return store.l.t("제안이 수락되어 교환 중입니다.", "Offer accepted; trading…", "提案が承認され交換中です。")
        case .declined: return store.l.t("제안이 거절됐습니다.", "Offer rejected.", "提案が拒否されました。")
        case .completed: return store.l.t("경매 교환이 완료됐습니다!", "Market trade completed!", "市場の交換が完了しました！")
        case .failed: return store.l.t("교환을 완료하지 못했습니다.", "Trade could not be completed.", "交換を完了できませんでした。")
        }
    }
}
