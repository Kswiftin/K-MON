import Foundation

/// 웨이브 런을 터미널 한 판으로 접는다. **부수효과 없음** — `RogueRun` 하나만 읽는다.
///
/// 판이 세이브에 남으므로(`CompanionStore.rogueRun`) 터미널이 **스스로 읽는다.** 화면 채널
/// (`PokedoroViewChannel`)로 나르지 않는 이유가 그것이다 — 그 통로는 세이브에 **없는** 값
/// (집중 타이머처럼 앱 메모리에만 사는 것)을 위한 자리고, 세이브에 있는 값까지 실어 나르면
/// 같은 진실이 두 경로로 흐른다.
///
/// 조회(`pokedoro wave`)와 전체 화면(`watch`)이 **같은 함수를 읽는다.** 두 곳이 각자 조립하면
/// 한쪽에만 있는 줄이 생기고, 그걸 알아챌 방법은 둘을 손으로 맞대 보는 것뿐이다.
enum WaveRunScreen {
    /// 지금 **숫자 키가 무엇이 되는가.** 국면마다 다르므로 화면이 이 값으로 안내를 고른다.
    enum Kind: Equatable, Sendable {
        /// 누를 숫자가 없다 — 판이 없거나, 끝났거나, 이번 턴의 입력이 이미 다 찼다.
        case none
        case move
        /// 쓰러진 칸을 **먼저 채워야 한다**(`slotsNeedingSendOut`). 그 전에는 행동을 받지 않으므로
        /// 기술을 권하면 눌러도 아무 일이 안 일어난다.
        case sendOut
        case offer
        case route
        /// 다음 웨이브 상대를 받는 중. 앱이 네트워크를 지나는 동안이라 누를 것이 없다.
        case loading
    }

    /// 지금 고를 수 있는 것 하나. `number` 는 **사람이 세는 번호**이고, 교체는 그 번호가 곧
    /// 파티 번호다 — 목록 순번을 따로 매기면 화면과 명령이 서로 다른 번호를 쓴다(개체 번호와
    /// 같은 부류의 함정).
    struct Choice: Equatable, Sendable {
        var number: Int
        var label: String
    }

    // MARK: 국면

    static func kind(_ run: RogueRun?) -> Kind {
        guard let run else { return .none }
        switch run.stage {
        case .battling:
            if !run.battle.slotsNeedingSendOut.isEmpty { return .sendOut }
            return run.battle.slotsAwaitingAction.isEmpty ? .none : .move
        case .picking:     return .offer
        case .routing:     return .route
        case .loadingWave: return .loading
        case .cleared, .failed: return .none
        }
    }

    /// 지금 유효한 번호. **이 목록이 진실이고 라벨도 요청도 여기서 파생된다** — 안내와 실행이
    /// 각자 유효성을 판단하면 눌러도 거절만 돌아오는 키를 화면이 권하게 된다.
    static func numbers(_ run: RogueRun?) -> [Int] {
        guard let run else { return [] }
        switch kind(run) {
        case .move:
            guard let side = actingSide(run) else { return [] }
            // 쓸 수 있는 기술이 하나도 없으면 발버둥 하나다 — `WaveBattle.choose` 가 그 자리에서
            // 접으므로 번호는 그대로 1 이다.
            guard !side.mustStruggle else { return [1] }
            return side.moves.indices.map { $0 + 1 }
        case .sendOut:
            return run.battle.benchCandidates.map { $0 + 1 }
        case .offer:
            return run.offers.indices.map { $0 + 1 }
        case .route:
            return RunRoute.allCases.indices.map { $0 + 1 }
        case .none, .loading:
            return []
        }
    }

    static func choices(_ run: RogueRun?, language: AppLanguage) -> [Choice] {
        guard let run else { return [] }
        let l = L(language)
        return numbers(run).map { number in
            Choice(number: number, label: label(number, in: run, l: l))
        }
    }

    /// 숫자 하나 → 앱에 보낼 요청. **목록에 없는 번호는 요청이 되지 않는다**(제안 ⊆ 실행 가능).
    static func action(number: Int, in run: RogueRun?) -> PokedoroRequest.Action? {
        guard let run, numbers(run).contains(number) else { return nil }
        switch kind(run) {
        case .move:    return .waveMove(move: number, target: nil)
        case .sendOut: return .waveSwitch(number: number)
        case .offer:   return .wavePick(number: number)
        case .route:   return .waveRoute(RunRoute.allCases[number - 1])
        case .none, .loading: return nil
        }
    }

