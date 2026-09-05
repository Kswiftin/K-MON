import Foundation

/// 터미널이 교환에 닿는 **좁은 창구.** 근거는 대전·방 창구와 같다 — 센터를 그대로 넘기면 실행기
/// 테스트가 listener 를 살려 실제 LAN 으로 나간다.
///
/// **상대를 찾는 일은 없다**(`browse`·`request`). 그건 소켓이고, 할 수 없는 일은 창구에 아예
/// 두지 않는다.
@MainActor
protocol TerminalTradeControl: AnyObject {
    var terminalState: TradeTerminalState { get }
    /// 내가 낼 개체 — **`party` 가 찍는 번호로** 받는다. 낼 수 없으면 사유를 돌려준다
    /// (`nil` 이 성공이다): 후보에서 빠지는 이유가 둘이라(체육관 방어·즐겨찾기) 갈라 말해야 한다.
    func offerMon(number: Int) -> String?
    /// 상대 목록에서 원하는 개체를 지목한다.
    func wantRemote(id: UUID)
    func accept()
    func decline()
    func confirm()
    func cancel()
}
