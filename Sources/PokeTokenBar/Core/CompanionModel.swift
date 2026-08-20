import Foundation

/// 표시 상태 — 사용량/burn 으로 결정(스프라이트 모션 강도·상태 문구).
enum CompanionStateKind: String, Sendable {
    case egg, idle, working, focus, tired, sleep, levelUp
}

/// 앱 언어. 포켓몬 이름은 PokéAPI 다국어 names 에서 가져온다.
enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case ko, en, ja
    /// PokéAPI language.name 후보(첫 매칭 사용)
    var apiCodes: [String] {
        switch self {
        case .ko: return ["ko"]
        case .en: return ["en"]
        case .ja: return ["ja-Hrkt", "ja"]
        }
    }
    var label: String {
        switch self { case .ko: return "한국어"; case .en: return "English"; case .ja: return "日本語" }
    }

    var displayLocale: Locale { Locale(identifier: rawValue) }

    /// byLang(langCode→name) 에서 이 언어의 이름을 고른다(apiCodes 첫 매칭 → 영어 폴백).
    func resolveName(_ byLang: [String: String]) -> String? {
        for code in apiCodes { if let n = byLang[code] { return n } }
        return byLang["en"]
    }

    /// 신규 설치 기본 언어 — 시스템 선호 언어에서 유추(글로벌 출시: 한국어 강제 금지).
    /// ko/ja 만 매칭, 그 외 전부 영어(fallback-of-fallback). 기존 사용자는 저장된 언어를 그대로 쓴다.
    static var systemDefault: AppLanguage {
        switch Locale.preferredLanguages.first?.prefix(2).lowercased() {
        case "ko": return .ko
        case "ja": return .ja
        default:   return .en
        }
    }
}

/// 희귀도 — PokéAPI capture_rate / is_legendary 로 판정.
enum Rarity: String, Codable, Sendable {
    case common, uncommon, rare, legendary
    /// 등급 크기(높을수록 희귀) — 두 `Rarity` 를 비교하기 위한 순위.
    /// **목록 정렬용이 아니다**: 포획 로그는 기록 시각순, 도감은 도감 번호순이고 희귀도는 필터로만 좁힌다.
    /// 유일한 소비자는 프리미엄 알의 보증 관문(`hatch` 의 `line.rarity.sortRank < tier.sortRank`) —
    /// 뽑힌 등급이 산 보증보다 낮은지 판정한다. 순서가 뒤집히면 고급/희귀 알이 조용히 낮은 등급을
    /// 통과시키므로 `testSortRankOrdersRarityAscendingByValue` 가 순서를 고정한다.
    var sortRank: Int {
        switch self {
        case .common:    return 0
        case .uncommon:  return 1
        case .rare:      return 2
        case .legendary: return 3
        }
    }
    /// 이 등급의 capture_rate 상한 — 이 값 이하면 그 종은 이 등급 **이상**이다.
    /// `from(captureRate:…)` 의 분류 임계이자, 프리미엄 알이 부화 후보를 미리 거르는 기준이다.
    /// 두 곳에 임계를 따로 적으면 한쪽만 바뀌었을 때 등급 보증이 조용히 깨지므로 **여기가 단일 소스**다.
    ///
    /// nil = capture_rate 로 표현할 수 없는 등급. 전설은 `is_legendary`/`is_mythical` 로만 판정되는데
    /// 부화 후보 인덱스(`BaseSpecies`)에는 그 플래그가 없다 → 전설 **전용** 알은 만들 수 없다(팔지도 않는다).
    /// 반대로 전설은 전원 capture_rate ≤ 45 라 하한을 *위로만* 벗어나므로, 고급/희귀 알의 capture_rate
    /// 필터에는 자연스럽게 포함된다("고급 이상"·"희귀 이상" 규칙이 그대로 성립).
    var captureRateCeiling: Int? {
        switch self {
        case .rare:      return 45
        case .uncommon:  return 120
        case .common:    return 255
        case .legendary: return nil
        }
    }
    /// capture_rate 가 이 등급 이상을 뜻하는지 — 전설은 capture_rate 로 판정할 수 없어 항상 false.
    func includes(captureRate: Int) -> Bool {
        guard let ceiling = captureRateCeiling else { return false }
        return captureRate <= ceiling
    }
    static func from(captureRate: Int, isLegendary: Bool, isMythical: Bool) -> Rarity {
        if isLegendary || isMythical { return .legendary }
        if Rarity.rare.includes(captureRate: captureRate) { return .rare }
        if Rarity.uncommon.includes(captureRate: captureRate) { return .uncommon }
        return .common
    }
}

/// 방치형 경제 — 재화는 **별의모래(stardust)**. 앱이 켜져 있는 동안 시간으로 생산되고,
/// 성장(부화·진화·졸업)과 상점이 같은 단위를 쓴다. 수치는 토큰 경제 시절의 표를 그대로 계승한다
/// (헤비유저 ~253M/일 기준으로 튜닝된 값 — 생산 속도를 그 등가로 맞춰 소요 기간 감각을 유지).
enum IdleEconomy {
    /// 경제 스키마 버전. 이 값보다 낮은 세이브(토큰 경제 시절)는 로드/불러오기 경계에서
    /// 도감·수집만 남기고 진행을 리셋한다(SaveTransfer.sanitized). 토큰 누적과 별의모래는
    /// 단위가 달라 환산하지 않는다(2026-08-13 결정: 전면 리셋).
    static let currentVersion = 2
    /// 기본 생산 속도 — 초당 별의모래. 7,000/s = 25.2M/시간: 알 부화(5M) ≈ 12분,
    /// common 졸업(750M) ≈ 30시간, legendary(6B) ≈ 240시간(하루 10시간 가동 시 ≈ 24일) —
    /// README 의 "common ≈3일 → legendary ≈24일" 약속을 실행 시간 기준으로 유지한다.
    static let dustPerSecond: Double = 7_000
    /// 도감 보너스 — 등록한 종(고유 최종체) 1종당 생산 속도 +2%. 수집이 곧 성장 엔진.
    static let dexBonusPerSpecies = 0.02
    /// 틱 1회가 인정하는 최대 경과 시간. 틱 타이머(60초)가 몇 번 밀려도 흡수하되,
    /// 시스템 슬립·강제 시계 점프 같은 "안 켜져 있던 시간"은 여기서 잘린다.
    static let maxTickInterval: TimeInterval = 180
}

