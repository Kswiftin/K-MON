import XCTest
@testable import PokeTokenBar

final class RotomMetronomeTests: XCTestCase {
    private func mon() -> MonState {
        MonState(baseID: 479, pathIDs: [479], stageIndex: 0, usedAtStage: 0,
                 rarity: .rare, totalForms: 1)
    }

    func testRotomFormsKeepSpeciesIdentityAndUseDistinctPresentationIDs() throws {
        var rotom = mon()
        XCTAssertEqual(rotom.currentID, 479)
        XCTAssertEqual(rotom.presentationID, 479)
        rotom.rotomForm = .wash
        XCTAssertEqual(rotom.currentID, 479, "폼체인지가 도감 종 번호를 바꾸면 안 된다")
        XCTAssertEqual(rotom.presentationID, 10_009)

        let restored = try JSONDecoder().decode(MonState.self, from: JSONEncoder().encode(rotom))
        XCTAssertEqual(restored.rotomForm, .wash)
        XCTAssertEqual(restored.presentationID, 10_009)
    }

    func testEveryApplianceFormHasTheGenerationFiveSignatureMove() {
        XCTAssertNil(RotomForm.normal.signatureMoveID)
        XCTAssertEqual(RotomForm.heat.signatureMoveID, 315)
        XCTAssertEqual(RotomForm.wash.signatureMoveID, 56)
        XCTAssertEqual(RotomForm.frost.signatureMoveID, 59)
        XCTAssertEqual(RotomForm.fan.signatureMoveID, 403)
        XCTAssertEqual(RotomForm.mow.signatureMoveID, 437)
    }

    func testMetronomeTurnUsesResolvedMovesButConsumesMetronomePP() {
        let metronome = MoveSpec(id: 118, names: ["ko": "손가락흔들기"], type: .normal,
                                 power: 0, damageClass: .status, accuracy: nil, pp: 10)
        let stats = BattleStats(hp: 85, atk: 50, def: 95, spa: 120, spd: 115, spe: 80)
        let rental = BattleSnapshot(speciesID: 468, name: "Rental Togekiss", trainer: nil,
                                    level: 50, nature: nil, isShiny: false,
                                    types: [.fairy, .flying], base: stats, moves: [metronome])
        var battle = TeamPracticeBattle(mine: [BattleSide(rental)], opponents: [BattleSide(rental)],
                                        rng: SplitMix64(seed: 7))
        let called = MoveSpec(id: 53, names: ["en": "Flamethrower"], type: .fire,
                              power: 90, damageClass: .special, accuracy: 100, pp: 15)

        XCTAssertTrue(battle.useResolvedMoves(called, cpuMove: called))
        XCTAssertEqual(battle.mine[0].pp[0], 9)
        XCTAssertEqual(battle.opponents[0].pp[0], 9)
        XCTAssertTrue(battle.events.contains { if case .move(_, let moveID) = $0 { return moveID == 53 }; return false })
    }

    func testNetworkMetronomeUsesSharedCalledMoveInsteadOfStruggle() {
        let metronome = MoveSpec(id: 118, names: ["ko": "손가락흔들기"], type: .normal,
                                 power: 0, damageClass: .status, accuracy: nil, pp: 99)
        let called = MoveSpec(id: 53, names: ["ko": "화염방사"], type: .fire,
                              power: 90, damageClass: .special, accuracy: 100, pp: 15)
        let stats = BattleStats(hp: 85, atk: 50, def: 95, spa: 120, spd: 115, spe: 80)
        let rental = BattleSnapshot(speciesID: 468, name: "Rental Togekiss", trainer: nil,
                                    level: 50, nature: nil, isShiny: false,
                                    types: [.fairy, .flying], base: stats, moves: [metronome])
        var battle = NetBattleState(iAmA: true, myTeam: [BattleSide(rental)],
                                    oppTeam: [BattleSide(rental)], rng: SplitMix64(seed: 19))
        battle.isMetronome = true
        battle.myAction = .metronome(move: called)
        battle.oppAction = .metronome(move: called)

        _ = battle.resolveChosenActions()

        XCTAssertEqual(battle.myTeam[0].pp[0], 98)
        XCTAssertTrue(battle.events.contains {
            if case .move(_, let moveID) = $0 { return moveID == called.id }
            return false
        })
        XCTAssertFalse(battle.events.contains {
            if case .move(_, let moveID) = $0 { return moveID == MoveSpec.struggleID }
            return false
        })
        let lines = BattleLogSource.netBattle(battle, mine: .a, l: L(.ko))
        XCTAssertTrue(lines.contains { $0.text.contains("화염방사") })
        XCTAssertFalse(lines.contains { $0.text.contains("발버둥") },
                       "호출 기술이 대여 포켓몬의 무브셋에 없더라도 발버둥으로 대체하면 안 된다")
        XCTAssertTrue(battle.eventBatches[0].b.moves.contains(where: { $0.id == called.id }),
                      "상대가 호출한 기술도 재생 문맥에 보존돼야 한다")
    }
}
