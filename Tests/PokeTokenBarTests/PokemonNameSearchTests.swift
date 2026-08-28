import XCTest
@testable import PokeTokenBar

final class PokemonNameSearchTests: XCTestCase {
    func testEmptyQueryMatchesEveryPokemon() {
        XCTAssertTrue(PokemonNameSearch.matches("", names: ["피카츄"]))
        XCTAssertTrue(PokemonNameSearch.matches("   ", names: ["Pikachu"]))
    }

    func testSearchIsPartialCaseAndSeparatorInsensitive() {
        XCTAssertTrue(PokemonNameSearch.matches("PIKA", names: ["Pikachu"]))
        XCTAssertTrue(PokemonNameSearch.matches("mimejr", names: ["Mime Jr."]))
        XCTAssertTrue(PokemonNameSearch.matches("farfetchd", names: ["Farfetch’d"]))
    }

    func testAnyLocalizedNameOrNicknameCanMatch() {
        XCTAssertTrue(PokemonNameSearch.matches("피카", names: ["Pikachu", "피카츄", "ピカチュウ"]))
        XCTAssertTrue(PokemonNameSearch.matches("내친구", names: ["Pikachu", "내친구"]))
        XCTAssertFalse(PokemonNameSearch.matches("꼬부기", names: ["Pikachu", "피카츄"]))
    }
}
