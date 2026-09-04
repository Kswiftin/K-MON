import Foundation

/// 상점에서 살 수 있는 것 하나. 종류마다 구매 경로가 다르지만(아이템·알·의상·기술머신)
/// **목록과 구매가 같은 값을 쓰게** 하나로 묶는다 — 두 벌이면 목록에 뜨는데 못 사는 물건이 생기고,
/// 갈라진 걸 알아챌 방법은 손으로 맞대 보는 것뿐이다.
enum ShopGood: Equatable, Sendable {
    case item(ItemKind)
    /// 보증 없는 기본 알. 상점은 등급 보증 알을 팔지 않는다(값만 비싸고 보증이 안 붙던 시절의
    /// 자국이 `buyEgg` 주석에 남아 있다).
    case egg
    case outfit(OutfitItem)
    case machine(TechnicalMachine)

    /// 요청 파일에 적히는 이름. **rawValue 계열만 쓴다** — 표시 이름으로 적으면 언어 설정을 바꾼
    /// 사용자가 자기 요청 파일을 못 읽는다.
    var slug: String {
        switch self {
        case .item(let kind): kind.rawValue
        case .egg: "egg"
        case .outfit(let item): item.rawValue
        case .machine(let machine): machine.label.lowercased()
        }
    }

    /// 별의조각 값. 카탈로그에 있는 것은 값이 있다 — 없는 물건은 애초에 목록에 안 들어간다.
    var price: Int {
        switch self {
        case .item(let kind): kind.shopPrice ?? 0
        case .egg: FreshEgg.price(guaranteeing: nil)
        case .outfit(let item): item.shopPrice ?? 0
        case .machine(let machine): machine.price
        }
    }

    /// 여러 개를 한 번에 살 수 있는가. 의상은 한 벌뿐이고, 보유형 아이템도 재구매가 막혀 있다.
    var allowsQuantity: Bool {
        switch self {
        case .item(let kind): !kind.isPassive
        case .egg, .machine: true
        case .outfit: false
        }
    }

    /// 사람이 읽는 이름. 목록과 답 문구가 같은 값을 쓰게 여기 한 곳에 둔다.
    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .item(let kind): L(language).itemName(kind)
        case .egg: L(language).t("신비한 알", "Mystery Egg", "ふしぎなタマゴ")
        // 의상·기술머신은 현지화 표가 없다. 슬러그를 그대로 보여 주는 편이 "없음" 보다 낫다 —
        // 사용자가 그 값을 그대로 쳐서 살 수 있다.
        case .outfit(let item): item.rawValue
        case .machine(let machine): machine.label
        }
    }
}

/// 상점 재고 한 벌. **파는 것만 담는다** — 값이 없는 물건(업적 보상 의상)이 섞이면 사용자가 살 수
/// 없는 줄을 보고 값을 묻는다.
enum ShopCatalog {
    static let all: [ShopGood] =
        ItemKind.allCases.filter { $0.shopPrice != nil }.map { ShopGood.item($0) }
        + [.egg]
        + OutfitItem.allCases.filter { $0.shopPrice != nil }.map { ShopGood.outfit($0) }
        + TechnicalMachine.catalog.map { ShopGood.machine($0) }

    /// 이름 → 물건. 슬러그와 **표시 이름 둘 다** 받는다 — `shop` 이 찍어 준 이름을 그대로 쳤을 때
    /// 안 되면 사용자는 무엇을 쳐야 할지 알 수 없다(`ItemKind.named` 와 같은 규칙).
    ///
    /// 추측이 아니라 닫힌 목록 대조다. 목록 밖 이름은 물건이 되지 않는다.
    static func named(_ raw: String) -> ShopGood? {
        let needle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return all.first { good in
            good.slug.lowercased() == needle
                || AppLanguage.allCases.contains { good.displayName($0).lowercased() == needle }
        }
    }
}
