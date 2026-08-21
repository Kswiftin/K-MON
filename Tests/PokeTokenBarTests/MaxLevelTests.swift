import XCTest
@testable import PokeTokenBar

/// 만렙(Lv.100) 경계(#81). 990,000,000 이 정확히 Lv.100 이라 **구간 나머지가 0** 이다 —
/// 만렙 가드가 없으면 다 키운 개체의 경험치 막대가 텅 빈 채로 그려졌다.
///
/// 경험치 누적은 클램프가 붙은 `MonState.gainExperience(_:)` 한 곳으로만 들어간다. 예전엔 누적
/// 지점이 세 곳이고 그중 이상한 사탕 경로만 클램프를 빠뜨려, 상한 위의 값이 저장되고
/// `SaveTransfer` 가 그 값을 조용히 되돌려 세이브를 옮긴 사람과 안 옮긴 사람의 데이터가 갈렸다.
@MainActor
final class MaxLevelTests: XCTestCase {

    private let line = EvoLine(baseID: 20, tree: EvoNode(speciesID: 20, children: []),
                               rarity: .common, names: [20: ["en": "P20", "ko": "포20"]])

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-maxlevel-\(UUID().uuidString).json")
    }

    private func store(at url: URL? = nil) -> CompanionStore {
        CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                       fileURL: url ?? tempURL(), rng: SeededRNG(seed: 7))
    }

    // MARK: 클램프 (MonState.gainExperience)

    func testExperienceStopsAtTheCap() {
        var mon = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1)
        mon.gainExperience(PokemonBalance.maxLevelExperience - 1)
        XCTAssertEqual(mon.level, 99, "전제: 상한 직전은 Lv.99 다")

        mon.gainExperience(RareCandy.xp)
        XCTAssertEqual(mon.levelExperience, PokemonBalance.maxLevelExperience,
                       "상한을 넘겨 저장하지 않는다")
        XCTAssertEqual(mon.level, PokemonBalance.maxLevel)
    }

    /// 손편집·구버전 세이브로 상한 위의 값이 들어와 있어도 더하는 순간 오버플로 트랩이 나면 안 된다.
    func testGainFromAnOverCapValueDoesNotOverflow() {
        var mon = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1)
        mon.levelExperience = Int.max
        mon.gainExperience(RareCandy.xp)
        XCTAssertEqual(mon.levelExperience, PokemonBalance.maxLevelExperience)
    }

    func testNonPositiveGainIsIgnored() {
        var mon = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1)
        mon.gainExperience(5_000_000)
        mon.gainExperience(-1_000_000)
        XCTAssertEqual(mon.levelExperience, 5_000_000, "음수 적립으로 레벨이 되감기지 않는다")
    }

    // MARK: 진행도 표시

    func testProgressIsFullAtMaxLevel() async {
        let s = store()
        await s.hatch(baseID: 20)
        s.debugAccrueLevelExperience(PokemonBalance.maxLevelExperience)

        XCTAssertEqual(s.currentLevel, PokemonBalance.maxLevel, "전제: 만렙에 닿았다")
        XCTAssertEqual(s.levelProgress, 1, "만렙 막대는 꽉 찬다 — 나머지가 0 이라고 빈 막대가 되면 안 된다")
        XCTAssertEqual(s.experienceToNextLevel, 0, "다음 레벨은 없다")
    }

    /// 대조군 — 구간 중간은 그 구간의 비율이어야 한다. 만렙 케이스만 두면 "항상 1" 도 통과한다.
    func testProgressIsProportionalBelowMaxLevel() async {
        let s = store()
        await s.hatch(baseID: 20)
        s.debugAccrueLevelExperience(PokemonBalance.experiencePerLevel * 2 + 5_000_000)

        XCTAssertEqual(s.currentLevel, 3)
        XCTAssertEqual(s.levelProgress, 0.5, accuracy: 0.0001)
    }

    // MARK: 누적 경로 (트리거 브랜치 = 상한 근처에서의 사탕 사용)

    func testRareCandyNearTheCapDoesNotStoreAnOverCapValue() async {
        let s = store()
        await s.hatch(baseID: 20)
        s.debugAccrueLevelExperience(PokemonBalance.maxLevelExperience - 1)
        s.debugAddCandy(1)

        _ = s.useRareCandy()

        XCTAssertEqual(s.state.active?.levelExperience, PokemonBalance.maxLevelExperience,
                       "사탕도 다른 누적 경로와 같은 상한을 지킨다")
        XCTAssertEqual(s.currentLevel, PokemonBalance.maxLevel)
    }

    // MARK: 외부 세이브 경계 (부류 스윕)

    /// `SaveTransfer.sanitized` 는 박스 개체만 자르고 **활성 개체의 경험치는 자르지 않았다.**
    /// 그 값에 사탕 XP 를 더하는 순간 오버플로 트랩으로 프로세스가 죽는다.
    func testSanitizeClampsTheActiveMonsExperience() throws {
        var state = CompanionState()
        var active = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                              rarity: .common, totalForms: 1)
        active.levelExperience = Int.max
        state.active = active
        var boxed = active
        boxed.levelExperience = Int.max
        state.boxedMons = [boxed]

        let clean = SaveTransfer.sanitized(state)

        XCTAssertEqual(clean.active?.levelExperience, PokemonBalance.maxLevelExperience)
        XCTAssertEqual(clean.boxedMons.first?.levelExperience, PokemonBalance.maxLevelExperience)
    }
}
