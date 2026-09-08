import SwiftUI
import AppKit

/// 클릭하면 다음 키 입력을 그대로 캡처하는 필드. 시스템·다른 앱이 이미 쓰는 조합과 겹쳐도
/// 그대로 받는다 — 이 프로세스 전용 등록이라 겹침을 미리 다 아는 방법이 없고, 겹치면 다음에
/// 눌렀을 때 안 되는 걸로 사용자가 바로 알아챈다.
struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var combo: KeyCombo?
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onCapture = { combo = $0; isRecording = false }
        view.onCancel = { isRecording = false }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        if isRecording { nsView.window?.makeFirstResponder(nsView) }
    }
}

/// 실제 키 입력을 받는 뷰. **최소 하나의 수정키(⌘⌥⇧⌃)를 요구한다** — 없으면 사용자가 타이핑
/// 중에 흔히 누르는 글자 하나가 그대로 전역 단축키가 되어 매번 팝오버를 열고 닫는다.
final class RecorderNSView: NSView {
    var onCapture: ((KeyCombo) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode != Self.escapeKeyCode else { onCancel?(); return }
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard !modifiers.isEmpty else { NSSound.beep(); return }
        let display = Self.displayCharacter(for: event)
        onCapture?(KeyCombo(keyCode: event.keyCode, modifierFlagsRawValue: modifiers.rawValue,
                            displayCharacter: display))
    }

    private static let escapeKeyCode: UInt16 = 53

    /// 특수 키는 이름으로, 나머지는 `charactersIgnoringModifiers` 를 대문자로 그대로 쓴다.
    /// 코드→문자 전체 표를 만들지 않는다 — 흔히 쓰는 몇 개만 이름을 붙이고 나머지는 시스템이
    /// 준 값을 믿는다(키보드 배열이 달라도 그 배열 기준 문자가 그대로 나온다).
    private static func displayCharacter(for event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "Space"
        case 48: return "Tab"
        case 36: return "Return"
        case 51: return "Delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return "?" }
            return characters.uppercased()
        }
    }
}
