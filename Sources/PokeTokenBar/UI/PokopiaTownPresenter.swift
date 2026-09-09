import AppKit
import Observation
import SwiftUI

/// 포코피아 마을 창의 주인.
///
/// **Memory Home 과 다른 창인 것이 이 타입의 존재 이유다.** Memory Home 은 싸이월드 미니홈피를
/// 앱에 접은 기능이고(방명록·일촌·TODAY/TOTAL·미니룸), 포코피아는 닌텐도 《포켓몬 포코피아》를
/// 접은 다른 게임이다. 한동안 마을이 그 창의 `TOWN` 탭이었는데, 두 기능이 공유하는 것은
/// "앨범에 저장한다" 뿐이라 탭으로 묶을 근거가 없었다.
///
/// 창 소유 방식은 `MemoryHomePresenter` 를 그대로 따른다 — 프레임은 macOS 의 창 복원이
/// 가지며 세이브 파일에는 절대 넣지 않는다.
@MainActor
@Observable
final class PokopiaTownPresenter: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let store: CompanionStore
    private var window: NSWindow?
    private static let defaultContentSize = NSSize(width: 1_040, height: 720)

    init(settings: AppSettings, store: CompanionStore) {
        self.settings = settings
        self.store = store
        super.init()
    }

    /// **게이트가 없다.** `memoryHomeEnabled` 를 보지 않는다 — 그 설정은 미니홈피의 LAN 공개를
    /// 끄는 스위치이고, 마을은 LAN 에 나가지 않는다. 여기서 그 값을 읽으면 미니홈피를 끈
    /// 사용자가 마을에 못 들어가고, 그건 창을 가른 이유를 되돌리는 것이다.
    func open() {
        let window = window ?? makeWindow()
        self.window = window
        if window.contentView == nil { installContent(in: window) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "포코피아"
        window.minSize = NSSize(width: 900, height: 640)
        // 배경 블러(`PokedoroTheme.pageBackground`)가 실제로 비치려면 창 자체가 불투명하면 안 된다
        // — 불투명한 창은 배경을 먼저 칠해 `.behindWindow` 블렌딩을 가린다.
        window.isOpaque = false
        window.backgroundColor = .clear
        // **Memory Home 과 달라야 한다.** 같은 이름을 쓰면 두 창이 한 프레임을 두고 다퉈,
        // 한쪽을 옮기면 다른 쪽이 다음 실행에서 그 자리에 뜬다.
        window.setFrameAutosaveName("PokopiaTownWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        installContent(in: window)
        // contentViewController 를 붙이면 AppKit 이 SwiftUI 의 fitting size 로 창을 다시 잰다.
        // 그대로 두면 위 contentRect 가 무효가 되고 minSize(900×640)까지 쪼그라든다 —
        // 크기는 붙인 **뒤에** 잡는다(`MemoryHomePresenter` 가 실제로 겪은 함정이다).
        window.setContentSize(Self.defaultContentSize)
        window.center()
        return window
    }

    /// 마을 화면이 자기 머리말과 스크롤을 이미 갖고 있어 **감싸는 뷰를 두지 않는다.**
    /// 창 크롬(배경·틴트·폰트)만 여기서 얹는다 — Memory Home 창과 같은 값이라야 한 앱으로 보인다.
    private func installContent(in window: NSWindow) {
        window.contentViewController = NSHostingController(rootView:
            PokopiaTownView(store: store)
                .background(PokedoroTheme.pageBackground)
                .tint(PokedoroTheme.blue)
                .fontDesign(.rounded)
                .environment(settings)
                .environment(store)
                .environment(\.locale, PokemonNaming.locale))
    }
}
