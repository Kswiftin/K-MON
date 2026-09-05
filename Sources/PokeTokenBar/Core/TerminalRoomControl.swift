import Foundation

/// 터미널이 LAN 방에 닿는 **좁은 창구.** 근거는 `TerminalBattleControl` 과 같다 — 센터를 그대로
/// 넘기면 실행기 테스트가 listener·browser 를 살려 실제 LAN 으로 나간다.
///
/// **방을 만들거나 찾는 일은 없다.** 그건 소켓과 목록 훑기라 터미널이 할 수 있는 모양이 아니고,
/// 할 수 없는 일은 창구에 아예 없어야 한다(수락·파티 편성을 대전 창구에 안 둔 것과 같다).
@MainActor
protocol TerminalRoomControl: AnyObject {
    var terminalState: RoomTerminalState { get }
    /// 대상은 **id 로** 받는다. 번호 → id 변환은 목록을 아는 실행기가 `RoomScreen.targetID` 로 한다.
    func submitAction(targetID: UUID, moveIndex: Int)
    func startRaid()
    func leaveRoom()
}

extension MultiplayerRoomCenter: TerminalRoomControl {
    var terminalState: RoomTerminalState {
        var state = RoomTerminalState(phase: phase, activity: roomActivity, myID: myID)
        state.round = combatRound
        state.fighters = combatFighters
        state.hasSubmitted = hasSubmittedAction
        state.isHost = isHost
        state.canStart = lobby?.canStart ?? false
        state.raidTier = raidTier
        // 승패·정산은 **센터가 이미 판정한 값**을 싣는다. 터미널이 전투원 목록으로 다시 세면
        // 팀전·관전자·무승부에서 갈라진다(그 네 갈래를 `myOutcome` 하나가 든다).
        state.outcome = isBattleFinished ? myOutcome : nil
        state.payout = raidPayout ?? settlementPayout
        return state
    }
}
