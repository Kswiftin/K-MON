import Foundation

enum PokemonOXInput: String, Codable, Sendable { case left, right }

struct PokemonOXQuestion: Codable, Sendable, Equatable, Identifiable {
    let id: Int
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
        for fact in facts {
            let dexAnswer = Bool.random()
            let shownNumber = dexAnswer ? fact.speciesID : wrongDexNumber(for: fact.speciesID)
            questions.append(.init(id: nextID,
                ko: "\(fact.name("ko"))의 전국도감 번호는 \(shownNumber)번이다.",
                en: "\(fact.name("en")) is National Pokédex No. \(shownNumber).",
                ja: "\(fact.name("ja-Hrkt"))の全国図鑑番号は\(shownNumber)番だ。", answer: dexAnswer))
            nextID += 1

            let typeAnswer = Bool.random()
            let shownType = typeAnswer ? (fact.types.randomElement() ?? .normal)
                : (PokemonType.allCases.filter { !fact.types.contains($0) }.randomElement() ?? .normal)
            questions.append(.init(id: nextID,
                ko: "\(fact.name("ko"))은(는) \(shownType.name(.ko))타입이다.",
                en: "\(fact.name("en")) is a \(shownType.name(.en))-type Pokémon.",
                ja: "\(fact.name("ja-Hrkt"))は\(shownType.name(.ja))タイプだ。", answer: typeAnswer))
            nextID += 1

            if let parent = fact.evolvesFromNames {
                questions.append(.init(id: nextID,
                    ko: "\(fact.name("ko"))은(는) \(localized(parent, "ko"))에서 진화한다.",
                    en: "\(fact.name("en")) evolves from \(localized(parent, "en")).",
                    ja: "\(fact.name("ja-Hrkt"))は\(localized(parent, "ja-Hrkt"))から進化する。", answer: true))
            } else {
                questions.append(.init(id: nextID,
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

    private static func wrongDexNumber(for actual: Int) -> Int {
        let offset = Int.random(in: 1...25)
        return actual + offset <= PokemonAssets.animatedSpeciesIDs.upperBound ? actual + offset : max(1, actual - offset)
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
    static let answerDuration: TimeInterval = 8
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
