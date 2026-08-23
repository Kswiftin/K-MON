import AppKit
import SwiftUI

/// App-owned chat surface. A single reusable window avoids losing a conversation whenever the
/// transient menu-bar popover is dismissed.
@MainActor
@Observable
final class PokemonChatPresenter {
    private let store: CompanionStore
    private let chat: PokemonChatStore
    private let album: PokemonMemoryAlbum
    private var window: NSWindow?

    init(store: CompanionStore, chat: PokemonChatStore, album: PokemonMemoryAlbum) {
        self.store = store; self.chat = chat; self.album = album
    }

    func open(companionID: UUID) {
        guard let mon = store.ownedMons.first(where: { $0.id == companionID }) else { return }
        _ = store.prepareChatProfile(for: mon)
        let view = PokemonChatView(store: store, companionID: companionID, chat: chat, album: album)
            .environment(self)
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
            window.title = store.chatProfile(for: mon).displayName
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = store.chatProfile(for: mon).displayName
            window.setContentSize(NSSize(width: 420, height: 520))
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            self.window = window
            window.center(); window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
