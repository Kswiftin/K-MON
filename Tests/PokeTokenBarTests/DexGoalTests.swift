import XCTest
@testable import PokeTokenBar

// 도감 완성 목표 — 종·타입·이로치 세 축.
//
// 진행도는 **어디에도 저장되지 않는다**. `state.dex` 는 항목이 빠지지 않으니 진행도가 파생값이고
// 지급은 도감을 바꾸기 전후 완료 집합의 차집합으로만 일어난다 — 수령 플래그도 클램프도 없다.
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

    /// 졸업은 그 자체로 보상 알 1개를 준다(`CompanionStore.graduate()` 끝부분). 도감 목표 몫은
    /// **그 위에 얹힌다** — 이 값을 빼놓으면 목표를 넘기지 않은 졸업도 "알이 늘었다"로 보인다.
    private let eggsFromGraduationItself = 1

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
        XCTAssertEqual(store.state.focusEggs - eggsBefore, eggsFromGraduationItself + 1,
                       "species10 의 알 1개가 졸업 보상 알 위에 더해져야 한다")
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
        XCTAssertEqual(store.state.focusEggs - eggsBefore, eggsFromGraduationItself,
                       "졸업 보상 알만 들어오고 도감 목표 몫은 없어야 한다")
        XCTAssertTrue(DexGoals.completed(in: store.state.dex).isEmpty)
    }

    /// **소급 지급 없음** — 이미 목표를 넘긴 도감으로 시작하면 첫 졸업이 그 목표를 지급하지 않는다.
    /// (차집합의 "이전" 스냅샷이 현재 도감이라 자동으로 성립한다. 로드 시점에 훑는 구현이면 여기서 깨진다.)
    func testAlreadyPassedGoalsAreNotPaidRetroactively() async {
        let clock = TestClock()
        let store = await hatchedStore(clock, species: 12)
        let eggsBefore = store.state.focusEggs

        XCTAssertTrue(store.graduateCompanion())

        XCTAssertEqual(store.state.focusEggs - eggsBefore, eggsFromGraduationItself,
                       "이미 넘긴 species10 이 다시 지급되면 안 된다")
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

        XCTAssertEqual(store.state.focusEggs - eggsAfterFirst, eggsFromGraduationItself,
                       "두 번째 졸업에는 졸업 보상 알만 들어와야 한다 — species10 이 두 번 지급됐다")
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

        XCTAssertEqual(store.state.focusEggs - eggsBefore, eggsFromGraduationItself + 1,
                       "species10 의 알")
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
        XCTAssertEqual(store.state.focusEggs - eggsBefore, eggsFromGraduationItself,
                       "types9 에 못 닿았으면 도감 목표 몫은 없다")
    }

    /// 도감 헤더의 두 숫자가 서로를 설명해야 한다 — **총계 − 육성중 = 목표 줄의 종 진행도**.
    /// 총계(`dexSpecies`)는 키우는 개체까지 세고 목표 줄은 졸업 기록만 세므로, 육성중 수를 따로
    /// 보여주지 않으면 "도감 12종" 과 "종 9/10" 이 나란히 보여 왜 보상이 없는지 알 수 없다.
    func testDexHeaderTotalAccountsForRaisingSpecies() async {
        let clock = TestClock()
        let store = await hatchedStore(clock, species: 9)   // 졸업분 9종 + 키우는 라인 3종

        let all = store.dexSpecies
        let raising = all.filter(\.isRaising).count

        XCTAssertEqual(raising, 3, "테스트 전제: 아직 졸업 안 한 라인이 총계에 섞여 있어야 한다")
        XCTAssertEqual(all.count - raising, DexGoals.progress(.species, in: store.state.dex))
        // 언어를 고정한다 — 신규 설치 기본값은 `.systemDefault` 라 `store.l` 은 CI 로케일에 딸려간다.
        XCTAssertEqual(L(.ko).dexSpeciesTotal(all.count, raising: raising), "12종 (3 육성중)")
        XCTAssertEqual(L(.ko).dexSpeciesTotal(9, raising: 0), "9종",
                       "육성중이 없으면 기존 문구 그대로여야 한다")
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

    /// 도감 목표의 멱등 가드는 **진행도의 단조성**뿐이다(수령 플래그가 없다 — `DexGoals` 주석).
    /// 그래서 진행도가 읽는 `DexEntry` 필드가 서명 밖에 있으면, 그 값을 내려 적는 것만으로
    /// 진행도가 되감기고 다음 졸업이 같은 보상을 재지급한다.
    private func signedDex(_ entry: DexEntry) -> CompanionState {
        var state = CompanionState()
        state.dex = [entry]
        let signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed), "테스트 전제: 서명 직후는 정상이어야 한다")
        return signed
    }

    /// 이로치 플래그를 내리면 이로치 진행도가 줄어 `shiny3` 이 다시 지급 가능해진다.
    func testLoweringADexEntryShinyFlagAfterSigningIsDetected() {
        var signed = signedDex(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3],
                                        rarity: .common, caughtAt: nil, isShiny: true))
        signed.dex[0].isShiny = false
        XCTAssertTrue(SaveTransfer.isTampered(signed),
                      "이로치 진행도를 내려 적으면 shiny 목표를 다시 받을 수 있다")
    }

    /// 라인을 잘라내면 종 진행도가 줄어 `species50` 이 다시 지급 가능해진다.
    func testShrinkingADexEntryChainAfterSigningIsDetected() {
        var signed = signedDex(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3],
                                        rarity: .common, caughtAt: nil))
        signed.dex[0].chainOrder = [1]
        XCTAssertTrue(SaveTransfer.isTampered(signed))
    }

    /// 타입을 지우면 타입 커버리지가 줄어 `types18` 이 다시 지급 가능해진다.
    ///
    /// 이 필드는 한때 "백필이 저장하는 순간 기존 서명이 무효가 된다" 는 이유로 서명 밖에 두었지만,
    /// 백필도 `save()` 를 지나며 재서명되므로 그 근거는 성립하지 않는다. 실제 제약은
    /// "이미 배포된 필드" 규칙이고 `integrityVersion` 7 은 아직 미배포라 지금이 넣을 수 있는 창이다.
    func testDeletingDexEntryTypesAfterSigningIsDetected() {
        var signed = signedDex(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3],
                                        rarity: .common, caughtAt: nil, types: [.grass, .poison]))
        signed.dex[0].types = nil
        XCTAssertTrue(SaveTransfer.isTampered(signed))
    }

    /// 세그먼트에 담기는 건 **숫자 세 개**(종·타입·이로치)여야 한다 — 목표 id 를 담으면 카탈로그
    /// 목표값 조정(`species50` → `40`)이 정상 세이브를 전부 조작 판정으로 만든다(밸런스 손잡이가
    /// 세이브 파괴 손잡이가 된다). 해시가 아니라 canonical 문자열을 본다 — 해시끼리 비교하면
    /// 양쪽이 같이 바뀌어도 통과한다.
    func testTheDexProgressSegmentCarriesCountsNotGoalIDs() {
        var state = CompanionState()
        state.dex = [DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common,
                              caughtAt: nil, isShiny: true, types: [.grass, .poison])]

        let canonical = SaveTransfer.canonicalString(state)

        XCTAssertTrue(canonical.contains("|dg3|2|1"), "종 3·타입 2·이로치 1 — 실제: \(canonical)")
        XCTAssertFalse(canonical.contains("species10"), "목표 id 가 들어가면 카탈로그 조정이 서명을 깬다")
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

    func testCurrentGymLeagueBadgeIsSignedSeparatelyFromLegacyBadges() {
        var state = CompanionState()
        state.gymBadges = ["bug"]
        state.gymLeagueBadges = ["bug"]
        var signed = SaveTransfer.signed(state)
        XCTAssertFalse(SaveTransfer.isTampered(signed))

        signed.gymLeagueBadges = []
        XCTAssertTrue(SaveTransfer.isTampered(signed), "현행 리그 키도 알 보상 멱등성을 위해 서명한다")
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
        XCTAssertFalse(canonical.contains("|glb"))
        XCTAssertFalse(canonical.contains("|shc"))
        XCTAssertFalse(canonical.contains("|dg"), "도감이 비면 진행도 세그먼트도 붙지 않는다")
    }

    /// **조건부 append 만으로는 부족한 경우** — `gymBadges`·`shinyEggCharges` 는 이전 배포에도 있던
    /// 필드라, 값이 든 정상 세이브는 세그먼트가 붙어 구서명과 안 맞는다. 방어는 `integrityVersion`
    /// 상향뿐이다(낮은 버전은 검사 면제 → 다음 저장에서 갱신). 안 올리면 배지를 딴 세이브가 전부 초기화된다.
    func testASaveSignedBeforeTheCanonicalChangeIsNotJudgedTampered() {
        var old = CompanionState()
        old.gymBadges = ["bug"]
        old.shinyEggCharges = 2
        old.integrityVersion = 6          // gb·shc 가 canonical 에 없던 시절의 서명
        old.integrity = "deadbeef"        // 새 canonical 로는 절대 안 맞는 값

        XCTAssertFalse(SaveTransfer.isTampered(old),
                       "구버전 서명이 조작 판정되면 배지·이로치 확정이 있던 세이브가 전부 초기화된다")

        // 대조군: 현재 버전으로 다시 서명하면 같은 편집이 잡힌다(면제가 영구가 아니다).
        var resigned = SaveTransfer.signed(old)
        resigned.shinyEggCharges = 99
        XCTAssertTrue(SaveTransfer.isTampered(resigned))
    }
}

