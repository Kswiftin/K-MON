import Foundation
import XCTest
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

// MARK: 만렙 시드 (만렙 경계를 밟는 테스트가 공유한다)

/// 진화 없는 1단 라인. 만렙 · 정산 표면 테스트가 같은 개체를 쓴다.
let stubMaxLevelLine = EvoLine(baseID: 20, tree: EvoNode(speciesID: 20, children: []),
                               rarity: .common,
                               names: [20: ["en": "P20", "ko": "포20", "ja": "ポ20"]])

func stubStoreURL(_ tag: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(tag)-\(UUID().uuidString).json")
}

@MainActor
func stubStore(_ clock: TestClock, tag: String = "store") -> CompanionStore {
    CompanionStore(provider: StubProvider(value: stubMaxLevelLine), clock: clock.closure,
                   fileURL: stubStoreURL(tag), rng: SeededRNG(seed: 7))
}

/// 만렙 파트너를 세운다 — 상한에 **정확히** 닿게 시드하므로 시드 자체로는 초과분이 없다.
/// 뒤에 오는 환산이 시드 부작용이 아니라 정산분임을 이 전제가 보장한다.
///
/// **한 자리에만 둔다.** 파일마다 복사해 두면 시드 방식(예: `maxLevelExperience` 정의)이 바뀔 때
/// 한쪽만 고치게 되고, 그러면 두 파일이 서로 다른 전제를 검증한다 — 실제로 MaxLevelTests ·
/// SettlementSurfaceTests 가 문서 주석까지 통째로 같은 사본을 들고 있었다.
@MainActor
func maxLevelStore(_ clock: TestClock, tag: String = "maxlevel",
                   file: StaticString = #filePath, line: UInt = #line) async -> CompanionStore {
    let s = stubStore(clock, tag: tag)
    await s.hatch(baseID: 20)
    s.debugAccrueLevelExperience(PokemonBalance.maxLevelExperience)
    XCTAssertEqual(s.currentLevel, PokemonBalance.maxLevel, "테스트 전제: 만렙에 닿았다", file: file, line: line)
    return s
}
