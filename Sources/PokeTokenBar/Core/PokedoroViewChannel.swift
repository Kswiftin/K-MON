import Foundation

/// 터미널이 "지금 보고 있다" 고 남기는 신호. **터미널만 쓴다**(`pokedoro-attach.json`).
///
/// 앱이 이 신호를 보는 이유는 둘이다. ⓐ 아무도 안 보는데 스냅샷을 쓰면 디스크만 갈린다.
/// ⓑ 터미널에서 대전을 보고 있는 사용자에게 앱 창이 튀어나오면 화면이 통째로 가려진다.
struct PokedoroAttachment: Codable, Equatable, Sendable {
    var id: UUID
    /// **터미널의 칸 수.** 줄을 만드는 쪽이 앱이므로 폭을 앱이 알아야 한다 — 모르면 80칸을
    /// 가정하게 되고, 좁은 창에서는 매 줄이 접혀 화면이 흘러간다.
    var width: Int
    var height: Int
    /// 마지막 인사 시각. 터미널은 살아 있는 동안 주기적으로 갱신한다.
    var at: Date
    /// **터미널이 지금 보고 있는 화면.** 앱은 이 이름의 생산자를 우선으로 내놓는다.
    ///
    /// 순위 하나로 고정하던 때의 한계가 경매에서 드러났다: 대전·방·교환은 판이 돌 때만 참이라
    /// 순위로 충분했지만, 경매 시장은 이웃이 하나만 올려 둬도 늘 참이다 — 앞에 두면 집중
    /// 타이머를 통째로 가리고, 뒤에 두면 `pokedoro auction` 이 시장을 볼 방법이 없다.
    ///
    /// **옛 파일에는 없는 칸**이라 없어도 디코딩된다. 안 그러면 새 앱이 옛 터미널의 신호를
    /// 통째로 못 읽어 화면이 죽는다.
    var screen: String?
}

/// 앱이 내놓는 **지금 화면 한 장**. 앱만 쓴다(`pokedoro-view.json`).
///
/// 줄을 이미 사람이 읽는 문자열로 담는 이유는, 무엇이 벌어지고 있는지 아는 곳이 앱뿐이기
/// 때문이다(대전 판·레이드 방·교환 상은 전부 앱 프로세스에 산다). 터미널은 **그리기만** 한다 —
/// 기능마다 구조체를 새로 만들면 라이브 기능 수만큼 모델이 늘고, 그 모델은 전부 한쪽에서만 쓰인다.
///
/// 폭은 `PokedoroAttachment.width` 를 쓴다. 그래서 줄 조립도 결국 같은 `TUIRender` 규칙을 탄다.
struct PokedoroViewSnapshot: Codable, Equatable, Sendable {
    /// 무엇을 보고 있는지. 터미널은 이 값으로 머리글·복귀 경로를 고른다.
    var screen: String
    var title: String
    var lines: [String]
    /// 지금 누를 수 있는 키. **앱이 보낸다** — 무엇을 할 수 있는지 아는 곳이 앱이고, 터미널이
    /// 따로 판정하면 두 표가 갈라져 먹지도 않는 키를 권하게 된다.
    var keys: [String]
    /// 숫자 키 하나가 만드는 요청 — `"1" → "battle.switch 1"`. **앱이 정한다**: 판이 세이브에
    /// 없어 터미널은 그 숫자가 기술인지 교체인지 방향인지 알 방법이 없다.
    ///
    /// 이 칸이 없던 동안 `watch` 의 숫자 키는 늘 `battle.move`·`room.move` 로 나갔고, 쓰러진
    /// 자리를 메우는 국면·결투의 교체·트랙(포켓슬론·퀴즈)의 방향은 앱이 키를 권해 놓고도
    /// 눌러 보면 거절만 돌아왔다.
    ///
    /// 모양은 요청 파일과 **같은 평평한 한 쌍**(이름 + 인자)이라 파서도 `Action(name:argument:)`
    /// 하나를 그대로 쓴다. **옛 파일에는 없는 칸**이라 없어도 디코딩된다.
    var numberActions: [String: String]?
    var writtenAt: Date
}

