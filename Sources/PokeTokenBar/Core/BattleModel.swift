import Foundation

// MARK: - 타입

/// 본가 18타입 — rawValue 는 PokéAPI type name 과 동일(직렬화·차트 키 겸용).
enum PokemonType: String, Codable, Sendable, CaseIterable {
    case normal, fire, water, electric, grass, ice
    case fighting, poison, ground, flying, psychic, bug
    case rock, ghost, dragon, dark, steel, fairy

    /// 본가 공식 번역 명칭 (ko/en/ja).
    var name: String {
        switch self {
        case .normal:    "노말"
        case .fire:      "불꽃"
        case .water:     "물"
        case .electric:  "전기"
        case .grass:     "풀"
        case .ice:       "얼음"
        case .fighting:  "격투"
        case .poison:    "독"
        case .ground:    "땅"
        case .flying:    "비행"
        case .psychic:   "에스퍼"
        case .bug:       "벌레"
        case .rock:      "바위"
        case .ghost:     "고스트"
        case .dragon:    "드래곤"
        case .dark:      "악"
        case .steel:     "강철"
        case .fairy:     "페어리"
        }
    }
}

/// 타입 상성표 (Gen 6+) — 1.0 이 아닌 칸만 기록. 조회는 `TypeChart.effectiveness`.
enum TypeChart {
    /// [공격타입: [방어타입: 배율]]
    static let multipliers: [PokemonType: [PokemonType: Double]] = [
        .normal:   [.rock: 0.5, .ghost: 0, .steel: 0.5],
        .fire:     [.fire: 0.5, .water: 0.5, .grass: 2, .ice: 2, .bug: 2, .rock: 0.5, .dragon: 0.5, .steel: 2],
        .water:    [.fire: 2, .water: 0.5, .grass: 0.5, .ground: 2, .rock: 2, .dragon: 0.5],
        .electric: [.water: 2, .electric: 0.5, .grass: 0.5, .ground: 0, .flying: 2, .dragon: 0.5],
        .grass:    [.fire: 0.5, .water: 2, .grass: 0.5, .poison: 0.5, .ground: 2, .flying: 0.5,
                    .bug: 0.5, .rock: 2, .dragon: 0.5, .steel: 0.5],
        .ice:      [.fire: 0.5, .water: 0.5, .grass: 2, .ice: 0.5, .ground: 2, .flying: 2,
                    .dragon: 2, .steel: 0.5],
        .fighting: [.normal: 2, .ice: 2, .poison: 0.5, .flying: 0.5, .psychic: 0.5, .bug: 0.5,
                    .rock: 2, .ghost: 0, .dark: 2, .steel: 2, .fairy: 0.5],
        .poison:   [.grass: 2, .poison: 0.5, .ground: 0.5, .rock: 0.5, .ghost: 0.5, .steel: 0, .fairy: 2],
        .ground:   [.fire: 2, .electric: 2, .grass: 0.5, .poison: 2, .flying: 0, .bug: 0.5,
                    .rock: 2, .steel: 2],
        .flying:   [.electric: 0.5, .grass: 2, .fighting: 2, .bug: 2, .rock: 0.5, .steel: 0.5],
        .psychic:  [.fighting: 2, .poison: 2, .psychic: 0.5, .dark: 0, .steel: 0.5],
        .bug:      [.fire: 0.5, .grass: 2, .fighting: 0.5, .poison: 0.5, .flying: 0.5, .psychic: 2,
                    .ghost: 0.5, .dark: 2, .steel: 0.5, .fairy: 0.5],
        .rock:     [.fire: 2, .ice: 2, .fighting: 0.5, .ground: 0.5, .flying: 2, .bug: 2, .steel: 0.5],
        .ghost:    [.normal: 0, .psychic: 2, .ghost: 2, .dark: 0.5],
        .dragon:   [.dragon: 2, .steel: 0.5, .fairy: 0],
        .dark:     [.fighting: 0.5, .psychic: 2, .ghost: 2, .dark: 0.5, .fairy: 0.5],
        .steel:    [.fire: 0.5, .water: 0.5, .electric: 0.5, .ice: 2, .rock: 2, .steel: 0.5, .fairy: 2],
        .fairy:    [.fire: 0.5, .fighting: 2, .poison: 0.5, .dragon: 2, .dark: 2, .steel: 0.5],
    ]

    /// 공격타입 → 방어타입 조합(단일/복합) 배율. 복합타입은 곱. **표시용**이다 —
    /// "효과가 굉장했다" 를 띄울지 판단하는 값이고, 데미지 계산은 `apply(_:of:against:)` 를 쓴다.
    static func effectiveness(_ attacking: PokemonType, against defending: [PokemonType]) -> Double {
        defending.reduce(1.0) { $0 * (multipliers[attacking]?[$1] ?? 1.0) }
    }

    /// 상성을 **정수 연산**으로 적용한다 — 방어 타입을 하나씩 곱하거나 나눈다(Gen 2 방식).
    /// 배율을 Double 로 한 번에 곱하면 두 피어가 각자 계산하는 이 대전에서 부동소수 오차가
    /// 결과를 가를 여지가 남는다. 표의 값은 0 / 0.5 / 2 뿐이라 정수 곱·나눗셈으로 정확히 옮겨진다.
    static func apply(_ damage: Int, of attacking: PokemonType, against defending: [PokemonType]) -> Int {
        var out = damage
        for type in defending {
            let multiplier = multipliers[attacking]?[type] ?? 1
            if multiplier == 0 { return 0 }
            if multiplier > 1 { out *= Int(multiplier) }
            else if multiplier < 1 { out /= Int(1 / multiplier) }
        }
        return out
    }
}

// MARK: - 스탯

/// 종족값(base stats) — PokéAPI `/pokemon/{id}` stats 순서와 무관하게 이름으로 매핑.
struct BattleStats: Codable, Sendable, Equatable {
    var hp: Int
    var atk: Int
    var def: Int
    var spa: Int
    var spd: Int
    var spe: Int

    /// 종족값 → 실제 능력치 (IV 31 고정, EV 0, 성격 보정 포함) — 본가 공식.
    ///
    /// **식이 여기 한 곳에만 있어야 한다.** 화면이 자기 식으로 계산하면 홈에 뜨는 숫자와 배틀이
    /// 쓰는 숫자가 갈라지고, 갈라진 걸 알아챌 방법은 둘을 손으로 맞대 보는 것뿐이다.
    func effective(level: Int, nature: PokemonNature?) -> BattleStats {
        func other(_ base: Int, _ stat: WritableKeyPath<BattleStats, Int>) -> Int {
            let raw = (2 * base + 31) * level / 100 + 5
            return Int(Double(raw) * NatureEffect.multiplier(nature, for: stat))
        }
        return BattleStats(
            hp: (2 * hp + 31) * level / 100 + level + 10,
            atk: other(atk, \.atk),
            def: other(def, \.def),
            spa: other(spa, \.spa),
            spd: other(spd, \.spd),
            spe: other(spe, \.spe))
    }
}

/// 랭크(스탯 단계)가 붙는 스탯 — HP 는 랭크가 없어서 빠졌다. rawValue 가 세이브·와이어 키를
/// 겸하고, PokéAPI 표기(`special-attack` …)는 `init(apiName:)` 이 옮긴다.
///
/// `CodingKeyRepresentable` 은 `[BattleStat: Int]` 를 JSON **객체**로 내보내기 위한 것이다.
/// 없으면 Swift 가 키·값 교대 배열로 인코딩해 와이어를 사람이 못 읽는다.
enum BattleStat: String, Codable, Sendable, Equatable, CaseIterable, CodingKeyRepresentable {
    case atk, def, spa, spd, spe, accuracy, evasion

    /// PokéAPI `stat_changes[].stat.name` → 랭크 스탯. `hp` 처럼 랭크가 없는 이름은 `nil` 이다.
    init?(apiName: String) {
        switch apiName {
        case "attack":          self = .atk
        case "defense":         self = .def
        case "special-attack":  self = .spa
        case "special-defense": self = .spd
        case "speed":           self = .spe
        case "accuracy":        self = .accuracy
        case "evasion":         self = .evasion
        default:                return nil
        }
    }

    /// 화면 배지용 약어 — 상태 배지(`BRN`·`PAR`)와 같은 이유로 언어를 타지 않는다.
    var shortLabel: String {
        switch self {
        case .atk:      return "Atk"
        case .def:      return "Def"
        case .spa:      return "SpA"
        case .spd:      return "SpD"
        case .spe:      return "Spe"
        case .accuracy: return "Acc"
        case .evasion:  return "Eva"
        }
    }

    /// 로그 문구용 이름 — `PokemonType.name` 과 같은 자리에 둔다(본가 공식 명칭).
    var name: String {
        switch self {
        case .atk:       "공격"
        case .def:       "방어"
        case .spa:       "특수공격"
        case .spd:       "특수방어"
        case .spe:       "스피드"
        case .accuracy:  "명중률"
        case .evasion:   "회피율"
        }
    }
}

/// 기술 하나가 만드는 랭크 변화. PokéAPI `stat_changes` 한 항목이다. 튜플이 아니라 값 타입인 건
/// 스냅샷에 실려 와이어·세이브를 건너야 하기 때문이다(`Codable`).
struct StatChange: Codable, Sendable, Equatable {
    var stat: BattleStat
    var change: Int
}

/// 랭크 배율. **데미지 스탯과 명중·회피가 서로 다른 표를 쓴다**(§3.2) — 한 표로 합치면
/// 명중 +1 이 150% 가 되거나 공격 +1 이 133% 가 된다.
enum StatStages {
    /// 랭크 상·하한. 본가와 같이 ±6 에서 멈춘다.
    static let limit = 6

    static func clamped(_ stage: Int) -> Int { min(limit, max(-limit, stage)) }

    /// 데미지 스탯 배율 — **Gen 3+ 정수 분수**(2/8 … 2/2 … 8/2). Gen 2 는 같은 값의 근사 소수
    /// (25/28/33/…/400 ÷100)를 썼는데, 두 피어가 각자 계산하는 이 대전에서는 정수 분수가 안전하다.
    static func fraction(stage: Int) -> (numerator: Int, denominator: Int) {
        let stage = clamped(stage)
        return stage >= 0 ? (2 + stage, 2) : (2, 2 - stage)
    }

    /// 랭크를 적용한 스탯. 곱을 먼저 하고 나눠야 정수 나눗셈의 손실이 한 번만 생긴다.
    static func apply(_ value: Int, stage: Int) -> Int {
        let (numerator, denominator) = fraction(stage: stage)
        return value * numerator / denominator
    }

    /// 명중·회피 배율(%) — **Gen 2 표**. 인덱스는 단계 + 6.
    /// Gen 5+ 는 명중 단계와 회피 단계를 합산해 한 번만 곱한다 — 그건 다른 방식이고 값도 다르다.
    static let accuracyTable = [33, 36, 43, 50, 60, 75, 100, 133, 166, 200, 233, 266, 300]

    static func accuracyPercent(stage: Int) -> Int { accuracyTable[clamped(stage) + limit] }
}

/// 성격의 스탯 보정 — 본가 공식 표(오른 스탯 ×1.1, 내린 스탯 ×0.9, 중립 5종은 무보정).
enum NatureEffect {
    /// (오르는 스탯, 내리는 스탯). nil = 중립.
    static func modifiers(_ nature: PokemonNature) -> (up: WritableKeyPath<BattleStats, Int>, down: WritableKeyPath<BattleStats, Int>)? {
        switch nature {
        case .lonely:  return (\.atk, \.def)
        case .brave:   return (\.atk, \.spe)
        case .adamant: return (\.atk, \.spa)
        case .naughty: return (\.atk, \.spd)
        case .bold:    return (\.def, \.atk)
        case .relaxed: return (\.def, \.spe)
        case .impish:  return (\.def, \.spa)
        case .lax:     return (\.def, \.spd)
        case .timid:   return (\.spe, \.atk)
        case .hasty:   return (\.spe, \.def)
        case .jolly:   return (\.spe, \.spa)
        case .naive:   return (\.spe, \.spd)
        case .modest:  return (\.spa, \.atk)
        case .mild:    return (\.spa, \.def)
        case .quiet:   return (\.spa, \.spe)
        case .rash:    return (\.spa, \.spd)
        case .calm:    return (\.spd, \.atk)
        case .gentle:  return (\.spd, \.def)
        case .sassy:   return (\.spd, \.spe)
        case .careful: return (\.spd, \.spa)
        case .hardy, .docile, .serious, .bashful, .quirky: return nil
        }
    }

    static func multiplier(_ nature: PokemonNature?, for stat: WritableKeyPath<BattleStats, Int>) -> Double {
        guard let nature, let m = modifiers(nature) else { return 1.0 }
        if m.up == stat { return 1.1 }
        if m.down == stat { return 0.9 }
        return 1.0
    }
}

// MARK: - 기술 (네트워크 대전용)

enum MoveDamageClass: String, Codable, Sendable { case physical, special, status }

/// 대전에서 고르는 기술 하나 — PokéAPI move 에서 필요한 것만. 스냅샷에 실려 상대에게 전달되므로
/// 이름은 PokéAPI 가 준 언어별 맵 그대로 오간다 — 표를 줄이면 옛 버전과 프레임 모양이 어긋난다.
struct MoveSpec: Codable, Sendable, Equatable, Identifiable {
    var id: Int                     // PokéAPI move id. 음수 = 로컬 합성 기술(fetch 실패 폴백)
    var names: [String: String]     // langCode → 이름
    var type: PokemonType
    var power: Int
    var damageClass: MoveDamageClass
    var accuracy: Int?              // nil = 필중
    var pp: Int
    var descriptions: [String: String]? = nil
    /// 기술 우선도(PokéAPI `priority`). 전광석화 +1, 축지법 −6 처럼 스피드보다 먼저 보는 값이다.
    /// 옵셔널인 이유는 호환이다 — 구버전 세이브의 학습 기술과 구버전 피어가 보내온 무브셋에는
    /// 이 키가 없다. 없으면 보통 기술(0)로 읽는다.
    var priority: Int? = nil

    /// 급소율 보정(PokéAPI `meta.crit_rate`). 베어가르기·잎날가르기처럼 급소가 잘 나는 기술은
    /// 여기에 양수가 온다. `priority` 와 같은 이유로 옵셔널이다 — 이 키가 없던 시절의 세이브와
    /// 구버전 피어의 무브셋에는 값이 아예 없다. 그런 기술은 보통 급소율로 읽는다.
    var critRate: Int? = nil

    /// 이 기술이 거는 상태이상(PokéAPI `meta.ailment` 의 이름). `priority`·`critRate` 와 같은 이유로
    /// 옵셔널이다 — 이 키가 없던 시절의 세이브와 구버전 피어의 무브셋에는 값이 아예 없다.
    var ailment: String? = nil
    /// 상태를 걸 확률(PokéAPI `meta.ailment_chance`). 0 은 "확률이 아니다" 라는 뜻이다.
    var ailmentChance: Int? = nil

    /// 이 기술이 만드는 랭크 변화(PokéAPI `stat_changes`).
    ///
    /// **`nil` 과 `[]` 를 구분한다.** 응답에 이 키는 늘 있고 변화가 없으면 빈 배열이므로,
    /// `nil` 은 "아직 안 받아봤다"(랭크 이전 세이브·구버전 피어)는 뜻이다. 섞으면 변화 없는
    /// 기술을 로드마다 다시 받거나, 옛 세이브가 영영 안 고쳐진다.
    /// `CompanionStore.needsDetailRefresh` 가 이 구분을 읽는다.
    var statChanges: [StatChange]? = nil
    /// 랭크 변화가 걸릴 확률(PokéAPI `meta.stat_chance`). `ailmentChance` 와 같이 0 은 "확률이 아니다".
    var statChance: Int? = nil

    /// 이 기술이 **자기**를 대상으로 하는가(PokéAPI `target` 이 `user` 계열). `statChanges` 와 같은
    /// 이유로 옵셔널이다 — 이 키가 없던 시절의 세이브·구버전 피어에는 값이 없다.
    ///
    /// 없으면 안 되는 값이다: 잠자기는 `damage_class: status` + `ailment: sleep` 이라
    /// `ailmentChancePercent` 가 100 을 주고, `applySecondaryEffect` 는 상태를 늘 **상대**에게 건다.
    /// 대상을 안 보면 회복 없는 필중 100% 수면기가 되어 CPU 가 무작위로 그걸 쓴다.
    var targetsUser: Bool? = nil
    /// PokéAPI `target` 슬러그 그대로(`selected-pokemon`·`all-opponents`·`all-other-pokemon` …).
    /// `targetsUser` 가 이 값에서 파생된 불리언인데도 원문을 함께 싣는 이유는 **범위**다 — 자기
    /// 대상 여부만으로는 광역기(양쪽 두 칸을 한 번에 때리는 기술)를 가릴 수 없다.
    /// `statChanges` 와 같은 이유로 옵셔널이다: 이 키가 없던 시절의 세이브와 구버전 피어에는
    /// 값이 아예 없고, 없으면 **단일 타겟**으로 읽는다(모르는 기술을 광역으로 만들지 않는다).
    var target: String? = nil
    /// **아군을 지목하는** 기술인가(PokéAPI `target` 이 `ally`). 도우미가 그 부류다.
    ///
    /// `targetsUser` 와 갈리는 값이다: 자기에게 거는 기술은 상대를 보지 않지만, 이 부류는 **다른
    /// 개체**에 효과를 얹는다. 대상을 고르는 자리가 상대 편만 훑으면 이 기술은 영영 아군에게
    /// 닿지 않는다(필드에 아군이 있는 두 모드에서만 값을 가진다).
    var targetsAlly: Bool { target == "ally" }
    var drain: Int? = nil
    /// 자기 회복량(PokéAPI `meta.healing`) — **최대 HP 대비 %**. 회복·아침햇살 계열이 50 이다.
    /// `drain` 과 다르다: 저쪽은 넣은 데미지의 비율이라 때려야 회복하고, 이쪽은 데미지와 무관하다.
    var healing: Int? = nil
    var flinchChance: Int? = nil
    var minHits: Int? = nil
    var maxHits: Int? = nil

    /// 턴 순서 비교용 우선도 — 값이 없으면 0.
    var turnPriority: Int { priority ?? 0 }

    /// 기술이 한 번에 닿는 범위. 데이터가 없으면(옛 세이브·구버전 피어·합성 무브셋) `single` 이다.
    ///
    /// 여기 없는 슬러그는 **전부 단일 취급**이다 — `entire-field`(날씨)·`opponents-field`(압정
    /// 뿌리기)처럼 필드에 거는 기술은 구현이 없고, 모르는 슬러그를 광역으로 승격하면 위력이 있는
    /// 기술 하나가 조용히 두 배로 닿는다.
    enum Reach: Sendable, Equatable {
        /// 고른 한 마리만.
        case single
        /// 상대 필드 전원(암석봉인·독가스 부류).
        case allOpponents
        /// 자기를 뺀 필드 전원 — **아군도 맞는다**(지진 부류).
        case allOthers
    }

    var reach: Reach {
        switch target {
        case "all-opponents":                    return .allOpponents
        // `all-pokemon` 도 여기로 접는다. 본가에서 이 부류(지진·폭발)는 시전자를 때리지 않으므로
        // 자기 제외 규칙이 같고, 자기 피해를 따로 두면 구현 없는 축이 하나 더 생긴다.
        case "all-other-pokemon", "all-pokemon": return .allOthers
        default:                                 return .single
        }
    }

    /// 이 기술이 여러 대상에게 한 번에 닿는가. **자기 대상 기술은 제외한다** — 회복·자기 랭크업은
    /// `target` 이 `user` 계열이라 애초에 `single` 이지만, 그 판정을 여기서 한 번 더 잠근다:
    /// 대상 루프를 타면 회복기가 상대 수만큼 회복하게 된다.
    var hitsSpread: Bool { reach != .single && targetsUser != true }

    /// 급소 단계 — PokéAPI `meta.crit_rate` 를 현행 본가 단계표에 그대로 연결한다.
    var critStage: Int { max(0, critRate ?? 0) }

    /// 실제로 걸 수 있는 상태 — 구현한 6종만. 나머지 14종은 `nil` 이라 부여 시도가 그냥 지나간다
    /// (무엇을 건너뛰었는지는 스펙을 만들 때 `AppLog` 에 한 번 남긴다).
    ///
    /// 맹독은 PokéAPI 가 별도 ailment 로 주지 않는다 — 맹독(id 92)도 `ailment` 는 `poison` 이다.
    /// 그래서 이 기술만 id 로 가른다.
    var inflictedStatus: Status? {
        if id == Self.toxicMoveID { return .toxic }
        return ailment.flatMap(Status.init(ailment:))
    }

    /// 이 명중률이 **필중**을 뜻하는가 — 이 규칙의 정본이다.
    ///
    /// PokéAPI 는 안 빗나가는 기술에 null 이 아니라 **0** 을 싣는 경우가 있다(타키온커터·파이어월·
    /// 드래곤치어). 그대로 읽으면 명중 0% 라 그 기술은 영영 빗나간다. 0% 명중인 기술은 도감에
    /// 없으므로 0 은 언제나 "명중 판정을 안 탄다" 는 뜻이다.
    ///
    /// `from` 이 디코딩할 때 nil 로 접지만 판정도 같은 규칙을 본다 — 옛 세이브와 구버전 피어가
    /// 이미 0 을 실어 보내고 있어, 디코딩만 고치면 그 데이터는 계속 빗나간다.
    static func neverMisses(_ accuracy: Int?) -> Bool { (accuracy ?? 0) <= 0 }

    /// 2차효과 확률의 기본값 규칙 — **상태·랭크가 이 한 곳을 공유한다.** 명시 확률이 있으면 그
    /// 값이고, 없으면 변화기는 100(효과가 기술 본체라 PokéAPI 가 0 을 준다) 공격기는 0 이다.
    /// 복제해 두면 한쪽만 고쳐도 컴파일·테스트가 아무것도 알려주지 않고 두 축이 갈라진다.
    private func chancePercent(_ declared: Int?) -> Int {
        if let declared, declared > 0 { return declared }
        return damageClass == .status ? 100 : 0
    }

    /// 상태를 거는 확률(%).
    var ailmentChancePercent: Int { chancePercent(ailmentChance) }
    var drainPercent: Int { min(100, max(-100, drain ?? 0)) }
    /// 자기 회복 비율(%). 0 이면 회복기가 아니다 — 잠자기는 `meta.healing` 이 0 이라 여기 안 걸리고
    /// `MoveSpec.restMoveID` 로 따로 판정한다(전회복 + 자기 수면이라 규칙이 다르다).
    var healingPercent: Int { min(100, max(0, healing ?? 0)) }

    /// 잠자기 — PokéAPI move id. 회복량이 `meta` 에 없어(0) 이 기술만 id 로 가른다.
    static let restMoveID = 156

    /// 잠자기의 수면 턴 — 원작대로 **2턴 고정**이다. 일반 수면(1~7턴)을 쓰면 운에 따라 7턴을
    /// 날려 쓸 이유가 없는 기술이 된다. `canAct` 이 카운터를 먼저 줄이므로 3을 넣어야 2턴 쉰다.
    static let restSleepCounter = 3

    /// 풀린치 확률(%). 상한 30 은 게이트 없는 기술들이 쓰는 최대치다.
    ///
    /// 도감에서 30 을 넘는 건 속임수(252) 하나뿐이고, 그 100% 는 "교체하고 나온 첫 턴에만"이라는
    /// 게이트와 한 몸이다. 게이트 없이 100 을 쓰면 우선도 +3 이 늘 선공을 보장해 **상대가 배틀
    /// 내내 한 번도 못 움직인다** — 냐옹이 레벨 1 습득기라 실제로 뽑힌다.
    ///
    /// ponytail: 첫 턴 게이트를 만들려면 `BattleSide` 가 필드에 나온 턴 수를 들고 교체·자동 출전이
    ///           리셋해야 한다. 만들면 클램프를 지우고 속임수에 게이트를 태운다.
    static let flinchChanceCap = 30
    var flinchPercent: Int { min(Self.flinchChanceCap, max(0, flinchChance ?? 0)) }
    /// 이 기술이 상대를 만지는가 — 쇼다운의 `contact` 플래그다. PokéAPI 에는 접촉 열이 아예 없어
    /// 이 데이터만이 답한다(손 목록이면 277개가 조용히 낡는다).
    var makesContact: Bool { ShowdownMoveData.makingContact.contains(id) }
    /// 펀치 기술인가 — 쇼다운의 `punch` 플래그다(펀치글러브가 읽는다).
    var isPunch: Bool { ShowdownMoveData.punching.contains(id) }
    /// 소리 기술인가 — 쇼다운의 `sound` 플래그다(목스프레이가 읽는다).
    var isSound: Bool { ShowdownMoveData.sound.contains(id) }

    /// 이번에 맞는 횟수. `minimumHits` 는 속임수주사위가 주는 하한이다 — **단발 기술은 만지지
    /// 않는다**(하한을 그냥 얹으면 몸통박치기가 네 번 맞는다). 인자로 받는 이유는 난수 소비다:
    /// 하한이 있어도 폭은 그대로 뽑아야 두 피어의 rng 가 갈리지 않는다.
    func hitCount(rng: inout SplitMix64, minimumHits: Int?) -> Int {
        let low = min(10, max(1, minHits ?? 1))
        let high = min(10, max(low, maxHits ?? low))
        guard low != high else { return low }
        let rolled: Int
        if low == 2, high == 5 {
            switch rng.next() % 8 {
            case 0...2: rolled = 2
            case 3...5: rolled = 3
            case 6:     rolled = 4
            default:    rolled = 5
            }
        } else {
            rolled = low + Int(rng.next() % UInt64(high - low + 1))
        }
        guard let minimumHits else { return rolled }
        return min(high, max(rolled, minimumHits))
    }
    var hasModeledStatusEffect: Bool {
        (inflictedStatus != nil && targetsUser != true)
            || (!(statChanges ?? []).isEmpty && statChangePercent > 0)
            // 날씨기·필드기는 상태이상도 랭크도 안 걸지만 판을 바꾼다 — 안 열면 아무도 못 배운다.
            || BattleWeather.called(byMoveID: id) != nil
            || BattleTerrain.called(byMoveID: id) != nil
            || BattleSideCondition.called(byMoveID: id) != nil
            // 방어기는 상태도 랭크도 안 걸고 **이번 턴 자기를 지킨다**(같은 이유로 열어 준다).
            || BattleGuard.called(byMoveID: id)
            // volatile 을 거는 기술도 상태이상 표에는 없다 — 안 열면 아무도 못 배운다.
            || BattleVolatile.called(byMoveID: id) != nil
    }

    /// 랭크 변화가 걸리는 확률(%) — 2차효과는 `stat_chance` 를 그대로 쓰고, 위력 없는 변화기는
    /// 랭크 변화가 기술 **본체**라 늘 건다(PokéAPI 가 그런 기술에 0 을 준다).
    ///
    /// 공격기 + 확률 없음(0) 은 **적용하지 않는다.** 인파이트·깨트리다처럼 *자기* 방어를 확정으로
    /// 깎는 기술인데, 응답만으로는 대상이 자기인지 상대인지 알 수 없다 — `applyStatChanges` 의
    /// 부호 규칙에 맡기면 상대를 깎아 완전히 뒤집힌다. 확률이 붙은 2차효과는 오로라빔·
    /// 사이코키네시스처럼 실제로 상대를 깎으므로 부호 규칙이 맞다.
    /// 부호가 대상을 정하는 규칙이 **통하지 않는** 랭크 변화 — 올리는 것과 내리는 것이 한 기술에
    /// 같이 있는 경우다. 저주(자기 스피드 −1 + 공격·방어 +1)가 그렇고, 부호로 가르면 스피드 감소가
    /// 상대에게 걸려 자기 버프 두 개 + 상대 디버프 하나가 된다. 가릴 수 없으면 걸지 않는다.
    var hasAmbiguousStatTargets: Bool {
        guard let statChanges else { return false }
        return statChanges.contains { $0.change > 0 } && statChanges.contains { $0.change < 0 }
    }

    /// 대가를 **모델링하지 않은** 큰 상승. 배가르기(공격 +6 + 최대 HP 절반)는 HP 소모가 어디에도
    /// 없어서, 그대로 통과시키면 첫 턴 공짜 +6 공격이 된다(CPU 도 무작위로 쓴다). 저주의 Ghost
    /// HP 반감도 같은 부류다.
    ///
    /// ponytail: `|변화| >= 3` 은 휴리스틱이다 — Gen 2 범위에서 이 문턱에 걸리는 건 배가르기뿐이고
    ///           (칼춤·방어막·기억상실은 ±2), 대가를 실제로 구현하면 이 게이트를 지우고 코스트를
    ///           태운다. 문턱을 넘는 기술이 늘면 여기 대신 기술별 코스트 표가 필요하다.
    var hasUnpricedGain: Bool {
        guard damageClass == .status else { return false }
        return (statChanges ?? []).contains { abs($0.change) >= 3 }
    }

    var statChangePercent: Int {
        if hasAmbiguousStatTargets || hasUnpricedGain { return 0 }
        return chancePercent(statChance)
    }

    /// 맹독 — PokéAPI move id.
    static let toxicMoveID = 92
    /// 테라버스트 — 테라스탈 상태에서만 타입·분류가 바뀌는 유일한 기술이다.
    static let teraBlastID = 851

    /// **이 개체가 지금 쓰는 형태**의 기술. 스펙(도감 값)과 실제로 나가는 값이 갈리는 자리를
    /// 한 함수로 모은다 — 지금은 테라버스트뿐이다.
    ///
    /// 테라스탈 상태면 타입이 테라 타입이 되고, 분류는 **공격·특공 중 높은 쪽**으로 갈린다
    /// (랭크를 포함한 현재 값 기준 — 본가와 같다). 테라스탈이 아니면 도감 그대로 노말 특수기다.
    ///
    /// 엔진의 **대상 단위 입구**(`applyHit`)와 AI 추정이 이 함수를 지난다. 한 자리라도 원본 스펙을
    /// 쓰면 그 경로에서만 테라버스트가 노말로 나가고, 화면에는 위력만 이상하게 보인다.
    func asUsed(by attacker: BattleSide) -> MoveSpec {
        guard id == MoveSpec.teraBlastID, attacker.isTerastallized else { return self }
        var used = self
        used.type = attacker.snapshot.teraType
        let attack = StatStages.apply(attacker.rawStat(.atk), stage: attacker.stage(.atk))
        let special = StatStages.apply(attacker.rawStat(.spa), stage: attacker.stage(.spa))
        used.damageClass = attack > special ? .physical : .special
        return used
    }

    /// 전기자석파 — PokéAPI move id.
    static let thunderWaveID = 86

    /// 상성표를 **그대로 보는** 상태기. 여기 없는 변화기는 상성을 타지 않는다.
    ///
    /// 노말↔고스트 면역은 **데미지 기술의 규칙**이다 — 이상한빛(고스트)은 노말에게, 노래(노말)는
    /// 고스트에게, 최면술(에스퍼)은 악에게 통해야 한다. 예전엔 "상태를 거는 변화기는 전부 상성표를
    /// 본다" 였고, 그 한 줄이 해당 12개 중 8개를 잘못 막았다.
    ///
    /// 독·화상·얼음 면역은 여기가 아니라 `BattleSide.canBeAfflicted` 가 본다 — 기술 타입이 아니라
    /// **거는 상태**로 판정하므로(강철은 독을 안 받는다) 상성표를 꺼도 그대로 막힌다.
    static let typeBlockedStatusMoveIDs: Set<Int> = [thunderWaveID]

    /// 화면·로그에 쓰는 이름. `names` 는 PokéAPI 가 준 언어별 표 그대로 LAN 으로도 오가므로
    /// 표 자체는 줄이지 않고, 읽을 때 한국어를 고른다.
    var name: String { PokemonNaming.name(names) ?? names.values.first ?? "?" }
    var flavorText: String? {
        guard let descriptions else { return nil }
        return PokemonNaming.name(descriptions) ?? descriptions["en"] ?? descriptions.values.first
    }

    /// 발버둥 — PP 전부 소진 시 폴백(무속성 취급은 엔진에서 id 로 판정).
    ///
    /// **반동이 이 기술의 본질이다** — 넣은 데미지의 1/4 을 자기가 받는다(Gen 2·3).
    /// 반동 축(`drain` 음수)이 없던 동안은 대가 없는 위력 50 무상성기였고, PP 가 마르면
    /// 오히려 더 나은 선택이 됐다. 합성 기술이라 `moveDetail` 이 못 채우니 여기에 직접 박는다.
    static let struggleID = -999
    static func struggle() -> MoveSpec {
        MoveSpec(id: struggleID,
                 names: ["ko": "발버둥", "en": "Struggle", "ja": "わるあがき"],
                 type: .normal, power: 50, damageClass: .physical, accuracy: nil, pp: 999,
                 drain: -25)
    }

    /// 기술 fetch 실패 시 합성 무브셋 — 자기 타입 기반 4개(대전 자체는 항상 가능해야 한다).
    static func fallbackSet(types: [PokemonType]) -> [MoveSpec] {
        let t1 = types.first ?? .normal
        let t2 = types.count > 1 ? types[1] : t1
        func synth(_ id: Int, _ ko: String, _ en: String, _ ja: String,
                   _ type: PokemonType, _ power: Int, _ cls: MoveDamageClass, _ acc: Int?, _ pp: Int) -> MoveSpec {
            MoveSpec(id: id, names: ["ko": ko, "en": en, "ja": ja],
                     type: type, power: power, damageClass: cls, accuracy: acc, pp: pp)
        }
        return [
            synth(-1, "몸통박치기", "Tackle", "たいあたり", .normal, 40, .physical, 100, 35),
            synth(-2, "속이기", "Fake Out", "ねこだまし", .normal, 40, .physical, 100, 10),
            synth(-3, "\(t1.name) 일격", "\(t1.name) Strike", "\(t1.name)のいちげき", t1, 80, .physical, 100, 15),
            synth(-4, "\(t2.name) 파동", "\(t2.name) Pulse", "\(t2.name)のはどう", t2, 70, .special, 100, 20),
        ]
    }
}

// MARK: - 배틀 스냅샷 (교환 단위)

/// 대전 상대와 교환되는 포켓몬 스냅샷 — 수신 측이 추가 조회 없이 배틀할 수 있게 스탯·타입을 내장한다.
struct BattleSnapshot: Codable, Sendable, Equatable {
    var v: Int = 1
    var speciesID: Int
    /// 표시 이름 — 내보내는 쪽 언어의 현지화 이름(수신 측은 그대로 표시).
    var name: String
    var trainer: String?
    var level: Int
    var nature: PokemonNature?
    var isShiny: Bool
    var types: [PokemonType]
    /// 종족값 — 유효 스탯은 배틀 시점에 level·nature 로 계산(레벨만 바꾸는 변조 방지 폭 축소).
    var base: BattleStats
    /// 네트워크 대전용 무브셋(최대 4).
    var moves: [MoveSpec]? = nil
    /// 특성 슬러그 원문(`levitate`) — 옵셔널은 `priority` 와 같은 호환 규칙이다(구버전 피어는 안 보낸다).
    ///
    /// **원문을 싣는 이유**: 아직 구현하지 않은 특성도 그대로 실어 두면 `BattleAbility` 에 case 를
    /// 늘릴 때 스냅샷 계약을 안 건드려도 된다. 모르는 값은 해석 시점에 `nil` 로 접힌다.
    /// 개체가 특성캡슐·패치를 쓴 경우에는 `MonState.abilitySlug`에 저장된 선택이 실린다.
    /// 구버전 개체는 nil이며 종의 첫 일반 특성으로 폴백한다.
    ///
    /// 스냅샷을 만드는 네 자리가 이 값을 싣는지는
    /// `VariableDamageTests.testEveryBattleSnapshotSiteCarriesTheWireOnlyFields` 가 소스에서 센다
    /// (인자 이름만 보므로 선언 순서는 자유다). 전부 기본값 `nil` 이라 빠뜨려도 컴파일은 통과한다.
    var ability: String? = nil
    /// 테라스탈했을 때 되는 타입 — **테라피스로 바꿨을 때만** 값이 있다. `nil` 이면 아래
    /// `teraType` 이 첫 번째 타입에서 파생한다(아이템이 없던 시절의 규칙 그대로).
    ///
    /// 읽는 자리는 `teraType` 하나다 — 이 저장 값을 직접 읽는 코드를 두면 그 자리만 파생 폴백을
    /// 잃고, 아이템을 안 쓴 개체 전부가 노말로 테라스탈한다.
    ///
    /// **와이어에 실린다.** 안 실으면 두 피어가 같은 개체를 다른 타입으로 테라스탈시켜 상성
    /// 배율부터 갈린다(각자 화면에는 정상으로 보인다). 스냅샷을 만드는 자리가 이 값을 싣는지는
    /// `ability` 와 같은 스캔이 센다.
    var storedTeraType: PokemonType? = nil
    /// 지금 지니고 있는 물건 — 배틀에서 하는 일은 `ItemKind.heldBattleEffect` 가 답한다.
    ///
    /// **와이어에 실린다.** 안 실으면 한쪽 피어만 데미지 배율·회복·버티기를 얹어 같은 판의 HP 가
    /// 갈린다(각자 화면에는 정상으로 보인다). 스냅샷을 만드는 자리가 이 값을 싣는지는 `ability`
    /// 와 같은 스캔이 센다.
    ///
    /// 피어가 보내온 값이라 **지닐 수 없는 물건은 거절한다**
    /// (`MultiplayerValidation.validHeldItem`). 모르는 이름은 디코딩에서 `nil` 로 접히므로
    /// (특성 슬러그와 같은 정책) 신버전이 아이템을 늘려도 옛 피어가 대전에서 막히지 않는다.
    var heldItem: ItemKind? = nil
    /// 헥토그램(0.1kg). 체중으로 위력이 정해지는 기술이 본다.
    ///
    /// 옵셔널인 이유는 **조회 실패**다(피어 호환이 아니다 — 이 필드가 없던 시절과는 `rulesVersion`
    /// 이 이미 대전을 막는다). 0 으로 접으면 안 된다: 저공격이 "가장 가벼움"으로 최저 위력이 되고
    /// 헤비봄버는 0 나눗셈 자리로 간다. 값이 없으면 그 기술만 실패시킨다(`VariableDamage.noEffect`).
    var weightHectograms: Int? = nil
    /// 이 개체가 **아직 진화할 수 있나** — 진화의휘석이 보는 값이다. 진화 라인에서만 알 수 있어
    /// (`EvoLine.canEvolveFurther`) 스냅샷을 만드는 자리가 실어 온다.
    ///
    /// `nil` 은 "모른다" 이고 휘석은 아무 일도 하지 않는다. 종 번호로 만드는 야생·CPU 스냅샷이
    /// 그 자리인데, 그 개체들은 물건을 쥐지 않으므로(`heldItem: nil`) 결과가 갈리지 않는다.
    var canStillEvolve: Bool? = nil

