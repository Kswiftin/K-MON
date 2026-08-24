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

    // 와이어 계약은 `snapshot`/`hp`/`pp` 를 **평면으로** 보낸다 — `side` 로 묶은 건 내부 구조 변경일
    // 뿐이라 JSON 모양을 그대로 뒀다. 상태이상은 받는 쪽이 배지를 그려야 해서 필드가 늘었다.
    // `stats`·`moves` 는 스냅샷에서 파생되므로 보내지 않고 받는 쪽이 다시 만든다.
    private enum CodingKeys: String, CodingKey {
        case id, trainerName, team, snapshot, hp, pp, status, statusCounter, confusionTurns, stages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        trainerName = try container.decode(String.self, forKey: .trainerName)
        team = try container.decode(BattleTeam.self, forKey: .team)
        var decoded = BattleSide(try container.decode(BattleSnapshot.self, forKey: .snapshot))
        decoded.hp = try container.decode(Int.self, forKey: .hp)
        decoded.pp = try container.decode([Int].self, forKey: .pp)
        decoded.status = try container.decodeIfPresent(Status.self, forKey: .status)
        decoded.statusCounter = try container.decodeIfPresent(Int.self, forKey: .statusCounter) ?? 0
        decoded.confusionTurns = try container.decodeIfPresent(Int.self, forKey: .confusionTurns) ?? 0
        // 랭크가 없던 시절의 피어는 이 키를 보내지 않는다 — 없으면 랭크 없음이다.
        // **경계에서 클램프한다** — `validStart` 는 개시 시점만 보고, 라운드마다 오는 값은
        // 호스트 소유다(`atk: 99` 를 들이면 다음 `changeStage` 가 −93 을 로그에 쓴다).
        // 0 키는 버린다 — `stages` 의 불변식.
        //
        // 키도 문자열로 받아서 **모르는 이름은 버린다.** `[BattleStat: Int]` 로 바로 디코딩하면
        // 키 하나(`"hp": 1`)가 라운드 메시지 **전체**의 디코딩을 던져서 게스트가 그 자리에 멈춘다 —
        // 값은 막고 키는 안 막으면 경계가 반쪽이다.
        decoded.stages = (try container.decodeIfPresent([String: Int].self, forKey: .stages) ?? [:])
            .reduce(into: [:]) { out, pair in
                guard let stat = BattleStat(rawValue: pair.key), pair.value != 0 else { return }
                out[stat] = StatStages.clamped(pair.value)
            }
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
        try container.encodeIfPresent(side.status, forKey: .status)
        try container.encode(side.statusCounter, forKey: .statusCounter)
        try container.encode(side.confusionTurns, forKey: .confusionTurns)
        try container.encode(side.stages, forKey: .stages)
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
        return validMoves(snapshot.moves ?? [])
    }

    /// 상대 무브셋 범위 검사. **1v1 LAN 도 이 함수를 쓴다** — 방에만 두면 1v1 이 무검사가 된다.
    static func validMoves(_ moves: [MoveSpec]) -> Bool {
        guard moves.count <= 4 else { return false }
        return moves.allSatisfy {
            (0...250).contains($0.power) && (1...100).contains($0.pp)
                && ($0.accuracy.map { (1...100).contains($0) } ?? true)
                // 상태 부여 확률은 상대가 보내오는 값이다 — 범위를 벗어나면 매번 확정 부여가 된다.
                && ($0.ailmentChance.map { (0...100).contains($0) } ?? true)
                && ($0.statChance.map { (0...100).contains($0) } ?? true)
                // 랭크 변화도 상대가 보내오는 값이다. 개수 상한은 랭크가 있는 스탯 수 —
                // 안 보면 `+6 공격` 이 열두 번 담긴 기술 하나로 첫 턴에 최대 랭크가 된다.
                && ($0.statChanges.map { changes in
                    changes.count <= BattleStat.allCases.count
                        // 중복 스탯도 막는다 — 안 보면 개수 상한이 뜻을 잃는다(`+2 공격` 일곱 개면
                        // 상한 안에서 한 방에 최대 랭크이고 로그도 일곱 줄이다).
                        && Set(changes.map(\.stat)).count == changes.count
                        && changes.allSatisfy { (-StatStages.limit...StatStages.limit).contains($0.change) }
                } ?? true)
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
                // 상태이상도 호스트가 보내오는 값이다. 최대 HP 로 시작하는 배틀이면 상태도 없어야 한다 —
                // 안 보면 `status: sleep, statusCounter: 9999` 로 시작해 게스트가 영구히 못 움직인다.
                && fighter.side.status == nil && fighter.side.confusionTurns == 0
                // 랭크도 같은 이유로 0 이어야 한다 — `stages: [atk: 6]` 로 시작하는 방을 막는다.
                && fighter.side.stages.isEmpty
        }) else { return false }
        if mode == .freeForAll { return fighters.allSatisfy { $0.team == .solo } }
        return fighters.count == 4 && fighters.filter { $0.team == .red }.count == 2
            && fighters.filter { $0.team == .blue }.count == 2
    }
}

