import XCTest
@testable import PokeTokenBar

final class PokemonOXQuizTests: XCTestCase {
    private let left = UUID()
    private let right = UUID()

    private func game(answer: Bool) -> PokemonOXGame {
        PokemonOXGame(players: [
            PokemonOXPlayer(id: left, trainerName: "Left", speciesID: 1, position: -1),
            PokemonOXPlayer(id: right, trainerName: "Right", speciesID: 25, position: 1),
        ], questions: [PokemonOXQuestion(id: 999, ko: "", en: "", ja: "", answer: answer)], startsAt: .now)
    }

    func testCorrectPlatformAwardsTenPoints() {
        var quiz = game(answer: true)
        quiz.reveal()
        XCTAssertEqual(quiz.players.first(where: { $0.id == right })?.score, 10)
        XCTAssertEqual(quiz.players.first(where: { $0.id == left })?.score, 0)
        XCTAssertEqual(quiz.players.first(where: { $0.id == right })?.lastCorrect, true)
    }

    func testMovementIsClampedToArena() {
        var quiz = game(answer: false)
        for _ in 0..<30 { quiz.move(.right, playerID: left) }
        XCTAssertEqual(quiz.players.first(where: { $0.id == left })?.position, 1)
        for _ in 0..<30 { quiz.move(.left, playerID: left) }
        XCTAssertEqual(quiz.players.first(where: { $0.id == left })?.position, -1)
    }

    func testTenQuestionsFinishAndStandingsUseScore() {
        var quiz = PokemonOXGame(players: [
            PokemonOXPlayer(id: left, trainerName: "A", speciesID: 1, position: -1),
            PokemonOXPlayer(id: right, trainerName: "B", speciesID: 25, position: 1),
        ], questions: Array(PokemonOXQuestion.bank.prefix(10)), startsAt: .now)
        for _ in 0..<10 { quiz.reveal(); quiz.advance() }
        XCTAssertTrue(quiz.isFinished)
        XCTAssertEqual(quiz.questionIndex, 10)
        XCTAssertGreaterThanOrEqual(quiz.standings[0].score, quiz.standings[1].score)
    }
}
