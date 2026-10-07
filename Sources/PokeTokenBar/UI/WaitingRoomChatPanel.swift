import SwiftUI

/// 공동 대기 화면들이 같은 지원 판정과 채팅 세션을 사용한다.
struct WaitingRoomChatPanel: View {
    let center: MultiplayerRoomCenter
    let l: L

    var body: some View {
        BattleChatPanel(configuration: BattleChatConfiguration(
            messages: center.chatMessages, mySenderID: center.myID,
            isEnabled: center.chatIsAvailable,
            unavailableMessage: center.chatIsAvailable ? nil : l.battleChatUnavailable,
            l: l, onSend: center.sendChat))
    }
}
