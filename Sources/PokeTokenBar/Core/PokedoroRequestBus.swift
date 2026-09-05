import Foundation

/// 터미널이 앱에 보내는 요청 한 건.
///
/// **왜 터미널이 직접 세이브를 바꾸지 않나.** 두 프로세스 사이에 잠금이 없어 나중 쓰기가 앞
/// 쓰기를 통째로 덮고, 세이브를 여는 것 자체가 "앱이 죽은 사이 밀린 일"(랭크전 패배 정산)을
/// 실행한다(`ReadOnlyStoreTests`). 잠금을 들이면 메뉴바 앱이 항상 떠 있으므로 터미널이 잠금을
/// 잡을 일이 사실상 없다 — 기능이 죽은 채로 태어난다. 그래서 **터미널은 부탁하고 앱이 한다**.
struct PokedoroRequest: Codable, Equatable, Sendable {
    /// 터미널이 부탁하는 일 하나. **이름과 인자가 한 값이다** — 예전엔 `verb` 와 `minutes` 가 따로
    /// 실려 "stop 인데 90분" 같은 요청을 타입이 허락했고, 파일은 손으로 고칠 수 있으니 그 조합은
    /// 실제로 들어온다. 표현할 수 없는 상태는 걸러 낼 필요도 없다.
    ///
    /// 인자는 **닫힌 타입만** 받는다(지금은 분 하나). 임의 문자열을 인자로 받는 동작은 이 목록에
    /// 넣지 않는다 — 요청 파일이 신뢰경계라 그 문자열이 곧 앱으로 들어오는 입력이 된다.
    enum Action: Equatable, Sendable {
        /// 분을 안 적으면 `nil` 이다 — 기본 길이는 실행기가 고른다. 여기서 25 를 채우면 기본값이
        /// 두 곳이 되고, 한쪽만 바뀌면 화면과 터미널이 다른 길이를 켠다.
        case start(minutes: Int?)
        case claim
        case stop
        /// 아이템 하나 사용. 종류는 **닫힌 목록**(`ItemKind.named`)을 지난 값이다.
        case use(item: ItemKind)
        case evolve
        /// `party` 가 찍는 번호(1부터). 인덱스로 접는 것은 로스터를 아는 실행기가 한다 —
        /// 파일에는 사용자가 본 값이 그대로 적혀야 손으로 고칠 수 있다.
        case switchCompanion(number: Int)
        /// **인자가 자유 문자열인 유일한 동작.** 별명은 본래 자유 문자열이고, 길이·개행 클램프는
        /// 실행기가 한다(파일을 직접 고친 경로까지 막아야 하므로).
        case rename(nickname: String)
        /// 상점 구매. 수량은 **1 이상**이고, 살 수 있는 것은 `ShopCatalog` 에 있는 것뿐이다.
        case buy(good: ShopGood, quantity: Int)
        /// 부화 조건이 찼으면 부화시킨다. 앱이 PokéAPI 를 타므로 실행이 오래 걸릴 수 있다.
        case hatch
        /// **되돌릴 수 없다.** 확인(`--yes`)은 명령 쪽에서 받고, 여기 오는 요청은 이미 확인된 것이다.
        case release(number: Int)

        // MARK: 웨이브 런
        //
        // 이름을 `wave.` 로 묶는 이유는 **낱말이 하나뿐**이기 때문이다. `move`·`pick` 을 최상위에
        // 두면 다음 라이브 기능(PvP·레이드)이 같은 낱말을 쓰고 싶을 때 이름이 이미 팔려 있고,
        // 손으로 고친 파일에서 어느 기능의 동작인지도 알 수 없다.

        /// 새 판. 스타터 번호는 `RogueRun.starterPool` 의 순번(1부터)이고, 없으면 앱이 무작위로
        /// 고른다 — 기본값을 여기 적으면 두 곳이 되고 한쪽만 바뀌는 날 다른 판이 열린다.
        case waveStart(starter: Int?)
        /// 기술 하나. `move` 는 내 칸의 기술 순번, `target` 은 상대 필드 칸(1부터)이다.
        /// **어느 칸이 행동하는지는 싣지 않는다** — 그 값은 판을 든 앱이 안다(`slotsAwaitingAction`).
        case waveMove(move: Int, target: Int?)
        /// 파티 번호로 교체. 쓰러진 칸이 있으면 **그 칸을 채우는 무료 출전**이고 아니면 그 칸의
        /// 행동을 쓰는 교체다 — 화면의 같은 줄이 두 일을 하는 것과 같은 규칙이라 동작도 하나다.
        case waveSwitch(number: Int)
        case waveBall(target: Int?)
        case wavePick(number: Int)
        /// 길은 **닫힌 목록**(`RunRoute`)이다. 모르는 이름을 안전한 길로 접으면 사용자는 위험한
        /// 길을 골랐다고 믿은 채 보상 한 장을 잃는다.
        case waveRoute(RunRoute)
        /// **되돌릴 수 없다** — 판이 사라진다. 확인은 방생과 같이 명령 쪽에서 받는다.
        case waveForfeit

