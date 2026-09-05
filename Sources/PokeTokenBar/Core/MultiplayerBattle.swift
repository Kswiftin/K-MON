import Foundation

/// 방이 무슨 규칙으로 싸우는가.
///
/// `coopBoss` 는 러너 전원이 한 팀(`.red`)이고 NPC 보스가 반대 팀(`.blue`) 하나인 협동전이다.
/// **승패 규칙은 `teams` 와 글자 그대로 같다** — 보스가 죽으면 살아 있는 팀이 하나(러너)라 승리,
/// 파티가 전멸하면 살아 있는 팀이 보스뿐이라 패배다. 그래서 판정에 새 분기를 만들지 않는다.
/// 갈리는 것은 정원(보스 한 자리가 더 든다)과 개시 편성뿐이다.
enum MultiplayerBattleMode: String, Codable, Sendable { case freeForAll, teams, coopBoss }

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

/// 러너와 경기는 **호스트가 보내오는 값이다.** 게스트는 그대로 그리고 그대로 인덱싱하므로
/// 경계에서 자르지 않으면 조작된(또는 버전이 다른) 호스트가 게스트를 인덱스 범위 밖 접근으로
/// 죽인다. 화면은 `teamSpeciesIDs` 의 인덱스로 `stamina` 를 읽고(`PokeathlonView`),
/// `activeSpeciesID` 는 `activeTeamIndex` 로 팀을 읽는다 — 둘 다 음수·길이 불일치에 무방비다.
///
/// 형제 타입 `PokeathlonPool` 은 같은 이유로 이미 디코딩 클램프를 갖고 있다.
extension PokeathlonRacer {
    /// 한 러너가 데려가는 팀 상한. 방 정원이 아니라 화면 한 줄에 그려지는 수다.
    static let maximumTeamSize = 6
    static let maximumStamina = 100

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        trainerName = BattleChatPolicy.displayName(
            try c.decodeIfPresent(String.self, forKey: .trainerName) ?? "") ?? "?"
        speciesID = PokemonAssets.clampedID(try c.decode(Int.self, forKey: .speciesID))
        let team = (try c.decodeIfPresent([Int].self, forKey: .teamSpeciesIDs) ?? [])
            .prefix(Self.maximumTeamSize).map(PokemonAssets.clampedID)
        teamSpeciesIDs = Array(team)
        let slots = max(1, team.count)
        activeTeamIndex = min(max(0, try c.decodeIfPresent(Int.self, forKey: .activeTeamIndex) ?? 0), slots - 1)
        // 스태미나는 팀 자리 수와 **같은 길이여야 한다** — 화면이 팀 인덱스로 이 배열을 읽는다.
        let reported = (try c.decodeIfPresent([Int].self, forKey: .stamina) ?? [])
            .prefix(slots).map { min(Self.maximumStamina, max(0, $0)) }
        stamina = reported + Array(repeating: Self.maximumStamina, count: slots - reported.count)
        distance = min(PokeathlonRace.finishLine, max(0, try c.decodeIfPresent(Int.self, forKey: .distance) ?? 0))
        crashes = max(0, try c.decodeIfPresent(Int.self, forKey: .crashes) ?? 0)
        lane = min(2, max(0, try c.decodeIfPresent(Int.self, forKey: .lane) ?? 1))
        finished = try c.decodeIfPresent(Bool.self, forKey: .finished) ?? false
        lastActionAt = try c.decodeIfPresent(Date.self, forKey: .lastActionAt)
    }
}