/// 4인 방의 와이어 계약. 호스트 권위형이라 클라이언트는 참가/준비/행동만 보내고,
/// 로비 상태와 라운드 결과는 호스트가 전 참가자에게 브로드캐스트한다.
enum MultiplayerWireMessage: Codable, Sendable, Equatable {
    // 호스트가 `roundResolved` 를 브로드캐스트하므로 구버전 게스트는 모르는 모양을 만나면 라운드를
    // 디코딩하지 못하고 멈춘다 → 입장 단계에서 막는다.
    // 2: LobbyParticipant.role + 관전자 베팅, 3: 이벤트 스트림, 4: 상태이상(status 필드 + case 추가),
    // 5: 랭크(stages 필드 + `.boost` case), 6: 방 전체 자유 채팅, 7: 포켓몬 OX 퀴즈.
    static let protocolVersion = 7
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
    case pokemonQuizStart(game: PokemonOXGame)
    case pokemonQuizInput(participantID: UUID, input: PokemonOXInput)
    case pokemonQuizState(game: PokemonOXGame)
    case chat(BattleChatMessage)
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
    var isFinished: Bool { Self.isFinished(fighters: fighters, mode: mode) }
    var winningIDs: [UUID] { Self.winners(fighters: fighters, mode: mode) }

    // MARK: 승패 판정 — 호스트·게스트·관전자가 같은 규칙을 본다
    //
    // static 인 건 **게스트가 `battle` 을 갱신하지 않기** 때문이다. 게스트는 `.start` 로 받은
    // 배틀만 들고 있고 라운드마다 오는 건 `fighters` 배열이라(`MultiplayerRoomCenter.combatFighters`),
    // 인스턴스 프로퍼티로만 두면 게스트 쪽 판정이 개시 시점 상태에 굳는다. 판정이 방마다 따로 있던
    // 시절엔 팀전에서 "이긴 팀의 쓰러진 대원 = 패배"가 됐다.

    static func isFinished(fighters: [MultiplayerFighter], mode: MultiplayerBattleMode) -> Bool {
        guard !fighters.isEmpty else { return false }
        let living = fighters.filter(\.isAlive)
        switch mode {
        case .freeForAll: return living.count <= 1
        case .teams: return Set(living.map(\.team)).count <= 1
        }
    }

    /// 이긴 쪽 전원. 팀전은 **쓰러진 대원까지** 포함한다 — 이긴 건 팀이지 생존자가 아니다.
    /// 양쪽이 전멸하면 아무도 이기지 않았으므로 빈 배열이다(무승부).
    static func winners(fighters: [MultiplayerFighter], mode: MultiplayerBattleMode) -> [UUID] {
        guard isFinished(fighters: fighters, mode: mode) else { return [] }
        let living = fighters.filter(\.isAlive)
        guard let winningTeam = living.first?.team else { return [] }   // 동시 전멸
        switch mode {
        case .freeForAll: return living.map(\.id)
        case .teams: return fighters.filter { $0.team == winningTeam }.map(\.id)
        }
    }

