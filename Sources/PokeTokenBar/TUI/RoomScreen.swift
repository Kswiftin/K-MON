import Foundation

/// 지금 LAN 방을 터미널에 보여 주기 위해 **앱이 모아 주는 값 한 벌.**
///
/// `MultiplayerRoomCenter` 를 그대로 넘기지 않는 이유는 `BattleTerminalState` 와 같다 — 그 타입은
/// listener·browser·타이머를 들고 있어 순수 함수의 입력이 될 수 없다.
struct RoomTerminalState {
    var phase: MultiplayerRoomCenter.Phase
    var activity: RoomActivity?
    /// **내 id.** 전투원 목록에서 나를 찾고, 대상 목록에서 나를 빼는 데 쓴다.
    var myID: UUID
    var round = 0
    var fighters: [MultiplayerFighter] = []
    var hasSubmitted = false
    var isHost = false
    /// 호스트가 지금 시작할 수 있나(`MultiplayerLobby.canStart`).
    var canStart = false
    var raidTier: RaidTier?
    /// 끝난 판의 내 승패. `nil` 은 "줄 결과가 없다" — 아직 안 끝났거나 관전자다.
    var outcome: BattleOutcome?
    /// 정산으로 받은 별의조각.
    var payout: Int?

    /// 지금 도는 **결투**(체육관·토너먼트). 이 값이 있으면 `fighters` 는 비어 있다 — 그 둘의 판은
    /// `combatFighters` 가 아니라 각자의 상태에 산다.
    var duel: DuelTerminalState?
    /// 지금 도는 **트랙**(포켓슬론·OX 퀴즈). 위와 같은 이유로 `fighters` 와 배타다.
    var track: TrackTerminalState?

    init(phase: MultiplayerRoomCenter.Phase, activity: RoomActivity? = nil, myID: UUID) {
        self.phase = phase
        self.activity = activity
        self.myID = myID
    }
}

/// LAN 방을 터미널 한 판으로 접는다. **부수효과 없음.**
///
/// 협동 레이드와 방 대전이 **같은 화면**인 이유는 둘이 같은 센터의 같은 국면(`.battling`)을 쓰기
/// 때문이다 — 활동 이름만 머리글에서 갈린다. 화면을 둘로 나누면 같은 규칙을 두 벌 쓰게 된다.
enum RoomScreen {
    enum Kind: Equatable, Sendable {
        /// 방에 없다.
        case none
        /// 로비 — 사람을 기다린다. 호스트만 시작할 수 있다.
        case lobby
        /// 내 차례 — 숫자 키가 기술이다.
        case move
        /// 결투(체육관·토너먼트)의 내 차례 — 숫자 키가 기술이다.
        case duelMove
        /// 결투에서 앞자리가 쓰러졌다 — **숫자 키가 팀 자리로 바뀐다.** 두 번호 공간을 배타로
        /// 두기 위해 국면을 갈랐다(`ArenaScreen.mustReplace`).
        case duelReplace
        /// 트랙(포켓슬론·퀴즈)에서 내가 뛴다 — 숫자 키가 방향이다.
        case trackMove
        /// 이미 냈거나, 쓰러져 있거나, 관전자다 — 누를 것이 없다.
        case waiting
        case finished
    }

    struct Choice: Equatable, Sendable {
        var number: Int
        var label: String
    }

    /// 때릴 수 있는 상대 하나. **번호와 id 를 함께 든다** — 화면은 번호를 찍고 실행기는 id 로
    /// 보내는데, 두 값을 따로 구하면 목록이 다시 읽히는 사이 엉뚱한 상대를 때린다.
    struct Target: Equatable, Sendable {
        var number: Int
        var id: UUID
        var label: String
    }

    // MARK: 국면

