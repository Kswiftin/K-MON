import Foundation

/// 한 시즌짜리 목표 하나. 세는 행동은 미션과 **같은 어휘**(`MissionEvent`)다 — 적립 훅이 이미
/// 뚫려 있는 곳(모험 정산·졸업)만 지난다. 배틀·레이스를 넣지 않은 건 그 훅이 LAN 전용이라
/// 혼자 하는 사람에게는 영원히 못 채우는 칸이 되기 때문이다.
struct SeasonChallenge: Identifiable, Sendable {
    /// 진행도 사전의 키이자 무결성 canonical 의 일부. 목표값을 품어서(`focus900`) 세트를 넘나들어도
    /// 같은 이름이면 같은 목표다 — 이 규칙이 깨지면 정규화 클램프가 시즌마다 다른 값을 남긴다.
    let id: String
    let event: MissionEvent
    let target: Int
    /// 완료 보상 — 기존 재화인 별의조각. 세트 총액은 아래 표 주석의 상한을 지킨다.
    let reward: Int
}

/// 시즌 순환 챌린지 — 달력 월마다 만료되고 갱신되는 기간 한정 목표 세트.
///
/// **콘텐츠를 저작하지 않는다.** 세트 3개를 시즌 인덱스로 고르는 공식이라 서버도, 시즌마다 앱
/// 업데이트도 필요 없다. 대가는 3개월 주기로 같은 세트가 돌아온다는 것이다 — 표에 세트를 더하면
/// 주기가 늘어난다(`SeasonBoardTests` 가 현재 주기를 못박아 둔다).
///
/// 갱신은 자정 타이머가 아니라 **키 비교**다(`MissionBoard` 와 같은 방식): `yyyy-MM` 이 바뀐 첫
/// 기록에서 진행도를 비운다. 재지급 차단은 수령 플래그가 아니라 **목표값 클램프**다 — 진행도가
/// 목표를 넘을 수 없으니 완료 순간을 두 번 지나지 못한다.
struct SeasonBoard: Codable, Sendable, Equatable {
    /// 조절 손잡이는 이 표뿐이다. 기준선 — 주간 미션 상한 10,600⭐/주(월 약 45,000⭐),
    /// 업적 사다리 평생 41,200⭐, 상점 알 1개 20,000⭐.
    ///
    /// 세트 총액은 셋 다 20,000⭐(알 한 개)로 맞춘다 — 시즌 운이 곧 수입 차이가 되면 안 된다.
    /// 목표는 **미션을 꾸준히 하면 자연히 닿는** 크기다(주간 집중 300분 × 4주 = 1,300분 ≥ 1,200분).
    /// 시즌이 별도 노동이 되면 집중하지 않고 타이머만 켜 두는 유인만 커진다.
    ///
    /// 세트마다 세 이벤트를 하나씩 담는다 — 빠진 이벤트가 있으면 그 시즌엔 그 축을 아무리 해도
    /// 채울 칸이 없고, 겹치면 한 정산이 같은 세트에서 두 칸을 민다.
    static let rotation: [[SeasonChallenge]] = [
        [SeasonChallenge(id: "focus1200", event: .focusMinutes, target: 1_200, reward: 9_000),
         SeasonChallenge(id: "adventures30", event: .adventures, target: 30, reward: 5_000),
         SeasonChallenge(id: "graduations3", event: .graduations, target: 3, reward: 6_000)],

        [SeasonChallenge(id: "adventures45", event: .adventures, target: 45, reward: 8_000),
         SeasonChallenge(id: "focus900", event: .focusMinutes, target: 900, reward: 6_000),
         SeasonChallenge(id: "graduations2", event: .graduations, target: 2, reward: 6_000)],

        [SeasonChallenge(id: "graduations5", event: .graduations, target: 5, reward: 9_000),
         SeasonChallenge(id: "focus900", event: .focusMinutes, target: 900, reward: 6_000),
         SeasonChallenge(id: "adventures25", event: .adventures, target: 25, reward: 5_000)]
    ]

    var seasonKey = ""
    var counts: [String: Int] = [:]

