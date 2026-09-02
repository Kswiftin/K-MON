import SwiftUI

struct PokemonAuctionView: View {
    let store: CompanionStore
    let center: PokemonAuctionCenter
    let onClose: () -> Void
    @State private var selectedListingMonID: UUID?
    @State private var offerSelections: [UUID: UUID] = [:]
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
                // 즐겨찾기를 목록에서 빼지 않고 잠긴 줄로 보여 주려면 행마다 별 버튼이 필요하다 —
                // `Picker` 는 줄에 버튼을 못 달고 줄별 비활성도 안 돼서 팝오버 목록으로 바꿨다.
                Button {
                    showsListingPicker = true
                } label: {
                    Label(selectedListingMon.map(nameWithLevel)
                          ?? store.l.t("게시할 포켓몬 선택", "Choose a Pokémon to list", "出品するポケモンを選ぶ"),
                          systemImage: "chevron.down")
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showsListingPicker) {
                    MonOfferPicker(store: store, mons: store.deployableMons) { mon in
                        selectedListingMonID = mon.id
                        showsListingPicker = false
                    }
                }
                Button(store.l.t("경매 시장에 올리기", "List on Market", "市場に出品")) {
                    center.publish(selectedListingMon)
                    selectedListingMonID = nil
                }.buttonStyle(.bordered).disabled(selectedListingMon == nil)
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
                        let offered = offerSelections[listing.id].flatMap(mon(withID:))
                        Button {
                            offerPickerListingID = listing.id
                        } label: {
                            Label(offered.map(nameWithLevel)
                                  ?? store.l.t("제안할 내 포켓몬 선택", "Choose your offer", "提案するポケモンを選ぶ"),
                                  systemImage: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: offerPickerBinding(for: listing.id)) {
                            MonOfferPicker(store: store, mons: store.deployableMons) { mon in
                                offerSelections[listing.id] = mon.id
                                offerPickerListingID = nil
                            }
                        }
                        Button(store.l.t("교환 제안", "Send Offer", "交換を提案")) {
                            if let offered { center.apply(to: listing, offering: offered) }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(offered == nil || center.outgoingStatus == .pending)
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
