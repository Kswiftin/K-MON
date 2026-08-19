import XCTest
@testable import PokeTokenBar

/// 이벤트 스트림을 로그 줄로 접는 자리를 본다. 이 판단은 예전에 `BattleView.eventLine` 의 if/else
/// 사슬 안에 있어서 테스트할 수 없었다(뷰를 띄워야 문구를 볼 수 있었다). 스트림이 타입된 값이 되면서
/// 문구를 고르는 일이 순수 함수로 빠졌고, 3언어 문구와 접기 규칙을 여기서 잠근다.
final class BattleLogTests: XCTestCase {

    /// 이름·기술명 해석은 호출부(뷰)의 몫이라 테스트에서는 고정값을 준다.
    private func lines(_ events: [BattleEvent], _ lang: AppLanguage = .ko) -> [String] {
        BattleLog.lines(events, l: L(lang),
                        name: { $0 == .a ? "거북왕" : "리자몽" },
                        moveName: { _, id in id == 57 ? "파도타기" : "화염방사" })
            .map(\.text)
    }

    /// 한 공격이 남기는 이벤트 여러 개(`.move` → `.superEffective` → `.damage`)가 **한 줄**로 접힌다.
    /// 이벤트마다 한 줄을 쓰면 최근 4줄만 보이는 팝오버 로그를 한 턴이 다 차지한다.
    func testOneAttackBecomesOneLine() {
        let stream: [BattleEvent] = [.turn(1), .move(.a, moveID: 57),
                                     .superEffective(.b), .damage(.b, amount: 122)]
        XCTAssertEqual(lines(stream),
                       ["턴 1", "거북왕의 파도타기! 122 데미지 · 효과가 굉장했다!"])
        // 반쪽 상성도 같은 자리에 붙는다 — 두 방향을 함께 봐야 한쪽만 배선된 경우를 걸러낸다.
        XCTAssertEqual(lines([.move(.b, moveID: 53), .resisted(.a), .damage(.a, amount: 40)]),
                       ["리자몽의 화염방사! 40 데미지 · 효과가 별로인 듯하다…"])
    }

    /// 3언어 모두 같은 접기 규칙을 따른다.
    func testAttackLineIsLocalized() {
        let stream: [BattleEvent] = [.move(.a, moveID: 57), .crit(.b), .damage(.b, amount: 122)]
        XCTAssertEqual(lines(stream, .en), ["거북왕 used 파도타기! 122 damage · A critical hit!"])
        XCTAssertEqual(lines(stream, .ja), ["거북왕の파도타기！ 122ダメージ · きゅうしょにあたった！"])
    }

    /// 턴마다 구분선이 들어가고, 그 턴의 행동은 행동별로 한 줄씩이다.
    func testEachTurnAndEachActionGetsItsOwnLine() {
        let stream: [BattleEvent] = [
            .turn(1), .move(.a, moveID: 57), .damage(.b, amount: 10),
            .move(.b, moveID: 53), .damage(.a, amount: 20),
            .turn(2), .move(.a, moveID: 57), .damage(.b, amount: 30),
        ]
        XCTAssertEqual(lines(stream).count, 5)
        XCTAssertEqual(lines(stream)[0], "턴 1")
        XCTAssertEqual(lines(stream)[3], "턴 2")
    }

    /// 빗나감·무효는 데미지 숫자 없이 렌더된다 — "0 데미지" 로 새면 맞았는데 0 인 것처럼 보인다.
    func testMissAndImmunityRenderWithoutADamageNumber() {
        XCTAssertEqual(lines([.move(.a, moveID: 57), .miss(.a)]),
                       ["거북왕의 파도타기! 빗나갔다!"])
        XCTAssertEqual(lines([.move(.a, moveID: 57), .immune(.b)]),
                       ["거북왕의 파도타기! 효과가 없었다…"])
    }

    /// 기술 없이 들어온 데미지는 **"기술을 썼다" 문구로 나오지 않는다.** Phase 2 의 화상·독 잔뎀이
    /// 이 모양으로 오는데, 현재 구조(플래그 뭉치 하나)에서 가장 흔한 오구현이 여기다.
    func testDamageWithoutAMoveIsNotRenderedAsAMove() {
        let out = lines([.damage(.a, amount: 12)])
        XCTAssertEqual(out, ["거북왕은(는) 12 데미지"])
        XCTAssertFalse(out[0].contains("파도타기"), "쓰지 않은 기술이 문구에 들어가면 안 된다")
    }

    /// 기절은 자기 줄을 갖는다 — 예전엔 뷰가 HP 0 을 보고 추론했다.
    func testFaintGetsItsOwnLine() {
        XCTAssertEqual(lines([.move(.a, moveID: 57), .damage(.b, amount: 200), .faint(.b)]),
                       ["거북왕의 파도타기! 200 데미지", "리자몽은(는) 쓰러졌다!"])
    }

    /// 줄의 주인은 **행동한 쪽**이다(뷰가 내 편/상대 색을 이 값으로 가른다). 급소·상성 이벤트는
    /// 맞은 쪽을 가리키지만, 그 줄의 주인은 여전히 때린 쪽이어야 한다.
    func testLineOwnerIsTheActingSide() {
        let out = BattleLog.lines([.turn(1), .move(.b, moveID: 53), .crit(.a), .damage(.a, amount: 40)],
                                  l: L(.ko), name: { _ in "X" }, moveName: { _, _ in "Y" })
        XCTAssertEqual(out.count, 2)
        XCTAssertNil(out[0].actor, "턴 구분선은 주인이 없다")
        XCTAssertEqual(out[1].actor, .b, "때린 쪽이 그 줄의 주인이다")
    }

    /// 데미지가 없는 기술은 숫자를 달지 않는다. 지금 그런 이벤트를 내는 곳은 없지만
    /// 변화기(Phase 3)가 이 모양이고, 기본값 0 을 채워 넣으면 "0 데미지" 라는 오해가 남는다.
    func testAMoveThatDealtNoDamageShowsNoNumber() {
        XCTAssertEqual(lines([.move(.a, moveID: 57)]), ["거북왕의 파도타기!"])
        XCTAssertEqual(lines([.move(.a, moveID: 57), .crit(.b)]),
                       ["거북왕의 파도타기! · 급소에 맞았다!"])
    }

    /// 데미지 없이 주석만 온 스트림(정상 경로에는 없다)도 문구를 만들어 낸다. 쓰지 않은 기술이나
    /// 0 이라는 숫자를 지어내지만 않으면 된다.
    func testNotesWithoutAnActionRenderOnTheirOwn() {
        XCTAssertEqual(lines([.crit(.a)]), ["급소에 맞았다!"])
    }

    /// 멀티(2~4인)는 참가자 UUID 로 쪽을 가른다 — 같은 스트림·같은 접기를 쓴다.
    func testFighterActorsUseTheSameFold() {
        let id = UUID()
        let out = BattleLog.lines([.move(.fighter(id), moveID: 1), .damage(.b, amount: 5)],
                                  l: L(.ko), name: { $0 == .fighter(id) ? "P1" : "P2" },
                                  moveName: { _, _ in "몸통박치기" })
        XCTAssertEqual(out.map(\.text), ["P1의 몸통박치기! 5 데미지"])
        XCTAssertEqual(out[0].actor, .fighter(id))
    }
}
