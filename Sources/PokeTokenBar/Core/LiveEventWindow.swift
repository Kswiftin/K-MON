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
}
