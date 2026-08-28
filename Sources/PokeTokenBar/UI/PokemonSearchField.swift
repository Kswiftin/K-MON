import SwiftUI

struct PokemonSearchField: View {
    @Binding var text: String
    let l: L

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(l.t("포켓몬 이름 검색", "Search Pokémon by name", "ポケモン名で検索"), text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l.t("검색어 지우기", "Clear search", "検索をクリア"))
            }
        }
        .font(.caption)
        .padding(.horizontal, 8).frame(height: 26)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.18)))
    }
}
