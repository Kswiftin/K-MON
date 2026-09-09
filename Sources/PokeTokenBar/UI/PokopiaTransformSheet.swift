import SwiftUI

/// 도감에서 변신 대상을 고르는 시트.
///
/// 후보 집합은 `CompanionStore.townTransformCandidates` **한 곳**에서 온다. 여기서 따로 만들면
/// 목록에 뜨는데 못 고르는 종이 생기고, 갈라진 걸 알아챌 방법은 손으로 맞대 보는 것뿐이다
/// (`ShopCatalog` 가 목록과 구매를 한 값으로 묶는 이유와 같다).
struct PokopiaTransformSheet: View {
    let store: CompanionStore
    @Environment(\.dismiss) private var dismiss

    /// 도감 한 칸 = 종 하나. 같은 종을 여러 번 키워도 후보는 한 줄이다.
    ///
    /// `types` 를 들고 있는 이유: **변신이 무엇을 주는지 고르기 전에 보여야** 조작이 된다.
    /// 고른 뒤에 알게 되면 변신이 다시 복권이 되고, 그게 티켓 경제의 문제였다.
    private struct Candidate: Identifiable {
        let id: Int
        let name: String
        let isShiny: Bool
        /// `DexEntry.types` 는 옵셔널이다 — 아직 백필 안 된 종은 nil 이고 스와치를 안 그린다.
        let brush: TownTerrain?
    }

    /// **후보를 만드는 식은 이 프로퍼티 하나다.** 그리는 쪽과 고르는 쪽이 각자 계산하면
    /// 목록에 있는데 `setDittoForm` 이 거절하는 종이 생긴다.
    private var candidates: [Candidate] {
        var seen = Set<Int>()
        return store.dexEntries.compactMap { entry -> Candidate? in
            guard store.townTransformCandidates.contains(entry.finalID),
                  seen.insert(entry.finalID).inserted else { return nil }
            let name = entry.names?[entry.finalID].flatMap { PokemonNaming.name($0) }
            return Candidate(id: entry.finalID, name: name ?? "#\(entry.finalID)",
                             isShiny: entry.isShiny,
                             brush: PokopiaTown.brush(dittoFormTypes: entry.types))
        }
        // 종 번호 순. 도감 순회 순서를 그대로 쓰면 졸업 시각에 따라 목록이 흔들린다.
        .sorted { $0.id < $1.id }
    }

    private var currentForm: Int? { store.memoryAlbum.town.dittoForm }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if candidates.isEmpty {
                ContentUnavailableView(
                    "아직 변신할 수 있는 포켓몬이 없어요",
                    systemImage: "theatermasks",
                    description: Text("도감에 기록된 포켓몬으로만 변신할 수 있어요. 먼저 함께 집중해 보세요."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid
            }
            footer
        }
        .padding(16)
        .frame(width: 460, height: 480)
        .background(PokedoroTheme.pageBackground)
        .fontDesign(.rounded)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("무엇으로 변신할까요?").font(.headline)
            Text("변신하면 그 포켓몬의 타입에 맞는 지형을 밀 수 있어요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(candidates) { candidate in
                    Button {
                        // 거절 가능성이 있는 호출이다 — 반환값을 버리지 않고 성공할 때만 닫는다.
                        if store.memoryAlbum.setDittoForm(candidate.id,
                                                          registeredSpecies: store.townTransformCandidates) {
                            dismiss()
                        }
                    } label: {
                        candidateCell(candidate)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(candidate.name)
                    .accessibilityValue([currentForm == candidate.id ? "변신 중" : "",
                                         candidate.brush.map { "\($0.name) 지형을 밀 수 있어요" } ?? ""]
                                        .filter { !$0.isEmpty }.joined(separator: ", "))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func candidateCell(_ candidate: Candidate) -> some View {
        let isCurrent = currentForm == candidate.id
        return VStack(spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
                PokopiaResidentView(speciesID: candidate.id, isShiny: candidate.isShiny, side: 40)
                // 이 종으로 변신하면 밀 수 있는 지형. 없으면(타입 미상) 빈 사각형을 그리지 않는다.
                if let brush = candidate.brush {
                    PokopiaTerrainSwatch(terrain: brush, side: 13)
                        // `PokedoroTheme.pageBackground` 는 `some View` 라 `ShapeStyle` 이 아니다.
                        // 스와치를 스프라이트에서 떼어 보이게 하는 테두리라 배경색 계열로 그린다.
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                        }
                }
            }
            Text(candidate.name)
                .font(.caption2.weight(.medium))
                // 축소 하한은 0.9 다 — 10pt 에 0.7 을 걸면 긴 이름에서 7pt 가 되어
                // 최소 크기 가드를 통과한 채 하한이 무너진다.
                .lineLimit(1).minimumScaleFactor(0.9)
        }
        .frame(width: 78, height: 64)
        .background(isCurrent ? PokedoroTheme.blue.opacity(0.18) : Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(PokedoroTheme.blue, lineWidth: 1.5)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("변신 해제") {
                // 해제는 도감과 무관하게 항상 된다 — 빈 집합을 넘겨도 통과하는 계약이다.
                _ = store.memoryAlbum.setDittoForm(nil, registeredSpecies: [])
                dismiss()
            }
            .disabled(currentForm == nil)
            Spacer()
            Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }
}
