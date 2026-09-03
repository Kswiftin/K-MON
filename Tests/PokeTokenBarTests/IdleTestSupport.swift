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

// MARK: 스토어 픽스처 격리 (디렉토리 단위)

extension XCTestCase {
    /// 스토어마다 **디렉토리**를 판다 — 픽스처가 쓸 수 있는 유일한 temp 경로다.
    ///
    /// `CompanionStore` 는 기억 앨범·대화 세이브·진행 중인 웨이브 런을 상태 파일 *옆에* **이름이
    /// 고정된** 채로 만든다(`CompanionStorageLocations`). 그러니 상태 파일 이름만 유일하게 하고
    /// 공용 temp 디렉토리에 두면 **격리가 되지 않는다** — 곁방 셋은 모든 픽스처가 하나를 공유하고,
    /// temp 는 실행 사이에도 지워지지 않아 `swift test` 를 다시 돌려도 남는다. 앞선 실행의 대표
    /// 사진이 다음 실행의 방문 카드에 실려 실제로 한 번 터졌다(#232).
    ///
    /// 디렉토리를 **미리 만든다**: 손상 세이브 픽스처는 스토어보다 먼저 `write(to:)` 하므로
    /// (`CompanionTests` 의 `poke-corrupt`) 스토어의 `createDirectory` 를 기다릴 수 없다.
    func storeDirectory(_ tag: String = "store") -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// 갓 판 디렉토리 안의 상태 파일. 픽스처 대부분은 스토어 URL 하나만 필요하므로 이쪽을 쓴다 —
    /// 디렉토리 자체가 필요한 것(세이브 이전·곁방 파일을 직접 읽는 테스트)만 `storeDirectory`.
    func storeStateURL(_ tag: String = "store") -> URL {
        storeDirectory(tag).appendingPathComponent(CompanionStorageLocations.stateFileName)
    }

    @MainActor
    func stubStore(_ clock: TestClock, tag: String = "store") -> CompanionStore {
        CompanionStore(provider: StubProvider(value: stubMaxLevelLine), clock: clock.closure,
                       fileURL: storeStateURL(tag), rng: SeededRNG(seed: 7))
    }
}

extension XCTestCase {
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
        XCTAssertEqual(s.currentLevel, PokemonBalance.maxLevel, "테스트 전제: 만렙에 닿았다",
                       file: file, line: line)
        return s
    }
}

// MARK: 3단 진화 라인 시드 (체인 중간·끝에서 시작하는 개체를 세우는 테스트가 공유한다)

/// 뿌리부터 최종체까지 3단인 라인(443 → 444 → 445). **`stubMaxLevelLine` 으로는 못 밟는 부류가
/// 있다** — 그 시드는 어떤 종을 물어도 단일 노드 트리 하나를 돌려주므로, "저장된 경로가 트리
/// 뿌리에서 시작하지 않는다" 는 조건이 테스트에서 영원히 성립하지 않는다. 실제 클라이언트의
/// `line(baseSpeciesID:)` 는 요청한 종이 최종체여도 **체인 전체**를 뿌리부터 싣고 온다
/// (`PokeAPIClient.line` → `evoNode(from: chainDTO.chain)`).
let stubThreeStageLine = EvoLine(
    baseID: 443,
    tree: EvoNode(speciesID: 443,
                  children: [EvoNode(speciesID: 444,
                                     children: [EvoNode(speciesID: 445, children: [])])]),
    rarity: .rare,
    names: [443: ["en": "P443", "ko": "포443", "ja": "ポ443"],
            444: ["en": "P444", "ko": "포444", "ja": "ポ444"],
            445: ["en": "P445", "ko": "포445", "ja": "ポ445"]])

extension XCTestCase {
    @MainActor
    func threeStageStore(_ clock: TestClock, tag: String = "three-stage") -> CompanionStore {
        CompanionStore(provider: StubProvider(value: stubThreeStageLine), clock: clock.closure,
                       fileURL: storeStateURL(tag), rng: SeededRNG(seed: 7))
    }
}