// MARK: 저장되는 타입의 출처 — 스테일 방어와 백필

private enum TypedProviderError: Error { case unknownSpecies }

/// 타입을 돌려주는 스텁. `DexEntry.types` 는 세이브에 남으므로 이 조회는 주입 가능해야 한다 —
/// `PokeAPIClient.shared` 를 직접 부르면 이 파일의 테스트가 전부 실네트워크에 걸린다.
private struct TypedProvider: PokeProviding {
    let evoLine: EvoLine
    /// 등록되지 않은 종은 throw — 오프라인과 같은 경로다.
    let types: [Int: [PokemonType]]

    func line(baseSpeciesID: Int) async throws -> EvoLine { evoLine }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: evoLine.baseID, captureRate: 255)] }
    func battleProfile(speciesID: Int) async throws -> PokemonBattleProfile {
        guard let t = types[speciesID] else { throw TypedProviderError.unknownSpecies }
        return PokemonBattleProfile(speciesID: speciesID,
                                    stats: BattleStats(hp: 1, atk: 1, def: 1, spa: 1, spd: 1, spe: 1),
                                    types: t)
    }
}

@MainActor
final class DexEntryTypeSourceTests: XCTestCase {

    private func store(_ types: [Int: [PokemonType]], dex: [String] = []) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-dextype-\(UUID().uuidString).json")
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"dex":[\#(dex.joined(separator: ","))]}"#
        try? Data(json.utf8).write(to: url)
        return CompanionStore(provider: TypedProvider(evoLine: dexGoalTestLine, types: types),
                              clock: TestClock().closure, fileURL: url, rng: SeededRNG(seed: 11))
    }

