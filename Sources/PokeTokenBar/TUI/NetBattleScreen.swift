import Foundation

/// 지금 LAN 대전을 터미널에 보여 주기 위해 **앱이 모아 주는 값 한 벌.**
///
/// `BattleCenter` 를 그대로 넘기지 않는 이유는 둘이다. ⓐ 그 타입은 소켓·타이머·관찰을 들고 있어
/// 순수 함수의 입력이 될 수 없다. ⓑ 값으로 끊어 두면 투영을 **프로세스 없이 전수 검증**할 수 있다
/// (`TUIHomeModel` 이 스토어를 끊어 낸 것과 같은 이유).
struct BattleTerminalState {
    var phase: BattleCenter.Phase
    var battle: NetBattleState?
    /// 이번 턴이 끝나기까지 남은 초. `nil` 이면 마감이 없다(대전 밖이거나 이미 낸 뒤).
    ///
    /// 초로 접어 넘기는 이유는 **터미널이 시계를 다시 계산하지 않게** 하기 위해서다 — 마감 시각을
    /// 넘기면 두 프로세스가 각자 남은 시간을 세고, 파일이 오래된 만큼 어긋난 값을 그린다.
    var remainingSeconds: Int?
}

/// LAN 대전을 터미널 한 판으로 접는다. **부수효과 없음** — 값 하나만 읽는다.
///
/// 웨이브 런(`WaveRunScreen`)과 짝을 이루지만 통로가 다르다: 그쪽은 세이브에서 읽고 이쪽은 앱이
/// 화면 채널로 내놓는다. 규칙은 같다 — 지금 누를 수 있는 것만 안내하고, 목록에 없는 번호는
/// 요청이 되지 않는다.
enum NetBattleScreen {
    /// 지금 **숫자 키가 무엇이 되는가.**
    enum Kind: Equatable, Sendable {
        /// 대전이 없다. 화면을 내놓지 않는 조건이기도 하다.
        case none
        /// 신청을 받았다 — **거절만** 여기서 한다. 수락은 6마리 후보를 고르는 화면으로 이어지고
        /// 그 화면은 앱에만 있다.
        case incoming
        /// 파티 편성처럼 앱에서만 하는 국면. 진행 중이라는 사실은 보여 준다.
        case appOnly
        /// 내 차례 — 숫자 키가 기술이다.
        case move
        /// 쓰러진 자리를 먼저 메운다. 숫자 키가 팀 번호다.
        case sendOut
        /// 이미 냈다 — 상대를 기다린다.
        case waiting
        case finished
    }

    struct Choice: Equatable, Sendable {
        var number: Int
        var label: String
    }

    // MARK: 국면

    static func kind(_ state: BattleTerminalState) -> Kind {
        switch state.phase {
        case .ready:    return .none
        case .incoming: return .incoming
        case .preparing, .challenging, .poolSelecting, .poolBuilding, .teamBuilding, .waitingTeam:
            return .appOnly
        case .finished: return .finished
        case .battling:
            guard let battle = state.battle else { return .appOnly }
            // 쓰러진 자리를 메우는 교체는 **턴 행동이 아니다**(`NetBattleState.replaceFainted`).
            // 그 상태에서 기술을 권하면 `canChoose` 가 거절해 눌러도 아무 일이 없다.
            if !battle.me.isAlive { return .sendOut }
            return battle.myAction == nil ? .move : .waiting
        }
    }

    /// 지금 유효한 번호. **이 목록이 진실이고 라벨도 요청도 여기서 파생된다.**
    static func numbers(_ state: BattleTerminalState) -> [Int] {
        guard let battle = state.battle else { return [] }
        switch kind(state) {
        case .move:
            // 쓸 수 있는 기술이 하나도 없으면 발버둥 하나다 — `chooseMove` 가 −1 로 접는다.
            guard !battle.mustStruggle else { return [1] }
            return battle.me.moves.indices.filter { battle.me.canUse(moveAt: $0) }.map { $0 + 1 }
        case .sendOut:
            return battle.myTeam.indices
                .filter { $0 != battle.myActive && battle.myTeam[$0].isAlive }
                .map { $0 + 1 }
        case .none, .incoming, .appOnly, .waiting, .finished:
            return []
        }
    }

