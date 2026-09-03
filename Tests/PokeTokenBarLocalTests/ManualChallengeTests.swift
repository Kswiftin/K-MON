import Foundation
import Testing
@testable import PokeTokenBar

/// mDNS 가 막힌 환경(사내망 등)의 폴백. 신청은 **후보 6마리를 요구**하는데, 수동 IP 화면에는
/// 고를 자리가 없어 폴백이 항상 "먼저 후보 포켓몬 6마리를 선택하세요" 로 끝났다. 화면은 이제
/// 탐색으로 찾은 상대와 같은 후보 선택 화면을 지난다 — 그 계약을 여기서 못 박는다.
@Suite struct ManualChallengeTests {

    /// 주소 판정은 화면과 신청이 **같은 함수**를 봐야 한다. 화면이 따로 짜면 후보를 다 고른 뒤에야
    /// 주소가 틀렸다는 말을 듣는다.
    @Test func addressesAreParsedByOneSharedRule() {
        #expect(BattleCenter.manualEndpoint("192.168.0.2:52000") != nil)
        #expect(BattleCenter.manualEndpoint(" 192.168.0.2:52000 ") != nil)
        #expect(BattleCenter.manualEndpoint("192.168.0.2") == nil)
        #expect(BattleCenter.manualEndpoint(":52000") == nil)
        #expect(BattleCenter.manualEndpoint("192.168.0.2:99999") == nil, "포트는 16비트다")
        #expect(BattleCenter.manualEndpoint("192.168.0.2:port") == nil)
        #expect(BattleCenter.manualEndpoint("") == nil)
    }

    /// 화면이 이 판정을 먼저 물어야 하는 이유 — 후보를 고르지 않은 신청은 거절된다.
    @Test func challengingWithoutSixCandidatesIsRefused() async {
        let store = await MainActor.run { manualChallengeStore() }
        let center = await MainActor.run { BattleCenter(companion: store) }
        await MainActor.run {
            center.pickedTeam = []
            center.challengeManual("127.0.0.1:52000")
            #expect(center.lastError != nil, "후보 없이 신청이 통과하면 상대가 빈 팀을 받는다")
        }
    }
}

@MainActor
private func manualChallengeStore() -> CompanionStore {
    let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                       names: [1: ["ko": "포1", "en": "P1", "ja": "ポ1"]])
    return CompanionStore(provider: ManualChallengeProvider(value: line),
                          clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                          fileURL: storeFixtureStateURL("manual-challenge"),
                          rng: ManualChallengeRNG(seed: 1))
}

private struct ManualChallengeProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        id == value.baseID ? BaseSpecies(id: id, captureRate: 255) : nil
    }
}

private struct ManualChallengeRNG: RandomNumberGenerator {
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
