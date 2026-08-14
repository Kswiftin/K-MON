import XCTest
@testable import PokeTokenBar

/// 메뉴바 상태 결정표(#20) — focus > adventuring > resting 우선순위와 시간 포맷 경계를 고정한다.
/// 뷰 안의 if 사슬에서는 새 상태가 추가돼도(예: 완료된 모험) 분기 누락이 컴파일도 테스트도 안 걸렀다.
@MainActor
final class MenuBarStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func adventure(endsAt: Date) -> AdventureRun {
        AdventureRun(zone: .forest, startedAt: now.addingTimeInterval(-60), endsAt: endsAt, companionSpeciesID: 1)
    }

    func testFocusWinsOverARunningAdventure() {
        let timer = FocusTimer()
        timer.startFocus(minutes: 25, now: now)
        let status = MenuBarStatus.resolve(focusTimer: timer,
                                           activeAdventure: adventure(endsAt: now.addingTimeInterval(600)),
                                           now: now)
        guard case .focus = status else { return XCTFail("포커스가 진행 중인 모험을 이겨야 한다: \(status)") }
    }

    func testRunningAdventureBeatsResting() {
        let timer = FocusTimer()   // idle — 시작한 적 없음
        let status = MenuBarStatus.resolve(focusTimer: timer,
                                           activeAdventure: adventure(endsAt: now.addingTimeInterval(600)),
                                           now: now)
        guard case .adventuring = status else { return XCTFail("모험이 휴식을 이겨야 한다: \(status)") }
    }

    /// 완료됐지만 미수령인 모험은 다음 집중 세션을 막는 상태라 "휴식 중"과 구분돼야 한다.
    func testCompleteButUnclaimedAdventureResolvesToClaimable() {
        let timer = FocusTimer()
        let status = MenuBarStatus.resolve(focusTimer: timer,
                                           activeAdventure: adventure(endsAt: now.addingTimeInterval(-1)),
                                           now: now)
        XCTAssertEqual(status, .adventureClaimable)
    }

    func testNoAdventureResolvesToResting() {
        let timer = FocusTimer()
        let status = MenuBarStatus.resolve(focusTimer: timer, activeAdventure: nil, now: now)
        XCTAssertEqual(status, .resting)
    }

    /// 해안 모험은 최대 2시간이라 mm:ss 만 쓰면 119:59 처럼 두 자리를 넘는다 — 1시간 경계 양쪽을 고정.
    func testCountdownFormatsOnBothSidesOfTheOneHourBoundary() {
        XCTAssertEqual(MenuBarStatus.remainingClockText(now.addingTimeInterval(59 * 60 + 59), at: now), "59:59")
        XCTAssertEqual(MenuBarStatus.remainingClockText(now.addingTimeInterval(60 * 60), at: now), "1h00m")
        XCTAssertEqual(MenuBarStatus.remainingClockText(now.addingTimeInterval(60 * 60 + 23 * 60), at: now), "1h23m")
    }

    /// text(_:) 도 세 언어 모두 요청한 세 상태를 다 렌더할 수 있어야 한다(문구 누락 방지).
    func testTextRendersEveryStateInEveryLanguage() {
        let states: [MenuBarStatus] = [.focus(prefix: "FOCUS", clock: "24:59"),
                                       .adventuring(remaining: "12:34"), .adventureClaimable, .resting]
        for language in AppLanguage.allCases {
            for status in states {
                XCTAssertFalse(status.text(L(language)).isEmpty)
            }
        }
    }
}
