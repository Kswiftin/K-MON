import XCTest
@testable import PokeTokenBar

/// `SafariKeyCaptureNSView.direction(for:)` — 키코드 → 방향 매핑. 좌우가 뒤바뀌는 것처럼
/// 조용히 방향이 어긋나는 결함을 막는다.
final class SafariKeyCaptureTests: XCTestCase {
    func testArrowKeysMapToTheirDirection() {
        XCTAssertEqual(SafariKeyCaptureNSView.direction(for: 126), .up)
        XCTAssertEqual(SafariKeyCaptureNSView.direction(for: 125), .down)
        XCTAssertEqual(SafariKeyCaptureNSView.direction(for: 123), .left)
        XCTAssertEqual(SafariKeyCaptureNSView.direction(for: 124), .right)
    }

    /// WASD(ANSI US 배열 키코드) — 물리 위치 기준이라 다른 배열에서도 손 위치가 방향과 맞는다.
    func testWASDMapsToTheSameDirectionAsArrows() {
        XCTAssertEqual(SafariKeyCaptureNSView.direction(for: 13), .up)     // W
        XCTAssertEqual(SafariKeyCaptureNSView.direction(for: 1), .down)   // S
        XCTAssertEqual(SafariKeyCaptureNSView.direction(for: 0), .left)   // A
        XCTAssertEqual(SafariKeyCaptureNSView.direction(for: 2), .right) // D
    }

    /// 관련 없는 키(예: 스페이스바 49)는 무시돼야 한다 — 소비하면 다른 기능이 막힌다.
    func testUnrelatedKeysAreIgnored() {
        XCTAssertNil(SafariKeyCaptureNSView.direction(for: 49))
    }

    /// 네 방향이 서로 다른 값으로 매핑되는지 — 두 방향이 우연히 같은 케이스로 겹치면 조용히
    /// 한 방향이 죽는다.
    func testAllFourDirectionsAreDistinct() {
        let mapped = Set([126, 125, 123, 124].compactMap(SafariKeyCaptureNSView.direction))
        XCTAssertEqual(mapped.count, 4, "네 방향키가 서로 다른 방향으로 매핑돼야 한다")
    }
}
