import Foundation

/// 한 시즌짜리 목표 하나. 어휘는 미션과 같은 `MissionEvent` — 적립 훅이 이미 뚫린 곳(모험 정산·
/// 졸업)만 쓴다. 배틀·레이스는 훅이 LAN 전용이라 혼자 하는 사람에겐 못 채우는 칸이 된다.
struct SeasonChallenge: Identifiable, Sendable, Goal {
    /// 진행도 사전의 키이자 무결성 canonical 의 일부. 목표값을 품어(`focus900`) 같은 이름이면 세트를
    /// 넘나들어도 같은 목표다 — 깨지면 정규화 클램프가 시즌마다 다른 값을 남긴다.
    let id: String
    let event: MissionEvent
    let target: Int
    /// 완료 보상 — 기존 재화인 별의조각.
    let reward: Int
}

/// 시즌 순환 챌린지 — 달력 월마다 만료·갱신되는 기간 한정 목표 세트.
///
/// **콘텐츠를 저작하지 않는다.** 세트를 시즌 인덱스로 고르는 공식이라 서버도, 시즌마다의 앱
/// 업데이트도 없다. 대가는 3개월 주기 반복 — 표에 세트를 더하면 주기가 늘어난다
/// (`SeasonBoardTests` 가 현재 주기를 못박는다).
///
/// 갱신은 자정 타이머가 아니라 **키 비교**(`MissionBoard` 와 같은 방식): `yyyy-MM` 이 바뀐 첫
/// 기록에서 진행도를 비운다. 재지급은 수령 플래그가 아니라 **목표값 클램프**가 막는다.
struct SeasonBoard: Codable, Sendable, Equatable {
    /// 조절 손잡이는 이 표뿐이다. 기준선 — 주간 미션 10,600⭐/주, 업적 평생 41,200⭐, 알 20,000⭐.
    ///
    /// 세트 총액은 셋 다 20,000⭐(알 한 개) — 시즌 운이 수입 차이가 되면 안 된다. 목표는 미션을
    /// 꾸준히 하면 닿는 크기다(주간 집중 300분 × 4주 = 1,300분 ≥ 1,200분).
    ///
    /// 세트마다 세 이벤트를 하나씩 — 빠지면 그 시즌엔 그 축을 채울 칸이 없고, 겹치면 한 정산이
    /// 같은 세트에서 두 칸을 민다.
    static let rotation: [[SeasonChallenge]] = [
        [SeasonChallenge(id: "focus1200", event: .focusMinutes, target: 1_200, reward: 9_000),
         SeasonChallenge(id: "adventures30", event: .adventures, target: 30, reward: 5_000),
         SeasonChallenge(id: "graduations3", event: .graduations, target: 3, reward: 6_000)],

        [SeasonChallenge(id: "adventures45", event: .adventures, target: 45, reward: 8_000),
         SeasonChallenge(id: "focus900", event: .focusMinutes, target: 900, reward: 6_000),
         SeasonChallenge(id: "graduations2", event: .graduations, target: 2, reward: 6_000)],

        // 집중 목표가 세트 1 과 같으면(`focus900`) 인접한 두 달에 같은 칸이 나와 로테이션이 반만
        // 돈다. 목표만 다르게 두고 보상은 6,000 유지 — 세트 총액이 곧 수입 안정성이다.
        [SeasonChallenge(id: "graduations5", event: .graduations, target: 5, reward: 9_000),
         SeasonChallenge(id: "focus1000", event: .focusMinutes, target: 1_000, reward: 6_000),
         SeasonChallenge(id: "adventures25", event: .adventures, target: 25, reward: 5_000)]
    ]

    /// 남은 일수용 달력. `.current` 면 시스템 달력이 이슬람력인 사용자에게 `seasonKey`
    /// (en_US_POSIX = 그레고리력)와 **다른 달**의 길이가 나와 카운트다운이 만료와 어긋난다.
    ///
    /// `let` 이 아니라 계산 프로퍼티인 이유: `Calendar` 는 생성 시점의 `TimeZone.current` 를 굳히는데
    /// `seasonKey` 는 호출마다 새로 읽는다. 굳히면 실행 중 시간대 변경 후 월초에 둘이 다른 달을 센다.
    static var gregorian: Calendar { Calendar(identifier: .gregorian) }

    var seasonKey = ""
    var counts: [String: Int] = [:]

    /// `yyyy-MM` → 월 단위 일련번호. 연도만 보면 12월→1월에서 순서가 뒤집히므로 달까지 편다.
    /// 못 읽는 키는 0 — 새 세이브는 `seasonKey` 가 `""` 인데 표시 경로가 그때도 세트를 묻는다.
    ///
    /// 연도 상한이 신뢰경계 가드다: 이 키는 **세이브에서 온다**(`normalize`). `1000000000000000000-01`
    /// 이면 `year * 12` 오버플로 트랩으로 프로세스가 죽고, 재기동해도 같은 파일을 읽어 또 죽는다.
    static func seasonIndex(_ key: String) -> Int {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              (1...9_999).contains(year), (1...12).contains(month) else { return 0 }
        return year * 12 + (month - 1)
    }

    /// 이번 시즌의 세트. 콘텐츠가 표가 아니라 이 한 줄의 공식이다.
    static func challenges(forSeasonKey key: String) -> [SeasonChallenge] {
        rotation[seasonIndex(key) % rotation.count]
    }

    /// 시즌 종료까지 남은 일수 — **오늘 포함**. 말일에 0이면 아직 채울 수 있는 시즌이 끝난 것으로 읽힌다.
    /// `?? 31` 은 달력이 월 범위를 못 줄 때의 폴백이라 그레고리력에서는 도달하지 않는다.
    static func daysRemaining(at date: Date, calendar: Calendar = SeasonBoard.gregorian) -> Int {
        let length = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        return max(1, length - calendar.component(.day, from: date) + 1)
    }

    /// 기록 — 갱신하고, 진행도를 올리고, **이번에 완료된** 챌린지만 반환한다.
    /// 호출부는 반환된 것에만 보상을 주므로 "이미 줬나"를 기억하지 않는다.
    mutating func record(_ event: MissionEvent, _ amount: Int, seasonKey: String) -> [SeasonChallenge] {
        roll(seasonKey: seasonKey)
        guard amount > 0 else { return [] }
        return Self.challenges(forSeasonKey: seasonKey).advance(event, amount, in: &counts)
    }

    /// 표시용 진행도. 시즌이 지났으면 **상태를 바꾸지 않고** 0 — 화면을 그리려고 세이브를 더럽히지
    /// 않으면서 달이 바뀌면 즉시 비어 보인다.
    func progress(_ challenge: SeasonChallenge, seasonKey: String) -> Int {
        self.seasonKey == seasonKey ? (counts[challenge.id] ?? 0) : 0
    }

    /// 신뢰경계 정규화 — **저장된 시즌**의 세트에 없는 키를 버린다. 키 길이도 여기서 자른다:
    /// 세이브에서 온 임의 길이 문자열이 canonical(해시 입력)에 그대로 실린다.
    mutating func normalize() {
        seasonKey = SaveTransfer.clampedKey(seasonKey)
        counts = Self.challenges(forSeasonKey: seasonKey).normalized(counts)
    }

    /// 무결성 해시 입력. 시즌 키까지 넣어야 지난 시즌 완료 상태의 이식도 막힌다.
    var canonical: String { "\(seasonKey)|" + counts.canonicalCounts }

    private mutating func roll(seasonKey: String) {
        guard self.seasonKey != seasonKey else { return }
        self.seasonKey = seasonKey
        counts = [:]
    }
}
