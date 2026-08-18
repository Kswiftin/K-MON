import SwiftUI

/// 홈 탭 상단의 미션 카드. 새 탭을 만들지 않는다 — 탭을 늘리면 `PopoverTab` 높이 표와
/// 360pt 폭 세그먼트 피커까지 따라오는데, 얻는 건 네 줄짜리 목록 하나다.
///
/// 진행도는 `store.missionRows` 가 읽는 시점의 날짜·주 키로 판정하므로, 팝오버를 다시 여는 것만으로
/// 자정 이후의 빈 일간 목록이 보인다(갱신 타이머 없음).
struct MissionBoardView: View {
    let store: CompanionStore

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🎯 \(l.missionsTitle)").font(.caption.weight(.semibold))
            ForEach(store.missionRows, id: \.mission.id) { row in
                let done = row.progress >= row.mission.target
                HStack(spacing: 6) {
                    Text(row.mission.period == .daily ? l.missionDaily : l.missionWeekly)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(row.mission.period == .daily ? .blue : .purple)
                    Text(l.missionName(row.mission)).font(.caption2).lineLimit(1)
                    Spacer()
                    if done {
                        Text("✓ \(GameNumberFormatter.compact(row.mission.reward)) ⭐")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    } else {
                        Text("\(row.progress)/\(row.mission.target)")
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: Double(row.progress), total: Double(row.mission.target))
                    .tint(done ? .green : .orange)
            }
        }
        .padding(9)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
