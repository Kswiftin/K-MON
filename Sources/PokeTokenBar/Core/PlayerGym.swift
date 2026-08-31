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

    // MARK: 보상 — **방어에만** 준다

    /// 방어 성공 1회.
    ///
    /// **점령에는 주지 않는다.** 관장이 바뀌면 쿨다운 원장이 비워지므로, 둘이 번갈아 뺏으면 5분
    /// 제한이 한 번도 걸리지 않는다(배틀 시간만이 제약이라 시간당 열 번 넘게 왕복한다).
    /// 점령에 값을 붙이는 순간 그 왕복이 그대로 파밍이 된다 — 0 이면 서로 져 줘도 아무도 방어
    /// 성공이 없어 무의미해진다. 점령 유인은 따로 필요 없다: 관장이 되어야 방어 보상을 받는다.
    ///
    /// 방어 쪽에 싣는 또 다른 이유는 균형이다. 방어팀 넷은 관전으로 다 노출되고, 육성·다른
    /// 배틀에서 잠기고, AI 모드는 교체를 판단하지 못한다 — 방어가 불리하다.
    ///
    /// 1,000 인 근거는 **능동 플레이 대비**다. 해안 모험(2시간, 7,200)은 누르고 방치하면 끝이지만
    /// 방어 일곱 번은 일곱 판을 연달아 이겨야 하고(한 판 3~5분), 한 번 지면 자리까지 잃는다.
    static let defenseReward = 1_000

    /// 이만큼 연속으로 지키면 보너스. 자리를 잃으면 0 부터 다시 센다.
    static let defenseStreakLength = 3
    static let defenseStreakBonus = 1_000

    /// 하루에 방어로 벌 수 있는 상한. **짜고 지는** 반대 방향 파밍을 막는 마지막 방어선이다 —
    /// 도전자가 일부러 져 주면 한 판이 1분도 안 걸려, 둘이 번갈아 도전하면 시간당 스무 번을 넘긴다.
    ///
    /// 회당 금액과 역할이 다르다는 점이 중요하다: **회당은 정직한 플레이의 체감**을 정하고,
    /// **파밍을 막는 것은 이 상한**이다. 그래서 회당을 올릴수록 이 값이 더 중요해진다.
    ///
    /// 1,000×6 + 1,000×2(3·6연승) = 8,000 이라 **여섯 번 지키면 상한**이다. 해안 모험 한 번보다
    /// 조금 위인데, 여섯 판을 연달아 이긴 값으로는 타당하다. 관장이 자주 바뀌는 판에서 하루
    /// 두세 번이 현실적이라 실수령은 2,000~3,000 — 던전(1,000)과 해안 모험(7,200) 사이다.
    static let dailyDefenseRewardCap = 8_000

    /// 도전 기록 보관 수. 전적(`battleHistory`)과 같은 30 이다 — 세이브가 무한히 늘지 않게.
    static let defenseLogLimit = 30

    /// 승패가 난 뒤 결과 화면을 보여 주는 시간. 이 뒤에 판을 지워 **다음 도전을 받을 수 있게** 한다.
    ///
    /// 안 지우면 끝난 판이 그대로 남아 `acceptGymChallenge` 의 "이미 배틀 중" 가드에 걸린다 —
    /// 한 번 방어한 체육관이 영구히 잠긴다.
    static let resultDisplaySeconds: TimeInterval = 4

    /// 이번 방어로 받을 금액. 상한을 넘는 만큼은 잘라 낸다.
    static func defensePayout(consecutiveDefenses: Int, earnedToday: Int) -> Int {
        let streakBonus = consecutiveDefenses > 0 && consecutiveDefenses % defenseStreakLength == 0
            ? defenseStreakBonus : 0
        let raw = defenseReward + streakBonus
        return max(0, min(raw, dailyDefenseRewardCap - earnedToday))
    }

    /// 이 이름이 공유 체육관 방인가.
    static func isGymRoomName(_ name: String) -> Bool { name.hasPrefix("\(roomNamePrefix) ·") }

    /// Bonjour 서비스 이름 상한. 네 LAN 센터가 공유하는 값이라 `LANServiceName` 이 원본이고
    /// 여기는 별칭이다 — 두 벌로 두면 한쪽만 고쳐진다.
    static let maxServiceNameBytes = LANServiceName.maxBytes

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
        // 자를 수 있는 건 관장 이름뿐이다 — 접두(GYM)·재임 시각·식별자는 파싱에 필요하다.
        // `base` 꼬리가 곧 이름이라 `LANServiceName` 의 꼬리 절단이 그대로 맞는다.
        return LANServiceName.make(base: "\(PlayerGym.roomNamePrefix) · \(stamp) · \(leaderName)",
                                   suffix: "#\(idTag)")
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

/// 내 체육관에 들어온 도전 한 건의 기록 — **누가 언제 왔고 어떻게 됐나.**
///
/// 관장 자리를 잃어도 남는다. 체육관의 기록이 아니라 **내 기록**이라, 자리를 되찾았을 때
/// 지난 도전을 그대로 이어 본다.
struct GymDefenseRecord: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var challengerName: String
    var at: Date
    /// 내가 지켰나. false 면 이 판에서 자리를 내줬다.
    var defended: Bool
    /// 그 방어로 받은 별의조각. 0 이면 하루 상한에 걸렸거나 진 판이다.
    var payout: Int
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
    /// **관장 몫만** 채운다. AI 모드에서 매 턴 부르는 자리다.
    ///
    /// 도전자 몫까지 채우면 사람이 고르기도 전에 판이 해상되어 **AI 끼리 알아서 끝난다.**
    /// 실제로 그렇게 만들었다가 도전자가 아무것도 못 누르는 배틀이 됐다 — 그래서 "둘 다 채우는"
    /// 함수와 자리를 갈라 둔다.
    mutating func fillLeaderAction(usingAI: Bool) {
        guard battle.myAction == nil else { return }
        battle.myAction = usingAI
            ? bestAction(team: battle.myTeam, active: battle.myActive, against: battle.opp)
            : firstAvailableAction(team: battle.myTeam, active: battle.myActive)
    }

    /// 양쪽을 다 채운다 — **턴 마감(30초)에서만** 쓴다. 사람이 시간 안에 안 고른 것을 대신하는
    /// 자리라 도전자 몫도 채우는 것이 맞다.
    mutating func fillTimedOutActions(leaderUsesAI: Bool) {
        fillLeaderAction(usingAI: leaderUsesAI)
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