    /// 레벨 유도 — 성장 진행도(단계 + 단계 내 진행)를 5~100 레벨로 사상.
    /// stageProgress 는 0~1 로 클램프, totalForms ≥ 1 보장.
    static func level(stageIndex: Int, totalForms: Int, stageProgress: Double) -> Int {
        let k = max(1, totalForms)
        let p = min(1.0, max(0.0, stageProgress))
        let overall = min(1.0, (Double(stageIndex) + p) / Double(k))
        return min(100, max(5, 5 + Int((overall * 95.0).rounded())))
    }

    /// 테라스탈했을 때 이 개체가 되는 타입 — **저장 값이 있으면 그것, 없으면 첫 번째 타입**이다.
    ///
    /// 폴백을 두는 이유는 본가와 같다: 야생·부화 개체의 테라 타입은 자기 타입 중 하나이고, 그것을
    /// 바꾸는 것이 테라피스(`ItemKind.teraShard`)다. 그래서 아이템을 안 쓴 개체와 이 필드가
    /// 없던 세이브·피어가 모두 예전과 같은 답을 받는다.
    var teraType: PokemonType { storedTeraType ?? types.first ?? .normal }

    /// 유효 스탯 — 식은 `BattleStats.effective` 한 곳에 있다(홈 화면도 같은 식을 쓴다).
    func effectiveStats() -> BattleStats { base.effective(level: level, nature: nature) }

}

// MARK: 스냅샷의 디코딩 경계

/// 스냅샷은 **피어가 보내오는 값이다** — 1v1 도전·수락, 방 입장, 라운드 브로드캐스트,
/// 토너먼트·체육관 라인업이 전부 이 타입을 나른다. 경계에서 자르지 않으면 검증이 돌기 **전에**
/// 죽는다: `MultiplayerFighter.init(from:)` 은 디코딩 직후 `BattleSide(_:)` 를 만들고, 그
/// 생성자가 `(2 * hp + 31) * level` 을 계산하므로 `Int` 상한 근처 값이 오버플로로 트랩된다
/// (Swift 의 산술 오버플로는 던지는 오류가 아니라 프로세스 종료다).
///
/// 형제 타입 `PokeathlonRacer`·`PokeathlonRace`·`PokeathlonPool`·`PokeathlonBet` 이 같은 이유로
/// 이미 클램프를 갖고 있다 — 같은 프레임으로 들어오는 타입은 함께 막는다.
///
/// **기술의 수치(위력·확률·히트 수)는 여기서 자르지 않는다.**
/// `MultiplayerValidation.validMoves` 가 입장·개시·1v1 라인업에서 그 값을 보고 **거절**하는데,
/// 여기서 잘라 버리면 거절이 조용한 하향으로 바뀌어 조작한 피어가 대전에 들어온다.
/// 배열 **길이**만 자른다(라운드마다 참가자 수만큼 다시 나가는 프레임의 증폭 상한).
extension BattleSnapshot {
    /// 대전 레벨 범위 — `MultiplayerValidation.valid` 가 보는 범위와 같다.
    static let levelRange = 1...100
    /// 종족값의 **안전 범위** — 도감 최대치는 255 이고 와이어에서 그 위를 거절하는 곳은
    /// `MultiplayerValidation.valid` 다. 여기 상한이 255 가 아닌 이유: 이 생성자는 세이브
    /// (`RogueRunSave`)도 통과하고, 판 조율·테스트가 도감 밖 종족값으로 판을 만든다 —
    /// 255 로 자르면 저장한 판이 되살아날 때 최대 HP 가 달라진다(저장이 하향이 된다).
    /// 이 범위가 막는 것은 오버플로 하나이며, 공정성은 위 검증이 계속 본다.
    static let baseStatRange = 1...100_000
    /// 한 개체의 타입 수 — 본가와 같이 최대 2 다.
    static let maximumTypes = 2
    /// 무브셋 상한 — 기술 칸이 넷이다.
    static let maximumMoves = 4
    /// 체중(헥토그램) 상한 — 도감 최대치가 9999(코스모움)다.
    static let maximumWeightHectograms = 9_999

    private static func clampedStat(_ value: Int) -> Int {
        min(baseStatRange.upperBound, max(baseStatRange.lowerBound, value))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        speciesID = PokemonAssets.clampedID(try c.decode(Int.self, forKey: .speciesID))
        // 이름은 길이를 재는 게 아니라 자른다 — 거부하면 대전 자체가 성립하지 않는다
        // (`PeerTextPolicy.displayName` 이 그 규칙의 정본이다).
        name = PeerTextPolicy.displayName(try c.decode(String.self, forKey: .name)) ?? "?"
        trainer = (try c.decodeIfPresent(String.self, forKey: .trainer))
            .flatMap(PeerTextPolicy.displayName)
        level = min(Self.levelRange.upperBound,
                    max(Self.levelRange.lowerBound, try c.decode(Int.self, forKey: .level)))
        nature = try c.decodeIfPresent(PokemonNature.self, forKey: .nature)
        isShiny = try c.decode(Bool.self, forKey: .isShiny)
        types = Array((try c.decode([PokemonType].self, forKey: .types)).prefix(Self.maximumTypes))
        let base = try c.decode(BattleStats.self, forKey: .base)
        self.base = BattleStats(hp: Self.clampedStat(base.hp), atk: Self.clampedStat(base.atk),
                                def: Self.clampedStat(base.def), spa: Self.clampedStat(base.spa),
                                spd: Self.clampedStat(base.spd), spe: Self.clampedStat(base.spe))
        moves = (try c.decodeIfPresent([MoveSpec].self, forKey: .moves))
            .map { Array($0.prefix(Self.maximumMoves)) }
        ability = try c.decodeIfPresent(String.self, forKey: .ability)
        storedTeraType = try c.decodeIfPresent(PokemonType.self, forKey: .storedTeraType)
        // 모르는 아이템 이름은 **접는다**. 타입된 디코딩은 오류를 던지고, 그 오류는 스냅샷 전체를
        // 못 읽게 만들어 대전 자체가 성립하지 않는다 — 신버전이 아이템을 하나 늘리면 옛 피어가
        // 통째로 막힌다(`ability` 를 슬러그 원문으로 싣는 것과 같은 이유다).
        heldItem = (try c.decodeIfPresent(String.self, forKey: .heldItem))
            .flatMap(ItemKind.init(rawValue:))
        weightHectograms = (try c.decodeIfPresent(Int.self, forKey: .weightHectograms))
            .map { min(Self.maximumWeightHectograms, max(0, $0)) }
    }
}

// MARK: - 상태이상

/// 상태이상 — Gen 2 의 6종 + 혼란. PokéAPI `/move-ailment` 20종 중 6종만 쓰고 나머지는 무시한다
/// (맹독은 이름이 없어 기술 id 로 가른다 — `MoveSpec.inflictedStatus`).
/// 앞 6종은 주 상태(한 번에 하나), 혼란은 volatile 이다. 화면 어휘를 하나로 두려고 한 enum 에 있고,
/// 어느 쪽인지는 `BattleSide` 가 필드로 가른다.
enum Status: String, Codable, Sendable, Equatable, CaseIterable {
    case burn, poison, toxic, paralysis, sleep, freeze, confusion, flinch

    /// PokéAPI `/move-ailment` 이름 → 구현한 상태. `none`·`unknown` 을 포함해 모르는 이름은 `nil` 이다.
    init?(ailment: String) {
        switch ailment {
        case "burn":      self = .burn
        case "poison":    self = .poison
        case "paralysis": self = .paralysis
        case "sleep":     self = .sleep
        case "freeze":    self = .freeze
        case "confusion": self = .confusion
        default:          return nil   // toxic 은 ailment 이름이 없다 — `MoveSpec.inflictedStatus` 참조
        }
    }

    /// HP바 옆 배지 — Showdown 과 같은 약어라 언어를 타지 않는다.
    var badge: String {
        switch self {
        case .burn:      return "BRN"
        case .poison:    return "PSN"
        case .toxic:     return "TOX"
        case .paralysis: return "PAR"
        case .sleep:     return "SLP"
        case .freeze:    return "FRZ"
        case .confusion: return "CNF"
        case .flinch:    return "FLN"
        }
    }
}

/// 데미지가 어디서 왔는가. 로그·연출은 "기술을 맞았다" 와 "화상으로 깎였다" 를 갈라야 하는데,
/// 원인이 없으면 잔뎀이 직전 `.move` 에 접혀 **쓰지도 않은 기술 이름**이 붙는다.
enum DamageCause: String, Codable, Sendable, Equatable {
    case move, burn, poison, toxic, confusion, recoil, weather
    /// 개체에 붙은 상태(`BattleVolatile`)가 깎은 몫 — 조이기·저주·나이트메어.
    /// volatile 하나에 원인 하나를 두는 이유는 로그다: "무엇에 맞았는지"를 잃으면 잔뎀이
    /// 전부 같은 줄로 읽혀, 조이기가 풀렸는데도 계속 깎이는 오구현이 화면에서 안 보인다.
    case trap, curse, nightmare, leechSeed
    /// 지닌 물건이 깎은 몫 — 검은오물. 반동(`recoil`)과 나누는 이유는 로그다: 반동은 자기가 쓴
    /// 기술의 대가고, 이쪽은 쥐고만 있어도 깎인다.
    case heldItem
    /// 교체로 나올 때 밟은 몫 — 압정뿌리기·스텔스록. 넷을 한 원인으로 묶는 이유는 문구다:
    /// 어느 것을 밟았는지는 밟기 전에 나간 시작 줄이 이미 말한다.
    case hazard
}

// MARK: - 배틀 전체에 걸리는 상태

/// 날씨 — 어느 한쪽의 상태가 아니라 **판 전체**의 상태다. 그래서 `BattleSide` 가 아니라
/// `BattleField` 에 있고, 배틀 모드마다 하나씩 들고 `applyAttack` 에 넘긴다.
enum BattleWeather: String, Codable, Sendable, Equatable, CaseIterable {
    case sun, rain, sandstorm, snow

    /// 지속 턴 — 본가의 지닌물건(구슬류)이 없으므로 늘 5턴이다.
    static let duration = 5

    /// 쇼다운이 쓰는 키 → 이 열거형. 싸라기눈(`hail`)은 9세대에서 눈으로 바뀌었고 데미지가
    /// 없어졌다 — 옛 기술을 옛 규칙으로 따로 두면 세는 자리가 둘이 되므로 눈으로 합친다.
    init?(showdownKey: String) {
        switch showdownKey.lowercased() {
        case "sunnyday":            self = .sun
        case "raindance":           self = .rain
        case "sandstorm":           self = .sandstorm
        case "hail", "snowscape":   self = .snow
        default:                    return nil
        }
    }

    /// 이 날씨를 부르는 기술인가 — **id 목록을 손으로 들지 않는다.** 어느 기술이 무엇을 부르는지는
    /// 추출한 데이터(`ShowdownMoveData.effects`)가 답하고, 엔진은 효과만 구현한다. 손 목록이던
    /// 시절에는 새로 생긴 같은 부류(한기의고동 같은 두 번째 눈 기술)가 조용히 빠졌다.
    static func called(byMoveID id: Int) -> BattleWeather? {
        ShowdownMoveData.effects[id]?.weather.flatMap(BattleWeather.init(showdownKey:))
    }

    /// 이 타입 기술의 데미지 배율 — 분수로 준다. 실수로 곱하면 두 피어의 값이 갈릴 수 있다.
    func damageScale(of type: PokemonType) -> (numerator: Int, denominator: Int) {
        switch (self, type) {
        case (.sun, .fire), (.rain, .water):   return (3, 2)
        case (.sun, .water), (.rain, .fire):   return (1, 2)
        default:                               return (1, 1)
        }
    }

    /// 턴 끝에 깎이는가 — 모래바람만 깎는다(눈은 9세대에서 데미지가 없어졌다).
    /// 바위·땅·강철은 모래에 안 깎인다.
    func residualDamage(for types: [PokemonType], maxHP: Int) -> Int? {
        guard self == .sandstorm else { return nil }
        let immune: [PokemonType] = [.rock, .ground, .steel]
        guard !types.contains(where: immune.contains) else { return nil }
        return max(1, maxHP / 16)
    }
}

/// 필드 — 땅에 깔리는 상태다. 날씨와 달리 **땅에 닿은 개체에게만** 걸린다(비행·부유는 안 받는다).
enum BattleTerrain: String, Codable, Sendable, Equatable, CaseIterable {
    case electric, grassy, misty, psychic

    static let duration = 5

    init?(showdownKey: String) {
        switch showdownKey.lowercased() {
        case "electricterrain": self = .electric
        case "grassyterrain":   self = .grassy
        case "mistyterrain":    self = .misty
        case "psychicterrain":  self = .psychic
        default:                return nil
        }
    }

    /// 이 필드를 까는 기술인가 — 날씨와 같은 자리에서 데이터가 답한다.
    static func called(byMoveID id: Int) -> BattleTerrain? {
        ShowdownMoveData.effects[id]?.terrain.flatMap(BattleTerrain.init(showdownKey:))
    }

    /// 땅에 닿은 **공격자**의 이 타입 기술을 1.3배로 만든다.
    var boostedType: PokemonType? {
        switch self {
        case .electric: return .electric
        case .grassy:   return .grass
        case .psychic:  return .psychic
        case .misty:    return nil      // 미스트필드는 올리지 않고 드래곤을 반으로 깎는다
        }
    }

    /// 땅에 닿은 개체가 이 상태에 안 걸리는가 — 일렉트릭필드는 잠듦만, 미스트필드는 주 상태 전부.
    func blocks(_ status: Status) -> Bool {
        switch self {
        case .electric: return status == .sleep
        // 미스트필드는 주 상태와 혼란을 전부 막는다. 풀죽음은 여기를 지나지 않는다.
        case .misty:    return status != .flinch
        default:        return false
        }
    }
}

/// 편 — 한쪽 진영 전체에 걸리는 상태(장막·부적)의 주인이다. 개체가 아니라 **자리**라서
/// 교체가 있는 모드에서도 살아남는다.
enum BattleTeamSlot: Codable, Sendable, Equatable, Hashable {
    case a, b
    /// 개인전(방의 free-for-all)은 참가자 하나가 곧 한 편이다. 좌우 두 자리로 접으면 한 명이 편
    /// 리플렉터가 경쟁자 전원을 지킨다 — `BattleActor` 가 UUID 로 갈리는 것과 같은 이유다.
    case solo(UUID)

    /// 판에 실제로 존재하는 편 — 진영 상태를 턴마다 훑을 때 쓴다. 개인전 자리는 깔린 것이 있을
    /// 때만 나타나므로 여기 상수로 둘 수 없다(그래서 `CaseIterable` 이 아니다).
    static let fixed: [BattleTeamSlot] = [.a, .b]

    /// 순회를 고정하기 위한 키. 값 자체에 뜻은 없다 — 두 피어가 같은 순서로 훑기만 하면 된다.
    var sortKey: String {
        switch self {
        case .a:               return "a"
        case .b:               return "b"
        case .solo(let id):    return "solo:" + id.uuidString
        }
    }
}

/// 한 진영에만 깔리는 상태 — 날씨·필드가 판 전체인 것과 다르다.
///
/// 셋으로 갈린다.
///
/// **장막·부적·순풍**은 자기 편에 깔리고 턴을 센다. 순풍만 데미지가 아니라 **턴 순서**를 바꾼다 —
/// 그래서 `BattleEngine.orderingSpeed` 를 지나는 모드만 순풍을 본다(모드마다 순서 계산이 따로라,
/// 새 모드가 직접 스피드를 읽으면 조용히 빠진다).
///
/// **편 방어기** 넷(와이드가드·퀵가드·니가하지마·트릭가드)은 개인 방어(`BattleGuard`)와 달리 편
/// 전체를 지키고 막는 기술의 종류가 갈린다. 한 턴짜리라 지속 턴도 1 이다.
///
/// **입장 데미지** 넷(끈적끈적네트·스텔스록·압정뿌리기·독압정)만 규칙이 셋 다 다르다:
/// ①**상대 편**에 깔린다(어느 편인지는 데이터가 답한다 — `landsOnFoeSide`) ②턴이 지나도 걷히지
/// 않고 **층**으로 쌓인다 ③효과는 기술을 쓴 턴이 아니라 **다음 교체**에 나온다
/// (`BattleEngine.applyEntryHazards`). `allCases` 의 **선언 순서가 밟는 순서**다.
enum BattleSideCondition: String, Codable, Sendable, Equatable, CaseIterable {
    case reflect, lightScreen, auroraVeil, safeguard, mist, luckyChant, tailwind
    case wideGuard, quickGuard, matBlock, craftyShield
    /// 밟는 순서 그대로 적는다(본가 순서 — 끈적끈적네트 → 스텔스록 → 압정 → 독압정).
    /// 순서를 바꾸면 같은 판에서 로그 줄 순서가 달라진다.
    case stickyWeb, stealthRock, spikes, toxicSpikes

    /// 지속 턴. 장막·부적은 5턴이고 순풍만 4턴이다 — 빛의점토를 쥔 쪽이 깔면 장막만 8턴이 된다
    /// (`HeldItemEffect.extendedTurns(of:)`가 거는 자리에서 답한다).
    /// 한 턴 더 불면 그 턴의 선공이 통째로 뒤집힌다. 편 방어기는 개인 방어와 같이 한 턴이다.
    ///
    /// 입장 데미지는 **0** 이다 — 걷히지 않으므로 셀 턴이 없다. 저장하는 숫자도 남은 턴이 아니라
    /// 층 수라, `BattleEngine.advanceField` 가 이 부류를 감소 루프에서 빼고 지나간다.
    /// `default` 를 두지 않는다: 새 case 가 조용히 5턴이 되면 걷히지 않아야 할 것이 걷힌다.
    var duration: Int {
        switch self {
        case .tailwind:                                         return 4
        case .wideGuard, .quickGuard, .matBlock, .craftyShield:  return 1
        case .stickyWeb, .stealthRock, .spikes, .toxicSpikes:    return 0
        case .reflect, .lightScreen, .auroraVeil,
             .safeguard, .mist, .luckyChant:                     return 5
        }
    }

    /// 교체로 새로 나오는 개체가 밟는 부류인가. 참이면 저장된 숫자가 남은 턴이 아니라 **층 수**다.
    var isEntryHazard: Bool {
        switch self {
        case .stickyWeb, .stealthRock, .spikes, .toxicSpikes:   return true
        case .reflect, .lightScreen, .auroraVeil, .safeguard, .mist, .luckyChant, .tailwind,
             .wideGuard, .quickGuard, .matBlock, .craftyShield: return false
        }
    }

    /// 쌓이는 층 수 상한. 상한이 없으면 매 턴 다시 깔아 교체가 즉사가 되고, 1 로 접으면
    /// 압정·독압정이 본가보다 약한 채 두 번째 사용이 실패한다.
    var maxLayers: Int {
        switch self {
        case .spikes:      return 3
        case .toxicSpikes: return 2
        case .stickyWeb, .stealthRock, .reflect, .lightScreen, .auroraVeil, .safeguard,
             .mist, .luckyChant, .tailwind,
             .wideGuard, .quickGuard, .matBlock, .craftyShield: return 1
        }
    }

    /// **접지한 개체만** 밟는가. 스텔스록만 공중에 뜬 쪽도 맞는다(본가와 같다) — 나머지 셋은
    /// 발밑에 놓인 것이라 비행·부유가 지난다(`BattleField.isGrounded`).
    var hitsOnlyGrounded: Bool {
        switch self {
        case .spikes, .toxicSpikes, .stickyWeb: return true
        case .stealthRock, .reflect, .lightScreen, .auroraVeil, .safeguard, .mist, .luckyChant,
             .tailwind, .wideGuard, .quickGuard, .matBlock, .craftyShield: return false
        }
    }

    /// 편 전체를 지키는 방어기인가. 참이면 **개인 방어와 같은 규칙**을 탄다: 연속으로 쓰면
    /// 실패 확률이 붙고(같은 카운터를 쓴다), 막는 판정은 대상 단위 입구에서 본다.
    var guardsTheTeam: Bool {
        switch self {
        case .wideGuard, .quickGuard, .matBlock, .craftyShield: return true
        case .reflect, .lightScreen, .auroraVeil, .safeguard, .mist, .luckyChant, .tailwind,
             .stickyWeb, .stealthRock, .spikes, .toxicSpikes:   return false
        }
    }

    /// 이 기술을 막는가 — 넷이 갈리는 것은 **무엇을 막느냐**뿐이다.
    ///
    /// 니가하지마는 본가에서 "나온 첫 턴에만" 쓸 수 있는데 그 게이트가 엔진에 없다
    /// (속임수와 같은 자리 — `MoveSpec.flinchChanceCap` 의 설명 참조). 게이트 대신 지속 턴 1 과
    /// 연속 실패 확률이 남아 있어, 매 턴 눌러도 개인 방어보다 세지지는 않는다.
    func blocks(_ move: MoveSpec) -> Bool {
        switch self {
        case .wideGuard:    return move.hitsSpread
        case .quickGuard:   return move.turnPriority > 0
        case .matBlock:     return move.damageClass != .status
        case .craftyShield: return move.damageClass == .status
        case .reflect, .lightScreen, .auroraVeil, .safeguard, .mist, .luckyChant, .tailwind,
             .stickyWeb, .stealthRock, .spikes, .toxicSpikes: return false
        }
    }

    init?(showdownKey: String) {
        switch showdownKey.lowercased() {
        case "reflect":     self = .reflect
        case "lightscreen": self = .lightScreen
        case "auroraveil":  self = .auroraVeil
        case "safeguard":   self = .safeguard
        case "mist":        self = .mist
        case "luckychant":  self = .luckyChant
        case "tailwind":     self = .tailwind
        case "wideguard":    self = .wideGuard
        case "quickguard":   self = .quickGuard
        case "matblock":     self = .matBlock
        case "craftyshield": self = .craftyShield
        case "stickyweb":    self = .stickyWeb
        case "stealthrock":  self = .stealthRock
        case "spikes":       self = .spikes
        case "toxicspikes":  self = .toxicSpikes
        default:             return nil
        }
    }

    /// 이 상태를 까는 기술인가 — 날씨·필드와 같은 자리에서 데이터가 답한다.
    static func called(byMoveID id: Int) -> BattleSideCondition? {
        ShowdownMoveData.effects[id]?.sideCondition.flatMap(BattleSideCondition.init(showdownKey:))
    }

    /// 이 기술이 상태를 **상대 편에** 까는가 — 압정 부류가 그렇다.
    ///
    /// 열거형이 아니라 **기술**에 묻는 이유는 같은 상태를 양쪽에 까는 기술이 생길 수 있어서다
    /// (쇼다운도 상태가 아니라 기술마다 `sideConditionTarget` 을 든다). 엔진이 열거형에서 편을
    /// 파생하면 그 순간 데이터를 두 번 적는 셈이 되고, 한쪽만 바뀌면 조용히 어긋난다.
    /// 이 대응이 데이터와 맞는지는 `ShowdownEffectTableTests` 가 확인한다.
    static func landsOnFoeSide(moveID id: Int) -> Bool {
        ShowdownMoveData.effects[id]?.sideConditionTarget == "foeSide"
    }

    /// 이 분류의 데미지를 반으로 깎는가. 오로라베일은 둘 다 깎는 대신 눈이 있어야 깔린다.
    func halves(_ damageClass: MoveDamageClass) -> Bool {
        switch self {
        case .reflect:     return damageClass == .physical
        case .lightScreen: return damageClass == .special
        case .auroraVeil:  return damageClass != .status
        case .safeguard, .mist, .luckyChant, .tailwind,
             .wideGuard, .quickGuard, .matBlock, .craftyShield,
             .stickyWeb, .stealthRock, .spikes, .toxicSpikes: return false
        }
    }
}

/// 이번 턴 자기를 지키는 기술(방어·잠깨기·니들가드 부류).
///
/// **왜 열거형이 아닌가.** 쇼다운은 여덟 개의 volatile 키로 갈라 두지만(`protect`·`kingsshield`·
/// `spikyshield`·`banefulbunker`·`burningbulwark`·`silktrap`·`obstruct`·`maxguard`) 갈리는 것은
/// **막은 뒤에 상대에게 무엇을 하나**뿐이다. 그 부가 효과는 접촉 판정(`flags.contact`)이 있어야
/// 하고 엔진에 아직 없다 — 그래서 지금은 **막는 일만** 여덟이 똑같이 한다. 접촉이 들어오면
/// 여기가 열거형이 되고 키마다 갈래가 붙는다(그 전에 미리 갈라 두면 아무도 밟지 않는 갈래다).
enum BattleGuard {
    /// 막는 일을 부르는 쇼다운 키. 이 키를 쓰는 기술이 늘면(9세대 실크트랩처럼) 자동으로 따라온다.
    static let showdownKeys: Set<String> = [
        "protect", "kingsshield", "spikyshield", "banefulbunker",
        "burningbulwark", "silktrap", "obstruct", "maxguard",
    ]

    /// 연속으로 쓰면 실패하기 쉬워진다 — 성공 확률 1/3^(연속 성공 횟수). 안 두면 방어를 매 턴
    /// 눌러 무적이 된다(CPU 도 무작위로 고르므로 실제로 그렇게 된다).
    static let consecutiveFailureBase = 3

    /// 이 기술이 방어기인가 — 날씨·필드·진영 상태와 같은 자리에서 데이터가 답한다.
    static func called(byMoveID id: Int) -> Bool {
        guard let key = ShowdownMoveData.effects[id]?.volatileStatus else { return false }
        return showdownKeys.contains(key)
    }

    /// 방어를 **뚫는** 기술인가(페인트·섀도다이브·울부짖기). 규칙이 "거의 다 막힌다" 라서
    /// 데이터가 예외만 들고 있다 — 막히는 목록을 손으로 들면 조용히 낡는다.
    static func isIgnored(byMoveID id: Int) -> Bool { ShowdownMoveData.ignoringGuard.contains(id) }
}

/// 이 칸을 못 쓰게 만든 것 — `BattleSide.selectionLock(forMoveAt:)` 이 답한다.
///
/// **`BattleVolatile` 을 그대로 쓰지 않는 이유는 구애 아이템이다**: 원인 하나가 volatile 이 아니라
/// 지닌물건이라 그 열거형에 담기지 않는다. 그리고 화면이 필요한 것은 상태 이름이 아니라 "왜 못
/// 누르나" 한 줄이라, 막는 이유만 든 작은 열거형이 그 질문에 정확히 답한다.
enum MoveSelectionLock: String, Codable, Sendable, Equatable, CaseIterable {
    case disable, encore, taunt, torment, imprison, healBlock, choiceItem, assaultVest

    /// 선택이 **끝난 뒤에도** 이 잠금이 기술을 막는가 — 걸린 순간이 상대 행동 뒤라서 이번 턴의
    /// 선택을 이미 마친 개체가 생긴다(도발을 건 쪽이 먼저 움직이는 순서).
    ///
    /// **부류마다 갈리는 값이라 하나로 접지 않는다.** 쇼다운 `moves.ts` 기준으로 씨앙코르·도발·
    /// 봉인·비밀의힘은 `onBeforeMove` 에서 `cant` 를 찍어 그 턴 행동을 막고, 트집·앙코르는
    /// `onDisableMove` 만 들어 선택만 막는다(앙코르는 대신 그 턴 행동을 앙코르 기술로 **바꾼다** —
    /// 여기서는 바꾸지 않는다). 넷을 다 막으면 본가보다 세지고, 넷을 다 안 막으면 도발이 한 턴
    /// 늦게 듣는다.
    ///
    /// 구애가 빠지는 것은 사유가 다르다: 잠금이 **자기 기술이 나가는 순간** 걸리므로
    /// (`BattleEngine.beginAttack`), 자기 선택과 자기 실행 사이에서 값이 달라질 수 없다.
    var blocksExecution: Bool {
        switch self {
        case .disable, .taunt, .imprison, .healBlock: return true
        // 돌격조끼가 구애와 같은 자리에 서는 이유도 같다: 막는 것이 자기 물건이라 선택과 실행
        // 사이에서 값이 달라질 수 없다.
        case .encore, .torment, .choiceItem, .assaultVest: return false
        }
    }
}

/// 개체에 붙어 **턴을 넘어 사는** 상태 — 조이기·저주·나이트메어·아쿠아링·뿌리박기.
///
/// 주 상태이상(`Status`)과 세 가지가 다르다: 여러 개가 동시에 붙고(그래서 `BattleSide` 가 표로
/// 든다), 잔뎀·회복이 `BattleEngine.endOfTurnResidual` 한 자리에 얹히고, 교체하면 전부 사라진다.
///
/// **교체 금지는 아직 없다.** 본가의 조이기·뿌리박기는 물러나는 것 자체를 막지만, 교체 게이트는
/// 네 모드와 터미널 UI 에 흩어져 있어 상태 하나로 막을 수 없다. 아무도 읽지 않는 필드를 미리 두지
/// 않는 것이 이 파일의 규칙이라, 막는 자리를 만들 때 같이 넣는다.
enum BattleVolatile: String, Codable, Sendable, Equatable, CaseIterable {
    /// **나열 순서가 곧 턴 끝 처리 순서다** — 회복 둘이 먼저, 그다음 깎는 셋이다. 훑는 쪽이
    /// `allCases` 를 쓰므로 딕셔너리 순회 순서가 이벤트에 남지 않는다(두 피어의 로그가 갈리지 않는다).
    case aquaRing, ingrain, leechSeed, nightmare, curse, partiallyTrapped
    /// 뒤 다섯은 턴 끝에 HP 를 만지지 않는다 — 배율만 얹는다(급소 단계·회피·위력). 그래서 위
    /// 순서 규칙과 부딪히지 않고 뒤에 붙는다. 충전·레이저포커스만 턴을 세고, 나머지 셋은
    /// 교체할 때까지 산다.
    case focusEnergy, laserFocus, minimize, defenseCurl, charge
    /// 마지막 셋은 **쓰러지는 순간**에만 답한다(버틴다·같이 데려간다·PP 를 앗는다). 턴 끝에는
    /// HP 도 배율도 만지지 않으므로 위 순서 규칙과 부딪히지 않고 뒤에 붙는다. 인내만 한 턴짜리고,
    /// 운명공동체·원한은 **주인이 다음 기술을 낼 때** 풀린다(`endsOnNextMove`).
    case endure, destinyBond, grudge
    /// 대타출동은 **HP 를 든 층**이라 이 표에 남은 턴을 세지 않는다(값은 늘 0 = 무기한). 층의 HP 는
    /// `BattleSide.substituteHP` 한 곳에 있고, 붙는 것과 HP 를 **함께** 만지는 자리는
    /// `BattleSide.raiseSubstitute()`·`absorbIntoSubstitute(_:)` 둘뿐이다 — 한쪽만 만지면
    /// "인형은 없는데 HP 가 남았다" 가 되고, 그 개체는 다음 공격을 이유 없이 흘린다.
    case substitute
    /// 다인전 타겟 유도 셋 — 이번 턴 상대의 단일 타겟 공격을 자기(스포트라이트는 지목한 자리)로
    /// 끌어온다. **한 케이스로 접지 않는 이유는 성원의 가루다**: 풀 타입은 가루를 무시하므로
    /// 어느 기술이 걸었는지가 판정을 가른다(하나로 접으면 그 예외를 물을 자리가 없다).
    case followMe, ragePowder, spotlight
    /// 도우미 — **아군에게** 붙어 그 아군의 이번 턴 기술 위력을 1.5 배로 만든다. 유도 셋과 같은
    /// 다인전 전용이지만 하는 일이 다르다: 대상을 옮기는 게 아니라 위력을 얹는다.
    case helpingHand
    /// 기술 **선택**을 막는 여섯. 위 상태들과 갈리는 점은 막는 자리다 — 데미지 경로가 아니라
    /// 선택 경로(`BattleSide.selectionLock(forMoveAt:)`)에서 답한다. 그래서 이 여섯은 아래 축
    /// (잔뎀·회복·급소·유도)에 하나도 답하지 않고, 대신 어느 칸을 막는지를 곁의 값이 든다:
    /// 씨앙코르는 `disabledMoveID`, 앙코르는 `encoredMoveID`, 봉인은 `imprisonedMoveIDs` 다
    /// (도발·트집·비밀의힘은 규칙만으로 정해져 곁의 값이 없다).
    ///
    /// **봉인이 걸리는 쪽이 본가와 다르다.** 본가는 쓴 쪽에 붙어 상대를 막고 쓴 쪽이 물러나면
    /// 풀리지만, 여기서는 **막히는 쪽**에 붙는다(겹치는 기술 id 를 그 자리에 적어 둔다). 선택
    /// 판정을 개체 하나만 보고 답하게 두려는 선택이다 — 판정에 상대편을 끌어들이면 네 모드와
    /// 터미널이 각자 상대를 찾아 넘겨야 하고, 한 자리만 빠뜨려도 그 모드에서만 봉인이 없다.
    /// 대가는 걸어 둔 쪽이 쓰러진 뒤에도 남는다는 것이고, 막히는 쪽이 교체하면 풀린다.
    case disable, encore, taunt, torment, imprison, healBlock

    /// 이 상태가 막는 선택 잠금 — 안 막으면 nil. 두 열거형이 **같은 case 이름**을 쓰므로 이름으로
    /// 잇는다. 목록을 손으로 적으면 새 잠금이 늘 때 한쪽만 남는다.
    var selectionLock: MoveSelectionLock? { MoveSelectionLock(rawValue: rawValue) }

    /// 쇼다운이 쓰는 키 → 이 열거형. 모르는 키는 `nil` 이고, 그 키가 미구현인 사유는
    /// `ShowdownEffectTableTests` 가 동결한다.
    init?(showdownKey: String) {
        switch showdownKey.lowercased() {
        case "aquaring":         self = .aquaRing
        case "ingrain":          self = .ingrain
        case "leechseed":        self = .leechSeed
        case "nightmare":        self = .nightmare
        case "curse":            self = .curse
        case "partiallytrapped": self = .partiallyTrapped
        case "focusenergy":      self = .focusEnergy
        case "laserfocus":       self = .laserFocus
        case "minimize":         self = .minimize
        case "defensecurl":      self = .defenseCurl
        case "charge":           self = .charge
        case "endure":           self = .endure
        case "destinybond":      self = .destinyBond
        case "grudge":           self = .grudge
        case "substitute":       self = .substitute
        case "followme":         self = .followMe
        case "ragepowder":       self = .ragePowder
        case "spotlight":        self = .spotlight
        case "helpinghand":      self = .helpingHand
        case "disable":          self = .disable
        case "encore":           self = .encore
        case "taunt":            self = .taunt
        case "torment":          self = .torment
        case "imprison":         self = .imprison
        case "healblock":        self = .healBlock
        default:                 return nil
        }
    }

