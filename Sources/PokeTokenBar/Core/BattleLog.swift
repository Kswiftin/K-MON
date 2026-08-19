import Foundation

/// 이벤트 스트림을 화면에 보이는 로그 줄로 접는다.
///
/// 한 공격은 이벤트 여러 개(`.move` → `.crit` → `.damage`)를 남기는데 팝오버 로그에는 최근 몇 줄만
/// 보인다. 이벤트마다 한 줄을 쓰면 한 턴이 로그를 다 차지한다. 접어도 스트림은 그대로 남으므로
/// 재생 애니메이션(Phase 7)은 접기 전 이벤트를 하나씩 읽는다.
///
/// 이 판단은 예전에 `BattleView.eventLine` 의 if/else 사슬 안에 있었다. 뷰 안에 두면 문구가 맞는지
/// 테스트할 방법이 없고, 실제로 1v1 과 멀티가 같은 사건에 서로 다른 문구를 만들고 있었다.
enum BattleLog {
    struct Line: Equatable {
        /// 이 줄을 만든 쪽 — 뷰가 내 편/상대 색을 이 값으로 가른다. 턴 구분선처럼 주인이 없으면 nil.
        var actor: BattleActor?
        var text: String
    }

    /// 이름·기술명 해석은 호출부(뷰)가 준다 — 같은 스트림을 1v1 은 좌우로, 멀티는 UUID 로 읽는다.
    static func lines(_ events: [BattleEvent], l: L,
                      name: (BattleActor) -> String,
                      moveName: (BattleActor, Int) -> String) -> [Line] {
        var out: [Line] = []
        var pending: Action?

        func flush() {
            guard let action = pending else { return }
            pending = nil
            out.append(Line(actor: action.actor, text: action.text(l: l, name: name, moveName: moveName)))
        }
        /// 행동 없이 들어온 이벤트(기술 없는 데미지 등)도 주인은 있어야 한다.
        func begin(_ actor: BattleActor) {
            if pending == nil { pending = Action(actor: actor) }
        }

        for event in events {
            switch event {
            case .turn(let number):
                flush()
                out.append(Line(actor: nil, text: l.battleTurnLabel(number)))
            case .move(let actor, let moveID):
                flush()
                pending = Action(actor: actor, moveID: moveID)
            case .miss(let actor):
                begin(actor); pending?.missed = true
            case .immune(let actor):
                begin(actor); pending?.immune = true
            case .crit(let actor):
                begin(actor); pending?.notes.append(l.battleCritical)
            case .superEffective(let actor):
                begin(actor); pending?.notes.append(l.battleSuperEffective)
            case .resisted(let actor):
                begin(actor); pending?.notes.append(l.battleNotVeryEffective)
            case .damage(let actor, let amount):
                begin(actor); pending?.damage = amount
            case .faint(let actor):
                flush()
                out.append(Line(actor: actor, text: l.battleFainted(name(actor))))
            }
        }
        flush()
        return out
    }

    /// 한 줄이 되기 전까지 모아 두는 행동 하나. 급소·상성 이벤트는 *맞은* 쪽을 가리키지만
    /// 줄의 주인은 때린 쪽이므로, `actor` 는 `.move` 가 정한 값을 유지한다.
    private struct Action {
        var actor: BattleActor
        var moveID: Int?
        var damage: Int?
        var notes: [String] = []
        var missed = false
        var immune = false

        func text(l: L, name: (BattleActor) -> String, moveName: (BattleActor, Int) -> String) -> String {
            let who = name(actor)
            guard let moveID else {
                // 기술 없이 들어온 데미지 — Phase 2 의 화상·독 잔뎀이 이 모양으로 온다.
                // 여기서 "기술을 썼다" 문구를 쓰면 쓰지 않은 기술 이름이 로그에 뜬다.
                guard let damage else { return notes.joined(separator: " · ") }
                return ([l.battleTookDamage(who, damage: damage)] + notes).joined(separator: " · ")
            }
            let move = moveName(actor, moveID)
            // 데미지 숫자는 실제로 깎였을 때만 붙인다 — 빗나감·무효에 "0 데미지" 를 붙이면 맞았는데
            // 0 인 것처럼 읽히고, 위력 없는 변화기(Phase 3)도 같은 이유로 숫자가 없어야 한다.
            if missed { return l.battleUsedMoveMissed(who, move: move) + " " + l.battleMissed }
            if immune { return l.battleUsedMoveMissed(who, move: move) + " " + l.battleNoEffect }
            guard let damage else {
                return ([l.battleUsedMoveMissed(who, move: move)] + notes).joined(separator: " · ")
            }
            return ([l.battleUsedMoveNamed(who, move: move, damage: damage)] + notes).joined(separator: " · ")
        }
    }
}
