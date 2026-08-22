import SwiftUI

/// 홈 탭 상단의 미션 카드. 새 탭을 만들지 않는다 — 탭을 늘리면 `PopoverTab` 높이 표와
/// 360pt 폭 세그먼트 피커까지 따라오는데, 얻는 건 네 줄짜리 목록 하나다.
///
/// **미션마다 `ProgressView` 를 한 줄씩 두지 않는다.** 그렇게 만든 첫 버전이 211pt 였는데,
/// 홈 탭 스크롤 뷰포트가 약 250pt 이고 파트너 카드가 176pt 라 파트너가 통째로 뷰포트 밖으로 밀렸다 —
/// 미션 체크리스트가 앱의 주인공을 가린 셈이다. 게이지 4개(약 56pt)와 그 사이 간격을 걷어내고
/// 진행도를 `25/60` 숫자로만 보이면 79pt 로 들어가 파트너와 한 화면에 공존한다.
/// 세로 예산은 `PopoverLayoutTests.testMissionCardFitsTheHomeViewportBudget` 이 지킨다.
///
/// 진행도는 `store.missionRows` 가 읽는 시점의 날짜·주 키로 판정하므로, 팝오버를 다시 여는 것만으로
/// 자정 이후의 빈 일간 목록이 보인다(갱신 타이머 없음).
struct MissionBoardView: View {
    let store: CompanionStore

    private var l: L { store.l }

    var body: some View {
        // 한 번만 읽는다 — `missionRows` 는 접근마다 날짜·주 키를 다시 굽고 배열을 다시 만든다.
        let rows = store.missionRows
        let doneCount = rows.filter { $0.progress >= $0.mission.target }.count
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("🎯 \(l.missionsTitle)").font(.caption.weight(.semibold))
                Spacer()
                // `✓` 가 "완료 개수"를 대신 말한다 — 번역 없이도 행의 진행도(25/60)와 구분된다.
                Text("✓ \(doneCount)/\(rows.count)")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.mission.id) { row in
                let done = row.progress >= row.mission.target
                HStack(spacing: 6) {
                    // 주기 배지가 "오늘/이번 주"를 대신 말해 주므로 미션 이름에서는 뺐다(가로도 아낀다).
                    Text(row.mission.period == .daily ? l.missionDaily : l.weekly)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(row.mission.period == .daily ? .blue : .purple)
                    Text(l.missionName(row.mission))
                        .font(.caption2).lineLimit(1)
                        .foregroundStyle(done ? .secondary : .primary)
                    Spacer(minLength: 4)
                    if done {
                        Text("✓ \(GameNumberFormatter.compact(row.mission.reward)) ⭐")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                            .lineLimit(1)
                    } else {
                        Text("\(row.progress)/\(row.mission.target)")
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
