import Foundation

/// PokéAPI 가 `power: null` 로 주는 공격기의 데미지.
///
/// **왜 있어야 하는가.** `MoveSpec.from` 은 `dto.power ?? 0` 으로 null 을 0 에 접고, 엔진은
/// `power <= 0` 을 변화기로 보아 데미지를 0 으로 확정한다. 그래서 일렉트릭볼·지구던지기·자이로볼
/// 같은 공격기가 **PP 만 태우고 로그 한 줄만 남기는** 죽은 기술이 됐다(1~5세대에 37개, 그중 36개가
/// 레벨업으로 배운다). 사용자가 직접 배우는 경로(레벨업 습득창·하트비늘·`canonicalLevelUpMoves`)
/// 는 필터가 없어 죽은 기술을 그대로 실었고, 자동 무브셋은 반대로 `power > 0` 으로 걸러
/// **살아난 뒤에도 한 번도 안 뽑았다.** 두 경로가 이제 `dealsDamage` 하나를 본다.
///
/// **결정성.** 여기서 쓰는 rng 는 두 피어가 **같은 횟수·같은 순서**로 소비해야 한다. 소비는
/// `resolveAttack` 의 명중 판정 **직후** 한 자리에서만 일어나고(명중 → 가변위력 → 급소 → 난수 폭),
/// 위력이 난수를 안 쓰는 기술은 한 번도 뽑지 않는다. 이 순서가 바뀌면 `rulesVersion` 을 올려야 한다.
enum VariableDamage: Equatable, Sendable {
    /// 위력만 상황에서 정해지고 나머지는 보통 공격기와 같다 — 상성·STAB·급소·난수를 전부 탄다.
    case power(Int)
    /// 공식을 건너뛰고 HP 를 이만큼 깎는다. 상성은 **면역만** 본다(나이트헤드는 노말에게 통하지
    /// 않지만, 통할 때는 2배도 절반도 되지 않는다).
    case fixedHP(Int)
    /// 맞으면 그대로 쓰러진다. 명중은 기술에 적힌 값(30)을 그대로 쓴다.
    case oneHitKO
    /// 조건이 안 맞아 통하지 않았다(레벨이 높은 상대에게 쓴 일격필살).
    ///
    /// 데미지 0 으로 접으면 안 된다 — `applyAttack` 은 데미지가 0 이면 아무 이벤트도 내지 않아서,
    /// 로그에 기술명 한 줄만 남는 그 무반응이 그대로 재현된다. 이 기술들이 죽어 있던 이유와 같다.
    case noEffect

