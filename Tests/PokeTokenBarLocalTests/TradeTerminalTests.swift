import Foundation
import Testing
@testable import PokeTokenBar

/// 교환을 터미널에서 보고 성사시키는 자리.
///
/// 대전·방과 같은 통로다(세이브에 없는 진행 → 화면 채널). 이 기능의 고유한 위험은 **번호가 두
/// 종류**라는 것이다: 내 개체는 `party` 가 찍는 번호를 그대로 쓰고, 상대 목록은 그 교환 세션에만
/// 있는 목록이라 따로 번호를 매긴다. 두 번호를 한 낱말로 받으면 사용자는 자기 것을 내주려다
/// 남의 것을 지목한다.
@Suite("TradeTerminalTests")
struct TradeTerminalTests {

    // MARK: 명령 어휘

    @Test func testEveryTradeSubcommandParsesIntoItsRequest() throws {
        #expect(try PokedoroCommandParser.parse(["trade"]) == .trade)
        #expect(try PokedoroCommandParser.parse(["trade", "accept"]) == .tradeAccept)
        #expect(try PokedoroCommandParser.parse(["trade", "decline"]) == .tradeDecline)
        #expect(try PokedoroCommandParser.parse(["trade", "offer", "3"]) == .tradeOffer(number: 3))
        #expect(try PokedoroCommandParser.parse(["trade", "want", "2"]) == .tradeWant(number: 2))
        #expect(try PokedoroCommandParser.parse(["trade", "confirm"]) == .tradeConfirm(confirmed: false))
        #expect(try PokedoroCommandParser.parse(["trade", "cancel"]) == .tradeCancel(confirmed: false))
    }

    /// **확인이 필요한 것은 성사와 취소 둘이다.** 성사는 개체가 영영 넘어가고, 취소는 협상을
    /// 통째로 버린다. 거절(`decline`)은 아직 아무것도 안 정해진 상태라 확인을 받지 않는다.
    @Test func testCommittingAndCancellingNeedConfirmation() throws {
        #expect(try PokedoroCommandParser.parse(["trade", "confirm"]).request == nil)
        #expect(try PokedoroCommandParser.parse(["trade", "confirm", "--yes"]).request == .tradeConfirm)
        #expect(try PokedoroCommandParser.parse(["trade", "cancel"]).request == nil)
        #expect(try PokedoroCommandParser.parse(["trade", "cancel", "--yes"]).request == .tradeCancel)
        #expect(try PokedoroCommandParser.parse(["trade", "decline"]).request == .tradeDecline)
    }

    /// `trade` 는 앱 전용 목록에서 빠진다 — 상대를 찾는 일만 앱에 남는다.
    @Test func testTradeIsNoLongerAnAppOnlyCommand() {
        #expect(!PokedoroCommandParser.appOnlyCommands.contains("trade"))
    }

    @Test func testEveryTradeActionSurvivesTheRoundTripThroughTheFile() throws {
        let actions: [PokedoroRequest.Action] = [
            .tradeAccept, .tradeDecline, .tradeOffer(number: 3), .tradeWant(number: 2),
            .tradeConfirm, .tradeCancel
        ]
        for action in actions {
            let sent = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
            let back = try JSONDecoder().decode(PokedoroRequest.self,
                                                from: try JSONEncoder().encode(sent))
            #expect(back.action == action, "\(action.name) 이 왕복에서 달라졌다")
        }
        #expect(PokedoroRequest.Action.tradeOffer(number: 1).name == "trade.offer")
        #expect(PokedoroRequest.Action(name: "trade.offer", argument: "0") == nil)
        #expect(PokedoroRequest.Action(name: "trade.accept", argument: "1") == nil)
    }

    // MARK: 화면 투영

    @Test func testNoTradeSaysWhereToStartOne() {
        let idle = TradeTerminalState(phase: .ready)
        #expect(TradeScreen.kind(idle) == .none)
        #expect(TradeScreen.lines(idle, width: 60).contains { $0.contains("앱") })
    }

