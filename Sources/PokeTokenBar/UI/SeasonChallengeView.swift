import SwiftUI

/// 컬렉션 탭 업적 세그먼트의 시즌 카드. 챌린지 3행 — 이름 · 진행도 · 완료 표식.
///
/// 홈 탭이 아니라 여기 있다. 홈 스크롤 뷰포트는 미션 카드와 파트너 카드(176pt)로 이미 차 있어
/// 세 번째 카드를 얹으면 앱의 주인공이 뷰포트 밖으로 밀린다. 반면 이 세그먼트는 520pt 프레임에
/// 업적 선반 하나뿐이라 자리가 남는다. 세로 예산은 `PopoverLayoutTests` 의 두 검증이 지킨다 —
/// 카드 단독, 그리고 **선반과의 합**.
///
/// **행마다 `ProgressView` 를 두지 않는다.** 미션 카드가 그렇게 만들어 예산을 두 배 넘겼다.
/// 헤더의 남은 일수가 "언제까지"를 말하므로 행은 숫자만으로 충분하다.
struct SeasonChallengeView: View {
    let store: CompanionStore

    private var l: L { store.l }

    private var rows: [(challenge: SeasonChallenge, progress: Int)] { store.seasonRows }
    private var doneCount: Int { rows.filter { $0.progress >= $0.challenge.target }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("🗓️ \(l.seasonTitle)").font(.caption.weight(.semibold))
                // 남은 일수가 이 카드의 존재 이유다 — 만료가 안 보이면 그냥 목표가 큰 미션이다.
                Text(l.seasonDaysLeft(store.seasonDaysRemaining))
                    .font(.caption2).monospacedDigit().foregroundStyle(.orange)
                Spacer()
                Text("✓ \(doneCount)/\(rows.count)")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.challenge.id) { row in
                let done = row.progress >= row.challenge.target
                HStack(spacing: 6) {
                    Text(l.goalName(row.challenge.event, row.challenge.target))
                        .font(.caption2).lineLimit(1)
                        .foregroundStyle(done ? .secondary : .primary)
                    Spacer(minLength: 4)
                    if done {
                        Text("✓ \(GameNumberFormatter.compact(row.challenge.reward)) ⭐")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    } else {
                        Text("\(row.progress)/\(row.challenge.target)")
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
