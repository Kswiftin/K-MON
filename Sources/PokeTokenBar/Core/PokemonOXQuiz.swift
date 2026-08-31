import Foundation

enum PokemonOXInput: String, Codable, Sendable { case left, right }

struct PokemonOXQuestion: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let speciesID: Int
    let ko: String
    let en: String
    let ja: String
    let answer: Bool
}

struct PokemonQuizFact: Sendable, Equatable {
    let speciesID: Int
    let names: [String: String]
    let types: [PokemonType]
    let abilityNames: [String: String]

    func name(_ language: String) -> String { names[language] ?? names["en"] ?? "#\(speciesID)" }
}

enum PokemonOXQuestionFactory {
    static func make(from facts: [PokemonQuizFact]) -> [PokemonOXQuestion] {
        var questions: [PokemonOXQuestion] = []
        var nextID = 1
        for (index, fact) in facts.enumerated() {
            // 단순히 "이 포켓몬은 무슨 타입"만 반복하지 않고, 실제 상성표를 이용해 공격 타입과
            // 복합 방어 타입 사이의 배율을 묻는다. 절반은 참, 절반은 거짓이 되도록 후보를 고른다.
            let typeAnswer = index.isMultiple(of: 2)
            let matchingTypes = PokemonType.allCases.filter {
                (TypeChart.effectiveness($0, against: fact.types) > 1) == typeAnswer
            }
            let shownType = matchingTypes.randomElement() ?? .normal
            questions.append(.init(id: nextID, speciesID: fact.speciesID,
                ko: "\(shownType.name(.ko))타입 기술은 \(fact.name("ko"))에게 효과가 굉장하다.",
                en: "\(shownType.name(.en))-type moves are super effective against \(fact.name("en")).",
                ja: "\(shownType.name(.ja))タイプのわざは\(fact.name("ja-Hrkt"))に効果抜群だ。",
                answer: typeAnswer))
            nextID += 1

            let decoyAbility = facts.first {
                $0.speciesID != fact.speciesID && $0.abilityNames != fact.abilityNames
            }?.abilityNames
            // 다른 특성을 구하지 못한 경우에는 거짓 문제를 만들지 않는다.
            let abilityAnswer = !index.isMultiple(of: 2) || decoyAbility == nil
            let shownAbility = abilityAnswer ? fact.abilityNames : decoyAbility!
            questions.append(.init(id: nextID, speciesID: fact.speciesID,
                ko: "\(fact.name("ko"))의 특성은 \(localized(shownAbility, "ko"))이다.",
                en: "\(fact.name("en")) can have the ability \(localized(shownAbility, "en")).",
                ja: "\(fact.name("ja-Hrkt"))の特性は\(localized(shownAbility, "ja-Hrkt"))だ。",
                answer: abilityAnswer))
            nextID += 1
        }
        return Array(questions.shuffled().prefix(PokemonOXGame.questionCount))
    }

    private static func localized(_ names: [String: String], _ language: String) -> String {
        names[language] ?? (language == "ja-Hrkt" ? names["ja"] : nil) ?? names["en"] ?? "?"
    }

}

struct PokemonOXPlayer: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let trainerName: String
    let speciesID: Int
    var position: Double = 0
    var score = 0
    var lastCorrect: Bool?
}

struct PokemonOXGame: Codable, Sendable, Equatable {
    static let questionCount = 10
    static let answerDuration: TimeInterval = 5
    static let revealDuration: TimeInterval = 2.5
    static let movementStep = 0.16

    var players: [PokemonOXPlayer]
    let questions: [PokemonOXQuestion]
    var questionIndex = 0
    var deadline: Date
    var isRevealing = false
    var isFinished = false

    init(players: [PokemonOXPlayer], questions: [PokemonOXQuestion], startsAt: Date = Date().addingTimeInterval(3)) {
        self.players = players
        self.questions = Array(questions.prefix(Self.questionCount))
        deadline = startsAt.addingTimeInterval(Self.answerDuration)
    }

    var currentQuestion: PokemonOXQuestion? {
        questions.indices.contains(questionIndex) ? questions[questionIndex] : nil
    }

    var standings: [PokemonOXPlayer] {
        players.sorted { $0.score == $1.score ? $0.trainerName < $1.trainerName : $0.score > $1.score }
    }

    mutating func move(_ input: PokemonOXInput, playerID: UUID) {
        guard !isFinished, !isRevealing, let i = players.firstIndex(where: { $0.id == playerID }) else { return }
        let delta = input == .left ? -Self.movementStep : Self.movementStep
        players[i].position = min(1, max(-1, players[i].position + delta))
    }

    mutating func reveal() {
        guard !isFinished, !isRevealing, let question = currentQuestion else { return }
        for i in players.indices {
            let choice: Bool? = players[i].position < -0.12 ? false : (players[i].position > 0.12 ? true : nil)
            let correct = choice == question.answer
            players[i].lastCorrect = correct
            if correct { players[i].score += 10 }
        }
        isRevealing = true
        deadline = Date().addingTimeInterval(Self.revealDuration)
    }

    mutating func advance() {
        guard isRevealing else { return }
        questionIndex += 1
        if questionIndex >= questions.count { isFinished = true; return }
        isRevealing = false
        for i in players.indices { players[i].position = 0; players[i].lastCorrect = nil }
        deadline = Date().addingTimeInterval(Self.answerDuration)
    }
}