    /// 이 기술이 위력을 상황에서 뽑는 부류면 그 결과, 아니면 `nil`(보통 기술이라는 뜻).
    ///
    /// 이름을 `MoveSpec.from(_ dto:)` 과 맞춘다 — 둘 다 "바깥 값 하나를 이 타입으로 옮긴다" 이다.
    /// - Parameter hit: 몇 번째 히트인가(0 부터). 다단기는 히트마다 이 함수를 지나므로, 히트별로
    ///   위력이 오르는 기술(트리플킥·트리플악셀)은 이 값만 보면 된다. 단발기는 늘 0 이다.
    static func from(_ move: MoveSpec, attacker: BattleSide, defender: BattleSide,
                     hit: Int = 0, field: BattleField = BattleField(),
                     attackerTeam: BattleTeamSlot = .a, defenderTeam: BattleTeamSlot = .b,
                     rng: inout SplitMix64) -> VariableDamage? {
        switch move.id {
        case MoveID.electroBall:
            return .power(electroBallPower(attacker: attacker, defender: defender, field: field,
                                           attackerTeam: attackerTeam, defenderTeam: defenderTeam))
        case MoveID.gyroBall:
            return .power(gyroBallPower(attacker: attacker, defender: defender, field: field,
                                        attackerTeam: attackerTeam, defenderTeam: defenderTeam))
        case MoveID.flail, MoveID.reversal:
            return .power(lowHealthPower(attacker))
        case MoveID.wringOut, MoveID.crushGrip:
            return .power(targetHealthPower(defender))
        case MoveID.punishment:   return .power(punishmentPower(defender))
        // 하드프레스는 크러시그립과 같은 식이고 상한만 100 이다. PokéAPI 는 위력을 **0** 으로 주는데
        // (`null` 이 아니다) 그대로 두면 데미지가 0 으로 접혀 기술명만 찍히고 아무 일도 안 일어난다.
        case MoveID.hardPress:    return .power(targetHealthPower(defender, max: 100))
        case MoveID.lowKick, MoveID.grassKnot:
            // 체중을 못 받아왔으면 **실패시킨다.** 0 으로 접으면 "가장 가벼움"이 되어 모든 상대에게
            // 최저 위력이 나가고, 그게 맞는 값인지 화면에서 구별할 수 없다.
            guard let weight = defender.effectiveWeightHectograms else { return .noEffect }
            return .power(targetWeightPower(weight))
        case MoveID.heavySlam, MoveID.heatCrash:
            guard let mine = attacker.effectiveWeightHectograms,
                  let theirs = defender.effectiveWeightHectograms, theirs > 0 else { return .noEffect }
            return .power(weightRatioPower(attacker: mine, defender: theirs))
        case MoveID.trumpCard:    return .power(trumpCardPower(attacker, move: move))
        // 아래 부류는 PokéAPI 가 위력을 제대로 주는 기술이다 — 죽어 있지는 않았고, 상황 배율만
        // 빠져 있었다. 그래서 기본 위력은 여기서 다시 적지 않고 `basePower` 로 데이터에서 읽는다.
        case MoveID.eruption, MoveID.waterSpout, MoveID.dragonEnergy:
            return .power(healthProportionalPower(attacker, base: basePower(move, fallback: 150)))
        case MoveID.storedPower, MoveID.powerTrip:
            return .power(raisedStagePower(attacker, base: basePower(move, fallback: 20)))
        case MoveID.hex:
            return .power(statusPunishingPower(defender, base: basePower(move, fallback: 65)))
        case MoveID.infernalParade:
            return .power(statusPunishingPower(defender, base: basePower(move, fallback: 60)))
        case MoveID.avalanche:
            // 이번 턴에 맞았으면 두 배. 우선도 −4 라 대개 후공이므로 조건이 실제로 자주 선다.
            let base = basePower(move, fallback: 60)
            return .power(attacker.lastHitThisTurn == nil ? base : base * 2)
        // 히트마다 위력이 오르는 다단기 — `resolveAttack` 이 히트 번호를 넘겨 준다.
        // 본가는 히트마다 명중을 따로 굴리지만 엔진은 기술 단위로 한 번 굴린다(다단기 공통 규칙).
        case MoveID.risingVoltage:
            // 일렉트릭필드 위의 **상대**에게 두 배. 뜬 상대는 필드를 안 받으므로 그대로다.
            let base = basePower(move, fallback: 70)
            let charged = field.terrain == .electric && BattleField.isGrounded(defender)
            return .power(charged ? base * 2 : base)
        case MoveID.tripleKick:
            return .power(basePower(move, fallback: 10) * (hit + 1))
        case MoveID.tripleAxel:
            return .power(basePower(move, fallback: 20) * (hit + 1))
        case MoveID.furyCutter:
            return .power(doublingStreakPower(attacker, base: basePower(move, fallback: 40), cap: 160))
        case MoveID.rollout:
            // 본가는 5턴간 사용자를 이 기술에 **묶는데** 기술 강제 상태가 엔진에 없다(`unmodeledMoveIDs`
            // 의 참기와 같은 이유). 그래서 연이어 고르는 동안만 세진다 — 상한은 본가와 같다.
            return .power(doublingStreakPower(attacker, base: basePower(move, fallback: 30), cap: 480))
        case MoveID.echoedVoice:
            // 본가는 **누가 썼든** 그 턴에 나온 횟수를 세는 필드값이다. 필드 레이어가 없으므로
            // 쓰는 쪽의 연속 횟수로 센다 — 1대1 에서 갈리는 건 상대도 같이 쓸 때뿐이다.
            return .power(min(200, basePower(move, fallback: 40) * max(1, attacker.consecutiveMoveUses)))
        case MoveID.rageFist:
            return .power(min(350, basePower(move, fallback: 50) * (1 + attacker.timesHit)))
        case MoveID.payback:
            // 상대가 이번 턴 행동을 이미 썼으면 두 배. 본가는 교체한 상대에게도 두 배지만, 교체를
            // 하는 모드(체육관·웨이브)에서도 교체는 `beginAttack` 을 지나지 않아 여기서 안 보인다.
            let base = basePower(move, fallback: 50)
            return .power(defender.movedThisTurn ? base * 2 : base)
        case MoveID.stompingTantrum, MoveID.temperFlare:
            let base = basePower(move, fallback: 75)
            return .power(attacker.lastMoveFailed ? base * 2 : base)
        case MoveID.acrobatics:
            // 본가는 "지닌물건이 없으면" 두 배인데, 대전에 지닌물건 축이 아직 없어(이슈 #24 의
            // Phase 5) 조건이 늘 참이다. 지닌물건이 생기면 여기에 분기를 세운다.
            return .power(basePower(move, fallback: 55) * 2)
        case MoveID.magnitude:    return .power(magnitudePower(rng: &rng))

        // 되돌려주는 기술 — 이번 턴에 맞은 것이 없으면 실패한다. 카운터·미러코트는 우선도 −5 라
        // 늘 후공이므로 "맞고 나서 되받는" 순서가 저절로 맞는다. 메탈버스트는 우선도 0 이라
        // 먼저 움직이면 맞은 게 없어 실패한다 — 본가와 같다.
        case MoveID.counter:
            return counterDamage(attacker, matching: .physical, multipliedBy: 2)
        case MoveID.mirrorCoat:
            return counterDamage(attacker, matching: .special, multipliedBy: 2)
        case MoveID.metalBurst, MoveID.comeuppance:
            // 분류를 가리지 않는다. 배율만 1.5 배로 낮다. 인과응보는 9세대판 메탈버스트라 규칙이 같다.
            guard let hit = attacker.lastHitThisTurn else { return .noEffect }
            return .fixedHP(max(1, hit.amount * 3 / 2))

        case MoveID.sonicBoom:    return .fixedHP(20)
        case MoveID.dragonRage:   return .fixedHP(40)
        case MoveID.seismicToss, MoveID.nightShade:
            return .fixedHP(attacker.snapshot.level)
        case MoveID.psywave:      return .fixedHP(psywaveDamage(attacker, rng: &rng))
        // 황폐가는 상대 **현재** HP 의 절반이다(깨물어부수기와 같은 식). PokéAPI 가 주는 위력 1 을
        // 그대로 쓰면 레벨과 무관하게 한 자릿수 데미지가 나온다.
        case MoveID.superFang, MoveID.ruination:
            return .fixedHP(max(1, defender.hp / 2))
        // 상대를 내 HP 까지 끌어내린다 — 내가 더 건강하면 아무 일도 없다(0 은 `.damage` 를 안 낸다).
        case MoveID.endeavor:     return .fixedHP(max(0, defender.hp - attacker.hp))
        case MoveID.finalGambit:  return .fixedHP(attacker.hp)

        case MoveID.guillotine, MoveID.hornDrill, MoveID.fissure, MoveID.sheerCold:
            // 레벨이 높은 상대에게는 통하지 않는다.
            return defender.snapshot.level > attacker.snapshot.level ? .noEffect : .oneHitKO

        default: return nil
        }
    }