        // MARK: LAN 1대1 대전
        //
        // 웨이브 런과 달리 판이 세이브에 없다 — `BattleCenter` 가 든다. 그래서 **볼 때도 앱이
        // 떠 있어야** 하고(화면 채널), 여기 오는 동작도 전부 그 객체를 지난다.
        //
        // 신청·수락·파티 편성은 없다. 상대를 찾는 일은 소켓이고, 수락은 6마리 후보를 고르는
        // 화면으로 이어진다 — 터미널에 입력 줄이 없어 그 화면을 대신할 방법이 없다.

        /// 기술 번호(1부터). 어느 개체가 쓰는지는 앱이 안다(`NetBattleState.myActive`).
        case battleMove(move: Int)
        /// 팀 번호(1부터)로 교체. 쓰러진 자리를 메우는 교체는 **턴을 쓰지 않는다**
        /// (`NetBattleState.replaceFainted`) — 어느 쪽인지도 앱이 판단한다.
        case battleSwitch(number: Int)
        /// **되돌릴 수 없다** — 그 판을 지고 랭크 판돈도 넘어간다.
        case battleForfeit
        /// 받은 신청을 거절한다. **확인을 받지 않는다** — 되돌릴 수 있는 일이다(상대가 다시 건다).
        case battleDecline

        // MARK: LAN 방 (협동 레이드·방 대전)
        //
        // 대전과 같은 성질이다 — 방 상태도 세이브에 없고 `MultiplayerRoomCenter` 가 든다.
        // **방을 만들고 찾는 일은 없다**: 소켓과 목록 훑기라 터미널이 할 수 있는 모양이 아니다.

        /// 기술 번호(1부터)와 **대상 번호**(1부터, 화면이 찍는 값). 대상을 안 적으면 첫 상대다 —
        /// 협동 레이드는 보스 하나라 대개 생략한다. UUID 를 싣지 않는 이유는 사람이 칠 수 없어서다.
        case roomMove(move: Int, target: Int?)
        /// 호스트가 판을 시작한다. 사람이 덜 모였으면 센터가 거절한다.
        case roomStart
        /// **되돌릴 수 없다** — 그 판의 정산을 못 받는다.
        case roomLeave

        // MARK: 교환
        //
        // 번호가 **두 종류**다: 내 개체는 `party` 가 찍는 번호, 상대 목록은 그 세션에만 있는
        // 번호다. 그래서 동작 이름도 갈라 둔다(`offer` / `want`) — 한 이름으로 받으면 사용자는
        // 자기 것을 내주려다 남의 것을 지목한다.

        case tradeAccept
        case tradeDecline
        /// 내가 낼 개체 — `party` 번호.
        case tradeOffer(number: Int)
        /// 상대에게 원하는 개체 — `trade` 가 찍는 번호.
        case tradeWant(number: Int)
        /// **되돌릴 수 없다** — 양쪽이 확인하면 개체가 넘어간다.
        case tradeConfirm
        /// **되돌릴 수 없다** — 협상을 통째로 버린다.
        case tradeCancel

        // MARK: 경매
        //
        // 번호가 **넷**이다: 내 개체는 `party` 번호, 근처 게시물·받은 제안·내가 건 제안은 각자
        // 그 세션의 번호다. 그래서 동작 이름도 넷으로 갈라 둔다 — 한 이름으로 받으면 손으로
        // 고친 파일에서 어느 목록의 번호인지 알 방법이 없다.