    /// **판의 유무가 국면보다 먼저다.** 체육관은 판이 도는 동안 `phase` 가 `.hosting` 그대로라
    /// (센터 주석: "체육관은 `phase` 가 `.hosting` 인 채로 판이 돈다 — 국면이 아니라 판의
    /// 유무로 가른다") 국면부터 보면 판 중에 로비를 그리고 시작 키를 권한다.
    static func kind(_ state: RoomTerminalState) -> Kind {
        if let duel = state.duel { return duelKind(duel) }
        if let track = state.track { return trackKind(track) }
        switch state.phase {
        case .idle, .creating, .joining: return .none
        case .hosting, .joined:          return .lobby
        case .battling, .pokeathlon, .pokemonQuiz, .tournament:
            // 끝난 판은 결과 화면이다. 판정은 `MultiplayerBattle.outcome` 이 하고 앱이 실어 준다.
            if state.outcome != nil { return .finished }
            guard let me = state.fighters.first(where: { $0.id == state.myID }), me.isAlive
            else { return .waiting }
            return state.hasSubmitted ? .waiting : .move
        }
    }

    private static func duelKind(_ duel: DuelTerminalState) -> Kind {
        if duel.winnerName != nil { return .finished }
        // 관전자와 이미 낸 쪽은 같은 국면이다 — `.waiting` 의 뜻이 원래 그 둘을 함께 든다.
        if !duel.amFighting || duel.hasSubmitted { return .waiting }
        return ArenaScreen.mustReplace(duel) ? .duelReplace : .duelMove
    }

    private static func trackKind(_ track: TrackTerminalState) -> Kind {
        if track.winnerName != nil { return .finished }
        // 관전자와 입력이 막힌 순간(정답 공개·출발 전)은 `.waiting` 이다 — 방향을 권하면
        // 눌러도 아무 일이 없고, 안내가 사유를 갈라 말한다.
        return track.amRacing && track.canMove ? .trackMove : .waiting
    }

    static func numbers(_ state: RoomTerminalState) -> [Int] {
        guard kind(state) == .move,
              let me = state.fighters.first(where: { $0.id == state.myID }) else { return [] }
        guard !me.side.mustStruggle else { return [1] }
        return me.side.moves.indices.filter { me.side.canUse(moveAt: $0) }.map { $0 + 1 }
    }

    /// 때릴 수 있는 상대. **나를 뺀 살아 있는 전투원**이다 — 협동 레이드는 보스 하나, 방 대전은 여럿.
    static func targets(_ state: RoomTerminalState) -> [Target] {
        state.fighters
            .filter { $0.id != state.myID && $0.isAlive }
            .enumerated()
            .map { index, fighter in
                Target(number: index + 1, id: fighter.id,
                       label: "\(fighter.trainerName)  \(fighter.side.hp)/\(fighter.side.stats.hp)")
            }
    }

    /// 대상 번호 → id. **접는 자리가 여기 하나뿐이다** — 화면이 찍은 번호와 실행기가 보내는 id 가
    /// 서로 다른 목록에서 나오면 사용자가 고른 것과 다른 상대를 때린다.
    static func targetID(number: Int, in state: RoomTerminalState) -> UUID? {
        targets(state).first { $0.number == number }?.id
    }

    static func choices(_ state: RoomTerminalState, language: AppLanguage) -> [Choice] {
        guard let me = state.fighters.first(where: { $0.id == state.myID }) else { return [] }
        return numbers(state).map { number in
            guard !me.side.mustStruggle else {
                return Choice(number: number, label: MoveSpec.struggle().name(language))
            }
            let index = number - 1
            // **닿지 않는다** — 번호는 `numbers` 가 `moves.indices` 에서 만든 값이다. switch 없이
            // 첨자를 쓰는 자리라 방어로 남긴다(커버리지에서 `^0` 으로 보인다).
            guard me.side.moves.indices.contains(index) else {
                return Choice(number: number, label: "")
            }
            let remaining = me.side.pp.indices.contains(index) ? me.side.pp[index] : 0
            return Choice(number: number,
                          label: "\(me.side.moves[index].name(language))  \(remaining)/\(me.side.moves[index].pp)")
        }
    }

