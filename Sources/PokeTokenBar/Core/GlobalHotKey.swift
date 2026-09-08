import AppKit
import Carbon

/// 사용자가 지정한 단축키 조합 — 물리 키 코드(`NSEvent.keyCode` 와 같은 값 체계, 키보드 배열에
/// 안 흔들린다)와 수정키 비트를 저장한다. `displayCharacter` 는 레코딩 그 순간
/// `NSEvent.charactersIgnoringModifiers` 로 얻은 표시용 문자다 — 코드→문자 표를 직접 만들지
/// 않고 캡처 시점에 시스템이 준 값을 그대로 보여준다.
struct KeyCombo: Equatable, Sendable, Codable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags` 의 raw value. command/option/shift/control 네 비트만 저장한다.
    var modifierFlagsRawValue: UInt
    var displayCharacter: String

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue) }

    /// 화면에 보여줄 문자열 — macOS 관례 순서(⌃⌥⇧⌘) 뒤에 키 문자.
    var displayString: String {
        var symbols = ""
        let flags = modifierFlags
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols + displayCharacter
    }
}

/// 앱이 백그라운드(팝오버가 닫혀 있는 상태)일 때도 반응하는 전역 단축키 하나.
///
/// Carbon `RegisterEventHotKey` 를 쓴다 — `NSEvent.addGlobalMonitorForEvents` 는 **관찰만** 하고
/// 이벤트를 가로채지 못해, 같은 조합을 쓰는 다른 창·앱에도 그대로 전달돼 두 동작이 동시에 난다.
/// Carbon 은 deprecated 표시가 있지만 이 등록 자체를 대체하는 공식 API가 아직 없어(macOS 15
/// 기준), 메뉴바 유틸리티들이 여전히 이 경로를 쓴다.
@MainActor
final class GlobalHotKey {
    // `OpaquePointer` 계열이라 Sendable 이 아니다 — `@MainActor` 클래스의 `deinit` 은 항상
    // nonisolated 라 그냥 두면 그 자리에서 못 읽는다. 실제로는 `register`/`unregister`(둘 다
    // MainActor) 와 `deinit` 에서만 손대고, deinit 시점엔 다른 참조가 없어 경합이 없다.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?
    /// 4바이트 서명 — "PKMN". 이 앱이 등록한 핫키임을 나타내는 태그일 뿐, 다른 앱과 절대
    /// 안 겹쳐야 하는 값은 아니다(Carbon 이 프로세스별로 핸들러를 가른다).
    private static let signature: OSType = 0x504B_4D4E
    private static var nextID: UInt32 = 1

    /// 등록 — 이전 등록이 있으면 먼저 해제한다(같은 인스턴스로 조합을 바꿔 다시 부를 수 있다).
    func register(_ combo: KeyCombo, action: @escaping () -> Void) {
        unregister()
        self.action = action

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in hotKey.action?() }
            return noErr
        }, 1, &eventSpec, selfPointer, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.nextID)
        Self.nextID += 1
        RegisterEventHotKey(UInt32(combo.keyCode), Self.carbonModifiers(from: combo.modifierFlags),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        action = nil
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
