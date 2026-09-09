import SwiftUI

/// 도전 탭 — **혼자 도전하는 콘텐츠를 한곳에 모은다.**
///
/// 체육관·던전은 친구가 필요 없는데 친구 탭 **두 단계 안**에 있었다(친구 → 배틀 → 버튼 줄).
/// 배틀 화면이 `FriendView` 아래로 한 겹 들어가면서 그 버튼 줄이 사실상 안 보이게 됐고,
/// 사용자가 "체육관이 사라졌다"고 보고했다. 자리를 옮기는 것으로 고친다 —
/// **친구 탭은 남과 하는 것, 도전 탭은 혼자 하는 것**이다.
///
/// 레이드는 "혼자 도전"이 아니라 별도 이웃 묶음(`neighborChallenges`)에 둔다 — 이웃이
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
                soloChallenges
                neighborChallenges
            }
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
                          subtitle: "벌판을 걸어 다니며 미끼·진흙·볼·도망으로 야생 포켓몬을 잡으세요.") {
                nav.showSafariZone = true
            }
            challengeCard(title: "포켓몬 경매 시장",
                          systemImage: "storefront.fill", tint: .orange,
                          subtitle: "한 마리를 올리고 여러 교환 제안을 받아보세요.") { nav.showAuction = true }
        }
    }

    /// 레이드는 이웃이 있으면 협동, 없으면 1★ 솔로라 순수 혼자용과 묶지 않는다.
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
