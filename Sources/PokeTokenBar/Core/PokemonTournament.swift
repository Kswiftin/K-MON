import Foundation

enum TournamentEggReward: String, Codable, Sendable, Equatable {
    case standard, uncommon, rare

    static func forParticipants(_ count: Int) -> Self {
        if count >= 7 { return .rare }
        if count >= 5 { return .uncommon }
        return .standard
    }

    var guarantee: Rarity? {
        switch self { case .standard: nil; case .uncommon: .uncommon; case .rare: .rare }
    }
}

struct TournamentEntrant: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let trainerName: String
    let speciesID: Int
}

struct TournamentBracketMatch: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let round: Int
    let playerA: UUID
    let playerB: UUID
    var winnerID: UUID?
}

/// `BattleSide`의 관전용 와이어 표현. 호스트만 판정하고 참가자 전원은 이 상태를 그린다.
struct TournamentPokemonState: Codable, Sendable, Equatable {
    var snapshot: BattleSnapshot
    var hp: Int
    var pp: [Int]
    var status: Status?
    var statusCounter: Int
    var confusionTurns: Int
    var stages: [BattleStat: Int]

    init(_ side: BattleSide) {
        snapshot = side.snapshot; hp = side.hp; pp = side.pp; status = side.status
        statusCounter = side.statusCounter; confusionTurns = side.confusionTurns; stages = side.stages
    }

    var side: BattleSide {
        var value = BattleSide(snapshot)
        value.hp = min(value.stats.hp, max(0, hp))
        value.pp = zip(value.pp, pp).map { min($0.0, max(0, $0.1)) }
        value.status = status; value.statusCounter = max(0, statusCounter)
        value.confusionTurns = max(0, confusionTurns)
        value.stages = stages.reduce(into: [:]) { $0[$1.key] = StatStages.clamped($1.value) }
        return value
    }
}

struct TournamentMatchState: Codable, Sendable, Equatable {
    let id: UUID
    let round: Int
    let playerA: UUID
    let playerB: UUID
    let nameA: String
    let nameB: String
    var teamA: [TournamentPokemonState]
    var teamB: [TournamentPokemonState]
    var activeA: Int
    var activeB: Int
    var turn: Int
    var events: [BattleEvent]
    var submitted: Set<UUID>
    var winnerID: UUID?

    func team(for playerID: UUID) -> [TournamentPokemonState]? {
        playerID == playerA ? teamA : (playerID == playerB ? teamB : nil)
    }
}

struct PokemonTournamentState: Codable, Sendable, Equatable {
    let entrants: [TournamentEntrant]
    let reward: TournamentEggReward
    var matches: [TournamentBracketMatch] = []
    var currentMatch: TournamentMatchState?
    var championID: UUID?

    var champion: TournamentEntrant? { entrants.first { $0.id == championID } }
}

/// 한 대진의 권위형 3대3 엔진. 기존 `NetBattleState`를 사용해 기술·교체·특성을 1:1과 공유한다.
struct TournamentMatchEngine {
    let id: UUID
    let round: Int
    let playerA: TournamentEntrant
    let playerB: TournamentEntrant
    private(set) var battle: NetBattleState

    init(id: UUID = UUID(), round: Int, playerA: TournamentEntrant, playerB: TournamentEntrant,
         teamA: [BattleSnapshot], teamB: [BattleSnapshot], seed: UInt64) {
        self.id = id; self.round = round; self.playerA = playerA; self.playerB = playerB
        let normalizedA = teamA.map { snapshot -> BattleSnapshot in
            var snapshot = snapshot; snapshot.level = 50; return snapshot
        }
        let normalizedB = teamB.map { snapshot -> BattleSnapshot in
            var snapshot = snapshot; snapshot.level = 50; return snapshot
        }
        battle = NetBattleState(iAmA: true, myTeam: normalizedA.map(BattleSide.init),
                                oppTeam: normalizedB.map(BattleSide.init), rng: SplitMix64(seed: seed))
        battle.automaticallyReplacesFainted = false
    }

    mutating func submit(_ action: NetBattleAction, from playerID: UUID) -> Bool {
        if playerID == playerA.id {
            guard battle.myAction == nil, battle.canChoose(action, mine: true) else { return false }
            if case .switchTo(let index) = action, battle.replaceFainted(to: index, mine: true) { return true }
            battle.myAction = action
        } else if playerID == playerB.id {
            guard battle.oppAction == nil, battle.canChoose(action, mine: false) else { return false }
            if case .switchTo(let index) = action, battle.replaceFainted(to: index, mine: false) { return true }
            battle.oppAction = action
        } else { return false }
        return true
    }

