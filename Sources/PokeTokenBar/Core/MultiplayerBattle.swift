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
    /// 배틀 상태 — 세 모드가 공유하는 `BattleSide` 하나. 새 기전은 여기 한 번만 얹는다.
    var side: BattleSide

    init(participant: LobbyParticipant, snapshot: BattleSnapshot) {
        id = participant.id
        trainerName = participant.trainerName
        team = participant.team
        side = BattleSide(snapshot)
    }

    var isAlive: Bool { side.isAlive }

    // 와이어 계약(`protocolVersion` 2)은 `snapshot`/`hp`/`pp` 를 **평면으로** 보낸다. 상태를
    // `side` 로 모은 건 내부 구조 변경일 뿐이므로 JSON 모양은 그대로 두고 구버전과 계속 붙게 한다.
    // (기전이 하나도 안 바뀐 리팩터로 프로토콜 버전을 올리면 구버전은 이유 없이 못 들어온다.)
    // `stats`·`moves` 는 스냅샷에서 파생되므로 보내지 않고 받는 쪽이 다시 만든다.
    private enum CodingKeys: String, CodingKey { case id, trainerName, team, snapshot, hp, pp }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        trainerName = try container.decode(String.self, forKey: .trainerName)
        team = try container.decode(BattleTeam.self, forKey: .team)
        var decoded = BattleSide(try container.decode(BattleSnapshot.self, forKey: .snapshot))
        decoded.hp = try container.decode(Int.self, forKey: .hp)
        decoded.pp = try container.decode([Int].self, forKey: .pp)
        side = decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(trainerName, forKey: .trainerName)
        try container.encode(team, forKey: .team)
        try container.encode(side.snapshot, forKey: .snapshot)
        try container.encode(side.hp, forKey: .hp)
        try container.encode(side.pp, forKey: .pp)
    }
}

struct MultiplayerAction: Codable, Sendable, Equatable {
    let attackerID: UUID
    let targetID: UUID
    let moveIndex: Int
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
                                                speciesID: fighter.side.snapshot.speciesID, team: fighter.team,
                                                isReady: true, isHost: false),
                  snapshot: fighter.side.snapshot)
                && fighter.side.hp == fighter.side.stats.hp
        }) else { return false }
        if mode == .freeForAll { return fighters.allSatisfy { $0.team == .solo } }
        return fighters.count == 4 && fighters.filter { $0.team == .red }.count == 2
            && fighters.filter { $0.team == .blue }.count == 2
    }
}

/// 4인 방의 와이어 계약. 호스트 권위형이라 클라이언트는 참가/준비/행동만 보내고,
/// 로비 상태와 라운드 결과는 호스트가 전 참가자에게 브로드캐스트한다.
enum MultiplayerWireMessage: Codable, Sendable, Equatable {
    // 3: 라운드 결과가 타입된 이벤트 스트림(`[BattleEvent]`)이 됐다. 1v1 은 이벤트를 주고받지 않아
    //    `rulesVersion` 만으로 충분하지만, 이쪽은 호스트가 `roundResolved` 로 브로드캐스트하므로
    //    구버전 게스트는 라운드를 디코딩하지 못한다 → 버전을 올려 입장 단계에서 막는다.
    static let protocolVersion = 3   // 2: LobbyParticipant.role + 관전자 베팅 메시지
    case join(version: Int, participant: LobbyParticipant, snapshot: BattleSnapshot)
    case lobby(MultiplayerLobby)
    case ready(participantID: UUID, ready: Bool)
    case team(participantID: UUID, team: BattleTeam)
    case start(seed: UInt64, fighters: [MultiplayerFighter], mode: MultiplayerBattleMode)
    case action(round: Int, action: MultiplayerAction)
    case roundResolved(round: Int, fighters: [MultiplayerFighter], events: [BattleEvent])
    case leave(participantID: UUID)
    case rejected(reason: String)
    case pokeathlonStart(race: PokeathlonRace)
    case pokeathlonInput(participantID: UUID, input: PokeathlonInput)
    case pokeathlonState(race: PokeathlonRace)
    case pokeathlonBet(participantID: UUID, runnerID: UUID, amount: Int)
    case pokeathlonPool(PokeathlonPool)
    case pokeathlonSettlement(pool: PokeathlonPool, winnerID: UUID?)
}

