import XCTest
@testable import PokeTokenBar

final class ChallengeIsolationTests: XCTestCase {
    func testFriendActivitiesNeverRenderInsideTheChallengeTab() {
        XCTAssertFalse(ChallengeView.presentsPokeathlon(phase: .tournament, activity: .tournament))
        XCTAssertFalse(ChallengeView.presentsPokeathlon(phase: .battling, activity: .battle))
        XCTAssertFalse(ChallengeView.presentsPokeathlon(phase: .joined, activity: .gym))
    }

    func testChallengeActivitiesRemainInTheChallengeTab() {
        XCTAssertTrue(ChallengeView.presentsPokeathlon(phase: .idle, activity: nil))
        XCTAssertTrue(ChallengeView.presentsPokeathlon(phase: .joined, activity: .pokeathlon))
        XCTAssertTrue(ChallengeView.presentsPokeathlon(phase: .pokemonQuiz, activity: .pokemonQuiz))
    }
}
