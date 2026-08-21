import XCTest
@testable import PokeTokenBar

/// 보관 알 자동 부화 카운트다운(#86) — **0 에 닿은 뒤 다시 올라가지 않는다.**
///
/// 결함은 뷰가 `Text(readyAt, style: .timer)` 를 쓴 데서 왔다. SwiftUI 의 그 스타일은 목표 시각을
/// 지나면 *경과* 시간을 세어 올리므로, 부화 트리거(60초 방치 틱)나 종 추첨(네트워크)이 늦는
/// 구간에서 숫자가 0 → 0:01 → 0:02 로 되올랐다. 그 구간은 정상 동작이라 없앨 수 없으므로,
/// 표시가 0 에서 멈추고 `.due` 로 넘어가는 것을 순수 함수로 잠근다.
///
/// 테스트가 못 걸렀던 이유: `CompanionTests` 는 `nextStoredEggHatchAt != nil`(카운트다운이 뜨는지)
/// 만 봤고, 그 시각을 **지난 뒤** 무엇이 그려지는지는 어느 테스트도 밟지 않았다. 표시 로직 자체가
/// 뷰 안에 있어 테스트 대상이 아니었던 것이 공백의 뿌리다.
@MainActor
final class StoredEggCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: 트리거 브랜치 — 예정 시각 도달·경과

    /// 결함의 바로 그 조건: 예정 시각을 지났는데 아직 부화하지 않은 구간.
    /// 결함을 되넣으면(경과 시간을 숫자로 그리면) `.counting` 이 나와 이 단정이 깨진다.
    func testPastDueNeverShowsANumber() {
        for elapsed in [0.5, 1.0, 30.0, 600.0, 86_400.0] {
            let state = StoredEggCountdown.resolve(readyAt: now.addingTimeInterval(-elapsed), now: now)
            XCTAssertEqual(state, .due, "\(elapsed)초 경과 구간에서 숫자를 그리면 안 된다: \(state)")
        }
    }

    /// 정확히 0 인 경계 — "00:00" 을 잠깐 보여주고 다음 초에 올라가던 자리다.
    func testExactBoundaryIsDue() {
        XCTAssertEqual(StoredEggCountdown.resolve(readyAt: now, now: now), .due)
    }

    /// 1초 미만 남음도 `.due` 로 접는다 — 올림(.rounded(.up)) 뒤 0 이하가 되는 구간.
    func testSubSecondRemainderIsDue() {
        XCTAssertEqual(StoredEggCountdown.resolve(readyAt: now.addingTimeInterval(0.4), now: now), .due)
    }

    // MARK: 남아 있는 구간

    func testCountingShowsFlooredClock() {
        XCTAssertEqual(StoredEggCountdown.resolve(readyAt: now.addingTimeInterval(300), now: now),
                       .counting(clock: "05:00"))
        XCTAssertEqual(StoredEggCountdown.resolve(readyAt: now.addingTimeInterval(1), now: now),
                       .counting(clock: "00:01"))
    }

    /// **표시가 단조 비증가**인지를 1초 간격으로 5분 전 구간 전수 확인한다. 어느 인접 쌍에서도
    /// 남은 초가 늘지 않고, 0 이후엔 전부 `.due` 로 남는다(되올라감 없음).
    func testDisplayNeverIncreasesAcrossTheWholeWindow() {
        let readyAt = now.addingTimeInterval(CompanionStore.storedEggHatchDelay)
        var previous = Int.max
        var sawDue = false
        for step in 0...(Int(CompanionStore.storedEggHatchDelay) + 120) {
            let at = now.addingTimeInterval(Double(step))
            switch StoredEggCountdown.resolve(readyAt: readyAt, now: at) {
            case .counting(let clock):
                XCTAssertFalse(sawDue, "한 번 `.due` 가 된 뒤 다시 숫자로 돌아가면 안 된다(step \(step))")
                let seconds = Self.seconds(clock)
                XCTAssertLessThan(seconds, previous, "남은 시간이 줄지 않았다(step \(step)): \(clock)")
                previous = seconds
            case .due:
                sawDue = true
            }
        }
        XCTAssertTrue(sawDue, "5분 창을 지나면 `.due` 에 도달해야 한다")
    }

    private static func seconds(_ clock: String) -> Int {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return -1 }
        return parts[0] * 60 + parts[1]
    }
}
