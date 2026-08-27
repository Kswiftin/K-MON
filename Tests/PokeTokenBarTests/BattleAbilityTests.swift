import XCTest
@testable import PokeTokenBar

/// 특성 1단계 — 면역만(#24 Phase 5 / PR 9).
///
/// 면역은 표 조회뿐이라 rng 를 한 번도 안 쓴다. 그래서 두 피어가 갈라질 수 없는 지점부터 들어간다.
/// 이 파일이 잠그는 건 **갈림길이 두 곳뿐**이라는 점이다 — 데미지는 상성 배율 한 지점,
/// 상태는 `canBeAfflicted` 한 지점. 세 번째 자리가 생기면 모드마다 특성이 달라진다.
final class BattleAbilityTests: XCTestCase {
    private func snapshot(types: [PokemonType] = [.normal], ability: String? = nil) -> BattleSnapshot {
        BattleSnapshot(speciesID: 1, name: "Test", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 100),
                       ability: ability)
    }

    private func attack(_ type: PokemonType, id: Int = 1, power: Int = 80) -> MoveSpec {
        MoveSpec(id: id, names: ["en": "Test"], type: type, power: power,
                 damageClass: .physical, accuracy: nil, pp: 20)
    }

    /// 같은 조건으로 한 대 때리고 (남은 HP, 최대 HP, 이벤트)를 돌려준다 — 대조군과 나란히 세우기 위한 헬퍼.
    private func hit(defender: BattleSnapshot, with move: MoveSpec,
                     defenderHP: Int? = nil, seed: UInt64 = 1) -> (hp: Int, maxHP: Int, events: [BattleEvent]) {
        var attacker = BattleSide(snapshot())
        var side = BattleSide(defender)
        if let defenderHP { side.hp = defenderHP }
        var rng = SplitMix64(seed: seed)
        let events = BattleEngine.applyAttack(attacker: &attacker, defender: &side,
                                              attackerActor: .a, defenderActor: .b,
                                              move: move, rng: &rng)
        return (side.hp, side.stats.hp, events)
    }

    // MARK: 타입 면역 — 상성 배율 한 지점

    func testLevitateZeroesGroundDamageAndLeavesOtherTypesAlone() {
        let floating = hit(defender: snapshot(ability: "levitate"), with: attack(.ground))
        XCTAssertEqual(floating.hp, floating.maxHP, "부유는 땅 기술을 0배로 만든다")
        XCTAssertTrue(floating.events.contains(.immune(.b)))

        // 대조군 ①: 특성이 없는 같은 종은 맞는다. 이게 없으면 "땅 기술이 원래 안 통했다" 와 구별이 안 된다.
        let grounded = hit(defender: snapshot(), with: attack(.ground))
        XCTAssertLessThan(grounded.hp, grounded.maxHP, "특성이 없으면 땅 기술은 그대로 들어간다")

        // 대조군 ②: 한 표가 전 타입을 막는 오구현 차단.
        let fire = hit(defender: snapshot(ability: "levitate"), with: attack(.fire))
        XCTAssertLessThan(fire.hp, fire.maxHP, "부유가 막는 건 땅뿐이다")
    }

    func testFlashFireBlocksOnlyFireMoves() {
        let fire = hit(defender: snapshot(ability: "flash-fire"), with: attack(.fire))
        XCTAssertEqual(fire.hp, fire.maxHP)
        XCTAssertTrue(fire.events.contains(.immune(.b)))

        let water = hit(defender: snapshot(ability: "flash-fire"), with: attack(.water))
        XCTAssertLessThan(water.hp, water.maxHP, "타오르는불꽃은 불꽃기만 막는다")
    }

    /// 흡수는 **무효 + 회복**이다. 회복 쪽만 보면 만피에서 조용히 데미지가 들어가도 초록이고,
    /// 무효 쪽만 보면 저수가 그냥 부유가 된다.
    func testAbsorbAbilitiesHealAQuarterAndStayImmuneEvenAtFullHP() {
        let hurt = hit(defender: snapshot(ability: "volt-absorb"), with: attack(.electric), defenderHP: 10)
        XCTAssertEqual(hurt.hp, 10 + hurt.maxHP / 4, "전기흡수는 최대 HP 의 1/4 을 회복한다")
        XCTAssertTrue(hurt.events.contains(.immune(.b)))
        XCTAssertTrue(hurt.events.contains(.heal(.b, amount: hurt.maxHP / 4)))

        // 만피 — 회복량은 0 이지만 **여전히 무효**다. `.heal(amount: 0)` 줄은 내지 않는다.
        let full = hit(defender: snapshot(ability: "volt-absorb"), with: attack(.electric))
        XCTAssertEqual(full.hp, full.maxHP)
        XCTAssertTrue(full.events.contains(.immune(.b)))
        XCTAssertFalse(full.events.contains { if case .heal = $0 { return true }; return false },
                       "회복량 0 은 로그에 남기지 않는다")

        // 대조군: 흡수 타입이 아니면 회복도 무효도 없다.
        let wrongType = hit(defender: snapshot(ability: "water-absorb"), with: attack(.electric), defenderHP: 10)
        XCTAssertLessThan(wrongType.hp, 10, "저수는 전기를 흡수하지 않는다")
    }

    /// 공식을 **안 타는** 히트(고정 데미지·일격필살)도 면역은 탄다. `fixedOutcome` 이 상성표만 보던
    /// 동안 부유는 지진을 막고 갈라진땅은 못 막았다 — 상성 배율을 내는 자리가 두 곳이었다는 뜻이고,
    /// 데미지 기술만으로 테스트하면 그 두 번째 자리를 한 번도 안 밟는다.
    func testAFixedDamageMoveStillRespectsAbilityImmunity() {
        let fissure = MoveSpec(id: VariableDamage.MoveID.fissure, names: ["en": "Fissure"],
                               type: .ground, power: 0, damageClass: .physical, accuracy: nil, pp: 5)
        let floating = hit(defender: snapshot(ability: "levitate"), with: fissure)
        XCTAssertEqual(floating.hp, floating.maxHP, "부유는 갈라진땅도 막는다")
        XCTAssertTrue(floating.events.contains(.immune(.b)))

        // 대조군: 특성이 없으면 일격필살이 그대로 들어간다(기술이 죽은 게 아니라 면역이 막은 것이다).
        let grounded = hit(defender: snapshot(), with: fissure)
        XCTAssertEqual(grounded.hp, 0, "특성이 없으면 갈라진땅은 그대로 쓰러뜨린다")

        // 부유는 흡수가 아니다 — 막은 자리에서 회복이 따라붙으면 안 된다.
        let hurt = hit(defender: snapshot(ability: "levitate"), with: fissure, defenderHP: 10)
        XCTAssertEqual(hurt.hp, 10)
    }

    /// 부유가 무효로 만든 기술은 흡수가 아니다 — 무효 전부를 회복으로 만들면 부유가 회복 특성이 된다.
    func testANonAbsorbingImmunityDoesNotHeal() {
        let floating = hit(defender: snapshot(ability: "levitate"), with: attack(.ground), defenderHP: 10)
        XCTAssertEqual(floating.hp, 10, "부유는 막을 뿐 회복하지 않는다")
    }

    // MARK: 상태 면역 — `canBeAfflicted` 한 지점

    func testStatusImmunitiesCoverExactlyTheirOwnStatus() {
        func side(_ ability: String?) -> BattleSide { BattleSide(snapshot(ability: ability)) }
        let all: [Status] = [.paralysis, .sleep, .poison, .toxic, .burn, .freeze, .confusion]

        // 대조군 먼저 — 특성이 없으면 전부 걸린다. 없으면 "원래 안 걸리는 상태" 와 구별할 수 없다.
        for status in all {
            XCTAssertTrue(side(nil).canBeAfflicted(by: status), "특성이 없으면 \(status) 는 걸린다")
        }

        let table: [(ability: String, blocked: [Status])] = [
            ("limber", [.paralysis]),
            ("insomnia", [.sleep]),
            ("vital-spirit", [.sleep]),
            ("immunity", [.poison, .toxic]),
            ("water-veil", [.burn]), ("water-bubble", [.burn]),
            ("magma-armor", [.freeze]),
            ("own-tempo", [.confusion]),
        ]
        for entry in table {
            for status in all {
                let expected = !entry.blocked.contains(status)
                XCTAssertEqual(side(entry.ability).canBeAfflicted(by: status), expected,
                               "\(entry.ability) 가 \(status) 를 \(expected ? "막으면 안 된다" : "막아야 한다")")
            }
        }
    }

    /// 두 축은 **서로 넘어오지 않는다.** 상태 특성이 데미지를 막거나 타입 특성이 상태를 막으면,
    /// 표 하나가 두 축을 다 덮는 오구현이다 — 각 표의 `default` 가름이 여기서만 실행된다
    /// (`--show-regions` 에서 두 `default` 가 `^0` 이던 자리다).
    func testTheTwoImmunityAxesDoNotLeakIntoEachOther() {
        let limber = hit(defender: snapshot(ability: "limber"), with: attack(.ground))
        XCTAssertLessThan(limber.hp, limber.maxHP, "유연은 상태 특성이다 — 데미지는 그대로 들어간다")

        let levitate = BattleSide(snapshot(ability: "levitate"))
        for status in [Status.paralysis, .sleep, .burn, .confusion] {
            XCTAssertTrue(levitate.canBeAfflicted(by: status),
                          "부유는 타입 특성이다 — \(status) 를 막으면 안 된다")
        }
    }

    // MARK: 미구현 슬러그

    /// 모르는 슬러그는 배틀을 **한 눈금도** 바꾸지 않는다. 이벤트 전체를 비교한다 —
    /// HP 만 보면 rng 를 한 번 더 굴리는 구현이 통과한다.
    func testAnUnimplementedAbilitySlugChangesNothing() {
        let plain = hit(defender: snapshot(), with: attack(.ground))
        let unknown = hit(defender: snapshot(ability: "wonder-guard"), with: attack(.ground))
        XCTAssertEqual(unknown.hp, plain.hp)
        XCTAssertEqual(unknown.events, plain.events, "모르는 특성은 소비도 결과도 바꾸지 않는다")
    }

    // MARK: 스냅샷 4경로

    // 네 자리 전부가 슬러그를 싣는지는 `VariableDamageTests
    // .testEveryBattleSnapshotSiteCarriesTheWireOnlyFields` 가 지킨다 — 체중과 **같은 부류**(스냅샷에만
    // 실리는 옵셔널 축)라 순회를 두 벌 두지 않는다. 여기서는 슬러그의 출처만 본다.

    /// 종에서 파생된다 — 세이브가 아니라 `/pokemon/{id}` 응답이 원천이고, 숨은 특성은 빼고 slot 이 낮은 쪽.
    func testTheBattleProfileTakesTheFirstNonHiddenAbility() {
        XCTAssertEqual(PokemonAbilitiesDTO.primaryAbilitySlug(
            [(slug: "chlorophyll", isHidden: true, slot: 3),
             (slug: "overgrow", isHidden: false, slot: 1)]), "overgrow")
        XCTAssertNil(PokemonAbilitiesDTO.primaryAbilitySlug(
            [(slug: "chlorophyll", isHidden: true, slot: 3)]))

        // **slot 이 배열 순서와 어긋난 경우.** 이게 없으면 `min(slot)` 을 `first` 로 써도 통과한다 —
        // PokéAPI 가 `abilities` 를 slot 순으로 준다는 보장이 계약에 없다.
        XCTAssertEqual(PokemonAbilitiesDTO.primaryAbilitySlug(
            [(slug: "shield-dust", isHidden: false, slot: 2),
             (slug: "run-away", isHidden: false, slot: 1)]), "run-away")
    }

    // MARK: 신뢰경계

    /// 특성은 **상대가 보내오는 문자열**이다. 숫자만 막고 문자열을 빼 두면 경계가 반만 있는 것이다.
    /// 두 수신 경로를 나란히 확인한다 — 한 곳만 막으면 형제 경로가 무검사다.
    func testTheAbilitySlugIsBoundedAtBothTrustBoundaries() {
        let huge = String(repeating: "a", count: 500)
        func participant(_ snapshot: BattleSnapshot) -> LobbyParticipant {
            LobbyParticipant(id: UUID(), trainerName: "T", speciesID: snapshot.speciesID,
                             team: .solo, isReady: true, isHost: false)
        }

        let ok = snapshot(ability: "levitate")
        XCTAssertTrue(MultiplayerValidation.valid(participant: participant(ok), snapshot: ok))
        XCTAssertTrue(BattleCenter.validLineup(snapshot: ok, lineup: [ok], teamSize: 1))

        let oversized = snapshot(ability: huge)
        XCTAssertFalse(MultiplayerValidation.valid(participant: participant(oversized), snapshot: oversized),
                       "방 입장에서 길이 상한이 없으면 슬러그 하나로 라운드 메시지가 불어난다")
        XCTAssertFalse(BattleCenter.validLineup(snapshot: oversized, lineup: [oversized], teamSize: 1),
                       "1v1 LAN 도 같은 상한을 봐야 한다")

        // 대조군: 특성이 없는 스냅샷(구버전 피어)은 그대로 통과한다.
        let none = snapshot()
        XCTAssertTrue(MultiplayerValidation.valid(participant: participant(none), snapshot: none))
    }

    /// 규칙이 바뀌면 **둘 다** 올린다 — 멀티는 `rulesVersion` 을 안 보고 `protocolVersion` 만 본다.
    /// 하나만 올리면 구버전 호스트와 신버전 게스트가 붙어 특성 유무가 갈린 채로 싸운다.
    func testTheRuleAndProtocolVersionsMovedTogetherForAbilities() {
        XCTAssertEqual(BattleEngine.rulesVersion, 17)
        XCTAssertEqual(MultiplayerWireMessage.protocolVersion, 9)
    }
}
