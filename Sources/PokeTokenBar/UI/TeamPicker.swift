import SwiftUI

/// 출전 팀 고르기 — 누르면 넣고 빼고, 배지 숫자가 출전 순서다.
///
/// 배틀 탭과 체육관 오버레이가 같은 것을 쓴다. 두 곳에서 고르는 팀이 다르면 "내 출전 팀" 이
/// 둘이 되어, 어느 쪽에서 고른 게 나가는지 알 수 없다.
///
/// 스크롤을 쓰지 않는다. 배틀 탭은 팝오버 본체 ScrollView 안이라 안쪽에 또 두면 그 칸이
/// 잘린다(`BattleFieldTests.testTheBattleFieldSourceHasNoScrollView` 가 소스에서 막는다).
/// 대신 도감·소유 포켓몬과 같은 페이지식이다.
struct TeamPicker: View {
    let store: CompanionStore
    @Environment(BattleCenter.self) private var center
    /// 이 화면에서 고를 수 있는 최대 인원. 체육관은 관장 팀에 맞춰 3, 모의전은 화면에서 고른 크기다.
    let limit: Int
    @State private var page = 0

    /// 한 페이지에 그리는 칩 수. 팝오버 콘텐츠 폭(332) 안에 칩 6개(44)와 간격이 들어간다.
    private static let pageSize = 6

    private var l: L { store.l }

    var body: some View {
        let owned = store.ownedMons
        if owned.count > 1 {
            let pageCount = max(1, (owned.count + Self.pageSize - 1) / Self.pageSize)
            // 개체가 줄면(졸업·방출) 보던 페이지가 사라진다 — 범위 밖이면 마지막 페이지로 당긴다.
            let current = min(page, pageCount - 1)
            let slice = Array(owned.dropFirst(current * Self.pageSize).prefix(Self.pageSize))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(store.language == .ko ? "출전 순서" : "Battle order")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if pageCount > 1 {
                        Button { page = max(0, current - 1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.plain).disabled(current == 0)
                            .accessibilityLabel(l.dexPagePrev)
                        Text("\(current + 1) / \(pageCount)")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            .accessibilityLabel(l.dexPageLabel(current + 1, pageCount))
                        Button { page = min(pageCount - 1, current + 1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.plain).disabled(current == pageCount - 1)
                            .accessibilityLabel(l.dexPageNext)
                    }
                    Text("\(center.pickedTeam.count) / \(limit)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(center.pickedTeam.isEmpty ? .tertiary : .secondary)
                }
                HStack(spacing: 5) {
                    ForEach(slice, id: \.id) { mon in
                        TeamPickChip(mon: mon,
                                     pickedIndex: center.pickedTeam.firstIndex(of: mon.id),
                                     onTap: { center.toggleTeamPick(mon.id, limit: limit) })
                    }
                    // 마지막 페이지가 덜 차도 칩 폭이 늘어나지 않게 빈 자리를 채운다.
                    if slice.count < Self.pageSize {
                        ForEach(slice.count..<Self.pageSize, id: \.self) { _ in
                            Color.clear.frame(width: 44)
                        }
                    }
                }
                // 아무것도 안 고르면 소유 순서 앞에서 채운다 — 고르지 않고도 바로 시작할 수 있어야 한다.
                if center.pickedTeam.isEmpty {
                    Text(store.language == .ko ? "고르지 않으면 목록 앞에서 자동으로 채워요"
                                               : "Left empty, the first of your list are sent in")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// 출전 팀 칩 하나. 고른 것에는 출전 순서를 배지로 얹는다 — 숫자가 없으면 무엇이 선봉인지 알 수 없다.
struct TeamPickChip: View {
    let mon: MonState
    let pickedIndex: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                ZStack(alignment: .topTrailing) {
                    SpriteView(speciesID: mon.currentID, size: 30, shiny: mon.isShiny)
                    if let pickedIndex {
                        Text("\(pickedIndex + 1)")
                            .font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 13, height: 13)
                            .background(Circle().fill(Color.accentColor))
                    }
                }
                Text("Lv.\(mon.level)").font(.system(size: 7)).foregroundStyle(.secondary)
            }
            .frame(width: 44)
            .padding(3)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(pickedIndex == nil ? Color.clear : Color.accentColor.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .stroke(pickedIndex == nil ? Color.secondary.opacity(0.25) : Color.accentColor, lineWidth: 1))
    }
}
