import Foundation

enum MultiplayerBattleMode: String, Codable, Sendable { case freeForAll, teams }

struct BattleRecord: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var playedAt: Date
    var mode: MultiplayerBattleMode
    var participantCount: Int
    var won: Bool
    var reward: Int
    var opponentNames: [String]
}

enum PokeathlonInput: String, Codable, Sendable { case run, dodgeLeft, dodgeRight, switchPokemon }

struct PokeathlonRacer: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var trainerName: String
    var speciesID: Int
    var teamSpeciesIDs: [Int] = []
    var activeTeamIndex = 0
    var stamina: [Int] = [100, 100, 100]
    var distance = 0
    var crashes = 0
    var lane = 1
    var finished = false
    var lastActionAt: Date?

    var activeSpeciesID: Int {
        let team = teamSpeciesIDs.isEmpty ? [speciesID] : teamSpeciesIDs
        return team[min(activeTeamIndex, team.count - 1)]
    }
}

struct PokeathlonRace: Codable, Sendable, Equatable {
    static let finishLine = 300
    static let obstacles = [35, 70, 125, 160, 220, 260]
    var racers: [PokeathlonRacer]
    var winnerID: UUID? = nil
    var startsAt = Date().addingTimeInterval(3)

    @discardableResult
    mutating func apply(_ input: PokeathlonInput, racerID: UUID, now: Date = Date()) -> Bool {
        guard now >= startsAt, winnerID == nil,
              let i = racers.firstIndex(where: { $0.id == racerID }), !racers[i].finished else { return false }
        if input == .run, let last = racers[i].lastActionAt, now.timeIntervalSince(last) < 0.12 { return false }
        if input == .run { racers[i].lastActionAt = now }
        switch input {
        case .switchPokemon:
            let teamCount = max(1, racers[i].teamSpeciesIDs.count)
            racers[i].activeTeamIndex = (racers[i].activeTeamIndex + 1) % teamCount
            return true
        case .dodgeLeft:
            racers[i].lane = max(0, racers[i].lane - 1)
            return true
        case .dodgeRight:
            racers[i].lane = min(2, racers[i].lane + 1)
            return true
        case .run:
            let staminaIndex = min(racers[i].activeTeamIndex, racers[i].stamina.count - 1)
            let tired = racers[i].stamina[staminaIndex] <= 15
            let next = racers[i].distance + (tired ? 1 : 4)
            if Self.obstacles.contains(where: {
                racers[i].distance < $0 && next >= $0 && Self.obstacleLane(at: $0) == racers[i].lane
            }) {
                racers[i].distance = max(0, racers[i].distance - 3)
                racers[i].crashes += 1
                racers[i].stamina[staminaIndex] = max(0, racers[i].stamina[staminaIndex] - 14)
            } else {
                racers[i].distance = next
                racers[i].stamina[staminaIndex] = max(0, racers[i].stamina[staminaIndex] - 5)
                if let other = racers.indices.first(where: {
                    $0 != i && !racers[$0].finished && racers[$0].lane == racers[i].lane
                        && abs(racers[$0].distance - racers[i].distance) <= 3
                }) {
                    applyCrash(to: i)
                    applyCrash(to: other)
                }
            }
        }
        if racers[i].distance >= Self.finishLine {
            racers[i].distance = Self.finishLine; racers[i].finished = true; winnerID = racers[i].id
        }
        return true
    }

    static func obstacleLane(at meter: Int) -> Int {
        guard let index = obstacles.firstIndex(of: meter) else { return 1 }
        return [1, 0, 2, 1, 2, 0][index % 6]
    }

    private mutating func applyCrash(to index: Int) {
        racers[index].distance = max(0, racers[index].distance - 3)
        racers[index].crashes += 1
        let staminaIndex = min(racers[index].activeTeamIndex, racers[index].stamina.count - 1)
        racers[index].stamina[staminaIndex] = max(0, racers[index].stamina[staminaIndex] - 14)
    }
}

struct MultiplayerFighter: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var trainerName: String
    var team: BattleTeam
    var snapshot: BattleSnapshot
    var hp: Int
    var pp: [Int]

    init(participant: LobbyParticipant, snapshot: BattleSnapshot) {
        id = participant.id
        trainerName = participant.trainerName
        team = participant.team
        self.snapshot = snapshot
        hp = snapshot.effectiveStats().hp
        pp = (snapshot.moves ?? MoveSpec.fallbackSet(types: snapshot.types)).map(\.pp)
    }

    var isAlive: Bool { hp > 0 }
}

struct MultiplayerAction: Codable, Sendable, Equatable {
    let attackerID: UUID
    let targetID: UUID
    let moveIndex: Int
}

