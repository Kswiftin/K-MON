import XCTest
@testable import PokeTokenBar

final class BattleRankTests: XCTestCase {
    func testFixedStakeUsesTierGapAndCap() {
        XCTAssertEqual(BattleRank.stake(challenger: .init(points: 0), defender: .init(points: 400)), 5_000)
        XCTAssertEqual(BattleRank.stake(challenger: .init(points: 0), defender: .init(points: 3_999)), 45_000)
        XCTAssertEqual(BattleRank.stake(challenger: .init(points: 800), defender: .init(points: 400)), 0)
    }

    func testOnlyHigherRankedLoserDrops() {
        var lower = BattleRank(points: 0)
        var higher = BattleRank(points: 450)
        XCTAssertEqual(lower.apply(win: false, opponent: higher), 0)
        XCTAssertLessThan(higher.apply(win: false, opponent: lower), 0)
    }
}

// 순수 모델/파생 로직 — 네트워크·프로세스 없이 결정적으로 검증.

private func evoNode(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }

// MARK: EvoLine 다국어 이름 폴백

final class EvoLineNameTests: XCTestCase {
    func testPicksLanguageSpecificThenFallsBackToEnglishThenID() {
        let line = EvoLine(
            baseID: 1, tree: evoNode(1), rarity: .common,
            names: [
                1: ["ja-Hrkt": "ピカ", "ja": "ピカチュウ", "en": "Pika", "ko": "피카"],
                2: ["en": "Eevee"],   // ja/ko 없음 → en 폴백
                3: [:],               // 비어 있음 → #id
            ])
        // ja 는 ja-Hrkt 를 ja 보다 먼저 시도
        XCTAssertEqual(line.localizedName(1, .ja), "ピカ")
        XCTAssertEqual(line.localizedName(1, .ko), "피카")
        XCTAssertEqual(line.localizedName(1, .en), "Pika")
        // 해당 언어 없으면 en 폴백
        XCTAssertEqual(line.localizedName(2, .ja), "Eevee")
        XCTAssertEqual(line.localizedName(2, .ko), "Eevee")
        // en 도 없으면 #id
        XCTAssertEqual(line.localizedName(3, .ko), "#3")
        // 아예 없는 id
        XCTAssertEqual(line.localizedName(99, .en), "#99")
    }

    func testJaFallsBackFromHrktToPlainJa() {
        let line = EvoLine(baseID: 1, tree: evoNode(1), rarity: .common,
                           names: [1: ["ja": "ピカチュウ", "en": "Pika"]])
        XCTAssertEqual(line.localizedName(1, .ja), "ピカチュウ")   // ja-Hrkt 없음 → ja
    }
}

// MARK: EvoLine 에셋 지원 범위

final class EvoLineAssetTests: XCTestCase {
    /// PokéAPI 원본 체인에 Gen-V 이후 진화형이 이어져도, 서비스가 제공하는 GIF가 있는 형태만
    /// 실제 진화 라인과 단계 수에 남아야 한다. 예: 망키(#56) → 성원숭(#57) → 저승갓숭(#979).
    func testKeepsOnlyFormsWithAnimatedAssets() {
        let line = EvoLine(
            baseID: 56,
            tree: evoNode(56, [evoNode(57, [evoNode(979)])]),
            rarity: .common,
            names: [:])

        XCTAssertEqual(line.totalForms, 2)
        XCTAssertEqual(line.tree.finalIDs, [57])
        XCTAssertNil(line.tree.node(withID: 979))
    }
}

// MARK: EvoNode 트리 연산