extension PokeathlonRace {
    /// 트랙에 설 수 있는 러너 수. 방 정원(러너 최대 8)과 같은 값이다.
    static let maximumRacers = 8

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        racers = Array((try c.decode([PokeathlonRacer].self, forKey: .racers)).prefix(Self.maximumRacers))
        // 트랙에 없는 우승자는 정산이 아무에게도 안 닿는 값이다 — 없던 것으로 만든다.
        let winner = try c.decodeIfPresent(UUID.self, forKey: .winnerID)
        winnerID = racers.contains { $0.id == winner } ? winner : nil
        startsAt = try c.decodeIfPresent(Date.self, forKey: .startsAt) ?? Date()
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
        // HP·PP 는 **최대치 안에서만** 뜻이 있다. `validStart` 는 개시 시점만 보고 라운드마다 오는
        // 값은 호스트 소유다 — `hp: Int.max` 를 들이면 회복 이벤트를 재생하는 자리에서
        // `hp + amount` 가 오버플로로 트랩된다(`BattleReplay.apply`). 형제 표현
        // `TournamentPokemonState.side` 가 같은 자리에서 같은 규칙으로 자른다.
        //
        // **레이드 보스만 천장이 다르다.** 보스 HP 는 종족값이 아니라 티어가 정하는 절대값이라
        // (`RaidTier.bossHP`) 종족값으로 자르면 도착하자마자 만피의 5% 로 접힌다. 고정 id 에만
        // 열어 주고 **천장은 그대로 둔다** — 이 클램프의 목적은 오버플로 방지이고 그 목적은 상한이
        // 무엇이든 지켜진다. "이게 정말 오늘의 그 보스인가" 는 `RaidBoss.validBoss` 가 정확한
        // 등호로 따로 본다. 다른 전투원의 상한은 손대지 않는다.
        let hpCeiling = id == RaidBoss.bossID
            ? max(decoded.stats.hp, RaidTier.maxBossHP)
            : decoded.stats.hp
        decoded.hp = min(hpCeiling, max(0, try container.decode(Int.self, forKey: .hp)))
        decoded.pp = zip(decoded.pp, try container.decode([Int].self, forKey: .pp))
            .map { min($0.0, max(0, $0.1)) }
        // 풀죽음은 **volatile** 이라 주 상태 슬롯으로 오면 안 된다. 받아들이면 `canBeAfflicted` 가
        // "이미 주 상태가 있다"로 읽어 그 개체가 **모든 상태이상에 영구 면역**이 되고 턴 끝 잔뎀도
        // 안 받는다 — 호스트가 자기에게 붙이면 그대로 이득이다. 랭크 클램프와 같은 자리에서 버린다.
        let wireStatus = try container.decodeIfPresent(Status.self, forKey: .status)
        decoded.status = wireStatus == .flinch ? nil : wireStatus
        decoded.statusCounter = max(0, try container.decodeIfPresent(Int.self, forKey: .statusCounter) ?? 0)
        decoded.confusionTurns = max(0, try container.decodeIfPresent(Int.self, forKey: .confusionTurns) ?? 0)
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
              (1...2).contains(snapshot.types.count),
              validAbility(snapshot.ability) else { return false }
        let stats = snapshot.base
        guard [stats.hp, stats.atk, stats.def, stats.spa, stats.spd, stats.spe]
            .allSatisfy({ (1...255).contains($0) }) else { return false }
        return validMoves(snapshot.moves ?? [])
    }

    /// 특성 슬러그 범위. **문자열도 신뢰경계다** — 숫자만 자르면 500자 슬러그가 라운드 메시지마다
    /// 실려 나간다. 빈 문자열도 막는다("특성이 없다"는 `nil` 하나로만 표현한다).
    ///
    /// **글자 수가 아니라 바이트로 잰다.** `count` 는 grapheme 을 세므로 40글자가 수 KB 일 수 있다
    /// (ZWJ 이모지 한 글자가 수십 바이트). 스냅샷은 `roundResolved` 로 매 라운드 참가자 수만큼 다시
    /// 나가므로, 막으려던 증폭이 상한을 지킨 채로 그대로 일어난다.
    ///
    /// 모르는 슬러그는 **여기서 거르지 않는다.** 해석 시점(`BattleAbility.resolve`)에 `nil` 로 접혀
    /// 배틀을 안 바꾸고, 여기서 거르면 신버전 피어가 특성을 하나 늘릴 때마다 입장 자체가 거절된다.
    static func validAbility(_ slug: String?) -> Bool {
        slug.map { !$0.isEmpty && $0.utf8.count <= BattleAbility.maxSlugLength } ?? true
    }

    /// 한 턴 데미지 천장 — **위력 × 히트 수**. `validMoves` 가 상대 무브셋을 이 값으로 자르고,
    /// `MoveSpec.from` 은 도감이 이 값을 넘기 시작하면 로그를 남긴다. 두 곳이 리터럴을 따로 들면
    /// 경고와 반려가 갈라져, 넘었다고 찍은 기술이 통과하거나 통과한다고 본 기술이 반려된다.
    static let turnDamageCap = 250

    /// 도감 기술이 천장을 넘는가 — 넘으면 **정상 기술이 상대에게서 반려된다.**
    /// 상대가 보내온 값을 거르는 `validMoves` 와 방향만 다르고 규칙은 같아야 한다.
    static func exceedsTurnDamageCap(_ move: MoveSpec) -> Bool {
        move.power * (move.maxHits ?? 1) > turnDamageCap
    }

    /// 상대 무브셋 범위 검사. **1v1 LAN 도 이 함수를 쓴다** — 방에만 두면 1v1 이 무검사가 된다.
    static func validMoves(_ moves: [MoveSpec]) -> Bool {
        guard moves.count <= 4 else { return false }
        return moves.allSatisfy {
            (0...turnDamageCap).contains($0.power) && (1...100).contains($0.pp)
                && ($0.accuracy.map { (1...100).contains($0) } ?? true)
                // 상태 부여 확률은 상대가 보내오는 값이다 — 범위를 벗어나면 매번 확정 부여가 된다.
                && ($0.ailmentChance.map { (0...100).contains($0) } ?? true)
                && ($0.statChance.map { (0...100).contains($0) } ?? true)
                // 흡수 상한은 도감 최대치(75, 드레인키스). 100 을 들이면 넣은 데미지를 그대로
                // 되돌려받아 매 턴 만피로 돌아간다. 반동(음수)은 자기 손해라 안 막는다.
                && ($0.drain.map { (-100...75).contains($0) } ?? true)
                && ($0.flinchChance.map { (0...100).contains($0) } ?? true)
                && ($0.minHits.map { (1...10).contains($0) } ?? true)
                && ($0.maxHits.map { (1...10).contains($0) } ?? true)
                && (($0.minHits ?? 1) <= ($0.maxHits ?? $0.minHits ?? 1))
                // **히트 수는 위력 상한을 곱한다.** 축마다 따로 보면 `위력 250 × 10 히트` 가 전부
                // 범위 안이라 250 이 지키던 한 턴 천장이 10배로 열린다.
                //
                // ponytail: 250 은 도감 다단기 총합 최대 100(드래곤애로우·기어소서) 기준으로 잡은
                //           천장이다 — 총합 100 을 넘는 다단기가 도감에 생기면 다시 계산한다.
                //           **그 순간을 알리는 것은 `MoveSpec.from` 의 로그다.** 도감은 원격이라
                //           코드를 안 건드려도 넘어설 수 있고, 넘어서면 정상 기술이 반려된다.
                && !exceedsTurnDamageCap($0)
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
        guard MultiplayerBattle.validCount(fighters.count, mode: mode),
              Set(fighters.map(\.id)).count == fighters.count else { return false }
        guard fighters.allSatisfy({ fighter in
            valid(participant: LobbyParticipant(id: fighter.id, trainerName: fighter.trainerName,
                                                speciesID: fighter.side.snapshot.speciesID, team: fighter.team,
                                                isReady: true, isHost: false),
                  snapshot: fighter.side.snapshot)
                // 협동 보스전의 보스만 "최대 HP 로 시작" 에서 빠진다 — 보스 HP 는 종족값이 아니라
                // 티어가 정하는 절대값이다(`RaidTier.bossHP`). 그 값이 오늘의 티어와 정확히 맞는지는
                // `RaidBoss.validBoss` 가 본다. 여기서는 "살아는 있는가" 까지만 본다.
                && (fighter.side.hp == fighter.side.stats.hp || (isRaidBoss(fighter, mode: mode) && fighter.side.hp > 0))
                // 상태이상도 호스트가 보내오는 값이다. 최대 HP 로 시작하는 배틀이면 상태도 없어야 한다 —
                // 안 보면 `status: sleep, statusCounter: 9999` 로 시작해 게스트가 영구히 못 움직인다.
                && fighter.side.status == nil && fighter.side.confusionTurns == 0
                // 랭크도 같은 이유로 0 이어야 한다 — `stages: [atk: 6]` 로 시작하는 방을 막는다.
                && fighter.side.stages.isEmpty
        }) else { return false }
        switch mode {
        case .freeForAll:
            return fighters.allSatisfy { $0.team == .solo }
        case .teams:
            return fighters.count == 4 && fighters.filter { $0.team == .red }.count == 2
                && fighters.filter { $0.team == .blue }.count == 2
        case .coopBoss:
            // 보스 하나 + 러너 1~4. **러너 1명을 허용하는 것이 요점이다** — LAN 은 이웃이 없을 수
            // 있고, 1★ 를 혼자 못 돌면 이 기능은 이웃 없는 사람에게 콘텐츠가 0 이다.
            return fighters.filter { $0.team == .blue }.count == 1
                && (1...4).contains(fighters.filter { $0.team == .red }.count)
                && fighters.allSatisfy { $0.team != .solo }
                // 러너는 전부 파티 레벨로 눕는다(체육관·토너먼트와 같은 규칙). **레벨은 따로 봐야
                // 한다** — `hp == stats.hp` 는 개시 시점에 계산된 스탯과 비교하므로, 스냅샷의 레벨만
                // 100 으로 적어 보낸 편성도 그 검사만으로는 통과한다.
                && fighters.filter { $0.team == .red }
                    .allSatisfy { $0.side.snapshot.level == RaidBoss.partyLevel }
        }
    }

    private static func isRaidBoss(_ fighter: MultiplayerFighter, mode: MultiplayerBattleMode) -> Bool {
        mode == .coopBoss && fighter.team == .blue
    }
}

