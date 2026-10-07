import SwiftUI

/// 도감에서 변신 대상을 고르는 시트.
///
/// 후보 집합은 `CompanionStore.townTransformCandidates` **한 곳**에서 온다. 여기서 따로 만들면
/// 목록에 뜨는데 못 고르는 종이 생기고, 갈라진 걸 알아챌 방법은 손으로 맞대 보는 것뿐이다
/// (`ShopCatalog` 가 목록과 구매를 한 값으로 묶는 이유와 같다).
struct PokopiaTransformSheet: View {
    let store: CompanionStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var terrain: TownTerrain?

    /// **후보를 만드는 식은 이 프로퍼티 하나다.** 그리는 쪽과 고르는 쪽이 각자 계산하면
    /// 목록에 있는데 `setDittoForm` 이 거절하는 종이 생긴다.
    private var candidates: [PokopiaTransformCandidate] {
        PokopiaTownPresentation.candidates(entries: store.dexEntries,
                                          registeredSpecies: store.townTransformCandidates)
    }

    private var filteredCandidates: [PokopiaTransformCandidate] {
        PokopiaTownPresentation.filtered(candidates, query: query, terrain: terrain)
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
                filters
                HStack {
                    Text("\(filteredCandidates.count)/\(candidates.count)종")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    if !query.isEmpty || terrain != nil {
                        Button("필터 초기화") { query = ""; terrain = nil }
                            .font(.caption)
                    }
                }
                if filteredCandidates.isEmpty {
                    ContentUnavailableView("조건에 맞는 포켓몬이 없어요", systemImage: "magnifyingglass",
                                           description: Text("다른 이름을 검색하거나 지형 필터를 바꿔 보세요."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    grid
                }
            }
            footer
        }
        .padding(16)
        .frame(width: 500, height: 560)
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

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("이름 또는 도감 번호 검색", text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("변신할 포켓몬 검색")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색 지우기")
                }
            }
            .padding(9)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            Picker("만들 지형", selection: $terrain) {
                Text("모든 지형").tag(TownTerrain?.none)
                ForEach(TownTerrain.allCases, id: \.self) { tile in
                    Text(tile.name).tag(Optional(tile))
                }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(filteredCandidates) { candidate in
                    Button {
                        // 거절 가능성이 있는 호출이다 — 반환값을 버리지 않고 성공할 때만 닫는다.
                        if currentForm == candidate.id || store.memoryAlbum.setDittoForm(candidate.id,
                                                          registeredSpecies: store.townTransformCandidates) {
                            dismiss()
                        }
                    } label: {
                        candidateCell(candidate)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(candidate.name)
                    .accessibilityValue([currentForm == candidate.id ? "변신 중" : "",
                                         candidate.brush.map { "\($0.name) 지형을 밀 수 있어요" } ?? "타입 미확인"]
                                        .filter { !$0.isEmpty }.joined(separator: ", "))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func candidateCell(_ candidate: PokopiaTransformCandidate) -> some View {
        let isCurrent = currentForm == candidate.id
        return VStack(spacing: 4) {
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
                .font(.caption.weight(.medium))
                .lineLimit(2)
            Text(candidate.brush.map { "\($0.name) 만들기" } ?? "타입 미확인")
                .font(.caption2).foregroundStyle(.secondary)
            if isCurrent {
                Label("변신 중", systemImage: "checkmark.circle.fill")
                    .font(.caption2).foregroundStyle(PokedoroTheme.blue)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
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