    /// 이 상태를 부르는 기술인가 — 날씨·필드·진영 상태와 같은 자리에서 데이터가 답한다.
    /// 조이기만 열 기술이 같은 키를 부르므로, 손 목록이면 새 기술 하나가 조용히 빠진다.
    static func called(byMoveID id: Int) -> BattleVolatile? {
        ShowdownMoveData.effects[id]?.volatileStatus.flatMap(BattleVolatile.init(showdownKey:))
    }

    /// 자기에게 거는가 — 대상이 갈리면 `applyAttack` 이 상대를 볼지 말지가 갈린다.
    ///
    /// 배율만 얹는 다섯(기합충전·레이저포커스·작아지기·방어태세·충전)도 자기에게 건다 — 랭크가
    /// 함께 오르는 셋(작아지기·방어태세·충전)이 있어서, 그 갈래는 랭크도 같이 움직여야 한다.
    var targetsUser: Bool {
        switch self {
        case .aquaRing, .ingrain, .focusEnergy, .laserFocus, .minimize, .defenseCurl, .charge,
             .endure, .destinyBond, .grudge, .substitute, .followMe, .ragePowder:
            return true
        // 스포트라이트만 **남을 지목한다** — 지목된 자리가 이번 턴의 공격을 받는다.
        // 선택을 막는 여섯은 전부 상대에게 건다 — 봉인도 그렇다(위 case 주석의 사유).
        case .leechSeed, .nightmare, .curse, .partiallyTrapped, .spotlight, .helpingHand,
             .disable, .encore, .taunt, .torment, .imprison, .healBlock:
            return false
        }
    }

    /// 자기에게 걸었을 때 사는 턴 — 0 은 무기한(교체할 때까지)이다.
    ///
    /// 충전과 레이저포커스만 턴을 센다(쇼다운도 둘만 `duration` 을 둔다). **2 여야 한다**: 건 턴의
    /// 끝에 1 로 줄고 다음 턴 끝에 풀리므로, 노리던 "다음 턴 한 방"에만 배율이 살아 있다. 1 로
    /// 두면 건 턴 끝에 풀려 아무 기술도 못 받고, 0(무기한)으로 두면 충전이 전기 기술을 영구히
    /// 두 배로 만든다.
    var selfDuration: Int {
        switch self {
        case .charge, .laserFocus: return 2
        // 인내는 **쓴 턴에만** 산다 — 1 이면 그 턴 끝에 풀린다. 운명공동체·원한은 턴이 아니라
        // 주인의 다음 행동까지 살아야 하므로 0(무기한)이고, 푸는 자리는 `beginAttack` 이다.
        // 유도 셋도 그 턴만 산다 — 무기한이면 한 번 쓴 자리가 배틀 내내 모든 공격을 받는다.
        case .endure, .followMe, .ragePowder, .spotlight, .helpingHand: return 1
        case .aquaRing, .ingrain, .focusEnergy, .minimize, .defenseCurl,
             .leechSeed, .nightmare, .curse, .partiallyTrapped,
             .destinyBond, .grudge, .substitute: return 0
        // 선택을 막는 여섯은 자기에게 걸지 않는다 — 기간은 `foeDuration` 이 답한다.
        case .disable, .encore, .taunt, .torment, .imprison, .healBlock: return 0
        }
    }

    /// 이 상태가 얹는 급소 단계. 레이저포커스는 3 을 얹어 표의 상한(100%)에 닿는다 —
    /// "확정 급소" 를 따로 표현하지 않는 이유가 그것이다(`critThreshold` 가 이미 잠근다).
    /// 행운의부적은 결과만 막으므로 여기서 볼 필요가 없다.
    var critStages: Int {
        switch self {
        case .focusEnergy: return 2
        case .laserFocus:  return 3
        case .minimize, .defenseCurl, .charge, .aquaRing, .ingrain,
             .leechSeed, .nightmare, .curse, .partiallyTrapped,
             .endure, .destinyBond, .grudge, .substitute,
             .followMe, .ragePowder, .spotlight, .helpingHand,
             .disable, .encore, .taunt, .torment, .imprison, .healBlock: return 0
        }
    }

    /// 턴 끝에 회복하는 최대 HP 분모. 깎는 쪽과 한 축에 두지 않는 이유는 순서다 — 회복이 먼저다.
    ///
    /// **`targetsUser` 로 답하지 않는다.** 자기에게 거는 volatile 이 회복하는 부류(아쿠아링·
    /// 뿌리박기)와 배율만 얹는 부류로 갈렸으므로, 그 축으로 물으면 기합충전이 매 턴 1/16 을
    /// 회복하는 기술이 된다.
    var healDivisor: Int? {
        switch self {
        case .aquaRing, .ingrain: return 16
        case .leechSeed, .nightmare, .curse, .partiallyTrapped,
             .focusEnergy, .laserFocus, .minimize, .defenseCurl, .charge,
             .endure, .destinyBond, .grudge, .substitute,
             .followMe, .ragePowder, .spotlight, .helpingHand,
             .disable, .encore, .taunt, .torment, .imprison, .healBlock: return nil
        }
    }

    /// 턴 끝에 깎는 최대 HP 분모와 로그에 남는 원인.
    /// **씨뿌리기는 여기서 답하지 않는다**(`nil`) — 깎은 만큼 뿌린 쪽이 회복하므로 개체 하나만
    /// 만지는 이 자리에서 처리할 수 없다. 그 몫은 `BattleEngine.endOfTurnLeechSeed` 가 맡는다.
    var residualDamage: (divisor: Int, cause: DamageCause)? {
        switch self {
        case .nightmare:                     return (4, .nightmare)
        case .curse:                         return (4, .curse)
        case .partiallyTrapped:              return (8, .trap)
        case .aquaRing, .ingrain, .leechSeed,
             .focusEnergy, .laserFocus, .minimize, .defenseCurl, .charge,
             .endure, .destinyBond, .grudge, .substitute,
             .followMe, .ragePowder, .spotlight, .helpingHand,
             .disable, .encore, .taunt, .torment, .imprison, .healBlock: return nil
        }
    }

    /// 주인이 **다음 기술을 낼 때** 풀리는가 — 턴이 아니라 행동을 세는 부류다.
    ///
    /// 운명공동체·원한은 본가에서 "다음 행동까지" 산다. 턴 끝(`selfDuration`)으로 재면 느린 쪽이
    /// 건 운명공동체가 다음 턴의 선공에 아무 일도 하지 않고, 무기한으로 두면 한 번 건 것이 배틀
    /// 내내 산다. 그래서 푸는 자리가 `BattleEngine.beginAttack`(주인이 실제로 움직인 순간)이다.
    var endsOnNextMove: Bool {
        switch self {
        case .destinyBond, .grudge: return true
        case .endure, .aquaRing, .ingrain, .leechSeed, .nightmare, .curse, .partiallyTrapped,
             .focusEnergy, .laserFocus, .minimize, .defenseCurl, .charge, .substitute,
             .followMe, .ragePowder, .spotlight, .helpingHand,
             .disable, .encore, .taunt, .torment, .imprison, .healBlock: return false
        }
    }

    /// 방어기와 **연속 실패 카운터를 공유하는가**(인내 하나다). 따로 두면 방어와 인내를 번갈아
    /// 눌러 벌점 없이 매 턴 살아남는다 — 본가도 같은 카운터를 쓴다.
    var sharesGuardStreak: Bool {
        switch self {
        case .endure: return true
        case .destinyBond, .grudge, .aquaRing, .ingrain, .leechSeed, .nightmare, .curse,
             .partiallyTrapped, .focusEnergy, .laserFocus, .minimize, .defenseCurl, .charge,
             .substitute, .followMe, .ragePowder, .spotlight, .helpingHand,
             .disable, .encore, .taunt, .torment, .imprison, .healBlock:
            return false
        }
    }

    /// 이번 턴 **상대의 단일 타겟 공격을 이 자리로 끌어오는가**(따라와·성원·스포트라이트).
    ///
    /// 필드에 넷이 서는 모드(웨이브 런·방)에서만 값을 가진다 — 1대1 은 끌어올 상대가 하나뿐이라
    /// 이 축을 물어도 답이 달라지지 않는다.
    var drawsAttacks: Bool {
        switch self {
        case .followMe, .ragePowder, .spotlight: return true
        case .substitute, .endure, .destinyBond, .grudge, .aquaRing, .ingrain, .leechSeed,
             .nightmare, .curse, .partiallyTrapped, .focusEnergy, .laserFocus, .minimize,
             .defenseCurl, .charge, .helpingHand,
             .disable, .encore, .taunt, .torment, .imprison, .healBlock:
            return false
        }
    }

    /// 풀 타입이 **무시하는** 유도인가 — 성원 하나다(가루를 뿌리는 기술이라 본가도 풀 타입에게
    /// 통하지 않는다). 따라와·스포트라이트는 가루가 아니므로 타입을 가리지 않는다.
    var ignoredByGrassTypes: Bool {
        switch self {
        case .ragePowder: return true
        case .followMe, .spotlight, .substitute, .endure, .destinyBond, .grudge, .aquaRing,
             .ingrain, .leechSeed, .nightmare, .curse, .partiallyTrapped, .focusEnergy,
             .laserFocus, .minimize, .defenseCurl, .charge, .helpingHand,
             .disable, .encore, .taunt, .torment, .imprison, .healBlock:
            return false
        }
    }

    /// 유도가 겹쳤을 때 이기는 순서 — 스포트라이트가 따라와·성원보다 세다(쇼다운의
    /// `onFoeRedirectTargetPriority` 와 같은 값). 같은 값끼리는 호출부가 준 자리 순서로 정한다 —
    /// 무작위로 고르면 같은 seed 의 판이 재현되지 않는다.
    var drawPriority: Int {
        switch self {
        case .spotlight:            return 2
        case .followMe, .ragePowder: return 1
        case .substitute, .endure, .destinyBond, .grudge, .aquaRing, .ingrain, .leechSeed,
             .nightmare, .curse, .partiallyTrapped, .focusEnergy, .laserFocus, .minimize,
             .defenseCurl, .charge, .helpingHand,
             .disable, .encore, .taunt, .torment, .imprison, .healBlock:
            return 0
        }
    }

    /// **상대에게** 걸었을 때 사는 턴 — 0 은 무기한(그 개체가 교체할 때까지)이다.
    /// 자기에게 거는 부류의 기간(`selfDuration`)과 자리를 나눈 이유는 값이 다른 부류라서다:
    /// 도발 3턴·씨앙코르 4턴·앙코르 3턴·비밀의힘 5턴은 걸린 쪽에서 세고, 트집·봉인은 안 센다.
    ///
    /// 조이기만 여기서 답하지 않는다(`nil` 이 아니라 0) — 4~5턴을 난수로 뽑으므로 호출부
    /// (`BattleEngine.applyVolatile`)가 그 하나만 따로 굴린다.
    var foeDuration: Int {
        switch self {
        case .taunt:     return 3
        case .disable:   return 4
        case .encore:    return 3
        case .healBlock: return 5
        // 트집·봉인은 걸린 개체가 교체할 때까지 산다(본가의 트집과 같다).
        case .torment, .imprison: return 0
        case .leechSeed, .nightmare, .curse, .partiallyTrapped, .spotlight, .helpingHand,
             .aquaRing, .ingrain, .focusEnergy, .laserFocus, .minimize, .defenseCurl, .charge,
             .endure, .destinyBond, .grudge, .substitute, .followMe, .ragePowder:
            return 0
        }
    }

    /// 씨뿌리기가 빨아내는 최대 HP 분모.
    static let leechSeedDivisor = 8

    /// 조이기가 깎는 턴 수 — 4~5턴(본가와 같다). 난수로 뽑는 유일한 기간이라 여기 상수로 둔다
    /// (충전·레이저포커스의 기간은 고정값이라 `selfDuration` 이 답한다).
    static let trapTurnFloor = 4
    static let trapTurnSpread: UInt64 = 2
}

/// 판 전체에 걸린 것 — 날씨와 필드.
///
/// **왜 인자로 나르는가.** 배틀 상태를 들고 있는 타입이 넷(1v1 LAN·연습·웨이브·방)이라, 엔진이
/// 전역으로 들면 모드끼리 날씨가 새어 든다. 인자라서 빠뜨릴 수 있다는 위험은
/// `BattleFieldGuardTests` 가 소스에서 막는다(`beginTurn` 을 지키는 방식과 같다).
struct BattleField: Sendable, Equatable {
    var weather: BattleWeather?
    /// 남은 턴 — 0 이면 날씨가 없다.
    var weatherTurns = 0
    var terrain: BattleTerrain?
    var terrainTurns = 0
    /// 편별로 깔린 상태와 그 숫자. 없는 키는 "안 깔렸다" 이므로 0 짜리 항목을 남기지 않는다 —
    /// 그래야 `has` 한 번으로 읽히고, 두 피어가 같은 순서로 훑는다(`allCases` 순).
    ///
    /// **숫자의 뜻이 부류마다 다르다**: 턴을 세는 상태는 남은 턴이고, 입장 데미지
    /// (`BattleSideCondition.isEntryHazard`)는 쌓인 **층 수**다(걷히지 않으므로 셀 턴이 없다).
    /// 자리를 나누지 않는 이유는 읽는 쪽이다 — `has`·순회·와이어가 한 벌이어야 새 부류가
    /// 그 셋 중 하나에서만 빠지는 일이 없다. 읽을 때는 `layers(_:for:)` 로 뜻을 밝힌다.
    var sideConditions: [BattleTeamSlot: [BattleSideCondition: Int]] = [:]

    func has(_ condition: BattleSideCondition, for team: BattleTeamSlot) -> Bool {
        (sideConditions[team]?[condition] ?? 0) > 0
    }

    /// 쌓인 층 수 — 입장 데미지만 1 보다 클 수 있다. 안 깔렸으면 0 이다.
    func layers(_ condition: BattleSideCondition, for team: BattleTeamSlot) -> Int {
        sideConditions[team]?[condition] ?? 0
    }

    /// 진영 상태를 깐다. 이미 깔려 있으면 **실패한다**(날씨와 같은 이유 — 매 턴 다시 깔면 영구다).
    /// 오로라베일은 눈이 내릴 때만 깔린다.
    ///
    /// 입장 데미지만 다시 깔 수 있다 — **층 상한까지**다(`maxLayers`). 상한 위는 다른 상태와 같이
    /// 실패라, 매 턴 다시 깔아도 교체 즉사가 되지 않는다.
    /// - Parameter turns: 지속 턴. `nil` 이면 이 상태의 정해진 길이고, 빛의점토를 쥔 쪽이 장막을
    ///   깔면 늘어난 값이 온다. **입장 데미지는 이 값을 안 본다** — 저장하는 숫자가 턴이 아니라
    ///   층이라, 늘려 봐야 층이 8 이 된다.
    mutating func start(_ condition: BattleSideCondition, for team: BattleTeamSlot,
                        turns: Int? = nil) -> Bool {
        guard condition != .auroraVeil || weather == .snow else { return false }
        let current = layers(condition, for: team)
        guard current < (condition.isEntryHazard ? condition.maxLayers : 1) else { return false }
        sideConditions[team, default: [:]][condition] =
            condition.isEntryHazard ? current + 1 : (turns ?? condition.duration)
        return true
    }

    /// 이 진영이 맞는 데미지가 장막에 반으로 깎이는가.
    func halvesDamage(_ damageClass: MoveDamageClass, against team: BattleTeamSlot) -> Bool {
        BattleSideCondition.allCases.contains { $0.halves(damageClass) && has($0, for: team) }
    }

    /// 편 방어기(와이드가드 부류)가 이 기술을 막는가. 넷 중 하나라도 막으면 막힌다.
    func blocksMove(_ move: MoveSpec, against team: BattleTeamSlot) -> Bool {
        BattleSideCondition.allCases.contains { $0.guardsTheTeam && $0.blocks(move) && has($0, for: team) }
    }

    /// 신비의부적 — 이 진영은 상대가 거는 상태이상을 받지 않는다.
    func blocksStatus(against team: BattleTeamSlot) -> Bool { has(.safeguard, for: team) }

    /// 하얀안개 — 이 진영은 상대가 내리는 랭크를 받지 않는다(자기 상승은 그대로다).
    func blocksStatDrop(against team: BattleTeamSlot) -> Bool { has(.mist, for: team) }

    /// 행운의부적 — 이 진영은 급소를 맞지 않는다.
    func blocksCrit(against team: BattleTeamSlot) -> Bool { has(.luckyChant, for: team) }

    /// 필드를 깐다. 같은 필드를 다시 깔면 실패한다(날씨와 같은 이유).
    /// - Parameter turns: 지속 턴. 기본은 이 상태의 정해진 길이고, 지닌물건(그라운드코트)이
    ///   늘리면 **거는 쪽이** 그 값을 넘긴다. 판이 아니라 부르는 쪽이 정하는 이유는 판이 누가
    ///   걸었는지를 안 들고 있어서다.
    mutating func start(_ terrain: BattleTerrain, turns: Int = BattleTerrain.duration) -> Bool {
        guard self.terrain != terrain else { return false }
        self.terrain = terrain
        terrainTurns = turns
        return true
    }

    /// 이 개체가 땅에 닿아 있는가 — 필드 효과는 닿은 쪽에만 걸린다.
    /// 비행 타입과 부유 특성이 뜬 쪽이다(공중에 뜨는 기술은 엔진에 없다).
    static func isGrounded(_ side: BattleSide) -> Bool {
        // 물건이 발을 옮긴다 — 검은철구는 뜬 개체를 내려놓고 풍선은 닿은 개체를 띄운다. 땅 기술
        // 면역(`BattleEngine.typeMultiplier`)과 **같은 축**(`groundContact`)을 봐야 "지진은 맞는데
        // 그래스필드는 안 받는" 반쪽 접지가 안 생긴다.
        if let contact = side.heldEffect?.groundContact { return contact == .grounded }
        return !side.activeTypes.contains(.flying) && side.ability != .levitate
    }

    /// 날씨를 건다. 같은 날씨를 다시 걸면 **실패한다**(본가와 같다) — 턴이 연장되면 한쪽이
    /// 매 턴 다시 걸어 영구 날씨가 된다.
    /// - Parameter turns: 필드와 같은 규칙이다 — 날씨 돌을 쥔 쪽이 걸면 늘어난 값이 온다.
    mutating func start(_ weather: BattleWeather, turns: Int = BattleWeather.duration) -> Bool {
        guard self.weather != weather else { return false }
        self.weather = weather
        weatherTurns = turns
        return true
    }
}

// MARK: - 배틀 중 한쪽의 상태

/// 대전 중 한쪽이 들고 있는 것 전부 — 스냅샷은 *교환 단위*고, 이쪽은 **턴을 넘어 사는 상태**다.
/// 세 모드(`NetBattleState`·`TeamPracticeBattle`·`MultiplayerFighter`)가 각자 `hp`/`pp` 를 나열하던
/// 자리다. 상태를 한 타입에 모아야 상태이상·랭크업 같은 기전을 세 번 쓰지 않는다.
/// 한 번 맞은 기록 — 되돌려주는 기술이 얼마를 어떤 분류로 맞았는지 알아야 한다.
/// 카운터는 물리만, 미러코트는 특수만, 메탈버스트는 둘 다 되돌려준다.
struct IncomingHit: Sendable, Equatable {
    var amount: Int
    var damageClass: MoveDamageClass
}

struct BattleSide: Sendable, Equatable {
    var snapshot: BattleSnapshot
    /// 유효 스탯 — 배틀에 들어올 때 1회 계산한다. `effectiveStats()` 를 그때그때 부르면 정렬
    /// 비교자 안에서 비교 횟수만큼 다시 계산되고(멀티가 그랬다), 랭크업이 들어오는 순간
    /// "부스트 없는 원래 스피드로 정렬" 이라는 오답이 된다.
    let stats: BattleStats
    var hp: Int
    /// 이 배틀에서 쓸 무브셋 — 스냅샷에 없으면(구버전 세이브·fetch 실패) 합성 무브셋.
    /// 세 모드가 각자 `snapshot.moves ?? fallbackSet(...)` 를 반복하던 자리다.
    let moves: [MoveSpec]
    var pp: [Int]
    /// **이번 턴에** 기술로 맞은 데미지 — 카운터·미러코트·메탈버스트가 되돌려준다.
    ///
    /// 턴이 시작될 때 `BattleEngine.beginTurn` 이 비운다. 안 비우면 지난 턴 데미지가 되돌아온다.
    /// 혼란 자멸·독·화상은 여기 안 들어간다 — `applyAttack` 의 기술 데미지 자리에서만 기록한다.
    ///
    /// `BattleSide` 는 `Codable` 이 아니라 와이어에 실리지 않는다. 두 피어가 각자 같은 규칙으로
    /// 채우므로 값이 오갈 필요가 없다(그래서 이 필드는 `rulesVersion` 만 올리면 된다).
    var lastHitThisTurn: IncomingHit?

    /// 주 상태이상 — 한 번에 하나. 혼란은 volatile 이라 여기가 아니라 `confusionTurns` 에 둔다.
    var status: Status?
    /// 상태마다 뜻이 다른 한 칸 — 맹독은 누적 배수(1, 2, 3…), 잠듦은 남은 카운터다.
    /// 주 상태가 하나뿐이라 두 값이 동시에 필요할 일이 없어 칸을 나누지 않는다.
    var statusCounter = 0
    /// 직전에 **낸** 기술과 연이어 낸 횟수 — 리프블레이드·구르기·에코보이스가 여기서 위력을 뽑는다.
    ///
    /// `lastHitThisTurn` 과 달리 **턴을 넘어 산다**. 끊기는 자리는 두 곳뿐이다: 다른 기술을 냈을
    /// 때(다시 1) 와 못 움직였을 때(0). `BattleEngine.beginAttack` 한 곳에서만 갱신한다 —
    /// 세 모드가 같은 함수를 지나므로 모드마다 카운터가 갈리지 않는다.
    var lastMoveID: Int?
    var consecutiveMoveUses = 0
    /// 이 배틀에서 **기술로** 맞은 횟수 — 원한의응보가 센다. 잔뎀·혼란 자멸은 세지 않는다
    /// (`lastHitThisTurn` 과 같은 자리에서 올린다). 다단기는 히트가 아니라 **기술 하나로** 센다 —
    /// 엔진이 다단기를 합계 한 번으로 적용하므로 히트마다 셀 자리가 없다.
    var timesHit = 0
    /// 직전에 낸 내 기술이 실패했나 — 분함의발구르기·역상승이 본다. 빗나감·무효·못 움직임이
    /// 전부 실패다(본가도 같다).
    var lastMoveFailed = false
    /// **이번 턴에** 행동을 썼나 — 리벤지가 상대의 이 값을 본다. 기술이 나갔는지가 아니라
    /// 행동을 소비했는지라, 마비·풀린치로 굳은 턴도 참이다(본가·쇼다운 모두 "이 턴에 더 움직이지
    /// 않는다" 로 판정한다). `lastHitThisTurn` 과 같은 자리(`beginTurn`)에서 비운다.
    var movedThisTurn = false
    /// **이번 턴에** 방어기가 성공했나 — 상대의 공격이 이 값을 보고 막힌다.
    /// `beginTurn` 에서 비우므로 다음 턴의 공격은 그대로 들어온다(방어는 한 턴짜리다).
    var isGuarding = false
    /// 방어기를 **연속으로 성공한 횟수** — 다음 방어의 성공 확률이 1/3^이 값이다.
    /// 턴을 넘어 살고, 방어가 아닌 기술을 냈거나 방어가 실패하면 0 으로 돌아간다
    /// (`consecutiveMoveUses` 와 달리 방어기끼리는 서로 다른 기술이어도 이어진다 — 본가와 같다).
    var guardStreak = 0
    /// 테라스탈했나 — **배틀당 한 번**이고 한 번 하면 안 풀린다(본가와 같다). 교체해도 그 개체는
    /// 계속 테라스탈 상태다. 한 번뿐이라는 제약은 진영 단위라 모드가 들고 있고
    /// (`TeamPracticeBattle.myTerastalUsed`), 이 값은 개체가 지금 그 상태인지만 말한다.
    ///
    /// `BattleSide` 는 `Codable` 이 아니라 와이어에 실리지 않는다 — 두 피어가 각자 같은 규칙으로
    /// 세운다(`lastHitThisTurn` 과 같은 이유).
    var isTerastallized = false
    /// 붙어 있는 volatile 과 **남은 턴**. 0 은 "턴을 세지 않는다"(교체하거나 조건이 깨질 때까지
    /// 남는다)는 뜻이고, 키가 없으면 안 붙은 것이다 — 진영 상태와 같은 규칙이라 0 턴짜리 항목을
    /// 남기지 않는다. 그래야 "하나도 안 붙었다" 가 `isEmpty` 한 번으로 읽힌다.
    ///
    /// `BattleSide` 는 `Codable` 이 아니라 와이어에 실리지 않는다 — 두 피어가 각자 같은 규칙으로
    /// 채운다(`isTerastallized` 와 같은 이유). 그래서 `rulesVersion` 만 올리면 된다.
    var volatiles: [BattleVolatile: Int] = [:]
    /// 씨뿌리기를 **누가** 걸었나 — 빨아낸 HP 를 받을 자리다. 개체가 아니라 **자리**(액터)를 들고
    /// 있어서, 뿌린 쪽이 교체돼도 그 자리에 선 개체가 받는다(본가와 같다).
    /// 자리를 배열의 몇 번째로 푸는 것은 모드의 일이다 — 모드마다 배열이 다르다.
    var leechSeedSource: BattleActor?
    /// 이 턴의 선공을 물건이 가져갔나 — 선제공격손톱·애슈열매다. 턴이 시작될 때
    /// `BattleEngine.rollTurnStartItems` 가 한 번 정하고, 순서를 재는 세 모드가 그 값을 읽는다.
    /// 굴리는 자리와 읽는 자리를 나눈 이유는 난수다: 정렬 비교 안에서 굴리면 소비 횟수가 비교
    /// 횟수에 딸려가 같은 seed 의 판이 재현되지 않는다(모드들의 tie-break 와 같은 함정).
    var actsFirstThisTurn = false
    /// 다음 기술 하나가 반드시 맞나 — 미클열매다. 쓴 기술이 명중 판정을 지나면 곧바로 꺼진다.
    var nextMoveNeverMisses = false
    /// 걸린 조이기의 잔뎀 분모 — 거는 쪽이 조임밴드를 쥐고 있었으면 그 값이 여기 남는다.
    /// 값이 없으면 기본 분모(`BattleVolatile.residualDamage`)다. 걸릴 때 정해지는 이유는 턴 끝이
    /// 개체 하나만 본다는 것이다 — 그 자리에서는 거는 쪽의 물건을 다시 물을 수 없다.
    var trapDamageDivisor: Int?
    /// 배틀 중에 **받아 쥔** 물건 — 지금은 접촉으로 옮겨 오는 끈적끈적바늘 하나다.
    ///
    /// 스냅샷을 고쳐 쓰지 않는 이유는 그것이 와이어의 값이라서다(`heldItemConsumed` 와 같은
    /// 판단이다). 그래서 "지금 무엇을 쥐고 있나" 를 묻는 자리는 `activeHeldItem` 하나다.
    var acquiredItem: ItemKind?
    /// 남은 혼란 턴 — 이 수만큼 자멸 판정을 굴린다.
    var confusionTurns = 0
    var flinched = false
    /// 랭크(−6…+6). 0 인 스탯은 **키를 두지 않는다** — 그래야 "랭크가 하나도 없다" 가
    /// `stages.isEmpty` 한 번으로 읽히고, 와이어 JSON 도 붙은 랭크만 나른다.
    var stages: [BattleStat: Int] = [:]
    /// 웨이브 런에서 쌓인 누적 강화({@link RunBoosts}). 채우는 것은 `RogueRun` 하나뿐이고,
    /// 네트워크 대전·체육관·모의전은 기본값(빈 값)으로 싸운다.
    ///
    /// **`rulesVersion` 을 올리지 않는 근거**: `BattleSide` 는 `Codable` 이 아니라 와이어에
    /// 실리지 않고, 비어 있으면 데미지도 rng 소비도 이 필드가 없던 때와 한 값도 다르지 않다.
    var runBoosts = RunBoosts()
    /// 지니고 있던 물건이 이 배틀에서 **일하고 소모됐나** — 기합의띠는 1회용이다.
    ///
    /// 스냅샷의 값을 지우지 않는 이유는 그것이 **와이어의 값**이라서다: 지우면 같은 스냅샷을
    /// 다시 쓰는 자리(재입장·정산)가 아이템 없는 개체를 보게 된다. 소모는 배틀 안에서만 산다 —
    /// 세이브의 재고는 배틀이 깎지 않는다(가방이 아이템을 잃는 유일한 자리는 `giveHeldItem` 이다).
    ///
    /// `BattleSide` 는 `Codable` 이 아니라 와이어에 실리지 않는다 — 두 피어가 각자 같은 규칙으로
    /// 세운다(`isTerastallized` 와 같은 이유).
    var heldItemConsumed = false
    /// 대타출동으로 세운 층의 남은 HP — 0 이면 층이 없다. `volatiles[.substitute]` 는 붙었는지만
    /// 말하고 값(남은 턴)은 늘 0 이라, **HP 의 정본은 이 한 칸이다**.
    ///
    /// 두 값을 함께 만지는 자리를 `raiseSubstitute()`·`absorbIntoSubstitute(_:)` 둘로 막아 둔다.
    /// 밖에서 따로 만지면 "인형은 없는데 HP 가 남았다"(공격을 이유 없이 흘린다)나 그 반대가 된다.
    ///
    /// `BattleSide` 는 `Codable` 이 아니라 와이어에 실리지 않는다 — 두 피어가 각자 같은 규칙으로
    /// 세운다(`isTerastallized` 와 같은 이유).
    var substituteHP = 0
    /// 씨앙코르가 막은 기술 id — `volatiles[.disable]` 은 남은 턴만 세고 **어느 칸인지는 이 값**이다.
    /// 층 HP 와 같은 부류의 짝이라 지우는 자리도 함께여야 한다(`BattleEngine.prepareForSwitch`).
    var disabledMoveID: Int?
    /// 앙코르가 남긴 기술 id — 이 하나만 낼 수 있다(막는 방향이 씨앙코르와 반대다).
    var encoredMoveID: Int?
    /// 봉인으로 막힌 기술 id — 걸어 둔 쪽과 겹치던 기술이다(`BattleVolatile.imprison` 주석의 사유로
    /// **막히는 쪽**이 든다).
    var imprisonedMoveIDs: Set<Int> = []
    /// 구애 아이템(구애머리띠·구애안경)이 묶어 둔 기술 id — 배틀에서 처음 낸 기술로 정해지고
    /// 교체할 때까지 그 하나만 낸다. volatile 이 아닌 이유는 원인이 지닌물건이라서다:
    /// 상대가 걸어 주는 것이 아니라 **자기 물건**이 묶으므로 붙는 순간(`beginAttack`)도 다르다.
    var choiceLockedMoveID: Int?

    init(_ snapshot: BattleSnapshot) {
        self.snapshot = snapshot
        stats = snapshot.effectiveStats()
        hp = stats.hp
        moves = snapshot.moves ?? MoveSpec.fallbackSet(types: snapshot.types)
        pp = moves.map(\.pp)
    }

    var isAlive: Bool { hp > 0 }
    var isConfused: Bool { confusionTurns > 0 }

    func has(_ volatileStatus: BattleVolatile) -> Bool { volatiles[volatileStatus] != nil }

    /// volatile 을 붙이고 **실제로 붙었는지**를 돌려준다. 이미 붙어 있으면 실패다(진영 상태·날씨와
    /// 같은 이유 — 매 턴 다시 걸면 아쿠아링이 실패 없는 무한 회복이 된다).
    /// `turns` 0 은 턴을 세지 않는다는 뜻이다.
    mutating func start(_ volatileStatus: BattleVolatile, turns: Int = 0) -> Bool {
        guard !has(volatileStatus) else { return false }
        volatiles[volatileStatus] = turns
        return true
    }

    /// 층이 서 있는가 — 데미지·상태·랭크가 주인에게 닿는지를 이 한 값이 가른다.
    var hasSubstitute: Bool { substituteHP > 0 }

    /// 층을 세운다. **값은 인형과 대가가 따로다**: 인형은 늘 최대 HP 의 1/4 이고, 내는 값만
    /// 기술마다 다르다(대타출동 1/4, 쉐도우테일 1/2 — `ShowdownMoveData.substituteCostDivisor`).
    ///
    /// 실패 조건은 본가와 같다: 이미 서 있거나, HP 가 대가 **이하**거나(치르면 그 자리에서
    /// 쓰러진다), 최대 HP 가 1 이다(누루프시 조항 — 1/4 이 0 이라 층이 서지 않는다).
    ///
    /// 쇼다운의 쉐도우테일은 대가를 올림으로 매기지만 여기는 내림이다 — 최대 HP 가 홀수일 때
    /// 1 만큼 싸다. 올림·내림을 데이터가 나르지 않아서고, 그 한 칸이 규칙을 뒤집지 않는다.
    mutating func raiseSubstitute(costDivisor: Int) -> Bool {
        let doll = stats.hp / 4
        let cost = stats.hp / max(1, costDivisor)
        guard !hasSubstitute, doll > 0, cost > 0, hp > cost else { return false }
        hp -= cost
        substituteHP = doll
        volatiles[.substitute] = 0
        return true
    }

    /// 층이 대신 맞는다 — **넘긴 데미지는 주인에게 넘어가지 않는다**(본가와 같다).
    /// 부서졌으면 `true` 다(호출부가 부서진 줄과 대신 맞은 줄을 가른다).
    mutating func absorbIntoSubstitute(_ damage: Int) -> Bool {
        substituteHP = max(0, substituteHP - damage)
        guard substituteHP == 0 else { return false }
        volatiles[.substitute] = nil
        return true
    }

    /// 지금 이 개체가 지닌물건에서 받는 효과 — 소모됐으면 `nil` 이다(없는 것과 같다).
    /// 읽는 자리를 하나로 두는 이유는 소모 조건이다: `snapshot.heldItem` 을 직접 보는 코드가
    /// 남으면 그 자리만 1회용 제약을 잃는다(기합의띠가 회복기 하나로 무적이 된다).
    /// 종 전용 물건(전기구슬 부류)의 **종 조건도 여기서** 본다 — 배율을 곱하는 자리마다 물으면
    /// 한 자리만 빠뜨렸을 때 그 배율만 아무에게나 붙는다.
    /// 지금 이 개체가 쥔 물건 — 배틀 중에 받아 쥔 것이 있으면 그것이다. 로그에 이름을 싣는
    /// 자리도 이것을 본다(스냅샷을 직접 보면 옮겨 온 바늘이 옛 이름으로 남는다).
    var activeHeldItem: ItemKind? { acquiredItem ?? snapshot.heldItem }

    var heldEffect: HeldItemEffect? {
        guard !heldItemConsumed, let effect = activeHeldItem?.heldBattleEffect else { return nil }
        if let species = effect.restrictedSpecies, !species.contains(snapshot.speciesID) { return nil }
        // 진화의휘석은 **모르면 안 붙는다** — 값이 없는 스냅샷(야생·CPU)에 붙이면 다 자란 개체가
        // 방어를 얻는다.
        if effect.requiresUnevolvedHolder, snapshot.canStillEvolve != true { return nil }
        return effect
    }

    /// 지금 이 개체의 체중(헥토그램) — 물건이 깎으면 깎인 값이다. 값이 없으면(조회 실패) 그대로
    /// `nil` 이라, 체중을 보는 기술은 예전처럼 실패한다(0 으로 접으면 "가장 가벼움" 이 된다).
    ///
    /// 체중을 보는 기술이 넷이라 읽는 자리를 하나로 둔다 — 기술마다 물건을 물으면 한 기술만
    /// 가벼운돌을 못 본다.
    var effectiveWeightHectograms: Int? {
        guard let weight = snapshot.weightHectograms else { return nil }
        guard let scale = heldEffect?.weightScale else { return weight }
        return max(1, weight * scale.numerator / scale.denominator)
    }

    /// 이 개체의 특성 — 스냅샷의 슬러그를 해석한 값. 모르는 슬러그는 `nil` 이라 특성이 없는 것과 같다.
    /// 해석은 사전 조회 한 번이라 턴마다 불러도 싸다(그래서 저장하지 않고 스냅샷 하나만 진실로 둔다).
    var ability: BattleAbility? { BattleAbility.resolve(snapshot.ability) }

