import XCTest
@testable import PokeTokenBar

/// 픽스처 격리 계약 — **스토어 픽스처는 디렉토리 단위로 격리된다.**
///
/// `CompanionStore` 는 기억 앨범·대화 세이브·진행 중인 웨이브 런을 상태 파일 *옆에* **이름이 고정된**
/// 채로 만든다(`CompanionStorageLocations`). 그래서 상태 파일 이름만 유일하게 하고 공용 temp
/// 디렉토리에 두면 곁방 셋은 모든 테스트가 하나를 공유한다 — temp 는 실행 사이에도 지워지지 않으니
/// `swift test` 를 다시 돌려도 남는다(#232, `MemoryHomeShowcaseTests` 가 실제로 밟았다).
///
/// **이 파일이 잠그는 것은 소스가 아니라 픽스처 헬퍼다.** `storeStateURL`/`storeDirectory` 가
/// 디렉토리를 파는 성질을 잃으면(예: 다시 파일만 유일하게 하면) 아래 테스트가 깨진다 — 곁방이
/// 새는 것을 조용히 되돌리지 못하게 하는 유일한 자리다. 게이트(`test-gate.sh` 의 픽스처 격리
/// 스윕)는 "헬퍼를 안 쓰는 픽스처" 를 막고, 이 테스트는 "헬퍼가 격리를 실제로 하는가" 를 막는다.
@MainActor
final class StoreFixtureIsolationTests: XCTestCase {

    private let line = EvoLine(baseID: 20, tree: EvoNode(speciesID: 20, children: []),
                               rarity: .common, names: [20: ["en": "P20", "ko": "포20"]])

    private func store(at url: URL) -> CompanionStore {
        CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                       fileURL: url, rng: SeededRNG(seed: 7))
    }

    /// 앞 픽스처가 적은 기억이 다음 픽스처의 앨범에 보이면 안 된다. 새 세이브는 앨범 정리
    /// (`prune`)를 타지 않으므로, 파일이 공유되면 남의 기억이 그대로 살아 있다.
    func testOneFixtureStoreCannotSeeAnothersMemories() async throws {
        let first = store(at: storeStateURL("iso-memories-a"))
        await first.hatch(baseID: 20)
        let mon = try XCTUnwrap(first.state.active)
        XCTAssertTrue(first.memoryAlbum.record(companionID: mon.id, body: "앞 테스트의 기억",
                                               source: .event, eventID: "iso-a"),
                      "테스트 전제: 첫 스토어에 기억이 실제로 적혔다")

        let second = store(at: storeStateURL("iso-memories-b"))
        XCTAssertTrue(second.memoryAlbum.entries(for: mon.id).isEmpty,
                      "픽스처가 앨범 파일을 공유한다 — 곁방 세이브는 이름이 고정이라 디렉토리를 나눠야 격리된다")
    }

    /// 진행 중인 런은 **기동 시 되살아난다**(`loadRogueRun`). 그래서 이 곁방은 앨범보다 더
    /// 직접적이다 — 파일이 공유되면 남의 판이 다음 스토어의 `rogueRun` 으로 그냥 올라온다.
    func testOneFixtureStoreCannotRestoreAnothersWaveRun() {
        let snapshot = BattleSnapshot(speciesID: 1, name: "M1", trainer: "T", level: 5, nature: nil,
                                      isShiny: false, types: [.normal],
                                      base: BattleStats(hp: 100, atk: 100, def: 50,
                                                        spa: 100, spd: 50, spe: 100),
                                      moves: [MoveSpec(id: 1, names: ["en": "Hit"], type: .normal,
                                                       power: 200, damageClass: .physical,
                                                       accuracy: nil, pp: 20)])
        let first = store(at: storeStateURL("iso-run-a"))
        first.rogueRun = RogueRun(party: [snapshot], opponents: [snapshot], seed: 5)
        XCTAssertNotNil(first.rogueRun, "테스트 전제: 첫 스토어에 판이 실제로 저장됐다")

        XCTAssertNil(store(at: storeStateURL("iso-run-b")).rogueRun,
                     "픽스처가 웨이브 런 파일을 공유한다 — 다음 스토어가 남의 판을 되살렸다")
    }

    /// 헬퍼가 준 두 경로는 **다른 디렉토리**여야 한다. 위 두 테스트는 곁방 파일을 하나씩만 보므로,
    /// 곁방이 하나 더 늘 때(네 번째 고정 이름) 그 새 파일은 아무 테스트도 보지 않는다 — 계약을
    /// 파일별로 세지 않고 디렉토리로 한 번 못 박아 그 공백을 닫는다.
    func testTheHelperGivesEachStoreItsOwnDirectory() {
        let a = storeStateURL("iso-dir")
        let b = storeStateURL("iso-dir")
        XCTAssertNotEqual(a.deletingLastPathComponent(), b.deletingLastPathComponent(),
                          "같은 tag 로 두 번 불렀는데 같은 디렉토리가 나왔다")
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.deletingLastPathComponent().path),
                      "디렉토리를 미리 만들지 않으면 스토어보다 먼저 write(to:) 하는 손상 세이브 픽스처가 던진다")
    }
}