    /// 지금 누를 수 있는 것만 적는 한 줄. 화면 안내와 명령 안내가 같은 값을 읽는다.
    static func hints(_ run: RogueRun?) -> String {
        switch kind(run) {
        case .none:
            return run == nil ? "wave start 로 새 판" : "판이 끝났다 — wave start 로 새 판"
        case .move:
            return "1-4 기술   t 잡기   f 판 포기   (wave move <n> [상대])"
        case .sendOut:
            return "쓰러진 칸을 먼저 채운다 — wave switch <파티 번호>"
        case .offer:
            return "1-\(RogueRun.offerCount) 보상 고르기   (wave pick <n>)"
        case .route:
            return "1-\(RunRoute.allCases.count) 길 고르기   (wave route <"
                + RunRoute.allCases.map(\.rawValue).joined(separator: "|") + ">)"
        case .loading:
            return "다음 상대를 받는 중…"
        }
    }

    // MARK: 줄

    /// 판 한 장. 모든 줄이 `width` 를 넘지 않는다 — 넘치면 터미널이 줄을 접어 다음 줄을 밀어내고,
    /// 전체 다시 그리기 방식에서는 그 밀림이 복구되지 않는다.
    static func lines(_ run: RogueRun?, language: AppLanguage, width: Int) -> [String] {
        let inner = max(1, width)
        guard let run else { return idleLines(width: inner) }
        var lines = [TUIRender.row(left: header(run), right: tally(run), width: inner)]
        lines.append(TUIRender.rule(width: inner))
        lines += field(run, width: inner)
        if let ending = endingLine(run) {
            lines.append("")
            lines.append(TUIText.truncate(ending, to: inner))
            return lines
        }
        let log = self.log(run, language: language).suffix(logTail)
        if !log.isEmpty {
            lines.append(TUIRender.rule(width: inner))
            lines += log.map { TUIText.truncate($0, to: inner) }
        }
        let offered = choices(run, language: language)
        if !offered.isEmpty {
            lines.append(TUIRender.rule(width: inner))
            lines += offered.map { TUIText.truncate("\($0.number) \($0.label)", to: inner) }
        }
        return lines
    }

    /// 판이 없을 때. **없다고 말하고 여는 법을 알려 준다** — 빈 화면을 그리면 고장으로 읽힌다.
    ///
    /// 스타터를 번호와 종 번호로만 찍는 이유는 이름이 **네트워크에서** 오기 때문이다
    /// (`resolveSpeciesName`). 짧게 살다 죽는 조회 명령은 그 왕복을 기다릴 수 없고, 기다리게
    /// 하면 목록 하나 보려고 몇 초를 쓴다. 판이 열리면 파티 이름은 앱이 실어 둔 값으로 보인다.
    private static func idleLines(width: Int) -> [String] {
        [
            "진행 중인 웨이브 런이 없다.",
            "",
            "새 판: pokedoro wave start [번호]",
            "스타터  " + RogueRun.starterPool.enumerated()
                .map { String(format: "%d #%04d", $0.offset + 1, $0.element) }
                .joined(separator: "  "),
        ].map { TUIText.truncate($0, to: width) }
    }

    private static func header(_ run: RogueRun) -> String {
        let boss = RogueRun.isBoss(wave: run.wave) ? " · 보스" : ""
        let route = run.route == .risky ? " · 험한 길" : ""
        return "웨이브 \(run.wave)/\(RogueRun.finalWave)\(boss)\(route)"
    }

    private static func tally(_ run: RogueRun) -> String {
        "볼 \(run.balls)  파티 \(run.party.count)/\(RogueRun.partyLimit)"
    }

    /// 필드 두 편. **쓰러진 개체도 그 자리에 남는다**(`WaveBattle.FieldSlot`) — 지우면 무엇이
    /// 눕었는지가 화면에서 사라지고, 채워야 할 칸이 몇 번인지도 알 수 없다.
    private static func field(_ run: RogueRun, width: Int) -> [String] {
        let theirs = run.battle.opponentField.indices.compactMap { ordinal -> String? in
            run.battle.opponentSide(at: ordinal).map { cell("상대 \(ordinal + 1)", $0, width: width) }
        }
        let mine = run.battle.myField.indices.compactMap { ordinal -> String? in
            run.battle.mySide(at: ordinal).map { cell("내 \(ordinal + 1)", $0, width: width) }
        }
        return theirs + mine
    }

    /// 칸 하나 — 이름·레벨·HP. HP 를 숫자와 막대로 **함께** 내는 이유는 막대만으로는 한 대 더
    /// 버티는지 알 수 없고, 숫자만으로는 훑어볼 수 없어서다.
    private static func cell(_ slot: String, _ side: BattleSide, width: Int) -> String {
        let status = side.status.map { " [\(statusMark($0))]" } ?? ""
        let left = "\(slot) \(side.snapshot.name) Lv.\(side.snapshot.level)\(status)"
        let gauge = TUIRender.bar(progress: Double(max(0, side.hp)) / Double(max(1, side.stats.hp)),
                                  width: 10)
        return TUIRender.row(left: left, right: "\(gauge) \(max(0, side.hp))/\(side.stats.hp)",
                             width: width)
    }