    /// 숫자 하나 → 요청. **대상은 싣지 않는다**(기본은 첫 상대) — 여럿일 때 고르는 것은 명령
    /// (`room move <n> <대상>`)의 몫이다. 이 화면에는 입력 줄이 없어 두 값을 연달아 받을 수 없다.
    static func action(number: Int, in state: RoomTerminalState) -> PokedoroRequest.Action? {
        switch kind(state) {
        case .move:
            guard numbers(state).contains(number) else { return nil }
            return .roomMove(move: number, target: nil)
        // 결투도 **같은 동작**을 쓴다 — 사용자에게는 "내 차례에 n번 기술" 하나이고, 어느 창구
        // 함수로 가는지는 실행기가 판을 보고 정한다. 동작을 갈라 두면 명령도 갈라야 한다.
        case .duelMove:
            guard ArenaScreen.moveNumbers(state).contains(number) else { return nil }
            return .roomMove(move: number, target: nil)
        case .duelReplace:
            guard ArenaScreen.replaceNumbers(state).contains(number) else { return nil }
            return .roomSwitch(slot: number)
        case .trackMove:
            guard let input = ArenaScreen.trackInput(number: number),
                  ArenaScreen.trackInputs(state).contains(input) else { return nil }
            return .roomTrack(input)
        case .none, .lobby, .waiting, .finished:
            return nil
        }
    }

    // MARK: 안내

    static func title(_ state: RoomTerminalState) -> String {
        let name = activityName(state.activity)
        guard let tier = state.raidTier, state.activity == .raid else { return name }
        return "\(name) \(tier.rawValue)★"
    }

    private static func activityName(_ activity: RoomActivity?) -> String {
        switch activity {
        case .raid: "협동 레이드"
        case .battle: "방 대전"
        case .gym: "체육관"
        case .tournament: "토너먼트"
        case .pokeathlon: "포켓슬론"
        case .pokemonQuiz: "OX 퀴즈"
        case nil: "LAN 방"
        }
    }

    /// **지금 누를 수 있는 키만.** 호스트가 아니거나 사람이 덜 모였으면 시작 키를 빼는 이유는
    /// `startRaid` 가 그 두 조건을 먼저 보기 때문이다 — 권해도 눌러도 아무 일이 없다.
    static func keys(_ state: RoomTerminalState) -> [String] {
        switch kind(state) {
        case .lobby:
            return (canStartNow(state) ? ["s 시작"] : []) + ["l 나가기"]
        case .move:
            return ["1-\(max(1, numbers(state).count)) 기술", "l 나가기"]
        case .duelMove:
            return ArenaScreen.duelKeys(state) + ["l 나가기"]
        case .duelReplace:
            return ArenaScreen.replaceKeys(state) + ["l 나가기"]
        case .trackMove:
            return ArenaScreen.trackKeys(state) + ["l 나가기"]
        case .waiting:
            return ["l 나가기"]
        case .none, .finished:
            return []
        }
    }

    /// 호스트가 지금 시작할 수 있나. **활동이 시작되는 종류인지까지 본다** — 체육관은 호스트가
    /// 시작하지 않는다(도전이 와야 판이 선다). 예전엔 그 방에서도 `s 시작` 을 권했고, 눌러도
    /// 아무 일이 없었다.
    static func canStartNow(_ state: RoomTerminalState) -> Bool {
        state.isHost && state.canStart && state.activity?.isHostStarted == true
    }

    static func hints(_ state: RoomTerminalState) -> String {
        switch kind(state) {
        case .none:
            return "방에 없다 — 방을 만들거나 찾는 일은 앱에서 한다(소켓)"
        case .lobby:
            guard state.isHost else { return "호스트가 시작할 때까지 기다린다   l 나가기" }
            if canStartNow(state) { return "s 시작   l 나가기" }
            // 시작이 없는 활동과 사람이 덜 모인 것은 **다음에 할 일이 다르다.**
            guard state.activity?.isHostStarted == true else {
                return "도전자가 오면 판이 선다 — 여는 일은 앱에서 한다   l 나가기"
            }
            return "사람을 더 기다린다   l 나가기"
        case .move:
            return "1-\(max(1, numbers(state).count)) 기술   (room move <n> [대상])   l 나가기"
        case .duelMove:
            return ArenaScreen.duelHints(state)
        case .duelReplace:
            return ArenaScreen.replaceHints(state)
        case .trackMove:
            return ArenaScreen.trackHints(state)
        case .waiting:
            // 트랙은 사유가 셋이다(걸 수 있는 관전 · 러너의 대기 · 닫힌 원장) — 나눠 말한다.
            if let track = state.track { return ArenaScreen.waitingHints(state, track) }
            // 결투의 관전자에게 "이번 라운드는 기다린다" 는 거짓말이다 — 낼 차례가 오지 않는다.
            if let duel = state.duel, !duel.amFighting {
                return "관전 중이다 — 판이 끝날 때까지 볼 수 있다   l 나가기"
            }
            return "이번 라운드는 기다린다   l 나가기"
        case .finished:
            return "판이 끝났다 — 다음 방은 앱에서 연다"
        }
    }

