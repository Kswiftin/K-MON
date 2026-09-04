import Foundation

/// 트랙 게임의 방향 입력 — **닫힌 목록**이다.
///
/// 포켓슬론(`PokeathlonInput`)과 OX 퀴즈(`PokemonOXInput`)는 센터에서 서로 다른 타입을 쓰지만,
/// 사용자가 하는 일은 같다: **한 축을 좌우로 움직인다.** 퀴즈의 O/X 가 레인 좌우와 같은 축이라
/// 터미널은 하나로 받고, 어느 센터 함수로 가는지는 창구가 정한다(`submitTrackInput`).
///
/// 이름이 `left`/`right` 인 이유: 뜻(`O`·`거짓`·`레인 0`)은 활동마다 다르지만 **입력의 모양**은
/// 같다. 뜻으로 이름을 붙이면(`agree`/`disagree`) 포켓슬론에서 그 이름이 거짓말이 된다.
enum ArenaTrackInput: String, Codable, Sendable, CaseIterable, Equatable {
    case left, right, run, swap
}

/// 두 사람이 팀을 데리고 붙는 판(체육관·토너먼트)의 터미널 값.
///
/// 두 컨텐츠를 한 값으로 받는 이유는 **상태가 구조적으로 같기** 때문이다 —
/// `GymMatchState` 와 `TournamentMatchState` 는 둘 다 이름 붙은 두 편, 각 편의
/// `[TournamentPokemonState]`, 나온 자리, 턴, 제출 집합, 승자를 든다(체육관 쪽 주석이 그렇게
/// 적혀 있다: "개체 표현은 `TournamentPokemonState` 를 그대로 쓴다").
struct DuelTerminalState: Equatable, Sendable {
    var myName: String
    var theirName: String
    /// 내 팀. **자리 번호는 팀 순서**(1부터)이고 교체 인자가 그 번호다.
    var mine: [ArenaScreen.Slot]
    var theirs: [ArenaScreen.Slot]
    var turn = 0
    var hasSubmitted = false
    /// 지금 나온 개체가 **낼 수 있는** 기술만. 번호는 엔진의 기술 순번(1부터)이라 PP 가 떨어진
    /// 자리는 목록에서 빠지고 번호에는 구멍이 남는다 — 다시 매기면 옆 기술이 나간다.
    var moves: [ArenaScreen.Move] = []
    var mustStruggle = false
    /// 머리글 오른쪽의 덧말 — 토너먼트의 라운드. 체육관에는 없다(`nil`).
    var caption: String?
    /// 내가 이 판의 **전투원**인가. 관전자는 누를 것이 없고, 내 팀 표시도 붙지 않는다 —
    /// 체육관·토너먼트 둘 다 관전이 되므로 이 갈래가 필요하다.
    var amFighting = true
    /// 승자 이름. `nil` 은 아직 안 끝났다.
    var winnerName: String?
    /// 내 승패. `nil` 은 줄 결과가 없다 — 관전자다.
    var iWon: Bool?

    init(myName: String, theirName: String,
         mine: [ArenaScreen.Slot], theirs: [ArenaScreen.Slot]) {
        self.myName = myName
        self.theirName = theirName
        self.mine = mine
        self.theirs = theirs
    }
}

/// 여럿이 한 축에서 겨루는 판(포켓슬론·OX 퀴즈)의 터미널 값.
struct TrackTerminalState: Equatable, Sendable {
    /// 순위. **번호는 이 목록의 자리**(1부터)이고 `room bet` 만 그 번호를 받는다 — 방향 키와
    /// 같은 숫자 공간에 두면 `3` 이 "전진" 이자 "3번 러너" 가 된다.
    var standings: [ArenaScreen.Runner]
    /// 내가 뛰는가. 관전자는 방향을 낼 수 없고 베팅만 한다.
    var amRacing = false
    /// **지금** 방향을 낼 수 있나. 퀴즈는 정답 공개 중에, 포켓슬론은 출발 전에 입력이 막힌다
    /// (`PokemonOXGame.move`·`PokeathlonRace.apply` 가 각자 먼저 본다). `amRacing` 과 갈라 둔
    /// 이유는 거절 문구가 다르기 때문이다 — 관전자는 베팅을 권하고, 러너는 기다리라고 한다.
    var canMove = true
    /// 퀴즈 문항. `nil` 이면 포켓슬론이다(문항이 없다).
    var question: String?
    /// 지금 내가 서 있는 쪽. 퀴즈는 `O`·`X`·가운데, 포켓슬론은 레인이다.
    var myChoice: String?
    /// 마감까지 남은 초. `nil` 은 마감이 없다.
    var secondsLeft: Int?
    /// 지금 걸 수 있나 — 관전자이고 원장이 아직 열려 있다(`PokeathlonPool.isClosed`).
    var canBet = false
    var pot = 0
    var myBet: ArenaScreen.Bet?
    var winnerName: String?