/// 성장 밸런스 — 졸업 총량 T 는 같은 희귀도면 진화 단계 수와 무관하게 동일.
/// 형태 k개 라인에서 i번째 형태 성장 비용 = T·i / (k(k+1)/2) → 합 = T, 단계↑일수록 비용↑.
enum PokemonBalance {
    /// 알 부화 임계 — 이만큼 별의모래가 쌓여야 알이 깨진다(즉시 부화 대신 기대감). 초과분은 부화체 성장에 이월.
    static let eggHatchThreshold = 5_000_000

    /// 진화가 아예 없는 종(totalForms==1)의 졸업 게이팅 레벨 — 희귀도 무관 단일 기준. 희귀도는
    /// 처음 뽑힐 확률에만 관여하고, 다 자란 뒤의 속도는 관여하지 않는다(#19 논의). 진화를 거쳐
    /// 최종형에 도달한 종은 그 마지막 진화 요구 레벨이 이미 관문이라 이 값을 다시 보지 않는다
    /// (CompanionStore.applyUsage). graduationTotal/phaseThreshold 는 레벨 메타데이터가 없는
    /// 진화(구버전 픽스처 등)의 성장치 게이트로만 남는다.
    static let graduationRequiredLevel = 30

    /// 친밀도 진화의 레벨 환산 — 앱엔 친밀도 축이 없다(돌봄 UI 는 제거됐고 affection 은 플로팅 펫
    /// 쓰다듬기로만 오른다). PokéAPI 의 `min_happiness` 는 실제로 160/220 두 값뿐이라 그 두 단계를
    /// 레벨 두 단계로 옮긴다. 하한 25 는 직전 진화 레벨(예: 주뱃→골뱃 22)보다 뒤에 오게 하는 값이고,
    /// 상한은 무진화 종 졸업 기준과 같은 30이다. 원본 값이 바뀌어도 이 규칙만 유지하면 된다.
    static func friendshipLevel(minHappiness: Int) -> Int {
        minHappiness > 160 ? 30 : 25
    }

    static func graduationTotal(_ rarity: Rarity) -> Int {
        switch rarity {
        case .common:    return    750_000_000
        case .uncommon:  return  1_875_000_000
        case .rare:      return  3_000_000_000
        case .legendary: return  6_000_000_000
        }
    }
    /// stageIndex(0-based)에서 다음 단계/졸업까지 필요한 토큰.
    static func phaseThreshold(rarity: Rarity, totalForms k: Int, stageIndex: Int) -> Int {
        let kk = max(1, k)
        let i = stageIndex + 1                         // 1-based
        let total = Double(graduationTotal(rarity))
        let denom = Double(kk * (kk + 1)) / 2.0
        return Int((total * Double(i) / denom).rounded())
    }
}

/// 인벤토리 아이템 종류 — 확장 대비 enum(현재 이상한 사탕 1종). rawValue 로 CompanionState.inventory 에 저장.
enum ItemKind: String, Codable, Sendable, CaseIterable {
    case rareCandy
    case mint
    case shinyCharm
    case linkingCord, fireStone, waterStone, thunderStone, leafStone, iceStone, moonStone, sunStone
    // 4세대 추가분 — 없으면 로즈레이드·눈여아·무레인 등 8종이 진화할 방법이 아예 없다.
    case shinyStone, duskStone, dawnStone

    /// PokéAPI 아이템 스프라이트 파일명(.../sprites/items/{name}.png). nil = 스프라이트 없음(이모지 폴백만).
    var spriteName: String? {
        switch self {
        case .rareCandy: return "rare-candy"
        case .mint: return nil   // PokéAPI 에 민트 스프라이트 없음(8세대 아이템) → 이모지 폴백
        case .shinyCharm: return "shiny-charm"
        case .linkingCord: return nil
        case .fireStone: return "fire-stone"; case .waterStone: return "water-stone"
        case .thunderStone: return "thunder-stone"; case .leafStone: return "leaf-stone"
        case .iceStone: return "ice-stone"; case .moonStone: return "moon-stone"; case .sunStone: return "sun-stone"
        case .shinyStone: return "shiny-stone"; case .duskStone: return "dusk-stone"; case .dawnStone: return "dawn-stone"
        }
    }
    /// 스프라이트 로딩 전/미제공/실패 시 폴백 이모지.
    var fallbackEmoji: String {
        switch self {
        case .rareCandy: return "🍬"
        case .mint: return "🌿"
        case .shinyCharm: return "✨"
        case .linkingCord: return "🔗"
        case .fireStone: return "🔥"; case .waterStone: return "💧"; case .thunderStone: return "⚡"
        case .leafStone: return "🍃"; case .iceStone: return "❄️"; case .moonStone: return "🌙"; case .sunStone: return "☀️"
        case .shinyStone: return "💠"; case .duskStone: return "🌑"; case .dawnStone: return "🌅"
        }
    }
    /// 상점 판매가(재화 = 사용한 토큰). nil = 상점 미판매.
    var shopPrice: Int? {
        switch self {
        case .rareCandy: return RareCandy.price
        case .mint: return Mint.price
        case .shinyCharm: return nil
        case .linkingCord, .fireStone, .waterStone, .thunderStone, .leafStone, .iceStone, .moonStone, .sunStone, .shinyStone, .duskStone, .dawnStone: return 500
        }
    }
    /// 보유형(패시브) 아이템 — 소비하지 않고 보유하는 동안 상시 효과. 1회 구매(재구매 불가), 가방엔 "적용 중" 표시.
    var isPassive: Bool {
        switch self {
        case .rareCandy, .mint, .linkingCord, .fireStone, .waterStone, .thunderStone, .leafStone, .iceStone, .moonStone, .sunStone, .shinyStone, .duskStone, .dawnStone: return false
        case .shinyCharm: return true
        }
    }

