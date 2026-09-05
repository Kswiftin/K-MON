import Foundation

/// Memory Home 을 터미널 값으로 조립한다.
///
/// **조립이 한 함수인 이유**는 터미널(읽기)과 실행기(쓰기)가 **같은 번호**를 봐야 하기
/// 때문이다. 두 곳이 각자 세면 사용자가 화면에서 본 `2 책상` 과 앱이 치우는 가구가 갈라진다 —
/// 경매·방·교환에서 번호를 창구 하나로 모아 둔 것과 같은 규칙이고, 여기서는 창구가 없으니
/// 이 프로퍼티가 그 자리다.
///
/// `CompanionStore` 의 확장으로 둔 근거: 필요한 값이 앨범과 스토어 **양쪽**에 걸쳐 있다
/// (가구는 앨범, 개체 이름은 스토어, 계절·시각은 달력). 앨범에만 두면 스토어를 되받아야 한다.
@MainActor
extension CompanionStore {
    var homeTerminalState: HomeTerminalState {
        let album = memoryAlbum
        let access = album.memoryHomeAccess
        let l = L(language)
        var state = HomeTerminalState(nickname: album.memoryHomePublicNickname,
                                      styleName: album.roomStyle.name(l))
        state.message = access.profileMessage
        state.visitToday = access.visitToday
        state.visitTotal = access.visitTotal
        state.seasonName = MemoryHomeSeasonStyle.name(MemoryHomeSeason.current(), l)
        state.isLANOpen = access.visibility == .open
        state.decorLimit = PokemonMemoryAlbum.decorLimit

        state.styles = MemoryHomeRoomStyle.allCases.map { style in
            HomeScreen.Style(name: style.name(l),
                             isUnlocked: album.isRoomStyleUnlocked(style),
                             isActive: style == album.roomStyle,
                             requirement: MemoryHomeNames.requirement(style, l))
        }
        // **화면과 같은 순서로 센다** — 앱은 `layer` 로 쌓아 그리므로 그 순서를 그대로 쓴다.
        // 두 화면이 각자 정렬하면 같은 가구가 화면마다 다른 번호를 갖는다.
        state.placed = access.placedDecor.sorted { $0.layer < $1.layer }
            .enumerated()
            .map { index, decor in
                // 정규화 좌표 ↔ 격자는 **앨범이** 안다(`gridPoint`), 격자 ↔ 칸 번호는 화면이
                // 안다(`HomeScreen.cell`). 두 변환을 각자 한 곳에 두면 어느 쪽을 고쳐도
                // 나머지가 따라온다 — 여기서 좌표를 직접 계산하면 그 규칙이 두 벌이 된다.
                let point = PokemonMemoryAlbum.gridPoint(decor.position)
                return HomeScreen.Placed(number: index + 1, id: decor.id,
                                         cell: HomeScreen.cell(column: point.0, row: point.1),
                                         label: l.itemName(decor.item))
            }
        state.moodName = album.mood().map {
            MemoryHomeMoodStyle.emoji($0) + " " + MemoryHomeMoodStyle.name($0, l)
        }
        state.canUndo = album.canUndoRoomEdit
        state.canRedo = album.canRedoRoomEdit

        let roommates = ownedMons.filter { access.roommateIDs.contains($0.id) }
        state.roommates = roommates.map { chatProfile(for: $0).displayName }
        guard let mon = self.state.active else { return state }

        let companion = chatProfile(for: mon).displayName
        let log = album.pokeLog(for: mon.id)
        state.companionName = companion
        state.daysTogether = log.daysTogether
        state.memoryCount = log.memoryCount
        state.closenessHearts = log.closenessHearts
        state.pinned = album.pinned(for: mon.id)?.body
        state.recent = album.timeline(for: mon.id).prefix(3).map(\.body)
        state.cards = album.milestones(for: mon.id).map { MemoryHomeCardStyle.title($0, l) }
        state.roomLine = MemoryHomeRoomLife.line(
            speciesID: mon.currentID,
            decor: access.placedDecor.map(\.item),
            roommates: state.roommates,
            mood: album.mood(),
            season: MemoryHomeSeason.current(),
            timeOfDay: MemoryHomeTimeOfDay.current(),
            companion: companion, l)
        return state
    }
}