    static func choices(_ state: BattleTerminalState, language: AppLanguage) -> [Choice] {
        numbers(state).map { Choice(number: $0, label: label($0, in: state, language: language)) }
    }

    /// 숫자 하나 → 앱에 보낼 요청. **목록에 없는 번호는 요청이 되지 않는다**(제안 ⊆ 실행 가능).
    static func action(number: Int, in state: BattleTerminalState) -> PokedoroRequest.Action? {
        guard numbers(state).contains(number) else { return nil }
        switch kind(state) {
        case .move:    return .battleMove(move: number)
        case .sendOut: return .battleSwitch(number: number)
        case .none, .incoming, .appOnly, .waiting, .finished: return nil
        }
    }

    // MARK: 안내

    /// 머리글. 채널의 `title` 이 되고 `watch` 의 첫 줄이 된다.
    static func title(_ state: BattleTerminalState) -> String {
        switch state.phase {
        case .ready: "대전 없음"
        case .incoming(let peer): "\(peer) 의 대전 신청"
        case .challenging(let peer): "\(peer) 에게 신청 중"
        case .preparing: "대전 준비 중"
        case .poolSelecting, .poolBuilding: "후보 6마리 고르는 중"
        case .teamBuilding, .waitingTeam: "파티 편성 중"
        case .battling: "LAN 대전"
        case .finished: "대전 종료"
        }
    }

    /// **지금 누를 수 있는 키만.** 이 배열이 그대로 채널의 `keys` 가 된다 — 무엇을 할 수 있는지
    /// 아는 곳이 앱이고, 터미널이 따로 판정하면 두 표가 갈라져 먹지도 않는 키를 권한다.
    static func keys(_ state: BattleTerminalState) -> [String] {
        switch kind(state) {
        case .move:
            return ["1-\(max(1, numbers(state).count)) 기술", "f 항복"]
        case .sendOut:
            return ["1-\(max(1, state.battle?.myTeam.count ?? 1)) 교체", "f 항복"]
        case .incoming:
            return ["n 거절"]
        case .waiting:
            return ["f 항복"]
        case .none, .appOnly, .finished:
            return []
        }
    }

    /// 한 줄 안내. 명령까지 함께 적는다 — `watch` 밖에서도 같은 일을 할 수 있어야 한다.
    static func hints(_ state: BattleTerminalState) -> String {
        switch kind(state) {
        case .none:
            return "진행 중인 대전이 없다 — 신청은 앱의 친구 탭에서 한다"
        case .incoming:
            return "n 거절   (수락은 앱에서 — 후보 6마리를 골라야 한다)"
        case .appOnly:
            return "앱에서 이어 한다 — 파티 편성은 터미널에 입력 줄이 없다"
        case .move:
            return "1-\(max(1, numbers(state).count)) 기술   f 항복   (battle move <n>)"
        case .sendOut:
            return "쓰러졌다 — 교체할 번호를 고른다 (battle switch <번호>)"
        case .waiting:
            return "상대의 행동을 기다린다"
        case .finished:
            return "대전이 끝났다 — 다음 판은 앱에서 시작한다"
        }
    }

    // MARK: 줄

    static func lines(_ state: BattleTerminalState, language: AppLanguage,
                      width: Int) -> [String] {
        let inner = max(1, width)
        var lines = [TUIRender.row(left: title(state), right: clock(state), width: inner)]
        lines.append(TUIRender.rule(width: inner))
        guard let battle = state.battle else {
            lines.append(TUIText.truncate(standingLine(state), to: inner))
            return lines
        }
        lines.append(cell("상대", battle.opp, width: inner))
        lines.append(cell("나", battle.me, width: inner))
        // 남은 팀은 한 줄로 접는다 — 몇 마리가 남았는지가 교체 판단의 전부다.
        if battle.myTeam.count > 1 {
            lines.append(TUIText.truncate("팀   " + battle.myTeam.enumerated().map { index, side in
                "\(index + 1)\(side.isAlive ? "" : "✗")"
            }.joined(separator: " "), to: inner))
        }
        let log = self.log(battle, language: language).suffix(logTail)
        if !log.isEmpty {
            lines.append(TUIRender.rule(width: inner))
            lines += log.map { TUIText.truncate($0, to: inner) }
        }
        let offered = choices(state, language: language)
        if !offered.isEmpty {
            lines.append(TUIRender.rule(width: inner))
            lines += offered.map { TUIText.truncate("\($0.number) \($0.label)", to: inner) }
        }
        return lines
    }

