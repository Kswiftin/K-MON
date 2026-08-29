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
        super.init()
        observeAvailability()
    }

    private func observeAvailability() {
        withObservationTracking { _ = settings.memoryHomeEnabled } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if !self.settings.memoryHomeEnabled {
                    self.visits.shutdown()
                    self.window?.orderOut(nil)
                } else {
                    self.visits.startHostingIfEligible()
                }
                self.observeAvailability()
            }
        }
    }

    func open() {
        guard settings.memoryHomeEnabled else { return }
        let window = window ?? makeWindow()
        self.window = window
        if window.contentView == nil { installContent(in: window) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settings.recordMemoryHomeEntry()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window only ends its UI. LAN-public hosting stays alive for the app.
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
    @State private var selectedFurniture: ItemKind?
    @State private var selectedCompanionID: UUID?
    @State private var showResetDecorConfirmation = false
    @State private var roomEditFeedback: String?
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
        .alert(l.t("배치를 초기화할까요?", "Reset room layout?", "配置をリセットしますか？"),
               isPresented: $showResetDecorConfirmation) {
            Button(l.t("취소", "Cancel", "キャンセル"), role: .cancel) { }
            Button(l.t("가구 치우기", "Remove furniture", "家具を片づける"), role: .destructive) {
                store.memoryAlbum.resetDecor()
                selectedDecorID = nil
                selectedFurniture = nil
            }
        } message: {
            Text(l.t("현재 배치된 가구 \(store.memoryAlbum.memoryHomeAccess.placedDecor.count)개를 치웁니다. 실행 취소로 되돌릴 수 있어요.",
                     "This removes \(store.memoryAlbum.memoryHomeAccess.placedDecor.count) placed furniture item(s). You can undo it.",
                     "配置中の家具 \(store.memoryAlbum.memoryHomeAccess.placedDecor.count) 個を片づけます。取り消しで戻せます。"))
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
                VStack(spacing: 12) {
                    profilePanel(mon: mon)
                    roomStage(mon: mon)
                    if editingRoom { roomEditor(mon: mon) }
                    sidePanel(mon: mon)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    profilePanel(mon: mon).frame(width: 164)
                    VStack(spacing: 12) {
                        roomStage(mon: mon)
                        if editingRoom { roomEditor(mon: mon) }
                    }.frame(maxWidth: .infinity)
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
            // 벽지는 8×8 패턴을 **반복**해서 깐다. 예전엔 가구 아틀라스 전체를 `scaledToFill` 로
            // 늘려 배경에 붙여서, 침대·서랍장 그림이 뭉개진 채 벽에 박혀 있었다.
            if let wallpaper = MemoryHomePixelArt.wallpaperTile(for: album.roomStyle) {
                Image(nsImage: wallpaper).resizable(resizingMode: .tile).interpolation(.none)
            } else {
                style.opacity(0.34)
            }
            // 테마(사용자가 고른 4색)는 벽지 위에 옅게 얹는다 — 스타일이 테마를 지우면 안 된다.
            tint.opacity(0.18)
            // §24 창밖. 시각은 여기서 **한 번** 읽는다 — `TimelineView` 로 매초 갱신하면 방이
            // 상시 애니메이션이 되어 미니룸이 열려 있는 내내 CPU 를 먹는다(`defect-log.md`).
            // 경계를 넘는 순간이 아니라 방을 다시 열 때 반영되는 것으로 충분하다.
            let timeOfDay = MemoryHomeTimeOfDay.current()
            if let window = MemoryHomePixelArt.windowImage(for: album.roomStyle, timeOfDay: timeOfDay) {
                GeometryReader { geometry in
                    Image(nsImage: window).interpolation(.none)
                        .position(x: geometry.size.width * 0.76, y: geometry.size.height * 0.27)
                }
                .accessibilityElement()
                .accessibilityLabel(l.t("창밖", "Outside the window", "窓の外"))
                .accessibilityValue(MemoryHomeTimeOfDayStyle.name(timeOfDay, l))
            }
            if let floor = MemoryHomePixelArt.floorTile(for: album.roomStyle) {
                Image(nsImage: floor).resizable(resizingMode: .tile).interpolation(.none)
                    .frame(height: 64).frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                Rectangle().fill(style.opacity(0.34)).frame(height: 34).frame(maxHeight: .infinity, alignment: .bottom)
            }
            GeometryReader { geometry in
                if editingRoom {
                    roomGrid(in: geometry.size, album: album)
                }
                ForEach(album.memoryHomeAccess.placedDecor.sorted { $0.layer < $1.layer }) { decor in
                    decorSprite(decor)
                        .position(x: decor.position.x * geometry.size.width,
                                  y: decor.position.y * geometry.size.height)
                        .onTapGesture {
                            guard editingRoom else { return }
                            selectedDecorID = decor.id; selectedCompanionID = nil; selectedFurniture = nil
                        }
                        .gesture(editingRoom ? DragGesture(minimumDistance: 2).onEnded { value in
                            _ = album.moveDecor(id: decor.id,
                                                to: .init(x: value.location.x / geometry.size.width,
                                                          y: value.location.y / geometry.size.height))
                        } : nil)
                        .accessibilityLabel(l.itemName(decor.item))
                        .accessibilityHint(l.t("드래그하여 8×6 격자에서 이동합니다.", "Drag to move on the 8 by 6 grid.", "ドラッグして8×6グリッドで移動します。"))
                }
                let companions = [mon] + roommates
                ForEach(Array(companions.enumerated()), id: \.element.id) { index, companion in
                    let point = album.companionPosition(for: companion.id, fallbackIndex: index)
                    SpriteView(speciesID: companion.currentID, size: companion.id == mon.id ? 128 : 78, shiny: companion.isShiny)
                        .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                        .onTapGesture {
                            guard editingRoom else { return }
                            selectedCompanionID = companion.id; selectedDecorID = nil; selectedFurniture = nil
                        }
                        .gesture(editingRoom ? DragGesture().onEnded { value in
                            album.setCompanionPosition(.clamped(x: value.location.x / geometry.size.width, y: value.location.y / geometry.size.height), for: companion.id, validCompanionIDs: Set(store.ownedMons.map(\.id)))
                        } : nil)
                        .background(selectedCompanionID == companion.id && editingRoom ? Color.white.opacity(0.75) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(store.chatProfile(for: companion).displayName)
                        .accessibilityHint(l.t("선택하거나 드래그하여 위치를 바꿉니다.", "Select or drag to change position.", "選択またはドラッグして位置を変えます。"))
                }
            }
            VStack { HStack { Text(l.t("미니룸", "Mini room", "ミニルーム")).font(.caption.weight(.semibold)); Spacer() }; Spacer() }.padding(12)
            VStack { Spacer(); Text(roomLifeLine(mon: mon)).font(.caption.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 5).background(.black.opacity(0.12), in: Capsule()).padding(12) }
            if editingRoom {
                VStack {
                    HStack { Spacer(); Text(roomCanvasInstruction).font(.caption.weight(.semibold)).padding(8).background(.ultraThinMaterial, in: Capsule()) }
                    Spacer()
                    if let roomEditFeedback { Text(roomEditFeedback).font(.caption.weight(.medium)).foregroundStyle(.red).padding(7).background(.ultraThinMaterial, in: Capsule()) }
                }.padding(12)
            }
        }
        .frame(minHeight: 365)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .pokedoroCard(tint: tint, emphasized: true)
        .accessibilityLabel(l.t("가구와 동행이 배치된 미니룸", "Mini room with furniture and companions", "家具と相棒を配置したミニルーム"))
    }

    @ViewBuilder private func roomGrid(in size: CGSize, album: PokemonMemoryAlbum) -> some View {
        ForEach(0..<8, id: \.self) { column in
            ForEach(0..<6, id: \.self) { row in
                let point = (column, row)
                let unavailable = selectedFurniture.map { !album.isDecorCellAvailable(point, item: $0, ownedItems: store.state.inventory) } ?? false
                let gridLabel = l.t("격자 \(column + 1), \(row + 1)", "Grid \(column + 1), \(row + 1)", "グリッド \(column + 1)、\(row + 1)")
                let gridHint = unavailable ? l.t("배치할 수 없는 칸", "Unavailable position", "配置できない場所") : l.t("선택한 가구를 배치합니다.", "Places the selected furniture.", "選んだ家具を配置します。")
                let gridFill: Color = selectedFurniture == nil ? .clear : (unavailable ? Color.red.opacity(0.12) : PokedoroTheme.mint.opacity(0.20))
                Rectangle()
                    .fill(gridFill)
                    .overlay(Rectangle().stroke(Color.white.opacity(0.42), lineWidth: 0.7))
                    .frame(width: size.width / 8, height: size.height / 6)
                    .position(x: (Double(column) + 0.5) * size.width / 8,
                              y: (Double(row) + 0.5) * size.height / 6)
                    .contentShape(Rectangle())
                    .onTapGesture { placeSelectedFurniture(at: point) }
                    .allowsHitTesting(selectedFurniture != nil)
                    .accessibilityHidden(selectedFurniture == nil)
                    .accessibilityLabel(gridLabel)
                    .accessibilityHint(gridHint)
            }
        }
    }

    private var roomCanvasInstruction: String {
        if let item = selectedFurniture { return l.t("\(l.itemName(item))을(를) 빈 격자에 클릭해 놓으세요", "Click an empty grid cell to place \(l.itemName(item))", "空いているマスをクリックして\(l.itemName(item))を置きます") }
        if selectedDecorID != nil || selectedCompanionID != nil { return l.t("선택됨 · 드래그해 이동하거나 아래에서 편집하세요", "Selected · drag to move or edit below", "選択中・ドラッグで移動するか下で編集します") }
        return l.t("가구를 고른 뒤 빈 격자를 클릭하세요 · 동행과 가구는 드래그로 이동", "Choose furniture, then click an empty grid · drag furniture or companions to move", "家具を選んで空きマスをクリック・家具と相棒はドラッグで移動")
    }

    private func placeSelectedFurniture(at point: (Int, Int)) {
        guard editingRoom, let item = selectedFurniture else { return }
        let album = store.memoryAlbum
        guard album.isDecorCellAvailable(point, item: item, ownedItems: store.state.inventory) else {
            roomEditFeedback = l.t("이 칸에는 더 배치할 수 없어요.", "That cell is unavailable.", "このマスにはこれ以上配置できません。"); return
        }
        let position = PokemonMemoryAlbum.normalizedGridPoint(point)
        if let decor = album.placeDecor(item, at: position, ownedItems: store.state.inventory) {
            selectedDecorID = decor.id; selectedCompanionID = nil; selectedFurniture = nil; roomEditFeedback = nil
        } else {
            roomEditFeedback = l.t("보유한 가구 수량이 부족해요.", "You do not own another copy of this furniture.", "この家具の所持数が足りません。")
        }
    }

    /// 가구 픽셀 아트 한 칸. **크기는 `MemoryHomePixelArt.displaySize` 가 정한다** — 뷰가 62pt
    /// 같은 값을 직접 쓰면 16px 스프라이트가 3.875 배로 늘어나 픽셀 폭이 3/4px 로 갈린다.
    @ViewBuilder private func furnitureIcon(_ item: ItemKind, style: MemoryHomeRoomStyle,
                                            scale: Int, emojiSize: CGFloat) -> some View {
        if let art = MemoryHomePixelArt.furnitureImage(for: item, style: style, scale: scale),
           let size = MemoryHomePixelArt.displaySize(for: item, scale: scale) {
            Image(nsImage: art).resizable().interpolation(.none)
                .frame(width: size.width, height: size.height)
        } else {
            // 격자가 없는 가구도 방에 보여야 한다 — 안 그리면 놓았는데 사라진 것처럼 보인다.
            Text(item.fallbackEmoji).font(.system(size: emojiSize))
        }
    }

    @ViewBuilder private func decorSprite(_ decor: MemoryHomePlacedDecor) -> some View {
        furnitureIcon(decor.item, style: store.memoryAlbum.roomStyle,
                      scale: MemoryHomePixelArt.roomScale, emojiSize: 34)
        .padding(3)
        .background(selectedDecorID == decor.id && editingRoom ? Color.white.opacity(0.8) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// §5 §17 §24 한 줄. 문구 판정은 전부 `MemoryHomeRoomLife` 에 있다 — 뷰에 두면 세 언어가
    /// 무테스트로 남는다(이 화면의 옛 문구 3줄이 정확히 그 상태였다).
    private func roomLifeLine(mon: MonState) -> String {
        MemoryHomeRoomLife.line(speciesID: mon.currentID,
                                decor: store.memoryAlbum.memoryHomeAccess.placedDecor.map(\.item),
                                roommates: roommates.map { store.chatProfile(for: $0).displayName },
                                mood: store.memoryAlbum.mood(),
                                season: MemoryHomeSeason.current(),
                                timeOfDay: MemoryHomeTimeOfDay.current(),
                                companion: store.chatProfile(for: mon).displayName, l)
    }

    private func roomEditor(mon: MonState) -> some View {
        let album = store.memoryAlbum
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(l.t("미니룸 스튜디오", "Mini room studio", "ミニルームスタジオ"), systemImage: "square.grid.3x3.fill")
                    .font(.headline)
                Spacer()
                Text(l.t("\(album.memoryHomeAccess.placedDecor.count)/12 배치", "\(album.memoryHomeAccess.placedDecor.count)/12 placed", "\(album.memoryHomeAccess.placedDecor.count)/12 配置"))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Button { album.undoRoomEdit() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!album.canUndoRoomEdit).accessibilityLabel(l.t("실행 취소", "Undo", "取り消す"))
                Button { album.redoRoomEdit() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!album.canRedoRoomEdit).accessibilityLabel(l.t("다시 실행", "Redo", "やり直す"))
                Button(editingRoom ? l.t("완료", "Done", "完了") : "") {
                    editingRoom = false; selectedFurniture = nil; selectedDecorID = nil; selectedCompanionID = nil; roomEditFeedback = nil
                }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            roomStyleCards(album: album)
            Text(l.t("가구 카탈로그", "Furniture catalogue", "家具カタログ")).font(.caption.weight(.bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 7)], spacing: 7) {
                ForEach(ItemKind.memoryHomeFurniture.sorted { $0.rawValue < $1.rawValue }, id: \.self) { item in
                    furnitureCard(item, album: album)
                }
            }
            if let selectedDecorID, let decor = album.memoryHomeAccess.placedDecor.first(where: { $0.id == selectedDecorID }) {
                HStack {
                    Label(l.t("선택: ", "Selected: ", "選択: ") + l.itemName(decor.item), systemImage: "cursorarrow.click")
                    Spacer()
                    Button(role: .destructive) { _ = album.removeDecor(id: selectedDecorID); self.selectedDecorID = nil } label: {
                        Label(l.t("삭제", "Remove", "削除"), systemImage: "trash")
                    }.accessibilityLabel(l.t("선택한 가구 치우기", "Remove selected furniture", "選んだ家具を片づける"))
                }.font(.caption)
            } else if let selectedCompanionID, let companion = store.ownedMons.first(where: { $0.id == selectedCompanionID }) {
                Label(l.t("선택한 동행: ", "Selected companion: ", "選んだ相棒: ") + store.chatProfile(for: companion).displayName,
                      systemImage: "figure.wave").font(.caption)
            }
            HStack {
                Menu(l.t("룸메이트", "Roommates", "ルームメイト")) {
                    ForEach(store.ownedMons.filter { $0.id != mon.id }) { candidate in
                        let included = album.memoryHomeAccess.roommateIDs.contains(candidate.id)
                        Button {
                            setRoommate(candidate.id, included: !included)
                        } label: { Label(store.chatProfile(for: candidate).displayName, systemImage: included ? "checkmark.circle.fill" : "circle") }
                    }
                }.menuStyle(.borderedButton).controlSize(.small)
                Spacer()
                Button(l.t("초기화", "Reset", "リセット"), role: .destructive) { showResetDecorConfirmation = true }
                    .disabled(album.memoryHomeAccess.placedDecor.isEmpty).controlSize(.small)
            }
        }
        .padding(12)
        .memoryHomePanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l.t("미니룸 편집 도구", "Mini room editing tools", "ミニルーム編集ツール"))
    }

    private func furnitureCard(_ item: ItemKind, album: PokemonMemoryAlbum) -> some View {
        let owned = store.itemCount(item)
        let placed = album.memoryHomeAccess.placedDecor.filter { $0.item == item }.count
        let selectable = owned > placed && album.memoryHomeAccess.placedDecor.count < 12
        return Button {
            selectedFurniture = selectedFurniture == item ? nil : item
            selectedDecorID = nil; selectedCompanionID = nil; roomEditFeedback = nil
        } label: {
            VStack(spacing: 3) {
                // 카탈로그도 방과 같은 픽셀 아트를 보여준다 — 이모지만 띄우면 무엇을 사는지,
                // 고른 스타일에서 어떤 색으로 놓이는지 사기 전에 알 수 없다.
                furnitureIcon(item, style: album.roomStyle, scale: MemoryHomePixelArt.thumbnailScale, emojiSize: 20)
                    .frame(height: 34)
                Text(l.itemName(item)).font(.caption.weight(.semibold)).lineLimit(1)
                Text(l.t("보유 \(owned) · 배치 \(placed)", "Owned \(owned) · placed \(placed)", "所持 \(owned)・配置 \(placed)"))
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.plain)
        .padding(5)
        .background(selectedFurniture == item ? PokedoroTheme.blue.opacity(0.23) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(selectedFurniture == item ? PokedoroTheme.blue : .clear, lineWidth: 1.5))
        .opacity(selectable || selectedFurniture == item ? 1 : 0.48)
        .accessibilityLabel(l.itemName(item))
        .accessibilityValue(l.t("보유 \(owned), 배치 \(placed)", "Owned \(owned), placed \(placed)", "所持 \(owned)、配置 \(placed)"))
        .accessibilityHint(selectable ? l.t("선택한 뒤 빈 격자를 클릭해 배치합니다.", "Select, then click an empty grid cell to place it.", "選んでから空きマスをクリックして配置します。") : l.t("더 배치할 수 없어요.", "No more copies can be placed.", "これ以上配置できません。"))
        .disabled(!selectable && selectedFurniture != item)
    }

    private func roomStyleCards(album: PokemonMemoryAlbum) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.t("방 스타일", "Room style", "部屋のスタイル")).font(.caption.weight(.bold))
            HStack(spacing: 7) {
                ForEach(MemoryHomeRoomStyle.allCases, id: \.self) { style in
                    let unlocked = album.isRoomStyleUnlocked(style)
                    Button { if unlocked { album.selectRoomStyle(style) } } label: {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 5).fill(MemoryHomeRoomStyle.tint(for: style)).frame(height: 18)
                            Text(style.name(l)).font(.caption2.weight(.semibold)).lineLimit(1)
                            Text(roomStyleStatus(style, unlocked: unlocked, active: style == album.roomStyle))
                                .font(.system(size: 9)).lineLimit(1).foregroundStyle(unlocked ? Color.secondary : Color.orange)
                        }.frame(maxWidth: .infinity).padding(5)
                    }.buttonStyle(.plain)
                    .background(style == album.roomStyle ? MemoryHomeRoomStyle.tint(for: style).opacity(0.18) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityLabel(style.name(l))
                    .accessibilityValue(unlocked ? (style == album.roomStyle ? l.t("사용 중", "Active", "使用中") : l.t("해금됨", "Unlocked", "解放済み")) : roomStyleRequirement(style))
                }
            }
        }
    }

    private func roomStyleRequirement(_ style: MemoryHomeRoomStyle) -> String {
        switch style {
        case .campus: return l.t("기본", "Default", "基本")
        case .lovely: return l.t("집중 첫 업적", "First focus achievement", "集中の初実績")
        case .nature: return l.t("진화 첫 업적", "First evolution achievement", "進化の初実績")
        case .retro: return l.t("배틀 첫 업적", "First battle achievement", "バトルの初実績")
        }
    }

    private func roomStyleStatus(_ style: MemoryHomeRoomStyle, unlocked: Bool, active: Bool) -> String {
        if !unlocked { return roomStyleRequirement(style) }
        return active ? l.t("사용 중", "Active", "使用中") : l.t("선택", "Select", "選択")
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
            Text(l.t("가구, 동행, 스타일은 스튜디오에서 함께 편집합니다.", "Edit furniture, companions, and style together in the studio.", "家具・相棒・スタイルはスタジオでまとめて編集します。"))
                .font(.caption2).foregroundStyle(.secondary)
            Button(editingRoom ? l.t("꾸미기 완료", "Done decorating", "模様替えを完了") : l.t("스튜디오 열기", "Open studio", "スタジオを開く")) {
                editingRoom.toggle()
                selectedFurniture = nil; selectedDecorID = nil; selectedCompanionID = nil; roomEditFeedback = nil
            }
                .buttonStyle(.borderedProminent).controlSize(.small)

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
    private var visit: some View { ScrollView { VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) { Text(l.t("같은 LAN의 Memory Home", "Memory Homes on this LAN", "同じLANのMemory Home")).font(.headline); Text(l.t("홈을 고르고 공개된 쇼룸을 둘러보세요.", "Choose a home and explore its public showroom.", "ホームを選び公開ショールームを見て回りましょう。")).font(.caption).foregroundStyle(.secondary) }.memoryHomePanel(tint: PokedoroTheme.blue)
        if let selected = visits.selectedProfile { remoteProfile(selected) }
        if visits.homes.isEmpty { ContentUnavailableView(l.t("주변 홈을 찾는 중이에요…", "Looking for homes…", "近くのホームを探しています…"), systemImage: "dot.radiowaves.left.and.right") } else { ForEach(visits.homes) { home in Button { visits.visit(home) } label: { Label(home.displayName, systemImage: "house.fill").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered) } }
    }.padding(18) }.onAppear { visits.start() }.onDisappear { visits.stop() } }

    private func remoteProfile(_ card: MemoryHomeProfileCard) -> some View { VStack(alignment: .leading, spacing: 8) {
        HStack { SpriteView(speciesID: card.speciesID, size: 72, shiny: card.isShiny); VStack(alignment: .leading) { Text(card.displayName).font(.title3.bold()); Text(card.profileMessage ?? l.t("환영합니다!", "Welcome!", "ようこそ！")).foregroundStyle(.secondary) } }
        if card.roomStyle != nil || !card.placedDecor.isEmpty || card.featuredPhoto != nil { remoteShowroom(card) }
        else if !card.showcaseFurniture.isEmpty { HStack { ForEach(card.showcaseFurniture, id: \.self) { furnitureIcon($0, style: .campus, scale: MemoryHomePixelArt.thumbnailScale, emojiSize: 22).frame(width: 42, height: 42) } } }
        if let memory = card.sharedMemoryBody { Text(memory).font(.caption) }
    }.memoryHomePanel(tint: PokedoroTheme.mint) }

    private func remoteShowroom(_ card: MemoryHomeProfileCard) -> some View { VStack(alignment: .leading, spacing: 8) {
        Label(l.t("공개 미니룸 쇼케이스", "Public mini-room showcase", "公開ミニルームショーケース"), systemImage: "house.fill").font(.caption.weight(.bold))
        GeometryReader { proxy in ZStack { RoundedRectangle(cornerRadius: 10).fill(MemoryHomeRoomTheme.tint(for: card.roomTheme ?? .blue).opacity(0.18)); ForEach(card.placedDecor.sorted { $0.layer < $1.layer }) { decor in furnitureIcon(decor.item, style: card.roomStyle ?? .campus, scale: MemoryHomePixelArt.thumbnailScale, emojiSize: 22).frame(width: 42, height: 42).position(x: decor.position.x * proxy.size.width, y: decor.position.y * proxy.size.height) } } }.frame(height: 130)
        if let photo = card.featuredPhoto { MemoryHomeRemotePhoto(photo: photo).frame(height: 160) }
    } }
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
}

private struct MemoryHomeRule: View { let label: String; let value: String; var body: some View { HStack { Text(label).font(.caption).foregroundStyle(.secondary); Spacer(); Text(value).font(.caption.weight(.medium)).lineLimit(1) } } }

/// Remote cards carry composition metadata, never image bytes. Reusing the local photo canvas
/// keeps a LAN featured shot faithful to its owner-selected frame, background and caption.
private struct MemoryHomeRemotePhoto: View {
    let photo: MemoryHomePhoto
    @State private var sprite: NSImage?

    var body: some View {
        StickerPhotoCanvas(sprite: sprite, caption: photo.caption,
                           frame: StickerPhotoFrame(rawValue: photo.frame) ?? .heart,
                           background: photo.background, composition: photo.composition,
                           trainerStyle: photo.trainerStyle)
            .task { sprite = await SpriteLoader.image(speciesID: photo.speciesID, shiny: photo.isShiny) }
    }
}
private extension View {
    func memoryHomePanel(tint: Color = PokedoroTheme.blue) -> some View {
        padding(12).pokedoroCard(tint: tint)
    }
}