    var evolutionKey: String? {
        switch self {
        case .linkingCord: return "trade"
        case .fireStone: return "fire-stone"; case .waterStone: return "water-stone"
        case .thunderStone: return "thunder-stone"; case .leafStone: return "leaf-stone"
        case .iceStone: return "ice-stone"; case .moonStone: return "moon-stone"; case .sunStone: return "sun-stone"
        case .shinyStone: return "shiny-stone"; case .duskStone: return "dusk-stone"; case .dawnStone: return "dawn-stone"
        default: return nil
        }
    }
}

/// 이상한 사탕 밸런스 상수.
enum RareCandy {
    /// 사용 시 현재 포켓몬에 주입하는 XP(별의모래 환산). 최소 진화 임계(커먼 1형태 125M)보다 작아
    /// 사탕 1개는 최대 1단계만 올린다(연쇄·졸업 폭주 없음). applyUsage 로 주입 → 이월/진화/졸업 자동.
    static let xp = 100_000_000
    /// 일일 보상 개수 — 그 날 첫 틱에 지급(방치형 출석 보상. 토큰 한도 연동 지급의 대체, 2026-08-13).
    static let dailyGrant = 1
    /// 상점 구매가(재화 = 별의조각 starPieces). 2026-08-14 재책정(#19) — 옛 값(5억)은 별의모래
    /// 시절 통화 단위 그대로라, 지금 지갑(모험 1회 수백~수천)으로는 사실상 못 사는 가격이었다.
    /// 해안 모험(2시간) 1회 최대 수입이 7,200 이라, 그보다 조금 싸게 잡아 "모험 한 번 다녀오면
    /// 살 수 있는" 감각으로 맞춘다. 무료 획득(일일 보상 1개)이 항상 이득이도록 그보다는 비싸게.
    static let price = 5_000
}

/// 민트 밸런스 상수.
enum Mint {
    /// 상점 구매가. 성격 변경은 순수 코스메틱(성장·능력치 무관)이라 밸런스 근거가 없어 "느낌" 값 —
    /// 사탕(5,000)의 1/5로 싸게 둬서 성격을 마음에 들 때까지 굴려보는 가벼운 재미. 성장을 안 줘서
    /// 이중계산 이슈도 없음(가격 = 순수 소비). 2026-08-14 재책정(#19), 비율은 유지.
    static let price = 1_000
}

/// 이로치 부적 밸런스 상수 — 보유형(1회 구매·영구, 소비 안 됨).
enum ShinyCharm {
    /// 상점 구매가. 앞으로의 모든 부화에 적용되는 영구 럭 업그레이드라 프리미엄(레어 1마리 졸업분=3B).
    static let price = 3_000_000_000
    /// 보유 시 이로치 부화 확률 분모 — 1/64 → 1/48 (+33%). 본가 '반짝이 부적'(이로치 확률↑) 오마주.
    /// ×2(1/32)는 과해 절제. 이미 부화한 개체엔 소급 없음(이로치는 부화 순간 확정).
    static let shinyDenominator: UInt64 = 48
}

/// 새 알(리롤) 밸런스 상수 — 상점 구매 시 현재 포켓몬을 폐기하고 새 알로 되돌린다.
enum FreshEgg {
    /// 상점 구매가(재화 = 별의조각 starPieces). 마음에 안 드는 부화를 리롤하는 프리미엄. 폐기 개체는
    /// 졸업이 아니라 그냥 사라지므로 도감·확률(collectedFinals)에 무영향 — "뽑은 적 없던 것처럼".
    /// 2026-08-14 재책정(#19): 옛 값(20억)은 별의모래 시절 단위였다. 사탕(5,000)이 "모험 한 번"이면
    /// 알은 "며칠 모아서 지르는 것" — 해안 모험(2시간, 7,200) 약 3회분으로 잡는다.
    static let price = 20_000

    /// 상점에서 파는 알 — 보증 없음(기본) → 고급 이상 → 희귀 이상. `nil` = 등급 보증 없는 기존 알.
    /// **전설 전용 알은 팔지 않는다**(등급 하한을 capture_rate 로 표현할 수 없고, 최고 등급을 확정
    /// 상품으로 만들지 않는다). 전설은 고급/희귀 알에서 자연 가중대로 섞여 나온다 — 희귀 알 기준 약 10%.
    static let shopTiers: [Rarity?] = [nil]

    /// 등급 보증 알의 가격 — 배율은 새 상수를 짓지 않고 **기존 졸업 총량 표**를 그대로 쓴다
    /// (common 750M : uncommon 1.875B : rare 3B = 1 : 2.5 : 4 → 1B / 2.5B / 4B).
    ///
    /// 확률 배율(고급 7.16% : 희귀 6.98% ≈ 1 : 2.03)로 매기면 안 된다 — 그러면 같은 값으로 고급 알
    /// 2개를 사는 쪽이 희귀+ 기대 1.039마리·전설 0.104마리로 희귀 알 1개(1.000·0.100)를 모든 축에서
    /// 앞질러 상위 티어가 완전 열등재가 된다. 졸업량 배율이라야 상위 티어가 희귀+ 1마리당 4.00B 로
    /// 하위 반복 구매(4.81B)보다 싸다.
    static func price(guaranteeing tier: Rarity?) -> Int {
        guard let tier else { return price }
        let multiplier = Double(PokemonBalance.graduationTotal(tier)) / Double(PokemonBalance.graduationTotal(.common))
        return Int((Double(price) * multiplier).rounded())
    }
}

