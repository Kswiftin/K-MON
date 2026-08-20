import XCTest
@testable import PokeTokenBar

// 도감 완성 목표 — 종·타입·이로치 세 축.
//
// 진행도는 **어디에도 저장되지 않는다**. `state.dex` 는 항목이 빠지지 않으므로 진행도가 파생값이고,
// 지급은 도감을 바꾸기 전후 완료 집합의 차집합으로만 일어난다. 그래서 수령 플래그도 클램프도 없다.
final class DexGoalTests: XCTestCase {

    // MARK: 카탈로그

    /// id 는 알림·차집합이 목표를 되찾는 키다 — 중복되면 두 목표가 서로를 덮어쓴다.
    func testCatalogIDsAreUnique() {
        XCTAssertEqual(Set(DexGoals.catalog.map(\.id)).count, DexGoals.catalog.count)
    }

    /// 종류별 목표는 오름차순이어야 한다. 뒤섞이면 "아직 안 넘은 첫 목표"(표시용)가 엉뚱한 칸을 가리킨다.
    func testCatalogTargetsAscendWithinEachKind() {
        for kind in DexGoalKind.allCases {
            let targets = DexGoals.catalog.filter { $0.kind == kind }.map(\.target)
            XCTAssertFalse(targets.isEmpty, "\(kind) 에 목표가 하나도 없다")
            XCTAssertEqual(targets, targets.sorted(), "\(kind) 목표가 오름차순이 아니다")
            XCTAssertTrue(targets.allSatisfy { $0 > 0 })
        }
    }

    /// 보상이 비면 목표를 넘겨도 아무 일이 없다 — 사용자에겐 표시만 바뀌는 죽은 칸이다.
    func testEveryGoalPaysSomething() {
        XCTAssertTrue(DexGoals.catalog.allSatisfy { !$0.reward.isEmpty })
    }

    /// 목표 이름은 세 언어 모두에서 채워져야 한다 — 한 언어만 비면 그 언어 사용자에겐 빈 줄이 보인다.
    /// (`missionName` 과 같은 계약: 이름 없는 목표는 빈 문자열을 돌려 여기서 실패한다.)
    func testEveryGoalIsNamedInAllThreeLanguages() {
        for goal in DexGoals.catalog {
            for lang in [AppLanguage.ko, .en, .ja] {
                XCTAssertFalse(L(lang).dexGoalName(goal).isEmpty, "\(goal.id) / \(lang)")
            }
        }
    }

    func testGoalLookupByIDFindsEveryCatalogEntry() {
        for goal in DexGoals.catalog {
            XCTAssertEqual(DexGoals.goal(id: goal.id)?.id, goal.id)
        }
        XCTAssertNil(DexGoals.goal(id: "nope"))
    }

    // MARK: 진행도 (순수)

    func testEmptyDexCompletesNothing() {
        for kind in DexGoalKind.allCases {
            XCTAssertEqual(DexGoals.progress(kind, in: []), 0)
        }
        XCTAssertTrue(DexGoals.completed(in: []).isEmpty)
    }

    /// 종 수는 라인 전체(chainOrder)를 세고 **중복을 제거한다** — 같은 라인을 두 번 졸업시켜도 안 오른다.
    func testSpeciesProgressCountsUniqueSpeciesAcrossChains() {
        let dex = [entry(chain: [1, 2, 3]), entry(chain: [1, 2, 3]), entry(chain: [4, 5])]
        XCTAssertEqual(DexGoals.progress(.species, in: dex), 5)
    }

    /// 타입도 중복 제거. 같은 타입 조합을 여러 번 졸업시켜도 커버리지는 그대로다.
    func testTypeProgressCountsUniqueTypes() {
        let dex = [entry(chain: [1], types: [.grass, .poison]),
                   entry(chain: [2], types: [.grass, .poison]),
                   entry(chain: [3], types: [.fire])]
        XCTAssertEqual(DexGoals.progress(.types, in: dex), 3)
    }

