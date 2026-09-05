import Foundation

/// 한 주의 집중을 요일·라벨별로 되돌아보는 표(PRD 마일스톤 4).
///
/// **저장 필드가 하나도 없다.** 마일스톤 1–3 이 옆 파일(`focus-sessions.json`)에 이미 날짜·길이·
/// 라벨을 쌓아 뒀으므로 회고는 전부 그 원장에서 **파생**한다 — `FocusChainRules` 가 체인 위치를
/// 파생시킨 것과 같은 형태다. 세이브도, 마이그레이션도, 새 파일도 없다.
///
/// **판정을 순수 타입에 두는 이유**는 `CompanionStore` 가 `@MainActor` 에 네트워크 로딩까지 물려
/// 있어 거기 두면 주 경계·자정·보존 기간을 따로 검증할 방법이 없기 때문이다(`FocusChainRules`·
/// `PokedoroSessionGate` 와 같은 이유).
struct FocusWeekRecap: Equatable, Sendable {

    /// 한 주의 하루. `date` 를 함께 드는 이유는 요일 이름을 **로캘에 맡기기** 위해서다 —
    /// 키 문자열만 들면 화면이 `"2026-09-07"` 을 다시 파싱해 요일을 뽑아야 하고, 그 파싱은
    /// 원장이 이미 쓰고 있는 달력과 갈라질 수 있는 두 번째 자리가 된다.
    struct Day: Equatable, Sendable {
        let date: Date
        let dayKey: String
        let sessions: Int
        let minutes: Int
    }

    /// 라벨 하나의 한 주 합. `label == nil` 이 **라벨 없이 마친 세션 묶음**이다 — 버리면 요일
    /// 막대의 합과 라벨 목록의 합이 달라져 화면이 스스로 모순된다. "제목 없음" 같은 이름을 지어
    /// 채우지도 않는다: 라벨을 안 쓴 것과 못 쓴 것이 화면에서 같아 보이면, 그 비율이 바로
    /// PRD 성공 지표 3("라벨이 붙은 세션 비율")이 보려던 신호다.
    struct LabelTotal: Equatable, Sendable {
        let label: String?
        let sessions: Int
        let minutes: Int
    }

    /// 그 주의 월요일 00:00.
    let weekStart: Date
    /// 항상 일곱 칸, 월요일 먼저. 세션이 없는 날도 0으로 자리를 지킨다 — 빈 날을 빼면 막대가
    /// 요일과 어긋나 붙는다.
    let days: [Day]
    /// 분 내림차순 → 라벨 오름차순 → 라벨 없는 묶음 순.
    let labels: [LabelTotal]
    /// 하루 평균의 분모(1...7).
    let elapsedDays: Int
    /// 앞 세션이 끝난 뒤 창 안에서 시작한 세션 수 — PRD 지표 2 의 근사치.
    let chainedSessions: Int

    /// 앞 세션이 끝나고 이만큼 안에 다음 세션이 **시작**됐으면 이어진 것으로 센다.
    /// 긴 휴식 15분 + 알림을 보고 실제로 시작하기까지의 여유 15분.
    ///
    /// 상수를 `FocusChainRules` 에서 파생시키는 이유: 긴 휴식을 늘리면 이 창도 함께 늘어야 하는데,
    /// 따로 적어 두면 휴식만 20분으로 바꾼 날 멀쩡히 이어 간 세션이 전부 끊긴 것으로 기록된다.
    // ponytail: 저장된 값에서 뽑은 근사치다 — 원장에 시작 시각이 없어 `endedAt - minutes` 로
    // 되돌려 계산한다. 실제 "휴식 종료 → 시작" 을 재려면 체인 이벤트를 따로 적어야 하고,
    // 그건 이 수치가 실제로 쓰인다는 걸 본 뒤에 연다.
    static let chainWindowMinutes = FocusChainRules.longRestMinutes * 2

    /// 라벨 목록에 몇 줄까지 세우나. 한 주에 라벨이 스무 종이면 그건 목록이 아니라 잡음이다.
    // ponytail: 상위 5개 — 전부 보는 자리는 아직 없다. 필요해지면 그때 연다.
    static let labelRowLimit = 5

    /// 몇 주 전까지 되돌아볼 수 있나. **손으로 적지 않고 보존 기간에서 파생한다.**
    ///
    /// `-1` 인 이유: 90일 상한은 `now` 기준이고 이번 주는 최대 7일 전에 시작하므로,
    /// `90 / 7 = 12` 주 전은 앞부분이 이미 잘려 나간 **반쪽 주**가 될 수 있다. 반쪽 주를 온전한
    /// 주와 나란히 놓고 "늘었다/줄었다" 를 읽는 순간 그 비교가 곧 오답이다.
    static let maxWeeksBack = FocusSessionLog.retentionDays / 7 - 1

    /// 한 주의 세션 수 · 분. **요일 칸에서 파생한다** — 원장을 따로 한 번 더 세면 "이번 주 12세션"
    /// 인데 막대 합은 11인 상태가 생기고, 그 차이는 화면만 봐서는 알 수 없다.
    var sessions: Int { days.reduce(0) { $0 + $1.sessions } }
    var minutes: Int { days.reduce(0) { $0 + $1.minutes } }

    /// 라벨이 붙은 세션 수 — PRD 성공 지표 3 이 읽는 값이다.
    var labeledSessions: Int {
        labels.reduce(0) { $0 + ($1.label == nil ? 0 : $1.sessions) }
    }

