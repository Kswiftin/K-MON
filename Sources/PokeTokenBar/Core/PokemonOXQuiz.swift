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
    let evolvesFromNames: [String: String]?

    func name(_ language: String) -> String { names[language] ?? names["en"] ?? "#\(speciesID)" }
}

enum PokemonOXQuestionFactory {
    static func make(from facts: [PokemonQuizFact]) -> [PokemonOXQuestion] {
        var questions: [PokemonOXQuestion] = []
        var nextID = 1
        for (index, fact) in facts.enumerated() {
            // 오답 타입을 18종 전체에서 뽑으면 불꽃 포켓몬에 페어리처럼 너무 티 나는 선택이 자주
            // 나온다. 같은 문제 세트의 다른 포켓몬이 실제로 가진 타입을 우선 써 그럴듯한 오답으로 만든다.
            let plausibleWrongTypes = facts.flatMap(\.types).filter { !fact.types.contains($0) }
            let typeAnswer = index.isMultiple(of: 2)
            let shownType = typeAnswer ? (fact.types.randomElement() ?? .normal)
                : (plausibleWrongTypes.randomElement()
                    ?? PokemonType.allCases.filter { !fact.types.contains($0) }.randomElement() ?? .normal)
            questions.append(.init(id: nextID, speciesID: fact.speciesID,
                ko: "\(fact.name("ko"))은(는) \(shownType.name(.ko))타입이다.",
                en: "\(fact.name("en")) is a \(shownType.name(.en))-type Pokémon.",
                ja: "\(fact.name("ja-Hrkt"))は\(shownType.name(.ja))タイプだ。", answer: typeAnswer))
            nextID += 1

            // 진화 문제도 항상 실제 부모를 보여주던 구조에서 벗어난다. 절반은 다른 포켓몬을 부모처럼
            // 제시하되, 실제 부모와 자기 자신은 제외해 정답 데이터가 모순되지 않게 한다.
            let decoy = facts.first {
                $0.speciesID != fact.speciesID
                    && $0.names != fact.evolvesFromNames
            }?.names
            let asksTrueEvolution = !index.isMultiple(of: 2) && fact.evolvesFromNames != nil
            if asksTrueEvolution, let parent = fact.evolvesFromNames {
                questions.append(.init(id: nextID, speciesID: fact.speciesID,
                    ko: "\(fact.name("ko"))은(는) \(localized(parent, "ko"))에서 진화한다.",
                    en: "\(fact.name("en")) evolves from \(localized(parent, "en")).",
                    ja: "\(fact.name("ja-Hrkt"))は\(localized(parent, "ja-Hrkt"))から進化する。", answer: true))
            } else if let decoy {
                questions.append(.init(id: nextID, speciesID: fact.speciesID,
                    ko: "\(fact.name("ko"))은(는) \(localized(decoy, "ko"))에서 진화한다.",
                    en: "\(fact.name("en")) evolves from \(localized(decoy, "en")).",
                    ja: "\(fact.name("ja-Hrkt"))は\(localized(decoy, "ja-Hrkt"))から進化する。", answer: false))
            } else {
                questions.append(.init(id: nextID, speciesID: fact.speciesID,
                    ko: "\(fact.name("ko"))에게는 진화 전 포켓몬이 있다.",
                    en: "\(fact.name("en")) has a pre-evolution.",
                    ja: "\(fact.name("ja-Hrkt"))には進化前のポケモンがいる。", answer: false))
            }
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