    /// 쓰고 나면 자기가 쓰러지는 기술. `applyAttack` 이 데미지를 넣은 **뒤에** 본다.
    static func userFaints(after move: MoveSpec) -> Bool { move.id == MoveID.finalGambit }

    // MARK: 위력 계산

    /// 일렉트릭볼 — 상대보다 빠를수록 세다. 마비·랭크·순풍이 그대로 반영되도록 순서 계산과
    /// **같은 값**(`BattleEngine.orderingSpeed`)을 쓴다. `stats.spe` 로는 마비가 위력에 안 잡히고,
    /// `effectiveSpeed` 만 보면 순풍이 순서만 바꾸고 위력은 예전 값으로 남는다.
    /// 나눗셈 대신 곱으로 비교한다 — 정수 나눗셈은 경계에서 값이 한 칸씩 밀린다.
    static func electroBallPower(attacker: BattleSide, defender: BattleSide,
                                 field: BattleField = BattleField(),
                                 attackerTeam: BattleTeamSlot = .a,
                                 defenderTeam: BattleTeamSlot = .b) -> Int {
        let mine = BattleEngine.orderingSpeed(attacker, team: attackerTeam, field: field)
        let theirs = BattleEngine.orderingSpeed(defender, team: defenderTeam, field: field)
        if mine <= theirs { return 40 }
        if mine <= theirs * 2 { return 60 }
        if mine <= theirs * 3 { return 80 }
        if mine <= theirs * 4 { return 120 }
        return 150
    }

