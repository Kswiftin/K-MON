import XCTest
@testable import PokeTokenBar

// MARK: 홈 화면 능력치 — 배틀과 같은 숫자여야 한다

/// 홈에 능력치 여섯 칸을 고정으로 띄운다. 위험한 건 **숫자가 배틀과 갈라지는 것**이다.
/// 화면이 자기 식으로 계산하면 홈에 뜬 공격 98 과 배틀이 쓰는 공격이 다른데, 갈라진 걸 알아챌
/// 방법은 둘을 손으로 맞대 보는 것뿐이다. 그래서 식은 `BattleStats.effective` 한 곳에 둔다.
final class HomeStatBlockTests: XCTestCase {

    private let base = BattleStats(hp: 108, atk: 130, def: 95, spa: 80, spd: 85, spe: 102)

    private func snapshot(level: Int, nature: PokemonNature?) -> BattleSnapshot {
        BattleSnapshot(speciesID: 1, name: "테스트", trainer: nil, level: level,
                       nature: nature, isShiny: false, types: [.normal], base: base)
    }

    /// **식이 한 곳에 있는가.** 배틀이 쓰는 값과 화면이 쓰는 값이 같은 함수에서 나와야 한다 —
    /// 갈라지면 홈이 거짓말을 한다.
    func testTheScreenAndTheBattleUseTheSameFormula() {
        for level in [5, 37, 50, 100] {
            for nature in [PokemonNature?.none, .adamant, .modest, .hardy] {
                XCTAssertEqual(snapshot(level: level, nature: nature).effectiveStats(),
                               base.effective(level: level, nature: nature),
                               "Lv.\(level) \(String(describing: nature)) 에서 갈라졌다")
            }
        }
    }

    /// **성격이 숫자를 움직인다.** 종족값을 그대로 띄우면 안 되는 이유가 이것이다 — 이 앱엔 민트가
    /// 있는데, 성격을 바꿔도 화면이 그대로면 민트를 쓰는 의미가 사라진다.
    func testNatureChangesTheNumbers() {
        let neutral = base.effective(level: 50, nature: .hardy)     // 보정 없음
        let physical = base.effective(level: 50, nature: .adamant)  // 공격 ↑ 특공 ↓

        XCTAssertGreaterThan(physical.atk, neutral.atk)
        XCTAssertLessThan(physical.spa, neutral.spa)
        XCTAssertEqual(physical.def, neutral.def, "보정 없는 칸은 그대로")
        XCTAssertEqual(physical.hp, neutral.hp, "HP 에는 성격 보정이 없다")
    }

    /// 레벨이 오르면 전부 오른다 — 레벨을 안 먹이면 표가 개체와 무관한 상수가 된다.
    func testEveryStatGrowsWithLevel() {
        let low = base.effective(level: 5, nature: nil)
        let high = base.effective(level: 100, nature: nil)
        for stat in [\BattleStats.hp, \.atk, \.def, \.spa, \.spd, \.spe] {
            XCTAssertGreaterThan(high[keyPath: stat], low[keyPath: stat])
        }
    }

    /// 본가 공식 표본 하나 — 식을 "고쳤다" 며 통째로 바꾸면 위 비교 테스트는 둘 다 틀린 채로도
    /// 초록이다. 바깥에서 검산할 값이 하나는 있어야 한다.
    /// Lv.100 · 무보정 · IV31 · EV0: HP = 2×108+31+100+10 = 357, 공격 = (2×130+31)+5 = 296.
    func testTheFormulaMatchesTheMainlineNumbers() {
        let stats = base.effective(level: 100, nature: nil)
        XCTAssertEqual(stats.hp, 357)
        XCTAssertEqual(stats.atk, 296)
    }
}

// MARK: 화면이 읽는 값

@MainActor
final class HomeStatSourceTests: XCTestCase {

    private let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                               rarity: .common, names: [1: ["ko": "포1", "en": "P1"]])
    private let base = BattleStats(hp: 45, atk: 49, def: 49, spa: 65, spd: 65, spe: 45)

    private func store() -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stat-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    /// 아직 못 받았으면 nil — 화면이 자리를 비운다. 0 으로 채우면 "능력치 0" 이라는 거짓이 뜬다.
    func testNoStatsBeforeTheProfileArrives() async {
        let companion = store()
        await companion.hatch(baseID: 1)
        XCTAssertNil(companion.currentStats)
    }

    func testStatsUseTheLoadedBaseWithThisMonsLevelAndNature() async throws {
        let companion = store()
        await companion.hatch(baseID: 1)
        companion.debugSetLoadedTypes([.grass], speciesID: 1, base: base)

        let mon = try XCTUnwrap(companion.state.active)
        XCTAssertEqual(companion.currentStats,
                       base.effective(level: companion.currentLevel, nature: mon.nature))
    }

    /// **개체가 바뀌면 남의 종족값으로 계산하지 않는다.** 빈 값은 화면이 자리를 비우지만,
    /// 그럴듯하게 틀린 숫자는 안 들킨다 — `currentTypes` 가 태그를 보는 것과 같은 이유다.
    func testStatsDisappearWhenTheyBelongToAnotherSpecies() async {
        let companion = store()
        await companion.hatch(baseID: 1)
        companion.debugSetLoadedTypes([.fire], speciesID: 4, base: base)   // 다른 종의 값
        XCTAssertNil(companion.currentStats)
    }

    /// 문구는 세 언어 모두 있어야 하고, 기준 레벨을 밝혀야 한다 — 안 밝히면 종족값으로 읽힌다.
    func testTheHeaderNamesTheLevelInAllThreeLanguages() {
        for language in AppLanguage.allCases {
            XCTAssertTrue(L(language).statsAtLevel(37).contains("37"), "\(language) 기준 레벨 누락")
        }
        XCTAssertNotEqual(L(.ko).statsAtLevel(37), L(.en).statsAtLevel(37))
        XCTAssertNotEqual(L(.ko).statsAtLevel(37), L(.ja).statsAtLevel(37))
    }
}
