import SwiftUI
import AppKit

/// 방향키·WASD 를 로컬 모니터로 잡아 던전 걷기 입력으로 바꾼다.
///
/// 모니터는 `.onAppear`/`.onDisappear` 로 여닫는다 — 팝오버 안에서 던전 탭을 떠나도 뷰가 살아
/// 있으면(`NavigationStack`·`TabView` 캐싱) 모니터가 계속 남아 다른 탭에서 방향키를 먹어버리고,
/// 팝오버를 다시 열 때마다 새 모니터가 또 설치돼 핸들이 누수된다. `onDisappear` 해제가 필수다.
///
/// 처리한 키에 `nil` 을 돌려주는 이유는 macOS 가 처리 안 된 keyDown 을 벨소리로 알리기 때문이다
/// (방향키·WASD 는 텍스트 입력 뷰가 없으면 "처리 안 됨"으로 잡혀 beep 이 난다).
struct KeyCaptureModifier: ViewModifier {
    let onPress: (WalkDirection) -> Void
    let onRelease: (WalkDirection) -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                    handle(event)
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
                // 모니터가 내려가는 순간까지 눌려 있던 키는 다시는 keyUp 을 못 받는다 — 여기서 전부
                // 놓아주지 않으면 `DungeonWalker.held` 가 latch 된 채로 남아 트레이너가 혼자 걷는다.
                for direction in WalkDirection.allCases { onRelease(direction) }
            }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // 텍스트 필드 편집 중이면(예: 트레이너 이름 입력) 방향키·WASD 도 텍스트 입력으로 흘려보낸다.
        if NSApp.keyWindow?.firstResponder is NSTextView {
            return event
        }
        guard let direction = walkDirection(for: event) else {
            return event
        }
        switch event.type {
        case .keyDown:
            // 단축키 조합은 누르는 쪽만 걷기 입력이 아니다 — ⌘/⌃/⌥ 가 눌려 있으면 ⌘W(닫기)·⌘A(전체선택)
            // 같은 시스템·앱 단축키를 그대로 흘려보낸다. keyUp 에는 이 가드를 걸지 않는다 — 모디파이어를
            // 누른 채로 걷기 키를 놓으면(예: 걷다가 ⌘ 로 팝오버를 닫으려는 순간) 여기서 걸러지면
            // `onRelease` 가 영영 안 불려 `held` 가 latch 되고 트레이너가 혼자 계속 걷는다.
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                return event
            }
            // 키를 누르고 있는 동안 OS 가 반복 keyDown 을 계속 보내는데, 눌림 상태는
            // `DungeonWalker.held` 가 이미 추적하므로 반복 이벤트는 무시한다.
            if !event.isARepeat {
                onPress(direction)
            }
        case .keyUp:
            onRelease(direction)
        default:
            break
        }
        return nil
    }

    private func walkDirection(for event: NSEvent) -> WalkDirection? {
        switch event.keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": return .up
        case "a": return .left
        case "s": return .down
        case "d": return .right
        default: return nil
        }
    }
}

extension View {
    /// 방향키·WASD 를 눌렀다 뗄 때마다 `onPress`/`onRelease` 로 `WalkDirection` 을 전달한다.
    func captureWalkKeys(
        onPress: @escaping (WalkDirection) -> Void,
        onRelease: @escaping (WalkDirection) -> Void
    ) -> some View {
        modifier(KeyCaptureModifier(onPress: onPress, onRelease: onRelease))
    }
}