/// 상점 표시 한 줄 — 판매 아이템(ItemKind) 또는 알 리롤(즉시 액션이라 ItemKind 가 아님).
/// `egg` 의 연관값은 **보증 등급 하한**(nil = 보증 없는 기존 알).
/// CompanionStore.shopEntries 가 이 둘을 가격 오름차순으로 병합해 뷰가 단일 목록으로 그린다.
enum ShopEntry: Hashable, Sendable {
    case item(ItemKind)
    case egg(Rarity?)

    var price: Int {
        switch self {
        case .item(let kind): return kind.shopPrice ?? 0
        case .egg(let tier): return FreshEgg.price(guaranteeing: tier)
        }
    }
}

/// 스타터 선택 규칙 — 후보 풀 범위·제외 종. SaveTransfer(세이브 정규화)와 CompanionStore(후보 롤)가 공유.
enum StarterRules {
    /// 1세대(1~151) 기본형(진화 전) 후보 풀 범위.
    static let genRange = 1...151
    /// 스타터에서 제외할 1세대 전설·환상 종(3신조·뮤츠·뮤). BaseSpecies 인덱스엔 is_legendary 가
    /// 없어 id 로 직접 거른다. 전설은 알/졸업 루프에서만 나온다.
    static let legendaryExclusions: Set<Int> = [144, 145, 146, 150, 151]
    static func isLegendary(_ id: Int) -> Bool { legendaryExclusions.contains(id) }
}

/// 현재 서비스가 제공하는 움직이는 포켓몬 스프라이트 범위.
/// K-MON currently limits animated companions to the Gen 1–5 species range (#1...649).
/// Showdown provides normal and shiny GIFs for every ID in this range.
enum PokemonAssets {
    static let animatedSpeciesIDs = 1...649

    static func hasAnimatedSprite(speciesID: Int) -> Bool {
        animatedSpeciesIDs.contains(speciesID)
    }
}

/// PokéAPI evolution-chain 을 파싱한 트리. 분기(evolves_to 다수)를 children 으로.
struct EvoNode: Codable, Sendable {
    let speciesID: Int
    let children: [EvoNode]
    var evolutionLevel: Int? = nil
    var evolutionTrigger: String? = nil
    var evolutionItem: String? = nil

    /// 최장 경로 길이(형태 수). 분기는 보통 같은 깊이라 대표값으로 사용.
    var depth: Int { 1 + (children.map(\.depth).max() ?? 0) }
    func node(withID id: Int) -> EvoNode? {
        if speciesID == id { return self }
        for c in children { if let f = c.node(withID: id) { return f } }
        return nil
    }
    /// 이 노드에서 도달 가능한 모든 최종체 id
    var finalIDs: [Int] {
        children.isEmpty ? [speciesID] : children.flatMap(\.finalIDs)
    }

    /// 서비스에 GIF 에셋이 있는 종만 남긴 진화 트리. 지원하지 않는 종부터 그 하위 체인도 제외한다.
    func keepingAnimatedSprites() -> EvoNode? {
        guard PokemonAssets.hasAnimatedSprite(speciesID: speciesID) else { return nil }
        return EvoNode(speciesID: speciesID, children: children.compactMap { $0.keepingAnimatedSprites() },
                       evolutionLevel: evolutionLevel, evolutionTrigger: evolutionTrigger,
                       evolutionItem: evolutionItem)
    }
}

enum EvoLineItemContent: Equatable, Sendable {
    case species(Int)
    case mystery
}

enum EvoLineItemState: Equatable, Sendable {
    case done
    case current
    case future
}

struct EvoLineItem: Equatable, Sendable {
    let content: EvoLineItemContent
    let state: EvoLineItemState

    init(_ content: EvoLineItemContent, _ state: EvoLineItemState) {
        self.content = content
        self.state = state
    }
}

/// 부화 시 확정되는 라인 정보(트리 + 희귀도 + 다국어 이름).
struct EvoLine: Sendable {
    let baseID: Int
    let tree: EvoNode
    let rarity: Rarity
    /// speciesID → (langCode → name)
    let names: [Int: [String: String]]
    var totalForms: Int { tree.depth }

    init(baseID: Int, tree: EvoNode, rarity: Rarity, names: [Int: [String: String]]) {
        self.baseID = baseID
        self.tree = tree.keepingAnimatedSprites() ?? EvoNode(speciesID: baseID, children: [])
        self.rarity = rarity
        self.names = names
    }

    func localizedName(_ id: Int, _ lang: AppLanguage) -> String {
        lang.resolveName(names[id] ?? [:]) ?? "#\(id)"   // 폴백 순서는 AppLanguage.resolveName 단일 소스
    }
}

/// 성격 — 본가 25종. 부화 시 확정, 능력치 영향 없음(개체 아이덴티티 표시용).
enum PokemonNature: String, Codable, Sendable, CaseIterable {
    case hardy, lonely, brave, adamant, naughty
    case bold, docile, relaxed, impish, lax
    case timid, hasty, serious, jolly, naive
    case modest, mild, quiet, bashful, rash
    case calm, gentle, sassy, careful, quirky

