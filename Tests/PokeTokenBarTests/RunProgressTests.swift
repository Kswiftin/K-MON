import XCTest
@testable import PokeTokenBar

/// 판 밖으로 남는 유일한 값(`RunProgress`). 재화를 주지 않으므로 잠글 것은 **기록이 정확한가**와
/// **세이브 경계(서명·정규화·기기 병합)를 지나는가**다.
final class RunProgressTests: XCTestCase {

    func testRecordingKeepsTheBestWaveNotTheLastOne() {
        var progress = RunProgress()
        progress.record(reachedWave: 9, cleared: false)
        progress.record(reachedWave: 3, cleared: false)
        XCTAssertEqual(progress.bestWave, 9, "실패한 판이 앞선 최고 기록을 지웠다")
        XCTAssertEqual(progress.finished, 2)
        XCTAssertEqual(progress.clears, 0)
    }

    func testClearingCountsSeparately() {
        var progress = RunProgress()
        progress.record(reachedWave: RogueRun.finalWave, cleared: true)
        progress.record(reachedWave: RogueRun.finalWave, cleared: true)
        XCTAssertEqual(progress.clears, 2)
        XCTAssertEqual(progress.finished, 2)
        XCTAssertEqual(progress.bestWave, RogueRun.finalWave)
    }

    /// 손편집·구버전 값은 경계에서 자른다. 최고 웨이브가 최종 웨이브를 넘으면 화면에 "13/12" 로 나온다.
    func testNormalizeClampsToTheRunLength() {
        var progress = RunProgress()
        progress.bestWave = 900
        progress.clears = -3
        progress.finished = -1
        progress.normalize()
        XCTAssertEqual(progress.bestWave, RogueRun.finalWave)
        XCTAssertEqual(progress.clears, 0)
        XCTAssertEqual(progress.finished, 0)
    }

    /// 클리어 횟수는 끝난 판 수를 넘을 수 없고, 클리어한 판이 있으면 최고 기록은 최종 웨이브다 —
    /// 두 값이 어긋난 세이브는 손편집이거나 옛 버그다.
    func testNormalizeMakesTheTwoCountersAgree() {
        var progress = RunProgress()
        progress.clears = 5
        progress.finished = 2
        progress.bestWave = 3
        progress.normalize()
        XCTAssertEqual(progress.clears, 2)
        XCTAssertEqual(progress.bestWave, RogueRun.finalWave)
    }

    /// 두 기기의 실적은 **각 축의 큰 값**으로 합친다. 한쪽을 고르면 다른 기기에서 세운 기록이 사라진다.
    func testMergingTakesTheBestOfBothDevices() {
        var a = RunProgress()
        a.record(reachedWave: 11, cleared: false)
        var b = RunProgress()
        b.record(reachedWave: 6, cleared: false)
        b.record(reachedWave: 8, cleared: false)
        let merged = RunProgress.merged(a, b)
        XCTAssertEqual(merged.bestWave, 11)
        XCTAssertEqual(merged.finished, 2)
    }

    // MARK: 세이브 경계

    /// 기본값이면 서명 조각이 붙지 않는다 — 붙이면 이 필드가 없던 시절의 정상 세이브가 전부
    /// 조작으로 판정돼 진행이 초기화된다. 해시끼리 비교하지 않고 문자열에서 직접 본다.
    func testDefaultProgressAddsNothingToTheIntegrityCanonical() {
        XCTAssertFalse(SaveTransfer.canonicalString(CompanionState()).contains("|wrun"))
        XCTAssertFalse(SaveTransfer.isTampered(SaveTransfer.signed(CompanionState())))
    }

    /// 대조군 — 값이 들어가면 세그먼트가 실제로 붙는다. 위 테스트만 있으면 canonical 에서 실적을
    /// 통째로 빼먹어도 통과한다.
    func testPopulatedProgressAppendsItsSegment() {
        var state = CompanionState()
        state.waveRun.record(reachedWave: 7, cleared: false)
        XCTAssertTrue(SaveTransfer.canonicalString(state).contains("|wrun7|0|1"),
                      "실제: \(SaveTransfer.canonicalString(state))")
    }