        /// 내 개체를 경매에 올린다 — `party` 번호. **확인을 받지 않는다**: 내릴 수 있고, 팔리는
        /// 것은 수락(`auctionAccept`)이 한 번 더 물어본 뒤다.
        case auctionPost(number: Int)
        case auctionUnpost(number: Int)
        /// 남의 게시물에 내 개체를 건다 — `listing` 은 시장 번호, `mon` 은 `party` 번호다.
        /// **되돌릴 수 없다**: 게시자가 수락하는 순간 더 물어볼 새 없이 커밋이 돈다.
        case auctionApply(listing: Int, mon: Int)
        /// 남의 게시물에 별의모래를 건다. **되돌릴 수 없다** — 위와 같은 이유다.
        case auctionBid(listing: Int, stardust: Int)
        /// 받은 제안을 수락한다. **되돌릴 수 없다** — 게시한 개체가 넘어간다.
        case auctionAccept(number: Int)
        /// 받은 제안을 거절한다. 확인을 받지 않는다 — 상대가 다시 걸 수 있다.
        case auctionReject(number: Int)
        /// 답을 못 받은 내 제안을 거둬들인다. 확인을 받지 않는다 — 다시 걸 수 있고, 그대로
        /// 두면 그 개체가 다른 제안에 묶여 있다(자동 시간 제한이 없다).
        case auctionCancel(number: Int)
        /// 끝난 제안 카드를 치운다 — 화면 정리다.
        case auctionClear(number: Int)

        // MARK: Memory Home
        //
        // **진행이 파일에 있는 두 번째 기능이다**(웨이브 런이 첫째). 그래서 조회는 터미널이
        // 직접 하고, 여기 오는 것은 쓰기뿐이다 — 앨범은 `CompanionStore` 가 이미 들고 있어
        // 창구가 필요 없다.
        //
        // 번호가 **셋**이다: 룸메이트는 `party` 번호, 가구를 놓는 칸은 격자 칸 번호(1–48),
        // 치울 가구는 화면이 찍는 번호다. 이름이 그 셋을 가른다.

        /// 오늘의 기분. **닫힌 목록**이다 — 방 문구와 동행 반응이 이 값으로 갈린다.
        case homeMood(MemoryHomeMood)
        /// 방 스타일. 닫힌 목록이고, 잠긴 스타일은 실행기가 조건을 붙여 거절한다.
        case homeStyle(MemoryHomeRoomStyle)
        /// 빠른 기록 한 줄. 길이(280자)는 앨범이 판정한다.
        case homeNote(body: String)
        /// 대문 문구. 길이(60자)·줄바꿈 금지도 앨범이 판정한다.
        case homeMessage(text: String)
        /// 공개 닉네임. 바뀌면 **LAN 광고도 다시** 나간다.
        case homeNickname(name: String)
        /// 룸메이트를 켜고 끈다 — `party` 번호. 같은 명령이 두 일을 하는 것은 화면의 체크
        /// 표시와 같은 모양이다.
        case homeRoommate(number: Int)
        /// 가구를 격자에 놓는다. `cell` 은 1–48 이고, 격자 좌표 변환은 `HomeScreen` 이 한다.
        case homePlace(item: ItemKind, cell: Int)
        /// 놓인 가구를 치운다 — 화면이 찍는 번호.
        case homeRemove(number: Int)
        /// 배치를 통째로 치운다. **확인을 받는다** — 되돌리기 기록은 앱 메모리라 앱을 다시
        /// 켜면 없다.
        case homeReset
        case homeUndo
        case homeRedo

        /// 파일에 적히는 이름.
        var name: String {
            switch self {
            case .start: "start"
            case .claim: "claim"
            case .stop: "stop"
            case .use: "use"
            case .evolve: "evolve"
            case .switchCompanion: "switch"
            case .rename: "name"
            case .buy: "buy"
            case .hatch: "hatch"
            case .release: "release"
            case .waveStart: "wave.start"
            case .waveMove: "wave.move"
            case .waveSwitch: "wave.switch"
            case .waveBall: "wave.ball"
            case .wavePick: "wave.pick"
            case .waveRoute: "wave.route"
            case .waveForfeit: "wave.forfeit"
            case .battleMove: "battle.move"
            case .battleSwitch: "battle.switch"
            case .battleForfeit: "battle.forfeit"
            case .battleDecline: "battle.decline"
            case .roomMove: "room.move"
            case .roomStart: "room.start"
            case .roomLeave: "room.leave"
            case .tradeAccept: "trade.accept"
            case .tradeDecline: "trade.decline"
            case .tradeOffer: "trade.offer"
            case .tradeWant: "trade.want"
            case .tradeConfirm: "trade.confirm"
            case .tradeCancel: "trade.cancel"
            case .auctionPost: "auction.post"
            case .auctionUnpost: "auction.unpost"
            case .auctionApply: "auction.apply"
            case .auctionBid: "auction.bid"
            case .auctionAccept: "auction.accept"
            case .auctionReject: "auction.reject"
            case .auctionCancel: "auction.cancel"
            case .auctionClear: "auction.clear"
            case .homeMood: "home.mood"
            case .homeStyle: "home.style"
            case .homeNote: "home.note"
            case .homeMessage: "home.message"
            case .homeNickname: "home.nickname"
            case .homeRoommate: "home.roommate"
            case .homePlace: "home.place"
            case .homeRemove: "home.remove"
            case .homeReset: "home.reset"
            case .homeUndo: "home.undo"
            case .homeRedo: "home.redo"
            }
        }