    /// 본가 공식 번역 명칭 (ko/en/ja).
    func name(_ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch self {
        case .hardy:   names = ("노력", "Hardy", "がんばりや")
        case .lonely:  names = ("외로움", "Lonely", "さみしがり")
        case .brave:   names = ("용감", "Brave", "ゆうかん")
        case .adamant: names = ("고집", "Adamant", "いじっぱり")
        case .naughty: names = ("개구쟁이", "Naughty", "やんちゃ")
        case .bold:    names = ("대담", "Bold", "ずぶとい")
        case .docile:  names = ("온순", "Docile", "すなお")
        case .relaxed: names = ("무사태평", "Relaxed", "のんき")
        case .impish:  names = ("장난꾸러기", "Impish", "わんぱく")
        case .lax:     names = ("촐랑", "Lax", "のうてんき")
        case .timid:   names = ("겁쟁이", "Timid", "おくびょう")
        case .hasty:   names = ("성급", "Hasty", "せっかち")
        case .serious: names = ("성실", "Serious", "まじめ")
        case .jolly:   names = ("명랑", "Jolly", "ようき")
        case .naive:   names = ("천진난만", "Naive", "むじゃき")
        case .modest:  names = ("조심", "Modest", "ひかえめ")
        case .mild:    names = ("의젓", "Mild", "おっとり")
        case .quiet:   names = ("냉정", "Quiet", "れいせい")
        case .bashful: names = ("수줍음", "Bashful", "てれや")
        case .rash:    names = ("덜렁", "Rash", "うっかりや")
        case .calm:    names = ("차분", "Calm", "おだやか")
        case .gentle:  names = ("얌전", "Gentle", "おとなしい")
        case .sassy:   names = ("건방", "Sassy", "なまいき")
        case .careful: names = ("신중", "Careful", "しんちょう")
        case .quirky:  names = ("변덕", "Quirky", "きまぐれ")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}

/// 게임 밸런스 — 개체 롤 확률.
enum PokemonOdds {
    /// 색이 다른 포켓몬(shiny) 부화 확률 분모 — 1/64 (본가 1/4096 은 데스크톱 앱 규모에선 평생 못 봄).
    static let shinyDenominator: UInt64 = 64
    /// 메타몽 위장 확률 분모 — common·≥2형태 부화에 한해 1/128 (GO 변장 메타몽 추정 1/50~70보다 귀하게).
    static let dittoDisguiseDenominator: UInt64 = 128
    /// 메타몽 종 id — 위장 리빌 전용(일반 부화 풀에서 제외).
    static let dittoSpeciesID = 132
}

/// 현재 키우는 포켓몬.
struct MonState: Codable, Sendable {
    var id = UUID()
    var baseID: Int
    var pathIDs: [Int]      // 실제 진화 경로(분기 선택 반영)
    var plannedPathIDs: [Int] // 사전에 선택한 전체 진화 경로
    var stageIndex: Int     // pathIDs 내 현재 위치
    var usedAtStage: Int    // 현재 형태에서 누적 사용량
    var rarity: Rarity
    var totalForms: Int
    var isShiny = false             // 부화 시 확정, 진화해도 유지
    var nature: PokemonNature?      // 부화 시 확정 (구버전 저장은 nil)
    var nickname: String?           // 사용자 지정 별명(없으면 종 이름 표시). 진화해도 유지.
    // 메타몽 위장 — nil=일반. 값=정체 메타몽, 이 종으로 위장 중(위장 구간엔 baseID 와 동일, 리빌 후에도 원 위장체 보존).
    var dittoDisguise: Int?
    var dittoRevealed = false       // 위장 → 리빌(정체 공개) 전환 여부
    var levelExperience = 0
    var learnedMoves: [MoveSpec] = []
    /// 진화 체인 각 종의 다국어 이름(speciesID → langCode → name). 부화 시 로드된 라인에서 저장한다 —
    /// `DexEntry.names` 와 같은 패턴이다. 박스에 있는 개체는 `currentLine` 이 없어(활성 개체만 로드됨)
    /// 이게 없으면 도감이 이름 대신 종 번호(#25)를 그린다. 구버전 저장분엔 없어(nil) 뷰가 폴백한다.
    var names: [Int: [String: String]]?
    /// 이미 졸업해 영구 `DexEntry` 가 기록된 개체. 졸업해도 개체는 박스에 남아 계속 키울 수 있는데(#27),
    /// 도감이 박스도 집계하므로(#28) 이 표식이 없으면 같은 개체가 영구 기록과 화면용 행으로 두 번 잡힌다.
    var isGraduated = false
    var level: Int { min(100, 1 + max(0, levelExperience) / 10_000_000) }
    // pathIDs 가 비면(손상된 상태 파일) baseID 로 폴백 — 렌더마다 읽히므로 out-of-bounds 크래시 방지.
    var currentID: Int { pathIDs.isEmpty ? baseID : pathIDs[min(stageIndex, pathIDs.count - 1)] }

    init(baseID: Int, pathIDs: [Int], plannedPathIDs: [Int]? = nil, stageIndex: Int, usedAtStage: Int,
         rarity: Rarity, totalForms: Int, isShiny: Bool = false, nature: PokemonNature? = nil,
         nickname: String? = nil, dittoDisguise: Int? = nil, dittoRevealed: Bool = false,
         names: [Int: [String: String]]? = nil, isGraduated: Bool = false) {
        self.baseID = baseID
        self.pathIDs = pathIDs
        if let plannedPathIDs, !plannedPathIDs.isEmpty {
            self.plannedPathIDs = plannedPathIDs
        } else {
            self.plannedPathIDs = pathIDs
        }
        self.stageIndex = stageIndex
        self.usedAtStage = usedAtStage
        self.rarity = rarity
        self.totalForms = totalForms
        self.isShiny = isShiny
        self.nature = nature
        self.nickname = nickname
        self.names = names
        self.isGraduated = isGraduated
        self.dittoDisguise = dittoDisguise
        self.dittoRevealed = dittoRevealed
    }

    // 하위호환 디코딩: shiny/nature 는 구버전 저장에 없음 → 기본값.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseID = try c.decode(Int.self, forKey: .baseID)
        pathIDs = try c.decode([Int].self, forKey: .pathIDs)
        // 빈 pathIDs 는 손상 상태 → 디코드 실패시켜 전체 CompanionState 가 기본(알)로 폴백되게 한다.
        guard !pathIDs.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .pathIDs, in: c, debugDescription: "empty pathIDs")
        }
        if let savedPlan = try c.decodeIfPresent([Int].self, forKey: .plannedPathIDs), !savedPlan.isEmpty {
            plannedPathIDs = savedPlan
        } else {
            plannedPathIDs = pathIDs
        }
        let decodedStageIndex = try c.decode(Int.self, forKey: .stageIndex)
        stageIndex = min(max(0, decodedStageIndex), pathIDs.count - 1)
        usedAtStage = try c.decode(Int.self, forKey: .usedAtStage)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        totalForms = try c.decode(Int.self, forKey: .totalForms)
        isShiny = try c.decodeIfPresent(Bool.self, forKey: .isShiny) ?? false
        nature = try c.decodeIfPresent(PokemonNature.self, forKey: .nature)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        dittoDisguise = try c.decodeIfPresent(Int.self, forKey: .dittoDisguise)
        dittoRevealed = try c.decodeIfPresent(Bool.self, forKey: .dittoRevealed) ?? false
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        levelExperience = try c.decodeIfPresent(Int.self, forKey: .levelExperience) ?? 0
        learnedMoves = try c.decodeIfPresent([MoveSpec].self, forKey: .learnedMoves) ?? []
        names = try c.decodeIfPresent([Int: [String: String]].self, forKey: .names)
        isGraduated = try c.decodeIfPresent(Bool.self, forKey: .isGraduated) ?? false
    }
}

