import SwiftUI

struct PokemonRosterView: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(store.language == .ko ? "소유 포켓몬" : "Owned Pokémon", systemImage: "square.grid.2x2.fill")
                    .font(.headline)
                Spacer()
                Text("\(store.boxedMons.count + (store.hasActive ? 1 : 0))")
                    .font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            if !store.ownedMons.isEmpty {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                        ForEach(store.ownedMons, id: \.id) { mon in
                            RosterMonCard(store: store, mon: mon, isActive: mon.id == store.activeMonID)
                        }
                    }
                }.frame(maxHeight: 260)
            }
            HStack {
                Button { nav.tab = .bag } label: { Label(store.l.bag, systemImage: "backpack.fill") }
                Spacer()
                if store.focusEggCount > 0 { Text("🥚 × \(store.focusEggCount)").font(.caption.bold()) }
            }.controlSize(.small)
        }
    }
}

private struct RosterMonCard: View {
    let store: CompanionStore
    let mon: MonState
    let isActive: Bool
    @State private var name = ""
    @State private var types: [PokemonType] = []

    var body: some View {
        Button { if !isActive { store.switchCompanion(to: mon.id) } } label: {
            VStack(spacing: 2) {
                SpriteView(speciesID: mon.currentID, size: 28, shiny: mon.isShiny)
                Text(name.isEmpty ? "#\(mon.currentID)" : name).font(.system(size: 10, weight: .bold)).lineLimit(1)
                Text("Lv.\(mon.level)").font(.system(size: 8)).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(types, id: \.self) { type in
                        Text(type.name(store.language).uppercased())
                            .font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(type.rosterColor, in: Capsule())
                    }
                }
                Text(isActive
                     ? (store.language == .ko ? "동행 중" : "Active")
                     : (store.language == .ko ? "교체" : "Switch"))
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(isActive ? .green : .secondary)
            }.frame(maxWidth: .infinity).padding(4)
        }.buttonStyle(.bordered).disabled(isActive)
        .task(id: mon.currentID) {
            name = await store.resolveSpeciesName(mon.currentID)
            types = (try? await PokeAPIClient.shared.battleProfile(speciesID: mon.currentID).types) ?? []
        }
    }
}

private extension PokemonType {
    var rosterColor: Color {
        switch self {
        case .normal: .gray; case .fire: .red; case .water: .blue; case .electric: .yellow
        case .grass: .green; case .ice: .cyan; case .fighting: .brown; case .poison: .purple
        case .ground: .orange; case .flying: .indigo; case .psychic: .pink; case .bug: .green
        case .rock: .brown; case .ghost: .purple; case .dragon: .indigo; case .dark: .black
        case .steel: .gray; case .fairy: .pink
        }
    }
}