    private func growToFinal(_ store: CompanionStore) async {
        await store.hatch(baseID: 1)
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))
        XCTAssertEqual(store.currentSpeciesID, 3, "테스트 전제: 최종형(3)까지 자라야 한다")
    }

    /// **트리거 재현** — 타입을 1단계(종 1)에서 받아 두고 최종형(종 3)까지 자란 뒤 졸업한다.
    /// 로드한 타입에 "어느 종의 것인가"가 없으면 종 1 의 타입이 종 3 항목에 영구 저장되고
    /// `types != nil` 이라 백필도 못 고친다. 개체가 바뀌는 경로(부화·박스 교체·불러오기)마다 같은 일이
    /// 생기니 리셋이 아니라 읽는 자리에서 막는다.
    func testGraduationNeverStoresTypesLoadedForAnotherSpecies() async {
        let store = self.store([1: [.grass], 3: [.fire, .flying]])
        await store.hatch(baseID: 1)
        await store.loadCurrentTypes()                     // 종 1 의 타입을 적재
        XCTAssertEqual(store.currentTypes, [.grass], "테스트 전제: 1단계 타입이 실제로 적재돼야 한다")
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))

        XCTAssertTrue(store.graduateCompanion())

        XCTAssertNil(store.state.dex.last?.types,
                     "종 1 의 타입이 종 3 항목에 저장됐다 — nil 이어야 백필이 고칠 수 있다")
    }

    /// 대조군 — 최종형 타입을 적재한 뒤 졸업하면 그 값이 저장된다(게이트가 항상 nil 로 만들지 않는다).
    func testGraduationStoresTheTypesLoadedForTheFinalForm() async {
        let store = self.store([1: [.grass], 3: [.fire, .flying]])
        await growToFinal(store)
        await store.loadCurrentTypes()

        XCTAssertTrue(store.graduateCompanion())

        XCTAssertEqual(store.state.dex.last?.types, [.fire, .flying])
    }

    /// 백필은 타입만 채우고 **보상은 지급하지 않는다** — 지급하면 구버전 세이브가 백필 한 번에
    /// 타입 목표를 소급 달성해 알을 한꺼번에 받는다.
    func testBackfillFillsTypesWithoutPayingTypeGoals() async {
        let nine: [PokemonType] = [.normal, .fire, .water, .electric, .grass, .ice, .fighting, .poison, .ground]
        let entries = nine.indices.map { i in
            #"{"baseID":\#(200 + i),"finalID":\#(200 + i),"chainOrder":[\#(200 + i)],"rarity":"common"}"#
        }
        let store = self.store(Dictionary(uniqueKeysWithValues: nine.indices.map { (200 + $0, [nine[$0]]) }),
                              dex: entries)
        XCTAssertEqual(DexGoals.progress(.types, in: store.state.dex), 0, "테스트 전제: 타입이 비어 있어야 한다")
        let eggsBefore = store.state.focusEggs

        await store.backfillMissingDexTypes()

        XCTAssertEqual(DexGoals.progress(.types, in: store.state.dex), 9)
        XCTAssertTrue(DexGoals.completed(in: store.state.dex).contains("types9"))
        XCTAssertEqual(store.state.focusEggs, eggsBefore, "백필이 소급 지급하면 안 된다")
    }

    /// 조회가 실패하면(오프라인) `[]` 가 아니라 nil 로 남아야 한다 — `[]` 는 "타입 없음"이라
    /// 백필이 영영 재시도하지 않는다.
    func testBackfillLeavesTypesNilWhenTheLookupFails() async {
        let entry = #"{"baseID":200,"finalID":200,"chainOrder":[200],"rarity":"common"}"#
        let store = self.store([:], dex: [entry])

        await store.backfillMissingDexTypes()

        XCTAssertNil(store.state.dex.first?.types)
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
