import XCTest
@testable import PokeTokenBar

/// 압정뿌리기 부류 — **상대 편에 깔리고, 교체로 새로 나오는 개체가 밟는다.**
///
/// 앞선 진영 상태(리플렉터·순풍)와 갈리는 곳이 셋이다: ①까는 편이 상대다 ②턴이 지나도 걷히지
/// 않는다(층으로 쌓인다) ③효과가 발동하는 시점이 기술을 쓴 턴이 아니라 **다음 교체**다.
/// 세 번째 때문에 교체 진입 훅이 없으면 데이터·엔진이 다 맞아도 화면에서는 아무 일도 없다.
final class BattleEntryHazardTests: XCTestCase {

    private func side(_ types: [PokemonType] = [.normal], hp: Int = 100,
                      ability: String? = nil) -> BattleSide {
        BattleSide(BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50,
                                  nature: nil, isShiny: false, types: types,
                                  base: BattleStats(hp: hp, atk: 100, def: 100,
                                                    spa: 100, spd: 100, spe: 100),
                                  ability: ability, weightHectograms: 100))
    }

    /// 이 상태를 까는 기술 — 데이터에서 되짚는다(엔진은 반대 방향만 안다).
    private func hazardMove(_ condition: BattleSideCondition) throws -> MoveSpec {
        let id = try XCTUnwrap(ShowdownMoveData.effects.keys.sorted().first {
            BattleSideCondition.called(byMoveID: $0) == condition
        }, "\(condition) 를 부르는 기술이 데이터에 없다")
        var move = MoveSpec(id: id, names: ["ko": "기술"], type: .normal, power: 0,
                            damageClass: .status, accuracy: nil, pp: 20)
        move.ailment = "none"; move.ailmentChance = 0
        move.statChanges = []; move.statChance = 0; move.targetsUser = false
        return move
    }

    /// 기술을 한 번 쓴다 — 공격자는 `.a`, 상대는 `.b` 다.
    @discardableResult
    private func use(_ move: MoveSpec, field: inout BattleField,
                     attacker: inout BattleSide) -> [BattleEvent] {
        var defender = side()
        var rng = SplitMix64(seed: 7)
        return BattleEngine.applyAttack(attacker: &attacker, defender: &defender,
                                        attackerActor: .a, defenderActor: .b,
                                        move: move, field: &field,
                                        attackerTeam: .a, defenderTeam: .b, rng: &rng)
    }

    /// 깔린 판에 개체 하나를 내보낸다.
    @discardableResult
    private func switchIn(_ entering: inout BattleSide, field: BattleField,
                          team: BattleTeamSlot = .b,
                          rng: inout SplitMix64) -> [BattleEvent] {
        BattleEngine.applyEntryHazards(&entering, actor: .b, team: team, field: field, rng: &rng)
    }

    private func laid(_ condition: BattleSideCondition, layers: Int = 1,
                      on team: BattleTeamSlot = .b) -> BattleField {
        var field = BattleField()
        for _ in 0..<layers { XCTAssertTrue(field.start(condition, for: team)) }
        return field
    }

    // MARK: 어느 편에 깔리는가

    /// 압정 부류는 **상대 편에** 깔린다. 지금까지의 진영 상태기와 반대라, 편을 데이터에서
    /// 읽지 않으면 자기 발밑에 압정을 깐다(그리고 화면에는 정상으로 보인다).
    func testEntryHazardMovesLandOnTheOpponentSide() throws {
        for condition in BattleSideCondition.allCases where condition.isEntryHazard {
            var field = BattleField()
            var attacker = side()
            let events = use(try hazardMove(condition), field: &field, attacker: &attacker)
            XCTAssertTrue(field.has(condition, for: .b), "\(condition) 가 상대 편에 안 깔렸다")
            XCTAssertFalse(field.has(condition, for: .a), "\(condition) 를 자기 발밑에 깔았다")
            XCTAssertFalse(attacker.lastMoveFailed)
            XCTAssertTrue(events.contains { event in
                if case .sideConditionStarted(.b, condition) = event { return true }
                return false
            }, "\(condition) 의 시작 줄이 상대 편으로 안 나갔다")
        }
    }

    /// 자기 편 상태기(리플렉터)는 그대로 자기 편이다 — 대조군이 없으면 "전부 상대 편에 깔기" 로
    /// 뒤집어도 위 테스트가 통과한다.
    func testAllySideConditionsStillLandOnTheUsersOwnSide() throws {
        var field = BattleField()
        var attacker = side()
        use(try hazardMove(.reflect), field: &field, attacker: &attacker)
        XCTAssertTrue(field.has(.reflect, for: .a))
        XCTAssertFalse(field.has(.reflect, for: .b))
    }

    // MARK: 층과 지속

    /// 압정은 3층, 독압정은 2층까지 쌓이고 그 위는 실패다. 층이 없으면 두 번째 사용이 실패해
    /// 본가보다 약하고, 상한이 없으면 무한히 쌓여 교체가 즉사가 된다.
    func testLayeredHazardsStackToTheirCapAndThenFail() throws {
        for condition in BattleSideCondition.allCases where condition.isEntryHazard {
            var field = BattleField()
            var attacker = side()
            for layer in 1...condition.maxLayers {
                use(try hazardMove(condition), field: &field, attacker: &attacker)
                XCTAssertEqual(field.layers(condition, for: .b), layer,
                               "\(condition) 가 \(layer) 층에서 안 쌓인다")
                XCTAssertFalse(attacker.lastMoveFailed)
            }
            use(try hazardMove(condition), field: &field, attacker: &attacker)
            XCTAssertEqual(field.layers(condition, for: .b), condition.maxLayers,
                           "\(condition) 가 상한을 넘겼다")
            XCTAssertTrue(attacker.lastMoveFailed, "\(condition) 상한 위에서 실패로 안 접힌다")
        }
    }

    /// 압정·스텔스록은 3층, 독압정은 2층, 끈적끈적네트는 1층이다 — 상한이 전부 같으면
    /// `maxLayers` 가 아무것도 안 재는 상수다.
    func testTheLayerCapsDifferPerHazard() {
        XCTAssertEqual(BattleSideCondition.spikes.maxLayers, 3)
        XCTAssertEqual(BattleSideCondition.toxicSpikes.maxLayers, 2)
        XCTAssertEqual(BattleSideCondition.stealthRock.maxLayers, 1)
        XCTAssertEqual(BattleSideCondition.stickyWeb.maxLayers, 1)
    }

    /// 압정은 **걷히지 않는다.** 턴을 세는 상태와 같은 딕셔너리에 살기 때문에, 감소 루프가
    /// 층을 남은 턴으로 읽으면 세 턴 뒤 조용히 사라진다.
    func testEntryHazardsNeverWearOff() {
        var field = laid(.spikes, layers: 3)
        _ = field.start(.reflect, for: .b)
        var ended: [BattleEvent] = []
        for _ in 0..<12 { ended += BattleEngine.advanceField(&field) }
        XCTAssertEqual(field.layers(.spikes, for: .b), 3, "압정 층이 턴과 함께 줄었다")
        XCTAssertFalse(field.has(.reflect, for: .b), "대조군인 리플렉터는 걷혀야 한다")
        XCTAssertFalse(ended.contains { event in
            if case .sideConditionEnded(_, .spikes) = event { return true }
            return false
        }, "압정에 걷히는 줄이 나갔다")
    }

    // MARK: 밟는 쪽

    /// 압정은 층에 따라 최대 HP 의 1/8·1/6·1/4 을 깎는다.
    func testSpikesHurtByLayerCount() {
        for (layers, divisor) in [(1, 8), (2, 6), (3, 4)] {
            let field = laid(.spikes, layers: layers)
            var entering = side(hp: 200)
            let before = entering.hp
            var rng = SplitMix64(seed: 1)
            let events = switchIn(&entering, field: field, rng: &rng)
            XCTAssertEqual(before - entering.hp, entering.stats.hp / divisor,
                           "\(layers) 층 압정이 1/\(divisor) 을 안 깎는다")
            XCTAssertTrue(events.contains { event in
                if case .damage(_, _, .hazard) = event { return true }
                return false
            }, "압정 데미지 줄이 없다")
        }
    }

    /// 압정·독압정·끈적끈적네트는 **접지한 개체만** 밟는다. 스텔스록만 공중도 맞는다.
    func testOnlyStealthRockReachesAFlierOrALevitator() {
        let grounded = [BattleSideCondition.spikes, .toxicSpikes, .stickyWeb]
        for condition in grounded {
            for airborne in [side([.flying], hp: 200), side([.normal], hp: 200, ability: "levitate")] {
                var entering = airborne
                var rng = SplitMix64(seed: 1)
                let events = switchIn(&entering, field: laid(condition), rng: &rng)
                XCTAssertEqual(events, [], "\(condition) 가 공중에 뜬 개체를 밟게 했다")
                XCTAssertEqual(entering.hp, entering.stats.hp)
                XCTAssertNil(entering.status)
                XCTAssertEqual(entering.stage(.spe), 0)
            }
        }
        var flier = side([.flying], hp: 200)
        var rng = SplitMix64(seed: 1)
        switchIn(&flier, field: laid(.stealthRock), rng: &rng)
        XCTAssertLessThan(flier.hp, flier.stats.hp, "스텔스록은 공중에도 맞는다")
    }

    /// 스텔스록은 **바위 상성**으로 배율이 갈린다(1/8 을 기준으로 ×0.25 ~ ×4).
    /// 배율을 안 보면 불꽃·비행 이중 타입이 1/8 만 맞아 스텔스록이 그냥 약한 압정이 된다.
    func testStealthRockScalesWithRockEffectiveness() {
        let cases: [(types: [PokemonType], divisor: Int)] = [
            ([.fire, .flying], 2),      // ×4
            ([.fire], 4),               // ×2
            ([.normal], 8),             // ×1
            ([.steel], 16),             // ×0.5
            ([.steel, .fighting], 32),  // ×0.25
        ]
        for (types, divisor) in cases {
            var entering = side(types, hp: 320)
            let before = entering.hp
            var rng = SplitMix64(seed: 1)
            switchIn(&entering, field: laid(.stealthRock), rng: &rng)
            XCTAssertEqual(before - entering.hp, entering.stats.hp / divisor,
                           "\(types) 가 1/\(divisor) 을 안 맞는다")
        }
    }

    /// 독압정은 1층이면 독, 2층이면 맹독이다. 층을 안 보면 둘 중 하나가 죽은 갈래다.
    func testToxicSpikesPoisonOnOneLayerAndBadlyPoisonOnTwo() {
        for (layers, status) in [(1, Status.poison), (2, Status.toxic)] {
            var entering = side([.normal], hp: 200)
            var rng = SplitMix64(seed: 1)
            let events = switchIn(&entering, field: laid(.toxicSpikes, layers: layers), rng: &rng)
            XCTAssertEqual(entering.status, status, "\(layers) 층 독압정이 \(status) 를 안 건다")
            XCTAssertEqual(entering.hp, entering.stats.hp, "독압정은 그 자리에서 깎지 않는다")
            XCTAssertTrue(events.contains { event in
                if case .status(_, status) = event { return true }
                return false
            })
        }
    }

    /// 독 면역(강철·독 타입)은 독압정을 밟아도 상태가 안 붙는다 — 면역 판정은 `inflict` 한 곳이
    /// 정본이라 여기서 다시 쓰지 않는다는 뜻이다.
    func testToxicSpikesRespectPoisonImmunity() {
        for types in [[PokemonType.steel], [PokemonType.poison]] {
            var entering = side(types, hp: 200)
            var rng = SplitMix64(seed: 1)
            let events = switchIn(&entering, field: laid(.toxicSpikes, layers: 2), rng: &rng)
            XCTAssertNil(entering.status, "\(types) 에 독이 붙었다")
            XCTAssertEqual(events, [])
        }
    }

    /// 끈적끈적네트는 스피드를 한 랭크 내린다 — 데미지가 아니다.
    func testStickyWebDropsSpeedByOneStage() {
        var entering = side([.normal], hp: 200)
        var rng = SplitMix64(seed: 1)
        let events = switchIn(&entering, field: laid(.stickyWeb), rng: &rng)
        XCTAssertEqual(entering.stage(.spe), -1)
        XCTAssertEqual(entering.hp, entering.stats.hp)
        XCTAssertEqual(events, [.boost(.b, .spe, -1)])
    }

    // MARK: 순서·기절·난수

    /// 여러 개가 깔려 있으면 **고정 순서**로 밟는다(끈적끈적네트 → 스텔스록 → 압정 → 독압정).
    /// 순서가 실행마다 달라지면 두 피어의 로그가 갈린다(딕셔너리 순회와 같은 함정이다).
    func testHazardsApplyInAFixedOrder() {
        var field = BattleField()
        for condition in BattleSideCondition.allCases where condition.isEntryHazard {
            for _ in 0..<condition.maxLayers { _ = field.start(condition, for: .b) }
        }
        var entering = side([.normal], hp: 400)
        var rng = SplitMix64(seed: 1)
        let events = switchIn(&entering, field: field, rng: &rng)
        XCTAssertEqual(events, [.boost(.b, .spe, -1),
                                .damage(.b, amount: entering.stats.hp / 8, cause: .hazard),
                                .damage(.b, amount: entering.stats.hp / 4, cause: .hazard),
                                .status(.b, .toxic)])
    }

    /// 압정으로 쓰러지면 **기절 줄이 나가고 남은 것은 밟지 않는다.** 쓰러진 뒤에도 계속 밟으면
    /// 쓰러진 개체에 독이 붙고, 재생과 엔진의 최종 상태가 갈린다.
    func testAHazardFaintStopsTheRestAndLeavesAFaintLine() {
        var field = laid(.spikes, layers: 3)
        _ = field.start(.toxicSpikes, for: .b)
        var entering = side([.normal], hp: 200)
        entering.hp = 1
        var rng = SplitMix64(seed: 1)
        let events = switchIn(&entering, field: field, rng: &rng)
        XCTAssertEqual(entering.hp, 0)
        XCTAssertNil(entering.status, "쓰러진 뒤에 독압정을 밟았다")
        XCTAssertEqual(events.last, .faint(.b))
    }

    /// 이미 쓰러진 개체는 아무것도 밟지 않는다(자동 출전이 죽은 칸을 다시 부를 수 있다).
    func testAFaintedSwitchInStepsOnNothing() {
        var entering = side([.normal], hp: 200)
        entering.hp = 0
        var rng = SplitMix64(seed: 1)
        XCTAssertEqual(switchIn(&entering, field: laid(.spikes, layers: 3), rng: &rng), [])
    }

    /// 밟는 일은 **난수를 쓰지 않는다.** 쓰면 교체마다 두 피어의 난수 소비가 갈려, 그 뒤 모든
    /// 판정이 한 칸씩 밀린다.
    func testSteppingOnHazardsConsumesNoRandomness() {
        var field = BattleField()
        for condition in BattleSideCondition.allCases where condition.isEntryHazard {
            for _ in 0..<condition.maxLayers { _ = field.start(condition, for: .b) }
        }
        var rng = SplitMix64(seed: 99)
        let before = rng
        var entering = side([.normal], hp: 400)
        switchIn(&entering, field: field, rng: &rng)
        var expected = before, actual = rng
        XCTAssertEqual(expected.next(), actual.next(), "교체 진입이 난수를 태웠다")
    }

    /// 깔린 편만 밟는다 — 편을 안 보면 내 압정이 내 개체를 밟는다.
    func testOnlyTheSideTheHazardWasLaidOnStepsOnIt() {
        let field = laid(.spikes, layers: 3, on: .b)
        var entering = side([.normal], hp: 200)
        var rng = SplitMix64(seed: 1)
        XCTAssertEqual(switchIn(&entering, field: field, team: .a, rng: &rng), [])
    }

    // MARK: 빠뜨린 모드 찾기

    /// **출전 이벤트를 내는 모든 모드가 밟기를 불러야 한다.** 한 곳만 빠지면 그 모드에서만
    /// 압정이 아무 일도 하지 않고, 화면에는 정상으로 보인다(순풍·씨뿌리기와 같은 함정이다).
    func testEverySendOutSiteAppliesEntryHazards() throws {
        var sitesWithoutHazards: [String] = []
        // 주석은 `SourceScan` 이 떼고 온다 — 안 떼면 호출을 지워도 그 이름을 말하는 주석이 남아
        // 통과한다(`docs/reference/defect-log.md` "소스를 문자열로 스캔하는 가드" 절).
        for (name, code) in try SourceScan.sources() {
            guard code.contains("events.append(.sendOut(") || code.contains(".sendOut(.a, teamIndex:")
                    || code.contains(".sendOut(.b, teamIndex:") else { continue }
            if !code.contains("applyEntryHazards(") { sitesWithoutHazards.append(name) }
        }
        XCTAssertEqual(sitesWithoutHazards, [],
                       "출전을 내면서 밟기를 안 부르는 모드가 있으면 그 모드만 압정이 죽는다")
    }

    // MARK: 모드마다 실제로 밟는가

    /// 소스 스캔은 **호출이 있는지**만 본다 — 아래는 세 모드에서 압정이 실제로 HP 를 깎는지
    /// 본다. 둘이 다 필요하다: 스캔만 있으면 엉뚱한 편·엉뚱한 개체에 걸어도 통과하고,
    /// 동작 테스트만 있으면 나중에 늘어나는 출전 자리를 아무도 세지 않는다.

    private func monSnapshot(_ id: Int, hp: Int = 200) -> BattleSnapshot {
        BattleSnapshot(speciesID: id, name: "#\(id)", trainer: "T", level: 50, nature: nil,
                       isShiny: false, types: [.normal],
                       base: BattleStats(hp: hp, atk: 60, def: 200, spa: 60, spd: 200, spe: 100),
                       moves: [MoveSpec(id: 33, names: ["en": "Tackle"], type: .normal, power: 10,
                                        damageClass: .physical, accuracy: nil, pp: 20)])
    }

    /// 팀 연습 — 내가 교체하면 새로 나온 개체가 내 편에 깔린 압정을 밟는다.
    func testTeamPracticeSwitchInStepsOnSpikes() {
        var battle = TeamPracticeBattle(mine: [BattleSide(monSnapshot(1)), BattleSide(monSnapshot(2))],
                                        opponents: [BattleSide(monSnapshot(9))],
                                        rng: SplitMix64(seed: 3))
        XCTAssertTrue(battle.field.start(.spikes, for: .a))
        let full = battle.mine[1].stats.hp

        XCTAssertTrue(battle.switchMine(to: 1))

        XCTAssertLessThanOrEqual(battle.mine[1].hp, full - full / 8,
                                 "교체로 나온 개체가 압정을 안 밟았다")
    }

    /// 팀 연습 — CPU 의 자동 출전도 밟는다. 밟는 자리를 내 쪽에만 달면 여기가 빠진다.
    func testTeamPracticeAutomaticOpponentSendOutStepsOnSpikes() {
        var battle = TeamPracticeBattle(mine: [BattleSide(monSnapshot(1))],
                                        opponents: [BattleSide(monSnapshot(9)),
                                                    BattleSide(monSnapshot(10))],
                                        rng: SplitMix64(seed: 3))
        XCTAssertTrue(battle.field.start(.spikes, for: .b))
        let full = battle.opponents[1].stats.hp

        battle.retireOpponent()                       // 첫 상대가 빠지고 다음이 자동 출전한다

        XCTAssertEqual(battle.opponentActive, 1)
        XCTAssertLessThanOrEqual(battle.opponents[1].hp, full - full / 8,
                                 "자동 출전한 상대가 압정을 안 밟았다")
    }

    /// 웨이브 — 쓰러진 칸을 채우는 출전(턴을 쓰지 않는 경로)도 밟는다.
    func testWaveSendOutStepsOnSpikes() {
        var battle = WaveBattle(mine: [BattleSide(monSnapshot(1)), BattleSide(monSnapshot(2)),
                                       BattleSide(monSnapshot(3))],
                                opponents: [BattleSide(monSnapshot(9)), BattleSide(monSnapshot(10))],
                                rng: SplitMix64(seed: 3))
        XCTAssertTrue(battle.field.start(.spikes, for: .a))
        battle.mine[battle.myField[0].teamIndex].hp = 0
        let full = battle.mine[2].stats.hp

        XCTAssertTrue(battle.sendOut(teamIndex: 2, toSlot: 0))

        XCTAssertLessThanOrEqual(battle.mine[2].hp, full - full / 8,
                                 "빈 칸을 채운 개체가 압정을 안 밟았다")
    }

    /// 웨이브 — 턴을 쓰는 교체(`SlotAction.switchTo`)도 밟는다. 두 경로가 따로라 둘 다 잠근다.
    func testWaveTurnSwitchStepsOnSpikes() {
        var battle = WaveBattle(mine: [BattleSide(monSnapshot(1)), BattleSide(monSnapshot(2)),
                                       BattleSide(monSnapshot(3))],
                                opponents: [BattleSide(monSnapshot(9)), BattleSide(monSnapshot(10))],
                                rng: SplitMix64(seed: 3))
        XCTAssertTrue(battle.field.start(.spikes, for: .a))
        let full = battle.mine[2].stats.hp

        XCTAssertTrue(battle.choose(.switchTo(teamIndex: 2), forSlot: 0))
        XCTAssertTrue(battle.choose(.move(index: 0, target: 0), forSlot: 1))

        XCTAssertLessThanOrEqual(battle.mine[2].hp, full - full / 8,
                                 "턴을 쓴 교체가 압정을 안 밟았다")
    }

    /// 1v1 LAN — 교체 행동으로 나온 개체가 밟는다.
    func testNetBattleSwitchInStepsOnSpikes() {
        var state = NetBattleState(iAmA: true,
                                   myTeam: [BattleSide(monSnapshot(1)), BattleSide(monSnapshot(2))],
                                   oppTeam: [BattleSide(monSnapshot(9))],
                                   rng: SplitMix64(seed: 3))
        XCTAssertTrue(state.field.start(.spikes, for: .a))
        let full = state.myTeam[1].stats.hp

        state.myAction = .switchTo(index: 1)
        state.oppAction = .move(index: 0)
        _ = state.resolveChosenActions()

        XCTAssertEqual(state.myActive, 1)
        XCTAssertLessThanOrEqual(state.myTeam[1].hp, full - full / 8,
                                 "교체로 나온 개체가 압정을 안 밟았다")
    }

    /// 1v1 LAN — 사용자가 직접 고르는 기절 보충(`replaceFainted`)도 밟는다.
    func testNetBattleReplaceFaintedStepsOnSpikes() {
        var fainted = BattleSide(monSnapshot(1))
        fainted.hp = 0
        var state = NetBattleState(iAmA: true, myTeam: [fainted, BattleSide(monSnapshot(2))],
                                   oppTeam: [BattleSide(monSnapshot(9))],
                                   rng: SplitMix64(seed: 3))
        state.automaticallyReplacesFainted = false
        XCTAssertTrue(state.field.start(.spikes, for: .a))
        let full = state.myTeam[1].stats.hp

        XCTAssertTrue(state.replaceFainted(to: 1, mine: true))

        XCTAssertLessThanOrEqual(state.myTeam[1].hp, full - full / 8,
                                 "기절 보충으로 나온 개체가 압정을 안 밟았다")
    }

    /// 1v1 LAN — **밟아서 파티가 전멸하는 턴**이 승부로 접힌다. 전멸 판정을 밟기 전 값으로 하면
    /// 활성 칸이 죽은 개체인 채 다음 턴을 기다려 배틀이 멈춘다.
    func testAHazardWipeEndsTheNetBattleInsteadOfStalling() {
        var lead = BattleSide(monSnapshot(1))
        lead.hp = 1
        var last = BattleSide(monSnapshot(2))
        last.hp = 1
        var state = NetBattleState(iAmA: true, myTeam: [lead, last],
                                   oppTeam: [BattleSide(monSnapshot(9))],
                                   rng: SplitMix64(seed: 3))
        for _ in 0..<3 { XCTAssertTrue(state.field.start(.spikes, for: .a)) }

        state.myAction = .move(index: 0)
        state.oppAction = .move(index: 0)
        let outcome = state.resolveChosenActions()

        XCTAssertFalse(state.myTeam.contains(where: \.isAlive), "압정이 마지막 한 마리를 데려갔다")
        XCTAssertEqual(outcome, .loss, "전멸한 턴인데 승부가 안 적혔다")
    }

    /// 대조군 — 위 스캔이 실제로 파일을 찾고 있는지 본다(0 개 대 0 개 비교로 통과하는 것을 막는다).
    func testTheSendOutScanActuallyFindsTheModes() throws {
        let found = try SourceScan.sources().filter {
            $0.code.contains("events.append(.sendOut(") || $0.code.contains(".sendOut(.a, teamIndex:")
                || $0.code.contains(".sendOut(.b, teamIndex:")
        }.map(\.name)
        XCTAssertTrue(found.contains("BattleNet.swift"))
        XCTAssertTrue(found.contains("TeamPracticeBattle.swift"))
        XCTAssertTrue(found.contains("WaveBattle.swift"))
    }
}
