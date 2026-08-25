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
    /// 실행 파일 경로를 쓰는 **유일한** 창구. 대화 창이 UserDefaults 를 직접 건드리면 설정 화면의
    /// 목록과 갈라져, 한쪽에서 고른 경로가 다른 쪽에 안 보인다.
    private let settings: AppSettings
    /// 대화가 실행할 수 있는 것 전부. 실행기를 여기서 한 번 조립해 내려보내므로, 도구가 붙는
    /// 자리가 화면마다 생기지 않는다.
    private let toolbox: PokemonChatToolbox
    private var window: NSWindow?

    init(store: CompanionStore, chat: PokemonChatStore, album: PokemonMemoryAlbum,
         timer: FocusTimer, settings: AppSettings) {
        self.store = store; self.chat = chat; self.album = album; self.settings = settings
        self.toolbox = PokemonChatToolbox(timer: timer, companion: store,
                                          lookup: PokemonChatToolbox.apiLookup)
    }

    func open(companionID: UUID) {
        guard let mon = store.ownedMons.first(where: { $0.id == companionID }) else { return }
        let view = PokemonChatView(store: store, companionID: companionID, chat: chat, album: album,
                                   toolbox: toolbox, settings: settings)
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