/// 도감 항목 — 라인 전체(초기→최종) 순서 보존.
struct DexEntry: Codable, Sendable, Identifiable {
    var id = UUID().uuidString
    var baseID: Int
    var finalID: Int
    var chainOrder: [Int]   // 초기→최종 종 id
    var rarity: Rarity
    var caughtAt: Date?
    var isShiny = false
    var nature: PokemonNature?
    /// 진화 체인 각 종의 다국어 이름(speciesID → langCode → name). 졸업 시 로드된 라인에서 저장 →
    /// 도감의 단계별 스프라이트 밑 이름 표시가 네트워크 없이 즉시 + 언어 전환 대응. 구버전 저장분엔
    /// 없어(nil) 뷰가 line fetch 로 조회 후 백필한다.
    var names: [Int: [String: String]]?
    /// 최종체 타입 — 도감 완성 목표의 타입 커버리지가 읽는 값(`DexGoals.progress(.types,…)`).
    ///
    /// **nil 과 `[]` 는 다르다.** nil = 아직 모름(구버전 졸업분·오프라인 졸업)이라 백필이 다음
    /// 열람에서 채운다. `[]` 로 저장하면 "타입 없음" 이 되어 백필이 영영 재시도하지 않는다.
    /// 이 필드는 무결성 서명 대상이다 — canonical 의 `dg` 세그먼트가 타입 커버리지를 세므로
    /// (`SaveTransfer.canonicalString`) 손으로 지우면 조작으로 잡힌다. 백필이 채우는 값은
    /// `save()` 가 재서명하니 정상 경로는 영향받지 않는다.
    var types: [PokemonType]?

    init(id: String = UUID().uuidString,
         baseID: Int, finalID: Int, chainOrder: [Int], rarity: Rarity,
         caughtAt: Date?, isShiny: Bool = false, nature: PokemonNature? = nil,
         names: [Int: [String: String]]? = nil, types: [PokemonType]? = nil) {
        self.id = id
        self.baseID = baseID
        self.finalID = finalID
        self.chainOrder = chainOrder
        self.rarity = rarity
        self.caughtAt = caughtAt
        self.isShiny = isShiny
        self.nature = nature
        self.names = names
        self.types = types
    }

    // 하위호환 디코딩 (MonState 와 동일 이유).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        baseID = try c.decode(Int.self, forKey: .baseID)
        finalID = try c.decode(Int.self, forKey: .finalID)
        chainOrder = try c.decode([Int].self, forKey: .chainOrder)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        caughtAt = try c.decodeIfPresent(Date.self, forKey: .caughtAt)
        isShiny = try c.decodeIfPresent(Bool.self, forKey: .isShiny) ?? false
        nature = try c.decodeIfPresent(PokemonNature.self, forKey: .nature)
        // try? — 구버전(최종체 단일 [String:String]) 형식이 남아 있어도 종별 맵 디코딩 실패 시 nil 로
        // 강등(항목 전체 로드는 유지). 뷰가 line 조회로 백필한다.
        names = (try? c.decodeIfPresent([Int: [String: String]].self, forKey: .names)) ?? nil
        // try? — 모르는 타입 이름이 섞여 있어도 항목 전체를 잃지 않는다. nil 로 강등되면
        // 백필이 다시 채우므로 복구 가능한 방향이다.
        types = (try? c.decodeIfPresent([PokemonType].self, forKey: .types)) ?? nil
    }
}

/// 배열 항목별 격리 디코딩 래퍼 — 손상된 한 항목이 배열 전체(및 상위 상태) 디코드를 실패시키지 않게.
/// 각 항목을 `try?` 로 감싸므로 실패 항목은 `value == nil` 이 되고 배열 디코드 자체는 성공한다.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(T.self) }
}

private extension KeyedDecodingContainer {
    /// 관대 디코드 — 키 없음/null/타입 불일치를 모두 기본값으로 흡수한다. 한 필드 손상이 상태 전체
    /// (도감·인벤토리)를 날리지 않게(부분 복원 > 전면 리셋). 최상위가 JSON 객체가 아닌 전면 손상은 여전히 throw.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key, default def: T) -> T {
        (try? decode(type, forKey: key)) ?? def
    }
    func lenientOptional<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decode(type, forKey: key)
    }
}

/// 개시 시점에 잡아 둔 랭크전 판돈. 상대 랭크를 함께 적는 건 앱이 죽은 뒤의 패배 정산에도
/// LP 계산(`BattleRank.apply(win:opponent:)`)에 상대 티어가 필요하기 때문이다.
struct PendingRankedBattle: Codable, Sendable, Equatable {
    var stake: Int
    var opponent: BattleRank
}

