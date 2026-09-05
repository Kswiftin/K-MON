import Foundation

/// 마친 집중 세션 하나. 남기는 것은 **끝난 시각과 길이** 둘뿐이다 — 작업 라벨은 다음 마일스톤이고,
/// 지금 자리만 잡아 두면 쓰지 않는 필드가 세이브 형식에 먼저 들어간다.
struct FocusSession: Codable, Sendable, Equatable {
    let endedAt: Date
    let minutes: Int
}

/// 집중 세션 원장 — "오늘 몇 세션 · 몇 분" 의 단일 출처.
///
/// **왜 따로 있나.** `FocusTimer.completedSessions` 는 프로세스 수명 카운터라 앱을 껐다 켜면 0이고
/// 자정도 모른다. 그런데 터미널은 그 값에 "오늘 마친 집중 N회" 라는 라벨을 붙여 내보내고 있었다
/// (`PokedoroViewChannel.focusSnapshot`) — 문구가 값보다 많은 것을 약속한 상태였다. 그 카운터는
/// 화면의 **변화 감지기**로만 남고(`FocusTimerView` 의 완료 배너), 보여주는 값은 이 원장이 낸다.
///
/// **날짜 경계는 키 비교다** — 자정 타이머도, 깨어날 이유도 없다(`MissionBoard` 와 같은 방식).
/// 하루의 정의는 `CompanionStore.dayKey` 하나에서만 온다: 원장이 자기 달력을 따로 들면 미션과
/// 세션 기록이 서로 다른 자정을 쓰게 된다.
struct FocusSessionLog: Codable, Sendable, Equatable {
    /// 보존 기간. 주간 회고(마일스톤 4)가 이 안에 들어오므로 지금은 이 값이 곧 상한이다.
    // ponytail: 90일 고정 — 회고 구간이 더 길어지면 그때 늘린다. 설정으로 열 이유가 아직 없다.
    static let retentionDays = 90

    /// 한 세션이 가질 수 있는 최대 길이. 디스크에서 온 값의 상한이다 — 손편집 한 줄이 "오늘 1,000분"
    /// 을 만들면 지표가 통째로 못 쓰게 된다. 하루를 넘는 세션은 정의상 세션이 아니다.
    static let maxSessionMinutes = 24 * 60

    /// 옆 파일 형식을 **여기서** 고정한다. 기본 전략(`.deferredToDate`)은 2001년 기준 실수라
    /// 파일을 열어 봐도 언제인지 알 수 없고, 나중에 전략만 바뀌면 기존 기록이 통째로 다른 날이 된다.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private(set) var sessions: [FocusSession] = []

    /// 마친 세션을 적는다. 시각은 호출부가 넘긴다 — 스토어의 `clock()` 이 들어오므로 테스트가
    /// 자정을 넘길 수 있다. 여기서 `Date()` 를 부르면 그 경로는 영영 검증되지 않는다.
    ///
    /// 적고 나서 곧바로 정규화한다 — 보존 기간 정리와 신뢰경계 검사를 **같은 규칙 한 곳**에 둔다.
    /// 두 벌로 나누면 한쪽만 고쳐져 기록 경로와 로드 경로가 다른 것을 남긴다.
    mutating func record(minutes: Int, at now: Date) {
        sessions.append(FocusSession(endedAt: now, minutes: minutes))
        normalize(now: now)
    }

    /// 그날 마친 세션 수.
    func count(on dayKey: String) -> Int {
        sessions.reduce(0) { CompanionStore.dayKey($1.endedAt) == dayKey ? $0 + 1 : $0 }
    }

    /// 그날 집중한 분.
    func minutes(on dayKey: String) -> Int {
        sessions.reduce(0) { CompanionStore.dayKey($1.endedAt) == dayKey ? $0 + $1.minutes : $0 }
    }

    /// 신뢰경계 — 디스크에서 온 값을 거른다. 이 원장은 무결성 서명 밖의 옆 파일이라
    /// (`CompanionStorageLocations.focusSessionsFileName`) 여기가 유일한 관문이다.
    ///
    /// 미래 시각을 버리는 이유: 시계를 되돌렸다 돌아오면 "아직 오지 않은 오늘" 의 세션이 남아
    /// 그날 집계를 두 번 센다.
    mutating func normalize(now: Date) {
        let oldest = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        sessions = sessions.filter {
            $0.minutes > 0 && $0.minutes <= Self.maxSessionMinutes
                && $0.endedAt <= now && $0.endedAt >= oldest
        }
    }
}