    /// `types == nil` 은 "아직 모름" 이다 — 커버리지에 넣으면 백필 전 구버전 도감이 사실과 다른 수를 보인다.
    func testTypeProgressIgnoresEntriesWithUnknownTypes() {
        let dex = [entry(chain: [1], types: nil), entry(chain: [2], types: [.water])]
        XCTAssertEqual(DexGoals.progress(.types, in: dex), 1)
    }

    /// 이로치는 **개체 수**다(종 수가 아니다) — 같은 종을 두 번 이로치로 졸업시키면 2다.
    func testShinyProgressCountsShinyEntries() {
        let dex = [entry(chain: [1], shiny: true), entry(chain: [1], shiny: true), entry(chain: [2])]
        XCTAssertEqual(DexGoals.progress(.shiny, in: dex), 2)
    }

    // MARK: 차집합 (재지급 방어의 전부)

    /// 완료 집합은 도감이 자랄 때 줄어들지 않는다 — 이 단조성이 차집합 지급의 전제다.
    func testCompletedNeverShrinksAsTheDexGrows() {
        var dex: [DexEntry] = []
        var previous: Set<String> = []
        for id in 1...60 {
            dex.append(entry(chain: [id],
                             types: [PokemonType.allCases[id % PokemonType.allCases.count]],
                             shiny: id % 7 == 0))
            let now = DexGoals.completed(in: dex)
            XCTAssertTrue(previous.isSubset(of: now), "\(id)번째 항목에서 완료 목표가 사라졌다")
            previous = now
        }
    }

    /// 한 번에 두 목표를 넘기면 차집합에 **둘 다** 들어와야 한다.
    /// (마지막 하나만 지급하는 구현이면 여기서 잡힌다.)
    func testCrossingTwoGoalsAtOnceYieldsBothInTheDifference() {
        let before = (1...9).map { entry(chain: [$0]) }                  // 종 9, 이로치 0
        let after = before + [entry(chain: [10], shiny: true)]           // 종 10, 이로치 1

        let newly = DexGoals.completed(in: after).subtracting(DexGoals.completed(in: before))

        XCTAssertEqual(newly, ["species10", "shiny1"])
    }

    /// 이미 넘긴 목표는 차집합에 다시 나오지 않는다.
    func testAnAlreadyCompletedGoalNeverReappears() {
        let before = (1...12).map { entry(chain: [$0]) }
        let after = before + [entry(chain: [13])]

        XCTAssertTrue(DexGoals.completed(in: before).contains("species10"))
        XCTAssertFalse(DexGoals.completed(in: after)
            .subtracting(DexGoals.completed(in: before)).contains("species10"))
    }

    private func entry(chain: [Int], types: [PokemonType]? = nil, shiny: Bool = false) -> DexEntry {
        DexEntry(baseID: chain[0], finalID: chain[chain.count - 1], chainOrder: chain,
                 rarity: .common, caughtAt: nil, isShiny: shiny, types: types)
    }
}

// MARK: 지급 경로

@MainActor
final class DexGoalGrantTests: XCTestCase {

