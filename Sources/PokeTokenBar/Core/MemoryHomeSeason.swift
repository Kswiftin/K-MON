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
    ///
    /// 달력은 `dayKey`·시즌 만료와 **같은 접근자**(`SeasonBoard.gregorian`)를 쓴다. `Calendar.current`
    /// 로 월을 뽑으면 비그레고리력 달력을 쓰는 사용자에게만 계절이 결산·일기와 갈라진다 —
    /// 소수만 겪고 리포트도 안 오는 부류다(`defect-log.md` 의 "한 파일 안에 달력이 둘이면").
    nonisolated static func current(_ date: Date = Date()) -> MemoryHomeSeason {
        switch SeasonBoard.gregorian.component(.month, from: date) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }
}

/// 미니룸의 하루. 계절과 같은 집안이다 — 시계에서 **파생**하므로 저장 필드가 0개이고,
/// 기존 사용자의 방도 업데이트 즉시 아침·밤을 갖는다.
///
/// 세 칸인 이유는 문구 예산이다. 네 칸(아침·낮·저녁·밤)으로 쪼개면 저녁이 밤과 같은 말을 하게
/// 되어 한 가지가 사실상 죽는다 — 방을 설명하는 힘이 실제로 갈리는 지점만 남겼다.
enum MemoryHomeTimeOfDay: Sendable, Hashable, CaseIterable {
    case morning, day, night

    /// 밤은 자정을 가로지르므로 `21...4` 로 못 적는다 — `MemoryHomeSeason` 의 겨울이 `default`
    /// 로 12·1·2 를 함께 받는 것과 같은 부류다. 여기서는 밤을 먼저 걸러 그 불연속을 없앤다.
    nonisolated static func current(_ date: Date = Date(), calendar: Calendar = .current) -> MemoryHomeTimeOfDay {
        let hour = calendar.component(.hour, from: date)
        if hour >= 21 || hour < 5 { return .night }
        return hour < 11 ? .morning : .day
    }
}
