import AppKit
import Observation
import SwiftUI

/// Memory Home is intentionally an AppKit-owned window.  Its frame belongs to macOS's
/// normal window restoration, never to the companion save file.
@MainActor
@Observable
final class MemoryHomePresenter: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let store: CompanionStore
    private let visits: MemoryHomeVisitCenter
    private var window: NSWindow?

    init(settings: AppSettings, store: CompanionStore, visits: MemoryHomeVisitCenter) {
        self.settings = settings
        self.store = store
        self.visits = visits
    }

    func open() {
        let window = window ?? makeWindow()
        self.window = window
        if window.contentView == nil { installContent(in: window) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settings.recordMemoryHomeEntry()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_040, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Poké Home"
        window.minSize = NSSize(width: 900, height: 640)
        window.setFrameAutosaveName("MemoryHomeWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        installContent(in: window)
        window.center()
        return window
    }

    private func installContent(in window: NSWindow) {
        window.contentViewController = NSHostingController(rootView:
            MemoryHomeWindowView(store: store, visits: visits)
                .environment(settings)
                .environment(store)
                .environment(visits)
                .environment(\.locale, store.language.displayLocale))
    }
}

struct MemoryHomeQuickCard: View {
    let store: CompanionStore
    let openHome: () -> Void
    @Environment(AppSettings.self) private var settings

    private var l: L { store.l }

    var body: some View {
        if let mon = store.state.active {
            let album = store.memoryAlbum
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("TODAY \(album.memoryHomeAccess.visitToday) · TOTAL \(album.memoryHomeAccess.visitTotal)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(PokedoroTheme.blue)
                    Spacer()
                    Text(store.chatProfile(for: mon).displayName).font(.caption.weight(.semibold)).lineLimit(1)
                }
                Text(album.memoryHomeAccess.profileMessage ?? l.t("우리의 작은 포케 홈", "Our little Poké Home", "ふたりの小さなポケホーム"))
                    .font(.caption).lineLimit(1)
                if let pinned = album.pinned(for: mon.id) {
                    Label(pinned.body, systemImage: "pin.fill")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Button(action: openHome) {
                    Label(l.t("미니홈피 열기", "Open Poké Home", "ポケホームを開く"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .accessibilityHint(l.t("전용 Memory Home 창을 엽니다.", "Opens the dedicated Memory Home window.", "専用Memory Homeウインドウを開きます。"))
            }
            .padding(10)
            .pokedoroCard(tint: PokedoroTheme.mint)
            .onAppear { settings.recordMemoryHomeExposure() }
        }
    }
}

private enum MemoryHomeTab: String, CaseIterable, Identifiable {
    case home = "HOME", profile = "PROFILE", records = "RECORDS", photo = "PHOTO", guestbook = "GUESTBOOK", visit = "VISIT"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .profile: "person.text.rectangle"
        case .records: "book.closed.fill"
        case .photo: "photo.fill"
        case .guestbook: "text.bubble.fill"
        case .visit: "figure.walk.arrival"
        }
    }
}

private struct MemoryHomeWindowView: View {
    let store: CompanionStore
    let visits: MemoryHomeVisitCenter
    @Environment(AppSettings.self) private var settings
    @State private var tab: MemoryHomeTab = .home
    @State private var note = ""
    @State private var photo = false
    @State private var guestbookDraft = ""
    @State private var profileMessageDraft = ""
    @State private var profileMessageError: String?
    @State private var editingRoom = false
    @State private var selectedDecorID: UUID?
    /// §25 계절 결산. `eee5c86` 이후 이 시트는 창에서 열 수 없는 상태였다.
    @State private var recap = false
    /// §25 연말 결산. 자동으로 띄우지 않는다 — "올해 한 번만" 을 판정하려면 새 저장 필드가
    /// 필요하고, 그건 이 홈의 "새 필드 0개" 원칙을 깬다(PRD 의 Open Question 으로 남겼다).
    @State private var yearRecap = false

    private var l: L { store.l }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                tabBar
                Group {
                    if let mon = store.state.active { tabContent(mon: mon, width: proxy.size.width) }
                    else { ContentUnavailableView(l.t("동행을 기다리고 있어요", "Waiting for a companion", "相棒を待っています"), systemImage: "house") }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(PokedoroTheme.pageBackground)
        .tint(PokedoroTheme.blue)
        .fontDesign(.rounded)
        .sheet(isPresented: $photo) {
            MemoryHomeStickerPhotoSheet(speciesID: store.state.active?.currentID ?? 25,
                                        shiny: store.state.active?.isShiny ?? false, language: l, album: store.memoryAlbum)
        }
        .sheet(isPresented: $recap) {
            MemoryHomeSeasonRecapSheet(recap: store.memoryAlbum.seasonRecap(for: store.ownedMons.map(\.id)),
                                       language: l)
        }
        .sheet(isPresented: $yearRecap) {
            let summary = store.memoryAlbum.yearRecap(for: store.ownedMons.map(\.id))
            MemoryHomeYearRecapSheet(recap: summary,
                                     topCompanionName: summary.topCompanionID
                                         .flatMap { id in store.ownedMons.first { $0.id == id } }
                                         .map { store.chatProfile(for: $0).displayName },
                                     language: l)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            let access = store.memoryAlbum.memoryHomeAccess
            Text("TODAY \(access.visitToday)  TOTAL \(access.visitTotal)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(PokedoroTheme.red)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(PokedoroTheme.red.opacity(0.11), in: Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.memoryAlbum.memoryHomePublicNickname)'s Poké Home").font(.headline)
                Text(access.profileMessage ?? l.t("기억을 모으는 작은 방", "A little room for memories", "思い出を集める小さな部屋"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            // §24 계절. 저장 없이 달력 월에서 파생한다 — 방 색은 사용자가 고른 테마 그대로 둔다.
            Label(MemoryHomeSeasonStyle.name(MemoryHomeSeason.current(), l),
                  systemImage: MemoryHomeSeasonStyle.symbol(MemoryHomeSeason.current()))
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.primary.opacity(0.055), in: Capsule())
            Label(access.visibility == .open ? l.t("LAN 공개", "LAN open", "LAN公開") : l.t("LAN 차단", "LAN blocked", "LANブロック"),
                  systemImage: access.visibility == .open ? "dot.radiowaves.left.and.right" : "lock.fill")
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.primary.opacity(0.055), in: Capsule())
                .accessibilityLabel(l.t("공유 상태", "Sharing status", "共有状態"))
            Button { tab = .profile } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).controlSize(.small)
                .frame(minWidth: 28, minHeight: 28)
                .accessibilityLabel(l.t("홈 설정", "Home settings", "ホーム設定"))
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(MemoryHomeTab.allCases) { item in
                    Button { withAnimation(.snappy(duration: 0.22)) { tab = item } } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .frame(minWidth: 84, minHeight: 34)
                            .foregroundStyle(tab == item ? PokedoroTheme.ink : .secondary)
                            .background(tab == item ? PokedoroTheme.blue.opacity(0.18) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.rawValue)
                        .accessibilityValue(tab == item ? l.t("현재 탭", "Current tab", "現在のタブ") : "")
                }
            }
        }
        .padding(4).padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52))
    }

    @ViewBuilder private func tabContent(mon: MonState, width: CGFloat) -> some View {
        switch tab {
        case .home: home(mon: mon, width: width)
        case .profile: profile(mon: mon)
        case .records: records(mon: mon)
        case .photo: photoTab(mon: mon)
        case .guestbook: guestbook(mon: mon)
        case .visit: visit
        }
    }

    private func home(mon: MonState, width: CGFloat) -> some View {
        return ScrollView {
            if width <= 920 {
                VStack(spacing: 12) { profilePanel(mon: mon); roomStage(mon: mon); sidePanel(mon: mon) }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    profilePanel(mon: mon).frame(width: 164)
                    roomStage(mon: mon).frame(maxWidth: .infinity)
                    sidePanel(mon: mon).frame(width: 245)
                }
            }
        }.padding(14)
    }

    private func profilePanel(mon: MonState) -> some View {
        let log = store.memoryAlbum.pokeLog(for: mon.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                SpriteView(speciesID: mon.currentID, size: 52, shiny: mon.isShiny)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.chatProfile(for: mon).displayName).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text("\(log.daysTogether) \(l.t("일 함께", "days together", "日いっしょ"))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            MemoryHomeRule(label: l.t("친밀도", "Closeness", "なかよし度"), value: String(repeating: "♥", count: log.closenessHearts) + String(repeating: "♡", count: 5 - log.closenessHearts))
            let mood = store.memoryAlbum.mood()
            MemoryHomeRule(label: l.t("현재 기분", "Mood", "今の気分"), value: mood.map { MemoryHomeMoodStyle.emoji($0) + " " + MemoryHomeMoodStyle.name($0, l) } ?? "—")
            Button(l.t("프로필 보기", "View profile", "プロフィールを見る")) { tab = .profile }
                .buttonStyle(.bordered).controlSize(.small)
        }.memoryHomePanel()
    }

    /// §5 미니룸. R8 격자(12칸)를 그린다 — `9de278f` 가 이 화면을 만들면서 격자·스타일·
    /// 되돌리기를 **삭제 예정이던 옛 화면**에만 붙였고, 창에는 legacy 3슬롯만 남았다.
    private func roomStage(mon: MonState) -> some View {
        let album = store.memoryAlbum
        let tint = MemoryHomeRoomTheme.tint(for: album.theme(for: mon.id))
        let style = MemoryHomeRoomStyle.tint(for: album.roomStyle)
        return ZStack {
            tint.opacity(0.18)
            if let art = MemoryHomeBundledArt.interiorTileset() {
                Image(nsImage: art).resizable().interpolation(.none).scaledToFill().opacity(0.32)
            }
            // 스타일은 바닥 띠에만 얹는다. 방 전체를 덮으면 사용자가 고른 테마 4색을 뭉갠다.
            Rectangle().fill(style.opacity(0.34)).frame(height: 34).frame(maxHeight: .infinity, alignment: .bottom)
            GeometryReader { geometry in
                ForEach(album.memoryHomeAccess.placedDecor.sorted { $0.layer < $1.layer }) { decor in
                    decorSprite(decor)
                        .position(x: decor.position.x * geometry.size.width,
                                  y: decor.position.y * geometry.size.height)
                        .onTapGesture { if editingRoom { selectedDecorID = decor.id } }
                        .gesture(editingRoom ? DragGesture(minimumDistance: 2).onEnded { value in
                            _ = album.moveDecor(id: decor.id,
                                                to: .init(x: value.location.x / geometry.size.width,
                                                          y: value.location.y / geometry.size.height))
                        } : nil)
                        .accessibilityLabel(l.itemName(decor.item))
                        .accessibilityHint(l.t("드래그하여 8×6 격자에서 이동합니다.", "Drag to move on the 8 by 6 grid.", "ドラッグして8×6グリッドで移動します。"))
                }
                let companions = [mon] + Array(roommates.prefix(2))
                ForEach(Array(companions.enumerated()), id: \.element.id) { index, companion in
                    let point = album.companionPosition(for: companion.id, fallbackIndex: index)
                    SpriteView(speciesID: companion.currentID, size: companion.id == mon.id ? 128 : 78, shiny: companion.isShiny)
                        .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                        .gesture(editingRoom ? DragGesture().onEnded { value in
                            album.setCompanionPosition(.clamped(x: value.location.x / geometry.size.width, y: value.location.y / geometry.size.height), for: companion.id, validCompanionIDs: Set(store.ownedMons.map(\.id)))
                        } : nil)
                }
            }
            VStack { HStack { Text(l.t("미니룸", "Mini room", "ミニルーム")).font(.caption.weight(.semibold)); Spacer() }; Spacer() }.padding(12)
            VStack { Spacer(); Text(roomLifeLine(mon: mon)).font(.caption.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 5).background(.black.opacity(0.12), in: Capsule()).padding(12) }
            if editingRoom { VStack { HStack { Spacer(); Text(l.t("가구와 동행을 드래그해 배치하세요", "Drag furniture and companions to arrange", "家具と相棒をドラッグして配置")) .font(.caption.weight(.semibold)).padding(8).background(.ultraThinMaterial, in: Capsule()) }; Spacer() }.padding(12) }
        }
        .frame(minHeight: 365)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .pokedoroCard(tint: tint, emphasized: true)
        .accessibilityLabel(l.t("가구와 동행이 배치된 미니룸", "Mini room with furniture and companions", "家具と相棒を配置したミニルーム"))
    }

    @ViewBuilder private func decorSprite(_ decor: MemoryHomePlacedDecor) -> some View {
        Group {
            if let art = MemoryHomeBundledArt.furnitureImage(for: decor.item) {
                Image(nsImage: art).resizable().interpolation(.none).scaledToFit().frame(width: 62, height: 62)
            } else {
                // 번들 아트가 없는 가구도 방에 보여야 한다 — 안 그리면 놓았는데 사라진 것처럼 보인다.
                Text(decor.item.fallbackEmoji).font(.system(size: 34))
            }
        }
        .padding(3)
        .background(selectedDecorID == decor.id && editingRoom ? Color.white.opacity(0.8) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// §5 §17 §24 한 줄. 문구 판정은 전부 `MemoryHomeRoomLife` 에 있다 — 뷰에 두면 세 언어가
    /// 무테스트로 남는다(이 화면의 옛 문구 3줄이 정확히 그 상태였다).
    private func roomLifeLine(mon: MonState) -> String {
        MemoryHomeRoomLife.line(speciesID: mon.currentID,
                                decor: store.memoryAlbum.memoryHomeAccess.placedDecor.map(\.item),
                                mood: store.memoryAlbum.mood(),
                                season: MemoryHomeSeason.current(),
                                companion: store.chatProfile(for: mon).displayName, l)
    }

    private func sidePanel(mon: MonState) -> some View {
        let album = store.memoryAlbum
        let timeline = album.timeline(for: mon.id)
        return VStack(alignment: .leading, spacing: 10) {
            Text(l.t("기억 보드", "Memory board", "思い出ボード")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let pin = album.pinned(for: mon.id) { Label(pin.body, systemImage: "pin.fill").font(.caption).lineLimit(3) }
            Divider()
            Text(l.t("최근 기억", "Recent", "最近の記憶")).font(.caption.weight(.bold))
            ForEach(timeline.prefix(3)) { Text("· \($0.body)").font(.caption2).lineLimit(2) }
            if !album.milestones(for: mon.id).isEmpty { Label("\(album.milestones(for: mon.id).count) \(l.t("열린 카드", "cards unlocked", "枚のカード"))", systemImage: "rectangle.stack.fill").font(.caption) }
            Divider()
            Text(l.t("오늘의 기분", "Today's mood", "今日の気分"))
                .font(.caption.weight(.bold))
            Menu {
                ForEach(MemoryHomeMood.allCases, id: \.self) { mood in
                    Button {
                        album.setMood(mood)
                    } label: {
                        Text("\(MemoryHomeMoodStyle.emoji(mood)) \(MemoryHomeMoodStyle.name(mood, l))")
                    }
                }
            } label: {
                Label(currentMoodLabel(album), systemImage: "face.smiling")
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .accessibilityHint(l.t("기분에 따라 동행의 방명록과 반응이 달라집니다.", "Your companion reacts differently in the guestbook and room.", "気分で相棒の反応とゲストブックが変わります。"))

            Divider()
            Text(l.t("미니룸 꾸미기", "Mini room", "ミニルームを飾る"))
                .font(.caption.weight(.bold))
            Button(editingRoom ? l.t("꾸미기 완료", "Done decorating", "模様替えを完了") : l.t("배치 편집", "Edit layout", "配置を編集")) { editingRoom.toggle() }
                .buttonStyle(.borderedProminent).controlSize(.small)
            Menu(l.t("룸메이트", "Roommates", "ルームメイト")) {
                ForEach(store.ownedMons.filter { $0.id != mon.id }) { candidate in
                    let included = album.memoryHomeAccess.roommateIDs.contains(candidate.id)
                    Button {
                        setRoommate(candidate.id, included: !included)
                    } label: {
                        Label(store.chatProfile(for: candidate).displayName,
                              systemImage: included ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)

            // R8 스타일. 해금하지 않은 스타일은 고를 수 없다 — `selectRoomStyle` 이 앨범에서
            // 한 번 더 막지만, 눌리는 버튼이 아무 일도 안 하는 화면을 만들지 않는다.
            Menu(l.t("방 스타일: ", "Room style: ", "スタイル: ") + album.roomStyle.name(l)) {
                ForEach(MemoryHomeRoomStyle.allCases, id: \.self) { style in
                    Button { album.selectRoomStyle(style) } label: {
                        Label(style.name(l), systemImage: style == album.roomStyle ? "checkmark" : "circle")
                    }
                    .disabled(!album.isRoomStyleUnlocked(style))
                }
            }
            .menuStyle(.borderedButton).controlSize(.small)
            .accessibilityLabel(l.t("방 스타일", "Room style", "部屋のスタイル"))
            .accessibilityValue(album.roomStyle.name(l))

            Menu(l.t("가구 놓기", "Place furniture", "家具を置く")) {
                ForEach(ItemKind.memoryHomeFurniture.sorted { $0.rawValue < $1.rawValue }, id: \.self) { item in
                    Button {
                        _ = album.placeDecor(item, at: .init(x: 0.5, y: 0.6), ownedItems: store.state.inventory)
                    } label: {
                        Text("\(item.fallbackEmoji) \(l.itemName(item)) ×\(store.itemCount(item))")
                    }
                    .disabled(store.itemCount(item) == 0 || album.memoryHomeAccess.placedDecor.count >= 12)
                }
            }
            .menuStyle(.borderedButton).controlSize(.small)
            .accessibilityLabel(l.t("가구 놓기", "Place furniture", "家具を置く"))
            .accessibilityValue(l.t("\(album.memoryHomeAccess.placedDecor.count)/12 배치", "\(album.memoryHomeAccess.placedDecor.count) of 12 placed", "\(album.memoryHomeAccess.placedDecor.count)/12 配置"))

            HStack(spacing: 6) {
                Button { album.undoRoomEdit() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!album.canUndoRoomEdit)
                    .accessibilityLabel(l.t("실행 취소", "Undo", "取り消す"))
                Button { album.redoRoomEdit() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!album.canRedoRoomEdit)
                    .accessibilityLabel(l.t("다시 실행", "Redo", "やり直す"))
                if let selectedDecorID, editingRoom {
                    Button(role: .destructive) {
                        _ = album.removeDecor(id: selectedDecorID); self.selectedDecorID = nil
                    } label: { Image(systemName: "trash") }
                        .accessibilityLabel(l.t("선택한 가구 치우기", "Remove selected furniture", "選んだ家具を片づける"))
                }
                Button(l.t("초기화", "Reset", "リセット"), role: .destructive) { album.resetDecor() }
                    .disabled(album.memoryHomeAccess.placedDecor.isEmpty)
            }
            .controlSize(.small)

            Divider()
            // §11 주크박스. `setJukeboxTrack` 은 이 화면이 생기기 전까지 테스트만 부르고 있었다.
            Text(l.t("대표 BGM", "Home BGM", "ホームのBGM")).font(.caption.weight(.bold))
            Menu {
                ForEach(MemoryHomeJukeboxTrack.allCases, id: \.self) { track in
                    let unlocked = jukeboxUnlocked(track)
                    Button { album.setJukeboxTrack(track) } label: {
                        Label(unlocked ? MemoryHomeJukebox.name(track, l)
                                       : MemoryHomeJukebox.name(track, l) + " · " + MemoryHomeJukebox.requirement(track, l),
                              systemImage: unlocked ? MemoryHomeJukebox.symbol(track) : "lock.fill")
                    }
                    .disabled(!unlocked)
                }
            } label: {
                Label(MemoryHomeJukebox.name(album.memoryHomeAccess.jukeboxTrack, l),
                      systemImage: MemoryHomeJukebox.symbol(album.memoryHomeAccess.jukeboxTrack))
            }
            .menuStyle(.borderedButton).controlSize(.small)
            .accessibilityLabel(l.t("대표 BGM", "Home BGM", "ホームのBGM"))
            .accessibilityHint(l.t("함께 쌓은 기억이 곡을 해금합니다. 소리는 재생하지 않아요.",
                                   "Memories you build together unlock tracks. No audio is played.",
                                   "いっしょに積んだ思い出が曲を解放します。音は再生しません。"))

            Divider()
            TextField(l.t("빠른 기록", "Quick note", "クイックメモ"), text: $note, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
            Button(l.t("남기기", "Save", "保存")) { if album.addManual(companionID: mon.id, body: note) { settings.recordManualMemoryCreated(); note = "" } }
                .buttonStyle(.borderedProminent).controlSize(.small).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.count > 280)
        }.memoryHomePanel()
    }

    private func profile(mon: MonState) -> some View {
        let album = store.memoryAlbum
        return ScrollView { VStack(alignment: .leading, spacing: 14) {
            let log = album.pokeLog(for: mon.id)
            HStack(spacing: 12) {
                SpriteView(speciesID: mon.currentID, size: 72, shiny: mon.isShiny)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.chatProfile(for: mon).displayName).font(.title3.weight(.bold))
                    Text(l.t("함께한 \(log.daysTogether)일 · 기억 \(log.memoryCount)개", "\(log.daysTogether) days · \(log.memoryCount) memories", "いっしょに\(log.daysTogether)日・記憶\(log.memoryCount)件"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(roommateNames).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }.memoryHomePanel(tint: PokedoroTheme.yellow)
            VStack(alignment: .leading, spacing: 10) {
                Text(l.t("공개 프로필", "Public profile", "公開プロフィール")).font(.headline)
                TextField(l.t("공개 닉네임", "Public nickname", "公開ニックネーム"), text: Binding(get: { album.memoryHomePublicNickname }, set: { _ = album.setMemoryHomePublicNickname($0); visits.refreshAccess() }))
                TextField(l.t("대문 문구", "Home message", "ホームの一言"), text: $profileMessageDraft)
                HStack {
                    Button(l.t("문구 저장", "Save message", "一言を保存")) {
                        if album.setProfileMessage(profileMessageDraft) { profileMessageError = nil }
                        else { profileMessageError = l.t("줄바꿈 없이 1~60자로 입력해 주세요.", "Use 1–60 characters without line breaks.", "改行なしで1〜60文字にしてください。") }
                    }.buttonStyle(.bordered).controlSize(.small)
                    if let profileMessageError { Text(profileMessageError).font(.caption).foregroundStyle(PokedoroTheme.red) }
                }
                Toggle(l.t("대문 문구 LAN 공유", "Share home message on LAN", "一言をLAN共有"), isOn: Binding(get: { album.memoryHomeAccess.sharesProfileMessage }, set: { album.setSharesProfileMessage($0) }))
                    .disabled(album.memoryHomeAccess.profileMessage == nil)
                if album.memoryHomeAccess.profileMessage == nil {
                    Text(l.t("대문 문구를 저장하면 같은 LAN 공유를 켤 수 있어요.", "Save a home message before enabling LAN sharing.", "一言を保存するとLAN共有を有効にできます。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(l.t("홈 LAN 공개", "Open home on LAN", "ホームをLAN公開"), isOn: Binding(get: { album.memoryHomeAccess.visibility == .open }, set: { album.setMemoryHomeVisibility($0 ? .open : .blocked); visits.refreshAccess() }))
            }.memoryHomePanel(tint: PokedoroTheme.mint).onAppear { profileMessageDraft = album.memoryHomeAccess.profileMessage ?? "" }
            VStack(alignment: .leading, spacing: 8) {
                Text(l.t("함께한 발자국", "Our journey", "ふたりのあしあと")).font(.headline)
                MemoryHomeRule(label: l.t("첫 만남", "First met", "出会い"), value: log.firstMetAt?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                MemoryHomeRule(label: l.t("집중", "Focus", "集中"), value: "\(log.completedFocusSessions)")
                MemoryHomeRule(label: l.t("방문", "Visits", "訪問"), value: "\(album.memoryHomeAccess.visitTotal)")
            }.memoryHomePanel(tint: PokedoroTheme.yellow)
            VStack(alignment: .leading, spacing: 5) {
                Text(l.t("개인정보", "Privacy", "プライバシー")).font(.headline)
                Text(l.t("수동 기억과 일촌명은 LAN에 공유되지 않습니다.", "Manual memories and peer aliases are never shared on LAN.", "手動の思い出と一村名はLAN共有されません。")).font(.callout).foregroundStyle(.secondary)
            }.memoryHomePanel(tint: PokedoroTheme.blue)
        }.padding(18) }
    }

    private func records(mon: MonState) -> some View { let album = store.memoryAlbum; let log = album.pokeLog(for: mon.id); return ScrollView { LazyVStack(alignment: .leading, spacing: 12) { VStack(alignment: .leading, spacing: 8) { Text(l.t("기록", "Records", "記録")).font(.title2.bold()); Text(l.t("매일의 기억과 함께한 발자국을 한곳에서 돌아봐요.", "Revisit daily memories and milestones in one place.", "毎日の思い出とふたりのあしあとを一緒に振り返ります。")) .font(.caption).foregroundStyle(.secondary); HStack { Button { recap = true } label: { Label(l.t("계절 결산 보기", "View season recap", "季節のまとめを見る"), systemImage: "calendar") }.buttonStyle(.bordered).controlSize(.small); Button { yearRecap = true } label: { Label(l.t("연말 결산 보기", "View year in review", "一年のまとめを見る"), systemImage: "sparkles.rectangle.stack") }.buttonStyle(.bordered).controlSize(.small).accessibilityHint(l.t("올해 함께한 기록을 한 장으로 봅니다.", "Shows this year's record on a single card.", "今年の記録を一枚にまとめて見ます。")) }; Text(l.t("함께한 \(log.daysTogether)일 · 집중 \(log.completedFocusSessions)회 · 기억 \(log.memoryCount)개", "\(log.daysTogether) days · \(log.completedFocusSessions) focus sessions · \(log.memoryCount) memories", "いっしょに\(log.daysTogether)日・集中\(log.completedFocusSessions)回・記憶\(log.memoryCount)件")) }.memoryHomePanel(tint: PokedoroTheme.red); if !log.milestones.isEmpty { VStack(alignment: .leading, spacing: 6) { Text(l.t("함께한 발자국", "Milestones", "あしあと")).font(.headline); ForEach(log.milestones) { Label(MemoryHomeCardStyle.title($0, l), systemImage: MemoryHomeCardStyle.icon($0)) } }.memoryHomePanel(tint: PokedoroTheme.yellow) }; ForEach(album.diary(for: mon.id)) { day in VStack(alignment: .leading, spacing: 5) { HStack { Text(day.date.formatted(date: .abbreviated, time: .omitted)).font(.headline); if let mood = day.mood { Text(MemoryHomeMoodStyle.emoji(mood)) } }; ForEach(day.memories) { Text("· \($0.body)").font(.caption) } }.memoryHomePanel() } } }.padding(14) }
    private func photoTab(mon: MonState) -> some View { let album = store.memoryAlbum; return ScrollView { VStack(alignment: .leading, spacing: 16) { HStack { VStack(alignment: .leading, spacing: 4) { Text(l.t("포토부스", "Photo booth", "フォトブース")).font(.title2.bold()); Text(l.t("트레이너와 동행의 구도·배경·프레임을 골라 전시해 보세요.", "Choose a trainer, companion, composition and background, then exhibit the shot.", "トレーナーと相棒の構図・背景・フレームを選んで展示しましょう。")) .font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(l.t("사진 만들기", "Make photo", "写真を作る")) { photo = true }.buttonStyle(.borderedProminent) }.memoryHomePanel(tint: PokedoroTheme.yellow); if album.memoryHomeAccess.photos.isEmpty { ContentUnavailableView(l.t("첫 사진을 전시해 보세요", "Exhibit your first photo", "最初の写真を展示しましょう"), systemImage: "photo.on.rectangle") } else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) { ForEach(album.memoryHomeAccess.photos) { shot in VStack(alignment: .leading, spacing: 6) { SpriteView(speciesID: shot.speciesID, size: 76, shiny: shot.isShiny).frame(maxWidth: .infinity); Label(shot.caption.isEmpty ? "POKÉDORO" : shot.caption, systemImage: "person.2.fill").font(.caption).lineLimit(2); Text(shot.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary); Button(role: .destructive) { album.deletePhoto(id: shot.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel(l.t("사진 삭제", "Delete photo", "写真を削除")) }.memoryHomePanel(tint: PokedoroTheme.mint) } } } }.padding(18) } }
    /// §13 방명록. 탭을 열 때 동행이 하루 한 번, 약 4일에 1번 흔적을 남긴다 — 판정은
    /// `MemoryHomeCompanionTrace` 의 dayKey 결정론이라 여닫아도 글이 늘지 않는다.
    private func guestbook(mon: MonState) -> some View { let album = store.memoryAlbum; return ScrollView { VStack(alignment: .leading, spacing: 14) { VStack(alignment: .leading, spacing: 8) { Label(l.t("방명록", "Guestbook", "ゲストブック"), systemImage: "text.bubble.fill").font(.title3.weight(.bold)); Text(l.t("내가 남긴 한마디를 모아 둬요. 이 글은 LAN에 공유되지 않습니다.", "Keep your notes here. They stay on this device.", "自分のひとことを残します。LANには共有されません。")) .font(.caption).foregroundStyle(.secondary); TextField(l.t("오늘의 한마디", "Leave a note", "今日のひとこと"), text: $guestbookDraft, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder); Button(l.t("내 이름으로 남기기", "Sign as me", "自分の名前で残す")) { if album.addGuestbookEntry(author: album.memoryHomePublicNickname, body: guestbookDraft, authorKind: .trainer) { guestbookDraft = "" } }.buttonStyle(.borderedProminent).controlSize(.small).disabled(guestbookDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || guestbookDraft.count > MemoryHomeAccessSettings.guestbookBodyLimit) }.memoryHomePanel(tint: PokedoroTheme.yellow); if album.memoryHomeAccess.guestbookEntries.isEmpty { ContentUnavailableView(l.t("첫 방명록을 남겨 보세요", "Leave the first note", "最初のひとことを残しましょう"), systemImage: "text.bubble") } else { ForEach(album.memoryHomeAccess.guestbookEntries) { entry in VStack(alignment: .leading, spacing: 5) { HStack { Label(entry.author, systemImage: entry.authorKind == .companion ? "pawprint.fill" : "person.fill").font(.subheadline.weight(.semibold)); Spacer(); Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary); Button { album.deleteGuestbookEntry(id: entry.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).accessibilityLabel(l.t("방명록 삭제", "Delete guestbook note", "メモを削除")) }; Text(entry.body).font(.callout).fixedSize(horizontal: false, vertical: true) }.memoryHomePanel(tint: entry.authorKind == .companion ? PokedoroTheme.mint : PokedoroTheme.blue) } } }.padding(18) }.onAppear { _ = store.memoryAlbum.recordCompanionTraceIfNeeded(companionName: store.chatProfile(for: mon).displayName, l: l) } }
    private var visit: some View { ScrollView { VStack(alignment: .leading, spacing: 12) { VStack(alignment: .leading, spacing: 4) { Text(l.t("같은 LAN의 Memory Home", "Memory Homes on this LAN", "同じLANのMemory Home")).font(.headline); Text(l.t("홈을 고르고, 공개된 대표 동행과 미니룸 쇼케이스를 둘러보세요. 수집한 방문 도장 \(store.memoryAlbum.memoryHomeAccess.visitedHomeStamps.count)개", "Choose a home and explore its public companion and mini-room showcase. \(store.memoryAlbum.memoryHomeAccess.visitedHomeStamps.count) visit stamps collected.", "ホームを選び、公開された相棒とミニルームを見て回りましょう。訪問スタンプ\(store.memoryAlbum.memoryHomeAccess.visitedHomeStamps.count)個を集めました。")) .font(.caption).foregroundStyle(.secondary) }.memoryHomePanel(tint: PokedoroTheme.blue); if let selected = visits.selectedProfile { VStack(alignment: .leading, spacing: 8) { HStack { SpriteView(speciesID: selected.speciesID, size: 72, shiny: selected.isShiny); VStack(alignment: .leading) { Text(selected.displayName).font(.title3.bold()); Text(selected.profileMessage ?? l.t("환영합니다!", "Welcome!", "ようこそ！")).foregroundStyle(.secondary) } }; if let theme = selected.roomTheme { Label(l.t("공개 미니룸 쇼케이스", "Public mini-room showcase", "公開ミニルームショーケース"), systemImage: "house.fill").font(.caption.weight(.bold)); HStack { ForEach(selected.showcaseFurniture, id: \.self) { item in if let art = MemoryHomeBundledArt.furnitureImage(for: item) { Image(nsImage: art).resizable().interpolation(.none).scaledToFit().frame(width: 42, height: 42) } } }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(MemoryHomeRoomTheme.tint(for: theme).opacity(0.18), in: RoundedRectangle(cornerRadius: 10)) }; if let memory = selected.sharedMemoryBody { Text(memory).font(.caption) } }.memoryHomePanel(tint: PokedoroTheme.mint) }; if visits.homes.isEmpty { ContentUnavailableView(l.t("주변 홈을 찾는 중이에요…", "Looking for homes…", "近くのホームを探しています…"), systemImage: "dot.radiowaves.left.and.right") } else { Button { if let home = visits.homes.randomElement() { visits.visit(home) } } label: { Label(l.t("파도타기", "Surf a random home", "波乗り"), systemImage: "shuffle").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).accessibilityHint(l.t("같은 LAN의 홈 하나로 무작위 이동합니다.", "Jumps to a random home on this LAN.", "同じLANのホームへランダムに移動します。")); ForEach(visits.homes) { home in Button { visits.visit(home) } label: { Label(home.displayName, systemImage: "house.fill").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered).controlSize(.regular) } } }.padding(18) }.onAppear { visits.start() }.onDisappear { visits.stop() } }
    private var roommates: [MonState] {
        let ids = store.memoryAlbum.memoryHomeAccess.roommateIDs
        return store.ownedMons.filter { ids.contains($0.id) && $0.id != store.state.active?.id }
    }
    private var roommateNames: String { let names = roommates.map { store.chatProfile(for: $0).displayName }; return names.isEmpty ? l.t("아직 없어요", "None yet", "まだいません") : names.joined(separator: ", ") }
    private func currentMoodLabel(_ album: PokemonMemoryAlbum) -> String {
        guard let mood = album.mood() else { return l.t("기분을 골라 주세요", "Choose a mood", "気分を選ぶ") }
        return "\(MemoryHomeMoodStyle.emoji(mood)) \(MemoryHomeMoodStyle.name(mood, l))"
    }
    private func setRoommate(_ id: UUID, included: Bool) {
        let album = store.memoryAlbum
        var ids = album.memoryHomeAccess.roommateIDs.filter { $0 != store.state.active?.id }
        if included { ids.append(id) } else { ids.removeAll { $0 == id } }
        album.setRoommates(ids, validCompanionIDs: Set(store.ownedMons.map(\.id)))
    }
    /// 해금 판정은 홈 전체의 기억을 본다 — 곡은 동행 한 마리가 아니라 이 홈의 기록이 연다.
    private func jukeboxUnlocked(_ track: MemoryHomeJukeboxTrack) -> Bool {
        let ids = store.ownedMons.map(\.id)
        let memories = ids.flatMap { store.memoryAlbum.entries(for: $0) }
        let focus = ids.reduce(0) { $0 + store.memoryAlbum.pokeLog(for: $1).completedFocusSessions }
        return MemoryHomeJukebox.isUnlocked(track, memories: memories, focusSessions: focus)
    }
}

private struct MemoryHomeRule: View { let label: String; let value: String; var body: some View { HStack { Text(label).font(.caption).foregroundStyle(.secondary); Spacer(); Text(value).font(.caption.weight(.medium)).lineLimit(1) } } }
private extension View {
    func memoryHomePanel(tint: Color = PokedoroTheme.blue) -> some View {
        padding(12).pokedoroCard(tint: tint)
    }
}