    /// 이 스탯의 랭크. 없으면 0 이다.
    func stage(_ stat: BattleStat) -> Int { stages[stat] ?? 0 }

    /// 랭크를 움직이고 **실제로 적용된 양**을 돌려준다. ±6 에 닿아 있으면 0 이고, 호출부는 그
    /// 0 을 보고 이벤트를 내지 않는다 — "0 만큼 올랐다" 줄이 로그에 남으면 거짓말이다.
    @discardableResult
    mutating func changeStage(_ stat: BattleStat, by delta: Int) -> Int {
        let before = stage(stat)
        let after = StatStages.clamped(before + delta)
        if after == 0 { stages[stat] = nil } else { stages[stat] = after }
        return after - before
    }

    /// 교체하면 랭크는 전부 사라진다(본가와 같다). 남겨 두면 다시 나올 때 옛 랭크로 싸운다.
    mutating func resetStages() { stages = [:] }

    /// **지금** 이 개체의 타입 — 테라스탈하면 테라 타입 하나로 접힌다.
    ///
    /// 상성·STAB·부유 판정·모래 면역이 전부 이 값을 봐야 한다. `snapshot.types` 를 직접 읽는
    /// 자리가 남으면 그 규칙에서만 테라스탈이 없고, 화면에는 숫자만 다르게 보인다.
    var activeTypes: [PokemonType] { isTerastallized ? [snapshot.teraType] : snapshot.types }

    /// 랭크 **전**의 스탯. 명중·회피는 스탯이 아니라 랭크만 있는 축이라 기준값 100 이다.
    func rawStat(_ stat: BattleStat) -> Int {
        switch stat {
        case .atk: return stats.atk
        case .def: return stats.def
        case .spa: return stats.spa
        case .spd: return stats.spd
        case .spe: return stats.spe
        case .accuracy, .evasion: return 100
        }
    }

    /// **개체 몫**의 스피드 — 랭크를 먼저 곱하고, 마비면 그 뒤에 50%.
    /// `stats.spe` 를 직접 읽으면 마비·랭크가 스탯 화면에만 보이고 실제 선공은 그대로다.
    /// 편에 깔린 것(순풍)은 여기서 모른다 — 순서를 재는 자리는 `BattleEngine.orderingSpeed` 를 쓴다.
    var effectiveSpeed: Int {
        var boosted = runBoosts.scaled(StatStages.apply(rawStat(.spe), stage: stage(.spe)),
                                       stacks: runBoosts.speed)
        // 구애스카프는 **마비 반감 앞에서** 곱한다(본가와 같은 순서). 뒤에 두면 정수 나눗셈이
        // 먼저 깎은 값을 올려 같은 개체가 마비 여부에 따라 다른 배율을 받는다.
        if heldEffect?.boostsSpeed == true {
            boosted = boosted * HeldItemBalance.choiceNumerator / HeldItemBalance.choiceDenominator
        }
        // 스피드파우더도 같은 자리다 — 종 조건은 `heldEffect` 가 이미 걸렀다.
        if let scale = heldEffect?.statScale(.spe) {
            boosted = boosted * scale.numerator / scale.denominator
        }
        // 검은철구도 **마비 반감 앞에서** 곱한다(구애스카프와 같은 순서·같은 이유).
        if heldEffect?.halvesSpeed == true { boosted = max(1, boosted / 2) }
        return status == .paralysis ? max(1, boosted / 2) : boosted
    }

    /// 이 상태가 붙을 수 있는가. 불꽃·얼음·독·강철·전기 타입의 본가 면역을 같이 본다.
    func canBeAfflicted(by status: Status) -> Bool {
        guard isAlive else { return false }
        // 주 상태와 혼란의 면역 특성은 여기서 갈린다. 타입 면역과 자리가 다른 건 판정 기준이 달라서다 —
        // 저기는 기술 타입, 여기는 걸리는 상태다(그래서 상성표를 안 타는 최면술도 막힌다).
        //
        // **풀죽음은 여기를 지나지 않는다.** `applySecondaryEffect` 가 `flinched` 를 직접 쓰고, 이
        // 함수는 `.flinch` 를 무조건 false 로 접는다(아래 줄). 지금은 막는 특성이 없어 차이가 안 보일 뿐이다.
        //
        // ponytail: 정신력(Inner Focus)은 `blocks` 에 case 만 더해선 **안 걸린다** — 컴파일도 되고
        //           읽히기도 맞게 읽히는데 아무 일도 안 한다. 넣으려면 풀죽음 쓰기를 이 함수로 먼저
        //           끌어오고(`.flinch` 조기 false 도 같이 걷어낸다), rng 소비가 붙는지 확인한다.
        if ability?.blocks(status) == true { return false }
        if status == .confusion { return !isConfused }
        if status == .flinch { return false }
        guard self.status == nil else { return false }   // 주 상태는 하나
        let types = snapshot.types
        switch status {
        case .burn:            return !types.contains(.fire)
        case .freeze:          return !types.contains(.ice)
        case .paralysis:       return !types.contains(.electric)
        case .poison, .toxic:  return !types.contains(.poison) && !types.contains(.steel)
        default:               return true
        }
    }

    /// 고를 수 있는 기술이 하나도 없으면 발버둥 — **PP 만 보지 않는다.** 도발·앙코르·구애가
    /// 남은 칸을 전부 막을 수 있어서다(변화기만 든 개체가 도발당한 자리). PP 만 세던 시절에는
    /// 그 개체가 "낼 기술이 있다" 로 읽혀 아무 기술도 못 내는 턴이 나왔다.
    var mustStruggle: Bool { !moves.indices.contains { canUse(moveAt: $0) } }

    /// 인덱스로 기술 — 범위 밖이거나 음수면 발버둥(PP 소진 선택은 −1 로 온다).
    func move(at index: Int) -> MoveSpec {
        moves.indices.contains(index) ? moves[index] : .struggle()
    }

    /// 이번 턴에 이 인덱스의 기술을 쓸 수 있는가 — 인덱스 범위·남은 PP·선택 잠금을 **같이** 본다.
    /// `pp` 는 와이어로 들어오는 값이라 `moves` 와 길이가 어긋날 수 있다(경계에서 함께 막는다).
    ///
    /// **네 모드와 터미널이 전부 이 함수를 지난다** — 그래서 잠금을 여기 얹으면 선택을 막는 부류가
    /// 모드마다 갈리지 않는다(모드별로 갈래를 두면 방에서만 도발이 통하지 않는 식으로 어긋난다).
    func canUse(moveAt index: Int) -> Bool {
        moves.indices.contains(index) && pp.indices.contains(index) && pp[index] > 0
            && selectionLock(forMoveAt: index) == nil
    }

    /// 네 칸의 잠금을 한 배열로 — 화면이 버튼을 그릴 때 칸마다 따로 묻지 않게 한다(화면이 넷이라
    /// 그 중 하나만 안 묻는 날 그 화면에서만 잠금이 안 보인다).
    var selectionLocks: [MoveSelectionLock?] { moves.indices.map { selectionLock(forMoveAt: $0) } }

    /// 이 칸이 **왜** 막혔나 — 막히지 않았으면 `nil`. UI 는 이 값으로 버튼을 비활성으로 남긴다
    /// (숨기지 않는다: 왜 못 쓰는지가 화면에 보여야 한다).
    ///
    /// 남은 PP 는 여기서 답하지 않는다 — PP 는 화면이 이미 숫자로 보여 주므로 이 값은 **상태가
    /// 막은 것**만 말한다. 여럿이 겹치면 아래 순서로 첫 하나를 답한다(앙코르가 가장 세다:
    /// 낼 수 있는 칸이 하나로 줄므로 다른 이유를 말해도 화면이 달라지지 않는다).
    func selectionLock(forMoveAt index: Int) -> MoveSelectionLock? {
        guard moves.indices.contains(index) else { return nil }
        return selectionLock(for: moves[index])
    }

    /// 같은 판정을 **기술 자체로** 묻는다 — 행동 시점 게이트(`BattleEngine.beginAttack`)는 칸
    /// 번호가 아니라 나가려는 기술을 들고 온다. 규칙을 그쪽에 다시 쓰면 두 자리가 갈린다.
    func selectionLock(for move: MoveSpec) -> MoveSelectionLock? {
        if has(.encore), let locked = encoredMoveID, move.id != locked { return .encore }
        if let locked = choiceLockedMoveID, move.id != locked { return .choiceItem }
        if has(.disable), move.id == disabledMoveID { return .disable }
        if has(.taunt), move.damageClass == .status { return .taunt }
        // 돌격조끼는 도발과 막는 것이 같아 바로 뒤에 선다. 도발이 먼저인 이유는 푸는 방법이
        // 달라서다 — 도발은 턴이 지나면 풀리고 조끼는 물건을 바꿔야 풀린다.
        if heldEffect?.blocksStatusMoves == true, move.damageClass == .status { return .assaultVest }
        if has(.torment), move.id == lastMoveID { return .torment }
        if has(.imprison), imprisonedMoveIDs.contains(move.id) { return .imprison }
        if has(.healBlock), ShowdownMoveData.healing.contains(move.id) { return .healBlock }
        return nil
    }
}

// MARK: - 배틀 엔진

/// 결정적 RNG — 같은 seed 면 같은 배틀(두 참가자가 각자 실행해도 동일 결과).
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// 끝난 배틀의 승패. **무승부가 값으로 있어야 한다** — 없으면 동시 전멸이 한쪽 승리로 접히고
/// (팀 연습이 그랬다) 보상·배지가 이기지 않은 판에서 나간다. 세 모드가 같은 enum 을 쓴다.
enum BattleOutcome: Sendable, Equatable { case win, loss, draw }

enum BattleEngine {
    /// 급소 확률의 분자(분모 24). 현행 본가 단계표를 정확한 분수로 표현한다.
    static let critDenominator: UInt64 = 24
    static func critThreshold(stage: Int) -> UInt64 {
        switch max(0, stage) {
        case 0: return 1       // 1/24 ≈ 4.17%
        case 1: return 3       // 1/8 = 12.5%
        case 2: return 12      // 1/2 = 50%
        default: return 24     // 100%
        }
    }

    /// 얼음이 행동 전에 자연 해동될 확률(%).
    static let thawChance = 25
    /// 마비로 행동이 막힐 확률. 1/8을 정확히 표현하기 위해 분모를 노출한다.
    static let paralysisFailDenominator: UInt64 = 8
    /// 혼란일 때 자기를 때릴 확률(%).
    static let confusionSelfHitChance = 50
    /// 혼란 자멸의 위력 — 무속성 물리 40.
    static let confusionPower = 40

    /// 대전 규칙 버전 — 턴 순서나 데미지 계산을 바꿀 때마다 올린다. 두 피어가 결과를 주고받지 않고
    /// 각자 계산하므로, 규칙이 다른 앱끼리 붙으면 같은 배틀을 서로 다르게 본다.
    /// 1 = 우선도 도입, 2 = Gen 2 데미지 파이프라인(정수 난수·급소 ×2·`+2` 위치),
    /// 3 = 상태이상 6종 + 혼란(행동 가능 판정·화상 반감·마비 스피드·턴 끝 잔뎀),
    /// 4 = 위력 0(변화기) 데미지 0,
    /// 5 = 끊김을 남은 HP 비율로 판정(몰수승 폐지) + 개시 시점 판돈 에스크로(구버전은 이탈로 판돈 회피),
    /// 6 = LAN 팀전(교체 행동·자동 다음 출전·팀 전체 HP 기반 끊김 판정),
    /// 7 = 출전 이벤트(`.sendOut`) — 스트림에만 생기는 변화라 팀·활성 칸·rng 는 구버전과 같다.
    ///     그래도 올린다: 이 스트림은 멀티 `roundResolved` 로 와이어에 실리고, `BattleEvent` 는
    ///     case 이름으로 디코딩하므로 모르는 case 를 받은 구버전은 **메시지 전체를 못 읽는다.**
    ///     지금은 멀티가 교체를 안 해 실릴 일이 없지만, "실릴 일이 없다" 를 근거로 두는 것보다
    ///     핸드셰이크에서 막는 쪽이 싸다.
    /// 8 = 랭크(스탯 단계) + 명중·회피 랭크 + 변화기 무브셋 편입(변화기는 상성을 타지 않는다),
    ///     그리고 교체할 때 랭크가 사라진다 — 데미지와 명중이 둘 다 달라지므로 구버전과 붙으면
    ///     같은 배틀을 다르게 본다.
    /// 9 = PokéAPI 가 `power: null` 로 주는 공격기의 데미지(`VariableDamage`). 세 가지가 한꺼번에
    ///     달라진다: ① 위력이 0 이 아니게 되어 데미지가 생기고, ② 고정 데미지·일격필살은 공식을
    ///     아예 안 타며, ③ 매그니튜드·사이코웨이브가 **rng 를 한 번 더** 소비한다(명중 → 가변위력 →
    ///     급소 → 난수 폭). 소비 횟수가 갈리면 그 뒤 모든 판정이 어긋나므로 구버전과 붙으면 안 된다.
    /// 10 = 체중 기반 위력(저공격·풀묶기·헤비봄버·히트스탬프). `BattleSnapshot.weightHectograms` 가
    ///     와이어에 새로 실린다 — 구버전이 보낸 스냅샷에는 이 값이 없어 같은 기술이 한쪽에서만
    ///     실패한다. rng 소비는 그대로다.
    /// 11 = 되돌려주는 기술(카운터·미러코트·메탈버스트). `BattleSide.lastHitThisTurn` 은 두 피어가
    ///     각자 채우는 지역 상태라 와이어는 그대로지만, 같은 입력에서 나오는 데미지가 달라진다.
    ///     rng 소비도 그대로다(되돌려주기는 난수를 쓰지 않는다).
    /// 12 = 변화기가 상성표를 안 탄다(전기자석파 제외). 예전엔 안 걸리던 상태가 걸리므로
    ///     같은 입력에서 배틀이 통째로 갈라진다. rng 소비는 그대로다 — 면역으로 조기반환하던
    ///     자리가 정상 경로로 바뀌는 것뿐이라 뽑는 횟수는 같다(명중 → 가변위력 → 급소 → 난수 폭).
    /// 13 = 안 읽던 `meta` 필드 넷(드레인·반동·다단 히트·풀린치). rng 소비가 두 군데 는다:
    ///     다단기는 명중 직후 히트 수를 뽑고 히트마다 급소·난수를 다시 뽑는다
    ///     (명중 → 히트 수 → (가변위력 → 급소 → 난수) × 히트). 풀린치는 상태 부여 앞에서 한 번 더
    ///     뽑는다. 드레인·반동은 비율 계산이라 안 쓴다. 횟수가 갈리면 뒤 판정이 전부 밀린다.
    /// 14 = 특성 1단계 — 타입 면역(부유·타오르는불꽃)과 흡수(저수·전기흡수), 상태 면역 7종.
    ///     `BattleSnapshot.ability` 가 와이어에 새로 실린다: 구버전이 보낸 스냅샷에는 이 값이 없어
    ///     같은 기술이 한쪽에서만 통한다. rng 소비는 **그대로다**(표 조회와 비율 계산뿐).
    ///     갈리는 건 소비 횟수가 아니라 값이라 여기서 막는다.
    /// 15 = 자기 회복기(회복·아침햇살·광합성·달빛·둥지틀기 = 최대 HP 절반, 잠자기 = 전회복 +
    ///     상태 해제 + 2턴 수면). 예전엔 위력 0 짜리 무동작이라 턴만 태웠다 — 이제 HP 가 오르므로
    ///     같은 입력에서 배틀이 갈라진다. rng 소비는 그대로다(회복량·수면 턴이 전부 고정값).
    /// 16 = 현행 상태이상·급소 규칙(마비 1/2·1/8, 잠듦 1~3턴, 해동 25%,
    ///      화상 1/16, 맹독 교체 카운터 초기화, 급소 1.5배·현행 단계표).
    /// 18 = 특성 2단계 — 불가사의부적, 타입/약점 반감, 테크니션, 공격·방어 스탯 특성.
    ///      전부 표·정수 계산이라 rng 소비 순서는 그대로지만 같은 입력의 데미지가 달라진다.
    /// 20 = 기절 뒤 강제 교체는 턴 행동이 아니다. 같은 턴에 새 포켓몬의 기술을 다시 선택한다.
    ///      일반 교체와 달리 상대의 단독 공격·턴 종료 잔뎀을 발생시키지 않는다.
    /// 22 = PokéAPI 결손을 쇼다운 표로 메운다(`ShowdownMoveData`) + 명중률 0 을 필중으로 읽는다
    ///      + 하드프레스·황폐가·인과응보. **rng 소비가 갈린다**: 보정으로 다단기가 된 기술
    ///      (타키온커터 2히트·파퓰레이션밤 10히트 …)은 명중 뒤에 히트 수를 뽑고 히트마다 급소·난수를
    ///      다시 뽑으므로, 구버전은 같은 기술을 1히트로 보고 그 뒤 모든 판정이 어긋난다.
    ///      명중률 0 도 값이 아니라 **경로**가 바뀐다 — 구버전은 명중 rng 를 뽑고 늘 빗나갔다.
    /// 23 = 상황에서 위력을 뽑는 기술이 한 묶음으로 늘었다(분화 부류의 HP 비례, 어시스트파워의
    ///      랭크 합, 악몽의 상태 배율, 리프블레이드·에코보이스·원한의응보의 누적 카운터,
    ///      트리플킥 부류의 히트별 위력, 리벤지의 후공 배율) + 날씨·필드 레이어(볕·비의 1.5·0.5배,
    ///      모래 잔뎀, 세 필드의 1.3배와 상태 차단, 그래스필드 회복) + 진영 상태(리플렉터·빛의장막·
    ///      오로라베일의 반감, 신비의부적·하얀안개·행운의부적의 차단, 순풍의 스피드 2배).
    ///      새 상태는 전부 지역 값이라 와이어는 그대로고 rng 소비 순서도 그대로지만, 같은 입력의
    ///      데미지가 갈린다. 순풍은 **턴 순서**까지 갈라 놓는다(그 뒤 판정이 통째로 밀린다).
    ///      + 방어 부류 여덟(막는 일만, 접촉 부가 효과는 아직 없다). **연속 방어에서만 rng 를
    ///      한 번 더 뽑는다**(1/3^연속) — 첫 방어는 뽑지 않으므로 예전 판의 소비 순서는 그대로다.
    ///      + 테라스탈(모의전·LAN 1v1 — 방·웨이브는 턴 액션이 아직 없다). LAN 은 **와이어에 행동
    ///      하나가 늘었다**(`NetBattleAction.terastallizeAndMove`): 구버전은 그 행동을 디코딩하지
    ///      못하므로 같은 버전끼리만 붙는다(이 값이 이미 그것을 막는다).
    ///      타입이 하나로 접히고 STAB 가 세 갈래가 되며 테라버스트의 타입·분류가 바뀐다.
    ///      **와이어는 그대로다**: 테라 타입은 두 피어가 같은 `types` 에서 파생하고, 테라스탈
    ///      여부는 `BattleSide`(와이어에 없는 타입)에만 산다. rng 소비도 늘지 않는다.
    /// 24 = 개체에 붙어 턴을 넘어 사는 상태(`BattleVolatile`) 여섯 — 조이기(열 기술)·저주·
    ///      나이트메어의 턴 끝 잔뎀, 아쿠아링·뿌리박기의 턴 끝 회복, 그리고 씨뿌리기(깎은 만큼
    ///      뿌린 자리가 회복한다 — 네 모드가 잔뎀 뒤·날씨 앞에서 부른다).
    ///      + 편 방어기 넷(와이드가드·퀵가드·니가하지마·트릭가드) — 한 턴짜리 진영 상태로 깔리고
    ///      막는 기술의 종류만 서로 갈린다. **연속 실패 확률을 개인 방어와 공유하므로** 방어를
    ///      쓴 다음 턴의 편 방어기는 rng 를 한 번 더 뽑는다(구버전은 안 뽑고 늘 성공한다). 상태는 전부 `BattleSide`
    ///      (와이어에 없는 타입)에 살지만 **rng 소비가 갈린다**: 조이기는 붙는 자리에서 지속 턴을
    ///      한 번 더 뽑으므로, 구버전은 그 뒤 모든 판정이 한 칸씩 밀린다. 같은 입력의 HP 도 갈린다.
    ///      `DamageCause` 에 원인 셋(`trap`·`curse`·`nightmare`)과 `BattleEvent` 에 case 둘
    ///      (`volatileStarted`·`volatileEnded`)이 늘어 구버전은 그 이벤트를 디코딩하지 못한다.
    ///      + 배율만 얹는 volatile 다섯(기합충전·레이저포커스·작아지기·방어태세·충전) — 급소 단계
    ///      (+2 / 확정)·데미지 두 배·위력 두 배가 달라진다. **rng 소비도 갈린다**: 이 다섯은 이제
    ///      데미지 경로를 안 지나므로 구버전이 뽑던 급소·난수 폭 두 번을 안 뽑고, 작아진 상대를
    ///      때리는 플래그 기술(발구르기 부류)은 명중 판정을 건너뛰어 한 번 덜 뽑는다.
    ///      + 기절 순간에 답하는 volatile 셋(인내·운명공동체·원한) — 인내는 기술 데미지를 남은
    ///      HP 하나로 자르고(잔뎀으로는 여전히 쓰러진다), 운명공동체는 쓰러뜨린 쪽을 함께 0 으로
    ///      만들고, 원한은 쓰러뜨린 기술의 PP 를 0 으로 만든다. **rng 소비도 갈린다**: 인내는 방어
    ///      부류와 연속 실패 카운터를 공유하므로 방어를 쓴 다음 턴의 인내가 한 번 더 뽑는다.
    ///      `BattleEvent` 에 case 하나(`volatileTriggered`)가 늘어 구버전은 그 이벤트를
    ///      디코딩하지 못한다.
    ///      + 입장 데미지 넷(압정뿌리기·독압정·스텔스록·끈적끈적네트) — **상대 편에** 깔리고
    ///      교체로 나오는 개체가 밟는다. rng 소비는 갈리지 않지만(밟기는 난수를 안 쓴다) 같은
    ///      입력의 HP·상태·랭크가 갈린다: 구버전은 교체할 때 아무 일도 없고, 층을 쌓는 두 번째
    ///      사용이 실패로 접힌다. `BattleSideCondition` 에 case 넷, `DamageCause` 에 원인
    ///      하나(`hazard`)가 늘어 구버전은 그 진영 상태와 그 데미지 줄을 디코딩하지 못한다.
    ///      + 테라 타입을 스냅샷에 **저장 값으로** 싣는다(테라피스 아이템). 구버전 피어는 그 필드를
    ///      안 보내므로 같은 개체가 첫 번째 타입으로 테라스탈하고, STAB 과 상성 배율이 갈린다.
    ///      rng 소비는 그대로다.
    ///      + 지닌물건 3종을 스냅샷에 싣는다(생명의구슬·기합의띠·먹다남은음식). 구버전 피어는 그
    ///      필드를 안 보내므로 데미지 배율(×1.3)·턴 끝 자해(1/10)·턴 끝 회복(1/16)·만피 버티기가
    ///      한쪽에만 얹혀 같은 판의 HP 가 갈린다. rng 소비는 그대로다(전부 정수 계산이다).
    ///      `BattleEvent` 에 case 하나(`heldItemTriggered`)가 늘어 구버전은 그 이벤트를
    ///      디코딩하지 못한다.
    ///      + 대타출동(쉐도우테일 포함) — HP 대신 맞는 층이 데미지·상태·랭크 앞에 선다. 구버전
    ///      피어는 그 기술이 턴만 태우므로 같은 판의 HP·상태·랭크가 통째로 갈린다. rng 소비도
    ///      갈린다: 층에 막힌 기술은 2차효과 확률·랭크 확률을 굴리지 않는다. `BattleVolatile` 에
    ///      case 하나(`substitute`)가 늘어 구버전은 그 상태의 이벤트를 디코딩하지 못한다.
    ///      + 다인전 타겟 유도 넷(따라와·성원·스포트라이트·도우미) — 앞 셋은 상대의 단일 타겟
    ///      공격을 한 자리로 끌어오고, 도우미는 아군의 이번 턴 위력을 1.5 배로 만든다. 구버전
    ///      피어는 네 기술이 턴만 태우므로 **누가 맞는지와 데미지가 통째로 갈린다**. 방의 액션
    ///      검증도 함께 넓어졌다: 자기 지목(자기에게 거는 기술)과 같은 편 지목(도우미)을 받는다 —
    ///      구버전은 그 액션을 `invalidTarget` 으로 거절한다. `BattleVolatile` 에 case 넷이 늘어
    ///      구버전은 그 상태의 이벤트를 디코딩하지 못한다.
    ///      + 기술 **선택**을 막는 여섯(씨앙코르·앙코르·도발·트집·봉인·비밀의힘)과 구애 2종
    ///      (구애머리띠·구애안경). 구버전 피어는 여섯이 턴만 태우므로 막혔어야 할 기술이 그대로
    ///      나가고, 낼 기술이 하나도 없어 발버둥이 되는 자리를 구버전은 정상 기술로 본다.
    ///      구애는 스냅샷의 `heldItem` 으로 실려 배율(한 계통 ×1.5)이 한쪽에만 얹힌다.
    ///      rng 소비도 갈린다: CPU 가 후보를 `canUse` 로 걸러 뽑으므로 잠긴 칸이 있으면 후보 수가
    ///      달라진다. `BattleVolatile` 에 case 여섯이 늘어 구버전은 그 상태의 이벤트를 디코딩하지
    ///      못한다.
    ///      + 그 잠금 중 넷(씨앙코르·도발·봉인·비밀의힘)은 **행동 직전에도** 막는다 — 잠금을 건
    ///      쪽이 먼저 움직인 턴에서 갈린다: 구버전은 이미 고른 기술을 그대로 내고 이 버전은 못 낸다.
    ///      데미지·상태가 통째로 갈리고 rng 소비도 갈린다(막힌 턴은 명중·급소를 굴리지 않는다).
    ///      `BattleEvent` 에 case 하나(`moveBlocked`)가 늘어 구버전은 그 이벤트를 디코딩하지 못한다.
    ///      + 열매 29종(약점 반감 18·위급 6·성격 회복 5). 구버전 피어는 그 이름을 모르는 값으로
    ///      접으므로 같은 판에서 데미지(반감)·랭크·HP 가 갈린다. 난수 소비는 그대로다 — 열매는
    ///      난수를 쓰지 않는다.
    ///      + 주얼 18종(그 타입 기술 하나 ×1.3 + 소모)과 대가만 있는 셋(검은철구의 스피드 절반·
    ///      접지, 느림보꼬리·만복향로의 후공). 구버전 피어는 그 이름을 모르는 값으로 접으므로
    ///      데미지·행동 순서·땅 기술 면역이 갈린다. 난수 소비도 갈린다: 후공 물건이 스피드 동점을
    ///      먼저 가르면 무작위 tie-break 를 안 뽑는다.
    ///      + 플레이트 17종(타입 강화 도구와 같은 ×1.2). 구버전 피어는 그 이름을 모르는 값으로
    ///      접어 데미지가 갈린다 — 강철은 이 저장소에서 처음 생긴 강화 수단이다.
    ///      + 특정 종 전용 10종(전기구슬·굵은뼈·금속파우더·스피드파우더·럭키펀치·대파·
    ///      마음의물방울·보옥 셋). 능력치 배율·급소 단계·두 타입 강화가 붙고, 구버전 피어는 그
    ///      이름을 모르는 값으로 접어 데미지·급소·행동 순서가 갈린다.
    ///      + 일반 배틀 도구 12종(힘의머리띠·박식안경의 분류별 ×1.1, 달인의띠의 효과 굉장 ×1.2,
    ///      메트로놈의 연속 사용 배율, 초점렌즈의 급소 +1, 광각렌즈·포커스렌즈의 명중 상승,
    ///      반짝가루·무사태평향로의 상대 명중 하락, 조개껍질방울·큰뿌리의 회복, 검은오물의 턴 끝
    ///      회복/데미지). 구버전 피어는 그 이름을 모르는 값으로 접어 데미지·명중·HP 가 갈린다.
    ///      명중 배율은 **난수 소비까지** 바꾼다: 같은 seed 에서 맞고 빗나감이 갈리면 그 뒤 급소·
    ///      난수 폭을 뽑는 횟수가 달라진다. `DamageCause` 에 원인 하나(`heldItem`)가 늘어
    ///      구버전은 그 이벤트를 디코딩하지 못한다.
    ///      + 면역·무시 물건 6종(풍선의 땅 기술 면역과 맞으면 터짐, 통굽부츠의 입장 데미지 무시,
    ///      방진고글의 날씨 잔뎀 무시, 만능우산의 볕·비 위력 보정 무시, 겨냥표적의 타입 면역 해제,
    ///      가벼운돌의 체중 절반). 구버전 피어는 그 이름을 모르는 값으로 접어 **통하지 않던 기술이
    ///      통하고** 밟지 않던 함정을 밟는다 — 데미지가 아니라 맞고 안 맞고가 갈린다.
    ///      + 지속 시간을 늘리는 물건 6종(빛의점토의 장막 8턴, 날씨 돌 넷의 날씨 8턴,
    ///      그라운드코트의 필드 8턴). 구버전 피어는 5턴으로 세어 세 턴 동안 판을 다르게 본다.
    ///      + 허브·무효화 물건 5종(하양허브의 랭크 원복, 멘탈허브의 선택 잠금 해제, 흉내허브의
    ///      랭크 상승 따라하기, 클리어참의 하락 차단, 은밀망토의 부가효과 차단). 은밀망토는
    ///      **rng 소비까지 바꾼다** — 막힌 부가효과는 확률을 굴리지 않는다.
    ///      + 방아쇠 하나에 랭크를 올리고 사라지는 물건 10종(약점보험·구근·충전지·눈덩이·
    ///      빛이끼가 맞은 히트에, 허탕보험이 빗나간 자기 기술에, 씨앗 넷이 발밑의 필드에 답한다).
    ///      구버전 피어는 그 랭크를 안 올려 그 뒤 모든 데미지·명중이 갈린다.
    ///      + 기술의 성질에 답하는 물건 8종(울퉁불퉁멧·끈적끈적바늘의 접촉 반응, 방호패드·
    ///      펀치글러브의 접촉 해제, 펀치글러브의 펀치 ×1.1, 속임수주사위의 다단 하한 4,
    ///      조임밴드의 조이기 잔뎀 1/6, 끈기갈고리손톱의 조이기 7턴, 목스프레이의 특공 상승).
    ///      **rng 소비까지 바꾼다** — 끈기갈고리손톱은 4~5턴 난수를 굴리지 않는다.
    ///      + 운에 걸린 물건 5종(선제공격손톱의 20% 선공, 기합의머리띠의 10% 버팀, 스타열매의
    ///      능력 상승, 애슈열매의 선공, 미클열매의 필중). **rng 소비가 갈린다** — 손톱은 턴마다,
    ///      머리띠는 치명적인 히트마다 한 번씩 더 굴린다.
    ///      + 진화의휘석(아직 진화할 수 있는 개체의 방어·특수방어 ×1.5). 스냅샷에 조건 필드가
    ///      하나(`canStillEvolve`) 늘어, 구버전 피어는 그 값을 안 보내 휘석이 한쪽에서만 일한다.
    static let rulesVersion = 38

    /// 연결이 끊긴 배틀의 승패 — 남은 HP **비율**이 앞선 쪽이 이기고, 같으면 `nil`(무효)이다.
    ///
    /// 예전엔 끊김을 무조건 `iWon: true` 로 접었다. 두 피어가 각자 자기 연결의 죽음을 보므로 한 번
    /// 끊기면 **양쪽이 동시에 승리**해 둘 다 `settleRankedBrawl(won: true)` 로 판돈 ★ 과 LP 를 받았다 —
    /// 어느 지갑에서도 빠져나가지 않아 총량만 늘었고, 지고 있으면 끊는 게 이득이었다. 판정을 두 피어가
    /// 공유하는 **상태에서** 뽑으면 두 쪽 결론이 자동으로 반대가 된다.
    ///
    /// 상태가 같다는 전제는 **턴 경계에서만** 참이다. `resolveIfReady` 는 두 선택이 모이는 즉시
    /// 해상하므로 한쪽 `.move` 만 도착한 채 링크가 죽으면 상태가 한 턴 어긋나고, 그 창에서는 양쪽이
    /// 모두 "내가 앞선다"를 봐 판돈이 두 지갑에 동시에 들어갔다. **그래서 호출부는 지금 상태가 아니라
    /// `AgreedTurnLedger.agreedState` 를 넘긴다** — 이 함수 자체는 받은 상태를 그대로 비교할 뿐이라,
    /// 어느 시점의 상태를 넘기는지가 정확성을 가른다(`connectionDropped` 참조).
    ///
    /// 명시적 `.forfeit` 메시지를 받은 몰수승은 이 판정을 타지 않는다 — 그건 상대가 스스로 진 것이다.
    ///
    /// 비교는 교차곱이다. `Double` 나눗셈은 최대 HP 가 다른 두 종에서 반올림이 갈릴 수 있고, 승패는
    /// 두 피어가 **같은 값**으로 봐야 한다(`resolveRound` 의 tie-break 와 같은 이유).
    static func disconnectOutcome(me: BattleSide, opp: BattleSide) -> Bool? {
        let mine = me.hp * max(1, opp.stats.hp)
        let theirs = opp.hp * max(1, me.stats.hp)
        return mine == theirs ? nil : mine > theirs
    }

    /// 끊김 판정이 볼 상태를 고르는 보관함 — **두 피어가 모두 해상했다고 확인된 마지막 턴**의 것.
    ///
    /// `disconnectOutcome` 은 "두 피어가 같은 상태를 본다" 를 전제하는데, 그 전제는 턴 경계에서만
    /// 참이다. `resolveIfReady` 가 두 선택이 모이는 즉시 해상하므로 한쪽 행동만 도착한 채 링크가
    /// 죽으면 상태가 한 턴 어긋나고, 그 창에서 양쪽이 모두 "내가 앞선다"를 본다. 정산은 각자 자기
    /// 지갑에만 하므로(공유 원장이 없다) 판돈이 두 지갑에 동시에 들어간다.
    ///
    /// **왜 `min` 이 양쪽에서 같은가.** 내가 쓰는 두 값은 (내 해상 턴, 상대가 알린 해상 턴)이고
    /// 상대가 쓰는 두 값은 (상대 해상 턴, 내가 알린 해상 턴)이다. 보고는 자기 해상 턴을 그대로
    /// 싣고 전송은 순서를 지키므로, 유실이 있어도 **양쪽이 같은 쌍의 min** 에 도달한다. 같은 턴의
    /// 상태는 엔진이 결정론적이라 양쪽에서 같은 값이고, 따라서 결론이 정확히 반대가 된다.
    ///
    /// 합의된 턴이 없으면 `agreedState` 가 nil 이다 — 판정하지 않고 환급한다.
    struct AgreedTurnLedger {
        /// 내가 해상을 끝낸 마지막 턴. 상대에게 보고하는 값이자 `min` 의 한쪽이다.
        private(set) var myResolved = 0
        /// 상대가 마지막으로 알려 온 해상 턴.
        private(set) var peerResolved = 0
        private var states: [Int: (me: [BattleSide], opp: [BattleSide])] = [:]

        /// 지금 판정 근거로 삼아도 되는 턴 — 둘 다 해상을 확인한 마지막 턴.
        var agreedTurn: Int { min(myResolved, peerResolved) }

        /// 합의된 턴의 상태. 보관하지 않은 턴이면 nil 이고, 그때는 판정 대신 환급이다.
        var agreedState: (me: [BattleSide], opp: [BattleSide])? { states[agreedTurn] }

        /// 보관 중인 턴 수 — 보관함이 배틀 내내 자라지 않는지 테스트가 본다.
        var retainedTurnCount: Int { states.count }

        mutating func recordResolved(turn: Int, me: [BattleSide], opp: [BattleSide]) {
            myResolved = max(myResolved, turn)
            states[turn] = (me: me, opp: opp)
            prune()
        }

        /// 보고는 뒤로 가지 않는다 — 순서가 뒤집힌 값을 그대로 받으면 합의 턴이 되감긴다.
        mutating func recordPeerResolved(_ turn: Int) {
            peerResolved = max(peerResolved, turn)
            prune()
        }

        /// 합의된 턴보다 오래된 상태는 다시 볼 일이 없다. 합의 지연은 최대 한 턴이라 보관은 둘이면
        /// 충분하지만, 경계를 숫자로 박지 않고 **합의 턴 기준**으로 버린다.
        private mutating func prune() {
            let keep = agreedTurn
            states = states.filter { $0.key >= keep }
        }
    }

