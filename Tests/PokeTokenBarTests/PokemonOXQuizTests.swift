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
        let questions = (0..<10).map {
            PokemonOXQuestion(id: $0, ko: "Q\($0)", en: "Q\($0)", ja: "Q\($0)", answer: $0.isMultiple(of: 2))
        }
        var quiz = PokemonOXGame(players: [
            PokemonOXPlayer(id: left, trainerName: "A", speciesID: 1, position: -1),
            PokemonOXPlayer(id: right, trainerName: "B", speciesID: 25, position: 1),
        ], questions: questions, startsAt: .now)
        for _ in 0..<10 { quiz.reveal(); quiz.advance() }
        XCTAssertTrue(quiz.isFinished)
        XCTAssertEqual(quiz.questionIndex, 10)
        XCTAssertGreaterThanOrEqual(quiz.standings[0].score, quiz.standings[1].score)
    }

    func testFactoryBuildsTenQuestionsOnlyFromFacts() {
        let facts = (1...4).map { id in
            PokemonQuizFact(speciesID: id,
                            names: ["ko": "포켓몬\(id)", "en": "Pokemon\(id)", "ja-Hrkt": "ポケモン\(id)"],
                            types: [.grass], evolvesFromNames: id == 1 ? nil : ["ko": "포켓몬1", "en": "Pokemon1", "ja-Hrkt": "ポケモン1"])
        }
        let questions = PokemonOXQuestionFactory.make(from: facts)
        XCTAssertEqual(questions.count, 10)
        XCTAssertTrue(questions.allSatisfy { !$0.ko.isEmpty && !$0.en.isEmpty && !$0.ja.isEmpty })
    }

    func testQuizLobbyAllowsTenRunners() throws {
        func participant(_ n: Int) -> LobbyParticipant {
            LobbyParticipant(id: UUID(), trainerName: "P\(n)", speciesID: n, team: .solo,
                             isReady: true, isHost: n == 1)
        }
        var lobby = try MultiplayerLobby(host: participant(1), capacity: 10, activity: .pokemonQuiz)
        for n in 2...10 { try lobby.join(participant(n)) }
        XCTAssertEqual(lobby.runners.count, 10)
        XCTAssertThrowsError(try lobby.join(participant(11)))
        XCTAssertTrue(lobby.canStart)
    }
}