    /// 도감을 세이브 파일에 심는다 — `state` 세터는 비공개고, 테스트 편의로 그걸 열면
    /// 프로덕션에서도 상태를 통째로 갈아 끼울 수 있다(`TrainerLevelAccrualTests` 와 같은 판단).
    private func makeStore(_ clock: TestClock,
                          species: Int = 0,
                          types: [PokemonType] = [],
                          shinyCharges: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-dexgoal-\(UUID().uuidString).json")
        // 종 id 는 스텁 라인(1~3)과 겹치지 않게 100번대부터 — 겹치면 졸업이 종 수를 못 늘린다.
        var entries = (0..<species).map { i in
            #"{"baseID":\#(100 + i),"finalID":\#(100 + i),"chainOrder":[\#(100 + i)],"rarity":"common"}"#
        }
        // 타입 커버리지는 별도 항목에 싣는다 — 종 수와 독립적으로 조절하려고.
        for (i, type) in types.enumerated() {
            entries.append(#"{"baseID":\#(200 + i),"finalID":\#(200 + i),"chainOrder":[\#(200 + i)],"#
                + #""rarity":"common","types":["\#(type.rawValue)"]}"#)
        }
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"shinyEggCharges":\#(shinyCharges),"#
            + #""dex":[\#(entries.joined(separator: ","))]}"#
        try? Data(json.utf8).write(to: url)
        return CompanionStore(provider: StubProvider(value: dexGoalTestLine), clock: clock.closure,
                              fileURL: url, rng: SeededRNG(seed: 11))
    }

    /// 부화 → 최종형까지 성장 → 졸업 준비 완료. 졸업 한 번이 종 3개(1·2·3)를 도감에 넣는다.
    private func hatchedStore(_ clock: TestClock,
                              species: Int = 0,
                              types: [PokemonType] = [],
                              shinyCharges: Int = 0) async -> CompanionStore {
        let store = makeStore(clock, species: species, types: types, shinyCharges: shinyCharges)
        await store.hatch(baseID: 1)
        XCTAssertNotNil(store.state.active, "테스트 전제: 활성 포켓몬이 있어야 졸업시킬 수 있다")
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))
        XCTAssertTrue(store.canGraduate, "테스트 전제: 졸업 가능 상태여야 한다")
        return store
    }

    /// 목표를 넘는 순간 보상이 실제로 들어온다 — 종 7 + 졸업(종 3개) = 10 → `species10`.
    func testGraduationPaysAGoalTheFirstTimeItIsCrossed() async {
        let clock = TestClock()
        let store = await hatchedStore(clock, species: 7)
        let eggsBefore = store.state.focusEggs

        XCTAssertTrue(store.graduateCompanion())

        XCTAssertEqual(DexGoals.progress(.species, in: store.state.dex), 10)
        XCTAssertEqual(store.state.focusEggs - eggsBefore, 1, "알 1개가 보관 알로 들어와야 한다")
        XCTAssertEqual(store.state.focusEggReadyDates.count, store.state.focusEggs,
                       "보관 알 개수와 부화 예정 시각 개수가 어긋나면 안 된다")
    }

    /// 목표에 못 닿았으면 도감 목표 몫은 나가지 않는다.
    func testGraduationBelowEveryTargetPaysNoGoalReward() async {
        let clock = TestClock()
        let store = await hatchedStore(clock, species: 3)
        let eggsBefore = store.state.focusEggs

        XCTAssertTrue(store.graduateCompanion())

        XCTAssertEqual(DexGoals.progress(.species, in: store.state.dex), 6)
        XCTAssertEqual(store.state.focusEggs, eggsBefore)
        XCTAssertTrue(DexGoals.completed(in: store.state.dex).isEmpty)
    }

    /// **소급 지급 없음** — 이미 목표를 넘긴 도감으로 시작하면 첫 졸업이 그 목표를 지급하지 않는다.
    /// (차집합의 "이전" 스냅샷이 현재 도감이라 자동으로 성립한다. 로드 시점에 훑는 구현이면 여기서 깨진다.)
    func testAlreadyPassedGoalsAreNotPaidRetroactively() async {
        let clock = TestClock()
        let store = await hatchedStore(clock, species: 12)
        let eggsBefore = store.state.focusEggs

        XCTAssertTrue(store.graduateCompanion())

        XCTAssertEqual(store.state.focusEggs, eggsBefore, "이미 넘긴 species10 이 다시 지급되면 안 된다")
    }

    /// 같은 목표는 두 번 지급되지 않는다 — 넘긴 뒤 졸업을 더 해도 그대로다.
    func testTheSameGoalIsNeverPaidTwice() async {
        let clock = TestClock()
        let store = await hatchedStore(clock, species: 7)
        XCTAssertTrue(store.graduateCompanion())
        let eggsAfterFirst = store.state.focusEggs

        // 두 번째 개체를 같은 라인으로 부화시켜 졸업 — 종 수는 이미 담긴 1·2·3 이라 안 오른다.
        await store.hatch(baseID: 1)
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))
        XCTAssertTrue(store.graduateCompanion())

        XCTAssertEqual(store.state.focusEggs, eggsAfterFirst, "species10 이 두 번 지급됐다")
    }

    /// 한 졸업이 두 목표를 넘기면 **둘 다** 지급된다 — 종 10 + 이로치 1.
    /// 이로치 확정(`shinyEggCharges`)을 심어 부화 결과를 고정한다.
    func testCrossingTwoGoalsAtOncePaysBoth() async {
        let clock = TestClock()
        let store = await hatchedStore(clock, species: 7, shinyCharges: 1)
        XCTAssertEqual(store.state.active?.isShiny, true, "테스트 전제: 이로치 개체여야 한다")
        let eggsBefore = store.state.focusEggs
        let dustBefore = store.state.starPieces

        XCTAssertTrue(store.graduateCompanion())

        XCTAssertEqual(store.state.focusEggs - eggsBefore, 1, "species10 의 알")
        XCTAssertGreaterThanOrEqual(store.state.starPieces - dustBefore, 2_000, "shiny1 의 별의조각")
    }

    /// **진행도 되감기 방어** — 키우는 중인 개체는 세지 않는다.
    /// `dexEntries`(활성·박스 합성 포함)로 계산하면 알을 새로 살 때 진행도가 줄고, 다음 졸업에서
    /// 같은 목표가 다시 지급된다.
    func testRaisedButUngraduatedPokemonDoNotCountTowardGoals() async {
        let clock = TestClock()
        let store = await hatchedStore(clock, species: 9)

        XCTAssertGreaterThan(store.dexEntries.count, store.state.dex.count,
                             "테스트 전제: 아직 졸업하지 않은 개체가 화면용 목록에만 있어야 한다")
        XCTAssertEqual(DexGoals.progress(.species, in: store.state.dex), 9,
                       "졸업 전에는 키우는 개체가 종 수를 올리지 않는다")
        XCTAssertFalse(DexGoals.completed(in: store.state.dex).contains("species10"))
    }

    /// 타입을 모르는 채(오프라인) 졸업하면 `[]` 가 아니라 **nil** 로 남아야 한다.
    /// `[]` 로 저장하면 "타입 없음" 이 되어 백필이 영영 재시도하지 않는다.
    func testGraduatingWithoutTypeDataStoresNilNotEmpty() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)

        XCTAssertTrue(store.graduateCompanion())

        let recorded = store.state.dex.last
        XCTAssertNotNil(recorded)
        XCTAssertNil(recorded?.types, "타입을 모를 때 빈 배열을 저장하면 백필이 멈춘다")
    }

    /// 타입 커버리지가 모자라면 타입 목표는 나가지 않는다 — 졸업 항목의 타입이 nil 이라
    /// 커버리지가 오르지 않는 경로를 그대로 밟는다.
    func testATypeGoalStaysUnpaidWhileCoverageIsShort() async {
        let clock = TestClock()
        let eight: [PokemonType] = [.normal, .fire, .water, .electric, .grass, .ice, .fighting, .poison]
        let store = await hatchedStore(clock, species: 3, types: eight)
        let eggsBefore = store.state.focusEggs

        XCTAssertTrue(store.graduateCompanion())

        XCTAssertEqual(DexGoals.progress(.types, in: store.state.dex), 8)
        XCTAssertEqual(store.state.focusEggs, eggsBefore, "types9 에 못 닿았으면 알이 없다")
    }

    /// 표시용 행 — 종류마다 **아직 안 넘은 첫 목표** 하나씩.
    func testGoalRowsShowTheNextUnclearedTargetPerKind() async {
        let clock = TestClock()
        let store = await hatchedStore(clock, species: 12)

        let rows = store.dexGoalRows

        XCTAssertEqual(rows.count, DexGoalKind.allCases.count)
        XCTAssertEqual(rows.first { $0.goal.kind == .species }?.goal.id, "species25",
                       "종 12 면 10 은 넘었고 다음은 25 다")
        XCTAssertEqual(rows.first { $0.goal.kind == .species }?.progress, 12)
        XCTAssertEqual(rows.first { $0.goal.kind == .shiny }?.goal.id, "shiny1")
    }
}

