import SwiftUI

enum MemoryHomeRoomTheme {
    static func tint(for theme: PokemonMemoryRoomTheme) -> Color {
        switch theme {
        case .blue: PokedoroTheme.blue
        case .mint: PokedoroTheme.mint
        case .yellow: PokedoroTheme.yellow
        case .red: PokedoroTheme.red
        }
    }
}

struct MemoryHomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MemoryHomeVisitCenter.self) private var visits
    let store: CompanionStore
    @State private var note = ""
    @State private var validationMessage: String?
    @State private var showingVisits = false

    private var l: L { store.l }

    var body: some View {
        guard let mon = store.state.active else { return AnyView(EmptyView()) }
        let album = store.memoryAlbum
        let entries = album.entries(for: mon.id)
        let timeline = album.timeline(for: mon.id)
        let hidden = entries.filter(\.isHidden).sorted { $0.createdAt > $1.createdAt }
        let milestones = album.milestones(for: mon.id)
        let roomTheme = album.theme(for: mon.id)
        let roomTint = MemoryHomeRoomTheme.tint(for: roomTheme)

        return AnyView(VStack(alignment: .leading, spacing: 10) {
            roomHeader(mon: mon, entries: entries, milestones: milestones, theme: roomTheme, tint: roomTint)

            HStack {
                Button { showingVisits = true } label: {
                    Label(l.t("주변 홈 방문", "Visit nearby homes", "近くのホームを訪問"), systemImage: "house.and.flag")
                }
                .accessibilityLabel(l.t("주변 Memory Home 방문", "Visit nearby Memory Homes", "近くのMemory Homeを訪問"))
                Spacer()
                Menu {
                    Button(store.memoryAlbum.memoryHomeAccess.visibility == .open
                           ? l.t("홈 차단", "Block home", "ホームをブロック")
                           : l.t("홈 공개", "Open home", "ホームを公開")) {
                        store.memoryAlbum.setMemoryHomeVisibility(store.memoryAlbum.memoryHomeAccess.visibility == .open ? .blocked : .open)
                        visits.refreshAccess()
                    }
                    if let pinned = album.pinned(for: mon.id) {
                        Button(album.sharedPinnedMemory(for: mon.id) == nil
                               ? l.t("고정 기억 공유", "Share pinned memory", "固定した思い出を共有")
                               : l.t("기억 공유 해제", "Stop sharing memory", "思い出の共有をやめる")) {
                            if album.sharedPinnedMemory(for: mon.id) == nil { album.setSharedPinnedMemory(pinned, activeCompanionID: mon.id) }
                            else { album.clearSharedPinnedMemory() }
                        }
                    }
                    if !album.memoryHomeAccess.recentRequesters.isEmpty {
                        Divider()
                        ForEach(album.memoryHomeAccess.recentRequesters) { requester in
                            Button(requester.displayName + " · " + (album.memoryHomeAccess.blockedPeerIDs.contains(requester.peerID)
                                   ? l.t("차단 해제", "Unblock", "ブロック解除")
                                   : l.t("차단", "Block", "ブロック"))) {
                                album.setMemoryHomeBlocked(requester.peerID, blocked: !album.memoryHomeAccess.blockedPeerIDs.contains(requester.peerID))
                            }
                        }
                    }
                } label: { Image(systemName: "lock.shield") }
                .accessibilityLabel(l.t("홈 공유 설정", "Home sharing settings", "ホーム共有設定"))
            }

            if let pinned = album.pinned(for: mon.id) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(l.t("고정한 기억", "Pinned memory", "固定した思い出"), systemImage: "pin.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(PokedoroTheme.red)
                    Text(pinned.body).font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                .pokedoroCard(tint: PokedoroTheme.red, emphasized: true)
            }

            if !milestones.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(l.t("함께 연 카드", "Unlocked cards", "解放したカード")).font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(milestones) { milestone in
                                milestoneCard(milestone, tint: roomTint)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $note).frame(minHeight: 54, maxHeight: 74)
                    .accessibilityLabel(l.t("새 개인 기억", "New private memory", "新しい非公開の思い出"))
                HStack {
                    Text(l.t("\(note.count)/280", "\(note.count)/280", "\(note.count)/280"))
                        .font(.caption).foregroundStyle(note.count > 280 ? PokedoroTheme.red : .secondary)
                    Spacer()
                    Button(l.t("기억 남기기", "Save memory", "思い出を残す")) {
                        if album.addManual(companionID: mon.id, body: note) {
                            settings.recordManualMemoryCreated()
                            note = ""; validationMessage = nil
                        } else {
                            validationMessage = l.t("1~280자로 적어 주세요.", "Enter 1–280 characters.", "1〜280文字で入力してください。")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let validationMessage { Text(validationMessage).font(.caption).foregroundStyle(PokedoroTheme.red) }
            }
            .padding(9).pokedoroCard(tint: PokedoroTheme.mint)

            Text(l.t("최근 기억", "Recent memories", "最近の思い出")).font(.headline)
            if timeline.isEmpty {
                Text(l.t("첫 집중을 마치면 여기에 함께한 기록이 쌓여요.",
                         "Finish a focus session to start this shared record.",
                         "集中を終えると、ここにふたりの記録が積み重なります。"))
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(timeline) { memory in
                memoryRow(memory, album: album)
            }
            if !hidden.isEmpty {
                DisclosureGroup(l.t("숨긴 기억", "Hidden memories", "非表示の思い出")) {
                    ForEach(hidden) { memory in
                        memoryRow(memory, album: album)
                    }
                }
            }
        }
        .padding(10).pokedoroCard(tint: roomTint)
        .onAppear { settings.recordMemoryHomeExposure() }
        .sheet(isPresented: $showingVisits, onDismiss: { visits.stop() }) {
            MemoryHomeVisitSheet(visits: visits, language: l)
                .onAppear { visits.start() }
        })
    }

    private func roomHeader(mon: MonState, entries: [PokemonMemory], milestones: [PokemonMemoryMilestone], theme: PokemonMemoryRoomTheme, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.18))
                Rectangle().fill(tint.opacity(0.24)).frame(height: 13).frame(maxHeight: .infinity, alignment: .bottom)
                SpriteView(speciesID: mon.currentID, size: 54, shiny: mon.isShiny)
            }
            .frame(width: 76, height: 68)
            VStack(alignment: .leading, spacing: 2) {
                Text(l.t("우리의 미니룸", "Our mini room", "ふたりのミニルーム")).font(.headline)
                Text(store.chatProfile(for: mon).displayName).font(.subheadline.weight(.semibold))
                Text(firstMeetingText(mon.id)).font(.caption).foregroundStyle(.secondary)
                Text(l.t("기억 \(entries.count)개 · 카드 \(milestones.count)개",
                         "\(entries.count) memories · \(milestones.count) cards",
                         "思い出 \(entries.count) 件・カード \(milestones.count) 枚"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                ForEach(PokemonMemoryRoomTheme.allCases, id: \.self) { candidate in
                    Button {
                        store.memoryAlbum.setTheme(candidate, for: mon.id)
                    } label: {
                        Label(themeName(candidate), systemImage: candidate == theme ? "checkmark" : "circle.fill")
                    }
                }
            } label: {
                Image(systemName: "paintpalette.fill")
                    .foregroundStyle(tint)
                    .frame(minWidth: 28, minHeight: 28)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(l.t("미니룸 테마", "Mini room theme", "ミニルームのテーマ"))
            .accessibilityValue(themeName(theme))
            .accessibilityHint(l.t("동행별 테마를 선택합니다.", "Choose a theme for this companion.", "この相棒のテーマを選びます。"))
        }
        .padding(8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l.t("\(store.chatProfile(for: mon).displayName)의 미니룸. \(firstMeetingText(mon.id)). 기억 \(entries.count)개, 카드 \(milestones.count)개",
                               "\(store.chatProfile(for: mon).displayName)'s mini room. \(firstMeetingText(mon.id)). \(entries.count) memories, \(milestones.count) cards",
                               "\(store.chatProfile(for: mon).displayName)のミニルーム。\(firstMeetingText(mon.id))。思い出 \(entries.count) 件、カード \(milestones.count) 枚"))
    }

    private func firstMeetingText(_ companionID: UUID) -> String {
        guard let first = store.memoryAlbum.firstMetAt(for: companionID) else {
            return l.t("첫 만남을 기다리고 있어요", "Waiting for our first meeting", "最初の出会いを待っています")
        }
        return l.t("첫 만남 ", "First meeting ", "最初の出会い ") + formattedDate(first)
    }

    private func milestoneCard(_ milestone: PokemonMemoryMilestone, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: milestoneIcon(milestone))
                .font(.title3.weight(.semibold)).foregroundStyle(tint)
            Text(milestoneTitle(milestone)).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(formattedDate(milestone.occurredAt)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 132, height: 98, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(milestoneTitle(milestone) + ", " + formattedDate(milestone.occurredAt))
    }

    private func milestoneIcon(_ milestone: PokemonMemoryMilestone) -> String {
        switch milestone.kind {
        case .firstMeeting: "person.2.fill"
        case .focusSessions: "timer"
        case .evolution: "arrow.triangle.2.circlepath"
        case .anniversary: "sparkles"
        }
    }

    private func milestoneTitle(_ milestone: PokemonMemoryMilestone) -> String {
        switch milestone.kind {
        case .firstMeeting: l.t("첫 만남", "First meeting", "最初の出会い")
        case .focusSessions(let count): l.t("집중 모험 \(count)회", "\(count) focus adventures", "集中冒険 \(count) 回")
        case .evolution: l.t("진화의 순간", "Evolution moment", "進化の瞬間")
        case .anniversary: l.t("첫 만남 1주년", "First-meeting anniversary", "最初の出会い 1周年")
        }
    }

    private func themeName(_ theme: PokemonMemoryRoomTheme) -> String {
        switch theme {
        case .blue: l.t("파랑", "Blue", "ブルー")
        case .mint: l.t("민트", "Mint", "ミント")
        case .yellow: l.t("노랑", "Yellow", "イエロー")
        case .red: l.t("빨강", "Red", "レッド")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.locale(store.language.displayLocale).year().month(.abbreviated).day())
    }

    private func memoryRow(_ memory: PokemonMemory, album: PokemonMemoryAlbum) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(memory.body).font(.subheadline)
                Text(sourceName(memory.source) + " · " + memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button(l.t("고정", "Pin", "固定")) { album.pin(memory) }
                Button(memory.isHidden ? l.t("다시 표시", "Show", "再表示") : l.t("숨기기", "Hide", "非表示")) {
                    _ = album.setHidden(memory, isHidden: !memory.isHidden)
                }
                if memory.source == .manual {
                    Button(l.t("삭제", "Delete", "削除"), role: .destructive) { _ = album.delete(memory) }
                }
            } label: {
                Image(systemName: album.pinned(for: memory.companionID)?.id == memory.id ? "pin.fill" : "ellipsis")
            }
            .menuStyle(.borderlessButton).accessibilityLabel(l.t("기억 동작", "Memory actions", "思い出の操作"))
        }
        .padding(.vertical, 4)
    }

    private func sourceName(_ source: PokemonMemorySource) -> String {
        switch source {
        case .event: return l.t("모험", "Event", "イベント")
        case .conversation: return l.t("대화", "Conversation", "会話")
        case .manual: return l.t("내 기록", "Note", "メモ")
        }
    }
}

