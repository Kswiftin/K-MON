import XCTest
@testable import PokeTokenBar

/// `SafariVisit` — 걷기·조우를 아우르는 방문 하나. `advance`/`act` 두 게이트(조우 시작 소스
/// 차단, 액션 진입점)와 방문당·하루 포획 상한, 걸음 소진 자동 종료를 검증한다.
final class SafariVisitTests: XCTestCase {

    /// 저장 복원 이니셜라이저를 그대로 빌려 임의 상태의 방문을 만든다 — `SafariVisit` 이
    /// `advance`/`act` 로만 상태를 바꾸게 캡슐화돼 있어, 테스트에서 특정 상황(볼 소진·상한
    /// 도달 등)을 즉석에서 재현하려면 이 경로가 필요하다.
    private func makeVisit(balls: Int = SafariZone.ballsPerVisit,
                           stepsRemaining: Int = SafariZone.stepsPerVisit,
                           cell: SafariCell = SafariCell(x: 5, y: 5),
                           encounter: SafariEncounter? = nil,
                           catchesThisVisit: Int = 0,
                           seed: UInt64 = 1) -> SafariVisit {
        SafariVisit(zone: .grassland, seed: seed, balls: balls, stepsRemaining: stepsRemaining,
                   walker: SafariWalker(startingAt: cell), currentEncounter: encounter,
                   catchesThisVisit: catchesThisVisit, caughtSpeciesIDs: [], visitLog: [],
                   hasEnded: false, rngState: seed)
    }

    // MARK: act(_:) — 게이트 전수

    /// 조우가 없으면 네 액션 전부가 상태를 안 바꾼다.
    func testActIsNoOpWhenThereIsNoEncounter() {
        var visit = makeVisit()
        for action in SafariAction.allCases {
            XCTAssertEqual(visit.act(action), .continuing)
        }
        XCTAssertNil(visit.currentEncounter)
        XCTAssertEqual(visit.balls, SafariZone.ballsPerVisit, "조우가 없으면 볼도 안 깎여야 한다")
        XCTAssertTrue(visit.visitLog.isEmpty, "조우가 없으면 로그도 안 남아야 한다")
    }

    /// 볼이 없으면 `.ball` 만 거부되고 나머지 셋(미끼·진흙·도망)은 그대로 된다 — 볼과 무관한
    /// 행동까지 막으면 안 된다.
    func testBallActionIsRejectedWithoutBallsButOtherActionsStillWork() {
        let encounter = SafariEncounter(speciesID: 1, rarity: .common)
        var visit = makeVisit(balls: 0, encounter: encounter)
        XCTAssertEqual(visit.act(.ball), .continuing, "볼이 없으면 .ball 은 거부돼야 한다")
        XCTAssertNotNil(visit.currentEncounter, "거부된 액션은 조우를 안 바꿔야 한다")
        XCTAssertEqual(visit.balls, 0)
        XCTAssertEqual(visit.act(.run), .ranAway, "볼이 없어도 도망은 항상 가능해야 한다")
    }

    // MARK: advance(_:) — 조우 중 이동 무시

    /// 조우가 진행 중이면 방향키를 아무리 눌러도 걷지 않고 걸음도 안 깎인다.
    func testAdvanceIgnoresMovementInputWhileEncounterIsActive() {
        let encounter = SafariEncounter(speciesID: 1, rarity: .common)
        var visit = makeVisit(encounter: encounter)
        let stepsBefore = visit.stepsRemaining
        for _ in 0..<10 {
            visit.advance(dt: 0.1, heldKeys: [.down], catchesRemainingToday: SafariZone.dailyCatchCap)
        }
        XCTAssertEqual(visit.walker.cell, SafariCell(x: 5, y: 5), "조우 중엔 걷기가 멈춰야 한다")
        XCTAssertEqual(visit.stepsRemaining, stepsBefore, "조우 중엔 걸음도 안 깎여야 한다")
    }

    // MARK: 걸음 소진 자동 종료

    func testAdvanceEndsVisitWhenStepsRunOut() {
        var visit = makeVisit(stepsRemaining: 1)
        // 칸 하나를 건너려면 dt=0.1 두 번(0.18s).
        visit.advance(dt: 0.1, heldKeys: [.down], catchesRemainingToday: SafariZone.dailyCatchCap)
        XCTAssertFalse(visit.hasEnded)
        visit.advance(dt: 0.1, heldKeys: [.down], catchesRemainingToday: SafariZone.dailyCatchCap)
        XCTAssertTrue(visit.hasEnded, "마지막 걸음을 다 쓰면 방문이 끝나야 한다")
    }

    // MARK: 방문당·하루 포획 상한 — 먼저 닿는 쪽이 이긴다

    func testAdvanceEndsVisitWhenPerVisitCatchCapIsReached() {
        var visit = makeVisit(catchesThisVisit: SafariZone.catchesPerVisitCap)
        visit.advance(dt: 0.1, heldKeys: [.down], catchesRemainingToday: SafariZone.dailyCatchCap)
        visit.advance(dt: 0.1, heldKeys: [.down], catchesRemainingToday: SafariZone.dailyCatchCap)
        XCTAssertTrue(visit.hasEnded, "방문당 상한을 이미 채웠으면 하루 여유가 남아도 방문이 끝나야 한다")
        XCTAssertNil(visit.currentEncounter)
    }

    func testAdvanceEndsVisitWhenDailyCatchCapIsReachedEvenIfVisitCapRemains() {
        var visit = makeVisit(catchesThisVisit: 0)
        visit.advance(dt: 0.1, heldKeys: [.down], catchesRemainingToday: 0)
        visit.advance(dt: 0.1, heldKeys: [.down], catchesRemainingToday: 0)
        XCTAssertTrue(visit.hasEnded, "하루 상한이 이미 소진됐으면 방문당 여유가 남아도 방문이 끝나야 한다")
    }

    /// 포획 여유가 0이면 대량 seed 를 순회해도 새 조우가 **절대** 안 생긴다 —
    /// `SafariVisit.advance` 의 `min(catchesRemainingThisVisit, catchesRemainingToday) > 0`
    /// 소스 차단 가드를 지우면 이 테스트가 실패해야 한다.
    func testAdvanceNeverStartsEncounterWhenNoCatchAllowanceRemains() {
        for seed: UInt64 in 0..<500 {
            var visit = makeVisit(stepsRemaining: 4, seed: seed)
            for _ in 0..<4 {
                visit.advance(dt: 0.1, heldKeys: [.down], catchesRemainingToday: 0)
                if visit.hasEnded { break }
            }
            XCTAssertNil(visit.currentEncounter, "seed \(seed): 포획 여유가 0인데 조우가 생겼다")
            XCTAssertTrue(visit.hasEnded, "seed \(seed): 포획 여유가 0이면 첫 걸음에 방문이 끝나야 한다")
        }
    }

    /// 볼이 없으면(포획 여유는 남아 있어도) 새 조우가 안 생긴다 — 잡을 방법이 없는 조우는
    /// 의미가 없다.
    func testAdvanceDoesNotStartEncounterWithoutBalls() {
        for seed: UInt64 in 0..<500 {
            var visit = makeVisit(balls: 0, stepsRemaining: 4, seed: seed)
            for _ in 0..<4 {
                visit.advance(dt: 0.1, heldKeys: [.down], catchesRemainingToday: SafariZone.dailyCatchCap)
            }
            XCTAssertNil(visit.currentEncounter, "seed \(seed): 볼이 없는데 조우가 생겼다")
        }
    }
}
