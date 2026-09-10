import SwiftUI

/// 소유 포켓몬 탭의 머리줄 — 정렬 메뉴 · 필터 세 개 · 타입 메뉴 · 마릿수.
///
/// **자리가 빠듯한 줄이다.** 정렬·타입 메뉴는 `.fixedSize()` 라 줄지 않고 필터 버튼과 마릿수
/// 캡슐도 고정 폭이라, 폭이 모자라면 접힐 수 있는 요소 하나가 대신 접힌다. 예전엔 그 자리가
/// "소유 포켓몬" 제목이어서 제목만 세 줄로 접혔다(2026-09-08 리포트). 탭 이름이 이미 화면에
/// 있으므로 제목은 아이콘 하나로 줄였고, **여기에 길이가 변하는 글자를 새로 두지 않는다** —
/// 두려면 `PopoverLayoutTests` 의 머리줄 높이 가드를 먼저 통과시켜야 한다.
///
/// 로스터 본체에서 떼어낸 이유도 그 가드다. 뷰로 있어야 폭을 제안해 실제로 렌더해 볼 수 있다.
struct RosterHeader: View {
    let shownCount: Int
    let ownedCount: Int
    let owned: [MonState]
    /// 종별 타입 표. 타입 필터 메뉴의 후보를 여기서 만든다.
    let types: [Int: [PokemonType]]
    let didResolveTypes: Bool
    @Binding var typeFilter: PokemonType?
    @Binding var favoritesOnly: Bool
    @Binding var duplicatesOnly: Bool
    @Binding var unregisteredOnly: Bool
    /// 필터를 건드리면 보이는 마릿수가 줄어 지금 페이지가 사라질 수 있다 — 항상 첫 장으로 되돌린다.
    @Binding var page: Int
    @Environment(AppSettings.self) private var settings

    /// 세 필터 버튼(즐겨찾기·중복·미등록)이 공유하는 호버 설명 상태. `.help()` 는 팝오버 안에서
    /// 믿을 수 있는 표시 경로가 아니다(defect-log "`.help()` 는 NSPopover 안에서는 아무것도 안 뜬다")
    /// — `.onHover` 로 잡아 직접 그린다.
    private enum FilterHint: Equatable { case favorites, duplicates, unregistered }
    @State private var hoveredHint: FilterHint?
    /// 이탈 시 곧장 지우지 않고 살짝 늦춘다. 주기 갱신이 트래킹 영역을 순간 재설치하면 이탈
    /// 이벤트 직후 같은 자리에 재진입 이벤트가 따라오는데, 그 사이 취소되지 않으면 설명이
    /// 깜빡였다 사라지는 것으로 보인다 — 재진입이 오면 대기 중인 삭제를 취소한다.
    @State private var hintHideTask: Task<Void, Never>?

