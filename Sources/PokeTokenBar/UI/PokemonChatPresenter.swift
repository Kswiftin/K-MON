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
    /// 대화가 실행할 수 있는 것 전부. 실행기를 여기서 한 번 조립해 내려보내므로, 도구가 붙는
    /// 자리가 화면마다 생기지 않는다.
    private let toolbox: PokemonChatToolbox
    private var window: NSWindow?

    init(store: CompanionStore, chat: PokemonChatStore, album: PokemonMemoryAlbum, timer: FocusTimer) {
        self.store = store; self.chat = chat; self.album = album
        self.toolbox = PokemonChatToolbox(timer: timer, companion: store,
                                          lookup: PokemonChatToolbox.apiLookup)
    }

    func open(companionID: UUID) {
        guard let mon = store.ownedMons.first(where: { $0.id == companionID }) else { return }
        let view = PokemonChatView(store: store, companionID: companionID, chat: chat, album: album, toolbox: toolbox)
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
