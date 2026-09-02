import Foundation
import Testing
@testable import PokeTokenBar

/// 터미널 프런트엔드는 메뉴바 앱과 **같은 세이브 파일**을 연다. 그 자체가 두 가지 위험이다:
/// ⓐ 세이브를 여는 것만으로 "앱이 죽은 사이 밀린 일"(랭크전 패배 정산·끝난 모험 정산)이 돌고
/// ⓑ 두 프로세스 사이에 잠금이 없어 나중 쓰기가 앞 쓰기를 통째로 덮는다.
/// 읽기 전용 생성 경로가 둘 다 막는지 본다.
@MainActor
@Suite struct ReadOnlyStoreTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("read-only-store-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func store(at directory: URL, readOnly: Bool) -> CompanionStore {
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                           names: [1: ["ko": "포1", "en": "P1", "ja": "ポ1"]])
        return CompanionStore(provider: ReadOnlyStubProvider(value: line), clock: { Self.now },
                              fileURL: directory.appendingPathComponent("state.json"),
                              rng: ReadOnlyRNG(seed: 1), isReadOnly: readOnly)
    }

    /// 판돈이 걸린 랭크전을 남긴 세이브를 만든다.
    private func seedPendingRankedBattle(in directory: URL) async -> Int {
        let store = store(at: directory, readOnly: false)
        await store.hatch(baseID: 1)
        store.creditStarPieces(1_000)
        #expect(store.escrowRankedBattle(stake: 100, opponent: BattleRank()))
        #expect(store.hasPendingRankedBattle)
        return store.availableTokens
    }

    /// **이 테스트가 이 기능의 존재 이유다.** 앱이 랭크전 중일 때 터미널이 같은 세이브를 열면,
    /// 읽기 전용이 아니면 그 배틀이 패배로 정산된다 — 사용자는 배틀을 하는 도중에 진다.
    @Test func openingASaveReadOnlyDoesNotSettleTheRankedBattleTheAppIsPlaying() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = await seedPendingRankedBattle(in: directory)

        let reader = store(at: directory, readOnly: true)
        #expect(reader.hasPendingRankedBattle, "터미널이 열었다는 이유로 진행 중인 랭크전이 정산됐다")
    }

    /// 가드가 헛돌지 않는다는 근거 — 평소 경로에서는 그대로 정산돼야 한다(앱이 죽은 뒤의 기동).
    @Test func openingASaveNormallyStillSettlesAnAbandonedBattle() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = await seedPendingRankedBattle(in: directory)

        let restarted = store(at: directory, readOnly: false)
        #expect(!restarted.hasPendingRankedBattle)
    }

    /// 기동 시 정산을 건너뛰는 것만으로는 부족하다 — 화면을 그리다 부수효과가 있는 계산을 밟아도
    /// 세이브가 나가면 앱이 올린 진행을 덮는다. 쓰기 경로 자체가 막혀 있는지 **파일 내용**으로 본다.
    @Test func aReadOnlyStoreNeverWritesTheSaveFile() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = await seedPendingRankedBattle(in: directory)
        let fileURL = directory.appendingPathComponent("state.json")
        let before = try Data(contentsOf: fileURL)

        let reader = store(at: directory, readOnly: true)
        reader.setLanguage(.en)                 // 평소라면 저장을 부르는 가장 짧은 경로
        reader.creditStarPieces(5_000)
        #expect(!reader.saveFailed, "쓰기를 시도조차 하지 않으므로 실패도 없어야 한다")

        #expect(try Data(contentsOf: fileURL) == before, "읽기 전용 저장소가 세이브를 덮어썼다")
    }
}

private struct ReadOnlyStubProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        id == value.baseID ? BaseSpecies(id: id, captureRate: 255) : nil
    }
}

private struct ReadOnlyRNG: RandomNumberGenerator {
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
