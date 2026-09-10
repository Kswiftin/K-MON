import SwiftUI

/// Pokédoro 전 화면이 공유하는 시각 언어. 밝은 필드, 선명한 빨강·파랑, 둥근 게임 카드로
/// 생산성 앱의 차분함과 몬스터 수집 게임의 활기를 함께 유지한다.
enum PokedoroTheme {
    static let red = Color(red: 0.72, green: 0.31, blue: 0.34)
    static let blue = Color(red: 0.30, green: 0.47, blue: 0.62)
    static let yellow = Color(red: 0.72, green: 0.61, blue: 0.34)
    static let mint = Color(red: 0.35, green: 0.57, blue: 0.49)
    static let ink = Color(red: 0.16, green: 0.20, blue: 0.26)

    /// 읽는 글자의 최소 크기. macOS 의 가장 작은 텍스트 스타일(`caption2` = 10pt)이 하한이고,
    /// 그 아래는 읽는 글자가 아니라 표식일 때만 허용한다(`badgeFont` · `glyphFont`).
    ///
    /// macOS 에는 Dynamic Type 이 없다 — `dynamicTypeSize` 를 키워도 `.caption2` 조차 안 커진다
    /// (접근성 텍스트 크기는 `com.apple.universalaccess` 의 `FontSizeCategory` 에 등록한 앱에만
    /// 걸린다). 그러니 사용자가 키울 방법이 없고, 우리가 정한 크기가 곧 사용자가 보는 크기다.
    static let minimumTextSize: CGFloat = 10