    /// `yyyy-MM` → 월 단위 일련번호. 연도만 보면 12월→1월에서 순서가 뒤집히므로 달까지 편다.
    /// 못 읽는 키는 0 — 새 세이브는 `seasonKey` 가 `""` 인 채로 시작하는데 표시 경로가 그 상태에서도
    /// 세트를 물어본다.
    static func seasonIndex(_ key: String) -> Int {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              year > 0, (1...12).contains(month) else { return 0 }
        return year * 12 + (month - 1)
    }

    /// 이번 시즌의 세트. 콘텐츠가 표가 아니라 이 한 줄의 공식이다.
    static func challenges(forSeasonKey key: String) -> [SeasonChallenge] {
        rotation[seasonIndex(key) % rotation.count]
    }

    /// 시즌이 끝나기까지 남은 일수 — **오늘을 포함**한다. 말일에 0이 되면 아직 채울 수 있는 시즌이
    /// "이미 끝난 것"으로 읽힌다.
    ///
    /// `?? 31` 은 달력이 월 범위를 못 주는 경우의 폴백이라 그레고리력에서는 도달하지 않는다
    /// (`--show-regions` 에 `^0` 으로 남는다). 상수 30/31 로 박으면 2월에서 음수가 나온다.
    static func daysRemaining(at date: Date, calendar: Calendar = .current) -> Int {
        let length = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        return max(1, length - calendar.component(.day, from: date) + 1)
    }

    /// 기록 — 갱신하고, 진행도를 올리고, **이번에 완료된** 챌린지만 반환한다.
    /// 호출부는 반환된 것에만 보상을 주면 되므로 "이미 줬나"를 따로 기억하지 않는다.
    mutating func record(_ event: MissionEvent, _ amount: Int, seasonKey: String) -> [SeasonChallenge] {
        roll(seasonKey: seasonKey)
        guard amount > 0 else { return [] }
        var completed: [SeasonChallenge] = []
        for challenge in Self.challenges(forSeasonKey: seasonKey) where challenge.event == event {
            let before = counts[challenge.id] ?? 0
            // 이미 목표에 닿았으면 건드리지 않는다 — 완료 순간을 두 번 지나지 못하게 하는 지점.
            guard before < challenge.target else { continue }
            let after = min(challenge.target, before + amount)
            counts[challenge.id] = after
            if after == challenge.target { completed.append(challenge) }
        }
        return completed
    }

    /// 표시용 진행도. 시즌이 지났으면 **상태를 바꾸지 않고** 0을 돌려준다 — 화면을 그리려고
    /// 세이브를 더럽히지 않으면서도 달이 바뀌면 즉시 비어 보인다.
    func progress(_ challenge: SeasonChallenge, seasonKey: String) -> Int {
        self.seasonKey == seasonKey ? (counts[challenge.id] ?? 0) : 0
    }

    /// 신뢰경계 정규화 — **저장된 시즌**의 세트에 없는 키를 버리고 값을 `0...target` 으로 클램프한다.
    /// 손편집으로 목표를 넘긴 값이 들어와도 클램프된 값은 곧 완료 상태라 재지급되지 않는다.
    mutating func normalize() {
        let set = Self.challenges(forSeasonKey: seasonKey)
        counts = counts.reduce(into: [:]) { result, entry in
            guard let challenge = set.first(where: { $0.id == entry.key }) else { return }
            result[entry.key] = min(max(0, entry.value), challenge.target)
        }
    }

    /// 무결성 해시 입력 — **정렬**해야 한다. 사전 순회 순서에 기대면 같은 상태가 실행마다 다른
    /// 문자열을 내서 정상 세이브가 무작위로 조작 판정된다. 시즌 키까지 넣어야 지난 시즌의 완료
    /// 상태를 이번 시즌 키에 옮겨 붙이는 것도 서명이 막는다.
    var canonical: String {
        "\(seasonKey)|" + counts.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: ",")
    }

    private mutating func roll(seasonKey: String) {
        guard self.seasonKey != seasonKey else { return }
        self.seasonKey = seasonKey
        counts = [:]
    }
}