    /// 하루 평균 세션 수. **분모가 지나간 날 수다.**
    ///
    /// 항상 7로 나누면 월요일 오전의 이번 주가 어느 지난주보다도 무조건 나빠 보인다. 이 화면이
    /// 존재하는 이유가 주 대 주 비교(PRD 주 지표 "하루 완료 세션 수가 기준선 대비 증가")라,
    /// 그 나눗셈 하나가 지표를 통째로 거꾸로 읽게 만든다.
    var dailyAverageSessions: Double { Double(sessions) / Double(elapsedDays) }

    /// 막대 높이의 분모. 0이면 그릴 막대가 없다는 뜻이라 화면이 바닥으로 눕힌다.
    var busiestDayMinutes: Int { days.map(\.minutes).max() ?? 0 }

    /// 원장에서 한 주를 뽑는다.
    ///
    /// - Parameters:
    ///   - weekStart: 그 주의 월요일. 계산은 `CompanionStore.weekStart` 한 곳이다 — 주 경계를
    ///     여기서 다시 구하면 주간 미션(`CompanionStore.weekKey`)과 다른 달력이 하나 더 생긴다.
    ///   - now: 지나간 날 수를 세는 기준. 스토어의 `clock()` 이 들어오므로 테스트가 주 경계를 넘길 수 있다.
    static func build(log: FocusSessionLog, weekStart: Date, now: Date) -> FocusWeekRecap {
        let calendar = CompanionStore.isoCalendar
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }

        // 요일 집계는 **원장의 `sessions(on:)` 을 그대로 부른다.** 하루의 정의(`dayKey`)를 여기서
        // 다시 짜면 오늘 목록과 이 화면이 다른 날을 세게 되고, 그건 마일스톤 3 이 이미 막은 부류다.
        let weekSessions = dates.map { log.sessions(on: CompanionStore.dayKey($0)) }
        let days = zip(dates, weekSessions).map { date, sessions in
            Day(date: date, dayKey: CompanionStore.dayKey(date), sessions: sessions.count,
                minutes: sessions.reduce(0) { $0 + $1.minutes })
        }

        return FocusWeekRecap(weekStart: weekStart,
                              days: days,
                              labels: labelTotals(weekSessions.flatMap { $0 }),
                              elapsedDays: elapsedDays(weekStart: weekStart, now: now,
                                                       calendar: calendar),
                              chainedSessions: chainedCount(weekSessions.flatMap { $0 }))
    }

    /// 지나간 날 수(1...7). 이번 주면 월요일부터 오늘까지, 이미 지나간 주면 7이다.
    ///
    /// 하한이 1인 이유는 나눗셈이다 — 월요일 00:00 에 열면 지나간 날이 0일이라 평균이 무한대가 된다.
    private static func elapsedDays(weekStart: Date, now: Date, calendar: Calendar) -> Int {
        guard now >= weekStart else { return 1 }   // 아직 오지 않은 주(시계 되돌림)
        let passed = calendar.dateComponents([.day], from: weekStart, to: now).day ?? 0
        return min(max(passed + 1, 1), 7)
    }

    /// 라벨별 합. 정렬은 **분 내림차순 → 라벨 오름차순 → 라벨 없는 묶음**이다.
    ///
    /// 동률 깨기를 넣는 이유: 사전 순회 순서는 보장되지 않아서, 그것만으로 정렬하면 같은 주가
    /// 팝오버를 열 때마다 다른 순서로 보인다. 회고에서 그건 곧 "이 화면은 매번 다른 말을 한다" 다.
    private static func labelTotals(_ sessions: [FocusSession]) -> [LabelTotal] {
        var totals: [String?: (sessions: Int, minutes: Int)] = [:]
        for session in sessions {
            let entry = totals[session.label] ?? (0, 0)
            totals[session.label] = (entry.sessions + 1, entry.minutes + session.minutes)
        }
        return totals
            .map { LabelTotal(label: $0.key, sessions: $0.value.sessions, minutes: $0.value.minutes) }
            .sorted { lhs, rhs in
                // 라벨 없는 묶음은 크기와 상관없이 맨 뒤다 — 목록의 머리가 "라벨 없음" 이면
                // 라벨을 쓰라고 권하는 화면이 라벨을 안 쓴 쪽을 앞세우게 된다.
                if (lhs.label == nil) != (rhs.label == nil) { return rhs.label == nil }
                if lhs.minutes != rhs.minutes { return lhs.minutes > rhs.minutes }
                return (lhs.label ?? "") < (rhs.label ?? "")
            }
    }

    /// 앞 세션이 끝난 뒤 창 안에서 시작한 세션의 수.
    ///
    /// **날짜로 쪼개지 않고 주 전체를 시간순으로 훑는다** — 23:50 에 끝내고 00:10 에 시작한 것은
    /// 사람에게 한 흐름인데, 날짜별로 세면 그 한 번이 매번 끊긴 것으로 기록된다.
    ///
    /// 시작 시각은 원장에 없어 `endedAt - minutes` 로 되돌린다. 간격이 **음수면 세지 않는다**:
    /// 이 파일은 무결성 서명 밖이라 손으로 겹치게 적을 수 있고, 그러면 "전부 이어졌다" 는
    /// 100% 짜리 가짜 지표가 만들어진다.
    private static func chainedCount(_ sessions: [FocusSession]) -> Int {
        let ordered = sessions.sorted { $0.endedAt < $1.endedAt }
        let window = Double(chainWindowMinutes) * 60
        return zip(ordered, ordered.dropFirst()).count { previous, next in
            let startedAt = next.endedAt.addingTimeInterval(-Double(next.minutes) * 60)
            let gap = startedAt.timeIntervalSince(previous.endedAt)
            return gap >= 0 && gap <= window
        }
    }
}
