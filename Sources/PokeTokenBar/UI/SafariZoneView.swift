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
    /// 방금 끝난 조우의 결과 배너를 보여주는 중인가 — `SafariEncounterView` 대신 여기서 갖는다.
    /// 조우가 끝나면 `SafariVisit.currentEncounter` 가 곧바로 `nil` 이 되므로, 이 값을
    /// `SafariEncounterView` 의 로컬 상태로 두면 그 판정 하나로 이 뷰 자체가 `SafariFieldView`
    /// 로 바뀌어 버려 배너가 한 프레임도 못 뜨고 사라진다(도망쳤는데 계속 몬스터 창이 떠 있는
    /// 것처럼 보이던 결함의 근본원인). 부모가 들고 있어야 "배너를 보여주는 동안은 걷기 화면으로
    /// 넘어가지 않는다"를 조건에 반영할 수 있다.
    @State private var pendingOutcome: SafariOutcome?
    @State private var encounterNames: [Int: String] = [:]

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let visit = store.safariVisit {
                if visit.hasEnded {
                    walkSummary(visit)
                } else if visit.currentEncounter != nil || pendingOutcome != nil {
                    SafariEncounterView(store: store, pendingOutcome: $pendingOutcome)
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
        .task { await loadEncounterNames() }
    }

    private func zoneCard(_ zone: SafariZone.ZoneID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                store.beginSafariZoneVisit(zone: zone)
            } label: {
                HStack {
                    Text(l.safariZoneName(zone)).fontWeight(.semibold)
                    Spacer()
                    Text(l.safariZoneEnter).font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .disabled(store.safariZoneVisitsRemainingToday <= 0)

            Text(l.safariZoneEncounterPool)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 7) {
                ForEach(SafariZone.encounterPool(for: zone), id: \.speciesID) { entry in
                    encounterCell(entry)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func encounterCell(_ entry: SafariZone.EncounterPoolEntry) -> some View {
        let discovered = store.isSpeciesAlreadyOwned(entry.speciesID)
        return VStack(spacing: 1) {
            SpriteView(speciesID: entry.speciesID, size: 34, animated: false,
                       fallbackLabel: "#\(entry.speciesID)")
                .grayscale(discovered ? 0 : 1)
                .opacity(discovered ? 1 : 0.38)
            Text(encounterNames[entry.speciesID] ?? "#\(entry.speciesID)")
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(l.safariZoneEncounterChance(entry.chancePercent))
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(discovered
            ? "\(encounterNames[entry.speciesID] ?? "#\(entry.speciesID)"), \(l.safariZoneEncounterChance(entry.chancePercent))"
            : "\(l.safariZoneUndiscoveredPokemon), \(l.safariZoneEncounterChance(entry.chancePercent))")
    }

    private func loadEncounterNames() async {
        let species = Set(SafariZone.ZoneID.allCases.flatMap { SafariZone.speciesPool(for: $0) }).sorted()
        for speciesID in species where encounterNames[speciesID] == nil {
            guard !Task.isCancelled else { return }
            encounterNames[speciesID] = await store.safariEncounterName(speciesID)
        }
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