        /// 파일에 적히는 인자 — **칸 하나**다. 동작마다 칸 이름을 따로 두면 새 동작이 늘 때마다
        /// "그 동작에 없어야 하는 칸" 검사가 같이 늘고, 한 칸을 빠뜨려도 컴파일이 통과한다.
        /// 대화 도구의 마커 문법(`[[tool:이름(인자)]]`)도 같은 모양이다.
        var argument: String? {
            switch self {
            case .start(let minutes): minutes.map(String.init)
            // 표시 이름이 아니라 rawValue 로 적는다 — 표시 이름으로 적으면 언어 설정을 바꾼
            // 사용자가 자기 요청 파일을 못 읽는다.
            case .use(let item): item.rawValue
            case .switchCompanion(let number): String(number)
            case .rename(let nickname): nickname
            // 수량 1 은 **안 적는다**. 적으면 같은 요청이 두 모양으로 존재하고, 손으로 고친 파일과
            // 프로그램이 쓴 파일이 달라 보인다.
            case .buy(let good, let quantity): quantity > 1 ? "\(good.slug) \(quantity)" : good.slug
            case .release(let number): String(number)
            case .waveStart(let starter): starter.map(String.init)
            // 타겟 1 은 안 적는다 — 수량 1 을 안 적는 것과 같은 이유다(같은 요청이 두 모양으로
            // 존재하면 손으로 고친 파일과 프로그램이 쓴 파일이 달라 보인다).
            case .waveMove(let move, let target):
                target.map { "\(move) \($0)" } ?? String(move)
            case .waveSwitch(let number): String(number)
            case .waveBall(let target): target.map(String.init)
            case .wavePick(let number): String(number)
            case .waveRoute(let route): route.rawValue
            case .battleMove(let move): String(move)
            case .battleSwitch(let number): String(number)
            case .roomMove(let move, let target):
                target.map { "\(move) \($0)" } ?? String(move)
            case .tradeOffer(let number), .tradeWant(let number): String(number)
            case .auctionPost(let number), .auctionUnpost(let number),
                 .auctionAccept(let number), .auctionReject(let number),
                 .auctionCancel(let number), .auctionClear(let number): String(number)
            // 두 번호는 **둘 다** 적는다. 하나를 생략 가능하게 두면(웨이브의 대상처럼) 어느
            // 쪽이 빠졌는지 알 수 없고, 추측으로 채우면 사용자가 적지 않은 개체를 내놓는다.
            case .homeMood(let mood): mood.rawValue
            case .homeStyle(let style): style.rawValue
            case .homeNote(let body): body
            case .homeMessage(let text): text
            case .homeNickname(let name): name
            case .homeRoommate(let number), .homeRemove(let number): String(number)
            // 아이템은 **rawValue 로** 적는다 — 표시 이름으로 적으면 언어를 바꾼 사용자가
            // 자기 요청 파일을 못 읽는다(`use` 와 같은 규칙).
            case .homePlace(let item, let cell): "\(item.rawValue) \(cell)"
            case .auctionApply(let listing, let mon): "\(listing) \(mon)"
            case .auctionBid(let listing, let stardust): "\(listing) \(stardust)"
            case .claim, .stop, .evolve, .hatch, .waveForfeit,
                 .battleForfeit, .battleDecline, .roomStart, .roomLeave,
                 .tradeAccept, .tradeDecline, .tradeConfirm, .tradeCancel,
                 .homeReset, .homeUndo, .homeRedo: nil
            }
        }

