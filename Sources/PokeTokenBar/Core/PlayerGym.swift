import Foundation

/// 공유 체육관 — 같은 네트워크에서 **하나의 체육관을 두고 겨루고, 이긴 사람이 관장이 된다.**
///
/// 카탈로그 체육관(`GymLeague`)과는 이름만 겹치는 별개 시스템이다. 그쪽은 혼자 도전하는 고정
/// 관장 8명이고, 이쪽은 사람이 관장 자리를 주고받는다.
///
/// **관장이 곧 방 호스트다.** 중앙 서버가 없으므로 체육관은 관장이 앱을 켜 둔 동안에만 존재한다
/// (AI 방어도 관장 기기에서 돈다 — 오프라인 자동 방어가 아니다). 대신 아무도 방에 상주하지
/// 않는다 — 관장은 광고만 띄워 두고 도전자·관전자는 그때그때 접속했다 나간다. 그래서 관장이
/// 업데이트로 재시작해도 광고가 잠깐 꺼졌다 다시 뜰 뿐, 재입장시킬 대상이 없다.
enum PlayerGym {
    /// 방어팀·도전팀 모두 이 머릿수다. 머릿수가 다르면 이겨도 이긴 것 같지 않다
    /// (`GymLeague.teamSize` 주석과 같은 이유).
    static let defenseTeamSize = 4

    /// 배틀에 세우는 레벨. 양쪽을 같은 값으로 눕혀 **레벨 공사가 아니라 팀 구성과 상성**으로
    /// 갈리게 한다 — 토너먼트(`TournamentMatchEngine`)와 같은 규칙이다. 레벨을 그대로 쓰면
    /// 먼저 키운 사람이 관장을 놓지 않아 컨텐츠가 멈춘다.
    static let battleLevel = 50

    /// 관장이 방어팀을 채울 기한. 넘기면 자격을 잃는다 — 이게 없으면 이기고 세팅을 안 한 사람이
    /// 체육관을 무한 점유하고 아무도 도전하지 못한다.
    static let defenseSetupWindow: TimeInterval = 5 * 60

    /// 같은 도전자가 다시 도전하기까지의 간격. **배틀이 끝난 시각**부터 잰다.
    ///
    /// 위 `defenseSetupWindow` 와 값이 같지만 **목적이 다르므로 상수를 따로 둔다** — 하나로
    /// 묶으면 한쪽을 조정할 때 다른 쪽이 딸려 간다.
    static let challengeCooldown: TimeInterval = 5 * 60

    /// 방 이름 접두사. 방 광고에는 TXT 레코드가 없어 이름 문자열이 유일한 단서다
    /// (`RUN`/`QUIZ`/`TOUR`/`BATTLE` 과 같은 관례).
    static let roomNamePrefix = "GYM"

    /// 이 이름이 공유 체육관 방인가.
    static func isGymRoomName(_ name: String) -> Bool { name.hasPrefix("\(roomNamePrefix) ·") }

    /// Bonjour 서비스 이름 상한. 프로토콜이 정한 값이라 넘기면 광고가 아예 안 뜬다 —
    /// 한국어 이름은 글자당 3바이트라 20자면 60바이트다. 넘칠 땐 **이름을 자른다**(재임 시각과
    /// 식별자는 자르면 뜻을 잃는다).
    static let maxServiceNameBytes = 63

    /// 방어팀이 정원 미만이 된 시점에서 계산한 마감. 정원을 채웠으면 마감이 없다(nil).
    static func setupDeadline(defenseCount: Int, now: Date) -> Date? {
        defenseCount >= defenseTeamSize ? nil : now.addingTimeInterval(defenseSetupWindow)
    }

    /// 쿨다운이 풀렸나. 기록이 없으면(첫 도전) 통과한다.
    static func challengeAllowed(lastFinishedAt: Date?, now: Date) -> Bool {
        guard let lastFinishedAt else { return true }
        return now.timeIntervalSince(lastFinishedAt) >= challengeCooldown
    }

