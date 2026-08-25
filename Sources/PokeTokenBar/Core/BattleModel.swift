import Foundation

// MARK: - 타입

/// 본가 18타입 — rawValue 는 PokéAPI type name 과 동일(직렬화·차트 키 겸용).
enum PokemonType: String, Codable, Sendable, CaseIterable {
    case normal, fire, water, electric, grass, ice
    case fighting, poison, ground, flying, psychic, bug
    case rock, ghost, dragon, dark, steel, fairy

    /// 본가 공식 번역 명칭 (ko/en/ja).
    func name(_ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch self {
        case .normal:   names = ("노말", "Normal", "ノーマル")
        case .fire:     names = ("불꽃", "Fire", "ほのお")
        case .water:    names = ("물", "Water", "みず")
        case .electric: names = ("전기", "Electric", "でんき")
        case .grass:    names = ("풀", "Grass", "くさ")
        case .ice:      names = ("얼음", "Ice", "こおり")
        case .fighting: names = ("격투", "Fighting", "かくとう")
        case .poison:   names = ("독", "Poison", "どく")
        case .ground:   names = ("땅", "Ground", "じめん")
        case .flying:   names = ("비행", "Flying", "ひこう")
        case .psychic:  names = ("에스퍼", "Psychic", "エスパー")
        case .bug:      names = ("벌레", "Bug", "むし")
        case .rock:     names = ("바위", "Rock", "いわ")
        case .ghost:    names = ("고스트", "Ghost", "ゴースト")
        case .dragon:   names = ("드래곤", "Dragon", "ドラゴン")
        case .dark:     names = ("악", "Dark", "あく")
        case .steel:    names = ("강철", "Steel", "はがね")
        case .fairy:    names = ("페어리", "Fairy", "フェアリー")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
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
    func name(_ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch self {
        case .atk:      names = ("공격", "Attack", "こうげき")
        case .def:      names = ("방어", "Defense", "ぼうぎょ")
        case .spa:      names = ("특수공격", "Sp. Atk", "とくこう")
        case .spd:      names = ("특수방어", "Sp. Def", "とくぼう")
        case .spe:      names = ("스피드", "Speed", "すばやさ")
        case .accuracy: names = ("명중률", "accuracy", "めいちゅう")
        case .evasion:  names = ("회피율", "evasiveness", "かいひ")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
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
/// 이름은 다국어 맵(수신 측이 자기 언어로 표시).
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
    var drain: Int? = nil
    /// 자기 회복량(PokéAPI `meta.healing`) — **최대 HP 대비 %**. 회복·아침햇살 계열이 50 이다.
    /// `drain` 과 다르다: 저쪽은 넣은 데미지의 비율이라 때려야 회복하고, 이쪽은 데미지와 무관하다.
    var healing: Int? = nil
    var flinchChance: Int? = nil
    var minHits: Int? = nil
    var maxHits: Int? = nil

    /// 턴 순서 비교용 우선도 — 값이 없으면 0.
    var turnPriority: Int { priority ?? 0 }

    /// 급소 단계 — Gen 2 의 고급소기는 **+2 단계**(1/4)다. PokéAPI 의 `crit_rate` 는 세대에 따라
    /// 뜻이 달라(Gen 6+ 는 +1 단계) 값을 그대로 쓰지 않고, 고급소기인지만 보고 Gen 2 단계로 옮긴다.
    var critStage: Int { (critRate ?? 0) > 0 ? 2 : 0 }

    /// 실제로 걸 수 있는 상태 — 구현한 6종만. 나머지 14종은 `nil` 이라 부여 시도가 그냥 지나간다
    /// (무엇을 건너뛰었는지는 스펙을 만들 때 `AppLog` 에 한 번 남긴다).
    ///
    /// 맹독은 PokéAPI 가 별도 ailment 로 주지 않는다 — 맹독(id 92)도 `ailment` 는 `poison` 이다.
    /// 그래서 이 기술만 id 로 가른다.
    var inflictedStatus: Status? {
        if id == Self.toxicMoveID { return .toxic }
        return ailment.flatMap(Status.init(ailment:))
    }

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
    func hitCount(rng: inout SplitMix64) -> Int {
        let low = min(10, max(1, minHits ?? 1))
        let high = min(10, max(low, maxHits ?? low))
        guard low != high else { return low }
        if low == 2, high == 5 {
            switch rng.next() % 8 { case 0...2: return 2; case 3...5: return 3; case 6: return 4; default: return 5 }
        }
        return low + Int(rng.next() % UInt64(high - low + 1))
    }
    var hasModeledStatusEffect: Bool {
        (inflictedStatus != nil && targetsUser != true)
            || (!(statChanges ?? []).isEmpty && statChangePercent > 0)
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

    func name(_ lang: AppLanguage) -> String { lang.resolveName(names) ?? names.values.first ?? "?" }
    func description(_ lang: AppLanguage) -> String? {
        guard let descriptions else { return nil }
        return lang.resolveName(descriptions) ?? descriptions["en"] ?? descriptions.values.first
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
            synth(-3, "\(t1.name(.ko)) 일격", "\(t1.name(.en)) Strike", "\(t1.name(.ja))のいちげき", t1, 80, .physical, 100, 15),
            synth(-4, "\(t2.name(.ko)) 파동", "\(t2.name(.en)) Pulse", "\(t2.name(.ja))のはどう", t2, 70, .special, 100, 20),
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
    /// 세이브에는 없다 — 특성은 종에서 파생되므로 저장할 값이 아니다.
    ///
    /// 스냅샷을 만드는 네 자리가 이 값을 싣는지는
    /// `VariableDamageTests.testEveryBattleSnapshotSiteCarriesTheWireOnlyFields` 가 소스에서 센다
    /// (인자 이름만 보므로 선언 순서는 자유다). 전부 기본값 `nil` 이라 빠뜨려도 컴파일은 통과한다.
    var ability: String? = nil
    /// 헥토그램(0.1kg). 체중으로 위력이 정해지는 기술이 본다.
    ///
    /// 옵셔널인 이유는 **조회 실패**다(피어 호환이 아니다 — 이 필드가 없던 시절과는 `rulesVersion`
    /// 이 이미 대전을 막는다). 0 으로 접으면 안 된다: 저공격이 "가장 가벼움"으로 최저 위력이 되고
    /// 헤비봄버는 0 나눗셈 자리로 간다. 값이 없으면 그 기술만 실패시킨다(`VariableDamage.noEffect`).
    var weightHectograms: Int? = nil

    /// 레벨 유도 — 성장 진행도(단계 + 단계 내 진행)를 5~100 레벨로 사상.
    /// stageProgress 는 0~1 로 클램프, totalForms ≥ 1 보장.
    static func level(stageIndex: Int, totalForms: Int, stageProgress: Double) -> Int {
        let k = max(1, totalForms)
        let p = min(1.0, max(0.0, stageProgress))
        let overall = min(1.0, (Double(stageIndex) + p) / Double(k))
        return min(100, max(5, 5 + Int((overall * 95.0).rounded())))
    }

    /// 유효 스탯 (IV 31 고정, EV 0, 성격 보정 포함) — 본가 공식.
    func effectiveStats() -> BattleStats {
        let l = level
        func other(_ base: Int, _ stat: WritableKeyPath<BattleStats, Int>) -> Int {
            let raw = (2 * base + 31) * l / 100 + 5
            return Int(Double(raw) * NatureEffect.multiplier(nature, for: stat))
        }
        return BattleStats(
            hp: (2 * base.hp + 31) * l / 100 + l + 10,
            atk: other(base.atk, \.atk),
            def: other(base.def, \.def),
            spa: other(base.spa, \.spa),
            spd: other(base.spd, \.spd),
            spe: other(base.spe, \.spe))
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
    case move, burn, poison, toxic, confusion, recoil
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
    /// 남은 혼란 턴 — 이 수만큼 자멸 판정을 굴린다.
    var confusionTurns = 0
    var flinched = false
    /// 랭크(−6…+6). 0 인 스탯은 **키를 두지 않는다** — 그래야 "랭크가 하나도 없다" 가
    /// `stages.isEmpty` 한 번으로 읽히고, 와이어 JSON 도 붙은 랭크만 나른다.
    var stages: [BattleStat: Int] = [:]

    init(_ snapshot: BattleSnapshot) {
        self.snapshot = snapshot
        stats = snapshot.effectiveStats()
        hp = stats.hp
        moves = snapshot.moves ?? MoveSpec.fallbackSet(types: snapshot.types)
        pp = moves.map(\.pp)
    }

    var isAlive: Bool { hp > 0 }
    var isConfused: Bool { confusionTurns > 0 }

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

    /// 턴 순서에 쓰는 스피드 — 랭크를 먼저 곱하고, 마비면 그 뒤에 Gen 2 기준 25%(Gen 7 부터 50%).
    /// 순서 계산이 `stats.spe` 를 직접 읽으면 마비·랭크가 스탯 화면에만 보이고 실제 선공은 그대로다.
    var effectiveSpeed: Int {
        let boosted = StatStages.apply(rawStat(.spe), stage: stage(.spe))
        return status == .paralysis ? max(1, boosted / 4) : boosted
    }

    /// 이 상태가 붙을 수 있는가. 타입 면역은 **Gen 2 것만** 가져온다 —
    /// 전기 타입의 마비 면역, 풀 타입의 가루 면역은 Gen 6 규칙이라 여기 없다.
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
        case .poison, .toxic:  return !types.contains(.poison) && !types.contains(.steel)
        default:               return true
        }
    }

    /// 고를 수 있는 기술이 하나도 없으면 발버둥.
    var mustStruggle: Bool { !pp.contains { $0 > 0 } }

    /// 인덱스로 기술 — 범위 밖이거나 음수면 발버둥(PP 소진 선택은 −1 로 온다).
    func move(at index: Int) -> MoveSpec {
        moves.indices.contains(index) ? moves[index] : .struggle()
    }

    /// 이번 턴에 이 인덱스의 기술을 쓸 수 있는가 — 인덱스 범위와 남은 PP 를 **같이** 본다.
    /// `pp` 는 와이어로 들어오는 값이라 `moves` 와 길이가 어긋날 수 있다(경계에서 함께 막는다).
    func canUse(moveAt index: Int) -> Bool {
        moves.indices.contains(index) && pp.indices.contains(index) && pp[index] > 0
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
    /// 급소 배율 — Gen 2 는 ×2(Gen 6+ 는 ×1.5). 상수인 건 밸런스 재조정 여지를 남기려는 것이다.
    static let critMultiplier = 2

    /// 급소 확률의 분자(분모 256) — Gen 2 단계표. 0단계 17/256, +1 은 1/8, +2 는 1/4, +3 이상은 85/256.
    /// 단계를 올리는 건 지금은 고급소기뿐이다(기술·특성 보정은 Phase 3·5).
    static func critThreshold(stage: Int) -> UInt64 {
        switch max(0, stage) {
        case 0: return 17
        case 1: return 32
        case 2: return 64
        default: return 85
        }
    }

    /// 얼음이 매턴 녹을 확률(%) — Gen 2 의 10% 는 평균 10턴이라 사실상 사망 선고다.
    /// Gen 3 값(20%)을 기본으로 두고 상수로 노출한다(계획 §7 리스크 표).
    static let thawChance = 20
    /// 마비로 행동이 막힐 확률(%) — Gen 2 는 25%(Gen 7 부터 50%).
    static let paralysisFailChance = 25
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
    static let rulesVersion = 15

    /// 연결이 끊긴 배틀의 승패 — 남은 HP **비율**이 앞선 쪽이 이기고, 같으면 `nil`(무효)이다.
    ///
    /// 예전엔 끊김을 무조건 `iWon: true` 로 접었다. 두 피어가 각자 자기 연결의 죽음을 보므로 한 번
    /// 끊기면 **양쪽이 동시에 승리**해 둘 다 `settleRankedBrawl(won: true)` 로 판돈 ★ 과 LP 를 받았다 —
    /// 어느 지갑에서도 빠져나가지 않아 총량만 늘었고, 지고 있으면 끊는 게 이득이었다. 판정을 두 피어가
    /// 공유하는 **상태에서** 뽑으면 두 쪽 결론이 자동으로 반대가 된다.
    ///
    /// ponytail: 단, 상태가 같다는 전제는 **턴 경계에서만** 참이다. `resolveIfReady` 는 두 선택이 모이는
    /// 즉시 해상하므로 한쪽 `.move` 만 도착한 채 링크가 죽으면 상태가 한 턴 어긋나고, 그 창에서는 양쪽이
    /// 모두 "내가 앞선다"를 봐 판돈이 두 지갑에 동시에 들어간다. 닫으려면 턴별 ack(또는 합의된 턴 인덱스
    /// 기준 판정)이 필요해 와이어 계약 변경 사안으로 남긴다 — 미해결(defect-log 참조).
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
        // Gen 2 는 물러난 포켓몬의 맹독을 보통 독으로 강등한다.
        if side.status == .toxic {
            side.status = .poison
            side.statusCounter = 0
        }
        // 혼란·풀죽음은 volatile — 다시 나왔을 때 이전 상태를 이어 가지 않는다.
        side.confusionTurns = 0
        side.flinched = false
        // 랭크도 물러나면 사라진다. 남겨 두면 칼춤을 세 번 쌓아 두고 교체로 피했다가 그 랭크
        // 그대로 다시 나오는 무료 세팅이 된다 — CPU/체육관과 LAN 교체가 같이 이 규칙을 쓴다.
        side.resetStages()
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
        if defender.ability?.immuneMoveType == move.type { return 0 }
        return TypeChart.effectiveness(move.type, against: defender.snapshot.types)
    }

    /// Gen 2 데미지 식의 앞부분 — 배율이 붙기 전의 뼈대. 기술 공격과 혼란 자멸이 같은 값을 쓴다.
    static func baseDamage(level: Int, power: Int, attack: Int, defense: Int) -> Int {
        (2 * level / 5 + 2) * power * attack / max(1, defense) / 50
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
        guard let accuracy = move.accuracy else { return nil }
        let withAccuracy = accuracy * StatStages.accuracyPercent(stage: attacker.stage(.accuracy)) / 100
        return withAccuracy * StatStages.accuracyPercent(stage: -defender.stage(.evasion)) / 100
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
    static func resolveAttack(attacker: BattleSide, defender: BattleSide,
                              move: MoveSpec, rng: inout SplitMix64) -> AttackOutcome {
        if let chance = hitChance(of: move, attacker: attacker, defender: defender),
           Int(rng.next() % 100) >= chance {
            return AttackOutcome(missed: true, damage: 0, effectiveness: 1, isCritical: false)
        }
        let requestedHits = move.hitCount(rng: &rng)
        // 남은 HP 는 지역에서 센다 — `defender` 는 값 사본이라 히트 사이에 줄지 않는다.
        // 안 세면 이미 쓰러진 상대를 남은 횟수만큼 계속 때린다.
        var remaining = defender.hp
        var total = 0, actualHits = 0, lastHit = 0
        var effectiveness = 1.0, critical = false
        for _ in 0..<requestedHits where remaining > 0 {
            let one = resolveSingleHit(attacker: attacker, defender: defender, move: move, rng: &rng)
            total += one.damage
            remaining -= one.damage
            actualHits += 1
            lastHit = one.damage
            effectiveness = one.effectiveness
            critical = critical || one.isCritical
            if one.effectiveness == 0 { break }
        }
        return AttackOutcome(missed: false, damage: total, effectiveness: effectiveness,
                             isCritical: critical, hits: actualHits, lastHitDamage: lastHit)
    }

    /// 히트 하나. 다단기는 이 함수를 히트마다 부르므로 급소·난수 폭이 히트별로 독립이다
    /// (본가와 같다 — 한 번 뽑아 곱하면 급소가 나면 전 히트가 급소가 된다).
    private static func resolveSingleHit(attacker: BattleSide, defender: BattleSide,
                                         move: MoveSpec, rng: inout SplitMix64) -> AttackOutcome {
        // PokéAPI 가 `power: null` 로 주는 공격기 — 위력을 여기서 뽑는다. `move.power` 는 0 이라
        // 그대로 쓰면 아래 식이 데미지를 0 으로 접는다(그게 이 기술들이 죽어 있던 원인이다).
        var power = move.power
        switch VariableDamage.from(move, attacker: attacker, defender: defender, rng: &rng) {
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
        case .noEffect:             return AttackOutcome(missed: false, damage: 0,
                                                        effectiveness: 0, isCritical: false)
        case nil:                   break
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
        let isCritical = rng.next() % 256 < critThreshold(stage: move.critStage)
        // 급소는 **불리한 랭크만** 무시한다(Gen 3+): 공격측의 마이너스와 방어측의 플러스가 빠진다.
        // 전부 무시하는 Gen 1·2 방식이면 랭크를 올린 쪽이 급소에서 손해를 봐 올릴 이유가 없어진다.
        let offense: BattleStat = isPhysical ? .atk : .spa
        let guardStat: BattleStat = isPhysical ? .def : .spd
        let offenseStage = isCritical ? max(0, attacker.stage(offense)) : attacker.stage(offense)
        let guardStage = isCritical ? min(0, defender.stage(guardStat)) : defender.stage(guardStat)
        // 화상은 **물리** 공격만 절반이다(Gen 2 는 공격 스탯을 반으로 깎는다). 특수기는 그대로다 —
        // 여기서 분류를 안 보면 화상이 공격 전체를 깎는 다른 게임이 된다.
        var attack = StatStages.apply(attacker.rawStat(offense), stage: offenseStage)
        if isPhysical, attacker.status == .burn { attack /= 2 }
        let defense = StatStages.apply(defender.rawStat(guardStat), stage: guardStage)
        // Gen 2 난수는 217~255 균등 **정수**를 뽑아 255 로 정수 나눗셈한다. 예전엔
        // `0.85 + (rng % 16)/100` 이라 0.01 간격 Double 이었다 — 두 피어가 각자 계산하는
        // 구조에서는 정수 연산이 유리하다(부동소수 오차가 끼어들 자리가 없다).
        let random = 217 + Int(rng.next() % 39)

        // Gen 2 의 계산 **순서** 그대로다. `+2` 가 급소 배율 뒤에 오고, STAB·상성은 그 뒤에 곱한다.
        // 예전 식은 `+2` 를 먼저 더한 뒤 급소 ×1.5 를 곱해 급소 데미지가 다르게 나왔다.
        // (배지·트레이너킥·날씨·기술보정은 §3.3 대로 안 가져온다.)
        var damage = baseDamage(level: attacker.snapshot.level, power: power,
                                attack: attack, defense: defense)
        damage = damage * (isCritical ? critMultiplier : 1) + 2
        // 위의 `effectiveness` 와 **같은 게이트**여야 한다. 예전 `!isStruggle` 은 위력 0 이
        // 데미지를 접어 준 덕에 우연히 같았을 뿐이다(위력 있는 무상성 기술이 생기면 갈라진다).
        if !ignoresTypeChart {
            if attacker.snapshot.types.contains(move.type) { damage = damage * 3 / 2 }   // STAB ×1.5
            damage = TypeChart.apply(damage, of: move.type, against: defender.snapshot.types)
        }
        damage = damage * random / 255
        // 위력 0(변화기)은 데미지가 없다. `max(1, …)` 만 두면 식의 `+2` 가 살아남아 상태기가 2 데미지를
        // 넣었다 — `learnedMoves` 는 변화기를 걸러내지 않으므로 실제로 밟히는 경로다.
        // rng 소비는 그대로다(명중 → 가변위력 → 급소 → 난수) — 값이 바뀌므로 `rulesVersion` 으로 막는다.
        let dealt = (effectiveness == 0 || power <= 0) ? 0 : max(1, damage)
        return AttackOutcome(missed: false, damage: dealt,
                             effectiveness: effectiveness, isCritical: isCritical)
    }

    /// 두 공격자 중 누가 먼저인가 — 본가와 같은 순서로 본다: **기술 우선도 → 스피드 → 무작위**.
    ///
    /// 무작위는 앞의 둘이 모두 같을 때만 소비한다(예전 1v1 규칙 그대로). 멀티는 이 자리에서
    /// UUID 문자열 순서로 갈랐는데, 그러면 앱을 켠 동안 사전순으로 앞선 참가자가 동점 때마다
    /// 선공을 가져간다 — 실력과 무관한 데다 화면에 드러나지도 않는다.
    static func firstMoverIsA(priorityA: Int, priorityB: Int, speedA: Int, speedB: Int,
                              rng: inout SplitMix64) -> Bool {
        if priorityA != priorityB { return priorityA > priorityB }
        if speedA != speedB { return speedA > speedB }
        return rng.next() & 1 == 0
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
            side.statusCounter = 2 + Int(rng.next() % 7)       // 카운터 2~8 → 행동불능 1~7턴
        case .toxic:
            side.status = .toxic
            side.statusCounter = 1                             // 1/16 부터 매턴 1/16 누적
        default:
            side.status = status
            side.statusCounter = 0
        }
        return [.status(actor, status)]
    }

    /// 턴 끝 잔뎀 — 화상·독은 최대 HP 의 1/8, 맹독은 n/16 으로 매턴 커진다.
    /// rng 를 쓰지 않으므로 호출 순서만 고정하면 두 피어가 같은 값을 본다.
    static func endOfTurnResidual(_ side: inout BattleSide, actor: BattleActor) -> [BattleEvent] {
        guard side.isAlive, let status = side.status else { return [] }
        let full = side.stats.hp
        let amount: Int
        let cause: DamageCause
        switch status {
        case .burn:
            amount = max(1, full / 8);  cause = .burn
        case .poison:
            amount = max(1, full / 8);  cause = .poison
        case .toxic:
            amount = max(1, full * side.statusCounter / 16); cause = .toxic
            side.statusCounter += 1
        case .paralysis, .sleep, .freeze, .confusion, .flinch:
            return []
        }
        side.hp = max(0, side.hp - amount)
        var events: [BattleEvent] = [.damage(actor, amount: amount, cause: cause)]
        if !side.isAlive { events.append(.faint(actor)) }
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
        if side.status == .paralysis, Int(rng.next() % 100) < paralysisFailChance {
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

    /// 턴이 시작될 때 "이번 턴에 맞은 것" 을 비운다.
    ///
    /// **`applyAttack` 을 직접 부르는 모든 턴 루프가 이걸 먼저 불러야 한다.** 한 곳만 빠지면 그
    /// 모드에서만 카운터가 지난 턴 데미지를 되돌려준다 — 화면에는 정상으로 보이고 숫자만 틀린다.
    /// 빠뜨림은 `VariableDamageTests.testEveryTurnLoopClearsTheIncomingHit` 이 소스에서 막는다.
    static func beginTurn(_ side: inout BattleSide) { side.lastHitThisTurn = nil; side.flinched = false }

    /// 공격 1회를 해상해 양쪽 상태를 갱신하고, 그 결과를 이벤트로 남긴다.
    /// 1v1·연습·멀티가 전부 이 함수를 지나므로 **세 모드의 이벤트 어휘가 같다** — 데미지 함수를
    /// 하나로 모은 것(#46)과 배틀 상태를 `BattleSide` 로 모은 것(Phase 0)과 같은 이유다.
    /// 행동 가능 판정도 여기 있어야 세 모드가 상태이상을 같은 규칙으로 받는다.
    ///
    /// ponytail: 못 움직인 턴에도 PP 는 이미 호출부에서 깎인 뒤다(본가는 안 깎는다). 되돌리려면
    ///           기술 선택 자체를 엔진 안으로 옮겨야 하는데, 그건 교체(Phase 4)와 같이 할 일이다.
    ///           양쪽 피어가 똑같이 깎으므로 desync 는 없다.
    static func applyAttack(attacker: inout BattleSide, defender: inout BattleSide,
                            attackerActor: BattleActor, defenderActor: BattleActor,
                            move: MoveSpec, rng: inout SplitMix64) -> [BattleEvent] {
        var events: [BattleEvent] = []
        // 못 움직이면 `.move` 자체가 나가지 않는다 — Showdown 도 `|move|` 대신 `|cant|` 를 보낸다.
        guard canAct(&attacker, actor: attackerActor, rng: &rng, into: &events) else { return events }
        events.append(.move(attackerActor, moveID: move.id))
        // 자기 회복기는 상대를 보지 않는다 — 명중·상성·데미지 계산을 통째로 건너뛴다.
        // `resolveAttack` 에 태우면 위력 0 이라 rng 만 태우고 아무것도 안 하는 기술이 된다.
        if let restored = selfHealing(of: move, user: &attacker, actor: attackerActor, rng: &rng) {
            return events + restored
        }
        let outcome = resolveAttack(attacker: attacker, defender: defender, move: move, rng: &rng)
        if outcome.missed { return events + [.miss(attackerActor)] }
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
        // 데미지 0(변화기)은 `.damage` 를 내보내지 않는다 — "0 데미지" 줄은 맞았는데 안 깎인 것처럼 읽힌다.
        if outcome.damage > 0 {
            defender.hp = max(0, defender.hp - outcome.damage)
            // 되돌려주는 기술(카운터 계열)이 이번 턴에 읽는다. 잔뎀·혼란 자멸은 여기를 지나지 않으므로
            // 기록되지 않는다 — 본가도 기술 데미지만 되돌려준다.
            //
            // **다단기는 마지막 히트만 기록한다**(본가와 같다). 합계를 넣으면 카운터가 5회 히트의
            // 총합을 2배로 되돌려줘 되돌리기가 히트 수만큼 세진다.
            defender.lastHitThisTurn = IncomingHit(amount: outcome.lastHitDamage ?? outcome.damage,
                                                   damageClass: move.damageClass)
            events.append(.damage(defenderActor, amount: outcome.damage, cause: .move))
            // 드레인·반동은 **넣은 데미지의 비율**이다. PokéAPI `meta.drain` 하나가 양쪽을 겸한다 —
            // 양수는 흡수, 음수는 반동. rng 를 안 쓰므로 소비 순서가 흔들리지 않는다.
            // 다단기는 합계로 한 번만 계산한다. 히트마다 회복하면 로그가 다섯 줄이 된다.
            let percent = move.drainPercent
            if percent > 0 {
                events += heal(&attacker, actor: attackerActor, upTo: outcome.damage * percent / 100)
            } else if percent < 0 {
                let amount = max(1, outcome.damage * -percent / 100)
                attacker.hp = max(0, attacker.hp - amount)
                events.append(.damage(attackerActor, amount: amount, cause: .recoil))
                // 기절 줄은 여기서 내지 않는다. `.faint` 는 2차효과·랭크 뒤(맨 뒤)가 이 파일의
                // 순서고, 여기서 내면 "때린 쪽이 쓰러졌다 → 맞은 쪽이 독에 걸렸다"로 읽힌다.
            }
        }
        // 2차효과는 데미지 뒤다 — 쓰러진 상대에게는 붙지 않는다(그 경우 rng 도 쓰지 않는다).
        if defender.isAlive {
            events += applySecondaryEffect(of: move, to: &defender, actor: defenderActor, rng: &rng)
        }
        // **랭크는 기절 앞에서 본다.** 예전엔 기절이 여기서 조기반환해 상대를 쓰러뜨린 턴의 자기
        // 랭크 상승(고대의힘 부류)이 통째로 사라졌다 — 본가는 KO 여부와 무관하게 오른다. 상대 몫만
        // `applyStatChanges` 가 걸러낸다. `.faint` 를 맨 뒤로 미루는 건 Showdown 순서와도 같다.
        events += applyStatChanges(of: move, attacker: &attacker, defender: &defender,
                                   attackerActor: attackerActor, defenderActor: defenderActor,
                                   rng: &rng)
        if !defender.isAlive { events.append(.faint(defenderActor)) }
        // 반동으로 때린 쪽이 쓰러졌으면 맞은 쪽 **뒤에** 적는다(Showdown 순서). 여기 오기 전에
        // 공격측이 죽는 길은 반동뿐이다. 혼란 자멸은 `canAct` 에서 조기반환한다.
        if !attacker.isAlive { events.append(.faint(attackerActor)) }
        // **변화기가 아무것도 못 했으면 그 사실을 말한다.** 데미지가 없는 기술이라 이벤트를 안 내면
        // 로그에 기술명 한 줄만 남아 무반응이 된다 — 독가루를 강철에게 쓰면(`canBeAfflicted` 가
        // 막는다) 정확히 그 모양이었다. 이 파일에서 세 번째로 밟는 부류라 여기서 한 번에 막는다.
        // `.move` 하나뿐이면 부여도 랭크 변화도 없었다는 뜻이다.
        if move.damageClass == .status, events.count == 1 {
            events.append(.immune(defenderActor))
        }
        // 자폭기(命がけの突撃)는 데미지를 넣은 **뒤에** 자기가 쓰러진다. 상대보다 먼저 쓰러뜨리면
        // 데미지 계산이 이미 끝난 뒤라 순서가 결과를 바꾸지 않지만, 로그는 때린 다음에 쓰러져야 읽힌다.
        if VariableDamage.userFaints(after: move), attacker.isAlive {
            attacker.hp = 0
            events.append(.faint(attackerActor))
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
                                         defenderActor: BattleActor,
                                         rng: inout SplitMix64) -> [BattleEvent] {
        let changes = move.statChanges ?? []
        let percent = move.statChangePercent
        // 쓰러진 상대에게는 못 걸지만 **자기 랭크 상승은 KO 여부와 무관하다**(본가와 같다). 상대가
        // 쓰러졌으면 자기 몫(양수)만 남기고 본다 — 남는 게 없으면 rng 도 쓰지 않는다. 조건은 두
        // 피어가 똑같이 보므로(누가 쓰러졌는지) 소비량이 갈라지지 않는다.
        let applicable = defender.isAlive ? changes : changes.filter { $0.change > 0 }
        guard !applicable.isEmpty, percent > 0, attacker.isAlive else { return [] }
        guard Int(rng.next() % 100) < percent else { return [] }
        var events: [BattleEvent] = []
        for change in applicable {
            let targetsSelf = change.change > 0
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
                                             actor: BattleActor, rng: inout SplitMix64) -> [BattleEvent] {
        // **자기 대상 상태기는 상대에게 걸지 않는다.** 잠자기는 `ailment: sleep` 이라 여기까지 오는데
        // 회복은 구현이 없어서, 걸면 남는 게 필중 100% 수면기다(대상을 모르는 게 아니라 아는데
        // 반대로 거는 경우다). 구현할 때는 `targetsUser` 를 보고 회복까지 같이 넣는다.
        guard move.targetsUser != true else { return [] }
        if move.flinchPercent > 0, side.isAlive, Int(rng.next() % 100) < move.flinchPercent { side.flinched = true }
        guard let status = move.inflictedStatus, side.canBeAfflicted(by: status),
              Int(rng.next() % 100) < move.ailmentChancePercent else { return [] }
        return inflict(status, on: &side, actor: actor, rng: &rng)
    }

    /// 양쪽 기술 선택이 모이면 한 턴 해상. 순수·결정적 — 같은 rng 상태·입력이면 두 피어가 같은 결과를
    /// 각자 계산한다(결과 자체는 네트워크로 보내지 않는다 → 변조 여지 축소).
    /// rng 소비 순서가 프로토콜의 일부다 — 브랜치를 바꾸면 두 피어 결과가 갈라진다.
    static func resolveTurn(a: inout BattleSide, b: inout BattleSide,
                            moveA: MoveSpec, moveB: MoveSpec, turn: Int,
                            rng: inout SplitMix64) -> [BattleEvent] {
        beginTurn(&a); beginTurn(&b)
        var events: [BattleEvent] = [.turn(turn)]
        // 마비가 스피드를 깎으므로 순서 계산이 상태를 봐야 한다 — `stats.spe` 를 그대로 넘기면
        // 마비가 스탯 표시에만 남고 선공은 그대로다.
        let aIsFirst = firstMoverIsA(priorityA: moveA.turnPriority, priorityB: moveB.turnPriority,
                                     speedA: a.effectiveSpeed, speedB: b.effectiveSpeed, rng: &rng)
        for attackerIsA in aIsFirst ? [true, false] : [false, true] {
            guard a.isAlive && b.isAlive else { break }   // 선공에 기절하면 후공 없음
            let move = attackerIsA ? moveA : moveB
            events += attackerIsA
                ? applyAttack(attacker: &a, defender: &b, attackerActor: .a, defenderActor: .b,
                              move: move, rng: &rng)
                : applyAttack(attacker: &b, defender: &a, attackerActor: .b, defenderActor: .a,
                              move: move, rng: &rng)
        }
        // 잔뎀은 두 공격이 **모두 끝난 뒤**다. 앞에 두면 그 턴의 데미지 계산과 기절 시점이 달라진다.
        // 좌변부터 고정 순서 — 순서가 흔들리면 동시 기절 때 두 피어의 승패가 갈린다.
        events += endOfTurnResidual(&a, actor: .a)
        events += endOfTurnResidual(&b, actor: .b)
        return events
    }
}
