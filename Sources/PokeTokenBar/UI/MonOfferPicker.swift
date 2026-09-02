import SwiftUI

/// 내보낼 포켓몬을 고르는 목록 — 교환·경매 게시·경매 제안 세 곳이 함께 쓴다.
///
/// **즐겨찾기는 목록에서 빼지 않는다.** 빼 버리면 "왜 얘가 없지"가 되고, 없어진 줄에서는 별을 끌
/// 수도 없어 잠금을 푸는 방법이 화면에 남지 않는다. 대신 별을 단 채로 흐리게 보여주고 **선택만**
/// 막는다 — 별을 끄는 즉시 그 줄이 눌린다.
///
/// 별 버튼은 행 버튼 **안**이 아니라 옆에 둔다. 중첩하면 바깥 버튼이 탭을 먹어 잠긴 줄의 별이
/// 영영 안 눌리고, 그러면 잠금을 푸는 유일한 자리가 사라진다.
struct MonOfferPicker: View {
    let store: CompanionStore
    /// 고를 수 있는 후보 — 호출부가 체육관 배치 같은 자기 사정으로 미리 좁힌다.
    /// 즐겨찾기는 여기서 빼지 않는다(그게 이 화면이 하는 일이다).
    let mons: [MonState]
    let onSelect: (MonState) -> Void
    @State private var searchText = ""

    var body: some View {
        let matches = mons.filter {
            PokemonNameSearch.matches(searchText, names: PokemonNameSearch.names(for: $0))
        }
        return VStack(alignment: .leading, spacing: 8) {
            PokemonSearchField(text: $searchText, l: store.l)
            if matches.contains(where: { store.isFavorite($0.id) }) {
                Text(store.l.favoriteLockedHint)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(matches, id: \.id) { row($0) }
                }
            }
        }
        .padding(10).frame(width: 260, height: 320)
    }

    private func row(_ mon: MonState) -> some View {
        let favorited = store.isFavorite(mon.id)
        return HStack(spacing: 4) {
            Button { onSelect(mon) } label: {
                HStack {
                    SpriteView(speciesID: mon.presentationID, size: 30, shiny: mon.isShiny)
                    Text(label(mon)).lineLimit(1)
                    Spacer()
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(favorited)
            .opacity(favorited ? 0.45 : 1)
            Button { store.toggleFavorite(mon.id) } label: {
                Image(systemName: favorited ? "star.fill" : "star")
                    .foregroundStyle(favorited ? Color.yellow : .secondary)
            }
            .buttonStyle(.borderless).controlSize(.mini)
            .accessibilityLabel(favorited ? store.l.unfavorite : store.l.favorite)
        }
        .padding(4)
    }

    private func label(_ mon: MonState) -> String {
        let name = mon.nickname ?? mon.names?[mon.currentID]?[store.language.rawValue] ?? "#\(mon.currentID)"
        return "\(name) · Lv.\(mon.level)"
    }
}