    /// 팀전 연결 종료 판정 — 한 슬롯이 아니라 양쪽 파티의 남은 HP 합 / 최대 HP 합을 비교한다.
    /// 양쪽이 같은 정수 연산을 하도록 나눗셈 대신 교차곱을 쓴다.
    static func disconnectOutcome(me: [BattleSide], opp: [BattleSide]) -> Bool? {
        guard !me.isEmpty, !opp.isEmpty else { return nil }
        let myHP = me.reduce(0) { $0 + $1.hp }
        let myMax = me.reduce(0) { $0 + max(1, $1.stats.hp) }
        let oppHP = opp.reduce(0) { $0 + $1.hp }
        let oppMax = opp.reduce(0) { $0 + max(1, $1.stats.hp) }
        let mine = myHP * oppMax
        let theirs = oppHP * myMax
        return mine == theirs ? nil : mine > theirs
    }

    /// 필드에서 물러나는 포켓몬의 volatile 상태를 정리한다. CPU/체육관과 LAN 교체가 이 한 규칙을 쓴다.
    static func prepareForSwitch(_ side: inout BattleSide) {
        // 맹독 상태는 유지하되, 누적 배수는 다시 1/16 부터 시작한다.
        if side.status == .toxic {
            side.statusCounter = 1
        }
        // 혼란·풀죽음은 volatile — 다시 나왔을 때 이전 상태를 이어 가지 않는다.
        side.confusionTurns = 0
        side.flinched = false
        // 붙어 있던 volatile 도 전부 사라진다(본가와 같다). 남겨 두면 조이기·저주를 교체로 피했다가
        // 그 상태 그대로 다시 나온다 — 랭크를 지우는 것과 같은 이유다.
        side.volatiles = [:]
        // 층도 함께 내린다. `volatiles` 만 비우면 HP 가 남아 다시 나온 개체가 공격을 흘린다 —
        // 두 값이 한 상태의 두 면이라 지우는 자리도 하나여야 한다.
        side.substituteHP = 0
        // 선택 잠금의 곁의 값도 함께 지운다. volatile 만 비우면 막힌 기술 id 가 남고, 구애는
        // volatile 이 아니라 아예 안 지워진다 — 다시 나온 개체가 이유 없이 한 칸만 내게 된다.
        side.disabledMoveID = nil
        side.encoredMoveID = nil
        side.imprisonedMoveIDs = []
        side.choiceLockedMoveID = nil
        side.leechSeedSource = nil
        // 랭크도 물러나면 사라진다. 남겨 두면 칼춤을 세 번 쌓아 두고 교체로 피했다가 그 랭크
        // 그대로 다시 나오는 무료 세팅이 된다 — CPU/체육관과 LAN 교체가 같이 이 규칙을 쓴다.
        side.resetStages()
    }

    /// 필드에 **새로 나온** 개체가 자기 편에 깔린 입장 데미지를 밟는다.
    ///
    /// **왜 `prepareForSwitch` 의 짝이 따로 필요한가.** 물러나는 쪽의 정리는 개체 하나만 만지면
    /// 끝나지만, 밟기는 판(`BattleField`)과 **어느 편의 자리인지**를 알아야 한다. 그 둘을 아는
    /// 것은 모드뿐이라(모드마다 좌우가 다르고 개인전은 참가자 하나가 한 편) 인자로 받는다.
    /// 출전을 내면서 이 함수를 빠뜨린 모드는 `BattleEntryHazardTests` 가 소스에서 찾아낸다 —
    /// 한 곳만 빠지면 그 모드에서만 압정이 아무 일도 하지 않고 화면에는 정상으로 보인다.
    ///
    /// **난수를 쓰지 않는다.** `inflict` 를 부르지만 독·맹독은 카운터를 뽑지 않는 갈래라 소비가
    /// 0 이다. 여기서 뽑으면 교체마다 두 피어의 소비가 갈려 그 뒤 모든 판정이 한 칸씩 밀린다.
    /// (독 면역 판정을 `inflict` 에 맡기는 이유이기도 하다 — 면역 규칙의 정본은 한 곳이다.)
    ///
    /// 밟는 순서는 `BattleSideCondition.allCases` 의 선언 순서다(끈적끈적네트 → 스텔스록 →
    /// 압정 → 독압정). 쓰러지면 남은 것은 밟지 않고 기절 줄로 끝낸다 — 계속 밟으면 쓰러진
    /// 개체에 독이 붙어 재생과 엔진의 최종 상태가 갈린다.
    static func applyEntryHazards(_ side: inout BattleSide, actor: BattleActor,
                                  team: BattleTeamSlot, field: BattleField,
                                  rng: inout SplitMix64) -> [BattleEvent] {
        guard side.isAlive else { return [] }
        // 통굽부츠는 **깔린 것 전부**를 건너뛴다 — 뜬 개체(`isGrounded`)가 압정만 피하는 것과
        // 다르다. 그래서 층을 훑기 전에 통째로 빠진다.
        guard side.heldEffect?.ignoresEntryHazards != true else { return [] }
        var events: [BattleEvent] = []
        let grounded = BattleField.isGrounded(side)
        for condition in BattleSideCondition.allCases where condition.isEntryHazard {
            let layers = field.layers(condition, for: team)
            guard layers > 0, grounded || !condition.hitsOnlyGrounded else { continue }
            switch condition {
            case .stickyWeb:
                // 끈적끈적네트도 남이 내리는 랭크다 — 클리어참이 여기서도 답한다.
                guard side.heldEffect?.blocksStatDrop != true else { continue }
                let applied = side.changeStage(.spe, by: -1)
                if applied != 0 { events.append(.boost(actor, .spe, applied)) }
            case .stealthRock:
                // 바위 상성으로 배율이 갈린다 — 1/8 을 기준으로 ×0.25 ~ ×4.
                // 배율이 2의 거듭제곱뿐이라 `Double` 곱이 정확하다(두 피어가 같은 정수를 본다).
                let multiplier = TypeChart.effectiveness(.rock, against: side.activeTypes)
                events += hazardDamage(&side, actor: actor,
                                       amount: Int(Double(side.stats.hp) * multiplier / 8.0))
            case .spikes:
                // 층에 따라 1/8·1/6·1/4 — 나누는 수가 10 − 2×층이다.
                events += hazardDamage(&side, actor: actor, amount: side.stats.hp / (10 - 2 * layers))
            case .toxicSpikes:
                // 2층이면 맹독이다. 데미지는 없고 상태만 붙는다(잔뎀은 턴 끝이 낸다).
                events += inflict(layers >= 2 ? .toxic : .poison, on: &side, actor: actor, rng: &rng)
            case .reflect, .lightScreen, .auroraVeil, .safeguard, .mist, .luckyChant, .tailwind,
                 .wideGuard, .quickGuard, .matBlock, .craftyShield:
                continue                    // 입장 데미지가 아니다 — 위 `where` 가 이미 걸렀다
            }
            if !side.isAlive { break }
        }
        if !side.isAlive { events.append(.faint(actor)) }
        // 밟아서 내려간 랭크에도 허브가 답한다 — 기술이 아니라 함정이 내렸을 뿐 같은 하락이다.
        // 따라 올릴 상대가 없으므로 앞뒤 값은 같은 것을 넘긴다.
        events += settleStageItems(&side, actor: actor, foeStagesBefore: [:], foeStagesAfter: [:])
        return events
    }

    /// 밟아서 깎인 몫 한 번. 최소 1 이다 — 0 이면 줄만 남고 아무 일도 안 한 것으로 읽힌다.
    private static func hazardDamage(_ side: inout BattleSide, actor: BattleActor,
                                     amount: Int) -> [BattleEvent] {
        let dealt = min(max(1, amount), side.hp)
        side.hp -= dealt
        return [.damage(actor, amount: dealt, cause: .hazard)]
    }

    /// 공격 1회의 결과. 1v1 과 멀티가 같은 값을 내야 하므로 계산은 `resolveAttack` 한 곳에만 둔다.
    struct AttackOutcome: Sendable {
        var missed: Bool
        var damage: Int
        /// 빗나갔으면 1 — 화면이 "효과가 굉장했다" 를 띄우지 않게 한다.
        var effectiveness: Double
        var isCritical: Bool
        /// 실제로 들어간 히트 수 — 다단기(더블킥·고드름침)만 1 보다 크다. 상대가 중간에 쓰러지면
        /// 요청 횟수보다 적다.
        var hits = 1
        /// **마지막 히트**가 넣은 데미지. 되돌려주는 기술(카운터·미러코트·메탈버스트)이 읽는다.
        /// 본가는 마지막 히트만 되돌려주므로, 합계를 주면 되돌아오는 데미지가 히트 수만큼 뻥튀기된다.
        /// `resolveAttack` 은 늘 채운다(단발기는 `damage` 와 같은 값). 히트 하나를 그대로 돌려주는
        /// 내부 경로(`resolveSingleHit`·`fixedOutcome`)만 `nil` 이라 읽는 쪽이 `?? damage` 로 접는다.
        var lastHitDamage: Int? = nil
        /// 맞는 쪽의 약점 반감 열매가 이 히트를 깎았나 — **소모를 결정하는 값**이다.
        ///
        /// 데미지를 깎은 자리(`resolveSingleHit`)와 열매를 없애는 자리(`applyHit`)가 갈려 있어서
        /// 두는 값이다. 같은 조건을 두 자리에서 각자 물으면 한쪽만 어긋난다(상성표를 안 보는
        /// 기술은 깎이지 않는데 열매만 사라지는 식으로).
        var berryHalved = false
        /// 때리는 쪽의 주얼이 이 히트를 올렸나 — 열매와 같은 이유로 두는 값이다(올린 자리와
        /// 없애는 자리가 갈려 있다). 주인이 반대편이라 열매 플래그와 한 값으로 접지 않는다.
        var gemSpent = false
    }

    /// 공식을 타지 않는 데미지(고정·일격필살)의 결과.
    ///
    /// 상성은 **면역만** 본다 — 나이트헤드는 노말에게 통하지 않지만, 통할 때는 2배도 절반도 되지
    /// 않는다. 급소·상성 문구를 막는 것도 여기다: `effectiveness` 를 1 로, `isCritical` 을 false 로
    /// 두면 `applyAttack` 의 문구 분기가 저절로 안 걸린다. 일격필살을 표시할 플래그는 두지 않는다 —
    /// 읽는 쪽이 없는데 다단 루프까지 전파해야 하는 값이 된다
    /// (`VariableDamageTests.testAOneHitKOSuppressesTheCritAndEffectivenessLines` 가 억제를 잠근다).
    private static func fixedOutcome(_ amount: Int, move: MoveSpec, defender: BattleSide) -> AttackOutcome {
        let immune = typeMultiplier(of: move, against: defender) == 0
        return AttackOutcome(missed: false, damage: immune ? 0 : max(0, amount),
                             effectiveness: immune ? 0 : 1, isCritical: false)
    }

    /// 이 기술이 이 상대에게 몇 배인가 — 상성표와 타입 면역 특성(부유·타오르는불꽃·저수·전기흡수)을
    /// **한 함수**에서 본다.
    ///
    /// 공식을 타는 히트(`resolveSingleHit`)와 안 타는 히트(`fixedOutcome`)가 각자 상성을 보던 동안
    /// 부유는 지진을 막고 갈라진땅은 못 막았다 — 특성이 붙는 갈림길은 여기 하나여야 한다.
    static func typeMultiplier(of move: MoveSpec, against defender: BattleSide) -> Double {
        // 물건이 발을 옮기면 땅 기술의 **면역만** 갈린다. 검은철구를 쥔 개체는 부유·비행이어도
        // 지진을 맞고, 풍선을 쥔 개체는 어떤 타입이어도 안 맞는다. 나머지 상성은 그대로다 —
        // 내려놓은 비행/강철이면 강철 몫의 2배가 남는다.
        let contact = defender.heldEffect?.groundContact
        if move.type == .ground, contact == .airborne { return 0 }
        let grounded = move.type == .ground && contact == .grounded
        if !grounded, defender.ability?.immuneMoveType == move.type { return 0 }
        let types = grounded ? defender.activeTypes.filter { $0 != .flying } : defender.activeTypes
        var multiplier = TypeChart.effectiveness(move.type, against: types)
        // 겨냥표적은 **상성표의** 0 만 지운다 — 위 특성 면역은 이미 지났으므로 부유는 그대로 막는다
        // (본가와 같다). 배율을 1 로 두는 이유도 본가와 같다: 통하게만 하고 세게 만들지는 않는다.
        if multiplier == 0, defender.heldEffect?.ignoresTypeImmunity == true { multiplier = 1 }
        if defender.ability == .wonderGuard, move.damageClass != .status, multiplier <= 1 { return 0 }
        return multiplier
    }

    /// Gen 2 데미지 식의 앞부분 — 배율이 붙기 전의 뼈대. 기술 공격과 혼란 자멸이 같은 값을 쓴다.
    static func baseDamage(level: Int, power: Int, attack: Int, defense: Int) -> Int {
        (2 * level / 5 + 2) * power * attack / max(1, defense) / 50
    }

    /// AI 가 기술을 고를 때 쓰는 한 턴 피해 추정 **× 명중률**. 실제 엔진과 같은 스탯·특성·STAB·
    /// 상성 공식을 쓰되 급소와 난수는 평균화하지 않는다. 변화기는 실전 이득을 보장할 수 없어
    /// 0 점이라 공격기보다 뒤로 밀린다 — 회복·랭크업 전술을 지원할 때 별도 전략으로 승격하면 된다.
    ///
    /// 카탈로그 체육관 관장(`TeamPracticeBattle` 의 `.damageFocused`)과 공유 체육관의 AI 방어
    /// (`GymMatchEngine`)가 **같은 식을 써야** 두 컨텐츠의 체감이 갈리지 않는다.
    static func expectedDamageScore(of move: MoveSpec, from attacker: BattleSide, to defender: BattleSide) -> Int {
        // 실제로 나가는 형태로 재야 한다 — 테라버스트를 노말 특수기로 보면 AI 가 자기 최대 피해
        // 기술을 저평가한다(`applyHit` 과 같은 함수를 지난다).
        let move = move.asUsed(by: attacker)
        guard move.damageClass != .status, move.power > 0 else { return 0 }
        let effectiveness = typeMultiplier(of: move, against: defender)
        guard effectiveness > 0 else { return 0 }

        let isPhysical = move.damageClass == .physical
        let offense: BattleStat = isPhysical ? .atk : .spa
        let guardStat: BattleStat = isPhysical ? .def : .spd
        var power = move.power
        var attack = StatStages.apply(attacker.rawStat(offense), stage: attacker.stage(offense))
        if let ability = attacker.ability {
            attack = ability.adjustedAttack(attack, isPhysical: isPhysical, status: attacker.status)
            power = ability.adjustedPower(power, move: move)
        }
        if isPhysical, attacker.status == .burn, attacker.ability != .guts { attack /= 2 }
        var defense = StatStages.apply(defender.rawStat(guardStat), stage: defender.stage(guardStat))
        if let ability = defender.ability {
            defense = ability.adjustedDefense(defense, isPhysical: isPhysical, status: defender.status)
        }

        var damage = baseDamage(level: attacker.snapshot.level, power: power,
                                attack: attack, defense: defense) + 2
        damage = stabbed(damage, of: move.type, by: attacker)
        damage = TypeChart.apply(damage, of: move.type, against: defender.activeTypes)
        if let ability = defender.ability {
            damage = ability.adjustedDamage(damage, moveType: move.type, effectiveness: effectiveness)
        }
        let accuracy = min(100, max(0, hitChance(of: move, attacker: attacker, defender: defender) ?? 100))
        return max(0, damage) * accuracy
    }

    /// 혼란 자멸 데미지 — 무속성 물리 위력 40. 급소도 난수도 타지 않으므로 **rng 를 소비하지 않는다**
    /// (분기마다 소비량이 달라지면 두 피어가 갈라진다). 물리라서 화상 반감은 그대로 받는다(Gen 2).
    static func confusionDamage(_ side: BattleSide) -> Int {
        // 자기 공격·방어를 쓰니 자기 랭크도 탄다 — 공격 랭크만 보면 방어를 올린 개체가
        // 자멸 데미지를 그대로 받는다.
        let boosted = StatStages.apply(side.rawStat(.atk), stage: side.stage(.atk))
        let attack = side.status == .burn ? boosted / 2 : boosted
        let defense = StatStages.apply(side.rawStat(.def), stage: side.stage(.def))
        return max(1, baseDamage(level: side.snapshot.level, power: confusionPower,
                                 attack: attack, defense: defense) + 2)
    }

    /// 이 공격이 맞을 확률(%) — `nil` 은 필중기(명중 계산을 타지 않는다)다.
    ///
    /// **명중 랭크와 회피 랭크를 따로 곱한다**(Gen 2). 합산해 한 번만 곱하는 Gen 5+ 방식이면
    /// (명중 +1, 회피 +1) 이 100% 인데, Gen 2 는 133% × 75% = 99% 다. 회피는 상대의 명중을
    /// 깎으므로 부호를 뒤집어 같은 표를 읽는다. 100 초과는 그대로 둔다(안 빗나간다는 뜻이고,
    /// Gen 2 의 1/256 miss 는 §3.3 대로 뺐다).
    static func hitChance(of move: MoveSpec, attacker: BattleSide, defender: BattleSide) -> Int? {
        // 작아진 상대에게 플래그 달린 기술은 **명중을 굴리지 않는다**(쇼다운의 `onAccuracy` 가
        // true 를 돌려주는 자리). 올린 회피 랭크가 그 기술들에는 통하지 않는 것이 작아지기의 대가다.
        if defender.has(.minimize), ShowdownMoveData.hittingMinimizedHarder.contains(move.id) {
            return nil
        }
        // 미클열매를 먹은 개체의 다음 기술은 명중을 굴리지 않는다 — 끄는 자리는 `applyHit` 이다
        // (이 함수는 값 사본을 받으므로 여기서 끄면 아무 데도 남지 않는다).
        if attacker.nextMoveNeverMisses { return nil }
        guard !MoveSpec.neverMisses(move.accuracy), let accuracy = move.accuracy else { return nil }
        let withAccuracy = accuracy * StatStages.accuracyPercent(stage: attacker.stage(.accuracy)) / 100
        var chance = withAccuracy * StatStages.accuracyPercent(stage: -defender.stage(.evasion)) / 100
        // 명중을 손대는 지닌물건은 **랭크 뒤**에 곱한다(본가 순서). 두 방향을 각자 묻는 이유는
        // 물건이 다르기 때문이다: 올리는 것은 때리는 쪽(광각렌즈·포커스렌즈), 깎는 것은 맞는 쪽
        // (반짝가루·무사태평향로)이 쥔다.
        //
        // 포커스렌즈의 조건(상대가 이번 턴 이미 움직였나)을 여기서 묻는 이유는 이 함수가 명중을
        // 재는 **유일한 자리**라서다 — 부르는 자리마다 물으면 한 모드만 빠뜨렸을 때 그 모드에서만
        // 렌즈가 상시로 일한다.
        if let scale = attacker.heldEffect?.accuracyScale(targetAlreadyMoved: defender.movedThisTurn) {
            chance = chance * scale.numerator / scale.denominator
        }
        if let scale = defender.heldEffect?.foeAccuracyScale {
            chance = chance * scale.numerator / scale.denominator
        }
        return chance
    }

    /// 공격 1회 해상. **rng 소비 순서가 프로토콜의 일부다** — 명중 → 히트 수 →
    /// (가변위력 → 급소 → 난수 폭) × 히트. 빗나가면 뒤를 하나도 소비하지 않는다.
    /// 세 모드가 이 함수 하나만 쓴다(예전엔 복사돼 있었다).
    ///
    /// 순서를 이렇게 잡은 건 **안 뽑는 기술이 다수**라서다. 히트 수는 다단기만 뽑고
    /// (`min == max` 인 더블킥은 그조차 안 뽑는다), 가변위력은 매그니튜드·사이코웨이브만 뽑는다.
    /// 뒤로 미룰수록 "언제 뽑는지"가 급소·난수 폭과 얽혀 두 피어의 소비 횟수를 눈으로 못 센다.
    /// 두 피어는 같은 무브셋을 들고 있어 히트 수도 소비 횟수도 같다.
    ///
    /// 히트마다 급소·난수 폭을 다시 뽑는 것도 본가와 같다 — 5회 히트는 rng 를 10번 쓴다.
    ///
    /// ponytail: 가변위력기와 다단기가 겹치지 않는다는 전제로 위력을 루프 **안**에서 뽑는다.
    ///           오늘 도감(1~5세대 37개)에 겹치는 기술은 없어서 밟는 경로가 0 이다 — 생기면
    ///           히트마다 위력이 다시 뽑히므로 뽑기를 루프 앞으로 끌어올린다(rng 순서가
    ///           바뀌니 `rulesVersion` 도 같이 올린다).
    ///           전제가 깨지는 순간은 `BattleAssumptionGuardTests` 가 잡는다 — 가변위력 기술
    ///           목록을 동결해 두므로 `VariableDamage` 에 새 기술이 붙으면 거기서 빨개진다.
    static func resolveAttack(attacker: BattleSide, defender: BattleSide, move: MoveSpec,
                              field: BattleField = BattleField(),
                              attackerTeam: BattleTeamSlot = .a,
                              defenderTeam: BattleTeamSlot = .b,
                              rng: inout SplitMix64) -> AttackOutcome {
        // 독 타입이 쓰는 맹독은 명중·회피 랭크를 포함한 명중 판정을 건너뛴다.
        let poisonTypeToxic = move.id == MoveSpec.toxicMoveID && attacker.activeTypes.contains(.poison)
        if !poisonTypeToxic, let chance = hitChance(of: move, attacker: attacker, defender: defender),
           Int(rng.next() % 100) >= chance {
            return AttackOutcome(missed: true, damage: 0, effectiveness: 1, isCritical: false)
        }
        let requestedHits = move.hitCount(rng: &rng,
                                          minimumHits: attacker.heldEffect?.minimumMultiHits)
        // 남은 HP 는 지역에서 센다 — `defender` 는 값 사본이라 히트 사이에 줄지 않는다.
        // 안 세면 이미 쓰러진 상대를 남은 횟수만큼 계속 때린다.
        var remaining = defender.hp
        var total = 0, actualHits = 0, lastHit = 0
        var effectiveness = 1.0, critical = false, halved = false, gemUsed = false
        for index in 0..<requestedHits where remaining > 0 {
            let one = resolveSingleHit(attacker: attacker, defender: defender, move: move,
                                       hit: index, field: field, attackerTeam: attackerTeam,
                                       defenderTeam: defenderTeam, rng: &rng)
            total += one.damage
            remaining -= one.damage
            actualHits += 1
            lastHit = one.damage
            effectiveness = one.effectiveness
            critical = critical || one.isCritical
            halved = halved || one.berryHalved
            gemUsed = gemUsed || one.gemSpent
            if one.effectiveness == 0 { break }
        }
        // **다단기는 히트마다 열매를 쓰지 않는다** — 합계 한 번으로 깎고 한 번 소모한다(인내·
        // 기합의띠와 같은 이유: 이 엔진은 히트별로 HP 를 깎지 않아 히트 사이에 소모를 끼울 자리가
        // 없다). 본가는 첫 히트만 반감하므로 그만큼 이쪽이 맞는 쪽에 유리하다.
        return AttackOutcome(missed: false, damage: total, effectiveness: effectiveness,
                             isCritical: critical, hits: actualHits, lastHitDamage: lastHit,
                             berryHalved: halved, gemSpent: gemUsed)
    }

    /// 히트 하나. 다단기는 이 함수를 히트마다 부르므로 급소·난수 폭이 히트별로 독립이다
    /// (본가와 같다 — 한 번 뽑아 곱하면 급소가 나면 전 히트가 급소가 된다).
    private static func resolveSingleHit(attacker: BattleSide, defender: BattleSide,
                                         move: MoveSpec, hit: Int, field: BattleField,
                                         attackerTeam: BattleTeamSlot,
                                         defenderTeam: BattleTeamSlot,
                                         rng: inout SplitMix64) -> AttackOutcome {
        // PokéAPI 가 `power: null` 로 주는 공격기 — 위력을 여기서 뽑는다. `move.power` 는 0 이라
        // 그대로 쓰면 아래 식이 데미지를 0 으로 접는다(그게 이 기술들이 죽어 있던 원인이다).
        var power = move.power
        switch VariableDamage.from(move, attacker: attacker, defender: defender, hit: hit,
                                   field: field, attackerTeam: attackerTeam,
                                   defenderTeam: defenderTeam, rng: &rng) {
        case .power(let computed):  power = computed
        case .fixedHP(let amount):  return fixedOutcome(amount, move: move, defender: defender)
        case .oneHitKO:             return fixedOutcome(defender.hp, move: move, defender: defender)
        // 통하지 않음은 면역과 **같은 줄**로 낸다("효과가 없는 것 같다"). 데미지 0 으로 두면
        // `applyAttack` 이 이벤트를 안 내서 기술명 한 줄만 남는다.
        //
        // ponytail: 그래서 **실패와 면역이 `effectiveness == 0` 하나로 합쳐진다.** 흡수 특성은
        //           그 값 하나로 갈리므로, 물·전기 기술이 이 자리로 오면 저수·전기흡수가 실패한
        //           기술에서 회복한다. 오늘 `.noEffect` 로 오는 기술은 격투·풀·강철·불꽃·에스퍼·
        //           땅·노말·얼음뿐이라 밟는 경로가 0 이다 — 물·전기가 하나라도 생기면 `AttackOutcome`
        //           에서 실패를 면역과 갈라야 한다(0배 하나로는 구별할 수 없다).
        //           물·전기가 이 자리로 오는 순간은 `BattleAssumptionGuardTests` 가 잡는다 —
        //           `.noEffect` 를 낼 수 있는 기술 목록을 동결해 두므로 새 기술이 붙으면 빨개진다.
        case .noEffect:             return AttackOutcome(missed: false, damage: 0,
                                                        effectiveness: 0, isCritical: false)
        case nil:                   break
        }
        if let ability = attacker.ability { power = ability.adjustedPower(power, move: move) }
        // 충전은 전기 기술만, 방어태세는 구르기·아이스볼만 두 배로 만든다. **어느 기술인지는
        // 데이터가 답한다**(`ShowdownMoveData`) — 손 목록이면 세대마다 붙는 기술이 조용히 빠진다.
        // 가변위력을 뽑은 **뒤**라서 구르기의 연속 배율까지 함께 두 배가 된다(본가와 같다).
        // 도우미는 받은 쪽 개체에 붙는다 — 그 개체가 이번 턴에 내는 기술이 1.5 배가 된다.
        if attacker.has(.helpingHand) { power = power * 3 / 2 }
        if attacker.has(.charge), move.type == .electric { power *= 2 }
        if attacker.has(.defenseCurl), ShowdownMoveData.doubledByDefenseCurl.contains(move.id) {
            power *= 2
        }
        // 발버둥은 무속성(상성·STAB 미적용). 변화기도 상성을 타지 않는다 — 노말↔고스트 면역은
        // **데미지 기술의 규칙**이라, 이상한빛은 노말에게 노래는 고스트에게 통해야 한다.
        // 상성으로 막히는 상태기(전기자석파)만 `typeBlockedStatusMoveIDs` 에 명시한다.
        //
        // **`move.power` 가 아니라 위에서 뽑은 `power` 를 본다.** 일렉트릭볼은 스펙상 0 이지만
        // 공격기라 상성·STAB 를 타야 한다 — 스펙 값으로 판정하면 전기가 물에게 2배로 안 들어간다.
        // 고정 데미지·일격필살은 이 줄에 오기 전에 `fixedOutcome` 으로 빠져나가고, 거기서 면역만
        // 본다(카운터는 격투 데미지 기술이라 고스트에게 실패한다 — 그건 맞는 동작이다).
        let isStruggle = move.id == MoveSpec.struggleID
        let ignoresTypeChart = isStruggle
            || (power <= 0 && !MoveSpec.typeBlockedStatusMoveIDs.contains(move.id))
        // 상성과 타입 면역 특성은 `typeMultiplier` 한 곳에서 갈린다 — 공식을 안 타는 히트
        // (`fixedOutcome`)도 같은 함수를 본다. rng 를 안 쓰므로 소비 순서는 그대로다.
        //
        // 상성표를 안 보는 기술(발버둥·변화기)은 특성도 안 본다. 부유가 발버둥을 막으면 PP 가 마른
        // 쪽이 아무것도 못 하게 되고, 그 상태로는 배틀이 끝나지 않는다.
        let effectiveness = ignoresTypeChart ? 1.0 : typeMultiplier(of: move, against: defender)
        let isPhysical = move.damageClass == .physical
        // 런 강화의 급소 단계는 기술 단계에 더한다 — 표의 상한(3단계 = 100%)은 `critThreshold` 가
        // 이미 잠그므로 스택 수를 따로 자르지 않는다.
        // 기합충전(+2)·레이저포커스(+3)도 여기서 더한다. 둘이 겹쳐도 표가 3 단계에서 막히므로
        // 확정 급소보다 세지지 않는다 — 상한을 따로 자르지 않는 이유가 그것이다.
        let volatileCritStages = BattleVolatile.allCases
            .filter { attacker.has($0) }
            .reduce(0) { $0 + $1.critStages }
        let critStage = move.critStage + attacker.runBoosts.critStages + volatileCritStages
            + (attacker.heldEffect?.bonusCritStages ?? 0)
        // 급소 판정은 **행운의부적이 있어도 그대로 굴린다** — 뽑는 횟수가 갈리면 그 뒤 모든 판정이
        // 밀린다. 막는 것은 결과뿐이다.
        let rolledCritical = rng.next() % critDenominator < critThreshold(stage: critStage)
        let isCritical = rolledCritical && !field.blocksCrit(against: defenderTeam)
        // 급소는 **불리한 랭크만** 무시한다(Gen 3+): 공격측의 마이너스와 방어측의 플러스가 빠진다.
        // 전부 무시하는 Gen 1·2 방식이면 랭크를 올린 쪽이 급소에서 손해를 봐 올릴 이유가 없어진다.
        let offense: BattleStat = isPhysical ? .atk : .spa
        let guardStat: BattleStat = isPhysical ? .def : .spd
        let offenseStage = isCritical ? max(0, attacker.stage(offense)) : attacker.stage(offense)
        let guardStage = isCritical ? min(0, defender.stage(guardStat)) : defender.stage(guardStat)
        // 화상은 **물리** 공격만 절반이다(Gen 2 는 공격 스탯을 반으로 깎는다). 특수기는 그대로다 —
        // 여기서 분류를 안 보면 화상이 공격 전체를 깎는 다른 게임이 된다.
        var attack = StatStages.apply(attacker.rawStat(offense), stage: offenseStage)
        if let ability = attacker.ability {
            attack = ability.adjustedAttack(attack, isPhysical: isPhysical, status: attacker.status)
        }
        // 근성은 화상의 공격 감소를 무시한다. 다른 물리 특성은 기존 화상 반감을 그대로 받는다.
        if isPhysical, attacker.status == .burn, attacker.ability != .guts { attack /= 2 }
        // 런 강화의 공격 스택. 화상 반감 **뒤**에 곱한다 — 앞에 두면 정수 나눗셈이 강화분을 먼저
        // 깎아, 같은 스택이 화상 여부에 따라 다른 값을 낸다.
        attack = attacker.runBoosts.scaled(attack, stacks: attacker.runBoosts.attack)
        // 종 전용 물건의 능력치 배율(전기구슬·굵은뼈·마음의물방울) — 화상 반감·런 강화 **뒤**다.
        // 앞에 두면 정수 나눗셈이 배율분을 먼저 깎아 같은 물건이 상태에 따라 다른 값을 낸다.
        if let scale = attacker.heldEffect?.statScale(offense) {
            attack = attack * scale.numerator / scale.denominator
        }
        var defense = StatStages.apply(defender.rawStat(guardStat), stage: guardStage)
        if let ability = defender.ability {
            defense = ability.adjustedDefense(defense, isPhysical: isPhysical, status: defender.status)
        }
        defense = defender.runBoosts.scaled(defense, stacks: defender.runBoosts.defense)
        // 맞는 쪽 몫도 같은 축이다(금속파우더의 방어, 마음의물방울의 특방).
        if let scale = defender.heldEffect?.statScale(guardStat) {
            defense = defense * scale.numerator / scale.denominator
        }
        // 돌격조끼는 **막아 주는 계통**으로 묻는다(물건 이름을 직접 보면 두 번째 조끼가 늘 때
        // 이 자리만 빠진다). 데미지가 아니라 방어 스탯에 곱하는 자리는 본가와 같다.
        if defender.heldEffect?.guardedDamageClass == move.damageClass {
            defense = defense * HeldItemBalance.assaultVestNumerator
                / HeldItemBalance.assaultVestDenominator
        }
        // Gen 2 난수는 217~255 균등 **정수**를 뽑아 255 로 정수 나눗셈한다. 예전엔
        // `0.85 + (rng % 16)/100` 이라 0.01 간격 Double 이었다 — 두 피어가 각자 계산하는
        // 구조에서는 정수 연산이 유리하다(부동소수 오차가 끼어들 자리가 없다).
        let random = 217 + Int(rng.next() % 39)

        // 기본 데미지의 `+2` 뒤에 현행 급소 ×1.5를 적용하고, STAB·상성은 그 뒤에 곱한다.
        // (배지·트레이너킥·기술보정은 §3.3 대로 안 가져온다. 날씨는 아래에서 곱한다.)
        var damage = baseDamage(level: attacker.snapshot.level, power: power,
                                attack: attack, defense: defense)
        damage += 2
        if isCritical { damage = damage * 3 / 2 }
        // 위의 `effectiveness` 와 **같은 게이트**여야 한다. 예전 `!isStruggle` 은 위력 0 이
        // 데미지를 접어 준 덕에 우연히 같았을 뿐이다(위력 있는 무상성 기술이 생기면 갈라진다).
        if !ignoresTypeChart {
            damage = stabbed(damage, of: move.type, by: attacker)
            damage = TypeChart.apply(damage, of: move.type, against: defender.activeTypes)
        }
        if let ability = defender.ability {
            damage = ability.adjustedDamage(damage, moveType: move.type, effectiveness: effectiveness)
        }
        // 런 강화의 타입 데미지. 상성표를 안 보는 기술(발버둥·변화기)은 여기도 안 탄다 — 플레이트가
        // 발버둥을 올리면 PP 가 마른 뒤가 오히려 강해진다.
        if !ignoresTypeChart { damage = attacker.runBoosts.damage(damage, moveType: move.type) }
        // 날씨 보정 — 상성표를 보는 기술만 탄다(발버둥은 무속성이라 볕이 세게 만들 이유가 없다).
        // 정수 분수로 곱한다. 위 주석이 "날씨는 안 가져온다" 였던 자리다 — 날씨 레이어가 생겨서
        // 그 유예가 끝났다.
        // 만능우산을 쥔 쪽은 볕·비를 안 본다 — **때리는 쪽** 기준이다(본가와 같다: 위력 보정은
        // 기술을 내는 개체가 날씨를 어떻게 겪는지의 문제다).
        if !ignoresTypeChart, let weather = field.weather,
           attacker.heldEffect?.ignoresWeatherPowerScale != true {
            let scale = weather.damageScale(of: move.type)
            damage = damage * scale.numerator / scale.denominator
        }
        // 필드 보정 — **땅에 닿은 쪽만** 받는다. 올려 주는 쪽은 공격자 기준(그래스필드에서 뜬
        // 포켓몬이 쓰는 풀 기술은 안 오른다), 미스트필드의 드래곤 반감은 맞는 쪽 기준이다.
        if !ignoresTypeChart, let terrain = field.terrain {
            if terrain.boostedType == move.type, BattleField.isGrounded(attacker) {
                damage = damage * 13 / 10
            }
            if terrain == .misty, move.type == .dragon, BattleField.isGrounded(defender) {
                damage /= 2
            }
        }
        // 작아진 상대는 **플래그 달린 기술**(발구르기 부류)에 두 배로 맞는다. 위력이 아니라
        // 데미지에 곱하는 자리가 쇼다운과 같다(`onSourceModifyDamage`) — 위력에 곱하면 식의
        // `+2` 와 급소 배율이 배가 되는 값 앞에 들어가 두 배가 정확히 두 배가 아니게 된다.
        if defender.has(.minimize), ShowdownMoveData.hittingMinimizedHarder.contains(move.id) {
            damage *= 2
        }
        // 생명의구슬은 **공식을 타는 히트에만** 얹는다 — 고정 데미지·일격필살은 이 줄에 오기 전에
        // `fixedOutcome` 으로 빠져나가므로 저절로 제외된다(본가와 같다). 위력이 아니라 데미지에
        // 곱하는 자리는 작아지기 두 배와 같은 이유다: 위력에 곱하면 식의 `+2` 와 급소 배율이
        // 배가 되는 값 앞에 들어가 1.3배가 정확히 1.3배가 아니게 된다.
        if attacker.heldEffect == .lifeOrb {
            damage = damage * HeldItemBalance.lifeOrbNumerator / HeldItemBalance.lifeOrbDenominator
        }
        // 타입 강화 도구 — 상성표를 보는 기술만 탄다(런 강화의 타입 데미지와 같은 게이트다:
        // 도구가 발버둥을 올리면 PP 가 마른 뒤가 오히려 강해진다). 물건이 아니라
        // `boostedMoveTypes` 로 묻는다.
        if !ignoresTypeChart, attacker.heldEffect?.boostedMoveTypes.contains(move.type) == true {
            damage = damage * HeldItemBalance.typeEnhancerNumerator
                / HeldItemBalance.typeEnhancerDenominator
        }
        // 주얼 — 타입 강화 도구와 같은 게이트(상성표를 보는 기술만)에 배율만 크고 1회용이다.
        // 소모는 `applyHit` 이 한다(이 함수는 `attacker` 의 사본을 받아 여기서 지운 값이 안 나간다).
        var gemSpent = false
        if !ignoresTypeChart, attacker.heldEffect?.oneShotBoostedMoveType == move.type {
            damage = damage * HeldItemBalance.gemNumerator / HeldItemBalance.gemDenominator
            gemSpent = true
        }
        // 약점 반감 열매 — 맞는 쪽의 물건이라 여기서 **깎는다**. 상성표를 보는 기술만 탄다
        // (타입 강화 도구와 같은 게이트다): 상성이 곱해지지 않은 데미지에는 "약점을 막았다" 가
        // 성립하지 않는다. 소모는 여기서 하지 않는다 — 이 함수는 `defender` 의 사본을 받으므로
        // 여기서 지운 값은 밖으로 나가지 않는다. `berryHalved` 로 `applyHit` 에 넘긴다.
        var berryHalved = false
        if !ignoresTypeChart,
           defender.heldEffect?.halvesIncomingHit(moveType: move.type,
                                                  effectiveness: effectiveness) == true {
            damage = damage * HeldItemBalance.resistBerryNumerator
                / HeldItemBalance.resistBerryDenominator
            berryHalved = true
        }
        // 구애 2종도 같은 자리에서 얹는다 — 한 계통만 올리므로 물건이 아니라
        // `boostedDamageClass` 로 묻는다(물건 이름을 직접 보면 세 번째 구애가 늘 때 빠진다).
        if attacker.heldEffect?.boostedDamageClass == move.damageClass {
            damage = damage * HeldItemBalance.choiceNumerator / HeldItemBalance.choiceDenominator
        }
        // 일반 배틀 도구(힘의머리띠·박식안경·달인의띠·메트로놈)는 **한 물음**에 답한다 —
        // 재는 것은 서로 다르지만 곱하는 자리가 하나라서다. 상성표를 안 보는 기술은
        // `effectiveness` 가 1 이라 달인의띠가 저절로 빠진다(게이트를 따로 두지 않는 이유).
        if let scale = attacker.heldEffect?.outgoingDamageScale(
                damageClass: move.damageClass, effectiveness: effectiveness,
                consecutiveUses: attacker.consecutiveMoveUses, isPunch: move.isPunch) {
            damage = damage * scale.numerator / scale.denominator
        }
        // 장막은 **급소를 못 막는다**(3세대 이후). 급소가 뚫지 못하면 장막 한 장으로 판이 잠긴다.
        // 고정 데미지·일격필살은 여기 오기 전에 빠져나가므로 장막을 타지 않는다(본가와 같다).
        if !isCritical, field.halvesDamage(move.damageClass, against: defenderTeam) { damage /= 2 }
        damage = damage * random / 255
        // 위력 0(변화기)은 데미지가 없다. `max(1, …)` 만 두면 식의 `+2` 가 살아남아 상태기가 2 데미지를
        // 넣었다 — `learnedMoves` 는 변화기를 걸러내지 않으므로 실제로 밟히는 경로다.
        // rng 소비는 그대로다(명중 → 가변위력 → 급소 → 난수) — 값이 바뀌므로 `rulesVersion` 으로 막는다.
        let dealt = (effectiveness == 0 || power <= 0) ? 0 : max(1, damage)
        return AttackOutcome(missed: false, damage: dealt,
                             effectiveness: effectiveness, isCritical: isCritical,
                             berryHalved: berryHalved && dealt > 0,
                             gemSpent: gemSpent && dealt > 0)
    }