    /// 신청을 받으면 **수락과 거절 둘 다** 터미널에서 할 수 있다 — 대전과 다른 점이다.
    /// 교환의 수락은 목록을 주고받는 것뿐이라 고를 화면이 필요 없다.
    @Test func testAnIncomingTradeOffersBothAnswers() {
        let state = TradeTerminalState(phase: .incoming(peer: "옆자리"))
        #expect(TradeScreen.kind(state) == .incoming)
        #expect(TradeScreen.keys(state).contains { $0.contains("수락") })
        #expect(TradeScreen.keys(state).contains { $0.contains("거절") })
        #expect(TradeScreen.lines(state, width: 60).contains { $0.contains("옆자리") })
    }

    /// 협상 중에는 **양쪽이 무엇을 냈는지와 확인 상태**가 보인다. 확인은 두 쪽이 다 눌러야
    /// 성사되므로, 상대 확인 여부가 안 보이면 사용자는 자기 차례인지 알 수 없다.
    @Test func testNegotiatingShowsBothOffersAndConfirmations() {
        var state = Self.negotiating()
        state.remoteConfirmed = true
        let lines = TradeScreen.lines(state, width: 70)
        #expect(lines.contains { $0.contains("내 것") && $0.contains("고디탱") })
        #expect(lines.contains { $0.contains("상대") && $0.contains("피카츄") })
        #expect(lines.contains { $0.contains("확인") })
    }

    /// 아직 아무것도 안 냈으면 **성사 키를 권하지 않는다** — `confirm` 은 양쪽 제안이 있어야
    /// 의미가 있고, 없는 상태로 누르면 아무 일이 없다.
    @Test func testConfirmIsOfferedOnlyOnceBothSidesHaveOffered() {
        var empty = Self.negotiating()
        empty.localOffer = nil
        #expect(!TradeScreen.keys(empty).contains { $0.contains("성사") })
        #expect(TradeScreen.keys(Self.negotiating()).contains { $0.contains("성사") })
    }

    /// 상대 목록은 **그 세션에만 있는 번호**로 찍고, 번호 → id 변환은 한 곳을 지난다.
    @Test func testTheirRosterIsNumberedAndFoldsToAnID() throws {
        let state = Self.negotiating()
        let listed = TradeScreen.theirRoster(state)
        #expect(listed.count == 1)
        #expect(listed.first?.number == 1)
        #expect(TradeScreen.remoteID(number: 1, in: state) == listed.first?.id)
        #expect(TradeScreen.remoteID(number: 4, in: state) == nil)
    }

    @Test func testEveryLineFitsTheRequestedWidth() {
        for state in [Self.negotiating(), TradeTerminalState(phase: .ready),
                      TradeTerminalState(phase: .completed)] {
            for width in [20, 40, 80] {
                for line in TradeScreen.lines(state, width: width) {
                    #expect(TUIText.displayWidth(line) <= width, "폭 \(width) 에서 넘친 줄: \(line)")
                }
            }
        }
    }

