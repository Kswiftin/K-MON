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

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 방이 돌아가는 중에는 감춘다. 그 화면은 자기 콘텐츠로 꽉 차 있고, 여기서 다른 데로
            // 빠져나가는 문을 열어 두면 진행 중인 방을 두고 나가게 된다.
            if battleCenter.multiplayer.phase == .idle { soloChallenges }
            PokeathlonView(store: store)
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
        }
    }
}