struct MultiplayerBattleEvent: Codable, Sendable, Equatable {
    let attackerID: UUID
    let targetID: UUID
    let moveID: Int
    let missed: Bool
    let damage: Int
    let effectiveness: Double
    let isCritical: Bool
    let defenderHPAfter: Int
}

enum MultiplayerBattleError: Error, Equatable {
    case invalidFighterCount, duplicateFighter, unknownFighter, invalidTarget, invalidMove, duplicateAction
}

enum MultiplayerValidation {
    static func valid(participant: LobbyParticipant, snapshot: BattleSnapshot) -> Bool {
        let name = participant.trainerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 30,
              participant.speciesID == snapshot.speciesID,
              (1...10_000).contains(snapshot.speciesID), (1...100).contains(snapshot.level),
              (1...2).contains(snapshot.types.count) else { return false }
        let stats = snapshot.base
        guard [stats.hp, stats.atk, stats.def, stats.spa, stats.spd, stats.spe]
            .allSatisfy({ (1...255).contains($0) }) else { return false }
        let moves = snapshot.moves ?? []
        guard moves.count <= 4 else { return false }
        return moves.allSatisfy {
            (0...250).contains($0.power) && (1...100).contains($0.pp)
                && ($0.accuracy.map { (1...100).contains($0) } ?? true)
        }
    }

    static func validStart(fighters: [MultiplayerFighter], mode: MultiplayerBattleMode) -> Bool {
        guard (2...4).contains(fighters.count), Set(fighters.map(\.id)).count == fighters.count else { return false }
        guard fighters.allSatisfy({ fighter in
            valid(participant: LobbyParticipant(id: fighter.id, trainerName: fighter.trainerName,
                                                speciesID: fighter.snapshot.speciesID, team: fighter.team,
                                                isReady: true, isHost: false), snapshot: fighter.snapshot)
                && fighter.hp == fighter.snapshot.effectiveStats().hp
        }) else { return false }
        if mode == .freeForAll { return fighters.allSatisfy { $0.team == .solo } }
        return fighters.count == 4 && fighters.filter { $0.team == .red }.count == 2
            && fighters.filter { $0.team == .blue }.count == 2
    }
}

/// 4인 방의 와이어 계약. 호스트 권위형이라 클라이언트는 참가/준비/행동만 보내고,
/// 로비 상태와 라운드 결과는 호스트가 전 참가자에게 브로드캐스트한다.
enum MultiplayerWireMessage: Codable, Sendable, Equatable {
    static let protocolVersion = 1
    case join(version: Int, participant: LobbyParticipant, snapshot: BattleSnapshot)
    case lobby(MultiplayerLobby)
    case ready(participantID: UUID, ready: Bool)
    case team(participantID: UUID, team: BattleTeam)
    case start(seed: UInt64, fighters: [MultiplayerFighter], mode: MultiplayerBattleMode)
    case action(round: Int, action: MultiplayerAction)
    case roundResolved(round: Int, fighters: [MultiplayerFighter], events: [MultiplayerBattleEvent])
    case leave(participantID: UUID)
    case rejected(reason: String)
    case pokeathlonStart(race: PokeathlonRace)
    case pokeathlonInput(participantID: UUID, input: PokeathlonInput)
    case pokeathlonState(race: PokeathlonRace)
}

/// 2~4명 개인전/2:2 공용 결정적 전투 상태. 네트워크는 action만 모아 호스트가 resolveRound를 호출한다.
struct MultiplayerBattle: Sendable {
    private(set) var fighters: [MultiplayerFighter]
    let mode: MultiplayerBattleMode
    private(set) var round = 1
    private(set) var events: [MultiplayerBattleEvent] = []
    private var rng: SplitMix64

    init(fighters: [MultiplayerFighter], mode: MultiplayerBattleMode, seed: UInt64) throws {
        guard (2...4).contains(fighters.count) else { throw MultiplayerBattleError.invalidFighterCount }
        guard Set(fighters.map(\.id)).count == fighters.count else { throw MultiplayerBattleError.duplicateFighter }
        self.fighters = fighters
        self.mode = mode
        rng = SplitMix64(seed: seed)
    }

    var livingFighters: [MultiplayerFighter] { fighters.filter(\.isAlive) }
    var isFinished: Bool {
        switch mode {
        case .freeForAll: return livingFighters.count <= 1
        case .teams: return Set(livingFighters.map(\.team)).count <= 1
        }
    }
    var winningIDs: [UUID] {
        guard isFinished else { return [] }
        return livingFighters.map(\.id)
    }

    mutating func forfeit(participantID: UUID) {
        guard let index = fighters.firstIndex(where: { $0.id == participantID }) else { return }
        fighters[index].hp = 0
    }