    /// 캡슐 배지 · 스프라이트 위 표식 전용 크기. 읽는 문장이 아니라 한두 단어짜리 표식이라
    /// 10pt 하한 밖에 둔다 — 자리가 고정폭(체육관 타입 캡슐은 42pt)이라 키우면 글자가 잘린다.
    static func badgeFont(size: CGFloat = 8, weight: Font.Weight = .bold,
                          design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    /// 글자가 아니라 그림인 자리(SF Symbol · 이모지 표식)의 크기. 여기서는 pt 가 글자 크기가
    /// 아니라 그림 크기라 하한을 적용하지 않는다.
    static func glyphFont(size: CGFloat, weight: Font.Weight = .regular,
                          design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    static var pageBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

extension BattleRankTier {
    var tint: Color {
        switch self {
        case .pokeBall:   return Color(red: 0.72, green: 0.31, blue: 0.34)
        case .greatBall:  return Color(red: 0.25, green: 0.50, blue: 0.72)
        case .ultraBall:  return Color(red: 0.76, green: 0.59, blue: 0.16)
        case .masterBall: return Color(red: 0.52, green: 0.35, blue: 0.68)
        case .champion:   return Color(red: 0.73, green: 0.48, blue: 0.12)
        }
    }
}

struct BattleRankBadge: View {
    let rank: BattleRank

    var body: some View {
        Text(rank.displayName)
            .font(PokedoroTheme.badgeFont(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(rank.tier.tint, in: Capsule())
            .fixedSize()
    }
}

private struct PokedoroCardModifier: ViewModifier {
    var emphasis: Color?

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(emphasis?.opacity(0.26) ?? Color.primary.opacity(0.075),
                                  lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// 게임 카드 한 장. **강조 예산은 한 화면에 하나다** — `emphasis` 를 주면 테두리가 그 색을
    /// 띠고, 그 순간 그 카드가 화면에서 "지금 여기를 보라" 고 말하는 유일한 카드여야 한다.
    /// 색은 **상태 신호**일 때만 준다(집중 중 빨강 · 휴식 중 파랑). 상시 강조는 강조가 아니다 —
    /// 카드 넷이 저마다 색 테두리를 두르면 어디를 봐야 할지가 사라진다.
    ///
    /// 색을 장식으로 넘기는 자리를 없애려고 `emphasis` 하나만 받는다. 예전 API 는 강조 여부와
    /// 무관하게 `tint` 를 받았고, 그래서 **그려지지도 않는 색**을 25곳이 넘겨 두고 있었다
    /// (무채색 카드는 테두리를 `Color.primary` 로 그린다 — tint 는 쓰이지 않았다).
    ///
    /// 허용 파일은 `PokedoroCardEmphasisGuardTests` 가 지킨다.
    func pokedoroCard(emphasis: Color? = nil) -> some View {
        modifier(PokedoroCardModifier(emphasis: emphasis))
    }
}

/// 오버레이 닫기 버튼 **정본**. 아이콘 · 위치 · 라벨을 여기 한 곳에서만 정한다.
///
/// 예전엔 화면마다 직접 만들어 설정은 좌상단 "‹ 뒤로", 레이드는 `xmark.circle.fill`, 나머지는
/// 우상단 `xmark` 였다. 오버레이는 팝오버 **전체**를 갈아 끼우므로 돌아가는 길이 화면마다 다르면
/// 사용자는 열 때마다 닫기를 다시 찾는다.
///
/// `help` 와 `accessibilityLabel` 을 **둘 다** 단다. `help` 는 마우스 툴팁이라 VoiceOver 에는
/// 안 읽힌다 — 아이콘뿐인 버튼에서 툴팁만 달면 화면 판독기 사용자에게는 이름 없는 버튼이다.
struct PokedoroOverlayCloseButton: View {
    let label: String
    /// Esc 로도 닫는다. 초안을 든 화면(대화 입력)만 끈다 — 타이핑 중 Esc 한 번에 쓰던 글이
    /// 화면째 사라지면 닫기가 편해진 것이 아니라 위험해진 것이다.
    var escapeCloses: Bool = true
    let onClose: () -> Void

    var body: some View {
        Button(action: onClose) { Image(systemName: "xmark") }
            .buttonStyle(.plain)
            .help(label)
            .accessibilityLabel(label)
            .keyboardShortcut(escapeCloses ? .cancelAction : nil)
    }
}

/// 오버레이 헤더 정본 — 제목 · 부가 컨트롤 · 닫기.
///
/// 제목이 한 줄 라벨인 오버레이가 쓴다. 대화처럼 제목 자리가 두 줄(이름 + 설명)인 화면은 헤더를
/// 직접 짜되 닫기만 `PokedoroOverlayCloseButton` 을 쓴다.
struct PokedoroOverlayHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    /// 화면을 알아보게 하는 색. 도전 탭 오버레이는 각자 색을 갖고(체육관 보라·던전 빨강·경매
    /// 주황·레이드 청록), 나머지는 `.primary` 로 둔다.
    let tint: Color
    let closeLabel: String
    let onClose: () -> Void
    private let trailing: Trailing

    init(title: String, systemImage: String, tint: Color = .primary, closeLabel: String,
         onClose: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.closeLabel = closeLabel
        self.onClose = onClose
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage).font(.headline).lineLimit(1)
                .foregroundStyle(tint)
            Spacer(minLength: 4)
            trailing
            PokedoroOverlayCloseButton(label: closeLabel, onClose: onClose)
        }
    }
}

extension PokedoroOverlayHeader where Trailing == EmptyView {
    init(title: String, systemImage: String, tint: Color = .primary, closeLabel: String,
         onClose: @escaping () -> Void) {
        self.init(title: title, systemImage: systemImage, tint: tint, closeLabel: closeLabel,
                  onClose: onClose) { EmptyView() }
    }
}

struct PokedoroTabBar: View {
    @Binding var selection: PopoverTab
    let l: L

    /// 라벨 · 아이콘은 여기 있고 **어떤 탭이 탭바에 오는지는** `PopoverTab.tabBarTabs` 가 정한다.
    /// 목록이 둘로 갈리면 탭을 더할 때 한쪽만 고쳐 어디에도 안 뜨는 탭이 생긴다.
    private func chrome(for tab: PopoverTab) -> (title: String, icon: String) {
        switch tab {
        case .home: (l.home, "house.fill")
        case .pokemon: ("포켓몬", "circle.grid.cross.fill")
        case .collection: (l.collection, "book.closed.fill")
        case .battle: ("친구", "person.2.fill")
        case .challenge: ("도전", "flag.checkered")
        case .shop: (l.shop, "cart")
        case .bag: (l.bag, "backpack.fill")
        }
    }

    private var tabs: [(PopoverTab, String, String)] {
        PopoverTab.tabBarTabs.map { tab in
            let chrome = chrome(for: tab)
            return (tab, chrome.title, chrome.icon)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.0) { tab, title, icon in
                Button { withAnimation(.snappy(duration: 0.22)) { selection = tab } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: icon).font(.system(size: 14, weight: .bold))
                        Text(title).font(.system(size: 10, weight: .bold)).lineLimit(1)
                    }
                    // **고정 색을 쓰면 안 되는 자리다.** 뒤에 깔리는 알약은 모드에 따라 밝기가
                    // 뒤집히는데 `ink`(고정 다크 네이비)는 안 바뀐다 — 다크 모드에서 대비가
                    // 1.07:1 이 되어 고른 탭의 글자만 사라졌다. `primary` 는 모드를 따라간다.
                    // 선택 표시는 알약과 굵기가 이미 하고 있으므로 브랜드 색을 글자에 넣을 이유가 없다.
                    .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
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
