import Foundation

/// 아이템 한 종류를 쓴 결과. **사유만 낸다** — 대화는 모델용 영문 한 줄이, 터미널은 사람이 읽는
/// 한국어가 필요하므로 문구는 프런트엔드가 붙인다(`PokedoroSessionGate` 와 같은 규칙).
enum ItemUseOutcome: Equatable, Sendable {
    case candy(CompanionStore.CandyUseResult)
    case mint(PokemonNature)
    /// 기술 후보 카드가 떴을 뿐 **아직 아무것도 안 바뀌었다.** 성공으로 뭉개면 부른 쪽이
    /// "기술을 바꿨다" 고 말한다.
    case relearnOpened
    case evolutionItemUsed
    /// 부적처럼 지니고만 있는 물건 — "지금 쓴다" 는 개념이 없다. **재고 부족과 갈라 둔다**:
    /// 사러 가야 하는지, 애초에 쓰는 물건이 아닌지 사용자가 할 일이 다르다.
    case notUsedThisWay
    case unavailable
    /// 재고는 있는데 사용 경로가 거절했다(진화 조건 불충족 등).
    case refused
}

/// 진화 승인 결과.
enum EvolutionOutcome: Equatable, Sendable {
    case evolved(stage: Int)
    case nonePending
    /// 카드가 뜬 뒤에 조건이 무너졌다 — 밤 한정 진화를 새벽에 승인하거나, 요구 기술을 잊었거나,
    /// 요구 파티원이 빠진 경우다. 대기 여부만 보면 이 구간이 성공으로 보고된다.
    case conditionsNoLongerMet
}

/// 파트너에게 하는 일의 **공유 실행 경로**. 화면 버튼이 부르는 스토어 메서드를 그대로 부른다 —
/// 여기서 인벤토리를 직접 깎거나 상태를 만지면 경로가 둘이 되어 소모·연출·진화가 어긋난다.
///
/// 대화와 터미널이 이 표를 함께 읽는 이유는 두 벌이 되는 순간 한쪽만 고쳐지기 때문이다. 실제로
/// 그 부류가 이미 있었다(`PokedoroSessionGate` 를 뽑은 이유 — 휴식 단계를 대화만 몰랐다).
@MainActor
enum CompanionAction {
    /// 아이템 한 종류를 그 종류의 **진짜 사용 경로**로 보낸다.
    static func useItem(_ kind: ItemKind, companion: CompanionStore) -> ItemUseOutcome {
        switch kind {
        case .rareCandy:
            let result = companion.useRareCandy()
            // `.unavailable` 은 결과가 아니라 재고 없음이다 — 두 사유를 한 케이스로 뭉개면
            // 부르는 쪽이 "썼는데 아무 일도 없음" 과 "못 썼음" 을 구분할 수 없다.
            return result == .unavailable ? .unavailable : .candy(result)
        case .mint:
            guard let nature = companion.useMint() else { return .unavailable }
            return .mint(nature)
        case .heartScale:
            guard companion.canUseHeartScale else { return .unavailable }
            companion.useHeartScale()
            return .relearnOpened
        case .shinyCharm:
            return .notUsedThisWay
        default:
            guard companion.canUseEvolutionItem(kind) else { return .unavailable }
            guard companion.useEvolutionItem(kind) else { return .refused }
            return .evolutionItemUsed
        }
    }

    /// 대기 중인 진화를 승인한다.
    static func acceptEvolution(companion: CompanionStore) -> EvolutionOutcome {
        guard companion.evolutionPrompt != nil else { return .nonePending }
        let before = companion.activeStageIndex
        companion.acceptEvolution()
        // 대기 여부만으로는 부족하다 — `acceptEvolution` 은 조건이 안 맞으면 카드만 지우고
        // **조용히 돌아간다**. 형태가 실제로 올라갔는지로 판정한다.
        guard let stage = companion.activeStageIndex, stage != before else {
            return .conditionsNoLongerMet
        }
        return .evolved(stage: stage)
    }
}
