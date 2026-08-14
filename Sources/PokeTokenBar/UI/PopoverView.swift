import AppKit
import SwiftUI

enum PopoverTab { case home, pokemon, collection, battle, pokeathlon, shop, bag }

enum PopoverMetrics {
    static let width: CGFloat = 360
    static let padding: CGFloat = 14
    static let contentWidth: CGFloat = width - padding * 2
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
                mainContent
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
