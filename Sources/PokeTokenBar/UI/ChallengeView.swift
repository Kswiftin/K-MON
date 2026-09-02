import SwiftUI

/// 도전 탭 — **혼자 도전하는 콘텐츠를 한곳에 모은다.**
///
/// 체육관·던전은 친구가 필요 없는데 친구 탭 **두 단계 안**에 있었다(친구 → 배틀 → 버튼 줄).
/// 배틀 화면이 `FriendView` 아래로 한 겹 들어가면서 그 버튼 줄이 사실상 안 보이게 됐고,
/// 사용자가 "체육관이 사라졌다"고 보고했다. 자리를 옮기는 것으로 고친다 —
/// **친구 탭은 남과 하는 것, 도전 탭은 혼자 하는 것**이다.
///
/// 포켓슬론(체인지릴레이·포켓몬 OX)은 근거리 방을 쓰지만 혼자 연습도 되고, 성격이 "겨루는
/// 콘텐츠"라 같은 탭에 둔다. 탭을 새로 만드는 대신 포켓슬론 탭을 넓힌 이유는 탭바가 이미
/// 다섯 칸이어서다 — 여섯 칸이 되면 칸당 55pt 라 긴 라벨이 잘린다.
struct ChallengeView: View {
    let store: CompanionStore
    @Environment(BattleCenter.self) private var battleCenter
    @Environment(PopoverNavigation.self) private var nav
    @State private var showsAuction = false

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsAuction {
                PokemonAuctionView(store: store, center: battleCenter.auction) { showsAuction = false }
            } else {
            // 친구 탭의 토너먼트·배틀·공유 체육관도 같은 LAN 센터를 쓴다. 활동 종류를 보지 않고
            // `PokeathlonView` 를 그리면 도전 탭까지 "토너먼트 진행 중" 화면과 나가기 버튼을 공유해
            // 두 탭이 하나처럼 움직인다. 도전 탭 소유 활동(OX·포켓슬론)만 여기서 이어 그린다.
            if battleCenter.multiplayer.phase == .idle || !presentsPokeathlonContent {
                soloChallenges
            }
            if presentsPokeathlonContent { PokeathlonView(store: store) }
            }
        }
    }

    private var presentsPokeathlonContent: Bool {
        Self.presentsPokeathlon(phase: battleCenter.multiplayer.phase,
                                activity: battleCenter.multiplayer.roomActivity)
    }

    nonisolated static func presentsPokeathlon(phase: MultiplayerRoomCenter.Phase,
                                               activity: RoomActivity?) -> Bool {
        switch phase {
        case .idle, .pokeathlon, .pokemonQuiz:
            return true
        case .creating, .hosting, .joining, .joined:
            return activity == .pokeathlon || activity == .pokemonQuiz
        case .battling, .tournament:
            return false
        }
    }

    /// 혼자 도전 — 누르면 각자 전체 화면으로 열린다(`PopoverNavigation`).
    private var soloChallenges: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(l.t("혼자 도전", "Solo challenges", "ひとりで挑戦"), systemImage: "flag.fill")
                .font(.caption.weight(.semibold))
            HStack(spacing: 6) {
                Button { nav.showGymLeague = true } label: {
                    Label(l.gymLeagueTitle, systemImage: "building.columns.fill")
                }
                .controlSize(.small)
                Button { nav.showDungeon = true } label: {
                    Label(l.dungeonTitle, systemImage: "map.fill")
                }
                .controlSize(.small)
                Spacer(minLength: 4)
            }
            Divider().opacity(0.5)
            Button { showsAuction = true } label: {
                HStack {
                    Image(systemName: "storefront.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.t("포켓몬 경매 시장", "Pokémon Offer Market", "ポケモン交換市場"))
                            .font(.callout.bold())
                        Text(l.t("한 마리를 올리고 여러 교환 제안을 받아보세요.",
                                 "List one Pokémon and compare offers from nearby trainers.",
                                 "1匹を出品し、近くのトレーナーの提案を比べましょう。"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "chevron.right")
                }.padding(9).pokedoroCard(tint: .orange)
            }.buttonStyle(.plain)
            Divider().opacity(0.5)
        }
    }
}
