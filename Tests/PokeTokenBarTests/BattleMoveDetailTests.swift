import XCTest
@testable import PokeTokenBar

/// 대전에 실려 나가는 기술 스펙의 신선도.
///
/// 회귀 원본: 기술 목록 화면만 `needsDetailRefresh` 를 지나고 대전 스냅샷은 `learnedMoves` 를
/// 그대로 실었다. `ailment` 축이 생기기 전의 세이브로 싸우면 수면가루·이상한빛이 **아무 로그도
/// 없이** 무효가 된다 — `inflictedStatus` 가 nil 이라 부여 시도 자체가 없고, 위력 0 이라
/// 데미지 줄도 안 나가서 기술명 한 줄만 남는다. 화면을 한 번도 안 펼친 사용자는 영영 못 고친다.
/// 스텁이 쓰는 재료는 **클래스 밖**에 둔다. `@MainActor` 클래스의 static 은 그 액터에 격리돼
/// 있어서, 액터 밖인 `MoveDetailProvider`(nonisolated) 에서 그냥 읽을 수 없다.
private let oddishSpeciesID = 43
private let sleepPowderID = 79

private let oddishLine = EvoLine(baseID: oddishSpeciesID,
                                 tree: EvoNode(speciesID: oddishSpeciesID, children: []),
                                 rarity: .common,
                                 names: [oddishSpeciesID: ["en": "Oddish", "ko": "뚜벅쵸"]])

/// 옛 세이브의 수면가루 — 이름·타입·위력만 있고 `ailment` 이후의 축이 전부 비어 있다.
private func staleSleepPowder() -> MoveSpec {
    MoveSpec(id: sleepPowderID, names: ["ko": "수면가루", "en": "Sleep Powder"],
             type: .grass, power: 0, damageClass: .status, accuracy: 75, pp: 15)
}

/// 지금 파서가 돌려주는 같은 기술 — 축이 다 차 있다.
private func freshSleepPowder() -> MoveSpec {
    var move = MoveSpec(id: sleepPowderID, names: ["ko": "수면가루", "en": "Sleep Powder"],
                        type: .grass, power: 0, damageClass: .status, accuracy: 75, pp: 15)
    move.descriptions = ["en": "Puts the target to sleep."]
    move.ailment = "sleep"
    move.ailmentChance = 0
    move.statChanges = []
    move.statChance = 0
    move.targetsUser = false
    // Phase 5 축. `min_hits`/`max_hits` 는 단발기에서 null 이 정답이라 안 채운다.
    // 수렴 판정이 보는 축은 `drain` 이다(`CompanionStore.needsDetailRefresh`).
    move.drain = 0
    move.flinchChance = 0
    return move
}

@MainActor
final class BattleMoveDetailTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-move-detail-\(UUID().uuidString).json")
    }

    private func makeStore(_ provider: MoveDetailProvider) -> CompanionStore {
        CompanionStore(provider: provider, clock: { Date() },
                       fileURL: tempURL(), rng: SeededRNG(seed: 7))
    }

    private func oddish(moves: [MoveSpec]) -> MonState {
        var mon = MonState(baseID: oddishSpeciesID, pathIDs: [oddishSpeciesID], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1,
                           names: [oddishSpeciesID: ["en": "Oddish", "ko": "뚜벅쵸"]])
        mon.learnedMoves = moves
        return mon
    }

    /// 원본 결함 — 이 단언이 죽으면 상태기가 대전에서 통째로 사라진다.
    func testBattleSnapshotFillsTheAxesMissingFromAnOldSave() async throws {
        let provider = MoveDetailProvider()
        let store = makeStore(provider)
        let mon = oddish(moves: [staleSleepPowder()])
        store.debugSetBoxedMons([mon])

        // `await` 는 XCTUnwrap 의 autoclosure 안에 못 들어간다 — 먼저 받고 나서 푼다.
        let built = await store.battleSnapshot(for: mon)
        let snapshot = try XCTUnwrap(built)
        let carried = try XCTUnwrap(snapshot.moves?.first)
        XCTAssertEqual(carried.ailment, "sleep",
                       "대전이 옛 스펙을 그대로 실으면 상태기가 로그 없이 무효가 된다")
        XCTAssertEqual(carried.inflictedStatus, .sleep)
        XCTAssertEqual(carried.targetsUser, false)
    }

    /// 되쓰기 — 한 번 채운 개체는 다음 대전에서 다시 조회하지 않는다.
    func testFilledMovesArePersistedSoTheNextBattleSkipsTheFetch() async throws {
        let provider = MoveDetailProvider()
        let store = makeStore(provider)
        store.debugSetBoxedMons([oddish(moves: [staleSleepPowder()])])

        let boxed = try XCTUnwrap(store.boxedMons.first)
        _ = await store.battleSnapshot(for: boxed)
        XCTAssertEqual(provider.moveDetailCalls, 1)
        XCTAssertEqual(store.boxedMons.first?.learnedMoves.first?.ailment, "sleep",
                       "세이브에 안 되쓰면 대전마다 같은 조회가 돈다")

        let refilled = try XCTUnwrap(store.boxedMons.first)
        _ = await store.battleSnapshot(for: refilled)
        XCTAssertEqual(provider.moveDetailCalls, 1)
    }

    /// 축이 다 찬 스펙은 건드리지 않는다 — 매 대전마다 도는 네트워크 조회를 막는 대조군이다.
    func testAFullySpecifiedMoveIsNotRefetched() async {
        let provider = MoveDetailProvider()
        let store = makeStore(provider)
        let mon = oddish(moves: [freshSleepPowder()])
        store.debugSetBoxedMons([mon])

        _ = await store.battleSnapshot(for: mon)
        XCTAssertEqual(provider.moveDetailCalls, 0)
    }
}

/// `moveDetail` 호출 횟수를 세는 스텁 — 되쓰기가 안 되면 대전마다 같은 조회가 반복된다.
private final class MoveDetailProvider: PokeProviding, @unchecked Sendable {
    private(set) var moveDetailCalls = 0
    func line(baseSpeciesID: Int) async throws -> EvoLine { oddishLine }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: oddishSpeciesID, captureRate: 255)] }
    func battleProfile(speciesID: Int) async throws -> PokemonBattleProfile {
        PokemonBattleProfile(speciesID: speciesID,
                             stats: BattleStats(hp: 45, atk: 50, def: 55, spa: 75, spd: 65, spe: 30),
                             types: [.grass, .poison])
    }
    func moveDetail(id: Int) async -> MoveSpec? {
        moveDetailCalls += 1
        return id == sleepPowderID ? freshSleepPowder() : nil
    }
}
