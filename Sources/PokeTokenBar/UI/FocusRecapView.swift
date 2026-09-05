import SwiftUI

/// 주간 회고 오버레이(PRD 마일스톤 4) — 한 주의 집중을 요일·라벨별로 되돌아본다.
///
/// **탭이 아니라 오버레이인 이유**: 새 탭은 `PopoverTab` 높이 표와 360pt 세그먼트 피커까지 끌고
/// 오는데 얻는 건 화면 하나다(`MissionBoardView` 가 같은 이유로 탭을 안 만들었다). 집중 카드
/// 안에 접어 넣는 것도 아니다 — 카드가 길어지면 780pt 고정 높이 안에서 파트너 카드가 밀린다.
///
/// **스크롤을 두지 않는다.** 내용이 유계다: 막대 일곱 + 라벨 최대 다섯 + 요약 줄 셋. 팝오버
/// 스크롤 *밖*이라 중첩은 아니지만, 필요 없는 스크롤은 만들지 않는다.
///
/// 값은 전부 `store.focusRecap(weeksAgo:)` 가 원장에서 파생한다 — 이 화면은 아무것도 저장하지 않고,
/// 세는 일도 하지 않는다(세는 자리가 둘이면 요약과 막대가 다른 수를 말한다).
struct FocusRecapView: View {
    let store: CompanionStore
    let onClose: () -> Void

    /// 몇 주 전을 보고 있나. **0 이 이번 주**다. 화면 상태라 저장하지 않는다 — 오버레이를
    /// 닫았다 열면 이번 주로 돌아오는 것이 맞다.
    @State private var weeksAgo = 0

    private var l: L { store.l }
    /// 앱 언어를 **명시**한다. `Date.formatted()` 기본값은 `Locale.autoupdatingCurrent` 라
    /// 시스템 로캘을 읽고, 그러면 앱을 일본어로 써도 요일만 시스템 언어로 나온다.
    private var locale: Locale { store.language.displayLocale }

    /// 막대의 최대 높이. 카드 하나 분량이라 요일 이름·분까지 얹어도 오버레이 예산 안이다.
    private static let barHeight: CGFloat = 48
    /// 0분인 날에도 남기는 최소 높이. 막대가 아예 사라지면 요일 칸이 비어 보인다.
    private static let emptyBarHeight: CGFloat = 2

