import AppKit
import SwiftUI

enum PopoverTab {
    case home, pokemon, collection, battle, pokeathlon, shop, bag

    /// 탭이 유지하는 팝오버 높이. 탭 안에서 콘텐츠가 늘고 줄어도(기술 목록 펼침, 로딩 자리표시자,
    /// 진화 프롬프트) 이 값은 그대로라 창이 다시 그려지지 않는다 — 펼칠 때마다 커졌다 작아지며
    /// 떨리던 원인을 없앤다. 탭을 바꿀 때만 크기가 바뀐다.
    var contentHeight: CGFloat {
        switch self {
        // 헤더·진화 라인·기술 4행까지 펼친 높이. 접어도 같은 높이라 아래가 조금 빈다.
        case .home: return 560
        // 도감·상점·가방은 안에 520pt 격자를 들고 있어 타이머·탭바·푸터까지 더하면 이만큼 든다.
        case .collection, .shop, .bag, .pokemon: return 780
        // 배틀·포켓슬론은 상대 목록·경기 상태에 따라 세로가 가장 많이 흔들리는 탭이다.
        case .battle, .pokeathlon: return 780
        }
    }
}

enum PopoverMetrics {
    static let width: CGFloat = 360
    static let padding: CGFloat = 14
    static let contentWidth: CGFloat = width - padding * 2

    /// 메뉴바·팝오버 화살표·화면 아래 여백이 먹는 세로 공간.
    static let verticalChrome: CGFloat = 80
    /// 좁은 화면에서도 최소한 이만큼은 준다 — 아래 스크롤로 나머지를 본다.
    static let minHeight: CGFloat = 320
    /// 화면 크기를 모를 때(NSScreen 부재) 쓰는 보수적 기본값.
    static let fallbackScreenHeight: CGFloat = 900

    /// 팝오버 콘텐츠 높이 상한. 넘으면 NSPopover 가 스크롤 없이 잘라내므로(#9) 스크롤 컨테이너와 짝으로 쓴다.
    ///
    /// 상한은 오직 화면 가용 높이에서만 나온다. 예전엔 720pt 짜리 고정 천장을 같이 걸었는데,
    /// 1440pt 화면에서도 상한이 720 이라 "기술 보기" 를 펼친 홈 탭(약 760pt)이 화면에 다 들어가는데도
    /// 스크롤로 넘어가 헤더와 돌봄·모험 카드가 잘려 보였다. 화면보다 작은 고정 천장은 두지 않는다.
    static func maxHeight(screenHeight: CGFloat) -> CGFloat {
        max(minHeight, screenHeight - verticalChrome)
    }

    @MainActor
    static var currentMaxHeight: CGFloat {
        maxHeight(screenHeight: NSScreen.main?.visibleFrame.height ?? fallbackScreenHeight)
    }

    /// 탭이 원하는 높이를 화면에 맞춘다 — 고정 높이가 화면 밖으로 나가면 다시 클리핑이 된다.
    static func height(for tab: PopoverTab, screenHeight: CGFloat) -> CGFloat {
        min(tab.contentHeight, maxHeight(screenHeight: screenHeight))
    }

    @MainActor
    static func currentHeight(for tab: PopoverTab) -> CGFloat {
        height(for: tab, screenHeight: NSScreen.main?.visibleFrame.height ?? fallbackScreenHeight)
    }
}

@MainActor
@Observable
final class PopoverNavigation {
    var showSettings = false
    var tab: PopoverTab = .home

    func reset() {
        showSettings = false
        tab = .home
    }

    func goToBattle() {
        showSettings = false
        tab = .battle
    }
}

