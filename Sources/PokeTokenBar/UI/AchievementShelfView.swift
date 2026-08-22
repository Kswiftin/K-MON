import SwiftUI

/// 컬렉션 탭의 업적 선반. 트랙 4행 — 이름 · 단계 표시 · 다음 문턱까지의 진행도.
///
/// **행마다 `ProgressView` 를 두지 않는다.** 미션 카드가 그렇게 예산을 두 배 넘겼고(211pt) 도감
/// 목표 줄이 되풀이했다. 4단계뿐이라 점 네 개(`●●○○`)가 게이지보다 정확하다. 세로 예산은
/// `PopoverLayoutTests.testAchievementShelfFitsItsBudget` 이 지킨다.
///
/// 체육관 배지 화면(`GymLeagueView`)과 층이 다르다 — 구분 근거는 `AchievementLadder` 주석에 있다.
struct AchievementShelfView: View {
    let store: CompanionStore

    private var l: L { store.l }

    var body: some View {
        // 한 번만 읽는다 — `achievementRows` 는 접근마다 배열을 다시 만든다.
        let rows = store.achievementRows
        let clearedCount = rows.filter { $0.tier >= $0.achievement.tiers.count }.count
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("🏅 \(l.achievementsTitle)").font(.caption.weight(.semibold))
                Spacer()
                // `✓` 가 "완주한 트랙 수" 를 대신 말한다 — 번역 없이도 행의 진행도와 구분된다.
                Text("✓ \(clearedCount)/\(rows.count)")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.achievement.id) { row in
                let next = store.nextAchievementTier(row.achievement.track)
                HStack(spacing: 6) {
                    Text(l.achievementName(row.achievement.track))
                        .font(.caption2).lineLimit(1)
                        .foregroundStyle(next == nil ? .secondary : .primary)
                    Text(tierDots(reached: row.tier, of: row.achievement.tiers.count))
                        .font(.system(size: 9)).foregroundStyle(.orange)
                        .accessibilityLabel(l.achievementTierLabel(row.tier, row.achievement.tiers.count))
                    Spacer(minLength: 4)
                    if let next {
                        Text("\(row.count)/\(next.goal)")
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        // 마지막 문턱까지 넘겼다 — 남은 목표가 없으니 완료 표식만 둔다.
                        Text("✓").font(.caption2.weight(.bold)).foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    /// 채운 점 + 빈 점. 스크린리더는 위 `accessibilityLabel` 로 읽는다 — 점 문자를 그대로 읽히면
    /// "검은 원 검은 원 흰 원" 이 된다.
    private func tierDots(reached: Int, of total: Int) -> String {
        String(repeating: "●", count: max(0, min(reached, total)))
            + String(repeating: "○", count: max(0, total - reached))
    }
}
