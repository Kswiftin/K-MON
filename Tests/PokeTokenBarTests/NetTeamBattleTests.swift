import XCTest
@testable import PokeTokenBar

final class NetTeamBattleTests: XCTestCase {
    @MainActor
    private final class ManualChallengeTimeoutScheduler: BattleChallengeTimeoutScheduling {
        private(set) var action: (@MainActor () -> Void)?
        private(set) var cancellationCount = 0

        func schedule(_ action: @escaping @MainActor () -> Void) -> BattleChallengeTimeout {
            self.action = action
            return BattleChallengeTimeout { [weak self] in self?.cancellationCount += 1 }
        }

        func fire() { action?() }
    }
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
                                             rulesVersion: BattleEngine.rulesVersion, chatSupported: true)
        let decodedChallenge = try JSONDecoder().decode(NetMessage.self,
                                                        from: JSONEncoder().encode(challenge))
        guard case .challenge(let lead, let decodedLineup, let size, let seed, let decodedProfile, let version, let chatSupported)
                = decodedChallenge else { return XCTFail("challenge case") }
        XCTAssertEqual(lead, lineup[0])
        XCTAssertEqual(decodedLineup, lineup)
        XCTAssertEqual(size, 3)
        XCTAssertEqual(seed, 99)
        XCTAssertEqual(decodedProfile, profile)
        XCTAssertEqual(version, BattleEngine.rulesVersion)
        XCTAssertEqual(chatSupported, true)

        let accept = NetMessage.accept(snapshot: lineup[0], lineup: lineup, teamSize: 3,
                                       profile: profile, rulesVersion: BattleEngine.rulesVersion, chatSupported: true)
        guard case .accept(let acceptedLead, let acceptedLineup, let acceptedSize, _, _, let acceptedChat)
                = try JSONDecoder().decode(NetMessage.self, from: JSONEncoder().encode(accept)) else {
            return XCTFail("accept case")
        }
        XCTAssertEqual(acceptedLead, lineup[0])
        XCTAssertEqual(acceptedLineup, lineup)
        XCTAssertEqual(acceptedSize, 3)
        XCTAssertEqual(acceptedChat, true)

        let action = NetMessage.action(turn: 7, action: .switchTo(index: 2))
        guard case .action(let turn, let decodedAction)
                = try JSONDecoder().decode(NetMessage.self, from: JSONEncoder().encode(action)) else {
            return XCTFail("action case")
        }
        XCTAssertEqual(turn, 7)
        XCTAssertEqual(decodedAction, .switchTo(index: 2))
    }

    func testSixPokemonPoolRoundTripsBeforeTheFinalTeam() throws {
        let pool = (1...6).map { snapshot($0) }
        let message = NetMessage.poolReady(lineup: pool, profile: profile,
                                           rulesVersion: BattleEngine.rulesVersion,
                                           chatSupported: true)
        guard case .poolReady(let decoded, let decodedProfile, let version, let chat)
                = try JSONDecoder().decode(NetMessage.self, from: JSONEncoder().encode(message)) else {
            return XCTFail("poolReady case")
        }
        XCTAssertEqual(decoded, pool)
        XCTAssertEqual(decodedProfile, profile)
        XCTAssertEqual(version, BattleEngine.rulesVersion)
        XCTAssertEqual(chat, true)
    }

    func testLegacyChallengeAndMoveStillDecode() throws {
        let lead = snapshot(1)
        let modern = NetMessage.challenge(snapshot: lead, lineup: [lead], teamSize: 1,
                                          seed: 4, profile: profile, rulesVersion: 5, chatSupported: true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(modern))
            as? [String: Any])
        var payload = try XCTUnwrap(object["challenge"] as? [String: Any])
        payload.removeValue(forKey: "lineup")
        payload.removeValue(forKey: "teamSize")
        payload.removeValue(forKey: "chatSupported")
        object["challenge"] = payload
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        guard case .challenge(let decodedLead, let lineup, let size, _, _, let version, let chatSupported)
                = try JSONDecoder().decode(NetMessage.self, from: legacyData) else {
            return XCTFail("legacy challenge case")
        }
        XCTAssertEqual(decodedLead, lead)
        XCTAssertEqual(lineup, [lead])
        XCTAssertEqual(size, 1)
        XCTAssertEqual(version, 5, "구버전은 디코딩된 뒤 규칙 불일치 경로에서 거절된다")
        XCTAssertNil(chatSupported)

        let oldMove = NetMessage.move(turn: 2, moveIndex: 0)
        guard case .move(let turn, let index)
                = try JSONDecoder().decode(NetMessage.self, from: JSONEncoder().encode(oldMove)) else {
            return XCTFail("legacy move case")
        }
        XCTAssertEqual(turn, 2)
        XCTAssertEqual(index, 0)
    }

    func testChallengeCancellationReasonRoundTripsWithoutChangingLegacyMessages() throws {
        let timeout = NetMessage.challengeCancelled(reason: .timedOut)
        guard case .challengeCancelled(let reason) = try JSONDecoder().decode(NetMessage.self,
                                                                                from: JSONEncoder().encode(timeout)) else {
            return XCTFail("challenge cancellation case")
        }
        XCTAssertEqual(reason, .timedOut)

        let legacyDecline = try JSONSerialization.data(withJSONObject: ["decline": [:]])
        guard case .decline = try JSONDecoder().decode(NetMessage.self, from: legacyDecline) else {
            return XCTFail("legacy decline must remain decodable")
        }
    }

    @MainActor
    func testChallengeTimeoutReturnsPendingChallengeToReadyAndClearsTemporarySelection() {
        let scheduler = ManualChallengeTimeoutScheduler()
        let store = CompanionStore(provider: StubProvider(value: EvoLine(baseID: 1, tree: .init(speciesID: 1, children: []), rarity: .common, names: [:])),
                                   clock: { Date() },
                                   fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                   rng: SeededRNG(seed: 1))
        let center = BattleCenter(companion: store, challengeTimeoutScheduler: scheduler)
        center.phase = .incoming(peer: "Misty")
        center.incomingPickedTeam = [UUID()]
        center.startChallengeTimeout()

        XCTAssertNotNil(center.challengeEndsAt)
        scheduler.fire()

        XCTAssertEqual(center.phase, .ready)
        XCTAssertNil(center.challengeEndsAt)
        XCTAssertTrue(center.incomingPickedTeam.isEmpty)
        XCTAssertEqual(center.lastError, store.l.battleChallengeTimedOut)
    }

    @MainActor
    func testCancellingAChallengeCancelsItsPendingTimeout() {
        let scheduler = ManualChallengeTimeoutScheduler()
        let store = CompanionStore(provider: StubProvider(value: EvoLine(baseID: 1, tree: .init(speciesID: 1, children: []), rarity: .common, names: [:])),
                                   clock: { Date() },
                                   fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                   rng: SeededRNG(seed: 1))
        let center = BattleCenter(companion: store, challengeTimeoutScheduler: scheduler)
        center.phase = .challenging(peer: "Brock")
        center.startChallengeTimeout()
        center.cancelChallenge()

        XCTAssertEqual(center.phase, .ready)
        XCTAssertNil(center.challengeEndsAt)
        XCTAssertEqual(scheduler.cancellationCount, 1)
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

        // 무브셋 범위는 **선봉이 아닌 슬롯**도 본다. 검사를 리드 스냅샷에만 걸면 2번 이후 슬롯이
        // 무검사로 들어와, 교체된 뒤부터 `statChance: 5000`(2차효과 확정)이 살아난다.
        var hostile = snapshot(2)
        var move = hostile.moves?.first
        move?.statChance = 5_000
        hostile.moves = move.map { [$0] }
        // teamSize 는 **지원 크기(1/3/6)** 로 잡는다 — 2 로 재면 크기 가드에서 먼저 걸려
        // 무브셋 검사에 닿지도 못한 채 초록으로 통과한다(검사를 지워도 통과한다).
        XCTAssertTrue(BattleCenter.validLineup(snapshot: one, lineup: [one, snapshot(2), snapshot(3)],
                                               teamSize: 3),
                      "정상 3인 라인업이 먼저 통과해야 아래 거절이 무브셋 때문임을 안다")
        XCTAssertFalse(BattleCenter.validLineup(snapshot: one, lineup: [one, hostile, snapshot(3)],
                                                teamSize: 3),
                       "2번 슬롯의 범위 밖 무브셋도 핸드셰이크에서 거절한다")
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
        XCTAssertEqual(state.myTeam[0].status, .toxic)
        XCTAssertEqual(state.myTeam[0].statusCounter, 1)
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

    func testManualReplacementLeavesTheFaintedSlotActiveUntilChosen() {
        let attacker = BattleSide(snapshot(1, speed: 200, power: 500))
        var lead = BattleSide(snapshot(2, speed: 10, power: 1)); lead.hp = 1
        var state = NetBattleState(iAmA: true, myTeam: [attacker],
                                   oppTeam: [lead, BattleSide(snapshot(3))],
                                   rng: SplitMix64(seed: 1))
        state.automaticallyReplacesFainted = false
        state.myAction = .move(index: 0); state.oppAction = .move(index: 0)

        XCTAssertNil(state.resolveChosenActions())
        XCTAssertEqual(state.oppActive, 0)
        XCTAssertFalse(state.oppTeam[0].isAlive)
        XCTAssertTrue(state.canChoose(.switchTo(index: 1), mine: false))
        XCTAssertFalse(state.canChoose(.move(index: 0), mine: false))
    }

    func testForcedReplacementDoesNotConsumeTheNewPokemonsMove() {
        var fainted = BattleSide(snapshot(1)); fainted.hp = 0
        let reserve = BattleSide(snapshot(2))
        var state = NetBattleState(iAmA: true, myTeam: [BattleSide(snapshot(3))],
                                   oppTeam: [fainted, reserve], rng: SplitMix64(seed: 7))
        state.automaticallyReplacesFainted = false

        XCTAssertTrue(state.replaceFainted(to: 1, mine: false))
        XCTAssertEqual(state.oppActive, 1)
        XCTAssertNil(state.oppAction, "강제 교체는 그 턴의 행동을 차지하지 않는다")
        XCTAssertEqual(state.turn, 1, "강제 교체만으로 턴이 넘어가지 않는다")
        XCTAssertTrue(state.canChoose(.move(index: 0), mine: false),
                      "새로 나온 포켓몬은 곧바로 기술을 선택할 수 있다")
        XCTAssertEqual(state.events.last, .sendOut(.b, teamIndex: 1))

        state.myAction = .move(index: 0)
        state.oppAction = .move(index: 0)
        XCTAssertNil(state.resolveChosenActions())
        XCTAssertEqual(state.turn, 2, "새 포켓몬의 기술까지 해상한 뒤에만 턴이 넘어간다")
    }

    /// 자동 출전이 **스트림에 남는다**. 재생기는 이 이벤트를 보고서야 표시 상태를 새 개체로
    /// 갈아탄다 — 없으면 기절 턴에 새로 나온 만피 개체를 이전 개체의 HP 로 깎아 그리고, `isAlive`
    /// 가 false 라 흐린 '쓰러진' 스프라이트로 보여 준다(리뷰 #1).
    func testTheAutomaticSendOutIsRecordedInTheEventStream() {
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
        XCTAssertEqual(state.events.last, .sendOut(.b, teamIndex: 1),
                       "출전은 기절 **뒤**다 — 앞에 두면 기절이 새 개체에 그려진다")
        XCTAssertTrue(state.events.contains(.faint(.b)))
    }

    /// 미러 분기 — **내 쪽(A)** 자동 출전. B 쪽만 검증하면 A 쪽 블록은 한 번도 돌지 않고, 그래도
    /// 라인 커버리지는 초록으로 보고한다(`--show-regions` 에서 `^0` 으로 잡힌 자리다).
    func testTheAutomaticSendOutIsRecordedForMyOwnSideToo() {
        var lead = BattleSide(snapshot(1, speed: 10, power: 1))
        lead.hp = 1
        let reserve = BattleSide(snapshot(2))
        var state = NetBattleState(iAmA: true, myTeam: [lead, reserve],
                                   oppTeam: [BattleSide(snapshot(3, speed: 200, power: 500))],
                                   rng: SplitMix64(seed: 1))
        state.myAction = .move(index: 0)
        state.oppAction = .move(index: 0)

        XCTAssertNil(state.resolveChosenActions())

        XCTAssertEqual(state.myActive, 1)
        XCTAssertEqual(state.events.last, .sendOut(.a, teamIndex: 1))
    }

    /// 자기 교체도 스트림에 남고 **상대 공격보다 앞**이다. 뒤에 두면 재생이 이전 개체에 남의
    /// 데미지를 그린다(교체한 쪽은 그 턴에 공격을 맞으며 시작한다).
    func testAVoluntarySwitchIsRecordedBeforeTheOpponentsAttack() {
        var state = NetBattleState(iAmA: true,
                                   myTeam: [BattleSide(snapshot(1)), BattleSide(snapshot(2))],
                                   oppTeam: [BattleSide(snapshot(3, power: 80))],
                                   rng: SplitMix64(seed: 5))
        state.myAction = .switchTo(index: 1)
        state.oppAction = .move(index: 0)

        XCTAssertNil(state.resolveChosenActions())

        let sendOut = state.events.firstIndex(of: .sendOut(.a, teamIndex: 1))
        let damage = state.events.firstIndex { if case .damage(.a, _, _) = $0 { return true } else { return false } }
        XCTAssertNotNil(sendOut)
        XCTAssertNotNil(damage, "교체해 들어온 쪽이 맞지 않으면 순서를 볼 수 없다")
        XCTAssertLessThan(sendOut ?? .max, damage ?? -1, "출전이 데미지 뒤면 이전 개체가 남의 데미지를 맞는다")
    }

    /// 배치의 이벤트 수는 평평한 스트림과 **정확히** 같다. 자동 출전 이벤트가 배치에 빠지면
    /// `BattleLogSource.netBattle` 이 진행도로 자를 때 그만큼 밀려, 로그가 재생보다 앞서거나
    /// 뒤처진다(배치 문맥을 자동 출전 전에 고정하면서 실수하기 쉬운 자리다).
    func testEveryEventLandsInABatchSoTheLogSliceStaysAligned() {
        let attacker = BattleSide(snapshot(1, speed: 200, power: 500))
        var lead = BattleSide(snapshot(2, speed: 10, power: 1))
        lead.hp = 1
        var state = NetBattleState(iAmA: true, myTeam: [attacker],
                                   oppTeam: [lead, BattleSide(snapshot(3)), BattleSide(snapshot(4))],
                                   rng: SplitMix64(seed: 1))
        for _ in 0..<2 {
            state.myAction = .move(index: 0)
            state.oppAction = .move(index: 0)
            _ = state.resolveChosenActions()
        }

        XCTAssertEqual(state.eventBatches.flatMap(\.events), state.events,
                       "배치와 평평한 스트림이 어긋나면 로그 진행도가 밀린다")
        XCTAssertTrue(state.events.contains { if case .sendOut = $0 { return true } else { return false } },
                      "자동 출전이 안 일어난 픽스처면 이 검증이 아무것도 안 본다")
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