    init(standings: [ArenaScreen.Runner]) { self.standings = standings }
}

/// 결투와 트랙을 터미널 줄로 접는다. **부수효과 없음.**
///
/// `RoomScreen` 안에 넣지 않은 이유: 그 화면의 값은 `MultiplayerFighter` 목록 하나인데 여기 둘은
/// 형태가 아예 다르다. 화면(키·이동 글자)은 여전히 하나다 — `RoomScreen` 이 이 함수들을 부르고,
/// 넷 다 LAN 방에서 벌어지므로 새 `TUIScreen` 도 새 글자도 없다.
enum ArenaScreen {

    /// 팀의 한 자리.
    struct Slot: Equatable, Sendable {
        var number: Int
        var id: UUID
        var label: String
        var hp: Int
        var maxHP: Int
        var isActive: Bool
        var statusName: String?

        var isAlive: Bool { hp > 0 }

        init(number: Int, id: UUID, label: String, hp: Int, maxHP: Int,
             isActive: Bool, statusName: String? = nil) {
            self.number = number
            self.id = id
            self.label = label
            self.hp = hp
            self.maxHP = maxHP
            self.isActive = isActive
            self.statusName = statusName
        }
    }

    struct Move: Equatable, Sendable {
        var number: Int
        var label: String
        var pp: Int
        var maxPP: Int
    }

    /// 트랙의 한 참가자. **번호와 id 를 함께 든다** — 화면은 번호를 찍고 창구는 id 로 걸므로,
    /// 두 값을 따로 구하면 목록이 다시 읽히는 사이 엉뚱한 러너에게 판돈이 간다.
    struct Runner: Equatable, Sendable {
        var number: Int
        var id: UUID
        var label: String
        var right: String
        var isMine: Bool
    }

    struct Bet: Equatable, Sendable {
        var runnerName: String
        var amount: Int
    }

    // MARK: 결투 — 번호 공간 둘을 배타로 둔다

    /// 앞자리가 쓰러졌고 내보낼 자리가 남았나. **이 판정 하나가 두 번호 공간을 가른다** —
    /// 기술 번호와 교체 자리 번호가 한 화면에 동시에 살면 숫자 한 자리로 어느 쪽인지 정할 수 없다.
    static func mustReplace(_ duel: DuelTerminalState) -> Bool {
        guard let active = duel.mine.first(where: \.isActive), !active.isAlive else { return false }
        return duel.mine.contains { !$0.isActive && $0.isAlive }
    }

    /// 낼 수 있는 기술 번호. 발버둥은 **하나**다 — 목록에 남은 번호를 권하면 낼 수 없는 것을 권한다.
    static func moveNumbers(_ state: RoomTerminalState) -> [Int] {
        guard let duel = state.duel, RoomScreen.kind(state) == .duelMove else { return [] }
        guard !duel.mustStruggle else { return [1] }
        return duel.moves.map(\.number)
    }

    /// 지금 내보낼 수 있는 자리 번호 — **살아 있고 아직 안 나온** 자리다.
    static func replaceNumbers(_ state: RoomTerminalState) -> [Int] {
        guard let duel = state.duel else { return [] }
        return duel.mine.filter { !$0.isActive && $0.isAlive }.map(\.number)
    }

    /// 자리 번호 → 그 자리. 교체 거절 사유를 갈라 말하는 자리라 "없는 번호" 와 "못 쓰는 자리" 를
    /// 구분한다.
    static func slot(number: Int, in state: RoomTerminalState) -> Slot? {
        state.duel?.mine.first { $0.number == number }
    }

    // MARK: 트랙 — 방향은 한 축, 표는 한 벌

    /// 번호 → 방향. **접는 자리가 여기 하나뿐이다.**
    static let trackOrder: [ArenaTrackInput] = [.left, .right, .run, .swap]