final class EvoNodeTests: XCTestCase {
    // 1 → {2 → 3, 4}  (분기: 3단 경로 + 2단 경로)
    private let tree = EvoNode(speciesID: 1, children: [
        EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])]),
        EvoNode(speciesID: 4, children: []),
    ])

    func testDepthIsLongestPath() {
        XCTAssertEqual(tree.depth, 3)            // 1-2-3
        XCTAssertEqual(evoNode(20).depth, 1)     // 무진화
    }

    func testNodeLookupByID() {
        XCTAssertEqual(tree.node(withID: 3)?.speciesID, 3)
        XCTAssertEqual(tree.node(withID: 4)?.speciesID, 4)
        XCTAssertNil(tree.node(withID: 99))
    }

    func testFinalIDsAreLeaves() {
        XCTAssertEqual(Set(tree.finalIDs), [3, 4])
        XCTAssertEqual(evoNode(20).finalIDs, [20])   // 잎이 곧 최종체
    }
}

// MARK: 희귀도 경계

final class RarityBoundaryTests: XCTestCase {
    func testCaptureRateBoundaries() {
        XCTAssertEqual(Rarity.from(captureRate: 45, isLegendary: false, isMythical: false), .rare)      // <=45
        XCTAssertEqual(Rarity.from(captureRate: 46, isLegendary: false, isMythical: false), .uncommon)
        XCTAssertEqual(Rarity.from(captureRate: 120, isLegendary: false, isMythical: false), .uncommon) // <=120
        XCTAssertEqual(Rarity.from(captureRate: 121, isLegendary: false, isMythical: false), .common)
    }

    func testLegendaryAndMythicalOverrideCaptureRate() {
        XCTAssertEqual(Rarity.from(captureRate: 255, isLegendary: true, isMythical: false), .legendary)
        XCTAssertEqual(Rarity.from(captureRate: 255, isLegendary: false, isMythical: true), .legendary)
    }
}

// MARK: MonState / CompanionState 영속

final class StatePersistenceLogicTests: XCTestCase {
    func testCurrentIDClampsToPath() {
        let m = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 1, usedAtStage: 0, rarity: .common, totalForms: 3)
        XCTAssertEqual(m.currentID, 2)
        // stageIndex 가 경로를 넘어가도 마지막으로 클램프 (방어)
        let over = MonState(baseID: 1, pathIDs: [1], stageIndex: 5, usedAtStage: 0, rarity: .common, totalForms: 1)
        XCTAssertEqual(over.currentID, 1)
    }

    func testMonStateDecodeClampsStageIndexToRealizedPathBounds() throws {
        let upper = #"{"baseID":1,"pathIDs":[1,2],"stageIndex":5,"usedAtStage":0,"rarity":"common","totalForms":2}"#
        let lower = #"{"baseID":1,"pathIDs":[1,2],"stageIndex":-1,"usedAtStage":0,"rarity":"common","totalForms":2}"#

        let decodedUpper = try JSONDecoder().decode(MonState.self, from: Data(upper.utf8))
        let decodedLower = try JSONDecoder().decode(MonState.self, from: Data(lower.utf8))

        XCTAssertEqual(decodedUpper.stageIndex, 1)
        XCTAssertEqual(decodedLower.stageIndex, 0)
    }

    func testMonStateRoundTripPreservesDistinctPlannedPath() throws {
        let state = MonState(baseID: 265, pathIDs: [265], plannedPathIDs: [265, 266, 267],
                             stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)

        let decoded = try JSONDecoder().decode(MonState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.pathIDs, [265])
        XCTAssertEqual(decoded.plannedPathIDs, [265, 266, 267])
    }

    func testMonStateLegacyDecodeUsesRealizedPathAsPlan() throws {
        let legacy = """
        {"baseID":265,"pathIDs":[265,266],"stageIndex":1,"usedAtStage":0,"rarity":"common","totalForms":3}
        """

        let decoded = try JSONDecoder().decode(MonState.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.pathIDs, [265, 266])
        XCTAssertEqual(decoded.plannedPathIDs, [265, 266])
    }

    func testMonStateEmptySavedPlanUsesRealizedPath() throws {
        let saved = """
        {"baseID":265,"pathIDs":[265,266],"plannedPathIDs":[],"stageIndex":1,"usedAtStage":0,"rarity":"common","totalForms":3}
        """

        let decoded = try JSONDecoder().decode(MonState.self, from: Data(saved.utf8))

        XCTAssertEqual(decoded.plannedPathIDs, [265, 266])
    }

    func testMonStateEmptyInitialPlanUsesRealizedPath() {
        let state = MonState(baseID: 265, pathIDs: [265, 266], plannedPathIDs: [],
                             stageIndex: 1, usedAtStage: 0, rarity: .common, totalForms: 3)

        XCTAssertEqual(state.plannedPathIDs, [265, 266])
    }

    func testCompanionStateEncodeDecodeRoundTrip() throws {
        var st = CompanionState()
        st.economyVersion = 2
        st.usedSinceInstall = 42
        st.eggUsage = 1234
        st.lastTickAt = Date(timeIntervalSince1970: 1_700_000_000)
        st.lastCandyDate = "2026-06-27"
        st.collectedFinals = ["1:3", "10:12"]
        st.language = .ja
        st.dex = [DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .rare, caughtAt: nil)]

        let data = try JSONEncoder().encode(st)
        let back = try JSONDecoder().decode(CompanionState.self, from: data)

        XCTAssertEqual(back.economyVersion, 2)
        XCTAssertEqual(back.usedSinceInstall, 42)
        XCTAssertEqual(back.eggUsage, 1234)
        XCTAssertEqual(back.lastTickAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(back.lastCandyDate, "2026-06-27")
        XCTAssertEqual(back.collectedFinals, ["1:3", "10:12"])
        XCTAssertEqual(back.language, .ja)
        XCTAssertEqual(back.dex.count, 1)
        XCTAssertEqual(back.dex[0].chainOrder, [1, 2, 3])
    }
}

