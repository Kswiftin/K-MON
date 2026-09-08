import SwiftUI

/// 사파리존 조우 화면 — 미끼/진흙/볼/도망 네 액션과 결과 배너.
///
/// **결과가 나는 즉시 `SafariVisit.currentEncounter` 가 `nil` 이 된다.** 배너를 보여주는
/// 동안에도 조우 정보(스프라이트·단계)를 화면에 붙잡아야 하므로, `displayedEncounter` 가
/// 그 마지막 스냅샷을 들고 있다가 사용자가 "계속"을 누르면 놓는다.
struct SafariEncounterView: View {
    @Bindable var store: CompanionStore
    @State private var resultBanner: SafariOutcome?
    @State private var displayedEncounter: SafariEncounter?
    @State private var isCommitting = false

    private var l: L { store.l }
    private var encounter: SafariEncounter? { store.safariVisit?.currentEncounter ?? displayedEncounter }

    var body: some View {
        VStack(spacing: 8) {
            if let encounter {
                header(encounter)
                stageGauges(encounter)
                Spacer(minLength: 0)
                if let resultBanner {
                    banner(resultBanner)
                } else {
                    actionButtons
                }
                log
            }
        }
        .onChange(of: store.safariVisit?.currentEncounter) { old, new in
            if let old, new == nil { displayedEncounter = old }
            if new != nil { displayedEncounter = nil; resultBanner = nil }
        }
    }

    private func header(_ encounter: SafariEncounter) -> some View {
        HStack {
            Spacer()
            SpriteView(speciesID: encounter.speciesID, size: 64, shiny: false)
            Spacer()
        }
    }

    private func stageGauges(_ encounter: SafariEncounter) -> some View {
        HStack {
            Label(l.safariCatchStageLabel(encounter.catchStage), systemImage: "arrow.up.circle")
            Spacer()
            Label(l.safariFleeStageLabel(encounter.fleeStage), systemImage: "arrow.down.circle")
        }
        .font(.caption2)
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            actionButton(l.safariBaitAction, action: .bait)
            actionButton(l.safariMudAction, action: .mud)
            actionButton(l.safariBallAction, action: .ball,
                        disabled: (store.safariVisit?.balls ?? 0) <= 0)
            actionButton(l.safariRunAction, action: .run)
        }
    }

    private func actionButton(_ title: String, action: SafariAction, disabled: Bool = false) -> some View {
        Button(title) { perform(action) }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(disabled || isCommitting)
    }

    private func perform(_ action: SafariAction) {
        guard let outcome = mutate({ $0.act(action) }), outcome != .continuing else { return }
        resultBanner = outcome
        guard outcome == .caught, let speciesID = displayedEncounter?.speciesID ?? encounter?.speciesID
        else { return }
        isCommitting = true
        Task {
            _ = await store.catchInSafariZone(speciesID: speciesID)
            isCommitting = false
        }
    }

    private func banner(_ outcome: SafariOutcome) -> some View {
        VStack(spacing: 6) {
            Text(bannerText(outcome)).font(.caption.bold())
            Button(l.safariContinue) {
                resultBanner = nil
                displayedEncounter = nil
            }
            .buttonStyle(.bordered).controlSize(.small).disabled(isCommitting)
        }
    }

    private func bannerText(_ outcome: SafariOutcome) -> String {
        switch outcome {
        case .caught: l.safariOutcomeCaught
        case .fled: l.safariOutcomeFled
        case .ranAway: l.safariOutcomeRanAway
        case .timedOut: l.safariOutcomeTimedOut
        case .continuing: ""
        }
    }

    /// 로그는 고정 높이 안에서만 스크롤한다(`BattleField.swift` 의 82pt 채팅창과 같은 규칙) —
    /// `NestedScrollGuardTests` 가 높이 안 묶인 중첩 스크롤을 막는다.
    private var log: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array((store.safariVisit?.visitLog ?? []).suffix(6).enumerated()),
                       id: \.offset) { _, entry in
                    Text(logLine(entry)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 60)
    }

    private func logLine(_ entry: SafariLogEntry) -> String {
        guard let action = entry.action, let outcome = entry.outcome else {
            return l.safariLogEncounterStarted
        }
        return l.safariLogLine(action: action, outcome: outcome)
    }

    @discardableResult
    private func mutate<T>(_ body: (inout SafariVisit) -> T) -> T? {
        guard var visit = store.safariVisit else { return nil }
        let result = body(&visit)
        store.safariVisit = visit
        return result
    }
}
