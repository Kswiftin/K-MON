import XCTest
@testable import PokeTokenBar

/// 특성 1단계 — 면역만(#24 Phase 5 / PR 9).
///
/// 면역은 표 조회뿐이라 rng 를 한 번도 안 쓴다. 그래서 두 피어가 갈라질 수 없는 지점부터 들어간다.
/// 여기서 지키는 건 **갈림길이 두 곳뿐**이라는 것이다 — 데미지는 상성 배율 한 지점,
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

    /// 같은 조건으로 한 대 때리고 (남은 HP, 이벤트) 를 돌려준다 — 대조군과 나란히 세우기 위한 헬퍼.
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
            ("water-veil", [.burn]),
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

    /// 스냅샷을 만드는 네 자리 전부가 특성을 실어야 한다. 한 곳을 빠뜨리면 **그 모드만** 특성이 없다.
    /// 소스 스캔으로 고정하는 이유는 `MultiplayerRoomCenter` 가 테스트에서 세워지지 않기 때문이고,
    /// 덤으로 앞으로 생길 다섯 번째 자리도 같이 잡힌다.
    func testEverySnapshotBuilderCarriesTheAbility() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var found = 0
        for path in ["CompanionStore.swift", "MultiplayerRoomCenter.swift", "BattleNet.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(
                "Sources/PokeTokenBar/Core/\(path)"), encoding: .utf8)
            let calls = source.components(separatedBy: "BattleSnapshot(speciesID:").dropFirst()
            XCTAssertFalse(calls.isEmpty, "\(path) 에 스냅샷 생성이 있어야 한다")
            for call in calls {
                found += 1
                let weight = try XCTUnwrap(call.range(of: "weightHectograms:"),
                                           "\(path): 스냅샷 생성 인자 끝을 못 찾았다")
                XCTAssertNotNil(call.range(of: "ability:", range: call.startIndex..<weight.lowerBound),
                                "\(path): 스냅샷 하나가 특성을 안 싣는다 — 그 모드만 특성이 없어진다")
            }
        }
        XCTAssertEqual(found, 4, "스냅샷 생성 자리는 네 곳이다(늘었으면 이 테스트도 같이 본다)")
    }

    /// 종에서 파생된다 — 세이브가 아니라 `/pokemon/{id}` 응답이 원천이고, 숨은 특성은 빼고 slot 이 낮은 쪽.
    func testTheBattleProfileTakesTheFirstNonHiddenAbility() {
        XCTAssertEqual(PokemonSpeciesIdentity.primaryAbilitySlug(
            [(slug: "chlorophyll", isHidden: true, slot: 3),
             (slug: "overgrow", isHidden: false, slot: 1)]), "overgrow")
        XCTAssertNil(PokemonSpeciesIdentity.primaryAbilitySlug(
            [(slug: "chlorophyll", isHidden: true, slot: 3)]))
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
        XCTAssertEqual(BattleEngine.rulesVersion, 14)
        XCTAssertEqual(MultiplayerWireMessage.protocolVersion, 9)
    }
}
