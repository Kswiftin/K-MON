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
    static func from(_ move: MoveSpec, attacker: BattleSide, defender: BattleSide,
                     rng: inout SplitMix64) -> VariableDamage? {
        switch move.id {
        case MoveID.electroBall:  return .power(electroBallPower(attacker: attacker, defender: defender))
        case MoveID.gyroBall:     return .power(gyroBallPower(attacker: attacker, defender: defender))
        case MoveID.flail, MoveID.reversal:
            return .power(lowHealthPower(attacker))
        case MoveID.wringOut, MoveID.crushGrip:
            return .power(targetHealthPower(defender))
        case MoveID.punishment:   return .power(punishmentPower(defender))
        case MoveID.lowKick, MoveID.grassKnot:
            // 체중을 못 받아왔으면 **실패시킨다.** 0 으로 접으면 "가장 가벼움"이 되어 모든 상대에게
            // 최저 위력이 나가고, 그게 맞는 값인지 화면에서 구별할 수 없다.
            guard let weight = effectiveWeight(defender) else { return .noEffect }
            return .power(targetWeightPower(weight))
        case MoveID.heavySlam, MoveID.heatCrash:
            guard let mine = effectiveWeight(attacker),
                  let theirs = effectiveWeight(defender), theirs > 0 else { return .noEffect }
            return .power(weightRatioPower(attacker: mine, defender: theirs))
        case MoveID.trumpCard:    return .power(trumpCardPower(attacker, move: move))
        case MoveID.magnitude:    return .power(magnitudePower(rng: &rng))

        // 되돌려주는 기술 — 이번 턴에 맞은 것이 없으면 실패한다. 카운터·미러코트는 우선도 −5 라
        // 늘 후공이므로 "맞고 나서 되받는" 순서가 저절로 맞는다. 메탈버스트는 우선도 0 이라
        // 먼저 움직이면 맞은 게 없어 실패한다 — 본가와 같다.
        case MoveID.counter:
            return counterDamage(attacker, matching: .physical, multipliedBy: 2)
        case MoveID.mirrorCoat:
            return counterDamage(attacker, matching: .special, multipliedBy: 2)
        case MoveID.metalBurst:
            // 분류를 가리지 않는다. 배율만 1.5 배로 낮다.
            guard let hit = attacker.lastHitThisTurn else { return .noEffect }
            return .fixedHP(max(1, hit.amount * 3 / 2))

        case MoveID.sonicBoom:    return .fixedHP(20)
        case MoveID.dragonRage:   return .fixedHP(40)
        case MoveID.seismicToss, MoveID.nightShade:
            return .fixedHP(attacker.snapshot.level)
        case MoveID.psywave:      return .fixedHP(psywaveDamage(attacker, rng: &rng))
        case MoveID.superFang:    return .fixedHP(max(1, defender.hp / 2))
        // 상대를 내 HP 까지 끌어내린다 — 내가 더 건강하면 아무 일도 없다(0 은 `.damage` 를 안 낸다).
        case MoveID.endeavor:     return .fixedHP(max(0, defender.hp - attacker.hp))
        case MoveID.finalGambit:  return .fixedHP(attacker.hp)

        case MoveID.guillotine, MoveID.hornDrill, MoveID.fissure, MoveID.sheerCold:
            // 레벨이 높은 상대에게는 통하지 않는다.
            return defender.snapshot.level > attacker.snapshot.level ? .noEffect : .oneHitKO

        default: return nil
        }
    }

    private static func effectiveWeight(_ side: BattleSide) -> Int? {
        guard let weight = side.snapshot.weightHectograms else { return nil }
        switch side.ability?.rawValue {
        case "heavy-metal": return weight * 2
        case "light-metal": return max(1, weight / 2)
        default: return weight
        }
    }

    /// 쓰고 나면 자기가 쓰러지는 기술. `applyAttack` 이 데미지를 넣은 **뒤에** 본다.
    static func userFaints(after move: MoveSpec) -> Bool { move.id == MoveID.finalGambit }

    // MARK: 위력 계산

    /// 일렉트릭볼 — 상대보다 빠를수록 세다. 마비의 스피드 감소가 그대로 반영되도록
    /// `effectiveSpeed` 를 쓴다(랭크만 보는 `stats.spe` 로는 마비가 위력에 안 잡힌다).
    /// 나눗셈 대신 곱으로 비교한다 — 정수 나눗셈은 경계에서 값이 한 칸씩 밀린다.
    static func electroBallPower(attacker: BattleSide, defender: BattleSide) -> Int {
        let mine = attacker.effectiveSpeed, theirs = defender.effectiveSpeed
        if mine <= theirs { return 40 }
        if mine <= theirs * 2 { return 60 }
        if mine <= theirs * 3 { return 80 }
        if mine <= theirs * 4 { return 120 }
        return 150
    }

    /// 자이로볼 — 일렉트릭볼의 반대로, 느릴수록 세다.
    static func gyroBallPower(attacker: BattleSide, defender: BattleSide) -> Int {
        let power = 25 * defender.effectiveSpeed / max(1, attacker.effectiveSpeed) + 1
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

    /// 목조르기·크러시그립 — 상대 HP 가 많을수록 세다.
    static func targetHealthPower(_ defender: BattleSide) -> Int {
        max(1, 120 * defender.hp / max(1, defender.stats.hp))
    }

    /// 응징 — 상대가 **올린** 랭크만 센다. 내린 랭크까지 세면 상대를 깎아 놓고 응징이 약해진다.
    static func punishmentPower(_ defender: BattleSide) -> Int {
        let raised = BattleStat.allCases.reduce(0) { $0 + max(0, defender.stage($1)) }
        return min(200, 60 + 20 * raised)
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
        static let flail = 175
        static let reversal = 179
        static let magnitude = 222
        static let mirrorCoat = 243
        static let endeavor = 283
        static let sheerCold = 329
        static let gyroBall = 360
        static let metalBurst = 368
        static let trumpCard = 376
        static let wringOut = 378
        static let punishment = 386
        static let grassKnot = 447
        static let crushGrip = 462
        static let heavySlam = 484
        static let electroBall = 486
        static let finalGambit = 515
        static let heatCrash = 535
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
