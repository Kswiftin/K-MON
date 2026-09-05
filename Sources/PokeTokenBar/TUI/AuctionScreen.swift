import Foundation

/// 지금 경매를 터미널에 보여 주기 위해 **앱이 모아 주는 값 한 벌.**
///
/// `PokemonAuctionCenter` 를 그대로 넘기지 않는 근거는 형제 셋과 같다 — 그 타입은 listener·
/// browser·연결 장부를 들고 있어 순수 함수의 입력이 될 수 없다.
///
/// **목록이 넷이고 번호도 넷이다.** 접는 자리를 목록마다 하나로 두는 것이 이 파일의 존재
/// 이유다: 같은 1번이 목록마다 다른 것을 뜻하므로, 한 번호가 다른 목록에서 풀리면 사용자가
/// 고른 것과 다른 게시물·다른 제안에 손이 간다.
struct AuctionTerminalState {
    /// 근처 게시물 — **이 세션에만 있는 번호**가 붙는다.
    var market: [AuctionScreen.Listed] = []
    /// 내 게시물. 번호는 **`party` 가 찍는 번호**다 — 게시한 개체는 팔리기 전까지 내 것이라
    /// 로스터에 그대로 있고, 목록을 새로 매기면 같은 개체가 화면마다 다른 번호를 갖는다.
    var mine: [AuctionScreen.Posted] = []
    /// 내 게시물에 들어온 제안 — 이 세션 번호. **게시물별로 나누지 않는다**: 나누면 "3번
    /// 게시물의 1번 제안" 처럼 번호가 두 겹이 되고, 터미널에는 그 둘을 받을 입력 줄이 없다.
    var incoming: [AuctionScreen.Card] = []
    /// 내가 건 제안 — 이 세션 번호.
    var outgoing: [AuctionScreen.Card] = []
    /// 아직 어느 제안에도 약속하지 않은 별의모래. **화면·실행기·센터가 같은 값을 본다**
    /// (`PokemonAuctionCenter.unpledgedTokens`) — 두 벌로 두면 한쪽만 넓어져 안내는 걸라고
    /// 하는데 센터가 조용히 거절한다.
    var unpledged = 0
    /// 제안을 하나 더 걸 수 있나(`canRegisterOffer`).
    var canOffer = true
    /// 센터가 남긴 마지막 실패 한 줄. 수락이 실패하는 자리가 여기뿐이라 화면이 그대로 옮긴다.
    var lastError: String?
}

/// 경매를 터미널 한 판으로 접는다. **부수효과 없음.**
enum AuctionScreen {
    /// 근처 게시물 한 줄. **번호와 id 를 함께 든다** — 화면은 번호를 찍고 실행기는 id 로
    /// 보내는데, 두 값을 따로 구하면 목록이 다시 읽히는 사이 다른 게시물에 제안을 건다.
    struct Listed: Equatable, Sendable {
        var number: Int
        var id: UUID
        var label: String
    }

    /// 내 게시물 한 줄. **id 가 없다** — 이 줄을 가리키는 명령(`auction unpost`)은 `party`
    /// 번호를 받고, 그 번호 → 게시물 변환은 로스터를 아는 창구가 한다.
    ///
    /// `number` 가 `nil` 인 경우가 있다: 경매에 올려 둔 개체를 **다른 경로**(교환)로 넘기면
    /// 게시물은 남고 개체는 내 것이 아니게 된다. 그 게시물은 번호로 가리킬 수 없으므로 화면이
    /// 그렇다고 말한다 — 조용히 빼면 사용자는 앱에만 있는 게시물을 영영 못 찾는다.
    struct Posted: Equatable, Sendable {
        var number: Int?
        var label: String
        var offers: Int
    }

    /// 제안 한 장. 받은 것과 내가 건 것이 **같은 모양**이다(번호·id·한 줄·국면) — 다른 것은
    /// 어느 목록에서 왔는지와 국면 낱말의 방향뿐이다.
    struct Card: Equatable, Sendable {
        var number: Int
        var id: UUID
        var label: String
        var status: AuctionOffer.Status
    }

    // MARK: 국면

    /// 볼 것이 있나. **`Kind` 를 두지 않는 이유**는 경매에 국면이 없기 때문이다 — 대전·방·교환은
    /// 한 판이 국면을 지나지만, 경매는 네 목록이 각자 차고 빈다.
    static func isIdle(_ state: AuctionTerminalState) -> Bool {
        state.market.isEmpty && state.mine.isEmpty
            && state.incoming.isEmpty && state.outgoing.isEmpty
    }

    /// 시장 번호 → 게시물 id. **이 목록을 접는 자리가 여기 하나뿐이다.**
    static func listingID(number: Int, in state: AuctionTerminalState) -> UUID? {
        state.market.first { $0.number == number }?.id
    }

    /// 받은 제안 번호 → 제안 id.
    static func incomingID(number: Int, in state: AuctionTerminalState) -> UUID? {
        incoming(number: number, in: state)?.id
    }

    /// 내가 건 제안 번호 → 제안 id.
    static func outgoingID(number: Int, in state: AuctionTerminalState) -> UUID? {
        outgoing(number: number, in: state)?.id
    }

    /// 받은 제안 한 장. 국면을 봐야 하는 실행기가 카드째 읽는다 — id 만 돌려주면 "이미 답한
    /// 제안" 을 가르려고 목록을 한 번 더 뒤져야 하고, 두 번 뒤지는 사이 목록이 바뀔 수 있다.
    static func incoming(number: Int, in state: AuctionTerminalState) -> Card? {
        state.incoming.first { $0.number == number }
    }

    static func outgoing(number: Int, in state: AuctionTerminalState) -> Card? {
        state.outgoing.first { $0.number == number }
    }

