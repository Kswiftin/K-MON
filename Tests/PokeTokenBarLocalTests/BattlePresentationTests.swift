import Testing
@testable import PokeTokenBar

struct BattlePresentationTests {
    @Test func automaticBattleEventsLeaveAnOpenPopoverAlone() {
        #expect(!BattleWindowPresentationPolicy.shouldOpenAutomatically(
            automaticOpeningEnabled: true,
            terminalControlling: false,
            wantsForegroundWindow: true,
            popoverIsShown: true))
    }

    @Test func aClosedPopoverStillOpensForForegroundBattleEvents() {
        #expect(BattleWindowPresentationPolicy.shouldOpenAutomatically(
            automaticOpeningEnabled: true,
            terminalControlling: false,
            wantsForegroundWindow: true,
            popoverIsShown: false))
    }

    @Test func closedPopoversStillRespectAutomaticOpeningAndTerminalControl() {
        for (enabled, terminal, foreground) in [
            (false, false, true), (true, true, true), (true, false, false),
        ] {
            #expect(!BattleWindowPresentationPolicy.shouldOpenAutomatically(
                automaticOpeningEnabled: enabled,
                terminalControlling: terminal,
                wantsForegroundWindow: foreground,
                popoverIsShown: false))
        }
    }
}
