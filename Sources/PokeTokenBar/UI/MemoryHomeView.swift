import SwiftUI

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

        return AnyView(VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SpriteView(speciesID: mon.currentID, size: 52, shiny: mon.isShiny)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.t("우리의 기록", "Our memories", "ふたりの記録")).font(.headline)
                    Text(store.chatProfile(for: mon).displayName).font(.subheadline.weight(.semibold))
                    Text(firstRecordedText(entries)).font(.caption).foregroundStyle(.secondary)
                    Text(l.t("기억 \(entries.count)개", "\(entries.count) memories", "思い出 \(entries.count) 件"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
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
        }
        .padding(10).pokedoroCard(tint: PokedoroTheme.mint)
        .onAppear { settings.recordMemoryHomeExposure() })
    }

    private func firstRecordedText(_ entries: [PokemonMemory]) -> String {
        guard let first = entries.min(by: { $0.createdAt < $1.createdAt }) else {
            return l.t("아직 기록이 없어요", "No memories yet", "まだ記録はありません")
        }
        return l.t("첫 기록 ", "First record ", "最初の記録 ") + first.createdAt.formatted(date: .abbreviated, time: .omitted)
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
                if memory.source == .manual {
                    Button(memory.isHidden ? l.t("다시 표시", "Show", "再表示") : l.t("숨기기", "Hide", "非表示")) {
                        _ = album.setHidden(memory, isHidden: !memory.isHidden)
                    }
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