    private static let favoritesHint = "즐겨찾기로 표시한 포켓몬만 표시합니다."
    private static let duplicatesHint = "진화 전후를 포함해 같은 계보가 2마리 이상인 포켓몬만 표시합니다."
    private static let unregisteredHint = "영구 도감에 아직 기록되지 않은 현재 모습만 표시합니다."

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.headline).foregroundStyle(.secondary)
                .accessibilityLabel("소유 포켓몬")
            Spacer(minLength: 2)
            sortMenu
            favoriteFilterButton
            duplicateFilterButton(duplicateCount: duplicateFamilyCount(in: owned))
            unregisteredFilterButton
            typeMenu(owned: owned)
            // 필터가 걸렸을 땐 "보이는 수 / 전체 수" — 숫자 하나만 두면 필터가 켜진 걸 놓친다.
            Text(shownCount == ownedCount ? "\(ownedCount)" : "\(shownCount)/\(ownedCount)")
                .font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
    }

    /// 정렬 메뉴 — **버튼 자체가 방향을 말한다.**
    ///
    /// 예전 버튼 아이콘은 `arrow.up.arrow.down` / `arrow.down.arrow.up` 이었다. 둘은 화살표 두 개가
    /// 자리만 바뀐 그림이라 나란히 놓고 봐야 겨우 구별되고, 하나만 보면 지금이 오름인지 내림인지
    /// 알 수 없다. 메뉴를 열어야만 알 수 있는 상태는 없는 것과 같다 — 한쪽 화살표로 바꾼다.
    private var sortMenu: some View {
        @Bindable var settings = settings
        return Menu {
            ForEach(RosterSort.allCases, id: \.self) { option in
                Button {
                    if settings.rosterSort == option { settings.rosterSortAscending.toggle() }
                    else { settings.rosterSort = option; settings.rosterSortAscending = true }
                    page = 0
                } label: {
                    Label(sortLabel(option), systemImage: settings.rosterSort == option
                          ? (settings.rosterSortAscending ? "arrow.up" : "arrow.down") : "")
                }
            }
        } label: {
            Label(sortLabel(settings.rosterSort),
                  systemImage: settings.rosterSortAscending ? "arrow.up" : "arrow.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel(settings.rosterSortAscending
                            ? "정렬 — 오름차순"
                            : "정렬 — 내림차순")
    }

    /// 켜짐/꺼짐이 아이콘 자체로 읽혀야 한다 — 채워진 노란 별이 카드의 즐겨찾기 표시와 같은 그림이라,
    /// 눌러 보지 않아도 지금 무엇으로 좁혀 보는 중인지 알 수 있다.
    private var favoriteFilterButton: some View {
        Button {
            favoritesOnly.toggle(); page = 0
        } label: {
            Image(systemName: favoritesOnly ? "star.fill" : "star")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(favoritesOnly ? .yellow : .secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("즐겨찾기만 보기")
        .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
        .help(Self.favoritesHint)
        .onHover { setHoveredHint(.favorites, isInside: $0) }
        .overlay(alignment: .bottom) {
            hintBubble(.favorites, text: Self.favoritesHint).offset(y: 22)
        }
    }

    private func duplicateFamilyCount(in owned: [MonState]) -> Int {
        RosterOrdering.duplicateEvolutionFamilyIDs(in: owned).count
    }

    /// 켜면 중복 계보의 개체를 **전부** 남긴다. 한 계보당 하나로 접는 기능이 아니다 — 사용자는
    /// 교환·방생할 중복 개체끼리 비교하려고 이 필터를 쓴다.
    private func duplicateFilterButton(duplicateCount: Int) -> some View {
        Button {
            duplicatesOnly.toggle(); page = 0
        } label: {
            Image(systemName: duplicatesOnly ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(duplicatesOnly ? Color.accentColor : .secondary)
        }
        .buttonStyle(.borderless)
        // 필터를 켠 채 마지막 중복을 방생해도 다시 전체 보기로 돌아갈 수 있어야 한다.
        .disabled(duplicateCount == 0 && !duplicatesOnly)
        .accessibilityLabel("중복 진화 계보만 보기")
        .accessibilityAddTraits(duplicatesOnly ? .isSelected : [])
        .help(Self.duplicatesHint)
        .onHover { setHoveredHint(.duplicates, isInside: $0) }
        .overlay(alignment: .bottom) {
            hintBubble(.duplicates, text: Self.duplicatesHint).offset(y: 22)
        }
    }

    private var unregisteredFilterButton: some View {
        Button {
            unregisteredOnly.toggle(); page = 0
        } label: {
            Image(systemName: unregisteredOnly ? "book.closed.fill" : "book.closed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(unregisteredOnly ? Color.accentColor : .secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("도감 미등록만 보기")
        .accessibilityAddTraits(unregisteredOnly ? .isSelected : [])
        .help(Self.unregisteredHint)
        .onHover { setHoveredHint(.unregistered, isInside: $0) }
        .overlay(alignment: .bottom) {
            hintBubble(.unregistered, text: Self.unregisteredHint).offset(y: 22)
        }
    }

    private func setHoveredHint(_ hint: FilterHint, isInside: Bool) {
        hintHideTask?.cancel()
        if isInside {
            hoveredHint = hint
        } else {
            hintHideTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                hoveredHint = nil
            }
        }
    }

    private func hintBubble(_ hint: FilterHint, text: String) -> some View {
        Group {
            if hoveredHint == hint {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    .fixedSize()
                    .transition(.opacity)
            }
        }
    }

    private func typeMenu(owned: [MonState]) -> some View {
        let available = RosterOrdering.availableTypes(owned, types: types)
        return Menu {
            Button("전체 타입") { typeFilter = nil; page = 0 }
            ForEach(available, id: \.self) { type in
                Button(type.name) { typeFilter = type; page = 0 }
            }
        } label: {
            Label(typeFilter?.name ?? "타입",
                  systemImage: "line.3.horizontal.decrease.circle")
                .font(.system(size: 10, weight: .semibold))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(!didResolveTypes || available.isEmpty)
        .accessibilityLabel("타입 필터")
    }

    private func sortLabel(_ option: RosterSort) -> String {
        switch option {
        case .caught:    return "부화순"
        case .dexNumber: return "도감번호순"
        case .name:      return "이름순"
        case .level:     return "레벨순"
        }
    }
}
