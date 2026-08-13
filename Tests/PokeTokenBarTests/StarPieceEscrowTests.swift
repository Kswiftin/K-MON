import XCTest
@testable import PokeTokenBar

/// 라인 로딩이 필요 없는 지갑 테스트용 provider(ShopTests 와 같은 패턴).
private struct EscrowNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

// MARK: 별조각 에스크로 — 베팅 차감/지급 (관전자 베팅의 세이브측 경로)

@MainActor
final class StarPieceEscrowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// `forcedResetVersion` 을 반드시 현재 값으로 넣는다 — 빠뜨리면 로드 시점에 세이브가 통째로
    /// 초기화돼(`CompanionStore.load` 의 배포 강제 초기화) 잔액이 0 이 되고, 테스트는 아무것도
    /// 검증하지 않은 채 통과할 수 있다.
    private func seed(starPieces: Int) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("escrow-\(UUID().uuidString).json")
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":\(SaveTransfer.forcedResetVersion),"
            + "\"installBaselineSet\":true,\"starPieces\":\(starPieces),"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        return url
    }

    /// starPieces 를 직접 지정한 세이브를 만들어 로드 — 잔액을 결정적으로 세팅.
    private func store(starPieces: Int) -> CompanionStore {
        CompanionStore(provider: EscrowNoProvider(), clock: { self.now },
                       fileURL: seed(starPieces: starPieces), rng: SeededRNG(seed: 1))
    }

    func testEscrowDeductsWhenAffordable() {
        let s = store(starPieces: 100)
        XCTAssertTrue(s.escrowStarPieces(30))
        XCTAssertEqual(s.availableTokens, 70)
    }

    func testEscrowRefusesWhenBalanceIsTooLow() {
        let s = store(starPieces: 10)
        XCTAssertFalse(s.escrowStarPieces(11))
        XCTAssertEqual(s.availableTokens, 10, "실패한 에스크로가 잔액을 건드리면 안 된다")
    }

    func testEscrowIgnoresNonPositiveAmounts() {
        let s = store(starPieces: 10)
        XCTAssertFalse(s.escrowStarPieces(0))
        XCTAssertFalse(s.escrowStarPieces(-5))
        XCTAssertEqual(s.availableTokens, 10)
    }

    func testCreditAddsPayout() {
        let s = store(starPieces: 10)
        s.creditStarPieces(25)
        XCTAssertEqual(s.availableTokens, 35)
        s.creditStarPieces(0); s.creditStarPieces(-9)
        XCTAssertEqual(s.availableTokens, 35, "0·음수 지급은 무시된다")
    }

    /// 차감 → 환불(= 판돈과 같은 금액 지급)이면 원래 잔액으로 정확히 돌아온다.
    func testEscrowThenRefundIsBalanceNeutral() {
        let s = store(starPieces: 77)
        XCTAssertTrue(s.escrowStarPieces(41))
        s.creditStarPieces(41)
        XCTAssertEqual(s.availableTokens, 77)
    }

    /// 세이브에 반영돼야 한다 — 앱을 다시 켜도 차감이 남아 있어야 이중 지급이 없다.
    func testEscrowPersistsAcrossReload() {
        let url = seed(starPieces: 50)
        let first = CompanionStore(provider: EscrowNoProvider(), clock: { self.now }, fileURL: url,
                                   rng: SeededRNG(seed: 1))
        XCTAssertTrue(first.escrowStarPieces(20))
        let reloaded = CompanionStore(provider: EscrowNoProvider(), clock: { self.now }, fileURL: url,
                                      rng: SeededRNG(seed: 1))
        XCTAssertEqual(reloaded.availableTokens, 30)
    }
}
