import SwiftUI

/// Pokédoro 전 화면이 공유하는 시각 언어. 밝은 필드, 선명한 빨강·파랑, 둥근 게임 카드로
/// 생산성 앱의 차분함과 몬스터 수집 게임의 활기를 함께 유지한다.
enum PokedoroTheme {
    static let red = Color(red: 0.72, green: 0.31, blue: 0.34)
    static let blue = Color(red: 0.30, green: 0.47, blue: 0.62)
    static let yellow = Color(red: 0.72, green: 0.61, blue: 0.34)
    static let mint = Color(red: 0.35, green: 0.57, blue: 0.49)
    static let ink = Color(red: 0.16, green: 0.20, blue: 0.26)

    static var pageBackground: some View {
        Color(nsColor: .windowBackgroundColor)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct PokedoroCardModifier: ViewModifier {
    var tint: Color
    var emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(emphasized ? tint.opacity(0.26) : Color.primary.opacity(0.075),
                                  lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func pokedoroCard(tint: Color = PokedoroTheme.blue, emphasized: Bool = false) -> some View {
        modifier(PokedoroCardModifier(tint: tint, emphasized: emphasized))
    }
}

struct PokedoroTabBar: View {
    @Binding var selection: PopoverTab
    let l: L

    private var tabs: [(PopoverTab, String, String)] {
        [
            (.home, l.home, "house.fill"),
            (.pokemon, l.t("포켓몬", "Pokémon", "ポケモン"), "circle.grid.cross.fill"),
            (.collection, l.collection, "book.closed.fill"),
            (.battle, l.t("친구", "Friends", "フレンド"), "person.2.fill"),
            (.challenge, l.t("도전", "Challenge", "チャレンジ"), "flag.checkered")
        ]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.0) { tab, title, icon in
                Button { withAnimation(.snappy(duration: 0.22)) { selection = tab } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: icon).font(.system(size: 14, weight: .bold))
                        Text(title).font(.system(size: 9, weight: .bold)).lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? PokedoroTheme.ink : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .contentShape(Rectangle())
                    .background(selection == tab
                                ? AnyShapeStyle(PokedoroTheme.blue.opacity(0.18))
                                : AnyShapeStyle(Color.clear),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(title)
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1).allowsHitTesting(false))
    }
}

/// 저작물 이미지를 쓰지 않고 도형만으로 만든 몬스터볼 모티프.
struct PokeBallMark: View {
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle().trim(from: 0, to: 0.5).fill(PokedoroTheme.red)
                .rotationEffect(.degrees(180))
            Rectangle().fill(PokedoroTheme.ink).frame(height: max(2, size * 0.11))
            Circle().fill(.white).frame(width: size * 0.34, height: size * 0.34)
                .overlay(Circle().stroke(PokedoroTheme.ink, lineWidth: max(2, size * 0.09)))
            Circle().stroke(PokedoroTheme.ink, lineWidth: max(1.5, size * 0.07))
        }
        .frame(width: size, height: size)
        .shadow(color: PokedoroTheme.ink.opacity(0.18), radius: 0, y: 1)
    }
}