    var isReady: Bool { battle.myAction != nil && battle.oppAction != nil }

    @discardableResult mutating func resolveIfReady() -> UUID? {
        guard isReady else { return nil }
        let outcome = battle.resolveChosenActions()
        switch outcome {
        case .win: return playerA.id
        case .loss: return playerB.id
        case .draw:
            let hpA = battle.myTeam.reduce(0) { $0 + $1.hp }
            let hpB = battle.oppTeam.reduce(0) { $0 + $1.hp }
            if hpA != hpB { return hpA > hpB ? playerA.id : playerB.id }
            return playerA.id.uuidString < playerB.id.uuidString ? playerA.id : playerB.id
        case nil: return nil
        }
    }

    mutating func fillMissingActions() {
        if battle.myAction == nil, !battle.me.isAlive,
           let next = battle.myTeam.indices.first(where: { battle.myTeam[$0].isAlive }) {
            _ = battle.replaceFainted(to: next, mine: true)
        }
        if battle.oppAction == nil, !battle.opp.isAlive,
           let next = battle.oppTeam.indices.first(where: { battle.oppTeam[$0].isAlive }) {
            _ = battle.replaceFainted(to: next, mine: false)
        }
        if battle.myAction == nil { battle.myAction = automatic(team: battle.myTeam, active: battle.myActive) }
        if battle.oppAction == nil { battle.oppAction = automatic(team: battle.oppTeam, active: battle.oppActive) }
    }

    func snapshot(winnerID: UUID? = nil) -> TournamentMatchState {
        TournamentMatchState(id: id, round: round, playerA: playerA.id, playerB: playerB.id,
                             nameA: playerA.trainerName, nameB: playerB.trainerName,
                             teamA: battle.myTeam.map(TournamentPokemonState.init),
                             teamB: battle.oppTeam.map(TournamentPokemonState.init),
                             activeA: battle.myActive, activeB: battle.oppActive, turn: battle.turn,
                             // 마지막 턴만 보내면 화면의 재생기가 매 턴 같은 길이의 새 배열을 받아
                             // 증가를 감지하지 못한다. 누적 스트림을 보내 일반 1:1과 같은 방식으로 재생한다.
                             events: battle.events,
                             submitted: Set([battle.myAction == nil ? nil : playerA.id,
                                             battle.oppAction == nil ? nil : playerB.id].compactMap { $0 }),
                             winnerID: winnerID)
    }

    private func automatic(team: [BattleSide], active: Int) -> NetBattleAction {
        guard team.indices.contains(active) else { return .move(index: -1) }
        if !team[active].isAlive,
           let next = team.indices.first(where: { team[$0].isAlive }) { return .switchTo(index: next) }
        if team[active].mustStruggle { return .move(index: -1) }
        return .move(index: team[active].pp.indices.first(where: { team[active].pp[$0] > 0 }) ?? -1)
    }
}

/// 라운드별 대진 진행. 홀수 인원은 마지막 참가자가 부전승으로 다음 라운드에 오른다.
struct TournamentBracket {
    private(set) var round = 1
    private(set) var waiting: [UUID]
    private(set) var winners: [UUID] = []
    private(set) var matches: [TournamentBracketMatch] = []

    init(participantIDs: [UUID], seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        waiting = participantIDs
        if waiting.count > 1 {
            for index in stride(from: waiting.count - 1, through: 1, by: -1) {
                waiting.swapAt(index, Int(rng.next() % UInt64(index + 1)))
            }
        }
    }

    mutating func nextPair() -> (UUID, UUID)? {
        while waiting.count == 1 {
            winners.append(waiting.removeFirst())
            advanceRoundIfNeeded()
        }
        guard waiting.count >= 2 else { return nil }
        return (waiting.removeFirst(), waiting.removeFirst())
    }

    mutating func record(match: TournamentBracketMatch) {
        matches.append(match)
        if let winner = match.winnerID { winners.append(winner) }
        advanceRoundIfNeeded()
    }

    var championID: UUID? { waiting.isEmpty && winners.count == 1 ? winners[0] : nil }

    private mutating func advanceRoundIfNeeded() {
        guard waiting.isEmpty, winners.count > 1 else { return }
        waiting = winners; winners = []; round += 1
    }
}
