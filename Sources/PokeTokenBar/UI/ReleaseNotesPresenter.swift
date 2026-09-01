import AppKit
import SwiftUI

/// 업데이트로 버전이 올라간 **뒤 첫 실행**에 릴리스 노트를 한 번 보여 준다.
/// 띄울지 말지는 `ReleaseNotesGate` 가 정하고, 여기는 조회와 창만 맡는다.
@MainActor
final class ReleaseNotesPresenter: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let store: CompanionStore
    private let updater: UpdateChecker
    private let defaults: UserDefaults
    private var window: NSWindow?

    init(settings: AppSettings, store: CompanionStore, updater: UpdateChecker,
         defaults: UserDefaults = .standard) {
        self.settings = settings
        self.store = store
        self.updater = updater
        self.defaults = defaults
    }

    /// 기동 시 1회. 도장은 **창을 띄운 뒤에** 찍는다 — 먼저 찍으면 조회에 실패한 버전의 노트가
    /// 영영 사라진다. 조회 실패 자체는 재시도하지 않고, 링크만 걸린 창으로 끝낸다.
    func showIfUpdated() async {
        let version = updater.currentVersion
        switch ReleaseNotesGate.decide(current: version,
                                       lastSeen: ReleaseNotesGate.lastSeenVersion(in: defaults),
                                       enabled: settings.releaseNotesOnUpdateEnabled) {
        case .skip:
            return
        case .stampOnly:
            ReleaseNotesGate.stamp(version, in: defaults)
        case .show:
            present(version: version, notes: await updater.releaseNotes(forVersion: version))
            ReleaseNotesGate.stamp(version, in: defaults)
        }
    }

    private func present(version: String, notes: String?) {
        let window = window ?? makeWindow()
        self.window = window
        window.contentViewController = NSHostingController(rootView:
            ReleaseNotesView(store: store, version: version, notes: notes,
                             close: { [weak window] in window?.close() })
                .environment(store)
                .environment(\.locale, store.language.displayLocale))
        window.title = store.l.releaseNotesWindowTitle
        // 메뉴바 전용(accessory) 앱이라 활성화하지 않으면 창이 다른 앱 뒤에 조용히 뜬다.
        // 버전당 한 번뿐이므로 앞으로 가져온다.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 420, height: 360)
        window.setFrameAutosaveName("ReleaseNotesWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

struct ReleaseNotesView: View {
    let store: CompanionStore
    let version: String
    /// GitHub 릴리스 본문(마크다운). 못 받았으면 nil — 그때는 링크만 건다.
    let notes: String?
    let close: () -> Void
    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l.releaseNotesUpdatedTo(version))
                .font(.title3).fontWeight(.semibold)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
            Divider()
            ScrollView {
                Group {
                    if let notes {
                        Text(Self.rendered(notes)).textSelection(.enabled)
                    } else {
                        Text(l.releaseNotesUnavailable).foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            Divider()
            HStack {
                if let url = UpdateChecker.releaseTagURL(version: version) {
                    Button(l.releaseNotesOpenPage) { NSWorkspace.shared.open(url) }
                }
                Spacer()
                Button(l.close, action: close).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    /// 릴리스 본문은 `## What's Changed` + 목록 + PR 링크가 전부다. 마크다운 렌더러를 따로 붙이지
    /// 않고 인라인 서식만 살린다 — `.full` 은 줄바꿈을 뭉쳐 목록이 한 문단으로 눌린다.
    static func rendered(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }
}
