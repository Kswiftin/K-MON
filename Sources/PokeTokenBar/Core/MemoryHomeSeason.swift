import Foundation

/// 미니룸 대문에 걸리는 계절. 달력 월에서 **파생**하므로 저장 필드가 하나도 없다.
///
/// 이름 앞의 `MemoryHome` 은 취향이 아니다 — `SeasonBoard`·`SeasonChallenge`·`seasonKey` 가 월간
/// 순환 챌린지로 "시즌" 어휘를 이미 점유했다. 접두를 빼면 코드에서 "이번 시즌" 이 챌린지 세트를
/// 가리키는지 계절을 가리키는지 구분되지 않는다.
///
/// **북반구 고정.** 남반구는 반대지만 그걸 맞추려면 위치 권한이 필요하고, 이 기능은 대문에 계절
/// 한 줄을 얹는 게 전부라 권한을 새로 요구할 값이 없다. 해제 조건: 앱이 다른 이유로 이미 위치를
/// 알게 되면 그때 뒤집는다.
enum MemoryHomeSeason: Sendable, Hashable, CaseIterable {
    case spring, summer, autumn, winter

    /// 겨울만 범위가 아니라 기본값이다 — 12·1·2 는 연말을 가로질러 `12...2` 로 못 적는다.
    /// `default` 로 받으면 그 불연속을 조건 두 개로 쪼개지 않아도 된다.
    nonisolated static func current(_ date: Date = Date()) -> MemoryHomeSeason {
        switch Calendar.current.component(.month, from: date) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }
}