    static func trackInput(number: Int) -> ArenaTrackInput? {
        guard trackOrder.indices.contains(number - 1) else { return nil }
        return trackOrder[number - 1]
    }

    /// 지금 뜻이 있는 방향만. 퀴즈에 전진·교체는 없다 — 권하면 눌러도 아무 일이 없다.
    static func trackInputs(_ state: RoomTerminalState) -> [ArenaTrackInput] {
        guard let track = state.track, track.amRacing, track.canMove,
              track.winnerName == nil else { return [] }
        switch state.activity {
        case .pokemonQuiz: return [.left, .right]
        case .pokeathlon:  return trackOrder
        default:           return []
        }
    }

    /// 방향 이름. 뜻이 활동마다 다르므로 **퀴즈인지 함께 받는다** — 한 이름으로 두면 퀴즈에서
    /// "왼 레인" 이 나오고 사용자는 무엇을 고르는지 모른다.
    static func trackName(_ input: ArenaTrackInput, quiz: Bool) -> String {
        switch input {
        case .left:  quiz ? "O (참)" : "왼 레인"
        case .right: quiz ? "X (거짓)" : "오른 레인"
        case .run:   "전진"
        case .swap:  "개체 교체"
        }
    }

    /// 러너 번호 → id. **접는 자리가 여기 하나뿐이다.**
    static func runnerID(number: Int, in state: RoomTerminalState) -> UUID? {
        state.track?.standings.first { $0.number == number }?.id
    }

    static func isQuiz(_ state: RoomTerminalState) -> Bool { state.activity == .pokemonQuiz }

    // MARK: 키와 안내

    static func duelKeys(_ state: RoomTerminalState) -> [String] {
        // **번호를 그대로 적는다.** `1-n` 으로 접으면 PP 가 떨어져 구멍이 난 번호가 눌러도 안
        // 되는 것으로 안내된다.
        let numbers = moveNumbers(state).map(String.init).joined(separator: "·")
        return numbers.isEmpty ? [] : ["\(numbers) 기술"]
    }

    static func replaceKeys(_ state: RoomTerminalState) -> [String] {
        let numbers = replaceNumbers(state).map(String.init).joined(separator: "·")
        return numbers.isEmpty ? [] : ["\(numbers) 교체"]
    }

    static func trackKeys(_ state: RoomTerminalState) -> [String] {
        let quiz = isQuiz(state)
        return trackInputs(state).compactMap { input in
            guard let number = trackOrder.firstIndex(of: input) else { return nil }
            return "\(number + 1) \(trackName(input, quiz: quiz))"
        }
    }

    static func duelHints(_ state: RoomTerminalState) -> String {
        let numbers = moveNumbers(state).map(String.init).joined(separator: "·")
        return "\(numbers) 기술   (room move <n>)   room switch <자리>   l 나가기"
    }

    static func replaceHints(_ state: RoomTerminalState) -> String {
        let numbers = replaceNumbers(state).map(String.init).joined(separator: "·")
        return "쓰러졌다 — \(numbers) 교체   (room switch <자리>)   l 나가기"
    }

    static func trackHints(_ state: RoomTerminalState) -> String {
        trackKeys(state).joined(separator: "   ") + "   l 나가기"
    }

    /// 누를 것이 없는 트랙의 안내. **사유가 셋이라 문구도 셋이다** — 하나로 접으면 원장이
    /// 없는 퀴즈에서 "원장이 닫혔다" 가 나오고, 걸 수 있는 관전자에게 기다리라고 한다.
    static func waitingHints(_ state: RoomTerminalState, _ track: TrackTerminalState) -> String {
        if track.canBet { return "관전 중이다 — room bet <러너> <금액> --yes   l 나가기" }
        if track.amRacing { return "지금은 낼 것이 없다 — 다음 차례를 기다린다   l 나가기" }
        guard state.activity == .pokeathlon else { return "관전 중이다 — 결과를 기다린다   l 나가기" }
        return "원장이 닫혔다 — 결과를 기다린다   l 나가기"
    }

    // MARK: 줄

