import Foundation

/// 터미널이 경매에 닿는 **좁은 창구.** 근거는 대전·방·교환 창구와 같다 — 센터를 그대로 넘기면
/// 실행기 테스트가 listener·browser 를 살려 실제 LAN 으로 나간다.
///
/// **시장을 훑는 일은 없다**(`start`·`updateListings`). 그건 Bonjour 가 계속 돌며 채우는 값이라
/// 부탁할 대상이 아니고, 터미널은 그 결과를 `terminalState` 로 받는다.
///
/// 개체를 가리키는 인자는 **`party` 번호**이고, 게시물·제안을 가리키는 인자는 **id** 다.
/// 번호 → 개체는 로스터를 아는 이 창구가 접고(못 하면 사유를 돌려준다), 번호 → 게시물·제안은
/// 목록을 아는 실행기가 `AuctionScreen` 의 접는 함수로 한다.
@MainActor
protocol TerminalAuctionControl: AnyObject {
    var terminalState: AuctionTerminalState { get }
    /// 내 개체를 경매에 올린다. 올릴 수 없으면 사유를 돌려준다(`nil` 이 성공이다) — 후보에서
    /// 빠지는 이유가 다섯이라(없는 번호·즐겨찾기·체육관 방어·동행·이미 걸림) 갈라 말해야 한다.
    func post(number: Int) -> String?
    /// 내 게시물을 내린다. 그 개체가 올라 있지 않으면 사유를 돌려준다.
    func unpost(number: Int) -> String?
    /// 남의 게시물에 **개체를** 건다.
    func apply(listingID: UUID, number: Int) -> String?
    /// 남의 게시물에 **별의모래를** 건다.
    func bid(listingID: UUID, stardust: Int) -> String?
    func accept(offerID: UUID)
    func reject(offerID: UUID)
    /// 답을 못 받은 내 제안을 거둬들인다.
    func cancelOffer(offerID: UUID)
    /// 끝난 제안 카드를 치운다.
    func clearResult(offerID: UUID)
}