    /// 제안 국면 → 한 낱말. **표는 여기 하나다.**
    ///
    /// 방향에 따라 `.declined` 의 낱말이 다르다 — 받은 제안을 거절한 것은 나이고, 내가 건
    /// 제안이 거절된 것은 상대가 한 일이다. 한 낱말로 뭉개면 방향이 뒤집혀 읽힌다.
    static func statusName(_ status: AuctionOffer.Status, mine: Bool) -> String {
        switch status {
        case .pending:   "응답 대기"
        case .accepted:  "교환 처리 중"
        case .declined:  mine ? "거절됨" : "거절함"
        case .completed: "교환 완료"
        case .failed:    "교환 실패"
        }
    }

    // MARK: 안내

    static func title(_ state: AuctionTerminalState) -> String {
        isIdle(state) ? "경매 없음" : "경매 시장"
    }

    /// **누를 키가 없다.** 번호 공간이 넷이라 숫자 한 자리로는 어느 목록의 몇 번인지 정할 수
    /// 없다 — 교환이 둘이라 숫자를 안 받은 것과 같은 근거이고, 여기서는 더 강하다.
    ///
    /// 그래도 안내가 없어지지는 않는다: 칠 명령은 `hints` 가 **줄에** 실린다.
    static func keys(_ state: AuctionTerminalState) -> [String] { [] }

    /// 지금 가장 쓸모 있는 명령 **하나**. 아홉 개를 한 줄에 늘어놓으면 폭을 넘겨 잘리고,
    /// 무엇이 잘렸는지는 화면에 남지 않는다(키 안내가 `q 종료` 를 먹은 것과 같은 부류).
    static func hints(_ state: AuctionTerminalState) -> String {
        let waiting = state.incoming.filter { $0.status == .pending }.count
        if waiting > 0 {
            return "받은 제안 \(waiting)건 — auction accept <n> --yes / auction reject <n>"
        }
        // 정원이 찼으면 **거둬들이라고** 말한다. 걸라고 권해도 센터가 조용히 거절한다.
        if !state.canOffer, state.outgoing.contains(where: { $0.status == .pending }) {
            return "제안 정원(\(PokemonAuctionCenter.maxOutgoingOffers))이 찼다 — "
                + "auction cancel <n> 로 하나를 거둬들인다"
        }
        if !state.market.isEmpty, state.canOffer {
            return "auction apply <시장> <party> --yes   auction bid <시장> <금액> --yes"
        }
        if state.outgoing.contains(where: { !$0.status.isLive }) {
            return "끝난 제안이 있다 — auction clear <n> 로 치운다"
        }
        return "근처에 올라온 것이 없다 — auction post <party 번호> 로 내 것을 올린다"
    }

    // MARK: 줄

    static func lines(_ state: AuctionTerminalState, width: Int) -> [String] {
        let inner = max(1, width)
        var lines = [TUIRender.row(left: title(state),
                                   right: "미약속 ★ \(TUIRender.number(state.unpledged))",
                                   width: inner),
                     TUIRender.rule(width: inner)]
        // 센터가 남긴 실패를 **먼저** 말한다 — 수락이 조용히 실패하면 사용자는 상대가 느린 것과
        // 자기 개체가 이미 사라진 것을 구분할 수 없다.
        if let error = state.lastError {
            lines.append(TUIText.truncate(error, to: inner))
        }
        lines += mineLines(state, width: inner)
        lines += cardLines(state.incoming, head: "받은 제안 \(state.incoming.count)건",
                           mine: false, width: inner)
        lines += cardLines(state.outgoing, head: outgoingHead(state), mine: true, width: inner)
        if !state.market.isEmpty {
            lines.append(TUIText.truncate("근처 게시물 \(state.market.count)건", to: inner))
            lines += state.market.map {
                TUIText.truncate(" \($0.number) \($0.label)", to: inner)
            }
        }
        // 안내는 **마지막 줄**이다. 이 화면에는 누를 키가 없어, 키 안내 자리에 아무것도 없다.
        lines.append(TUIText.truncate(hints(state), to: inner))
        return lines
    }

    private static func mineLines(_ state: AuctionTerminalState, width: Int) -> [String] {
        guard !state.mine.isEmpty else { return [] }
        var lines = [TUIText.truncate("내 게시물 \(state.mine.count)건", to: width)]
        lines += state.mine.map { posted in
            TUIRender.row(left: " \(posted.number.map(String.init) ?? "-") \(posted.label)",
                          right: "제안 \(posted.offers)", width: width)
        }
        // 번호로 가리킬 수 없는 게시물이 있으면 그렇다고 말한다 — `-` 만 찍으면 사용자는 그것이
        // 오류인지 자기가 못 읽는 것인지 모른다.
        if state.mine.contains(where: { $0.number == nil }) {
            lines.append(TUIText.truncate("- 는 이제 내 개체가 아니다 — 앱에서 내린다", to: width))
        }
        return lines
    }

    private static func cardLines(_ cards: [Card], head: String, mine: Bool,
                                  width: Int) -> [String] {
        guard !cards.isEmpty else { return [] }
        return [TUIText.truncate(head, to: width)] + cards.map { card in
            TUIRender.row(left: " \(card.number) \(card.label)",
                          right: statusName(card.status, mine: mine), width: width)
        }
    }

    /// 정원은 **내가 건 제안** 머리글에 붙는다 — 그 값이 막는 것이 이 목록의 길이다.
    /// 세는 것은 살아 있는 제안뿐이다(끝난 카드는 자리를 먹지 않는다).
    private static func outgoingHead(_ state: AuctionTerminalState) -> String {
        let live = state.outgoing.filter { $0.status.isLive }.count
        return "내가 건 제안 \(live)/\(PokemonAuctionCenter.maxOutgoingOffers)"
    }
}