struct PopoverView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CompanionStore.self) private var companion
    @Environment(UpdateChecker.self) private var updater
    @Environment(PopoverNavigation.self) private var nav
    @Environment(BattleCenter.self) private var battleCenter
    @Environment(FocusTimer.self) private var focusTimer

    private var l: L { companion.l }

    var body: some View {
        @Bindable var nav = nav
        Group {
            if nav.showSettings {
                SettingsView(onClose: { nav.showSettings = false })
                    .environment(settings)
                    .environment(companion)
                    .environment(updater)
            } else {
                // 고정 높이 + 탭 안 스크롤. 콘텐츠가 늘 때마다 창이 커지면 NSPopover 가 매번 다시
                // 그려 떨리고, 화면을 넘기면 스크롤 대신 잘라낸다(#9). 창 크기는 고정하고 넘치는
                // 부분만 탭 안에서 스크롤한다 — 타이머·탭바·푸터는 스크롤 밖이라 항상 제자리다.
                mainContent
                    .frame(height: PopoverMetrics.currentHeight(for: nav.tab))
            }
        }
        .frame(width: PopoverMetrics.width)
        .environment(\.spriteAntialiasing, settings.imageAntialiasing)
        .environment(\.locale, companion.language.displayLocale)
        .onAppear { if battleCenter.pendingAttention { nav.tab = .battle } }
    }

    @ViewBuilder
    private var updateBanner: some View {
        if let update = updater.available, settings.updateNotificationsEnabled {
            HStack(spacing: 8) {
                Text(l.updateAvailable(update.version, current: updater.currentVersion)).font(.caption)
                Spacer()
                if updater.isUpdating {
                    ProgressView().controlSize(.small)
                } else {
                    Button(l.updateButton) { updater.applyUpdate() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button(l.updateLater) { updater.skipCurrent() }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// 계정 단위 상태 한 줄 — 트레이너 레벨과 별의조각 잔액. 팝오버 최상단에 고정해 어느 탭에서도 보인다.
    ///
    /// 파트너 카드가 아니라 여기 있어야 한다 — 레벨은 졸업으로 초기화되지 않는 **계정** 값이다.
    /// 라벨의 "트레이너" 도 빼면 안 된다. `Lv.N` 만 쓰면 파트너·로스터·배틀이 이미 쓰는 표기와
    /// 겹쳐 포켓몬 레벨로 잘못 읽힌다. 게이지와 남은 포인트가 있어야 배지가 아니라 쫓을 목표가 되고,
    /// 옆의 잔액이 레벨업 보상이 어디로 들어왔는지 연결해 준다(그 전엔 상점 안에서만 보였다).
    private var trainerBar: some View {
        HStack(spacing: 8) {
            Text("👑 \(l.trainerLevelLabel) Lv.\(companion.trainerLevel.level)")
                .font(.caption.weight(.semibold)).monospacedDigit()
            ProgressView(value: companion.trainerLevel.progress)
                .tint(.orange).frame(width: 64)
            if let remaining = companion.trainerLevel.pointsToNextLevel {
                Text("\(remaining)p")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
            Text("⭐ " + GameNumberFormatter.compact(companion.availableTokens))
                .font(.caption.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var mainContent: some View {
        @Bindable var nav = nav
        return VStack(alignment: .leading, spacing: 12) {
            updateBanner
            trainerBar
            FocusTimerView()
            Picker("", selection: $nav.tab) {
                Text(l.home).tag(PopoverTab.home)
                Text(companion.language == .ko ? "포켓몬" : "Pokémon").tag(PopoverTab.pokemon)
                Text(l.collection).tag(PopoverTab.collection)
                Text(l.battle).tag(PopoverTab.battle)
                Text(companion.language == .ko ? "포켓슬론" : "Pokéathlon").tag(PopoverTab.pokeathlon)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // 탭 콘텐츠만 스크롤한다. 짧은 탭은 위로 붙고 남는 자리는 빈 공간으로 둔다 —
            // 창 높이가 고정이라 탭을 바꾸거나 기술 목록을 펼쳐도 팝오버는 그대로다.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch nav.tab {
                    case .pokeathlon: PokeathlonView(store: companion)
                    case .battle: BattleView(store: companion)
                    case .collection: CollectionView(store: companion)
                    case .pokemon: PokemonRosterView(store: companion, nav: nav)
                    case .bag: BagView(store: companion, nav: nav)
                    case .shop: ShopView(store: companion, nav: nav)
                    case .home: CompanionHeader(store: companion)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity, alignment: .top)

            footer
        }
        .padding(PopoverMetrics.padding)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if nav.tab == .home {
                Text("\(l.totalPlaytime) \(l.duration(companion.activeSecondsTotal))")
                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            }
            Button { nav.tab = .shop } label: { Label(l.shop, systemImage: "cart") }
                .buttonStyle(.borderless).help(l.shop)
            Spacer()
            Button { nav.showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help(l.settings)
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless).help(l.quit)
        }
    }
}
