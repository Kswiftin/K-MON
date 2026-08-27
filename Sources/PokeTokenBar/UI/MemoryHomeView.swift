import SwiftUI

enum MemoryHomeRoomTheme {
    static func tint(forUnlockedCardCount count: Int) -> Color {
        switch count {
        case 0: PokedoroTheme.blue
        case 1...2: PokedoroTheme.mint
        case 3...4: PokedoroTheme.yellow
        default: PokedoroTheme.red
        }
    }
}

struct MemoryHomeView: View {
    @Environment(AppSettings.self) private var settings
    let store: CompanionStore
    @State private var note = ""
    @State private var validationMessage: String?

    private var l: L { store.l }

    var body: some View {
        guard let mon = store.state.active else { return AnyView(EmptyView()) }
        let album = store.memoryAlbum
        let entries = album.entries(for: mon.id)
        let timeline = album.timeline(for: mon.id)
        let hidden = entries.filter(\.isHidden).sorted { $0.createdAt > $1.createdAt }
        let milestones = album.milestones(for: mon.id)
        let roomTint = MemoryHomeRoomTheme.tint(forUnlockedCardCount: milestones.count)

        return AnyView(VStack(alignment: .leading, spacing: 10) {
            roomHeader(mon: mon, entries: entries, milestones: milestones, tint: roomTint)

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
                    ForEach(milestones) { milestone in
                        milestoneRow(milestone, tint: roomTint)
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
        .onAppear { settings.recordMemoryHomeExposure() })
    }

    private func roomHeader(mon: MonState, entries: [PokemonMemory], milestones: [PokemonMemoryMilestone], tint: Color) -> some View {
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
                Text(firstRecordedText(mon.id)).font(.caption).foregroundStyle(.secondary)
                Text(l.t("기억 \(entries.count)개 · 카드 \(milestones.count)개",
                         "\(entries.count) memories · \(milestones.count) cards",
                         "思い出 \(entries.count) 件・カード \(milestones.count) 枚"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(l.t("\(store.chatProfile(for: mon).displayName)의 미니룸. \(firstRecordedText(mon.id)). 기억 \(entries.count)개, 카드 \(milestones.count)개",
                               "\(store.chatProfile(for: mon).displayName)'s mini room. \(firstRecordedText(mon.id)). \(entries.count) memories, \(milestones.count) cards",
                               "\(store.chatProfile(for: mon).displayName)のミニルーム。\(firstRecordedText(mon.id))。思い出 \(entries.count) 件、カード \(milestones.count) 枚"))
    }

    private func firstRecordedText(_ companionID: UUID) -> String {
        guard let first = store.memoryAlbum.firstRecordedAt(for: companionID) else {
            return l.t("아직 기록이 없어요", "No memories yet", "まだ記録はありません")
        }
        return l.t("첫 기록 ", "First record ", "最初の記録 ") + first.formatted(date: .abbreviated, time: .omitted)
    }

    private func milestoneRow(_ milestone: PokemonMemoryMilestone, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: milestoneIcon(milestone)).foregroundStyle(tint).frame(width: 16)
            Text(milestoneTitle(milestone)).font(.subheadline)
            Spacer(minLength: 0)
            Text(milestone.occurredAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(milestoneTitle(milestone) + ", " + milestone.occurredAt.formatted(date: .abbreviated, time: .omitted))
    }

    private func milestoneIcon(_ milestone: PokemonMemoryMilestone) -> String {
        switch milestone.kind {
        case .firstRecord: "book.fill"
        case .focusSessions: "timer"
        case .evolution: "arrow.triangle.2.circlepath"
        case .anniversary: "sparkles"
        }
    }

    private func milestoneTitle(_ milestone: PokemonMemoryMilestone) -> String {
        switch milestone.kind {
        case .firstRecord: l.t("첫 기록", "First record", "最初の記録")
        case .focusSessions(let count): l.t("집중 모험 \(count)회", "\(count) focus adventures", "集中冒険 \(count) 回")
        case .evolution: l.t("진화의 순간", "Evolution moment", "進化の瞬間")
        case .anniversary: l.t("첫 기록 1주년", "First-record anniversary", "最初の記録 1周年")
        }
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
