import XCTest
@testable import PokeTokenBar

final class MissionBoardTests: XCTestCase {
    private let day = "2026-08-18"
    private let nextDay = "2026-08-19"
    private let week = "2026-W34"

    private func mission(_ id: String) -> Mission { MissionBoard.catalog.first { $0.id == id }! }

    func testCatalogIsALargerPoolOfDailyEggMissions() {
        XCTAssertGreaterThan(MissionBoard.catalog.count, 3)
        XCTAssertTrue(MissionBoard.catalog.allSatisfy {
            $0.period == .daily && $0.target > 0 && $0.reward == 1
        })
        XCTAssertEqual(Set(MissionBoard.catalog.map(\.id)).count, MissionBoard.catalog.count)
    }

    func testEachUserGetsThreeStableMissionsForTheDay() {
        let first = MissionBoard.assignedDailyMissions(dayKey: day, seed: "서희")
        let reopened = MissionBoard.assignedDailyMissions(dayKey: day, seed: "서희")
        XCTAssertEqual(first.map(\.id), reopened.map(\.id))
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(Set(first.map(\.id)).count, 3)
    }

    func testDateAndUserParticipateInTheRandomAssignment() {
        let today = MissionBoard.assignedDailyMissions(dayKey: day, seed: "서희").map(\.id)
        let tomorrow = MissionBoard.assignedDailyMissions(dayKey: nextDay, seed: "서희").map(\.id)
        let neighbour = MissionBoard.assignedDailyMissions(dayKey: day, seed: "현태").map(\.id)
        XCTAssertNotEqual(today, tomorrow)
        XCTAssertNotEqual(today, neighbour)
    }

    func testEveryMissionIsNamedAndUnique() {
        let names = MissionBoard.catalog.map { L().missionName($0) }
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testOnlyAssignedMissionsCanProgress() {
        let assigned = MissionBoard.assignedDailyMissions(dayKey: day, seed: "서희")
        for mission in MissionBoard.catalog {
            var board = MissionBoard()
            let completed = board.record(mission.event, mission.target, dayKey: day, weekKey: week,
                                         assignmentSeed: "서희")
            XCTAssertEqual(completed.contains { $0.id == mission.id },
                           assigned.contains { $0.id == mission.id })
        }
    }

    func testCompletedMissionCannotPayTwice() {
        let picked = MissionBoard.assignedDailyMissions(dayKey: day, seed: "서희")[0]
        var board = MissionBoard()
        XCTAssertEqual(board.record(picked.event, picked.target, dayKey: day, weekKey: week,
                                    assignmentSeed: "서희").count, 1)
        XCTAssertTrue(board.record(picked.event, picked.target, dayKey: day, weekKey: week,
                                   assignmentSeed: "서희").isEmpty)
    }

    func testDayRolloverMakesDailyMissionsAvailableAgain() {
        let picked = Set(MissionBoard.assignedDailyMissions(dayKey: day, seed: "서희").map(\.id))
            .intersection(MissionBoard.assignedDailyMissions(dayKey: nextDay, seed: "서희").map(\.id))
            .first!
        let goal = mission(picked)
        var board = MissionBoard()
        _ = board.record(goal.event, goal.target, dayKey: day, weekKey: week, assignmentSeed: "서희")
        XCTAssertEqual(board.progress(goal, dayKey: nextDay, weekKey: week), 0)
        XCTAssertEqual(board.record(goal.event, goal.target, dayKey: nextDay, weekKey: week,
                                    assignmentSeed: "서희").count, 1)
    }

    func testNonPositiveAmountsDoNothing() {
        var board = MissionBoard()
        XCTAssertTrue(board.record(.battles, 0, dayKey: day, weekKey: week).isEmpty)
        XCTAssertTrue(board.record(.battles, -1, dayKey: day, weekKey: week).isEmpty)
        XCTAssertEqual(board.progress(mission("dailyBattle"), dayKey: day, weekKey: week), 0)
    }

    func testNormalizeDropsUnknownIDsAndClampsProgress() {
        var board = MissionBoard()
        board.dayKey = day
        board.daily = ["dailyBattle": Int.max, "removed": 1]
        board.normalize()
        XCTAssertEqual(board.daily["dailyBattle"], 1)
        XCTAssertNil(board.daily["removed"])
    }

    func testCanonicalIsStableRegardlessOfRecordingOrder() {
        var forward = MissionBoard()
        _ = forward.record(.battles, 1, dayKey: day, weekKey: week)
        _ = forward.record(.dungeonClears, 1, dayKey: day, weekKey: week)
        var reverse = MissionBoard()
        _ = reverse.record(.dungeonClears, 1, dayKey: day, weekKey: week)
        _ = reverse.record(.battles, 1, dayKey: day, weekKey: week)
        XCTAssertEqual(forward.canonical, reverse.canonical)
    }
}

final class MissionSaveTests: XCTestCase {
    func testLegacySaveWithoutMissionsKeepsTheRestOfTheSave() throws {
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"starPieces":1234}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(state.missions, MissionBoard())
        XCTAssertEqual(state.starPieces, 1234)
    }

    func testDefaultMissionBoardDoesNotInvalidateOldSignatures() {
        XCTAssertFalse(SaveTransfer.canonicalString(CompanionState()).contains("|ms"))
        XCTAssertFalse(SaveTransfer.isTampered(SaveTransfer.signed(CompanionState())))
    }

    func testMissionProgressIsCoveredByIntegritySignature() {
        var state = CompanionState()
        _ = state.missions.record(.battles, 1, dayKey: "2026-08-18", weekKey: "2026-W34")
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed))
        signed.missions.daily["dailyBattle"] = 0
        XCTAssertTrue(SaveTransfer.isTampered(signed))
    }
}
