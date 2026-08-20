import XCTest
@testable import PokeTokenBar

final class NetTeamBattleTests: XCTestCase {
    private func move(id: Int = 1, power: Int = 20) -> MoveSpec {
        MoveSpec(id: id, names: ["en": "Move \(id)"], type: .normal, power: power,
                 damageClass: power == 0 ? .status : .physical, accuracy: nil, pp: 20)
    }

    private func snapshot(_ id: Int, speed: Int = 80, power: Int = 20) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "#\(id)", trainer: "Trainer", level: 50,
                       nature: nil, isShiny: false, types: [.normal],
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: speed),
                       moves: [move(id: id, power: power)])
    }

    private var profile: BattleRankProfile {
        BattleRankProfile(rank: BattleRank(points: 100), stardust: 10_000)
    }

    func testChallengeAcceptAndActionMessagesRoundTrip() throws {
        let lineup = [snapshot(1), snapshot(2), snapshot(3)]
        let challenge = NetMessage.challenge(snapshot: lineup[0], lineup: lineup, teamSize: 3,
                                             seed: 99, profile: profile,
                                             rulesVersion: BattleEngine.rulesVersion)
        let decodedChallenge = try JSONDecoder().decode(NetMessage.self,
                                                        from: JSONEncoder().encode(challenge))
        guard case .challenge(let lead, let decodedLineup, let size, let seed, let decodedProfile, let version)
                = decodedChallenge else { return XCTFail("challenge case") }
        XCTAssertEqual(lead, lineup[0])
        XCTAssertEqual(decodedLineup, lineup)
        XCTAssertEqual(size, 3)
        XCTAssertEqual(seed, 99)
        XCTAssertEqual(decodedProfile, profile)
        XCTAssertEqual(version, BattleEngine.rulesVersion)

        let accept = NetMessage.accept(snapshot: lineup[0], lineup: lineup, teamSize: 3,
                                       profile: profile, rulesVersion: BattleEngine.rulesVersion)
        guard case .accept(let acceptedLead, let acceptedLineup, let acceptedSize, _, _)
                = try JSONDecoder().decode(NetMessage.self, from: JSONEncoder().encode(accept)) else {
            return XCTFail("accept case")
        }
        XCTAssertEqual(acceptedLead, lineup[0])
        XCTAssertEqual(acceptedLineup, lineup)
        XCTAssertEqual(acceptedSize, 3)

        let action = NetMessage.action(turn: 7, action: .switchTo(index: 2))
        guard case .action(let turn, let decodedAction)
                = try JSONDecoder().decode(NetMessage.self, from: JSONEncoder().encode(action)) else {
            return XCTFail("action case")
        }
        XCTAssertEqual(turn, 7)
        XCTAssertEqual(decodedAction, .switchTo(index: 2))
    }

    func testLegacyChallengeAndMoveStillDecode() throws {
        let lead = snapshot(1)
        let modern = NetMessage.challenge(snapshot: lead, lineup: [lead], teamSize: 1,
                                          seed: 4, profile: profile, rulesVersion: 5)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(modern))
            as? [String: Any])
        var payload = try XCTUnwrap(object["challenge"] as? [String: Any])
        payload.removeValue(forKey: "lineup")
        payload.removeValue(forKey: "teamSize")
        object["challenge"] = payload
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        guard case .challenge(let decodedLead, let lineup, let size, _, _, let version)
                = try JSONDecoder().decode(NetMessage.self, from: legacyData) else {
            return XCTFail("legacy challenge case")
        }
        XCTAssertEqual(decodedLead, lead)
        XCTAssertEqual(lineup, [lead])
        XCTAssertEqual(size, 1)
        XCTAssertEqual(version, 5, "구버전은 디코딩된 뒤 규칙 불일치 경로에서 거절된다")

        let oldMove = NetMessage.move(turn: 2, moveIndex: 0)
        guard case .move(let turn, let index)
                = try JSONDecoder().decode(NetMessage.self, from: JSONEncoder().encode(oldMove)) else {
            return XCTFail("legacy move case")
        }
        XCTAssertEqual(turn, 2)
        XCTAssertEqual(index, 0)
    }

    func testLineupValidationRejectsUnsupportedSizesCountsAndBadSnapshots() {
        let one = snapshot(1)
        XCTAssertTrue(BattleCenter.validLineup(snapshot: one, lineup: [one], teamSize: 1))
        XCTAssertFalse(BattleCenter.validLineup(snapshot: one, lineup: [one, snapshot(2)], teamSize: 2))
        XCTAssertFalse(BattleCenter.validLineup(snapshot: one, lineup: [one], teamSize: 3))
        var badLevel = one
        badLevel.level = 101
        XCTAssertFalse(BattleCenter.validLineup(snapshot: badLevel, lineup: [badLevel], teamSize: 1))
        var noType = one
        noType.types = []
        XCTAssertFalse(BattleCenter.validLineup(snapshot: noType, lineup: [noType], teamSize: 1))
        XCTAssertFalse(BattleCenter.validLineup(snapshot: one, lineup: [snapshot(9)], teamSize: 1),
                       "미리보기 선봉과 실제 1번 슬롯이 달라서는 안 된다")
    }

    func testAllFourActionCombinationsStayIdenticalFromBothPeerViews() {
        let teamA = [BattleSide(snapshot(1)), BattleSide(snapshot(2))]
        let teamB = [BattleSide(snapshot(3)), BattleSide(snapshot(4))]
        let combinations: [(NetBattleAction, NetBattleAction)] = [
            (.move(index: 0), .move(index: 0)),
            (.switchTo(index: 1), .move(index: 0)),
            (.move(index: 0), .switchTo(index: 1)),
            (.switchTo(index: 1), .switchTo(index: 1)),
        ]

        for (actionA, actionB) in combinations {
            var challenger = NetBattleState(iAmA: true, myTeam: teamA, oppTeam: teamB,
                                            rng: SplitMix64(seed: 77))
            challenger.myAction = actionA
            challenger.oppAction = actionB
            let challengerResult = challenger.resolveChosenActions()

            var defender = NetBattleState(iAmA: false, myTeam: teamB, oppTeam: teamA,
                                          rng: SplitMix64(seed: 77))
            defender.myAction = actionB
            defender.oppAction = actionA
            let defenderResult = defender.resolveChosenActions()

            XCTAssertEqual(challenger.myTeam, defender.oppTeam, "A action \(actionA), B action \(actionB)")
            XCTAssertEqual(challenger.oppTeam, defender.myTeam)
            XCTAssertEqual(challenger.myActive, defender.oppActive)
            XCTAssertEqual(challenger.oppActive, defender.myActive)
            XCTAssertEqual(challenger.events, defender.events)
            XCTAssertEqual(challenger.eventBatches, defender.eventBatches)
            XCTAssertEqual(challenger.rng.state, defender.rng.state)
            XCTAssertEqual(challengerResult, defenderResult)
        }
    }

    func testSwitchConsumesTurnResetsOutgoingAndNewSlotTakesAttack() {
        var outgoing = BattleSide(snapshot(1))
        outgoing.status = .toxic
        outgoing.statusCounter = 4
        outgoing.confusionTurns = 3
        let incoming = BattleSide(snapshot(2))
        let attacker = BattleSide(snapshot(3, power: 80))
        var state = NetBattleState(iAmA: true, myTeam: [outgoing, incoming], oppTeam: [attacker],
                                   rng: SplitMix64(seed: 5))
        state.myAction = .switchTo(index: 1)
        state.oppAction = .move(index: 0)

        XCTAssertNil(state.resolveChosenActions())

        XCTAssertEqual(state.myActive, 1)
        XCTAssertEqual(state.myTeam[0].status, .poison)
        XCTAssertEqual(state.myTeam[0].statusCounter, 0)
        XCTAssertEqual(state.myTeam[0].confusionTurns, 0)
        XCTAssertLessThan(state.myTeam[1].hp, state.myTeam[1].stats.hp,
                          "교체해 들어온 포켓몬이 상대 공격을 받아야 한다")
        XCTAssertEqual(state.turn, 2)
    }

    func testFaintedLeadAutomaticallyAdvancesInLineupOrder() {
        let attacker = BattleSide(snapshot(1, speed: 200, power: 500))
        var lead = BattleSide(snapshot(2, speed: 10, power: 1))
        lead.hp = 1
        let reserve = BattleSide(snapshot(3))
        var state = NetBattleState(iAmA: true, myTeam: [attacker], oppTeam: [lead, reserve],
                                   rng: SplitMix64(seed: 1))
        state.myAction = .move(index: 0)
        state.oppAction = .move(index: 0)

        XCTAssertNil(state.resolveChosenActions())
        XCTAssertEqual(state.oppActive, 1)
        XCTAssertTrue(state.oppTeam[1].isAlive)
    }

    func testSimultaneousTeamWipeIsADraw() {
        var a = BattleSide(snapshot(1, power: 0))
        var b = BattleSide(snapshot(2, power: 0))
        a.hp = 1; b.hp = 1
        a.status = .poison; b.status = .poison
        var state = NetBattleState(iAmA: true, myTeam: [a], oppTeam: [b],
                                   rng: SplitMix64(seed: 2))
        state.myAction = .move(index: 0)
        state.oppAction = .move(index: 0)

        XCTAssertEqual(state.resolveChosenActions(), .draw)
        XCTAssertFalse(state.myTeam[0].isAlive)
        XCTAssertFalse(state.oppTeam[0].isAlive)
    }

    func testDisconnectOutcomeUsesWholeTeamHP() {
        var myLead = BattleSide(snapshot(1)), myReserve = BattleSide(snapshot(2))
        var oppLead = BattleSide(snapshot(3)), oppReserve = BattleSide(snapshot(4))
        myLead.hp = myLead.stats.hp
        myReserve.hp = 0
        oppLead.hp = oppLead.stats.hp * 3 / 4
        oppReserve.hp = oppReserve.stats.hp

        XCTAssertEqual(BattleEngine.disconnectOutcome(me: myLead, opp: oppLead), true,
                       "활성 슬롯만 보면 내가 앞선다는 픽스처")
        XCTAssertEqual(BattleEngine.disconnectOutcome(me: [myLead, myReserve],
                                                      opp: [oppLead, oppReserve]), false,
                       "팀 전체 비율로는 상대가 앞선다")
    }

    func testInvalidSwitchAndMoveActionsAreRejectedAtBoundary() {
        var fainted = BattleSide(snapshot(2))
        fainted.hp = 0
        let state = NetBattleState(iAmA: true,
                                   myTeam: [BattleSide(snapshot(1)), fainted],
                                   oppTeam: [BattleSide(snapshot(3))],
                                   rng: SplitMix64(seed: 0))
        XCTAssertFalse(state.canChoose(.switchTo(index: -1), mine: true))
        XCTAssertFalse(state.canChoose(.switchTo(index: 0), mine: true))
        XCTAssertFalse(state.canChoose(.switchTo(index: 1), mine: true))
        XCTAssertFalse(state.canChoose(.move(index: 9), mine: true))
        XCTAssertFalse(state.canChoose(.move(index: -1), mine: true),
                       "PP가 남았는데 임의로 발버둥을 고를 수 없다")
    }
}
