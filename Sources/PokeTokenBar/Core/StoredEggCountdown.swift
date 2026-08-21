import Foundation

/// 보관 알 자동 부화까지 남은 시간의 **표시 상태**. 뷰 밖 순수 로직으로 둔다 —
/// `Text(readyAt, style: .timer)` 를 그대로 쓰면 예정 시각을 지난 뒤 SwiftUI 가 *경과* 시간을
/// 세어 올려, 0 에 닿은 카운트다운이 다시 증가한다(#86). 남은 시간은 0 에서 멈추고,
/// 그 뒤로는 숫자가 아니라 "곧 부화" 상태를 내보낸다.
///
/// 예정 시각이 지나도 실제 부화가 곧바로 일어나지 않는 건 정상이다 — 부화 트리거는 60초 방치
/// 틱이고(`CompanionStore.refreshLifecycle`), 종 추첨은 네트워크가 필요해 오프라인이거나 등급
/// 보증에 미달하면 다음 틱으로 미뤄진다. 그 대기 구간을 숫자로 보여줄 방법이 없으므로 상태로 만든다.
enum StoredEggCountdown: Equatable {
    /// 아직 남았다 — `clock` 은 이미 0 으로 바닥이 잡힌 표시 문자열.
    case counting(clock: String)
    /// 예정 시각 도달(또는 경과) — 부화 대기 중. 숫자를 보여주지 않는다.
    case due

    /// 남은 시간 판정. 1초 미만이면 `.due` — 초 단위 표시가 "00:00" 으로 굳는 구간을 숫자로
    /// 남기지 않기 위해 올림(`.rounded(.up)`) 뒤 0 이하를 모두 `.due` 로 접는다.
    static func resolve(readyAt: Date, now: Date) -> StoredEggCountdown {
        let seconds = Int(readyAt.timeIntervalSince(now).rounded(.up))
        guard seconds > 0 else { return .due }
        // 표시 형식은 모험 남은시간과 같은 한 곳을 쓴다 — 바닥(max(0,…))이 두 번 구현되지 않게.
        return .counting(clock: MenuBarStatus.remainingClockText(readyAt, at: now))
    }
}