        /// 파일에 적힌 이름·인자 → 동작. 모르면 `nil` 이다.
        ///
        /// **인자를 받지 않는 동작에 인자가 붙었으면 추측하지 않는다**(대화 도구 파서와 같은 규칙).
        /// 인자를 버리고 실행하면 사용자는 자기가 적은 값이 무시된 걸 모른 채 다른 일이 벌어진
        /// 것을 본다. 목록 밖 이름도 거절이 아니라 **요청으로 읽히지 않는 것**이다.
        ///
        /// 인자 변환도 여기서 닫는다 — 통과한 동작은 늘 실행할 수 있는 모양이다(모르는 아이템
        /// 이름·0 이하의 번호·빈 별명은 동작이 되지 않는다).
        init?(name: String, argument: String?) {
            switch name {
            case "start":
                // 분 없는 시작은 그대로 통과한다 — 기본 길이는 실행기가 고른다.
                guard let argument else { self = .start(minutes: nil); return }
                guard let minutes = Self.wholeNumber(argument) else { return nil }
                self = .start(minutes: minutes)
            case "claim" where argument == nil: self = .claim
            case "stop" where argument == nil: self = .stop
            case "evolve" where argument == nil: self = .evolve
            case "use":
                guard let argument, let item = ItemKind.named(argument) else { return nil }
                self = .use(item: item)
            case "switch":
                // 0 이하는 `party` 의 목록에 없는 번호다. 그대로 인덱스로 접으면 배열 밖을 읽거나
                // 엉뚱한 개체를 건드린다.
                guard let argument, let number = Self.wholeNumber(argument), number >= 1 else { return nil }
                self = .switchCompanion(number: number)
            case "name":
                // 빈 이름·공백만은 요청이 아니다. 실수로 지운 이름이 조용히 통과하면 사용자는
                // 자기가 무엇을 지웠는지 모른다.
                guard let argument,
                      !argument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                self = .rename(nickname: argument)
            case "hatch" where argument == nil: self = .hatch
            case "buy":
                // 마지막 조각이 숫자면 수량이다. 이름이 여러 조각인 물건이 있으므로(표시 이름)
                // 앞쪽을 통째로 이름으로 본다.
                guard let argument else { return nil }
                var words = argument.split(separator: " ").map(String.init)
                var quantity = 1
                if words.count > 1, let last = words.last, let value = Self.wholeNumber(last) {
                    // 0개·음수 구매는 요청이 아니다 — 실행해도 아무 일이 안 일어나는데 성공으로
                    // 보고된다. 숫자가 아닌 마지막 조각은 이름의 일부다(그대로 둔다).
                    guard value >= 1 else { return nil }
                    quantity = value
                    words.removeLast()
                }
                guard let good = ShopCatalog.named(words.joined(separator: " ")) else { return nil }
                // 한 벌뿐인 물건에 수량이 붙었으면 추측하지 않는다.
                guard quantity == 1 || good.allowsQuantity else { return nil }
                self = .buy(good: good, quantity: quantity)
            case "release":
                guard let argument, let number = Self.wholeNumber(argument), number >= 1 else { return nil }
                self = .release(number: number)
            // 웨이브 런 — 번호는 전부 **1 이상**이다. 0 이하를 그대로 인덱스로 접으면 배열 밖을
            // 읽거나 엉뚱한 칸을 건드린다(개체 번호와 같은 규칙이고, 상한은 판을 아는 실행기가 본다).
            case "wave.start":
                guard let argument else { self = .waveStart(starter: nil); return }
                guard let number = Self.countingNumber(argument) else { return nil }
                self = .waveStart(starter: number)
            case "wave.move":
                guard let argument else { return nil }
                let words = argument.split(separator: " ").map(String.init)
                guard let move = words.first.flatMap(Self.countingNumber) else { return nil }
                switch words.count {
                case 1: self = .waveMove(move: move, target: nil)
                case 2:
                    guard let target = Self.countingNumber(words[1]) else { return nil }
                    self = .waveMove(move: move, target: target)
                default: return nil
                }
            case "wave.switch":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .waveSwitch(number: number)
            case "wave.ball":
                guard let argument else { self = .waveBall(target: nil); return }
                guard let number = Self.countingNumber(argument) else { return nil }
                self = .waveBall(target: number)
            case "wave.pick":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .wavePick(number: number)
            case "wave.route":
                guard let argument, let route = RunRoute(rawValue: argument) else { return nil }
                self = .waveRoute(route)
            case "wave.forfeit" where argument == nil: self = .waveForfeit
            case "battle.move":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .battleMove(move: number)
            case "battle.switch":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .battleSwitch(number: number)
            case "battle.forfeit" where argument == nil: self = .battleForfeit
            case "battle.decline" where argument == nil: self = .battleDecline
            case "room.move":
                guard let argument else { return nil }
                let words = argument.split(separator: " ").map(String.init)
                guard let move = words.first.flatMap(Self.countingNumber) else { return nil }
                switch words.count {
                case 1: self = .roomMove(move: move, target: nil)
                case 2:
                    guard let target = Self.countingNumber(words[1]) else { return nil }
                    self = .roomMove(move: move, target: target)
                default: return nil
                }
            case "room.start" where argument == nil: self = .roomStart
            case "room.leave" where argument == nil: self = .roomLeave
            case "trade.accept" where argument == nil: self = .tradeAccept
            case "trade.decline" where argument == nil: self = .tradeDecline
            case "trade.offer":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .tradeOffer(number: number)
            case "trade.want":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .tradeWant(number: number)
            case "trade.confirm" where argument == nil: self = .tradeConfirm
            case "trade.cancel" where argument == nil: self = .tradeCancel
            // 경매 — 번호는 전부 **1 이상**이고, 어느 목록의 번호인지는 이름이 말한다.
            case "auction.post":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .auctionPost(number: number)
            case "auction.unpost":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .auctionUnpost(number: number)
            case "auction.apply":
                guard let pair = Self.numberPair(argument) else { return nil }
                self = .auctionApply(listing: pair.0, mon: pair.1)
            case "auction.bid":
                guard let pair = Self.numberPair(argument) else { return nil }
                self = .auctionBid(listing: pair.0, stardust: pair.1)
            case "auction.accept":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .auctionAccept(number: number)
            case "auction.reject":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .auctionReject(number: number)
            case "auction.cancel":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .auctionCancel(number: number)
            case "auction.clear":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .auctionClear(number: number)
            // Memory Home — 닫힌 목록은 **모르는 값을 접지 않는다.** 손으로 고친 파일에서
            // 기본값으로 접히면 사용자가 고르지 않은 방이 켜진다.
            case "home.mood":
                guard let argument, let mood = MemoryHomeMood(rawValue: argument) else { return nil }
                self = .homeMood(mood)
            case "home.style":
                guard let argument,
                      let style = MemoryHomeRoomStyle(rawValue: argument) else { return nil }
                self = .homeStyle(style)
            case "home.note":
                guard let body = Self.meaningfulText(argument) else { return nil }
                self = .homeNote(body: body)
            case "home.message":
                guard let text = Self.meaningfulText(argument) else { return nil }
                self = .homeMessage(text: text)
            case "home.nickname":
                guard let name = Self.meaningfulText(argument) else { return nil }
                self = .homeNickname(name: name)
            case "home.roommate":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .homeRoommate(number: number)
            case "home.place":
                // 가구 이름 + 칸. **둘 다** 있어야 한다 — 칸을 추측으로 채우면 사용자가 고르지
                // 않은 자리에 가구가 놓인다.
                guard let argument else { return nil }
                let words = argument.split(separator: " ").map(String.init)
                guard words.count == 2, let item = ItemKind.furnitureNamed(words[0]),
                      let cell = Self.countingNumber(words[1]),
                      cell <= HomeScreen.cellCount else { return nil }
                self = .homePlace(item: item, cell: cell)
            case "home.remove":
                guard let argument, let number = Self.countingNumber(argument) else { return nil }
                self = .homeRemove(number: number)
            case "home.reset" where argument == nil: self = .homeReset
            case "home.undo" where argument == nil: self = .homeUndo
            case "home.redo" where argument == nil: self = .homeRedo
            default: return nil
            }
        }