// MARK: 친밀도 진화 → 레벨 환산

/// PokéAPI 는 친밀도 진화를 min_level 없이(trigger=level-up + min_happiness) 준다. 앱엔 친밀도 축이
/// 없어 그대로 두면 레벨 게이트를 못 타고 트리거 게이트에도 막혀 **영영 진화하지 않는다** —
/// 앱 지원 범위(1~649)에서 크로뱃·에브이·블래키·루카리오·치렁 등 17건이 여기 걸렸다.
final class FriendshipEvolutionTests: XCTestCase {
    /// 원본에 실재하는 두 단계(160·220)가 서로 다른 레벨로 갈려야 한다 — 한 값으로 뭉치면
    /// 본가에서 더 어려운 축(피츄→피카츄, 꼬몽울→치렁)이 같은 난이도로 내려앉는다.
    func testTwoHappinessTiersMapToDistinctLevels() {
        XCTAssertEqual(PokemonBalance.friendshipLevel(minHappiness: 160), 25)
        XCTAssertEqual(PokemonBalance.friendshipLevel(minHappiness: 220), 30)
        XCTAssertLessThan(PokemonBalance.friendshipLevel(minHappiness: 160),
                          PokemonBalance.friendshipLevel(minHappiness: 220))
    }

    /// 하한은 직전 단계 진화 레벨보다 뒤여야 순서가 뒤집히지 않는다(주뱃→골뱃 22 → 크로뱃).
    func testMapsAboveTypicalFirstStageEvolutionLevel() {
        XCTAssertGreaterThan(PokemonBalance.friendshipLevel(minHappiness: 160), 22)
    }

    /// 도달 가능해야 한다 — 레벨 상한(100) 안이고, 무진화 졸업 기준을 넘지 않는다.
    func testStaysWithinReachableLevels() {
        for happiness in [160, 220] {
            let level = PokemonBalance.friendshipLevel(minHappiness: happiness)
            XCTAssertLessThanOrEqual(level, PokemonBalance.graduationRequiredLevel)
            XCTAssertGreaterThan(level, 1)
        }
    }
}