    /// 자이로볼 — 일렉트릭볼의 반대로, 느릴수록 세다.
    static func gyroBallPower(attacker: BattleSide, defender: BattleSide,
                              field: BattleField = BattleField(),
                              attackerTeam: BattleTeamSlot = .a,
                              defenderTeam: BattleTeamSlot = .b) -> Int {
        let mine = BattleEngine.orderingSpeed(attacker, team: attackerTeam, field: field)
        let theirs = BattleEngine.orderingSpeed(defender, team: defenderTeam, field: field)
        let power = 25 * theirs / max(1, mine) + 1
        return min(150, max(1, power))
    }

    /// 기사회생·역전 — 내 HP 가 적을수록 세다.
    static func lowHealthPower(_ side: BattleSide) -> Int {
        let scaled = 48 * side.hp / max(1, side.stats.hp)
        switch scaled {
        case ...1:  return 200
        case ...4:  return 150
        case ...9:  return 100
        case ...16: return 80
        case ...32: return 40
        default:    return 20
        }
    }

    /// 목조르기·크러시그립·하드프레스 — 상대 HP 가 많을수록 세다. 상한만 기술마다 다르다
    /// (크러시그립 계열 120, 하드프레스 100).
    static func targetHealthPower(_ defender: BattleSide, max ceiling: Int = 120) -> Int {
        Swift.max(1, ceiling * defender.hp / Swift.max(1, defender.stats.hp))
    }

    /// 응징 — 상대가 **올린** 랭크만 센다. 내린 랭크까지 세면 상대를 깎아 놓고 응징이 약해진다.
    static func punishmentPower(_ defender: BattleSide) -> Int {
        min(200, raisedStagePower(defender, base: 60))
    }

    /// 기본 위력 — PokéAPI 값을 쓰되 **0 이면 쇼다운 기준값으로 되돌린다.**
    ///
    /// 0 은 값이 아니라 "없음"일 수 있다(하드프레스가 실제로 0 으로 왔다). 상황 배율을 곱하는
    /// 부류에서 0 을 그대로 쓰면 무엇을 곱해도 0 이라 기술이 통째로 죽는다.
    static func basePower(_ move: MoveSpec, fallback: Int) -> Int {
        move.power > 0 ? move.power : fallback
    }

    /// 분화·물대포·드래곤에너지 — **내** 남은 HP 비율만큼 위력이 준다.
    static func healthProportionalPower(_ side: BattleSide, base: Int) -> Int {
        max(1, base * side.hp / max(1, side.stats.hp))
    }

    /// 어시스트파워·긍지의칼날·응징 — **올린** 랭크 하나당 20 씩 더한다. 어느 쪽 랭크를 세는지는
    /// 부르는 자리가 정한다(어시스트파워는 자기, 응징은 상대).
    static func raisedStagePower(_ side: BattleSide, base: Int) -> Int {
        base + 20 * BattleStat.allCases.reduce(0) { $0 + max(0, side.stage($1)) }
    }

    /// 리프블레이드·구르기 — 연이어 쓴 횟수만큼 두 배씩. 상한이 없으면 여섯 턴 만에 위력이
    /// 네 자리가 된다. `consecutiveMoveUses` 는 이 기술을 쓰는 턴에 이미 올라 있으므로 1 회차가
    /// 기본 위력이다.
    static func doublingStreakPower(_ side: BattleSide, base: Int, cap: Int) -> Int {
        let steps = Swift.max(0, side.consecutiveMoveUses - 1)
        // 지수는 상한에 닿는 지점에서 자른다 — 32 턴을 넘기면 시프트가 오버플로한다.
        var power = base
        for _ in 0..<steps {
            power *= 2
            if power >= cap { return cap }
        }
        return Swift.min(cap, power)
    }

    /// 악몽·저승의불꽃 — 상대가 **주** 상태이상일 때만 두 배다. 혼란은 volatile 이라 세지 않는다.
    static func statusPunishingPower(_ defender: BattleSide, base: Int) -> Int {
        defender.status == nil ? base : base * 2
    }

