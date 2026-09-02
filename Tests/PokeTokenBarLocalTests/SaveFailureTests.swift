import Foundation
import Testing
@testable import PokeTokenBar

/// 저장 실패는 **화면까지** 올라와야 한다. `save()` 는 거의 모든 상태 변경 뒤에 불리는 유일한
/// 영속화 경로라, 디스크가 차거나 권한이 막혔을 때 덮어두면 진행이 조용히 사라지고 사용자는
/// 다음 기동에서야 알아차린다(그때는 추적할 단서도 없다).
@MainActor
@Suite struct SaveFailureTests {
    private func store(at fileURL: URL) -> CompanionStore {
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                           names: [1: ["ko": "포1", "en": "P1", "ja": "ポ1"]])
        return CompanionStore(provider: SaveFailureStubProvider(value: line),
                              clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                              fileURL: fileURL, rng: SaveFailureRNG(seed: 1))
    }

    /// 쓸 수 없는 경로. 세이브 자리에 **디렉터리**가 앉아 있어 `write(to:options:.atomic)` 가
    /// 실패한다(상위 디렉터리는 저장소가 스스로 만들므로 없는 경로로는 실패시킬 수 없다).
    @Test func aFailedWriteRaisesTheFlagTheHomeScreenReads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-failure-\(UUID().uuidString)")
        let unwritable = directory.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: unwritable, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store(at: unwritable)
        #expect(!store.saveFailed, "아직 아무것도 저장하지 않았다")

        store.setLanguage(.en)   // 저장을 부르는 가장 짧은 경로

        #expect(store.saveFailed, "저장이 실패했는데 화면이 읽을 신호가 없다")
    }

    /// 쓸 수 있는 경로에서는 깃발이 서지 않는다 — 서면 경고가 상시 표시가 돼 아무 의미가 없다.
    @Test func aSuccessfulWriteLeavesTheFlagDown() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-ok-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = store(at: directory.appendingPathComponent("state.json"))
        store.setLanguage(.en)

        #expect(!store.saveFailed)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("state.json").path))
    }
}

private struct SaveFailureStubProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        id == value.baseID ? BaseSpecies(id: id, captureRate: 255) : nil
    }
}

private struct SaveFailureRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