    /// 남은 쿨다운(초). 0 이면 지금 도전할 수 있다.
    static func remainingCooldown(lastFinishedAt: Date?, now: Date) -> TimeInterval {
        guard let lastFinishedAt else { return 0 }
        return max(0, challengeCooldown - now.timeIntervalSince(lastFinishedAt))
    }

    /// 재임 기간을 분으로. 표시 단위가 분이라 여기서 잘라 두면 화면이 매초 다시 그려도 값이 안 튄다.
    static func tenureMinutes(since: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(since) / 60))
    }

    /// 체육관이 둘 보일 때 **어느 쪽이 남는가.** 두 기기가 같은 답을 내야 하므로 발견 시각처럼
    /// 기기마다 다른 값을 쓰지 않는다 — 그러면 둘 다 닫거나 둘 다 남는다.
    static func survivor(_ one: UUID, _ other: UUID) -> UUID {
        one.uuidString < other.uuidString ? one : other
    }
}

/// 체육관 방 이름에 실어 나르는 정보 — **관장 이름과 재임 시작 시각**.
///
/// 방 광고(`_kmonroom._tcp`)에는 TXT 레코드가 없어서(리스너·브라우저 어느 쪽도 요청하지 않는다)
/// 이름 문자열이 유일한 통로다. 그래서 목록에서 "누가 몇 분째 지키고 있는지"를 **접속하지 않고**
/// 보려면 여기 실어야 한다.
///
/// 형식: `GYM · <재임시작 base36> · <관장이름>#<식별자앞6>`
///
/// 재임 시각을 **이름보다 앞에** 두는 이유는 길이 때문이다. 상한을 넘으면 이름을 자르는데,
/// 뒤에 있으면 잘려 나가 뜻을 잃는다. 식별자가 맨 끝인 것은 기존 파서(`split("#").last`)와
/// 내 방 판별(`name.contains(myIDTag)`)이 그 자리를 보기 때문이다.
struct PlayerGymRoomName: Equatable {
    let heldSince: Date
    let leaderName: String
    let idTag: String

    static func make(leaderName: String, idTag: String, heldSince: Date) -> String {
        let stamp = String(Int(heldSince.timeIntervalSince1970), radix: 36)
        let fixed = "\(PlayerGym.roomNamePrefix) · \(stamp) · #\(idTag)"
        let budget = PlayerGym.maxServiceNameBytes - fixed.utf8.count
        var name = leaderName
        while name.utf8.count > max(0, budget), !name.isEmpty { name.removeLast() }
        return "\(PlayerGym.roomNamePrefix) · \(stamp) · \(name)#\(idTag)"
    }

    /// 옛 형식(`GYM · 이름#식별자`)도 읽는다 — 재임 시각이 없으면 nil 이라 화면이 시간을 생략한다.
    static func parse(_ name: String) -> PlayerGymRoomName? {
        guard PlayerGym.isGymRoomName(name) else { return nil }
        let body = name.dropFirst("\(PlayerGym.roomNamePrefix) · ".count)
        guard let hash = body.lastIndex(of: "#") else { return nil }
        let idTag = String(body[body.index(after: hash)...])
        let head = body[..<hash]
        guard let separator = head.range(of: " · ") else { return nil }
        let stamp = String(head[..<separator.lowerBound])
        guard let seconds = Int(stamp, radix: 36) else { return nil }
        return PlayerGymRoomName(heldSince: Date(timeIntervalSince1970: TimeInterval(seconds)),
                                 leaderName: String(head[separator.upperBound...]),
                                 idTag: idTag)
    }
}

/// 도전이 거절된 이유. 화면이 문구를 고르고, 쿨다운은 남은 초를 함께 싣는다.
enum GymChallengeRejection: Codable, Sendable, Equatable {
    /// 관장이 이미 다른 도전을 받고 있다. 대기열은 두지 않으므로 나중에 다시 누른다.
    case busy
    /// 방어팀이 아직 정원 미만이라 도전을 받을 수 없다.
    case notReady
    case cooldown(remainingSeconds: Int)
}