    /// 되돌려주기 — 이번 턴에 **그 분류로** 맞은 데미지의 배수를 그대로 돌려준다.
    /// 분류가 다르면(카운터로 특수기를 받으면) 실패한다.
    static func counterDamage(_ attacker: BattleSide, matching damageClass: MoveDamageClass,
                              multipliedBy multiplier: Int) -> VariableDamage {
        guard let hit = attacker.lastHitThisTurn, hit.damageClass == damageClass else { return .noEffect }
        return .fixedHP(max(1, hit.amount * multiplier))
    }

    /// 저공격·풀묶기 — **상대가** 무거울수록 세다. 구간은 본가의 kg 경계(10·25·50·100·200)를
    /// 헥토그램 그대로 쓴다 — kg 으로 바꾸면 소수점이 생겨 경계에서 한 칸씩 밀린다.
    static func targetWeightPower(_ weightHectograms: Int) -> Int {
        switch weightHectograms {
        case ..<100:  return 20
        case ..<250:  return 40
        case ..<500:  return 60
        case ..<1000: return 80
        case ..<2000: return 100
        default:      return 120
        }
    }

    /// 헤비봄버·히트스탬프 — **내가 상대보다** 무거울수록 세다. 비율 비교라 나눗셈 대신 곱을 쓴다.
    static func weightRatioPower(attacker: Int, defender: Int) -> Int {
        if attacker < defender * 2 { return 40 }
        if attacker < defender * 3 { return 60 }
        if attacker < defender * 4 { return 80 }
        if attacker < defender * 5 { return 100 }
        return 120
    }

    /// 필살기 — 남은 PP 가 적을수록 세다. PP 는 호출부가 이미 깎은 뒤라 지금 값이 곧 "쓰고 남은 수"다.
    /// 슬롯을 id 로 되짚는다 — `applyAttack` 은 몇 번째 칸인지 모르고 기술만 받는다.
    static func trumpCardPower(_ attacker: BattleSide, move: MoveSpec) -> Int {
        let slot = attacker.moves.firstIndex { $0.id == move.id }
        let remaining = slot.flatMap { $0 < attacker.pp.count ? attacker.pp[$0] : nil } ?? 0
        switch remaining {
        case 0:  return 200
        case 1:  return 80
        case 2:  return 60
        case 3:  return 50
        default: return 40
        }
    }

    /// 매그니튜드 — 규모가 무작위다. 확률표(5·10·20·30·20·10·5%)를 누적 경계로 편다.
    static func magnitudePower(rng: inout SplitMix64) -> Int {
        switch Int(rng.next() % 100) {
        case ..<5:   return 10
        case ..<15:  return 30
        case ..<35:  return 50
        case ..<65:  return 70
        case ..<85:  return 90
        case ..<95:  return 110
        default:     return 150
        }
    }

    /// 사이코웨이브 — 레벨의 50~150%.
    static func psywaveDamage(_ attacker: BattleSide, rng: inout SplitMix64) -> Int {
        max(1, attacker.snapshot.level * (Int(rng.next() % 101) + 50) / 100)
    }

    // MARK: 기술 id

    /// 위력을 상황에서 뽑는 기술의 PokéAPI id. 숫자를 분기에 흩어 두면 어느 기술인지 읽을 수 없다.
    enum MoveID {
        static let guillotine = 12
        static let hornDrill = 32
        static let sonicBoom = 49
        static let lowKick = 67
        static let counter = 68
        static let seismicToss = 69
        static let dragonRage = 82
        static let fissure = 90
        static let nightShade = 101
        static let psywave = 149
        static let superFang = 162
        static let tripleKick = 167
        static let flail = 175
        static let reversal = 179
        static let rollout = 205
        static let furyCutter = 210
        static let magnitude = 222
        static let mirrorCoat = 243
        static let endeavor = 283
        static let eruption = 284
        static let waterSpout = 323
        static let sheerCold = 329
        static let gyroBall = 360
        static let metalBurst = 368
        static let trumpCard = 376
        static let wringOut = 378
        static let punishment = 386
        static let avalanche = 419
        static let grassKnot = 447
        static let crushGrip = 462
        static let heavySlam = 484
        static let electroBall = 486
        static let echoedVoice = 497
        static let storedPower = 500
        static let hex = 506
        static let acrobatics = 512
        static let finalGambit = 515
        static let payback = 371
        static let heatCrash = 535
        static let powerTrip = 681
        static let stompingTantrum = 707
        static let risingVoltage = 804
        static let tripleAxel = 813
        static let dragonEnergy = 820
        static let infernalParade = 844
        static let ruination = 877
        static let rageFist = 889
        static let comeuppance = 894
        static let hardPress = 912
        static let temperFlare = 915
    }

