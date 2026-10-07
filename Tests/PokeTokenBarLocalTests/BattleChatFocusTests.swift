import AppKit
import SwiftUI
import Testing
@testable import PokeTokenBar

@MainActor
@Suite(.serialized)
struct BattleChatFocusTests {
    @Observable
    final class Session {
        var turn = 1
        var messages: [BattleChatMessage] = []
        let senderID = UUID()
    }

    private struct Chat: View {
        let session: Session

        var body: some View {
            VStack {
                Text("Turn \(session.turn)")
                BattleChatPanel(configuration: BattleChatConfiguration(
                    messages: session.messages, mySenderID: session.senderID,
                    isEnabled: true, unavailableMessage: nil, l: L(),
                    onSend: { body in
                        session.messages.append(BattleChatMessage(
                            senderID: session.senderID, senderName: "나", body: body))
                    }))
            }
        }
    }

    private func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { textField(in: $0) }.first
    }

    private func settle() async throws {
        // SwiftUI's focus and Observation updates run on the next main-loop pass.
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test func advancingTurnsPreservesTheDraftAndKeyboardFocus() async throws {
        _ = NSApplication.shared
        let session = Session()
        let hosting = NSHostingView(rootView: Chat(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 330, height: 220),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        try await settle()

        let field = try #require(textField(in: hosting))
        #expect(window.makeFirstResponder(field))
        try await settle()
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("대화 중 12", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(window.firstResponder === editor)

        for turn in 2...4 {
            session.turn = turn
            try await settle()
            #expect(window.firstResponder === editor, "턴 \(turn)에서 채팅 포커스를 잃었다")
            #expect(field.stringValue == "대화 중 12")
        }

        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        try await settle()
        #expect(session.messages.map(\.body) == ["대화 중 12"])
        #expect(field.stringValue.isEmpty)
        #expect(window.firstResponder === editor)

        editor.insertText("계속 대화", replacementRange: NSRange(location: NSNotFound, length: 0))
        session.turn = 5
        try await settle()
        #expect(window.firstResponder === editor)
        #expect(field.stringValue == "계속 대화")

        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        try await settle()
        #expect(window.firstResponder !== editor, "Esc는 채팅 입력을 벗어나게 해야 한다")
        #expect(field.stringValue == "계속 대화")
    }
}