    /// 서명 뒤에 기록을 고치면 조작으로 잡힌다.
    func testEditingTheRecordAfterSigningIsDetected() {
        var state = CompanionState()
        state.waveRun.record(reachedWave: 5, cleared: false)
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed), "테스트 전제: 서명 직후는 정상이어야 한다")
        signed.waveRun.bestWave = 12
        XCTAssertTrue(SaveTransfer.isTampered(signed), "실적이 무결성 해시에 들어가 있어야 한다")
    }

    /// 경계 정규화가 저장 경로에서도 걸린다 — 불러오기만 막으면 이미 저장된 극단값이 그대로 남는다.
    func testSanitizeClampsTheStoredRecord() {
        var state = CompanionState()
        state.waveRun.bestWave = 9_999
        state.waveRun.finished = 4
        XCTAssertEqual(SaveTransfer.sanitized(state).waveRun.bestWave, RogueRun.finalWave)
    }

    /// 필드가 없는 옛 세이브는 기본값으로 읽는다 — 디코드 실패로 상태 전체를 버리면 업데이트
    /// 당일에 도감·인벤토리까지 사라진다.
    func testAnOlderSaveWithoutTheFieldDecodesToDefaults() throws {
        let json = Data(#"{"trainerName":"T","starPieces":12}"#.utf8)
        let state = try JSONDecoder().decode(CompanionState.self, from: json)
        XCTAssertEqual(state.waveRun, RunProgress())
        XCTAssertEqual(state.trainerName, "T")
    }

    /// 실적을 남기는 것이 **재화를 주지는 않는다.** 별의조각이 붙으면 무제한 판 수라는 결정을
    /// 다시 제한해야 하므로, 이 경계가 깨지는지 테스트로 잠근다.
    func testRecordingARunDoesNotPayCurrency() {
        var state = CompanionState()
        state.starPieces = 40
        state.waveRun.record(reachedWave: RogueRun.finalWave, cleared: true)
        XCTAssertEqual(state.starPieces, 40)
        XCTAssertTrue(state.dex.isEmpty)
    }

    /// 기기 이전 경로에서도 실제로 합쳐진다 — 순수 함수만 잠그면 `rebasedForThisDevice` 가 그 함수를
    /// 부르지 않아도 통과한다(불러온 기기의 기록이 조용히 사라진다).
    func testImportingAnotherDeviceKeepsTheBetterRecord() {
        var imported = CompanionState()
        imported.waveRun.record(reachedWave: 4, cleared: false)
        var current = CompanionState()
        current.waveRun.record(reachedWave: 10, cleared: false)

        let rebased = SaveTransfer.rebasedForThisDevice(imported, current: current)
        XCTAssertEqual(rebased.waveRun.bestWave, 10, "이 기기에서 세운 기록이 이전으로 사라졌다")
        XCTAssertEqual(rebased.waveRun.finished, 1)
    }

    // MARK: 판 하나는 한 번만 센다

    /// 결과 화면은 팝오버를 여닫을 때마다 다시 그려진다 — 플래그가 없으면 같은 판이 그만큼 쌓인다.
    func testTheResultIsRecordedOnlyOnce() {
        var run = RogueRun(party: [snapshot(1, hp: 1)], opponents: [snapshot(99, speed: 200)], seed: 1)
        for _ in 0..<20 where run.stage == .battling { run.useMove(0) }
        guard run.stage == .failed else { return XCTFail("패배하지 못했다: \(run.stage)") }
        XCTAssertFalse(run.resultRecorded)
        run.markResultRecorded()
        XCTAssertTrue(run.resultRecorded)
    }

    /// 진행 중인 판은 적을 수 없다 — 적히면 그 판이 실패로 세어지고, 끝나고 한 번 더 세어진다.
    func testAnUnfinishedRunCannotBeRecorded() {
        var run = RogueRun(party: [snapshot(1, hp: 900)], opponents: [snapshot(99, hp: 900)], seed: 1)
        XCTAssertEqual(run.stage, .battling)
        run.markResultRecorded()
        XCTAssertFalse(run.resultRecorded)
    }

    private func snapshot(_ id: Int, level: Int = 5, hp: Int = 100, speed: Int = 100) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "M\(id)", trainer: "T", level: level, nature: nil,
                       isShiny: false, types: [.normal],
                       base: BattleStats(hp: hp, atk: 100, def: 50, spa: 100, spd: 50, spe: speed),
                       moves: [MoveSpec(id: 1, names: ["en": "Hit"], type: .normal, power: 200,
                                        damageClass: .physical, accuracy: nil, pp: 20)])
    }
}
