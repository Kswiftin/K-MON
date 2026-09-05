import Foundation

/// 마친 집중 세션 하나 — 끝난 시각, 길이, 그리고 **무엇을 하기로 했었나**.
struct FocusSession: Codable, Sendable, Equatable {
    let endedAt: Date
    let minutes: Int
    /// 시작할 때 붙인 한 줄. **선택이다** — 라벨 입력이 시작의 마찰이 되면 세션 자체가 안 시작되고,
    /// 그러면 이 기록이 재려던 주 지표가 먼저 망가진다. 라벨 없는 세션도 똑같이 기록된다.
    ///
    /// **옛 파일에는 없는 칸**이라 없어도 디코딩된다(옵셔널 → `decodeIfPresent`). 여기가 깨지면
    /// `loadFocusSessions` 가 복원 실패로 보고 파일을 지우므로, 마일스톤 1이 쌓은 90일치 기준선이
    /// 통째로 사라진다.
    let label: String?

    /// 라벨 최대 길이. 팝오버 한 줄과 터미널 한 줄에 들어가야 하고, 이 파일은 무결성 서명 밖이라
    /// 손으로도 고칠 수 있다 — 상한이 없으면 한 줄짜리 손편집이 두 화면을 통째로 밀어낸다.
    static let maxLabelCharacters = 40

    /// 라벨 정리. **시작 경로와 디스크 경로가 이 함수 하나를 함께 쓴다** — 두 벌로 나누면 화면에
    /// 뜨는 라벨과 기록에 남는 라벨이 갈리고, 그 차이는 아무 테스트도 못 잡는다.
    ///
    /// 공백(줄바꿈·탭 포함)으로 쪼개 한 칸으로 다시 잇는다: 라벨은 **한 줄**이라는 계약이라
    /// 줄바꿈이 남으면 터미널이 한 줄로 세어 둔 자리에 두 줄을 그려 그 아래가 전부 밀린다.
    /// 남는 것이 없으면 `nil` — 빈 문자열을 남기면 "라벨이 붙은 세션" 을 세는 쪽이 그걸 센다.
    static func sanitize(label: String?) -> String? {
        guard let label else { return nil }
        let flattened = label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !flattened.isEmpty else { return nil }
        return String(flattened.prefix(maxLabelCharacters))
    }
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
    mutating func record(minutes: Int, label: String? = nil, at now: Date) {
        sessions.append(FocusSession(endedAt: now, minutes: minutes, label: label))
        normalize(now: now)
    }

    /// 그날 마친 세션들 — 기록한 순서(오래된 것부터). 개수·분도 **이 목록에서 파생한다**:
    /// 화면이 목록을, 요약이 개수를 따로 세면 "오늘 3세션" 인데 두 줄만 보이는 상태가 생긴다.
    func sessions(on dayKey: String) -> [FocusSession] {
        sessions.filter { CompanionStore.dayKey($0.endedAt) == dayKey }
    }

    /// 그날 마친 세션 수.
    func count(on dayKey: String) -> Int { sessions(on: dayKey).count }

    /// 그날 집중한 분.
    func minutes(on dayKey: String) -> Int {
        sessions(on: dayKey).reduce(0) { $0 + $1.minutes }
    }

    /// 신뢰경계 — 디스크에서 온 값을 거른다. 이 원장은 무결성 서명 밖의 옆 파일이라
    /// (`CompanionStorageLocations.focusSessionsFileName`) 여기가 유일한 관문이다.
    ///
    /// 미래 시각을 버리는 이유: 시계를 되돌렸다 돌아오면 "아직 오지 않은 오늘" 의 세션이 남아
    /// 그날 집계를 두 번 센다.
    ///
    /// 라벨도 여기서 다시 정리한다 — 디스크에서 온 라벨은 시작 경로를 거치지 않았으므로, 길이·한 줄
    /// 규칙을 여기 걸지 않으면 손편집한 200자 라벨이 그대로 팝오버와 터미널까지 간다.
    /// 라벨이 비어도 **세션은 남긴다**: 라벨은 선택이고, 버리면 집계가 줄어든다.
    mutating func normalize(now: Date) {
        let oldest = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        sessions = sessions.compactMap { session in
            guard session.minutes > 0, session.minutes <= Self.maxSessionMinutes,
                  session.endedAt <= now, session.endedAt >= oldest else { return nil }
            return FocusSession(endedAt: session.endedAt, minutes: session.minutes,
                                label: FocusSession.sanitize(label: session.label))
        }
    }
}
