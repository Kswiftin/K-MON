import XCTest
@testable import PokeTokenBar

/// 즐겨찾기는 표시가 아니라 **자물쇠**다 — 켜져 있으면 그 개체를 잃는 동작(놓아주기·경매 출품)이
/// 막힌다. 라인 로딩과 무관하므로 항상 throw 하는 provider 로 충분하다.
private struct FavoriteNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class FavoriteMonTests: XCTestCase {

    /// 활성 1마리 + 박스 1마리. 놓아주기는 박스 개체만 대상이라 둘 다 필요하다.
    private func store(file: URL? = nil) -> CompanionStore {
        let url = file ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("favorite-\(UUID().uuidString).json")
        let mon = "{\"baseID\":4,\"pathIDs\":[4],\"stageIndex\":0,\"usedAtStage\":0,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"learnedMoves\":[]}"
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,"
            + "\"installBaselineSet\":true,\"starPieces\":0,\"lastDate\":\"d\",\"dex\":[],"
            + "\"collectedFinals\":[],\"active\":\(mon),\"boxedMons\":[\(mon)]}"
        try? Data(json.utf8).write(to: url)
        return CompanionStore(provider: FavoriteNoProvider(), fileURL: url, rng: SeededRNG(seed: 1))
    }

    private func boxedID(_ companion: CompanionStore) throws -> UUID {
        let boxed = try XCTUnwrap(companion.state.boxedMons.first)
        return boxed.id
    }

    // MARK: 토글

    func testToggleTurnsFavoriteOnAndOff() throws {
        let companion = store()
        let id = try boxedID(companion)
        XCTAssertFalse(companion.isFavorite(id))
        XCTAssertTrue(companion.toggleFavorite(id))
        XCTAssertTrue(companion.isFavorite(id))
        XCTAssertTrue(companion.toggleFavorite(id))
        XCTAssertFalse(companion.isFavorite(id))
    }

    /// 소유하지 않은 개체는 즐겨찾기할 수 없다 — 세이브에 주인 없는 ID 가 쌓이는 경로를 막는다.
    func testToggleRejectsUnownedID() {
        let companion = store()
        XCTAssertFalse(companion.toggleFavorite(UUID()))
        XCTAssertTrue(companion.state.favoriteMonIDs.isEmpty)
    }

    func testFavoritePersistsAcrossRestart() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("favorite-persist-\(UUID().uuidString).json")
        let first = store(file: url)
        let id = try boxedID(first)
        XCTAssertTrue(first.toggleFavorite(id))

        let reloaded = CompanionStore(provider: FavoriteNoProvider(), fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertTrue(reloaded.isFavorite(id))
    }

    /// 즐겨찾기 필드가 없던 구버전 세이브도 그대로 읽힌다(기본값 빈 집합).
    func testOldSaveWithoutFavoritesDecodesEmpty() throws {
        let state = try JSONDecoder().decode(CompanionState.self, from: Data("{}".utf8))
        XCTAssertTrue(state.favoriteMonIDs.isEmpty)
    }

    // MARK: 놓아주기 잠금

    func testFavoritedMonCannotBeReleased() throws {
        let companion = store()
        let id = try boxedID(companion)
        XCTAssertTrue(companion.toggleFavorite(id))
        XCTAssertFalse(companion.releaseMon(id))
        XCTAssertTrue(companion.ownedMons.contains { $0.id == id })
    }

    /// 별을 끄면 곧바로 풀린다 — 잠금과 해제가 같은 스위치다.
    func testReleaseWorksAfterUnfavoriting() throws {
        let companion = store()
        let id = try boxedID(companion)
        XCTAssertTrue(companion.toggleFavorite(id))
        XCTAssertTrue(companion.toggleFavorite(id))
        XCTAssertTrue(companion.releaseMon(id))
        XCTAssertFalse(companion.ownedMons.contains { $0.id == id })
    }

    // MARK: 경매 출품 잠금

    func testFavoritedMonCannotBeListedOnTheAuction() throws {
        let companion = store()
        let boxed = try XCTUnwrap(companion.state.boxedMons.first)
        let auction = PokemonAuctionCenter(companion: companion)
        XCTAssertTrue(companion.toggleFavorite(boxed.id))
        auction.publish(boxed)
        XCTAssertNil(auction.localListing, "즐겨찾기한 개체는 게시되지 않는다")

        XCTAssertTrue(companion.toggleFavorite(boxed.id))
        auction.publish(boxed)
        XCTAssertNotNil(auction.localListing, "별을 끄면 게시된다")
    }

    // MARK: 소유가 바뀌면 자국을 지운다

    /// 교환으로 나간 개체의 즐겨찾기 ID 는 남지 않는다. 남아도 오답을 내지는 않지만 세이브에 계속
    /// 쌓이므로, 소유가 바뀌는 자리에서 함께 정리한다.
    func testTradingAwayAFavoriteClearsItsMark() throws {
        let companion = store()
        let id = try boxedID(companion)
        XCTAssertTrue(companion.toggleFavorite(id))

        let incoming = MonState(baseID: 25, pathIDs: [25], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 2)
        XCTAssertTrue(companion.performTrade(offeredID: id, received: incoming))
        XCTAssertFalse(companion.isFavorite(id))
        XCTAssertTrue(companion.state.favoriteMonIDs.isEmpty)
    }
}
