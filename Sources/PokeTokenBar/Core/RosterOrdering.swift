import Foundation

/// 로스터(소유 포켓몬 박스) 정렬 기준.
///
/// `caught` 는 저장 순서 — 지금까지의 유일한 순서였다. 60마리가 넘으면 페이지를 넘겨 가며
/// 눈으로 찾는 수밖에 없었다(#87).
enum RosterSort: String, CaseIterable, Sendable {
    case caught     // 저장 순서(부화한 순서)
    /// 도감 번호순 — 도감 격자와 같은 순서다. 두 화면을 같은 순서로 두면 "도감 몇 번째 칸의 그 개체"
    /// 를 박스에서 같은 자리로 찾는다. rawValue 를 세이브에 쓰므로 case 를 나중에 지우면 안 된다.
    case dexNumber
    case name
    case level
}

/// 박스 목록의 정렬·필터. 순수 함수라 뷰 없이 검증할 수 있다 — 표시에 쓰는 이름·타입은
/// 뷰가 미리 해석해 넘긴다(여기서 네트워크를 타지 않는다).
enum RosterOrdering {

    /// 카드에 그리는 이름과 **같은** 문자열. 개체에 저장된 다국어 이름(`MonState.names`)에서 꺼내고,
    /// 없으면 `#종번호`. 정렬 키를 화면과 다른 값으로 잡으면 "이름순인데 순서가 이상하다"가 된다.
    ///
    /// 별명(`nickname`)은 쓰지 않는다 — 카드가 별명을 그리지 않기 때문이다. 카드가 별명을 그리게
    /// 되면 이 함수도 같이 바꿔야 한다.
    static func displayName(_ mon: MonState, language: AppLanguage,
                            resolved: [Int: String] = [:]) -> String {
        if let name = resolved[mon.presentationID], !name.isEmpty { return name }
        if let stored = mon.names?[mon.currentID], let name = language.resolveName(stored), !name.isEmpty {
            return name
        }
        return "#\(mon.currentID)"
    }

    /// 타입 필터 통과 여부.
    ///
    /// **타입이 아직 해석되지 않은 개체는 통과시킨다.** 타입은 `PokeAPIClient.battleProfile` 로
    /// 오므로 오프라인·응답 실패면 영영 비어 있을 수 있다. 그때 숨기면 내 박스의 포켓몬이 조용히
    /// 사라진 것처럼 보인다 — 필터가 데이터 로딩 상태에 따라 결과를 바꾸는 쪽이 더 나쁘다.
    static func passesTypeFilter(_ mon: MonState, type: PokemonType?,
                                 types: [Int: [PokemonType]]) -> Bool {
        guard let type else { return true }
        guard let resolved = types[mon.presentationID], !resolved.isEmpty else { return true }
        return resolved.contains(type)
    }

    /// 필터 적용 후 정렬. 같은 키끼리는 저장 순서를 유지한다(정렬이 흔들리지 않게).
    static func arrange(_ mons: [MonState], sort: RosterSort, ascending: Bool = true,
                        typeFilter: PokemonType? = nil, types: [Int: [PokemonType]] = [:],
                        language: AppLanguage = .en, names: [Int: String] = [:]) -> [MonState] {
        let filtered = mons.filter { passesTypeFilter($0, type: typeFilter, types: types) }
        let indexed = Array(filtered.enumerated())
        let sorted: [(offset: Int, element: MonState)]
        switch sort {
        case .caught:
            sorted = indexed   // 저장 순서 그대로
        case .dexNumber:
            // **현재 형태의 번호**다. 카드가 그리는 스프라이트·이름과 같은 종이라야 순서가 납득된다
            // (기본형 번호로 묶으면 이상해꽃이 3번이 아니라 1번 자리에 선다).
            sorted = indexed.sorted { a, b in
                if a.element.currentID == b.element.currentID { return a.offset < b.offset }
                return a.element.currentID < b.element.currentID
            }
        case .name:
            sorted = indexed.sorted { a, b in
                let l = displayName(a.element, language: language, resolved: names)
                let r = displayName(b.element, language: language, resolved: names)
                let order = l.localizedStandardCompare(r)
                if order == .orderedSame { return a.offset < b.offset }
                return order == .orderedAscending
            }
        case .level:
            sorted = indexed.sorted { a, b in
                if a.element.level == b.element.level { return a.offset < b.offset }
                return a.element.level < b.element.level
            }
        }
        let result = sorted.map(\.element)
        return ascending ? result : result.reversed()
    }

    /// 필터 메뉴에 올릴 타입 — **박스에 실제로 있는** 타입만. 18종을 다 열어 두면 고르는 순간
    /// 빈 화면이 되는 항목이 대부분이다. 도감 순서(`PokemonType.allCases`)로 낸다.
    static func availableTypes(_ mons: [MonState], types: [Int: [PokemonType]]) -> [PokemonType] {
        let present = Set(mons.flatMap { types[$0.presentationID] ?? [] })
        return PokemonType.allCases.filter { present.contains($0) }
    }
}