    /// 테라스탈 선언 — 개체를 테라스탈 상태로 만들고 줄 하나를 낸다. **난수를 쓰지 않는다.**
    ///
    /// 횟수 제약(진영당 한 번)은 모드가 들고 있고 이 함수는 그것을 묻지 않는다 — 이미 그 상태면
    /// 아무 일도 안 하고 빈 스트림을 낸다(같은 줄을 두 번 내면 로그가 거짓말을 한다).
    static func declareTerastal(_ side: inout BattleSide, actor: BattleActor) -> [BattleEvent] {
        guard side.isAlive, !side.isTerastallized else { return [] }
        side.isTerastallized = true
        return [.terastallized(actor, side.snapshot.teraType)]
    }

    /// 자기 타입 보정(STAB). 테라스탈 때문에 **세 갈래**다 — AI 추정과 실제 데미지가 같은
    /// 함수를 봐야 화면의 예상치와 결과가 갈라지지 않는다.
    ///
    /// - 평소: 자기 타입이면 1.5배.
    /// - 테라스탈: 테라 타입이면서 원래 타입이기도 하면 **2배**. 한쪽만 해당하면 1.5배 —
    ///   즉 접혀 나간 옛 타입 기술도 1.5배로 남는다(본가와 같다. "현재 타입만 STAB" 으로 짜면
    ///   그 기술만 조용히 약해지고 화면에 표시가 없다).
    ///
    /// "테라 타입이 원래에 없던 타입" 갈래는 테라피스(`ItemKind.teraShard`)로만 생긴다 —
    /// 그 아이템이 붙기 전에는 도달할 수 없는 갈래였다(`TeraShardTests` 가 셋을 다 잠근다).
    static func stabbed(_ damage: Int, of moveType: PokemonType, by attacker: BattleSide) -> Int {
        let isOriginal = attacker.snapshot.types.contains(moveType)
        guard attacker.isTerastallized else { return isOriginal ? damage * 3 / 2 : damage }
        let isTera = attacker.snapshot.teraType == moveType
        if isTera && isOriginal { return damage * 2 }
        return (isTera || isOriginal) ? damage * 3 / 2 : damage
    }

    /// 턴 순서에 쓰는 스피드 — 개체 상태(`BattleSide.effectiveSpeed`) 위에 **편에 깔린 것**을 얹는다.
    ///
    /// 순서 계산이 모드마다 따로라(1v1 `resolveTurn`·방·웨이브) 이 함수 하나를 지나게 한다.
    /// 한 모드가 `effectiveSpeed` 를 직접 읽으면 그 모드에서만 순풍이 없고, 화면에는 아무 오류도
    /// 안 보인다 — 그래서 `BattleTailwindTests` 가 순서를 재는 소스 자리를 스캔한다.
    /// 스피드를 위력으로 읽는 기술(일렉트릭볼·자이로볼)도 이 값을 봐야 순서와 위력이 갈라지지 않는다.
    static func orderingSpeed(_ side: BattleSide, team: BattleTeamSlot, field: BattleField) -> Int {
        field.has(.tailwind, for: team) ? side.effectiveSpeed * 2 : side.effectiveSpeed
    }

    /// 두 공격자 중 누가 먼저인가 — 본가와 같은 순서로 본다: **기술 우선도 → 스피드 → 무작위**.
    ///
    /// 무작위는 앞의 둘이 모두 같을 때만 소비한다(예전 1v1 규칙 그대로). 멀티는 이 자리에서
    /// UUID 문자열 순서로 갈랐는데, 그러면 앱을 켠 동안 사전순으로 앞선 참가자가 동점 때마다
    /// 선공을 가져간다 — 실력과 무관한 데다 화면에 드러나지도 않는다.
    static func firstMoverIsA(priorityA: Int, priorityB: Int, speedA: Int, speedB: Int,
                              movesLastA: Bool = false, movesLastB: Bool = false,
                              movesFirstA: Bool = false, movesFirstB: Bool = false,
                              rng: inout SplitMix64) -> Bool {
        if priorityA != priorityB { return priorityA > priorityB }
        // 선공 물건(선제공격손톱·애슈열매)은 우선도 **뒤**, 후공 물건 **앞**이다 — 우선도는 못
        // 이기지만 느림보꼬리를 쥔 상대보다는 먼저 움직인다(본가와 같은 순서).
        if movesFirstA != movesFirstB { return movesFirstA }
        if movesLastA != movesLastB { return movesLastB }
        if speedA != speedB { return speedA > speedB }
        return rng.next() & 1 == 0
    }

    /// 이 개체가 같은 우선도 안에서 **뒤로 밀리는가** — 느림보꼬리·만복향로다.
    ///
    /// 순서를 재는 자리가 모드마다 따로라(1v1 `resolveTurn`·방·웨이브) 이 함수 하나를 지나게
    /// 한다. 한 모드가 물건을 안 물으면 그 모드에서만 후공이 없고 화면에는 아무 오류도 안 보인다 —
    /// 순풍(`orderingSpeed`)과 같은 함정이라, 같은 방식으로 소스 스캔이 자리를 센다.
    static func movesLast(_ side: BattleSide) -> Bool { side.heldEffect?.movesLast == true }

    /// 이 개체가 이번 턴 **선공을 가져갔는가** — 선제공격손톱·애슈열매다. 굴린 결과를 읽기만
    /// 한다(`BattleEngine.rollTurnStartItems` 가 턴 머리에서 굴린다).
    ///
    /// 순서를 재는 자리가 모드마다 따로라 이 함수 하나를 지나게 한다 — 후공 물건과 같은 함정이고
    /// 같은 방식으로 소스 스캔이 자리를 센다.
    static func movesFirst(_ side: BattleSide) -> Bool { side.actsFirstThisTurn }

    /// 턴 머리에서 물건이 굴리는 것 — 선공(선제공격손톱·애슈열매)과 다음 기술의 필중(미클열매)이다.
    ///
    /// **순서를 재기 전에** 부른다. 굴린 값을 `BattleSide` 에 적어 두는 이유는 정렬이다: 비교
    /// 클로저 안에서 굴리면 난수 소비가 정렬 알고리즘의 비교 횟수에 딸려간다.
    ///
    /// 물건이 답하지 않는 개체에서는 난수를 **한 번도 쓰지 않는다** — 두 피어는 서로의 물건을
    /// 스냅샷으로 알고 있으므로 소비 횟수가 갈리지 않는다.
    static func rollTurnStartItems(_ side: inout BattleSide, actor: BattleActor,
                                   rng: inout SplitMix64) -> [BattleEvent] {
        side.actsFirstThisTurn = false
        guard side.isAlive, let effect = side.heldEffect, let item = side.activeHeldItem else {
            return []
        }
        let pinched = side.hp * HeldItemBalance.pinchThresholdDivisor <= side.stats.hp
        var events: [BattleEvent] = []
        if let chance = effect.turnStartHurryChance(pinched: pinched),
           Int(rng.next() % 100) < chance {
            side.actsFirstThisTurn = true
            if effect.isConsumedWhenHurrying { side.heldItemConsumed = true }
            events.append(.heldItemTriggered(actor, item))
        }
        // 미클열매는 확률이 아니라 위급 조건만 본다 — 난수를 쓰지 않는다.
        if pinched, effect.makesNextMoveHitAtPinch {
            side.nextMoveNeverMisses = true
            side.heldItemConsumed = true
            events.append(.heldItemTriggered(actor, item))
        }
        return events
    }
}

// MARK: - 이벤트 스트림

/// 이벤트가 가리키는 쪽. 1v1 LAN·연습 배틀은 좌우 두 자리뿐이고(엔진 좌변이 항상 challenger),
/// 2~4인 방은 참가자가 여럿이라 UUID 로 가른다.
enum BattleActor: Codable, Sendable, Equatable, Hashable {
    case a, b
    case fighter(UUID)
}

/// 배틀에서 일어난 일 하나 — Showdown 의 `|move|`·`|-damage|`·`|-crit|` 처럼 **타입된** 이벤트다.
/// 로그·HP바·애니메이션은 전부 이 스트림의 렌더러다. 플래그 묶음(`missed`/`damage`/…)으로는
/// "화상으로 깎였다"·"마비로 못 움직였다" 를 표현할 수 없어 case 로 바꿨다.
/// 새 case 는 **그것을 내보내는 코드와 함께** 추가한다 — 아무도 밟지 않는 분기를 미리 두지 않는다.
enum BattleEvent: Codable, Sendable, Equatable {
    case turn(Int)
    case move(BattleActor, moveID: Int)
    case miss(BattleActor)
    case immune(BattleActor)
    case crit(BattleActor)
    case superEffective(BattleActor)
    case resisted(BattleActor)
    /// 실제로 깎인 양. 남은 HP 는 싣지 않는다 — 뷰는 `BattleSide.hp` 를 그대로 읽으므로 읽는 데가
    /// 없다. 재생 애니메이션(Phase 7)이 바를 보간할 때 필요해지면 그때 붙인다.
    case damage(BattleActor, amount: Int, cause: DamageCause)
    /// 회복량. **원인은 싣지 않는다** — 지금 내는 건 드레인 하나뿐이고, 무엇으로 회복했는지는
    /// 바로 앞 줄의 기술명이 이미 말한다. 문구를 갈라야 하는 두 번째 발신자(특성 흡수, Phase 5)가
    /// 생기면 그때 붙인다. 아무도 밟지 않는 분기를 미리 두지 않는다.
    case heal(BattleActor, amount: Int)
    case multiHit(BattleActor, hits: Int)
    /// 날씨가 시작됐다 / 끝났다. 액터가 없다 — 판 전체의 상태라 어느 쪽의 줄도 아니다.
    case weatherStarted(BattleWeather)
    case weatherEnded(BattleWeather)
    case terrainStarted(BattleTerrain)
    case terrainEnded(BattleTerrain)
    /// 한쪽 진영에만 깔린 상태 — 어느 편인지가 문구의 절반이다("우리 편은/상대 편은").
    case sideConditionStarted(BattleTeamSlot, BattleSideCondition)
    case sideConditionEnded(BattleTeamSlot, BattleSideCondition)
    /// 테라스탈했다 — 액터와 그 개체가 된 타입. 배틀당 한 번뿐이라 로그에 한 줄이면 충분하다.
    case terastallized(BattleActor, PokemonType)
    /// 개체에 붙은 상태가 붙었다 / 풀렸다. 진영 상태와 달리 **주인이 있다** — 누구에게 붙은
    /// 조이기인지가 문구의 절반이다.
    case volatileStarted(BattleActor, BattleVolatile)
    case volatileEnded(BattleActor, BattleVolatile)
    /// 붙어 있던 상태가 **일했다** — 인내로 버텼다 / 운명공동체로 데려갔다 / 원한으로 PP 를 앗았다.
    /// 액터는 그 상태의 **주인**이다(버틴 쪽·쓰러진 쪽). 붙는 줄(`volatileStarted`)과 나누는 이유는
    /// 시점이다: 셋은 붙는 턴이 아니라 쓰러지는 순간에 일하고, 그 순간에 줄이 없으면 상대가 왜
    /// 같이 쓰러졌는지 로그로 설명되지 않는다.
    case volatileTriggered(BattleActor, BattleVolatile)
    /// 지니고 있던 물건이 **일했다** — 기합의띠로 버텼다. 액터는 그 물건의 **주인**이다.
    ///
    /// `volatileTriggered` 를 쓸 수 없다: 지닌물건은 volatile 이 아니라 개체에 붙은 물건이고,
    /// 문구도 "무엇으로 버텼는지" 를 말해야 한다(어휘를 합치면 "인내로 버텼다" 와 구별되지 않는다).
    /// 생명의구슬의 자해는 이 case 가 아니라 `.damage(cause: .recoil)` 이다 — 반동은 반동이다.
    case heldItemTriggered(BattleActor, ItemKind)
    /// 이번 턴 몸을 지켰다 / 그 방어가 상대의 기술을 막았다. 액터는 **지킨 쪽**이다 —
    /// 막힌 줄이 누구의 방어인지가 문구의 절반이고, 공격자는 바로 앞 줄이 이미 말한다.
    case guardUp(BattleActor)
    case guardBlocked(BattleActor)
    case faint(BattleActor)
    /// 새 개체가 필드에 나왔다 — 자기 교체(턴 머리)와 기절 자동 출전(턴 끝) 양쪽이 이 case 다.
    ///
    /// **재생기가 개체 전환을 알아야 하는 이유**: 표시 상태가 활성 칸을 모르면 기절 턴에 새로 나온
    /// 만피 포켓몬을 이전 개체의 HP 로 깎아 그린다(그리고 `isAlive == false` 라 흐린 스프라이트로).
    /// 실을 수 있는 건 **팀 인덱스뿐**이다 — 이 스트림은 와이어에 실리므로(멀티 `roundResolved`)
    /// `BattleSide` 를 담을 수 없고, 들어온 개체의 상태는 받는 쪽이 자기 팀에서 읽는다.
    /// (Showdown 의 `|switch|` 가 남은 HP 를 같이 싣는 것과 다른 선택이다: 여기선 받는 쪽이
    /// 같은 팀 배열을 들고 있어 인덱스만으로 충분하다.)
    case sendOut(BattleActor, teamIndex: Int)
    /// 상태가 붙었다 / 나았다 / 그 상태 때문에 이번 턴을 못 썼다.
    case status(BattleActor, Status)
    case cureStatus(BattleActor, Status)
    case cant(BattleActor, Status)
    /// 잠금 때문에 이번 턴 그 기술을 못 냈다 — 선택은 끝났는데 행동 직전에 막힌 경우다
    /// (`MoveSelectionLock.blocksExecution`). `.cant` 와 갈라 두는 이유는 사유의 축이 달라서다:
    /// 저쪽은 주 상태이상(`Status`)이고 이쪽은 선택 잠금이라, 한 case 로 접으면 둘 중 하나가
    /// 자기 사유를 말할 수 없다.
    case moveBlocked(BattleActor, MoveSelectionLock)
    /// 랭크가 움직였다 — 값은 **실제로 적용된 양**이다(±6 에 닿아 0 이면 이 이벤트가 나가지 않는다).
    /// Showdown 의 `|-boost|`·`|-unboost|` 를 부호 하나로 합쳤다.
    case boost(BattleActor, BattleStat, Int)
}

// MARK: - 네트워크 대전 턴 해상

extension BattleEngine {
    /// 상태를 실제로 붙인다. 붙지 않으면(면역·이미 다른 주 상태·기절) 빈 배열이다.
    ///
    /// **rng 는 카운터가 필요한 상태(잠듦·혼란)에서만 소비한다.** 붙을 수 있는지를 먼저 보고
    /// 그 뒤에만 뽑으므로, 두 피어가 같은 상태를 보고 있으면 소비량도 같다.
    @discardableResult
    static func inflict(_ status: Status, on side: inout BattleSide, actor: BattleActor,
                        rng: inout SplitMix64) -> [BattleEvent] {
        guard side.canBeAfflicted(by: status) else { return [] }
        switch status {
        case .confusion:
            side.confusionTurns = 2 + Int(rng.next() % 4)      // 2~5턴
        case .sleep:
            side.status = .sleep
            side.statusCounter = 2 + Int(rng.next() % 3)       // 카운터 2~4 → 행동불능 1~3턴
        case .toxic:
            side.status = .toxic
            side.statusCounter = 1                             // 1/16 부터 매턴 1/16 누적
        default:
            side.status = status
            side.statusCounter = 0
        }
        return [.status(actor, status)]
    }

    /// 턴 끝 잔뎀 — 화상은 1/16, 독은 1/8, 맹독은 n/16 으로 매턴 커진다. 개체에 붙은
    /// volatile(조이기·저주·나이트메어의 잔뎀, 아쿠아링·뿌리박기의 회복)도 같은 자리에서 본다.
    ///
    /// 순서는 **회복 전부 → 주 상태 → volatile 잔뎀**이고, 기절 줄은 **맨 끝에 한 번**이다.
    /// 회복을 뒤로 밀면 잔뎀으로 쓰러진 개체가 그 턴에 되살아나고, 기절을 잔뎀마다 내면 같은
    /// 개체가 한 턴에 두 번 쓰러진다(재생이 그대로 두 번 그린다).
    ///
    /// rng 를 쓰지 않으므로 호출 순서만 고정하면 두 피어가 같은 값을 본다.
    static func endOfTurnResidual(_ side: inout BattleSide, actor: BattleActor) -> [BattleEvent] {
        guard side.isAlive else { return [] }
        var events: [BattleEvent] = []
        let full = side.stats.hp
        // 런 강화의 턴 끝 회복은 **잔뎀보다 먼저**다(본가와 같다). 만피면 회복량이 0 이라
        // 이벤트도 나가지 않는다.
        //
        // **런 강화의 회복과 지닌물건의 회복은 합산한다.** 둘은 사는 자리가 다르다 — 스택은 판
        // 안에서만 살고(`RunBoosts`), 지닌물건은 개체에 붙어 와이어에 실린다. 그래서 웨이브 런에서
        // 둘이 겹치는 판이 실제로 있고, 한쪽만 보는 구현은 그 판에서 회복을 조용히 잃는다.
        // 줄은 **한 줄**이다: 같은 턴의 같은 회복을 두 줄로 내면 로그가 두 번 회복한 것처럼 읽힌다.
        //
        // 물건이 회복인지 데미지인지는 **물건이 답한다**(`endOfTurnHPChange`) — 검은오물은 지닌
        // 개체의 타입에 따라 둘 다 되므로, 이름을 직접 보는 자리를 두면 그 물건이 반쪽만 일한다.
        let itemChange = side.heldEffect?.endOfTurnHPChange(holderTypes: side.activeTypes)
        var itemHeal = 0
        if case .heal(let divisor)? = itemChange { itemHeal = max(1, full / divisor) }
        let heal = min(side.runBoosts.leftoversHeal(maxHP: full) + itemHeal, full - side.hp)
        if heal > 0 {
            side.hp += heal
            events.append(.heal(actor, amount: heal))
        }
        events += volatileRecovery(&side, actor: actor)
        if let hurt = statusResidual(&side) {
            side.hp = max(0, side.hp - hurt.amount)
            events.append(.damage(actor, amount: hurt.amount, cause: hurt.cause))
        }
        events += volatileResidual(&side, actor: actor)
        // 생명의구슬의 대가 — **매 턴** 최대 HP 의 1/10 이다. 본가는 공격할 때마다지만, 이 엔진은
        // 광역기가 대상마다 `applyHit` 을 부르므로 그 자리에 두면 대상 수만큼 중복 과금된다.
        // 턴 끝 한 자리에 모으면 네 모드가 같은 규칙을 받고 난수도 안 쓴다(두 피어가 같은 값을 본다).
        // 원인은 `.recoil` 을 쓴다 — 반동을 두 어휘로 나누면 로그가 같은 일을 다르게 말한다.
        if side.isAlive, side.heldEffect == .lifeOrb {
            let cost = min(max(1, full / HeldItemBalance.lifeOrbRecoilDivisor), side.hp)
            side.hp -= cost
            events.append(.damage(actor, amount: cost, cause: .recoil))
        }
        // 검은오물의 데미지 몫 — 회복과 **같은 축**의 반대쪽이다. 생명의구슬 자해와 같은 자리에
        // 두는 이유도 같다: 잔뎀 뒤라야 이번 턴 깎인 HP 로 판단하고, 쓰러진 개체에게 다시 얹지 않는다.
        if side.isAlive, case .hurt(let divisor)? = itemChange {
            let cost = min(max(1, full / divisor), side.hp)
            side.hp -= cost
            events.append(.damage(actor, amount: cost, cause: .heldItem))
        }
        // 구슬 2종 — 턴 끝에 주인에게 상태를 건다. **잔뎀 뒤**다: 앞에 두면 구슬을 쥔 그 턴부터
        // 깎이고, `isAlive` 로 막지 않으면 그 턴에 쓰러진 개체가 기절 줄 뒤에 화상을 얻는다.
        //
        // rng 를 안 쓰는 자리라 여기에 넘길 난수원이 없다. 구슬이 거는 상태(화상·맹독)는
        // `inflict` 에서 카운터를 뽑지 않으므로 지역 난수원을 넘겨도 두 피어가 갈리지 않는다 —
        // 그 사실을 아래 단언이 지킨다(잠듦·혼란을 구슬에 붙이는 날 여기가 터진다).
        if side.isAlive, let orbStatus = side.heldEffect?.selfInflictedStatus {
            var unusedRNG = SplitMix64(seed: 0)
            events += inflict(orbStatus, on: &side, actor: actor, rng: &unusedRNG)
            assert(unusedRNG.state == SplitMix64(seed: 0).state,
                   "구슬이 난수를 소비했다 — 턴 끝 자리에는 두 피어가 공유하는 난수원이 없다")
        }
        // 위급 열매는 잔뎀·자해 **뒤**다: 앞에 두면 이번 턴 깎이기 전 HP 로 판단해 임계를 놓친다.
        events += triggerPinchBerry(&side, actor: actor)
        if !side.isAlive { events.append(.faint(actor)) }
        return events
    }

    /// 위급 열매 — HP 가 최대의 1/4 **이하**면 한 번 일하고 사라진다. 난수를 쓰지 않는다.
    ///
    /// 부르는 자리는 둘이다: 히트 뒤(`applyHit`)와 턴 끝(`endOfTurnResidual`). 그 둘 밖에서 HP 가
    /// 줄면(혼란 자멸·반동) 열매는 다음 턴 끝에 터진다 — 한 턴 늦지만 네 모드가 같은 자리에서
    /// 같은 값을 본다.
    ///
    /// **본가와 갈리는 점**: "임계를 넘어선 순간" 이 아니라 "지금 임계 이하인가" 를 묻는다. 넘어선
    /// 순간을 세려면 개체마다 직전 HP 를 들고 다녀야 하고, 그 값은 네 모드가 각자 갱신해야 해서 한
    /// 모드만 빠뜨리면 거기서만 열매가 안 터진다. 소모가 1회용을 보장하므로 결과는 같다.
    static func triggerPinchBerry(_ side: inout BattleSide, actor: BattleActor) -> [BattleEvent] {
        guard side.isAlive, let action = side.heldEffect?.pinchAction,
              let item = side.activeHeldItem,
              side.hp * HeldItemBalance.pinchThresholdDivisor <= side.stats.hp else { return [] }
        side.heldItemConsumed = true
        var events: [BattleEvent] = [.heldItemTriggered(actor, item)]
        switch action {
        case .raiseBest:
            // 능력치가 가장 높은 축을 올린다 — 본가의 무작위를 대신한다(턴 끝에는 두 피어가
            // 공유하는 난수원이 없다). 같은 값이면 나열 순서가 정하므로 두 피어가 같은 답을 낸다.
            let stat = HeldItemEffect.pinchRaisedStats.max {
                side.rawStat($0) < side.rawStat($1)
            } ?? .atk
            let applied = side.changeStage(stat, by: HeldItemBalance.pinchStatStages)
            if applied != 0 { events.append(.boost(actor, stat, applied)) }
        case .raise(let stat):
            // 랭크가 이미 +6 이면 적용량이 0 이고 줄도 안 나간다 — 열매는 그래도 사라진다
            // (본가와 같다: 먹은 뒤에 "효과가 없었다" 다).
            let applied = side.changeStage(stat, by: HeldItemBalance.pinchStatStages)
            if applied != 0 { events.append(.boost(actor, stat, applied)) }
        case .sharpenCrit:
            if side.start(.focusEnergy) { events.append(.volatileStarted(actor, .focusEnergy)) }
        case .heal:
            events += heal(&side, actor: actor,
                           upTo: side.stats.hp / HeldItemBalance.pinchHealDivisor)
        }
        return events
    }

    /// 씨뿌리기의 턴 끝 — 깎은 만큼 씨를 뿌린 쪽이 회복한다.
    ///
    /// **두 개체를 동시에 만지는 유일한 턴 끝 효과**라 잔뎀(`endOfTurnResidual`, 개체 하나)과 자리를
    /// 따로 뒀다: 깎는 쪽과 받는 쪽이 다른 배열에 있는 모드가 둘이다(웨이브·방). 받는 쪽을 인자로
    /// 받는 이유도 그것이다 — 뿌린 자리(`BattleSide.leechSeedSource`)가 어느 배열의 몇 번째인지는
    /// 모드만 안다. **잔뎀 뒤에 부른다**: 그 앞에 두면 화상으로 쓰러질 개체에게서 먼저 빨아낸다.
    ///
    /// 뿌린 쪽이 쓰러져 있으면 깎기만 하고 회복은 없다(본가와 같다). rng 는 쓰지 않는다.
    ///
    /// 이 함수를 빠뜨린 턴 루프는 `BattleVolatileTests` 가 소스에서 찾아낸다 — 한 모드만 안 부르면
    /// 그 모드에서 씨뿌리기가 아무 일도 하지 않고, 화면에는 정상으로 보인다.
    static func endOfTurnLeechSeed(seeded: inout BattleSide, seededActor: BattleActor,
                                   seeder: inout BattleSide, seederActor: BattleActor) -> [BattleEvent] {
        guard seeded.isAlive, seeded.has(.leechSeed) else { return [] }
        let amount = max(1, seeded.stats.hp / BattleVolatile.leechSeedDivisor)
        seeded.hp = max(0, seeded.hp - amount)
        var events: [BattleEvent] = [.damage(seededActor, amount: amount, cause: .leechSeed)]
        if seeder.isAlive { events += heal(&seeder, actor: seederActor, upTo: amount) }
        if !seeded.isAlive { events.append(.faint(seededActor)) }
        return events
    }

    /// 주 상태이상이 이번 턴 깎는 몫. 깎지 않는 상태(마비·잠듦·얼음·혼란·풀죽음)는 `nil` 이다.
    /// 맹독은 여기서 누적 배수를 올린다 — 깎는 자리와 세는 자리가 갈리면 한쪽만 고치게 된다.
    private static func statusResidual(_ side: inout BattleSide) -> (amount: Int, cause: DamageCause)? {
        let full = side.stats.hp
        switch side.status {
        case .burn:   return (max(1, full / 16), .burn)
        case .poison: return (max(1, full / 8), .poison)
        case .toxic:
            defer { side.statusCounter += 1 }
            return (max(1, full * side.statusCounter / 16), .toxic)
        case .paralysis, .sleep, .freeze, .confusion, .flinch, nil: return nil
        }
    }

    /// volatile 의 턴 끝 **회복**(아쿠아링·뿌리박기). 잔뎀과 자리를 나눈 이유는 순서다 — 둘을 한
    /// 루프에서 돌리면 `allCases` 순서가 곧 "회복이 먼저인가" 를 정해 버린다.
    private static func volatileRecovery(_ side: inout BattleSide, actor: BattleActor) -> [BattleEvent] {
        var events: [BattleEvent] = []
        for volatileStatus in BattleVolatile.allCases {
            guard side.has(volatileStatus), let divisor = volatileStatus.healDivisor else { continue }
            let healed = min(max(1, side.stats.hp / divisor), side.stats.hp - side.hp)
            guard healed > 0 else { continue }        // 만피면 줄을 내지 않는다(0 회복은 거짓말이다)
            side.hp += healed
            events.append(.heal(actor, amount: healed))
        }
        return events
    }

    /// volatile 의 턴 끝 **잔뎀과 해제**. 조이기는 턴을 세고, 나이트메어는 상대가 깨면 그 자리에서
    /// 풀린다 — 해제 갈래가 없으면 조건이 사라진 뒤에도 HP 가 계속 빠진다.
    private static func volatileResidual(_ side: inout BattleSide, actor: BattleActor) -> [BattleEvent] {
        var events: [BattleEvent] = []
        for volatileStatus in BattleVolatile.allCases {
            guard let remaining = side.volatiles[volatileStatus] else { continue }
            // 나이트메어는 잠든 동안만 산다. 잠을 깬 턴에는 깎지 않고 풀린다.
            if volatileStatus == .nightmare, side.status != .sleep {
                side.volatiles[volatileStatus] = nil
                events.append(.volatileEnded(actor, volatileStatus))
                continue
            }
            // 쓰러진 뒤에는 남은 volatile 이 더 깎지도, 턴을 세지도 않는다 — 만지면 재생과
            // 엔진의 최종 HP 가 갈리고, 쓰러진 개체의 해제 줄이 기절 뒤에 하나 더 붙는다.
            guard side.isAlive else { continue }
            if let residual = volatileStatus.residualDamage {
                // 조이기만 분모가 걸릴 때 정해진다 — 조임밴드가 키운 값이 있으면 그것을 쓴다.
                let divisor = volatileStatus == .partiallyTrapped
                    ? (side.trapDamageDivisor ?? residual.divisor) : residual.divisor
                let amount = max(1, side.stats.hp / divisor)
                side.hp = max(0, side.hp - amount)
                events.append(.damage(actor, amount: amount, cause: residual.cause))
            }
            // 턴을 세는 것은 조이기·충전·레이저포커스다(`remaining` 0 은 무기한). 깎은 **뒤에**
            // 줄여야 4턴짜리가 네 번 깎는다 — 먼저 줄이면 마지막 턴이 잔뎀 없이 풀린다.
            // 잔뎀이 없는 부류도 여기서 세야 한다: 안 세면 충전이 영구 배율이 된다.
            guard remaining > 0 else { continue }
            if remaining <= 1 {
                side.volatiles[volatileStatus] = nil
                events.append(.volatileEnded(actor, volatileStatus))
            } else {
                side.volatiles[volatileStatus] = remaining - 1
            }
        }
        return events
    }

    /// 행동 가능 판정 — **잠듦 → 얼음 → 혼란 → 마비** 순서로 본다(Gen 2 의 검사 순서).
    /// 분기마다 rng 소비량이 달라지므로 이 순서가 곧 프로토콜이다. 상태는 스냅샷에 실려 오는 값이
    /// 아니라 배틀 중 파생값이라, `(스냅샷, seed, 행동열)` 만으로 두 피어가 같은 분기를 밟는다.
    private static func canAct(_ side: inout BattleSide, actor: BattleActor,
                               rng: inout SplitMix64, into events: inout [BattleEvent]) -> Bool {
        if side.flinched { events.append(.cant(actor, .flinch)); return false }
        if side.status == .sleep {
            // 카운터를 먼저 줄이고 0 이면 그 턴에 바로 움직인다 — Gen 1 처럼 깬 턴을 버리지 않는다.
            side.statusCounter -= 1
            if side.statusCounter <= 0 {
                side.status = nil
                side.statusCounter = 0
                events.append(.cureStatus(actor, .sleep))
            } else {
                events.append(.cant(actor, .sleep))
                return false
            }
        }
        if side.status == .freeze {
            if Int(rng.next() % 100) < thawChance {
                side.status = nil
                events.append(.cureStatus(actor, .freeze))
            } else {
                events.append(.cant(actor, .freeze))
                return false
            }
        }
        if side.isConfused {
            let hurtsItself = Int(rng.next() % 100) < confusionSelfHitChance
            side.confusionTurns -= 1                 // 남은 턴 수만큼 판정을 굴린다(2~5회)
            // 쓰러진 뒤에는 "혼란이 풀렸다" 를 쓰지 않는다 — 기절 다음 줄로 붙어 읽히기만 한다.
            defer { if side.confusionTurns == 0, side.isAlive { events.append(.cureStatus(actor, .confusion)) } }
            if hurtsItself {
                events.append(.cant(actor, .confusion))
                let damage = confusionDamage(side)
                side.hp = max(0, side.hp - damage)
                events.append(.damage(actor, amount: damage, cause: .confusion))
                if !side.isAlive { events.append(.faint(actor)) }
                return false
            }
        }
        if side.status == .paralysis, rng.next() % paralysisFailDenominator == 0 {
            events.append(.cant(actor, .paralysis))
            return false
        }
        return true
    }

    /// 만피를 넘지 않게 잘라 회복하고 **실제로 찬 만큼**만 줄을 낸다. 0 회복 줄은 로그가 거짓말을 한다.
    ///
    /// 드레인(기술)과 흡수 특성이 같은 상한 처리를 두 벌 들고 있으면 한쪽만 고치게 된다 — 빠뜨린
    /// 쪽은 만피를 넘겨 회복하고 HP 바가 최대치보다 길게 그려진다.
    private static func heal(_ side: inout BattleSide, actor: BattleActor, upTo amount: Int) -> [BattleEvent] {
        let healed = min(side.stats.hp - side.hp, amount)
        guard healed > 0 else { return [] }
        side.hp += healed
        return [.heal(actor, amount: healed)]
    }