/// 2~4명 개인전/2:2 공용 결정적 전투 상태. 네트워크는 action만 모아 호스트가 resolveRound를 호출한다.
struct MultiplayerBattle: Sendable {
    private(set) var fighters: [MultiplayerFighter]
    let mode: MultiplayerBattleMode
    private(set) var round = 1
    private(set) var events: [BattleEvent] = []
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
        fighters[index].side.hp = 0
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
                                     moveIndex: fighter.side.pp.firstIndex(where: { $0 > 0 }) ?? -1)
        }
    }

    mutating func resolveRound(_ actions: [MultiplayerAction]) throws -> [BattleEvent] {
        let alive = livingFighters
        let actionIDs = actions.map(\.attackerID)
        guard Set(actionIDs).count == actionIDs.count else { throw MultiplayerBattleError.duplicateAction }
        guard Set(actionIDs) == Set(alive.map(\.id)) else { throw MultiplayerBattleError.unknownFighter }

        // 사전 검증은 **데미지가 한 점도 들어가기 전에** 끝난다. PP 검사가 해상 루프 안에 있던
        // 동안은, 남지 않은 기술을 지목한 액션 하나가 이미 해상된 앞 공격과 함께 라운드를 통째로
        // 무효로 만들었다. `mutating` 메서드는 throw 해도 그때까지의 변경이 호출자에게 남으므로
        // 라운드가 **반쯤 적용된** 상태가 되고, 호스트(`finishRoundIfReady`)는 그 라운드를 버리면서
        // 턴 타이머를 다시 걸지 않아 방의 진행이 멈춘다. 액션은 상대가 보내오는 값이니 신뢰 경계
        // 밖이다. 검증은 경계 한 곳에서 끝내야 한다.
        for action in actions {
            guard let attacker = fighters.first(where: { $0.id == action.attackerID }),
                  let target = fighters.first(where: { $0.id == action.targetID }) else {
                throw MultiplayerBattleError.unknownFighter
            }
            guard attacker.id != target.id, target.isAlive,
                  mode == .freeForAll || attacker.team != target.team else {
                throw MultiplayerBattleError.invalidTarget
            }
            guard action.moveIndex == -1 || attacker.side.canUse(moveAt: action.moveIndex) else {
                throw MultiplayerBattleError.invalidMove
            }
        }

        // 본가와 같은 순서: 기술 우선도 → 스피드 → 무작위. 모든 피어가 같은 순서로 rng를 소비한다.
        //
        // 무작위 tie-break 키는 정렬에 들어가기 **전에** `actions` 순서대로 하나씩 뽑는다.
        // 비교 클로저 안에서 rng 를 부르면 소비 횟수가 정렬 알고리즘의 비교 횟수에 딸려가고,
        // 그건 곧 피어마다 다른 rng 상태 — 이 배틀에서는 desync 다.
        let tieBreakers = actions.map { _ in rng.next() }
        let ordered = zip(actions, tieBreakers).sorted { lhs, rhs in
            let leftFighter = fighters.first { $0.id == lhs.0.attackerID }!
            let rightFighter = fighters.first { $0.id == rhs.0.attackerID }!
            let leftPriority = leftFighter.side.move(at: lhs.0.moveIndex).turnPriority
            let rightPriority = rightFighter.side.move(at: rhs.0.moveIndex).turnPriority
            if leftPriority != rightPriority { return leftPriority > rightPriority }
            // `stats` 는 배틀 시작에 한 번 계산된 값이다. 여기서 `effectiveStats()` 를 부르던
            // 때는 비교 횟수만큼 스탯을 다시 만들었다.
            let leftSpeed = leftFighter.side.stats.spe
            let rightSpeed = rightFighter.side.stats.spe
            if leftSpeed != rightSpeed { return leftSpeed > rightSpeed }
            return lhs.1 < rhs.1
        }.map(\.0)
        var roundEvents: [BattleEvent] = [.turn(round)]
        for action in ordered {
            guard let ai = fighters.firstIndex(where: { $0.id == action.attackerID }), fighters[ai].isAlive,
                  let ti = fighters.firstIndex(where: { $0.id == action.targetID }), fighters[ti].isAlive else { continue }
            // 인덱스·PP 는 위 사전 검증을 통과한 값이다.
            let move = fighters[ai].side.move(at: action.moveIndex)
            if action.moveIndex >= 0 { fighters[ai].side.pp[action.moveIndex] -= 1 }
            // 방어측을 지역 사본으로 꺼내 넘긴다 — 같은 배열의 두 원소를 동시에 inout 으로 잡으면
            // 배타적 접근 위반이다. 데미지와 이벤트는 `applyAttack` 한 곳에서 만든다.
            var target = fighters[ti].side
            roundEvents += BattleEngine.applyAttack(attacker: fighters[ai].side, defender: &target,
                                                    attackerActor: .fighter(fighters[ai].id),
                                                    defenderActor: .fighter(fighters[ti].id),
                                                    move: move, rng: &rng)
            fighters[ti].side = target
        }
        events.append(contentsOf: roundEvents)
        round += 1
        return roundEvents
    }
}
