import AppKit
import XCTest
@testable import PokeTokenBar

final class GlobalHotKeyTests: XCTestCase {

    /// 관례 순서(⌃⌥⇧⌘)로 조합해야 한다 — 시스템 메뉴가 단축키를 표기하는 순서와 같아야
    /// 사용자가 자기가 고른 조합을 알아본다.
    func testDisplayStringOrdersModifiersInSystemConvention() {
        let combo = KeyCombo(keyCode: 40, // 'K'
                             modifierFlagsRawValue: NSEvent.ModifierFlags([.control, .command, .shift, .option]).rawValue,
                             displayCharacter: "K")
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘K")
    }

    func testDisplayStringOmitsUnusedModifiers() {
        let combo = KeyCombo(keyCode: 40,
                             modifierFlagsRawValue: NSEvent.ModifierFlags.command.rawValue,
                             displayCharacter: "K")
        XCTAssertEqual(combo.displayString, "⌘K")
    }

    /// 설정 화면을 다시 열어도(=새 `AppSettings` 인스턴스) 고른 단축키가 유지돼야 한다 —
    /// `rosterSort` 등 다른 설정과 같은 라운드트립 계약이다.
    @MainActor
    func testTogglePopoverShortcutSurvivesReopeningSettings() {
        let suiteName = "popover-shortcut-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertNil(settings.togglePopoverShortcut, "기본은 설정 안 함이다")

        let combo = KeyCombo(keyCode: 40, modifierFlagsRawValue: NSEvent.ModifierFlags.command.rawValue,
                             displayCharacter: "K")
        settings.togglePopoverShortcut = combo

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.togglePopoverShortcut, combo)
    }

    /// 지우면(nil) 다음에 열었을 때도 비어 있어야 한다 — 지운 값이 되살아나면 사용자가
    /// 의도적으로 끈 단축키가 다시 켜진 것처럼 보인다.
    @MainActor
    func testClearingTheShortcutPersists() {
        let suiteName = "popover-shortcut-clear-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.togglePopoverShortcut = KeyCombo(keyCode: 40,
                                                   modifierFlagsRawValue: NSEvent.ModifierFlags.command.rawValue,
                                                   displayCharacter: "K")
        settings.togglePopoverShortcut = nil

        let reopened = AppSettings(defaults: defaults)
        XCTAssertNil(reopened.togglePopoverShortcut)
    }

    /// 내 턴·방 이벤트가 있어도 자동으로 팝오버를 열지 않는 선택은 다음 실행 뒤에도 유지돼야 한다.
    @MainActor
    func testAutomaticBattlePopoverSettingDefaultsToEnabledAndPersists() {
        let suiteName = "automatic-battle-popover-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.automaticBattlePopoverEnabled)
        settings.automaticBattlePopoverEnabled = false

        XCTAssertFalse(AppSettings(defaults: defaults).automaticBattlePopoverEnabled)
    }
}