        /// 빈 글·공백만은 요청이 아니다. 실수로 지운 문구가 조용히 통과하면 사용자는 자기가
        /// 무엇을 지웠는지 모른다(`name` 과 같은 규칙). 길이 상한은 앨범이 판정한다.
        private static func meaningfulText(_ argument: String?) -> String? {
            guard let argument,
                  !argument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return argument
        }

        /// 번호 **둘**. 하나만 적혀 있거나 셋이 적혀 있으면 요청이 아니다 — 빠진 자리를
        /// 추측으로 채우면 사용자가 적지 않은 개체를 내놓거나 적지 않은 게시물에 제안을 건다.
        private static func numberPair(_ argument: String?) -> (Int, Int)? {
            guard let argument else { return nil }
            let words = argument.split(separator: " ").map(String.init)
            guard words.count == 2, let first = countingNumber(words[0]),
                  let second = countingNumber(words[1]) else { return nil }
            return (first, second)
        }

        /// 사람이 세는 번호(1부터). 목록에 없는 0 이하는 번호가 아니다.
        private static func countingNumber(_ raw: String) -> Int? {
            guard let value = wholeNumber(raw), value >= 1 else { return nil }
            return value
        }

        /// 숫자만 있는 문자열만 숫자다. `" 25 "`·`"+25"` 는 `Int(_:)` 를 통과하므로 자릿수 검사를
        /// 먼저 둔다 — 무엇을 붙였는지 추측하지 않겠다는 뜻이다(명령 파서와 같은 규칙).
        private static func wholeNumber(_ raw: String) -> Int? {
            guard !raw.isEmpty, raw.allSatisfy(\.isASCII), raw.allSatisfy(\.isNumber) else { return nil }
            return Int(raw)
        }
    }

