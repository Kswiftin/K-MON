import Foundation

/// 2026-09-11 08:00~20:00(기기 로컬 시간) 한정 이벤트 창 — 이로치 확률 4배(`PokemonOdds`),
/// 레이드 보스 1시간마다 로테이션, 레이드 포획 추첨 무제한(`CompanionStore.catchRaidBoss`)이
/// 이 창 안에서만 켜진다.
///
/// **스스로 꺼진다.** 날짜가 지나면 `isActive` 가 항상 `false` 를 반환하므로, 이 창을 껐다 켰다
/// 하려고 되돌리는 릴리스를 따로 낼 필요가 없다 — 릴리스 하나만 9/11 전에 나가 있으면 된다.
enum LiveEventWindow {
    static func isActive(_ date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard components.year == 2026, components.month == 9, components.day == 11,
              let hour = components.hour else { return false }
        return (8..<20).contains(hour)
    }

    /// 창이 끝나는 시각(`date` 가 속한 날의 20:00) — 화면이 "몇 시간 남았다" 배너를 그릴 때 쓴다.
    /// `isActive(date)` 가 참일 때만 의미 있는 값이다(호출부가 그 가드를 먼저 본다).
    static func endDate(_ date: Date = Date(), calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 20
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }
}
