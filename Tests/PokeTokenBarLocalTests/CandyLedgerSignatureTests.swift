import Foundation
import Testing
@testable import PokeTokenBar

/// 일일 사탕은 `lastCandyDate` 하나로 하루 한 번을 지킨다. 그 키가 서명 밖에 있으면 세이브를
/// 손으로 고쳐 어제 날짜로 되돌리는 것만으로 사탕을 매일 여러 번 받는다 — 형제 원장인 체육관
/// 방어 보상(`gd`)·모험 보너스(`ab`)는 같은 이유로 이미 서명 안에 있다.
@Suite struct CandyLedgerSignatureTests {

    /// 기본값 세이브에는 세그먼트가 붙지 않는다.
    ///
    /// **이 단언만으로는 구세이브가 지켜지지 않는다.** `lastCandyDate` 는 이 세그먼트보다 3 주 앞선
    /// 배포부터 있던 필드라, 사탕을 한 번이라도 받은 실제 세이브는 값이 차 있다 — 기본값만 보는
    /// 검사가 통과하는 동안 실사용 세이브는 전부 조작으로 판정돼 초기화됐다(2026-09-03).
    /// 실제 방어는 `integrityVersion` 상향이고, 그것을 `aSaveSignedBeforeTheCandySegmentIsExempt`
    /// 가 검증한다.
    @Test func anEmptyLedgerAddsNoSegment() {
        #expect(!SaveTransfer.canonicalString(CompanionState()).contains("dcd"))
    }

    /// 회귀 — 세그먼트가 생기기 **전** 빌드가 서명한 세이브(값이 든 `lastCandyDate` + 구
    /// `integrityVersion`)는 조작이 아니다. 구서명은 새 canonical 을 재현할 수 없으므로 버전
    /// 면제가 유일한 방어다.
    @Test func aSaveSignedBeforeTheCandySegmentIsExempt() {
        var saved = CompanionState()
        saved.starPieces = 138_679
        saved.lastCandyDate = "2026-09-03"

        // 이전 배포의 서명 재현 — 그 빌드의 canonical 은 지금 것과 `dcd` 세그먼트 하나만 다르다.
        var asPreviousBuild = saved
        asPreviousBuild.lastCandyDate = ""
        var onDisk = SaveTransfer.signed(asPreviousBuild)
        onDisk.lastCandyDate = saved.lastCandyDate
        onDisk.integrityVersion = candySegmentIntegrityVersion - 1

        #expect(!SaveTransfer.isTampered(onDisk),
                "구서명 세이브가 조작으로 판정되면 진행이 통째로 초기화된다")

        // 대조군 — 같은 바이트에 현재 버전을 써 넣으면 검사가 돌고 실제로 안 맞는다.
        // (면제가 아니라 해시가 우연히 같아서 통과하는 게 아님을 보인다.)
        var claimingCurrentVersion = onDisk
        claimingCurrentVersion.integrityVersion = SaveTransfer.integrityVersion
        #expect(SaveTransfer.isTampered(claimingCurrentVersion))
    }

    /// 세그먼트를 넣은 배포가 올려야 했던 버전. 누군가 `integrityVersion` 을 되내리면(또는 다음에
    /// 같은 부류의 실수를 하면) 여기서 걸린다.
    private var candySegmentIntegrityVersion: Int { 10 }

    @Test func theCandySegmentRequiredAnIntegrityVersionBump() {
        var state = CompanionState()
        state.lastCandyDate = "2026-09-03"
        #expect(SaveTransfer.canonicalString(state).contains("dcd"))
        #expect(SaveTransfer.integrityVersion >= candySegmentIntegrityVersion,
                "이미 배포된 필드를 서명에 넣었으면 버전을 올려야 한다")
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
