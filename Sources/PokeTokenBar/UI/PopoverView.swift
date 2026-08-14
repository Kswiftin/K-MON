import AppKit
import SwiftUI

enum PopoverTab { case home, pokemon, collection, battle, pokeathlon, shop, bag }

enum PopoverMetrics {
    static let width: CGFloat = 360
    static let padding: CGFloat = 14
    static let contentWidth: CGFloat = width - padding * 2

    /// 메뉴바·팝오버 화살표·화면 아래 여백이 먹는 세로 공간.
    static let verticalChrome: CGFloat = 80
    /// 화면이 아무리 커도 이 이상은 안 키운다(팝오버가 화면을 뒤덮지 않게).
    static let hardMaxHeight: CGFloat = 720
    /// 좁은 화면에서도 최소한 이만큼은 준다 — 아래 스크롤로 나머지를 본다.
    static let minHeight: CGFloat = 320

    /// 팝오버 콘텐츠 높이 상한. 넘으면 NSPopover 가 스크롤 없이 잘라내므로(#9) 스크롤 컨테이너와 짝으로 쓴다.
    static func maxHeight(screenHeight: CGFloat) -> CGFloat {
        max(minHeight, min(hardMaxHeight, screenHeight - verticalChrome))
    }

    @MainActor
    static var currentMaxHeight: CGFloat {
        maxHeight(screenHeight: NSScreen.main?.visibleFrame.height ?? hardMaxHeight)
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
                // 높이 상한 + 스크롤. 기술 목록을 펼치면 홈 탭이 화면 아래를 넘고, NSPopover 는
                // 넘친 만큼을 스크롤 대신 잘라내 타이머·푸터가 사라졌다(#9). 상한은 화면 높이에서 파생.
                ScrollView {
                    mainContent
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: PopoverMetrics.currentMaxHeight)
                // fixedSize 가 없으면 ScrollView 가 제안받은 높이를 통째로 먹어 짧은 탭에서도
                // 팝오버가 상한 높이(빈 여백)로 부푼다. 순서 주의 — frame 뒤에 와야 한다.
                .fixedSize(horizontal: false, vertical: true)
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

    private var mainContent: some View {
        @Bindable var nav = nav
        return VStack(alignment: .leading, spacing: 12) {
            updateBanner
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

            switch nav.tab {
            case .pokeathlon: PokeathlonView(store: companion)
            case .battle: BattleView(store: companion)
            case .collection: CollectionView(store: companion)
            case .pokemon: PokemonRosterView(store: companion, nav: nav)
            case .bag: BagView(store: companion, nav: nav)
            case .shop: ShopView(store: companion, nav: nav)
            case .home: CompanionHeader(store: companion)
            }

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