/// 화면 채널의 판정. 순수 함수로 두는 이유는 **프로세스 둘을 띄우지 않고 전수 검증**하기
/// 위해서다 — 요청 우편함(`PokedoroRequestBus`)과 같은 규칙이다.
enum PokedoroViewChannel {
    /// 신호가 살아 있는 시간. 터미널의 갱신 주기(0.5초 프레임)보다 넉넉히 크되, 터미널이 죽은 뒤
    /// 앱이 스냅샷을 계속 쓰는 시간이기도 하므로 짧게 잡는다.
    static let attachmentTimeout: TimeInterval = 5
    /// 스냅샷을 믿는 시간. 앱이 죽으면 파일은 마지막 상태로 얼어붙으므로, 이 시간을 넘기면
    /// 화면은 "낡았다" 고 말해야 한다 — 멈춘 대전을 진행 중으로 읽으면 사용자는 계속 기다린다.
    static let snapshotTimeout: TimeInterval = 5

    /// 지금 터미널이 보고 있는가.
    ///
    /// **어긋남은 양쪽 대칭으로 본다.** 앞으로 어긋난 시각을 통과시키면 미래로 적은 신호 하나로
    /// 나이 제한이 통째로 우회되고, 그 파일이 남아 있는 한 앱은 영원히 붙어 있다고 믿는다
    /// (요청 나이 제한과 같은 이유이며, 이 파일도 손으로 고칠 수 있다).
    static func isAttached(_ attachment: PokedoroAttachment?, now: Date) -> Bool {
        guard let attachment else { return false }
        return abs(now.timeIntervalSince(attachment.at)) <= attachmentTimeout
    }

    /// 바뀐 것이 없어도 **이 주기마다 한 번은 다시 쓴다.** 낡음 한계보다 짧아야 한다 — 같거나
    /// 길면 안 바뀌는 화면이 반드시 한 번은 낡은 상태를 지난다.
    ///
    /// 이 값이 없던 동안의 결함: 집중 타이머는 매초 글자가 바뀌어 늘 다시 쓰였지만, 대전 화면은
    /// 상대를 기다리는 30초 동안 한 글자도 안 바뀐다. 그 사이 파일의 시각이 멈춰 `isStale` 이
    /// 참이 되고, 터미널은 **진행 중인 대전을 지운다.**
    static let refreshInterval: TimeInterval = 2

    /// 이 화면을 파일에 써야 하는가. **바뀐 것이 없으면 안 쓴다** — 연출 프레임마다 쓰면 디스크가
    /// 갈리고, 터미널은 바뀐 게 없는데도 매번 다시 그린다.
    ///
    /// 내용 비교에서 시각은 뺀다(넣으면 매번 달라져 아무것도 거르지 못한다). 대신 **살아 있다는
    /// 표시로** 주기마다 한 번 다시 쓴다 — 위 `refreshInterval` 의 근거를 본다.
    static func shouldWrite(_ snapshot: PokedoroViewSnapshot,
                            lastWritten: PokedoroViewSnapshot?) -> Bool {
        guard let lastWritten else { return true }
        // 숫자 표도 **내용에 넣는다** — 줄과 키가 같은데 숫자의 뜻만 바뀌는 국면이 생기면,
        // 빼 두었을 때 터미널이 낡은 표로 엉뚱한 요청을 보낸다.
        let changed = (snapshot.screen, snapshot.title, snapshot.lines,
                       snapshot.keys, snapshot.numberActions)
            != (lastWritten.screen, lastWritten.title, lastWritten.lines,
                lastWritten.keys, lastWritten.numberActions)
        if changed { return true }
        return snapshot.writtenAt.timeIntervalSince(lastWritten.writtenAt) >= refreshInterval
    }

