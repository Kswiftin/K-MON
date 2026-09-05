import Foundation

/// 지금 교환을 터미널에 보여 주기 위해 **앱이 모아 주는 값 한 벌.**
///
/// 개체를 `MonState` 로 싣지 않고 **이미 사람이 읽는 한 줄**로 접어 넘긴다. 표시 이름은 앱이
/// 진화 라인을 지나 만든 값이고(`PokemonTradeCenter.displayName`), 터미널이 그 계산을 다시 하면
/// 네트워크 없이 자리표시자만 얻는다 — 화면 채널이 문자열을 나르는 이유 그대로다.
struct TradeTerminalState {
    var phase: PokemonTradeCenter.Phase
    /// 내가 낸 것 / 상대가 낸 것. `nil` 은 아직 안 냈다는 뜻이다.
    var localOffer: String?
    var remoteOffer: String?
    var localConfirmed = false
    var remoteConfirmed = false
    /// 상대 목록 — **이 세션에만 있는 번호**가 붙는다.
    var theirRoster: [TradeScreen.Listed] = []
    /// 상대가 지목한 내 개체의 표시 이름. 있으면 화면이 그것을 먼저 말한다.
    var theyWant: String?

    init(phase: PokemonTradeCenter.Phase) { self.phase = phase }
}

/// 교환을 터미널 한 판으로 접는다. **부수효과 없음.**
enum TradeScreen {
    enum Kind: Equatable, Sendable {
        case none
        /// 신청을 받았다 — 수락·거절 둘 다 여기서 한다(목록을 주고받는 것뿐이라 고를 화면이 없다).
        case incoming
        /// 상대를 찾거나 목록을 받는 중 — 앱이 진행한다.
        case connecting
        case negotiating
        /// 성사 중이거나 끝났다.
        case settling
    }

    /// 번호가 붙은 목록 한 줄. **번호와 id 를 함께 든다** — 두 값을 따로 구하면 목록이 다시
    /// 읽히는 사이 다른 개체를 지목한다(방 대상과 같은 규칙).
    struct Listed: Equatable, Sendable {
        var number: Int
        var id: UUID
        var label: String
    }

    static func kind(_ state: TradeTerminalState) -> Kind {
        switch state.phase {
        case .ready: .none
        case .incoming: .incoming
        case .browsing, .roster, .requesting: .connecting
        case .negotiating: .negotiating
        case .committing, .animating, .completed, .failed: .settling
        }
    }

    static func theirRoster(_ state: TradeTerminalState) -> [Listed] { state.theirRoster }

    /// 상대 목록 번호 → id. **접는 자리가 여기 하나뿐이다.**
    static func remoteID(number: Int, in state: TradeTerminalState) -> UUID? {
        state.theirRoster.first { $0.number == number }?.id
    }

    static func title(_ state: TradeTerminalState) -> String {
        switch state.phase {
        case .ready: "교환 없음"
        case .browsing(let peer), .roster(let peer), .requesting(let peer): "\(peer) 에게 신청 중"
        case .incoming(let peer): "\(peer) 의 교환 신청"
        case .negotiating(let peer): "\(peer) 와 교환 협상"
        case .committing, .animating: "교환 성사 중"
        case .completed: "교환 완료"
        case .failed: "교환 실패"
        }
    }

    /// **지금 누를 수 있는 키만.** 성사 키는 양쪽이 다 냈을 때만 오른다 — 없는 상태로 누르면
    /// 아무 일도 안 일어난다.
    static func keys(_ state: TradeTerminalState) -> [String] {
        switch kind(state) {
        case .incoming:
            return ["a 수락", "n 거절"]
        case .negotiating:
            let bothOffered = state.localOffer != nil && state.remoteOffer != nil
            return (bothOffered && !state.localConfirmed ? ["y 성사"] : []) + ["c 취소"]
        case .connecting:
            return ["c 취소"]
        case .none, .settling:
            return []
        }
    }

    static func hints(_ state: TradeTerminalState) -> String {
        switch kind(state) {
        case .none:
            return "진행 중인 교환이 없다 — 상대를 찾는 일은 앱에서 한다"
        case .incoming:
            return "a 수락   n 거절"
        case .connecting:
            return "상대의 응답을 기다린다   c 취소"
        case .negotiating:
            if state.localOffer == nil { return "낼 개체를 고른다 — trade offer <party 번호>" }
            if state.remoteOffer == nil { return "상대가 낼 때까지 기다린다   (trade want <번호>)" }
            return state.localConfirmed
                ? "상대의 확인을 기다린다"
                : "양쪽이 다 냈다 — trade confirm --yes 로 성사"
        case .settling:
            return "교환이 끝났다 — 다음 교환은 앱에서 시작한다"
        }
    }

    static func lines(_ state: TradeTerminalState, width: Int) -> [String] {
        let inner = max(1, width)
        var lines = [TUIRender.row(left: title(state), right: "", width: inner),
                     TUIRender.rule(width: inner)]
        guard kind(state) == .negotiating else {
            lines.append(TUIText.truncate(standingLine(state), to: inner))
            return lines
        }
        lines.append(TUIRender.row(left: "내 것   " + (state.localOffer ?? "아직 안 냈다"),
                                   right: state.localConfirmed ? "확인" : "",
                                   width: inner))
        lines.append(TUIRender.row(left: "상대    " + (state.remoteOffer ?? "아직 안 냈다"),
                                   right: state.remoteConfirmed ? "확인" : "",
                                   width: inner))
        // 상대가 지목한 개체를 먼저 말한다 — 그게 이 협상에서 사용자가 답할 질문이다.
        if let wanted = state.theyWant {
            lines.append(TUIText.truncate("상대가 원하는 것  \(wanted)", to: inner))
        }
        if !state.theirRoster.isEmpty {
            lines.append(TUIRender.rule(width: inner))
            lines += state.theirRoster.map {
                TUIText.truncate("\($0.number) \($0.label)", to: inner)
            }
        }
        return lines
    }

    private static func standingLine(_ state: TradeTerminalState) -> String {
        switch state.phase {
        case .ready: "진행 중인 교환이 없다. 상대를 찾는 것은 앱에서 한다."
        case .incoming(let peer): "\(peer) 가 교환을 신청했다. 수락하면 목록을 주고받는다."
        case .completed: "교환이 끝났다."
        case .failed(let reason): "교환이 실패했다 — \(reason)"
        default: "앱에서 이어 한다 — \(title(state))."
        }
    }
}
