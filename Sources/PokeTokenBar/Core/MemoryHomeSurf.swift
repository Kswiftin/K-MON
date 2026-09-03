import Foundation

/// 발자국 한 줄. `id` 는 광고 원문(닉네임+설치 접미)이라 같은 닉네임을 쓰는 두 기기가 한 줄로
/// 뭉개지지 않는다. `label` 은 접미를 뗀 표시용이다 — 목록 버튼과 같은 규칙을 쓴다.
struct MemoryHomeFootprint: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let at: Date
}

/// 기획서 §14 파도타기 — 다음 홈 선택과 발자국 파생의 **유일한** 출처다.
///
/// 저장 필드가 하나도 없다. 이미 저장 중인 방문 도장(`memoryHomeAccess.visitedHomeStamps`)과
/// 지금 보이는 홈 목록만 읽는다(`MemoryHomeRoomLife`·`MemoryHomeSeason` 이 같은 원칙을 쓴다).
/// 그 도장은 `recordMemoryHomeVisitStamp` 가 릴리스 내내 써 왔지만 **어느 화면도 읽지 않아서**,
/// 다녀온 집이 세이브에만 쌓이고 화면에는 없었다 — 파도타기가 없던 실제 이유다.
///
/// 난수를 쓰지 않는다. 같은 목록·같은 커서면 같은 답이다(`MemoryHomeCompanionTrace` 와 같은
/// 이유 — 난수면 누를 때마다 달라 "돌아본다" 는 감각이 생기지 않고, 방문 도장을 잠식한다).
enum MemoryHomeSurf {
    /// 화면이 보여 주는 발자국 수. 도장은 200개까지 쌓이므로(`recordMemoryHomeVisitStamp`)
    /// 전부 늘어놓으면 VISIT 탭이 발자국으로만 채워진다.
    static let footprintLimit = 10

    /// 그날 다녀온 집. 도장은 통산 기록이라 날짜를 보지 않으면 어제 다녀온 집이 영구히 제외되고,
    /// 이웃이 한 채인 사용자는 다음 날부터 파도타기를 쓸 수 없다.
    /// 판정은 **dayKey 문자열 비교**다 — `Date` 산술이면 타임존 변경·DST 경계에서 어긋난다
    /// (TODAY 카운터가 이미 같은 이유로 dayKey 를 쓴다).
    static func visitedIDs(in stamps: [String: Date], on dayKey: String) -> Set<String> {
        Set(stamps.filter { CompanionStore.dayKey($0.value) == dayKey }.keys)
    }

    /// 다음에 갈 집. 커서 **다음**부터 한 바퀴 돌며 오늘 안 간 집을 먼저 고르고, 전부 다녀왔으면
    /// 그 한 바퀴의 첫 집(= 커서 다음)을 고른다.
    ///
    /// 두 번째 규칙이 없으면 하루에 이웃을 다 돈 사용자에게 버튼이 조용히 죽는다. 커서가 목록에
    /// 없는 경우(mDNS 만료·상대 종료 — 흔하다)도 멈추지 않고 목록 처음부터 돈다.
    static func target(in homes: [MemoryHomePeer], visited: Set<String>, after current: String?) -> MemoryHomePeer? {
        guard !homes.isEmpty else { return nil }
        let start = current.flatMap { id in homes.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
        let rotated = (0..<homes.count).map { homes[(start + $0) % homes.count] }
        return rotated.first { !visited.contains($0.id) } ?? rotated[0]
    }

    /// 다녀온 집을 최신순으로. 상한은 **정렬 뒤에** 자른다 — 먼저 자르면 딕셔너리 순회 순서가
    /// 남길 항목을 정하므로 가장 최근 발자국이 사라질 수 있다.
    ///
    /// 키는 남이 지은 문자열이다. 라벨을 만들 수 없는 값은 화면에 올리지 않는다 — 목록이 쓰는
    /// 경계(`MemoryHomeVisitCenter.displayName(fromService:)`)를 그대로 재사용해, 버튼에는 못
    /// 뜨는 이름이 발자국으로는 뜨는 갈라짐을 없앤다.
    static func footprints(from stamps: [String: Date], limit: Int = footprintLimit) -> [MemoryHomeFootprint] {
        stamps
            .compactMap { id, at in
                MemoryHomeVisitCenter.displayName(fromService: id).map { MemoryHomeFootprint(id: id, label: $0, at: at) }
            }
            // 같은 시각 두 발자국의 순서가 딕셔너리 순회를 따라가면 목록이 열 때마다 자리를 바꾼다.
            .sorted { ($0.at, $1.id) > ($1.at, $0.id) }
            .prefix(max(0, limit))
            .map { $0 }
    }
}