    /// 자기 회복기(회복·아침햇살·광합성·달빛·둥지틀기·잠자기)를 처리한다.
    /// 회복기가 아니면 `nil` — 호출부가 보통 공격 경로로 넘어간다.
    ///
    /// **꽉 찼으면 실패시킨다.** 원작 규칙이자, 없으면 멀쩡한 상태에서 눌러 턴만 날리는 사고가 난다.
    /// 실패도 줄을 남긴다 — 데미지 0 은 무반응과 구별되지 않는다(이 파일이 여러 번 밟은 부류).
    ///
    /// rng 는 쓰지 않는다. 회복량이 최대 HP 비율로 고정이고 잠자기 턴도 고정이라, 두 피어의
    /// 소비 횟수가 이 분기에서 갈라지지 않는다.
    private static func selfHealing(of move: MoveSpec, user: inout BattleSide, actor: BattleActor,
                                    rng: inout SplitMix64) -> [BattleEvent]? {
        // **대상이 상대라고 적힌 스펙은 자기 회복으로 보지 않는다.** 잠자기는 id 로 가르는데,
        // id 만 보면 `targetsUser: false` 로 조작한 스펙이 "필중 100% 자기 전회복"이 아니라
        // 반대로 읽힐 여지가 남는다 — 무브셋은 피어가 보내는 값이다. nil(옛 세이브)은 통과시킨다.
        let isRest = move.id == MoveSpec.restMoveID && move.targetsUser != false
        let percent = move.healingPercent
        guard isRest || percent > 0 else { return nil }
        // 잠자기는 상태이상까지 지우므로 **만피여도 상태가 있으면 성공**한다(원작 규칙).
        // 그 예외가 없으면 독에 걸린 만피 개체가 해독할 방법을 잃는다.
        let missingHP = user.stats.hp - user.hp
        guard missingHP > 0 || (isRest && user.status != nil) else { return [.immune(actor)] }
        var events: [BattleEvent] = []
        if isRest {
            // 순서: 상태 해제 → 전회복 → 자기 수면. 회복을 먼저 내면 "독이 낫기 전에 회복했다"로
            // 읽히고, 수면을 먼저 걸면 아래 해제가 그 수면을 지운다.
            if let cured = user.status {
                user.status = nil
                user.statusCounter = 0
                events.append(.cureStatus(actor, cured))
            }
            events += heal(&user, actor: actor, upTo: user.stats.hp)
            user.status = .sleep
            user.statusCounter = MoveSpec.restSleepCounter
            events.append(.status(actor, .sleep))
        } else {
            events += heal(&user, actor: actor, upTo: user.stats.hp * percent / 100)
        }
        return events
    }

    /// 턴 끝의 날씨 몫 — **판 전체에 한 번**이 아니라 개체마다 부른다(모래는 양쪽을 깎는다).
    /// 잔뎀(`endOfTurnResidual`)과 나란히 서는 함수라 순서는 부르는 쪽이 정한다.
    static func endOfTurnWeather(_ side: inout BattleSide, actor: BattleActor,
                                 field: BattleField) -> [BattleEvent] {
        var events: [BattleEvent] = []
        // 씨앗 넷도 **땅에 닿은 쪽만** 받는다 — 필드 위에 서 있는 것이 방아쇠이기 때문이다.
        // 본가는 필드가 깔리는 순간 터지지만 이 엔진에는 출전 훅이 없어 여기서 본다(한 턴 늦다).
        if side.isAlive, let terrain = field.terrain, BattleField.isGrounded(side),
           let gains = side.heldEffect?.stageGainOnTerrain(terrain) {
            events += applyItemStageGains(gains, to: &side, actor: actor)
        }
        // 그래스필드는 땅에 닿은 쪽을 매 턴 회복시킨다 — 모래와 **같은 자리**에서 본다.
        // 회복이 먼저다: 모래에 깎여 쓰러진 뒤 되살아나는 순서가 되면 안 된다.
        if side.isAlive, field.terrain == .grassy, BattleField.isGrounded(side) {
            let healed = min(max(1, side.stats.hp / 16), side.stats.hp - side.hp)
            if healed > 0 {
                side.hp += healed
                events.append(.heal(actor, amount: healed))
            }
        }
        // 방진고글은 날씨의 턴 끝 데미지만 막는다 — 위력 보정(만능우산)은 여기를 지나지 않는다.
        guard side.isAlive, side.heldEffect?.blocksWeatherResidual != true,
              let weather = field.weather,
              let amount = weather.residualDamage(for: side.activeTypes, maxHP: side.stats.hp)
        else { return events }
        side.hp = max(0, side.hp - amount)
        events.append(.damage(actor, amount: amount, cause: .weather))
        if !side.isAlive { events.append(.faint(actor)) }
        return events
    }

    /// 날씨의 남은 턴을 하나 줄인다 — **턴마다 한 번**, 개체 수와 무관하게 부른다.
    /// 개체마다 부르면 2:2 에서 날씨가 절반만 간다.
    static func advanceField(_ field: inout BattleField) -> [BattleEvent] {
        var events: [BattleEvent] = []
        if let weather = field.weather {
            field.weatherTurns -= 1
            if field.weatherTurns <= 0 {
                field.weather = nil
                field.weatherTurns = 0
                events.append(.weatherEnded(weather))
            }
        }
        if let terrain = field.terrain {
            field.terrainTurns -= 1
            if field.terrainTurns <= 0 {
                field.terrain = nil
                field.terrainTurns = 0
                events.append(.terrainEnded(terrain))
            }
        }
        // 진영 상태는 편·상태 **둘 다 고정 순서**로 훑는다. 딕셔너리 순회는 실행마다 순서가
        // 달라져서, 그 순서가 이벤트에 남으면 두 피어의 로그가 갈린다.
        // 개인전 자리는 깔린 것이 있을 때만 생기므로 고정 두 자리에 더해 **키로 남은 것**까지 본다.
        // 정렬은 `sortKey` — 딕셔너리 순회 순서가 이벤트에 남으면 두 피어의 로그가 갈린다.
        let teams = (BattleTeamSlot.fixed + field.sideConditions.keys.filter { !BattleTeamSlot.fixed.contains($0) }
            .sorted { $0.sortKey < $1.sortKey })
        for team in teams {
            // 입장 데미지는 여기를 지나지 않는다 — 저장된 숫자가 남은 턴이 아니라 층 수라,
            // 같이 감소시키면 세 턴 뒤 압정이 조용히 사라진다.
            for condition in BattleSideCondition.allCases
            where !condition.isEntryHazard && field.has(condition, for: team) {
                let left = field.layers(condition, for: team) - 1
                if left <= 0 {
                    field.sideConditions[team]?[condition] = nil
                    events.append(.sideConditionEnded(team, condition))
                } else {
                    field.sideConditions[team]?[condition] = left
                }
            }
        }
        return events
    }

    /// 턴이 시작될 때 "이번 턴에 맞은 것" 을 비운다.
    ///
    /// **`applyAttack` 을 직접 부르는 모든 턴 루프가 이걸 먼저 불러야 한다.** 한 곳만 빠지면 그
    /// 모드에서만 카운터가 지난 턴 데미지를 되돌려준다 — 화면에는 정상으로 보이고 숫자만 틀린다.
    /// 빠뜨림은 `VariableDamageTests.testEveryTurnLoopClearsTheIncomingHit` 이 소스에서 막는다.
    static func beginTurn(_ side: inout BattleSide) {
        side.lastHitThisTurn = nil
        side.flinched = false
        side.movedThisTurn = false
        // 방어는 한 턴짜리다 — 안 비우면 한 번 성공한 방어가 배틀이 끝날 때까지 모든 공격을 막는다.
        side.isGuarding = false
    }

    /// 공격 1회를 해상해 양쪽 상태를 갱신하고, 그 결과를 이벤트로 남긴다.
    /// 1v1·연습·멀티가 전부 이 함수를 지나므로 **세 모드의 이벤트 어휘가 같다** — 데미지 함수를
    /// 하나로 모은 것(#46)과 배틀 상태를 `BattleSide` 로 모은 것(Phase 0)과 같은 이유다.
    /// 행동 가능 판정도 여기 있어야 세 모드가 상태이상을 같은 규칙으로 받는다.
    ///
    /// ponytail: 못 움직인 턴에도 PP 는 이미 호출부에서 깎인 뒤다(본가는 안 깎는다). 되돌리려면
    ///           기술 선택 자체를 엔진 안으로 옮겨야 하는데, 그건 교체(Phase 4)와 같이 할 일이다.
    ///           양쪽 피어가 똑같이 깎으므로 desync 는 없다.
    ///
    /// `attackerTeam`·`defenderTeam` 은 **진영 상태**(장막·부적)의 주인이다. 개체가 아니라 자리라서
    /// 인자로 받는다 — 모드마다 좌우가 다르고(멀티는 `.red`/`.blue`, 개인전은 참가자 하나가 한 편),
    /// 빠뜨리면 장막이 늘 좌변에 깔린다. 둘을 따로 받는 이유는 개인전이다: 상대가 "반대편" 하나로
    /// 정해지지 않는다.
    static func applyAttack(attacker: inout BattleSide, defender: inout BattleSide,
                            attackerActor: BattleActor, defenderActor: BattleActor,
                            move: MoveSpec, field: inout BattleField,
                            attackerTeam: BattleTeamSlot = .a, defenderTeam: BattleTeamSlot = .b,
                            rng: inout SplitMix64) -> [BattleEvent] {
        // 랭크에 답하는 물건(허브 3종)은 **기술이 끝난 뒤** 한 자리에서 본다. 랭크를 만지는 자리가
        // 여럿이라(2차효과·저주·필드) 자리마다 물으면 새 자리가 늘 때 그 경로에서만 허브가 죽는다.
        // 따라 올리려면 상대가 이번 기술에서 얼마나 올랐는지가 필요해서 앞뒤를 잰다.
        let attackerStagesBefore = attacker.stages
        let defenderStagesBefore = defender.stages
        var events = resolveAttackAction(attacker: &attacker, defender: &defender,
                                         attackerActor: attackerActor, defenderActor: defenderActor,
                                         move: move, field: &field, attackerTeam: attackerTeam,
                                         defenderTeam: defenderTeam, rng: &rng)
        events += settleStageItems(&attacker, actor: attackerActor,
                                   foeStagesBefore: defenderStagesBefore, foeStagesAfter: defender.stages)
        events += settleStageItems(&defender, actor: defenderActor,
                                   foeStagesBefore: attackerStagesBefore, foeStagesAfter: attacker.stages)
        return events
    }

    /// 물건이 올려 주는 랭크를 얹고 그 물건을 없앤다 — 방아쇠가 다른 열 물건이 **한 자리**를 쓴다.
    ///
    /// 랭크를 올리는 자리를 물건마다 두지 않는 이유는 소모 규칙이다: 올리는 것과 없애는 것이 늘
    /// 짝이라, 자리를 나누면 한쪽만 빠뜨린 물건이 무한히 랭크를 올린다. 올릴 랭크가 하나도 안
    /// 붙으면(±6 에 닿아 있으면) 물건도 남는다 — 아무 일도 없었는데 사라지면 로그가 거짓말을 한다.
    static func applyItemStageGains(_ gains: [StatChange], to side: inout BattleSide,
                                    actor: BattleActor) -> [BattleEvent] {
        guard side.isAlive, let item = side.activeHeldItem else { return [] }
        var events: [BattleEvent] = []
        for gain in gains {
            let applied = side.changeStage(gain.stat, by: gain.change)
            if applied != 0 { events.append(.boost(actor, gain.stat, applied)) }
        }
        guard !events.isEmpty else { return [] }
        side.heldItemConsumed = true
        return events + [.heldItemTriggered(actor, item)]
    }

    /// 접촉으로 맞은 쪽의 물건이 **때린 쪽에** 하는 일 — 울퉁불퉁멧은 깎고, 끈적끈적바늘은
    /// 옮겨 간다. 한 자리인 이유는 조건이 같아서다: 둘 다 "접촉으로 맞았다" 만 본다.
    ///
    /// 바늘이 옮겨 갈 자리는 **빈손일 때만** 이다(본가와 같다) — 안 보면 상대의 물건을 조용히
    /// 덮어써, 지니고 싸운 물건이 배틀 도중 사라진다.
    static func applyContactEffects(attacker: inout BattleSide, defender: inout BattleSide,
                                    attackerActor: BattleActor,
                                    defenderActor: BattleActor) -> [BattleEvent] {
        guard let effect = defender.heldEffect, let item = defender.activeHeldItem else { return [] }
        var events: [BattleEvent] = []
        if let divisor = effect.contactDamageDivisor {
            let amount = min(max(1, attacker.stats.hp / divisor), attacker.hp)
            attacker.hp -= amount
            events.append(.damage(attackerActor, amount: amount, cause: .heldItem))
            events.append(.heldItemTriggered(defenderActor, item))
        }
        if effect.transfersOnContact, attacker.activeHeldItem == nil || attacker.heldItemConsumed {
            defender.heldItemConsumed = true
            attacker.acquiredItem = item
            attacker.heldItemConsumed = false
            events.append(.heldItemTriggered(attackerActor, item))
        }
        return events
    }

    /// 기술 하나가 랭크·잠금에 남긴 것에 답하는 물건들 — 하양허브·흉내허브·멘탈허브.
    ///
    /// 세 물건을 한 함수에 두는 이유는 부르는 자리가 같아서다: 셋 다 "기술이 끝난 지금" 을 본다.
    /// 물건은 하나만 쥐므로 셋 중 하나만 답하고, 답한 물건은 그 자리에서 사라진다.
    static func settleStageItems(_ side: inout BattleSide, actor: BattleActor,
                                 foeStagesBefore: [BattleStat: Int],
                                 foeStagesAfter: [BattleStat: Int]) -> [BattleEvent] {
        guard let effect = side.heldEffect, let item = side.activeHeldItem, side.isAlive
        else { return [] }
        var events: [BattleEvent] = []
        if effect.copiesFoeStatBoosts {
            // **올라간 몫만** 따라간다(본가와 같다). 상대가 내려간 것까지 따라가면 물건이 벌이 된다.
            // 순서를 `allCases` 로 도는 이유는 두 피어의 로그를 같게 하려는 것이다(딕셔너리 순회는
            // 순서가 없다).
            for stat in BattleStat.allCases {
                let gained = (foeStagesAfter[stat] ?? 0) - (foeStagesBefore[stat] ?? 0)
                guard gained > 0 else { continue }
                let applied = side.changeStage(stat, by: gained)
                if applied != 0 { events.append(.boost(actor, stat, applied)) }
            }
        }
        if effect.restoresLoweredStages {
            for stat in BattleStat.allCases where side.stage(stat) < 0 {
                let applied = side.changeStage(stat, by: -side.stage(stat))
                if applied != 0 { events.append(.boost(actor, stat, applied)) }
            }
        }
        if effect.clearsSelectionLocks {
            // 어느 상태가 선택을 막는지는 **잠금 열거형이 답한다**(같은 case 이름을 쓴다) — 목록을
            // 여기 다시 적으면 새 잠금이 늘 때 이 자리만 옛 목록으로 남는다.
            for volatileStatus in BattleVolatile.allCases
            where volatileStatus.selectionLock != nil && side.has(volatileStatus) {
                side.volatiles[volatileStatus] = nil
                events.append(.volatileEnded(actor, volatileStatus))
            }
        }
        guard !events.isEmpty else { return [] }
        side.heldItemConsumed = true
        return events + [.heldItemTriggered(actor, item)]
    }

    private static func resolveAttackAction(attacker: inout BattleSide, defender: inout BattleSide,
                                            attackerActor: BattleActor, defenderActor: BattleActor,
                                            move: MoveSpec, field: inout BattleField,
                                            attackerTeam: BattleTeamSlot,
                                            defenderTeam: BattleTeamSlot,
                                            rng: inout SplitMix64) -> [BattleEvent] {
        var events: [BattleEvent] = []
        guard beginAttack(attacker: &attacker, actor: attackerActor, move: move,
                          rng: &rng, into: &events) else { return events }
        // 방어기는 자기에게 건다 — 상대·상성·데미지를 통째로 건너뛴다.
        if BattleGuard.called(byMoveID: move.id) {
            return events + raiseGuard(user: &attacker, actor: attackerActor,
                                       defenderActor: defenderActor, rng: &rng)
        }
        // 인내도 방어기와 **같은 카운터**를 쓴다(`BattleVolatile.sharesGuardStreak`) — 아래 연속
        // 끊기보다 앞이어야 자기 카운터를 스스로 지우지 않는다. 막는 게 아니라 버티는 것이라
        // `BattleGuard` 가 아니지만, 연속 사용 벌점은 하나를 나눠 쓴다.
        if let selfVolatile = BattleVolatile.called(byMoveID: move.id), selfVolatile.sharesGuardStreak {
            return events + raiseEndure(selfVolatile, user: &attacker, actor: attackerActor,
                                        defenderActor: defenderActor, rng: &rng)
        }
        // 편 방어기(와이드가드 부류)는 편 전체를 지킨다 — 개인 방어와 **같은 카운터**를 쓴다.
        // 여기가 연속 끊기(아래 줄)보다 앞이어야 자기 카운터를 스스로 지우지 않는다.
        if let teamGuard = BattleSideCondition.called(byMoveID: move.id), teamGuard.guardsTheTeam {
            return events + raiseTeamGuard(teamGuard, user: &attacker, actor: attackerActor,
                                           defenderActor: defenderActor, team: attackerTeam,
                                           field: &field, rng: &rng)
        }
        // 방어기가 아닌 기술을 냈으면 연속 성공은 끊긴다 — 안 끊으면 한 번 쌓은 확률 벌점이
        // 배틀 끝까지 남아, 사이에 다른 기술을 낀 방어가 이유 없이 실패한다.
        attacker.guardStreak = 0
        // 필드기도 상대를 보지 않는다 — 날씨기와 같은 자리다.
        if let terrain = BattleTerrain.called(byMoveID: move.id) {
            attacker.lastMoveFailed = !field.start(
                terrain, turns: attacker.heldEffect?.extendedTurns(of: .terrain(terrain))
                    ?? BattleTerrain.duration)
            return events + (attacker.lastMoveFailed ? [.immune(defenderActor)]
                                                     : [.terrainStarted(terrain)])
        }
        // 진영 상태기는 데미지·상성을 보지 않는다. **어느 편에 까는지는 데이터가 답한다** —
        // 장막·순풍은 자기 편이고 압정 부류는 상대 편이다. 열거형에서 파생하면 데이터를 두 번
        // 적는 셈이라, 쇼다운이 같은 상태를 양쪽에 까는 기술을 더하면 조용히 어긋난다.
        if let condition = BattleSideCondition.called(byMoveID: move.id) {
            let team = BattleSideCondition.landsOnFoeSide(moveID: move.id) ? defenderTeam
                                                                           : attackerTeam
            attacker.lastMoveFailed = !field.start(
                condition, for: team,
                turns: attacker.heldEffect?.extendedTurns(of: .sideCondition(condition)))
            return events + (attacker.lastMoveFailed ? [.immune(defenderActor)]
                                                     : [.sideConditionStarted(team, condition)])
        }
        // 대타출동은 자기에게 걸지만 **대가와 층 HP** 가 있어 아래 갈래로 다룰 수 없다. 아래는
        // `start` 만 부르므로 여기 두지 않으면 HP 를 안 내고 층도 0 인 인형이 선다.
        if BattleVolatile.called(byMoveID: move.id) == .substitute {
            // **쉐도우테일의 교체는 아직 없다.** 교체 게이트가 네 모드와 터미널 UI 에 흩어져 있어
            // 엔진 안에서 부를 자리가 없다 — 그 자리를 만들 때(항목 8 이후) 여기서 함께 부른다.
            // 지금은 대가가 비싼 대타출동으로 나간다.
            let raised = attacker.raiseSubstitute(
                costDivisor: ShowdownMoveData.substituteCostDivisor[move.id] ?? 4)
            attacker.lastMoveFailed = !raised
            return events + (raised ? [.volatileStarted(attackerActor, .substitute)]
                                    : [.immune(defenderActor)])
        }
        // 자기에게 거는 volatile(아쿠아링·뿌리박기)도 상대를 보지 않는다 — 진영 상태기와 같은 자리다.
        // 이미 붙어 있으면 실패한다(매 턴 다시 걸면 실패 없는 무한 회복이 된다).
        if let volatileStatus = BattleVolatile.called(byMoveID: move.id), volatileStatus.targetsUser {
            let started = attacker.start(volatileStatus, turns: volatileStatus.selfDuration)
            var applied: [BattleEvent] = started ? [.volatileStarted(attackerActor, volatileStatus)] : []
            // **랭크도 같이 오르는 부류가 있다**(작아지기 회피 +2·방어태세 방어 +1·충전 특방 +1).
            // 이 갈래가 조기반환하므로 `applyStatChanges` 를 여기서 직접 불러야 한다 — 안 부르면
            // 작아지기가 회피를 하나도 안 올린다(이 다섯을 volatile 로 옮기기 전에는 올랐다).
            // 두 번째 사용도 랭크는 오른다(본가와 같다): 그래서 실패 판정은 `started` 가 아니라
            // **아무 일도 없었는가**로 본다.
            applied += applyStatChanges(of: move, attacker: &attacker, defender: &defender,
                                        attackerActor: attackerActor, defenderActor: defenderActor,
                                        field: field, defenderTeam: defenderTeam, rng: &rng)
            attacker.lastMoveFailed = applied.isEmpty
            return events + (applied.isEmpty ? [.immune(defenderActor)] : applied)
        }
        // 날씨기는 상대를 보지 않는다 — 자기 회복기와 같은 자리에서 빠져나간다.
        if let weather = BattleWeather.called(byMoveID: move.id) {
            attacker.lastMoveFailed = !field.start(
                weather, turns: attacker.heldEffect?.extendedTurns(of: .weather(weather))
                    ?? BattleWeather.duration)
            // 같은 날씨를 다시 걸면 아무 일도 없다. 변화기가 아무것도 못 한 다른 경우와 같은 줄이다.
            return events + (attacker.lastMoveFailed ? [.immune(defenderActor)]
                                                     : [.weatherStarted(weather)])
        }
        // 자기 회복기는 상대를 보지 않는다 — 명중·상성·데미지 계산을 통째로 건너뛴다.
        // `resolveAttack` 에 태우면 위력 0 이라 rng 만 태우고 아무것도 안 하는 기술이 된다.
        if let restored = selfHealing(of: move, user: &attacker, actor: attackerActor, rng: &rng) {
            attacker.lastMoveFailed = false
            return events + restored
        }
        events += applyHit(attacker: &attacker, defender: &defender,
                           attackerActor: attackerActor, defenderActor: defenderActor,
                           move: move, field: field, attackerTeam: attackerTeam,
                           defenderTeam: defenderTeam, rng: &rng)
        events += faintFromSelfDestruct(move, attacker: &attacker, actor: attackerActor)
        return events
    }

    /// 방어기 한 번 — 성공하면 이번 턴 자기를 지키고 연속 횟수를 올린다.
    ///
    /// 연속으로 쓰면 확률이 1/3, 1/9, 1/27… 로 떨어진다(본가·쇼다운과 같은 식). **rng 는 연속일
    /// 때만 뽑는다** — 첫 방어에서 뽑으면 방어를 넣은 뒤 모든 판정이 한 칸씩 밀려, 같은 seed 로
    /// 예전 판이 재현되지 않는다(연속 방어는 예전에 존재하지 않던 경로라 밀릴 판이 없다).
    private static func raiseGuard(user: inout BattleSide, actor: BattleActor,
                                   defenderActor: BattleActor,
                                   rng: inout SplitMix64) -> [BattleEvent] {
        let succeeded = guardSucceeds(streak: user.guardStreak, rng: &rng)
        user.lastMoveFailed = !succeeded
        user.isGuarding = succeeded
        // 실패하면 연속이 끊긴다 — 안 끊으면 한 번 실패한 뒤로 확률이 영영 회복되지 않는다.
        user.guardStreak = succeeded ? user.guardStreak + 1 : 0
        return succeeded ? [.guardUp(actor)] : [.immune(defenderActor)]
    }

    /// 편 방어기 한 번 — 성공하면 **편에** 한 턴짜리 상태가 깔린다.
    ///
    /// 확률·카운터는 개인 방어와 **하나를 공유한다**(본가와 같다). 따로 두면 방어와 와이드가드를
    /// 번갈아 눌러 벌점 없는 무적이 된다. 이미 깔려 있으면(같은 턴에 두 번) 실패다 — 다른 진영
    /// 상태와 같은 규칙이고, 성공 판정을 지난 뒤에 보므로 rng 소비는 성공·실패에서 같다.
    private static func raiseTeamGuard(_ condition: BattleSideCondition, user: inout BattleSide,
                                       actor: BattleActor, defenderActor: BattleActor,
                                       team: BattleTeamSlot, field: inout BattleField,
                                       rng: inout SplitMix64) -> [BattleEvent] {
        let succeeded = guardSucceeds(streak: user.guardStreak, rng: &rng)
            && field.start(condition, for: team)
        user.lastMoveFailed = !succeeded
        user.guardStreak = succeeded ? user.guardStreak + 1 : 0
        return succeeded ? [.sideConditionStarted(team, condition)] : [.immune(defenderActor)]
    }

    /// 인내 한 번 — 성공하면 이번 턴 쓰러지지 않는 상태가 자기에게 붙는다.
    ///
    /// 확률·카운터는 방어기와 **하나를 공유한다**(본가와 같다). 이미 붙어 있으면(같은 턴에 두 번)
    /// 실패고, 성공 판정을 지난 뒤에 보므로 rng 소비는 성공·실패에서 같다 — `raiseTeamGuard` 와
    /// 같은 모양이다.
    private static func raiseEndure(_ volatileStatus: BattleVolatile, user: inout BattleSide,
                                    actor: BattleActor, defenderActor: BattleActor,
                                    rng: inout SplitMix64) -> [BattleEvent] {
        let succeeded = guardSucceeds(streak: user.guardStreak, rng: &rng)
            && user.start(volatileStatus, turns: volatileStatus.selfDuration)
        user.lastMoveFailed = !succeeded
        user.guardStreak = succeeded ? user.guardStreak + 1 : 0
        return succeeded ? [.volatileStarted(actor, volatileStatus)] : [.immune(defenderActor)]
    }

    /// 방어 성공 판정 — 연속 성공 횟수만큼 확률이 1/3^n 로 떨어진다.
    ///
    /// **rng 는 연속일 때만 뽑는다.** 첫 방어에서 뽑으면 방어를 넣은 뒤 모든 판정이 한 칸씩 밀려,
    /// 같은 seed 로 예전 판이 재현되지 않는다. 개인 방어와 편 방어기가 이 한 함수를 공유한다.
    private static func guardSucceeds(streak: Int, rng: inout SplitMix64) -> Bool {
        var odds = 1
        for _ in 0..<streak { odds *= BattleGuard.consecutiveFailureBase }
        return odds == 1 || Int(rng.next() % UInt64(odds)) == 0
    }

    /// 공격의 **머리** — 행동 가능 판정과 `.move` 줄. 대상이 몇이든 여기는 **한 번만** 지난다.
    ///
    /// 광역기(`MoveSpec.hitsSpread`)를 위해 따로 뺐다. 대상마다 `applyAttack` 을 부르면 마비·잠듦·
    /// 혼란 판정이 대상 수만큼 굴러서 rng 소비가 달라지고(같은 seed 로 판이 재현되지 않는다),
    /// 한 대상에게는 움직이고 다른 대상에게는 못 움직이는 턴이 생기며, 로그에 기술명이 두 줄 남는다.
    ///
    /// `false` 면 못 움직였다 — 사유(`.cant`·혼란 자멸)는 `events` 에 들어간다.
    static func beginAttack(attacker: inout BattleSide, actor: BattleActor, move: MoveSpec,
                            rng: inout SplitMix64, into events: inout [BattleEvent]) -> Bool {
        // 행동을 쓴 것은 여기까지 왔다는 뜻이다 — 기술이 나갔는지와 무관하다(못 움직인 턴도 쓴 턴이다).
        attacker.movedThisTurn = true
        // 못 움직이면 `.move` 자체가 나가지 않는다 — Showdown 도 `|move|` 대신 `|cant|` 를 보낸다.
        guard canAct(&attacker, actor: actor, rng: &rng, into: &events) else {
            // 기술이 아예 나가지 않았다 — 연속은 끊기고, 직전 기술은 실패로 친다.
            attacker.consecutiveMoveUses = 0
            attacker.lastMoveID = nil
            attacker.lastMoveFailed = true
            return false
        }
        // 선택이 끝난 뒤에 걸린 잠금은 여기서 막는다 — 도발을 건 쪽이 먼저 움직이면 맞은 쪽은
        // 이번 턴 기술을 이미 골라 둔 상태다. 선택 게이트(`BattleSide.selectionLock(for:)`)만
        // 두면 그 턴은 그대로 나가 도발이 한 턴 늦게 듣는다. **어느 잠금이 여기까지 막는지는
        // 잠금이 답한다**(`blocksExecution`) — 트집·앙코르는 본가도 선택만 막는다.
        //
        // PP 는 여기서 돌려주지 않는다: 모드 네 곳이 `beginAttack` 을 부르기 **전에** 이미 깎고,
        // 잠듦·마비로 못 움직인 턴도 같은 자리에서 깎여 왔다. 이 게이트만 예외로 두면 같은
        // "못 움직인 턴" 이 사유에 따라 PP 를 다르게 쓴다.
        if let lock = attacker.selectionLock(for: move), lock.blocksExecution {
            events.append(.moveBlocked(actor, lock))
            attacker.consecutiveMoveUses = 0
            attacker.lastMoveID = nil
            attacker.lastMoveFailed = true
            return false
        }
        // 운명공동체·원한은 **주인이 움직이는 순간** 풀린다(본가와 같다). 못 움직인 턴(잠듦·마비)에는
        // 위에서 조기반환하므로 그대로 살아 있다 — 그것도 본가와 같다.
        for volatileStatus in BattleVolatile.allCases where volatileStatus.endsOnNextMove {
            guard attacker.volatiles[volatileStatus] != nil else { continue }
            attacker.volatiles[volatileStatus] = nil
            events.append(.volatileEnded(actor, volatileStatus))
        }
        // 위력을 **뽑기 전에** 올린다 — 리프블레이드는 첫 사용이 1회차(기본 위력)여야 한다.
        if attacker.lastMoveID == move.id {
            attacker.consecutiveMoveUses += 1
        } else {
            attacker.lastMoveID = move.id
            attacker.consecutiveMoveUses = 1
        }
        // 구애는 **실제로 기술이 나간 순간** 묶는다(선택한 순간이 아니다) — 못 움직인 턴에 묶으면
        // 잠깨기·마비로 굳은 턴이 기술을 하나 정해 버린다. 무브셋에 없는 기술(발버둥)은 묶지
        // 않는다: 묶으면 그 뒤로 고를 수 있는 칸이 하나도 없다.
        if attacker.heldEffect?.locksIntoOneMove == true, attacker.choiceLockedMoveID == nil,
           attacker.moves.contains(where: { $0.id == move.id }) {
            attacker.choiceLockedMoveID = move.id
        }
        events.append(.move(actor, moveID: move.id))
        return true
    }

    /// 자폭기(命がけの突撃)는 데미지를 넣은 **뒤에** 자기가 쓰러진다. 광역기면 대상 전원을 때린
    /// 다음이라, 이 판정이 대상 루프 **밖**에 있어야 기절 줄이 대상 수만큼 나가지 않는다.
    static func faintFromSelfDestruct(_ move: MoveSpec, attacker: inout BattleSide,
                                      actor: BattleActor) -> [BattleEvent] {
        guard VariableDamage.userFaints(after: move), attacker.isAlive else { return [] }
        attacker.hp = 0
        return [.faint(actor)]
    }

    /// 다인전에서 이 공격이 **실제로 향하는 자리** — 유도(따라와·성원·스포트라이트)가 끼어든다.
    ///
    /// 두 모드(웨이브 런·방)가 이 한 함수를 쓴다. 각자 자기 배열에서 판정하면 한쪽에서만 유도가
    /// 듣고 화면에는 정상으로 보인다 — 모드마다 배열 모양이 다를 뿐 규칙은 하나다.
    ///
    /// `candidates` 는 **맞을 자리(방어 편)의 살아 있는 개체들**이고, 순서가 곧 동점의 승자다
    /// (무작위로 고르면 같은 seed 의 판이 재현되지 않는다). 끌려가지 않으면 `nil` 이다.
    ///
    /// 광역기와 자기 대상 기술은 애초에 끌 자리가 없다 — 전자는 이미 전원을 때리고, 후자는
    /// 상대를 보지 않는다.
    static func redirectedTarget<Slot>(move: MoveSpec, attacker: BattleSide,
                                       candidates: [(slot: Slot, side: BattleSide)])
        -> (slot: Slot, volatileStatus: BattleVolatile)? {
        guard !move.hitsSpread, move.targetsUser != true else { return nil }
        var best: (slot: Slot, volatileStatus: BattleVolatile)?
        for candidate in candidates where candidate.side.isAlive {
            for volatileStatus in BattleVolatile.allCases where volatileStatus.drawsAttacks {
                guard candidate.side.has(volatileStatus) else { continue }
                // 풀 타입은 성원의 가루를 무시한다(본가와 같다). 따라와는 가루가 아니라 그대로 끈다.
                if volatileStatus.ignoredByGrassTypes,
                   attacker.activeTypes.contains(.grass) { continue }
                if volatileStatus.drawPriority > (best?.volatileStatus.drawPriority ?? 0) {
                    best = (candidate.slot, volatileStatus)
                }
            }
        }
        return best
    }