    var id: UUID
    var action: Action
    var requestedAt: Date
}

/// 요청 파일의 모양. **평평한 JSON 을 손으로 유지한다** — 인자를 든 enum 을 Swift 에 그냥 맡기면
/// `{"action":{"start":{"minutes":25}}}` 같은 중첩이 나오는데, 그 파일은 사람이 고치기 어렵고
/// 문서가 약속한 모양도 아니다(고친 파일이 조용히 무시된다).
extension PokedoroRequest {
    private enum CodingKeys: String, CodingKey { case id, action, argument, requestedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        requestedAt = try container.decode(Date.self, forKey: .requestedAt)
        let name = try container.decode(String.self, forKey: .action)
        let argument = try container.decodeIfPresent(String.self, forKey: .argument)
        // 이름과 인자가 어긋난 파일은 **요청이 아니다**. 던지면 `pendingRequest()` 가 nil 을
        // 돌려주므로 깨진 파일과 같은 취급이 된다 — 그 경로는 이미 앱을 죽이지 않는다.
        guard let action = Action(name: name, argument: argument) else {
            throw DecodingError.dataCorruptedError(forKey: .action, in: container,
                                                   debugDescription: "unknown action \(name)")
        }
        self.action = action
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(action.name, forKey: .action)
        // 인자 칸을 **아예 안 쓴다**. 남겨 두면 `{"action":"stop","argument":null}` 이 정상으로
        // 보이고, 손으로 고치는 사용자가 그 칸이 뭔가 한다고 믿는다.
        try container.encodeIfPresent(action.argument, forKey: .argument)
        try container.encode(requestedAt, forKey: .requestedAt)
    }
}

/// 앱이 되돌려 주는 답. `message` 는 **사람이 읽는 한국어 한 줄**이다 — 대화 도구의 영문
/// 기계 문자열과 다른 물건이고, 그래서 사유 → 문구 변환은 프런트엔드가 각자 한다.
struct PokedoroReply: Codable, Equatable, Sendable {
    var id: UUID
    var succeeded: Bool
    var message: String
}

/// 요청·답이 오가는 두 파일. **파일마다 쓰는 쪽이 하나다** — 요청은 터미널만, 답은 앱만 쓴다.
///
/// 앱이 처리한 요청 파일을 지우지 않는 이유가 그것이다. 지우려면 앱이 터미널의 파일에 손을 대야
/// 하고, 그 순간 한 파일에 쓰기 주체가 둘이 된다(정확히 이 기능이 피하려던 상태다). 대신
/// `PokedoroRequestBus` 의 나이 제한과 id 두 가드가 "이미 처리한 요청" 을 걸러 낸다.
struct PokedoroMailbox: Sendable {
    let requestURL: URL
    let replyURL: URL
    /// 터미널이 "보고 있다" 고 남기는 신호. 터미널만 쓴다.
    let attachURL: URL
    /// 앱이 내놓는 지금 화면. 앱만 쓴다.
    let viewURL: URL

    /// 세이브와 **같은 디렉터리**에 둔다 — `PTB_STATE_DIR` 하나로 프로필 전체가 격리된다는
    /// `CompanionStorageLocations` 의 계약을 요청도 지켜야 한다. 아니면 격리된 QA 세션의
    /// 터미널이 실제 사용자 앱을 조종한다.
    init(directory: URL? = nil) {
        let base = directory ?? CompanionStorageLocations().directory
        requestURL = base.appendingPathComponent("pokedoro-request.json")
        replyURL = base.appendingPathComponent("pokedoro-reply.json")
        attachURL = base.appendingPathComponent("pokedoro-attach.json")
        viewURL = base.appendingPathComponent("pokedoro-view.json")
    }

