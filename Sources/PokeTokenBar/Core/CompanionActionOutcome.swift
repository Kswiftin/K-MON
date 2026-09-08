import Foundation

/// 아이템 한 종류를 쓴 결과. **사유만 낸다** — 대화는 모델용 영문 한 줄이, 터미널은 사람이 읽는
/// 한국어가 필요하므로 문구는 프런트엔드가 붙인다(`PokedoroSessionGate` 와 같은 규칙).
enum ItemUseOutcome: Equatable, Sendable {
    case candy(CompanionStore.CandyUseResult)
    case mint(PokemonNature)
    /// 테라피스 — 바뀐 타입을 싣는다(민트가 성격을 싣는 것과 같은 이유: 결과가 그 값이다).
    case teraShard(PokemonType)
    /// 지닌물건을 동행에게 지니게 했다. 바뀐 값을 싣지 않는 이유는 부른 쪽이 이미 어느 아이템인지
    /// 알고 있어서다(민트·테라피스는 **무작위 결과**라 값이 필요했다).
    case heldItemGiven
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
    /// **`default:` 를 두지 않는다.** 갈래를 하나 늘렸는데 여기를 빠뜨리면 컴파일은 통과한 채 그
    /// 아이템이 진화 아이템으로 흘러가 대화·터미널에서만 `.unavailable` 이 된다 — 가방의 네 자리와
    /// 같은 함정이고, 그것이 `ItemKind.bagUse` 축이 있는 이유다.
    static func useItem(_ kind: ItemKind, companion: CompanionStore) -> ItemUseOutcome {
        switch kind.bagUse {
        case .candy:
            let result = companion.useRareCandy()
            // `.unavailable` 은 결과가 아니라 재고 없음이다 — 두 사유를 한 케이스로 뭉개면
            // 부르는 쪽이 "썼는데 아무 일도 없음" 과 "못 썼음" 을 구분할 수 없다.
            return result == .unavailable ? .unavailable : .candy(result)
        case .mint:
            guard let nature = companion.useMint() else { return .unavailable }
            return .mint(nature)
        case .teraShard:
            guard let type = companion.useTeraShard() else { return .unavailable }
            return .teraShard(type)
        case .heartScale:
            guard companion.canUseHeartScale else { return .unavailable }
            companion.useHeartScale()
            return .relearnOpened
        case .heldItem:
            // 재고 없음(사러 가야 한다)과 거절(이미 그것을 지니고 있다)을 갈라 낸다.
            guard companion.itemCount(kind) > 0 else { return .unavailable }
            return companion.giveHeldItem(kind) ? .heldItemGiven : .refused
        case .passive:
            return .notUsedThisWay
        case .furniture:
            // 가방에서 쓰는 물건이 아니다(방에서 배치한다). 이름표(`nameable`)가 가구를 빼므로
            // 이름으로는 여기까지 오지 않지만, 갈래를 비워 두면 그 사실이 코드에 안 남는다.
            return .notUsedThisWay
        case .evolutionItem:
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
