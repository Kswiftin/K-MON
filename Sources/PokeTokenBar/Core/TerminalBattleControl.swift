import Foundation

/// 터미널이 LAN 대전에 닿는 **좁은 창구.**
///
/// `BattleCenter` 를 실행기에 그대로 넘기지 않는 이유는 테스트다. 그 타입은 Bonjour 광고·소켓·
/// 턴 타이머를 들고 기동 시 `start()` 로 살아나므로, 실행기 테스트가 그것을 만들면 실제 네트워크로
/// 나간다. 창구를 좁혀 두면 가짜를 끼워 **거절 사유와 실제 호출을 프로세스 없이** 검증할 수 있다
/// (`PokeProviding`·`BattleChallengeTimeoutScheduling` 과 같은 이유).
///
/// LAN 대전의 신청·수락·파티 편성은 창구에 두지 않는다. 상대를 찾는 일은 소켓이고, 수락은
/// 6마리 후보를 고르는 화면으로 이어진다. 반면 로컬 체육관 레이드는 `party`의 번호 네 개만으로
/// 편성이 끝나므로 그 좁은 설정 함수만 따로 노출한다.
@MainActor
protocol TerminalBattleControl: AnyObject {
    /// 지금 대전 한 장. 화면 채널의 생산자와 실행기가 **같은 값**을 본다 — 두 곳이 각자
    /// `BattleCenter` 를 읽으면 안내와 실행이 서로 다른 순간의 판을 보게 된다.
    var terminalState: BattleTerminalState { get }
    /// 기술 인덱스(0부터). 번호 → 인덱스 변환은 부르는 쪽(실행기)이 한다.
    func chooseMove(_ index: Int)
    func switchLAN(to index: Int)
    /// 로컬 체육관전은 LAN `battle` 이 아니라 `teamPractice` 에 산다. 두 함수를 갈라 두지 않으면
    /// 화면은 체육관 기술을 안내하고 실행기는 비어 있는 LAN 판에 기술을 내는 조용한 무동작이 된다.
    func chooseTeamPracticeMove(_ index: Int)
    func switchTeamPractice(to index: Int)
    func terastallizeTeamPractice()
    func dismissResult()
    /// `gym` 목록이 찍는 순번(1부터)으로 로컬 체육관전을 연다.
    @discardableResult func startGymChallenge(number: Int) -> Bool
    func setGymChallengeTeam(_ ids: [UUID])
    func forfeit()
    func declineIncoming()
}

extension BattleCenter: TerminalBattleControl {
    /// 남은 초를 **여기서 접는다.** 마감 시각을 터미널로 넘기면 두 프로세스가 각자 시계를 세고,
    /// 파일이 오래된 만큼 어긋난 값을 그린다 — 사용자는 없는 시간을 믿고 턴을 놓친다.
    var terminalState: BattleTerminalState {
        BattleTerminalState(phase: phase, battle: battle,
                            practice: activeGym == nil ? nil : teamPractice,
                            activeGym: activeGym, gymReward: lastGymReward,
                            remainingSeconds: turnEndsAt.map {
                                Int($0.timeIntervalSinceNow.rounded())
                            })
    }

    @discardableResult func startGymChallenge(number: Int) -> Bool {
        guard let gym = GymLeague.catalog.indices.contains(number - 1)
                ? GymLeague.catalog[number - 1] : nil else { return false }
        startGymChallenge(gym)
        return phase != .ready
    }

    func setGymChallengeTeam(_ ids: [UUID]) { pickedTeam = ids }
}
