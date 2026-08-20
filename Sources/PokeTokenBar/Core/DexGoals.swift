import Foundation

/// 목표가 세는 축. **세이브에 들어가는 건 아무것도 없다** — 진행도는 `state.dex` 에서 계산되므로
/// 이 열거형은 `Codable` 이 아니고, case 이름을 나중에 바꿔도 기존 세이브가 깨지지 않는다.
enum DexGoalKind: Sendable, CaseIterable { case species, types, shiny }

struct DexGoal: Identifiable, Sendable {
    /// 카탈로그 안에서 유일해야 한다 — 차집합·알림·테스트가 이 값으로 목표를 되찾는다.
    let id: String
    let kind: DexGoalKind
    let target: Int
    /// 보상은 체육관과 같은 형태다(알·등급 보증·이로치 확정). 목표 하나가 졸업 수십 회라
    /// 별의조각으로는 크기가 안 맞는다 — `GymLeague.completionReward` 가 같은 판단을 먼저 내렸다.
    let reward: GymReward
}

/// 도감 완성 목표 — 종·타입·이로치.
///
/// **진행도를 저장하지 않는다.** 졸업 기록은 도감에서 빠지지 않으므로 진행도는 `state.dex` 의
/// 파생값이고, 그래서 지급 여부를 기억할 필요가 없다: 도감을 바꾸기 **전후로 완료 집합을 한 번씩
/// 계산해 차집합만 지급**하면 그것이 곧 "이번에 넘은 목표"다. 수령 플래그도, 클램프도, 새 세이브
/// 필드도 없다(미션·배지가 각각 무결성·정규화·필드 분류 세 곳을 손대야 했던 부분이 사라진다).
///
/// 단조성이 이 방식의 전제다 — 진행도가 줄 수 있으면 같은 목표를 두 번 넘게 된다. 그래서 세는
/// 대상은 **졸업 기록뿐**이다. 화면용 `dexEntries` 는 활성·박스 개체를 합성해 넣으므로
/// (`CompanionStore.livingDexEntries`) 알을 새로 사면 그 개체가 사라지면서 진행도가 되감긴다.
enum DexGoals {
    /// 조절 손잡이는 이 표 하나뿐이다. 기준선 — 체육관 완주 총액이 알 4개 + 이로치 확정 1,
    /// 상점 알 1개가 20,000⭐. 여기 총액은 알 7개 + 이로치 확정 2 + 2,000⭐ 이고 달성에 드는 건
    /// 졸업 50회다(체육관은 배틀 8승). 첫 칸은 이미 몇 번 졸업한 사람이 곧 닿도록 낮게 둔다.
    static let catalog: [DexGoal] = [
        DexGoal(id: "species10", kind: .species, target: 10,
                reward: GymReward(eggs: 1)),
        DexGoal(id: "species25", kind: .species, target: 25,
                reward: GymReward(eggs: 1, eggGuarantee: .uncommon)),
        DexGoal(id: "species50", kind: .species, target: 50,
                reward: GymReward(eggs: 2, eggGuarantee: .rare)),
        DexGoal(id: "types9", kind: .types, target: 9,
                reward: GymReward(eggs: 1)),
        DexGoal(id: "types18", kind: .types, target: 18,
                reward: GymReward(eggs: 1, eggGuarantee: .rare, shinyCharges: 1)),
        DexGoal(id: "shiny1", kind: .shiny, target: 1,
                reward: GymReward(starPieces: 2_000)),
        DexGoal(id: "shiny3", kind: .shiny, target: 3,
                reward: GymReward(eggs: 1, shinyCharges: 1))
    ]

    /// 목표 id 로 되찾기 — 차집합이 돌려주는 건 id 뿐이다(`GymLeague.gym(id:)` 와 같은 형태).
    static func goal(id: String) -> DexGoal? { catalog.first { $0.id == id } }

    /// 한 축의 진행도. 넘기는 배열은 **졸업 기록**이어야 한다(위 주석의 단조성 참고).
    static func progress(_ kind: DexGoalKind, in dex: [DexEntry]) -> Int {
        switch kind {
        // 라인 전체를 센다 — 도감 격자와 같은 단위(`CompanionStore.dexSpecies`).
        case .species: return Set(dex.flatMap(\.chainOrder)).count
        // nil 은 "아직 모름" 이다(구버전·오프라인 졸업). 커버리지에 넣지 않으니 백필 뒤에 오른다.
        case .types:   return Set(dex.compactMap(\.types).flatMap { $0 }).count
        // 종이 아니라 **개체** 수 — 같은 종을 두 번 이로치로 졸업시키면 2다.
        case .shiny:   return dex.lazy.filter(\.isShiny).count
        }
    }

    /// 지금 달성된 목표 id 집합. 지급은 이 집합의 차집합으로만 일어난다.
    /// 진행도는 축마다 한 번만 계산한다 — 목표마다 다시 훑으면 도감 크기 × 카탈로그가 된다.
    static func completed(in dex: [DexEntry]) -> Set<String> {
        var reached: Set<String> = []
        for kind in DexGoalKind.allCases {
            let current = progress(kind, in: dex)
            for goal in catalog where goal.kind == kind && current >= goal.target {
                reached.insert(goal.id)
            }
        }
        return reached
    }

    /// 표시용 — 축마다 **아직 안 넘은 첫 목표** 하나씩(전부 넘겼으면 마지막 목표).
    /// 도감 헤더가 한 줄이라 축 수(3)만큼만 보여준다.
    static func rows(in dex: [DexEntry]) -> [(goal: DexGoal, progress: Int)] {
        DexGoalKind.allCases.compactMap { kind in
            let ladder = catalog.filter { $0.kind == kind }
            guard let last = ladder.last else { return nil }
            let current = progress(kind, in: dex)
            return (ladder.first { current < $0.target } ?? last, current)
        }
    }
}