/// 체육관 한 판의 진행 상태 — 관장·도전자·관전자가 **같은 값을 보고 같은 화면을 그린다.**
/// 판정은 호스트(관장)만 한다.
///
/// 개체 표현은 `TournamentPokemonState` 를 그대로 쓴다. 이름은 토너먼트에서 왔지만 내용은
/// "`BattleSide` 의 관전용 와이어 표현"(그 타입 주석)이라 이 컨텐츠에도 그대로 맞는다 —
/// 같은 것을 한 벌 더 만들 이유가 없다.
struct GymMatchState: Codable, Sendable, Equatable {
    let matchID: UUID
    /// 관장(방어)과 도전자(공격). 배틀 엔진의 A 자리가 항상 관장이다.
    let leaderID: UUID
    let challengerID: UUID
    let leaderName: String
    let challengerName: String
    var leaderTeam: [TournamentPokemonState]
    var challengerTeam: [TournamentPokemonState]
    var leaderActive: Int
    var challengerActive: Int
    var turn: Int
    /// 그 턴에 일어난 이벤트만. 로그는 화면이 접는다.
    var events: [BattleEvent]
    var submitted: Set<UUID>
    var winnerID: UUID?

    func team(for playerID: UUID) -> [TournamentPokemonState]? {
        playerID == leaderID ? leaderTeam : (playerID == challengerID ? challengerTeam : nil)
    }
}

/// 체육관 한 판의 권위형 엔진. `TournamentMatchEngine` 과 같은 구조로 `NetBattleState` 를 감싼다 —
/// 기술·교체·특성·상태이상이 1:1 배틀과 완전히 같은 규칙으로 돌아간다.
struct GymMatchEngine {
    let matchID: UUID
    let leaderID: UUID
    let challengerID: UUID
    let leaderName: String
    let challengerName: String
    private(set) var battle: NetBattleState

    init(matchID: UUID = UUID(),
         leaderID: UUID, challengerID: UUID,
         leaderName: String, challengerName: String,
         leaderTeam: [BattleSnapshot], challengerTeam: [BattleSnapshot],
         seed: UInt64) {
        self.matchID = matchID
        self.leaderID = leaderID
        self.challengerID = challengerID
        self.leaderName = leaderName
        self.challengerName = challengerName
        // 양쪽을 같은 레벨로 눕힌다. 레벨 차가 상성을 덮으면 이 컨텐츠의 공략이 사라진다.
        let normalizedLeader = leaderTeam.map { snapshot -> BattleSnapshot in
            var snapshot = snapshot; snapshot.level = PlayerGym.battleLevel; return snapshot
        }
        let normalizedChallenger = challengerTeam.map { snapshot -> BattleSnapshot in
            var snapshot = snapshot; snapshot.level = PlayerGym.battleLevel; return snapshot
        }
        battle = NetBattleState(iAmA: true,
                                myTeam: normalizedLeader.map(BattleSide.init),
                                oppTeam: normalizedChallenger.map(BattleSide.init),
                                rng: SplitMix64(seed: seed))
        // 쓰러진 자리를 엔진이 자동으로 메우지 않는다 — 다음에 누구를 내보낼지는 사람이 고른다.
        battle.automaticallyReplacesFainted = false
    }

    mutating func submit(_ action: NetBattleAction, from playerID: UUID) -> Bool {
        if playerID == leaderID {
            guard battle.myAction == nil, battle.canChoose(action, mine: true) else { return false }
            battle.myAction = action
        } else if playerID == challengerID {
            guard battle.oppAction == nil, battle.canChoose(action, mine: false) else { return false }
            battle.oppAction = action
        } else { return false }
        return true
    }

    var isReady: Bool { battle.myAction != nil && battle.oppAction != nil }

