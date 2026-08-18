import Foundation

/// 미션이 세는 행동. **정산된 결과**만 이벤트가 된다 — 타이머를 시작하는 것만으로 진행되면
/// 집중하지 않고 세션만 켜 두는 게 곧 미션 진행이 되어 목표가 집중과 무관해진다.
/// 세이브에 들어가는 건 미션 **id 문자열**뿐이라 이 열거형들은 `Codable` 이 아니다 —
/// 저장되지 않으니 case 이름을 나중에 바꿔도 기존 세이브가 깨지지 않는다.
enum MissionEvent: Sendable {
    case focusMinutes, adventures, graduations
}

enum MissionPeriod: Sendable {
    case daily, weekly
}

struct Mission: Identifiable, Sendable {
    /// 진행도 사전의 키이자 무결성 canonical 의 일부라 카탈로그 안에서 유일해야 한다.
    let id: String
    let period: MissionPeriod
    let event: MissionEvent
    let target: Int
    /// 완료 보상 — **기존 재화인 별의조각**. 새 재화를 만들면 상점·판돈 경제가 두 갈래로 쪼개진다.
    let reward: Int
}

/// 정해진 주기로 갱신되는 반복 목표. 파트너 서사와 무관하게 "내일 앱을 열 이유"를 만드는 층이다.
///
/// 갱신은 자정 타이머가 아니라 **키 비교**다(모험 주간 카운터와 같은 방식) — 날짜/주 키가 바뀐 첫
/// 기록에서 그 주기만 비운다. 백그라운드 작업도, 자정에 깨어날 이유도 없다.
///
/// 완료 보상은 그 순간 자동 지급된다(수령 버튼 없음 — 일일 사탕과 같은 형태). 재지급을 막는 장치는
/// 별도의 "수령함" 플래그가 아니라 **목표에서 자르는 것**이다: 진행도가 목표를 넘을 수 없으니
/// 완료 순간을 두 번 지날 수 없다.
struct MissionBoard: Codable, Sendable, Equatable {
    /// 조절 손잡이는 이 표 하나뿐이다. 기준선 — 25분 모험 200⭐ · 90분 5,400⭐ · 사탕 5,000⭐ · 알 20,000⭐.
    /// 주간 상한은 알 한 개 값보다 낮게 유지한다(`MissionBoardTests` 가 강제).
    static let catalog: [Mission] = [
        Mission(id: "dailyAdventures", period: .daily, event: .adventures, target: 2, reward: 300),
        Mission(id: "dailyFocus", period: .daily, event: .focusMinutes, target: 60, reward: 500),
        Mission(id: "weeklyFocus", period: .weekly, event: .focusMinutes, target: 300, reward: 3_000),
        Mission(id: "weeklyGraduation", period: .weekly, event: .graduations, target: 1, reward: 2_000)
    ]

    var dayKey = ""
    var weekKey = ""
    var daily: [String: Int] = [:]
    var weekly: [String: Int] = [:]

    /// 기록 — 갱신하고, 진행도를 올리고, **이번에 완료된** 미션만 반환한다.
    /// 호출부는 반환된 것에만 보상을 지급하면 되므로 "이미 줬나" 를 따로 기억할 필요가 없다.
    mutating func record(_ event: MissionEvent, _ amount: Int,
                         dayKey: String, weekKey: String) -> [Mission] {
        roll(dayKey: dayKey, weekKey: weekKey)
        guard amount > 0 else { return [] }
        var completed: [Mission] = []
        for mission in Self.catalog where mission.event == event {
            let before = self[mission]
            // 이미 목표에 닿았으면 건드리지 않는다 — 완료 순간을 두 번 지나지 못하게 하는 지점.
            guard before < mission.target else { continue }
            let after = min(mission.target, before + amount)
            self[mission] = after
            if after == mission.target { completed.append(mission) }
        }
        return completed
    }

    /// 표시용 진행도. 주기가 지났으면 **상태를 바꾸지 않고** 0을 돌려준다 —
    /// 화면을 그리려고 세이브를 더럽히지 않으면서도 자정이 지나면 즉시 비어 보인다.
    func progress(_ mission: Mission, dayKey: String, weekKey: String) -> Int {
        let current = mission.period == .daily ? self.dayKey == dayKey : self.weekKey == weekKey
        return current ? self[mission] : 0
    }

    /// 신뢰경계 정규화 — 카탈로그에서 사라진 미션의 잔재를 버리고 값을 `0...target` 으로 자른다.
    /// 손편집으로 목표를 넘긴 값이 들어와도 잘린 값은 곧 완료 상태라 재지급되지 않는다.
    mutating func normalize() {
        daily = Self.normalized(daily, period: .daily)
        weekly = Self.normalized(weekly, period: .weekly)
    }

    /// 무결성 해시 입력 — **정렬**해야 한다. 사전 순회 순서에 기대면 같은 상태가 실행마다 다른
    /// 문자열을 내 정상 세이브가 무작위로 조작 판정된다.
    var canonical: String {
        let counts = [daily, weekly].map { dict in
            dict.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
        }
        return "d\(dayKey)|w\(weekKey)|\(counts[0])|\(counts[1])"
    }

    private mutating func roll(dayKey: String, weekKey: String) {
        // 두 주기를 따로 본다 — 같이 비우면 주간 목표가 매일 초기화돼 도달할 수 없게 된다.
        if self.dayKey != dayKey { self.dayKey = dayKey; daily = [:] }
        if self.weekKey != weekKey { self.weekKey = weekKey; weekly = [:] }
    }

    private subscript(mission: Mission) -> Int {
        get { (mission.period == .daily ? daily : weekly)[mission.id] ?? 0 }
        set {
            if mission.period == .daily { daily[mission.id] = newValue } else { weekly[mission.id] = newValue }
        }
    }

    private static func normalized(_ counts: [String: Int], period: MissionPeriod) -> [String: Int] {
        counts.reduce(into: [:]) { result, entry in
            guard let mission = catalog.first(where: { $0.id == entry.key && $0.period == period })
            else { return }
            result[entry.key] = min(max(0, entry.value), mission.target)
        }
    }
}
