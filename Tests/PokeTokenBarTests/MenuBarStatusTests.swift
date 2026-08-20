import AppKit
import XCTest
@testable import PokeTokenBar

/// 메뉴바 상태 결정표(#20) — focus > adventuring > resting 우선순위와 시간 포맷 경계를 고정한다.
/// 뷰 안의 if 사슬에서는 새 상태가 추가돼도(예: 완료된 모험) 분기 누락이 컴파일도 테스트도 안 걸렀다.
/// FocusTimer(@MainActor) 를 값으로만 받으므로 이 테스트는 액터 격리와 무관하다.
final class MenuBarStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func adventure(endsAt: Date) -> AdventureRun {
        AdventureRun(zone: .forest, startedAt: now.addingTimeInterval(-60), endsAt: endsAt, companionSpeciesID: 1)
    }

    private func resolve(focusRunning: Bool, activeAdventure: AdventureRun?) -> MenuBarStatus {
        MenuBarStatus.resolve(focusRunning: focusRunning, focusPhase: .focus, focusClockText: "24:59",
                              activeAdventure: activeAdventure, now: now)
    }

    func testFocusWinsOverARunningAdventure() {
        let status = resolve(focusRunning: true, activeAdventure: adventure(endsAt: now.addingTimeInterval(600)))
        guard case .focus = status else { return XCTFail("포커스가 진행 중인 모험을 이겨야 한다: \(status)") }
    }

    func testRunningAdventureBeatsResting() {
        let status = resolve(focusRunning: false, activeAdventure: adventure(endsAt: now.addingTimeInterval(600)))
        guard case .adventuring = status else { return XCTFail("모험이 휴식을 이겨야 한다: \(status)") }
    }

    /// 완료됐지만 미수령인 모험은 다음 집중 세션을 막는 상태라 "휴식 중"과 구분돼야 한다.
    func testCompleteButUnclaimedAdventureResolvesToClaimable() {
        let status = resolve(focusRunning: false, activeAdventure: adventure(endsAt: now.addingTimeInterval(-1)))
        XCTAssertEqual(status, .adventureClaimable)
    }

    func testNoAdventureResolvesToResting() {
        XCTAssertEqual(resolve(focusRunning: false, activeAdventure: nil), .resting)
    }

    /// 해안 모험은 최대 2시간이라 mm:ss 만 쓰면 119:59 처럼 두 자리를 넘는다 — 1시간 경계 양쪽을 고정.
    func testCountdownFormatsOnBothSidesOfTheOneHourBoundary() {
        XCTAssertEqual(MenuBarStatus.remainingClockText(now.addingTimeInterval(59 * 60 + 59), at: now), "59:59")
        XCTAssertEqual(MenuBarStatus.remainingClockText(now.addingTimeInterval(60 * 60), at: now), "1h00m")
        XCTAssertEqual(MenuBarStatus.remainingClockText(now.addingTimeInterval(60 * 60 + 23 * 60), at: now), "1h23m")
    }

    func testCompactTitleForEveryState() {
        XCTAssertEqual(MenuBarStatus.focus(prefix: "FOCUS", clock: "24:59").compactTitle, "F 24:59")
        XCTAssertEqual(MenuBarStatus.focus(prefix: "BREAK", clock: "04:59").compactTitle, "B 04:59")
        XCTAssertEqual(MenuBarStatus.adventuring(remaining: "12:34").compactTitle, "A 12:34")
        XCTAssertEqual(MenuBarStatus.adventuring(remaining: "1h23m").compactTitle, "A 1h23m")
        XCTAssertEqual(MenuBarStatus.adventureClaimable.compactTitle, "!")
        XCTAssertEqual(MenuBarStatus.resting.compactTitle, "R")
    }

    /// 1시간 경계에서 남은 시간 표기가 바뀌어도 컴팩트 접두사와 함께 그대로 보여야 한다.
    func testCompactAdventureTitleKeepsCountdownFormatAcrossOneHourBoundary() {
        let underOneHour = resolve(
            focusRunning: false,
            activeAdventure: adventure(endsAt: now.addingTimeInterval(59 * 60 + 59))
        )
        let atOneHour = resolve(
            focusRunning: false,
            activeAdventure: adventure(endsAt: now.addingTimeInterval(60 * 60))
        )

        XCTAssertEqual(underOneHour.compactTitle, "A 59:59")
        XCTAssertEqual(atOneHour.compactTitle, "A 1h00m")
    }

    /// 최장 표기도 메뉴 막대에서 실제 사용하는 13pt 고정폭 숫자 폰트로 56pt 예산을 넘지 않는다.
    func testCompactTitlesFitRenderedWidthBudget() {
        let states: [MenuBarStatus] = [
            .focus(prefix: "FOCUS", clock: "24:59"),
            .focus(prefix: "BREAK", clock: "04:59"),
            .adventuring(remaining: "12:34"),
            .adventuring(remaining: "1h23m"),
            .adventureClaimable,
            .resting,
        ]
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let widest = states.map {
            ($0.compactTitle as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0

        XCTAssertLessThanOrEqual(widest, 56)
    }

    /// fullDescription(_:) 도 세 언어 모두 모든 상태를 렌더할 수 있어야 한다(툴팁 문구 누락 방지).
    func testFullDescriptionRendersEveryStateInEveryLanguage() {
        let states: [MenuBarStatus] = [.focus(prefix: "FOCUS", clock: "24:59"),
                                       .adventuring(remaining: "12:34"), .adventureClaimable, .resting]
        for language in AppLanguage.allCases {
            for status in states {
                XCTAssertFalse(status.fullDescription(L(language)).isEmpty)
            }
        }
    }
}