    /// 승부가 났으면 승자 id. 무승부는 남은 HP 합으로 가르고, 그마저 같으면 **방어 성공**이다 —
    /// 도전자가 관장을 확실히 이겨야 자리를 가져간다.
    @discardableResult mutating func resolveIfReady() -> UUID? {
        guard isReady else { return nil }
        switch battle.resolveChosenActions() {
        case .win: return leaderID
        case .loss: return challengerID
        case .draw:
            let leaderHP = battle.myTeam.reduce(0) { $0 + $1.hp }
            let challengerHP = battle.oppTeam.reduce(0) { $0 + $1.hp }
            if leaderHP != challengerHP { return leaderHP > challengerHP ? leaderID : challengerID }
            return leaderID
        case nil: return nil
        }
    }

    /// 마감이 지났거나 관장이 AI 모드일 때 비어 있는 행동을 채운다.
    ///
    /// 관장 쪽은 `usesAI` 면 상성·랭크·명중률까지 보는 점수식으로 고르고(체육관 카탈로그 관장이
    /// 쓰는 그 식이다), 도전자 쪽과 AI 가 아닌 관장은 마감 대타라 첫 사용가능 기술로 채운다.
    mutating func fillMissingActions(leaderUsesAI: Bool) {
        if battle.myAction == nil {
            battle.myAction = leaderUsesAI
                ? bestAction(team: battle.myTeam, active: battle.myActive, against: battle.opp)
                : firstAvailableAction(team: battle.myTeam, active: battle.myActive)
        }
        if battle.oppAction == nil {
            battle.oppAction = firstAvailableAction(team: battle.oppTeam, active: battle.oppActive)
        }
    }

    func snapshot(winnerID: UUID? = nil) -> GymMatchState {
        GymMatchState(matchID: matchID,
                      leaderID: leaderID, challengerID: challengerID,
                      leaderName: leaderName, challengerName: challengerName,
                      leaderTeam: battle.myTeam.map(TournamentPokemonState.init),
                      challengerTeam: battle.oppTeam.map(TournamentPokemonState.init),
                      leaderActive: battle.myActive, challengerActive: battle.oppActive,
                      turn: battle.turn,
                      events: battle.eventBatches.last?.events ?? [],
                      submitted: Set([battle.myAction == nil ? nil : leaderID,
                                      battle.oppAction == nil ? nil : challengerID].compactMap { $0 }),
                      winnerID: winnerID)
    }

    /// 상성·랭크·명중률을 보는 선택. 교체는 판단하지 않는다 — 쓰러진 자리만 다음 생존자로 넘긴다.
    private func bestAction(team: [BattleSide], active: Int, against target: BattleSide) -> NetBattleAction {
        guard team.indices.contains(active) else { return .move(index: -1) }
        let attacker = team[active]
        if !attacker.isAlive, let next = team.indices.first(where: { team[$0].isAlive }) {
            return .switchTo(index: next)
        }
        if attacker.mustStruggle { return .move(index: -1) }
        let usable = attacker.pp.indices.filter { attacker.canUse(moveAt: $0) }
        guard !usable.isEmpty else { return .move(index: -1) }
        let best = usable.max { left, right in
            BattleEngine.expectedDamageScore(of: attacker.move(at: left), from: attacker, to: target)
                < BattleEngine.expectedDamageScore(of: attacker.move(at: right), from: attacker, to: target)
        }
        return .move(index: best ?? usable[0])
    }

    private func firstAvailableAction(team: [BattleSide], active: Int) -> NetBattleAction {
        guard team.indices.contains(active) else { return .move(index: -1) }
        if !team[active].isAlive, let next = team.indices.first(where: { team[$0].isAlive }) {
            return .switchTo(index: next)
        }
        if team[active].mustStruggle { return .move(index: -1) }
        return .move(index: team[active].pp.indices.first { team[active].canUse(moveAt: $0) } ?? -1)
    }
}