    var body: some View {
        let recap = store.focusRecap(weeksAgo: weeksAgo)
        VStack(alignment: .leading, spacing: 12) {
            header
            weekSwitcher(recap)
            if recap.sessions == 0 {
                // 빈 상자를 그리면 화면이 고장 난 것처럼 보인다 — 쉬어 간 주도 정상이라고 말한다.
                Text(l.t("이 주엔 마친 세션이 없어요.", "No sessions finished this week.",
                         "この週に完了したセッションはありません。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                summary(recap)
                dayBars(recap)
                labelList(recap)
                chainLine(recap)
            }
            Spacer(minLength: 0)
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
    }

    private var header: some View {
        HStack {
            Label(l.t("주간 회고", "Weekly recap", "週間ふりかえり"), systemImage: "chart.bar.xaxis")
                .font(.headline)
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
        }
    }

    /// 주 이동. **이번 주보다 앞으로는 못 간다** — 아직 오지 않은 주는 빈 막대 일곱 개일 뿐이다.
    /// 뒤로는 `maxWeeksBack` 까지고, 그 상한은 보존 기간에서 파생한다.
    private func weekSwitcher(_ recap: FocusWeekRecap) -> some View {
        HStack {
            Button { weeksAgo = min(weeksAgo + 1, FocusWeekRecap.maxWeeksBack) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(weeksAgo >= FocusWeekRecap.maxWeeksBack)
            Spacer()
            Text(weekTitle(recap)).font(.caption.weight(.semibold)).monospacedDigit()
            Spacer()
            Button { weeksAgo = max(weeksAgo - 1, 0) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(weeksAgo == 0)
        }
    }

    /// 요약 한 줄. **하루 평균이 여기 있는 이유**는 PRD 주 지표가 그것이기 때문이다 —
    /// 총합만 있으면 사흘 지난 이번 주와 다 지난 지난 주를 견줄 수 없다.
    private func summary(_ recap: FocusWeekRecap) -> some View {
        HStack(spacing: 6) {
            Text(l.t("\(recap.sessions)세션 · \(recap.minutes)분",
                     "\(recap.sessions) sessions · \(recap.minutes) min",
                     "\(recap.sessions)セッション・\(recap.minutes)分"))
                .font(.caption.weight(.semibold)).monospacedDigit()
            Spacer()
            Text(l.t("하루 평균 \(averageText(recap))세션",
                     "\(averageText(recap)) sessions/day",
                     "1日平均 \(averageText(recap))セッション"))
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    /// 요일 막대. 높이는 그 주 최다 분에 대한 비율이다 — 절대 분으로 그리면 25분짜리 주가
    /// 전부 바닥에 눌려 요일 차이가 안 보인다.
    private func dayBars(_ recap: FocusWeekRecap) -> some View {
        let peak = recap.busiestDayMinutes
        let todayKey = CompanionStore.dayKey(Date())
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(recap.days, id: \.dayKey) { day in
                let isToday = day.dayKey == todayKey
                VStack(spacing: 3) {
                    Text(day.minutes > 0 ? "\(day.minutes)" : " ")
                        .font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                    // 0분인 날도 실선 한 줄은 남긴다 — 칸이 통째로 비면 요일 이름만 떠 있어
                    // 막대가 아니라 오류처럼 보인다.
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isToday ? PokedoroTheme.red : PokedoroTheme.blue.opacity(0.55))
                        .frame(height: barLength(minutes: day.minutes, peak: peak))
                    Text(day.date.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated)))
                        .font(.system(size: 9, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.barHeight + 26, alignment: .bottom)
    }

    /// 무엇에 썼는가. 라벨 없는 묶음도 한 줄로 남긴다 — 빼면 막대의 합과 목록의 합이 갈린다.
    private func labelList(_ recap: FocusWeekRecap) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(recap.labels.prefix(FocusWeekRecap.labelRowLimit), id: \.label) { total in
                HStack(spacing: 6) {
                    Text(total.label ?? l.t("라벨 없음", "No label", "ラベルなし"))
                        .font(.caption)
                        .foregroundStyle(total.label == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(l.t("\(total.sessions)회 · \(total.minutes)분",
                             "\(total.sessions) · \(total.minutes) min",
                             "\(total.sessions)回・\(total.minutes)分"))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            // PRD 성공 지표 3 이 이 한 줄이다 — 라벨을 아무도 안 쓰면 기록의 회고 가치가 없다는 신호.
            Text(l.t("라벨 붙은 세션 \(recap.labeledSessions)/\(recap.sessions)",
                     "Labeled \(recap.labeledSessions)/\(recap.sessions) sessions",
                     "ラベル付き \(recap.labeledSessions)/\(recap.sessions) セッション"))
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    /// 이어서 시작한 세션. **판정 기준을 함께 적는다** — 근사치라는 것이 화면에 없으면
    /// 이 수치를 실제 계측으로 읽게 된다.
    private func chainLine(_ recap: FocusWeekRecap) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l.t("이어서 시작한 세션 \(recap.chainedSessions)/\(recap.sessions)",
                     "Chained \(recap.chainedSessions)/\(recap.sessions) sessions",
                     "続けて始めたセッション \(recap.chainedSessions)/\(recap.sessions)"))
                .font(.caption.weight(.semibold)).monospacedDigit()
            Text(l.t("앞 세션이 끝나고 \(FocusWeekRecap.chainWindowMinutes)분 안에 시작한 경우",
                     "Started within \(FocusWeekRecap.chainWindowMinutes) min of the previous session",
                     "前のセッション終了から\(FocusWeekRecap.chainWindowMinutes)分以内に開始した場合"))
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func barLength(minutes: Int, peak: Int) -> CGFloat {
        guard peak > 0, minutes > 0 else { return Self.emptyBarHeight }
        return max(Self.emptyBarHeight, Self.barHeight * CGFloat(minutes) / CGFloat(peak))
    }

    /// 평균은 소수 한 자리까지. 정수로 반올림하면 0.4세션과 1.4세션이 같은 "0" · "1" 이 되어
    /// 주 대 주 차이가 통째로 사라진다.
    private func averageText(_ recap: FocusWeekRecap) -> String {
        recap.dailyAverageSessions.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    private func weekTitle(_ recap: FocusWeekRecap) -> String {
        switch weeksAgo {
        case 0: return l.t("이번 주", "This week", "今週")
        case 1: return l.t("지난 주", "Last week", "先週")
        default:
            let end = recap.days.last?.date ?? recap.weekStart
            let style = Date.FormatStyle(locale: locale).month(.abbreviated).day()
            return "\(recap.weekStart.formatted(style)) – \(end.formatted(style))"
        }
    }
}
