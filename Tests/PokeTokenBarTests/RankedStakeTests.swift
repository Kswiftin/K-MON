import XCTest
@testable import PokeTokenBar

/// 랭크전 정산 — 판돈(화폐)과 LP(실력 지표)는 다른 자원이다.
///
/// 회귀: `settleRankedBrawl` 이 판돈을 못 내면 그 자리에서 `return 0` 해서 **그 뒤의 LP 차감까지
/// 건너뛰었다.** 지갑을 판돈 아래로 비워 두면 랭크전에서 절대 LP 를 잃지 않는 무손실 랭크가 됐다.
@MainActor
final class RankedStakeTests: XCTestCase {

    /// 정산은 활성 포켓몬을 요구하지 않으므로(`settleRankedBrawl` 은 지갑과 랭크만 본다) 라인은
    /// 최소 형태로 둔다. `StubProvider`·`SeededRNG` 는 `CompanionTests.swift` 의 헬퍼다.
    private func makeStore() -> CompanionStore {
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                           rarity: .common, names: [:])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-rank-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    /// 내 티어가 상대보다 높아야 패배가 LP 를 깎는다(`BattleRank.apply` 의 조건).
    /// 판돈 0 짜리 승리를 쌓아 티어만 올린다 — 지갑은 그대로 0 이다.
    private func storeAtBronze() -> CompanionStore {
        let store = makeStore()
        while store.battleRank.tier == .iron {
            store.settleRankedBrawl(won: true, opponent: BattleRank(points: 0), stake: 0)
        }
        XCTAssertEqual(store.availableTokens, 0, "테스트 전제: 지갑은 비어 있다")
        return store
    }

    func testLosingWithoutEnoughStardustStillCostsRankPoints() {
        let store = storeAtBronze()
        let pointsBefore = store.battleRank.points

        let delta = store.settleRankedBrawl(won: false, opponent: BattleRank(points: 0), stake: 5_000)

        XCTAssertEqual(store.availableTokens, 0, "낼 수 없는 판돈은 안 나간다(빚을 지지 않는다)")
        XCTAssertLessThan(delta, 0, "그래도 패배는 패배다 — LP 는 깎인다")
        XCTAssertLessThan(store.battleRank.points, pointsBefore)
    }

    /// 대조군 — 낼 수 있으면 판돈과 LP 가 함께 나간다. 한쪽만 보면 "둘 다 안 나감"도 통과한다.
    func testLosingWithEnoughStardustPaysTheStakeAndDropsRank() {
        let store = storeAtBronze()
        store.creditStarPieces(9_000)
        let pointsBefore = store.battleRank.points

        let delta = store.settleRankedBrawl(won: false, opponent: BattleRank(points: 0), stake: 5_000)

        XCTAssertEqual(store.availableTokens, 4_000, "판돈이 나간다")
        XCTAssertLessThan(delta, 0)
        XCTAssertLessThan(store.battleRank.points, pointsBefore)
    }

    /// 승리는 판돈을 받고 LP 를 올린다 — 정산 방향이 뒤집히지 않았는지 본다.
    func testWinningCreditsTheStakeAndRaisesRank() {
        let store = makeStore()
        let pointsBefore = store.battleRank.points

        let delta = store.settleRankedBrawl(won: true, opponent: BattleRank(points: 3_999), stake: 5_000)

        XCTAssertEqual(store.availableTokens, 5_000)
        XCTAssertGreaterThan(delta, 0)
        XCTAssertGreaterThan(store.battleRank.points, pointsBefore)
    }
}
