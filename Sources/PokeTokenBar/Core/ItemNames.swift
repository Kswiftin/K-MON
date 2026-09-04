import Foundation

/// 이름으로 아이템 종류를 되찾는 표. **대화와 터미널이 같은 표를 읽는다** — 두 벌이면 한쪽만
/// 넓어져 "대화로는 쓸 수 있는데 터미널로는 이름조차 못 부르는" 아이템이 생긴다.
extension ItemKind {
    /// 이름으로 지목할 수 있는 종류 — `useItem` 이 갈래를 가진 것들과 진화 아이템 전체다.
    ///
    /// 가구는 뺀다. `useItem` 의 어느 갈래로도 성공하지 못하는데(진화 규칙이 없어
    /// `canUseEvolutionItem` 에 걸린다) 이름은 갖고 있어서, 표에 두면 **먼저 받아들이고 그제서야
    /// 실패한다** — 사용자에겐 자기가 시킨 일이 안 된 것으로 보인다. 이름 대조 단계에서 걸러야
    /// 화면이 "그런 아이템이 없다" 고 정확히 답할 수 있다.
    ///
    /// 앱 상태(가방 재고)로 좁히지 않는다. 이름 대조가 그때그때의 인벤토리에 의존하면 같은 입력이
    /// 재고에 따라 이름이 되거나 안 되고, 재고는 실행기가 이미 본다.
    static let nameable: [ItemKind] = ItemKind.allCases.filter {
        $0.evolutionRule != nil || [.rareCandy, .mint, .heartScale, .shinyCharm].contains($0)
    }

    /// 이름 → 종류. **화면이 찍어 준 이름 그대로도 받는다** — 대화의 `bag.list` 는 rawValue 를,
    /// 터미널의 `bag` 은 현지화된 표시 이름을 찍으므로 둘 다 정답이어야 한다. 한쪽만 받으면
    /// 사용자가 방금 읽은 이름을 그대로 쳤을 때 이유 없이 실패한다.
    ///
    /// 추측이 아니라 **닫힌 목록 대조**다. 목록 밖 이름은 종류가 되지 않는다.
    ///
    /// 정규화는 **한 번만** 걸린다. rawValue 만 원문 그대로 비교하던 동안 `rare candy`(표시 이름)는
    /// 통하는데 `rarecandy`·` rareCandy `(기계가 찍어 준 정답 값)는 떨어져, 기계가 준 값이 사람
    /// 말보다 까다로운 상태였다.
    static func named(_ raw: String) -> ItemKind? {
        match(raw, in: nameable)
    }

    /// 이름 → **가구.** `named` 와 나눠 두는 이유는 위 주석 그대로다 — 가구는 `use` 로 쓸 수
    /// 없어 `nameable` 에서 일부러 빠져 있고, 거기에 넣으면 `use 침대` 가 먼저 받아들여진 뒤
    /// 실패한다. 방에 놓는 명령은 **가구만** 이름으로 받으면 되므로 표를 하나 더 둔다.
    ///
    /// 대조 규칙(공백 정리·rawValue·세 언어 표시 이름)은 `match` 하나를 공유한다 — 두 벌로
    /// 쓰면 한쪽만 관대해져 같은 이름이 명령에 따라 통하고 안 통한다.
    static func furnitureNamed(_ raw: String) -> ItemKind? {
        match(raw, in: memoryHomeFurniture.sorted { $0.rawValue < $1.rawValue })
    }

    private static func match(_ raw: String, in candidates: [ItemKind]) -> ItemKind? {
        let needle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return candidates.first { kind in
            kind.rawValue.lowercased() == needle
                || AppLanguage.allCases.contains { L($0).itemName(kind).lowercased() == needle }
        }
    }
}
