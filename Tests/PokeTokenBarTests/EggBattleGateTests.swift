import XCTest
@testable import PokeTokenBar

/// 알을 품는 동안 배틀이 막히던 자리.
///
/// 알을 품으면 `state.active` 가 nil 이 된다. 그걸 그대로 "배틀 불가" 로 읽었더니, 박스에 키워
/// 둔 개체가 아무리 많아도 친구 배틀·방 계열(토너먼트·포켓슬론·퀴즈·체육관)에 못 들어갔다.
/// 막아야 하는 것은 **"동행이 알인가" 가 아니라 "내보낼 개체가 없는가"** 다.
@MainActor
final class EggBattleGateTests: XCTestCase {

    private let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                               rarity: .common, names: [1: ["en": "One", "ko": "하나"]])

    private func store() -> CompanionStore {
        CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                       fileURL: FileManager.default.temporaryDirectory
                           .appendingPathComponent("poke-egg-\(UUID().uuidString).json"),
                       rng: SeededRNG(seed: 7))
    }

    private func boxed(_ id: Int) -> MonState {
        MonState(baseID: id, pathIDs: [id], stageIndex: 0, usedAtStage: 0,
                 rarity: .common, totalForms: 1, names: [id: ["en": "P\(id)", "ko": "포\(id)"]])
    }

    /// 알 하나뿐이면 정말 못 싸운다 — 이 경우에만 막는다.
    func testAnEggWithNothingElseCannotBattle() {
        let s = store()
        XCTAssertTrue(s.isEgg, "새 세이브는 알로 시작한다")
        XCTAssertFalse(s.hasBattleReadyMon)
        XCTAssertNil(s.battleFacadeMon)
    }

    /// **회귀**: 알을 품는 중이어도 박스에 개체가 있으면 싸울 수 있어야 한다.
    func testAnEggDoesNotBlockBattlesWhenTheBoxHasPokemon() {
        let s = store()
        s.debugSetBoxedMons([boxed(4), boxed(7)])

        XCTAssertTrue(s.isEgg, "동행은 여전히 알이다")
        XCTAssertTrue(s.hasBattleReadyMon, "박스에 있는 개체로 싸우면 된다")
        XCTAssertNotNil(s.battleFacadeMon)
    }

    /// 동행이 있으면 그 개체가 나를 대표한다.
    func testTheActiveCompanionRepresentsMeWhenThereIsOne() {
        let s = store()
        let mon = boxed(4)
        s.debugSetBoxedMons([mon, boxed(7)])
        s.switchCompanion(to: mon.id)

        XCTAssertFalse(s.isEgg)
        XCTAssertEqual(s.battleFacadeMon?.id, mon.id)
    }

    /// 대표 포켓몬을 지정해 뒀으면 알을 품는 동안 그 개체를 내세운다 — 박스 순서에 맡기지 않는다.
    func testTheChosenRepresentativeIsPreferredWhileIncubating() {
        let s = store()
        let first = boxed(4)
        let chosen = boxed(7)
        s.debugSetBoxedMons([first, chosen])
        s.setBattleRepresentative(chosen.id)

        XCTAssertTrue(s.isEgg)
        XCTAssertEqual(s.battleFacadeMon?.id, chosen.id)
    }

    /// 체육관에 배치한 개체는 내보낼 수 없다 — 그것뿐이면 알일 때와 같이 막혀야 한다.
    func testGymDefendersDoNotCountAsBattleReady() {
        let s = store()
        let team = (1...PlayerGym.defenseTeamSize).map { boxed(10 + $0) }
        s.debugSetBoxedMons(team)
        s.becomeGymLeader()
        s.setGymDefenseTeam(team.map(\.id))

        XCTAssertTrue(s.isEgg)
        XCTAssertFalse(s.hasBattleReadyMon, "잠긴 넷만 남았으면 내보낼 개체가 없는 것이다")
        XCTAssertNil(s.battleFacadeMon)
    }
}