/// 영속 상태(Application Support JSON). 포켓몬 전환 — 이전 커스텀 캐릭터 상태는 폐기(새로 시작).
struct CompanionState: Codable, Sendable {
    /// 배포 단위 강제 초기화 버전. 기존 세이브에는 키가 없어서 0으로 읽히며, 현재 버전보다 낮으면
    /// 최초 실행 한 번만 완전 초기화한다. 초기화 후 현재 값이 저장돼 다음 실행부터는 유지된다.
    var forcedResetVersion = SaveTransfer.forcedResetVersion
    /// 무결성 canonical 형식 버전. 구버전은 첫 로드에서 검사를 건너뛰고 새 형식으로 재서명한다.
    /// 새 필드 추가가 정상 세이브를 변조로 오인해 초기화하는 일을 막는다.
    var integrityVersion = SaveTransfer.integrityVersion
    /// 경제 스키마 버전 — 신규 상태는 현재 버전, 구버전 세이브는 디코드 기본값 0 으로 남아
    /// SaveTransfer.sanitized 의 리셋 마이그레이션을 탄다(도감·수집·언어만 계승).
    var economyVersion = IdleEconomy.currentVersion
    /// 마지막 생산 틱 시각 — 다음 틱은 이 시각과의 경과분(maxTickInterval 캡)만 적립한다.
    /// nil = 아직 틱 없음(신규/리셋 직후) — 첫 틱은 기준점만 잡고 적립하지 않는다.
    var lastTickAt: Date?
    /// 함께한 시간(초) — 앱이 켜져 생산한 누적 시간. 대시보드가 "토큰 사용량" 대신 이 시간을 보여준다.
    var activeSecondsTotal: Double = 0
    /// 오늘 함께한 시간(초) + 그 날짜 — 날짜가 바뀐 첫 틱에 0으로 리셋.
    var activeSecondsToday: Double = 0
    var activeSecondsDate: String = ""
    /// 일일 사탕을 지급한 로컬 날짜(YYYY-MM-DD). 날짜가 바뀐 첫 틱에 재지급.
    var lastCandyDate = ""
    // 별의모래: 설치 이후 생산 누적(성장 미터, 불변)
    var usedSinceInstall = 0
    // 상점에서 쓴 별의모래 누적(재화 지출 원장). 쓸 수 있는 재화 = usedSinceInstall − spentTokens.
    // 성장 미터(usedSinceInstall)는 불변 — 구매는 이 값만 올려 잔액을 깎는다(성장 되감김 없음).
    var spentTokens = 0
    var starPieces = 0
    // 현재 알이 생긴 뒤 쌓인 별의모래(부화 인큐베이션). 누적(usedSinceInstall)과 별개 — 졸업 후 새 알마다 0.
    var eggUsage = 0
    // 현재 알이 보증하는 등급 하한(프리미엄 알). nil = 보증 없음(무료 알·기본 알).
    // ★영속이어야 한다 — 구매 시점엔 종을 못 정한다(롤에 네트워크가 필요). 보증을 상태에 적어 두고
    // 롤이 그것을 읽어야 오프라인·재시작을 건너서도 산 것을 받는다. 부화·졸업 때 nil 로 소비된다.
    var eggTier: Rarity?
    // 알 상태에서 미리 롤해둔 부화 종(프리패칭) — 부화 순간 네트워크 딜레이 제거. 재시작에도 유지.
    var pendingHatchID: Int?
    // 트레이너 이름 — 첫 시작에 입력받아 배틀에 표시. 빈 문자열이면 아직 미입력(이름 입력 화면).
    var trainerName = ""
    // 첫 파트너를 골랐는지 — false면 알이 아니라 스타터 선택 화면으로 시작(맨 처음 1회).
    // 졸업 후 새 알부터는 true 라 기존 알/부화 루프로 돌아간다.
    var starterChosen = false
    // 스타터 선택 후보 — 1세대(1~151) 기본형 중 무작위 3종. 한 번 뽑아 고정(재렌더/재시작에도 유지).
    var starterCandidates: [Int] = []
    // 현재 포켓몬(없으면 알)
    var active: MonState?
    var boxedMons: [MonState] = []
    // 도감
    var dex: [DexEntry] = []
    // 소유한 (base,final) 쌍 — 분기 다양성용
    var collectedFinals: Set<String> = []
    /// 딴 체육관 배지(`Gym.id`). 기록이므로 한 번 들어가면 빠지지 않는다 —
    /// 재도전은 연습이고, 보상은 첫 승리에만 나간다.
    var gymBadges: Set<String> = []
    /// 남은 이로치 확정 부화 횟수. 부화 한 번에 하나씩 쓴다.
    /// ★영속이어야 한다 — `eggTier` 와 같은 이유로, 받은 시점과 쓰는 시점이 떨어져 있다.
    var shinyEggCharges = 0
    var language: AppLanguage = .systemDefault   // 신규 설치 = 시스템 로케일
    // 인벤토리 (ItemKind.rawValue → 개수)
    var inventory: [String: Int] = [:]
    var care = PetCareState()
    var adventure: AdventureRun?
    var adventureHistory: [AdventureRecord] = []
    var battleHistory: [BattleRecord] = []
    var battleRank = BattleRank()
    /// 진행 중인 랭크전의 에스크로 — 개시 때 지갑에서 빠져나간 판돈과 상대 랭크를 적어 둔다.
    /// 정산이 배틀 **끝**에만 있던 때는 지고 있을 때 앱을 종료하면 판돈을 안 냈다(상대는 승리
    /// 처리로 받으니 총량이 늘었다). 이 값이 남아 있는 채로 앱이 뜨면 그 배틀은 패배로 정산된다.
    var pendingRanked: PendingRankedBattle?
    // 트레이너 성장 — 졸업으로 초기화되지 않는 계정 단위 누적. 파트너가 바뀌어도 이어진다.
    var trainer = TrainerLevel()
    // 일간·주간 미션 진행도. 갱신은 타이머가 아니라 날짜/주 키 비교로 일어난다(MissionBoard 참고).
    var missions = MissionBoard()
    var focusEggs = 0
    // 보관 중인 알마다 자동 부화 예정 시각. 알은 획득 5분 뒤 현재 동행과 무관하게 박스에서 부화한다.
    var focusEggReadyDates: [Date] = []
    var eggFragments = 0
    var lastAdventureBonusDate = ""
    var adventureWeekKey = ""
    var weeklyAdventureCount = 0
    // 세이브 무결성 해시(기기 시드) — 손으로 JSON 을 고치면 불일치 → 로드 때 조작 판정.
    // 이 필드 자체는 해시 입력에서 제외한다(자기참조 방지). 빈 값 = 아직 서명 전(구버전/첫 로드).
    var integrity = ""