    /// 생산자가 여럿일 때 **하나를 고른다.** 부르는 쪽이 우선순위 순서로 넘긴다(대전이 집중
    /// 타이머보다 앞이다: 라이브 판이 도는 동안 타이머 줄을 그리면 사용자는 자기 차례를 놓친다).
    ///
    /// **터미널이 보고 있다고 말한 화면이 순위를 이긴다.** 순위만으로 고르면 동시에 참인 두
    /// 화면 중 뒤에 있는 것을 영영 못 본다 — 경매가 그 부류를 처음 드러냈다(시장은 상시 참이다).
    /// 요청한 화면이 지금 없으면 순위로 되돌아간다: 빈 화면을 내놓으면 앱이 죽은 것과 구분되지
    /// 않는다.
    ///
    /// 앱 루트에 `if let a { … } else if let b { … }` 로 쓰지 않는 이유는 그 자리에 테스트가
    /// 닿지 않기 때문이다 — 우선순위는 규칙이고, 규칙은 순수 쪽에 둔다.
    static func preferred(_ candidates: [PokedoroViewSnapshot?],
                          wanted: String? = nil) -> PokedoroViewSnapshot? {
        let live = candidates.compactMap { $0 }
        if let wanted, let asked = live.first(where: { $0.screen == wanted }) { return asked }
        return live.first
    }

    /// 경매 화면. **판이 아니라 목록이다** — 대전·방·교환처럼 국면이 서고 지는 것이 아니라,
    /// 네 목록(근처 게시물·내 게시물·받은 제안·내가 건 제안)이 각자 차고 빈다.
    ///
    /// 그래서 순위에서 **집중 타이머 뒤**에 둔다. 앞에 두면 이웃의 게시물 하나가 집중 타이머를
    /// 영영 가리고, 그 화면은 터미널이 `wanted` 로 부를 때 온다.
    ///
    /// 누를 키가 없어(번호 공간이 넷) 칠 명령을 **줄의 마지막에** 싣는다 — `AuctionScreen.lines`
    /// 가 그 일을 하므로 여기서 다시 붙이지 않는다.
    static func auctionSnapshot(_ state: AuctionTerminalState, width: Int,
                                now: Date) -> PokedoroViewSnapshot? {
        guard !AuctionScreen.isIdle(state) else { return nil }
        return PokedoroViewSnapshot(
            screen: "auction",
            title: AuctionScreen.title(state),
            lines: AuctionScreen.lines(state, width: drawableWidth(width)),
            keys: AuctionScreen.keys(state),
            writtenAt: now)
    }

    /// 교환 화면. 대전·방과 같은 통로다.
    static func tradeSnapshot(_ state: TradeTerminalState, width: Int,
                              now: Date) -> PokedoroViewSnapshot? {
        guard TradeScreen.kind(state) != .none else { return nil }
        return PokedoroViewSnapshot(
            screen: "trade",
            title: TradeScreen.title(state),
            lines: TradeScreen.lines(state, width: drawableWidth(width)),
            keys: TradeScreen.keys(state),
            writtenAt: now)
    }

    /// LAN 방(협동 레이드·방 대전) 화면. 대전과 **같은 통로**다 — 방 상태도 세이브에 없다.
    static func roomSnapshot(_ state: RoomTerminalState, language: AppLanguage,
                             width: Int, now: Date) -> PokedoroViewSnapshot? {
        guard RoomScreen.kind(state) != .none else { return nil }
        return PokedoroViewSnapshot(
            screen: "room",
            title: RoomScreen.title(state),
            lines: RoomScreen.lines(state, language: language, width: drawableWidth(width)),
            keys: RoomScreen.keys(state),
            numberActions: numberActions { RoomScreen.action(number: $0, in: state) },
            writtenAt: now)
    }

    /// 터미널이 받을 수 있는 숫자 키의 폭. 판마다 뜻이 다르지만(기술 넷·팀 여섯·방향 넷) 표를
    /// 만드는 쪽은 전부를 훑고 **요청이 되지 않는 번호는 알아서 빠진다** — 화면마다 상한을 다시
    /// 적으면 그 숫자가 두 벌이 된다.
    static let numberKeyRange = 1...9