/// 4인 방의 와이어 계약. 호스트 권위형이라 클라이언트는 참가/준비/행동만 보내고,
/// 로비 상태와 라운드 결과는 호스트가 전 참가자에게 브로드캐스트한다.
enum MultiplayerWireMessage: Codable, Sendable, Equatable {
    // 호스트가 `roundResolved` 를 브로드캐스트하므로 구버전 게스트는 모르는 모양을 만나면 라운드를
    // 디코딩하지 못하고 멈춘다 → 입장 단계에서 막는다.
    // 2: LobbyParticipant.role + 관전자 베팅, 3: 이벤트 스트림, 4: 상태이상(status 필드 + case 추가),
    // 5: 랭크(stages 필드 + `.boost` case), 6: 방 전체 자유 채팅, 7: 포켓몬 OX 퀴즈,
    // 8: 안 읽던 `meta` 필드 넷(드레인·반동·다단 히트·풀린치 — `Status.flinch` case 추가),
    // 9: 특성 1단계(`BattleSnapshot.ability`), 10: 전 특성 규칙, 11: 3대3 토너먼트 상태·행동,
    // 12: 공유 체육관(도전·거절·상태·행동·승계), 13: 토너먼트 6마리 후보 공개,
    // 14: 기절 뒤 강제 교체가 턴을 소비하지 않고 새 포켓몬의 기술 선택을 받음.
    // 방은 `rulesVersion` 을 안 본다 — 규칙 차이를 막을 곳이 여기뿐이라 규칙이 바뀌면 이 값도 같이 올린다.
    // 15: LAN 협동 레이드(`.raidStart`·`.raidSettlement`, `MultiplayerBattleMode.coopBoss`).
    static let protocolVersion = 15
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
    case tournamentTeam(participantID: UUID, lineup: [BattleSnapshot])
    case tournamentPool(participantID: UUID, lineup: [BattleSnapshot])
    case tournamentPools([UUID: [BattleSnapshot]])
    case tournamentStart(state: PokemonTournamentState)
    case tournamentAction(matchID: UUID, participantID: UUID, action: NetBattleAction)
    case tournamentState(PokemonTournamentState)
    // 공유 체육관. 관장이 호스트라 도전은 게스트→호스트, 판정과 상태는 호스트→전원이다.
    case gymChallenge(participantID: UUID, lineup: [BattleSnapshot])
    case gymRejected(reason: GymChallengeRejection)
    case gymState(GymMatchState)
    case gymAction(matchID: UUID, participantID: UUID, action: NetBattleAction)
    /// 승계 — 진 관장이 이긴 도전자에게만 개별 전송한다. 쿨다운 원장은 넘기지 않는다(초기화).
    case gymHandoff(gymID: UUID)
    // 레이드. `.start` 에 티어를 끼우지 않고 case 를 새로 낸 이유는 호환이다 — `.start` 의 모양을
    // 바꾸면 1v1·4인 방까지 전부 JSON 이 달라진다.
    case raidStart(seed: UInt64, fighters: [MultiplayerFighter], tier: RaidTier)
    /// 정산의 기여도 항. 남은 턴·생존자는 받는 쪽이 자기 `combatFighters`·`combatRound` 로 알지만,
    /// **누가 얼마나 넣었는지는 호스트만 안다**(`MultiplayerBattle.damageDealt`).
    case raidSettlement(contributions: [UUID: Int])
    case chat(BattleChatMessage)
}

