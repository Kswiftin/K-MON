import Foundation
import XCTest
@testable import PokeTokenBar

final class ChallengeIsolationTests: XCTestCase {
    func testChallengeScreenNoLongerExposesPokeathlonOrQuiz() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/PokeTokenBar/UI/ChallengeView.swift"),
                                encoding: .utf8)
        XCTAssertFalse(source.contains("PokeathlonView"))
        XCTAssertFalse(source.contains("createPokeathlonRoom"))
        XCTAssertFalse(source.contains("createPokemonQuizRoom"))
    }
}
