import SwiftUI
import AppKit

/// 사파리존 걷기 화면 전용 방향키 캡처 — `room-walk-dungeon-design.md` 의 `KeyCapture` 설계를
/// 그대로 가져온다. `NSEvent` 로컬 모니터를 화면이 떠 있는 동안만 등록한다.
/// `ShortcutRecorderView.swift` 가 이미 같은 `NSViewRepresentable` + `NSEvent` 패턴을 쓴다.
struct SafariKeyCapture: NSViewRepresentable {
    @Binding var heldKeys: Set<SafariDirectionKey>

    func makeNSView(context: Context) -> SafariKeyCaptureNSView {
        let view = SafariKeyCaptureNSView()
        view.onKeysChanged = { heldKeys = $0 }
        view.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: SafariKeyCaptureNSView, context: Context) {}

    /// SwiftUI 가 뷰를 뜯어낼 때(탭 전환·오버레이 닫힘) 호출한다 — 여기서 모니터를 반드시
    /// 해제해야 다른 화면에서 화살표가 먹히고 모니터 핸들이 누수되는 일이 없다.
    static func dismantleNSView(_ nsView: SafariKeyCaptureNSView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

/// 방향키·WASD 를 소비하고(경고음 방지) 눌린 집합을 알린다. 텍스트 입력 뷰가 first responder면
/// 전부 통과시킨다(설정 화면 등 보호) — `ShortcutRecorderView` 와 같은 주의사항.
final class SafariKeyCaptureNSView: NSView {
    var onKeysChanged: ((Set<SafariDirectionKey>) -> Void)?
    private var held: Set<SafariDirectionKey> = [] {
        didSet { if held != oldValue { onKeysChanged?(held) } }
    }
    private var monitor: Any?

    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        held = []
    }

    // `deinit` 에서는 정리하지 않는다 — Swift 6 엄격한 동시성 모드에서 `nonisolated deinit`
    // 이 `Any?`(`Sendable` 아님)인 이 프로퍼티에 접근할 수 없다(컴파일 오류로 CI 가 잡았다).
    // `dismantleNSView` 가 SwiftUI 표준 생명주기 훅으로 뷰가 트리에서 빠질 때 항상
    // `stopMonitoring()` 을 부르므로(MainActor 컨텍스트), `deinit` 의 안전망은 애초에 불필요한
    // 중복이었다.

    private func handle(_ event: NSEvent) -> NSEvent? {
        if window?.firstResponder is NSTextView { return event }
        guard let direction = Self.direction(for: event.keyCode) else { return event }
        switch event.type {
        case .keyDown: held.insert(direction)
        case .keyUp: held.remove(direction)
        default: break
        }
        return nil
    }

    /// 방향키 또는 WASD(ANSI US 배열 기준 키코드) — 다른 배열에서도 물리 위치가 같아 탑다운
    /// 이동에는 자연스럽다(레이아웃마다 문자를 다시 매핑하지 않는다).
    /// 키코드 매핑 실수(예: 좌우가 뒤바뀜)는 조용히 방향이 어긋나는 결함이라 테스트가 직접
    /// 확인할 수 있게 `internal` 로 둔다(`SafariKeyCaptureTests`).
    static func direction(for keyCode: UInt16) -> SafariDirectionKey? {
        switch keyCode {
        case 126, 13: return .up      // ↑ / W
        case 125, 1:  return .down    // ↓ / S
        case 123, 0:  return .left    // ← / A
        case 124, 2:  return .right   // → / D
        default: return nil
        }
    }
}
