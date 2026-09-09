import SwiftUI

/// 사파리존(#80 후속) — 4세대 그레이트 마쉬식 스테이지 포획. 존을 고르면 방향키(WASD 겸용)로
/// 벌판을 걸어 다니고, 걸음마다 낮은 확률로 조우가 뜬다.
///
/// 화면이 세 국면을 갈아 끼운다: **존 선택**(방문이 없을 때), **걷기/조우**(방문이 진행 중일
/// 때), **방문 요약**(걸음 소진 또는 포획 상한 도달로 방문이 끝났을 때). 존 선택만 스크롤
/// 가능하다 — `Canvas` 걷기 화면은 고정 픽셀 치수라 스크롤과 상극이다(`NestedScrollGuardTests`
/// 의 `ownsItsOwnScroll` 예외 목록에 이 파일을 올린 이유).
struct SafariZoneView: View {
    let store: CompanionStore
    let onClose: () -> Void

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let visit = store.safariVisit {
                if visit.hasEnded {
                    walkSummary(visit)
                } else if visit.currentEncounter != nil {
                    SafariEncounterView(store: store)
                } else {
                    SafariFieldView(store: store)
                }
            } else {
                ScrollView {
                    zoneSelection
                        .padding(.horizontal, 2)
                }
            }
        }
        .padding(10)
        .frame(height: PopoverMetrics.currentHeight(for: .challenge))
    }

    private var header: some View {
        PokedoroOverlayHeader(title: l.safariZoneTitle, systemImage: "leaf.fill", tint: .green,
                              closeLabel: l.close, onClose: onClose)
    }

    private var zoneSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l.safariZoneVisitsRemaining(store.safariZoneVisitsRemainingToday,
                                             cap: SafariZone.dailyVisitCap))
                .font(.caption2).foregroundStyle(.secondary)
            if store.safariZoneVisitsRemainingToday <= 0 {
                Text(l.safariZoneNoVisitsLeftToday).font(.caption2).foregroundStyle(.orange)
            }
            ForEach(SafariZone.ZoneID.allCases, id: \.self) { zone in
                zoneCard(zone)
            }
        }
    }

    private func zoneCard(_ zone: SafariZone.ZoneID) -> some View {
        Button {
            store.beginSafariZoneVisit(zone: zone)
        } label: {
            HStack {
                Text(l.safariZoneName(zone))
                Spacer()
                Text(l.safariZoneEnter).font(.caption2).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption2)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(store.safariZoneVisitsRemainingToday <= 0)
    }

    private func walkSummary(_ visit: SafariVisit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l.safariZoneWalkEndedTitle).font(.headline)
            Text(l.safariZoneWalkEndedSummary(caughtCount: visit.caughtSpeciesIDs.count))
                .font(.caption).foregroundStyle(.secondary)
            Button(l.safariZoneConfirm) { store.safariVisit = nil }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
    }
}