    /// 판이 없는 국면의 한 줄. **무엇을 기다리는지와 어디서 하는지**를 말한다 — 빈 화면을 그리면
    /// 사용자는 대전이 끊긴 줄 안다.
    private static func standingLine(_ state: BattleTerminalState) -> String {
        switch state.phase {
        case .ready:
            return "진행 중인 대전이 없다. 신청은 앱의 친구 탭에서 한다."
        case .incoming(let peer):
            return "\(peer) 가 대전을 걸었다. 수락은 앱에서(후보 6마리), 거절은 여기서."
        case .challenging(let peer):
            return "\(peer) 의 응답을 기다린다."
        case .finished(let iWon, let byForfeit):
            if byForfeit { return iWon == true ? "상대가 항복했다." : "항복했다 — 이 판은 졌다." }
            switch iWon {
            case true?:  return "이겼다!"
            case false?: return "졌다."
            default:     return "무승부다."
            }
        default:
            return "앱에서 이어 한다 — \(title(state))."
        }
    }

    /// 남은 시간. **앱이 접어 준 초를 그대로 쓴다** — 터미널이 다시 세면 파일이 오래된 만큼
    /// 어긋난 값을 그리고, 사용자는 없는 시간을 믿는다.
    private static func clock(_ state: BattleTerminalState) -> String {
        guard let remaining = state.remainingSeconds else { return "" }
        return "남은 \(max(0, remaining))초"
    }

    private static func cell(_ side: String, _ combatant: BattleSide, width: Int) -> String {
        let status = combatant.status.map { " [\(WaveRunScreen.statusName($0))]" } ?? ""
        let left = "\(side)   \(combatant.snapshot.name) Lv.\(combatant.snapshot.level)\(status)"
        let gauge = TUIRender.bar(
            progress: Double(max(0, combatant.hp)) / Double(max(1, combatant.stats.hp)), width: 10)
        return TUIRender.row(left: left,
                             right: "\(gauge) \(max(0, combatant.hp))/\(combatant.stats.hp)",
                             width: width)
    }

    private static let logTail = 4

    /// 이벤트 → 사람이 읽는 줄. **턴이 벌어졌을 때의 문맥으로** 이름·기술을 해석하는 자리는
    /// `BattleLogSource.netBattle` 하나다 — 활성 개체가 바뀐 뒤의 이름으로 옛 줄을 그리면
    /// 지나간 턴이 엉뚱한 포켓몬 이야기가 된다.
    static func log(_ battle: NetBattleState, language: AppLanguage) -> [String] {
        BattleLogSource.netBattle(battle, mine: battle.iAmA ? .a : .b, l: L(language))
            .map(\.text)
    }

    // MARK: 라벨

    private static func label(_ number: Int, in state: BattleTerminalState,
                              language: AppLanguage) -> String {
        guard let battle = state.battle else { return "" }
        switch kind(state) {
        case .move:
            guard !battle.mustStruggle else { return MoveSpec.struggle().name(language) }
            let index = number - 1
            guard battle.me.moves.indices.contains(index) else { return "" }
            let remaining = battle.me.pp.indices.contains(index) ? battle.me.pp[index] : 0
            return "\(battle.me.moves[index].name(language))  \(remaining)/\(battle.me.moves[index].pp)"
        case .sendOut:
            let index = number - 1
            guard battle.myTeam.indices.contains(index) else { return "" }
            let member = battle.myTeam[index]
            return "\(member.snapshot.name) Lv.\(member.snapshot.level)  \(member.hp)/\(member.stats.hp)"
        // 라벨은 `choices` 가 `numbers` 를 돌며 부르고, 이 국면들의 `numbers` 는 비어 있다 —
        // switch 를 닫기 위한 자리다.
        case .none, .incoming, .appOnly, .waiting, .finished:
            return ""
        }
    }
}