    static func automaticActions(fighters: [MultiplayerFighter], mode: MultiplayerBattleMode,
                                 excluding submitted: Set<UUID>) -> [MultiplayerAction] {
        let living = fighters.filter(\.isAlive)
        return living.filter { !submitted.contains($0.id) }.compactMap { fighter in
            let targets = living.filter {
                $0.id != fighter.id && (mode == .freeForAll || $0.team != fighter.team)
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            guard let target = targets.first else { return nil }
            return MultiplayerAction(attackerID: fighter.id, targetID: target.id,
                                     moveIndex: fighter.pp.firstIndex(where: { $0 > 0 }) ?? -1)
        }
    }

    mutating func resolveRound(_ actions: [MultiplayerAction]) throws -> [MultiplayerBattleEvent] {
        let alive = livingFighters
        let actionIDs = actions.map(\.attackerID)
        guard Set(actionIDs).count == actionIDs.count else { throw MultiplayerBattleError.duplicateAction }
        guard Set(actionIDs) == Set(alive.map(\.id)) else { throw MultiplayerBattleError.unknownFighter }

        for action in actions {
            guard let attacker = fighters.first(where: { $0.id == action.attackerID }),
                  let target = fighters.first(where: { $0.id == action.targetID }) else {
                throw MultiplayerBattleError.unknownFighter
            }
            guard attacker.id != target.id, target.isAlive,
                  mode == .freeForAll || attacker.team != target.team else {
                throw MultiplayerBattleError.invalidTarget
            }
            let moves = attacker.snapshot.moves ?? MoveSpec.fallbackSet(types: attacker.snapshot.types)
            guard action.moveIndex == -1 || moves.indices.contains(action.moveIndex) else {
                throw MultiplayerBattleError.invalidMove
            }
        }

        // 속도 내림차순, 동률은 UUID 문자열 순. 모든 피어가 같은 순서로 rng를 소비한다.
        let ordered = actions.sorted { lhs, rhs in
            let ls = fighters.first { $0.id == lhs.attackerID }!.snapshot.effectiveStats().spe
            let rs = fighters.first { $0.id == rhs.attackerID }!.snapshot.effectiveStats().spe
            return ls == rs ? lhs.attackerID.uuidString < rhs.attackerID.uuidString : ls > rs
        }
        var roundEvents: [MultiplayerBattleEvent] = []
        for action in ordered {
            guard let ai = fighters.firstIndex(where: { $0.id == action.attackerID }), fighters[ai].isAlive,
                  let ti = fighters.firstIndex(where: { $0.id == action.targetID }), fighters[ti].isAlive else { continue }
            let moves = fighters[ai].snapshot.moves ?? MoveSpec.fallbackSet(types: fighters[ai].snapshot.types)
            let move = action.moveIndex < 0 ? MoveSpec.struggle() : moves[action.moveIndex]
            if action.moveIndex >= 0 {
                guard fighters[ai].pp[action.moveIndex] > 0 else { throw MultiplayerBattleError.invalidMove }
                fighters[ai].pp[action.moveIndex] -= 1
            }
            let event = resolveAttack(attacker: fighters[ai], target: fighters[ti], move: move)
            fighters[ti].hp = event.defenderHPAfter
            roundEvents.append(event)
        }
        events.append(contentsOf: roundEvents)
        round += 1
        return roundEvents
    }

    private mutating func resolveAttack(attacker: MultiplayerFighter, target: MultiplayerFighter,
                                        move: MoveSpec) -> MultiplayerBattleEvent {
        var missed = false
        if let accuracy = move.accuracy { missed = Int(rng.next() % 100) >= accuracy }
        var damage = 0, effectiveness = 1.0
        var critical = false
        if !missed {
            let struggle = move.id == MoveSpec.struggleID
            effectiveness = struggle ? 1 : TypeChart.effectiveness(move.type, against: target.snapshot.types)
            let stab = !struggle && attacker.snapshot.types.contains(move.type) ? 1.5 : 1
            let attackStats = attacker.snapshot.effectiveStats(), targetStats = target.snapshot.effectiveStats()
            let attack = move.damageClass == .physical ? attackStats.atk : attackStats.spa
            let defense = move.damageClass == .physical ? targetStats.def : targetStats.spd
            critical = rng.next() % BattleEngine.critDenominator == 0
            let roll = 0.85 + Double(rng.next() % 16) / 100
            let base = Double((2 * attacker.snapshot.level / 5 + 2) * move.power * attack / max(1, defense)) / 50 + 2
            damage = effectiveness == 0 ? 0 : max(1, Int(base * stab * effectiveness * (critical ? 1.5 : 1) * roll))
        }
        let hp = max(0, target.hp - damage)
        return MultiplayerBattleEvent(attackerID: attacker.id, targetID: target.id, moveID: move.id,
                                      missed: missed, damage: damage,
                                      effectiveness: missed ? 1 : effectiveness,
                                      isCritical: critical, defenderHPAfter: hp)
    }
}
