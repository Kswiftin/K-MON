import XCTest
@testable import PokeTokenBar

final class BattleRankTests: XCTestCase {
    func testLegacyRankProfileDefaultsBeginnerBadgeToOff() throws {
        let data = Data(#"{"rank":{"points":100},"stardust":5000}"#.utf8)
        let decoded = try JSONDecoder().decode(BattleRankProfile.self, from: data)
        XCTAssertFalse(decoded.beginnerMode)
        let modern = BattleRankProfile(rank: BattleRank(points: 100), stardust: 5_000,
                                       beginnerMode: true)
        XCTAssertTrue(try JSONDecoder().decode(BattleRankProfile.self,
                                                from: JSONEncoder().encode(modern)).beginnerMode)
    }

    func testFixedStakeUsesTierGapAndCap() {
        XCTAssertEqual(BattleRank.stake(challenger: .init(points: 0), defender: .init(points: 400)), 5_000)
        XCTAssertEqual(BattleRank.stake(challenger: .init(points: 0), defender: .init(points: 3_999)), 20_000)
        XCTAssertEqual(BattleRank.stake(challenger: .init(points: 800), defender: .init(points: 400)), 0)
    }

    func testPokemonChampionsTierOrderAndRanks() {
        XCTAssertEqual(BattleRank(points: 0).displayName, "Poké Ball R4 · 0 LP")
        XCTAssertEqual(BattleRank(points: 399).displayName, "Poké Ball R1 · 99 LP")
        XCTAssertEqual(BattleRank(points: 400).displayName, "Great Ball R4 · 0 LP")
        XCTAssertEqual(BattleRank(points: 800).tier, .ultraBall)
        XCTAssertEqual(BattleRank(points: 1_200).tier, .masterBall)
        XCTAssertEqual(BattleRank(points: 1_599).displayName, "Master Ball R1 · 99 LP")
        XCTAssertEqual(BattleRank(points: 1_600).displayName, "Champion · 0 RP")
        XCTAssertEqual(BattleRank(points: 3_999).displayName, "Champion · 2399 RP")
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
/// 앱 지원 범위에서 크로뱃·에브이·블래키·루카리오·치렁 등 17건이 여기 걸렸다.
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
    /// 획득 가능 종(1~1025 − `spriteGaps`)의 use-item 진화가 요구하는 아이템 키 전체.
    /// PokéAPI GraphQL 실측값이다(2026-09-02).
    ///
    /// 가라두구팔찌·가라두구머리장식은 뺐다 — 대상이 야도란(80)·야도킹(199)의 **가라르 폼**이라
    /// 종 번호는 이미 레벨·교환으로 도달하는 것과 같고, 이 앱은 지역폼을 구분하지 않는다.
    /// 넣으면 이미 열려 있는 진화에 값만 받는 두 번째 문이 생긴다.
    private let requiredKeys: Set<String> = [
        "fire-stone", "water-stone", "thunder-stone", "leaf-stone", "ice-stone",
        "moon-stone", "sun-stone", "shiny-stone", "dusk-stone", "dawn-stone",
        "tart-apple", "sweet-apple", "syrupy-apple",
        "cracked-pot", "chipped-pot", "unremarkable-teacup", "masterpiece-teacup",
        "scroll-of-darkness", "scroll-of-waters",
        "black-augurite", "peat-block",
        "auspicious-armor", "malicious-armor", "metal-alloy",
    ]

    /// 지닌물건 진화(#89)가 요구하는 아이템 — 획득 가능 종에서 실제로 쓰이는 것 전부.
    /// 이게 없으면 야도킹·킹크로스·강철톤·밀로틱 등이 진화할 방법이 아예 없다.
    private let requiredHeldItemKeys: Set<String> = [
        "kings-rock", "metal-coat", "dragon-scale", "up-grade", "dubious-disc",
        "deep-sea-tooth", "deep-sea-scale", "protector", "electirizer", "magmarizer",
        "reaper-cloth", "razor-claw", "razor-fang", "prism-scale", "oval-stone",
        "sachet", "whipped-dream",
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
            .union(["ice-stone"])   // 지역폼 전용이라 requiredKeys 엔 없지만 예전부터 파는 것
        for kind in ItemKind.allCases {
            guard let key = kind.evolutionRule?.apiItemName else { continue }
            XCTAssertEqual(key, key.lowercased(), "\(kind) 키는 소문자여야 한다: \(key)")
            XCTAssertFalse(key.contains("_"), "\(kind) 키는 kebab-case 여야 한다: \(key)")
            XCTAssertTrue(allowed.contains(key), "\(kind) 키가 API 명명과 다르다: \(key)")
            XCTAssertEqual(kind.spriteName, key, "\(kind) 스프라이트 파일명은 API 아이템명과 같다")
        }
    }

    /// 지닌물건 아이템이 실제로 진화시키는 종 — 상점에 올린 아이템이 "쓸 수 있는 것" 인지 재는 기준.
    /// 손으로 적는 목록이지만 손으로 적는 것 자체가 게이트다: 새 아이템을 넣으면서 여기에 대상 종을
    /// 적어야 하고, 그 종이 스프라이트 범위 밖이면 아래 테스트가 막는다.
    private let heldItemTargets: [String: [Int]] = [
        "kings-rock": [186, 199],        // 왕구리·야도킹
        "metal-coat": [208, 212],        // 강철톤·핫삼
        "dragon-scale": [230],           // 킹드라
        "up-grade": [233],               // 폴리곤2
        "dubious-disc": [474],           // 폴리곤Z
        "deep-sea-tooth": [367],         // 헌테일
        "deep-sea-scale": [368],         // 분홍장이
        "protector": [464],              // 거대코뿔
        "electirizer": [466],            // 에레키블
        "magmarizer": [467],             // 마그마번
        "reaper-cloth": [477],           // 야느와르몬
        "razor-claw": [461, 903],        // 포푸니라 · 8세대 히스이 계열
        "razor-fang": [472],             // 글라이온
        "prism-scale": [350],            // 밀로틱
        "oval-stone": [113],             // 럭키
        "sachet": [683],
        "whipped-dream": [685],
    ]

    /// 상점에 올린 아이템이 **쓸 수 있는 아이템인지** 재는 게이트.
    ///
    /// 앱은 애니메이션 스프라이트가 있는 종만 다루고, 그 밖의 종은
    /// `EvoNode.keepingAnimatedSprites()` 가 진화 트리에서 지운다. 그래서 대상 종이 범위 밖인 아이템은
    /// **어떤 진화도 열지 못하는데 상점에는 그대로 뜬다** — 사는 순간 500 별의조각을 버리는 함정이다.
    /// 향기주머니·휘핑팝(마이앵·나룸퍼프 682~685)이 그래서 빠졌다.
    ///
    /// 스프라이트 범위가 아이템 유효성의 숨은 전제라는 게 요점이다. 아이템 쪽만 보면 아무 문제가 없어
    /// 보이고, 리뷰에서도 "PokéAPI 에 있는 아이템이니 맞다" 로 통과한다.
    func testEveryHeldItemHasATargetInsideTheSpriteRange() {
        for kind in ItemKind.allCases {
            guard case .heldItem(let key)? = kind.evolutionRule else { continue }
            let targets = heldItemTargets[key]
            XCTAssertNotNil(targets, "\(kind): 대상 종을 heldItemTargets 에 적어야 한다")
            for id in targets ?? [] {
                XCTAssertTrue(PokemonAssets.hasAnimatedSprite(speciesID: id),
                              "\(kind) 대상 #\(id) 이 스프라이트 범위 밖 — 이 아이템은 아무 진화도 못 열고 함정 구매가 된다")
            }
            XCTAssertFalse(targets?.isEmpty ?? true, "\(kind) 는 열 수 있는 진화가 없다")
        }
    }

    /// 획득 가능 종은 **연속 범위가 아니다.** 9세대 후반 14종은 애니메이션 GIF 가 없어 빠진다.
    /// 범위로 되돌리면(`1...1025`) 그 14종이 다시 뽑혀 멈춘 스프라이트로 나타난다.
    func testObtainableSpeciesSkipTheAnimationGaps() {
        XCTAssertEqual(PokemonAssets.speciesRange, 1...1025)
        XCTAssertEqual(PokemonAssets.obtainableSpeciesIDs.count,
                       1025 - PokemonAssets.spriteGaps.count)
        for gap in PokemonAssets.spriteGaps {
            XCTAssertFalse(PokemonAssets.hasAnimatedSprite(speciesID: gap), "#\(gap) 은 GIF 가 없다")
            XCTAssertFalse(PokemonAssets.obtainableSpeciesIDs.contains(gap))
        }
        // 세대별 대표 한 마리씩 — 상한만 올리고 구멍을 안 판 상태를 잡는다.
        for id in [1, 251, 386, 493, 649, 721, 809, 905, 1021] {
            XCTAssertTrue(PokemonAssets.hasAnimatedSprite(speciesID: id), "#\(id) 은 획득 가능해야 한다")
        }
        XCTAssertFalse(PokemonAssets.hasAnimatedSprite(speciesID: 1026), "종 번호 상한 밖")
        XCTAssertFalse(PokemonAssets.hasAnimatedSprite(speciesID: 0))
    }

    /// 야생 추첨이 구멍을 뽑으면 스프라이트 없는 상대가 필드에 선다. 풀 자체가 구멍을 안 갖는지 본다.
    func testWildPoolNeverContainsAGap() {
        XCTAssertTrue(PokemonAssets.spriteGaps.isDisjoint(with: Set(RogueRun.wildSpeciesPool)))
        XCTAssertFalse(RogueRun.wildSpeciesPool.isEmpty)
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