    /// 언어를 받는 이유는 **발버둥 하나** 때문이다. 나머지 기술 이름은 창구가 조립할 때 이미
    /// 접었지만(`TerminalRoomControl.moves`), 발버둥은 목록이 비었을 때 화면이 만든다 —
    /// 여기서 `.ko` 로 못 박으면 일본어 사용자에게 한국어가 나간다(그 검사가 `LanguageSplitGuard`).
    static func duelLines(_ state: RoomTerminalState, _ duel: DuelTerminalState,
                          language: AppLanguage, width: Int) -> [String] {
        let turn = duel.turn > 0 ? "\(duel.turn) 턴" : ""
        var lines = [TUIRender.row(left: RoomScreen.title(state),
                                   right: [duel.caption, turn].compactMap { $0 }
                                       .filter { !$0.isEmpty }.joined(separator: " · "),
                                   width: width),
                     TUIRender.rule(width: width)]
        // 표시는 **내가 뛸 때만** 붙인다 — 관전자에게 붙이면 내 것이 아닌 팀이 내 것으로 읽힌다.
        let mark = duel.amFighting ? TUIRender.activeMark : " "
        lines.append(TUIText.truncate("\(mark) \(duel.myName)", to: width))
        lines += duel.mine.map { slotLine($0, width: width) }
        lines.append(TUIText.truncate("  \(duel.theirName)", to: width))
        lines += duel.theirs.map { slotLine($0, width: width) }
        if let ending = duelEnding(duel) {
            lines.append(TUIRender.rule(width: width))
            lines.append(TUIText.truncate(ending, to: width))
            return lines
        }
        let offered = duel.mustStruggle
            ? [Move(number: 1, label: MoveSpec.struggle().name(language), pp: 1, maxPP: 1)]
            : duel.moves
        guard duel.amFighting, !duel.hasSubmitted, !mustReplace(duel),
              !offered.isEmpty else { return lines }
        lines.append(TUIRender.rule(width: width))
        lines += offered.map {
            TUIRender.row(left: "\($0.number) \($0.label)",
                          right: "\(TUIRender.number($0.pp))/\(TUIRender.number($0.maxPP))",
                          width: width)
        }
        return lines
    }

    private static func slotLine(_ slot: Slot, width: Int) -> String {
        let mark = slot.isActive ? " \(TUIRender.activeMark)" : "  "
        let status = slot.statusName.map { " [\($0)]" } ?? ""
        let gauge = TUIRender.bar(progress: Double(max(0, slot.hp)) / Double(max(1, slot.maxHP)),
                                  width: 10)
        return TUIRender.row(left: "\(mark)\(slot.number) \(slot.label)\(status)",
                             right: "\(gauge) \(max(0, slot.hp))/\(slot.maxHP)", width: width)
    }

    /// 판이 끝난 줄. **승패는 앱이 판정한 값**을 쓴다 — HP 로 다시 세면 무승부·관전이 갈라진다.
    private static func duelEnding(_ duel: DuelTerminalState) -> String? {
        guard let winner = duel.winnerName else { return nil }
        guard let iWon = duel.iWon else { return "\(winner) 승" }
        return (iWon ? "이겼다!" : "졌다.") + " \(winner) 승"
    }

    static func trackLines(_ state: RoomTerminalState, _ track: TrackTerminalState,
                           width: Int) -> [String] {
        var lines = [TUIRender.row(left: RoomScreen.title(state),
                                   right: track.secondsLeft.map { "\(max(0, $0))초" } ?? "",
                                   width: width),
                     TUIRender.rule(width: width)]
        if let question = track.question {
            lines.append(TUIText.truncate(question, to: width))
        }
        lines += track.standings.map {
            TUIRender.row(left: "\($0.isMine ? TUIRender.activeMark : " ") \($0.number) \($0.label)",
                          right: $0.right, width: width)
        }
        if let choice = track.myChoice {
            lines.append(TUIRender.row(left: "내 위치", right: choice, width: width))
        }
        // 판돈은 **관전 중일 때만** 낸다 — 러너는 걸 수 없고, 줄을 채우면 좁은 창에서 순위가 잘린다.
        if !track.amRacing {
            lines.append(TUIRender.rule(width: width))
            lines.append(TUIRender.row(left: "판돈", right: TUIRender.number(track.pot),
                                       width: width))
            if let bet = track.myBet {
                lines.append(TUIRender.row(left: "내 베팅  \(bet.runnerName)",
                                           right: TUIRender.number(bet.amount), width: width))
            }
        }
        if let winner = track.winnerName {
            lines.append(TUIRender.rule(width: width))
            lines.append(TUIText.truncate("\(winner) 우승", to: width))
        }
        return lines
    }
}
