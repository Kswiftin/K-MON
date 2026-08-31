import SwiftUI

/// 친구 탭의 관문. 근거리 상호작용을 한곳에 모으고 배틀과 교환 중 무엇을 할지 먼저 고른다.
struct FriendView: View {
    enum Destination { case battle, trade, tournament, gym }
    @State private var representativeSearchText = ""
    @State private var showsRepresentativePicker = false

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
            // **관장인 것만으로는 화면을 붙잡지 않는다.** 관장은 도전을 기다리는 배경 상태지
            // 배틀 중이 아니다 — 그 내내 친구 탭을 잠그면 교환도 1:1 배틀도 못 한다(닫기를 눌러도
            // 조건이 계속 참이라 안 나가진다). 붙잡는 것은 **판이 실제로 돌 때**뿐이다.
            } else if destination == .gym || battleCenter.multiplayer.gymMatch != nil {
                PlayerGymView(store: store, center: battleCenter.multiplayer) { destination = nil }
            // 방이 켜졌다는 것만으로는 어느 화면인지 못 정한다 — 토너먼트와 체육관이 같은 방을
            // 쓰므로 **활동 종류로** 가른다. 체육관 방을 빼지 않으면 관장이 토너먼트 화면에 갇힌다.
            } else if destination == .tournament
                        || (battleCenter.multiplayer.phase != .idle && !battleCenter.multiplayer.isGymRoom) {
                PokemonTournamentView(store: store, center: battleCenter.multiplayer) { destination = nil }
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
            // 토너먼트는 방이 켜져 있으면 그 화면으로 돌아간다. 체육관은 **판이 돌 때만** 그렇게
            // 한다 — 관장이라는 이유로 되돌리면 다른 걸 하러 나올 수가 없다.
            if battleCenter.multiplayer.phase != .idle, !battleCenter.multiplayer.isGymRoom {
                destination = .tournament
            }
            if battleCenter.multiplayer.gymMatch != nil { destination = .gym }
        }
        // 도전이 들어와 판이 서면 체육관으로 데려간다 — 다른 화면을 보고 있으면 도전이 온 줄 모른다.
        .onChange(of: battleCenter.multiplayer.gymMatch == nil) { _, isIdle in
            if !isIdle { destination = .gym }
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

    /// "현우 — 25분째 유지중". 내가 관장이면 내 세이브에서, 아니면 **방 이름에 실린 값**에서 읽는다
    /// (방 광고에 TXT 가 없어 접속하지 않고 알 수 있는 통로가 이름뿐이다).
    /// 열린 체육관이 없으면 nil — 그땐 카드가 규칙 설명을 그린다.
    private var gymStatusLine: String? {
        if let held = store.gymLeadership?.heldSince {
            return store.l.playerGymTenure(
                store.state.trainerName,
                store.l.playerGymDuration(minutes: PlayerGym.tenureMinutes(since: held, now: Date())))
        }
        guard let room = battleCenter.multiplayer.visibleGymRoom,
              let parsed = PlayerGymRoomName.parse(room.serviceName) else { return nil }
        return store.l.playerGymTenure(
            parsed.leaderName,
            store.l.playerGymDuration(minutes: PlayerGym.tenureMinutes(since: parsed.heldSince, now: Date())))
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

            Button {
                destination = .gym
            } label: {
                HStack {
                    Image(systemName: "building.columns.fill").foregroundStyle(.purple)
                    VStack(alignment: .leading) {
                        Text(store.l.playerGymTitle).font(.headline)
                        // 열린 체육관이 있으면 "누가 몇 분째 지키는지"를 대신 보여준다 —
                        // 규칙 설명보다 지금 상태가 궁금한 자리다.
                        Text(gymStatusLine ?? store.l.playerGymSubtitle)
                            .font(.caption2)
                            // 두 가지가 `Color` 로 같아야 한다 — `.secondary` 는 다른 타입이라
                            // 삼항으로 섞으면 타입이 안 맞는다.
                            .foregroundStyle(gymStatusLine == nil ? Color.secondary : Color.purple)
                    }
                    Spacer(); Image(systemName: "chevron.right")
                }.padding(10).pokedoroCard(tint: .purple)
            }.buttonStyle(.plain)

            Button {
                destination = .tournament
            } label: {
                HStack {
                    Image(systemName: "trophy.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(store.l.t("3대3 포켓몬 토너먼트", "3-on-3 Pokémon Tournament", "3対3ポケモントーナメント"))
                            .font(.headline)
                        Text(store.l.t("최대 8명 · 경기 중이 아니면 실시간 관전", "Up to 8 · spectate every other match",
                                       "最大8人・対戦外はリアルタイム観戦"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "chevron.right")
                }.padding(10).pokedoroCard(tint: .orange)
            }.buttonStyle(.plain)

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
                BattleRankBadge(rank: store.battleRank)
            }
            Spacer()
            VStack(spacing: 4) {
                if let representative = store.battleRepresentative {
                    SpriteView(speciesID: representative.presentationID, size: 36,
                               shiny: representative.isShiny)
                }
                representativeMenu
                Button(store.l.outfitWardrobe) { nav.showOutfit = true }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var representativeMenu: some View {
        Button { showsRepresentativePicker.toggle() } label: {
            Label(store.l.t("대표 포켓몬", "Representative", "代表ポケモン"),
                  systemImage: "star.circle.fill")
        }
        .buttonStyle(.borderless).controlSize(.small)
        .popover(isPresented: $showsRepresentativePicker) { representativePicker }
    }

    private var representativePicker: some View {
        let mons = store.ownedMons.filter {
            PokemonNameSearch.matches(representativeSearchText, names: PokemonNameSearch.names(for: $0))
        }
        return VStack(alignment: .leading, spacing: 8) {
            PokemonSearchField(text: $representativeSearchText, l: store.l)
            Button(store.l.t("대표 포켓몬 없음", "No representative", "代表ポケモンなし")) {
                store.setBattleRepresentative(nil)
                showsRepresentativePicker = false
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(mons) { mon in
                        Button {
                            store.setBattleRepresentative(mon.id)
                            showsRepresentativePicker = false
                        } label: {
                            HStack {
                                SpriteView(speciesID: mon.presentationID, size: 28, shiny: mon.isShiny)
                                let name = RosterOrdering.displayName(mon, language: store.language)
                                Text("\(name) · Lv.\(mon.level)").lineLimit(1)
                                Spacer()
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).padding(3)
                    }
                }
            }
        }.padding(10).frame(width: 250, height: 300)
    }

    private func trainerRow(_ peer: BattlePeer) -> some View {
        let tradePeer = battleCenter.trading.peers.first {
            $0.name.localizedCaseInsensitiveCompare(peer.name) == .orderedSame
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TrainerAvatarView(outfit: peer.advertisement.outfit ?? TrainerOutfit())
                if let speciesID = peer.advertisement.representativeSpeciesID {
                    SpriteView(speciesID: speciesID, size: 34,
                               shiny: peer.advertisement.representativeIsShiny)
                        .help(store.l.t("대표 포켓몬", "Representative Pokémon", "代表ポケモン"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(peer.name).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        if let rank = peer.advertisement.rank {
                            BattleRankBadge(rank: rank)
                        } else {
                            Text(store.l.t("랭크 정보 없음", "Rank unavailable", "ランク情報なし"))
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.gray.opacity(0.16), in: Capsule()).fixedSize()
                        }
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
                    destination = .battle
                    battleCenter.challengeMetronome(peer)
                } label: {
                    Label(store.l.t("손가락흔들기", "Metronome", "ゆびをふる"),
                          systemImage: "hand.point.up.left.fill")
                }
                .buttonStyle(.borderedProminent).tint(.purple)
                .disabled(battleCenter.phase != .ready)
                .help(store.l.t("서로 동일한 Lv.50 대여 토게키스로 대결합니다.",
                                "Battle each other with identical Lv.50 rental Togekiss.",
                                "同じLv.50レンタルトゲキッスで対戦します。"))

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

                Button {
                    guard let tradePeer else { return }
                    destination = .trade
                    battleCenter.trading.viewRoster(tradePeer)
                } label: {
                    Label(store.l.t("포켓몬 보기", "View Pokémon", "ポケモンを見る"), systemImage: "eye.fill")
                }
                .buttonStyle(.bordered).disabled(tradePeer == nil)
            }
            .controlSize(.small)
        }
        .padding(10)
        .pokedoroCard(tint: PokedoroTheme.blue)
    }

}
