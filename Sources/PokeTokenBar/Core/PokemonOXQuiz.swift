import Foundation

enum PokemonOXInput: String, Codable, Sendable { case left, right }

struct PokemonOXQuestion: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let ko: String
    let en: String
    let ja: String
    let answer: Bool

    static let bank: [Self] = [
        .init(id: 1, ko: "피카츄의 도감 번호는 25번이다.", en: "Pikachu is Pokédex No. 25.", ja: "ピカチュウの図鑑番号は25番だ。", answer: true),
        .init(id: 2, ko: "파이리는 물타입 포켓몬이다.", en: "Charmander is a Water-type Pokémon.", ja: "ヒトカゲはみずタイプのポケモンだ。", answer: false),
        .init(id: 3, ko: "이브이는 여러 종류의 포켓몬으로 진화할 수 있다.", en: "Eevee can evolve into several different Pokémon.", ja: "イーブイは複数のポケモンに進化できる。", answer: true),
        .init(id: 4, ko: "메타몽은 변신을 사용할 수 있다.", en: "Ditto can use Transform.", ja: "メタモンはへんしんを使える。", answer: true),
        .init(id: 5, ko: "꼬부기의 최종 진화는 어니부기다.", en: "Wartortle is Squirtle's final evolution.", ja: "カメールはゼニガメの最終進化だ。", answer: false),
        .init(id: 6, ko: "이상해씨는 풀·독타입이다.", en: "Bulbasaur is Grass/Poison type.", ja: "フシギダネはくさ・どくタイプだ。", answer: true),
        .init(id: 7, ko: "고오스는 노말타입 기술에 약점을 찔린다.", en: "Gastly is weak to Normal-type moves.", ja: "ゴースはノーマル技が弱点だ。", answer: false),
        .init(id: 8, ko: "잉어킹은 레벨 20에 갸라도스로 진화한다.", en: "Magikarp evolves into Gyarados at level 20.", ja: "コイキングはレベル20でギャラドスに進化する。", answer: true),
        .init(id: 9, ko: "잠만보는 벌레타입 포켓몬이다.", en: "Snorlax is a Bug-type Pokémon.", ja: "カビゴンはむしタイプのポケモンだ。", answer: false),
        .init(id: 10, ko: "뮤츠는 1세대에 처음 등장했다.", en: "Mewtwo first appeared in Generation I.", ja: "ミュウツーは第1世代で初登場した。", answer: true),
        .init(id: 11, ko: "전기타입 기술은 땅타입에게 효과가 없다.", en: "Electric-type moves do not affect Ground types.", ja: "でんき技はじめんタイプに効果がない。", answer: true),
        .init(id: 12, ko: "리자몽은 불꽃·드래곤타입이다.", en: "Charizard is Fire/Dragon type.", ja: "リザードンはほのお・ドラゴンタイプだ。", answer: false),
        .init(id: 13, ko: "캐터피는 단데기로 진화한다.", en: "Caterpie evolves into Metapod.", ja: "キャタピーはトランセルに進化する。", answer: true),
        .init(id: 14, ko: "푸린은 달의돌로 푸크린이 된다.", en: "Jigglypuff evolves into Wigglytuff with a Moon Stone.", ja: "プリンはつきのいしでプクリンに進化する。", answer: true),
        .init(id: 15, ko: "라프라스는 진화 전 포켓몬이 있다.", en: "Lapras has a pre-evolution.", ja: "ラプラスには進化前のポケモンがいる。", answer: false),
        .init(id: 16, ko: "격투타입은 노말타입에 효과가 굉장하다.", en: "Fighting-type moves are super effective against Normal types.", ja: "かくとう技はノーマルタイプに効果抜群だ。", answer: true),
        .init(id: 17, ko: "디그다는 날개가 있다.", en: "Diglett has wings.", ja: "ディグダには翼がある。", answer: false),
        .init(id: 18, ko: "프리져·썬더·파이어는 전설의 새 포켓몬이다.", en: "Articuno, Zapdos, and Moltres are legendary birds.", ja: "フリーザー・サンダー・ファイヤーは伝説の鳥ポケモンだ。", answer: true),
        .init(id: 19, ko: "독타입 기술은 강철타입에게 효과가 없다.", en: "Poison-type moves do not affect Steel types.", ja: "どく技ははがねタイプに効果がない。", answer: true),
        .init(id: 20, ko: "망나뇽은 미뇽의 바로 다음 진화다.", en: "Dragonite evolves directly from Dratini.", ja: "カイリューはミニリュウから直接進化する。", answer: false),
    ]
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
        if questionIndex >= questions.count {
            isFinished = true
            return
        }
        isRevealing = false
        for i in players.indices { players[i].position = 0; players[i].lastCorrect = nil }
        deadline = Date().addingTimeInterval(Self.answerDuration)
    }
}