    /// 한 참가자의 승패. `nil` 은 "이 사람에게 줄 결과가 없다" — 아직 안 끝났거나 전투원이 아니다(관전자).
    /// 관전자도 라운드 브로드캐스트를 받으므로 이 nil 이 없으면 배틀 기록이 남는다.
    static func outcome(for id: UUID, fighters: [MultiplayerFighter],
                        mode: MultiplayerBattleMode) -> BattleOutcome? {
        guard fighters.contains(where: { $0.id == id }),
              isFinished(fighters: fighters, mode: mode) else { return nil }
        let winners = winners(fighters: fighters, mode: mode)
        guard !winners.isEmpty else { return .draw }
        return winners.contains(id) ? .win : .loss
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

        // 사전 검증은 **데미지가 한 점도 들어가기 전에** 끝난다. `mutating` 메서드는 throw 해도
        // 그때까지의 변경이 호출자에게 남으므로, PP 검사가 해상 루프 안에 있으면 라운드가 반쯤
        // 적용된 채 버려진다. 액션은 상대가 보내오는 값 — 검증은 경계 한 곳에서 끝낸다.
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
            // 때는 비교 횟수만큼 스탯을 다시 만들었다. 마비 보정은 `effectiveSpeed` 가 들고 있다 —
            // 1v1 과 같은 값을 봐야 두 모드의 순서 규칙이 갈라지지 않는다.
            let leftSpeed = leftFighter.side.effectiveSpeed
            let rightSpeed = rightFighter.side.effectiveSpeed
            if leftSpeed != rightSpeed { return leftSpeed > rightSpeed }
            return lhs.1 < rhs.1
        }.map(\.0)
        // 라운드가 시작될 때 "이번 턴에 맞은 것" 을 비운다 — 참가자 전원이다. 한 명만 빠져도
        // 그 참가자의 카운터가 지난 라운드 데미지를 되돌려준다.
        for index in fighters.indices { BattleEngine.beginTurn(&fighters[index].side) }
        var roundEvents: [BattleEvent] = [.turn(round)]
        for action in ordered {
            guard let ai = fighters.firstIndex(where: { $0.id == action.attackerID }), fighters[ai].isAlive,
                  let ti = fighters.firstIndex(where: { $0.id == action.targetID }), fighters[ti].isAlive else { continue }
            // 인덱스·PP 는 위 사전 검증을 통과한 값이다.
            let move = fighters[ai].side.move(at: action.moveIndex)
            if action.moveIndex >= 0 { fighters[ai].side.pp[action.moveIndex] -= 1 }
            // 양쪽을 지역 사본으로 꺼내 넘긴다 — 같은 배열의 두 원소를 동시에 inout 으로 잡으면
            // 배타적 접근 위반이다. 공격측도 inout 인 건 행동 가능 판정(잠듦·혼란)이 공격측 상태를
            // 바꾸기 때문이다. 데미지·상태·이벤트는 전부 `applyAttack` 한 곳에서 만든다.
            var attacker = fighters[ai].side
            var target = fighters[ti].side
            roundEvents += BattleEngine.applyAttack(attacker: &attacker, defender: &target,
                                                    attackerActor: .fighter(fighters[ai].id),
                                                    defenderActor: .fighter(fighters[ti].id),
                                                    move: move, rng: &rng)
            fighters[ai].side = attacker
            fighters[ti].side = target
        }
        // 턴 끝 잔뎀 — 1v1 과 같은 규칙이다. 참가자 배열 순서로 고정해야 모든 피어가 같은 순서로 본다.
        for index in fighters.indices {
            var side = fighters[index].side
            roundEvents += BattleEngine.endOfTurnResidual(&side, actor: .fighter(fighters[index].id))
            fighters[index].side = side
        }
        events.append(contentsOf: roundEvents)
        round += 1
        return roundEvents
    }
}