    init() {}

    // 하위호환 + 손상 복원 디코딩: 누락 키·타입 불일치·일부 손상 필드를 모두 기본값으로 흡수한다 —
    // 한 필드가 깨져도 상태 전체(도감·인벤토리)를 날리지 않는다(부분 복원). 최상위가 JSON 객체가 아닌
    // 전면 손상만 throw → load() 가 원본을 .corrupt 로 백업하고 fresh 로 시작.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        forcedResetVersion = c.lenient(Int.self, forKey: .forcedResetVersion, default: 0)
        // 키 없음 = 토큰 경제 시절 세이브 → 0 으로 남겨 sanitized 의 리셋 마이그레이션 대상이 되게 한다.
        economyVersion     = c.lenient(Int.self, forKey: .economyVersion, default: 0)
        integrityVersion   = c.lenient(Int.self, forKey: .integrityVersion, default: 0)
        lastTickAt         = c.lenientOptional(Date.self, forKey: .lastTickAt)
        activeSecondsTotal = c.lenient(Double.self, forKey: .activeSecondsTotal, default: 0)
        activeSecondsToday = c.lenient(Double.self, forKey: .activeSecondsToday, default: 0)
        activeSecondsDate  = c.lenient(String.self, forKey: .activeSecondsDate, default: "")
        lastCandyDate      = c.lenient(String.self, forKey: .lastCandyDate, default: "")
        usedSinceInstall   = c.lenient(Int.self, forKey: .usedSinceInstall, default: 0)
        spentTokens        = c.lenient(Int.self, forKey: .spentTokens, default: 0)
        starPieces          = c.lenient(Int.self, forKey: .starPieces,
                                       default: max(0, usedSinceInstall - spentTokens))
        eggUsage           = c.lenient(Int.self, forKey: .eggUsage, default: 0)
        // 모르는 rawValue 는 nil(보증 없음)로 강등 — 관대 디코딩의 안전한 방향(있지도 않은 보증을 만들지 않는다).
        eggTier            = c.lenientOptional(Rarity.self, forKey: .eggTier)
        pendingHatchID     = c.lenientOptional(Int.self, forKey: .pendingHatchID)
        trainerName        = c.lenient(String.self, forKey: .trainerName, default: "")
        starterChosen      = c.lenient(Bool.self, forKey: .starterChosen, default: false)
        starterCandidates  = c.lenient([Int].self, forKey: .starterCandidates, default: [])
        // active 손상(빈 pathIDs 등) → 알로 폴백하되 도감·인벤토리는 보존.
        active             = c.lenientOptional(MonState.self, forKey: .active)
        boxedMons          = c.lenient([Lossy<MonState>].self, forKey: .boxedMons, default: []).compactMap(\.value)
        // 도감은 항목별 격리 — 손상 항목 하나가 도감 전체를 날리지 않게.
        dex                = c.lenient([Lossy<DexEntry>].self, forKey: .dex, default: []).compactMap(\.value)
        collectedFinals    = c.lenient(Set<String>.self, forKey: .collectedFinals, default: [])
        gymBadges          = c.lenient(Set<String>.self, forKey: .gymBadges, default: [])
        shinyEggCharges    = c.lenient(Int.self, forKey: .shinyEggCharges, default: 0)
        language           = c.lenient(AppLanguage.self, forKey: .language, default: .systemDefault)
        inventory          = c.lenient([String: Int].self, forKey: .inventory, default: [:])
        care               = c.lenient(PetCareState.self, forKey: .care, default: PetCareState())
        adventure          = c.lenientOptional(AdventureRun.self, forKey: .adventure)
        adventureHistory   = c.lenient([Lossy<AdventureRecord>].self, forKey: .adventureHistory, default: []).compactMap(\.value)
        battleHistory      = c.lenient([Lossy<BattleRecord>].self, forKey: .battleHistory, default: []).compactMap(\.value)
        battleRank         = c.lenient(BattleRank.self, forKey: .battleRank, default: BattleRank())
        pendingRanked      = c.lenientOptional(PendingRankedBattle.self, forKey: .pendingRanked)
        trainer            = c.lenient(TrainerLevel.self, forKey: .trainer, default: TrainerLevel())
        missions           = c.lenient(MissionBoard.self, forKey: .missions, default: MissionBoard())
        focusEggs          = c.lenient(Int.self, forKey: .focusEggs, default: 0)
        focusEggReadyDates = c.lenient([Date].self, forKey: .focusEggReadyDates, default: [])
        eggFragments       = c.lenient(Int.self, forKey: .eggFragments, default: 0)
        lastAdventureBonusDate = c.lenient(String.self, forKey: .lastAdventureBonusDate, default: "")
        adventureWeekKey   = c.lenient(String.self, forKey: .adventureWeekKey, default: "")
        weeklyAdventureCount = c.lenient(Int.self, forKey: .weeklyAdventureCount, default: 0)
        integrity          = c.lenient(String.self, forKey: .integrity, default: "")
    }
}

// NOTE: 부화 후보는 더 이상 하드코딩하지 않는다 — CompanionStore.chooseBase() 가
// PokéAPI 전수(1~5세대)를 capture_rate 가중 rejection sampling 으로 선정한다.