/// 2~4명 개인전/2:2 공용 결정적 전투 상태. 네트워크는 action만 모아 호스트가 resolveRound를 호출한다.
struct MultiplayerBattle: Sendable {
    private(set) var fighters: [MultiplayerFighter]
    let mode: MultiplayerBattleMode
    private(set) var round = 1
    private(set) var events: [BattleEvent] = []
    /// 참가자별 **보스에게** 넣은 누적 피해 — 협동 보스전 정산의 기여도 항이 읽는 값이다.
    ///
    /// 이벤트 스트림으로는 못 만든다: `BattleEvent.damage` 의 주인은 **맞은 쪽**이라 누가 때렸는지가
    /// 실려 있지 않다. 공격자를 아는 유일한 자리가 아래 해상 루프다.
    private(set) var damageDealt: [UUID: Int] = [:]
    private var rng: SplitMix64

    /// 모드별 정원. 협동 보스전만 한 자리를 더 쓴다 — 러너 1~4 **더하기 보스 하나**라 최대 5다.
    /// 다른 모드의 상한은 그대로 4다(협동전 때문에 개인전이 5명이 되면 안 된다).
    static func validCount(_ count: Int, mode: MultiplayerBattleMode) -> Bool {
        mode == .coopBoss ? (2...5).contains(count) : (2...4).contains(count)
    }

