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

/// 미션과 시즌 챌린지가 공유하는 목표. 두 원장은 주기 축(일·주 vs 월)만 다르고 **진행도 규칙은
/// 같다** — 클램프가 곧 멱등 가드다(진행도가 목표를 넘을 수 없어 완료 순간을 두 번 지나지 못한다).
/// 규칙을 양쪽에 복제하면 한쪽만 고쳐져 미션과 시즌이 다르게 동작한다.
protocol Goal: Identifiable, Sendable where ID == String {
    var event: MissionEvent { get }
    var target: Int { get }
}

extension Array where Element: Goal {
    /// 진행도를 올리고 **이번에 완료된** 목표만 돌려준다. 호출부는 반환된 것에만 보상을 주므로
    /// "이미 줬나"를 기억하지 않는다.
    func advance(_ event: MissionEvent, _ amount: Int, in counts: inout [String: Int]) -> [Element] {
        var completed: [Element] = []
        for goal in self where goal.event == event {
            let before = counts[goal.id] ?? 0
            // 이미 목표에 닿았으면 건드리지 않는다 — 완료 순간을 두 번 지나지 못하게 하는 지점.
            guard before < goal.target else { continue }
            let after = Swift.min(goal.target, before + amount)
            counts[goal.id] = after
            if after == goal.target { completed.append(goal) }
        }
        return completed
    }

    /// 이 목록에 없는 키를 버리고 값을 `0...target` 으로 클램프한다. 클램프된 값이 곧 완료 상태라
    /// 손편집으로 목표를 넘겨도 재지급되지 않는다.
    func normalized(_ counts: [String: Int]) -> [String: Int] {
        counts.reduce(into: [:]) { result, entry in
            guard let goal = first(where: { $0.id == entry.key }) else { return }
            result[entry.key] = Swift.min(Swift.max(0, entry.value), goal.target)
        }
    }
}

extension Dictionary where Key == String, Value == Int {
    /// 무결성 해시 입력의 진행도 부분 — **정렬** 필수. 사전 순회 순서에 기대면 같은 상태가 실행마다
    /// 다른 문자열을 내서 정상 세이브가 무작위로 조작 판정된다.
    var canonicalCounts: String {
        sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
    }
}

struct Mission: Identifiable, Sendable, Goal {
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
/// 별도의 "수령함" 플래그가 아니라 **목표값 클램프**다: 진행도가 목표를 넘을 수 없으니
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
    /// 호출부는 반환된 것에만 보상을 지급하면 되므로 "이미 줬나"를 따로 기억할 필요가 없다.
    mutating func record(_ event: MissionEvent, _ amount: Int,
                         dayKey: String, weekKey: String) -> [Mission] {
        roll(dayKey: dayKey, weekKey: weekKey)
        guard amount > 0 else { return [] }
        return Self.missions(in: .daily).advance(event, amount, in: &daily)
             + Self.missions(in: .weekly).advance(event, amount, in: &weekly)
    }

    /// 표시용 진행도. 주기가 지났으면 **상태를 바꾸지 않고** 0을 돌려준다 —
    /// 화면을 그리려고 세이브를 더럽히지 않으면서도 자정이 지나면 즉시 비어 보인다.
    func progress(_ mission: Mission, dayKey: String, weekKey: String) -> Int {
        let daily = mission.period == .daily
        guard daily ? self.dayKey == dayKey : self.weekKey == weekKey else { return 0 }
        return (daily ? self.daily : weekly)[mission.id] ?? 0
    }

    /// 신뢰경계 정규화 — 카탈로그에서 사라진 미션의 잔재를 버리고 값을 클램프한다. 키 길이도 여기서
    /// 자른다: 세이브에서 온 임의 길이 문자열이 canonical(해시 입력)에 그대로 실린다.
    mutating func normalize() {
        dayKey = SaveTransfer.clampedKey(dayKey)
        weekKey = SaveTransfer.clampedKey(weekKey)
        daily = Self.missions(in: .daily).normalized(daily)
        weekly = Self.missions(in: .weekly).normalized(weekly)
    }

    var canonical: String { "d\(dayKey)|w\(weekKey)|\(daily.canonicalCounts)|\(weekly.canonicalCounts)" }

    private mutating func roll(dayKey: String, weekKey: String) {
        // 두 주기를 따로 본다 — 같이 비우면 주간 목표가 매일 초기화돼 도달할 수 없게 된다.
        if self.dayKey != dayKey { self.dayKey = dayKey; daily = [:] }
        if self.weekKey != weekKey { self.weekKey = weekKey; weekly = [:] }
    }

    /// 주기별 목록 — 진행도 사전이 주기마다 따로라 목록도 나눠서 넘긴다.
    private static func missions(in period: MissionPeriod) -> [Mission] {
        catalog.filter { $0.period == period }
    }
}
