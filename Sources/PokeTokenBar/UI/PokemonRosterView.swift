import SwiftUI

/// 소유 포켓몬 — 도감과 같은 페이지식 고정 격자(3열×5행).
///
/// 스크롤을 쓰지 않는 이유는 도감(`DexGridView`)과 같다. 팝오버 본체가 이미 ScrollView 라
/// 여기에 또 하나를 두면 중첩이 되고, 안쪽은 스크롤되지 않아 한 화면에 들어가는 만큼만 보이고
/// 나머지는 **볼 방법이 없었다**(21마리째부터 도달 불가). 예전엔 격자에 260 을 걸어 9마리쯤에서,
/// 그 뒤 520 으로 늘려 20마리쯤에서 끊겼다 — 잘리는 지점만 옮겼을 뿐 같은 결함이었다.
struct PokemonRosterView: View {
    let store: CompanionStore
    @State private var page = 0

    /// 도감·상점·가방과 같은 520. 탭을 넘나들어도 팝오버가 리사이즈되지 않는다.
    private static let contentHeight: CGFloat = 520
    private static let columns = 3
    private static let rows = 5
    /// 한 페이지 15칸. 격자에 주어지는 세로(520 − 헤더 − 페이저 − 간격 ≈ 468)를 5행이 나누면
    /// 행이 약 90pt 라 카드(스프라이트 28 + 이름·레벨·타입·상태)가 찌그러지지 않는다.
    static let pageSize = columns * rows
    private static let spacing: CGFloat = 5

    /// 마지막 페이지가 덜 차도 한 페이지다. 한 마리도 없으면 빈 격자 한 장.
    static func pageCount(ownedCount: Int) -> Int {
        max(1, (ownedCount + pageSize - 1) / pageSize)
    }

    var body: some View {
        let owned = store.ownedMons
        let pageCount = Self.pageCount(ownedCount: owned.count)
        // 졸업·방출로 마릿수가 줄면 보던 페이지가 사라진다 — 범위 밖이면 마지막 페이지로 당긴다.
        let current = min(page, pageCount - 1)
        let slice = Array(owned.dropFirst(current * Self.pageSize).prefix(Self.pageSize))
        VStack(alignment: .leading, spacing: 6) {
            header(ownedCount: owned.count)
            grid(slice)
            footer(current: current, pageCount: pageCount)
        }
        .frame(height: Self.contentHeight, alignment: .top)
    }

    private func header(ownedCount: Int) -> some View {
        HStack {
            Label(store.language == .ko ? "소유 포켓몬" : "Owned Pokémon", systemImage: "square.grid.2x2.fill")
                .font(.headline)
            Spacer()
            Text("\(ownedCount)")
                .font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
    }

    /// 도감과 같은 이유로 행마다 maxHeight 를 건다 — 빈 칸의 Color 는 유연 크기라, 행에 안 걸면
    /// 빈 행이 늘어나 채워진 행을 짓누른다(마지막 페이지가 한 줄뿐일 때 그 줄이 찌그러짐).
    private func grid(_ slice: [MonState]) -> some View {
        VStack(spacing: Self.spacing) {
            ForEach(0..<Self.rows, id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(0..<Self.columns, id: \.self) { column in
                        let index = row * Self.columns + column
                        if index < slice.count {
                            let mon = slice[index]
                            RosterMonCard(store: store, mon: mon, isActive: mon.id == store.activeMonID)
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// 하단 한 줄 — 왼쪽은 모아둔 알, 오른쪽은 페이저. 페이저가 1페이지라 안 보일 때도 이 줄을
    /// 항상 예약한다(도감과 같은 규칙) — 페이지 수에 따라 격자 높이가 흔들리지 않게.
    private func footer(current: Int, pageCount: Int) -> some View {
        HStack(spacing: 8) {
            if store.focusEggCount > 0 {
                Text("🥚 × \(store.focusEggCount)").font(.caption.bold())
            }
            Spacer(minLength: 4)
            if pageCount > 1 {
                Button { page = max(0, current - 1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).disabled(current == 0)
                    .accessibilityLabel(store.l.dexPagePrev)
                Text("\(current + 1) / \(pageCount)")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(store.l.dexPageLabel(current + 1, pageCount))
                Button { page = min(pageCount - 1, current + 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).disabled(current == pageCount - 1)
                    .accessibilityLabel(store.l.dexPageNext)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .frame(height: 18)
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
