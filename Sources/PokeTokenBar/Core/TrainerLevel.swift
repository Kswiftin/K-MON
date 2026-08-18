import Foundation

/// 졸업으로 초기화되지 않는 계정 성장 축. 파트너는 졸업하면 도감으로 떠나고 새 알부터 다시
/// 시작하지만 이 포인트는 남는다 — 한 마리짜리 서사 위에 놓이는 유일한 목표다.
///
/// `BattleRank` 와 같은 구조: 영속은 `points` 하나뿐이고 레벨·진행도·표시는 모두 계산이다.
/// 곡선을 다시 잡아도 세이브 형식은 그대로라 이전 문제가 생기지 않는다.
struct TrainerLevel: Codable, Sendable, Equatable {
    static let maximumLevel = 99
    /// 레벨 n 도달선 = `pointsPerStep × (n-1)²`. 25분 세션 한 번이 딱 2레벨이다.
    /// 초반은 빠르고 뒤로 갈수록 느려진다 — 평평한 곡선은 2레벨이 50레벨만큼 멀어 목표가 안 된다.
    static let pointsPerStep = 25
    /// 만렙 도달선. 적립은 여기서 포화한다(그 위 값은 의미가 없다).
    static let maximumPoints = points(forLevel: maximumLevel)
    /// 졸업 1회 = 25분 세션 4회분. 집중만이 아니라 도감을 채우는 쪽도 성장으로 인정한다.
    static let graduationPoints = 100

    var points = 0

    /// 호출 인자는 항상 1 이상이다 — `level`(1부터), `level + 1`, `maximumLevel` 뿐이다.
    static func points(forLevel level: Int) -> Int {
        let steps = level - 1
        return pointsPerStep * steps * steps
    }

    /// 레벨업 보상 — **기존 재화인 별의조각**으로 지급한다(새 재화를 만들지 않는다).
    /// 규모 기준: 10레벨업 5,000 ≈ 이상한 사탕 1개, 알은 20,000. 이 계수 하나가 경제 조절 손잡이다.
    static func reward(forReaching level: Int) -> Int { 500 * max(0, level) }

    var level: Int {
        let steps = (Double(max(0, points)) / Double(Self.pointsPerStep)).squareRoot()
        return min(Self.maximumLevel, 1 + Int(steps))
    }

    /// 다음 레벨까지 남은 포인트. 만렙이면 nil.
    var pointsToNextLevel: Int? {
        guard level < Self.maximumLevel else { return nil }
        return Self.points(forLevel: level + 1) - max(0, points)
    }

    /// 현재 레벨 구간 진행도(0...1). 만렙은 1.
    var progress: Double {
        guard level < Self.maximumLevel else { return 1 }
        let base = Self.points(forLevel: level)
        // 구간 폭은 `pointsPerStep × (2·level − 1)` 이라 level ≥ 1 에서 항상 양수다 — 0 나눗셈 가드는 두지 않는다.
        let span = Self.points(forLevel: level + 1) - base
        return min(1, max(0, Double(max(0, points) - base) / Double(span)))
    }

    /// 적립 — 오른 레벨 수를 반환한다(한 번에 두 칸 이상도 가능). 0·음수는 무시해 되감기를 막는다.
    @discardableResult
    mutating func add(_ amount: Int) -> Int {
        guard amount > 0 else { return 0 }
        let before = level
        points = min(Self.maximumPoints, max(0, points) + amount)
        return level - before
    }
}
