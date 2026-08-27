import SwiftUI

/// 친구 탭의 관문. 근거리 상호작용을 한곳에 모으고 배틀과 교환 중 무엇을 할지 먼저 고른다.
struct FriendView: View {
    enum Destination { case battle, trade }

    let store: CompanionStore
    let nav: PopoverNavigation
    @Environment(BattleCenter.self) private var battleCenter
    @State private var destination: Destination?
    @State private var revealsIncomingMessage = false

    var body: some View {
        Group {
            if hasHiddenIncomingMessage && !revealsIncomingMessage {
                privateMessageCard
            } else if battleCenter.phase != .ready {
                VStack(alignment: .leading, spacing: 10) {
                    if battleCenter.phase == .ready {
                        Button { destination = nil } label: {
                            Label(store.l.t("친구 메뉴", "Friends", "フレンドメニュー"),
                                  systemImage: "chevron.left")
                        }.buttonStyle(.borderless)
                    }
                    BattleView(store: store)
                }
            } else if destination == .trade || battleCenter.trading.phase != .ready {
                PokemonTradeView(store: store, center: battleCenter.trading) {
                    destination = nil
                }
            } else {
                chooser
            }
        }
        .onAppear {
            if battleCenter.phase != .ready { destination = .battle }
            if battleCenter.trading.phase != .ready { destination = .trade }
        }
        .onChange(of: battleCenter.trading.phase) { _, phase in
            if phase != .ready { destination = .trade }
            if case .incoming = phase { revealsIncomingMessage = false }
        }
        .onChange(of: battleCenter.phase) { _, phase in
            if case .incoming = phase { revealsIncomingMessage = false }
            if phase == .ready, destination == .battle { destination = nil }
        }
    }

    private var hasHiddenIncomingMessage: Bool {
        if case .incoming = battleCenter.phase { return true }
        if case .incoming = battleCenter.trading.phase { return true }
        return false
    }

    private var privateMessageCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope.badge.fill").font(.system(size: 42)).foregroundStyle(.blue)
            Text(store.l.t("메시지가 왔습니다", "You have a message", "メッセージが届きました"))
                .font(.headline)
            Text(store.l.t("내용은 확인 버튼을 누른 뒤 표시됩니다.",
                           "Details remain hidden until you choose to view them.",
                           "内容は確認ボタンを押すまで表示されません。"))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(store.l.t("메시지 확인", "View Message", "メッセージを確認")) {
                revealsIncomingMessage = true
                if case .incoming = battleCenter.trading.phase { destination = .trade }
                else { destination = .battle }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .pokedoroCard(tint: PokedoroTheme.blue, emphasized: true)
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            myTrainerCard
            VStack(alignment: .leading, spacing: 4) {
                Label(store.l.t("친구와 함께", "Play with Friends", "フレンドと遊ぶ"),
                      systemImage: "person.2.fill")
                    .font(.title3.bold())
                Text(store.l.t("같은 네트워크에 있는 트레이너와 즐길 활동을 선택하세요.",
                               "Choose what to do with a trainer on the same network.",
                               "同じネットワークのトレーナーと遊ぶ内容を選んでください。"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Picker("", selection: Binding(get: { battleCenter.rankedTeamSize },
                                           set: { battleCenter.rankedTeamSize = $0 })) {
                Text("1 vs 1").tag(1)
                Text("3 vs 3").tag(3)
                Text("6 vs 6").tag(6)
            }
            .pickerStyle(.segmented).labelsHidden()

            if battleCenter.peers.isEmpty {
                ContentUnavailableView(
                    store.l.t("근처 트레이너를 찾는 중…", "Looking for nearby trainers…", "近くのトレーナーを検索中…"),
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text(store.l.t("같은 네트워크에서 Pokédoro를 실행하면 여기에 표시됩니다.",
                                                "Trainers running Pokédoro on the same network appear here.",
                                                "同じネットワークでPokédoroを起動すると表示されます。")))
            } else {
                Text(store.l.t("근처 트레이너", "Nearby Trainers", "近くのトレーナー")).font(.headline)
                LazyVStack(spacing: 8) {
                    ForEach(battleCenter.peers) { peer in
                        trainerRow(peer)
                    }
                }
            }

        }
        .padding(.top, 4)
    }

    /// 내 트레이너 카드 — 친구 목록 맨 위에 둔다. 친구 행이 상대 착장을 보여주니, 내 착장도
    /// 여기서 바로 바꿀 수 있어야 대칭이 맞는다("꾸미기" 진입점이 상점 안에만 있으면 못 찾는다).
    private var myTrainerCard: some View {
        HStack(spacing: 8) {
            TrainerAvatarView(outfit: store.outfit, scale: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.hasTrainerName ? store.trainerName
                     : store.l.t("나", "You", "自分")).font(.headline).lineLimit(1)
                Text(store.l.t("트레이너 Lv.\(store.trainerLevel.level)",
                               "Trainer Lv.\(store.trainerLevel.level)",
                               "トレーナー Lv.\(store.trainerLevel.level)"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(store.l.outfitWardrobe) { nav.showOutfit = true }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func trainerRow(_ peer: BattlePeer) -> some View {
        let tradePeer = battleCenter.trading.peers.first {
            $0.name.localizedCaseInsensitiveCompare(peer.name) == .orderedSame
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TrainerAvatarView(outfit: peer.advertisement.outfit ?? TrainerOutfit())
                VStack(alignment: .leading, spacing: 4) {
                    Text(peer.name).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(peer.advertisement.rank?.displayName
                             ?? store.l.t("랭크 정보 없음", "Rank unavailable", "ランク情報なし"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(peer.advertisement.rank == nil ? Color.secondary : Color.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(peer.advertisement.rank == nil ? Color.gray.opacity(0.16) : Color.indigo,
                                        in: Capsule())
                            .fixedSize()
                        Text(peer.advertisement.trainerLevel.map {
                            store.l.t("트레이너 Lv.\($0)", "Trainer Lv.\($0)", "トレーナー Lv.\($0)")
                        } ?? store.l.t("레벨 정보 없음", "Level unavailable", "レベル情報なし"))
                        .font(.caption2).foregroundStyle(.secondary).fixedSize()
                    }
                }
                Spacer()
            }
            HStack {
                Button {
                    destination = .battle
                    battleCenter.challenge(peer)
                } label: {
                    Label(store.l.t("배틀 신청", "Battle", "バトル"), systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(store.isEgg || battleCenter.phase != .ready)

                Button {
                    guard let tradePeer else { return }
                    destination = .trade
                    battleCenter.trading.request(tradePeer)
                } label: {
                    Label(store.l.t("교환 신청", "Trade", "交換"), systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(.borderedProminent).tint(.blue)
                .disabled(tradePeer == nil)
                .help(tradePeer == nil
                      ? store.l.t("상대가 교환 기능을 지원하는 최신 버전인지 확인하세요.",
                                  "Ask them to update to a version that supports trading.",
                                  "相手が交換対応の最新版か確認してください。") : "")
            }
            .controlSize(.small)
        }
        .padding(10)
        .pokedoroCard(tint: PokedoroTheme.blue)
    }

}
