import Foundation
import Testing
@testable import PokeTokenBar

/// 방 개설·참가는 `await` 를 지나 끝난다. 그 사이 사용자는 나가기를 누를 수 있고(체육관 타이머도
/// `leaveRoom()` 을 부른다), 깨어난 작업이 그 사실을 안 보면 이미 정리된 방에 계속 손을 댄다 —
/// 실제 증상은 닫았다고 믿는 방이 LAN 에 남아 이후 모든 개설·참가가 조용히 거절되는 것이다.
@MainActor
@Suite struct RoomSessionEpochTests {
    private func makeStore() -> CompanionStore {
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                           names: [1: ["ko": "포1", "en": "P1", "ja": "ポ1"]])
        return CompanionStore(provider: RoomEpochStubProvider(value: line),
                              clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                              fileURL: storeFixtureStateURL("room-epoch"),
                              rng: RoomEpochRNG(seed: 1))
    }

    /// 동행이 없는 저장소는 `buildSnapshot()` 이 첫 `await` 뒤 곧바로 nil 을 돌려준다 — 그 지점이
    /// 결함이 사는 자리다(작업이 깨어나 국면과 오류 문구를 쓴다).
    @Test func aRoomLeftDuringSetupIsNotTouchedByTheTaskThatWakesUpLater() async {
        let center = MultiplayerRoomCenter(companion: makeStore())
        center.startSoloPokeathlon()
        #expect(center.phase == .creating)

        center.leaveRoom()
        #expect(center.phase == .idle)

        // 개설 작업이 깨어난다. 이미 떠난 방에는 아무것도 쓰지 않아야 한다.
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(center.phase == .idle)
        #expect(center.lastError == nil, "떠난 방의 작업이 화면에 오류를 남겼다")
        #expect(center.pokeathlonRace == nil)
    }

    /// 나가지 않았으면 그대로 끝난다 — 위 가드가 정상 경로까지 막으면 개설이 영영 안 끝난다.
    @Test func aRoomThatIsNotLeftStillReportsItsFailure() async {
        let center = MultiplayerRoomCenter(companion: makeStore())
        center.startSoloPokeathlon()

        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(center.phase == .idle)
        #expect(center.lastError != nil, "동행이 없어 개설이 실패했는데 화면에 이유가 없다")
    }
}

private struct RoomEpochStubProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        id == value.baseID ? BaseSpecies(id: id, captureRate: 255) : nil
    }
}

private struct RoomEpochRNG: RandomNumberGenerator {
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
