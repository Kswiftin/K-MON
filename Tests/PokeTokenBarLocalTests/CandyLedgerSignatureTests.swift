import Foundation
import Testing
@testable import PokeTokenBar

/// 일일 사탕은 `lastCandyDate` 하나로 하루 한 번을 지킨다. 그 키가 서명 밖에 있으면 세이브를
/// 손으로 고쳐 어제 날짜로 되돌리는 것만으로 사탕을 매일 여러 번 받는다 — 형제 원장인 체육관
/// 방어 보상(`gd`)·모험 보너스(`ab`)는 같은 이유로 이미 서명 안에 있다.
@Suite struct CandyLedgerSignatureTests {

    /// 기본값 세이브의 서명은 **바뀌지 않아야 한다.** 무조건 붙이면 이 필드가 없던 시절의 정상
    /// 세이브가 전부 조작으로 판정돼 진행이 초기화된다.
    @Test func anEmptyLedgerAddsNoSegment() {
        #expect(!SaveTransfer.canonicalString(CompanionState()).contains("dcd"))
    }

    @Test func theDailyCandyKeyIsSigned() {
        var state = CompanionState()
        state.lastCandyDate = "2026-09-02"
        #expect(SaveTransfer.canonicalString(state).contains("dcd2026-09-02"))

        var edited = state
        edited.lastCandyDate = "2026-09-01"   // 손편집으로 하루 되돌리기
        #expect(SaveTransfer.canonicalString(edited) != SaveTransfer.canonicalString(state),
                "원장 키를 되돌려도 서명이 같으면 사탕을 다시 받는다")
    }
}
