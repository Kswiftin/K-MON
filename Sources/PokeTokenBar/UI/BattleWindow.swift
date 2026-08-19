import AppKit
import SwiftUI

/// 전용 배틀 창 — 계획 §6.3 안 A. 대전이 도는 동안만 뜨고, 결과를 확인하면 닫힌다.
///
/// 팝오버가 아니라 창인 이유는 예산이다. Showdown 배치는 필드 **옆에** 로그를 두므로 팝오버
/// 콘텐츠 폭 332pt 에 애초에 들어가지 않는다(`BattleFieldTests.testTheSameArenaDoesNotFit…`).
/// 게다가 팝오버는 고정 높이 780pt 한 장을 모든 탭이 나눠 쓰고 있어 배틀만 키울 수도 없다.
///
/// 만드는 방식은 새로 짜지 않았다 — `FloatingPetController` 가 이미 쓰는 NSPanel + SwiftUI 호스팅
/// 패턴 그대로다. 다르게 둔 것은 둘뿐이다:
/// - `.nonactivatingPanel` 을 쓰지 않는다. 펫은 클릭을 받지 않지만 배틀 창은 버튼이 전부라,
///   LSUIElement 앱이 비활성인 채로는 기술 버튼 클릭이 무시된다(팝오버가 `NSApp.activate` 를
///   먼저 부르는 것과 같은 이유).
/// - 닫기 버튼을 주지 않는다. 대전 중에 창을 닫으면 기권도 아니고 진행도 못 하는 상태가 된다 —
///   나가는 길은 기권 버튼 하나로 둔다.
@MainActor
final class BattleWindowController {
    private var panel: NSPanel?

    /// 창의 표시 여부를 상태에 맞춘다. `content` 는 **처음 띄울 때 한 번만** 평가된다 —
    /// 매번 다시 호스팅하면 SwiftUI 가 뷰 identity 를 잃고 스프라이트 GIF 가 매 턴 처음부터 돈다.
    func setVisible(_ visible: Bool, content: () -> AnyView) {
        guard visible else { hide(); return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.contentViewController == nil {
            panel.contentViewController = NSHostingController(rootView: content())
            panel.setContentSize(NSSize(width: BattleFieldMetrics.windowWidth,
                                        height: BattleFieldMetrics.windowHeight))
            panel.center()
        }
        guard !panel.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// 팝오버의 "배틀 창 보기" 가 부른다 — 다른 창에 가려졌을 때 앞으로 끌어온다.
    func bringToFront() {
        guard let panel, panel.contentViewController != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        // 호스팅 트리를 놓아 준다 — 숨은 SwiftUI 트리는 매 디스플레이 사이클 재레이아웃되며
        // idle CPU 를 먹는다(팝오버가 닫힐 때 `contentViewController` 를 비우는 것과 같은 이유).
        panel.contentViewController = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0,
                                                width: BattleFieldMetrics.windowWidth,
                                                height: BattleFieldMetrics.windowHeight),
                            styleMask: [.titled, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "PokeTokenBar"
        panel.level = .floating              // 일하면서 배틀 — 다른 창 뒤로 숨지 않는다
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        return panel
    }
}
