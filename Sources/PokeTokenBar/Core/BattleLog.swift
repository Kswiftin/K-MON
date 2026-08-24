import Foundation

/// 이벤트 스트림을 로그 줄로 접는다 — 한 공격(`.move` → `.crit` → `.damage`)이 한 줄이다.
/// 팝오버 로그는 최근 몇 줄만 보이므로 이벤트마다 한 줄을 쓰면 한 턴이 로그를 다 차지한다.
/// 스트림 자체는 남으므로 재생 애니메이션(Phase 7)은 접기 전 이벤트를 읽는다.
/// 뷰가 아니라 여기 있어야 문구를 테스트할 수 있고 세 모드가 같은 어휘를 쓴다.
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
            case .damage(let actor, let amount, .move):
                begin(actor); pending?.damage = amount
            case .damage(let actor, let amount, let cause):
                // 기술이 아닌 데미지(화상·독·맹독·혼란 자멸)는 **자기 줄**이다. 진행 중인 행동에
                // 접으면 쓰지도 않은 기술 이름이 잔뎀 줄에 붙는다.
                flush()
                out.append(Line(actor: actor,
                                text: l.battleStatusDamage(name(actor), damage: amount, cause: cause)))
            case .heal(let actor, let amount):
                // 회복은 **자기 줄**이다 — 잔뎀과 같은 이유다. 진행 중인 행동에 접으면 드레인은
                // 맞지만(때린 쪽이 회복한다) 특성 흡수(Phase 5)는 *맞은* 쪽이 회복하므로 남의
                // 기술 줄에 내 회복이 붙는다.
                flush()
                out.append(Line(actor: actor, text: l.battleHealed(name(actor), amount: amount)))
            case .multiHit(let actor, let hits):
                // 급소·상성과 같은 자리(공격 줄의 노트)다. 자기 줄로 빼면 "3번 맞았다" 가 데미지
                // 줄과 떨어져 무엇이 세 번 맞은 건지 읽히지 않는다.
                begin(actor); pending?.notes.append(l.battleMultiHit(hits))
            case .faint(let actor):
                flush()
                out.append(Line(actor: actor, text: l.battleFainted(name(actor))))
            case .sendOut:
                // 줄을 만들지 않는다 — 이 이벤트의 렌더러는 **필드**다(스프라이트와 바가 새 개체로
                // 바뀌는 것이 곧 문구다). 이름을 쓰려면 팀 인덱스를 풀 팀이 필요하고, 그건 로그가
                // 아는 값이 아니다. 진행 중인 행동은 접는다 — 출전은 배치의 머리 아니면 끝이다.
                flush()
            case .status(let actor, let status):
                flush()
                out.append(Line(actor: actor, text: l.battleStatusInflicted(name(actor), status: status)))
            case .cureStatus(let actor, let status):
                flush()
                out.append(Line(actor: actor, text: l.battleStatusCured(name(actor), status: status)))
            case .cant(let actor, let status):
                flush()
                out.append(Line(actor: actor, text: l.battleCantMove(name(actor), status: status)))
            case .boost(let actor, let stat, let amount) where amount != 0:
                // 랭크 변화는 **자기 줄**이다. 진행 중인 행동에 접으면 "칼춤! 0 데미지 · 공격이
                // 올라갔다" 처럼 쓰지도 않은 데미지 칸에 붙어 읽힌다.
                flush()
                out.append(Line(actor: actor,
                                text: amount > 0 ? l.battleStatRose(name(actor), stat: stat, by: amount)
                                                 : l.battleStatFell(name(actor), stat: stat, by: -amount)))
            case .boost:
                // 0 변화는 줄이 없다 — 호스트가 보낸 0 이 "떨어졌다!" 로 읽히는 걸 막는다.
                break
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
