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
    private func makeStore(at url: URL? = nil) -> CompanionStore {
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                           rarity: .common, names: [:])
        let fileURL = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-rank-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                              fileURL: fileURL, rng: SeededRNG(seed: 7))
    }

    /// 같은 세이브 파일을 다시 열어 "앱을 껐다 켠" 상황을 만든다.
    private func relaunch(_ store: CompanionStore) -> CompanionStore { makeStore(at: store.saveFileURL) }

    /// 내 티어가 상대보다 높아야 패배가 LP 를 깎는다(`BattleRank.apply` 의 조건).
    /// 판돈 0 짜리 승리를 쌓아 티어만 올린다 — 지갑은 그대로 0 이다.
    private func storeAtBronze() -> CompanionStore {
        let store = makeStore()
        while store.battleRank.tier == .iron {
            store.settleRankedBrawl(won: true, opponent: BattleRank(points: 0))
        }
        XCTAssertEqual(store.availableTokens, 0, "테스트 전제: 지갑은 비어 있다")
        return store
    }

    func testLosingWithoutEnoughStardustStillCostsRankPoints() {
        let store = storeAtBronze()
        let pointsBefore = store.battleRank.points

        let delta = store.settleRankedBrawl(won: false, opponent: BattleRank(points: 0))

        XCTAssertEqual(store.availableTokens, 0, "에스크로가 없으면 판돈 이동도 없다")
        XCTAssertLessThan(delta, 0, "그래도 패배는 패배다 — LP 는 깎인다")
        XCTAssertLessThan(store.battleRank.points, pointsBefore)
    }

    /// 대조군 — 에스크로를 잡고 지면 판돈과 LP 가 함께 나간다.
    /// 한쪽만 보면 "둘 다 안 나감"도 통과한다.
    func testLosingAfterEscrowPaysTheStakeAndDropsRank() {
        let store = storeAtBronze()
        store.creditStarPieces(9_000)
        XCTAssertTrue(store.escrowRankedBattle(stake: 5_000, opponent: BattleRank(points: 0)))
        let pointsBefore = store.battleRank.points

        let delta = store.settleRankedBrawl(won: false, opponent: BattleRank(points: 0))

        XCTAssertEqual(store.availableTokens, 4_000, "개시 때 빠진 판돈이 그대로다 — 두 번 걷지 않는다")
        XCTAssertLessThan(delta, 0)
        XCTAssertLessThan(store.battleRank.points, pointsBefore)
    }

    // MARK: 에스크로 — 정산 시점을 배틀 끝에서 배틀 시작으로 옮긴다

    /// 회귀(판돈 회피): 정산이 배틀 **끝**에 있어서, 지고 있을 때 앱을 종료하면 내 쪽 정산이 아예
    /// 돌지 않아 판돈을 안 냈다. 상대는 승리 처리로 판돈을 받으니 총량이 늘었다.
    func testEscrowTakesTheStakeUpFront() {
        let store = makeStore()
        store.creditStarPieces(9_000)

        XCTAssertTrue(store.escrowRankedBattle(stake: 5_000, opponent: BattleRank(points: 400)))

        XCTAssertEqual(store.availableTokens, 4_000, "개시 시점에 이미 나간다")
    }

    /// 이기면 내 에스크로가 돌아오고 상대 몫이 더해진다 — 순증은 판돈 1배다.
    func testWinningReturnsTheEscrowPlusTheOpponentStake() {
        let store = makeStore()
        store.creditStarPieces(9_000)
        store.escrowRankedBattle(stake: 5_000, opponent: BattleRank(points: 3_999))
        let pointsBefore = store.battleRank.points

        let delta = store.settleRankedBrawl(won: true, opponent: BattleRank(points: 3_999))

        XCTAssertEqual(store.availableTokens, 14_000, "9,000 − 5,000 + 10,000")
        XCTAssertGreaterThan(delta, 0)
        XCTAssertGreaterThan(store.battleRank.points, pointsBefore)
    }

    /// 무효(끊김 동률·무승부)면 에스크로만 돌려주고 랭크는 그대로다.
    func testANoContestRefundsTheEscrowAndLeavesRankAlone() {
        let store = storeAtBronze()
        store.creditStarPieces(9_000)
        store.escrowRankedBattle(stake: 5_000, opponent: BattleRank(points: 0))
        let pointsBefore = store.battleRank.points

        store.refundRankedEscrow()

        XCTAssertEqual(store.availableTokens, 9_000, "판돈이 돌아온다")
        XCTAssertEqual(store.battleRank.points, pointsBefore, "무효는 승패가 아니다")
    }

    /// **B 의 핵심**: 배틀 중에 앱이 죽으면 다음 실행이 그 배틀을 패배로 정산한다.
    /// 크래시와 고의 종료는 로컬에서 구분할 수 없으므로 랭크 게임의 통상 규칙을 따른다 —
    /// 환급으로 두면 "지고 있으면 종료"가 다시 최적해가 된다.
    func testAbandonedRankedBattleIsSettledAsALossOnNextLaunch() {
        let store = storeAtBronze()
        store.creditStarPieces(9_000)
        store.escrowRankedBattle(stake: 5_000, opponent: BattleRank(points: 0))
        let pointsBefore = store.battleRank.points

        let next = relaunch(store)          // 정산 없이 앱이 죽었다

        XCTAssertEqual(next.availableTokens, 4_000, "에스크로는 돌아오지 않는다")
        XCTAssertLessThan(next.battleRank.points, pointsBefore, "미결 배틀은 패배로 정산된다")
        XCTAssertFalse(next.hasPendingRankedBattle, "한 번만 정산된다")
        XCTAssertEqual(relaunch(next).battleRank.points, next.battleRank.points,
                       "다음 실행에서 또 깎이지 않는다")
    }

    /// 잔액이 판돈에 못 미치면 에스크로를 잡지 않는다 — 호출부가 이 false 로 배틀을 시작하지 않는다.
    /// (빚을 지고 배틀에 들어가면 정산이 뒷받침되지 않는다.)
    func testEscrowIsRefusedWhenTheWalletIsShort() {
        let store = makeStore()
        store.creditStarPieces(1_000)

        XCTAssertFalse(store.escrowRankedBattle(stake: 5_000, opponent: BattleRank(points: 400)))

        XCTAssertEqual(store.availableTokens, 1_000, "실패한 에스크로는 지갑을 건드리지 않는다")
        XCTAssertFalse(store.hasPendingRankedBattle)
    }

    /// 판돈 0(같은 티어끼리)이어도 에스크로는 잡힌다 — 종료 이탈의 **LP** 대가가 걸려 있다.
    func testAZeroStakeBattleStillRecordsAnEscrowSoLeavingCostsRank() {
        let store = storeAtBronze()
        let pointsBefore = store.battleRank.points

        XCTAssertTrue(store.escrowRankedBattle(stake: 0, opponent: BattleRank(points: 0)))
        let next = relaunch(store)

        XCTAssertLessThan(next.battleRank.points, pointsBefore)
    }

    /// 1v1 경로가 실제로 에스크로를 지나는지 — `beginBattle` 은 private 이고 `NWConnection` 이
    /// 필요해 인스턴스를 세울 수 없으므로 소스로 고정한다(방 판정 가드와 같은 방식).
    func testTheOneOnOnePathEscrowsAtStartAndRefundsANoContest() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeTokenBar/Core/BattleNet.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("escrowRankedBattle("), "개시 때 판돈을 잡는다")
        XCTAssertTrue(source.contains("refundRankedEscrow()"), "무효면 돌려준다")
    }
}
