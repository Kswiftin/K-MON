import XCTest
@testable import PokeTokenBar

final class BattleWindowPresentationPolicyTests: XCTestCase {

    func testDisabledAutomaticOpeningNeverOpensForAForegroundEvent() {
        XCTAssertFalse(BattleWindowPresentationPolicy.shouldOpenAutomatically(
            automaticOpeningEnabled: false,
            terminalControlling: false,
            wantsForegroundWindow: true
        ))
    }

    func testAutomaticOpeningStillRequiresAForegroundEventAndNoTerminalControl() {
        XCTAssertFalse(BattleWindowPresentationPolicy.shouldOpenAutomatically(
            automaticOpeningEnabled: true,
            terminalControlling: false,
            wantsForegroundWindow: false
        ))
        XCTAssertFalse(BattleWindowPresentationPolicy.shouldOpenAutomatically(
            automaticOpeningEnabled: true,
            terminalControlling: true,
            wantsForegroundWindow: true
        ))
        XCTAssertTrue(BattleWindowPresentationPolicy.shouldOpenAutomatically(
            automaticOpeningEnabled: true,
            terminalControlling: false,
            wantsForegroundWindow: true
        ))
    }
}