    /// 아직 모델링하지 않은 가변 위력 기술 — **무브셋 후보에서 뺀다.**
    ///
    /// 위력 0 인 채로 두면 예전과 똑같이 PP 만 태우는 죽은 기술이 된다. 고칠 수 없으면 권하지도
    /// 않는 쪽이 낫다. 각 기술에 필요한 것이 엔진에 생기면 여기서 빼고 `from` 에 넣는다.
    ///
    /// - 친밀도(은혜갚기·화풀이): 개체별 친밀도 축이 앱에 없다(`CompanionModel` 주석 참고).
    /// - 지닌물건(던지기·자연의은혜): 대전에 지닌물건이 없다(이슈 #24 의 Phase 5).
    /// - 참기: 3턴간 사용자를 그 기술에 **묶어야** 하는데, 기술을 강제하는 상태가 엔진에 없다.
    ///   만들면 화면(매 턴 기술 선택)과 네트워크가 다 따라와야 한다.
    /// - 토해내기: 비축하기 카운터가 없다(회복 이벤트는 Phase 5 에서 생겼으니 남은 건 카운터뿐).
    /// - 동료(집단구타): 대전이 파티를 안 본다 — 1대1 에는 파티 자체가 없다(스냅샷 하나).
    ///   다단 히트는 Phase 5 에서 생겼으니 남은 건 파티뿐이다.
    /// - 선물: 위력이 확률로 갈리는데(40/80/120/회복) 그 분포가 엔진에 없다.
    ///   회복 자체는 Phase 5 의 `BattleEvent.heal` 로 표현할 수 있다.
    /// - 섀도하프: 본편 밖 기술이다.
    static let unmodeledMoveIDs: Set<Int> = [
        216, 218,               // 은혜갚기 · 화풀이 (친밀도)
        374, 363,               // 던지기 · 자연의은혜 (지닌물건)
        117,                    // 참기 (기술 강제 상태)
        255,                    // 토해내기 (비축하기 카운터 + 회복 이벤트)
        251,                    // 집단구타 (파티 + 다단 히트)
        217,                    // 선물 (회복 분기)
        10013,                  // 섀도하프 (본편 밖)
    ]

    /// 무브셋에 올려도 되는 기술인가 — 위력이 0 인데 효과도 없는 기술을 걸러낸다.
    /// `PokeAPIClient.pickStatusMove` 와 **같은 기준**을 쓰되, 여기는 사용자가 직접 고르는
    /// 경로(레벨업 습득창·하트비늘)를 위한 것이다.
    static func isUsable(_ move: MoveSpec) -> Bool {
        !unmodeledMoveIDs.contains(move.id)
            && (move.damageClass != .status || move.hasModeledStatusEffect)
    }

    /// 엔진이 실제로 데미지를 내는 기술인가 — **무브셋 선택은 `power > 0` 대신 이걸 본다.**
    ///
    /// `power > 0` 은 "공격기냐"와 같은 뜻이 아니다. PokéAPI 가 `power: null` 로 주는 공격기는
    /// `MoveSpec.power` 가 0 이고 위력은 `from` 이 뽑아 준다. 위력으로 가르면 그 부류가 공격기
    /// 칸에도(위력 0) 변화기 칸에도(`hasModeledStatusEffect` 가 false) 못 들어가 **자동 무브셋에서
    /// 영원히 안 뽑혔다.** `isUsable` 을 보는 사용자 습득 경로(`canonicalLevelUpMoves`·하트비늘)는
    /// 같은 기술을 통과시켰으니, "같은 기준"이라던 두 게이트가 갈라져 있던 셈이다.
    /// `isUsable` 을 그대로 재사용해 갈라질 자리를 없앤다.
    static func dealsDamage(_ move: MoveSpec) -> Bool {
        move.damageClass != .status && isUsable(move)
    }
}