    @Test func testTheChannelOnlyPublishesALiveTrade() throws {
        let now = Date()
        #expect(PokedoroViewChannel.tradeSnapshot(TradeTerminalState(phase: .ready),
                                                   width: 60, now: now) == nil)
        let live = try #require(PokedoroViewChannel.tradeSnapshot(Self.negotiating(),
                                                                    width: 60, now: now))
        #expect(live.screen == "trade")
    }

    /// 국면마다 **키와 한 줄 안내가 함께** 바뀐다.
    @Test func testEveryPhaseAdvertisesOnlyWhatItCanDo() {
        // 상대를 찾는 중 — 취소만 된다.
        let connecting = TradeTerminalState(phase: .browsing(peer: "옆자리"))
        #expect(TradeScreen.kind(connecting) == .connecting)
        #expect(TradeScreen.keys(connecting) == ["c 취소"])
        #expect(TradeScreen.hints(connecting).contains("기다린다"))
        #expect(TradeScreen.lines(connecting, width: 60).contains { $0.contains("앱") })

        // 성사 중·끝난 뒤에는 누를 것이 없다.
        for phase: PokemonTradeCenter.Phase in [.committing, .animating, .completed,
                                                .failed("연결이 끊겼다")] {
            let state = TradeTerminalState(phase: phase)
            #expect(TradeScreen.kind(state) == .settling, "\(phase) 가 정산으로 안 잡혔다")
            #expect(TradeScreen.keys(state).isEmpty)
        }
        #expect(TradeScreen.lines(TradeTerminalState(phase: .failed("연결이 끊겼다")), width: 60)
            .contains { $0.contains("연결이 끊겼다") }, "실패 사유가 안 보이면 왜 끝났는지 모른다")
        #expect(TradeScreen.hints(TradeTerminalState(phase: .completed)).contains("끝났다"))
    }

    /// 협상의 세 단계가 **서로 다른 다음 할 일**을 말한다 — 안 내면 고르라고, 상대를 기다릴 땐
    /// 기다리라고, 다 냈으면 성사시키라고.
    @Test func testNegotiatingHintsWalkThroughTheSteps() {
        var state = Self.negotiating()
        state.localOffer = nil
        #expect(TradeScreen.hints(state).contains("trade offer"))

        state = Self.negotiating()
        state.remoteOffer = nil
        #expect(TradeScreen.hints(state).contains("기다린다"))

        #expect(TradeScreen.hints(Self.negotiating()).contains("trade confirm"))

        var confirmed = Self.negotiating()
        confirmed.localConfirmed = true
        #expect(TradeScreen.hints(confirmed).contains("상대"))
        #expect(!TradeScreen.keys(confirmed).contains { $0.contains("성사") },
                "이미 확인했는데 성사 키를 또 권하면 눌러도 아무 일이 없다")
    }

    /// 상대가 지목한 개체를 **먼저 말한다** — 그게 이 협상에서 사용자가 답할 질문이다.
    @Test func testWhatTheyWantIsShown() {
        var state = Self.negotiating()
        state.theyWant = "고디탱 Lv.20"
        #expect(TradeScreen.lines(state, width: 70).contains { $0.contains("원하는") })
    }

    // MARK: 키 배정

    /// **화면 이동 키는 어떤 화면의 안쪽 키와도 겹칠 수 없다.** 이동 키가 먼저 잡히므로 겹치면
    /// 그 화면의 동작이 조용히 죽는다 — 교환 화면에 `t` 를 줬더니 웨이브의 볼 던지기가 사라졌다.
    @Test func testNoScreenKeyShadowsAnInScreenKey() {
        let screenKeys = Set(TUIScreen.allCases.map(\.key))
        for screen in TUIScreen.allCases {
            for key in screenKeys where TUIScreen.screen(for: key) != screen {
                // 이동 키를 눌렀으면 **이동만** 해야 한다. 그 화면의 동작으로 해석되면 둘 중
                // 하나는 영영 못 쓰는 키다.
                #expect(TUIKeymap.action(for: .char(key), screen: screen, canWrite: true)
                        == .show(TUIScreen.screen(for: key) ?? .home),
                        "\(screen) 화면에서 \(key) 가 이동이 아니다")
            }
        }
    }

    /// 교환 화면은 **숫자 키를 받지 않는다** — 낼 개체와 원하는 개체가 서로 다른 목록의 번호라
    /// 한 숫자로 받을 수 없다.
    @Test func testTheTradeScreenTakesNoNumbers() {
        #expect(TUIKeymap.action(for: .char("1"), screen: .trade, canWrite: true) == .ignored)
        #expect(TUIKeymap.action(for: .char("a"), screen: .trade, canWrite: true) == .acceptTrade)
        #expect(TUIKeymap.action(for: .char("y"), screen: .trade, canWrite: true) == .confirmTrade)
    }

    // MARK: 픽스처

    static func negotiating() -> TradeTerminalState {
        var state = TradeTerminalState(phase: .negotiating(peer: "옆자리"))
        state.localOffer = "고디탱 Lv.20"
        state.remoteOffer = "피카츄 Lv.18"
        state.theirRoster = [TradeScreen.Listed(number: 1, id: UUID(), label: "피카츄 Lv.18")]
        return state
    }
}
