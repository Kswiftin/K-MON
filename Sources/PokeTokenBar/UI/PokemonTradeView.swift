import SwiftUI

struct PokemonTradeView: View {
    let store: CompanionStore
    let center: PokemonTradeCenter
    let onClose: () -> Void
    @State private var remoteSearchText = ""
    @State private var offerSearchText = ""
    @State private var showsOfferPicker = false

    init(store: CompanionStore, center: PokemonTradeCenter, onClose: @escaping () -> Void = {}) {
        self.store = store
        self.center = center
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label(store.l.t("포켓몬 교환", "Pokémon Trade", "ポケモン交換"),
                      systemImage: "arrow.left.arrow.right.circle.fill")
                    .font(.title3.bold())
                Spacer()
                Button { close() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Divider()
            content
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var content: some View {
        switch center.phase {
        case .ready:
            peerList
        case .browsing(let peer):
            waiting(title: store.l.t("\(peer)님의 포켓몬을 불러오는 중…",
                                     "Loading \(peer)'s Pokémon…", "\(peer)のポケモンを読み込み中…"))
        case .roster(let peer):
            rosterPreview(peer: peer)
        case .requesting(let peer):
            waiting(title: store.l.t("\(peer)님에게 교환 신청 중", "Requesting a trade with \(peer)", "\(peer)に交換を申請中"))
        case .incoming(let peer):
            VStack(spacing: 18) {
                Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 48)).foregroundStyle(.blue)
                Text(store.l.t("\(peer)님의 교환 신청", "Trade request from \(peer)", "\(peer)からの交換申請"))
                    .font(.headline)
                HStack {
                    Button(store.l.t("거절", "Decline", "断る"), role: .cancel) { center.decline() }
                    Button(store.l.t("수락", "Accept", "受ける")) { center.accept() }.buttonStyle(.borderedProminent)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .negotiating(let peer):
            negotiation(peer: peer)
        case .committing:
            waiting(title: store.l.t("교환 정보를 확인하는 중…", "Verifying trade…", "交換内容を確認中…"), cancellable: false)
        case .animating:
            TradeAnimationView(sent: center.localOffer, received: center.remoteOffer) { center.finishAnimation() }
        case .completed:
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 52)).foregroundStyle(.green)
                Text(store.l.t("교환 완료!", "Trade complete!", "交換完了！")).font(.title2.bold())
                if let received = center.remoteOffer {
                    Text(store.l.t("\(received.displayName)이(가) 동료가 되었습니다.",
                                   "\(received.displayName) joined you.",
                                   "\(received.displayName)が仲間になりました。"))
                }
                Button(store.l.t("확인", "Done", "完了")) { close() }.buttonStyle(.borderedProminent)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 42)).foregroundStyle(.orange)
                Text(message)
                Button(store.l.t("닫기", "Close", "閉じる")) { close() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rosterPreview(peer: String) -> some View {
        let roster = center.remoteRoster.filter {
            PokemonNameSearch.matches(remoteSearchText, names: [$0.displayName] +
                                      PokemonNameSearch.names(for: $0.mon))
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text(store.l.t("\(peer)님의 포켓몬", "\(peer)'s Pokémon", "\(peer)のポケモン"))
                .font(.headline)
            PokemonSearchField(text: $remoteSearchText, l: store.l)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 8) {
                    ForEach(roster, id: \.mon.id) { entry in
                        VStack(spacing: 4) {
                            SpriteView(speciesID: entry.mon.presentationID, size: 48,
                                       shiny: entry.mon.isShiny)
                            Text(entry.displayName).font(.caption.bold()).lineLimit(1)
                            Text("Lv.\(entry.mon.level)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(8).frame(maxWidth: .infinity)
                        .pokedoroCard()
                    }
                }
            }
            Button(store.l.t("돌아가기", "Back", "戻る")) { close() }
        }
    }

    private var peerList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.l.t("근처 트레이너", "Nearby Trainers", "近くのトレーナー")).font(.headline)
            Text(store.l.t("같은 네트워크에서 앱을 실행 중인 트레이너에게 신청하세요.",
                           "Choose a trainer running the app on the same network.",
                           "同じネットワークでアプリを起動中のトレーナーを選んでください。"))
                .font(.caption).foregroundStyle(.secondary)
            if center.peers.isEmpty {
                ContentUnavailableView(store.l.t("트레이너를 찾는 중…", "Looking for trainers…", "トレーナーを検索中…"),
                                       systemImage: "dot.radiowaves.left.and.right")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(center.peers) { peer in
                            HStack {
                                Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.blue)
                                Text(peer.name).font(.headline)
                                Spacer()
                                Button(store.l.t("교환 신청", "Request", "申請")) { center.request(peer) }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                            }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    private func waiting(title: String, cancellable: Bool = true) -> some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text(title).font(.headline)
            if cancellable { Button(store.l.t("취소", "Cancel", "キャンセル")) { center.cancel() } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func negotiation(peer: String) -> some View {
        let remoteRoster = center.remoteRoster.filter {
            PokemonNameSearch.matches(remoteSearchText, names: [$0.displayName] +
                                      PokemonNameSearch.names(for: $0.mon))
        }
        return VStack(spacing: 12) {
            Text(store.l.t("\(peer)님과 교환", "Trading with \(peer)", "\(peer)と交換"))
                .font(.headline)
            HStack(spacing: 14) {
                offerCard(title: store.l.t("내 포켓몬", "Your Pokémon", "自分のポケモン"),
                          offer: center.localOffer, confirmed: center.localConfirmed, isMine: true)
                Image(systemName: "arrow.left.arrow.right").font(.title2.bold()).foregroundStyle(.blue)
                offerCard(title: store.l.t("상대 포켓몬", "Their Pokémon", "相手のポケモン"),
                          offer: center.remoteOffer, confirmed: center.remoteConfirmed, isMine: false)
            }
            if !center.remoteRoster.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.l.t("상대에게 원하는 포켓몬 요청", "Request a Pokémon",
                                   "相手に希望ポケモンを伝える"))
                        .font(.caption.bold())
                    PokemonSearchField(text: $remoteSearchText, l: store.l)
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(remoteRoster, id: \.mon.id) { entry in
                                Button {
                                    center.requestRemotePokemon(entry.mon.id)
                                } label: {
                                    VStack(spacing: 2) {
                                        SpriteView(speciesID: entry.mon.presentationID, size: 34,
                                                   shiny: entry.mon.isShiny)
                                        Text(entry.displayName).font(.system(size: 8, weight: .semibold)).lineLimit(1)
                                    }
                                    .padding(5).frame(width: 70)
                                    .background(center.requestedRemoteMonID == entry.mon.id
                                                ? Color.blue.opacity(0.16) : Color.secondary.opacity(0.05),
                                                in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            if let wanted = center.remoteRequestedLocalMonID,
               let entry = store.ownedMons.first(where: { $0.id == wanted }) {
                HStack {
                    Text(store.l.t("상대가 원하는 포켓몬: \(monLabel(entry))",
                                   "They requested: \(monLabel(entry))",
                                   "相手の希望: \(monLabel(entry))"))
                        .font(.caption.bold())
                    Spacer()
                    Button(store.l.t("올려두기", "Offer", "提示する")) { center.offerRequestedPokemon() }
                        .controlSize(.small).buttonStyle(.bordered)
                }
            }
            Text(store.l.t("포켓몬을 바꾸면 두 사람의 확인이 모두 해제됩니다.",
                           "Changing an offer clears both confirmations.",
                           "ポケモンを変更すると双方の確認が解除されます。"))
                .font(.caption).foregroundStyle(.secondary)
            BattleChatPanel(configuration: BattleChatConfiguration(
                messages: center.chatMessages,
                mySenderID: center.chatSenderID,
                isEnabled: center.peerSupportsChat,
                unavailableMessage: center.peerSupportsChat ? nil : store.l.battleChatUnavailable,
                l: store.l,
                onSend: { center.sendChat($0) }))
            HStack {
                Button(store.l.t("교환 취소", "Cancel Trade", "交換をやめる"), role: .cancel) { center.cancel() }
                Spacer()
                Button(center.localConfirmed
                       ? store.l.t("확인 완료", "Confirmed", "確認済み")
                       : store.l.t("이 내용으로 교환", "Confirm Trade", "この内容で交換")) {
                    center.confirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(center.localOffer == nil || center.remoteOffer == nil || center.localConfirmed)
            }
        }
    }

    private func offerCard(title: String, offer: TradePokemonSnapshot?, confirmed: Bool, isMine: Bool) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            if let offer {
                SpriteView(speciesID: offer.mon.currentID, size: 72, shiny: offer.mon.isShiny)
                Text(offer.displayName).font(.headline).lineLimit(1)
                Text("Lv.\(offer.mon.level)\(offer.mon.isShiny ? " ✨" : "")").font(.caption)
            } else {
                Image(systemName: "questionmark").font(.system(size: 42)).foregroundStyle(.tertiary).frame(height: 76)
                Text(store.l.t("선택 전", "Not selected", "未選択")).foregroundStyle(.secondary)
            }
            if isMine {
                Button { showsOfferPicker.toggle() } label: {
                    Label(store.l.t("포켓몬 선택", "Choose Pokémon", "ポケモンを選ぶ"),
                          systemImage: "chevron.down")
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showsOfferPicker) { offerPicker }
            }
            Label(confirmed ? store.l.t("확인 완료", "Confirmed", "確認済み")
                            : store.l.t("확인 대기", "Waiting", "確認待ち"),
                  systemImage: confirmed ? "checkmark.circle.fill" : "clock")
                .font(.caption.bold()).foregroundStyle(confirmed ? .green : .secondary)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 230)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }

    private var offerPicker: some View {
        let mons = store.ownedMons.filter {
            PokemonNameSearch.matches(offerSearchText, names: PokemonNameSearch.names(for: $0))
        }
        return VStack(alignment: .leading, spacing: 8) {
            PokemonSearchField(text: $offerSearchText, l: store.l)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(mons, id: \.id) { mon in
                        Button {
                            center.selectOffer(mon)
                            showsOfferPicker = false
                        } label: {
                            HStack {
                                SpriteView(speciesID: mon.presentationID, size: 30, shiny: mon.isShiny)
                                Text(monLabel(mon)).lineLimit(1)
                                Spacer()
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).padding(4)
                    }
                }
            }
        }
        .padding(10).frame(width: 250, height: 300)
    }

    private func monLabel(_ mon: MonState) -> String {
        let name = mon.nickname ?? mon.names?[mon.currentID]?[store.language.rawValue] ?? "#\(mon.currentID)"
        return "\(name) · Lv.\(mon.level)"
    }

    private func close() {
        center.closeCompleted()
        onClose()
    }
}

private struct TradeAnimationView: View {
    let sent: TradePokemonSnapshot?
    let received: TradePokemonSnapshot?
    let completion: () -> Void
    @State private var crossed = false
    @State private var revealed = false
    @State private var flash = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [.blue.opacity(0.55), .indigo.opacity(0.95), .black], center: .center,
                           startRadius: 10, endRadius: 310).ignoresSafeArea()
            Circle().stroke(.white.opacity(flash ? 0.75 : 0.15), lineWidth: flash ? 9 : 2)
                .frame(width: flash ? 260 : 90).animation(.easeOut(duration: 0.6), value: flash)
            HStack {
                tradeOrb(label: sent?.displayName ?? "", snapshot: revealed ? received : nil)
                    .offset(x: crossed ? 245 : 0, y: crossed ? -45 : 35)
                Spacer()
                tradeOrb(label: received?.displayName ?? "", snapshot: revealed ? sent : nil)
                    .offset(x: crossed ? -245 : 0, y: crossed ? 45 : -35)
            }.padding(.horizontal, 55)
            if flash { Image(systemName: "sparkles").font(.system(size: 72)).foregroundStyle(.yellow) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            withAnimation(.easeInOut(duration: 1.25)) { crossed = true }
            try? await Task.sleep(for: .seconds(1.25))
            withAnimation(.easeOut(duration: 0.45)) { flash = true }
            try? await Task.sleep(for: .milliseconds(400))
            revealed = true
            try? await Task.sleep(for: .milliseconds(650))
            completion()
        }
    }

    private func tradeOrb(label: String, snapshot: TradePokemonSnapshot?) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(.white).frame(width: 82, height: 82)
                    .shadow(color: .cyan.opacity(0.9), radius: 18)
                if let snapshot {
                    SpriteView(speciesID: snapshot.mon.currentID, size: 62, shiny: snapshot.mon.isShiny)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "circle.bottomhalf.filled").font(.system(size: 55)).foregroundStyle(.red)
                }
            }
            Text(label).font(.caption.bold()).foregroundStyle(.white).lineLimit(1)
        }
    }
}
