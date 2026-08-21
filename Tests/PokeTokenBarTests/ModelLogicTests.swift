import XCTest
@testable import PokeTokenBar

final class BattleRankTests: XCTestCase {
    func testFixedStakeUsesTierGapAndCap() {
        XCTAssertEqual(BattleRank.stake(challenger: .init(points: 0), defender: .init(points: 400)), 5_000)
        XCTAssertEqual(BattleRank.stake(challenger: .init(points: 0), defender: .init(points: 3_999)), 45_000)
        XCTAssertEqual(BattleRank.stake(challenger: .init(points: 800), defender: .init(points: 400)), 0)
    }

    /// 랭크는 와이어로도 온다(`BattleRankProfile` — 상대가 채우는 값). 그래서 경계에서 자른다.
    /// 세이브 경로는 `SaveTransfer.sanitized` 가 이미 자르지만 와이어 경로엔 가드가 없었다.
    func testPointsAreClampedAtTheBoundary() throws {
        func decoded(_ raw: String) throws -> BattleRank {
            try JSONDecoder().decode(BattleRank.self, from: Data("{\"points\":\(raw)}".utf8))
        }
        XCTAssertEqual(try decoded("\(Int.max)").points, BattleRank.maximumPoints)
        XCTAssertEqual(try decoded("-5").points, 0)
        XCTAssertEqual(try decoded("450").points, 450, "정상 값은 그대로 통과한다")
        XCTAssertEqual(BattleRank(points: Int.max).points, BattleRank.maximumPoints,
                       "직접 생성도 같은 상한을 쓴다")
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

// MARK: 진화 아이템 커버리지

/// 앱이 파는 진화 아이템이 PokéAPI 의 `use-item` 진화를 덮지 못하면 그 종은 **진화할 방법이 없다**.
/// 빛의돌·어둠의돌·각성의돌이 빠져 있어 로즈레이드 등 8종이 그 상태였다(레벨을 올려도 아무 안내 없음).
final class EvolutionItemCoverageTests: XCTestCase {
    /// 앱 지원 범위(1~649)의 use-item 진화가 요구하는 아이템 키 전체.
    /// 지역폼 전용(가라르 등, 앱 범위 밖)은 제외한 실측값이다.
    private let requiredKeys: Set<String> = [
        "fire-stone", "water-stone", "thunder-stone", "leaf-stone",
        "moon-stone", "sun-stone", "shiny-stone", "dusk-stone", "dawn-stone",
    ]

    /// 지닌물건 진화(#89)가 요구하는 아이템 — 앱 지원 범위(1~649)에서 실제로 쓰이는 것만.
    /// 이게 없으면 야도킹·킹크로스·강철톤·밀로틱 등이 진화할 방법이 아예 없다.
    private let requiredHeldItemKeys: Set<String> = [
        "kings-rock", "metal-coat", "dragon-scale", "up-grade", "dubious-disc",
        "deep-sea-tooth", "deep-sea-scale", "protector", "electirizer", "magmarizer",
        "reaper-cloth", "razor-claw", "razor-fang", "prism-scale", "oval-stone",
    ]

    private var soldKeys: Set<String> {
        Set(ItemKind.allCases.compactMap(\.evolutionRule?.apiItemName))
    }

    func testEveryRequiredEvolutionItemIsSold() {
        let missing = requiredKeys.subtracting(soldKeys)
        XCTAssertTrue(missing.isEmpty, "이 아이템이 없으면 해당 진화는 도달 불가: \(missing.sorted())")
    }

    func testEveryRequiredHeldItemIsSold() {
        let missing = requiredHeldItemKeys.subtracting(soldKeys)
        XCTAssertTrue(missing.isEmpty, "지닌물건 진화가 도달 불가: \(missing.sorted())")
    }

    /// 진화 아이템 키는 PokéAPI 의 item.name 과 정확히 같아야 매칭된다 — 오타 하나면 그 아이템은
    /// 아무 포켓몬도 진화시키지 못하고(조용히 재화만 소모) 스프라이트도 깨진다(파일명이 같은 값).
    func testEvolutionKeysUseApiItemNaming() {
        let allowed = requiredKeys.union(requiredHeldItemKeys)
            .union(["ice-stone", "sachet", "whipped-dream"])   // 앱 범위 밖이지만 함께 파는 것
        for kind in ItemKind.allCases {
            guard let key = kind.evolutionRule?.apiItemName else { continue }
            XCTAssertEqual(key, key.lowercased(), "\(kind) 키는 소문자여야 한다: \(key)")
            XCTAssertFalse(key.contains("_"), "\(kind) 키는 kebab-case 여야 한다: \(key)")
            XCTAssertTrue(allowed.contains(key), "\(kind) 키가 API 명명과 다르다: \(key)")
            XCTAssertEqual(kind.spriteName, key, "\(kind) 스프라이트 파일명은 API 아이템명과 같다")
        }
    }

    /// 새 아이템도 상점에 값이 있어야 산다 — nil 이면 목록에 안 뜬다.
    func testNewStonesArePurchasable() {
        for kind in [ItemKind.shinyStone, .duskStone, .dawnStone] {
            XCTAssertEqual(kind.shopPrice, 500, "\(kind) 가격이 기존 돌과 달라졌다")
            XCTAssertFalse(kind.isPassive)
        }
    }

    /// 진화 아이템은 종류를 가리지 않고 같은 값·같은 소모형이어야 한다 — 하나라도 shopPrice 가
    /// nil 이면 상점 목록에서 빠져 그 종은 진화 경로가 없는 상태로 되돌아간다.
    func testEveryEvolutionItemIsSoldAtTheSamePrice() {
        for kind in ItemKind.allCases where kind.isEvolutionItem {
            XCTAssertEqual(kind.shopPrice, ItemKind.evolutionItemPrice, "\(kind) 가격이 다르다")
            XCTAssertFalse(kind.isPassive, "\(kind) 는 쓰면 소모되는 아이템이다")
        }
    }
}
