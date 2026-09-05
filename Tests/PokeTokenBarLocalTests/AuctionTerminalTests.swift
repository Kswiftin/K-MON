import Foundation
import Testing
@testable import PokeTokenBar

/// 경매를 터미널에서 보고 제안을 주고받는 자리.
///
/// 이 기능의 고유한 위험은 **번호 공간이 넷**이라는 것이다 — 내 개체(`party`), 근처 게시물,
/// 받은 제안, 내가 건 제안. 교환은 둘이었고 그때도 한 낱말로 받으면 자기 것을 내주려다 남의
/// 것을 지목했다. 넷이면 접는 자리마다 **자기 목록만** 봐야 하고, 거절 문구는 어느 목록을
/// 봐야 하는지 말해야 한다.
///
/// 둘째 위험은 **경매가 상시 참**이라는 것이다. 대전·방·교환은 판이 돌 때만 있지만 경매
/// 시장은 이웃이 하나만 올려 둬도 늘 있다 — 화면 채널이 순위 하나로 고르면 그 화면이 집중
/// 타이머를 영영 가린다.
@Suite("AuctionTerminalTests")
struct AuctionTerminalTests {

    // MARK: 명령 어휘

    @Test func testEveryAuctionSubcommandParsesIntoItsRequest() throws {
        #expect(try PokedoroCommandParser.parse(["auction"]) == .auction)
        #expect(try PokedoroCommandParser.parse(["auction", "post", "3"])
                == .auctionPost(number: 3))
        #expect(try PokedoroCommandParser.parse(["auction", "unpost", "3"])
                == .auctionUnpost(number: 3))
        #expect(try PokedoroCommandParser.parse(["auction", "apply", "2", "5"])
                == .auctionApply(listing: 2, mon: 5, confirmed: false))
        #expect(try PokedoroCommandParser.parse(["auction", "bid", "2", "500"])
                == .auctionBid(listing: 2, stardust: 500, confirmed: false))
        #expect(try PokedoroCommandParser.parse(["auction", "accept", "1"])
                == .auctionAccept(number: 1, confirmed: false))
        #expect(try PokedoroCommandParser.parse(["auction", "reject", "1"])
                == .auctionReject(number: 1))
        #expect(try PokedoroCommandParser.parse(["auction", "cancel", "1"])
                == .auctionCancel(number: 1))
        #expect(try PokedoroCommandParser.parse(["auction", "clear", "1"])
                == .auctionClear(number: 1))
    }

    /// **확인이 필요한 것은 셋이다** — 제안을 걸면(개체·별의모래) 게시자가 수락하는 순간 더
    /// 물어볼 새 없이 넘어가고, 수락하면 내 게시물이 그대로 넘어간다.
    ///
    /// 나머지는 되돌릴 수 있다: 게시는 내릴 수 있고, 거절당한 상대는 다시 걸 수 있고, 내가 건
    /// 제안은 거둬들일 수 있고, 끝난 카드를 치우는 것은 화면 정리다.
    @Test func testOnlyIrreversibleAuctionActionsNeedConfirmation() throws {
        for words in [["auction", "apply", "2", "5"], ["auction", "bid", "2", "500"],
                      ["auction", "accept", "1"]] {
            #expect(try PokedoroCommandParser.parse(words).request == nil,
                    "\(words.joined(separator: " ")) 가 확인 없이 요청이 됐다")
            #expect(try PokedoroCommandParser.parse(words + ["--yes"]).request != nil,
                    "\(words.joined(separator: " ")) --yes 가 요청이 안 됐다")
        }
        for words in [["auction", "post", "3"], ["auction", "unpost", "3"],
                      ["auction", "reject", "1"], ["auction", "cancel", "1"],
                      ["auction", "clear", "1"]] {
            #expect(try PokedoroCommandParser.parse(words).request != nil,
                    "\(words.joined(separator: " ")) 가 확인을 요구했다")
        }
    }

    /// `auction` 은 앱 전용 목록에서 빠진다 — 상대를 찾는 일(Bonjour)만 앱에 남는다.
    @Test func testAuctionIsNoLongerAnAppOnlyCommand() {
        #expect(!PokedoroCommandParser.appOnlyCommands.contains("auction"))
    }

    @Test func testEveryAuctionActionSurvivesTheRoundTripThroughTheFile() throws {
        let actions: [PokedoroRequest.Action] = [
            .auctionPost(number: 3), .auctionUnpost(number: 3),
            .auctionApply(listing: 2, mon: 5), .auctionBid(listing: 2, stardust: 500),
            .auctionAccept(number: 1), .auctionReject(number: 1),
            .auctionCancel(number: 1), .auctionClear(number: 1),
        ]
        for action in actions {
            let sent = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
            let back = try JSONDecoder().decode(PokedoroRequest.self,
                                                from: try JSONEncoder().encode(sent))
            #expect(back.action == action, "\(action.name) 이 왕복에서 달라졌다")
        }
        #expect(PokedoroRequest.Action.auctionApply(listing: 2, mon: 5).name == "auction.apply")
        // 두 번호를 받는 동작은 **둘 다** 있어야 한다 — 하나만 적힌 파일을 추측으로 채우면
        // 사용자가 적지 않은 개체를 내놓는다.
        #expect(PokedoroRequest.Action(name: "auction.apply", argument: "2") == nil)
        #expect(PokedoroRequest.Action(name: "auction.apply", argument: "2 0") == nil)
        #expect(PokedoroRequest.Action(name: "auction.bid", argument: "0 500") == nil)
        #expect(PokedoroRequest.Action(name: "auction.post", argument: nil) == nil)
        #expect(PokedoroRequest.Action(name: "auction.clear", argument: "1")
                == .auctionClear(number: 1))
    }

    // MARK: 화면 투영

    /// 아무 데도 참여하지 않았고 근처에도 없으면 **화면 채널이 아무것도 내놓지 않는다** —
    /// 빈 줄을 내놓으면 우선순위 뒤의 생산자(집중 타이머)까지 덮는다.
    @Test func testAnIdleAuctionPublishesNothing() {
        let idle = AuctionTerminalState()
        #expect(AuctionScreen.isIdle(idle))
        #expect(PokedoroViewChannel.auctionSnapshot(idle, width: 60, now: Date()) == nil)

        var justAMarket = AuctionTerminalState()
        justAMarket.market = [AuctionScreen.Listed(number: 1, id: UUID(), label: "피카츄 Lv.18")]
        #expect(!AuctionScreen.isIdle(justAMarket), "근처에 올라온 것이 있으면 볼 것이 있다")
        let live = PokedoroViewChannel.auctionSnapshot(justAMarket, width: 60, now: Date())
        #expect(live?.screen == "auction")
    }

    /// **접는 자리마다 자기 목록만 본다.** 같은 1번이 목록마다 다른 것을 뜻하므로, 한 목록의
    /// 번호가 다른 목록에서 풀리면 사용자가 고른 것과 다른 일이 벌어진다.
    @Test func testEachNumberedListFoldsOnlyItsOwnList() throws {
        let state = Self.busy()
        let market = try #require(state.market.first)
        let incoming = try #require(state.incoming.first)
        let outgoing = try #require(state.outgoing.first)

        #expect(AuctionScreen.listingID(number: 1, in: state) == market.id)
        #expect(AuctionScreen.incomingID(number: 1, in: state) == incoming.id)
        #expect(AuctionScreen.outgoingID(number: 1, in: state) == outgoing.id)
        // 세 값이 서로 다르다 — 같으면 위 세 줄이 통과해도 아무것도 증명하지 못한다.
        #expect(Set([market.id, incoming.id, outgoing.id]).count == 3)

        // 목록 밖 번호는 첫 항목으로 접히지 않는다.
        #expect(AuctionScreen.listingID(number: 9, in: state) == nil)
        #expect(AuctionScreen.incomingID(number: 2, in: state) == nil)
        #expect(AuctionScreen.outgoingID(number: 2, in: state) == nil)
    }

    /// 네 목록이 **각자 이름을 달고** 나온다. 번호만 찍으면 어느 번호가 어느 명령의 것인지
    /// 알 방법이 없다.
    @Test func testTheScreenNamesEveryListItShows() {
        let lines = AuctionScreen.lines(Self.busy(), width: 74)
        for label in ["내 게시물", "받은 제안", "내가 건 제안", "근처"] {
            #expect(lines.contains { $0.contains(label) }, "\(label) 구획이 없다")
        }
        #expect(lines.contains { $0.contains("고디탱") }, "내 게시물의 개체가 안 보인다")
        #expect(lines.contains { $0.contains("옆자리") }, "누가 제안했는지가 안 보인다")
    }

    /// 국면 낱말은 **방향에 따라 다르다** — 받은 제안의 `.declined` 는 내가 거절한 것이고,
    /// 내가 건 제안의 `.declined` 는 상대가 거절한 것이다. 한 낱말로 뭉개면 방향이 뒤집힌다.
    @Test func testStatusWordsDependOnDirection() {
        #expect(AuctionScreen.statusName(.declined, mine: false)
                != AuctionScreen.statusName(.declined, mine: true))
        // 나머지 국면은 방향과 무관하게 같은 사실을 말한다.
        for status: AuctionOffer.Status in [.pending, .accepted, .completed, .failed] {
            #expect(AuctionScreen.statusName(status, mine: false)
                    == AuctionScreen.statusName(status, mine: true),
                    "\(status) 의 낱말이 방향에 따라 갈렸다")
        }
    }

    /// 안내는 **지금 가장 쓸모 있는 명령 하나**를 말한다. 아홉 개를 한 줄에 늘어놓으면 폭을
    /// 넘겨 잘리고(무엇이 잘렸는지는 알 수 없다), 답할 제안이 있는데 시장을 권하면 사용자는
    /// 자기 게시물이 답을 기다리는 걸 모른다.
    @Test func testHintsPointAtTheMostUsefulNextCommand() {
        // 답할 제안이 먼저다.
        #expect(AuctionScreen.hints(Self.busy()).contains("auction accept"))

        // 답할 것이 없으면 시장이다.
        var onlyMarket = Self.busy()
        onlyMarket.incoming = []
        #expect(AuctionScreen.hints(onlyMarket).contains("auction apply"))

        // 정원이 찼으면 거둬들이라고 말한다 — 걸라고 권해도 센터가 거절한다.
        var full = onlyMarket
        full.canOffer = false
        #expect(full.outgoing.count == 1, "거둬들일 제안이 있어야 이 안내가 성립한다")
        #expect(AuctionScreen.hints(full).contains("auction cancel"))

        // 시장이 비었고 끝난 카드만 남았으면 치우라고 말한다 — 그 카드는 자리를 먹지 않지만
        // 쌓이면 목록을 읽을 수 없다.
        var leftovers = AuctionTerminalState()
        leftovers.outgoing = [AuctionScreen.Card(number: 1, id: UUID(), label: "피카츄",
                                                 status: .declined)]
        #expect(AuctionScreen.hints(leftovers).contains("auction clear"))

        // 아무것도 없으면 내 것을 올리라고 말한다.
        #expect(AuctionScreen.hints(AuctionTerminalState()).contains("auction post"))
    }

    /// 경매에 올려 둔 개체를 **다른 경로**(교환)로 넘기면 게시물은 남고 개체는 내 것이 아니게
    /// 된다. 그 게시물은 번호로 가리킬 수 없으므로 화면이 그렇다고 말한다 — 조용히 빼면
    /// 사용자는 앱에만 있는 게시물을 영영 못 찾는다.
    @Test func testAListingWhoseMonIsGoneSaysSoInsteadOfShowingANumber() {
        var orphaned = AuctionTerminalState()
        orphaned.mine = [AuctionScreen.Posted(number: nil, label: "고디탱 Lv.20", offers: 0)]
        let lines = AuctionScreen.lines(orphaned, width: 60)
        #expect(lines.contains { $0.contains("내 개체가 아니다") },
                "번호가 `-` 인 이유를 말하지 않으면 오류로 읽힌다")
        #expect(!AuctionScreen.isIdle(orphaned), "게시물이 남아 있으면 볼 것이 있다")
    }

    /// 센터가 남긴 실패 한 줄은 **화면에 남는다** — 수락이 조용히 실패하면 사용자는 상대가
    /// 느린 것과 자기 개체가 이미 사라진 것을 구분할 수 없다.
    @Test func testTheCentresLastErrorIsShown() {
        var state = Self.busy()
        state.lastError = "게시한 포켓몬을 확인할 수 없습니다."
        #expect(AuctionScreen.lines(state, width: 74).contains { $0.contains("확인할 수 없") })
    }

    @Test func testEveryLineFitsTheRequestedWidth() {
        var withError = Self.busy()
        withError.lastError = "게시한 포켓몬을 확인할 수 없습니다."
        for state in [Self.busy(), AuctionTerminalState(), withError] {
            for width in [20, 40, 80] {
                for line in AuctionScreen.lines(state, width: width) {
                    #expect(TUIText.displayWidth(line) <= width, "폭 \(width) 에서 넘친 줄: \(line)")
                }
            }
        }
    }

    // MARK: 키 배정

    /// 경매 화면은 **누를 키가 없다.** 번호 공간이 넷이라 숫자 한 자리로는 어느 목록의 몇 번인지
    /// 정할 수 없다(교환이 둘이라 숫자를 안 받은 것과 같은 근거, 더 강하게).
    ///
    /// 그래서 안내를 **줄에 싣는다** — 키 안내만 두면 이 화면은 영영 빈 줄을 그린다.
    @Test func testTheAuctionScreenTakesNoKeysAndSaysSoInItsLines() {
        #expect(AuctionScreen.keys(Self.busy()).isEmpty)
        for key in ["1", "a", "y", "s", "l", "t"] {
            #expect(TUIKeymap.action(for: .char(Character(key)), screen: .auction, canWrite: true)
                    == .ignored, "\(key) 가 경매 화면에서 무언가를 했다")
        }
        let snapshot = PokedoroViewChannel.auctionSnapshot(Self.busy(), width: 74, now: Date())
        #expect(snapshot?.lines.last == AuctionScreen.hints(Self.busy()),
                "칠 명령이 줄에 없으면 이 화면에서 할 수 있는 일을 알 방법이 없다")
    }

    // MARK: 채널 — 터미널이 보는 화면을 고른다

    /// **터미널이 보고 있는 화면이 우선순위를 이긴다.**
    ///
    /// 순위 하나로 고정하면 동시에 참인 두 화면 중 뒤에 있는 것을 영영 못 본다. 경매가 그
    /// 부류를 처음 드러냈다 — 시장은 이웃이 하나만 올려 둬도 늘 참이라, 앞에 두면 집중 타이머를
    /// 통째로 가리고 뒤에 두면 `pokedoro auction` 이 시장을 볼 방법이 없다.
    @Test func testTheTerminalCanAskForTheScreenItIsShowing() throws {
        let now = Date()
        let focus = try #require(PokedoroViewChannel.focusSnapshot(phase: .focus,
                                                                    clockText: "24:59",
                                                                    completed: 1, goal: 4,
                                                                    isLongRest: false, now: now))
        let auction = try #require(PokedoroViewChannel.auctionSnapshot(Self.busy(),
                                                                        width: 60, now: now))
        // 아무 요청이 없으면 순위대로 — 경매는 타이머 뒤다.
        #expect(PokedoroViewChannel.preferred([focus, auction])?.screen == "focus")
        // 터미널이 경매를 보고 있다고 하면 경매다.
        #expect(PokedoroViewChannel.preferred([focus, auction], wanted: "auction")?.screen
                == "auction")
        // 요청한 화면이 지금 없으면 순위로 되돌아간다 — 빈 화면을 내놓으면 앱이 죽은 것과
        // 구분되지 않는다.
        #expect(PokedoroViewChannel.preferred([focus], wanted: "auction")?.screen == "focus")
        #expect(PokedoroViewChannel.preferred([nil], wanted: "auction") == nil)
    }

    /// 신호에 화면 이름이 실린다. **옛 파일에는 없는 칸**이라 없어도 디코딩이 된다 —
    /// 안 그러면 새 앱이 옛 터미널의 신호를 통째로 못 읽어 화면이 죽는다.
    @Test func testTheAttachmentCarriesTheScreenAndOldFilesStillDecode() throws {
        let signal = PokedoroAttachment(id: UUID(), width: 80, height: 24, at: Date(),
                                        screen: "auction")
        let back = try JSONDecoder().decode(PokedoroAttachment.self,
                                            from: try JSONEncoder().encode(signal))
        #expect(back.screen == "auction")

        let old = Data("""
        {"id":"\(UUID().uuidString)","width":80,"height":24,"at":0}
        """.utf8)
        let decoded = try JSONDecoder().decode(PokedoroAttachment.self, from: old)
        #expect(decoded.screen == nil)
    }

    // MARK: 픽스처

    /// 네 목록이 **전부 비어 있지 않은** 한 벌. 하나라도 비면 그 목록의 구획·접기가 테스트를
    /// 지나가 버린다.
    static func busy() -> AuctionTerminalState {
        var state = AuctionTerminalState()
        state.market = [AuctionScreen.Listed(number: 1, id: UUID(), label: "피카츄 Lv.18  옆자리"),
                        AuctionScreen.Listed(number: 2, id: UUID(), label: "꼬부기 Lv.9  앞자리")]
        state.mine = [AuctionScreen.Posted(number: 3, label: "고디탱 Lv.20", offers: 1)]
        state.incoming = [AuctionScreen.Card(number: 1, id: UUID(),
                                             label: "옆자리  이상해씨 Lv.14", status: .pending)]
        state.outgoing = [AuctionScreen.Card(number: 1, id: UUID(),
                                             label: "피카츄 Lv.18 ← 별의모래 500", status: .pending)]
        state.unpledged = 1_200
        return state
    }
}
