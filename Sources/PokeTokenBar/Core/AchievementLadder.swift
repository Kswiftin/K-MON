import Foundation

/// 업적이 세는 축. **rawValue 가 세이브 사전의 키다** — case 이름을 바꾸면 기존 진행이 사라진다
/// (`normalize()` 가 모르는 키를 버리므로 조용히 0 이 된다).
enum AchievementTrack: String, Sendable, CaseIterable { case focus, evolve, battle, race }

struct Achievement: Identifiable, Sendable {
    let track: AchievementTrack
    /// 오름차순 문턱. 마지막 값이 카운터 상한이자 재지급 차단선이다.
    let tiers: [Int]
    /// 단계별 보상(별의조각). `tiers` 와 같은 길이여야 한다 — `rewards[tier - 1]` 로 꺼낸다.
    let rewards: [Int]
    /// 진행도 사전의 키. 트랙과 1:1 이라 rawValue 를 그대로 쓴다.
    var id: String { track.rawValue }
}

/// 누적 행동 사다리 — 집중·진화·배틀·레이스.
///
/// 체육관 배지(`CompanionState.gymBadges`)와 **다른 층**이다: 그쪽은 컨텐츠 첫 승리 기록이고
/// 이쪽은 파트너와 무관하게 쌓이는 누적 행동이다. 그래서 이름도 "배지" 가 아니라 업적이다.
///
/// 세이브에 들어가는 건 **누적 카운터 사전 하나**뿐이다. 도달 단계는 저장하지 않는다 — 카운터가
/// 단조 증가라 단계는 파생값이고, 저장하면 둘이 어긋난 상태(단계 3인데 카운터 0)가 생긴다.
///
/// 도감 목표(`DexGoals`)처럼 진행도를 완전히 파생시킬 수는 없다: 그쪽은 `state.dex` 라는 기존
/// 단조 기록이 있었지만 집중 분·진화·승리·완주 누계는 어디에도 없다(`battleHistory` 는 30건에서 잘린다).
///
/// 재지급을 막는 장치는 수령 플래그가 아니라 **마지막 문턱 클램프**다: 카운터가 상한을 넘을 수
/// 없으니 같은 문턱을 두 번 지나지 못한다(`MissionBoard` 의 목표값 클램프와 같은 형태).
struct AchievementLadder: Codable, Sendable, Equatable {
    /// 조절 손잡이는 이 표 하나뿐이다. 기준선 — 25분 모험 200⭐ · 90분 5,400⭐ · 사탕 5,000⭐ ·
    /// 알 20,000⭐ · 주간 미션 상한 10,600⭐/주.
    ///
    /// 트랙당 총액 10,300⭐, 네 트랙 전부 41,200⭐ ≈ 알 2개. **평생 1회**라 반복 수입인 주간 미션보다
    /// 유량이 훨씬 낮다(`AchievementLadderTests` 가 총액 상한을 강제한다).
    /// 1단계는 전부 첫날에 닿도록 낮게 둔다 — 사다리는 첫 칸이 보여야 오른다.
    static let catalog: [Achievement] = [
        Achievement(track: .focus,  tiers: [60, 300, 1_200, 3_000],
                    rewards: [300, 1_000, 3_000, 6_000]),
        Achievement(track: .evolve, tiers: [3, 10, 30, 60],
                    rewards: [300, 1_000, 3_000, 6_000]),
        Achievement(track: .battle, tiers: [1, 5, 20, 50],
                    rewards: [300, 1_000, 3_000, 6_000]),
        Achievement(track: .race,   tiers: [1, 5, 20, 50],
                    rewards: [300, 1_000, 3_000, 6_000])
    ]

    var counts: [String: Int] = [:]

    /// 기록 — 카운터를 올리고 **이번에 넘은 단계만** 반환한다. 호출부는 반환된 것에만 보상을
    /// 지급하면 되므로 "이미 줬나"를 따로 기억할 필요가 없다.
    /// 한 번에 두 단계 이상도 넘을 수 있어 배열을 돌려준다 — 마지막 하나만 주면 그만큼이 손실된다.
    mutating func record(_ track: AchievementTrack, _ amount: Int) -> [(achievement: Achievement, tier: Int)] {
        guard amount > 0 else { return [] }
        var crossed: [(achievement: Achievement, tier: Int)] = []
        for entry in Self.catalog where entry.track == track {
            // 카탈로그상 도달 불가 — 문턱이 빈 칸은 없다(`AchievementLadderTests` 의
            // `testCatalogTiersAscendAndPairWithRewards` 가 강제). 그래서 `--show-regions` 에
            // `^0` 으로 남는다. 빈 칸을 넣으면 크래시 대신 그 트랙이 조용히 멈춘다.
            // (`DexGoals.rows` 의 `guard let last` 와 같은 부류다.)
            guard let ceiling = entry.tiers.last else { continue }
            let before = counts[entry.id] ?? 0
            // 이미 상한이면 건드리지 않는다 — 같은 문턱을 두 번 지나지 못하게 하는 지점.
            guard before < ceiling else { continue }
            let after = min(ceiling, before + amount)
            counts[entry.id] = after
            for (index, threshold) in entry.tiers.enumerated() where before < threshold && threshold <= after {
                crossed.append((entry, index + 1))
            }
        }
        return crossed
    }

    func count(_ track: AchievementTrack) -> Int { max(0, counts[track.rawValue] ?? 0) }

    /// 도달 단계 수(0...문턱 개수). 저장하지 않고 카운터에서 계산한다.
    ///
    /// 아래 `?? 0` 과 `next(_:)` 의 `else { return nil }` 은 **트랙이 카탈로그에 없을 때**의 폴백이라
    /// 도달 불가다(`testCatalogCoversEveryTrackExactlyOnce` 가 강제) — `--show-regions` 에 `^0` 으로 남는다.
    func tier(_ track: AchievementTrack) -> Int {
        let current = count(track)
        return Self.catalog.first { $0.track == track }?.tiers.filter { $0 <= current }.count ?? 0
    }

    /// 아직 안 넘은 첫 문턱. 최고 단계면 nil — 화면이 숫자 대신 완료 표식을 띄운다.
    func next(_ track: AchievementTrack) -> (goal: Int, tier: Int)? {
        guard let entry = Self.catalog.first(where: { $0.track == track }) else { return nil }
        let current = count(track)
        guard let index = entry.tiers.firstIndex(where: { current < $0 }) else { return nil }
        return (entry.tiers[index], index + 1)
    }

    /// 화면용 행 — **카탈로그 순서 그대로**. 사전을 순회하면 선반이 렌더마다 뒤바뀐다.
    var rows: [(achievement: Achievement, count: Int, tier: Int)] {
        Self.catalog.map { ($0, count($0.track), tier($0.track)) }
    }

    /// 신뢰경계 정규화 — 카탈로그에서 사라진 트랙의 잔재를 버리고 `0...마지막 문턱` 으로 클램프한다.
    /// 손편집으로 상한을 넘긴 값이 들어와도 클램프된 값은 곧 최고 단계라 재지급되지 않는다.
    mutating func normalize() {
        counts = counts.reduce(into: [:]) { result, entry in
            guard let known = Self.catalog.first(where: { $0.id == entry.key }),
                  let ceiling = known.tiers.last else { return }
            result[entry.key] = min(max(0, entry.value), ceiling)
        }
    }

    /// 무결성 해시 입력 — **정렬**해야 한다. 사전 순회 순서에 기대면 같은 상태가 실행마다 다른
    /// 문자열을 내서, 정상 세이브가 무작위로 조작 판정된다.
    var canonical: String {
        counts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
    }
}