    // MARK: 터미널 쪽

    /// 요청을 남긴다. 실패를 **던진다** — 조용히 삼키면 터미널이 3초를 기다린 뒤 "앱이 꺼져
    /// 있다" 고 답하는데, 실제로는 디렉터리 권한 문제라 사용자가 영영 못 고친다.
    func send(_ request: PokedoroRequest) throws {
        try Self.encoder.encode(request).write(to: requestURL, options: .atomic)
    }

    /// **내 요청의 답만** 받는다. id 를 안 보면 앞 세션의 답을 자기 것으로 착각해, 하지도 않은
    /// 일을 성공으로 보고한다.
    func reply(to id: UUID) -> PokedoroReply? {
        guard let reply: PokedoroReply = Self.load(replyURL) else { return nil }
        return reply.id == id ? reply : nil
    }

    /// 보고 있다는 신호를 남긴다. **살아 있는 동안 계속 갱신한다** — 터미널은 인사하고 죽을 수
    /// 있으므로(창을 닫거나 kill 당한다) 앱은 나이로 판정한다.
    func attach(_ attachment: PokedoroAttachment) throws {
        try Self.encoder.encode(attachment).write(to: attachURL, options: .atomic)
    }

    /// 앱이 내놓은 지금 화면.
    func view() -> PokedoroViewSnapshot? { Self.load(viewURL) }

    // MARK: 앱 쪽

    /// 터미널이 남긴 신호. 나이 판정은 `PokedoroViewChannel.isAttached` 가 한다.
    func attachment() -> PokedoroAttachment? { Self.load(attachURL) }

    /// 지금 화면을 내놓는다. **바뀔 때만** 부른다(`PokedoroViewChannel.shouldWrite`).
    func postView(_ snapshot: PokedoroViewSnapshot) throws {
        try Self.encoder.encode(snapshot).write(to: viewURL, options: .atomic)
    }

    /// 지금 놓여 있는 요청. **파일이 없는 것이 정상이다** — 앱은 요청이 없는 매 초에도 이
    /// 경로를 밟는다. 깨진 파일도 `nil` 이다: 여기서 죽으면 메뉴바 앱이 통째로 내려간다.
    func pendingRequest() -> PokedoroRequest? { Self.load(requestURL) }

    func post(_ reply: PokedoroReply) throws {
        try Self.encoder.encode(reply).write(to: replyURL, options: .atomic)
    }

    // MARK: 인코딩

    private static let encoder = JSONEncoder()

    private static func load<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// 앱이 요청을 실행해도 되는지 정하는 두 가드. 순수 함수로 둔 이유는 여기가 **터미널이 앱의
/// 세이브를 움직이는 유일한 입구**라서다 — 프로세스 둘을 띄우지 않고 전수 검증할 수 있어야 한다.
enum PokedoroRequestBus {
    /// 요청이 살아 있는 시간. 짧게 잡는 이유는 이 값이 곧 "앱이 꺼진 사이 쌓인 요청" 의 수명이기
    /// 때문이다. 터미널은 3초 기다렸다 포기하므로 그보다 여유만 있으면 된다.
    static let maximumAge: TimeInterval = 10

    /// 실행해야 하는가.
    ///
    /// ⓐ **나이**: 앱이 꺼진 사이 남은 요청을 그대로 실행하면, 사용자가 세 시간 전에 포기한
    /// 90분 집중이 앱을 켜는 순간 시작된다. 어긋남은 양쪽 대칭으로 본다 — 앞으로 어긋난 값만
    /// 통과시키면 시각을 미래로 적은 요청 하나로 이 제한을 통째로 우회할 수 있다.
    ///
    /// ⓑ **id**: 앱은 1초마다 이 파일을 보고 파일은 지워지지 않는다. 마지막으로 실행한 id 를
    /// 기억하지 않으면 같은 요청이 매 틱마다 다시 실행된다.
    static func shouldExecute(_ request: PokedoroRequest, now: Date, lastExecutedID: UUID?) -> Bool {
        guard request.id != lastExecutedID else { return false }
        return abs(now.timeIntervalSince(request.requestedAt)) <= maximumAge
    }
}
