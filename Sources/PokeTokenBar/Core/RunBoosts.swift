import Foundation

/// 런 동안 **쌓이는** 강화. 회복·부활 같은 소모형 보상과 달리 웨이브를 넘어 남고 중첩되므로,
/// 12 웨이브를 지나는 사이 판마다 다른 빌드가 만들어진다 — 포켓로그의 modifier 더미가 하는 일이다.
/// 소모형만 있던 프로토타입은 매 웨이브의 선택이 "회복 타이밍" 하나였고, 그래서 12 웨이브가
/// 첫 웨이브와 같은 모양으로 끝났다.
///
/// **파티 전체에 걸린다**(개체별 지닌물건이 아니다). 개체마다 갈리면 교체가 손해가 되고,
/// 팝오버 한 화면에 6마리 × 강화 목록이 들어가지 않는다.
///
/// 이 값은 세이브에 남지 않는다(런과 함께 사라진다) — 그래서 숫자를 언제 고쳐도 세이브 이전이 없다.
struct RunBoosts: Sendable, Equatable {
    /// 타입별 데미지 강화 스택. 키가 없는 타입은 강화가 없다.
    var typeDamage: [PokemonType: Int] = [:]
    /// 급소 단계 가산. 기술의 `critStage` 에 더해진다.
    var critStages = 0
    /// 턴 끝 회복 스택. 스택당 최대 HP 의 1/16 이다.
    var leftovers = 0

    /// 스택당 데미지 가산(%).
    static let typeDamagePercentPerStack = 20
    /// 회복 1스택이 돌려주는 최대 HP 의 분모.
    static let leftoversDenominator = 16

    /// 강화가 하나도 없는가. 네트워크 대전·체육관은 이 상태로만 싸운다 — 비어 있으면 데미지도
    /// rng 소비도 강화가 없던 시절과 한 값도 다르지 않다.
    var isEmpty: Bool { typeDamage.isEmpty && critStages == 0 && leftovers == 0 }

    /// 이 기술 타입에 강화를 곱한 데미지. 정수 연산으로 두는 이유는 엔진의 다른 배율과 같다 —
    /// 부동소수 오차가 끼면 같은 판을 두 번 굴려도 값이 갈릴 자리가 생긴다.
    func damage(_ amount: Int, moveType: PokemonType) -> Int {
        guard let stacks = typeDamage[moveType], stacks > 0 else { return amount }
        return amount * (100 + Self.typeDamagePercentPerStack * stacks) / 100
    }

    /// 턴 끝 회복량. 스택이 없으면 0 이고, 호출부는 그 0 을 보고 이벤트를 내지 않는다 —
    /// 매 턴 "회복했다" 줄이 로그를 덮으면 실제로 무엇이 일어났는지 읽을 수 없다.
    func leftoversHeal(maxHP: Int) -> Int {
        guard leftovers > 0 else { return 0 }
        return max(leftovers, maxHP * leftovers / Self.leftoversDenominator)
    }
}
