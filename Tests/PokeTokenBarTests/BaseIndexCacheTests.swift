import XCTest
@testable import PokeTokenBar

// MARK: 부화 후보 디스크 캐시 — 종 범위가 넓어져도 옛 캐시를 계속 쓰던 결함 (2026-09)

/// 종 범위가 열려도(#212) 30일 TTL 하나만 보면 옛 캐시가 계속 통과해, 새로 추가된 종이 부화
/// 후보에 안 들어갔다. `isBaseIndexSnapshotUsable` 이 그 판정 하나를 뽑아 둔 자리다.
final class BaseIndexCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(fetchedAt: Date, maxSpeciesID: Int) -> PokeAPIClient.BaseIndexSnapshot {
        PokeAPIClient.BaseIndexSnapshot(fetchedAt: fetchedAt, maxSpeciesID: maxSpeciesID,
                                        entries: [BaseSpecies(id: 1, captureRate: 45)])
    }

    /// 고의 주입: 종 범위 검사를 빼면(값 비교를 지우면) 이 테스트가 실패한다.
    func testAStaleRangeSnapshotIsNotUsableEvenWithinTTL() {
        let old = snapshot(fetchedAt: now.addingTimeInterval(-60), maxSpeciesID: 649)
        XCTAssertFalse(PokeAPIClient.isBaseIndexSnapshotUsable(old, currentMaxSpeciesID: 1025, now: now),
                       "종 범위가 옛 값(649)이면 방금 받은 캐시라도 새 범위(1025)에서는 쓰면 안 된다")
    }

    func testAMatchingRangeSnapshotIsUsableWithinTTL() {
        let fresh = snapshot(fetchedAt: now.addingTimeInterval(-60), maxSpeciesID: 1025)
        XCTAssertTrue(PokeAPIClient.isBaseIndexSnapshotUsable(fresh, currentMaxSpeciesID: 1025, now: now))
    }

    func testAMatchingRangeSnapshotExpiresAfterTTL() {
        let expired = snapshot(fetchedAt: now.addingTimeInterval(-31 * 86400), maxSpeciesID: 1025)
        XCTAssertFalse(PokeAPIClient.isBaseIndexSnapshotUsable(expired, currentMaxSpeciesID: 1025, now: now))
    }

    func testAnEmptySnapshotIsNeverUsable() {
        let empty = PokeAPIClient.BaseIndexSnapshot(fetchedAt: now, maxSpeciesID: 1025, entries: [])
        XCTAssertFalse(PokeAPIClient.isBaseIndexSnapshotUsable(empty, currentMaxSpeciesID: 1025, now: now))
    }
}