private struct MemoryHomeVisitSheet: View {
    let visits: MemoryHomeVisitCenter
    let language: L
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language.t("주변 Memory Home", "Nearby Memory Homes", "近くのMemory Home")).font(.headline)
                Spacer(); Button(language.t("닫기", "Close", "閉じる")) { dismiss() }
            }
            if let profile = visits.selectedProfile {
                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.displayName).font(.title3.weight(.bold))
                    Text("#(profile.speciesID)" + (profile.isShiny ? " ✨" : ""))
                    if let memory = profile.sharedMemoryBody { Text(memory).font(.callout) }
                }.padding().pokedoroCard(tint: PokedoroTheme.mint)
            }
            if let error = visits.lastError { Text(error).foregroundStyle(PokedoroTheme.red).font(.caption) }
            if visits.homes.isEmpty { Text(language.t("홈을 찾는 중이에요…", "Looking for homes…", "ホームを探しています…")).foregroundStyle(.secondary) }
            ForEach(visits.homes) { home in
                Button { visits.visit(home) } label: { Label(home.displayName, systemImage: "house") }
                    .accessibilityLabel(language.t("\(home.displayName) 홈 방문", "Visit \(home.displayName)'s home", "\(home.displayName)のホームを訪問"))
            }
            Spacer()
        }.padding().frame(minWidth: 330, minHeight: 260)
    }
}