    /// 대상 **하나**에 실제로 적용한다 — 명중·상성·데미지·2차효과·랭크·기절. `.move` 줄은 이
    /// 함수가 내지 않는다(`beginAttack` 의 몫이다).
    ///
    /// `damageScale` 은 광역기가 둘 이상을 때릴 때의 감쇠(본가 4세대 이후 0.75)다. 1 이면 단일
    /// 타겟과 한 값도 다르지 않다 — 세 모드(1v1·연습·LAN)가 지나는 길은 늘 1 이다.
    static func applyHit(attacker: inout BattleSide, defender: inout BattleSide,
                         attackerActor: BattleActor, defenderActor: BattleActor,
                         move: MoveSpec, damageScale: Double = 1,
                         field: BattleField = BattleField(),
                         attackerTeam: BattleTeamSlot = .a,
                         defenderTeam: BattleTeamSlot = .b,
                         rng: inout SplitMix64) -> [BattleEvent] {
        // 상대가 이번 턴 몸을 지켰으면 여기서 끝난다 — 명중·데미지·상태·랭크 전부 건너뛴다.
        //
        // **`applyAttack` 이 아니라 여기서 본다.** 광역기는 대상마다 `applyHit` 을 직접 부르므로
        // (`WaveBattle`), 위에서 한 번만 보면 그 모드의 광역기가 방어를 통과한다 — 그리고 대상이
        // 여럿일 때 막은 쪽만 막히는 것이 본가와 같은 판정이다.
        // **자기에게 거는 기술은 막히지 않는다**(방어와 나 사이에는 아무것도 없다), 페인트 부류는
        // 데이터가 예외로 답한다.
        // 테라버스트는 여기서 실제로 나가는 형태가 된다 — 아래 전부(상성·STAB·분류)가 그 값을 본다.
        let move = move.asUsed(by: attacker)
        // 편 방어기(와이드가드 부류)는 **편에** 깔리므로 개인 방어와 조건이 다르지만 같은 자리에서
        // 본다 — 두 판정이 갈리면 광역기가 한쪽만 통과한다. 페인트 부류는 둘 다 뚫는다.
        let isBlockable = move.targetsUser != true && !BattleGuard.isIgnored(byMoveID: move.id)
        if isBlockable, defender.isGuarding || field.blocksMove(move, against: defenderTeam) {
            attacker.lastMoveFailed = true   // 분함의발구르기는 막힌 것도 실패로 센다(본가와 같다)
            return [.guardBlocked(defenderActor)]
        }
        // 층이 서 있으면 이 기술은 **인형에게** 간다. 자기에게 거는 기술은 층과 상관없고(방어와
        // 나 사이에 아무것도 없다), 층을 지나가는 기술은 데이터가 답한다(소리 기술 부류).
        let hitsSubstitute = defender.hasSubstitute && move.targetsUser != true
            && !ShowdownMoveData.bypassingSubstitute.contains(move.id)
        var events: [BattleEvent] = []
        // 목스프레이는 **소리 기술을 쓴 것만** 본다 — 맞았는지 빗나갔는지를 묻지 않으므로 명중
        // 판정 앞이다. 막힌 기술은 위에서 이미 돌아갔으니 여기 오지 않는다(쓰지 못한 턴이다).
        // 광역기가 대상마다 이 자리를 지나도 두 번 오르지 않는다: 첫 번에 소모된다.
        if move.isSound, let gains = attacker.heldEffect?.stageGainOnOwnSoundMove {
            events += applyItemStageGains(gains, to: &attacker, actor: attackerActor)
        }
        let outcome = resolveAttack(attacker: attacker, defender: defender, move: move,
                                    field: field, attackerTeam: attackerTeam,
                                    defenderTeam: defenderTeam, rng: &rng)
        // 미클열매의 필중은 **기술 하나짜리**다 — 명중 판정을 지난 지금 끈다(빗나갈 수 있었는지와
        // 무관하다: 필중 기술에 쓴 턴도 그 한 번으로 끝나는 것이 본가와 같다).
        attacker.nextMoveNeverMisses = false
        // 실패 여부는 **모든 갈래에서** 갱신한다. 성공 갈래만 내리면 한 번 실패한 뒤로 계속 실패로
        // 남아 분함의발구르기가 영원히 두 배가 된다. 광역기는 마지막 대상의 결과가 남는다 —
        // 본가도 여러 대상 중 하나만 실패한 턴을 실패로 세지 않는다.
        attacker.lastMoveFailed = outcome.missed || outcome.effectiveness == 0
        if outcome.missed {
            // 허탕보험은 **빗나간 그 자리**에서 답한다 — 때린 쪽의 물건이라 아래 맞은 쪽 갈래와
            // 자리가 다르다.
            if let gains = attacker.heldEffect?.stageGainOnOwnMiss {
                events += applyItemStageGains(gains, to: &attacker, actor: attackerActor)
            }
            return events + [.miss(attackerActor)]
        }
        if outcome.effectiveness == 0 {
            events.append(.immune(defenderActor))
            // 흡수 특성(저수·전기흡수)은 무효 **위에** 회복을 얹는다. 만피면 회복량이 0 이라 줄을
            // 내지 않지만 무효는 그대로다 — 회복만 확인하면 만피에서 데미지가 들어가도 초록이다.
            // 부유처럼 흡수가 아닌 면역은 여기 안 걸린다(면역 전부를 회복으로 만들면 안 된다).
            // 쓰러진 쪽은 회복하지 않는다 — 이 파일의 다른 회복·부여가 전부 `isAlive` 를 먼저 본다.
            if defender.isAlive, defender.ability?.absorbs(move.type) == true {
                events += heal(&defender, actor: defenderActor, upTo: defender.stats.hp / 4)
            }
            return events
        }
        if outcome.hits > 1 { events.append(.multiHit(attackerActor, hits: outcome.hits)) }
        // 급소·상성 문구가 데미지보다 먼저 온다(Showdown 순서) — 재생할 때 "급소!" 뒤에 HP 가 줄어든다.
        // 고정 데미지·일격필살은 `fixedOutcome` 이 급소를 false, 상성을 1 로 두므로 여기 안 걸린다 —
        // 공식을 안 탄 기술에 "효과가 굉장했다" 를 붙이면 상성이 곱해진 것처럼 읽힌다.
        //
        // **변화기에는 급소·상성 문구를 안 붙인다.** 깎을 데미지가 없어서 배율이 아무 데도 안 쓰이는데,
        // 전기자석파(상성표를 보는 유일한 상태기)가 물 타입에게 "효과가 굉장했다" 를 달면 마비가 2배로
        // 걸린 것처럼 읽힌다. 무효(0배)는 위에서 이미 처리했다 — 그건 실제로 실패했다는 뜻이라 남긴다.
        if move.damageClass != .status {
            if outcome.isCritical { events.append(.crit(defenderActor)) }
            if outcome.effectiveness > 1 { events.append(.superEffective(defenderActor)) }
            else if outcome.effectiveness < 1 { events.append(.resisted(defenderActor)) }
        }
        // 감쇠는 **0 을 만들지 않는다** — 1 이라도 들어가야 "맞았는데 안 깎였다"가 안 된다.
        var damage = scaled(outcome.damage, by: damageScale)
        // 인내는 **기술 데미지로만** 버틴다 — 남은 HP 하나를 남기고 자른다(쇼다운 `onDamage` 와 같은
        // 자리다). 잔뎀·혼란 자멸은 여기를 지나지 않으므로 그쪽으로는 쓰러진다(본가와 같다).
        // 다단기는 합계로 한 번 자른다 — 이 엔진이 히트별로 HP 를 깎지 않기 때문이다.
        // 인내·기합의띠는 **주인이 맞을 때만** 답한다. 층이 받는 데미지에 걸면 인형 하나로
        // 그 배틀의 인내·띠가 소모된다(주인의 HP 는 한 칸도 안 줄었는데).
        let endured = !hitsSubstitute && defender.has(.endure) && damage >= defender.hp
        if endured { damage = defender.hp - 1 }
        // 기합의띠도 같은 자리에서 자른다. 조건은 본가와 같다: **만피**에서 맞은 치명적인 한 방
        // 하나다(만피가 아니어도 버티면 HP 1 짜리 무적이 된다).
        // 다단기는 합계로 한 번 자른다 — 인내와 같은 이유다(엔진이 히트별로 HP 를 깎지 않는다).
        // 잔뎀·혼란 자멸은 여기를 지나지 않으므로 그쪽으로는 쓰러진다(인내와 같다).
        //
        // **인내와 겹칠 때 `endured` 를 따로 묻지 않는다.** 위에서 인내가 이미 데미지를 `hp - 1` 로
        // 잘랐으므로 아래의 `damage >= defender.hp` 가 거짓이 된다 — 그것이 "둘 다 발동하지
        // 않는다" 를 보장하는 유일한 이유다. `!endured` 를 덧붙여 두면 그 가드가 **도달 불가한
        // 죽은 조건**이 되어, 인내의 자르기를 없애는 결함이 들어와도 이 자리는 초록으로 남는다
        // (결함 주입에서 실제로 그렇게 지나갔다).
        let sashed = !hitsSubstitute && defender.heldEffect == .focusSash
            && defender.hp == defender.stats.hp && damage >= defender.hp
        if sashed {
            damage = defender.hp - 1
            defender.heldItemConsumed = true
        }
        // 기합의머리띠는 확률로 버틴다 — 만피 조건이 없고 소모되지 않는 것이 띠와 갈리는 점이다.
        // 띠가 이미 잘랐으면 굴리지 않는다(같은 히트를 두 물건이 버티는 자리를 만들지 않는다).
        if !sashed, !hitsSubstitute, damage >= defender.hp,
           let percent = defender.heldEffect?.survivesLethalHitPercent,
           Int(rng.next() % 100) < percent, let item = defender.activeHeldItem {
            damage = defender.hp - 1
            events.append(.heldItemTriggered(defenderActor, item))
        }
        // 데미지 0(변화기)은 `.damage` 를 내보내지 않는다 — "0 데미지" 줄은 맞았는데 안 깎인 것처럼 읽힌다.
        if damage > 0 {
            if hitsSubstitute {
                // 넘긴 데미지는 주인에게 넘어가지 않는다 — 그래서 아래 드레인·반동도 **인형에
                // 실제로 들어간 만큼**을 본다(쇼다운과 같다). `.damage` 줄은 내지 않는다:
                // 재생기가 그 줄을 보고 주인의 HP 바를 깎으면 엔진의 최종 HP 와 갈린다.
                let absorbed = min(damage, defender.substituteHP)
                let broke = defender.absorbIntoSubstitute(damage)
                damage = absorbed
                events.append(broke ? .volatileEnded(defenderActor, .substitute)
                                    : .volatileTriggered(defenderActor, .substitute))
            } else {
                defender.hp = max(0, defender.hp - damage)
                ownerHitBookkeeping(&defender, actor: defenderActor, move: move, damage: damage,
                                    outcome: outcome, damageScale: damageScale, into: &events)
            }
            // 조개껍질방울 — 넣은 데미지의 1/8 을 회복한다. 드레인 **앞**에 두는 이유는 반동이다:
            // 뒤에 두면 반동으로 쓰러진 개체가 기절 줄 뒤에 회복한다. 층이 대신 맞아도 회복한다
            // (인형에 실제로 들어간 만큼을 본다 — 드레인과 같은 기준이다).
            if let divisor = attacker.heldEffect?.damageDealtHealDivisor {
                events += heal(&attacker, actor: attackerActor, upTo: max(1, damage / divisor))
            }
            // 드레인·반동은 **넣은 데미지의 비율**이다. PokéAPI `meta.drain` 하나가 양쪽을 겸한다 —
            // 양수는 흡수, 음수는 반동. rng 를 안 쓰므로 소비 순서가 흔들리지 않는다.
            // 다단기는 합계로 한 번만 계산한다. 히트마다 회복하면 로그가 다섯 줄이 된다.
            // 광역기는 **대상마다** 계산한다(감쇠된 데미지 기준이라 합계 비율은 그대로다).
            let percent = move.drainPercent
            if percent > 0 {
                var drained = damage * percent / 100
                // 큰뿌리는 **회복만** 키운다 — 데미지에 곱하면 흡수기가 위력까지 얻는다.
                if let scale = attacker.heldEffect?.drainHealScale {
                    drained = drained * scale.numerator / scale.denominator
                }
                events += heal(&attacker, actor: attackerActor, upTo: drained)
            } else if percent < 0 {
                let amount = max(1, damage * -percent / 100)
                attacker.hp = max(0, attacker.hp - amount)
                events.append(.damage(attackerActor, amount: amount, cause: .recoil))
                // 기절 줄은 여기서 내지 않는다. `.faint` 는 2차효과·랭크 뒤(맨 뒤)가 이 파일의
                // 순서고, 여기서 내면 "때린 쪽이 쓰러졌다 → 맞은 쪽이 독에 걸렸다"로 읽힌다.
            }
        }
        // HP 1 에서 버티면 자른 데미지가 0 이라 위 블록을 아예 지나지 않는다 — 그래서 버틴 줄은
        // 데미지 줄과 **따로** 낸다(안 그러면 그 턴이 로그에 무반응으로 남는다).
        if endured { events.append(.volatileTriggered(defenderActor, .endure)) }
        // 띠가 버틴 줄도 데미지 줄과 **따로** 낸다 — 만피가 1 이었던 개체(최대 HP 1)는 자른
        // 데미지가 0 이라 위 데미지 블록을 아예 지나지 않는다(인내와 같은 이유).
        if sashed, let item = defender.activeHeldItem {
            events.append(.heldItemTriggered(defenderActor, item))
        }
        // 약점 반감 열매는 **깎은 그 히트에서** 사라진다. 조건을 여기서 다시 묻지 않고
        // `outcome.berryHalved` 를 보는 이유는 깎은 자리와 같은 답을 쓰기 위해서다 — 각자 물으면
        // 상성표를 안 보는 기술에서 "데미지는 그대로인데 열매만 사라진다" 가 된다.
        //
        // **층이 대신 맞아도 소모한다**(기합의띠와 반대다). 열매는 이미 그 히트의 데미지를 깎았고,
        // 깎은 채로 남겨 두면 인형이 서 있는 동안 반감이 공짜로 무한히 계속된다.
        if outcome.berryHalved, let item = defender.activeHeldItem {
            defender.heldItemConsumed = true
            events.append(.heldItemTriggered(defenderActor, item))
        }
        // 주얼은 **올린 그 기술에서** 사라진다. 층이 대신 맞아도 마찬가지다 — 위력은 이미 올랐다.
        if outcome.gemSpent, let item = attacker.activeHeldItem {
            attacker.heldItemConsumed = true
            events.append(.heldItemTriggered(attackerActor, item))
        }
        // 맞은 히트에 답하는 물건들(약점보험·구근·충전지·눈덩이·빛이끼)도 **데미지가 들어간
        // 히트**만 본다 — 흘린 기술에 답하면 땅 타입이 전기를 무효로 만든 턴에 충전지가 터진다.
        // 층이 대신 맞았으면 주인은 맞지 않았으므로 답하지 않는다(기합의띠와 같은 기준).
        if damage > 0, !hitsSubstitute,
           let gains = defender.heldEffect?.stageGainOnHit(moveType: move.type,
                                                           effectiveness: outcome.effectiveness) {
            events += applyItemStageGains(gains, to: &defender, actor: defenderActor)
        }
        // 풍선은 **데미지가 들어간 히트**에서 터진다(본가와 같다) — 변화기와 빗나간 기술은
        // 안 터뜨린다. 층이 대신 맞으면 터지지 않는다: 인형이 맞은 것이라 주인은 아직 떠 있다.
        if damage > 0, !hitsSubstitute, defender.heldEffect?.consumedWhenHit == true,
           let item = defender.activeHeldItem {
            defender.heldItemConsumed = true
            events.append(.heldItemTriggered(defenderActor, item))
        }
        // 접촉에 답하는 물건(울퉁불퉁멧·끈적끈적바늘)은 **때린 쪽을 만진다** — 위 물건들과 주인이
        // 반대라서 자리를 나눈다. 접촉 여부는 데이터가 답하고(`MoveSpec.makesContact`), 때린 쪽의
        // 물건이 그 접촉을 없앨 수 있다(방호패드는 전부, 펀치글러브는 펀치만).
        //
        // 층이 대신 맞으면 답하지 않는다 — 인형을 만진 것이라 주인에게 닿지 않았다.
        if damage > 0, !hitsSubstitute, move.makesContact, attacker.isAlive,
           attacker.heldEffect?.suppressesContact(isPunch: move.isPunch) != true {
            events += applyContactEffects(attacker: &attacker, defender: &defender,
                                          attackerActor: attackerActor,
                                          defenderActor: defenderActor)
        }
        // 2차효과는 데미지 뒤다 — 쓰러진 상대에게는 붙지 않는다(그 경우 rng 도 쓰지 않는다).
        // 층에 막힌 기술은 2차효과·상대 volatile 도 주인에게 닿지 않는다 — 인형은 마비되지 않는다.
        if defender.isAlive, !hitsSubstitute {
            events += applySecondaryEffect(of: move, to: &defender, actor: defenderActor,
                                           field: field, defenderTeam: defenderTeam, rng: &rng)
            // 상대에게 붙는 volatile(조이기·저주·나이트메어)은 **대상 단위 입구**인 여기서 붙인다.
            // `applyAttack` 에 두면 대상마다 `applyHit` 을 직접 부르는 광역 모드(`WaveBattle`)에서
            // 아무에게도 안 붙는다 — 방어 판정이 이 자리로 내려온 것과 같은 이유다.
            events += applyVolatile(of: move, attacker: &attacker, defender: &defender,
                                    attackerActor: attackerActor, defenderActor: defenderActor,
                                    rng: &rng)
        }
        // **랭크는 기절 앞에서 본다.** 예전엔 기절이 여기서 조기반환해 상대를 쓰러뜨린 턴의 자기
        // 랭크 상승(고대의힘 부류)이 통째로 사라졌다 — 본가는 KO 여부와 무관하게 오른다. 상대 몫만
        // `applyStatChanges` 가 걸러낸다. `.faint` 를 맨 뒤로 미루는 건 Showdown 순서와도 같다.
        events += applyStatChanges(of: move, attacker: &attacker, defender: &defender,
                                   attackerActor: attackerActor, defenderActor: defenderActor,
                                   field: field, defenderTeam: defenderTeam,
                                   targetIsShielded: hitsSubstitute, rng: &rng)
        // 위급 열매는 **임계를 넘긴 그 히트에서** 터진다 — 턴 끝까지 미루면 그 사이의 두 번째
        // 공격에 쓰러져, 열매가 존재하는 이유인 그 한 방을 못 버틴다. 기절 판정 앞이라 쓰러진
        // 개체에게는 터지지 않는다(함수가 `isAlive` 를 먼저 본다).
        events += triggerPinchBerry(&defender, actor: defenderActor)
        if !defender.isAlive {
            events.append(.faint(defenderActor))
            // **기절 순간의 훅은 이 자리 하나다.** 광역기는 대상마다 `applyHit` 을 직접 부르므로
            // (`WaveBattle`) 여기 둬야 네 모드가 같은 규칙을 쓴다 — 방어 판정·상대 volatile 이
            // 이 자리로 내려온 것과 같은 이유다. 턴 끝 잔뎀에는 **두지 않는다**: 운명공동체·원한은
            // "상대의 기술로 쓰러졌다" 가 조건이라, 독으로 쓰러진 턴에 걸리면 아무도 안 때렸는데
            // 상대가 같이 쓰러진다(본가·쇼다운도 기술로 쓰러질 때만 발동한다).
            events += faintTriggers(of: move, victim: &defender, killer: &attacker,
                                    victimActor: defenderActor)
        }
        // 반동으로 때린 쪽이 쓰러졌으면 맞은 쪽 **뒤에** 적는다(Showdown 순서). 여기 오기 전에
        // 공격측이 죽는 길은 반동뿐이다. 혼란 자멸은 `canAct` 에서 조기반환한다.
        if !attacker.isAlive { events.append(.faint(attackerActor)) }
        // **변화기가 아무것도 못 했으면 그 사실을 말한다.** 데미지가 없는 기술이라 이벤트를 안 내면
        // 로그에 기술명 한 줄만 남아 무반응이 된다 — 독가루를 강철에게 쓰면(`canBeAfflicted` 가
        // 막는다) 정확히 그 모양이었다. 이 파일에서 세 번째로 밟는 부류라 여기서 한 번에 막는다.
        // 이 배열에 `.move` 는 없으므로(머리는 `beginAttack` 이 냈다) **비어 있으면** 아무 일도
        // 없었다는 뜻이다.
        if move.damageClass == .status, events.isEmpty {
            events.append(.immune(defenderActor))
        }
        return events
    }

    /// 주인이 실제로 맞았을 때만 남는 기록 — 깎인 줄·되돌려줄 데미지·맞은 횟수.
    ///
    /// 층(대타출동)이 대신 맞은 턴에는 **하나도 남지 않는다**: 주인의 HP 는 그대로이므로 카운터가
    /// 되돌려줄 것도, 원한의응보가 셀 것도 없다. 세 줄이 흩어져 있으면 층을 붙이는 다음 사람이
    /// 하나만 빠뜨린다 — 그래서 한 자리에 모은다.
    private static func ownerHitBookkeeping(_ defender: inout BattleSide, actor: BattleActor,
                                            move: MoveSpec, damage: Int, outcome: AttackOutcome,
                                            damageScale: Double, into events: inout [BattleEvent]) {
        // 원한의응보가 배틀 내내 센다. 다단기도 여기를 한 번만 지나므로 기술 하나로 센다.
        defender.timesHit += 1
        // 되돌려주는 기술(카운터 계열)이 이번 턴에 읽는다. 잔뎀·혼란 자멸은 여기를 지나지 않으므로
        // 기록되지 않는다 — 본가도 기술 데미지만 되돌려준다.
        //
        // **다단기는 마지막 히트만 기록한다**(본가와 같다). 합계를 넣으면 카운터가 5회 히트의
        // 총합을 2배로 되돌려줘 되돌리기가 히트 수만큼 세진다.
        defender.lastHitThisTurn = IncomingHit(
            amount: outcome.lastHitDamage.map { scaled($0, by: damageScale) } ?? damage,
            damageClass: move.damageClass)
        events.append(.damage(actor, amount: damage, cause: .move))
    }

    /// 광역 감쇠를 곱한 데미지. **0 으로 접지 않는다** — 원래 데미지가 1 이상이었으면 최소 1 은
    /// 들어가야 "맞았는데 안 깎였다"(변화기와 구별되지 않는 줄)가 되지 않는다.
    private static func scaled(_ damage: Int, by factor: Double) -> Int {
        guard factor != 1, damage > 0 else { return damage }
        return max(1, Int((Double(damage) * factor).rounded(.down)))
    }

    /// 상대에게 붙는 volatile(조이기·저주·나이트메어)을 붙인다. 붙지 않으면 그 사실을 남긴다 —
    /// 데미지 없는 변화기가 이벤트를 안 내면 로그에 기술명 한 줄만 남아 무반응으로 읽힌다.
    ///
    /// **rng 는 턴을 세는 조이기에서만 한 번 쓴다.** 조건(잠들었나·이미 붙었나)을 확률보다 먼저
    /// 보므로 두 피어의 소비량이 갈리지 않는다.
    private static func applyVolatile(of move: MoveSpec, attacker: inout BattleSide,
                                      defender: inout BattleSide, attackerActor: BattleActor,
                                      defenderActor: BattleActor,
                                      rng: inout SplitMix64) -> [BattleEvent] {
        guard let volatileStatus = BattleVolatile.called(byMoveID: move.id),
              !volatileStatus.targetsUser else { return [] }
        // 저주는 **쓴 쪽의 타입이 규칙을 가른다**: 고스트는 최대 HP 절반을 내고 상대를 저주하고,
        // 나머지는 자기 랭크를 움직인다(본가와 같다). 랭크 갈래를 `applyStatChanges` 에 맡길 수
        // 없는 이유는 부호다 — 올림과 내림이 한 기술에 섞여 `statChangePercent` 가 0 을 준다
        // (`MoveSpec.hasAmbiguousStatTargets`). 그래서 이 기술의 랭크는 여기서 직접 움직인다.
        if volatileStatus == .curse, !attacker.activeTypes.contains(.ghost) {
            var events: [BattleEvent] = []
            for change in move.statChanges ?? [] {
                let applied = attacker.changeStage(change.stat, by: change.change)
                guard applied != 0 else { continue }
                events.append(.boost(attackerActor, change.stat, applied))
            }
            attacker.lastMoveFailed = events.isEmpty
            return events
        }
        // 풀 타입에는 씨가 박히지 않는다(본가와 같다). 상성표가 아니라 이 기술만의 규칙이라
        // 여기서 본다 — 씨뿌리기는 풀 기술이고 풀은 풀을 0.5배로 받을 뿐 무효가 아니다.
        if volatileStatus == .leechSeed, defender.activeTypes.contains(.grass) {
            attacker.lastMoveFailed = true
            return [.immune(defenderActor)]
        }
        // 나이트메어는 잠든 상대에게만 걸린다 — 깨어 있으면 실패다(붙여 두면 깨는 순간 풀리는
        // 갈래가 곧바로 지워, 아무 일도 없었던 턴이 성공으로 기록된다).
        if volatileStatus == .nightmare, defender.status != .sleep {
            attacker.lastMoveFailed = true
            return [.immune(defenderActor)]
        }
        // 선택을 막는 셋은 **막을 것이 정해져야** 붙는다: 씨앙코르·앙코르는 상대가 직전에 낸
        // 기술이 있어야 하고, 봉인은 서로 겹치는 기술이 있어야 한다(본가와 같다). 조건을 안 보면
        // 아무 칸도 막지 않는 상태가 붙어 로그에만 남는다 — 화면에는 성공한 턴으로 보인다.
        switch volatileStatus {
        case .disable, .encore:
            guard let repeated = defender.lastMoveID,
                  defender.moves.contains(where: { $0.id == repeated }) else {
                attacker.lastMoveFailed = true
                return [.immune(defenderActor)]
            }
        case .imprison:
            let shared = Set(attacker.moves.map(\.id)).intersection(defender.moves.map(\.id))
            guard !shared.isEmpty else {
                attacker.lastMoveFailed = true
                return [.immune(defenderActor)]
            }
        default: break
        }
        // 끈기갈고리손톱은 4~5턴 난수를 **대신한다** — 값이 있으면 굴리지 않는다. 두 피어가 같은
        // 물건을 스냅샷으로 보므로 rng 소비가 갈리지 않는다(은밀망토와 같은 자리의 판단이다).
        let turns: Int
        if volatileStatus == .partiallyTrapped {
            turns = attacker.heldEffect?.trapTurns
                ?? BattleVolatile.trapTurnFloor + Int(rng.next() % BattleVolatile.trapTurnSpread)
        } else {
            turns = volatileStatus.foeDuration
        }
        guard defender.start(volatileStatus, turns: turns) else {
            attacker.lastMoveFailed = true
            return [.immune(defenderActor)]
        }
        attacker.lastMoveFailed = false
        // 빨아낸 HP 를 받을 자리를 함께 적는다. 안 적으면 씨가 박혀도 아무도 회복하지 않는다.
        if volatileStatus == .leechSeed { defender.leechSeedSource = attackerActor }
        // 조임밴드가 키운 잔뎀도 **걸린 쪽에** 적는다(씨뿌리기의 회복 자리와 같은 짝이다) — 턴 끝은
        // 개체 하나만 보므로, 거는 쪽의 물건을 그때 다시 물을 방법이 없다.
        if volatileStatus == .partiallyTrapped {
            defender.trapDamageDivisor = attacker.heldEffect?.trapDamageDivisor
        }
        // 어느 칸을 막는지는 상태와 **함께** 적는다(층 HP 와 같은 짝이다) — 위 조건 검사를 이미
        // 지났으므로 여기서 다시 실패할 수 없다.
        switch volatileStatus {
        case .disable: defender.disabledMoveID = defender.lastMoveID
        case .encore:  defender.encoredMoveID = defender.lastMoveID
        case .imprison:
            defender.imprisonedMoveIDs = Set(attacker.moves.map(\.id))
                .intersection(defender.moves.map(\.id))
        default: break
        }
        var events: [BattleEvent] = [.volatileStarted(defenderActor, volatileStatus)]
        // 고스트의 저주는 대가가 있다 — 최대 HP 절반이고, 그것으로 쓰러질 수 있다(본가와 같다).
        // 기절 줄은 여기서 내지 않는다: `applyHit` 이 랭크·2차효과 뒤 맨 끝에서 낸다.
        if volatileStatus == .curse {
            let cost = max(1, attacker.stats.hp / 2)
            attacker.hp = max(0, attacker.hp - cost)
            events.append(.damage(attackerActor, amount: cost, cause: .curse))
        }
        return events
    }

    /// 상대의 기술로 쓰러진 순간에 답하는 둘 — 운명공동체(같이 데려간다)·원한(그 기술의 PP 를 앗는다).
    ///
    /// 쓰러진 쪽에 붙어 있던 상태를 읽으므로 **쓰러뜨린 쪽을 함께 만진다**. `.faint(쓰러뜨린 쪽)` 줄은
    /// 여기서 내지 않는다 — `applyHit` 이 맞은 쪽 뒤에 한 번 낸다(쇼다운 순서).
    private static func faintTriggers(of move: MoveSpec, victim: inout BattleSide,
                                      killer: inout BattleSide,
                                      victimActor: BattleActor) -> [BattleEvent] {
        var events: [BattleEvent] = []
        if victim.has(.destinyBond), killer.isAlive {
            killer.hp = 0
            events.append(.volatileTriggered(victimActor, .destinyBond))
        }
        // 원한은 **쓰러뜨린 그 기술**의 PP 만 앗는다. 같은 id 를 두 칸에 든 무브셋은 없으므로
        // 첫 칸으로 찾는다. 이미 0 이면(발버둥으로 쓰러뜨린 경우 무브셋에 없다) 아무 일도 없다 —
        // "PP 를 앗았다" 줄만 남는 턴을 만들지 않는다.
        if victim.has(.grudge),
           let index = killer.moves.firstIndex(where: { $0.id == move.id }),
           killer.pp.indices.contains(index), killer.pp[index] > 0 {
            killer.pp[index] = 0
            events.append(.volatileTriggered(victimActor, .grudge))
        }
        return events
    }

    /// 기술의 랭크 변화. **부호가 대상을 정한다** — 올리면 자기, 내리면 상대다. `stat_changes` 에는
    /// 대상이 없고 `target` 은 공격 대상만 가리키므로(자기 랭크를 깎는 공격기도 `selected-pokemon`)
    /// 부호가 유일한 신호다. 부호로 **가릴 수 없는** 두 부류는 `MoveSpec.statChangePercent` 가 0 을
    /// 주어 미리 걸러낸다: 확정 자기감소 공격기(인파이트)와 부호가 섞인 기술(저주).
    ///
    /// rng 는 **적용할 변화가 있을 때만** 한 번 소비한다 — 두 피어가 같은 조건에서 같은 횟수를
    /// 불러야 한다(쓰러졌는지, 확률이 0 인지는 양쪽이 똑같이 본다). 대가를 모델링하지 않은 큰
    /// 상승(배가르기)도 `statChangePercent` 가 0 으로 접는다.
    private static func applyStatChanges(of move: MoveSpec, attacker: inout BattleSide,
                                         defender: inout BattleSide, attackerActor: BattleActor,
                                         defenderActor: BattleActor, field: BattleField,
                                         defenderTeam: BattleTeamSlot,
                                         targetIsShielded: Bool = false,
                                         rng: inout SplitMix64) -> [BattleEvent] {
        let changes = move.statChanges ?? []
        let percent = move.statChangePercent
        // 쓰러진 상대에게는 못 걸지만 **자기 랭크 상승은 KO 여부와 무관하다**(본가와 같다). 상대가
        // 쓰러졌으면 자기 몫(양수)만 남기고 본다 — 남는 게 없으면 rng 도 쓰지 않는다. 조건은 두
        // 피어가 똑같이 보므로(누가 쓰러졌는지) 소비량이 갈라지지 않는다.
        // 층 뒤에 있는 상대에게도 못 건다 — 쓰러진 상대와 **같은 규칙**이라 자기 몫(양수)만 남는다.
        let applicable = defender.isAlive && !targetIsShielded
            ? changes : changes.filter { $0.change > 0 }
        guard !applicable.isEmpty, percent > 0, attacker.isAlive else { return [] }
        guard Int(rng.next() % 100) < percent else { return [] }
        var events: [BattleEvent] = []
        for change in applicable {
            let targetsSelf = change.change > 0
            // 하얀안개는 **상대가 내리는** 랭크만 막는다. 자기 상승까지 막으면 쓴 쪽이 손해를 본다.
            // 클리어참은 하얀안개와 **같은 물음**에 답한다 — 남이 내리는 랭크만 막는다.
            if !targetsSelf, field.blocksStatDrop(against: defenderTeam)
                || defender.heldEffect?.blocksStatDrop == true { continue }
            // 은밀망토는 **덤으로 붙는** 하락만 막는다. 변화기의 하락은 그 기술 자체라 지나간다.
            if !targetsSelf, move.damageClass != .status,
               defender.heldEffect?.blocksAddedEffects == true { continue }
            let applied = targetsSelf
                ? attacker.changeStage(change.stat, by: change.change)
                : defender.changeStage(change.stat, by: change.change)
            // 0 은 ±6 에 닿아 아무 일도 없었다는 뜻이다 — 줄을 내면 로그가 거짓말을 한다.
            guard applied != 0 else { continue }
            events.append(.boost(targetsSelf ? attackerActor : defenderActor, change.stat, applied))
        }
        return events
    }

    /// 기술의 2차효과(상태 부여). 붙을 수 있는지를 **확률 판정보다 먼저** 보므로, 이미 다른 상태가
    /// 걸려 있거나 면역인 상대에게는 rng 를 쓰지 않는다 — 두 피어의 소비량이 같아야 한다.
    private static func applySecondaryEffect(of move: MoveSpec, to side: inout BattleSide,
                                             actor: BattleActor, field: BattleField,
                                             defenderTeam: BattleTeamSlot,
                                             rng: inout SplitMix64) -> [BattleEvent] {
        // **자기 대상 상태기는 상대에게 걸지 않는다.** 잠자기는 `ailment: sleep` 이라 여기까지 오는데
        // 회복은 구현이 없어서, 걸면 남는 게 필중 100% 수면기다(대상을 모르는 게 아니라 아는데
        // 반대로 거는 경우다). 구현할 때는 `targetsUser` 를 보고 회복까지 같이 넣는다.
        guard move.targetsUser != true else { return [] }
        // 은밀망토는 공격기에 딸린 덤만 막는다 — 변화기는 그것이 기술 자체라 지나간다. 확률을
        // 굴리기 **전에** 막으므로 rng 소비가 줄지만, 두 피어가 같은 물건을 보므로 갈리지 않는다.
        if move.damageClass != .status, side.heldEffect?.blocksAddedEffects == true { return [] }
        if move.flinchPercent > 0, side.isAlive, Int(rng.next() % 100) < move.flinchPercent { side.flinched = true }
        // 필드가 막는 상태는 걸리지 않는다 — 땅에 닿은 쪽만이다(일렉트릭필드는 잠듦,
        // 미스트필드는 주 상태 전부). 막히면 확률 판정을 굴리지 않아 rng 소비가 줄지만, 두 피어가
        // 같은 필드를 보므로 갈리지 않는다.
        // 신비의부적은 **상대가 거는** 상태를 막는다. 필드가 막을 때와 같은 자리라 확률 판정을
        // 굴리지 않는다 — 두 피어가 같은 판을 보므로 소비량이 갈리지 않는다.
        guard let status = move.inflictedStatus, side.canBeAfflicted(by: status),
              !field.blocksStatus(against: defenderTeam),
              !(field.terrain?.blocks(status) == true && BattleField.isGrounded(side)),
              Int(rng.next() % 100) < move.ailmentChancePercent else { return [] }
        return inflict(status, on: &side, actor: actor, rng: &rng)
    }

    /// 양쪽 기술 선택이 모이면 한 턴 해상. 순수·결정적 — 같은 rng 상태·입력이면 두 피어가 같은 결과를
    /// 각자 계산한다(결과 자체는 네트워크로 보내지 않는다 → 변조 여지 축소).
    /// rng 소비 순서가 프로토콜의 일부다 — 브랜치를 바꾸면 두 피어 결과가 갈라진다.
    static func resolveTurn(a: inout BattleSide, b: inout BattleSide,
                            moveA: MoveSpec, moveB: MoveSpec, turn: Int,
                            field: inout BattleField, rng: inout SplitMix64) -> [BattleEvent] {
        beginTurn(&a); beginTurn(&b)
        var events: [BattleEvent] = [.turn(turn)]
        // 물건의 턴 머리 굴림은 **순서를 재기 전**이다 — 선공을 가져갔는지가 순서의 입력이다.
        events += rollTurnStartItems(&a, actor: .a, rng: &rng)
        events += rollTurnStartItems(&b, actor: .b, rng: &rng)
        // 마비가 스피드를 깎으므로 순서 계산이 상태를 봐야 한다 — `stats.spe` 를 그대로 넘기면
        // 마비가 스탯 표시에만 남고 선공은 그대로다.
        let aIsFirst = firstMoverIsA(priorityA: moveA.turnPriority, priorityB: moveB.turnPriority,
                                     speedA: orderingSpeed(a, team: .a, field: field),
                                     speedB: orderingSpeed(b, team: .b, field: field),
                                     movesLastA: movesLast(a), movesLastB: movesLast(b),
                                     movesFirstA: movesFirst(a), movesFirstB: movesFirst(b),
                                     rng: &rng)
        for attackerIsA in aIsFirst ? [true, false] : [false, true] {
            guard a.isAlive && b.isAlive else { break }   // 선공에 기절하면 후공 없음
            let move = attackerIsA ? moveA : moveB
            events += attackerIsA
                ? applyAttack(attacker: &a, defender: &b, attackerActor: .a, defenderActor: .b,
                              move: move, field: &field, attackerTeam: .a, defenderTeam: .b,
                              rng: &rng)
                : applyAttack(attacker: &b, defender: &a, attackerActor: .b, defenderActor: .a,
                              move: move, field: &field, attackerTeam: .b, defenderTeam: .a,
                              rng: &rng)
        }
        // 잔뎀은 두 공격이 **모두 끝난 뒤**다. 앞에 두면 그 턴의 데미지 계산과 기절 시점이 달라진다.
        // 좌변부터 고정 순서 — 순서가 흔들리면 동시 기절 때 두 피어의 승패가 갈린다.
        events += endOfTurnResidual(&a, actor: .a)
        events += endOfTurnResidual(&b, actor: .b)
        // 씨뿌리기는 짝이 있어야 처리된다. 1대1 은 상대가 하나뿐이라 자리를 찾을 것이 없다.
        events += endOfTurnLeechSeed(seeded: &a, seededActor: .a, seeder: &b, seederActor: .b)
        events += endOfTurnLeechSeed(seeded: &b, seededActor: .b, seeder: &a, seederActor: .a)
        // 날씨는 잔뎀 뒤, 그리고 **개체 몫 전부가 끝난 뒤에** 한 번 줄인다.
        events += endOfTurnWeather(&a, actor: .a, field: field)
        events += endOfTurnWeather(&b, actor: .b, field: field)
        events += advanceField(&field)
        return events
    }
}