    init(fighters: [MultiplayerFighter], mode: MultiplayerBattleMode, seed: UInt64) throws {
        guard Self.validCount(fighters.count, mode: mode) else { throw MultiplayerBattleError.invalidFighterCount }
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
        // 협동 보스전이 같은 줄을 타는 것이 설계다 — 보스가 죽으면 남은 팀은 러너뿐이고,
        // 파티가 전멸하면 남은 팀은 보스뿐이다. 별도 규칙을 쓰면 두 규칙이 갈라질 자리만 는다.
        case .teams, .coopBoss: return Set(living.map(\.team)).count <= 1
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
        case .teams, .coopBoss: return fighters.filter { $0.team == winningTeam }.map(\.id)
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

    /// 턴 상한에 닿았나. **`static` 인 이유는 `isFinished`·`winners` 와 같다** — 게스트는 자기
    /// `battle` 을 갱신하지 않으므로(라운드마다 오는 건 `fighters` 배열이다) 인스턴스에만 두면
    /// 게스트 쪽 판정이 개시 시점에 굳는다.
    ///
    /// 상한 라운드 **자체는 아직 싸운다** — `round` 는 해상 뒤에 오르므로 `> turnCap` 이 곧
    /// "상한만큼 싸웠다" 다.
    static func reachedTurnCap(round: Int, mode: MultiplayerBattleMode) -> Bool {
        mode == .coopBoss && round > RaidBoss.turnCap
    }

    var reachedTurnCap: Bool { Self.reachedTurnCap(round: round, mode: mode) }

    /// 상한이 지났다 — 파티를 전멸 처리해 판을 닫는다.
    ///
    /// **새 종료 상태를 만들지 않는 것이 요점이다.** 여기서 러너를 눕히면 기존
    /// `isFinished`·`winners`·`grantRewardIfFinished`·`broadcastCombatState` 가 그대로 패배를
    /// 닫고, 게스트도 늘 받던 라운드 메시지로 같은 결말을 본다 — 판정이 두 벌이 되지 않는다.
    mutating func endByTurnCap() {
        for index in fighters.indices where fighters[index].team == .red {
            fighters[index].side.hp = 0
        }
    }

    /// 보스가 이번 턴에 할 일 — **보스에겐 클라이언트가 없어 호스트가 대신 낸다.**
    ///
    /// 점수식은 카탈로그 관장·공유 체육관 AI 와 같은 `BattleEngine.expectedDamageScore` 다.
    /// 난수를 쓰지 않는다: 이 함수는 호스트만 부르지만, 흔들리면 같은 판이 재현되지 않아
    /// 결함 재현이 불가능해진다. 동점은 대상 UUID 문자열 순으로 가른다(`automaticActions` 와 같다).
    static func bossAction(fighters: [MultiplayerFighter]) -> MultiplayerAction? {
        guard let boss = fighters.first(where: { $0.id == RaidBoss.bossID }), boss.isAlive else { return nil }
        let targets = fighters
            .filter { $0.id != boss.id && $0.isAlive && $0.team != boss.team }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        guard let fallbackTarget = targets.first else { return nil }

        var best: (score: Int, moveIndex: Int, targetID: UUID)?
        for target in targets {
            for index in boss.side.moves.indices where boss.side.canUse(moveAt: index) {
                let score = BattleEngine.expectedDamageScore(of: boss.side.moves[index],
                                                             from: boss.side, to: target.side)
                if score > (best?.score ?? -1) { best = (score, index, target.id) }
            }
        }
        // 점수가 전부 0 이거나 PP 가 말랐어도 **행동은 낸다** — 안 내면 라운드가 마감까지 멈춘다.
        // `-1` 은 발버둥이다(1v1·개인전과 같은 규약).
        let chosen = best ?? (0, boss.side.pp.firstIndex(where: { $0 > 0 }) ?? -1, fallbackTarget.id)
        return MultiplayerAction(attackerID: boss.id, targetID: chosen.targetID,
                                 moveIndex: chosen.moveIndex)
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
            let targetHPBefore = target.hp
            roundEvents += BattleEngine.applyAttack(attacker: &attacker, defender: &target,
                                                    attackerActor: .fighter(fighters[ai].id),
                                                    defenderActor: .fighter(fighters[ti].id),
                                                    move: move, rng: &rng)
            fighters[ai].side = attacker
            fighters[ti].side = target
            // 보스에게 들어간 몫만 센다 — 러너끼리 때릴 수는 없지만, 보스가 러너를 때린 것을
            // 기여도로 세면 정산이 보스에게 보상을 배정한다.
            if mode == .coopBoss, fighters[ti].team == .blue {
                damageDealt[fighters[ai].id, default: 0] += max(0, targetHPBefore - fighters[ti].side.hp)
            }
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