// MARK: 세이브 무결성 — 1회성 보상 상태 (기존 공백 스윕)

final class OneShotRewardSignatureTests: XCTestCase {

    /// `DexEntry.types` 는 무결성 canonical 에 들어가지 않는다(`dex` 줄은 baseID:finalID:rarity 뿐).
    /// 들어가면 백필이 저장하는 순간 기존 서명이 전부 무효가 되어 정상 세이브가 조작 판정된다.
    /// 해시가 아니라 **canonical 문자열**을 비교한다 — 해시끼리 비교하면 양쪽이 같이 바뀌어도 통과한다.
    func testDexEntryTypesDoNotAffectTheIntegritySignature() {
        var withoutTypes = CompanionState()
        withoutTypes.dex = [DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3],
                                     rarity: .common, caughtAt: nil)]
        var withTypes = withoutTypes
        withTypes.dex[0].types = [.grass, .poison]

        XCTAssertEqual(SaveTransfer.canonicalString(withTypes),
                       SaveTransfer.canonicalString(withoutTypes))
        XCTAssertFalse(SaveTransfer.isTampered(SaveTransfer.signed(withTypes)))
    }

    /// 체육관 배지는 첫 승리 보상의 **유일한** 멱등 가드다(`recordGymVictory`). 서명 밖에 있으면
    /// 세이브에서 배지 키를 지우는 것만으로 같은 체육관에서 알을 다시 받을 수 있다.
    func testDeletingAGymBadgeAfterSigningIsDetected() {
        var state = CompanionState()
        state.gymBadges = ["bug", "rock"]
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed))

        signed.gymBadges = ["bug"]
        XCTAssertTrue(SaveTransfer.isTampered(signed), "배지가 무결성 해시에 들어가 있어야 한다")
    }

    /// 같은 배지 집합은 순회 순서와 무관하게 같은 서명을 내야 한다 — `Set` 순회는 실행마다 다르다.
    func testGymBadgeSignatureDoesNotDependOnSetOrder() {
        var a = CompanionState(); a.gymBadges = ["water", "bug", "rock"]
        var b = CompanionState(); b.gymBadges = ["rock", "water", "bug"]
        XCTAssertEqual(SaveTransfer.canonicalString(a), SaveTransfer.canonicalString(b))
    }

    /// 이로치 확정 부화 횟수를 손으로 올리면 잡혀야 한다 — 올리면 확정 이로치가 공짜다.
    func testEditingShinyEggChargesAfterSigningIsDetected() {
        var state = CompanionState()
        state.shinyEggCharges = 1
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed))

        signed.shinyEggCharges = 99
        XCTAssertTrue(SaveTransfer.isTampered(signed))
    }

    /// 조건부 append 여야 한다 — 기본값 상태의 canonical 이 바뀌면 그 필드가 없던 시절의
    /// 정상 세이브가 전부 조작 판정된다. (`testDefaultStateCanonicalFormIsFrozen` 의 짝.)
    func testDefaultStateGainsNoNewCanonicalSegments() {
        let canonical = SaveTransfer.canonicalString(CompanionState())
        XCTAssertFalse(canonical.contains("|gb"))
        XCTAssertFalse(canonical.contains("|shc"))
    }
}

// 부화용 최소 진화 라인(1 → 2 → 3).
private let dexGoalTestLine: EvoLine = {
    var names: [Int: [String: String]] = [:]
    for id in [1, 2, 3] { names[id] = ["en": "D\(id)", "ko": "도\(id)", "ja": "ド\(id)"] }
    return EvoLine(baseID: 1,
                   tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                   rarity: .common, names: names)
}()