    /// 숫자 → 요청 표. 값은 요청 파일과 같은 평평한 모양(이름 + 인자)이다.
    static func numberActions(_ action: (Int) -> PokedoroRequest.Action?) -> [String: String] {
        Dictionary(uniqueKeysWithValues: numberKeyRange.compactMap { number in
            action(number).map {
                (String(number), [$0.name, $0.argument].compactMap { $0 }.joined(separator: " "))
            }
        })
    }

    /// LAN 1대1 대전 화면. **이 채널의 첫 라이브 생산자**다.
    ///
    /// 대전 판은 세이브에 없고 `BattleCenter` 에만 살아서 터미널이 스스로 만들 수 없다 — 웨이브
    /// 런과 갈리는 지점이 여기다(그쪽은 세이브에 남아 터미널이 직접 읽는다).
    ///
    /// 대전이 아예 없으면 `nil` 이다. 빈 화면을 내놓으면 터미널이 빈 줄을 그리고, 우선순위에서
    /// 뒤에 있는 생산자(집중 타이머)까지 덮는다.
    static func battleSnapshot(_ state: BattleTerminalState, language: AppLanguage,
                               width: Int, now: Date) -> PokedoroViewSnapshot? {
        guard NetBattleScreen.kind(state) != .none else { return nil }
        return PokedoroViewSnapshot(
            screen: "battle",
            title: NetBattleScreen.title(state),
            lines: NetBattleScreen.lines(state, language: language,
                                         width: drawableWidth(width)),
            keys: NetBattleScreen.keys(state),
            numberActions: numberActions { NetBattleScreen.action(number: $0, in: state) },
            writtenAt: now)
    }

    /// 이 화면이 낡았는가(앱이 조용해졌는가).
    static func isStale(_ snapshot: PokedoroViewSnapshot, now: Date) -> Bool {
        now.timeIntervalSince(snapshot.writtenAt) > snapshotTimeout
    }

    /// 줄을 만들 수 있는 폭. 파이프로 붙었거나 손으로 고친 파일에서 0·음수가 올 수 있는데,
    /// 그 값으로는 `TUIRender` 가 빈 줄만 내놓는다 — 화면이 죽는 대신 읽을 수 있는 폭으로 접는다.
    static let fallbackWidth = 80

    static func drawableWidth(_ width: Int) -> Int { width > 0 ? width : fallbackWidth }

    /// 집중 타이머 화면. **이 채널의 첫 생산자**다.
    ///
    /// `FocusTimer` 는 세이브에 저장되지 않으므로 터미널이 스스로 만들 수 없다 — 지금까지 `watch`
    /// 는 모험 진행만 보여 주고 "집중 12:34 남음" 은 못 보여 줬다. 앱만 아는 값을 앱이 내놓는
    /// 것이 이 채널의 존재 이유이고, 라이브 기능(대전·레이드…)은 같은 자리에 생산자를 더한다.
    ///
    /// 아무것도 안 돌면 `nil` 이다 — 빈 화면을 내놓으면 터미널이 빈 줄을 그리고 파일도 이유 없이
    /// 갱신된다.
    static func focusSnapshot(phase: FocusPhase, clockText: String, completed: Int,
                              now: Date) -> PokedoroViewSnapshot? {
        let title: String
        switch phase {
        case .idle: return nil
        case .focus: title = "집중 중"
        case .rest: title = "휴식 중"
        }
        return PokedoroViewSnapshot(
            screen: "focus",
            title: title,
            lines: ["\(title)   남은 시간 \(clockText)", "오늘 마친 집중  \(completed)회"],
            // 키는 앱이 정한다 — 무엇을 할 수 있는지 아는 곳이 앱이다. 지금 단계에서 할 수 있는
            // 것은 끝내기뿐이고, 시작 키는 홈이 이미 상태를 보고 고른다.
            keys: ["x 끝내기"],
            writtenAt: now)
    }
}
