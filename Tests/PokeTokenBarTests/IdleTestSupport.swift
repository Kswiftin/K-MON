import Foundation
@testable import PokeTokenBar

/// 전진 가능한 테스트 시계 — CompanionStore(clock:)에 `clock.closure` 로 주입한다.
/// 방치 경제 전환 후 성장 적립은 tick() 경과분이라, 고정 시계 대신 이걸 쓴다.
/// 테스트는 MainActor 단일 스레드에서만 전진시키므로 unsafe 표시가 실제로 안전하다.
final class TestClock: @unchecked Sendable {
    nonisolated(unsafe) var now: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_755_000_000)) { now = start }
    var closure: () -> Date { { [self] in now } }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// 별의모래를 최소 `dust` 만큼 생산한다 — maxTickInterval 캡 안에서 tick 을 반복.
/// 첫 tick 은 기준점만 잡으므로(적립 0) 내부에서 시드를 보장한다.
/// 반환값은 실제 적립된 양(캡 단위 생산이라 target 을 살짝 넘을 수 있다).
@MainActor
@discardableResult
func produceDust(_ store: CompanionStore, _ clock: TestClock, atLeast dust: Int) -> Int {
    if store.state.lastTickAt == nil { store.tick() }   // 기준점 시드(적립 0)
    let before = store.state.usedSinceInstall
    while store.state.usedSinceInstall - before < dust {
        clock.advance(IdleEconomy.maxTickInterval)
        store.tick()
    }
    return store.state.usedSinceInstall - before
}
