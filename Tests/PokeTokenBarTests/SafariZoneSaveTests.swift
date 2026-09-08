import XCTest
@testable import PokeTokenBar

/// 진행 중인 사파리존 방문을 디스크로 옮기는 경로(`SafariZoneSave`). 잠그는 것은 **되살린 방문이
/// 저장한 방문과 같은가** 와 **못 믿을 파일을 버리는가** 다 — `RogueRunSaveTests` 와 같은 틀.
final class SafariZoneSaveTests: XCTestCase {

    private func makeVisit(seed: UInt64 = 5) -> SafariVisit {
        SafariVisit(zone: .wetland, seed: seed)
    }

    private func roundTrip(_ visit: SafariVisit) throws -> SafariVisit {
        let data = try JSONEncoder().encode(visit.saveForm)
        let save = try JSONDecoder().decode(SafariZoneSave.self, from: data)
        return try XCTUnwrap(save.restored)
    }

    /// 걸음·볼·워커 위치·조우·단계·로그가 그대로 복원되는지.
    func testVisitStateSurvivesTheRoundTrip() throws {
        var original = makeVisit()
        // 실제로 걸어서 걸음·워커 위치를 흔든다.
        for _ in 0..<4 {
            original.advance(dt: 0.1, heldKeys: [.down], catchesRemainingToday: SafariZone.dailyCatchCap)
        }
        let restored = try roundTrip(original)
        XCTAssertEqual(restored.zone, original.zone)
        XCTAssertEqual(restored.balls, original.balls)
        XCTAssertEqual(restored.stepsRemaining, original.stepsRemaining)
        XCTAssertEqual(restored.walker, original.walker)
        XCTAssertEqual(restored.currentEncounter, original.currentEncounter)
        XCTAssertEqual(restored.catchesThisVisit, original.catchesThisVisit)
        XCTAssertEqual(restored.caughtSpeciesIDs, original.caughtSpeciesIDs)
        XCTAssertEqual(restored.visitLog, original.visitLog)
        XCTAssertEqual(restored.hasEnded, original.hasEnded)
    }

    /// 진행 중인 조우도 그대로 복원돼야 한다 — 단계·턴까지.
    ///
    /// 미끼 뒤 도망 판정은 확률적이라(seed 1 에서 실제로 `.fled` 가 나 CI 에서 걸렸다), 진행 중
    /// (`.continuing`)이 나오는 seed 를 찾아서 쓴다 — 고정 seed 하나로는 결과를 보장 못 한다.
    func testInProgressEncounterSurvivesTheRoundTrip() throws {
        var original = makeVisit()
        func makeProgressingEncounter(seed: UInt64) -> SafariEncounter? {
            var rng = SplitMix64(seed: seed)
            var encounter = SafariEncounter(speciesID: 16, rarity: .common)
            return encounter.act(.bait, rng: &rng) == .continuing ? encounter : nil
        }
        guard let encounter = (UInt64(0)..<200).lazy.compactMap(makeProgressingEncounter).first else {
            return XCTFail("미끼 후 진행 중인 시드를 못 찾았다")
        }
        original = SafariVisit(zone: original.zone, seed: original.seed, balls: original.balls,
                               stepsRemaining: original.stepsRemaining, walker: original.walker,
                               currentEncounter: encounter, catchesThisVisit: 0,
                               caughtSpeciesIDs: [], visitLog: [], hasEnded: false,
                               rngState: original.rngState)
        let restored = try roundTrip(original)
        XCTAssertEqual(restored.currentEncounter, encounter)
    }

    /// rng 는 **소비한 뒤의 상태** 를 싣는다. 씨앗을 실으면 앱을 껐다 켤 때마다 같은 조우가
    /// 다시 나와, 마음에 드는 뽑기가 나올 때까지 재시작하는 것이 최적 전략이 된다.
    func testTheRandomStreamContinuesInsteadOfRestarting() throws {
        var original = makeVisit()
        for _ in 0..<20 {
            original.advance(dt: 0.1, heldKeys: [.down], catchesRemainingToday: SafariZone.dailyCatchCap)
        }
        let restored = try roundTrip(original)
        XCTAssertEqual(restored.saveForm.rngState, original.saveForm.rngState)
    }

    // MARK: 못 믿을 파일

    /// 모르는 형식 판은 반쯤 읽어 되살리지 않는다.
    func testAnUnknownFormatVersionIsRejected() {
        var save = makeVisit().saveForm
        save.version = SafariZoneSave.currentVersion + 1
        XCTAssertNil(save.restored)
    }

    /// 손편집으로 음수가 된 볼·걸음은 0 이상으로 자른다 — 음수 볼로 `.ball` 게이트가 통과되면
    /// 안 된다.
    func testNegativeBallsAndStepsAreClampedToZero() {
        var save = makeVisit().saveForm
        save.balls = -3
        save.stepsRemaining = -10
        save.catchesThisVisit = -1
        let restored = try? XCTUnwrap(save.restored)
        XCTAssertEqual(restored?.balls, 0)
        XCTAssertEqual(restored?.stepsRemaining, 0)
        XCTAssertEqual(restored?.catchesThisVisit, 0)
    }
}
