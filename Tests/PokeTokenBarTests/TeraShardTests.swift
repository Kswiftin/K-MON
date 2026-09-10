import XCTest
@testable import PokeTokenBar

/// 라인 로딩 없는 provider — 테라피스는 `currentLine` 과 무관하다(테라 타입은 `MonState` 에 있다).
private struct TeraShardNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// 테라피스 — 테라스탈했을 때 되는 타입을 바꾸는 아이템.
///
/// 지금까지 테라 타입은 **첫 번째 타입에서 파생**했다. 그래서 "테라 타입이 원래에 없던 타입"
/// 이라는 갈래가 `BattleEngine.stabbed` 에 식으로만 있고 아무도 밟지 않았다. 이 아이템이 그
/// 갈래를 살린다 — 그래서 STAB 세 갈래를 여기서 함께 잠근다.
@MainActor
final class TeraShardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(_ types: [PokemonType] = [.water],
                          teraType: PokemonType? = nil) -> BattleSnapshot {
        BattleSnapshot(speciesID: 7, name: "테스트", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 100),
                       storedTeraType: teraType, weightHectograms: 100)
    }

    /// 활성 포켓몬 + 테라피스 재고를 지정한 세이브. 테라 타입을 미리 박아 둘 수도 있다.
    private func store(shards: Int = 1, teraType: PokemonType? = nil) -> CompanionStore {
        store(at: storeStateURL("terashard"), shards: shards, teraType: teraType)
    }

    /// 같은 파일을 두 번 열어야 하는 테스트(저장 확인)를 위해 경로를 받는 갈래.
    /// `storeStateURL` 은 부를 때마다 **새 디렉토리**를 파므로 두 번 부르면 다른 세이브가 된다.
    private func store(at url: URL, shards: Int = 1, teraType: PokemonType? = nil) -> CompanionStore {
        let tera = teraType.map { ",\"teraType\":\"\($0.rawValue)\"" } ?? ""
        let active = "{\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":0,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false\(tera)}"
        let inv = shards > 0 ? ",\"inventory\":{\"teraShard\":\(shards)}" : ""
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,"
            + "\"installBaselineSet\":true,\"usedSinceInstall\":1000000000,\"spentTokens\":0,"
            + "\"starPieces\":1000000000,\"lastDate\":\"d\",\"active\":\(active),\"dex\":[],"
            + "\"collectedFinals\":[]\(inv)}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: TeraShardNoProvider(), clock: { self.now },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    // MARK: 스냅샷 — 저장 값과 파생 폴백

    /// 값이 없으면 **첫 번째 타입**에서 파생한다(지금까지의 규칙 그대로). 이 폴백이 없으면
    /// 테라피스를 안 쓴 개체 전부가 노말로 테라스탈한다.
    func testTeraTypeFallsBackToTheFirstTypeWhenNothingIsStored() {
        XCTAssertEqual(snapshot([.water, .flying]).teraType, .water)
        XCTAssertEqual(snapshot([]).teraType, .normal, "타입이 비면 노말로 접는다")
    }

    /// 저장 값이 있으면 그것이 이긴다 — 파생을 먼저 보는 오구현은 아이템이 아무 일도 안 하게 만든다.
    func testAStoredTeraTypeWinsOverTheFirstType() {
        XCTAssertEqual(snapshot([.water, .flying], teraType: .fairy).teraType, .fairy)
    }

    /// **와이어에 실린다.** 안 실으면 두 피어가 같은 개체를 다른 타입으로 테라스탈시켜, 상성
    /// 배율부터 갈린다(화면에는 각자 정상으로 보인다).
    func testTheStoredTeraTypeSurvivesTheWire() throws {
        let sent = snapshot([.water], teraType: .fairy)
        let received = try JSONDecoder().decode(BattleSnapshot.self,
                                                from: JSONEncoder().encode(sent))
        XCTAssertEqual(received.storedTeraType, .fairy)
        XCTAssertEqual(received, sent)
    }

    /// 이 필드가 없던 피어·세이브의 payload 는 그대로 디코딩되고 파생으로 접힌다.
    func testAPayloadWithoutTheFieldStillDecodes() throws {
        let json = """
        {"v":1,"speciesID":7,"name":"old","level":50,"isShiny":false,"types":["water"],
         "base":{"hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100}}
        """
        let decoded = try JSONDecoder().decode(BattleSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(decoded.storedTeraType)
        XCTAssertEqual(decoded.teraType, .water)
    }

    /// 스냅샷을 만드는 자리가 이 값을 싣는지는 소스에서 센다 — 한 자리만 빠지면 그 모드의
    /// 개체만 옛 규칙으로 테라스탈하고, 화면에는 아무 오류도 안 보인다.
    /// (`VariableDamageTests.testEveryBattleSnapshotSiteCarriesTheWireOnlyFields` 가 그 스캔이다.)
    func testTheSnapshotScanCountsTheTeraTypeField() throws {
        let sources = try SourceScan.sources().filter { $0.code.contains("BattleSnapshot(") }
        XCTAssertFalse(sources.isEmpty)
        for (name, code) in sources where !code.contains("struct BattleSnapshot") {
            XCTAssertTrue(code.contains("storedTeraType:"),
                          "\(name) 의 스냅샷이 테라 타입을 안 싣는다")
        }
    }

    // MARK: STAB 세 갈래 — 이 아이템이 살리는 죽은 갈래

    private func side(_ types: [PokemonType], teraType: PokemonType?,
                      terastallized: Bool) -> BattleSide {
        var out = BattleSide(snapshot(types, teraType: teraType))
        out.isTerastallized = terastallized
        return out
    }

    /// 테라 타입이 **원래에 없던 타입**일 때: 그 타입 기술도, 옛 타입 기술도 1.5배다(2배는 없다).
    /// 이 갈래는 테라피스가 붙기 전까지 도달 불가였다.
    func testAnAcquiredTeraTypeGivesOneAndAHalfOnBothSides() {
        let attacker = side([.water], teraType: .fairy, terastallized: true)
        XCTAssertEqual(BattleEngine.stabbed(100, of: .fairy, by: attacker), 150,
                       "얻은 테라 타입 기술은 1.5배다")
        XCTAssertEqual(BattleEngine.stabbed(100, of: .water, by: attacker), 150,
                       "접혀 나간 옛 타입 기술도 1.5배로 남는다")
        XCTAssertEqual(BattleEngine.stabbed(100, of: .fire, by: attacker), 100,
                       "둘 다 아닌 타입은 보정이 없다")
    }

    /// 대조군 — 테라 타입이 원래 타입이기도 하면 그 기술만 2배다(옛 규칙이 살아 있어야 한다).
    func testATeraTypeThatWasAlreadyOriginalStillDoublesd() {
        let attacker = side([.water, .flying], teraType: .water, terastallized: true)
        XCTAssertEqual(BattleEngine.stabbed(100, of: .water, by: attacker), 200)
        XCTAssertEqual(BattleEngine.stabbed(100, of: .flying, by: attacker), 150)
    }

    /// 테라스탈하지 않았으면 저장 값은 데미지에 아무 영향이 없다 — 아이템이 상시 강화가 되면
    /// 안 된다.
    func testAStoredTeraTypeDoesNothingUntilTerastallized() {
        let attacker = side([.water], teraType: .fairy, terastallized: false)
        XCTAssertEqual(BattleEngine.stabbed(100, of: .fairy, by: attacker), 100)
        XCTAssertEqual(BattleEngine.stabbed(100, of: .water, by: attacker), 150)
    }

    /// 테라스탈 선언 줄과 현재 타입도 저장 값을 본다 — `stabbed` 만 고치면 로그와 상성이 갈린다.
    func testTheDeclarationLineAndActiveTypesFollowTheStoredType() {
        var side = self.side([.water], teraType: .fairy, terastallized: false)
        XCTAssertEqual(BattleEngine.declareTerastal(&side, actor: .a),
                       [.terastallized(.a, .fairy)])
        XCTAssertEqual(side.activeTypes, [.fairy])
    }

    // MARK: 아이템 — 값·분류·문구

    /// 진화 아이템이 아니다. 이 판정이 틀리면 상점가가 진화 아이템 공통가로 접히고, 가방의
    /// `default:` 분기가 "진화 가능할 때 사용" 을 띄운다.
    func testTheShardIsNotAnEvolutionItem() {
        XCTAssertNil(ItemKind.teraShard.evolutionRule)
        XCTAssertFalse(ItemKind.teraShard.isEvolutionItem)
        XCTAssertNil(ItemKind.teraShard.roomReaction)
    }

    /// 스프라이트가 없어 이모지로 떨어진다(민트와 같은 이유 — 9세대 아이템이라 PokéAPI 에 없다).
    func testTheShardFallsBackToAnEmoji() {
        XCTAssertNil(ItemKind.teraShard.spriteName)
        XCTAssertFalse(ItemKind.teraShard.fallbackEmoji.isEmpty)
    }

    /// 값은 민트와 사탕 사이다 — 민트(성격)와 같은 코스메틱이지만 대전 성능을 바꾸므로 더 비싸고,
    /// 성장 1회분(사탕)보다는 싸다.
    func testTheShardIsPricedBetweenTheMintAndTheCandy() throws {
        let price = try XCTUnwrap(ItemKind.teraShard.shopPrice)
        XCTAssertGreaterThan(price, Mint.price)
        XCTAssertLessThan(price, RareCandy.price)
    }

    /// 이름·효과 문구가 채워져 있다. 하나라도 비면 가방에 빈 줄이 뜬다.
    func testTheShardIsNamed() {
        let l = L()
        XCTAssertFalse(l.itemName(.teraShard).isEmpty)
        XCTAssertFalse(l.teraShardEffectHint.isEmpty)
        XCTAssertTrue(ItemKind.nameable.contains(.teraShard),
                      "이름표에 없으면 대화·터미널이 이 아이템을 부를 수 없다")
    }

    /// **아이템 하나는 가방 갈래 하나로 답해야 한다** — `bagUse` 가 없던 동안 가방은 같은 질문을
    /// 네 자리에서 따로 물었고, 진화가 아닌 새 아이템은 네 곳에 다 적어야 했다. 한 자리만
    /// 빠뜨리면 컴파일은 통과한 채 "진화 가능할 때 사용" 이 뜨고 `useEvolutionItem` 으로 흘러간다
    /// (`heartScale` 의 주석이 경고하던 함정이고, 테라피스에서 실제로 한 자리가 빠졌다).
    ///
    /// 그 빠뜨림은 이제 **컴파일 오류**다(네 switch 가 `default:` 없이 `bagUse` 를 훑는다).
    /// 여기서는 축 자체가 진화 규칙과 어긋나지 않는지만 본다.
    func testTheBagAxisAgreesWithTheEvolutionRule() {
        for kind in ItemKind.allCases {
            XCTAssertEqual(kind.bagUse == .evolutionItem, kind.isEvolutionItem,
                           "\(kind.rawValue) 의 가방 갈래와 진화 규칙이 어긋난다")
            XCTAssertEqual(kind.bagUse == .furniture, kind.roomReaction != nil)
        }
        XCTAssertEqual(ItemKind.teraShard.bagUse, .teraShard)
    }

    /// **모든 아이템에 설명이 있다.** 설명이 진화 갈래로 흘러간 아이템은 빈 문자열이 되고,
    /// 가방·상점에 빈 줄이 뜬다(문구를 안 적었다는 신호가 화면에 안 나온다).
    func testEveryItemHasADescription() {
        let l = L()
        for kind in ItemKind.allCases {
            XCTAssertFalse(l.itemDescription(kind).isEmpty, "\(kind.rawValue) 의 설명이 비었다")
            XCTAssertFalse(l.itemName(kind).isEmpty, "\(kind.rawValue) 의 이름이 비었다")
        }
    }

    // MARK: 사용 경로

    func testCannotUseWithoutStock() {
        XCTAssertFalse(store(shards: 0).canUseTeraShard)
        XCTAssertTrue(store(shards: 1).canUseTeraShard)
    }

    /// 한 개 쓰면 테라 타입이 **반드시 바뀌고** 재고가 하나 줄어든다(민트와 같은 규칙).
    ///
    /// **18종을 다 시작 타입으로 넣어 본다.** 하나만 쓰면 후보에서 제외하지 않는 오구현도 그 seed
    /// 가 우연히 다른 타입을 뽑아 통과한다(실제로 결함 주입에서 그렇게 지나갔다 —
    /// `docs/reference/defect-log.md` "확률 tie-break 에 기대는 테스트" 와 같은 부류다).
    /// 18종을 다 돌리면 제외를 안 하는 구현은 반드시 한 번 자기 타입을 뽑는다.
    func testUsingAShardAlwaysChangesTheTeraTypeAndSpendsOne() throws {
        for current in PokemonType.allCases {
            let s = store(shards: 2, teraType: current)
            let new = try XCTUnwrap(s.useTeraShard())
            XCTAssertNotEqual(new, current, "\(current) 로 시작하면 같은 타입이 다시 나온다")
            XCTAssertEqual(s.state.active?.teraType, new)
            XCTAssertEqual(s.itemCount(.teraShard), 1)
        }
    }

    /// 재고가 없으면 아무것도 소모하지 않고 `nil` 이다.
    func testUsingAShardWithoutStockChangesNothing() {
        let s = store(shards: 0, teraType: .fairy)
        XCTAssertNil(s.useTeraShard())
        XCTAssertEqual(s.state.active?.teraType, .fairy)
    }

    /// 저장된 값이 없던 개체도 쓸 수 있다 — 그때 후보는 18종 전체다(민트가 성격 nil 을 다루는
    /// 방식과 같다). 안 열어 두면 구버전 개체가 이 아이템을 영영 못 쓴다.
    func testAMonWithNoStoredTypeCanStillUseAShard() {
        let s = store(shards: 1, teraType: nil)
        XCTAssertNotNil(s.useTeraShard())
        XCTAssertNotNil(s.state.active?.teraType)
    }

    /// 대화·터미널이 쓰는 공유 경로도 같은 스토어 메서드를 지난다 — 갈래를 따로 쓰면 한쪽만
    /// 고쳐져 "대화로는 되는데 가방으로는 안 되는" 아이템이 생긴다.
    func testTheSharedActionPathUsesTheShard() throws {
        let s = store(shards: 1, teraType: .fairy)
        let outcome = CompanionAction.useItem(.teraShard, companion: s)
        guard case .teraShard(let type) = outcome else { return XCTFail("teraShard 결과가 아니다") }
        XCTAssertNotEqual(type, .fairy)
        XCTAssertEqual(s.itemCount(.teraShard), 0)
    }

    /// 재고가 없으면 공유 경로도 `.unavailable` 이다(진화 거절과 갈라 둔다).
    func testTheSharedActionPathReportsAnEmptyBag() {
        let s = store(shards: 0)
        XCTAssertEqual(CompanionAction.useItem(.teraShard, companion: s), .unavailable)
    }

    /// 세이브에 실린다 — 저장을 안 하면 앱을 다시 켤 때 바꾼 타입이 사라진다.
    func testTheTeraTypeSurvivesTheSave() throws {
        let url = storeStateURL("terashard")
        let s = store(at: url, shards: 1, teraType: nil)
        let new = try XCTUnwrap(s.useTeraShard())
        let reopened = CompanionStore(provider: TeraShardNoProvider(), clock: { self.now },
                                      fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(reopened.state.active?.teraType, new)
    }
}
