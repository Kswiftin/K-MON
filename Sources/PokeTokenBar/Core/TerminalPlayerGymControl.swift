import Foundation

/// 체육관 쟁탈전의 라이브 상태. 도전 탭의 `GymLeague`와 이름이 겹치므로 별도 값으로 둔다.
struct PlayerGymTerminalState {
    var isLeader: Bool
    var phase: MultiplayerRoomCenter.Phase
    var visibleLeader: String?
    var canChallengeVisibleGym: Bool
    var discoveryUnavailable: Bool
    var hasScannedOnce: Bool
    var needsAppUpdate: Bool
    var defenseTeam: [UUID]
    var usesAI: Bool
    var consecutiveDefenses: Int
    var earnedToday: Int
    var defenseLog: [GymDefenseRecord]
    var setupSecondsRemaining: Int?
    var takeoverAvailable: Bool
}

/// 터미널이 체육관 쟁탈전의 수명주기를 앱과 같은 경로로 조작하는 좁은 창구.
@MainActor
protocol TerminalPlayerGymControl: AnyObject {
    var terminalState: PlayerGymTerminalState { get }
    func refreshForTerminal()
    func openFromTerminal(defenseTeam: [UUID]) -> Bool
    func challengeFromTerminal(team: [UUID]) -> Bool
    func spectateFromTerminal() -> Bool
    func setDefenseTeamFromTerminal(_ team: [UUID]) -> Bool
    func setAIFromTerminal(_ enabled: Bool) -> Bool
    func resignFromTerminal()
    func takeOverFromTerminal() -> Bool
}
