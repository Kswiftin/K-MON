import XCTest
@testable import PokeTokenBar

/// 라인 로딩 없는 provider — 지닌물건은 `currentLine` 과 무관하다(`MonState` 에 있다).
private struct HeldItemNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// 지닌물건 3종 — 생명의구슬(데미지 ×1.3 + 매 턴 자해)·기합의띠(만피에서 한 방 버틴다)·
/// 먹다남은음식(턴 끝 회복).
///
/// 테라피스(`TeraShardTests`)와 갈리는 점은 **개체에 붙어 배틀 안에서 일한다**는 것이다. 그래서
/// 검증이 세 층에 걸린다: 세이브(개체에 붙는다) → 와이어(스냅샷이 나른다) → 엔진(효과가 돈다).
/// 웨이브 런의 `RunBoosts.leftovers` 와 **합산**된다는 규칙도 여기서 잠근다 — 둘이 겹치는 판이
/// 실제로 있고, 한쪽만 보면 회복이 조용히 한 번 사라지거나 두 배가 된다.
@MainActor
final class HeldItemTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: 픽스처

    private func snapshot(hp: Int = 100, held: ItemKind? = nil,
                          moves: [MoveSpec]? = nil) -> BattleSnapshot {
        BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: [.normal],
                       base: BattleStats(hp: hp, atk: 100, def: 100, spa: 100, spd: 100, spe: 100),
                       moves: moves, heldItem: held, weightHectograms: 100)
    }

    private func side(hp: Int? = nil, held: ItemKind? = nil) -> BattleSide {
        var out = BattleSide(snapshot(held: held))
        if let hp { out.hp = hp }
        return out
    }

    private func attackMove(_ id: Int = 33, power: Int = 60,
                            damageClass: MoveDamageClass = .physical) -> MoveSpec {
        var move = MoveSpec(id: id, names: ["ko": "공격"], type: .normal, power: power,
                            damageClass: damageClass, accuracy: 100, pp: 10)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0
        move.targetsUser = false
        return move
    }

    @discardableResult
    private func hit(_ move: MoveSpec, by attacker: inout BattleSide, on defender: inout BattleSide,
                     seed: UInt64 = 7) -> [BattleEvent] {
        var rng = SplitMix64(seed: seed)
        return BattleEngine.applyHit(attacker: &attacker, defender: &defender,
                                     attackerActor: .a, defenderActor: .b,
                                     move: move, rng: &rng)
    }

    /// **최대 HP 는 종족값·레벨에서 파생한다** — 픽스처의 `base.hp` 를 그대로 만피로 쓰면 회복량·
    /// 자해량 기대값이 전부 어긋난다(실제로 처음 이 테스트가 그렇게 빨갰다).
    private func fullHP(_ side: BattleSide) -> Int { side.stats.hp }

    /// 데미지 줄에서 깎인 양만 뽑는다 — 이벤트 순서까지 보려는 테스트가 아니다.
    private func dealt(_ events: [BattleEvent]) -> Int {
        events.reduce(0) {
            if case .damage(.b, let amount, .move) = $1 { return $0 + amount }
            return $0
        }
    }

    /// 활성 포켓몬 + 지정 재고를 가진 세이브. 지니고 있는 물건도 미리 박을 수 있다.
    private func store(at url: URL, inventory: [ItemKind: Int] = [:],
                       held: ItemKind? = nil) -> CompanionStore {
        let heldJSON = held.map { ",\"heldItem\":\"\($0.rawValue)\"" } ?? ""
        let active = "{\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":0,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false\(heldJSON)}"
        let items = inventory.map { "\"\($0.key.rawValue)\":\($0.value)" }.sorted().joined(separator: ",")
        let inv = items.isEmpty ? "" : ",\"inventory\":{\(items)}"
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,"
            + "\"installBaselineSet\":true,\"usedSinceInstall\":1000000000,\"spentTokens\":0,"
            + "\"starPieces\":1000000000,\"lastDate\":\"d\",\"active\":\(active),\"dex\":[],"
            + "\"collectedFinals\":[]\(inv)}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: HeldItemNoProvider(), clock: { self.now },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    private func store(inventory: [ItemKind: Int] = [:], held: ItemKind? = nil) -> CompanionStore {
        store(at: storeStateURL("helditem"), inventory: inventory, held: held)
    }

    private static let three: [ItemKind] = [.lifeOrb, .focusSash, .leftovers]

    // MARK: - 아이템 축

    /// 셋 다 진화 아이템이 아니고 가구도 보유형도 아니다. 이 판정이 틀리면 상점가가 진화 아이템
    /// 공통가로 접히고 가방이 "진화 가능할 때 사용" 을 띄운다(하트비늘·테라피스와 같은 함정).
    func testTheThreeAreNotEvolutionItems() {
        for kind in Self.three {
            XCTAssertNil(kind.evolutionRule, "\(kind.rawValue)")
            XCTAssertFalse(kind.isEvolutionItem, "\(kind.rawValue)")
            XCTAssertFalse(kind.isPassive, "\(kind.rawValue)")
            XCTAssertNil(kind.roomReaction, "\(kind.rawValue)")
            XCTAssertEqual(kind.bagUse, .heldItem, "\(kind.rawValue)")
        }
    }

    /// **가방 갈래와 배틀 효과가 같은 축이어야 한다.** 갈래만 `.heldItem` 인 아이템은 지니게 할 수
    /// 있는데 배틀에서 아무 일도 안 하고, 효과만 있는 아이템은 가방에서 지니게 할 방법이 없다.
    func testTheBagAxisAndTheBattleEffectAgree() {
        for kind in ItemKind.allCases {
            XCTAssertEqual(kind.bagUse == .heldItem, kind.heldBattleEffect != nil,
                           "\(kind.rawValue) 의 가방 갈래와 배틀 효과가 어긋난다")
        }
        XCTAssertEqual(ItemKind.lifeOrb.heldBattleEffect, .lifeOrb)
        XCTAssertEqual(ItemKind.focusSash.heldBattleEffect, .focusSash)
        XCTAssertEqual(ItemKind.leftovers.heldBattleEffect, .leftovers)
        // 효과 셋이 전부 아이템을 갖는다 — 아이템 없는 효과는 아무도 못 켜는 죽은 갈래다.
        for effect in HeldItemEffect.allCases {
            XCTAssertTrue(ItemKind.allCases.contains { $0.heldBattleEffect == effect },
                          "\(effect) 를 주는 아이템이 없다")
        }
    }

    /// 값은 사탕(성장 1회분) 근처다 — 대전 성능을 상시로 바꾸므로 코스메틱(민트·테라피스)보다 비싸다.
    func testThePricesSitNearTheCandy() throws {
        for kind in Self.three {
            let price = try XCTUnwrap(kind.shopPrice, "\(kind.rawValue) 가 상점에 없다")
            XCTAssertGreaterThan(price, TeraShard.price, "\(kind.rawValue)")
            XCTAssertLessThanOrEqual(price, RareCandy.price, "\(kind.rawValue)")
        }
    }

    /// 이름·설명·효과 힌트가 세 언어에 다 있다. 하나라도 비면 가방·상점에 빈 줄이 뜬다.
    func testTheThreeAreNamedInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            for kind in Self.three {
                XCTAssertFalse(l.itemName(kind).isEmpty, "\(kind.rawValue)/\(lang)")
                XCTAssertFalse(l.itemDescription(kind).isEmpty, "\(kind.rawValue)/\(lang)")
                XCTAssertFalse(l.heldItemEffectHint(kind).isEmpty, "\(kind.rawValue)/\(lang)")
            }
            // 가방의 비활성 사유 — 화면에만 뜨는 문구라 여기서만 잡힌다.
            XCTAssertFalse(l.heldItemAlreadyHeld.isEmpty, "\(lang)")
        }
        // 설명은 아이템마다 갈린다 — 한 문구로 뭉개면 무엇을 사는지 알 수 없다.
        let l = L(.ko)
        XCTAssertNotEqual(l.itemDescription(.lifeOrb), l.itemDescription(.leftovers))
        XCTAssertNotEqual(l.heldItemEffectHint(.lifeOrb), l.heldItemEffectHint(.focusSash))
    }

    /// 이름표에 있어야 대화·터미널이 이 아이템을 부를 수 있다.
    func testTheThreeAreNameable() {
        for kind in Self.three {
            XCTAssertTrue(ItemKind.nameable.contains(kind), "\(kind.rawValue)")
            XCTAssertEqual(ItemKind.named(kind.rawValue), kind)
        }
        // 가구는 여전히 빠져 있다 — `use 침대` 가 먼저 받아들여진 뒤 실패하면 안 된다.
        XCTAssertFalse(ItemKind.nameable.contains(.roomBed))
    }

    // MARK: - 와이어

    /// **와이어에 실린다.** 안 실으면 한쪽 피어만 데미지 배율·회복을 얹어 같은 판의 HP 가 갈린다
    /// (각자 화면에는 정상으로 보인다).
    func testTheHeldItemSurvivesTheWire() throws {
        let sent = snapshot(held: .lifeOrb)
        let received = try JSONDecoder().decode(BattleSnapshot.self,
                                                from: JSONEncoder().encode(sent))
        XCTAssertEqual(received.heldItem, .lifeOrb)
        XCTAssertEqual(received, sent)
    }

    /// 이 필드가 없던 피어·세이브의 payload 는 그대로 디코딩되고 "안 지녔다" 로 접힌다.
    func testAPayloadWithoutTheFieldStillDecodes() throws {
        let json = """
        {"v":1,"speciesID":7,"name":"old","level":50,"isShiny":false,"types":["water"],
         "base":{"hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100}}
        """
        let decoded = try JSONDecoder().decode(BattleSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(decoded.heldItem)
    }

    /// 모르는 아이템 이름은 **접는다**(던지지 않는다). 던지면 신버전 피어가 아이템을 하나 늘릴
    /// 때마다 스냅샷 전체가 디코딩에 실패해 대전이 성립하지 않는다 — 특성 슬러그와 같은 정책이다.
    func testAnUnknownHeldItemFoldsToNil() throws {
        let json = """
        {"v":1,"speciesID":7,"name":"new","level":50,"isShiny":false,"types":["water"],
         "base":{"hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100},
         "heldItem":"itemFromTheFuture"}
        """
        let decoded = try JSONDecoder().decode(BattleSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(decoded.heldItem)
    }

    /// 스냅샷을 만드는 자리가 이 값을 싣는지는 소스에서 센다 — 한 자리만 빠지면 그 모드에서만
    /// 지닌물건이 아무 일도 안 하고, 화면에는 아무 오류도 안 보인다.
    func testTheSnapshotScanCountsTheHeldItemField() throws {
        let sources = try SourceScan.sources().filter { $0.code.contains("BattleSnapshot(") }
        XCTAssertFalse(sources.isEmpty)
        for (name, code) in sources where !code.contains("struct BattleSnapshot") {
            XCTAssertTrue(code.contains("heldItem:"), "\(name) 의 스냅샷이 지닌물건을 안 싣는다")
        }
    }

    // MARK: - 피어 검증

    /// 지닐 수 없는 아이템은 거절한다 — 피어가 보내온 값이라, 사탕·부적에 배틀 효과를 붙이는 날
    /// 검증이 없으면 그것이 곧 조작 경로가 된다.
    func testValidationRejectsAnItemThatCannotBeHeld() {
        XCTAssertTrue(MultiplayerValidation.validHeldItem(nil))
        for kind in Self.three {
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "\(kind.rawValue)")
        }
        XCTAssertFalse(MultiplayerValidation.validHeldItem(.rareCandy))
        XCTAssertFalse(MultiplayerValidation.validHeldItem(.roomBed))
    }

    /// **두 입구가 다 본다.** 방 입장만 보면 1v1 LAN 라인업이 무검사가 되고, 그 반대도 같다
    /// (특성 슬러그가 같은 이유로 두 자리에 있다).
    func testBothEntryPointsRejectABadHeldItem() {
        let participant = LobbyParticipant(id: UUID(), trainerName: "트레이너", speciesID: 25,
                                           team: .solo, isReady: true, isHost: false)
        XCTAssertTrue(MultiplayerValidation.valid(participant: participant,
                                                 snapshot: snapshot(held: .leftovers)))
        XCTAssertFalse(MultiplayerValidation.valid(participant: participant,
                                                  snapshot: snapshot(held: .rareCandy)))
        let good = snapshot(held: .leftovers)
        let bad = snapshot(held: .rareCandy)
        XCTAssertTrue(BattleCenter.validLineup(snapshot: good, lineup: [good], teamSize: 1))
        XCTAssertFalse(BattleCenter.validLineup(snapshot: bad, lineup: [bad], teamSize: 1))
    }

    // MARK: - 생명의구슬

    /// 데미지가 1.3배가 된다. **같은 seed 로 붙였을 때와 안 붙였을 때를 비교한다** — 난수 폭이
    /// 같으므로 차이는 배율뿐이다.
    func testTheLifeOrbMultipliesDamage() {
        var plain = side(held: nil)
        var orb = side(held: .lifeOrb)
        var victimA = side(), victimB = side()
        let move = attackMove()
        let without = dealt(hit(move, by: &plain, on: &victimA))
        let with = dealt(hit(move, by: &orb, on: &victimB))
        XCTAssertGreaterThan(without, 0)
        // 배율을 난수 폭 앞에서 곱하므로 정수 절단이 몇 점 어긋난다 — 그 폭만 허용한다.
        XCTAssertLessThanOrEqual(abs(with - without * 13 / 10), 2,
                                 "생명의구슬은 데미지의 1.3배다(\(without) → \(with))")
    }

    /// **공식을 안 타는 기술은 안 오른다** — 나이트헤드(고정 데미지)에 배율을 얹으면 본가와 갈리고,
    /// 배율을 데미지 자리 대신 결과 자리에 얹은 오구현이 여기서 잡힌다.
    func testTheLifeOrbDoesNotBoostFixedDamage() {
        var plain = side(held: nil)
        var orb = side(held: .lifeOrb)
        var victimA = side(), victimB = side()
        let nightShade = attackMove(VariableDamage.MoveID.nightShade, power: 0, damageClass: .special)
        let without = dealt(hit(nightShade, by: &plain, on: &victimA))
        XCTAssertGreaterThan(without, 0, "고정 데미지가 0 이면 이 테스트는 아무것도 안 잠근다")
        XCTAssertEqual(dealt(hit(nightShade, by: &orb, on: &victimB)), without)
    }

    /// 대가는 **매 턴 최대 HP 의 1/10** 이다. 본가는 공격할 때마다지만 이 엔진은 광역기가 대상마다
    /// `applyHit` 을 부르므로 그 자리에 두면 대상 수만큼 중복 과금된다 — 턴 끝 한 자리로 모은다.
    func testTheLifeOrbHurtsItsHolderEveryTurn() {
        var holder = side(held: .lifeOrb)
        let full = fullHP(holder)
        let cost = full / HeldItemBalance.lifeOrbRecoilDivisor
        let events = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.hp, full - cost)
        XCTAssertEqual(events, [.damage(.a, amount: cost, cause: .recoil)])
    }

    /// 자해로 쓰러질 수 있고, 그때 기절 줄은 **한 번만** 나간다(잔뎀과 같은 규칙).
    func testTheLifeOrbCanKnockOutItsHolder() {
        var holder = side(hp: 3, held: .lifeOrb)
        let events = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.hp, 0)
        XCTAssertEqual(events.filter { $0 == .faint(.a) }.count, 1)
    }

    // MARK: - 먹다남은음식

    /// 턴 끝에 최대 HP 의 1/16 을 회복한다.
    func testLeftoversHealsAtTheEndOfTheTurn() {
        var holder = side(hp: 50, held: .leftovers)
        let heal = fullHP(holder) / HeldItemBalance.leftoversDivisor
        let events = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.hp, 50 + heal)
        XCTAssertEqual(events, [.heal(.a, amount: heal)])
    }

    /// 만피면 회복량이 0 이라 **줄을 내지 않는다** — 매 턴 "회복했다" 가 로그를 덮으면 무슨 일이
    /// 있었는지 읽을 수 없다(런 강화의 회복과 같은 규칙).
    func testLeftoversIsSilentAtFullHP() {
        var holder = side(held: .leftovers)
        let full = fullHP(holder)
        XCTAssertEqual(BattleEngine.endOfTurnResidual(&holder, actor: .a), [])
        XCTAssertEqual(holder.hp, full)
    }

    /// **웨이브 런의 회복 스택과 합산된다.** 둘은 사는 자리가 다르다(스택은 판 안, 지닌물건은
    /// 개체) — 한쪽만 보는 구현은 겹치는 판에서 회복을 조용히 잃거나 두 배로 준다. 줄은 한 줄이다.
    func testTheHeldLeftoversAddsToTheRunBoostStack() {
        var holder = side(hp: 50, held: .leftovers)
        holder.runBoosts.leftovers = 1
        let heldHeal = fullHP(holder) / HeldItemBalance.leftoversDivisor
        let stackOnly = { () -> Int in
            var other = self.side(hp: 50, held: nil)
            other.runBoosts.leftovers = 1
            _ = BattleEngine.endOfTurnResidual(&other, actor: .a)
            return other.hp - 50
        }()
        XCTAssertGreaterThan(stackOnly, 0, "스택 회복이 0 이면 합산을 잠그지 못한다")
        let events = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.hp - 50, stackOnly + heldHeal,
                       "스택 회복 + 지닌물건 회복이 함께 들어간다")
        XCTAssertEqual(events.count, 1, "회복은 한 줄로 낸다")
    }

    /// 회복은 **최대 HP 를 넘지 않는다.**
    func testLeftoversNeverOverheals() {
        var holder = side(held: .leftovers)
        let full = fullHP(holder)
        holder.hp = full - 1
        _ = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.hp, full)
    }

    // MARK: - 기합의띠

    /// 만피에서 치명적인 한 방을 HP 1 로 버틴다 + 버틴 줄이 따로 나간다.
    func testTheFocusSashSurvivesALethalHitFromFullHP() {
        var attacker = side()
        var victim = side(held: .focusSash)
        let events = hit(attackMove(power: 400), by: &attacker, on: &victim)
        XCTAssertEqual(victim.hp, 1)
        XCTAssertTrue(events.contains(.heldItemTriggered(.b, .focusSash)),
                      "버틴 줄이 없으면 그 턴이 로그에 무반응으로 남는다")
        XCTAssertFalse(events.contains(.faint(.b)))
    }

    /// **만피가 아니면 안 버틴다** — 이 조건이 없으면 띠가 HP 1 짜리 무적이 된다.
    func testTheFocusSashDoesNothingBelowFullHP() {
        var attacker = side()
        var victim = side(held: .focusSash)
        victim.hp -= 1                                    // 한 점만 깎여도 만피가 아니다
        let events = hit(attackMove(power: 400), by: &attacker, on: &victim)
        XCTAssertEqual(victim.hp, 0)
        XCTAssertTrue(events.contains(.faint(.b)))
        XCTAssertFalse(events.contains(.heldItemTriggered(.b, .focusSash)))
    }

    /// **한 번 쓰면 소모된다.** 만피로 되돌아간 개체가 다시 버티면 회복기 하나로 무적이 된다.
    /// 소모는 배틀 안에서만이다(가방의 재고는 그대로) — 세이브를 배틀이 깎지 않는다.
    func testTheFocusSashIsSpentAfterItTriggers() {
        var attacker = side()
        var victim = side(held: .focusSash)
        _ = hit(attackMove(power: 400), by: &attacker, on: &victim)
        XCTAssertEqual(victim.hp, 1)
        victim.hp = victim.stats.hp                       // 회복해서 다시 만피
        let again = hit(attackMove(power: 400), by: &attacker, on: &victim)
        XCTAssertEqual(victim.hp, 0, "두 번째는 버티지 않는다")
        XCTAssertTrue(again.contains(.faint(.b)))
        XCTAssertEqual(victim.snapshot.heldItem, .focusSash, "와이어 값은 배틀이 바꾸지 않는다")
    }

    /// 치명적이지 않은 한 방에는 발동하지 않는다(소모도 없다).
    func testTheFocusSashStaysUnusedOnANonLethalHit() {
        var attacker = side()
        var victim = side(held: .focusSash)
        let events = hit(attackMove(), by: &attacker, on: &victim)
        XCTAssertGreaterThan(victim.hp, 1)
        XCTAssertFalse(events.contains(.heldItemTriggered(.b, .focusSash)))
        XCTAssertNotNil(victim.heldEffect, "발동하지 않았으면 소모되지 않는다")
    }

    /// 인내와 겹치면 **줄이 두 개 나가지 않는다** — 인내가 이미 HP 1 을 남겼으므로 띠는 일할 것이
    /// 없다(둘 다 발동으로 세면 로그가 같은 일을 두 번 말하고 띠가 헛되게 소모된다).
    func testEndureTakesPrecedenceOverTheSash() {
        var attacker = side()
        var victim = side(held: .focusSash)
        XCTAssertTrue(victim.start(.endure))
        let events = hit(attackMove(power: 400), by: &attacker, on: &victim)
        XCTAssertEqual(victim.hp, 1)
        XCTAssertTrue(events.contains(.volatileTriggered(.b, .endure)))
        XCTAssertFalse(events.contains(.heldItemTriggered(.b, .focusSash)))
        XCTAssertNotNil(victim.heldEffect, "인내가 막았으면 띠는 그대로 남는다")
    }

    /// 잔뎀으로는 버티지 않는다 — 인내와 같은 규칙이고, 자리가 다르므로 따로 잠근다.
    func testTheSashDoesNotSaveFromResidualDamage() {
        var holder = side(held: .focusSash)
        holder.status = .poison
        holder.hp = 1
        let events = BattleEngine.endOfTurnResidual(&holder, actor: .a)
        XCTAssertEqual(holder.hp, 0)
        XCTAssertTrue(events.contains(.faint(.a)))
    }

    // MARK: - 로그·재생

    /// 발동 줄이 세 언어에 다 있고 **주인 이름이 들어간다**(맞은 쪽의 줄이다).
    func testTheTriggerLineIsRenderedInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let lines = BattleLog.lines([.heldItemTriggered(.b, .focusSash)], l: L(lang),
                                        name: { $0 == .a ? "거북왕" : "리자몽" },
                                        move: { _, id in
                                            MoveSpec(id: id, names: ["ko": "공격"], type: .normal,
                                                     power: 40, damageClass: .physical,
                                                     accuracy: 100, pp: 20)
                                        })
            XCTAssertEqual(lines.count, 1, "\(lang)")
            XCTAssertEqual(lines[0].actor, .b, "\(lang)")
            XCTAssertTrue(lines[0].text.contains("리자몽"), "\(lang): \(lines[0].text)")
            XCTAssertTrue(lines[0].text.contains(L(lang).itemName(.focusSash)),
                          "\(lang): 무엇이 일했는지가 문구의 절반이다 — \(lines[0].text)")
        }
    }

    /// 진행 중인 행동에 접히지 않는다 — 때린 쪽 줄에 붙으면 누가 버텼는지가 뒤바뀐다.
    func testTheTriggerLineIsNotFoldedIntoTheAttack() {
        let lines = BattleLog.lines([.move(.a, moveID: 33), .damage(.b, amount: 19, cause: .move),
                                     .heldItemTriggered(.b, .focusSash)],
                                    l: L(.ko), name: { $0 == .a ? "거북왕" : "리자몽" },
                                    move: { _, id in
                                        MoveSpec(id: id, names: ["ko": "공격"], type: .normal,
                                                 power: 40, damageClass: .physical,
                                                 accuracy: 100, pp: 20)
                                    })
        XCTAssertEqual(lines.count, 2)
    }

    /// 재생 박자가 있고 팝 문구는 없다(문구에 아이템 이름이 들어가 `KeyPath` 로 못 담는다 —
    /// 날씨와 같은 이유로 로그 줄로만 나간다).
    func testTheTriggerHasAReplayBeat() {
        let event = BattleEvent.heldItemTriggered(.b, .focusSash)
        XCTAssertGreaterThan(BattleReplay.duration(of: event), 0)
        XCTAssertNil(BattleReplay.popupKey(for: event))
    }

    // MARK: - 가방 → 개체

    func testCannotGiveWithoutStock() {
        XCTAssertFalse(store(inventory: [:]).canGiveHeldItem(.lifeOrb))
        XCTAssertTrue(store(inventory: [.lifeOrb: 1]).canGiveHeldItem(.lifeOrb))
    }

    /// 지니게 하면 가방에서 하나 빠지고 개체에 붙는다.
    func testGivingAHeldItemMovesItOutOfTheBag() {
        let s = store(inventory: [.lifeOrb: 2])
        XCTAssertTrue(s.giveHeldItem(.lifeOrb))
        XCTAssertEqual(s.state.active?.heldItem, .lifeOrb)
        XCTAssertEqual(s.itemCount(.lifeOrb), 1)
    }

    /// **한 번에 하나다.** 두 번째를 지니게 하면 먼저 지녔던 것이 가방으로 **돌아온다** —
    /// 사라지면 5,000 별의조각이 조용히 없어진다.
    func testGivingASecondItemReturnsTheFirstToTheBag() {
        let s = store(inventory: [.leftovers: 1], held: .lifeOrb)
        XCTAssertTrue(s.giveHeldItem(.leftovers))
        XCTAssertEqual(s.state.active?.heldItem, .leftovers)
        XCTAssertEqual(s.itemCount(.lifeOrb), 1, "먼저 지녔던 것이 가방으로 돌아온다")
        XCTAssertEqual(s.itemCount(.leftovers), 0)
    }

    /// 이미 지니고 있는 것을 또 지니게 하지 않는다 — 재고만 오갈 뿐 아무것도 안 바뀐다.
    func testGivingTheSameItemTwiceIsRefused() {
        let s = store(inventory: [.lifeOrb: 1], held: .lifeOrb)
        XCTAssertFalse(s.canGiveHeldItem(.lifeOrb))
        XCTAssertFalse(s.giveHeldItem(.lifeOrb))
        XCTAssertEqual(s.itemCount(.lifeOrb), 1)
    }

    /// 세이브에 실린다 — 저장을 안 하면 앱을 다시 켤 때 지닌물건이 사라진다.
    func testTheHeldItemSurvivesTheSave() {
        let url = storeStateURL("helditem")
        let s = store(at: url, inventory: [.leftovers: 1])
        XCTAssertTrue(s.giveHeldItem(.leftovers))
        let reopened = CompanionStore(provider: HeldItemNoProvider(), clock: { self.now },
                                      fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(reopened.state.active?.heldItem, .leftovers)
    }

    /// 모르는 아이템 이름이 세이브에 있으면 **접는다** — 던지면 세이브 전체가 알로 되돌아간다
    /// (앱을 되돌려 설치한 사용자가 동행을 잃는다).
    func testAnUnknownHeldItemInTheSaveFoldsToNil() throws {
        let mon = """
        {"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":0,"rarity":"common",
         "totalForms":3,"isShiny":false,"heldItem":"itemFromTheFuture"}
        """
        let decoded = try JSONDecoder().decode(MonState.self, from: Data(mon.utf8))
        XCTAssertNil(decoded.heldItem)
        XCTAssertEqual(decoded.baseID, 1, "개체는 살아남는다")
    }

    /// 대화·터미널이 쓰는 공유 경로도 같은 스토어 메서드를 지난다 — 갈래를 따로 쓰면 한쪽만
    /// 고쳐져 "대화로는 되는데 가방으로는 안 되는" 아이템이 생긴다.
    func testTheSharedActionPathGivesTheItem() {
        let s = store(inventory: [.focusSash: 1])
        XCTAssertEqual(CompanionAction.useItem(.focusSash, companion: s), .heldItemGiven)
        XCTAssertEqual(s.state.active?.heldItem, .focusSash)
    }

    /// 재고가 없으면 공유 경로도 `.unavailable` 이다(진화 거절과 갈라 둔다).
    func testTheSharedActionPathReportsAnEmptyBag() {
        XCTAssertEqual(CompanionAction.useItem(.focusSash, companion: store()), .unavailable)
    }

    /// 동행 스냅샷이 지닌물건을 싣는다 — 여기가 배틀로 들어가는 유일한 입구다.
    func testTheCompanionSnapshotCarriesTheHeldItem() async {
        let s = store(inventory: [.lifeOrb: 1])
        XCTAssertTrue(s.giveHeldItem(.lifeOrb))
        guard let mon = s.state.active else { return XCTFail("활성 개체가 없다") }
        // provider 가 배틀 프로필을 못 주면 스냅샷 자체가 nil 이다 — 그때는 이 단언을 건너뛴다
        // (조회 실패는 이 테스트가 잠그려는 것이 아니다).
        if let snapshot = await s.battleSnapshot(for: mon) {
            XCTAssertEqual(snapshot.heldItem, .lifeOrb)
        }
    }
}
