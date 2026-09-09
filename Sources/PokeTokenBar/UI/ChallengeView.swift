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
///
/// 레이드도 같은 이유로 "혼자 도전"이 아니라 포켓슬론 옆(`neighborChallenges`)에 둔다 — 이웃이
/// 있으면 협동, 없으면 1★ 솔로라 체육관·던전처럼 순수 혼자용이 아니다. 진입 카드(체육관·던전·
/// 레이드·경매)는 친구 탭이 이미 쓰는 아이콘+제목+부제+화살표(`pokedoroCard`) 모양으로 통일한다.
struct ChallengeView: View {
    let store: CompanionStore
    @Environment(BattleCenter.self) private var battleCenter
    @Environment(PopoverNavigation.self) private var nav

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if nav.showAuction {
                PokemonAuctionView(store: store, center: battleCenter.auction) { nav.showAuction = false }
            } else {
            // 친구 탭의 토너먼트·배틀·공유 체육관도 같은 LAN 센터를 쓴다. 활동 종류를 보지 않고
            // `PokeathlonView` 를 그리면 도전 탭까지 "토너먼트 진행 중" 화면과 나가기 버튼을 공유해
            // 두 탭이 하나처럼 움직인다. 도전 탭 소유 활동(OX·포켓슬론)만 여기서 이어 그린다.
            if battleCenter.multiplayer.phase == .idle || !presentsPokeathlonContent {
                soloChallenges
                // 레이드는 이웃이 있으면 협동, 없으면 1★ 솔로다 — 체육관·던전처럼 순수 혼자용이
                // 아니라 포켓슬론과 같은 "LAN 방을 쓰되 혼자도 되는" 부류라 그 옆에 묶는다.
                neighborChallenges
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
            // 레이드 방은 `RaidView` 소유다 — 여기서 참으로 두면 도전 탭이 레이드 로비 위에
            // 포켓슬론 화면을 덮는다(`.gym`·`.tournament` 를 뺀 이유와 같다).
            return activity == .pokeathlon || activity == .pokemonQuiz
        case .battling, .tournament:
            return false
        }
    }

    /// 혼자 도전 — 누르면 각자 전체 화면으로 열린다(`PopoverNavigation`).
    private var soloChallenges: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("혼자 도전", systemImage: "flag.fill")
                .font(.caption.weight(.semibold))
            challengeCard(title: l.gymLeagueTitle, systemImage: "building.columns.fill", tint: .purple,
                          subtitle: "체육관을 차례로 돌며 배지를 모으세요.") { nav.showGymLeague = true }
            challengeCard(title: l.dungeonTitle, systemImage: "map.fill", tint: .red,
                          subtitle: "무작위로 이어지는 웨이브를 오르는 로그라이크 런.") { nav.showDungeon = true }
            challengeCard(title: l.safariZoneTitle, systemImage: "leaf.fill", tint: .green,
                          subtitle: "미끼·진흙·볼·도망으로 야생을 잡는 그레이트 마쉬식 산책.") {
                nav.showSafariZone = true
            }
            challengeCard(title: "포켓몬 경매 시장",
                          systemImage: "storefront.fill", tint: .orange,
                          subtitle: "한 마리를 올리고 여러 교환 제안을 받아보세요.") { nav.showAuction = true }
        }
    }

    /// 레이드는 이웃이 있으면 협동, 없으면 1★ 솔로다 — 포켓슬론과 같은 "LAN 방을 쓰되 혼자도
    /// 되는" 부류라 포켓슬론 바로 위에 묶는다. `soloChallenges` 와 같은 조건으로만 그려지므로
    /// (`body` 참고) 포켓슬론이 실제로 안 그려지는 경우에도 이 묶음만 남을 수 있다 — 그럴 때도
    /// 헤딩 아래 카드가 하나는 있어야 하므로 비워 두지 않는다.
    private var neighborChallenges: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("이웃과 함께", systemImage: "person.2.wave.2.fill")
                .font(.caption.weight(.semibold))
            challengeCard(title: l.raidTitle, systemImage: "person.3.sequence.fill", tint: .teal,
                          subtitle: "오전·오후 보스에 혼자, 또는 이웃과 함께 도전하세요.") { nav.showRaid = true }
        }
    }

    private func challengeCard(title: String, systemImage: String, tint: Color, subtitle: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.bold())
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "chevron.right")
            }.padding(9).pokedoroCard()
        }.buttonStyle(.plain)
    }
}