    // MARK: 줄

    static func lines(_ state: RoomTerminalState, language: AppLanguage, width: Int) -> [String] {
        let inner = max(1, width)
        // 형태가 다른 판은 형태별로 접는다 — 전투원 목록으로 그리려 하면 빈 목록이 되어
        // "판을 준비하는 중이다" 가 판이 끝날 때까지 남는다(#252 가 그랬다).
        if let duel = state.duel {
            return ArenaScreen.duelLines(state, duel, language: language, width: inner)
        }
        if let track = state.track { return ArenaScreen.trackLines(state, track, width: inner) }
        var lines = [TUIRender.row(left: title(state),
                                   right: state.round > 0 ? "\(state.round) 라운드" : "",
                                   width: inner)]
        lines.append(TUIRender.rule(width: inner))
        guard !state.fighters.isEmpty else {
            lines.append(TUIText.truncate(standingLine(state), to: inner))
            return lines
        }
        // 나를 먼저 찍는다 — 내 HP 가 이 판에서 가장 자주 보는 값이다.
        for fighter in state.fighters.sorted(by: { lhs, _ in lhs.id == state.myID }) {
            lines.append(cell(fighter, mine: fighter.id == state.myID, width: inner))
        }
        if let ending = endingLine(state) {
            lines.append(TUIRender.rule(width: inner))
            lines.append(TUIText.truncate(ending, to: inner))
            return lines
        }
        let offered = choices(state, language: language)
        if !offered.isEmpty {
            lines.append(TUIRender.rule(width: inner))
            lines += offered.map { TUIText.truncate("\($0.number) \($0.label)", to: inner) }
            // 대상이 둘 이상일 때만 목록을 찍는다 — 보스 하나짜리 레이드에서는 고를 것이 없다.
            let all = targets(state)
            if all.count > 1 {
                lines.append(TUIText.truncate(
                    "대상  " + all.map { "\($0.number) \($0.label)" }.joined(separator: "  "),
                    to: inner))
            }
        }
        return lines
    }

    private static func standingLine(_ state: RoomTerminalState) -> String {
        switch kind(state) {
        case .none:  "방에 없다. 방을 만들거나 찾는 것은 앱에서 한다."
        case .lobby: state.isHost ? "방을 열었다. 참가자를 기다린다." : "방에 들어왔다. 호스트를 기다린다."
        default:     "판을 준비하는 중이다."
        }
    }

    private static func endingLine(_ state: RoomTerminalState) -> String? {
        guard let outcome = state.outcome else { return nil }
        let head: String
        switch outcome {
        case .win:  head = "이겼다!"
        case .loss: head = "졌다."
        case .draw: head = "무승부다."
        }
        guard let payout = state.payout, payout > 0 else { return head }
        return head + " 별의조각 +\(TUIRender.number(payout))"
    }

    private static func cell(_ fighter: MultiplayerFighter, mine: Bool, width: Int) -> String {
        let mark = mine ? TUIRender.activeMark + " " : "  "
        let status = fighter.side.status.map { " [\(WaveRunScreen.statusName($0))]" } ?? ""
        let gauge = TUIRender.bar(
            progress: Double(max(0, fighter.side.hp)) / Double(max(1, fighter.side.stats.hp)),
            width: 10)
        return TUIRender.row(left: "\(mark)\(fighter.trainerName)\(status)",
                             right: "\(gauge) \(max(0, fighter.side.hp))/\(fighter.side.stats.hp)",
                             width: width)
    }
}