    /// 상태이상 이름. 터미널은 폭이 귀해 길게 적을 수 없고, 안 적으면 왜 못 움직이는지 알 수 없다.
    private static func statusMark(_ status: Status) -> String {
        switch status {
        case .burn: "화상"
        case .freeze: "얼음"
        case .paralysis: "마비"
        case .poison: "독"
        case .toxic: "맹독"
        case .sleep: "잠듦"
        default: "이상"
        }
    }

    /// 끝난 판의 한 줄. 아무 말도 안 하면 사용자는 왜 키가 안 먹는지 모른다.
    private static func endingLine(_ run: RogueRun) -> String? {
        switch run.stage {
        case .cleared: "\(RogueRun.finalWave) 웨이브를 모두 돌파했다."
        case .failed: "웨이브 \(run.wave) 에서 파티가 전멸했다."
        default: nil
        }
    }

    /// 마지막 몇 줄만. 전부 찍으면 판 하나가 화면을 통째로 덮는다.
    private static let logTail = 4

    /// 이벤트 → 사람이 읽는 줄. 문구 결정은 `BattleLog` 한 곳이고 여기서는 **주인 → 이름·기술**만
    /// 잇는다 — 앱 화면(`BattleLogSource.waveRun`)과 같은 규칙이다.
    ///
    /// `since` 는 **그 번호 뒤에 붙은 줄만** 달라는 뜻이다. 한 번 찍고 끝나는 명령의 답이
    /// 이 값을 쓴다 — 전부 실으면 요청 하나가 지난 턴들을 통째로 되뇌고, 마지막 줄만 실으면
    /// 아무 일도 안 일어난 입력(2대2 의 첫 칸)이 지난 턴의 결과를 자기 것처럼 보고한다.
    static func log(_ run: RogueRun, language: AppLanguage, since index: Int = 0) -> [String] {
        let events = run.battle.events
        guard index < events.count else { return [] }
        return lines(of: Array(events[max(0, index)...]), in: run, l: L(language))
    }

    private static func lines(of events: [BattleEvent], in run: RogueRun, l: L) -> [String] {
        var byActor: [BattleActor: BattleSide] = [:]
        for slot in run.battle.myField where run.battle.mine.indices.contains(slot.teamIndex) {
            byActor[.fighter(slot.id)] = run.battle.mine[slot.teamIndex]
        }
        for slot in run.battle.opponentField
        where run.battle.opponents.indices.contains(slot.teamIndex) {
            byActor[.fighter(slot.id)] = run.battle.opponents[slot.teamIndex]
        }
        return BattleLog.lines(events, l: l,
                               // 모르는 주인(이 웨이브의 칸이 아닌 옛 이벤트)은 물음표로 남긴다 —
                               // 엉뚱한 칸의 이름을 붙이는 것보다 낫다.
                               name: { byActor[$0]?.snapshot.name ?? "?" },
                               move: { actor, id in
                                   byActor[actor]?.moves.first { $0.id == id } ?? .struggle()
                               })
            .map(\.text)
    }

    // MARK: 라벨

    private static func label(_ number: Int, in run: RogueRun, l: L) -> String {
        switch kind(run) {
        case .move:
            guard let side = actingSide(run) else { return "" }
            guard !side.mustStruggle else { return MoveSpec.struggle().name(l.lang) }
            let index = number - 1
            guard side.moves.indices.contains(index) else { return "" }
            let remaining = side.pp.indices.contains(index) ? side.pp[index] : 0
            return "\(side.moves[index].name(l.lang))  \(remaining)/\(side.moves[index].pp)"
        case .sendOut:
            let index = number - 1
            guard run.party.indices.contains(index) else { return "" }
            let member = run.party[index]
            return "\(member.snapshot.name) Lv.\(member.snapshot.level)  \(member.hp)/\(member.stats.hp)"
        case .offer:
            let index = number - 1
            guard run.offers.indices.contains(index) else { return "" }
            let offer = run.offers[index]
            return offer.name(l) + (offer.isPersistent ? "  [지속]" : "")
        case .route:
            let route = RunRoute.allCases[number - 1]
            return route.name(l) + (route == .risky
                                    ? "  상대 +\(RunRoute.risky.levelBonus)Lv · 보상 \(RunRoute.risky.pickCount)장"
                                    : "")
        case .none, .loading:
            return ""
        }
    }

    /// 이번 턴에 행동을 정할 칸의 개체. **`slotsAwaitingAction` 의 첫 칸**이다 — 앱 화면도 같은
    /// 값을 쓰므로(`RogueRunView.arena`) 터미널에서 고른 기술이 화면과 같은 칸에서 나간다.
    static func actingSide(_ run: RogueRun) -> BattleSide? {
        guard let slot = run.battle.slotsAwaitingAction.first else { return nil }
        return run.battle.mySide(at: slot)
    }
}
